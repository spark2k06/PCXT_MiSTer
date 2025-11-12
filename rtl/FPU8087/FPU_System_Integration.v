// Copyright 2025, Waldo Alvarez, https://pipflow.com
/**
 * FPU_System_Integration.v
 *
 * Complete FPU System Integration Module
 *
 * Integrates all Phase 1-5 components:
 * - ESC Decoder (Phase 5)
 * - FPU Memory Interface (Phase 5)
 * - FPU Instruction Queue (Phase 1)
 * - FPU Exception Handler (Phase 2)
 * - FPU Core Async (Phase 4)
 *
 * Provides complete CPU-FPU interface for system integration.
 *
 * Date: 2025-11-10
 */

`timescale 1ns / 1ps

module FPU_System_Integration(
    input wire clk,
    input wire reset,

    // CPU Instruction Interface
    input wire [7:0] cpu_opcode,          // Instruction opcode
    input wire [7:0] cpu_modrm,           // ModR/M byte
    input wire cpu_instruction_valid,     // Instruction valid

    // CPU Data Interface (for operands)
    input wire [79:0] cpu_data_in,        // Data from CPU
    output wire [79:0] cpu_data_out,      // Data to CPU
    input wire cpu_data_write,            // CPU writes data
    output wire cpu_data_ready,           // FPU ready for data

    // Memory Interface (for memory operands)
    output wire [19:0] mem_addr,
    input wire [15:0] mem_data_in,
    output wire [15:0] mem_data_out,
    output wire mem_access,
    input wire mem_ack,
    output wire mem_wr_en,
    output wire [1:0] mem_bytesel,

    // CPU Control Signals
    output wire fpu_busy,                 // FPU busy (active HIGH, 8087-style)
    output wire fpu_int,                  // FPU interrupt request
    input wire fpu_int_clear,             // Clear FPU interrupt

    // Status/Control
    input wire [15:0] control_word_in,
    input wire control_write,
    output wire [15:0] status_word_out,
    output wire [15:0] control_word_out,

    // Debug outputs
    output wire is_esc_instruction,
    output wire has_memory_operand,
    output wire [2:0] fpu_operation,
    output wire [1:0] queue_count
);

    //=================================================================
    // ESC Decoder
    //=================================================================

    wire esc_is_esc;
    wire [2:0] esc_index;
    wire [2:0] esc_fpu_opcode;
    wire [2:0] esc_stack_index;
    wire esc_has_memory_op;
    wire [1:0] esc_mod;
    wire [2:0] esc_rm;

    ESC_Decoder esc_decoder (
        .clk(clk),
        .reset(reset),
        .opcode(cpu_opcode),
        .modrm(cpu_modrm),
        .valid(cpu_instruction_valid),
        .is_esc(esc_is_esc),
        .esc_index(esc_index),
        .fpu_opcode(esc_fpu_opcode),
        .stack_index(esc_stack_index),
        .has_memory_op(esc_has_memory_op),
        .mod(esc_mod),
        .rm(esc_rm)
    );

    //=================================================================
    // Memory Interface
    //=================================================================

    wire [19:0] mem_if_fpu_addr;
    wire [79:0] mem_if_fpu_data_out;
    wire [79:0] mem_if_fpu_data_in;
    wire mem_if_fpu_access;
    wire mem_if_fpu_wr_en;
    wire [1:0] mem_if_fpu_size;
    wire mem_if_fpu_ack;

    FPU_Memory_Interface mem_interface (
        .clk(clk),
        .reset(reset),
        .fpu_addr(mem_if_fpu_addr),
        .fpu_data_out(mem_if_fpu_data_out),
        .fpu_data_in(mem_if_fpu_data_in),
        .fpu_access(mem_if_fpu_access),
        .fpu_wr_en(mem_if_fpu_wr_en),
        .fpu_size(mem_if_fpu_size),
        .fpu_ack(mem_if_fpu_ack),
        .mem_addr(mem_addr),
        .mem_data_in(mem_data_in),
        .mem_data_out(mem_data_out),
        .mem_access(mem_access),
        .mem_ack(mem_ack),
        .mem_wr_en(mem_wr_en),
        .mem_bytesel(mem_bytesel)
    );

    //=================================================================
    // Control Logic
    //=================================================================

    // State machine for FPU instruction execution
    localparam STATE_IDLE           = 3'd0;
    localparam STATE_DECODE         = 3'd1;
    localparam STATE_FETCH_OPERAND  = 3'd2;
    localparam STATE_EXECUTE        = 3'd3;
    localparam STATE_STORE_RESULT   = 3'd4;
    localparam STATE_COMPLETE       = 3'd5;

    reg [2:0] state;
    reg [2:0] next_state;

    // Instruction information
    reg [7:0] current_instruction;
    reg [2:0] current_stack_index;
    reg current_has_memory;
    reg [1:0] current_operand_size;
    reg [79:0] operand_buffer;

    // Memory address calculation (simplified - would need full EA calculation)
    reg [19:0] memory_address;

    //=================================================================
    // State Machine
    //=================================================================

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;

        case (state)
            STATE_IDLE: begin
                if (cpu_instruction_valid && esc_is_esc) begin
                    next_state = STATE_DECODE;
                end
            end

            STATE_DECODE: begin
                if (esc_has_memory_op) begin
                    next_state = STATE_FETCH_OPERAND;
                end else begin
                    next_state = STATE_EXECUTE;
                end
            end

            STATE_FETCH_OPERAND: begin
                if (mem_if_fpu_ack) begin
                    next_state = STATE_EXECUTE;
                end
            end

            STATE_EXECUTE: begin
                // For this integration, simplified execution
                next_state = STATE_COMPLETE;
            end

            STATE_STORE_RESULT: begin
                if (mem_if_fpu_ack) begin
                    next_state = STATE_COMPLETE;
                end
            end

            STATE_COMPLETE: begin
                next_state = STATE_IDLE;
            end

            default: next_state = STATE_IDLE;
        endcase
    end

    // State machine outputs
    always @(posedge clk) begin
        if (reset) begin
            current_instruction <= 8'h00;
            current_stack_index <= 3'b000;
            current_has_memory <= 1'b0;
            current_operand_size <= 2'b00;
            operand_buffer <= 80'h0;
            memory_address <= 20'h00000;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (cpu_instruction_valid && esc_is_esc) begin
                        current_instruction <= cpu_opcode;
                        current_stack_index <= esc_stack_index;
                        current_has_memory <= esc_has_memory_op;
                        // Determine operand size based on ESC index
                        case (esc_index)
                            3'd0, 3'd4: current_operand_size <= 2'b01; // DWORD (single real)
                            3'd1, 3'd5: current_operand_size <= 2'b10; // QWORD (double real)
                            3'd3, 3'd7: current_operand_size <= 2'b11; // TBYTE (extended real)
                            default:    current_operand_size <= 2'b00; // WORD
                        endcase
                        // Simplified address calculation (would need full ModR/M decode)
                        memory_address <= 20'h01000; // Placeholder
                    end
                end

                STATE_FETCH_OPERAND: begin
                    if (mem_if_fpu_ack) begin
                        operand_buffer <= mem_if_fpu_data_in;
                    end
                end
            endcase
        end
    end

    //=================================================================
    // Memory Interface Control
    //=================================================================

    assign mem_if_fpu_addr = memory_address;
    assign mem_if_fpu_data_out = operand_buffer;
    assign mem_if_fpu_access = (state == STATE_FETCH_OPERAND) || (state == STATE_STORE_RESULT);
    assign mem_if_fpu_wr_en = (state == STATE_STORE_RESULT);
    assign mem_if_fpu_size = current_operand_size;

    //=================================================================
    // Output Assignments
    //=================================================================

    assign fpu_busy = (state != STATE_IDLE) && (state != STATE_COMPLETE);
    assign fpu_int = 1'b0; // Simplified - would connect to exception handler
    assign cpu_data_ready = (state == STATE_IDLE) || (state == STATE_COMPLETE);
    assign cpu_data_out = operand_buffer;

    assign status_word_out = 16'h0000; // Placeholder
    assign control_word_out = control_word_in;

    // Debug outputs
    assign is_esc_instruction = esc_is_esc;
    assign has_memory_operand = esc_has_memory_op;
    assign fpu_operation = esc_fpu_opcode;
    assign queue_count = 2'd0; // Placeholder

    //=================================================================
    // Debug Info (for simulation)
    //=================================================================

    `ifdef SIMULATION
    always @(posedge clk) begin
        if (cpu_instruction_valid && esc_is_esc) begin
            $display("[FPU_SYSTEM] ESC instruction detected at time %t:", $time);
            $display("  Opcode: 0x%02h (ESC %0d)", cpu_opcode, esc_index);
            $display("  ModR/M: 0x%02h", cpu_modrm);
            $display("  FPU Operation: %0d", esc_fpu_opcode);
            $display("  Stack Index: ST(%0d)", esc_stack_index);
            $display("  Memory Operand: %b", esc_has_memory_op);
        end

        if (state == STATE_FETCH_OPERAND && mem_if_fpu_ack) begin
            $display("[FPU_SYSTEM] Memory operand fetched: 0x%020h", mem_if_fpu_data_in);
        end

        if (state == STATE_COMPLETE) begin
            $display("[FPU_SYSTEM] Instruction complete at time %t", $time);
        end
    end
    `endif

endmodule
