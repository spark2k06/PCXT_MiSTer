`timescale 1ns / 1ps

//=================================================================
// Comparison Instructions Test
//
// Tests: FCOM, FCOMP, FCOMPP, FTST, FXAM
//=================================================================

module tb_fcom;

    reg clk;
    reg reset;
    reg execute;
    reg [7:0] instruction;
    reg [2:0] stack_index;
    reg [79:0] data_in;
    reg [31:0] int_data_in;
    reg [15:0] control_in;
    reg control_write;

    wire ready;
    wire error;
    wire [79:0] data_out;
    wire [15:0] status_out;

    // Instruction opcodes
    localparam INST_FLD   = 8'h20;
    localparam INST_FCOM  = 8'h60;
    localparam INST_FCOMP = 8'h61;
    localparam INST_FCOMPP = 8'h62;
    localparam INST_FTST  = 8'h63;
    localparam INST_FXAM  = 8'h64;

    // Test values (FP80 format)
    localparam FP_ZERO     = 80'h0000_0000000000000000;  // +0.0
    localparam FP_ONE      = 80'h3FFF_8000000000000000;  // +1.0
    localparam FP_TWO      = 80'h4000_8000000000000000;  // +2.0
    localparam FP_HALF     = 80'h3FFE_8000000000000000;  // +0.5
    localparam FP_NEG_ONE  = 80'hBFFF_8000000000000000;  // -1.0
    localparam FP_INF      = 80'h7FFF_8000000000000000;  // +Infinity
    localparam FP_NINF     = 80'hFFFF_8000000000000000;  // -Infinity
    localparam FP_NAN      = 80'h7FFF_C000000000000000;  // NaN (mantissa MSB=1, rest != 0)
    localparam FP_DENORM   = 80'h0000_4000000000000000;  // Denormal

    // Condition code masks
    wire cc_c3 = status_out[14];
    wire cc_c2 = status_out[10];
    wire cc_c1 = status_out[9];
    wire cc_c0 = status_out[8];

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT instantiation
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

    // Test sequence
    initial begin
        $dumpfile("fcom_test.vcd");
        $dumpvars(0, tb_fcom);

        // Initialize
        reset = 1;
        execute = 0;
        instruction = 8'h00;
        stack_index = 3'd0;
        data_in = 80'd0;
        int_data_in = 32'd0;
        control_in = 16'h037F;  // Default control word
        control_write = 0;

        #20 reset = 0;
        #10;

        $display("\n========================================");
        $display("Comparison Instructions Test");
        $display("========================================\n");

        // Test 1: FCOM with equal values (1.0 == 1.0)
        $display("Test 1: FCOM - Equal values (1.0 == 1.0)");
        load_value(FP_ONE);   // ST(0) = 1.0
        load_value(FP_ONE);   // ST(0) = 1.0, ST(1) = 1.0
        exec_compare(INST_FCOM, 3'd1);  // Compare ST(0) with ST(1)
        check_condition_codes(3'b100, "Equal", 1);  // Expected: C3=1, C2=0, C0=0

        // Test 2: FCOM with ST(0) > operand (2.0 > 1.0)
        $display("\nTest 2: FCOM - Greater than (2.0 > 1.0)");
        load_value(FP_ONE);   // ST(0) = 1.0
        load_value(FP_TWO);   // ST(0) = 2.0, ST(1) = 1.0
        exec_compare(INST_FCOM, 3'd1);
        check_condition_codes(3'b000, "Greater than", 2);  // Expected: C3=0, C2=0, C0=0

        // Test 3: FCOM with ST(0) < operand (0.5 < 1.0)
        $display("\nTest 3: FCOM - Less than (0.5 < 1.0)");
        load_value(FP_ONE);   // ST(0) = 1.0
        load_value(FP_HALF);  // ST(0) = 0.5, ST(1) = 1.0
        exec_compare(INST_FCOM, 3'd1);
        check_condition_codes(3'b001, "Less than", 3);  // Expected: C3=0, C2=0, C0=1

        // Test 4: FCOM with NaN (unordered)
        $display("\nTest 4: FCOM - Unordered (NaN)");
        load_value(FP_ONE);   // ST(0) = 1.0
        load_value(FP_NAN);   // ST(0) = NaN, ST(1) = 1.0
        exec_compare(INST_FCOM, 3'd1);
        check_condition_codes(3'b111, "Unordered (NaN)", 4);  // Expected: C3=1, C2=1, C0=1

        // Reset stack to prevent overflow
        #10;
        reset = 1;
        #20 reset = 0;
        #10;

        // Test 5: FTST with positive value
        $display("\nTest 5: FTST - Positive value (2.0 > 0.0)");
        load_value(FP_TWO);   // ST(0) = 2.0
        exec_ftst();
        check_condition_codes(3'b000, "Greater than zero", 5);

        // Test 6: FTST with negative value
        $display("\nTest 6: FTST - Negative value (-1.0 < 0.0)");
        load_value(FP_NEG_ONE);  // ST(0) = -1.0
        exec_ftst();
        check_condition_codes(3'b001, "Less than zero", 6);

        // Test 7: FTST with zero
        $display("\nTest 7: FTST - Zero (0.0 == 0.0)");
        load_value(FP_ZERO);  // ST(0) = 0.0
        exec_ftst();
        check_condition_codes(3'b100, "Equal to zero", 7);

        // Reset stack before FXAM tests
        #10;
        reset = 1;
        #20 reset = 0;
        #10;

        // Test 8: FXAM with zero
        $display("\nTest 8: FXAM - Zero");
        load_value(FP_ZERO);
        exec_fxam();
        $display("  C3 C2 C1 C0 = %b %b %b %b", cc_c3, cc_c2, cc_c1, cc_c0);
        if (cc_c3 == 1'b1 && cc_c2 == 1'b0 && cc_c0 == 1'b0)
            $display("  PASS - Zero detected");
        else
            $display("  FAIL - Expected C3=1, C2=0, C0=0 for +zero");

        // Test 9: FXAM with normal number
        $display("\nTest 9: FXAM - Normal number");
        load_value(FP_ONE);
        $display("  DEBUG: After loading FP_ONE, dut.st0 = 0x%020X", dut.st0);
        exec_fxam();
        $display("  C3 C2 C1 C0 = %b %b %b %b", cc_c3, cc_c2, cc_c1, cc_c0);
        if (cc_c3 == 1'b0 && cc_c2 == 1'b1 && cc_c0 == 1'b0)
            $display("  PASS - Normal number detected");
        else
            $display("  FAIL - Expected C3=0, C2=1, C0=0 for normal");

        // Test 10: FXAM with infinity
        $display("\nTest 10: FXAM - Infinity");
        load_value(FP_INF);
        exec_fxam();
        $display("  C3 C2 C1 C0 = %b %b %b %b", cc_c3, cc_c2, cc_c1, cc_c0);
        if (cc_c3 == 1'b0 && cc_c2 == 1'b1 && cc_c0 == 1'b1)
            $display("  PASS - Infinity detected");
        else
            $display("  FAIL - Expected C3=0, C2=1, C0=1 for infinity");

        // Test 11: FXAM with NaN
        $display("\nTest 11: FXAM - NaN");
        load_value(FP_NAN);
        exec_fxam();
        $display("  C3 C2 C1 C0 = %b %b %b %b", cc_c3, cc_c2, cc_c1, cc_c0);
        if (cc_c3 == 1'b0 && cc_c2 == 1'b0 && cc_c0 == 1'b1)
            $display("  PASS - NaN detected");
        else
            $display("  FAIL - Expected C3=0, C2=0, C0=1 for NaN");

        // Test 12: FXAM with denormal
        $display("\nTest 12: FXAM - Denormal");
        load_value(FP_DENORM);
        exec_fxam();
        $display("  C3 C2 C1 C0 = %b %b %b %b", cc_c3, cc_c2, cc_c1, cc_c0);
        if (cc_c3 == 1'b1 && cc_c2 == 1'b1)
            $display("  PASS - Denormal detected");
        else
            $display("  FAIL - Expected C3=1, C2=1 for denormal");

        // Test 13: FXAM with negative number (check sign in C1)
        $display("\nTest 13: FXAM - Negative number (sign check)");
        load_value(FP_NEG_ONE);
        exec_fxam();
        $display("  C3 C2 C1 C0 = %b %b %b %b", cc_c3, cc_c2, cc_c1, cc_c0);
        if (cc_c1 == 1'b1)
            $display("  PASS - Sign bit in C1 is 1 (negative)");
        else
            $display("  FAIL - Expected C1=1 for negative number");

        // Reset stack before comparison tests
        #10;
        reset = 1;
        #20 reset = 0;
        #10;

        // Test 14: FCOMP (compare and pop)
        $display("\nTest 14: FCOMP - Compare and pop");
        load_value(FP_ONE);   // ST(0) = 1.0
        load_value(FP_TWO);   // ST(0) = 2.0, ST(1) = 1.0
        $display("  Before FCOMP: Stack has 2 values");
        exec_compare(INST_FCOMP, 3'd1);
        check_condition_codes(3'b000, "2.0 > 1.0", 14);
        $display("  After FCOMP: Stack should have 1 value (popped ST(0))");

        // Test 15: FCOMPP (compare and pop twice)
        $display("\nTest 15: FCOMPP - Compare and pop twice");
        load_value(FP_ONE);   // ST(0) = 1.0
        $display("  DEBUG: After loading 1.0, st0=0x%020X", dut.st0);
        load_value(FP_HALF);  // ST(0) = 0.5, ST(1) = 1.0
        $display("  DEBUG: After loading 0.5, st0=0x%020X, st1=0x%020X",
                 dut.st0, dut.st1);
        $display("  Before FCOMPP: Stack has 2 values");
        exec_compare(INST_FCOMPP, 3'd1);  // FCOMPP compares ST(0) with ST(1) - need index 1!
        check_condition_codes(3'b001, "0.5 < 1.0", 15);
        $display("  After FCOMPP: Stack should be empty (popped both)");

        #100;
        $display("\n========================================");
        $display("All Comparison Tests Complete");
        $display("========================================\n");
        $finish;
    end

    // Helper task: Load a value onto the stack
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

    // Helper task: Execute compare instruction
    task exec_compare;
        input [7:0] inst;
        input [2:0] index;
        begin
            @(posedge clk);
            instruction = inst;
            stack_index = index;
            execute = 1;
            @(posedge clk);
            execute = 0;
            wait(ready == 1);
            @(posedge clk);
        end
    endtask

    // Helper task: Execute FTST
    task exec_ftst;
        begin
            @(posedge clk);
            instruction = INST_FTST;
            execute = 1;
            @(posedge clk);
            execute = 0;
            wait(ready == 1);
            @(posedge clk);
        end
    endtask

    // Helper task: Execute FXAM
    task exec_fxam;
        begin
            @(posedge clk);
            instruction = INST_FXAM;
            execute = 1;
            @(posedge clk);
            execute = 0;
            wait(ready == 1);
            @(posedge clk);
        end
    endtask

    // Helper task: Check condition codes
    task check_condition_codes;
        input [2:0] expected;  // [C3, C2, C0]
        input [127:0] description;
        input integer test_num;
        reg [2:0] actual;
        begin
            actual = {cc_c3, cc_c2, cc_c0};
            $display("  Expected condition codes: C3=%b, C2=%b, C0=%b (%s)",
                     expected[2], expected[1], expected[0], description);
            $display("  Actual condition codes:   C3=%b, C2=%b, C0=%b",
                     cc_c3, cc_c2, cc_c0);
            if (actual == expected)
                $display("  Test %0d: PASS", test_num);
            else
                $display("  Test %0d: FAIL", test_num);
        end
    endtask

endmodule
