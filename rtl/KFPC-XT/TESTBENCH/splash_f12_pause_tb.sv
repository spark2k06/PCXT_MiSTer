//============================================================================
//
//  Splash F12 pause regression.
//
//============================================================================

`timescale 1ns/1ps

module splash_f12_pause_tb;

    logic        clock = 1'b0;
    logic        splash_active = 1'b1;
    logic [10:0] ps2_key = 11'd0;
    wire         paused;

    always #34.92 clock = ~clock;   // 14.318 MHz

    splash_f12_pause dut (
        .clock         (clock),
        .splash_active (splash_active),
        .ps2_key       (ps2_key),
        .paused        (paused)
    );

    integer errors = 0;

    task automatic check(input logic actual, input logic expected, input string what);
        begin
            if (actual !== expected) begin
                $display("FAIL: %s - expected %0d, got %0d", what, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task automatic key(input logic pressed, input logic extended, input [7:0] code);
        begin
            @(negedge clock);
            ps2_key = {~ps2_key[10], pressed, extended, code};
            repeat (6) @(posedge clock);
        end
    endtask

    initial begin
        repeat (6) @(posedge clock);
        check(paused, 1'b0, "idle");

        // The make code is ignored; the break code toggles once.
        key(1'b1, 1'b0, 8'h07);
        check(paused, 1'b0, "F12 make does not toggle");
        key(1'b0, 1'b0, 8'h07);
        check(paused, 1'b1, "F12 break pauses");

        // Repeated make codes must not chatter the pause state.
        key(1'b1, 1'b0, 8'h07);
        key(1'b1, 1'b0, 8'h07);
        check(paused, 1'b1, "auto-repeat does not chatter");
        key(1'b0, 1'b0, 8'h07);
        check(paused, 1'b0, "second press resumes");

        // Other keys and extended 07 are ignored.
        key(1'b0, 1'b0, 8'h07);
        key(1'b0, 1'b0, 8'h09);
        check(paused, 1'b1, "F10 ignored");
        key(1'b0, 1'b1, 8'h07);
        check(paused, 1'b1, "extended 07 ignored");

        splash_active = 1'b0;
        repeat (4) @(posedge clock);
        check(paused, 1'b0, "cleared when the splash ends");
        key(1'b0, 1'b0, 8'h07);
        check(paused, 1'b0, "F12 ignored once the splash is gone");

        if (errors == 0)
            $display("PASS: F12 holds the splash and only F12 does");
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

endmodule
