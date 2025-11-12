`timescale 1ns / 1ps

//=====================================================================
// Testbench for IEEE 754 Extended Precision Add/Subtract Unit
//=====================================================================

module tb_ieee754_addsub;

    reg clk;
    reg reset;
    reg enable;
    reg [79:0] operand_a;
    reg [79:0] operand_b;
    reg subtract;
    reg [1:0] rounding_mode;

    wire [79:0] result;
    wire done;
    wire cmp_equal, cmp_less, cmp_greater;
    wire flag_invalid, flag_overflow, flag_underflow, flag_inexact;

    integer test_num;
    integer passed_tests;
    integer failed_tests;
    reg [79:0] expected_result;

    // Instantiate the Unit Under Test (UUT)
    FPU_IEEE754_AddSub uut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .subtract(subtract),
        .rounding_mode(rounding_mode),
        .result(result),
        .done(done),
        .cmp_equal(cmp_equal),
        .cmp_less(cmp_less),
        .cmp_greater(cmp_greater),
        .flag_invalid(flag_invalid),
        .flag_overflow(flag_overflow),
        .flag_underflow(flag_underflow),
        .flag_inexact(flag_inexact)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz clock
    end

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("tb_ieee754_addsub.vcd");
        $dumpvars(0, tb_ieee754_addsub);
    end

    // Test stimulus
    initial begin
        $display("========================================");
        $display("IEEE 754 Add/Sub Unit Test Suite");
        $display("========================================");
        $display("");

        // Initialize
        reset = 1;
        enable = 0;
        operand_a = 80'd0;
        operand_b = 80'd0;
        subtract = 0;
        rounding_mode = 2'b00;  // Round to nearest
        passed_tests = 0;
        failed_tests = 0;

        #20;
        reset = 0;
        #20;

        // Test 1: 1.0 + 1.0 = 2.0
        test_num = 1;
        $display("[Test %0d] 1.0 + 1.0 = 2.0", test_num);
        operand_a = 80'h3FFF8000000000000000;
        operand_b = 80'h3FFF8000000000000000;
        subtract = 1'b0;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        expected_result = 80'h40008000000000000000;
        if (result == expected_result) begin
            $display("  PASS: 1.0 + 1.0 = 2.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.0 + 1.0");
            $display("    Got:      %h", result);
            $display("    Expected: %h", expected_result);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 2: 2.0 - 1.0 = 1.0
        test_num = 2;
        $display("[Test %0d] 2.0 - 1.0 = 1.0", test_num);
        operand_a = 80'h40008000000000000000;
        operand_b = 80'h3FFF8000000000000000;
        subtract = 1'b1;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        expected_result = 80'h3FFF8000000000000000;
        if (result == expected_result) begin
            $display("  PASS: 2.0 - 1.0 = 1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 2.0 - 1.0");
            $display("    Got:      %h", result);
            $display("    Expected: %h", expected_result);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 3: 1.0 - 1.0 = 0.0
        test_num = 3;
        $display("[Test %0d] 1.0 - 1.0 = 0.0", test_num);
        operand_a = 80'h3FFF8000000000000000;
        operand_b = 80'h3FFF8000000000000000;
        subtract = 1'b1;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        expected_result = 80'h00000000000000000000;
        if (result == expected_result) begin
            $display("  PASS: 1.0 - 1.0 = 0.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.0 - 1.0");
            $display("    Got:      %h", result);
            $display("    Expected: %h", expected_result);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 4: 1.0 + 0.0 = 1.0
        test_num = 4;
        $display("[Test %0d] 1.0 + 0.0 = 1.0", test_num);
        operand_a = 80'h3FFF8000000000000000;
        operand_b = 80'h00000000000000000000;
        subtract = 1'b0;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        expected_result = 80'h3FFF8000000000000000;
        if (result == expected_result) begin
            $display("  PASS: 1.0 + 0.0 = 1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.0 + 0.0");
            $display("    Got:      %h", result);
            $display("    Expected: %h", expected_result);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 5: (-1.0) + (-1.0) = -2.0
        test_num = 5;
        $display("[Test %0d] (-1.0) + (-1.0) = -2.0", test_num);
        operand_a = 80'hBFFF8000000000000000;
        operand_b = 80'hBFFF8000000000000000;
        subtract = 1'b0;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        expected_result = 80'hC0008000000000000000;
        if (result == expected_result) begin
            $display("  PASS: (-1.0) + (-1.0) = -2.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: (-1.0) + (-1.0)");
            $display("    Got:      %h", result);
            $display("    Expected: %h", expected_result);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 6: 1.0 + (-1.0) = 0.0
        test_num = 6;
        $display("[Test %0d] 1.0 + (-1.0) = 0.0", test_num);
        operand_a = 80'h3FFF8000000000000000;
        operand_b = 80'hBFFF8000000000000000;
        subtract = 1'b0;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        expected_result = 80'h00000000000000000000;
        if (result == expected_result) begin
            $display("  PASS: 1.0 + (-1.0) = 0.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.0 + (-1.0)");
            $display("    Got:      %h", result);
            $display("    Expected: %h", expected_result);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 7: +∞ + 1.0 = +∞
        test_num = 7;
        $display("[Test %0d] +∞ + 1.0 = +∞", test_num);
        operand_a = 80'h7FFF8000000000000000;
        operand_b = 80'h3FFF8000000000000000;
        subtract = 1'b0;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        expected_result = 80'h7FFF8000000000000000;
        if (result == expected_result) begin
            $display("  PASS: +∞ + 1.0 = +∞");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: +∞ + 1.0");
            $display("    Got:      %h", result);
            $display("    Expected: %h", expected_result);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 8: +∞ + +∞ = +∞
        test_num = 8;
        $display("[Test %0d] +∞ + +∞ = +∞", test_num);
        operand_a = 80'h7FFF8000000000000000;
        operand_b = 80'h7FFF8000000000000000;
        subtract = 1'b0;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        expected_result = 80'h7FFF8000000000000000;
        if (result == expected_result) begin
            $display("  PASS: +∞ + +∞ = +∞");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: +∞ + +∞");
            $display("    Got:      %h", result);
            $display("    Expected: %h", expected_result);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 9: +∞ - +∞ = NaN (invalid)
        test_num = 9;
        $display("[Test %0d] +∞ - +∞ = NaN (invalid)", test_num);
        operand_a = 80'h7FFF8000000000000000;
        operand_b = 80'h7FFF8000000000000000;
        subtract = 1'b1;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        expected_result = 80'h7FFFC000000000000000;
        if (result[78:64] == 15'h7FFF && flag_invalid) begin
            $display("  PASS: +∞ - +∞ = NaN (invalid flag set)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: +∞ - +∞");
            $display("    Got:      %h, invalid=%b", result, flag_invalid);
            $display("    Expected: NaN with invalid flag");
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 10: 0.0 + 0.0 = 0.0
        test_num = 10;
        $display("[Test %0d] 0.0 + 0.0 = 0.0", test_num);
        operand_a = 80'h00000000000000000000;
        operand_b = 80'h00000000000000000000;
        subtract = 1'b0;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        expected_result = 80'h00000000000000000000;
        if (result == expected_result) begin
            $display("  PASS: 0.0 + 0.0 = 0.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 0.0 + 0.0");
            $display("    Got:      %h", result);
            $display("    Expected: %h", expected_result);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 11: 1.0 - 0.5 = 0.5
        test_num = 11;
        $display("[Test %0d] 1.0 - 0.5 = 0.5", test_num);
        operand_a = 80'h3FFF8000000000000000;
        operand_b = 80'h3FFE8000000000000000;
        subtract = 1'b1;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        expected_result = 80'h3FFE8000000000000000;
        if (result == expected_result) begin
            $display("  PASS: 1.0 - 0.5 = 0.5");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.0 - 0.5");
            $display("    Got:      %h", result);
            $display("    Expected: %h", expected_result);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 12: Comparison - 1.0 == 1.0
        test_num = 12;
        $display("[Test %0d] Comparison: 1.0 == 1.0", test_num);
        operand_a = 80'h3FFF8000000000000000;
        operand_b = 80'h3FFF8000000000000000;
        subtract = 1'b0;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        if (cmp_equal && !cmp_less && !cmp_greater) begin
            $display("  PASS: 1.0 == 1.0 (comparison)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: Comparison 1.0 == 1.0");
            $display("    equal=%b, less=%b, greater=%b", cmp_equal, cmp_less, cmp_greater);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 13: Comparison - 1.0 < 2.0
        test_num = 13;
        $display("[Test %0d] Comparison: 1.0 < 2.0", test_num);
        operand_a = 80'h3FFF8000000000000000;
        operand_b = 80'h40008000000000000000;
        subtract = 1'b0;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        if (!cmp_equal && cmp_less && !cmp_greater) begin
            $display("  PASS: 1.0 < 2.0 (comparison)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: Comparison 1.0 < 2.0");
            $display("    equal=%b, less=%b, greater=%b", cmp_equal, cmp_less, cmp_greater);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 14: Comparison - 2.0 > 1.0
        test_num = 14;
        $display("[Test %0d] Comparison: 2.0 > 1.0", test_num);
        operand_a = 80'h40008000000000000000;
        operand_b = 80'h3FFF8000000000000000;
        subtract = 1'b0;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        if (!cmp_equal && !cmp_less && cmp_greater) begin
            $display("  PASS: 2.0 > 1.0 (comparison)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: Comparison 2.0 > 1.0");
            $display("    equal=%b, less=%b, greater=%b", cmp_equal, cmp_less, cmp_greater);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Test 15: Comparison - 0.0 == -0.0
        test_num = 15;
        $display("[Test %0d] Comparison: 0.0 == -0.0", test_num);
        operand_a = 80'h00000000000000000000;
        operand_b = 80'h80000000000000000000;
        subtract = 1'b0;
        enable = 1;
        #10 enable = 0;
        wait(done);
        #10;
        if (cmp_equal && !cmp_less && !cmp_greater) begin
            $display("  PASS: 0.0 == -0.0 (comparison)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: Comparison 0.0 == -0.0");
            $display("    equal=%b, less=%b, greater=%b", cmp_equal, cmp_less, cmp_greater);
            failed_tests = failed_tests + 1;
        end
        #20;

        // Summary
        $display("");
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests:  %0d", passed_tests + failed_tests);
        $display("Passed:       %0d", passed_tests);
        $display("Failed:       %0d", failed_tests);
        $display("");

        if (failed_tests == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** %0d TEST(S) FAILED ***", failed_tests);
        end

        $display("");
        $finish;
    end

endmodule
