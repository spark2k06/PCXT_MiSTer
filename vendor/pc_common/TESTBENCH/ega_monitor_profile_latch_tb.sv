//============================================================================
//
//  IBM EGA monitor selection must only take effect during machine reset.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_monitor_profile_latch_tb;

    logic clock = 1'b0;
    always #10 clock = ~clock;

    logic       reset_active = 1'b1;
    logic [1:0] selected = 2'b00;
    wire  [1:0] applied;
    integer errors = 0;

    ega_monitor_profile_latch dut (
        .clock        (clock),
        .reset_active (reset_active),
        .selected     (selected),
        .applied      (applied)
    );

    task automatic check(input string tag, input logic [1:0] expected);
        begin
            if (applied !== expected) begin
                errors = errors + 1;
                $display("FAIL: %s applied=%02b expected=%02b", tag, applied, expected);
            end
        end
    endtask

    initial begin
        selected = 2'd1;
        repeat (2) @(posedge clock);
        #1 check("CGA captured during initial reset", 2'd1);

        reset_active = 1'b0;
        selected = 2'd2;
        repeat (4) @(posedge clock);
        #1 check("MDA remains pending while running", 2'd1);

        reset_active = 1'b1;
        repeat (2) @(posedge clock);
        #1 check("MDA applied by reset", 2'd2);

        selected = 2'd0;
        repeat (2) @(posedge clock);
        #1 check("latest stable choice captured before BIOS", 2'd0);

        reset_active = 1'b0;
        selected = 2'd1;
        repeat (3) @(posedge clock);
        #1 check("post-reset CGA waits for another reset", 2'd0);

        if (errors == 0)
            $display("PASS: monitor selection changes only during reset");
        else
            $display("FAIL: %0d monitor profile latch checks failed", errors);
        $finish;
    end

endmodule
