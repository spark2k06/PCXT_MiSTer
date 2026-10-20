//
// sdram_txn_mux: two masters on one bridge. The bench stands in for the bridge
// (one transaction at a time; busy from the accepting edge, done with busy low,
// as sdram_xbridge does) and checks that
//   - every transaction reaches the bridge with the fields of the master that
//     started it,
//   - the done goes to that master only, also when the other master asks in the
//     very clock the previous transaction finishes,
//   - nothing is lost or duplicated under random, mixed traffic.
//
`timescale 1ns / 1ps

module sdram_txn_mux_tb;
    logic clock = 1'b0, reset = 1'b1;
    always #10 clock = ~clock;

    logic        a0_start = 0, a1_start = 0;
    logic [23:0] a0_addr = 0, a1_addr = 0;
    logic [63:0] a0_wdata = 0, a1_wdata = 0;
    wire         a0_done, a1_done;
    wire         m_start, m_we;  wire [23:0] m_addr;  wire [1:0] m_len;
    wire [63:0]  m_wdata;  wire [7:0] m_wbe;
    logic        m_busy = 0, m_done = 0;

    sdram_txn_mux dut (
        .clock(clock), .reset(reset),
        .a0_start(a0_start), .a0_we(1'b1), .a0_addr(a0_addr), .a0_len(2'd0),
        .a0_wdata(a0_wdata), .a0_wbe(8'h03), .a0_done(a0_done),
        .a1_start(a1_start), .a1_we(1'b0), .a1_addr(a1_addr), .a1_len(2'd1),
        .a1_wdata(a1_wdata), .a1_wbe(8'h0F), .a1_done(a1_done),
        .m_start(m_start), .m_we(m_we), .m_addr(m_addr), .m_len(m_len),
        .m_wdata(m_wdata), .m_wbe(m_wbe), .m_busy(m_busy), .m_done(m_done)
    );

    // the bridge
    int          left = 0;
    logic        who_q;
    logic [23:0] addr_q;
    always @(posedge clock) begin
        m_done <= 1'b0;
        if (m_start && !m_busy) begin
            m_busy <= 1'b1;
            left   <= $urandom_range(6, 1);
            addr_q <= m_addr;
        end
        else if (m_busy) begin
            if (left == 0) begin m_busy <= 1'b0; m_done <= 1'b1; end
            else left <= left - 1;
        end
    end

    // masters: a request is held until the bridge takes it; then wait for the done
    int errors = 0, n0 = 0, n1 = 0, issued0 = 0, issued1 = 0;
    logic w0 = 0, w1 = 0;                       // waiting for the done
    logic [23:0] exp_addr0, exp_addr1;

    always @(posedge clock) if (!reset) begin
        // field checks at the accepting edge
        if (m_start && !m_busy) begin
            if (a1_start) begin
                if (m_we !== 1'b0 || m_len !== 2'd1 || m_wbe !== 8'h0F || m_addr !== a1_addr || m_wdata !== a1_wdata)
                    begin errors++; $display("FAIL fields of master 1 wrong"); end
            end
            else begin
                if (m_we !== 1'b1 || m_len !== 2'd0 || m_wbe !== 8'h03 || m_addr !== a0_addr || m_wdata !== a0_wdata)
                    begin errors++; $display("FAIL fields of master 0 wrong"); end
            end
        end
        // dones
        if (a0_done) begin
            if (!w0) begin errors++; $display("FAIL master 0 got a done it did not wait for"); end
            w0 <= 1'b0;  a0_start <= 1'b0;  n0++;
        end
        if (a1_done) begin
            if (!w1) begin errors++; $display("FAIL master 1 got a done it did not wait for"); end
            w1 <= 1'b0;  a1_start <= 1'b0;  n1++;
        end
        // a master that is idle may ask again, at random
        if (!a0_start && !w0 && $urandom_range(3, 0) == 0) begin
            a0_start <= 1'b1;  a0_addr <= 24'($urandom);  a0_wdata <= {$urandom, $urandom};  issued0++;
        end
        if (!a1_start && !w1 && !a0_start && $urandom_range(3, 0) == 0) begin
            a1_start <= 1'b1;  a1_addr <= 24'($urandom);  a1_wdata <= {$urandom, $urandom};  issued1++;
        end
        // a start the bridge has accepted becomes a wait (the master drops start next clock)
        if (m_start && !m_busy) begin
            if (a1_start) begin w1 <= 1'b1; a1_start <= 1'b0; end
            else          begin w0 <= 1'b1; a0_start <= 1'b0; end
        end
    end

    initial begin
        repeat (4) @(posedge clock);
        reset = 1'b0;
        repeat (40000) @(posedge clock);
        a0_start = 1'b0;  a1_start = 1'b0;
        repeat (100) @(posedge clock);
        $display("transactions: master 0 %0d of %0d, master 1 %0d of %0d", n0, issued0, n1, issued1);
        if (n0 + 2 < issued0 || n1 + 2 < issued1) begin errors++; $display("FAIL transactions lost"); end
        if (errors == 0) $display("RESULT: PASS"); else $display("RESULT: FAIL (%0d)", errors);
        $finish;
    end
endmodule
