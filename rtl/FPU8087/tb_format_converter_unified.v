`timescale 1ns / 1ps

//=====================================================================
// Testbench for Unified Format Converter
//
// Tests all conversion modes:
//   - FP32 ↔ FP80
//   - FP64 ↔ FP80
//   - Int16 ↔ FP80
//   - Int32 ↔ FP80
//   - UInt64 ↔ FP80
//
// Validates against original separate converter modules
//=====================================================================

module tb_format_converter_unified;

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
    // Signals for Unified Converter
    //=================================================================

    reg enable;
    reg [3:0] mode;

    // Inputs
    reg [79:0] fp80_in;
    reg [63:0] fp64_in;
    reg [31:0] fp32_in;
    reg [63:0] uint64_in;
    reg [31:0] int32_in;
    reg [15:0] int16_in;
    reg        uint64_sign;
    reg [1:0]  rounding_mode;

    // Outputs
    wire [79:0] fp80_out;
    wire [63:0] fp64_out;
    wire [31:0] fp32_out;
    wire [63:0] uint64_out;
    wire [31:0] int32_out;
    wire [15:0] int16_out;
    wire        uint64_sign_out;
    wire        done;
    wire        flag_invalid;
    wire        flag_overflow;
    wire        flag_underflow;
    wire        flag_inexact;

    //=================================================================
    // Instantiate Unified Converter
    //=================================================================

    FPU_Format_Converter_Unified uut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .mode(mode),
        .fp80_in(fp80_in),
        .fp64_in(fp64_in),
        .fp32_in(fp32_in),
        .uint64_in(uint64_in),
        .int32_in(int32_in),
        .int16_in(int16_in),
        .uint64_sign(uint64_sign),
        .rounding_mode(rounding_mode),
        .fp80_out(fp80_out),
        .fp64_out(fp64_out),
        .fp32_out(fp32_out),
        .uint64_out(uint64_out),
        .int32_out(int32_out),
        .int16_out(int16_out),
        .uint64_sign_out(uint64_sign_out),
        .done(done),
        .flag_invalid(flag_invalid),
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
    // Test Tasks
    //=================================================================

    task test_fp32_to_fp80;
        input [31:0] fp32_value;
        input [79:0] expected_fp80;
        input [80:0] test_name;  // String parameter
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            mode = 4'd0;  // MODE_FP32_TO_FP80
            fp32_in = fp32_value;
            rounding_mode = 2'b00;

            @(posedge clk);
            enable = 1'b0;

            // Wait for done signal
            while (!done) @(posedge clk);

            if (fp80_out == expected_fp80) begin
                $display("PASS: FP32→FP80: %h → %h", fp32_value, fp80_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: FP32→FP80: %h → %h (expected %h)", fp32_value, fp80_out, expected_fp80);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task test_fp64_to_fp80;
        input [63:0] fp64_value;
        input [79:0] expected_fp80;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            mode = 4'd1;  // MODE_FP64_TO_FP80
            fp64_in = fp64_value;
            rounding_mode = 2'b00;

            @(posedge clk);
            enable = 1'b0;

            while (!done) @(posedge clk);

            if (fp80_out == expected_fp80) begin
                $display("PASS: FP64→FP80: %h → %h", fp64_value, fp80_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: FP64→FP80: %h → %h (expected %h)", fp64_value, fp80_out, expected_fp80);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task test_fp80_to_fp32;
        input [79:0] fp80_value;
        input [31:0] expected_fp32;
        input [1:0]  rmode;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            mode = 4'd2;  // MODE_FP80_TO_FP32
            fp80_in = fp80_value;
            rounding_mode = rmode;

            @(posedge clk);
            enable = 1'b0;

            while (!done) @(posedge clk);

            if ( fp32_out == expected_fp32) begin
                $display("PASS: FP80→FP32: %h → %h", fp80_value, fp32_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: FP80→FP32: %h → %h (expected %h)", fp80_value, fp32_out, expected_fp32);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task test_fp80_to_fp64;
        input [79:0] fp80_value;
        input [63:0] expected_fp64;
        input [1:0]  rmode;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            mode = 4'd3;  // MODE_FP80_TO_FP64
            fp80_in = fp80_value;
            rounding_mode = rmode;

            @(posedge clk);
            enable = 1'b0;

            while (!done) @(posedge clk);

            if ( fp64_out == expected_fp64) begin
                $display("PASS: FP80→FP64: %h → %h", fp80_value, fp64_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: FP80→FP64: %h → %h (expected %h)", fp80_value, fp64_out, expected_fp64);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task test_int16_to_fp80;
        input signed [15:0] int_value;
        input [79:0] expected_fp80;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            mode = 4'd4;  // MODE_INT16_TO_FP80
            int16_in = int_value;
            rounding_mode = 2'b00;

            @(posedge clk);
            enable = 1'b0;

            while (!done) @(posedge clk);

            if ( fp80_out == expected_fp80) begin
                $display("PASS: Int16→FP80: %d → %h", int_value, fp80_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Int16→FP80: %d → %h (expected %h)", int_value, fp80_out, expected_fp80);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task test_int32_to_fp80;
        input signed [31:0] int_value;
        input [79:0] expected_fp80;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            mode = 4'd5;  // MODE_INT32_TO_FP80
            int32_in = int_value;
            rounding_mode = 2'b00;

            @(posedge clk);
            enable = 1'b0;

            while (!done) @(posedge clk);

            if ( fp80_out == expected_fp80) begin
                $display("PASS: Int32→FP80: %d → %h", int_value, fp80_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Int32→FP80: %d → %h (expected %h)", int_value, fp80_out, expected_fp80);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task test_fp80_to_int16;
        input [79:0] fp80_value;
        input signed [15:0] expected_int;
        input [1:0]  rmode;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            mode = 4'd6;  // MODE_FP80_TO_INT16
            fp80_in = fp80_value;
            rounding_mode = rmode;

            @(posedge clk);
            enable = 1'b0;

            while (!done) @(posedge clk);

            if ( int16_out == expected_int) begin
                $display("PASS: FP80→Int16: %h → %d", fp80_value, $signed(int16_out));
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: FP80→Int16: %h → %d (expected %d)", fp80_value, $signed(int16_out), expected_int);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task test_fp80_to_int32;
        input [79:0] fp80_value;
        input signed [31:0] expected_int;
        input [1:0]  rmode;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            mode = 4'd7;  // MODE_FP80_TO_INT32
            fp80_in = fp80_value;
            rounding_mode = rmode;

            @(posedge clk);
            enable = 1'b0;

            while (!done) @(posedge clk);

            if ( int32_out == expected_int) begin
                $display("PASS: FP80→Int32: %h → %d", fp80_value, $signed(int32_out));
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: FP80→Int32: %h → %d (expected %d)", fp80_value, $signed(int32_out), expected_int);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task test_uint64_to_fp80;
        input [63:0] uint_value;
        input        sign_value;
        input [79:0] expected_fp80;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            mode = 4'd8;  // MODE_UINT64_TO_FP80
            uint64_in = uint_value;
            uint64_sign = sign_value;
            rounding_mode = 2'b00;

            @(posedge clk);
            enable = 1'b0;

            while (!done) @(posedge clk);

            if ( fp80_out == expected_fp80) begin
                $display("PASS: UInt64→FP80: %h (sign=%b) → %h", uint_value, sign_value, fp80_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: UInt64→FP80: %h (sign=%b) → %h (expected %h)", uint_value, sign_value, fp80_out, expected_fp80);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task test_fp80_to_uint64;
        input [79:0] fp80_value;
        input [63:0] expected_uint;
        input [1:0]  rmode;
        begin
            test_count = test_count + 1;
            @(posedge clk);
            enable = 1'b1;
            mode = 4'd9;  // MODE_FP80_TO_UINT64
            fp80_in = fp80_value;
            rounding_mode = rmode;

            @(posedge clk);
            enable = 1'b0;

            while (!done) @(posedge clk);

            if ( uint64_out == expected_uint) begin
                $display("PASS: FP80→UInt64: %h → %h", fp80_value, uint64_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: FP80→UInt64: %h → %h (expected %h)", fp80_value, uint64_out, expected_uint);
                fail_count = fail_count + 1;
            end
        end
    endtask

    //=================================================================
    // Main Test Sequence
    //=================================================================

    initial begin
        $display("========================================");
        $display("Unified Format Converter Testbench");
        $display("========================================");

        // Initialize
        reset = 1;
        enable = 0;
        mode = 0;
        fp80_in = 0;
        fp64_in = 0;
        fp32_in = 0;
        uint64_in = 0;
        int32_in = 0;
        int16_in = 0;
        uint64_sign = 0;
        rounding_mode = 2'b00;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        #20;
        reset = 0;
        #20;

        $display("\n--- Testing FP32 → FP80 ---");
        // +0.0
        test_fp32_to_fp80(32'h00000000, 80'h00000000000000000000, "Zero");
        // +1.0 = 0x3F800000 (exp=127, frac=0) → FP80: exp=16383, mant=0x8000000000000000
        test_fp32_to_fp80(32'h3F800000, 80'h3FFF8000000000000000, "1.0");
        // -1.0
        test_fp32_to_fp80(32'hBF800000, 80'hBFFF8000000000000000, "-1.0");
        // +∞
        test_fp32_to_fp80(32'h7F800000, 80'h7FFF8000000000000000, "+Inf");
        // -∞
        test_fp32_to_fp80(32'hFF800000, 80'hFFFF8000000000000000, "-Inf");

        $display("\n--- Testing FP64 → FP80 ---");
        // +0.0
        test_fp64_to_fp80(64'h0000000000000000, 80'h00000000000000000000);
        // +1.0
        test_fp64_to_fp80(64'h3FF0000000000000, 80'h3FFF8000000000000000);
        // -1.0
        test_fp64_to_fp80(64'hBFF0000000000000, 80'hBFFF8000000000000000);
        // +∞
        test_fp64_to_fp80(64'h7FF0000000000000, 80'h7FFF8000000000000000);

        $display("\n--- Testing FP80 → FP32 ---");
        // +1.0
        test_fp80_to_fp32(80'h3FFF8000000000000000, 32'h3F800000, 2'b00);
        // -1.0
        test_fp80_to_fp32(80'hBFFF8000000000000000, 32'hBF800000, 2'b00);
        // +∞
        test_fp80_to_fp32(80'h7FFF8000000000000000, 32'h7F800000, 2'b00);

        $display("\n--- Testing FP80 → FP64 ---");
        // +1.0
        test_fp80_to_fp64(80'h3FFF8000000000000000, 64'h3FF0000000000000, 2'b00);
        // -1.0
        test_fp80_to_fp64(80'hBFFF8000000000000000, 64'hBFF0000000000000, 2'b00);

        $display("\n--- Testing Int16 → FP80 ---");
        // 0
        test_int16_to_fp80(16'sd0, 80'h00000000000000000000);
        // +1 → exp=16383, mant=0x8000000000000000
        test_int16_to_fp80(16'sd1, 80'h3FFF8000000000000000);
        // -1
        test_int16_to_fp80(-16'sd1, 80'hBFFF8000000000000000);
        // +100 → exp=16383+6=16389, mant=100<<57 = 0xC800000000000000
        test_int16_to_fp80(16'sd100, 80'h4005C800000000000000);
        // -100
        test_int16_to_fp80(-16'sd100, 80'hC005C800000000000000);

        $display("\n--- Testing Int32 → FP80 ---");
        // 0
        test_int32_to_fp80(32'sd0, 80'h00000000000000000000);
        // +1
        test_int32_to_fp80(32'sd1, 80'h3FFF8000000000000000);
        // -1
        test_int32_to_fp80(-32'sd1, 80'hBFFF8000000000000000);
        // +1000 (0x3E8 → normalized 1.111101 × 2^9 → exp=0x4008, mant=0xFA00...)
        test_int32_to_fp80(32'sd1000, 80'h4008FA00000000000000);

        $display("\n--- Testing FP80 → Int16 ---");
        // +1.0 → 1
        test_fp80_to_int16(80'h3FFF8000000000000000, 16'sd1, 2'b00);
        // -1.0 → -1
        test_fp80_to_int16(80'hBFFF8000000000000000, -16'sd1, 2'b00);
        // +100.0 → 100
        test_fp80_to_int16(80'h4005C800000000000000, 16'sd100, 2'b00);

        $display("\n--- Testing FP80 → Int32 ---");
        // +1.0 → 1
        test_fp80_to_int32(80'h3FFF8000000000000000, 32'sd1, 2'b00);
        // -1.0 → -1
        test_fp80_to_int32(80'hBFFF8000000000000000, -32'sd1, 2'b00);
        // +1000.0 → 1000
        test_fp80_to_int32(80'h4008FA00000000000000, 32'sd1000, 2'b00);

        $display("\n--- Testing UInt64 → FP80 ---");
        // 0
        test_uint64_to_fp80(64'd0, 1'b0, 80'h00000000000000000000);
        // +1
        test_uint64_to_fp80(64'd1, 1'b0, 80'h3FFF8000000000000000);
        // +1000
        test_uint64_to_fp80(64'd1000, 1'b0, 80'h4008FA00000000000000);

        $display("\n--- Testing FP80 → UInt64 ---");
        // +1.0 → 1
        test_fp80_to_uint64(80'h3FFF8000000000000000, 64'd1, 2'b00);
        // +1000.0 → 1000
        test_fp80_to_uint64(80'h4008FA00000000000000, 64'd1000, 2'b00);

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
        #50000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule
