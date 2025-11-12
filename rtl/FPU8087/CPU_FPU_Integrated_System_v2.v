// Copyright 2025, Waldo Alvarez, https://pipflow.com
/**
 * CPU_FPU_Integrated_System_v2.v
 *
 * Phase 8: Authentic Coprocessor Interface
 *
 * Complete CPU+FPU integration using dedicated coprocessor ports
 * instead of memory-mapped registers. This matches the authentic
 * 8086+8087 architecture more closely.
 *
 * Key Improvements over v1:
 * - 50% faster instruction dispatch (3 cycles vs 6 cycles)
 * - 50% faster BUSY polling (1 cycle vs 2 cycles)
 * - No memory address management overhead
 * - More authentic to original 8087 design
 *
 * Date: 2025-11-10
 */

`timescale 1ns / 1ps

module CPU_FPU_Integrated_System_v2(
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
    output wire fpu_status_busy,
    output wire fpu_status_error
);

    //=================================================================
    // CPU Control FSM (Simplified for Dedicated Ports)
    //=================================================================

    localparam [2:0] CPU_STATE_IDLE         = 3'd0;
    localparam [2:0] CPU_STATE_DECODE       = 3'd1;
    localparam [2:0] CPU_STATE_DISPATCH_FPU = 3'd2;  // Send to FPU via ports
    localparam [2:0] CPU_STATE_WAIT_FPU     = 3'd3;  // Poll BUSY
    localparam [2:0] CPU_STATE_COMPLETE     = 3'd4;

    reg [2:0] state, next_state;

    assign cpu_state = state;

    // Instruction buffer
    reg [7:0] current_opcode;
    reg [7:0] current_modrm;
    reg instruction_is_esc;

    //=================================================================
    // Coprocessor Port Signals
    //=================================================================

    // CPU to FPU
    reg [7:0] cpu_fpu_opcode_reg;
    reg [7:0] cpu_fpu_modrm_reg;
    reg cpu_fpu_cmd_valid_reg;
    reg [19:0] cpu_fpu_mem_addr_reg;

    // FPU to CPU
    wire cpu_fpu_busy;
    wire cpu_fpu_error;
    wire cpu_fpu_int;

    // Bus control
    wire cpu_bus_idle;
    wire fpu_has_bus;

    assign cpu_bus_idle = (state == CPU_STATE_IDLE || state == CPU_STATE_WAIT_FPU);

    //=================================================================
    // FPU System Integration Interface
    //=================================================================

    wire [7:0] fpu_opcode;
    wire [7:0] fpu_modrm;
    wire fpu_instruction_valid;
    wire [19:0] fpu_mem_addr;
    wire fpu_busy;
    wire fpu_error;
    wire fpu_int_request;
    wire fpu_bus_request;
    wire fpu_bus_grant;

    //=================================================================
    // Coprocessor Bridge (Dedicated Ports)
    //=================================================================

    CPU_FPU_Coprocessor_Bridge_v2 bridge (
        .clk(clk),
        .reset(reset),

        // CPU Side
        .cpu_fpu_opcode(cpu_fpu_opcode_reg),
        .cpu_fpu_modrm(cpu_fpu_modrm_reg),
        .cpu_fpu_cmd_valid(cpu_fpu_cmd_valid_reg),
        .cpu_fpu_mem_addr(cpu_fpu_mem_addr_reg),
        .cpu_fpu_busy(cpu_fpu_busy),
        .cpu_fpu_error(cpu_fpu_error),
        .cpu_fpu_int(cpu_fpu_int),
        .cpu_bus_idle(cpu_bus_idle),
        .fpu_has_bus(fpu_has_bus),

        // FPU Side
        .fpu_opcode(fpu_opcode),
        .fpu_modrm(fpu_modrm),
        .fpu_instruction_valid(fpu_instruction_valid),
        .fpu_mem_addr(fpu_mem_addr),
        .fpu_busy(fpu_busy),
        .fpu_error(fpu_error),
        .fpu_int_request(fpu_int_request),
        .fpu_bus_request(fpu_bus_request),
        .fpu_bus_grant(fpu_bus_grant)
    );

    //=================================================================
    // FPU System Integration (from Phase 5)
    //=================================================================

    wire [19:0] fpu_sys_mem_addr;
    wire [15:0] fpu_sys_mem_data_out;
    wire fpu_sys_mem_access;
    wire fpu_sys_mem_wr_en;

    FPU_System_Integration fpu_system (
        .clk(clk),
        .reset(reset),

        // CPU Interface
        .cpu_opcode(fpu_opcode),
        .cpu_modrm(fpu_modrm),
        .cpu_instruction_valid(fpu_instruction_valid),

        // Memory Interface
        .mem_addr(fpu_sys_mem_addr),
        .mem_data_in(sys_mem_data_in),
        .mem_data_out(fpu_sys_mem_data_out),
        .mem_access(fpu_sys_mem_access),
        .mem_ack(sys_mem_ack & fpu_has_bus),  // Only ack when FPU has bus
        .mem_wr_en(fpu_sys_mem_wr_en),
        .mem_bytesel(),  // Not used

        // Status
        .fpu_busy(fpu_busy),
        .fpu_int(fpu_int_request)
    );

    assign fpu_bus_request = fpu_sys_mem_access;

    //=================================================================
    // Memory Bus Arbitration
    //=================================================================

    // FPU gets bus when granted, otherwise CPU (if needed)
    assign sys_mem_addr = fpu_has_bus ? fpu_sys_mem_addr : 20'h00000;
    assign sys_mem_data_out = fpu_has_bus ? fpu_sys_mem_data_out : 16'h0000;
    assign sys_mem_access = fpu_has_bus ? fpu_sys_mem_access : 1'b0;
    assign sys_mem_wr_en = fpu_has_bus ? fpu_sys_mem_wr_en : 1'b0;
    assign sys_mem_bytesel = 2'b00;

    //=================================================================
    // CPU State Machine
    //=================================================================

    // State register
    always @(posedge clk) begin
        if (reset) begin
            state <= CPU_STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Next state logic
    always @(*) begin
        next_state = state;

        case (state)
            CPU_STATE_IDLE: begin
                if (cpu_instruction_valid) begin
                    next_state = CPU_STATE_DECODE;
                end
            end

            CPU_STATE_DECODE: begin
                // Check if ESC instruction
                if (instruction_is_esc) begin
                    next_state = CPU_STATE_DISPATCH_FPU;
                end else begin
                    // Non-ESC: complete immediately
                    next_state = CPU_STATE_COMPLETE;
                end
            end

            CPU_STATE_DISPATCH_FPU: begin
                // Instruction dispatched, now wait for FPU
                next_state = CPU_STATE_WAIT_FPU;
            end

            CPU_STATE_WAIT_FPU: begin
                // Poll FPU BUSY signal
                if (!cpu_fpu_busy) begin
                    // FPU completed
                    next_state = CPU_STATE_COMPLETE;
                end
            end

            CPU_STATE_COMPLETE: begin
                // Return to idle
                next_state = CPU_STATE_IDLE;
            end

            default: begin
                next_state = CPU_STATE_IDLE;
            end
        endcase
    end

    //=================================================================
    // CPU Control Outputs
    //=================================================================

    // Latch instruction
    always @(posedge clk) begin
        if (reset) begin
            current_opcode <= 8'h00;
            current_modrm <= 8'h00;
            instruction_is_esc <= 1'b0;
        end else begin
            if (state == CPU_STATE_IDLE && cpu_instruction_valid) begin
                current_opcode <= cpu_instruction_opcode;
                current_modrm <= cpu_instruction_modrm;
                // Detect ESC instructions (D8-DF)
                instruction_is_esc <= (cpu_instruction_opcode[7:3] == 5'b11011);
            end
        end
    end

    // FPU coprocessor port control
    always @(posedge clk) begin
        if (reset) begin
            cpu_fpu_opcode_reg <= 8'h00;
            cpu_fpu_modrm_reg <= 8'h00;
            cpu_fpu_cmd_valid_reg <= 1'b0;
            cpu_fpu_mem_addr_reg <= 20'h00000;
        end else begin
            // Default: no command valid
            cpu_fpu_cmd_valid_reg <= 1'b0;

            if (state == CPU_STATE_DISPATCH_FPU) begin
                // Send instruction to FPU via dedicated ports
                cpu_fpu_opcode_reg <= current_opcode;
                cpu_fpu_modrm_reg <= current_modrm;
                cpu_fpu_cmd_valid_reg <= 1'b1;  // 1-cycle pulse
                cpu_fpu_mem_addr_reg <= 20'h00000;  // Could add EA calculation here
            end
        end
    end

    // Acknowledge instruction completion
    assign cpu_instruction_ack = (state == CPU_STATE_COMPLETE);

    // System status
    assign system_busy = (state != CPU_STATE_IDLE);
    assign fpu_interrupt = cpu_fpu_int;

    // Debug outputs
    assign fpu_status_busy = cpu_fpu_busy;
    assign fpu_status_error = cpu_fpu_error;

    //=================================================================
    // Debug Display (Simulation)
    //=================================================================

    `ifdef SIMULATION
    always @(posedge clk) begin
        case (state)
            CPU_STATE_IDLE: begin
                if (cpu_instruction_valid) begin
                    $display("[CPU_FPU_SYSTEM_V2] Instruction received at time %t:", $time);
                    $display("  Opcode: 0x%02h", cpu_instruction_opcode);
                    $display("  ModR/M: 0x%02h", cpu_instruction_modrm);
                end
            end

            CPU_STATE_DECODE: begin
                $display("[CPU_FPU_SYSTEM_V2] Decode: ESC=%b", instruction_is_esc);
            end

            CPU_STATE_DISPATCH_FPU: begin
                $display("[CPU_FPU_SYSTEM_V2] Dispatching to FPU via dedicated ports");
            end

            CPU_STATE_WAIT_FPU: begin
                if (cpu_fpu_busy) begin
                    $display("[CPU_FPU_SYSTEM_V2] Waiting for FPU (BUSY=1)");
                end else begin
                    $display("[CPU_FPU_SYSTEM_V2] FPU completed (BUSY=0)");
                end
            end

            CPU_STATE_COMPLETE: begin
                $display("[CPU_FPU_SYSTEM_V2] Instruction complete");
            end
        endcase
    end
    `endif

    //=================================================================
    // Performance Counters (Simulation)
    //=================================================================

    `ifdef SIMULATION
    integer total_instructions;
    integer total_esc_instructions;
    integer total_cycles;
    integer esc_dispatch_cycles;
    integer esc_wait_cycles;

    initial begin
        total_instructions = 0;
        total_esc_instructions = 0;
        total_cycles = 0;
        esc_dispatch_cycles = 0;
        esc_wait_cycles = 0;
    end

    always @(posedge clk) begin
        if (reset) begin
            total_instructions <= 0;
            total_esc_instructions <= 0;
            total_cycles <= 0;
            esc_dispatch_cycles <= 0;
            esc_wait_cycles <= 0;
        end else begin
            if (state == CPU_STATE_COMPLETE) begin
                total_instructions <= total_instructions + 1;
                if (instruction_is_esc) begin
                    total_esc_instructions <= total_esc_instructions + 1;
                end
            end

            if (state == CPU_STATE_DISPATCH_FPU) begin
                esc_dispatch_cycles <= esc_dispatch_cycles + 1;
            end

            if (state == CPU_STATE_WAIT_FPU) begin
                esc_wait_cycles <= esc_wait_cycles + 1;
            end

            if (state != CPU_STATE_IDLE) begin
                total_cycles <= total_cycles + 1;
            end
        end
    end
    `endif

endmodule
