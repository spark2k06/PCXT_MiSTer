`timescale 1ns / 1ps

//=====================================================================
// Testbench for FP32/FP64 ↔ FP80 Format Conversion
//
// Tests all floating-point conversion modules:
// - FP32 → FP80
// - FP64 → FP80
// - FP80 → FP32
// - FP80 → FP64
//=====================================================================

module tb_format_conv_fp;

    // Clock and reset
    reg clk;
    reg reset;

    // Test control
    reg enable;
    integer passed_tests;
    integer failed_tests;
    integer total_tests;

    //=================================================================
    // FP32 → FP80 Test Signals
    //=================================================================

    reg [31:0] fp32_in;
    wire [79:0] fp32_to_fp80_out;
    wire fp32_to_fp80_done;

    FPU_FP32_to_FP80 dut_fp32_to_fp80 (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .fp32_in(fp32_in),
        .fp80_out(fp32_to_fp80_out),
        .done(fp32_to_fp80_done)
    );

    //=================================================================
    // FP64 → FP80 Test Signals
    //=================================================================

    reg [63:0] fp64_in;
    wire [79:0] fp64_to_fp80_out;
    wire fp64_to_fp80_done;

    FPU_FP64_to_FP80 dut_fp64_to_fp80 (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .fp64_in(fp64_in),
        .fp80_out(fp64_to_fp80_out),
        .done(fp64_to_fp80_done)
    );

    //=================================================================
    // FP80 → FP32 Test Signals
    //=================================================================

    reg [79:0] fp80_to_fp32_in;
    reg [1:0] fp80_to_fp32_round;
    wire [31:0] fp80_to_fp32_out;
    wire fp80_to_fp32_done;
    wire fp80_to_fp32_invalid;
    wire fp80_to_fp32_overflow;
    wire fp80_to_fp32_underflow;
    wire fp80_to_fp32_inexact;

    FPU_FP80_to_FP32 dut_fp80_to_fp32 (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .fp80_in(fp80_to_fp32_in),
        .rounding_mode(fp80_to_fp32_round),
        .fp32_out(fp80_to_fp32_out),
        .done(fp80_to_fp32_done),
        .flag_invalid(fp80_to_fp32_invalid),
        .flag_overflow(fp80_to_fp32_overflow),
        .flag_underflow(fp80_to_fp32_underflow),
        .flag_inexact(fp80_to_fp32_inexact)
    );

    //=================================================================
    // FP80 → FP64 Test Signals
    //=================================================================

    reg [79:0] fp80_to_fp64_in;
    reg [1:0] fp80_to_fp64_round;
    wire [63:0] fp80_to_fp64_out;
    wire fp80_to_fp64_done;
    wire fp80_to_fp64_invalid;
    wire fp80_to_fp64_overflow;
    wire fp80_to_fp64_underflow;
    wire fp80_to_fp64_inexact;

    FPU_FP80_to_FP64 dut_fp80_to_fp64 (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .fp80_in(fp80_to_fp64_in),
        .rounding_mode(fp80_to_fp64_round),
        .fp64_out(fp80_to_fp64_out),
        .done(fp80_to_fp64_done),
        .flag_invalid(fp80_to_fp64_invalid),
        .flag_overflow(fp80_to_fp64_overflow),
        .flag_underflow(fp80_to_fp64_underflow),
        .flag_inexact(fp80_to_fp64_inexact)
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
        $display("FP32/64 ↔ FP80 Conversion Test Suite");
        $display("========================================");
        $display("");

        // Initialize
        reset = 1;
        enable = 0;
        passed_tests = 0;
        failed_tests = 0;
        total_tests = 20;

        #20 reset = 0;
        #10;

        //=============================================================
        // Test Suite 1: FP32 → FP80
        //=============================================================

        $display("Test Suite 1: FP32 → FP80");
        $display("----------------------------");

        // Test 1: 0.0
        fp32_in = 32'h00000000;
        enable = 1;
        #10 enable = 0;
        wait(fp32_to_fp80_done);
        if (fp32_to_fp80_out == 80'h00000000000000000000) begin
            $display("  PASS: FP32 0.0 → FP80 0.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP32 0.0, got %h", fp32_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 2: 1.0
        fp32_in = 32'h3F800000;
        enable = 1;
        #10 enable = 0;
        wait(fp32_to_fp80_done);
        if (fp32_to_fp80_out == 80'h3FFF8000000000000000) begin
            $display("  PASS: FP32 1.0 → FP80 1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP32 1.0, got %h", fp32_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 3: -1.0
        fp32_in = 32'hBF800000;
        enable = 1;
        #10 enable = 0;
        wait(fp32_to_fp80_done);
        if (fp32_to_fp80_out == 80'hBFFF8000000000000000) begin
            $display("  PASS: FP32 -1.0 → FP80 -1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP32 -1.0, got %h", fp32_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 4: +∞
        fp32_in = 32'h7F800000;
        enable = 1;
        #10 enable = 0;
        wait(fp32_to_fp80_done);
        if (fp32_to_fp80_out == 80'h7FFF8000000000000000) begin
            $display("  PASS: FP32 +∞ → FP80 +∞");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP32 +∞, got %h", fp32_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 5: NaN
        fp32_in = 32'h7FC00000;
        enable = 1;
        #10 enable = 0;
        wait(fp32_to_fp80_done);
        if (fp32_to_fp80_out[78:64] == 15'h7FFF && fp32_to_fp80_out[63]) begin
            $display("  PASS: FP32 NaN → FP80 NaN");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP32 NaN, got %h", fp32_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        $display("");

        //=============================================================
        // Test Suite 2: FP64 → FP80
        //=============================================================

        $display("Test Suite 2: FP64 → FP80");
        $display("----------------------------");

        // Test 6: 0.0
        fp64_in = 64'h0000000000000000;
        enable = 1;
        #10 enable = 0;
        wait(fp64_to_fp80_done);
        if (fp64_to_fp80_out == 80'h00000000000000000000) begin
            $display("  PASS: FP64 0.0 → FP80 0.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP64 0.0, got %h", fp64_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 7: 1.0
        fp64_in = 64'h3FF0000000000000;
        enable = 1;
        #10 enable = 0;
        wait(fp64_to_fp80_done);
        if (fp64_to_fp80_out == 80'h3FFF8000000000000000) begin
            $display("  PASS: FP64 1.0 → FP80 1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP64 1.0, got %h", fp64_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 8: -1.0
        fp64_in = 64'hBFF0000000000000;
        enable = 1;
        #10 enable = 0;
        wait(fp64_to_fp80_done);
        if (fp64_to_fp80_out == 80'hBFFF8000000000000000) begin
            $display("  PASS: FP64 -1.0 → FP80 -1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP64 -1.0, got %h", fp64_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 9: +∞
        fp64_in = 64'h7FF0000000000000;
        enable = 1;
        #10 enable = 0;
        wait(fp64_to_fp80_done);
        if (fp64_to_fp80_out == 80'h7FFF8000000000000000) begin
            $display("  PASS: FP64 +∞ → FP80 +∞");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP64 +∞, got %h", fp64_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 10: NaN
        fp64_in = 64'h7FF8000000000000;
        enable = 1;
        #10 enable = 0;
        wait(fp64_to_fp80_done);
        if (fp64_to_fp80_out[78:64] == 15'h7FFF && fp64_to_fp80_out[63]) begin
            $display("  PASS: FP64 NaN → FP80 NaN");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP64 NaN, got %h", fp64_to_fp80_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        $display("");

        //=============================================================
        // Test Suite 3: FP80 → FP32
        //=============================================================

        $display("Test Suite 3: FP80 → FP32");
        $display("----------------------------");

        // Test 11: 0.0
        fp80_to_fp32_in = 80'h00000000000000000000;
        fp80_to_fp32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_fp32_done);
        if (fp80_to_fp32_out == 32'h00000000) begin
            $display("  PASS: FP80 0.0 → FP32 0.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP80 0.0, got %h", fp80_to_fp32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 12: 1.0
        fp80_to_fp32_in = 80'h3FFF8000000000000000;
        fp80_to_fp32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_fp32_done);
        if (fp80_to_fp32_out == 32'h3F800000) begin
            $display("  PASS: FP80 1.0 → FP32 1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP80 1.0, got %h", fp80_to_fp32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 13: -1.0
        fp80_to_fp32_in = 80'hBFFF8000000000000000;
        fp80_to_fp32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_fp32_done);
        if (fp80_to_fp32_out == 32'hBF800000) begin
            $display("  PASS: FP80 -1.0 → FP32 -1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP80 -1.0, got %h", fp80_to_fp32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 14: +∞
        fp80_to_fp32_in = 80'h7FFF8000000000000000;
        fp80_to_fp32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_fp32_done);
        if (fp80_to_fp32_out == 32'h7F800000) begin
            $display("  PASS: FP80 +∞ → FP32 +∞");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP80 +∞, got %h", fp80_to_fp32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 15: NaN
        fp80_to_fp32_in = 80'h7FFFC000000000000000;
        fp80_to_fp32_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_fp32_done);
        if (fp80_to_fp32_out[30:23] == 8'hFF && fp80_to_fp32_out[22:0] != 23'd0) begin
            $display("  PASS: FP80 NaN → FP32 NaN");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP80 NaN, got %h", fp80_to_fp32_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        $display("");

        //=============================================================
        // Test Suite 4: FP80 → FP64
        //=============================================================

        $display("Test Suite 4: FP80 → FP64");
        $display("----------------------------");

        // Test 16: 0.0
        fp80_to_fp64_in = 80'h00000000000000000000;
        fp80_to_fp64_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_fp64_done);
        if (fp80_to_fp64_out == 64'h0000000000000000) begin
            $display("  PASS: FP80 0.0 → FP64 0.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP80 0.0, got %h", fp80_to_fp64_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 17: 1.0
        fp80_to_fp64_in = 80'h3FFF8000000000000000;
        fp80_to_fp64_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_fp64_done);
        if (fp80_to_fp64_out == 64'h3FF0000000000000) begin
            $display("  PASS: FP80 1.0 → FP64 1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP80 1.0, got %h", fp80_to_fp64_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 18: -1.0
        fp80_to_fp64_in = 80'hBFFF8000000000000000;
        fp80_to_fp64_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_fp64_done);
        if (fp80_to_fp64_out == 64'hBFF0000000000000) begin
            $display("  PASS: FP80 -1.0 → FP64 -1.0");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP80 -1.0, got %h", fp80_to_fp64_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 19: +∞
        fp80_to_fp64_in = 80'h7FFF8000000000000000;
        fp80_to_fp64_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_fp64_done);
        if (fp80_to_fp64_out == 64'h7FF0000000000000) begin
            $display("  PASS: FP80 +∞ → FP64 +∞");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP80 +∞, got %h", fp80_to_fp64_out);
            failed_tests = failed_tests + 1;
        end
        #10;

        // Test 20: NaN
        fp80_to_fp64_in = 80'h7FFFC000000000000000;
        fp80_to_fp64_round = 2'b00;
        enable = 1;
        #10 enable = 0;
        wait(fp80_to_fp64_done);
        if (fp80_to_fp64_out[62:52] == 11'h7FF && fp80_to_fp64_out[51:0] != 52'd0) begin
            $display("  PASS: FP80 NaN → FP64 NaN");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FP80 NaN, got %h", fp80_to_fp64_out);
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
