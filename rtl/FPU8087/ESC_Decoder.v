// Copyright 2025, Waldo Alvarez, https://pipflow.com
/**
 * ESC_Decoder.v
 *
 * ESC Instruction Decoder for 8086/8087 Interface
 *
 * Detects and decodes ESC instructions (opcodes D8-DF) used for
 * communicating with the 8087 FPU coprocessor.
 *
 * ESC instructions have the format:
 *   Opcode: 11011xxx (D8-DF)
 *   ModR/M: mod reg r/m
 *
 * The ESC opcode identifies the instruction class, and the ModR/M byte
 * specifies the operation and operands.
 *
 * Date: 2025-11-10
 */

`timescale 1ns / 1ps

module ESC_Decoder(
    input wire clk,
    input wire reset,

    // Instruction input
    input wire [7:0] opcode,         // Instruction opcode from CPU
    input wire [7:0] modrm,          // ModR/M byte
    input wire valid,                // Opcode valid (sample inputs)

    // Decoded outputs
    output reg is_esc,               // Is ESC instruction (D8-DF)
    output reg [2:0] esc_index,      // ESC index (0-7 for D8-DF)
    output reg [2:0] fpu_opcode,     // FPU opcode from ModR/M.reg
    output reg [2:0] stack_index,    // ST(i) from ModR/M.rm (if register)
    output reg has_memory_op,        // Memory operand present (mod != 11)
    output reg [1:0] mod,            // ModR/M.mod field
    output reg [2:0] rm              // ModR/M.rm field
);

    //=================================================================
    // ESC Opcode Detection
    //=================================================================

    // ESC instructions: D8-DF (11011xxx)
    wire is_esc_opcode = (opcode[7:3] == 5'b11011);

    //=================================================================
    // ModR/M Decoding
    //=================================================================

    // ModR/M format: mod reg r/m
    //   mod[7:6] - addressing mode
    //   reg[5:3] - register or additional opcode
    //   r/m[2:0] - register/memory operand

    wire [1:0] modrm_mod = modrm[7:6];
    wire [2:0] modrm_reg = modrm[5:3];
    wire [2:0] modrm_rm  = modrm[2:0];

    // Memory operand present when mod != 11 (register direct)
    wire has_mem_operand = (modrm_mod != 2'b11);

    //=================================================================
    // Output Logic
    //=================================================================

    always @(posedge clk) begin
        if (reset) begin
            is_esc <= 1'b0;
            esc_index <= 3'b000;
            fpu_opcode <= 3'b000;
            stack_index <= 3'b000;
            has_memory_op <= 1'b0;
            mod <= 2'b00;
            rm <= 3'b000;
        end else if (valid) begin
            // Sample and decode when valid asserted
            is_esc <= is_esc_opcode;
            if (is_esc_opcode) begin
                // Only decode ModR/M for ESC instructions
                esc_index <= opcode[2:0];        // ESC index (0-7)
                fpu_opcode <= modrm_reg;         // FPU opcode from reg field
                stack_index <= modrm_rm;         // ST(i) if register operand
                has_memory_op <= has_mem_operand; // Memory vs register
                mod <= modrm_mod;
                rm <= modrm_rm;
            end else begin
                // Non-ESC instruction - clear outputs
                esc_index <= 3'b000;
                fpu_opcode <= 3'b000;
                stack_index <= 3'b000;
                has_memory_op <= 1'b0;
                mod <= 2'b00;
                rm <= 3'b000;
            end
        end
    end

    //=================================================================
    // Debug Info (for simulation)
    //=================================================================

    `ifdef SIMULATION
    always @(posedge clk) begin
        if (valid && is_esc_opcode) begin
            $display("[ESC_DECODER] Decoded ESC instruction at time %t:", $time);
            $display("  Opcode: 0x%02h (ESC %0d)", opcode, opcode[2:0]);
            $display("  ModR/M: 0x%02h (mod=%0d, reg=%0d, r/m=%0d)",
                     modrm, modrm_mod, modrm_reg, modrm_rm);
            $display("  FPU Opcode: %0d", modrm_reg);
            $display("  Stack Index: ST(%0d)", modrm_rm);
            $display("  Has Memory Operand: %b", has_mem_operand);
        end
    end
    `endif

endmodule
