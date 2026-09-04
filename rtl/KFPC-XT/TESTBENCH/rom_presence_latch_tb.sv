//============================================================================
//
//  ROM presence latch regression.
//
//============================================================================

`timescale 1ns/1ps

module rom_presence_latch_tb;

    logic clock = 1'b0;
    logic reset = 1'b1;
    logic sdram_initialized = 1'b0;
    logic download_active = 1'b0;
    logic write_complete = 1'b0;
    wire loaded;

    always #5 clock = ~clock;

    rom_presence_latch dut (.*);

    integer errors = 0;

    task automatic check(input logic actual, input logic expected, input string what);
        begin
            if (actual !== expected) begin
                $display("FAIL: %s - expected %0d, got %0d", what, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clock);
        @(negedge clock);
        reset = 1'b0;
        sdram_initialized = 1'b1;
        @(posedge clock);
        #1;
        check(loaded, 1'b0, "empty slot starts absent");

        // A download clears the previous state once, but is not present until
        // the loader reports its final write.
        @(negedge clock);
        download_active = 1'b1;
        @(posedge clock);
        #1;
        check(loaded, 1'b0, "download is not yet complete");
        @(negedge clock);
        write_complete = 1'b1;
        @(posedge clock);
        #1 check(loaded, 1'b1, "completed download is present");
        @(negedge clock);
        write_complete = 1'b0;
        download_active = 1'b0;
        @(posedge clock);
        #1;
        check(loaded, 1'b1, "idle keeps the loaded state");

        // A new active download invalidates the old image immediately.
        @(negedge clock);
        download_active = 1'b1;
        @(posedge clock);
        #1 check(loaded, 1'b0, "replacement download invalidates old image");

        if (errors == 0)
            $display("PASS: ROM presence requires a completed download");
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
