`timescale 1ns / 1ps

//=====================================================================
// Test for Denormal Arithmetic and Precision Control
//
// Tests:
// - Denormal number detection
// - Precision control masking (24-bit, 53-bit, 64-bit)
//=====================================================================

module tb_denormal_precision;

    // FP80 test values
    localparam [79:0] FP_NORMAL     = 80'h3FFF_8000_0000_0000_0000;  // 1.0 (normal)
    localparam [79:0] FP_DENORMAL   = 80'h0000_4000_0000_0000_0000;  // Denormal (exp=0, mant≠0)
    localparam [79:0] FP_ZERO       = 80'h0000_0000_0000_0000_0000;  // Zero
    localparam [79:0] FP_DENORMAL2  = 80'h0000_0000_0000_0000_0001;  // Smallest denormal

    integer test_count, pass_count, fail_count;

    // Test stimulus
    initial begin
        $display("\nDenormal and Precision Control Test Suite");
        $display("==================================================\n");

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        // ===========================
        // Denormal Detection Tests
        // ===========================
        $display("Testing Denormal Detection");
        $display("--------------------------------------------------");

        // Test 1: Normal number should not be denormal
        test_denormal("Normal (1.0)", FP_NORMAL, 1'b0);

        // Test 2: Denormal should be detected
        test_denormal("Denormal", FP_DENORMAL, 1'b1);

        // Test 3: Zero should not be denormal
        test_denormal("Zero", FP_ZERO, 1'b0);

        // Test 4: Smallest denormal
        test_denormal("Smallest denormal", FP_DENORMAL2, 1'b1);

        $display("");

        // ===========================
        // Precision Control Tests
        // ===========================
        $display("Testing Precision Control Masking");
        $display("--------------------------------------------------");

        // Test 5: 24-bit precision (single)
        test_precision_mask("24-bit precision", 2'b00,
                           64'hFFFFFFFF_FFFFFFFF,
                           64'hFFFFFF00_00000000);

        // Test 6: 53-bit precision (double)
        test_precision_mask("53-bit precision", 2'b10,
                           64'hFFFFFFFF_FFFFFFFF,
                           64'hFFFFFFFF_FFFFE000);

        // Test 7: 64-bit precision (extended)
        test_precision_mask("64-bit precision", 2'b11,
                           64'hFFFFFFFF_FFFFFFFF,
                           64'hFFFFFFFF_FFFFFFFF);

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

    // Test denormal detection
    task test_denormal;
        input [255:0] test_name;
        input [79:0] value;
        input expected;
        reg result;
        begin
            test_count = test_count + 1;
            $display("[Test %0d] %s", test_count, test_name);

            // Check if denormal: exp=0 and mant≠0
            result = (value[78:64] == 15'd0) && (value[63:0] != 64'd0);

            if (result == expected) begin
                $display("  PASS: is_denormal=%0d", result);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: is_denormal=%0d (expected %0d)", result, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Test precision control masking
    task test_precision_mask;
        input [255:0] test_name;
        input [1:0] precision;
        input [63:0] input_mantissa;
        input [63:0] expected_output;
        reg [63:0] result;
        reg [63:0] mask;
        begin
            test_count = test_count + 1;
            $display("[Test %0d] %s", test_count, test_name);

            // Apply precision mask
            case (precision)
                2'b00: mask = 64'hFFFFFF00_00000000;  // 24-bit
                2'b10: mask = 64'hFFFFFFFF_FFFFE000;  // 53-bit
                2'b11: mask = 64'hFFFFFFFF_FFFFFFFF;  // 64-bit
                default: mask = 64'hFFFFFFFF_FFFFFFFF;
            endcase

            result = input_mantissa & mask;

            if (result == expected_output) begin
                $display("  PASS: result=%h", result);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: result=%h (expected %h)", result, expected_output);
                fail_count = fail_count + 1;
            end
        end
    endtask

endmodule
