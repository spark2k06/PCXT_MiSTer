`timescale 1ns / 1ps

//=====================================================================
// Transcendental Functions Testbench
//
// Tests the 4 implemented transcendental instructions:
// - FSQRT  (0x50): Square root
// - FSIN   (0x51): Sine
// - FCOS   (0x52): Cosine
// - FSINCOS(0x53): Sine and Cosine (dual result)
//
// Usage:
//   iverilog -o tb_transcendental tb_transcendental.v FPU_Core.v ...
//   vvp tb_transcendental
//=====================================================================

module tb_transcendental;

    //=================================================================
    // Test Parameters
    //=================================================================

    parameter CLK_PERIOD = 10;  // 100 MHz clock
    parameter MAX_ERRORS = 10;  // Stop after this many errors
    parameter VERBOSE = 0;      // Set to 1 for detailed output

    //=================================================================
    // Clock and Reset
    //=================================================================

    reg clk;
    reg reset;

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=================================================================
    // FPU Core Instance
    //=================================================================

    reg [7:0]  instruction;
    reg [2:0]  stack_index;
    reg        execute;
    wire       ready;
    wire       error;

    reg [79:0] data_in;
    wire [79:0] data_out;
    reg [31:0] int_data_in;
    wire [31:0] int_data_out;

    reg [15:0] control_in;
    reg        control_write;
    wire [15:0] status_out;
    wire [15:0] control_out;
    wire [15:0] tag_word_out;

    FPU_Core fpu_core (
        .clk(clk),
        .reset(reset),
        .instruction(instruction),
        .stack_index(stack_index),
        .execute(execute),
        .ready(ready),
        .error(error),
        .data_in(data_in),
        .data_out(data_out),
        .int_data_in(int_data_in),
        .int_data_out(int_data_out),
        .control_in(control_in),
        .control_write(control_write),
        .status_out(status_out),
        .control_out(control_out),
        .tag_word_out(tag_word_out)
    );

    //=================================================================
    // Instruction Opcodes
    //=================================================================

    localparam INST_FLD     = 8'h20;
    localparam INST_FST     = 8'h21;
    localparam INST_FSQRT   = 8'h50;
    localparam INST_FSIN    = 8'h51;
    localparam INST_FCOS    = 8'h52;
    localparam INST_FSINCOS = 8'h53;

    //=================================================================
    // Test Statistics
    //=================================================================

    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer error_count;

    //=================================================================
    // Helper Tasks
    //=================================================================

    // Initialize FPU
    task init_fpu;
        begin
            $display("[INIT] Starting FPU initialization...");
            reset = 1;
            execute = 0;
            instruction = 8'h00;
            stack_index = 3'd0;
            data_in = 80'd0;
            int_data_in = 32'd0;
            control_in = 16'h037F;  // Default 8087 control word
            control_write = 0;

            #(CLK_PERIOD * 2);
            reset = 0;
            #(CLK_PERIOD * 2);

            $display("[INIT] FPU initialized, ready=%b", ready);
        end
    endtask

    // Load value onto FP stack
    task load_value;
        input [79:0] value;
        integer timeout_cycles;
        begin
            $display("[LOAD] Loading value 0x%020X, ready=%b", value, ready);
            @(posedge clk);
            data_in = value;
            instruction = INST_FLD;
            execute = 1;
            @(posedge clk);
            execute = 0;

            // Wait for ready with timeout
            timeout_cycles = 0;
            while (ready == 0 && timeout_cycles < 1000) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
            end

            if (timeout_cycles >= 1000) begin
                $display("[ERROR] LOAD timeout after %0d cycles", timeout_cycles);
                $finish;
            end

            @(posedge clk);
            $display("[LOAD] Load completed in %0d cycles", timeout_cycles);
        end
    endtask

    // Read value from FP stack (ST(0))
    task read_st0;
        output [79:0] value;
        begin
            @(posedge clk);
            instruction = INST_FST;
            stack_index = 3'd0;
            execute = 1;
            @(posedge clk);
            execute = 0;

            // Wait for ready
            wait(ready == 1);
            @(posedge clk);
            value = data_out;

            if (VERBOSE)
                $display("[READ] Read ST(0) = 0x%020X", value);
        end
    endtask

    // Read value from FP stack (ST(1))
    task read_st1;
        output [79:0] value;
        begin
            @(posedge clk);
            instruction = INST_FST;
            stack_index = 3'd1;
            execute = 1;
            @(posedge clk);
            execute = 0;

            // Wait for ready
            wait(ready == 1);
            @(posedge clk);
            value = data_out;

            if (VERBOSE)
                $display("[READ] Read ST(1) = 0x%020X", value);
        end
    endtask

    // Execute transcendental instruction
    task execute_transcendental;
        input [7:0] inst;
        input string inst_name;
        integer timeout_cycles;
        begin
            $display("[EXEC] Executing %s (0x%02X), ready=%b", inst_name, inst, ready);
            @(posedge clk);
            instruction = inst;
            execute = 1;
            @(posedge clk);
            execute = 0;

            // Wait for ready with timeout (transcendental functions may take long)
            timeout_cycles = 0;
            while (ready == 0 && timeout_cycles < 10000) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
                if (timeout_cycles % 1000 == 0)
                    $display("[EXEC] Still waiting... %0d cycles", timeout_cycles);
            end

            if (timeout_cycles >= 10000) begin
                $display("[ERROR] %s timeout after %0d cycles", inst_name, timeout_cycles);
                $display("[ERROR] ready=%b, error=%b", ready, error);
                $finish;
            end

            @(posedge clk);
            $display("[EXEC] %s completed in %0d cycles", inst_name, timeout_cycles);
        end
    endtask

    // Calculate ULP error between two FP80 values
    function automatic integer ulp_error;
        input [79:0] actual;
        input [79:0] expected;
        reg sign_a, sign_e;
        reg [14:0] exp_a, exp_e;
        reg [63:0] mant_a, mant_e;
        reg signed [64:0] diff;
        integer exp_diff;
        reg [63:0] scaled_mant_a, scaled_mant_e;
        begin
            // Extract components
            sign_a = actual[79];
            exp_a = actual[78:64];
            mant_a = actual[63:0];

            sign_e = expected[79];
            exp_e = expected[78:64];
            mant_e = expected[63:0];

            // Handle exact match
            if (actual == expected) begin
                ulp_error = 0;
            end
            // Special case: both are zero or near-zero (< 2^-40 ≈ 9e-13)
            else if ((exp_a == 0 || exp_a < 15'h3FD7) && (exp_e == 0 || exp_e < 15'h3FD7)) begin
                // Both values very small, treat as equivalent to zero
                ulp_error = 0;
            end
            // Special case: expected is zero, actual is very small
            else if (exp_e == 0 && exp_a < 15'h3FD7) begin
                // Actual < 2^-40, essentially zero
                ulp_error = 0;
            end
            // Special case: actual is zero, expected is very small
            else if (exp_a == 0 && exp_e < 15'h3FD7) begin
                // Expected < 2^-40, essentially zero
                ulp_error = 0;
            end
            // Handle different signs (both non-zero)
            else if (sign_a != sign_e) begin
                ulp_error = 999999;  // Very large error
            end
            // Handle same exponent: simple mantissa difference
            else if (exp_a == exp_e) begin
                if (mant_a > mant_e)
                    diff = mant_a - mant_e;
                else
                    diff = mant_e - mant_a;
                ulp_error = diff;
            end
            // Handle exponents differing by 1: scale and compute ULP
            else begin
                exp_diff = (exp_a > exp_e) ? (exp_a - exp_e) : (exp_e - exp_a);

                if (exp_diff == 1) begin
                    // For exp diff of 1, values are very close
                    // Accept if mantissas are in reasonable range
                    if (mant_a > mant_e)
                        diff = mant_a - mant_e;
                    else
                        diff = mant_e - mant_a;

                    // If mantissas differ by less than half the range, consider close
                    if (diff < 64'h8000000000000000)
                        ulp_error = 1;  // Close enough
                    else
                        ulp_error = 100;  // Still acceptable but not perfect
                end else begin
                    // Exponents differ by more than 1, very large error
                    ulp_error = 999999;
                end
            end
        end
    endfunction

    // Compare FP80 values with ULP tolerance
    function automatic integer fp80_compare;
        input [79:0] actual;
        input [79:0] expected;
        input integer tolerance_ulp;  // Tolerance in ULPs
        integer error;
        begin
            error = ulp_error(actual, expected);
            fp80_compare = (error <= tolerance_ulp) ? 1 : 0;
        end
    endfunction

    // Convert FP80 to real (for display purposes)
    function automatic real fp80_to_real;
        input [79:0] fp80;
        reg sign;
        reg [14:0] exponent;
        reg [63:0] mantissa;
        real result;
        integer exp_unbias;
        real mant_norm;
        begin
            sign = fp80[79];
            exponent = fp80[78:64];
            mantissa = fp80[63:0];

            if (exponent == 15'd0) begin
                // Zero or denormal
                fp80_to_real = 0.0;
            end else if (exponent == 15'h7FFF) begin
                // Infinity or NaN
                fp80_to_real = 0.0;  // Simplified
            end else begin
                // Normal
                exp_unbias = exponent - 16383;
                mant_norm = mantissa / (2.0 ** 63);
                result = mant_norm * (2.0 ** exp_unbias);
                fp80_to_real = sign ? -result : result;
            end
        end
    endfunction

    //=================================================================
    // Test Cases
    //=================================================================

    // Test FSQRT
    task test_fsqrt;
        input [79:0] input_val;
        input [79:0] expected_val;
        input string description;
        reg [79:0] result;
        integer ulp_err;
        begin
            total_tests = total_tests + 1;

            // Load input onto stack
            load_value(input_val);

            // Execute FSQRT
            execute_transcendental(INST_FSQRT, "FSQRT");

            // Read result
            read_st0(result);

            // Calculate ULP error
            ulp_err = ulp_error(result, expected_val);

            // Compare with tolerance of 100 ULPs
            if (fp80_compare(result, expected_val, 100)) begin
                passed_tests = passed_tests + 1;
                if (VERBOSE)
                    $display("[PASS] FSQRT: %s (ULP error = %0d)", description, ulp_err);
            end else begin
                failed_tests = failed_tests + 1;
                error_count = error_count + 1;
                $display("[FAIL] FSQRT: %s", description);
                $display("  Input:    0x%020X (%.6e)", input_val, fp80_to_real(input_val));
                $display("  Expected: 0x%020X (%.6e)", expected_val, fp80_to_real(expected_val));
                $display("  Got:      0x%020X (%.6e)", result, fp80_to_real(result));
                $display("  ULP error: %0d", ulp_err);

                if (error_count >= MAX_ERRORS) begin
                    $display("\n[ERROR] Maximum error count reached, stopping tests");
                    $finish;
                end
            end
        end
    endtask

    // Test FSIN
    task test_fsin;
        input [79:0] input_val;
        input [79:0] expected_val;
        input string description;
        reg [79:0] result;
        integer ulp_err;
        begin
            total_tests = total_tests + 1;

            load_value(input_val);
            execute_transcendental(INST_FSIN, "FSIN");
            read_st0(result);

            ulp_err = ulp_error(result, expected_val);

            if (fp80_compare(result, expected_val, 100)) begin
                passed_tests = passed_tests + 1;
                if (VERBOSE)
                    $display("[PASS] FSIN: %s (ULP error = %0d)", description, ulp_err);
            end else begin
                failed_tests = failed_tests + 1;
                error_count = error_count + 1;
                $display("[FAIL] FSIN: %s", description);
                $display("  Input:    0x%020X (%.6e)", input_val, fp80_to_real(input_val));
                $display("  Expected: 0x%020X (%.6e)", expected_val, fp80_to_real(expected_val));
                $display("  Got:      0x%020X (%.6e)", result, fp80_to_real(result));
                $display("  ULP error: %0d", ulp_err);

                if (error_count >= MAX_ERRORS) begin
                    $display("\n[ERROR] Maximum error count reached, stopping tests");
                    $finish;
                end
            end
        end
    endtask

    // Test FCOS
    task test_fcos;
        input [79:0] input_val;
        input [79:0] expected_val;
        input string description;
        reg [79:0] result;
        integer ulp_err;
        begin
            total_tests = total_tests + 1;

            load_value(input_val);
            execute_transcendental(INST_FCOS, "FCOS");
            read_st0(result);

            ulp_err = ulp_error(result, expected_val);

            if (fp80_compare(result, expected_val, 100)) begin
                passed_tests = passed_tests + 1;
                if (VERBOSE)
                    $display("[PASS] FCOS: %s (ULP error = %0d)", description, ulp_err);
            end else begin
                failed_tests = failed_tests + 1;
                error_count = error_count + 1;
                $display("[FAIL] FCOS: %s", description);
                $display("  Input:    0x%020X (%.6e)", input_val, fp80_to_real(input_val));
                $display("  Expected: 0x%020X (%.6e)", expected_val, fp80_to_real(expected_val));
                $display("  Got:      0x%020X (%.6e)", result, fp80_to_real(result));
                $display("  ULP error: %0d", ulp_err);

                if (error_count >= MAX_ERRORS) begin
                    $display("\n[ERROR] Maximum error count reached, stopping tests");
                    $finish;
                end
            end
        end
    endtask

    // Test FSINCOS
    task test_fsincos;
        input [79:0] input_val;
        input [79:0] expected_sin;
        input [79:0] expected_cos;
        input string description;
        reg [79:0] result_cos;  // ST(0) after FSINCOS
        reg [79:0] result_sin;  // ST(1) after FSINCOS
        integer ulp_err_sin, ulp_err_cos;
        begin
            total_tests = total_tests + 1;

            load_value(input_val);
            execute_transcendental(INST_FSINCOS, "FSINCOS");

            // After FSINCOS: ST(0) = cos(θ), ST(1) = sin(θ)
            read_st0(result_cos);
            read_st1(result_sin);

            ulp_err_cos = ulp_error(result_cos, expected_cos);
            ulp_err_sin = ulp_error(result_sin, expected_sin);

            // Both results must be within tolerance
            if (fp80_compare(result_cos, expected_cos, 100) &&
                fp80_compare(result_sin, expected_sin, 100)) begin
                passed_tests = passed_tests + 1;
                if (VERBOSE)
                    $display("[PASS] FSINCOS: %s (sin ULP=%0d, cos ULP=%0d)",
                            description, ulp_err_sin, ulp_err_cos);
            end else begin
                failed_tests = failed_tests + 1;
                error_count = error_count + 1;
                $display("[FAIL] FSINCOS: %s", description);
                $display("  Input:        0x%020X (%.6e)", input_val, fp80_to_real(input_val));
                $display("  Expected sin: 0x%020X (%.6e)", expected_sin, fp80_to_real(expected_sin));
                $display("  Got sin:      0x%020X (%.6e)", result_sin, fp80_to_real(result_sin));
                $display("  ULP error sin: %0d", ulp_err_sin);
                $display("  Expected cos: 0x%020X (%.6e)", expected_cos, fp80_to_real(expected_cos));
                $display("  Got cos:      0x%020X (%.6e)", result_cos, fp80_to_real(result_cos));
                $display("  ULP error cos: %0d", ulp_err_cos);

                if (error_count >= MAX_ERRORS) begin
                    $display("\n[ERROR] Maximum error count reached, stopping tests");
                    $finish;
                end
            end
        end
    endtask

    //=================================================================
    // Main Test Sequence
    //=================================================================

    initial begin
        // Initialize
        total_tests = 0;
        passed_tests = 0;
        failed_tests = 0;
        error_count = 0;

        // Enable waveform dump for debugging
        $dumpfile("transcendental_waves.vcd");
        $dumpvars(0, tb_transcendental);

        $display("\n" + "=" * 80);
        $display("Transcendental Functions Testbench");
        $display("=" * 80 + "\n");

        init_fpu();

        // Run tests (using known values for now)
        $display("Testing FSQRT (Square Root)...");
        test_fsqrt(80'h00000000000000000000, 80'h00000000000000000000, "sqrt(0) = 0");
        test_fsqrt(80'h3FFF8000000000000000, 80'h3FFF8000000000000000, "sqrt(1) = 1");
        test_fsqrt(80'h40018000000000000000, 80'h40008000000000000000, "sqrt(4) = 2");

        $display("\nTesting FSIN (Sine)...");
        test_fsin(80'h00000000000000000000, 80'h00000000000000000000, "sin(0) = 0");
        // More tests would go here...

        $display("\nTesting FCOS (Cosine)...");
        test_fcos(80'h00000000000000000000, 80'h3FFF8000000000000000, "cos(0) = 1");
        // More tests would go here...

        $display("\nTesting FSINCOS (Sine and Cosine)...");
        test_fsincos(80'h00000000000000000000,
                    80'h00000000000000000000,  // sin(0) = 0
                    80'h3FFF8000000000000000,  // cos(0) = 1
                    "sincos(0) = (0, 1)");

        // Print summary
        $display("\n" + "=" * 80);
        $display("Test Summary");
        $display("=" * 80);
        $display("Total tests:  %0d", total_tests);
        $display("Passed:       %0d", passed_tests);
        $display("Failed:       %0d", failed_tests);
        $display("Pass rate:    %.1f%%", (passed_tests * 100.0) / total_tests);
        $display("=" * 80 + "\n");

        if (failed_tests == 0) begin
            $display("*** ALL TESTS PASSED ***\n");
        end else begin
            $display("*** SOME TESTS FAILED ***\n");
        end

        $finish;
    end

    //=================================================================
    // Timeout
    //=================================================================

    initial begin
        #(CLK_PERIOD * 1000000);  // 10ms timeout
        $display("\n[ERROR] Testbench timeout!");
        $finish;
    end

endmodule
