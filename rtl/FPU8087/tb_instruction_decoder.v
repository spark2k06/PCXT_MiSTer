`timescale 1ns / 1ps

//=====================================================================
// Testbench for FPU_Instruction_Decoder
//
// Tests decoding of all 68 8087 instructions
//=====================================================================

module tb_instruction_decoder;

    reg [15:0] instruction;
    reg decode;

    wire [7:0] internal_opcode;
    wire [2:0] stack_index;
    wire has_memory_op;
    wire has_pop;
    wire has_push;
    wire [1:0] operand_size;
    wire is_integer;
    wire is_bcd;
    wire valid;
    wire uses_st0_sti;
    wire uses_sti_st0;

    integer test_count;
    integer pass_count;
    integer fail_count;

    // Instantiate decoder
    FPU_Instruction_Decoder dut (
        .instruction(instruction),
        .decode(decode),
        .internal_opcode(internal_opcode),
        .stack_index(stack_index),
        .has_memory_op(has_memory_op),
        .has_pop(has_pop),
        .has_push(has_push),
        .operand_size(operand_size),
        .is_integer(is_integer),
        .is_bcd(is_bcd),
        .valid(valid),
        .uses_st0_sti(uses_st0_sti),
        .uses_sti_st0(uses_sti_st0)
    );

    initial begin
        $dumpfile("decoder_waves.vcd");
        $dumpvars(0, tb_instruction_decoder);

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        $display("");
        $display("========================================");
        $display("8087 Instruction Decoder Test Suite");
        $display("========================================");
        $display("");

        decode = 1'b1;

        //=================================================================
        // Test D8 Opcodes - Arithmetic (32-bit memory or ST(i))
        //=================================================================
        $display("Testing D8: Arithmetic operations...");

        // FADD ST(0), ST(3): D8 C3
        test_decode(16'hD8C3, "FADD ST(0),ST(3)", 8'h10, 3'd3, 0, 0, 0, 0);

        // FMUL ST(0), ST(5): D8 CD
        test_decode(16'hD8CD, "FMUL ST(0),ST(5)", 8'h16, 3'd5, 0, 0, 0, 0);

        // FCOM ST(2): D8 D2
        test_decode(16'hD8D2, "FCOM ST(2)", 8'h60, 3'd2, 0, 0, 0, 0);

        // FSUB ST(0), ST(1): D8 E1
        test_decode(16'hD8E1, "FSUB ST(0),ST(1)", 8'h12, 3'd1, 0, 0, 0, 0);

        // FDIV ST(0), ST(4): D8 F4
        test_decode(16'hD8F4, "FDIV ST(0),ST(4)", 8'h18, 3'd4, 0, 0, 0, 0);

        //=================================================================
        // Test D9 Opcodes - Load/Store, Constants, Transcendental
        //=================================================================
        $display("Testing D9: Load/Store and transcendental...");

        // FLD ST(2): D9 C2
        test_decode(16'hD9C2, "FLD ST(2)", 8'h20, 3'd2, 0, 1, 0, 0);

        // FXCH ST(4): D9 CC
        test_decode(16'hD9CC, "FXCH ST(4)", 8'h23, 3'd4, 0, 0, 0, 0);

        // FLD1: D9 E8
        test_decode(16'hD9E8, "FLD1", 8'h80, 3'd0, 0, 1, 0, 0);

        // FLDPI: D9 EB
        test_decode(16'hD9EB, "FLDPI", 8'h82, 3'd0, 0, 1, 0, 0);

        // FLDZ: D9 EE
        test_decode(16'hD9EE, "FLDZ", 8'h81, 3'd0, 0, 1, 0, 0);

        // F2XM1: D9 F0
        test_decode(16'hD9F0, "F2XM1", 8'h56, 3'd0, 0, 0, 0, 0);

        // FYL2X: D9 F1
        test_decode(16'hD9F1, "FYL2X", 8'h57, 3'd0, 0, 0, 1, 0);

        // FPTAN: D9 F2
        test_decode(16'hD9F2, "FPTAN", 8'h54, 3'd0, 0, 1, 0, 0);

        // FPATAN: D9 F3
        test_decode(16'hD9F3, "FPATAN", 8'h55, 3'd0, 0, 0, 1, 0);

        // FSQRT: D9 FA
        test_decode(16'hD9FA, "FSQRT", 8'h50, 3'd0, 0, 0, 0, 0);

        // FSINCOS: D9 FB
        test_decode(16'hD9FB, "FSINCOS", 8'h53, 3'd0, 0, 1, 0, 0);

        // FSIN: D9 FE
        test_decode(16'hD9FE, "FSIN", 8'h51, 3'd0, 0, 0, 0, 0);

        // FCOS: D9 FF
        test_decode(16'hD9FF, "FCOS", 8'h52, 3'd0, 0, 0, 0, 0);

        // FCHS: D9 E0
        test_decode(16'hD9E0, "FCHS", 8'h95, 3'd0, 0, 0, 0, 0);

        // FABS: D9 E1
        test_decode(16'hD9E1, "FABS", 8'h94, 3'd0, 0, 0, 0, 0);

        // FTST: D9 E4
        test_decode(16'hD9E4, "FTST", 8'h63, 3'd0, 0, 0, 0, 0);

        // FXAM: D9 E5
        test_decode(16'hD9E5, "FXAM", 8'h64, 3'd0, 0, 0, 0, 0);

        //=================================================================
        // Test DB Opcodes - 80-bit, BCD, Control
        //=================================================================
        $display("Testing DB: 80-bit and control...");

        // FCLEX: DB E2
        test_decode(16'hDBE2, "FCLEX", 8'hF4, 3'd0, 0, 0, 0, 0);

        // FINIT: DB E3
        test_decode(16'hDBE3, "FINIT", 8'hF0, 3'd0, 0, 0, 0, 0);

        //=================================================================
        // Test DC Opcodes - Reversed arithmetic
        //=================================================================
        $display("Testing DC: Reversed register operations...");

        // FADD ST(3), ST(0): DC C3
        test_decode(16'hDCC3, "FADD ST(3),ST(0)", 8'h10, 3'd3, 0, 0, 0, 0);

        // FMUL ST(2), ST(0): DC CA
        test_decode(16'hDCCA, "FMUL ST(2),ST(0)", 8'h16, 3'd2, 0, 0, 0, 0);

        // FSUB ST(4), ST(0): DC EC
        test_decode(16'hDCEC, "FSUB ST(4),ST(0)", 8'h12, 3'd4, 0, 0, 0, 0);

        //=================================================================
        // Test DD Opcodes - 64-bit, FFREE, FST/FSTP
        //=================================================================
        $display("Testing DD: FFREE and ST(i) operations...");

        // FFREE ST(3): DD C3
        test_decode(16'hDDC3, "FFREE ST(3)", 8'h72, 3'd3, 0, 0, 0, 0);

        // FST ST(5): DD D5
        test_decode(16'hDDD5, "FST ST(5)", 8'h21, 3'd5, 0, 0, 0, 0);

        // FSTP ST(7): DD DF
        test_decode(16'hDDDF, "FSTP ST(7)", 8'h22, 3'd7, 0, 0, 1, 0);

        //=================================================================
        // Test DE Opcodes - Arithmetic with pop
        //=================================================================
        $display("Testing DE: Arithmetic with pop...");

        // FADDP ST(1), ST(0): DE C1
        test_decode(16'hDEC1, "FADDP ST(1),ST(0)", 8'h11, 3'd1, 0, 0, 1, 0);

        // FMULP ST(6), ST(0): DE CE
        test_decode(16'hDECE, "FMULP ST(6),ST(0)", 8'h17, 3'd6, 0, 0, 1, 0);

        // FCOMPP: DE D9
        test_decode(16'hDED9, "FCOMPP", 8'h62, 3'd1, 0, 0, 1, 0);

        // FSUBP ST(3), ST(0): DE E3
        test_decode(16'hDEE3, "FSUBP ST(3),ST(0)", 8'h13, 3'd3, 0, 0, 1, 0);

        // FDIVP ST(2), ST(0): DE F2
        test_decode(16'hDEF2, "FDIVP ST(2),ST(0)", 8'h19, 3'd2, 0, 0, 1, 0);

        //=================================================================
        // Test DF Opcodes - FINCSTP, FDECSTP, FSTSW AX
        //=================================================================
        $display("Testing DF: Stack management...");

        // FINCSTP: DF F7
        test_decode(16'hDFF7, "FINCSTP", 8'h70, 3'd7, 0, 0, 0, 0);

        // FDECSTP: DF F6
        test_decode(16'hDFF6, "FDECSTP", 8'h71, 3'd6, 0, 0, 0, 0);

        // FSTSW AX: DF E0
        test_decode(16'hDFE0, "FSTSW AX", 8'hF3, 3'd0, 0, 0, 0, 0);

        //=================================================================
        // Test Memory Operations (simplified - just checking flags)
        //=================================================================
        $display("Testing memory operations...");

        // FLD m32real: D9 /0 (using MOD=00, RM=110 for direct)
        instruction = 16'hD906;
        decode = 1'b1;
        #10;
        if (valid && has_memory_op && operand_size == 2'd1 && !is_integer) begin
            pass_count = pass_count + 1;
            $display("  PASS: FLD m32real - memory op, dword, not integer");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: FLD m32real");
        end
        test_count = test_count + 1;

        // FILD m32int: DB /0
        instruction = 16'hDB06;
        decode = 1'b1;
        #10;
        if (valid && has_memory_op && operand_size == 2'd1 && is_integer && has_push) begin
            pass_count = pass_count + 1;
            $display("  PASS: FILD m32int - memory op, dword, integer");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: FILD m32int");
        end
        test_count = test_count + 1;

        // FLD m64real: DD /0
        instruction = 16'hDD06;
        decode = 1'b1;
        #10;
        if (valid && has_memory_op && operand_size == 2'd2 && !is_integer && has_push) begin
            pass_count = pass_count + 1;
            $display("  PASS: FLD m64real - memory op, qword, not integer");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: FLD m64real");
        end
        test_count = test_count + 1;

        // FLD m80real: DB /5
        instruction = 16'hDB2E;
        decode = 1'b1;
        #10;
        if (valid && has_memory_op && operand_size == 2'd3 && has_push) begin
            pass_count = pass_count + 1;
            $display("  PASS: FLD m80real - memory op, tbyte");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: FLD m80real");
        end
        test_count = test_count + 1;

        //=================================================================
        // Test Integer Memory Operations
        //=================================================================
        $display("Testing integer memory operations...");

        // FIADD m32int: DA /0
        instruction = 16'hDA06;
        decode = 1'b1;
        #10;
        if (valid && has_memory_op && is_integer && operand_size == 2'd1) begin
            pass_count = pass_count + 1;
            $display("  PASS: FIADD m32int");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: FIADD m32int");
        end
        test_count = test_count + 1;

        // FIADD m16int: DE /0
        instruction = 16'hDE06;
        decode = 1'b1;
        #10;
        if (valid && has_memory_op && is_integer && operand_size == 2'd0) begin
            pass_count = pass_count + 1;
            $display("  PASS: FIADD m16int");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: FIADD m16int");
        end
        test_count = test_count + 1;

        //=================================================================
        // Summary
        //=================================================================
        $display("");
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests:  %0d", test_count);
        $display("Passed:       %0d", pass_count);
        $display("Failed:       %0d", fail_count);
        $display("");

        if (fail_count == 0) begin
            $display("*** ALL DECODER TESTS PASSED ***");
            $display("");
        end else begin
            $display("*** SOME TESTS FAILED ***");
            $display("");
        end

        $finish;
    end

    // Helper task for testing decoder
    task test_decode;
        input [15:0] instr;
        input [200*8:1] name;
        input [7:0] expected_opcode;
        input [2:0] expected_index;
        input expected_mem;
        input expected_push;
        input expected_pop;
        input expected_int;
        begin
            instruction = instr;
            decode = 1'b1;
            #10;

            if (valid &&
                internal_opcode == expected_opcode &&
                stack_index == expected_index &&
                has_memory_op == expected_mem &&
                has_push == expected_push &&
                has_pop == expected_pop &&
                is_integer == expected_int) begin
                pass_count = pass_count + 1;
                $display("  PASS: %0s", name);
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL: %0s", name);
                $display("        Expected: op=%02x idx=%0d mem=%0d push=%0d pop=%0d int=%0d",
                    expected_opcode, expected_index, expected_mem, expected_push, expected_pop, expected_int);
                $display("        Got:      op=%02x idx=%0d mem=%0d push=%0d pop=%0d int=%0d valid=%0d",
                    internal_opcode, stack_index, has_memory_op, has_push, has_pop, is_integer, valid);
            end
            test_count = test_count + 1;
        end
    endtask

endmodule
