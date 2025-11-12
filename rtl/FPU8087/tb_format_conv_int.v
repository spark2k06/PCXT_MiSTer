`timescale 1ns / 1ps

//=====================================================================
// Testbench for Integer ↔ FP80 Format Conversion
//
// Tests all integer conversion modules:
// - Int16 → FP80
// - Int32 → FP80
// - FP80 → Int16
// - FP80 → Int32
//=====================================================================

module tb_format_conv_int;

    // Clock and reset
    reg clk;
    reg reset;

    // Test control
    reg enable;
    integer passed_tests;
    integer failed_tests;
    integer total_tests;

    //=================================================================
    // Int16 → FP80 Test Signals
    //=================================================================

    reg signed [15:0] int16_in;
    wire [79:0] int16_to_fp80_out;
    wire int16_to_fp80_done;

    FPU_Int16_to_FP80 dut_int16_to_fp80 (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .int_in(int16_in),
        .fp_out(int16_to_fp80_out),
        .done(int16_to_fp80_done)
    );

    //=================================================================
    // Int32 → FP80 Test Signals
    //=================================================================

    reg signed [31:0] int32_in;
    wire [79:0] int32_to_fp80_out;
    wire int32_to_fp80_done;

    FPU_Int32_to_FP80 dut_int32_to_fp80 (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .int_in(int32_in),
        .fp_out(int32_to_fp80_out),
        .done(int32_to_fp80_done)
    );

    //=================================================================
    // FP80 → Int16 Test Signals
    //=================================================================

    reg [79:0] fp80_to_int16_in;
    reg [1:0] fp80_to_int16_round;
    wire signed [15:0] fp80_to_int16_out;
    wire fp80_to_int16_done;
    wire fp80_to_int16_invalid;
    wire fp80_to_int16_overflow;
    wire fp80_to_int16_inexact;

    FPU_FP80_to_Int16 dut_fp80_to_int16 (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .fp_in(fp80_to_int16_in),
        .rounding_mode(fp80_to_int16_round),
        .int_out(fp80_to_int16_out),
        .done(fp80_to_int16_done),
        .flag_invalid(fp80_to_int16_invalid),
        .flag_overflow(fp80_to_int16_overflow),
        .flag_inexact(fp80_to_int16_inexact)
    );

    //=================================================================
    // FP80 → Int32 Test Signals
    //=================================================================

    reg [79:0] fp80_to_int32_in;
    reg [1:0] fp80_to_int32_round;
    wire signed [31:0] fp80_to_int32_out;
    wire fp80_to_int32_done;
    wire fp80_to_int32_invalid;
    wire fp80_to_int32_overflow;
    wire fp80_to_int32_inexact;

    FPU_FP80_to_Int32 dut_fp80_to_int32 (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .fp_in(fp80_to_int32_in),
        .rounding_mode(fp80_to_int32_round),
        .int_out(fp80_to_int32_out),
        .done(fp80_to_int32_done),
        .flag_invalid(fp80_to_int32_invalid),
        .flag_overflow(fp80_to_int32_overflow),
        .flag_inexact(fp80_to_int32_inexact)
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
        $display("Integer ↔ FP80 Conversion Test Suite");
        $display("========================================");
        $display("");

        // Initialize
        reset = 1;
        enable = 0;
        passed_tests = 0;
        failed_tests = 0;
        total_tests = 30;

        #20 reset = 0;
        #10;

        //=============================================================
        // Test Suite 1: Int16 → FP80
        //=============================================================

        $display("Test Suite 1: Int16 → FP80");
        $display("----------------------------");

        // Test 1: 0 → 0.0
        int16_in = 16'd0;
        enable = 1;
        #10 enable = 0;
        wait(int16_to_fp80_done);
        if (int16_to_fp80_out == 80'h00000000000000000000) begin
            $display("  PASS: 0 → 0.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 0 → 0.0, got %h", int16_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 2: 1 → 1.0
        int16_in = 16'd1;
        enable = 1;
        #10 enable = 0;
        wait(int16_to_fp80_done);
        if (int16_to_fp80_out == 80'h3FFF8000000000000000) begin
            $display("  PASS: 1 → 1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1 → 1.0, got %h", int16_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 3: -1 → -1.0
        int16_in = -16'sd1;
        enable = 1;
        #10 enable = 0;
        wait(int16_to_fp80_done);
        if (int16_to_fp80_out == 80'hBFFF8000000000000000) begin
            $display("  PASS: -1 → -1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: -1 → -1.0, got %h", int16_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 4: 100 → 100.0
        int16_in = 16'sd100;
        enable = 1;
        #10 enable = 0;
        wait(int16_to_fp80_done);
        if (int16_to_fp80_out == 80'h4005C800000000000000) begin
            $display("  PASS: 100 → 100.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 100 → 100.0, got %h", int16_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 5: -100 → -100.0
        int16_in = -16'sd100;
        enable = 1;
        #10 enable = 0;
        wait(int16_to_fp80_done);
        if (int16_to_fp80_out == 80'hC005C800000000000000) begin
            $display("  PASS: -100 → -100.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: -100 → -100.0, got %h", int16_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 6: 32767 (max positive)
        int16_in = 16'sh7FFF;
        enable = 1;
        #10 enable = 0;
        wait(int16_to_fp80_done);
        if (int16_to_fp80_out[79] == 1'b0 && int16_to_fp80_out[78:64] == 15'h400D) begin
            $display("  PASS: 32767 → FP80");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 32767, got %h", int16_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 7: -32768 (max negative)
        int16_in = 16'sh8000;
        enable = 1;
        #10 enable = 0;
        wait(int16_to_fp80_done);
        if (int16_to_fp80_out[79] == 1'b1 && int16_to_fp80_out[78:64] == 15'h400E) begin
            $display("  PASS: -32768 → FP80");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: -32768, got %h", int16_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        $display("");

        //=============================================================
        // Test Suite 2: Int32 → FP80
        //=============================================================

        $display("Test Suite 2: Int32 → FP80");
        $display("----------------------------");

        // Test 8: 0 → 0.0
        int32_in = 32'd0;
        enable = 1;
        #10 enable = 0;
        wait(int32_to_fp80_done);
        if (int32_to_fp80_out == 80'h00000000000000000000) begin
            $display("  PASS: 0 → 0.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 0 → 0.0, got %h", int32_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 9: 1 → 1.0
        int32_in = 32'd1;
        enable = 1;
        #10 enable = 0;
        wait(int32_to_fp80_done);
        if (int32_to_fp80_out == 80'h3FFF8000000000000000) begin
            $display("  PASS: 1 → 1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1 → 1.0, got %h", int32_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 10: 1000000 → 1000000.0
        int32_in = 32'sd1000000;
        enable = 1;
        #10 enable = 0;
        wait(int32_to_fp80_done);
        if (int32_to_fp80_out[78:64] == 15'h4012 && int32_to_fp80_out[63]) begin
            $display("  PASS: 1000000 → FP80");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1000000, got %h", int32_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 11: -1000000 → -1000000.0
        int32_in = -32'sd1000000;
        enable = 1;
        #10 enable = 0;
        wait(int32_to_fp80_done);
        if (int32_to_fp80_out[79] == 1'b1 && int32_to_fp80_out[78:64] == 15'h4012) begin
            $display("  PASS: -1000000 → FP80");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: -1000000, got %h", int32_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        $display("");

        //=============================================================
        // Test Suite 3: FP80 → Int16
        //=============================================================

        $display("Test Suite 3: FP80 → Int16");
        $display("----------------------------");

        // Test 12: 0.0 → 0
        fp80_to_int16_in = 80'h00000000000000000000;
        fp80_to_int16_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int16_done);
        if (fp80_to_int16_out == 16'd0) begin
            $display("  PASS: 0.0 → 0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 0.0 → 0, got %d", fp80_to_int16_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 13: 1.0 → 1
        fp80_to_int16_in = 80'h3FFF8000000000000000;
        fp80_to_int16_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int16_done);
        if (fp80_to_int16_out == 16'sd1) begin
            $display("  PASS: 1.0 → 1");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.0 → 1, got %d", fp80_to_int16_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 14: -1.0 → -1
        fp80_to_int16_in = 80'hBFFF8000000000000000;
        fp80_to_int16_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int16_done);
        if (fp80_to_int16_out == -16'sd1) begin
            $display("  PASS: -1.0 → -1");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: -1.0 → -1, got %d", fp80_to_int16_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 15: 100.0 → 100
        fp80_to_int16_in = 80'h4005C800000000000000;
        fp80_to_int16_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int16_done);
        if (fp80_to_int16_out == 16'sd100) begin
            $display("  PASS: 100.0 → 100");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 100.0 → 100, got %d", fp80_to_int16_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 16: 1.5 → 2 (round to nearest)
        fp80_to_int16_in = 80'h3FFFC000000000000000;
        fp80_to_int16_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int16_done);
        if (fp80_to_int16_out == 16'sd2 && fp80_to_int16_inexact) begin
            $display("  PASS: 1.5 → 2 (rounded)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.5 → 2, got %d", fp80_to_int16_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 17: 1.5 → 1 (truncate)
        fp80_to_int16_in = 80'h3FFFC000000000000000;
        fp80_to_int16_round = 2'b11;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int16_done);
        if (fp80_to_int16_out == 16'sd1 && fp80_to_int16_inexact) begin
            $display("  PASS: 1.5 → 1 (truncate)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.5 → 1 (trunc), got %d", fp80_to_int16_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 18: +∞ → 32767 (overflow)
        fp80_to_int16_in = 80'h7FFF8000000000000000;
        fp80_to_int16_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int16_done);
        if (fp80_to_int16_out == 16'sh7FFF && fp80_to_int16_invalid) begin
            $display("  PASS: +∞ → 32767 (invalid)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: +∞ invalid, got %d", fp80_to_int16_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 19: -∞ → -32768 (overflow)
        fp80_to_int16_in = 80'hFFFF8000000000000000;
        fp80_to_int16_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int16_done);
        if (fp80_to_int16_out == 16'sh8000 && fp80_to_int16_invalid) begin
            $display("  PASS: -∞ → -32768 (invalid)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: -∞ invalid, got %d", fp80_to_int16_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        $display("");

        //=============================================================
        // Test Suite 4: FP80 → Int32
        //=============================================================

        $display("Test Suite 4: FP80 → Int32");
        $display("----------------------------");

        // Test 20: 0.0 → 0
        fp80_to_int32_in = 80'h00000000000000000000;
        fp80_to_int32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int32_done);
        if (fp80_to_int32_out == 32'd0) begin
            $display("  PASS: 0.0 → 0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 0.0 → 0, got %d", fp80_to_int32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 21: 1.0 → 1
        fp80_to_int32_in = 80'h3FFF8000000000000000;
        fp80_to_int32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int32_done);
        if (fp80_to_int32_out == 32'sd1) begin
            $display("  PASS: 1.0 → 1");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.0 → 1, got %d", fp80_to_int32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 22: 1000000.0 → 1000000
        fp80_to_int32_in = 80'h4012F424000000000000;
        fp80_to_int32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int32_done);
        if (fp80_to_int32_out == 32'sd1000000) begin
            $display("  PASS: 1000000.0 → 1000000");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1000000.0, got %d", fp80_to_int32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 23: -1000000.0 → -1000000
        fp80_to_int32_in = 80'hC012F424000000000000;
        fp80_to_int32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int32_done);
        if (fp80_to_int32_out == -32'sd1000000) begin
            $display("  PASS: -1000000.0 → -1000000");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: -1000000.0, got %d", fp80_to_int32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 24: 3.0 → 3 (exact)
        fp80_to_int32_in = 80'h4000C000000000000000;  // 3.0 = 1.5 × 2^1
        fp80_to_int32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int32_done);
        if (fp80_to_int32_out == 32'sd3) begin
            $display("  PASS: 3.0 → 3");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 3.0 → 3, got %d", fp80_to_int32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 25: 10.0 → 10 (exact)
        fp80_to_int32_in = 80'h4002A000000000000000;  // 10.0 = 1.25 × 2^3
        fp80_to_int32_round = 2'b11;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int32_done);
        if (fp80_to_int32_out == 32'sd10) begin
            $display("  PASS: 10.0 → 10");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 10.0 → 10, got %d", fp80_to_int32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 26: +∞ → 2147483647 (overflow)
        fp80_to_int32_in = 80'h7FFF8000000000000000;
        fp80_to_int32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int32_done);
        if (fp80_to_int32_out == 32'sh7FFFFFFF && fp80_to_int32_invalid) begin
            $display("  PASS: +∞ → 2147483647 (invalid)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: +∞ invalid, got %d", fp80_to_int32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 27: -∞ → -2147483648 (overflow)
        fp80_to_int32_in = 80'hFFFF8000000000000000;
        fp80_to_int32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int32_done);
        if (fp80_to_int32_out == 32'sh80000000 && fp80_to_int32_invalid) begin
            $display("  PASS: -∞ → -2147483648 (invalid)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: -∞ invalid, got %d", fp80_to_int32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 28: 0.5 → 0 (truncate)
        fp80_to_int32_in = 80'h3FFE8000000000000000;
        fp80_to_int32_round = 2'b11;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int32_done);
        if (fp80_to_int32_out == 32'sd0 && fp80_to_int32_inexact) begin
            $display("  PASS: 0.5 → 0 (truncate)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 0.5 → 0 (trunc), got %d", fp80_to_int32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 29: 0.5 → 1 (round up mode)
        fp80_to_int32_in = 80'h3FFE8000000000000000;
        fp80_to_int32_round = 2'b10;  // Round up
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int32_done);
        if (fp80_to_int32_out == 32'sd1 && fp80_to_int32_inexact) begin
            $display("  PASS: 0.5 → 1 (round up)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 0.5 round up, got %d", fp80_to_int32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 30: 1.5 → 2 (round to nearest)
        fp80_to_int32_in = 80'h3FFFC000000000000000;
        fp80_to_int32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_int32_done);
        if (fp80_to_int32_out == 32'sd2 && fp80_to_int32_inexact) begin
            $display("  PASS: 1.5 → 2 (round to even)");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: 1.5 round, got %d", fp80_to_int32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        $display("");

        //=============================================================
        // Test Results Summary
        //=============================================================

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
