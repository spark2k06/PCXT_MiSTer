//
// sdram_arbiter + sdram_ctrl + chip model under mixed traffic.
//
// Clients:
//   CPU  one request at a time, as the chipset port issues them, with 0..
//        CPU_GAP_MAX idle clocks between them (0 = saturating, harsher than
//        the real port, which always leaves a few clocks).
//   VID  a video fetch stream: one read every VID_PERIOD clocks, requested
//        VID_LEAD clocks before it is needed, several outstanding.
//   LDR  occasional ROM-loader writes.
//   AUX  occasional reads.
//
// SAME_BANK = 0 puts the video stream in bank 1 (PCXT: dedicated VRAM);
// SAME_BANK = 1 puts it in bank 0 with the CPU, which also writes into it
// (Tandy / PCjr: video memory is system RAM). Every read word of every
// client is checked against a reference updated in ack order.
//
// Reports and checks: worst CPU latency (request to first word), worst VID
// latency, video underruns (= 0), refresh rate, and the
// worst wait of LDR and AUX (no starvation).
//
`timescale 1ns / 1ps

module sdram_arbiter_tb #(
    parameter int  SAME_BANK   = 0,
    parameter int  CYCLES      = 400000,
    parameter int  VID_PERIOD  = 28,        // EGA text: cell + glyph per 8-dot character
    parameter int  VID_LEN     = 0,         // sdram_pkg::LEN_*
    parameter int  VID_LEAD    = 112,       // two EGA characters
    parameter int  CPU_GAP_MIN = 0,
    parameter int  CPU_GAP_MAX = 4,
    parameter int  LIMIT_CPU   = 0,         // 0: 16 (other bank) or 31 (same bank)
    parameter int  LIMIT_VID   = 32,
    parameter int  EXTRA       = 0,         // 1: LDR and AUX traffic as well
    parameter int  HIGH_ROWS   = 0          // 1: some rows have address bits 12:11 set (XS boards)
);
    import sdram_pkg::*;

    localparam real TCK  = 8.730;
    localparam real LEAD = 2.0;
    localparam real TCO  = 3.0;
    localparam int  CPU_LIMIT = (LIMIT_CPU != 0) ? LIMIT_CPU : (SAME_BANK ? 31 : 16);
    localparam logic [1:0] VID_BANK = SAME_BANK ? 2'd0 : 2'd1;

    logic clk = 1'b0, sdram_clk = 1'b0;
    always #(TCK / 2.0) clk = ~clk;
    initial begin
        #(TCK - LEAD);
        forever #(TCK / 2.0) sdram_clk = ~sdram_clk;
    end
    logic reset = 1'b1;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    logic        vid_req = 0;  logic [23:0] vid_addr = 0;  logic [1:0] vid_len = 0;
    logic [15:0] vid_deadline = 0;
    wire         vid_ack, vid_rvalid, vid_rlast;
    logic        cpu_req = 0, cpu_we = 0;  logic [23:0] cpu_addr = 0;  logic [1:0] cpu_len = 0;
    logic [63:0] cpu_wdata = 0;  logic [7:0] cpu_wbe = 0;
    wire         cpu_ack, cpu_rvalid, cpu_rlast;
    logic        ldr_req = 0;  logic [23:0] ldr_addr = 0;  logic [15:0] ldr_wdata = 0;
    wire         ldr_ack, ldr_rvalid, ldr_rlast;
    logic        aux_req = 0;  logic [23:0] aux_addr = 0;
    logic        stop = 0;      // generators stop issuing new requests
    wire         aux_ack, aux_rvalid, aux_rlast;
    wire [15:0]  rdata;

    wire        op_valid, op_ref, op_we, op_issue, init_done;
    wire [23:0] op_addr;  wire [1:0] op_len;  wire [63:0] op_wdata;  wire [7:0] op_wbe;
    wire [1:0]  op_tag;
    wire        rd_valid, rd_last;  wire [15:0] rd_data;  wire [1:0] rd_tag;
    wire [15:0] cpu_lat_max, vid_lat_max, vid_underruns;
    wire [3:0]  ref_debt;
    wire [3:0]  bank_idle;

    sdram_arbiter arb (
        .clk(clk), .reset(reset), .init_done(init_done),
        .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
        .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_len(cpu_len),
        .cpu_wdata(cpu_wdata), .cpu_wbe(cpu_wbe),
        .cpu_ack(cpu_ack), .cpu_rvalid(cpu_rvalid), .cpu_rlast(cpu_rlast),
        .ldr_req(ldr_req), .ldr_we(1'b1), .ldr_addr(ldr_addr), .ldr_len(LEN_1),
        .ldr_wdata({48'd0, ldr_wdata}), .ldr_wbe(8'h03), .ldr_high(1'b0),
        .ldr_ack(ldr_ack), .ldr_rvalid(ldr_rvalid), .ldr_rlast(ldr_rlast),
        .aux_req(aux_req), .aux_addr(aux_addr), .aux_len(LEN_2),
        .aux_ack(aux_ack), .aux_rvalid(aux_rvalid), .aux_rlast(aux_rlast),
        .rdata(rdata),
        .op_valid(op_valid), .op_ref(op_ref), .op_we(op_we), .op_addr(op_addr),
        .op_len(op_len), .op_wdata(op_wdata), .op_wbe(op_wbe), .op_tag(op_tag),
        .op_issue(op_issue), .bank_idle(bank_idle), .rd_valid(rd_valid), .rd_data(rd_data),
        .rd_tag(rd_tag), .rd_last(rd_last),
        .cpu_lat_max(cpu_lat_max), .vid_lat_max(vid_lat_max),
        .vid_underruns(vid_underruns), .ref_debt(ref_debt)
    );

    wire        c_cke, c_cs_n, c_ras_n, c_cas_n, c_we_n, c_oe;
    wire [1:0]  c_ba, c_dqm;  wire [12:0] c_a;  wire [15:0] c_dq;
    logic       p_cke = 0, p_cs_n = 1, p_ras_n = 1, p_cas_n = 1, p_we_n = 1, p_oe = 0;
    logic [1:0] p_ba = 0, p_dqm = 3;  logic [12:0] p_a = 0;  logic [15:0] p_dq = 0;

    always @(posedge clk) begin
        #(TCO);
        {p_cke, p_cs_n, p_ras_n, p_cas_n, p_we_n, p_oe} = {c_cke, c_cs_n, c_ras_n, c_cas_n, c_we_n, c_oe};
        {p_ba, p_dqm, p_a, p_dq} = {c_ba, c_dqm, c_a, c_dq};
    end

    wire [15:0] chip_dq;  wire chip_drive, chip_valid;
    wire [15:0] dq_pin = p_oe ? p_dq : (chip_drive ? chip_dq : 16'hF10A);

    sdram_ctrl #(.INIT_US(20)) ctrl (
        .clk(clk), .reset(reset), .init_done(init_done),
        .op_valid(op_valid), .op_ref(op_ref), .op_we(op_we), .op_addr(op_addr),
        .op_len(op_len), .op_wdata(op_wdata), .op_wbe(op_wbe), .op_tag(op_tag),
        .op_issue(op_issue), .bank_idle(bank_idle), .rd_valid(rd_valid), .rd_data(rd_data),
        .rd_tag(rd_tag), .rd_last(rd_last),
        .sdram_cke(c_cke), .sdram_cs_n(c_cs_n), .sdram_ras_n(c_ras_n), .sdram_cas_n(c_cas_n),
        .sdram_we_n(c_we_n), .sdram_ba(c_ba), .sdram_a(c_a), .sdram_dqm(c_dqm),
        .sdram_dq_out(c_dq), .sdram_dq_oe(c_oe), .sdram_dq_in(dq_pin)
    );

    sdram_model #(.TCK(TCK), .CL(3)) chip (
        .clk(sdram_clk), .cke(p_cke), .cs_n(p_cs_n), .ras_n(p_ras_n), .cas_n(p_cas_n),
        .we_n(p_we_n), .ba(p_ba), .a(p_a), .dqm(p_dqm), .dq_in(p_dq), .dq_in_oe(p_oe),
        .dq_out(chip_dq), .dq_drive(chip_drive), .dq_valid(chip_valid)
    );

    // ------------------------------------------------------------------
    // Reference memory, updated in ack order
    // ------------------------------------------------------------------
    int errors = 0;
    task automatic err(input string m);
        errors++;
        if (errors <= 20) $display("%0.3f ERROR: %s", $realtime, m);
    endtask

    always @(p_oe or chip_drive) if (p_oe && chip_drive) err("DQ contention");
    always @(posedge clk) if (!reset && ctrl.rdq_v[0] && !chip_valid) err("sample outside valid window");

    logic [15:0] ref_mem [int unsigned];
    function automatic logic [15:0] rp(input int unsigned a);
        rp = ref_mem.exists(a) ? ref_mem[a] : 16'h0000;
    endfunction

    logic [15:0] exp_cpu [$], exp_vid [$], exp_aux [$];

    // Clock number of the edge being processed, the same in every process.
    function automatic longint cyc();
        cyc = longint'($rtoi($realtime / TCK));
    endfunction

    always @(posedge clk) begin
        if (cpu_ack) begin
            for (int i = 0; i < len_words(cpu_len); i++) begin
                int unsigned a = cpu_addr + i;
                if (cpu_we) begin
                    logic [15:0] o = rp(a);
                    ref_mem[a] = {cpu_wbe[2*i+1] ? cpu_wdata[16*i+8 +: 8] : o[15:8],
                                  cpu_wbe[2*i]   ? cpu_wdata[16*i   +: 8] : o[7:0]};
                end
                else exp_cpu.push_back(rp(a));
            end
        end
        if (vid_ack)
            for (int i = 0; i < len_words(vid_len); i++) exp_vid.push_back(rp(vid_addr + i));
        if (ldr_ack)
            ref_mem[ldr_addr] = ldr_wdata;
        if (aux_ack)
            for (int i = 0; i < 2; i++) exp_aux.push_back(rp(aux_addr + i));

        if (cpu_rvalid) begin
            if (exp_cpu.size() == 0) err("stray CPU word");
            else if (rdata !== exp_cpu[0]) err($sformatf("CPU read %04h expected %04h", rdata, exp_cpu[0]));
            if (exp_cpu.size() != 0) void'(exp_cpu.pop_front());
        end
        if (vid_rvalid) begin
            if (exp_vid.size() == 0) err("stray VID word");
            else if (rdata !== exp_vid[0]) err($sformatf("VID read %04h expected %04h", rdata, exp_vid[0]));
            if (exp_vid.size() != 0) void'(exp_vid.pop_front());
        end
        if (aux_rvalid) begin
            if (exp_aux.size() == 0) err("stray AUX word");
            else if (rdata !== exp_aux[0]) err($sformatf("AUX read %04h expected %04h", rdata, exp_aux[0]));
            if (exp_aux.size() != 0) void'(exp_aux.pop_front());
        end
        if (ldr_rvalid) err("LDR never reads");
    end

    // ------------------------------------------------------------------
    // CPU: one at a time, random gap
    // ------------------------------------------------------------------
    int cpu_gap = 0;
    logic cpu_wait_data = 0;
    int cpu_lat_hist [64];
    logic first_word = 1'b1;
    always @(posedge clk)
        if (cpu_rvalid) first_word <= cpu_rlast;
    longint cpu_t0;
    longint cpu_ops = 0;

    function automatic logic [23:0] cpu_rand_addr(input logic [1:0] len);
        logic [23:0] a;
        // HIGH_ROWS: one access in six uses a row with bits 12:11 set. On the
        // XS/XSDS boards those address bits are the chip's DQM pins
        // (-DDQM_XS). The PCXT memory map never reaches such rows (they are
        // above 4 MiB of a bank), so this is a correctness stress only.
        a = {2'd0, 13'($urandom_range(64, 127) | ((HIGH_ROWS != 0 && $urandom_range(0, 5) == 0) ? ($urandom_range(1, 3) << 11) : 0)),
             9'($urandom_range(0, 508))};
        if (SAME_BANK && $urandom_range(0, 3) == 0)
            a = {VID_BANK, 13'($urandom_range(0, 15)), 9'($urandom_range(0, 508))};
        cpu_rand_addr = a;
    endfunction

    always @(posedge clk) begin
        if (reset || !init_done) ;
        else if (cpu_req) begin
            if (cpu_ack) begin
                cpu_req <= 1'b0;
                cpu_ops++;
                if (cpu_we) begin
                    int l = int'(cyc() - cpu_t0);
                    cpu_lat_hist[l > 63 ? 63 : l]++;
                    cpu_gap <= $urandom_range(CPU_GAP_MIN, CPU_GAP_MAX);
                end
                else cpu_wait_data <= 1'b1;
            end
        end
        else if (cpu_wait_data) begin
            if (cpu_rvalid && first_word) begin
                int l = int'(cyc() - cpu_t0);
                cpu_lat_hist[l > 63 ? 63 : l]++;
            end
            if (cpu_rlast) begin
                cpu_wait_data <= 1'b0;
                cpu_gap <= $urandom_range(CPU_GAP_MIN, CPU_GAP_MAX);
            end
        end
        else if (cpu_gap > 0)
            cpu_gap <= cpu_gap - 1;
        else if (!stop) begin
            logic [1:0] len;
            logic we;
            we  = ($urandom_range(0, 9) < 3);
            len = we ? LEN_1 : (($urandom_range(0, 9) < 5) ? LEN_1 : ($urandom_range(0, 1) ? LEN_2 : LEN_4));
            cpu_req   <= 1'b1;
            cpu_we    <= we;
            cpu_len   <= len;
            cpu_addr  <= cpu_rand_addr(len);
            cpu_wdata <= {$urandom, $urandom};
            cpu_wbe   <= 8'($urandom_range(1, 3));
            cpu_t0    = cyc() + 1;
        end
    end

    // ------------------------------------------------------------------
    // VID: a fetch every VID_PERIOD clocks, VID_LEAD ahead of its use
    // ------------------------------------------------------------------
    typedef struct { logic [23:0] addr; longint due; } vreq_t;
    vreq_t vq [$];
    int    vid_tick = 0;
    logic [17:0] vid_next = 0;
    int    vid_backlog_max = 0;

    always @(posedge clk) begin
        if (!reset && init_done) begin
            longint c = cyc();
            if (vid_ack) void'(vq.pop_front());
            if (vid_tick == VID_PERIOD - 1 && !stop) begin
                vreq_t r;
                vid_tick <= 0;
                r.addr = {VID_BANK, 4'((HIGH_ROWS != 0) ? ($urandom_range(0, 3) << 2) : 0), vid_next};
                r.due  = c + 1 + VID_LEAD;
                vq.push_back(r);
                vid_next <= (vid_next + 18'(len_words(VID_LEN)) + 18'd4) & 18'h00FFF;
                if (vq.size() > vid_backlog_max) vid_backlog_max = vq.size();
            end
            else vid_tick <= vid_tick + 1;

            // What the arbiter sees during the next clock.
            vid_req      <= (vq.size() > 0);
            vid_addr     <= (vq.size() > 0) ? vq[0].addr : 24'd0;
            vid_len      <= 2'(VID_LEN);
            vid_deadline <= (vq.size() > 0 && vq[0].due > c + 1) ? 16'(vq[0].due - c - 1) : 16'd0;
        end
    end

    // ------------------------------------------------------------------
    // LDR and AUX
    // ------------------------------------------------------------------
    longint ldr_t0 = 0, aux_t0 = 0;
    int ldr_wait_max = 0, aux_wait_max = 0;
    int ldr_cnt = 0, aux_cnt = 0;

    always @(posedge clk) begin
        if (!reset && init_done) begin
            if (ldr_req && ldr_ack) begin
                ldr_req <= 1'b0;
                if (int'(cyc() - ldr_t0) > ldr_wait_max) ldr_wait_max = int'(cyc() - ldr_t0);
            end
            else if (EXTRA && !stop && !ldr_req && $urandom_range(0, 199) == 0) begin
                ldr_req   <= 1'b1;
                ldr_addr  <= {2'd0, 13'd200, 9'(ldr_cnt)};
                ldr_wdata <= 16'($urandom);
                ldr_cnt++;
                ldr_t0    = cyc() + 1;
            end
            if (aux_req && aux_ack) begin
                aux_req <= 1'b0;
                if (int'(cyc() - aux_t0) > aux_wait_max) aux_wait_max = int'(cyc() - aux_t0);
            end
            else if (EXTRA && !stop && !aux_req && $urandom_range(0, 499) == 0) begin
                aux_req  <= 1'b1;
                aux_addr <= {2'd0, 13'd200, 9'($urandom_range(0, 500))};
                aux_cnt++;
                aux_t0   = cyc() + 1;
            end
        end
    end

    // VID latency from the request, measured here.
    longint vreq_t0 [$];
    int     vid_req_lat_max = 0;
    logic   vfirst = 1'b1;
    longint vcur_t0 = -1;
    always @(posedge clk) begin
        if (vid_req && vcur_t0 < 0) vcur_t0 = cyc();
        if (vid_ack) begin vreq_t0.push_back(vcur_t0); vcur_t0 = -1; end
        if (vid_rvalid) begin
            if (vfirst && vreq_t0.size() > 0 && int'(cyc() - vreq_t0[0]) > vid_req_lat_max)
                vid_req_lat_max = int'(cyc() - vreq_t0[0]);
            if (vid_rlast && vreq_t0.size() > 0) void'(vreq_t0.pop_front());
            vfirst = vid_rlast;
        end
    end

    // Trace of the last commands, dumped once when the CPU latency limit is first exceeded.
    string  trace [$];
    logic   dumped = 1'b0;
    always @(posedge clk) begin
        string t;
        t = "";
        if (arb.load) t = {t, $sformatf(" load:%s", arb.sel.name())};
        if (op_issue) t = {t, $sformatf(" issue:%s%s b%0d", op_ref ? "REF" : (op_we ? "WR" : "RD"),
                                        op_ref ? "" : $sformatf("%0d", len_words(op_len)), op_addr[23:22])};
        if (cpu_req) t = {t, " cpu_req"};
        if (vid_req) t = {t, $sformatf(" vid_req(dl %0d)", vid_deadline)};
        if (cpu_rvalid) t = {t, " cpu_word"};
        trace.push_back($sformatf("%0d:%s", cyc(), t));
        if (trace.size() > 40) void'(trace.pop_front());
        if (!dumped && cpu_lat_max > CPU_LIMIT) begin
            dumped = 1'b1;
            $display("-- trace up to the first CPU latency excess --");
            foreach (trace[i]) $display("   %s", trace[i]);
        end
    end

    int debt_max = 0;
    always @(posedge clk) if (ref_debt > debt_max) debt_max = ref_debt;

    // ------------------------------------------------------------------
    initial begin
        // Video memory content, written behind the controller's back.
        for (int i = 0; i < 4096; i++) begin
            chip.poke({VID_BANK, 4'd0, 18'(i)}, 16'(i * 7 + 3));
            ref_mem[{VID_BANK, 4'd0, 18'(i)}] = 16'(i * 7 + 3);
        end
        repeat (10) @(posedge clk);
        reset = 1'b0;
        wait (init_done);
        repeat (CYCLES) @(posedge clk);
        stop = 1'b1;
        repeat (400) @(posedge clk);

        begin
            int p50 = 0, acc = 0, total = 0;
            for (int i = 0; i < 64; i++) total += cpu_lat_hist[i];
            for (int i = 0; i < 64; i++) begin
                acc += cpu_lat_hist[i];
                if (p50 == 0 && acc * 2 >= total) p50 = i;
            end
            $display("%s bank, VID every %0d clocks (len %0d, lead %0d), CPU gap %0d..%0d, %0d clocks",
                     SAME_BANK ? "shared" : "separate", VID_PERIOD, len_words(VID_LEN), VID_LEAD,
                     CPU_GAP_MIN, CPU_GAP_MAX, CYCLES);
            $display("CPU latency to first word: max %0d clocks (limit %0d), median %0d, %0d requests",
                     cpu_lat_max, CPU_LIMIT, p50, cpu_ops);
            $display("VID latency, from becoming urgent to first word: max %0d clocks (limit %0d), backlog max %0d",
                     vid_lat_max, LIMIT_VID, vid_backlog_max);
            $display("     VID latency from the request: max %0d clocks", vid_req_lat_max);
            $display("VID underruns: %0d", vid_underruns);
            $display("LDR %0d writes, worst wait %0d; AUX %0d reads, worst wait %0d",
                     ldr_cnt, ldr_wait_max, aux_cnt, aux_wait_max);
            $display("refresh: %0d AUTO REFRESH in %.1f us (%.2f us each), worst debt %0d; chip errors %0d",
                     chip.refs, $realtime / 1000.0, $realtime / 1000.0 / chip.refs, debt_max, chip.errors);
            $write("CPU latency histogram:");
            for (int i = 0; i < 64; i++) if (cpu_lat_hist[i] != 0) $write(" %0d:%0d", i, cpu_lat_hist[i]);
            $display("");
        end

        if (cpu_lat_max > CPU_LIMIT) err($sformatf("CPU latency limit exceeded: %0d > %0d", cpu_lat_max, CPU_LIMIT));
        if (vid_lat_max > LIMIT_VID) err($sformatf("VID latency limit exceeded: %0d > %0d", vid_lat_max, LIMIT_VID));
        if (vid_underruns != 0)     err("video underruns");
        if (ldr_wait_max > 300 || aux_wait_max > 300) err("LDR/AUX starvation");
        if (debt_max > 8) err("refresh debt above 8");
        if (exp_cpu.size() || exp_vid.size() || exp_aux.size()) err("words never returned");

        $display("RESULT: %s", (errors == 0 && chip.errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

endmodule
