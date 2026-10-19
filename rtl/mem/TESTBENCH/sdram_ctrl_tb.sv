//
// sdram_ctrl against the behavioural chip (sdram_model.sv).
//
// The bench plays the arbiter: it holds one operation until op_issue, with a
// reference copy of the memory to check every read word against. It runs
// directed cases, then random traffic over all banks with refreshes in
// between, and reports issue spacing so the bank overlap can be seen.
//
// Pin timing: the controller's outputs reach the chip TCO after the clock
// edge, and SDRAM_CLK leads the controller clock by LEAD, as on the board.
// The bench fails on any protocol error from the model, on DQ contention, on
// a capture edge where the chip's data was not valid, and on wrong data.
//
// Run with run_tests.sh (Verilator --binary --timing).
//
`timescale 1ns / 1ps

module sdram_ctrl_tb #(
    parameter int  RANDOM_OPS = 30000,
    parameter real LEAD = 2.0,
    parameter real TCO  = 3.0,
    parameter int  RD_DELAY = 0
);
    import sdram_pkg::*;

    localparam real TCK = 8.730;
    localparam int  CL  = 3;
    localparam int  REFI = 894;

    logic clk = 1'b0;
    logic sdram_clk = 1'b0;
    always #(TCK / 2.0) clk = ~clk;
    initial begin
        #(TCK - LEAD);
        forever #(TCK / 2.0) sdram_clk = ~sdram_clk;
    end

    logic reset = 1'b1;

    // Arbiter side
    logic        op_valid = 1'b0, op_ref = 1'b0, op_we = 1'b0;
    logic [23:0] op_addr = '0;
    logic [1:0]  op_len = LEN_1;
    logic [63:0] op_wdata = '0;
    logic [7:0]  op_wbe = '0;
    logic [1:0]  op_tag = '0;
    wire         op_issue;
    wire         init_done;
    wire         rd_valid, rd_last;
    wire [15:0]  rd_data;
    wire [1:0]   rd_tag;

    // Controller pins
    wire        c_cke, c_cs_n, c_ras_n, c_cas_n, c_we_n, c_oe;
    wire [1:0]  c_ba, c_dqm;
    wire [12:0] c_a;
    wire [15:0] c_dq;

    // The same pins TCO later
    logic        p_cke = 0, p_cs_n = 1, p_ras_n = 1, p_cas_n = 1, p_we_n = 1, p_oe = 0;
    logic [1:0]  p_ba = 0, p_dqm = 3;
    logic [12:0] p_a = 0;
    logic [15:0] p_dq = 0;

    always @(posedge clk) begin
        #(TCO);
        {p_cke, p_cs_n, p_ras_n, p_cas_n, p_we_n, p_oe} = {c_cke, c_cs_n, c_ras_n, c_cas_n, c_we_n, c_oe};
        {p_ba, p_dqm, p_a, p_dq} = {c_ba, c_dqm, c_a, c_dq};
    end

    wire [15:0] chip_dq;
    wire        chip_drive, chip_valid;

    // DQ as the FPGA input register sees it.
    wire [15:0] dq_pin = p_oe ? p_dq : (chip_drive ? chip_dq : 16'hF10A);

    sdram_ctrl #(.INIT_US(200), .RD_DELAY(RD_DELAY)) dut (
        .clk(clk), .reset(reset), .init_done(init_done),
        .op_valid(op_valid), .op_ref(op_ref), .op_we(op_we), .op_addr(op_addr),
        .op_len(op_len), .op_wdata(op_wdata), .op_wbe(op_wbe), .op_tag(op_tag),
        .op_issue(op_issue), .bank_idle(),
        .rd_valid(rd_valid), .rd_data(rd_data), .rd_tag(rd_tag), .rd_last(rd_last),
        .sdram_cke(c_cke), .sdram_cs_n(c_cs_n), .sdram_ras_n(c_ras_n),
        .sdram_cas_n(c_cas_n), .sdram_we_n(c_we_n), .sdram_ba(c_ba), .sdram_a(c_a),
        .sdram_dqm(c_dqm), .sdram_dq_out(c_dq), .sdram_dq_oe(c_oe), .sdram_dq_in(dq_pin)
    );

    sdram_model #(.TCK(TCK), .CL(CL)) chip (
        .clk(sdram_clk), .cke(p_cke), .cs_n(p_cs_n), .ras_n(p_ras_n), .cas_n(p_cas_n),
        .we_n(p_we_n), .ba(p_ba), .a(p_a), .dqm(p_dqm), .dq_in(p_dq), .dq_in_oe(p_oe),
        .dq_out(chip_dq), .dq_drive(chip_drive), .dq_valid(chip_valid)
    );

    // ------------------------------------------------------------------
    // Checks
    // ------------------------------------------------------------------
    int errors = 0;

    task automatic err(input string msg);
        errors++;
        if (errors <= 20) $display("%0.3f ERROR: %s", $realtime, msg);
    endtask

    always @(p_oe or chip_drive)
        if (p_oe && chip_drive) err("DQ contention");

    // The input register samples on every edge; when the schedule says it is
    // a read word, the chip must be holding valid data right then.
    always @(posedge clk)
        if (!reset && dut.rdq_v[0] && !chip_valid)
            err("read word sampled outside the chip's valid window");

    // Reference memory and the queue of expected read words.
    logic [15:0] ref_mem [int unsigned];
    logic [15:0] expq [$];
    logic        lastq [$];

    function automatic logic [15:0] ref_peek(input int unsigned wa);
        ref_peek = ref_mem.exists(wa) ? ref_mem[wa] : 16'h0000;
    endfunction

    // Book-keeping happens on the issue edge, in issue order, which is also
    // the order in which the chip executes same-bank operations.
    longint cycle = 0;
    longint last_issue = 0;
    longint issues = 0, gap_sum = 0, back2back = 0;
    longint t_issue_q [$];
    int     lat_min = 1000, lat_max = 0;
    int     words_read = 0;

    always @(posedge clk) begin
        cycle++;
        if (op_valid && op_issue && !op_ref) begin
            int n;
            n = len_words(op_len);
            issues++;
            if (issues > 1) begin
                gap_sum += cycle - last_issue;
                if (cycle - last_issue < 4) back2back++;
            end
            last_issue = cycle;
            for (int i = 0; i < n; i++) begin
                int unsigned wa;
                wa = op_addr + i;
                if (op_we) begin
                    logic [15:0] o;
                    o = ref_peek(wa);
                    ref_mem[wa] = {op_wbe[2*i+1] ? op_wdata[16*i+8 +: 8] : o[15:8],
                                   op_wbe[2*i]   ? op_wdata[16*i   +: 8] : o[7:0]};
                end
                else begin
                    expq.push_back(ref_peek(wa));
                    lastq.push_back(i == n - 1);
                end
            end
            if (!op_we) t_issue_q.push_back(cycle);
        end

        if (rd_valid) begin
            words_read++;
            if (expq.size() == 0)
                err("unexpected read word");
            else begin
                logic [15:0] e;
                logic l;
                e = expq.pop_front();
                l = lastq.pop_front();
                if (rd_data !== e) err($sformatf("read %04h expected %04h", rd_data, e));
                if (rd_last !== l) err("rd_last out of place");
                if (rd_tag !== 2'd2) err("rd_tag");
                if (l) begin
                    int lat;
                    lat = int'(cycle - t_issue_q.pop_front());
                    if (lat < lat_min) lat_min = lat;
                    if (lat > lat_max) lat_max = lat;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------------
    // The initial block below only queues operations; this clocked process
    // presents them, so the bench and the DUT never race on a clock edge.
    typedef struct {
        logic        ref_;
        logic        we;
        logic [23:0] addr;
        logic [1:0]  len;
        logic [63:0] wdata;
        logic [7:0]  wbe;
        int          gap;       // idle clocks before presenting it
    } op_t;

    op_t  opq [$];
    op_t  staged;
    logic have_staged = 1'b0;
    int   gap_left = 0;

    always @(posedge clk) begin
        if (!op_valid || op_issue) begin
            op_valid <= 1'b0;
            if (!have_staged && opq.size() > 0) begin
                staged      = opq.pop_front();
                have_staged = 1'b1;
                gap_left    = staged.gap;
            end
            if (have_staged) begin
                if (gap_left > 0)
                    gap_left--;
                else begin
                    op_valid    <= 1'b1;
                    op_ref      <= staged.ref_;
                    op_we       <= staged.we;
                    op_addr     <= staged.addr;
                    op_len      <= staged.len;
                    op_wdata    <= staged.wdata;
                    op_wbe      <= staged.wbe;
                    op_tag      <= 2'd2;
                    have_staged = 1'b0;
                end
            end
        end
    end

    task automatic do_op(input logic we, input logic [23:0] addr, input logic [1:0] len,
                         input logic [63:0] wdata, input logic [7:0] wbe, input int gap = 0);
        op_t o;
        o.ref_ = 1'b0;  o.we = we;  o.addr = addr;  o.len = len;
        o.wdata = wdata; o.wbe = wbe; o.gap = gap;
        opq.push_back(o);
    endtask

    task automatic do_ref();
        op_t o;
        o.ref_ = 1'b1;  o.we = 1'b0;  o.addr = 24'd0;  o.len = LEN_1;
        o.wdata = 64'd0; o.wbe = 8'd0; o.gap = 0;
        opq.push_back(o);
    endtask

    task automatic drain();
        while (opq.size() > 0 || have_staged || op_valid) @(posedge clk);
    endtask

    // Refresh debt as the arbiter keeps it: one tREFI tick adds one.
    int produced = 0;
    int consumed = 0;
    int refi_cnt = 0;
    always @(posedge clk)
        if (init_done) begin
            if (refi_cnt == REFI - 1) begin
                refi_cnt <= 0;
                produced <= produced + 1;
            end
            else
                refi_cnt <= refi_cnt + 1;
        end

    function automatic logic [23:0] rand_addr(input logic [1:0] len);
        logic [23:0] a;
        a = $urandom;
        // Keep a burst inside its row, and use few rows so that reads hit
        // data written earlier.
        // Rows with bits 12:11 set matter on the XS/XSDS boards, where those
        // address bits are also the chip's DQM pins (-DDQM_XS models that).
        a[21:9] = 13'($urandom_range(0, 3) | ($urandom_range(0, 3) << 11));
        a[8:0]  = 9'($urandom_range(0, 511 - (len_words(len) - 1)));
        rand_addr = a;
    endfunction

    function automatic logic [1:0] rand_len();
        case ($urandom_range(0, 2))
            0: rand_len = LEN_1;
            1: rand_len = LEN_2;
            default: rand_len = LEN_4;
        endcase
    endfunction

    initial begin
        repeat (10) @(posedge clk);
        reset = 1'b0;
        wait (init_done);
        @(posedge clk);

        // Directed: every length, both directions, byte masks.
        do_op(1, 24'h000010, LEN_1, 64'h1111, 8'h03);
        do_op(1, 24'h000020, LEN_2, 64'h2222_1111, 8'h0F);
        do_op(1, 24'h000040, LEN_4, 64'h4444_3333_2222_1111, 8'hFF);
        do_op(1, 24'h000041, LEN_1, 64'hAB00, 8'h02);               // high byte only
        do_op(1, 24'h000042, LEN_1, 64'h00CD, 8'h01);               // low byte only
        do_op(0, 24'h000010, LEN_1, 0, 0);
        do_op(0, 24'h000020, LEN_2, 0, 0);
        do_op(0, 24'h000040, LEN_4, 0, 0);
        // Column 508..511: last burst of a row.
        do_op(1, 24'h0001FC, LEN_4, 64'hDDDD_CCCC_BBBB_AAAA, 8'hFF);
        do_op(0, 24'h0001FC, LEN_4, 0, 0);
        // Alternating banks, back to back.
        for (int i = 0; i < 8; i++)
            do_op(0, {2'(i), 13'd1, 9'd0}, LEN_2, 0, 0);
        // Read then write on another bank: DQ turnaround.
        for (int i = 0; i < 8; i++) begin
            do_op(0, {2'd0, 13'd2, 9'(i * 4)}, LEN_4, 0, 0);
            do_op(1, {2'd1, 13'd2, 9'(i * 4)}, LEN_4, {4{16'(i)}}, 8'hAA);
        end
        do_ref();

        drain();

        // Random traffic, queued a few operations ahead.
        for (int k = 0; k < RANDOM_OPS; k++) begin
            logic [1:0] len;
            while (opq.size() > 4) @(posedge clk);
            if (produced - consumed >= 8 || (produced > consumed && $urandom_range(0, 15) == 0)) begin
                do_ref();
                consumed++;
            end
            len = rand_len();
            do_op($urandom_range(0, 2) == 0, rand_addr(len), len,
                  {$urandom, $urandom}, 8'($urandom) | 8'h01,
                  ($urandom_range(0, 3) == 0) ? $urandom_range(1, 3) : 0);
        end
        drain();

        repeat (40) @(posedge clk);
        if (expq.size() != 0) err($sformatf("%0d read words never returned", expq.size()));

        $display("%0d ops, %0d words read, read latency issue->last word %0d..%0d clocks",
                 issues, words_read, lat_min, lat_max);
        $display("  mean issue spacing %.2f clocks, %0d issues closer than 4 clocks (bank overlap)",
                 real'(gap_sum) / real'(issues - 1), back2back);
        $display("  chip: %0d ACT, %0d READ, %0d WRITE, %0d REF, %0d protocol errors",
                 chip.acts, chip.reads, chip.writes, chip.refs, chip.errors);
        if (errors == 0 && chip.errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL (%0d bench, %0d chip)", errors, chip.errors);
        $finish;
    end

endmodule
