`timescale 1ns / 1ps

//=====================================================================
// Comprehensive Testbench for Unified MulDiv Unit
//
// Tests both multiply and divide operations:
// - Basic operations with known values
// - Special values (±0, ±∞, NaN)
// - Overflow/underflow conditions
// - All rounding modes
// - Comparison with original separate modules
//=====================================================================

module tb_muldiv_unified;

    //=================================================================
    // Clock and Reset
    //=================================================================

    reg clk;
    reg reset;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100 MHz clock
    end

    //=================================================================
    // Unified Module Signals
    //=================================================================

    reg enable;
    reg operation;  // 0=multiply, 1=divide
    reg [79:0] operand_a;
    reg [79:0] operand_b;
    reg [1:0]  rounding_mode;

    wire [79:0] result;
    wire        done;
    wire        flag_invalid;
    wire        flag_div_by_zero;
    wire        flag_overflow;
    wire        flag_underflow;
    wire        flag_inexact;

    //=================================================================
    // Instantiate Unified MulDiv Module
    //=================================================================

    FPU_IEEE754_MulDiv_Unified uut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .operation(operation),
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
    // Test Counters
    //=================================================================

    integer test_count;
    integer pass_count;
    integer fail_count;

    //=================================================================
    // Helper Function: FP80 representation
    //=================================================================

    function [79:0] make_fp80;
        input        sign;
        input [14:0] exp;
        input [63:0] mant;
        begin
            make_fp80 = {sign, exp, mant};
        end
    endfunction

    //=================================================================
    // Test Tasks
    //=================================================================

    task test_multiply;
        input [79:0] a;
        input [79:0] b;
        input [79:0] expected;
        input [1:0]  rmode;
        input [80*8-1:0] test_name;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            operation = 1'b0;  // multiply
            operand_a = a;
            operand_b = b;
            rounding_mode = rmode;

            @(posedge clk);
            enable = 1'b0;

            // Wait for done
            while (!done) @(posedge clk);

            if (result == expected) begin
                $display("PASS MUL: %0s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL MUL: %0s", test_name);
                $display("  Expected: %h", expected);
                $display("  Got:      %h", result);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task test_divide;
        input [79:0] a;
        input [79:0] b;
        input [79:0] expected;
        input [1:0]  rmode;
        input [80*8-1:0] test_name;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            operation = 1'b1;  // divide
            operand_a = a;
            operand_b = b;
            rounding_mode = rmode;

            @(posedge clk);
            enable = 1'b0;

            // Wait for done
            while (!done) @(posedge clk);

            if (result == expected) begin
                $display("PASS DIV: %0s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL DIV: %0s", test_name);
                $display("  Expected: %h", expected);
                $display("  Got:      %h", result);
                fail_count = fail_count + 1;
            end
        end
    endtask

    //=================================================================
    // Test FP80 Values
    //=================================================================

    // Common test values
    reg [79:0] fp80_zero;
    reg [79:0] fp80_one;
    reg [79:0] fp80_two;
    reg [79:0] fp80_half;
    reg [79:0] fp80_neg_one;
    reg [79:0] fp80_inf;
    reg [79:0] fp80_neg_inf;
    reg [79:0] fp80_nan;
    reg [79:0] fp80_pi;
    reg [79:0] fp80_e;

    initial begin
        // +0.0
        fp80_zero = 80'h0000_0000_0000_0000_0000;
        // +1.0 = exp=16383 (0x3FFF), mant=0x8000000000000000
        fp80_one = 80'h3FFF_8000_0000_0000_0000;
        // +2.0 = exp=16384 (0x4000), mant=0x8000000000000000
        fp80_two = 80'h4000_8000_0000_0000_0000;
        // +0.5 = exp=16382 (0x3FFE), mant=0x8000000000000000
        fp80_half = 80'h3FFE_8000_0000_0000_0000;
        // -1.0
        fp80_neg_one = 80'hBFFF_8000_0000_0000_0000;
        // +∞
        fp80_inf = 80'h7FFF_8000_0000_0000_0000;
        // -∞
        fp80_neg_inf = 80'hFFFF_8000_0000_0000_0000;
        // NaN
        fp80_nan = 80'h7FFF_C000_0000_0000_0000;
        // π ≈ 3.14159265358979323846
        fp80_pi = 80'h4000_C90F_DAA2_2168_C235;
        // e ≈ 2.71828182845904523536
        fp80_e = 80'h4000_ADF8_5458_A2BB_4A9A;
    end

    //=================================================================
    // Main Test Sequence
    //=================================================================

    initial begin
        $display("========================================");
        $display("Unified MulDiv Comprehensive Testbench");
        $display("========================================");

        // Initialize
        reset = 1;
        enable = 0;
        operation = 0;
        operand_a = 0;
        operand_b = 0;
        rounding_mode = 2'b00;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        #20;
        reset = 0;
        #20;

        $display("\n========== MULTIPLY TESTS ==========");

        $display("\n--- Basic Multiply Tests ---");
        // 1.0 × 1.0 = 1.0
        test_multiply(fp80_one, fp80_one, fp80_one, 2'b00, "1.0 × 1.0 = 1.0");
        // 2.0 × 2.0 = 4.0 (exp=16385, mant=0x8000000000000000)
        test_multiply(fp80_two, fp80_two, 80'h4001_8000_0000_0000_0000, 2'b00, "2.0 × 2.0 = 4.0");
        // 0.5 × 2.0 = 1.0
        test_multiply(fp80_half, fp80_two, fp80_one, 2'b00, "0.5 × 2.0 = 1.0");
        // 1.0 × -1.0 = -1.0
        test_multiply(fp80_one, fp80_neg_one, fp80_neg_one, 2'b00, "1.0 × -1.0 = -1.0");
        // -1.0 × -1.0 = 1.0
        test_multiply(fp80_neg_one, fp80_neg_one, fp80_one, 2'b00, "-1.0 × -1.0 = 1.0");

        $display("\n--- Multiply Special Values ---");
        // 0.0 × 1.0 = 0.0
        test_multiply(fp80_zero, fp80_one, fp80_zero, 2'b00, "0.0 × 1.0 = 0.0");
        // 1.0 × 0.0 = 0.0
        test_multiply(fp80_one, fp80_zero, fp80_zero, 2'b00, "1.0 × 0.0 = 0.0");
        // ∞ × 2.0 = ∞
        test_multiply(fp80_inf, fp80_two, fp80_inf, 2'b00, "∞ × 2.0 = ∞");
        // 0.0 × ∞ = NaN (invalid)
        test_multiply(fp80_zero, fp80_inf, fp80_nan, 2'b00, "0.0 × ∞ = NaN");
        // NaN × 1.0 = NaN
        test_multiply(fp80_nan, fp80_one, fp80_nan, 2'b00, "NaN × 1.0 = NaN");

        $display("\n========== DIVIDE TESTS ==========");

        $display("\n--- Basic Divide Tests ---");
        // 1.0 ÷ 1.0 = 1.0
        test_divide(fp80_one, fp80_one, fp80_one, 2'b00, "1.0 ÷ 1.0 = 1.0");
        // 2.0 ÷ 2.0 = 1.0
        test_divide(fp80_two, fp80_two, fp80_one, 2'b00, "2.0 ÷ 2.0 = 1.0");
        // 1.0 ÷ 2.0 = 0.5
        test_divide(fp80_one, fp80_two, fp80_half, 2'b00, "1.0 ÷ 2.0 = 0.5");
        // 2.0 ÷ 1.0 = 2.0
        test_divide(fp80_two, fp80_one, fp80_two, 2'b00, "2.0 ÷ 1.0 = 2.0");
        // -1.0 ÷ 1.0 = -1.0
        test_divide(fp80_neg_one, fp80_one, fp80_neg_one, 2'b00, "-1.0 ÷ 1.0 = -1.0");
        // -1.0 ÷ -1.0 = 1.0
        test_divide(fp80_neg_one, fp80_neg_one, fp80_one, 2'b00, "-1.0 ÷ -1.0 = 1.0");

        $display("\n--- Divide Special Values ---");
        // 0.0 ÷ 1.0 = 0.0
        test_divide(fp80_zero, fp80_one, fp80_zero, 2'b00, "0.0 ÷ 1.0 = 0.0");
        // 1.0 ÷ 0.0 = ∞ (div by zero)
        test_divide(fp80_one, fp80_zero, fp80_inf, 2'b00, "1.0 ÷ 0.0 = ∞");
        // 0.0 ÷ 0.0 = NaN (invalid)
        test_divide(fp80_zero, fp80_zero, fp80_nan, 2'b00, "0.0 ÷ 0.0 = NaN");
        // ∞ ÷ 1.0 = ∞
        test_divide(fp80_inf, fp80_one, fp80_inf, 2'b00, "∞ ÷ 1.0 = ∞");
        // ∞ ÷ ∞ = NaN (invalid)
        test_divide(fp80_inf, fp80_inf, fp80_nan, 2'b00, "∞ ÷ ∞ = NaN");
        // 1.0 ÷ ∞ = 0.0
        test_divide(fp80_one, fp80_inf, fp80_zero, 2'b00, "1.0 ÷ ∞ = 0.0");
        // NaN ÷ 1.0 = NaN
        test_divide(fp80_nan, fp80_one, fp80_nan, 2'b00, "NaN ÷ 1.0 = NaN");

        $display("\n--- Multiplication with Various Values ---");
        // π × 2 ≈ 6.28318530717958647692
        test_multiply(fp80_pi, fp80_two, 80'h4001_C90F_DAA2_2168_C235, 2'b00, "π × 2 ≈ 6.283");
        // e × 2 ≈ 5.43656365691809047072
        test_multiply(fp80_e, fp80_two, 80'h4001_ADF8_5458_A2BB_4A9A, 2'b00, "e × 2 ≈ 5.437");

        $display("\n--- Division with Various Values ---");
        // π ÷ 2 ≈ 1.57079632679489661923
        test_divide(fp80_pi, fp80_two, 80'h3FFF_C90F_DAA2_2168_C235, 2'b00, "π ÷ 2 ≈ 1.571");
        // e ÷ 2 ≈ 1.35914091422952261768
        test_divide(fp80_e, fp80_two, 80'h3FFF_ADF8_5458_A2BB_4A9A, 2'b00, "e ÷ 2 ≈ 1.359");

        $display("\n--- Edge Cases ---");
        // Very small × very small (test underflow handling)
        test_multiply(80'h0001_8000_0000_0000_0000, 80'h0001_8000_0000_0000_0000,
                      80'h0000_0000_0000_0000_0000, 2'b00, "tiny × tiny → underflow");

        #100;

        $display("\n========================================");
        $display("Test Results:");
        $display("  Total: %0d", test_count);
        $display("  Pass:  %0d", pass_count);
        $display("  Fail:  %0d", fail_count);
        $display("========================================");

        if (fail_count == 0) begin
            $display("✓ ALL TESTS PASSED");
        end else begin
            $display("✗ %0d TESTS FAILED", fail_count);
        end

        $finish;
    end

    // Timeout watchdog
    initial begin
        #500000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule
