`timescale 1ns / 1ps

//=====================================================================
// Hybrid Execution Testbench
//
// Tests both direct execution (FPU_Core) and microcode execution
// (MicroSequencer_Extended) side-by-side to validate:
// 1. Both produce identical results
// 2. Interface compatibility
// 3. Timing characteristics
//=====================================================================

module tb_hybrid_execution();

    //=================================================================
    // Clock and Reset
    //=================================================================

    reg clk;
    reg reset;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz clock
    end

    //=================================================================
    // Test Control
    //=================================================================

    integer test_count;
    integer pass_count;
    integer fail_count;

    //=================================================================
    // FPU_ArithmeticUnit Instance (Shared Resource)
    //=================================================================

    // Direct mode control (from testbench)
    reg [4:0]  direct_arith_operation;
    reg        direct_arith_enable;
    reg [1:0]  direct_arith_rounding_mode;
    reg [79:0] direct_arith_operand_a;
    reg [79:0] direct_arith_operand_b;
    reg signed [15:0] direct_arith_int16_in;
    reg signed [31:0] direct_arith_int32_in;
    reg [31:0] direct_arith_fp32_in;
    reg [63:0] direct_arith_fp64_in;

    // Micro mode control (from microsequencer)
    wire [4:0]  micro_arith_operation;
    wire        micro_arith_enable;
    wire [1:0]  micro_arith_rounding_mode;
    wire [79:0] micro_arith_operand_a;
    wire [79:0] micro_arith_operand_b;
    wire signed [15:0] micro_arith_int16_in;
    wire signed [31:0] micro_arith_int32_in;
    wire [31:0] micro_arith_fp32_in;
    wire [63:0] micro_arith_fp64_in;

    // Mode selector
    reg use_microcode_path;

    // Multiplexed signals to arithmetic unit
    wire [4:0]  arith_operation    = use_microcode_path ? micro_arith_operation    : direct_arith_operation;
    wire        arith_enable       = use_microcode_path ? micro_arith_enable       : direct_arith_enable;
    wire [1:0]  arith_rounding_mode= use_microcode_path ? micro_arith_rounding_mode: direct_arith_rounding_mode;
    wire [79:0] arith_operand_a    = use_microcode_path ? micro_arith_operand_a    : direct_arith_operand_a;
    wire [79:0] arith_operand_b    = use_microcode_path ? micro_arith_operand_b    : direct_arith_operand_b;
    wire signed [15:0] arith_int16_in = use_microcode_path ? micro_arith_int16_in : direct_arith_int16_in;
    wire signed [31:0] arith_int32_in = use_microcode_path ? micro_arith_int32_in : direct_arith_int32_in;
    wire [31:0] arith_fp32_in      = use_microcode_path ? micro_arith_fp32_in     : direct_arith_fp32_in;
    wire [63:0] arith_fp64_in      = use_microcode_path ? micro_arith_fp64_in     : direct_arith_fp64_in;

    // Arithmetic unit outputs
    wire [79:0] arith_result;
    wire signed [15:0] arith_int16_out;
    wire signed [31:0] arith_int32_out;
    wire [31:0] arith_fp32_out;
    wire [63:0] arith_fp64_out;
    wire        arith_done;
    wire        arith_cc_less;
    wire        arith_cc_equal;
    wire        arith_cc_greater;
    wire        arith_cc_unordered;
    wire        arith_invalid;
    wire        arith_denormal;
    wire        arith_zero_divide;
    wire        arith_overflow;
    wire        arith_underflow;
    wire        arith_inexact;

    // Debug: Monitor arithmetic unit inputs
    always @(posedge clk) begin
        if (arith_enable) begin
            $display("[ARITH_UNIT] enable=1, op=%0d, a=0x%020X, b=0x%020X, mode=%b",
                     arith_operation, arith_operand_a, arith_operand_b, use_microcode_path);
        end
        if (arith_done) begin
            $display("[ARITH_UNIT] done=1, result=0x%020X", arith_result);
        end
    end

    FPU_ArithmeticUnit arith_unit (
        .clk(clk),
        .reset(reset),
        .operation(arith_operation),
        .enable(arith_enable),
        .rounding_mode(arith_rounding_mode),
        .operand_a(arith_operand_a),
        .operand_b(arith_operand_b),
        .int16_in(arith_int16_in),
        .int32_in(arith_int32_in),
        .uint64_in(64'd0),
        .uint64_sign_in(1'b0),
        .fp32_in(arith_fp32_in),
        .fp64_in(arith_fp64_in),
        .result(arith_result),
        .result_secondary(),
        .has_secondary(),
        .int16_out(arith_int16_out),
        .int32_out(arith_int32_out),
        .uint64_out(),
        .uint64_sign_out(),
        .fp32_out(arith_fp32_out),
        .fp64_out(arith_fp64_out),
        .done(arith_done),
        .cc_less(arith_cc_less),
        .cc_equal(arith_cc_equal),
        .cc_greater(arith_cc_greater),
        .cc_unordered(arith_cc_unordered),
        .flag_invalid(arith_invalid),
        .flag_denormal(arith_denormal),
        .flag_zero_divide(arith_zero_divide),
        .flag_overflow(arith_overflow),
        .flag_underflow(arith_underflow),
        .flag_inexact(arith_inexact)
    );

    //=================================================================
    // MicroSequencer_Extended Instance
    //=================================================================

    reg        micro_start;
    reg [3:0]  micro_program_index;
    reg [79:0] micro_data_in;
    wire [79:0] micro_data_out;
    wire       micro_instruction_complete;

    // Microsequencer's debug outputs (connected to internal registers)
    wire [79:0] micro_temp_result;
    wire [79:0] micro_temp_fp_a;
    wire [79:0] micro_temp_fp_b;

    MicroSequencer_Extended microseq (
        .clk(clk),
        .reset(reset),
        .start(micro_start),
        .micro_program_index(micro_program_index),
        .data_in(micro_data_in),
        .data_out(micro_data_out),
        .instruction_complete(micro_instruction_complete),

        // Debug outputs
        .debug_temp_result(micro_temp_result),
        .debug_temp_fp_a(micro_temp_fp_a),
        .debug_temp_fp_b(micro_temp_fp_b),

        // Connect to multiplexed arithmetic unit signals
        .arith_operation(micro_arith_operation),
        .arith_enable(micro_arith_enable),
        .arith_rounding_mode(micro_arith_rounding_mode),
        .arith_operand_a(micro_arith_operand_a),
        .arith_operand_b(micro_arith_operand_b),
        .arith_int16_in(micro_arith_int16_in),
        .arith_int32_in(micro_arith_int32_in),
        .arith_fp32_in(micro_arith_fp32_in),
        .arith_fp64_in(micro_arith_fp64_in),
        .arith_result(arith_result),
        .arith_int16_out(arith_int16_out),
        .arith_int32_out(arith_int32_out),
        .arith_fp32_out(arith_fp32_out),
        .arith_fp64_out(arith_fp64_out),
        .arith_done(arith_done),
        .arith_cc_less(arith_cc_less),
        .arith_cc_equal(arith_cc_equal),
        .arith_cc_greater(arith_cc_greater),
        .arith_cc_unordered(arith_cc_unordered),

        // Stack interface (simplified - not used in these tests)
        .stack_push_req(),
        .stack_pop_req(),
        .stack_read_sel(),
        .stack_write_sel(),
        .stack_write_en(),
        .stack_write_data(),
        .stack_read_data(80'd0),
        .stack_op_done(1'b1),

        // Status/Control interface (simplified)
        .status_word_in(16'd0),
        .status_word_out(),
        .status_word_write(),
        .control_word_in(16'h037F),
        .control_word_out(),
        .control_word_write()
    );

    // Access internal registers for test setup (would need to expose these)
    // For now, we'll use external setup

    //=================================================================
    // Test Tasks
    //=================================================================

    task test_arithmetic_operation;
        input [79:0] operand_a_val;
        input [79:0] operand_b_val;
        input [4:0]  operation;
        input [79:0] expected_result;
        input [200*8:1] test_name;

        reg [79:0] direct_result;
        reg [79:0] micro_result;
        integer cycles;
        reg sqrt_test;  // Flag for SQRT testing

        begin
            $display("\n----------------------------------------");
            $display("Test: %0s", test_name);
            $display("Operation: %0d, A=0x%020X, B=0x%020X", operation, operand_a_val, operand_b_val);

            sqrt_test = (operation == 5'd12);  // SQRT operation

            //=============================================================
            // Method 1: Direct Arithmetic Unit Call
            //=============================================================
            if (sqrt_test) begin
                $display("\n[Direct Execution]");
                $display("  SKIPPED: SQRT hardware removed (microcode-only)");
                $display("  Note: FPU_SQRT_Newton eliminated for 22% area reduction");
                direct_result = 80'h0;  // Not tested
            end else begin
                $display("\n[Direct Execution]");

                use_microcode_path = 1'b0;  // Select direct mode

                @(posedge clk);
                direct_arith_operand_a <= operand_a_val;
                direct_arith_operand_b <= operand_b_val;
                direct_arith_operation <= operation;
                direct_arith_enable <= 1'b1;
                direct_arith_rounding_mode <= 2'b00;  // Round to nearest

                @(posedge clk);
                direct_arith_enable <= 1'b0;

                // Wait for completion
                cycles = 0;
                while (!arith_done && cycles < 2000) begin
                    @(posedge clk);
                    cycles = cycles + 1;
                end

                if (arith_done) begin
                    direct_result = arith_result;
                    $display("  Direct result: 0x%020X (cycles=%0d)", direct_result, cycles);
                end else begin
                    $display("  ERROR: Direct execution timeout!");
                    fail_count = fail_count + 1;
                    test_count = test_count + 1;
                    disable test_arithmetic_operation;  // Exit task
                end

                // Let arithmetic unit settle
                repeat(5) @(posedge clk);
            end

            //=============================================================
            // Method 2: Microcode Execution
            //=============================================================
            // Now with full operand loading via MOP_LOAD_A/MOP_LOAD_B

            $display("\n[Microcode Execution]");
            $display("  Loading operands A=0x%020X, B=0x%020X", operand_a_val, operand_b_val);

            use_microcode_path = 1'b1;  // Select microcode mode

            // Map operation to program index
            // 0=ADD, 1=SUB, 2=MUL, 3=DIV, 4=SQRT
            case (operation)
                5'd0: micro_program_index = 4'd0;  // FADD
                5'd1: micro_program_index = 4'd1;  // FSUB
                5'd2: micro_program_index = 4'd2;  // FMUL
                5'd3: micro_program_index = 4'd3;  // FDIV
                5'd12: micro_program_index = 4'd4; // FSQRT
                default: micro_program_index = 4'd0;
            endcase

            // Provide operand A on data bus for LOAD_A instruction
            micro_data_in <= operand_a_val;

            @(posedge clk);
            micro_start <= 1'b1;

            @(posedge clk);
            micro_start <= 1'b0;

            // Wait for LOAD_A to execute (2-3 cycles)
            repeat(3) @(posedge clk);

            // Now provide operand B for LOAD_B instruction
            micro_data_in <= operand_b_val;

            // Wait a bit for LOAD_B to execute
            repeat(2) @(posedge clk);

            // Wait for completion
            // Note: SQRT needs ~1425 cycles + microcode overhead
            cycles = 0;
            while (!micro_instruction_complete && cycles < 2500) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            if (micro_instruction_complete) begin
                micro_result = micro_temp_result;
                $display("  Microcode complete (cycles=%0d)", cycles);
                $display("  Microcode result: 0x%020X", micro_result);
            end else begin
                $display("  ERROR: Microcode execution timeout!");
                fail_count = fail_count + 1;
                test_count = test_count + 1;
                disable test_arithmetic_operation;  // Exit task
            end

            //=============================================================
            // Comparison
            //=============================================================
            $display("\n[Results]");
            $display("  Expected:  0x%020X", expected_result);
            if (!sqrt_test) begin
                $display("  Direct:    0x%020X", direct_result);
            end
            $display("  Microcode: 0x%020X", micro_result);

            if (sqrt_test) begin
                // SQRT: Only test microcode path (hardware removed)
                if (micro_result == expected_result) begin
                    $display("  ✓ PASS: Microcode execution matches expected (hardware-free)");
                    pass_count = pass_count + 1;
                end else begin
                    $display("  ✗ FAIL: Microcode execution mismatch!");
                    fail_count = fail_count + 1;
                end
            end else begin
                // Other operations: Test both paths
                if (direct_result == expected_result && micro_result == expected_result) begin
                    $display("  ✓ PASS: Both execution paths match expected");
                    pass_count = pass_count + 1;
                end else begin
                    if (direct_result != expected_result) begin
                        $display("  ✗ FAIL: Direct execution mismatch!");
                    end
                    if (micro_result != expected_result) begin
                        $display("  ✗ FAIL: Microcode execution mismatch!");
                    end
                    fail_count = fail_count + 1;
                end
            end

            test_count = test_count + 1;
        end
    endtask

    //=================================================================
    // Test Stimulus
    //=================================================================

    initial begin
        // Enable waveform dumping for debug
        $dumpfile("hybrid_execution.vcd");
        $dumpvars(0, tb_hybrid_execution);

        $display("\n========================================");
        $display("Hybrid Execution Validation Testbench");
        $display("========================================\n");

        // Initialize
        reset = 1;
        micro_start = 0;
        micro_program_index = 0;
        micro_data_in = 0;
        use_microcode_path = 0;
        direct_arith_enable = 0;
        direct_arith_operation = 0;
        direct_arith_operand_a = 0;
        direct_arith_operand_b = 0;
        direct_arith_rounding_mode = 0;
        direct_arith_int16_in = 0;
        direct_arith_int32_in = 0;
        direct_arith_fp32_in = 0;
        direct_arith_fp64_in = 0;

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        // Reset
        repeat(10) @(posedge clk);
        reset = 0;
        repeat(10) @(posedge clk);

        //=============================================================
        // Test 1: FP Addition (3.14159... + 2.71 = 5.85159...)
        //=============================================================
        test_arithmetic_operation(
            80'h4000C90FDAA22168C000,  // 3.14159265358979... (pi approximation)
            80'h4000AD70A3D70A3D7000,  // 2.71 (FIXED: correct encoding)
            5'd0,                       // OP_ADD
            80'h4001BB403F3C95D31800,  // 5.85159... (FIXED: correct sum)
            "FP Addition: 3.14159 + 2.71"
        );

        //=============================================================
        // Test 2: FP Subtraction (5.0 - 2.0 = 3.0)
        //=============================================================
        test_arithmetic_operation(
            80'h4001A000000000000000,  // 5.0
            80'h40008000000000000000,  // 2.0
            5'd1,                       // OP_SUB
            80'h4000C000000000000000,  // 3.0
            "FP Subtraction: 5.0 - 2.0"
        );

        //=============================================================
        // Test 3: FP Multiplication (3.0 * 4.0 = 12.0)
        //=============================================================
        test_arithmetic_operation(
            80'h4000C000000000000000,  // 3.0
            80'h40018000000000000000,  // 4.0 (FIXED: added integer bit)
            5'd2,                       // OP_MUL
            80'h4002C000000000000000,  // 12.0
            "FP Multiplication: 3.0 * 4.0"
        );

        //=============================================================
        // Test 4: FP Division (12.0 / 3.0 = 4.0)
        //=============================================================
        test_arithmetic_operation(
            80'h4002C000000000000000,  // 12.0
            80'h4000C000000000000000,  // 3.0
            5'd3,                       // OP_DIV
            80'h40018000000000000000,  // 4.0 (FIXED: added integer bit)
            "FP Division: 12.0 / 3.0"
        );

        //=============================================================
        // Test 5: Square Root (16.0 → 4.0)
        //=============================================================
        test_arithmetic_operation(
            80'h40038000000000000000,  // 16.0 (FIXED: added integer bit)
            80'h00000000000000000000,  // (unused for SQRT)
            5'd12,                      // OP_SQRT
            80'h40018000000000000000,  // 4.0 (FIXED: added integer bit)
            "Square Root: sqrt(16.0)"
        );

        //=============================================================
        // Summary
        //=============================================================
        repeat(20) @(posedge clk);

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

    //=================================================================
    // Timeout Watchdog
    //=================================================================

    initial begin
        #1000000;  // 1ms timeout
        $display("\n*** ERROR: Simulation timeout! ***\n");
        $finish;
    end

endmodule
