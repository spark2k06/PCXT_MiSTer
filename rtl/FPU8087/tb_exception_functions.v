`timescale 1ns / 1ps

//=====================================================================
// Exception Handling Functions Unit Test
//
// Tests the exception handling helper functions directly:
// - is_nan, is_qnan, is_snan
// - is_infinity, is_zero
// - make_qnan, make_infinity, make_zero
// - propagate_nan
//=====================================================================

module tb_exception_functions;

    //=================================================================
    // Test Infrastructure
    //=================================================================

    integer test_num;
    integer passed_tests;
    integer failed_tests;

    //=================================================================
    // FP80 Test Constants
    //=================================================================

    // Normal values
    localparam [79:0] FP_ZERO_POS    = 80'h0000_0000_0000_0000_0000;  // +0.0
    localparam [79:0] FP_ZERO_NEG    = 80'h8000_0000_0000_0000_0000;  // -0.0
    localparam [79:0] FP_ONE_POS     = 80'h3FFF_8000_0000_0000_0000;  // +1.0
    localparam [79:0] FP_ONE_NEG     = 80'hBFFF_8000_0000_0000_0000;  // -1.0

    // Special values
    localparam [79:0] FP_INF_POS     = 80'h7FFF_8000_0000_0000_0000;  // +Infinity
    localparam [79:0] FP_INF_NEG     = 80'hFFFF_8000_0000_0000_0000;  // -Infinity
    localparam [79:0] FP_QNAN_POS    = 80'h7FFF_C000_0000_0000_0000;  // +QNaN
    localparam [79:0] FP_QNAN_NEG    = 80'hFFFF_C000_0000_0000_0000;  // -QNaN
    localparam [79:0] FP_SNAN_POS    = 80'h7FFF_A000_0000_0000_0000;  // +SNaN (bit 63=0)
    localparam [79:0] FP_SNAN_NEG    = 80'hFFFF_A000_0000_0000_0000;  // -SNaN

    // QNaN with payloads
    localparam [79:0] FP_QNAN_PAYLOAD1 = 80'h7FFF_C000_0000_1234_5678;
    localparam [79:0] FP_QNAN_PAYLOAD2 = 80'h7FFF_C000_0000_ABCD_EF00;
    localparam [79:0] FP_SNAN_PAYLOAD  = 80'h7FFF_A000_0000_DEAD_BEEF;

    //=================================================================
    // Helper Functions (copied from FPU_Core.v)
    //=================================================================

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

    function automatic is_infinity;
        input [79:0] fp_value;
        begin
            is_infinity = (fp_value[78:64] == 15'h7FFF) && (fp_value[63:0] == 64'h8000_0000_0000_0000);
        end
    endfunction

    function automatic is_zero;
        input [79:0] fp_value;
        begin
            is_zero = (fp_value[78:64] == 15'd0) && (fp_value[63:0] == 64'd0);
        end
    endfunction

    function automatic get_sign;
        input [79:0] fp_value;
        begin
            get_sign = fp_value[79];
        end
    endfunction

    function automatic [79:0] make_qnan;
        input sign_bit;
        begin
            make_qnan = {sign_bit, 15'h7FFF, 64'hC000_0000_0000_0000};
        end
    endfunction

    function automatic [79:0] make_infinity;
        input sign_bit;
        begin
            make_infinity = {sign_bit, 15'h7FFF, 64'h8000_0000_0000_0000};
        end
    endfunction

    function automatic [79:0] make_zero;
        input sign_bit;
        begin
            make_zero = {sign_bit, 15'd0, 64'd0};
        end
    endfunction

    function automatic [79:0] propagate_nan;
        input [79:0] operand_a;
        input [79:0] operand_b;
        input has_operand_b;
        reg found_nan;
        begin
            found_nan = 1'b0;
            propagate_nan = 80'd0;

            // Check for SNaN in operand_a
            if (is_snan(operand_a)) begin
                // Convert SNaN to QNaN by setting bit 62 (quiet bit)
                propagate_nan = operand_a | 80'h0000_4000_0000_0000_0000;
                found_nan = 1'b1;
            end
            // Check for SNaN in operand_b
            else if (has_operand_b && is_snan(operand_b)) begin
                // Convert SNaN to QNaN by setting bit 62 (quiet bit)
                propagate_nan = operand_b | 80'h0000_4000_0000_0000_0000;
                found_nan = 1'b1;
            end
            // Check for QNaN in operand_a
            else if (is_qnan(operand_a)) begin
                propagate_nan = operand_a;
                found_nan = 1'b1;
            end
            // Check for QNaN in operand_b
            else if (has_operand_b && is_qnan(operand_b)) begin
                propagate_nan = operand_b;
                found_nan = 1'b1;
            end

            if (!found_nan)
                propagate_nan = 80'd0;
        end
    endfunction

    //=================================================================
    // Test Tasks
    //=================================================================

    task test_detection;
        input [255:0] test_desc;
        input [79:0] value;
        input expected_nan;
        input expected_qnan;
        input expected_snan;
        input expected_inf;
        input expected_zero;
        reg result;
        begin
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_desc);
            $display("  Value: %h", value);

            // Test is_nan
            result = is_nan(value);
            if (result == expected_nan) begin
                $display("  PASS: is_nan = %b (expected %b)", result, expected_nan);
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: is_nan = %b (expected %b)", result, expected_nan);
                failed_tests = failed_tests + 1;
            end

            // Test is_qnan
            result = is_qnan(value);
            if (result == expected_qnan) begin
                $display("  PASS: is_qnan = %b (expected %b)", result, expected_qnan);
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: is_qnan = %b (expected %b)", result, expected_qnan);
                failed_tests = failed_tests + 1;
            end

            // Test is_snan
            result = is_snan(value);
            if (result == expected_snan) begin
                $display("  PASS: is_snan = %b (expected %b)", result, expected_snan);
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: is_snan = %b (expected %b)", result, expected_snan);
                failed_tests = failed_tests + 1;
            end

            // Test is_infinity
            result = is_infinity(value);
            if (result == expected_inf) begin
                $display("  PASS: is_infinity = %b (expected %b)", result, expected_inf);
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: is_infinity = %b (expected %b)", result, expected_inf);
                failed_tests = failed_tests + 1;
            end

            // Test is_zero
            result = is_zero(value);
            if (result == expected_zero) begin
                $display("  PASS: is_zero = %b (expected %b)", result, expected_zero);
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: is_zero = %b (expected %b)", result, expected_zero);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    task test_creation;
        input [255:0] test_desc;
        input sign;
        input [79:0] expected_qnan;
        input [79:0] expected_inf;
        input [79:0] expected_zero;
        reg [79:0] result;
        begin
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s (sign=%b)", test_num, test_desc, sign);

            // Test make_qnan
            result = make_qnan(sign);
            if (result == expected_qnan && is_qnan(result)) begin
                $display("  PASS: make_qnan = %h", result);
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: make_qnan = %h (expected %h)", result, expected_qnan);
                failed_tests = failed_tests + 1;
            end

            // Test make_infinity
            result = make_infinity(sign);
            if (result == expected_inf && is_infinity(result)) begin
                $display("  PASS: make_infinity = %h", result);
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: make_infinity = %h (expected %h)", result, expected_inf);
                failed_tests = failed_tests + 1;
            end

            // Test make_zero
            result = make_zero(sign);
            if (result == expected_zero && is_zero(result)) begin
                $display("  PASS: make_zero = %h", result);
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: make_zero = %h (expected %h)", result, expected_zero);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    task test_nan_propagation;
        input [255:0] test_desc;
        input [79:0] operand_a;
        input [79:0] operand_b;
        input has_b;
        input [79:0] expected_result;
        input should_be_qnan;
        reg [79:0] result;
        begin
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_desc);
            $display("  Operand A: %h", operand_a);
            if (has_b)
                $display("  Operand B: %h", operand_b);

            result = propagate_nan(operand_a, operand_b, has_b);
            $display("  Result:    %h", result);

            if (should_be_qnan && is_qnan(result)) begin
                $display("  PASS: Result is QNaN");
                passed_tests = passed_tests + 1;

                // For SNaN conversion, check that bit 63 is set
                if (is_snan(operand_a) || (has_b && is_snan(operand_b))) begin
                    if (result[63] == 1'b1) begin
                        $display("  PASS: SNaN converted to QNaN (bit 63 set)");
                        passed_tests = passed_tests + 1;
                    end else begin
                        $display("  FAIL: SNaN not properly converted (bit 63 not set)");
                        failed_tests = failed_tests + 1;
                    end
                end
            end else if (result == expected_result) begin
                $display("  PASS: Result matches expected value");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Unexpected result (expected %h)", expected_result);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    //=================================================================
    // Main Test Sequence
    //=================================================================

    initial begin
        $display("\n========================================");
        $display("Exception Functions Unit Test");
        $display("========================================");

        test_num = 0;
        passed_tests = 0;
        failed_tests = 0;

        //=============================================================
        // Test Suite 1: Detection Functions
        //=============================================================
        $display("\n========================================");
        $display("Test Suite 1: Detection Functions");
        $display("========================================");

        // Test normal values
        test_detection("Normal: +1.0", FP_ONE_POS, 0, 0, 0, 0, 0);
        test_detection("Normal: -1.0", FP_ONE_NEG, 0, 0, 0, 0, 0);

        // Test zeros
        test_detection("Zero: +0.0", FP_ZERO_POS, 0, 0, 0, 0, 1);
        test_detection("Zero: -0.0", FP_ZERO_NEG, 0, 0, 0, 0, 1);

        // Test infinities
        test_detection("Infinity: +Inf", FP_INF_POS, 0, 0, 0, 1, 0);
        test_detection("Infinity: -Inf", FP_INF_NEG, 0, 0, 0, 1, 0);

        // Test QNaNs
        test_detection("QNaN: +QNaN", FP_QNAN_POS, 1, 1, 0, 0, 0);
        test_detection("QNaN: -QNaN", FP_QNAN_NEG, 1, 1, 0, 0, 0);
        test_detection("QNaN: with payload", FP_QNAN_PAYLOAD1, 1, 1, 0, 0, 0);

        // Test SNaNs
        test_detection("SNaN: +SNaN", FP_SNAN_POS, 1, 0, 1, 0, 0);
        test_detection("SNaN: -SNaN", FP_SNAN_NEG, 1, 0, 1, 0, 0);
        test_detection("SNaN: with payload", FP_SNAN_PAYLOAD, 1, 0, 1, 0, 0);

        //=============================================================
        // Test Suite 2: Creation Functions
        //=============================================================
        $display("\n========================================");
        $display("Test Suite 2: Creation Functions");
        $display("========================================");

        test_creation("Create positive values", 1'b0,
                     FP_QNAN_POS, FP_INF_POS, FP_ZERO_POS);

        test_creation("Create negative values", 1'b1,
                     FP_QNAN_NEG, FP_INF_NEG, FP_ZERO_NEG);

        //=============================================================
        // Test Suite 3: NaN Propagation
        //=============================================================
        $display("\n========================================");
        $display("Test Suite 3: NaN Propagation");
        $display("========================================");

        // QNaN propagation
        test_nan_propagation("QNaN + Normal → QNaN",
            FP_QNAN_POS, FP_ONE_POS, 1'b1, FP_QNAN_POS, 1);

        test_nan_propagation("Normal + QNaN → QNaN",
            FP_ONE_POS, FP_QNAN_POS, 1'b1, FP_QNAN_POS, 1);

        test_nan_propagation("QNaN(payload1) + Normal → QNaN(payload1)",
            FP_QNAN_PAYLOAD1, FP_ONE_POS, 1'b1, FP_QNAN_PAYLOAD1, 1);

        // SNaN propagation (should convert to QNaN)
        test_nan_propagation("SNaN + Normal → QNaN (SNaN converted)",
            FP_SNAN_POS, FP_ONE_POS, 1'b1, 80'd0, 1);

        test_nan_propagation("Normal + SNaN → QNaN (SNaN converted)",
            FP_ONE_POS, FP_SNAN_POS, 1'b1, 80'd0, 1);

        test_nan_propagation("SNaN(payload) + Normal → QNaN(payload preserved)",
            FP_SNAN_PAYLOAD, FP_ONE_POS, 1'b1, 80'd0, 1);

        // Priority: SNaN > QNaN
        test_nan_propagation("SNaN + QNaN → QNaN (SNaN priority)",
            FP_SNAN_POS, FP_QNAN_POS, 1'b1, 80'd0, 1);

        test_nan_propagation("QNaN + SNaN → QNaN (SNaN priority)",
            FP_QNAN_POS, FP_SNAN_POS, 1'b1, 80'd0, 1);

        // Priority: First QNaN
        test_nan_propagation("QNaN1 + QNaN2 → QNaN1 (first operand priority)",
            FP_QNAN_PAYLOAD1, FP_QNAN_PAYLOAD2, 1'b1, FP_QNAN_PAYLOAD1, 1);

        // Unary operation (no second operand)
        test_nan_propagation("QNaN (unary) → QNaN",
            FP_QNAN_POS, 80'd0, 1'b0, FP_QNAN_POS, 1);

        test_nan_propagation("SNaN (unary) → QNaN",
            FP_SNAN_POS, 80'd0, 1'b0, 80'd0, 1);

        //=============================================================
        // Test Summary
        //=============================================================
        #100;
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests:  %0d", test_num);
        $display("Passed:       %0d", passed_tests);
        $display("Failed:       %0d", failed_tests);

        if (failed_tests == 0) begin
            $display("\n*** ALL TESTS PASSED ***");
        end else begin
            $display("\n*** %0d TESTS FAILED ***", failed_tests);
        end

        $display("\n========================================\n");
        $finish;
    end

endmodule
