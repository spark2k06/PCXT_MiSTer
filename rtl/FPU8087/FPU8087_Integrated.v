// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Integrated FPU8087 Module
//
// Combines the FPU_CPU_Interface and FPU_Core_Wrapper to create
// a complete FPU that can communicate with the CPU.
//=====================================================================

module FPU8087_Integrated(
    // Clock and Reset
    input wire clk,
    input wire reset,

    // ========== CPU Side Interface ==========

    // Instruction Interface
    input wire        cpu_fpu_instr_valid,
    input wire [7:0]  cpu_fpu_opcode,
    input wire [7:0]  cpu_fpu_modrm,
    output wire       cpu_fpu_instr_ack,

    // Data Transfer Interface
    input wire        cpu_fpu_data_write,
    input wire        cpu_fpu_data_read,
    input wire [2:0]  cpu_fpu_data_size,
    input wire [79:0] cpu_fpu_data_in,
    output wire [79:0] cpu_fpu_data_out,
    output wire       cpu_fpu_data_ready,

    // Status and Control
    output wire       cpu_fpu_busy,
    output wire [15:0] cpu_fpu_status_word,
    input wire [15:0] cpu_fpu_control_word,
    input wire        cpu_fpu_ctrl_write,
    output wire       cpu_fpu_exception,
    output wire       cpu_fpu_irq,

    // Synchronization
    input wire        cpu_fpu_wait,
    output wire       cpu_fpu_ready
);

    //=================================================================
    // Instruction Decoder Signals
    //=================================================================

    wire [15:0] instruction_word;
    wire [7:0]  decoded_opcode;
    wire [2:0]  decoded_stack_index;
    wire        decoded_has_memory_op;
    wire        decoded_has_pop;
    wire        decoded_has_push;
    wire [1:0]  decoded_operand_size;
    wire        decoded_is_integer;
    wire        decoded_is_bcd;
    wire        decoded_valid;
    wire        decoded_uses_st0_sti;
    wire        decoded_uses_sti_st0;

    // Combine opcode and ModR/M into 16-bit instruction
    assign instruction_word = {cpu_fpu_opcode, cpu_fpu_modrm};

    //=================================================================
    // FPU Instruction Decoder
    //=================================================================

    FPU_Instruction_Decoder decoder (
        .instruction(instruction_word),
        .decode(cpu_fpu_instr_valid),

        .internal_opcode(decoded_opcode),
        .stack_index(decoded_stack_index),
        .has_memory_op(decoded_has_memory_op),
        .has_pop(decoded_has_pop),
        .has_push(decoded_has_push),
        .operand_size(decoded_operand_size),
        .is_integer(decoded_is_integer),
        .is_bcd(decoded_is_bcd),
        .valid(decoded_valid),
        .uses_st0_sti(decoded_uses_st0_sti),
        .uses_sti_st0(decoded_uses_sti_st0)
    );

    //=================================================================
    // Interface to Core Signals
    //=================================================================

    wire        if_fpu_start;
    wire [7:0]  if_fpu_operation;
    wire [7:0]  if_fpu_operand_select;
    wire [79:0] if_fpu_operand_data;
    wire        if_fpu_operation_complete;
    wire [79:0] if_fpu_result_data;
    wire [15:0] if_fpu_status;
    wire        if_fpu_error;
    wire [15:0] if_fpu_control_reg;
    wire        if_fpu_control_update;

    // Memory operation signals (from decoder to core)
    wire        if_fpu_has_memory_op;
    wire [1:0]  if_fpu_operand_size;
    wire        if_fpu_is_integer;
    wire        if_fpu_is_bcd;

    //=================================================================
    // FPU Interface Module
    //=================================================================

    FPU_CPU_Interface cpu_interface (
        .clk(clk),
        .reset(reset),

        // CPU Side
        .cpu_fpu_instr_valid(cpu_fpu_instr_valid && decoded_valid),  // Only acknowledge valid decoded instructions
        .cpu_fpu_opcode(decoded_opcode),          // Pass decoded opcode to interface
        .cpu_fpu_modrm({5'b0, decoded_stack_index}),  // Pass decoded stack index
        .cpu_fpu_instr_ack(cpu_fpu_instr_ack),

        .cpu_fpu_data_write(cpu_fpu_data_write),
        .cpu_fpu_data_read(cpu_fpu_data_read),
        .cpu_fpu_data_size(cpu_fpu_data_size),
        .cpu_fpu_data_in(cpu_fpu_data_in),
        .cpu_fpu_data_out(cpu_fpu_data_out),
        .cpu_fpu_data_ready(cpu_fpu_data_ready),

        .cpu_fpu_busy(cpu_fpu_busy),
        .cpu_fpu_status_word(cpu_fpu_status_word),
        .cpu_fpu_control_word(cpu_fpu_control_word),
        .cpu_fpu_ctrl_write(cpu_fpu_ctrl_write),
        .cpu_fpu_exception(cpu_fpu_exception),
        .cpu_fpu_irq(cpu_fpu_irq),

        .cpu_fpu_wait(cpu_fpu_wait),
        .cpu_fpu_ready(cpu_fpu_ready),

        // Memory Operation Format (from decoder)
        .cpu_fpu_has_memory_op(decoded_has_memory_op),
        .cpu_fpu_operand_size(decoded_operand_size),
        .cpu_fpu_is_integer(decoded_is_integer),
        .cpu_fpu_is_bcd(decoded_is_bcd),

        // FPU Core Side
        .fpu_start(if_fpu_start),
        .fpu_operation(if_fpu_operation),
        .fpu_operand_select(if_fpu_operand_select),
        .fpu_operand_data(if_fpu_operand_data),

        .fpu_operation_complete(if_fpu_operation_complete),
        .fpu_result_data(if_fpu_result_data),
        .fpu_status(if_fpu_status),
        .fpu_error(if_fpu_error),

        .fpu_control_reg(if_fpu_control_reg),
        .fpu_control_update(if_fpu_control_update),

        // Memory Operation Format (to core)
        .fpu_has_memory_op(if_fpu_has_memory_op),
        .fpu_operand_size(if_fpu_operand_size),
        .fpu_is_integer(if_fpu_is_integer),
        .fpu_is_bcd(if_fpu_is_bcd)
    );

    //=================================================================
    // FPU Core Wrapper
    //=================================================================

    FPU_Core_Wrapper core (
        .clk(clk),
        .reset(reset),

        .if_start(if_fpu_start),
        .if_operation(if_fpu_operation),
        .if_operand_select(if_fpu_operand_select),
        .if_operand_data(if_fpu_operand_data),

        .if_operation_complete(if_fpu_operation_complete),
        .if_result_data(if_fpu_result_data),
        .if_status(if_fpu_status),
        .if_error(if_fpu_error),

        .if_control_reg(if_fpu_control_reg),
        .if_control_update(if_fpu_control_update),

        // Memory Operation Format (from interface)
        .if_has_memory_op(if_fpu_has_memory_op),
        .if_operand_size(if_fpu_operand_size),
        .if_is_integer(if_fpu_is_integer),
        .if_is_bcd(if_fpu_is_bcd)
    );

endmodule
