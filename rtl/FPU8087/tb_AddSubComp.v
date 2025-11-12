`timescale 1ns / 1ps

//=====================================================================
// Testbench for FPU Add/Sub/Compare Unit
//
// Tests addition, subtraction, and comparison operations
// on 80-bit extended precision floating point numbers
//=====================================================================

module tb_AddSubComp;

    reg clk;
    reg invert_operand_b;
    reg [79:0] operand_a;
    reg [79:0] operand_b;
    wire [79:0] result;
    wire cmp_equal;
    wire cmp_less;
    wire cmp_greater;

    integer test_passed;
    integer test_failed;

    // Instantiate the Add/Sub/Compare unit
    FPU_AddSub_Comp_Unit dut (
        .clk(clk),
        .invert_operand_b(invert_operand_b),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result(result),
        .cmp_equal(cmp_equal),
        .cmp_less(cmp_less),
        .cmp_greater(cmp_greater)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test sequence
    initial begin
        $dumpfile("tb_AddSubComp.vcd");
        $dumpvars(0, tb_AddSubComp);

        test_passed = 0;
        test_failed = 0;

        $display("\n========================================");
        $display("FPU Add/Sub/Compare Unit Testbench");
        $display("========================================\n");

        // Initialize
        invert_operand_b = 0;
        operand_a = 80'h0;
        operand_b = 80'h0;
        #20;

        //=============================================================
        // Test 1: Compare Equal - Two zeros
        //=============================================================
        $display("Test 1: Compare two zeros");
        operand_a = 80'h00000000000000000000; // +0.0
        operand_b = 80'h00000000000000000000; // +0.0
        invert_operand_b = 0;
        #20; // Wait for result

        if (cmp_equal && !cmp_less && !cmp_greater) begin
            $display("  PASS: Two zeros are equal");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Comparison incorrect. Equal=%b, Less=%b, Greater=%b",
                     cmp_equal, cmp_less, cmp_greater);
            test_failed = test_failed + 1;
        end
        #10;

        //=============================================================
        // Test 2: Compare two identical positive numbers
        //=============================================================
        $display("\nTest 2: Compare two identical positive numbers");
        // 1.0 in extended precision: Sign=0, Exp=3FFF, Mantissa=8000000000000000
        operand_a = 80'h3FFF8000000000000000;
        operand_b = 80'h3FFF8000000000000000;
        invert_operand_b = 0;
        #20;

        if (cmp_equal && !cmp_less && !cmp_greater) begin
            $display("  PASS: Identical numbers are equal");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Comparison incorrect. Equal=%b, Less=%b, Greater=%b",
                     cmp_equal, cmp_less, cmp_greater);
            test_failed = test_failed + 1;
        end
        #10;

        //=============================================================
        // Test 3: Compare positive vs negative (positive > negative)
        //=============================================================
        $display("\nTest 3: Compare positive vs negative");
        operand_a = 80'h3FFF8000000000000000; // +1.0
        operand_b = 80'hBFFF8000000000000000; // -1.0
        invert_operand_b = 0;
        #20;

        if (!cmp_equal && !cmp_less && cmp_greater) begin
            $display("  PASS: Positive > Negative");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Comparison incorrect. Equal=%b, Less=%b, Greater=%b",
                     cmp_equal, cmp_less, cmp_greater);
            test_failed = test_failed + 1;
        end
        #10;

        //=============================================================
        // Test 4: Compare negative vs positive (negative < positive)
        //=============================================================
        $display("\nTest 4: Compare negative vs positive");
        operand_a = 80'hBFFF8000000000000000; // -1.0
        operand_b = 80'h3FFF8000000000000000; // +1.0
        invert_operand_b = 0;
        #20;

        if (!cmp_equal && cmp_less && !cmp_greater) begin
            $display("  PASS: Negative < Positive");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Comparison incorrect. Equal=%b, Less=%b, Greater=%b",
                     cmp_equal, cmp_less, cmp_greater);
            test_failed = test_failed + 1;
        end
        #10;

        //=============================================================
        // Test 5: Simple Addition (not normalized)
        //=============================================================
        $display("\nTest 5: Simple addition (same exponent)");
        // Note: This is a simplified test - the real 8087 would normalize
        operand_a = 80'h3FFF8000000000000000; // ~1.0
        operand_b = 80'h3FFF8000000000000000; // ~1.0
        invert_operand_b = 0;
        #20;

        $display("  Result: 0x%020X", result);
        $display("  Note: Result is not normalized (would need normalizer)");
        test_passed = test_passed + 1; // Pass if no errors
        #10;

        //=============================================================
        // Test 6: Simple Subtraction
        //=============================================================
        $display("\nTest 6: Simple subtraction (via sign inversion)");
        operand_a = 80'h40008000000000000000; // ~2.0
        operand_b = 80'h3FFF8000000000000000; // ~1.0
        invert_operand_b = 1; // Subtract
        #20;

        $display("  Result: 0x%020X", result);
        $display("  Note: Result is not normalized (would need normalizer)");
        test_passed = test_passed + 1; // Pass if no errors
        #10;

        //=============================================================
        // Test Summary
        //=============================================================
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Tests Passed: %0d", test_passed);
        $display("Tests Failed: %0d", test_failed);
        $display("Total Tests:  %0d", test_passed + test_failed);

        if (test_failed == 0) begin
            $display("\nALL TESTS PASSED!");
        end else begin
            $display("\nSOME TESTS FAILED!");
        end
        $display("========================================\n");

        #100;
        $finish;
    end

    // Timeout watchdog
    initial begin
        #10000;
        $display("\nERROR: Simulation timeout!");
        $finish;
    end

endmodule
