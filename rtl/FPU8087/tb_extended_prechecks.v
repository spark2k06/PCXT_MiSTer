`timescale 1ns / 1ps

//=====================================================================
// Test for Extended Pre-Operation Checks
//
// Tests:
// - is_invalid_mul() - 0 × Inf detection
// - is_invalid_sqrt() - sqrt(negative) detection
//=====================================================================

module tb_extended_prechecks;

    //=================================================================
    // Test Control
    //=================================================================

    integer test_count;
    integer pass_count;
    integer fail_count;

    //=================================================================
    // FP80 Test Constants
    //=================================================================

    localparam [79:0] FP_ZERO_POS    = 80'h0000_0000_0000_0000_0000;
    localparam [79:0] FP_ZERO_NEG    = 80'h8000_0000_0000_0000_0000;
    localparam [79:0] FP_ONE_POS     = 80'h3FFF_8000_0000_0000_0000;
    localparam [79:0] FP_ONE_NEG     = 80'hBFFF_8000_0000_0000_0000;
    localparam [79:0] FP_TWO_POS     = 80'h4000_8000_0000_0000_0000;
    localparam [79:0] FP_TWO_NEG     = 80'hC000_8000_0000_0000_0000;
    localparam [79:0] FP_INF_POS     = 80'h7FFF_8000_0000_0000_0000;
    localparam [79:0] FP_INF_NEG     = 80'hFFFF_8000_0000_0000_0000;
    localparam [79:0] FP_QNAN_POS    = 80'h7FFF_C000_0000_0000_0000;  // Bit 62=1
    localparam [79:0] FP_QNAN_NEG    = 80'hFFFF_C000_0000_0000_0000;
    localparam [79:0] FP_SNAN_POS    = 80'h7FFF_A000_0000_0000_0000;  // Bit 62=0
    localparam [79:0] FP_SNAN_NEG    = 80'hFFFF_A000_0000_0000_0000;

    //=================================================================
    // Helper Functions (copied from FPU_Core.v for testing)
    //=================================================================

    function automatic is_zero;
        input [79:0] fp_value;
        begin
            is_zero = (fp_value[78:0] == 79'd0);
        end
    endfunction

    function automatic is_infinity;
        input [79:0] fp_value;
        begin
            is_infinity = (fp_value[78:64] == 15'h7FFF) && (fp_value[63:0] == 64'h8000_0000_0000_0000);
        end
    endfunction

    function automatic is_nan;
        input [79:0] fp_value;
        begin
            is_nan = (fp_value[78:64] == 15'h7FFF) && (fp_value[63:0] != 64'h8000_0000_0000_0000);
        end
    endfunction

    function automatic is_qnan;
        input [79:0] fp_value;
        begin
            // QNaN: exp=0x7FFF, mantissa != 0x8000_0000_0000_0000 (not infinity), bit 62 = 1
            is_qnan = (fp_value[78:64] == 15'h7FFF) &&
                      (fp_value[63:0] != 64'h8000_0000_0000_0000) &&
                      fp_value[62];  // Quiet bit = 1
        end
    endfunction

    function automatic is_snan;
        input [79:0] fp_value;
        begin
            // SNaN: exp=0x7FFF, mantissa != 0x8000_0000_0000_0000 (not infinity), bit 62 = 0, has payload
            is_snan = (fp_value[78:64] == 15'h7FFF) &&
                      (fp_value[63:0] != 64'h8000_0000_0000_0000) &&
                      !fp_value[62] &&  // Quiet bit = 0
                      (fp_value[61:0] != 62'd0);  // Has some payload bits
        end
    endfunction

    // Check for invalid multiplication: 0 × Inf or Inf × 0
    function automatic is_invalid_mul;
        input [79:0] operand_a;
        input [79:0] operand_b;
        begin
            is_invalid_mul = (is_zero(operand_a) && is_infinity(operand_b)) ||
                             (is_infinity(operand_a) && is_zero(operand_b));
        end
    endfunction

    // Check for invalid square root: sqrt(negative)
    function automatic is_invalid_sqrt;
        input [79:0] operand;
        begin
            // Invalid if operand is negative (sign bit = 1) and not zero and not NaN
            // Note: sqrt(-0) = -0 is valid, sqrt(-NaN) propagates NaN
            is_invalid_sqrt = operand[79] && !is_zero(operand) && !is_nan(operand);
        end
    endfunction

    //=================================================================
    // Test Tasks
    //=================================================================

    task check_result;
        input [255:0] test_name;
        input actual;
        input expected;
        begin
            test_count = test_count + 1;
            if (actual === expected) begin
                $display("  PASS: %s = %0d (expected %0d)", test_name, actual, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: %s = %0d (expected %0d)", test_name, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    //=================================================================
    // Test Stimulus
    //=================================================================

    initial begin
        $display("\nIcarus Verilog Simulation");
        $display("==================================================\n");
        $display("Extended Pre-Operation Checks Test Suite");
        $display("==================================================\n");

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        // Test is_invalid_mul()
        $display("Testing is_invalid_mul() - 0 \u00d7 Inf Detection");
        $display("--------------------------------------------------");

        $display("[Test 1] 0 \u00d7 +Inf");
        check_result("is_invalid_mul", is_invalid_mul(FP_ZERO_POS, FP_INF_POS), 1'b1);

        $display("[Test 2] +Inf \u00d7 0");
        check_result("is_invalid_mul", is_invalid_mul(FP_INF_POS, FP_ZERO_POS), 1'b1);

        $display("[Test 3] -0 \u00d7 -Inf");
        check_result("is_invalid_mul", is_invalid_mul(FP_ZERO_NEG, FP_INF_NEG), 1'b1);

        $display("[Test 4] -Inf \u00d7 -0");
        check_result("is_invalid_mul", is_invalid_mul(FP_INF_NEG, FP_ZERO_NEG), 1'b1);

        $display("[Test 5] 0 \u00d7 1 (valid)");
        check_result("is_invalid_mul", is_invalid_mul(FP_ZERO_POS, FP_ONE_POS), 1'b0);

        $display("[Test 6] 1 \u00d7 0 (valid)");
        check_result("is_invalid_mul", is_invalid_mul(FP_ONE_POS, FP_ZERO_POS), 1'b0);

        $display("[Test 7] +Inf \u00d7 1 (valid)");
        check_result("is_invalid_mul", is_invalid_mul(FP_INF_POS, FP_ONE_POS), 1'b0);

        $display("[Test 8] 2 \u00d7 -Inf (valid)");
        check_result("is_invalid_mul", is_invalid_mul(FP_TWO_POS, FP_INF_NEG), 1'b0);

        $display("[Test 9] 1 \u00d7 2 (valid)");
        check_result("is_invalid_mul", is_invalid_mul(FP_ONE_POS, FP_TWO_POS), 1'b0);

        $display("");
        $display("Testing is_invalid_sqrt() - sqrt(negative) Detection");
        $display("--------------------------------------------------");

        $display("[Test 10] sqrt(-1)");
        check_result("is_invalid_sqrt", is_invalid_sqrt(FP_ONE_NEG), 1'b1);

        $display("[Test 11] sqrt(-2)");
        check_result("is_invalid_sqrt", is_invalid_sqrt(FP_TWO_NEG), 1'b1);

        $display("[Test 12] sqrt(-Inf)");
        check_result("is_invalid_sqrt", is_invalid_sqrt(FP_INF_NEG), 1'b1);

        $display("[Test 13] sqrt(-0) - valid");
        check_result("is_invalid_sqrt", is_invalid_sqrt(FP_ZERO_NEG), 1'b0);

        $display("[Test 14] sqrt(+0) - valid");
        check_result("is_invalid_sqrt", is_invalid_sqrt(FP_ZERO_POS), 1'b0);

        $display("[Test 15] sqrt(+1) - valid");
        check_result("is_invalid_sqrt", is_invalid_sqrt(FP_ONE_POS), 1'b0);

        $display("[Test 16] sqrt(+2) - valid");
        check_result("is_invalid_sqrt", is_invalid_sqrt(FP_TWO_POS), 1'b0);

        $display("[Test 17] sqrt(+Inf) - valid");
        check_result("is_invalid_sqrt", is_invalid_sqrt(FP_INF_POS), 1'b0);

        $display("[Test 18] sqrt(+QNaN) - valid (NaN propagation)");
        check_result("is_invalid_sqrt", is_invalid_sqrt(FP_QNAN_POS), 1'b0);

        $display("[Test 19] sqrt(-QNaN) - valid (NaN propagation)");
        check_result("is_invalid_sqrt", is_invalid_sqrt(FP_QNAN_NEG), 1'b0);

        // Summary
        $display("");
        $display("==================================================");
        $display("Test Summary");
        $display("==================================================");
        $display("Total tests:  %0d", test_count);
        $display("Passed:       %0d", pass_count);
        $display("Failed:       %0d", fail_count);
        $display("");

        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** %0d TEST(S) FAILED ***", fail_count);
        end
        $display("");

        $finish;
    end

endmodule
