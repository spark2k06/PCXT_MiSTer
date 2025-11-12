`timescale 1ns / 1ps

module tb_int32_simple;

    reg clk, reset, enable;
    reg signed [31:0] int_in;
    wire [79:0] fp_out;
    wire done;

    always #5 clk = ~clk;

    FPU_Int32_to_FP80 dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .int_in(int_in),
        .fp_out(fp_out),
        .done(done)
    );

    initial begin
        $display("Simple Int32 to FP80 Test");
        clk = 0;
        reset = 1;
        enable = 0;
        int_in = 32'd0;

        #20 reset = 0;
        #10;

        // Test 1: Convert 2
        int_in = 32'd2;
        enable = 1;
        #10;  // One clock cycle
        $display("After 1 cycle: done=%b, fp_out=%h", done, fp_out);
        #10;  // Two clock cycles
        $display("After 2 cycles: done=%b, fp_out=%h", done, fp_out);
        enable = 0;
        #10;
        $display("After enable=0: done=%b, fp_out=%h", done, fp_out);

        #20;
        $display("\nExpected: 4000c000000000000000 (2.0 = 1.0 * 2^1)");
        $finish;
    end

endmodule
