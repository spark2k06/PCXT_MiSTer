`timescale 1ns/1ps

module CGA_Bus_Wait_tb;
    logic clock = 1'b0;
    logic reset = 1'b1;
    logic [4:0] sequencer_phase = 5'd0;
    logic memory_select = 1'b0;
    logic memory_read_n = 1'b1;
    logic memory_write_n = 1'b1;
    wire ready;

    integer pass_count = 0;
    integer fail_count = 0;

    always #5 clock = ~clock;

    CGA_BUS_WAIT dut (.*);

    task automatic step;
        begin
            @(negedge clock);
            if (sequencer_phase == 5'd31)
                sequencer_phase = 5'd0;
            else
                sequencer_phase = sequencer_phase + 5'd1;
            @(posedge clock);
            #1;
        end
    endtask

    task automatic check(input string label, input logic got, input logic want);
        begin
            if (got !== want) begin
                fail_count = fail_count + 1;
                $display("FAIL  %s: got %b, expected %b at phase %0d",
                         label, got, want, sequencer_phase);
            end
            else begin
                pass_count = pass_count + 1;
                $display("PASS  %s", label);
            end
        end
    endtask

    task automatic release_bus;
        begin
            memory_select = 1'b0;
            memory_read_n = 1'b1;
            memory_write_n = 1'b1;
            step();
            check("release rearms the generator", ready, 1'b1);
        end
    endtask

    initial begin
        repeat (3) @(posedge clock);
        reset = 1'b0;
        step();
        check("idle bus is ready", ready, 1'b1);

        // An access in the first half still completes at the phase-21 slot.
        sequencer_phase = 5'd12;
        memory_select = 1'b1;
        memory_read_n = 1'b0;
        step();
        check("first-half read starts a wait", ready, 1'b0);
        while (sequencer_phase != 5'd20) begin
            step();
            check("READY stays low through the second fetch", ready, 1'b0);
        end
        step();
        check("read completes in the phase-21 ISA window", ready, 1'b1);

        repeat (3) step();
        check("completed access is not stretched twice", ready, 1'b1);
        release_bus();

        // This is the regression case: an access after phase 21 must use the
        // phase-5 window after wrap, not wait another half turn to phase 21.
        sequencer_phase = 5'd24;
        memory_select = 1'b1;
        memory_write_n = 1'b0;
        step();
        check("second-half write starts a wait", ready, 1'b0);
        while (sequencer_phase != 5'd4) begin
            step();
            check("READY stays low through the first fetch", ready, 1'b0);
        end
        step();
        check("write completes in the phase-5 ISA window", ready, 1'b1);

        // From phase 24 the wait is bounded at phase 5.  The old single-window
        // implementation would still be low here until phase 21.
        release_bus();

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
