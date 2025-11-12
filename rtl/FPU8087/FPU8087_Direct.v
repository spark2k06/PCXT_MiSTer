// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Intel 8087 FPU - Direct Integration
//
// This module provides a simple, direct connection between
// FPU_Instruction_Decoder and FPU_Core.
//
// Architecture:
//   Real 8087 Opcode (D8-DF + ModR/M) → Decoder → Internal Opcode → FPU_Core
//
// Usage:
//   1. Set cpu_opcode and cpu_modrm
//   2. Assert cpu_execute for one cycle
//   3. Wait for cpu_ready to go high
//   4. Read results from cpu_data_out
//=====================================================================

module FPU8087_Direct(
    input wire clk,
    input wire reset,

    // ========== Instruction Interface ==========
    input wire [7:0]  cpu_opcode,         // Real 8087 opcode (D8h-DFh)
    input wire [7:0]  cpu_modrm,          // ModR/M byte
    input wire        cpu_execute,        // Start execution (1 cycle pulse)
    output wire       cpu_ready,          // FPU ready for new instruction
    output wire       cpu_error,          // Exception occurred

    // ========== Data Interface ==========
    input wire [79:0] cpu_data_in,        // Data input (for loads)
    output wire [79:0] cpu_data_out,      // Data output (for stores)
    input wire [31:0] cpu_int_data_in,    // Integer data input
    output wire [31:0] cpu_int_data_out,  // Integer data output

    // ========== Control/Status Interface ==========
    input wire [15:0] cpu_control_in,     // Control word input
    input wire        cpu_control_write,  // Write control word
    output wire [15:0] cpu_status_out,    // Status word output
    output wire [15:0] cpu_control_out,   // Control word output
    output wire [15:0] cpu_tag_word_out   // Tag word output
);

    //=================================================================
    // Decoder Outputs
    //=================================================================

    wire [7:0]  decoded_opcode;
    wire [2:0]  decoded_stack_index;
    wire        decoded_has_memory_op;
    wire [1:0]  decoded_operand_size;
    wire        decoded_is_integer;
    wire        decoded_is_bcd;
    wire        decoded_valid;

    // Decoder runs combinationally on every cycle (valid flag indicates success)
    FPU_Instruction_Decoder decoder (
        .instruction({cpu_opcode, cpu_modrm}),
        .decode(1'b1),  // Always decode

        // Decoded outputs
        .internal_opcode(decoded_opcode),
        .stack_index(decoded_stack_index),
        .has_memory_op(decoded_has_memory_op),
        .has_pop(),  // Unused - pop handled by internal opcode
        .has_push(), // Unused - push handled by internal opcode
        .operand_size(decoded_operand_size),
        .is_integer(decoded_is_integer),
        .is_bcd(decoded_is_bcd),
        .valid(decoded_valid),
        .uses_st0_sti(),  // Unused - operand order handled internally
        .uses_sti_st0()   // Unused - operand order handled internally
    );

    //=================================================================
    // FPU Core
    //=================================================================

    FPU_Core core (
        .clk(clk),
        .reset(reset),

        // Instruction interface (using decoded internal opcodes)
        .instruction(decoded_opcode),
        .stack_index(decoded_stack_index),
        .execute(cpu_execute & decoded_valid),  // Only execute valid instructions
        .ready(cpu_ready),
        .error(cpu_error),

        // Data interface
        .data_in(cpu_data_in),
        .data_out(cpu_data_out),
        .int_data_in(cpu_int_data_in),
        .int_data_out(cpu_int_data_out),

        // Memory operand format information (from decoder)
        .has_memory_op(decoded_has_memory_op),
        .operand_size(decoded_operand_size),
        .is_integer(decoded_is_integer),
        .is_bcd(decoded_is_bcd),

        // Control/Status interface
        .control_in(cpu_control_in),
        .control_write(cpu_control_write),
        .status_out(cpu_status_out),
        .control_out(cpu_control_out),
        .tag_word_out(cpu_tag_word_out)
    );

endmodule
