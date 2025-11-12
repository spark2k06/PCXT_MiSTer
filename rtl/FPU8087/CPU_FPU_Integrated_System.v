// Copyright 2025, Waldo Alvarez, https://pipflow.com
/**
 * CPU_FPU_Integrated_System.v
 *
 * Complete CPU+FPU Integration System
 *
 * Demonstrates full integration of:
 * - Simplified CPU control logic (ESC instruction executor)
 * - CPU_FPU_Bridge (memory-mapped interface)
 * - FPU_System_Integration (from Phase 5)
 *
 * This module serves as a proof-of-concept for Phase 6,
 * showing how a CPU would interact with the FPU through
 * memory-mapped registers.
 *
 * Date: 2025-11-10
 */

`timescale 1ns / 1ps

module CPU_FPU_Integrated_System(
    input wire clk,
    input wire reset,

    // CPU Instruction Input (from external test or instruction decoder)
    input wire [7:0] cpu_instruction_opcode,
    input wire [7:0] cpu_instruction_modrm,
    input wire cpu_instruction_valid,
    output wire cpu_instruction_ack,

    // System Memory Interface (16-bit data bus)
    output wire [19:0] sys_mem_addr,
    input wire [15:0] sys_mem_data_in,
    output wire [15:0] sys_mem_data_out,
    output wire sys_mem_access,
    input wire sys_mem_ack,
    output wire sys_mem_wr_en,
    output wire [1:0] sys_mem_bytesel,

    // System Status
    output wire system_busy,
    output wire fpu_interrupt,

    // Debug
    output wire [2:0] cpu_state,
    output wire [15:0] fpu_status_out
);

    //=================================================================
    // CPU Control FSM
    //=================================================================

    localparam [2:0] CPU_STATE_IDLE             = 3'd0;
    localparam [2:0] CPU_STATE_DECODE           = 3'd1;
    localparam [2:0] CPU_STATE_WRITE_FPU_CMD    = 3'd2;
    localparam [2:0] CPU_STATE_WAIT_FPU         = 3'd3;
    localparam [2:0] CPU_STATE_READ_RESULT      = 3'd4;
    localparam [2:0] CPU_STATE_COMPLETE         = 3'd5;

    reg [2:0] state, next_state;

    assign cpu_state = state;

    // Instruction buffer
    reg [7:0] current_opcode;
    reg [7:0] current_modrm;
    reg instruction_is_esc;

    //=================================================================
    // CPU-FPU Bridge Interface
    //=================================================================

    reg [19:0] bridge_addr;
    reg [15:0] bridge_data_in;
    wire [15:0] bridge_data_out;
    reg bridge_access;
    wire bridge_ack;
    reg bridge_wr_en;

    wire [7:0] fpu_opcode;
    wire [7:0] fpu_modrm;
    wire fpu_valid;
    wire fpu_busy;
    wire fpu_int;
    wire [79:0] fpu_data_to_fpu;
    wire [79:0] fpu_data_from_fpu;
    wire [15:0] fpu_control_word;
    wire [15:0] fpu_status_word;
    wire [19:0] fpu_mem_addr;

    CPU_FPU_Bridge bridge (
        .clk(clk),
        .reset(reset),
        .cpu_addr(bridge_addr),
        .cpu_data_in(bridge_data_in),
        .cpu_data_out(bridge_data_out),
        .cpu_access(bridge_access),
        .cpu_ack(bridge_ack),
        .cpu_wr_en(bridge_wr_en),
        .cpu_bytesel(2'b00),
        .fpu_opcode(fpu_opcode),
        .fpu_modrm(fpu_modrm),
        .fpu_instruction_valid(fpu_valid),
        .fpu_busy(fpu_busy),
        .fpu_int(fpu_int),
        .fpu_data_to_fpu(fpu_data_to_fpu),
        .fpu_data_from_fpu(fpu_data_from_fpu),
        .fpu_control_word(fpu_control_word),
        .fpu_status_word(fpu_status_word),
        .fpu_mem_addr(fpu_mem_addr)
    );

    //=================================================================
    // FPU System Integration
    //=================================================================

    wire fpu_data_ready;
    wire [79:0] fpu_cpu_data_out;
    wire fpu_is_esc;
    wire fpu_has_mem_op;
    wire [2:0] fpu_operation;
    wire [1:0] fpu_queue_count;

    FPU_System_Integration fpu_system (
        .clk(clk),
        .reset(reset),
        .cpu_opcode(fpu_opcode),
        .cpu_modrm(fpu_modrm),
        .cpu_instruction_valid(fpu_valid),
        .cpu_data_in(fpu_data_to_fpu),
        .cpu_data_out(fpu_cpu_data_out),
        .cpu_data_write(1'b0),
        .cpu_data_ready(fpu_data_ready),
        .mem_addr(sys_mem_addr),
        .mem_data_in(sys_mem_data_in),
        .mem_data_out(sys_mem_data_out),
        .mem_access(sys_mem_access),
        .mem_ack(sys_mem_ack),
        .mem_wr_en(sys_mem_wr_en),
        .mem_bytesel(sys_mem_bytesel),
        .fpu_busy(fpu_busy),
        .fpu_int(fpu_int),
        .fpu_int_clear(1'b0),
        .control_word_in(fpu_control_word),
        .control_write(1'b0),
        .status_word_out(fpu_status_word),
        .control_word_out(),
        .is_esc_instruction(fpu_is_esc),
        .has_memory_operand(fpu_has_mem_op),
        .fpu_operation(fpu_operation),
        .queue_count(fpu_queue_count)
    );

    assign fpu_data_from_fpu = fpu_cpu_data_out;

    //=================================================================
    // CPU State Machine
    //=================================================================

    always @(posedge clk) begin
        if (reset) begin
            state <= CPU_STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;

        case (state)
            CPU_STATE_IDLE: begin
                if (cpu_instruction_valid) begin
                    next_state = CPU_STATE_DECODE;
                end
            end

            CPU_STATE_DECODE: begin
                // Check if ESC instruction (D8-DF)
                if (instruction_is_esc) begin
                    next_state = CPU_STATE_WRITE_FPU_CMD;
                end else begin
                    // Non-ESC instruction, complete immediately
                    next_state = CPU_STATE_COMPLETE;
                end
            end

            CPU_STATE_WRITE_FPU_CMD: begin
                if (bridge_ack) begin
                    next_state = CPU_STATE_WAIT_FPU;
                end
            end

            CPU_STATE_WAIT_FPU: begin
                // Poll FPU status until not busy
                if (bridge_ack && !fpu_busy) begin
                    next_state = CPU_STATE_COMPLETE;
                end
            end

            CPU_STATE_COMPLETE: begin
                next_state = CPU_STATE_IDLE;
            end

            default: next_state = CPU_STATE_IDLE;
        endcase
    end

    //=================================================================
    // CPU State Machine Outputs
    //=================================================================

    always @(posedge clk) begin
        if (reset) begin
            current_opcode <= 8'h00;
            current_modrm <= 8'h00;
            instruction_is_esc <= 1'b0;
            bridge_addr <= 20'h00000;
            bridge_data_in <= 16'h0000;
            bridge_access <= 1'b0;
            bridge_wr_en <= 1'b0;
        end else begin
            // Default: no bridge access
            bridge_access <= 1'b0;
            bridge_wr_en <= 1'b0;

            case (state)
                CPU_STATE_IDLE: begin
                    if (cpu_instruction_valid) begin
                        // Capture instruction
                        current_opcode <= cpu_instruction_opcode;
                        current_modrm <= cpu_instruction_modrm;
                        // Check if ESC (D8-DF)
                        instruction_is_esc <= (cpu_instruction_opcode[7:3] == 5'b11011);
                    end
                end

                CPU_STATE_WRITE_FPU_CMD: begin
                    // Write opcode and ModR/M to FPU_CMD register (0xFFE0)
                    bridge_addr <= 20'hFFE0;
                    bridge_data_in <= {current_modrm, current_opcode};
                    bridge_access <= 1'b1;
                    bridge_wr_en <= 1'b1;
                end

                CPU_STATE_WAIT_FPU: begin
                    // Read FPU_STATUS register (0xFFE2) to check BUSY
                    bridge_addr <= 20'hFFE2;
                    bridge_access <= 1'b1;
                    bridge_wr_en <= 1'b0;
                end

                default: ;
            endcase
        end
    end

    //=================================================================
    // Output Assignments
    //=================================================================

    assign cpu_instruction_ack = (state == CPU_STATE_COMPLETE);
    assign system_busy = (state != CPU_STATE_IDLE);
    assign fpu_interrupt = fpu_int;
    assign fpu_status_out = fpu_status_word;

    //=================================================================
    // Debug Info (for simulation)
    //=================================================================

    `ifdef SIMULATION
    always @(posedge clk) begin
        if (cpu_instruction_valid && state == CPU_STATE_IDLE) begin
            $display("[CPU_FPU_SYSTEM] Instruction received at time %t:", $time);
            $display("  Opcode: 0x%02h", cpu_instruction_opcode);
            $display("  ModR/M: 0x%02h", cpu_instruction_modrm);
            $display("  Is ESC: %b", (cpu_instruction_opcode[7:3] == 5'b11011));
        end

        if (state == CPU_STATE_WRITE_FPU_CMD && bridge_ack) begin
            $display("[CPU_FPU_SYSTEM] FPU command written at time %t", $time);
        end

        if (state == CPU_STATE_WAIT_FPU && bridge_ack) begin
            $display("[CPU_FPU_SYSTEM] FPU status polled at time %t: BUSY=%b", $time, fpu_busy);
        end

        if (state == CPU_STATE_COMPLETE) begin
            $display("[CPU_FPU_SYSTEM] Instruction complete at time %t", $time);
        end
    end
    `endif

endmodule
