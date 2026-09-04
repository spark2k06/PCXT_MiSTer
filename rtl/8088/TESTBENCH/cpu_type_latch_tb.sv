//============================================================================
//
//  CPU type selection must only take effect during machine reset.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module cpu_type_latch_tb;

    logic clock = 1'b0;
    always #10 clock = ~clock;

    logic reset_active = 1'b0;
    logic selected_8086 = 1'b0;
    wire  is8086;
    integer errors = 0;

    cpu_type_latch dut (
        .clock        (clock),
        .reset_active (reset_active),
        .selected_8086(selected_8086),
        .is8086       (is8086)
    );

    task automatic check(input string tag, input logic expected);
        begin
            if (is8086 !== expected) begin
                errors = errors + 1;
                $display("FAIL: %s is8086=%0b expected=%0b", tag, is8086, expected);
            end
        end
    endtask

    initial begin
        #1 check("power-on default is 8088", 1'b0);

        selected_8086 = 1'b1;
        repeat (3) @(posedge clock);
        #1 check("running selection remains pending", 1'b0);

        reset_active = 1'b1;
        repeat (2) @(posedge clock);
        #1 check("reset applies 8086", 1'b1);

        selected_8086 = 1'b0;
        repeat (2) @(posedge clock);
        #1 check("latest selection is tracked throughout reset", 1'b0);

        reset_active = 1'b0;
        selected_8086 = 1'b1;
        repeat (3) @(posedge clock);
        #1 check("post-reset change cannot alter the running CPU", 1'b0);

        reset_active = 1'b1;
        repeat (2) @(posedge clock);
        #1 check("next reset applies pending 8086", 1'b1);

        reset_active = 1'b0;
        selected_8086 = 1'b0;
        repeat (3) @(posedge clock);
        #1 check("applied 8086 remains stable while running", 1'b1);

        if (errors == 0)
            $display("RESULT: PASS (CPU type changes only during reset)");
        else
            $display("RESULT: FAIL (%0d CPU type latch checks failed)", errors);
        $finish;
    end

endmodule
