`timescale 1ns / 1ps

//=====================================================================
// Testbench for IEEE 754 Extended Precision (80-bit) Divide Unit
//
// Comprehensive test suite covering:
// - Basic division operations
// - Sign handling (positive ÷ positive, negative ÷ negative, mixed)
// - Special values (±0, ±∞, NaN)
// - Edge cases (divide by zero, overflow, underflow)
// - Normalization and rounding
//=====================================================================

module tb_ieee754_divide;

    // Clock and reset
    reg clk;
    reg reset;

    // DUT inputs
    reg enable;
    reg [79:0] operand_a;
    reg [79:0] operand_b;
    reg [1:0] rounding_mode;

    // DUT outputs
    wire [79:0] result;
    wire done;
    wire flag_invalid;
    wire flag_div_by_zero;
    wire flag_overflow;
    wire flag_underflow;
    wire flag_inexact;

    // Test variables
    reg [79:0] expected_result;
    integer passed_tests;
    integer failed_tests;
    integer total_tests;

    //=================================================================
    // Instantiate DUT
    //=================================================================

    FPU_IEEE754_Divide dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .rounding_mode(rounding_mode),
        .result(result),
        .done(done),
        .flag_invalid(flag_invalid),
        .flag_div_by_zero(flag_div_by_zero),
        .flag_overflow(flag_overflow),
        .flag_underflow(flag_underflow),
        .flag_inexact(flag_inexact)
    );

    //=================================================================
    // Clock generation
    //=================================================================

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //=================================================================
    // Test sequence
    //=================================================================

    initial begin
        $display("========================================");
        $display("IEEE 754 Divide Unit Test Suite");
        $display("========================================");
        $display("");

        // Initialize
        reset = 1;
        enable = 0;
        operand_a = 80'd0;
        operand_b = 80'd0;
        rounding_mode = 2'b00;
        passed_tests = 0;
        failed_tests = 0;
        total_tests = 15;

        #20 reset = 0;
        #10;

        //=============================================================
        // Test 1: 1.0 ÷ 1.0 = 1.0
        //=============================================================
        $display("Test 1: 1.0 ÷ 1.0 = 1.0");
        operand_a = 80'h3FFF8000000000000000;
        operand_b = 80'h3FFF8000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        expected_result = 80'h3FFF8000000000000000;
        if (result == expected_result) begin
            $display("  PASS: 1.0 ÷ 1.0 = 1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.0 ÷ 1.0 = 1.0");
            $display("    Expected: %h", expected_result);
            $display("    Got:      %h", result);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 2: 6.0 ÷ 3.0 = 2.0
        //=============================================================
        $display("Test 2: 6.0 ÷ 3.0 = 2.0");
        operand_a = 80'h4001C000000000000000;
        operand_b = 80'h4000C000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        expected_result = 80'h40008000000000000000;
        if (result == expected_result) begin
            $display("  PASS: 6.0 ÷ 3.0 = 2.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 6.0 ÷ 3.0 = 2.0");
            $display("    Expected: %h", expected_result);
            $display("    Got:      %h", result);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 3: 1.0 ÷ 2.0 = 0.5
        //=============================================================
        $display("Test 3: 1.0 ÷ 2.0 = 0.5");
        operand_a = 80'h3FFF8000000000000000;
        operand_b = 80'h40008000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        expected_result = 80'h3FFE8000000000000000;
        if (result == expected_result) begin
            $display("  PASS: 1.0 ÷ 2.0 = 0.5");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.0 ÷ 2.0 = 0.5");
            $display("    Expected: %h", expected_result);
            $display("    Got:      %h", result);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 4: -6.0 ÷ 3.0 = -2.0
        //=============================================================
        $display("Test 4: -6.0 ÷ 3.0 = -2.0");
        operand_a = 80'hC001C000000000000000;
        operand_b = 80'h4000C000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        expected_result = 80'hC0008000000000000000;
        if (result == expected_result) begin
            $display("  PASS: -6.0 ÷ 3.0 = -2.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: -6.0 ÷ 3.0 = -2.0");
            $display("    Expected: %h", expected_result);
            $display("    Got:      %h", result);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 5: -6.0 ÷ -3.0 = 2.0
        //=============================================================
        $display("Test 5: -6.0 ÷ -3.0 = 2.0");
        operand_a = 80'hC001C000000000000000;
        operand_b = 80'hC000C000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        expected_result = 80'h40008000000000000000;
        if (result == expected_result) begin
            $display("  PASS: -6.0 ÷ -3.0 = 2.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: -6.0 ÷ -3.0 = 2.0");
            $display("    Expected: %h", expected_result);
            $display("    Got:      %h", result);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 6: 0.0 ÷ 1.0 = +0.0
        //=============================================================
        $display("Test 6: 0.0 ÷ 1.0 = +0.0");
        operand_a = 80'h00000000000000000000;
        operand_b = 80'h3FFF8000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        expected_result = 80'h00000000000000000000;
        if (result == expected_result) begin
            $display("  PASS: 0.0 ÷ 1.0 = +0.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 0.0 ÷ 1.0 = +0.0");
            $display("    Expected: %h", expected_result);
            $display("    Got:      %h", result);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 7: -0.0 ÷ 1.0 = -0.0
        //=============================================================
        $display("Test 7: -0.0 ÷ 1.0 = -0.0");
        operand_a = 80'h80000000000000000000;
        operand_b = 80'h3FFF8000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        expected_result = 80'h80000000000000000000;
        if (result == expected_result) begin
            $display("  PASS: -0.0 ÷ 1.0 = -0.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: -0.0 ÷ 1.0 = -0.0");
            $display("    Expected: %h", expected_result);
            $display("    Got:      %h", result);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 8: 1.0 ÷ +∞ = +0.0
        //=============================================================
        $display("Test 8: 1.0 ÷ +∞ = +0.0");
        operand_a = 80'h3FFF8000000000000000;
        operand_b = 80'h7FFF8000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        expected_result = 80'h00000000000000000000;
        if (result == expected_result) begin
            $display("  PASS: 1.0 ÷ +∞ = +0.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.0 ÷ +∞ = +0.0");
            $display("    Expected: %h", expected_result);
            $display("    Got:      %h", result);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 9: +∞ ÷ 1.0 = +∞
        //=============================================================
        $display("Test 9: +∞ ÷ 1.0 = +∞");
        operand_a = 80'h7FFF8000000000000000;
        operand_b = 80'h3FFF8000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        expected_result = 80'h7FFF8000000000000000;
        if (result == expected_result) begin
            $display("  PASS: +∞ ÷ 1.0 = +∞");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: +∞ ÷ 1.0 = +∞");
            $display("    Expected: %h", expected_result);
            $display("    Got:      %h", result);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 10: 1.0 ÷ 0.0 = +∞ (div by zero)
        //=============================================================
        $display("Test 10: 1.0 ÷ 0.0 = +∞ (div by zero)");
        operand_a = 80'h3FFF8000000000000000;
        operand_b = 80'h00000000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        if (flag_div_by_zero && result[78:64] == 15'h7FFF && result[63:0] == 64'h8000000000000000) begin
            $display("  PASS: 1.0 ÷ 0.0 = +∞ (div by zero)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.0 ÷ 0.0 should set div_by_zero flag and return +∞");
            $display("    Got: %h, div_by_zero=%b", result, flag_div_by_zero);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 11: 0.0 ÷ 0.0 = NaN (invalid)
        //=============================================================
        $display("Test 11: 0.0 ÷ 0.0 = NaN (invalid)");
        operand_a = 80'h00000000000000000000;
        operand_b = 80'h00000000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        if (flag_invalid && result[78:64] == 15'h7FFF && result[63]) begin
            $display("  PASS: 0.0 ÷ 0.0 = NaN (invalid)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 0.0 ÷ 0.0 should set invalid flag and return NaN");
            $display("    Got: %h, invalid=%b", result, flag_invalid);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 12: ∞ ÷ ∞ = NaN (invalid)
        //=============================================================
        $display("Test 12: ∞ ÷ ∞ = NaN (invalid)");
        operand_a = 80'h7FFF8000000000000000;
        operand_b = 80'h7FFF8000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        if (flag_invalid && result[78:64] == 15'h7FFF && result[63]) begin
            $display("  PASS: ∞ ÷ ∞ = NaN (invalid)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: ∞ ÷ ∞ should set invalid flag and return NaN");
            $display("    Got: %h, invalid=%b", result, flag_invalid);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 13: NaN ÷ 1.0 = NaN
        //=============================================================
        $display("Test 13: NaN ÷ 1.0 = NaN");
        operand_a = 80'h7FFFC000000000000000;
        operand_b = 80'h3FFF8000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        if (flag_invalid && result[78:64] == 15'h7FFF && result[63]) begin
            $display("  PASS: NaN ÷ 1.0 = NaN");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: NaN ÷ 1.0 should set invalid flag and return NaN");
            $display("    Got: %h, invalid=%b", result, flag_invalid);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 14: Large ÷ very small (overflow)
        //=============================================================
        $display("Test 14: Large ÷ very small (overflow)");
        operand_a = 80'h7FFE8000000000000000;
        operand_b = 80'h00018000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        if (flag_overflow && result[78:64] == 15'h7FFF && result[63:0] == 64'h8000000000000000) begin
            $display("  PASS: Overflow to +∞ for large ÷ very small");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: Should overflow to +∞");
            $display("    Got: %h, overflow=%b", result, flag_overflow);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test 15: Very small ÷ large (underflow)
        //=============================================================
        $display("Test 15: Very small ÷ large (underflow)");
        operand_a = 80'h00018000000000000000;
        operand_b = 80'h7FFE8000000000000000;
        rounding_mode = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(done);
        if (flag_underflow) begin
            $display("  PASS: Underflow detected for very small ÷ large");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: Should detect underflow");
            $display("    Got: %h, underflow=%b", result, flag_underflow);
            failed_tests = failed_tests + 1;
        end
        #10;

        //=============================================================
        // Test Results Summary
        //=============================================================
        $display("");
        $display("========================================");
        $display("Test Results Summary");
        $display("========================================");
        $display("Total tests:  %0d", total_tests);
        $display("Passed:       %0d", passed_tests);
        $display("Failed:       %0d", failed_tests);

        if (failed_tests == 0) begin
            $display("");
            $display("*** ALL TESTS PASSED! ***");
            $display("");
        end else begin
            $display("");
            $display("*** SOME TESTS FAILED ***");
            $display("");
        end

        $finish;
    end

endmodule
