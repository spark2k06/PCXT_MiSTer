//
// Behavioural x16 SDR SDRAM (4 banks, 8192 rows, 512 columns) with protocol
// checks, for the memory-subsystem benches. Verilator only (--timing): it
// keeps its contents in an associative array and schedules its DQ output
// with fork/join_none.
//
// The model is two-state, so it does not use X or Z on DQ. It says what it is
// doing on DQ with two flags instead:
//
//   dq_drive  the chip is driving DQ (from tLZ to tHZ of a read word)
//   dq_valid  the read data is valid (tAC after the edge before, to tOH after)
//
// The bench builds the pin from these and flags contention and samples taken
// outside dq_valid.
//
// Checked: command decode at the chip's own clock edge, setup/hold of every
// input, tRCD, tRP, tRAS, tRC, tRRD, tWR, tRFC, tMRD, commands to busy or idle
// banks, auto-precharge, the mode register (BL = 1, CL), the power-up order,
// the refresh interval (9 x tREFI at most between AUTO REFRESH commands, i.e.
// no more than 8 postponed) and DQM on reads and writes.
//
`timescale 1ns / 1ps

module sdram_model #(
    parameter real TCK   = 8.730,     // ns
    parameter int  CL    = 3,
    parameter real T_AC  = 5.4,
    parameter real T_OH  = 2.7,
    parameter real T_LZ  = 1.0,
    parameter real T_HZ  = 5.4,
    parameter real T_IS  = 1.5,
    parameter real T_IH  = 0.8,
    parameter real T_RCD = 18.0,
    parameter real T_RP  = 18.0,
    parameter real T_RAS = 42.0,
    parameter real T_RC  = 60.0,
    parameter real T_RRD = 12.0,
    parameter real T_WR  = 14.0,      // and at least 2 clocks
    parameter real T_RFC = 60.0,
    parameter real T_REFI_MAX = 9.0 * 7812.5,
    // MiSTer SDRAM XS/XSDS boards wire the chip's DQML/DQMH to the FPGA's
    // A11/A12 nets, not to the dedicated DQML/DQMH pins (official schematic,
    // sdram_xsds_3.0.pdf, U1A/U2A pins 15/39). 1 models that wiring.
`ifdef DQM_XS
    parameter bit DQM_FROM_A = 1'b1       // -DDQM_XS: the XS board wiring
