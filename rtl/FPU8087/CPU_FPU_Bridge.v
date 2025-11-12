// Copyright 2025, Waldo Alvarez, https://pipflow.com
/**
 * CPU_FPU_Bridge.v
 *
 * Memory-Mapped Bridge between s80x86 CPU and 8087 FPU
 *
 * Provides memory-mapped registers for CPU-FPU communication:
 * - 0xFFE0-0xFFFF: FPU register space (32 bytes)
 *
 * Registers:
 * - 0xFFE0: FPU_CMD (W) - Command: Opcode + ModR/M
 * - 0xFFE2: FPU_STATUS (R) - Status: BUSY, exceptions, flags
 * - 0xFFE4: FPU_CONTROL (R/W) - Control word
 * - 0xFFE6-0xFFEE: FPU_DATA (R/W) - 80-bit data (5 words)
 * - 0xFFF0: FPU_ADDR (W) - Memory address for operands
 *
 * Date: 2025-11-10
 */

`timescale 1ns / 1ps

module CPU_FPU_Bridge(
    input wire clk,
    input wire reset,

    // CPU Side (Memory-Mapped Interface)
    input wire [19:0] cpu_addr,          // CPU address bus
    input wire [15:0] cpu_data_in,       // Data from CPU
    output reg [15:0] cpu_data_out,      // Data to CPU
    input wire cpu_access,               // CPU requests access
    output reg cpu_ack,                  // Bridge acknowledges
    input wire cpu_wr_en,                // Write enable
    input wire [1:0] cpu_bytesel,        // Byte select

    // FPU Side (connects to FPU_System_Integration)
    output reg [7:0] fpu_opcode,         // FPU instruction opcode
    output reg [7:0] fpu_modrm,          // FPU ModR/M byte
    output reg fpu_instruction_valid,    // Instruction valid pulse
    input wire fpu_busy,                 // FPU busy signal
    input wire fpu_int,                  // FPU interrupt request
    output reg [79:0] fpu_data_to_fpu,   // Data to FPU
    input wire [79:0] fpu_data_from_fpu, // Data from FPU
    output reg [15:0] fpu_control_word,  // FPU control word
    input wire [15:0] fpu_status_word,   // FPU status word
    output reg [19:0] fpu_mem_addr       // Memory address for FPU operands
);

    //=================================================================
    // FPU Register Space: 0xFFE0-0xFFFF
    //=================================================================

    localparam [19:0] FPU_BASE_ADDR    = 20'hFFE0;
    localparam [19:0] FPU_CMD          = 20'hFFE0;  // Command (Opcode + ModR/M)
    localparam [19:0] FPU_STATUS       = 20'hFFE2;  // Status register
    localparam [19:0] FPU_CONTROL      = 20'hFFE4;  // Control register
    localparam [19:0] FPU_DATA_W0      = 20'hFFE6;  // Data word 0 (bits 15:0)
    localparam [19:0] FPU_DATA_W1      = 20'hFFE8;  // Data word 1 (bits 31:16)
    localparam [19:0] FPU_DATA_W2      = 20'hFFEA;  // Data word 2 (bits 47:32)
    localparam [19:0] FPU_DATA_W3      = 20'hFFEC;  // Data word 3 (bits 63:48)
    localparam [19:0] FPU_DATA_W4      = 20'hFFEE;  // Data word 4 (bits 79:64)
    localparam [19:0] FPU_ADDR_LO      = 20'hFFF0;  // Address low word
    localparam [19:0] FPU_ADDR_HI      = 20'hFFF2;  // Address high word

    //=================================================================
    // Address Decoder
    //=================================================================

    wire is_fpu_space = (cpu_addr[19:5] == 15'h7FF);  // 0xFFE0-0xFFFF

    wire is_fpu_cmd      = (cpu_addr == FPU_CMD);
    wire is_fpu_status   = (cpu_addr == FPU_STATUS);
    wire is_fpu_control  = (cpu_addr == FPU_CONTROL);
    wire is_fpu_data_w0  = (cpu_addr == FPU_DATA_W0);
    wire is_fpu_data_w1  = (cpu_addr == FPU_DATA_W1);
    wire is_fpu_data_w2  = (cpu_addr == FPU_DATA_W2);
    wire is_fpu_data_w3  = (cpu_addr == FPU_DATA_W3);
    wire is_fpu_data_w4  = (cpu_addr == FPU_DATA_W4);
    wire is_fpu_addr_lo  = (cpu_addr == FPU_ADDR_LO);
    wire is_fpu_addr_hi  = (cpu_addr == FPU_ADDR_HI);

    //=================================================================
    // Internal Registers
    //=================================================================

    reg [15:0] cmd_reg;           // Stores opcode (low byte) and ModR/M (high byte)
    reg [15:0] status_reg;        // FPU status (synthesized from fpu_busy, fpu_int, fpu_status_word)
    reg [79:0] data_buffer;       // 80-bit data buffer for transfers
    reg cmd_written;              // Flag: command has been written
    reg execute_pending;          // Flag: instruction ready to execute

    //=================================================================
    // Status Register Composition
    //=================================================================

    // Status register format:
    // Bit 15: BUSY
    // Bit 14: INT
    // Bits 13-0: FPU status word flags

    always @(*) begin
        status_reg = {fpu_busy, fpu_int, fpu_status_word[13:0]};
    end

    //=================================================================
    // Memory-Mapped Register Access
    //=================================================================

    always @(posedge clk) begin
        if (reset) begin
            cpu_ack <= 1'b0;
            cpu_data_out <= 16'h0000;
            cmd_reg <= 16'h0000;
            fpu_control_word <= 16'h037F;  // Default 8087 control word
            data_buffer <= 80'h0;
            fpu_mem_addr <= 20'h00000;
            cmd_written <= 1'b0;
            execute_pending <= 1'b0;
            fpu_instruction_valid <= 1'b0;
            fpu_opcode <= 8'h00;
            fpu_modrm <= 8'h00;
            fpu_data_to_fpu <= 80'h0;
        end else begin
            // Default: no ack, no instruction valid
            cpu_ack <= 1'b0;
            fpu_instruction_valid <= 1'b0;

            // Handle execute_pending: send instruction to FPU
            if (execute_pending && !fpu_busy) begin
                fpu_opcode <= cmd_reg[7:0];
                fpu_modrm <= cmd_reg[15:8];
                fpu_instruction_valid <= 1'b1;
                fpu_data_to_fpu <= data_buffer;
                execute_pending <= 1'b0;
                cmd_written <= 1'b0;
            end

            // Handle CPU access
            if (cpu_access && is_fpu_space) begin
                cpu_ack <= 1'b1;  // Acknowledge immediately

                if (cpu_wr_en) begin
                    // *** Write Operations ***
                    case (1'b1)
                        is_fpu_cmd: begin
                            // Write command register (opcode + ModR/M)
                            cmd_reg <= cpu_data_in;
                            cmd_written <= 1'b1;
                            // Trigger execution when both command and data ready
                            if (!fpu_busy) begin
                                execute_pending <= 1'b1;
                            end
                        end

                        is_fpu_control: begin
                            // Write control word
                            fpu_control_word <= cpu_data_in;
                        end

                        is_fpu_data_w0: data_buffer[15:0]   <= cpu_data_in;
                        is_fpu_data_w1: data_buffer[31:16]  <= cpu_data_in;
                        is_fpu_data_w2: data_buffer[47:32]  <= cpu_data_in;
                        is_fpu_data_w3: data_buffer[63:48]  <= cpu_data_in;
                        is_fpu_data_w4: data_buffer[79:64]  <= cpu_data_in;

                        is_fpu_addr_lo: fpu_mem_addr[15:0]  <= cpu_data_in;
                        is_fpu_addr_hi: fpu_mem_addr[19:16] <= cpu_data_in[3:0];

                        default: ;
                    endcase
                end else begin
                    // *** Read Operations ***
                    case (1'b1)
                        is_fpu_status: begin
                            // Read status register
                            cpu_data_out <= status_reg;
                        end

                        is_fpu_control: begin
                            // Read control word
                            cpu_data_out <= fpu_control_word;
                        end

                        is_fpu_data_w0: cpu_data_out <= fpu_data_from_fpu[15:0];
                        is_fpu_data_w1: cpu_data_out <= fpu_data_from_fpu[31:16];
                        is_fpu_data_w2: cpu_data_out <= fpu_data_from_fpu[47:32];
                        is_fpu_data_w3: cpu_data_out <= fpu_data_from_fpu[63:48];
                        is_fpu_data_w4: cpu_data_out <= fpu_data_from_fpu[79:64];

                        is_fpu_addr_lo: cpu_data_out <= fpu_mem_addr[15:0];
                        is_fpu_addr_hi: cpu_data_out <= {12'h000, fpu_mem_addr[19:16]};

                        default: cpu_data_out <= 16'h0000;
                    endcase
                end
            end
        end
    end

    //=================================================================
    // Debug Info (for simulation)
    //=================================================================

    `ifdef SIMULATION
    always @(posedge clk) begin
        if (cpu_access && cpu_wr_en && is_fpu_cmd) begin
            $display("[CPU_FPU_BRIDGE] Command written at time %t:", $time);
            $display("  Opcode: 0x%02h", cpu_data_in[7:0]);
            $display("  ModR/M: 0x%02h", cpu_data_in[15:8]);
        end

        if (fpu_instruction_valid) begin
            $display("[CPU_FPU_BRIDGE] Sending instruction to FPU at time %t:", $time);
            $display("  Opcode: 0x%02h", fpu_opcode);
            $display("  ModR/M: 0x%02h", fpu_modrm);
            $display("  Data: 0x%020h", fpu_data_to_fpu);
        end

        if (cpu_access && !cpu_wr_en && is_fpu_status) begin
            $display("[CPU_FPU_BRIDGE] Status read at time %t: 0x%04h (BUSY=%b, INT=%b)",
                     $time, status_reg, fpu_busy, fpu_int);
        end
    end
    `endif

endmodule
