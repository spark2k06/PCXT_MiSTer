//
// vram_fetch + vid_mux + sdram_arbiter + sdram_ctrl + chip model, with the CPU
// and the loader writing into the very words the engines are fetching.
//
// Two engines share the VID port:
//   A  DEPTH 4, MAX_WORDS 4: requests of 1, 2 and 4 words, random lead.
//   B  DEPTH 3, MAX_WORDS 1: one word per CRTC character, a fixed period.
//
// The reference is an ideal memory that is updated one clock after the arbiter
// captures a write (the engine's snoop takes two clocks: it finds the words,
// then patches them). Whenever an engine hands out a complete entry on
// rsp_pop, every word must equal the reference at that clock: the display shows
// what a RAM with no latency would have shown.
//
// Also checked: entries come out in request order; a pop of an entry that is
// not there yet is counted as an underrun and the entry is skipped (the next
// pop returns the next request); flush drops everything and the queue works
// afterwards; the underrun counter equals the number of late pops.
//
`timescale 1ns / 1ps

module vram_fetch_tb #(
    parameter int CYCLES    = 300000,
    parameter int LATE_PCT  = 3,        // % of A requests that are popped before their data can be there
    parameter int FLUSH_PCT = 1,        // % chance, per 1000 clocks, of a flush of engine A
    parameter int WR_GAP    = 24,       // average clocks between CPU writes
    parameter int B_PERIOD  = 64        // clocks between B requests (CGA 80 columns = 64)
);
    import sdram_pkg::*;

    localparam real TCK  = 8.730;
    localparam real LEAD = 2.0;
    localparam real TCO  = 3.0;
    localparam int  NA   = 40;          // words of the test area

    logic clk = 1'b0, sdram_clk = 1'b0;
    always #(TCK / 2.0) clk = ~clk;
    initial begin
        #(TCK - LEAD);
        forever #(TCK / 2.0) sdram_clk = ~sdram_clk;
    end
    logic reset = 1'b1;

    function automatic logic [23:0] area(input int w);
        area = {2'd1, 13'd5, 9'(w)};
    endfunction

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    logic        cpu_req = 0, cpu_we = 0;  logic [23:0] cpu_addr = 0;  logic [1:0] cpu_len = 0;
    logic [63:0] cpu_wdata = 0;  logic [7:0] cpu_wbe = 0;
    wire         cpu_ack, cpu_rvalid, cpu_rlast;
    logic        ldr_req = 0;  logic [23:0] ldr_addr = 0;  logic [15:0] ldr_wdata = 0;
    wire         ldr_ack, ldr_rvalid, ldr_rlast;
    wire         aux_ack, aux_rvalid, aux_rlast;
    wire [15:0]  rdata;
    logic        stop = 0;

    wire        vid_req, vid_ack, vid_rvalid, vid_rlast;
    wire [23:0] vid_addr;  wire [1:0] vid_len;  wire [15:0] vid_deadline;

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
        .aux_req(1'b0), .aux_addr(24'd0), .aux_len(LEN_2),
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

    // Snoop: what the arbiter captures
    wire        snoop_valid = (cpu_ack & cpu_we) | ldr_ack;
    wire [23:0] snoop_addr  = ldr_ack ? ldr_addr : cpu_addr;
    wire [1:0]  snoop_len   = ldr_ack ? LEN_1    : cpu_len;
    wire [63:0] snoop_wdata = ldr_ack ? {48'd0, ldr_wdata} : cpu_wdata;
    wire [7:0]  snoop_wbe   = ldr_ack ? 8'h03    : cpu_wbe;

    // Engines
    logic        a_rv = 0, b_rv = 0;
    logic [23:0] a_ra = 0, b_ra = 0;
    logic [1:0]  a_rl = 0, b_rl = 0;
    logic [15:0] a_rd = 0, b_rd = 0;
    wire         a_rdy, b_rdy;
    wire         a_pend, a_val, b_pend, b_val;
    wire [63:0]  a_data, b_data;
    wire [23:0]  a_raddr, b_raddr;
    wire [1:0]   a_rlen, b_rlen;
    logic        a_pop = 0, b_pop = 0, a_flush = 0;
    wire [15:0]  a_under, b_under;
    wire [3:0]   a_occ, b_occ;

    wire        a_vreq, b_vreq, a_ack, b_ack, a_rvalid, b_rvalid, a_rlast, b_rlast;
    wire [23:0] a_vaddr, b_vaddr;  wire [1:0] a_vlen, b_vlen;  wire [15:0] a_vdl, b_vdl;

    vram_fetch #(.DEPTH(4), .MAX_WORDS(4)) eng_a (
        .clk(clk), .reset(reset),
        .req_valid(a_rv), .req_addr(a_ra), .req_len(a_rl), .req_deadline(a_rd), .req_ready(a_rdy),
        .rsp_pending(a_pend), .rsp_valid(a_val), .rsp_data(a_data), .rsp_addr(a_raddr), .rsp_len(a_rlen),
        .rsp_pop(a_pop), .flush(a_flush),
        .snoop_valid(snoop_valid), .snoop_addr(snoop_addr), .snoop_len(snoop_len),
        .snoop_wdata(snoop_wdata), .snoop_wbe(snoop_wbe),
        .vid_req(a_vreq), .vid_addr(a_vaddr), .vid_len(a_vlen), .vid_deadline(a_vdl),
        .vid_ack(a_ack), .vid_rvalid(a_rvalid), .vid_rlast(a_rlast), .vid_rdata(rdata),
        .underrun_count(a_under), .occupancy(a_occ)
    );

    vram_fetch #(.DEPTH(3), .MAX_WORDS(1)) eng_b (
        .clk(clk), .reset(reset),
        .req_valid(b_rv), .req_addr(b_ra), .req_len(b_rl), .req_deadline(b_rd), .req_ready(b_rdy),
        .rsp_pending(b_pend), .rsp_valid(b_val), .rsp_data(b_data), .rsp_addr(b_raddr), .rsp_len(b_rlen),
        .rsp_pop(b_pop), .flush(1'b0),
        .snoop_valid(snoop_valid), .snoop_addr(snoop_addr), .snoop_len(snoop_len),
        .snoop_wdata(snoop_wdata), .snoop_wbe(snoop_wbe),
        .vid_req(b_vreq), .vid_addr(b_vaddr), .vid_len(b_vlen), .vid_deadline(b_vdl),
        .vid_ack(b_ack), .vid_rvalid(b_rvalid), .vid_rlast(b_rlast), .vid_rdata(rdata),
        .underrun_count(b_under), .occupancy(b_occ)
    );

    vid_mux #(.N(2)) mux (
        .clk(clk), .reset(reset),
        .c_req({b_vreq, a_vreq}), .c_addr({b_vaddr, a_vaddr}), .c_len({b_vlen, a_vlen}),
        .c_deadline({b_vdl, a_vdl}),
        .c_ack({b_ack, a_ack}), .c_rvalid({b_rvalid, a_rvalid}), .c_rlast({b_rlast, a_rlast}),
        .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
        .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast)
    );

    // ------------------------------------------------------------------
    // Reference memory and checks
    // ------------------------------------------------------------------
    int errors = 0;
    task automatic err(input string m);
        errors++;
        if (errors <= 20) $display("%0.3f ERROR: %s", $realtime, m);
    endtask

    always @(p_oe or chip_drive) if (p_oe && chip_drive) err("DQ contention");

    logic [15:0] ref_mem [int unsigned];
    function automatic logic [15:0] rp(input int unsigned a);
        rp = ref_mem.exists(a) ? ref_mem[a] : 16'h0000;
    endfunction

    function automatic longint cyc();
        cyc = longint'($rtoi($realtime / TCK));
    endfunction

    typedef struct { logic [23:0] addr; logic [1:0] len; longint due; } rq_t;
    rq_t qa [$], qb [$];

    int a_checked = 0, a_late = 0, b_checked = 0, b_late = 0, a_flushes = 0;
    int a_mismatch = 0, b_mismatch = 0;
    longint a_last_pop = 0, b_last_pop = 0;

    logic        pc_v = 1'b0, pl_v = 1'b0;
    logic [23:0] pc_addr = 0, pl_addr = 0;
    logic [1:0]  pc_len = 0;
    logic [63:0] pc_wdata = 0;
    logic [7:0]  pc_wbe = 0;
    logic [15:0] pl_wdata = 0;

    always @(posedge clk) begin
        // ---- checks on a pop, before this clock's write is applied ----
        if (a_pop && !reset) begin
            if (qa.size() == 0) err("A pop with nothing queued");
            else begin
                if (a_val) begin
                    a_checked++;
                    if (a_raddr !== qa[0].addr || a_rlen !== qa[0].len)
                        err($sformatf("A head is %06h/%0d, expected %06h/%0d", a_raddr, a_rlen, qa[0].addr, qa[0].len));
                    for (int i = 0; i < len_words(qa[0].len); i++)
                        if (a_data[16*i +: 16] !== rp(qa[0].addr + i)) begin
                            a_mismatch++;
                            err($sformatf("A word %0d of %06h: %04h expected %04h", i, qa[0].addr, a_data[16*i +: 16], rp(qa[0].addr + i)));
                        end
                end
                else a_late++;
                void'(qa.pop_front());
            end
        end
        if (b_pop && !reset) begin
            if (qb.size() == 0) err("B pop with nothing queued");
            else begin
                if (b_val) begin
                    b_checked++;
                    if (b_raddr !== qb[0].addr)
                        err($sformatf("B head is %06h, expected %06h", b_raddr, qb[0].addr));
                    if (b_data[15:0] !== rp(qb[0].addr)) begin
                        b_mismatch++;
                        err($sformatf("B word %06h: %04h expected %04h", qb[0].addr, b_data[15:0], rp(qb[0].addr)));
                    end
                end
                else b_late++;
                void'(qb.pop_front());
            end
        end

        // ---- reference update: one clock after the arbiter captured the write ----
        if (pc_v)
            for (int i = 0; i < len_words(pc_len); i++) begin
                int unsigned a = pc_addr + i;
                logic [15:0] o = rp(a);
                ref_mem[a] = {pc_wbe[2*i+1] ? pc_wdata[16*i+8 +: 8] : o[15:8],
                              pc_wbe[2*i]   ? pc_wdata[16*i   +: 8] : o[7:0]};
            end
        if (pl_v)
            ref_mem[pl_addr] = pl_wdata;
        pc_v <= cpu_ack && cpu_we;
        pc_addr <= cpu_addr;  pc_len <= cpu_len;  pc_wdata <= cpu_wdata;  pc_wbe <= cpu_wbe;
        pl_v <= ldr_ack;
        pl_addr <= ldr_addr;  pl_wdata <= ldr_wdata;
    end

    // CPU reads are only here to load the arbiter: the data is not checked.
    always @(posedge clk) if (cpu_rvalid && rdata === 16'bx) err("X on CPU read");

    // ------------------------------------------------------------------
    // CPU / loader writers (and some reads to keep the memory busy)
    // ------------------------------------------------------------------
    int cpu_gap = 0;
    logic cpu_wait_data = 0;
    int writes = 0;

    always @(posedge clk) begin
        if (reset || !init_done) ;
        else if (cpu_req) begin
            if (cpu_ack) begin
                cpu_req <= 1'b0;
                if (cpu_we) writes++;
                else cpu_wait_data <= 1'b1;
            end
        end
        else if (cpu_wait_data) begin
            if (cpu_rlast) begin
                cpu_wait_data <= 1'b0;
                cpu_gap <= $urandom_range(0, 2 * WR_GAP);
            end
        end
        else if (cpu_gap > 0)
            cpu_gap <= cpu_gap - 1;
        else if (!stop) begin
            logic we;
            logic [1:0] len;
            we  = ($urandom_range(0, 9) < 7);
            len = we ? (($urandom_range(0, 9) < 8) ? LEN_1 : LEN_2) : LEN_1;
            cpu_req   <= 1'b1;
            cpu_we    <= we;
            cpu_len   <= len;
            cpu_addr  <= we ? area($urandom_range(0, NA - 1 - 1))
                            : {2'd0, 13'($urandom_range(64, 127)), 9'($urandom_range(0, 508))};
            cpu_wdata <= {$urandom, $urandom};
            cpu_wbe   <= (($urandom_range(0, 9) < 5) ? 8'h03 : (($urandom_range(0, 1)) ? 8'h01 : 8'h02))
                         | ((len == LEN_2) ? 8'h0C : 8'h00);
            cpu_gap   <= $urandom_range(0, 2 * WR_GAP);
        end

        if (!reset && init_done) begin
            if (ldr_req && ldr_ack) ldr_req <= 1'b0;
            else if (!stop && !ldr_req && $urandom_range(0, 399) == 0) begin
                ldr_req   <= 1'b1;
                ldr_addr  <= area($urandom_range(0, NA - 1));
                ldr_wdata <= 16'($urandom);
            end
        end
    end

    // ------------------------------------------------------------------
    // Engine A: random requests, pops at their due time
    // ------------------------------------------------------------------
    int a_gap = 0;
    rq_t a_cur;
    always @(posedge clk) begin
        logic accepted;
        a_pop   <= 1'b0;
        a_flush <= 1'b0;
        if (reset) a_rv <= 1'b0;
        else if (init_done) begin
            longint c = cyc();
            accepted = a_rv && a_rdy;
            if (accepted) begin
                qa.push_back(a_cur);
                a_rv <= 1'b0;
            end
            if (a_flush) qa.delete();       // the engine drops everything at this edge
            // flush (never in the clock a pop is being sampled)
            if (!stop && !a_pop && !a_flush && FLUSH_PCT != 0 && $urandom_range(0, 99999) < FLUSH_PCT * 100
                && qa.size() != 0) begin
                a_flush <= 1'b1;
                a_flushes++;
            end
            // pop the head when it is due (never within 4 clocks of the last pop)
            else if (qa.size() != 0 && c + 1 >= qa[0].due && c - a_last_pop >= 4) begin
                a_pop      <= 1'b1;
                a_last_pop  = c + 1;
            end
            // a new request, once the previous one has been taken
            else if (a_gap > 0) a_gap <= a_gap - 1;
            else if (!stop && (!a_rv || accepted) && qa.size() < 3) begin
                logic [1:0]  len;
                int lead;
                len  = ($urandom_range(0, 9) < 4) ? LEN_1 : (($urandom_range(0, 1)) ? LEN_2 : LEN_4);
                lead = ($urandom_range(0, 99) < LATE_PCT) ? $urandom_range(1, 6) : $urandom_range(40, 220);
                a_cur.addr = area($urandom_range(0, NA - 4));
                a_cur.len  = len;
                a_cur.due  = c + 1 + lead;     // the deadline counts from the clock of acceptance
                a_rv <= 1'b1;
                a_rl <= len;
                a_ra <= a_cur.addr;
                a_rd <= 16'(lead);
                a_gap <= $urandom_range(0, 40);
            end
        end
    end

    // ------------------------------------------------------------------
    // Engine B: one word every B_PERIOD clocks, requested one period ahead
    // ------------------------------------------------------------------
    int b_tick = 0;
    int b_pos = 0;
    rq_t b_cur;
    always @(posedge clk) begin
        b_pop <= 1'b0;
        if (reset) b_rv <= 1'b0;
        else if (init_done) begin
            if (b_rv && b_rdy) begin
                qb.push_back(b_cur);
                b_rv <= 1'b0;
            end
            if (!stop) begin
                b_tick <= (b_tick == B_PERIOD - 1) ? 0 : b_tick + 1;
                if (b_tick == 1 && !b_rv) begin
                    b_rv <= 1'b1;
                    b_rl <= LEN_1;
                    b_ra <= area(b_pos);
                    b_rd <= 16'(B_PERIOD + 2);
                    b_cur.addr = area(b_pos);
                    b_cur.len  = LEN_1;
                    b_cur.due  = 0;
                    b_pos <= (b_pos + 1) % NA;
                end
                if (b_tick == 3 && qb.size() > 1)
                    b_pop <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    initial begin
        for (int i = 0; i < NA; i++) begin
            chip.poke(area(i), 16'(i * 37 + 5));
            ref_mem[area(i)] = 16'(i * 37 + 5);
        end
        repeat (10) @(posedge clk);
        reset = 1'b0;
        wait (init_done);
        repeat (CYCLES) @(posedge clk);
        stop = 1'b1;
        repeat (800) @(posedge clk);

        $display("A: %0d entries checked, %0d late pops, %0d flushes, %0d word mismatches, underrun counter %0d",
                 a_checked, a_late, a_flushes, a_mismatch, a_under);
        $display("B: %0d entries checked, %0d late pops, %0d word mismatches, underrun counter %0d",
                 b_checked, b_late, b_mismatch, b_under);
        $display("%0d CPU writes; arbiter: VID latency from urgency max %0d, underruns %0d, CPU latency max %0d",
                 writes, vid_lat_max, vid_underruns, cpu_lat_max);

        if (a_under !== 16'(a_late)) err($sformatf("A underrun counter %0d != late pops %0d", a_under, a_late));
        if (b_under !== 16'(b_late)) err($sformatf("B underrun counter %0d != late pops %0d", b_under, b_late));
        if (a_checked < 500 || b_checked < 500) err("too few entries checked");
        if (a_flushes == 0 && FLUSH_PCT != 0) err("no flush happened");
        if (a_occ != 0 && qa.size() == 0) err($sformatf("A occupancy %0d after drain", a_occ));

        $display("RESULT: %s", (errors == 0 && chip.errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

endmodule
