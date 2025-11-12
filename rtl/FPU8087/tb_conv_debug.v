`timescale 1ns / 1ps

//===========================================
// Direct conversion test
//===========================================

module tb_conv_debug;

    reg clk, reset;
    always #5 clk = ~clk;

    reg enable;
    reg signed [31:0] int_in;
    wire [79:0] fp_out;
    wire done;

    FPU_Int32_to_FP80 dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .int_in(int_in),
        .fp_out(fp_out),
        .done(done)
    );

    initial begin
        $display("Direct Int32 to FP80 Conversion Test");
        $display("====================================");

        clk = 0;
        reset = 1;
        enable = 0;
        int_in = 32'd0;

        #20 reset = 0;
        #20;

        // Test converting 2
        int_in = 32'd2;
        enable = 1;
        @(posedge clk);
        enable = 0;

        wait(done == 1'b1);
        @(posedge clk);

        $display("Input: %0d", 32'sd2);
        $display("Output: %h", fp_out);
        $display("Expected: 4000c000000000000000");  // 2.0 = 1.0 * 2^1
        if (fp_out == 80'h4000C000000000000000)
            $display("PASS");
        else
            $display("FAIL");

        #100;
        $finish;
    end

endmodule
