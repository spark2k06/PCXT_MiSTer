/**
 * tb_esc_decoder.v
 *
 * Testbench for ESC_Decoder module
 *
 * Tests:
 * 1. All ESC opcodes (D8-DF)
 * 2. ModR/M decoding (reg and r/m fields)
 * 3. Memory vs register operand detection
 * 4. Edge cases
 *
 * Date: 2025-11-10
 */

`timescale 1ns/1ps

module tb_esc_decoder;

    //=================================================================
    // Testbench Signals
    //=================================================================

    reg clk;
    reg reset;

    reg [7:0] opcode;
    reg [7:0] modrm;
    reg valid;

    wire is_esc;
    wire [2:0] esc_index;
    wire [2:0] fpu_opcode;
    wire [2:0] stack_index;
    wire has_memory_op;
    wire [1:0] mod;
    wire [2:0] rm;

    //=================================================================
    // Test Statistics
    //=================================================================

    integer test_count;
    integer pass_count;
    integer fail_count;

    //=================================================================
    // DUT Instantiation
    //=================================================================

    ESC_Decoder dut (
        .clk(clk),
        .reset(reset),
        .opcode(opcode),
        .modrm(modrm),
        .valid(valid),
        .is_esc(is_esc),
        .esc_index(esc_index),
        .fpu_opcode(fpu_opcode),
        .stack_index(stack_index),
        .has_memory_op(has_memory_op),
        .mod(mod),
        .rm(rm)
    );

    //=================================================================
    // Clock Generation
    //=================================================================

    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100 MHz clock
    end

    //=================================================================
    // Test Tasks
    //=================================================================

    // Task: Decode an instruction
    task decode_instruction;
        input [7:0] opc;
        input [7:0] mr;
        begin
            @(posedge clk);
            opcode <= opc;
            modrm <= mr;
            valid <= 1'b1;
            @(posedge clk);
            valid <= 1'b0;
            @(posedge clk);
        end
    endtask

    // Task: Check decoded values
    task check_decode;
        input exp_is_esc;
        input [2:0] exp_esc_idx;
        input [2:0] exp_fpu_opc;
        input [2:0] exp_stack_idx;
        input exp_has_mem;
        input [1:0] exp_mod;
        input [2:0] exp_rm;
        input [255:0] test_name;
        begin
            test_count = test_count + 1;
            $display("[Test %0d] %s", test_count, test_name);

            if (is_esc == exp_is_esc &&
                esc_index == exp_esc_idx &&
                fpu_opcode == exp_fpu_opc &&
                stack_index == exp_stack_idx &&
                has_memory_op == exp_has_mem &&
                mod == exp_mod &&
                rm == exp_rm) begin
                $display("  PASS: is_esc=%b, esc_idx=%0d, fpu_opc=%0d, ST(%0d), mem=%b, mod=%0d, rm=%0d",
                         is_esc, esc_index, fpu_opcode, stack_index, has_memory_op, mod, rm);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Expected is_esc=%b esc_idx=%0d fpu_opc=%0d ST(%0d) mem=%b mod=%0d rm=%0d",
                         exp_is_esc, exp_esc_idx, exp_fpu_opc, exp_stack_idx, exp_has_mem, exp_mod, exp_rm);
                $display("        Got is_esc=%b esc_idx=%0d fpu_opc=%0d ST(%0d) mem=%b mod=%0d rm=%0d",
                         is_esc, esc_index, fpu_opcode, stack_index, has_memory_op, mod, rm);
                fail_count = fail_count + 1;
            end
        end
    endtask

    //=================================================================
    // Main Test Sequence
    //=================================================================

    initial begin
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        opcode = 8'h00;
        modrm = 8'h00;
        valid = 0;

        // Reset
        reset = 1;
        repeat(5) @(posedge clk);
        reset = 0;
        repeat(2) @(posedge clk);

        $display("\n=== ESC Decoder Tests ===\n");

        // Test 1: Non-ESC instruction
        $display("\n--- Test: Non-ESC instructions ---");
        decode_instruction(8'h90, 8'h00);  // NOP
        check_decode(1'b0, 3'd0, 3'd0, 3'd0, 1'b0, 2'd0, 3'd0, "NOP (not ESC)");

        decode_instruction(8'h01, 8'hC0);  // ADD
        check_decode(1'b0, 3'd0, 3'd0, 3'd0, 1'b0, 2'd0, 3'd0, "ADD (not ESC)");

        // Test 2: ESC D8 (ESC 0) - FADD, FMUL, etc.
        $display("\n--- Test: ESC D8 (ESC 0) ---");
        decode_instruction(8'hD8, 8'hC1);  // FADD ST, ST(1)
        check_decode(1'b1, 3'd0, 3'd0, 3'd1, 1'b0, 2'd3, 3'd1, "D8 C1 - FADD ST, ST(1)");

        decode_instruction(8'hD8, 8'hC9);  // FMUL ST, ST(1)
        check_decode(1'b1, 3'd0, 3'd1, 3'd1, 1'b0, 2'd3, 3'd1, "D8 C9 - FMUL ST, ST(1)");

        // Test 3: ESC D9 (ESC 1) - FLD, FST, etc.
        $display("\n--- Test: ESC D9 (ESC 1) ---");
        decode_instruction(8'hD9, 8'hC0);  // FLD ST(0)
        check_decode(1'b1, 3'd1, 3'd0, 3'd0, 1'b0, 2'd3, 3'd0, "D9 C0 - FLD ST(0)");

        decode_instruction(8'hD9, 8'hD0);  // FNOP
        check_decode(1'b1, 3'd1, 3'd2, 3'd0, 1'b0, 2'd3, 3'd0, "D9 D0 - FNOP");

        // Test 4: ESC DA (ESC 2) - Integer operations
        $display("\n--- Test: ESC DA (ESC 2) ---");
        decode_instruction(8'hDA, 8'hC0);  // FCMOVB ST, ST(0)
        check_decode(1'b1, 3'd2, 3'd0, 3'd0, 1'b0, 2'd3, 3'd0, "DA C0 - FCMOVB");

        // Test 5: ESC DB (ESC 3)
        $display("\n--- Test: ESC DB (ESC 3) ---");
        decode_instruction(8'hDB, 8'hE3);  // FNINIT
        check_decode(1'b1, 3'd3, 3'd4, 3'd3, 1'b0, 2'd3, 3'd3, "DB E3 - FNINIT");

        // Test 6: ESC DC (ESC 4)
        $display("\n--- Test: ESC DC (ESC 4) ---");
        decode_instruction(8'hDC, 8'hC1);  // FADD ST(1), ST
        check_decode(1'b1, 3'd4, 3'd0, 3'd1, 1'b0, 2'd3, 3'd1, "DC C1 - FADD ST(1), ST");

        // Test 7: ESC DD (ESC 5)
        $display("\n--- Test: ESC DD (ESC 5) ---");
        decode_instruction(8'hDD, 8'hD8);  // FSTP ST(0)
        check_decode(1'b1, 3'd5, 3'd3, 3'd0, 1'b0, 2'd3, 3'd0, "DD D8 - FSTP ST(0)");

        // Test 8: ESC DE (ESC 6)
        $display("\n--- Test: ESC DE (ESC 6) ---");
        decode_instruction(8'hDE, 8'hC1);  // FADDP ST(1), ST
        check_decode(1'b1, 3'd6, 3'd0, 3'd1, 1'b0, 2'd3, 3'd1, "DE C1 - FADDP ST(1), ST");

        // Test 9: ESC DF (ESC 7)
        $display("\n--- Test: ESC DF (ESC 7) ---");
        decode_instruction(8'hDF, 8'hE0);  // FSTSW AX
        check_decode(1'b1, 3'd7, 3'd4, 3'd0, 1'b0, 2'd3, 3'd0, "DF E0 - FSTSW AX");

        // Test 10: Memory operands (mod != 11)
        $display("\n--- Test: Memory operands ---");
        decode_instruction(8'hD9, 8'h06);  // FLD [addr16] (mod=00, rm=110)
        check_decode(1'b1, 3'd1, 3'd0, 3'd6, 1'b1, 2'd0, 3'd6, "D9 06 - FLD [addr]");

        decode_instruction(8'hDD, 8'h46);  // FLD [BP+disp8] (mod=01, rm=110)
        check_decode(1'b1, 3'd5, 3'd0, 3'd6, 1'b1, 2'd1, 3'd6, "DD 46 - FLD [BP+disp8]");

        decode_instruction(8'hDB, 8'h86);  // ? [BP+disp16] (mod=10, rm=110)
        check_decode(1'b1, 3'd3, 3'd0, 3'd6, 1'b1, 2'd2, 3'd6, "DB 86 - [BP+disp16]");

        // Test 11: All register combinations (mod=11)
        $display("\n--- Test: Register operands (mod=11) ---");
        decode_instruction(8'hD8, 8'hC0);
        check_decode(1'b1, 3'd0, 3'd0, 3'd0, 1'b0, 2'd3, 3'd0, "D8 C0 - ST(0)");
        decode_instruction(8'hD8, 8'hC1);
        check_decode(1'b1, 3'd0, 3'd0, 3'd1, 1'b0, 2'd3, 3'd1, "D8 C1 - ST(1)");
        decode_instruction(8'hD8, 8'hC2);
        check_decode(1'b1, 3'd0, 3'd0, 3'd2, 1'b0, 2'd3, 3'd2, "D8 C2 - ST(2)");
        decode_instruction(8'hD8, 8'hC3);
        check_decode(1'b1, 3'd0, 3'd0, 3'd3, 1'b0, 2'd3, 3'd3, "D8 C3 - ST(3)");
        decode_instruction(8'hD8, 8'hC4);
        check_decode(1'b1, 3'd0, 3'd0, 3'd4, 1'b0, 2'd3, 3'd4, "D8 C4 - ST(4)");
        decode_instruction(8'hD8, 8'hC5);
        check_decode(1'b1, 3'd0, 3'd0, 3'd5, 1'b0, 2'd3, 3'd5, "D8 C5 - ST(5)");
        decode_instruction(8'hD8, 8'hC6);
        check_decode(1'b1, 3'd0, 3'd0, 3'd6, 1'b0, 2'd3, 3'd6, "D8 C6 - ST(6)");
        decode_instruction(8'hD8, 8'hC7);
        check_decode(1'b1, 3'd0, 3'd0, 3'd7, 1'b0, 2'd3, 3'd7, "D8 C7 - ST(7)");

        // Test 12: All ESC opcodes with same ModR/M
        $display("\n--- Test: All ESC opcodes ---");
        decode_instruction(8'hD8, 8'hC0);
        check_decode(1'b1, 3'd0, 3'd0, 3'd0, 1'b0, 2'd3, 3'd0, "ESC 0 (D8)");
        decode_instruction(8'hD9, 8'hC0);
        check_decode(1'b1, 3'd1, 3'd0, 3'd0, 1'b0, 2'd3, 3'd0, "ESC 1 (D9)");
        decode_instruction(8'hDA, 8'hC0);
        check_decode(1'b1, 3'd2, 3'd0, 3'd0, 1'b0, 2'd3, 3'd0, "ESC 2 (DA)");
        decode_instruction(8'hDB, 8'hC0);
        check_decode(1'b1, 3'd3, 3'd0, 3'd0, 1'b0, 2'd3, 3'd0, "ESC 3 (DB)");
        decode_instruction(8'hDC, 8'hC0);
        check_decode(1'b1, 3'd4, 3'd0, 3'd0, 1'b0, 2'd3, 3'd0, "ESC 4 (DC)");
        decode_instruction(8'hDD, 8'hC0);
        check_decode(1'b1, 3'd5, 3'd0, 3'd0, 1'b0, 2'd3, 3'd0, "ESC 5 (DD)");
        decode_instruction(8'hDE, 8'hC0);
        check_decode(1'b1, 3'd6, 3'd0, 3'd0, 1'b0, 2'd3, 3'd0, "ESC 6 (DE)");
        decode_instruction(8'hDF, 8'hC0);
        check_decode(1'b1, 3'd7, 3'd0, 3'd0, 1'b0, 2'd3, 3'd0, "ESC 7 (DF)");

        // Test 13: All FPU opcodes (reg field 0-7)
        $display("\n--- Test: All FPU opcodes (reg field) ---");
        decode_instruction(8'hD8, 8'hC0);
        check_decode(1'b1, 3'd0, 3'd0, 3'd0, 1'b0, 2'd3, 3'd0, "FPU opcode 0");
        decode_instruction(8'hD8, 8'hC8);
        check_decode(1'b1, 3'd0, 3'd1, 3'd0, 1'b0, 2'd3, 3'd0, "FPU opcode 1");
        decode_instruction(8'hD8, 8'hD0);
        check_decode(1'b1, 3'd0, 3'd2, 3'd0, 1'b0, 2'd3, 3'd0, "FPU opcode 2");
        decode_instruction(8'hD8, 8'hD8);
        check_decode(1'b1, 3'd0, 3'd3, 3'd0, 1'b0, 2'd3, 3'd0, "FPU opcode 3");
        decode_instruction(8'hD8, 8'hE0);
        check_decode(1'b1, 3'd0, 3'd4, 3'd0, 1'b0, 2'd3, 3'd0, "FPU opcode 4");
        decode_instruction(8'hD8, 8'hE8);
        check_decode(1'b1, 3'd0, 3'd5, 3'd0, 1'b0, 2'd3, 3'd0, "FPU opcode 5");
        decode_instruction(8'hD8, 8'hF0);
        check_decode(1'b1, 3'd0, 3'd6, 3'd0, 1'b0, 2'd3, 3'd0, "FPU opcode 6");
        decode_instruction(8'hD8, 8'hF8);
        check_decode(1'b1, 3'd0, 3'd7, 3'd0, 1'b0, 2'd3, 3'd0, "FPU opcode 7");

        // Summary
        repeat(5) @(posedge clk);
        $display("\n=== ESC Decoder Test Summary ===");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);

        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
            $display("ESC Decoder Verified:");
            $display("  ✓ Non-ESC instructions correctly identified");
            $display("  ✓ All ESC opcodes (D8-DF) decoded");
            $display("  ✓ ModR/M reg field extracted as FPU opcode");
            $display("  ✓ ModR/M r/m field extracted as stack index");
            $display("  ✓ Memory operands (mod != 11) detected");
            $display("  ✓ Register operands (mod == 11) detected");
            $display("  ✓ All mod values handled correctly");
            $display("");
        end else begin
            $display("\n*** SOME TESTS FAILED ***\n");
        end

        $finish;
    end

    //=================================================================
    // Timeout
    //=================================================================

    initial begin
        #100000;  // 100 us timeout
        $display("\n*** TEST TIMEOUT ***\n");
        $finish;
    end

endmodule
