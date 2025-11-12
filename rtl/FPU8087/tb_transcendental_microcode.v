`timescale 1ns / 1ps

//=====================================================================
// Testbench for Microcode Transcendental Functions
//
// Tests FSIN and FCOS microcode implementations with:
// - Known test vectors
// - Boundary conditions
// - Accuracy verification against expected values
//=====================================================================

module tb_transcendental_microcode;

    // Clock and reset
    reg clk;
    reg reset;

    // Control signals
    reg start;
    reg [3:0] program_index;
    reg [79:0] operand_a;
    reg [79:0] operand_b;

    // Output signals
    wire micro_done;
    wire [79:0] micro_result;

    // Microsequencer to arithmetic unit wires
    wire arith_enable;
    wire [4:0] arith_op;
    wire [1:0] arith_rounding;
    wire [79:0] arith_a, arith_b;
    wire signed [15:0] arith_int16_in_wire;
    wire signed [31:0] arith_int32_in_wire;
    wire [31:0] arith_fp32_in_wire;
    wire [63:0] arith_fp64_in_wire;
    wire arith_done;
    wire [79:0] arith_result;

    // Tie unused outputs to constant values
    assign arith_int16_in_wire = 16'sd0;
    assign arith_int32_in_wire = 32'sd0;
    assign arith_fp32_in_wire = 32'd0;
    assign arith_fp64_in_wire = 64'd0;

    // Instantiate FPU_ArithmeticUnit
    FPU_ArithmeticUnit arith_unit (
        .clk(clk),
        .reset(reset),
        .enable(arith_enable),
        .operation(arith_op),
        .operand_a(arith_a),
        .operand_b(arith_b),
        .rounding_mode(2'b00),
        .result(arith_result),
        .done(arith_done),
        .cc_less(),
        .cc_equal(),
        .cc_greater(),
        .cc_unordered()
    );

    MicroSequencer_Extended microseq (
        .clk(clk),
        .reset(reset),
        .start(start),
        .micro_program_index(program_index),
        .data_in(operand_a),
        .instruction_complete(micro_done),
        .data_out(micro_result),

        // Debug outputs
        .debug_temp_result(),
        .debug_temp_fp_a(),
        .debug_temp_fp_b(),

        // Arithmetic unit interface
        .arith_operation(arith_op),
        .arith_enable(arith_enable),
        .arith_rounding_mode(arith_rounding),
        .arith_operand_a(arith_a),
        .arith_operand_b(arith_b),
        .arith_int16_in(arith_int16_in_wire),
        .arith_int32_in(arith_int32_in_wire),
        .arith_fp32_in(arith_fp32_in_wire),
        .arith_fp64_in(arith_fp64_in_wire),
        .arith_result(arith_result),
        .arith_int16_out(),
        .arith_int32_out(),
        .arith_fp32_out(),
        .arith_fp64_out(),
        .arith_done(arith_done),
        .arith_cc_less(1'b0),
        .arith_cc_equal(1'b0),
        .arith_cc_greater(1'b0),
        .arith_cc_unordered(1'b0),

        // Stack interface (unused)
        .stack_push_req(),
        .stack_pop_req(),
        .stack_read_sel(),
        .stack_write_sel(),
        .stack_write_en(),
        .stack_write_data(),
        .stack_read_data(80'd0),
        .stack_op_done(1'b1),

        // Status/Control (unused)
        .status_word_in(16'd0),
        .status_word_out(),
        .status_word_write(),
        .control_word_in(16'd0),
        .control_word_out(),
        .control_word_write()
    );

    // Clock generation: 10ns period (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test variables
    integer test_count;
    integer pass_count;
    integer fail_count;
    real expected_real, result_real, error;
    real max_allowed_error;

    // Helper task: Convert FP80 to real for comparison
    task fp80_to_real;
        input [79:0] fp80;
        output real result;
        reg sign;
        reg [14:0] exponent;
        reg [63:0] mantissa;
        integer exp_unbiased;
        real mant_real;
        begin
            sign = fp80[79];
            exponent = fp80[78:64];
            mantissa = fp80[63:0];

            // Handle special cases
            if (exponent == 15'h7FFF) begin
                result = (mantissa == 64'd0) ? (sign ? -1.0e308 : 1.0e308) : 0.0;  // Inf or NaN
            end else if (exponent == 15'd0 && mantissa == 64'd0) begin
                result = 0.0;  // Zero
            end else begin
                // Normal/denormal number
                exp_unbiased = exponent - 16383;
                mant_real = mantissa / (2.0 ** 63.0);  // Normalize mantissa (bit 63 is integer bit)
                result = mant_real * (2.0 ** exp_unbiased);
                if (sign) result = -result;
            end
        end
    endtask

    // Helper task: Convert real to FP80
    task real_to_fp80;
        input real value;
        output [79:0] fp80;
        reg sign;
        reg [14:0] exponent;
        reg [63:0] mantissa;
        real abs_val, temp;
        integer exp_val, i;
        begin
            if (value == 0.0) begin
                fp80 = 80'd0;
            end else begin
                sign = (value < 0.0);
                abs_val = sign ? -value : value;

                // Find exponent
                exp_val = 0;
                temp = abs_val;
                if (temp >= 2.0) begin
                    while (temp >= 2.0) begin
                        temp = temp / 2.0;
                        exp_val = exp_val + 1;
                    end
                end else begin
                    while (temp < 1.0) begin
                        temp = temp * 2.0;
                        exp_val = exp_val - 1;
                    end
                end

                // temp is now in [1.0, 2.0)
                exponent = exp_val + 16383;
                mantissa = $rtoi(temp * (2.0 ** 63.0));

                fp80 = {sign, exponent, mantissa};
            end
        end
    endtask

    // Test execution task
    task test_transcendental;
        input [3:0] prog_idx;
        input [79:0] input_val;
        input real expected;
        input real tolerance;
        input [80*8-1:0] test_name;
        real result_val;
        integer timeout;
        begin
            test_count = test_count + 1;

            $display("\n========================================");
            $display("Test %0d: %s", test_count, test_name);
            $display("Input: 0x%020X", input_val);

            // Start microcode execution
            operand_a = input_val;
            operand_b = 80'd0;
            program_index = prog_idx;
            start = 1;
            @(posedge clk);
            start = 0;

            // Wait for completion with timeout
            timeout = 0;
            while (!micro_done && timeout < 100000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 100000) begin
                $display("✗ TIMEOUT after %0d cycles", timeout);
                fail_count = fail_count + 1;
            end else begin
                $display("Completed in %0d cycles", timeout);
                $display("Result: 0x%020X", micro_result);

                // Convert result to real
                fp80_to_real(micro_result, result_val);
                error = result_val - expected;
                if (error < 0.0) error = -error;

                $display("Expected: %f", expected);
                $display("Got:      %f", result_val);
                $display("Error:    %e", error);

                if (error <= tolerance) begin
                    $display("✓ PASS (error within tolerance %e)", tolerance);
                    pass_count = pass_count + 1;
                end else begin
                    $display("✗ FAIL (error exceeds tolerance %e)", tolerance);
                    fail_count = fail_count + 1;
                end
            end
        end
    endtask

    // Main test sequence
    initial begin
        $display("\n");
        $display("========================================");
        $display("Transcendental Function Microcode Tests");
        $display("========================================");

        // Initialize
        reset = 1;
        start = 0;
        program_index = 0;
        operand_a = 0;
        operand_b = 0;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        // Reset sequence
        repeat(5) @(posedge clk);
        reset = 0;
        repeat(5) @(posedge clk);

        // Test vectors for FSIN (program 5)
        // Note: CORDIC accuracy is typically 1e-6 to 1e-9
        max_allowed_error = 1.0e-6;

        // FSIN Tests
        // Note: FP80 format: [79:Sign][78:64:Exponent][63:Integer][62:0:Fraction]
        $display("\n========================================");
        $display("FSIN Tests (Program 5)");
        $display("========================================");

        // sin(0.0) = 0.0
        test_transcendental(4'd5, 80'h0000_0000000000000000, 0.0, max_allowed_error, "sin(0.0)");

        // sin(π/6) ≈ 0.5: π/6 ≈ 0.523598776 = 0x3FFE860A91C16B9B3
        test_transcendental(4'd5, 80'h3FFE860A91C16B9B3000, 0.5, max_allowed_error, "sin(π/6) ≈ 0.5");

        // sin(π/4) ≈ 0.707: π/4 ≈ 0.785398163 = 0x3FFEC90FDAA22168C
        test_transcendental(4'd5, 80'h3FFEC90FDAA22168C000, 0.707106781, max_allowed_error, "sin(π/4) ≈ √2/2");

        // sin(π/2) = 1.0: π/2 ≈ 1.570796327 = 0x3FFFC90FDAA22168C
        test_transcendental(4'd5, 80'h3FFFC90FDAA22168C000, 1.0, max_allowed_error, "sin(π/2) = 1.0");

        // sin(π) ≈ 0.0: π ≈ 3.141592654 = 0x4000C90FDAA22168C
        test_transcendental(4'd5, 80'h4000C90FDAA22168C000, 0.0, max_allowed_error, "sin(π) ≈ 0.0");

        // FCOS Tests
        $display("\n========================================");
        $display("FCOS Tests (Program 6)");
        $display("========================================");

        // cos(0.0) = 1.0
        test_transcendental(4'd6, 80'h0000_0000000000000000, 1.0, max_allowed_error, "cos(0.0) = 1.0");

        // cos(π/6) ≈ 0.866: π/6 ≈ 0.523598776
        test_transcendental(4'd6, 80'h3FFE860A91C16B9B3000, 0.866025404, max_allowed_error, "cos(π/6) ≈ √3/2");

        // cos(π/4) ≈ 0.707: π/4 ≈ 0.785398163
        test_transcendental(4'd6, 80'h3FFEC90FDAA22168C000, 0.707106781, max_allowed_error, "cos(π/4) ≈ √2/2");

        // cos(π/2) ≈ 0.0: π/2 ≈ 1.570796327
        test_transcendental(4'd6, 80'h3FFFC90FDAA22168C000, 0.0, max_allowed_error, "cos(π/2) ≈ 0.0");

        // cos(π) = -1.0: π ≈ 3.141592654
        test_transcendental(4'd6, 80'h4000C90FDAA22168C000, -1.0, max_allowed_error, "cos(π) = -1.0");

        // Summary
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests:  %0d", test_count);
        $display("Passed:       %0d", pass_count);
        $display("Failed:       %0d", fail_count);

        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
        end else begin
            $display("\n*** SOME TESTS FAILED ***\n");
        end

        $display("========================================\n");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #10000000;  // 10ms timeout
        $display("\n*** ERROR: Global timeout reached ***\n");
        $finish;
    end

endmodule
