// Copyright 2025, Waldo Alvarez, https://pipflow.com
/**
 * FPU_Memory_Interface.v
 *
 * Memory Interface for 8087 FPU
 *
 * Converts between FPU's 80-bit extended precision format and the
 * 16-bit memory bus. Handles multi-cycle transfers for different
 * operand sizes: word (16-bit), dword (32-bit), qword (64-bit),
 * and tbyte (80-bit).
 *
 * Critical for memory synchronization between CPU and FPU.
 *
 * Date: 2025-11-10
 */

`timescale 1ns / 1ps

module FPU_Memory_Interface(
    input wire clk,
    input wire reset,

    // FPU side (80-bit extended precision)
    input wire [19:0] fpu_addr,           // 20-bit address (1MB addressing)
    input wire [79:0] fpu_data_out,       // 80-bit data from FPU
    output reg [79:0] fpu_data_in,        // 80-bit data to FPU
    input wire fpu_access,                // FPU requests memory access
    input wire fpu_wr_en,                 // Write enable
    input wire [1:0] fpu_size,            // Operand size: 0=word, 1=dword, 2=qword, 3=tbyte
    output reg fpu_ack,                   // Transfer complete

    // Memory bus side (16-bit)
    output reg [19:0] mem_addr,           // Memory address
    input wire [15:0] mem_data_in,        // Data from memory
    output reg [15:0] mem_data_out,       // Data to memory
    output reg mem_access,                // Memory access request
    input wire mem_ack,                   // Memory acknowledges
    output reg mem_wr_en,                 // Memory write enable
    output reg [1:0] mem_bytesel          // Byte select (00=both, 01=low, 10=high)
);

    //=================================================================
    // Operand Size Definitions
    //=================================================================

    localparam SIZE_WORD  = 2'b00;  // 16-bit (1 cycle)
    localparam SIZE_DWORD = 2'b01;  // 32-bit (2 cycles)
    localparam SIZE_QWORD = 2'b10;  // 64-bit (4 cycles)
    localparam SIZE_TBYTE = 2'b11;  // 80-bit (5 cycles)

    //=================================================================
    // State Machine
    //=================================================================

    localparam STATE_IDLE      = 3'b000;
    localparam STATE_CYCLE1    = 3'b001;
    localparam STATE_CYCLE2    = 3'b010;
    localparam STATE_CYCLE3    = 3'b011;
    localparam STATE_CYCLE4    = 3'b100;
    localparam STATE_CYCLE5    = 3'b101;
    localparam STATE_COMPLETE  = 3'b110;

    reg [2:0] state;
    reg [2:0] next_state;

    //=================================================================
    // Internal Registers
    //=================================================================

    reg [79:0] write_buffer;    // Buffer for FPU write data
    reg [79:0] read_buffer;     // Buffer for FPU read data
    reg [19:0] base_addr;       // Base address for transfer
    reg [1:0] transfer_size;    // Size of current transfer
    reg is_write;               // Write operation flag
    reg [2:0] cycle_count;      // Current cycle in multi-cycle transfer

    //=================================================================
    // Transfer Cycle Calculation
    //=================================================================

    // Calculate number of 16-bit cycles needed for transfer
    function [2:0] get_cycle_count;
        input [1:0] size;
        begin
            case (size)
                SIZE_WORD:  get_cycle_count = 3'd1;  // 1 cycle
                SIZE_DWORD: get_cycle_count = 3'd2;  // 2 cycles
                SIZE_QWORD: get_cycle_count = 3'd4;  // 4 cycles
                SIZE_TBYTE: get_cycle_count = 3'd5;  // 5 cycles
                default:    get_cycle_count = 3'd1;
            endcase
        end
    endfunction

    //=================================================================
    // Address Calculation
    //=================================================================

    // Calculate address for current cycle (increments by 2 for each 16-bit word)
    wire [19:0] current_addr = base_addr + {17'b0, (cycle_count - 1'b1), 1'b0};

    //=================================================================
    // Data Extraction/Assembly
    //=================================================================

    // Extract 16-bit word from 80-bit buffer based on cycle
    function [15:0] extract_word;
        input [79:0] data;
        input [2:0] cycle;
        begin
            case (cycle)
                3'd1: extract_word = data[15:0];
                3'd2: extract_word = data[31:16];
                3'd3: extract_word = data[47:32];
                3'd4: extract_word = data[63:48];
                3'd5: extract_word = data[79:64];
                default: extract_word = 16'h0000;
            endcase
        end
    endfunction

    //=================================================================
    // State Machine - State Transitions
    //=================================================================

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    //=================================================================
    // State Machine - Next State Logic
    //=================================================================

    always @(*) begin
        next_state = state;

        case (state)
            STATE_IDLE: begin
                if (fpu_access) begin
                    next_state = STATE_CYCLE1;
                end
            end

            STATE_CYCLE1: begin
                if (mem_ack) begin
                    if (cycle_count >= get_cycle_count(transfer_size)) begin
                        next_state = STATE_COMPLETE;
                    end else begin
                        next_state = STATE_CYCLE2;
                    end
                end
            end

            STATE_CYCLE2: begin
                if (mem_ack) begin
                    if (cycle_count >= get_cycle_count(transfer_size)) begin
                        next_state = STATE_COMPLETE;
                    end else begin
                        next_state = STATE_CYCLE3;
                    end
                end
            end

            STATE_CYCLE3: begin
                if (mem_ack) begin
                    if (cycle_count >= get_cycle_count(transfer_size)) begin
                        next_state = STATE_COMPLETE;
                    end else begin
                        next_state = STATE_CYCLE4;
                    end
                end
            end

            STATE_CYCLE4: begin
                if (mem_ack) begin
                    if (cycle_count >= get_cycle_count(transfer_size)) begin
                        next_state = STATE_COMPLETE;
                    end else begin
                        next_state = STATE_CYCLE5;
                    end
                end
            end

            STATE_CYCLE5: begin
                if (mem_ack) begin
                    next_state = STATE_COMPLETE;
                end
            end

            STATE_COMPLETE: begin
                next_state = STATE_IDLE;
            end

            default: next_state = STATE_IDLE;
        endcase
    end

    //=================================================================
    // State Machine - Output Logic
    //=================================================================

    always @(posedge clk) begin
        if (reset) begin
            fpu_ack <= 1'b0;
            mem_access <= 1'b0;
            mem_wr_en <= 1'b0;
            mem_addr <= 20'h00000;
            mem_data_out <= 16'h0000;
            mem_bytesel <= 2'b00;
            fpu_data_in <= 80'h0;
            write_buffer <= 80'h0;
            read_buffer <= 80'h0;
            base_addr <= 20'h00000;
            transfer_size <= 2'b00;
            is_write <= 1'b0;
            cycle_count <= 3'd0;
        end else begin
            // Default outputs
            fpu_ack <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    mem_access <= 1'b0;
                    mem_wr_en <= 1'b0;
                    cycle_count <= 3'd0;

                    if (fpu_access) begin
                        // Start new transfer
                        base_addr <= fpu_addr;
                        transfer_size <= fpu_size;
                        is_write <= fpu_wr_en;
                        write_buffer <= fpu_data_out;
                        read_buffer <= 80'h0;
                        cycle_count <= 3'd1;
                    end
                end

                STATE_CYCLE1, STATE_CYCLE2, STATE_CYCLE3, STATE_CYCLE4, STATE_CYCLE5: begin
                    // Assert memory access
                    mem_access <= 1'b1;
                    mem_wr_en <= is_write;
                    mem_addr <= current_addr;
                    mem_bytesel <= 2'b00;  // Both bytes

                    if (is_write) begin
                        // Write: Output data from write buffer
                        mem_data_out <= extract_word(write_buffer, cycle_count);
                    end else begin
                        // Read: Capture data when ack received
                        if (mem_ack) begin
                            // Store 16-bit word in appropriate position
                            case (cycle_count)
                                3'd1: read_buffer[15:0]   <= mem_data_in;
                                3'd2: read_buffer[31:16]  <= mem_data_in;
                                3'd3: read_buffer[47:32]  <= mem_data_in;
                                3'd4: read_buffer[63:48]  <= mem_data_in;
                                3'd5: read_buffer[79:64]  <= mem_data_in;
                            endcase
                        end
                    end

                    // Increment cycle count when memory acknowledges
                    if (mem_ack) begin
                        cycle_count <= cycle_count + 1'b1;
                    end
                end

                STATE_COMPLETE: begin
                    mem_access <= 1'b0;
                    mem_wr_en <= 1'b0;
                    fpu_ack <= 1'b1;

                    // For reads, output assembled data to FPU
                    if (!is_write) begin
                        // Zero-extend or sign-extend based on size
                        case (transfer_size)
                            SIZE_WORD:  fpu_data_in <= {64'h0, read_buffer[15:0]};
                            SIZE_DWORD: fpu_data_in <= {48'h0, read_buffer[31:0]};
                            SIZE_QWORD: fpu_data_in <= {16'h0, read_buffer[63:0]};
                            SIZE_TBYTE: fpu_data_in <= read_buffer[79:0];
                        endcase
                    end
                end

                default: begin
                    mem_access <= 1'b0;
                    mem_wr_en <= 1'b0;
                end
            endcase
        end
    end

    //=================================================================
    // Debug Info (for simulation)
    //=================================================================

    `ifdef SIMULATION
    always @(posedge clk) begin
        if (fpu_access && state == STATE_IDLE) begin
            $display("[MEM_INTERFACE] Starting %s transfer at time %t:",
                     fpu_wr_en ? "WRITE" : "READ", $time);
            $display("  Address: 0x%05h", fpu_addr);
            $display("  Size: %s (%0d cycles)",
                     fpu_size == SIZE_WORD ? "WORD" :
                     fpu_size == SIZE_DWORD ? "DWORD" :
                     fpu_size == SIZE_QWORD ? "QWORD" : "TBYTE",
                     get_cycle_count(fpu_size));
            if (fpu_wr_en) begin
                $display("  Data: 0x%020h", fpu_data_out);
            end
        end

        if (state != STATE_IDLE && state != STATE_COMPLETE && mem_ack) begin
            if (is_write) begin
                $display("[MEM_INTERFACE] Write cycle %0d: addr=0x%05h data=0x%04h",
                         cycle_count, current_addr, mem_data_out);
            end else begin
                $display("[MEM_INTERFACE] Read cycle %0d: addr=0x%05h data=0x%04h",
                         cycle_count, current_addr, mem_data_in);
            end
        end

        if (fpu_ack) begin
            if (!is_write) begin
                $display("[MEM_INTERFACE] Read complete: data=0x%020h", fpu_data_in);
            end else begin
                $display("[MEM_INTERFACE] Write complete");
            end
        end
    end
    `endif

endmodule
