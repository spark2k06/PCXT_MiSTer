`timescale 1ns / 1ps

//=====================================================================
// Decoder Debug Test
//
// Check what the decoder outputs for FLD1, FLDPI, FSTP
//=====================================================================

module tb_decoder_debug;

    reg [15:0] instruction;
    wire [7:0] internal_opcode;
    wire [2:0] stack_index;
    wire has_memory_op;
    wire [1:0] operand_size;
    wire is_integer;
    wire is_bcd;
    wire valid;

    FPU_Instruction_Decoder uut (
        .instruction(instruction),
        .decode(1'b1),
        .internal_opcode(internal_opcode),
        .stack_index(stack_index),
        .has_memory_op(has_memory_op),
        .has_pop(),
        .has_push(),
        .operand_size(operand_size),
        .is_integer(is_integer),
        .is_bcd(is_bcd),
        .valid(valid),
        .uses_st0_sti(),
        .uses_sti_st0()
    );

    initial begin
        $display("\n=== Decoder Debug Test ===\n");

        // Test FLD1 (D9 E8)
        instruction = 16'hD9E8;
        #1;
        $display("FLD1 (D9 E8):");
        $display("  internal_opcode = %02X", internal_opcode);
        $display("  valid = %b", valid);
        $display("  has_memory_op = %b", has_memory_op);
        $display("");

        // Test FLDPI (D9 EB)
        instruction = 16'hD9EB;
        #1;
        $display("FLDPI (D9 EB):");
        $display("  internal_opcode = %02X", internal_opcode);
        $display("  valid = %b", valid);
        $display("  has_memory_op = %b", has_memory_op);
        $display("");

        // Test FLDZ (D9 EE)
        instruction = 16'hD9EE;
        #1;
        $display("FLDZ (D9 EE):");
        $display("  internal_opcode = %02X", internal_opcode);
        $display("  valid = %b", valid);
        $display("  has_memory_op = %b", has_memory_op);
        $display("");

        // Test FSTP m80 (DB 38)
        instruction = 16'hDB38;
        #1;
        $display("FSTP m80 (DB 38):");
        $display("  internal_opcode = %02X", internal_opcode);
        $display("  valid = %b", valid);
        $display("  has_memory_op = %b", has_memory_op);
        $display("  operand_size = %d", operand_size);
        $display("");

        $finish;
    end

endmodule
