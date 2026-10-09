`timescale 1ns/1ps

// CGA_BUS_WAIT runs its state machine on the chipset clock and only takes a
// synchronized fetch-window level from the CGA clock. Drive both clocks at
// their real frequencies (50 MHz and 28.636 MHz) so the bench exercises the
// crossing, and check READY as the chipset sees it.
module CGA_Bus_Wait_tb;
    localparam real CHIP_HALF  = 10.0;          // 50 MHz
    localparam real VIDEO_HALF = 17.4603;       // 28.636 MHz

    logic clock = 1'b0;
    logic video_clock = 1'b0;
    logic reset = 1'b1;
    logic [4:0] sequencer_phase = 5'd0;
    logic memory_select = 1'b0;
    logic memory_read_n = 1'b1;
    logic memory_write_n = 1'b1;
    wire ready;

    integer pass_count = 0;
    integer fail_count = 0;

    always #(CHIP_HALF)  clock = ~clock;
    always #(VIDEO_HALF) video_clock = ~video_clock;

    always @(posedge video_clock)
        sequencer_phase <= sequencer_phase + 5'd1;

    CGA_BUS_WAIT dut (.*);

    task automatic check(input string label, input logic cond);
        begin
            if (!cond) begin
                fail_count = fail_count + 1;
                $display("FAIL  %s (phase %0d, t=%0t)", label, sequencer_phase, $time);
            end
            else
                pass_count = pass_count + 1;
        end
    endtask

    task automatic wait_phase(input logic [4:0] phase);
        begin
            @(posedge video_clock);
            while (sequencer_phase != phase)
                @(posedge video_clock);
        end
    endtask

    // Start an access on a chipset edge and return the sequencer phase at
    // which the chipset first sees READY high again, and the wait in ns.
    task automatic access(input logic write, output logic [4:0] done_phase,
                          output real wait_ns, output logic hung);
        real t0;
        integer cycles;
        begin
            @(posedge clock);
            #1;
            memory_select  = 1'b1;
            memory_read_n  = write;
            memory_write_n = ~write;
            #0.1;
            check("READY drops in the cycle the access starts", ready == 1'b0);
            t0 = $realtime;
            cycles = 0;
            hung = 1'b0;
            @(posedge clock);
            while (ready !== 1'b1 && !hung) begin
                cycles = cycles + 1;
                if (cycles > 200)
                    hung = 1'b1;
                else
                    @(posedge clock);
            end
            done_phase = sequencer_phase;
            wait_ns = $realtime - t0;
            repeat (2) @(posedge clock);
            #1;
            memory_select  = 1'b0;
            memory_read_n  = 1'b1;
            memory_write_n = 1'b1;
            repeat (2) @(posedge clock);
            #0.1;
            check("READY returns high when the access ends", ready == 1'b1);
        end
    endtask

    logic [4:0] done_phase;
    real        wait_ns;
    real        max_wait;
    logic       hung;
    integer     i, hangs;

    initial begin
        repeat (4) @(posedge clock);
        reset = 1'b0;
        repeat (4) @(posedge clock);
        #0.1;
        check("idle bus is ready", ready == 1'b1);

        // An access in the first half completes in the phase-21 slot.
        wait_phase(5'd12);
        access(1'b0, done_phase, wait_ns, hung);
        check("first-half read is not hung", !hung);
        check("first-half read completes around the phase-21 slot",
              done_phase >= 5'd21 && done_phase <= 5'd23);

        // An access after phase 21 uses the phase-5 slot after wrap instead
        // of waiting another half turn to phase 21.
        wait_phase(5'd24);
        access(1'b1, done_phase, wait_ns, hung);
        check("second-half write is not hung", !hung);
        check("second-half write completes around the phase-5 slot",
              done_phase >= 5'd5 && done_phase <= 5'd7);

        // Stress the crossing: accesses starting at arbitrary times relative
        // to both clocks must always complete, within one half sequencer
        // turn plus the synchronizer latency.
        hangs = 0;
        max_wait = 0.0;
        for (i = 0; i < 20000; i = i + 1) begin
            #($urandom_range(0, 997) / 100.0);
            access($urandom_range(0, 1), done_phase, wait_ns, hung);
            if (hung)
                hangs = hangs + 1;
            if (wait_ns > max_wait)
                max_wait = wait_ns;
        end
        check("no access hangs under random start times", hangs == 0);
        check("no wait exceeds half a sequencer turn plus sync latency",
              max_wait < 16.0 * 2.0 * VIDEO_HALF + 4.0 * 2.0 * VIDEO_HALF + 60.0);
        $display("random accesses: 20000, hangs: %0d, longest wait %0.1f ns", hangs, max_wait);

        $display("");
        $display("%0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0) begin
            $display("RESULT: PASS");
            $finish;
        end
        else begin
            $display("RESULT: FAIL");
            $fatal(1);
        end
    end
endmodule
