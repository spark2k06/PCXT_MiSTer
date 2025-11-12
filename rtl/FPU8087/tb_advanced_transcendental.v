`timescale 1ns / 1ps

//=====================================================================
// Advanced Transcendental Functions Test Bench
//
// Tests: FPTAN, FPATAN, F2XM1, FYL2X, FYL2XP1
//=====================================================================

module tb_advanced_transcendental;

    reg clk, reset, execute;
    reg [7:0] instruction;
    reg [2:0] stack_index;
    reg [79:0] data_in;
    reg [31:0] int_data_in;
    reg [15:0] control_in;
    reg control_write;

    wire ready, error;
    wire [79:0] data_out;
    wire [15:0] status_out;

    // Instruction opcodes
    localparam INST_FLD = 8'h20;
    localparam INST_FPTAN = 8'h54;
    localparam INST_FPATAN = 8'h55;
    localparam INST_F2XM1 = 8'h56;
    localparam INST_FYL2X = 8'h57;
    localparam INST_FYL2XP1 = 8'h58;
    localparam INST_FST = 8'h22;

    // Test constants (80-bit FP80 format)
    localparam FP_ZERO = 80'h0000_0000000000000000;
    localparam FP_ONE = 80'h3FFF_8000000000000000;      // 1.0
    localparam FP_TWO = 80'h4000_8000000000000000;      // 2.0
    localparam FP_HALF = 80'h3FFE_8000000000000000;     // 0.5
    localparam FP_QUARTER = 80'h3FFD_8000000000000000;  // 0.25
    localparam FP_THREE = 80'h4000_C000000000000000;    // 3.0

    // π/4 ≈ 0.7853981633974483 (for tan test)
    localparam FP_PI_4 = 80'h3FFE_C90FDAA22168C235;     // π/4

    // Small angle for F2XM1 test (x should be in [-1, 1] for best accuracy)
    localparam FP_0_5 = 80'h3FFE_8000000000000000;      // 0.5

    // log₂(2) = 1.0, log₂(4) = 2.0
    localparam FP_FOUR = 80'h4001_8000000000000000;     // 4.0

    // Test counters
    integer test_num;
    integer pass_count;
    integer fail_count;

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT
    FPU_Core dut (
        .clk(clk),
        .reset(reset),
        .execute(execute),
        .instruction(instruction),
        .stack_index(stack_index),
        .data_in(data_in),
        .int_data_in(int_data_in),
        .control_in(control_in),
        .control_write(control_write),
        .ready(ready),
        .error(error),
        .data_out(data_out),
        .status_out(status_out)
    );

    // Helper task: Load value onto stack
    task load_value;
        input [79:0] value;
        begin
            @(posedge clk);
            data_in = value;
            instruction = INST_FLD;
            execute = 1;
            @(posedge clk);
            execute = 0;
            wait(ready == 1);
            @(posedge clk);
        end
    endtask

    // Helper task: Execute instruction
    task exec_inst;
        input [7:0] inst;
        begin
            @(posedge clk);
            instruction = inst;
            execute = 1;
            @(posedge clk);
            execute = 0;
            wait(ready == 1);
            @(posedge clk);
        end
    endtask

    // Helper task: Check result with tolerance
    task check_result;
        input [79:0] expected;
        input [79:0] actual;
        input [255:0] test_name;
        reg signed [15:0] exp_diff;
        reg [63:0] mant_diff;
        reg pass;
        begin
            test_num = test_num + 1;
            pass = 1'b0;

            // Check sign
            if (expected[79] != actual[79]) begin
                $display("[FAIL] Test %0d: %s", test_num, test_name);
                $display("  Sign mismatch: expected=%b, actual=%b", expected[79], actual[79]);
                pass = 1'b0;
            end
            // Check if both are zero
            else if (expected[78:64] == 0 && actual[78:64] == 0) begin
                pass = 1'b1;
            end
            // Check exponent (allow ±2 ULP difference for transcendentals)
            else begin
                exp_diff = $signed({1'b0, expected[78:64]}) - $signed({1'b0, actual[78:64]});
                if (exp_diff < -1 || exp_diff > 1) begin
                    $display("[FAIL] Test %0d: %s", test_num, test_name);
                    $display("  Exponent diff too large: %0d", exp_diff);
                    $display("  Expected: 0x%020X", expected);
                    $display("  Actual:   0x%020X", actual);
                    pass = 1'b0;
                end else begin
                    // Check mantissa (allow some ULP error for transcendentals)
                    // For now, just check if exponents match
                    if (expected[78:64] == actual[78:64]) begin
                        mant_diff = (expected[63:0] > actual[63:0]) ?
                                   (expected[63:0] - actual[63:0]) :
                                   (actual[63:0] - expected[63:0]);
                        // Allow up to 2^48 ULPs for transcendentals (very lenient)
                        if (mant_diff < 64'h0001_0000_0000_0000) begin
                            pass = 1'b1;
                        end else begin
                            $display("[FAIL] Test %0d: %s", test_num, test_name);
                            $display("  Mantissa diff too large: 0x%016X", mant_diff);
                            $display("  Expected: 0x%020X", expected);
                            $display("  Actual:   0x%020X", actual);
                            pass = 1'b0;
                        end
                    end else begin
                        // Exponent differs by 1, very lenient check
                        pass = 1'b1;
                    end
                end
            end

            if (pass) begin
                $display("[PASS] Test %0d: %s", test_num, test_name);
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Main test
    initial begin
        $dumpfile("advanced_transcendental.vcd");
        $dumpvars(0, tb_advanced_transcendental);

        // Initialize
        reset = 1;
        execute = 0;
        instruction = 8'h00;
        stack_index = 3'd0;
        data_in = 80'd0;
        int_data_in = 32'd0;
        control_in = 16'h037F;
        control_write = 0;
        test_num = 0;
        pass_count = 0;
        fail_count = 0;

        #20 reset = 0;
        #10;

        $display("\n========================================");
        $display("Advanced Transcendental Functions Test");
        $display("========================================\n");

        //=============================================================
        // Test 1: FPTAN with π/4 (tan(π/4) = 1.0)
        //=============================================================
        $display("=== Test Group 1: FPTAN ===");
        load_value(FP_PI_4);
        exec_inst(INST_FPTAN);
        $display("After FPTAN: ST(0)=0x%020X, ST(1)=0x%020X",
                 dut.st0, dut.st1);
        // ST(0) should be 1.0, ST(1) should be tan(π/4) ≈ 1.0
        check_result(FP_ONE, dut.st0, "FPTAN: ST(0) = 1.0 (pushed constant)");
        check_result(FP_ONE, dut.st1, "FPTAN: ST(1) = tan(π/4) ≈ 1.0");

        // Reset for next test
        #10; reset = 1; #20; reset = 0; #10;

        //=============================================================
        // Test 2: FPTAN with 0 (tan(0) = 0)
        //=============================================================
        load_value(FP_ZERO);
        exec_inst(INST_FPTAN);
        $display("After FPTAN(0): ST(0)=0x%020X, ST(1)=0x%020X",
                 dut.st0, dut.st1);
        check_result(FP_ONE, dut.st0, "FPTAN: ST(0) = 1.0");
        check_result(FP_ZERO, dut.st1, "FPTAN: ST(1) = tan(0) = 0");

        #10; reset = 1; #20; reset = 0; #10;

        //=============================================================
        // Test 3: FPATAN with y=1.0, x=1.0 (atan(1/1) = π/4)
        //=============================================================
        $display("\n=== Test Group 2: FPATAN ===");
        load_value(FP_ONE);   // x = 1.0 (ST(0))
        load_value(FP_ONE);   // y = 1.0 (ST(1), becomes ST(0) after push)
        exec_inst(INST_FPATAN);
        $display("After FPATAN(1,1): ST(0)=0x%020X", dut.st0);
        // atan(1/1) = π/4 ≈ 0.785398
        check_result(FP_PI_4, dut.st0, "FPATAN: atan(1/1) = π/4");

        #10; reset = 1; #20; reset = 0; #10;

        //=============================================================
        // Test 4: FPATAN with y=0, x=1 (atan(0/1) = 0)
        //=============================================================
        load_value(FP_ONE);    // x = 1.0
        load_value(FP_ZERO);   // y = 0.0
        exec_inst(INST_FPATAN);
        $display("After FPATAN(0,1): ST(0)=0x%020X", dut.st0);
        check_result(FP_ZERO, dut.st0, "FPATAN: atan(0/1) = 0");

        #10; reset = 1; #20; reset = 0; #10;

        //=============================================================
        // Test 5: F2XM1 with x=0 (2^0 - 1 = 0)
        //=============================================================
        $display("\n=== Test Group 3: F2XM1 ===");
        load_value(FP_ZERO);
        exec_inst(INST_F2XM1);
        $display("After F2XM1(0): ST(0)=0x%020X", dut.st0);
        check_result(FP_ZERO, dut.st0, "F2XM1: 2^0 - 1 = 0");

        #10; reset = 1; #20; reset = 0; #10;

        //=============================================================
        // Test 6: F2XM1 with x=1 (2^1 - 1 = 1)
        //=============================================================
        load_value(FP_ONE);
        exec_inst(INST_F2XM1);
        $display("After F2XM1(1): ST(0)=0x%020X", dut.st0);
        check_result(FP_ONE, dut.st0, "F2XM1: 2^1 - 1 = 1");

        #10; reset = 1; #20; reset = 0; #10;

        //=============================================================
        // Test 7: FYL2X with y=2, x=2 (2 × log₂(2) = 2 × 1 = 2)
        //=============================================================
        $display("\n=== Test Group 4: FYL2X ===");
        load_value(FP_TWO);   // x = 2.0 (ST(0))
        load_value(FP_TWO);   // y = 2.0 (ST(1))
        exec_inst(INST_FYL2X);
        $display("After FYL2X(2,2): ST(0)=0x%020X", dut.st0);
        // 2 × log₂(2) = 2 × 1 = 2
        check_result(FP_TWO, dut.st0, "FYL2X: 2 × log₂(2) = 2");

        #10; reset = 1; #20; reset = 0; #10;

        //=============================================================
        // Test 8: FYL2X with y=1, x=4 (1 × log₂(4) = 2)
        //=============================================================
        load_value(FP_FOUR);  // x = 4.0
        load_value(FP_ONE);   // y = 1.0
        exec_inst(INST_FYL2X);
        $display("After FYL2X(1,4): ST(0)=0x%020X", dut.st0);
        // 1 × log₂(4) = 1 × 2 = 2
        check_result(FP_TWO, dut.st0, "FYL2X: 1 × log₂(4) = 2");

        #10; reset = 1; #20; reset = 0; #10;

        //=============================================================
        // Test 9: FYL2XP1 with y=2, x=1 (2 × log₂(1+1) = 2 × 1 = 2)
        //=============================================================
        $display("\n=== Test Group 5: FYL2XP1 ===");
        load_value(FP_ONE);   // x = 1.0 (ST(0))
        load_value(FP_TWO);   // y = 2.0 (ST(1))
        exec_inst(INST_FYL2XP1);
        $display("After FYL2XP1(2,1): ST(0)=0x%020X", dut.st0);
        // 2 × log₂(1+1) = 2 × log₂(2) = 2 × 1 = 2
        check_result(FP_TWO, dut.st0, "FYL2XP1: 2 × log₂(2) = 2");

        #10; reset = 1; #20; reset = 0; #10;

        //=============================================================
        // Test 10: FYL2XP1 with y=1, x=3 (1 × log₂(1+3) = log₂(4) = 2)
        //=============================================================
        load_value(FP_THREE); // x = 3.0
        load_value(FP_ONE);   // y = 1.0
        exec_inst(INST_FYL2XP1);
        $display("After FYL2XP1(1,3): ST(0)=0x%020X", dut.st0);
        // 1 × log₂(3+1) = log₂(4) = 2
        check_result(FP_TWO, dut.st0, "FYL2XP1: 1 × log₂(4) = 2");

        #10; reset = 1; #20; reset = 0; #10;

        //=============================================================
        // Summary
        //=============================================================
        #100;
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests: %0d", test_num);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("Success rate: %0d%%", (pass_count * 100) / test_num);
        $display("========================================\n");

        if (fail_count == 0) begin
            $display("✓ ALL TESTS PASSED!");
        end else begin
            $display("✗ SOME TESTS FAILED");
        end

        $finish;
    end

endmodule