`else
    parameter bit DQM_FROM_A = 1'b0
`endif
) (
    input  logic        clk,          // SDRAM_CLK as seen by the chip
    input  logic        cke,
    input  logic        cs_n,
    input  logic        ras_n,
    input  logic        cas_n,
    input  logic        we_n,
    input  logic [1:0]  ba,
    input  logic [12:0] a,
    input  logic [1:0]  dqm,          // the dedicated DQMH/DQML pins
    input  logic [15:0] dq_in,        // what the FPGA drives
    input  logic        dq_in_oe,
    output logic [15:0] dq_out,
    output logic        dq_drive,
    output logic        dq_valid
);

    wire [1:0] dqm_e = DQM_FROM_A ? {a[12], a[11]} : dqm;

    // Driven by forked processes, so they live at module scope.
    logic [15:0] r_out   = 16'h0000;
    int          r_drive = 0;       // words being driven (they overlap)
    logic        r_valid = 1'b0;

    assign dq_out   = r_out;
    assign dq_drive = (r_drive != 0);
    assign dq_valid = r_valid;

    logic [15:0] mem [int unsigned];

    int errors = 0;
    int reads = 0, writes = 0, acts = 0, refs = 0;

    task automatic fail(input string msg);
        errors++;
        if (errors <= 20)
            $display("%0.3f SDRAM ERROR: %s", $realtime, msg);
    endtask

    // ---------------------------------------------------------------------
    // Setup / hold
    // ---------------------------------------------------------------------
    real last_change = -1000.0;
    real last_edge   = -1000.0;
    real last_dq_change = -1000.0;

    always @(cke or cs_n or ras_n or cas_n or we_n or ba or a or dqm) begin
        last_change = $realtime;
        if (($realtime - last_edge) < T_IH && $realtime > 1.0 && ~cs_n)
            fail($sformatf("command/address hold %.3f ns", $realtime - last_edge));
    end

    always @(dq_in or dq_in_oe)
        last_dq_change = $realtime;

    // ---------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------
    typedef enum {B_IDLE, B_ACTIVE} bstate_t;

    bstate_t   bstate   [4];
    int        brow     [4];
    real       t_act    [4];
    real       t_ready  [4];       // earliest next ACTIVE (precharge done)
    real       t_last_act_any = -1000.0;
    real       t_last_ref     = -1000.0;
    real       t_ref_busy     = -1000.0;
    real       t_mrs          = -1000.0;
    logic      mode_set = 1'b0;
    logic      pall_seen = 1'b0;
    int        init_refs = 0;
    int        edge_no = 0;

    // A read waiting for its DQM edge (CL - 2 clocks after the command).
    typedef struct {
        int          dqm_edge;
        logic [15:0] data;
    } pend_t;
    pend_t pend [$];

    initial
        for (int b = 0; b < 4; b++) begin
            bstate[b]  = B_IDLE;
            t_act[b]   = -1000.0;
            t_ready[b] = 0.0;
        end

    function automatic int unsigned waddr(input logic [1:0] b, input int row, input logic [8:0] col);
        waddr = {b, 13'(row), col};
    endfunction

    // Drive one read word whose data edge is two clocks after now.
    task automatic emit(input logic [15:0] v, input logic [1:0] mask);
        fork begin
            // The data edge is now + 2 TCK. The chip starts driving tLZ after
            // the edge before it and has valid data tAC after that edge; it
            // holds it tOH after the data edge and stops driving tHZ after.
            automatic logic [15:0] vv = v;
            automatic logic [1:0]  mm = mask;
            #(TCK + T_LZ);
            if (mm != 2'b11) r_drive++;
            #(T_AC - T_LZ);
            r_out   = vv;
            r_valid = (mm == 2'b00);
            #(TCK + T_OH - T_AC);
            r_valid = 1'b0;
            r_out   = 16'hDEAD;
            #(T_HZ - T_OH);
            if (mm != 2'b11) r_drive--;
        end join_none
    endtask

    // ---------------------------------------------------------------------
    // Command decode
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        real now;
        logic [3:0] cmd;
        now = $realtime;
        last_edge = now;
        edge_no++;

        if ((now - last_change) < T_IS && ~cs_n)
            fail($sformatf("command/address setup %.3f ns", now - last_change));

        // Reads whose DQM is sampled on this edge.
        while (pend.size() > 0 && pend[0].dqm_edge == edge_no) begin
            emit(pend[0].data, dqm_e);
            void'(pend.pop_front());
        end

        cmd = {cs_n, ras_n, cas_n, we_n};

        if (cke) case (cmd)
            4'b0011: begin  // ACTIVE
                acts++;
                if (!mode_set) fail("ACTIVE before MODE REGISTER SET");
                if (bstate[ba] != B_IDLE) fail($sformatf("ACTIVE to open bank %0d", ba));
                if (now < t_ready[ba] - 0.01) fail($sformatf("ACTIVE bank %0d %.2f ns early (tRP/tRC/tWR)", ba, t_ready[ba] - now));
                if (now - t_act[ba] < T_RC - 0.01) fail($sformatf("tRC bank %0d: %.2f", ba, now - t_act[ba]));
                if (now - t_last_act_any < T_RRD - 0.01) fail($sformatf("tRRD: %.2f", now - t_last_act_any));
                if (now < t_ref_busy - 0.01) fail("ACTIVE inside tRFC");
                if (now - t_mrs < 2.0 * TCK - 0.01) fail("tMRD");
                bstate[ba] = B_ACTIVE;
                brow[ba]   = int'(a);
                t_act[ba]  = now;
                t_last_act_any = now;
            end

            4'b0101, 4'b0100: begin  // READ, WRITE
                logic w;
                logic ap;
                logic [8:0] col;
                int unsigned wa;
                w   = (cmd == 4'b0100);
                ap  = a[10];
                col = a[8:0];
                if (bstate[ba] != B_ACTIVE) fail($sformatf("%s to idle bank %0d", w ? "WRITE" : "READ", ba));
                if (now - t_act[ba] < T_RCD - 0.01) fail($sformatf("tRCD bank %0d: %.2f", ba, now - t_act[ba]));
                wa = waddr(ba, brow[ba], col);
                if (w) begin
                    logic [15:0] old, v;
                    writes++;
                    if (!dq_in_oe) fail("WRITE without the FPGA driving DQ");
                    if ((now - last_dq_change) < T_IS) fail($sformatf("DQ setup %.3f ns", now - last_dq_change));
                    old = mem.exists(wa) ? mem[wa] : 16'h0000;
                    v   = {dqm_e[1] ? old[15:8] : dq_in[15:8], dqm_e[0] ? old[7:0] : dq_in[7:0]};
                    mem[wa] = v;
                end
                else begin
                    pend_t p;
                    reads++;
                    p.dqm_edge = edge_no + CL - 2;
                    p.data     = mem.exists(wa) ? mem[wa] : 16'h0000;
                    if (CL == 2)
                        emit(p.data, dqm_e);
                    else
                        pend.push_back(p);
                end
                if (ap) begin
                    real pre;
                    real wr;
                    wr  = (T_WR > 2.0 * TCK) ? T_WR : 2.0 * TCK;
                    pre = w ? now + wr : now + TCK;
                    if (pre < t_act[ba] + T_RAS) pre = t_act[ba] + T_RAS;   // tRAS lock-out
                    t_ready[ba] = pre + T_RP;
                    bstate[ba]  = B_IDLE;
                end
            end

            4'b0010: begin  // PRECHARGE
                for (int b = 0; b < 4; b++)
                    if (a[10] || ba == 2'(b)) begin
                        if (bstate[b] == B_ACTIVE && now - t_act[b] < T_RAS - 0.01)
                            fail($sformatf("tRAS bank %0d", b));
                        bstate[b]  = B_IDLE;
                        if (t_ready[b] < now + T_RP) t_ready[b] = now + T_RP;
                    end
                if (a[10]) pall_seen = 1'b1;
            end

            4'b0001: begin  // AUTO REFRESH
                refs++;
                for (int b = 0; b < 4; b++) begin
                    if (bstate[b] != B_IDLE) fail("AUTO REFRESH with a bank open");
                    if (now < t_ready[b] - 0.01) fail($sformatf("AUTO REFRESH bank %0d not precharged", b));
                end
                if (now < t_ref_busy - 0.01) fail("AUTO REFRESH inside tRFC");
                if (!pall_seen) fail("AUTO REFRESH before PRECHARGE ALL");
                if (mode_set && t_last_ref > 0.0 && now - t_last_ref > T_REFI_MAX)
                    fail($sformatf("refresh interval %.1f ns", now - t_last_ref));
                if (!mode_set) init_refs++;
                t_last_ref = now;
                t_ref_busy = now + T_RFC;
                for (int b = 0; b < 4; b++)
                    t_ready[b] = now + T_RFC;
            end

            4'b0000: begin  // MODE REGISTER SET
                if (init_refs < 2) fail("MODE REGISTER SET before two AUTO REFRESH");
                if (a[2:0] != 3'b000) fail("burst length is not 1");
                if (a[6:4] != 3'(CL)) fail($sformatf("CAS latency %0d, expected %0d", a[6:4], CL));
                for (int b = 0; b < 4; b++)
                    if (bstate[b] != B_IDLE) fail("MODE REGISTER SET with a bank open");
                mode_set = 1'b1;
                t_mrs    = now;
            end

            default: ;      // NOP, DESELECT, BURST STOP (unused)
        endcase

        // Refresh starvation, even while nothing else happens.
        if (mode_set && t_last_ref > 0.0 && now - t_last_ref > T_REFI_MAX + TCK)
            fail($sformatf("no AUTO REFRESH for %.1f ns", now - t_last_ref));
    end

    // Back-door access for the benches.
    function automatic logic [15:0] peek(input int unsigned wa);
        peek = mem.exists(wa) ? mem[wa] : 16'h0000;
    endfunction

    task automatic poke(input int unsigned wa, input logic [15:0] v);
        mem[wa] = v;
    endtask

endmodule
