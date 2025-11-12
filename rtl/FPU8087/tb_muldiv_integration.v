`timescale 1ns / 1ps

//=====================================================================
// Integration Test for MulDiv in FPU_ArithmeticUnit
//
// Tests multiply and divide operations through FPU_ArithmeticUnit
// to ensure proper integration of the unified MulDiv module.
//=====================================================================

module tb_muldiv_integration;

    reg clk, reset;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // FPU_ArithmeticUnit signals
    reg [4:0]  operation;
    reg        enable;
    reg [1:0]  rounding_mode;
    reg [79:0] operand_a, operand_b;
    reg signed [15:0] int16_in;
    reg signed [31:0] int32_in;
    reg [63:0] uint64_in;
    reg        uint64_sign_in;
    reg [31:0] fp32_in;
    reg [63:0] fp64_in;

    wire [79:0] result;
    wire [79:0] result_secondary;
    wire        has_secondary;
    wire signed [15:0] int16_out;
    wire signed [31:0] int32_out;
    wire [63:0] uint64_out;
    wire        uint64_sign_out;
    wire [31:0] fp32_out;
    wire [63:0] fp64_out;
    wire        done;
    wire        cc_less, cc_equal, cc_greater, cc_unordered;
    wire        flag_invalid, flag_denormal, flag_zero_divide;
    wire        flag_overflow, flag_underflow, flag_inexact;

    // Operation codes
    localparam OP_ADD = 4'd0;
    localparam OP_SUB = 4'd1;
    localparam OP_MUL = 4'd2;
    localparam OP_DIV = 4'd3;

    // Instantiate FPU_ArithmeticUnit
    FPU_ArithmeticUnit arith_unit (
        .clk(clk),
        .reset(reset),
        .operation(operation),
        .enable(enable),
        .rounding_mode(rounding_mode),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .int16_in(int16_in),
        .int32_in(int32_in),
        .uint64_in(uint64_in),
        .uint64_sign_in(uint64_sign_in),
        .fp32_in(fp32_in),
        .fp64_in(fp64_in),
        .result(result),
        .result_secondary(result_secondary),
        .has_secondary(has_secondary),
        .int16_out(int16_out),
        .int32_out(int32_out),
        .uint64_out(uint64_out),
        .uint64_sign_out(uint64_sign_out),
        .fp32_out(fp32_out),
        .fp64_out(fp64_out),
        .done(done),
        .cc_less(cc_less),
        .cc_equal(cc_equal),
        .cc_greater(cc_greater),
        .cc_unordered(cc_unordered),
        .flag_invalid(flag_invalid),
        .flag_denormal(flag_denormal),
        .flag_zero_divide(flag_zero_divide),
        .flag_overflow(flag_overflow),
        .flag_underflow(flag_underflow),
        .flag_inexact(flag_inexact)
    );

    integer test_count, pass_count, fail_count;

    task test_operation;
        input [4:0]  op;
        input [79:0] a;
        input [79:0] b;
        input [79:0] expected;
        input [80*8-1:0] name;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            operation = op;
            operand_a = a;
            operand_b = b;
            rounding_mode = 2'b00;

            @(posedge clk);
            enable = 1'b0;

            while (!done) @(posedge clk);

            if (result == expected) begin
                $display("PASS: %0s", name);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s", name);
                $display("  Expected: %h", expected);
                $display("  Got:      %h", result);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $display("========================================");
        $display("MulDiv Integration Test (FPU_ArithmeticUnit)");
        $display("========================================");

        reset = 1;
        enable = 0;
        operation = 0;
        operand_a = 0;
        operand_b = 0;
        rounding_mode = 2'b00;
        int16_in = 0;
        int32_in = 0;
        uint64_in = 0;
        uint64_sign_in = 0;
        fp32_in = 0;
        fp64_in = 0;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        #20;
        reset = 0;
        #20;

        $display("\n--- Multiply Tests ---");
        test_operation(OP_MUL, 80'h3FFF_8000_0000_0000_0000, 80'h3FFF_8000_0000_0000_0000,
                       80'h3FFF_8000_0000_0000_0000, "1.0 * 1.0 = 1.0");
        test_operation(OP_MUL, 80'h4000_8000_0000_0000_0000, 80'h4000_8000_0000_0000_0000,
                       80'h4001_8000_0000_0000_0000, "2.0 * 2.0 = 4.0");
        test_operation(OP_MUL, 80'h3FFE_8000_0000_0000_0000, 80'h4000_8000_0000_0000_0000,
                       80'h3FFF_8000_0000_0000_0000, "0.5 * 2.0 = 1.0");

        $display("\n--- Divide Tests ---");
        test_operation(OP_DIV, 80'h3FFF_8000_0000_0000_0000, 80'h3FFF_8000_0000_0000_0000,
                       80'h3FFF_8000_0000_0000_0000, "1.0 / 1.0 = 1.0");
        test_operation(OP_DIV, 80'h4000_8000_0000_0000_0000, 80'h4000_8000_0000_0000_0000,
                       80'h3FFF_8000_0000_0000_0000, "2.0 / 2.0 = 1.0");
        test_operation(OP_DIV, 80'h3FFF_8000_0000_0000_0000, 80'h4000_8000_0000_0000_0000,
                       80'h3FFE_8000_0000_0000_0000, "1.0 / 2.0 = 0.5");

        #100;

        $display("\n========================================");
        $display("Test Results:");
        $display("  Total: %0d", test_count);
        $display("  Pass:  %0d", pass_count);
        $display("  Fail:  %0d", fail_count);
        $display("========================================");

        if (fail_count == 0) begin
            $display("✓ ALL INTEGRATION TESTS PASSED");
        end else begin
            $display("✗ %0d TESTS FAILED", fail_count);
        end

        $finish;
    end

    initial begin
        #100000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule
