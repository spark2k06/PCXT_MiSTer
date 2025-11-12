// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// CPU-FPU Adapter Module
//
// This module adapts the CPU's data bus interface to the FPU interface.
// It translates CPU memory/IO cycles into FPU operations.
//
// CPU Side: Standard 8086 memory-mapped interface
// FPU Side: FPU8087_Integrated interface signals
//=====================================================================

module CPU_FPU_Adapter(
    input wire clk,
    input wire reset,

    // ========== CPU Side (8086-compatible) ==========

    // Address/Data Bus
    input wire [19:0]  cpu_address,         // Full 20-bit address
    input wire [15:0]  cpu_data_in,         // Data from CPU
    output reg [15:0]  cpu_data_out,        // Data to CPU
    input wire         cpu_read,            // CPU read cycle
    input wire         cpu_write,           // CPU write cycle
    input wire [1:0]   cpu_bytesel,         // Byte select (00=word, 01=low, 10=high)
    output reg         cpu_ready,           // Ready signal to CPU

    // FPU-specific signals
    input wire         cpu_fpu_escape,      // CPU decoded ESC instruction
    input wire [7:0]   cpu_opcode,          // Current opcode being executed
    input wire [7:0]   cpu_modrm,           // ModR/M byte

    // ========== FPU Side ==========

    // To/From FPU8087_Integrated
    output reg         fpu_instr_valid,
    output reg [7:0]   fpu_opcode,
    output reg [7:0]   fpu_modrm,
    input wire         fpu_instr_ack,

    output reg         fpu_data_write,
    output reg         fpu_data_read,
    output reg [2:0]   fpu_data_size,
    output reg [79:0]  fpu_data_in,
    input wire [79:0]  fpu_data_out,
    input wire         fpu_data_ready,

    input wire         fpu_busy,
    input wire [15:0]  fpu_status_word,
    output reg [15:0]  fpu_control_word,
    output reg         fpu_ctrl_write,
    input wire         fpu_exception,
    input wire         fpu_irq,

    output reg         fpu_wait,
    input wire         fpu_ready
);

    //=================================================================
    // State Machine
    //=================================================================

    localparam STATE_IDLE           = 3'd0;
    localparam STATE_INSTR_DISPATCH = 3'd1;
    localparam STATE_DATA_TRANSFER  = 3'd2;
    localparam STATE_WAIT_FPU       = 3'd3;
    localparam STATE_READ_RESULT    = 3'd4;
    localparam STATE_COMPLETE       = 3'd5;

    reg [2:0] state;
    reg [2:0] next_state;

    // Data accumulation for multi-word transfers
    reg [79:0] data_accumulator;
    reg [2:0]  transfer_count;
    reg [2:0]  transfer_total;

    // Instruction tracking
    reg [7:0] current_opcode;
    reg [7:0] current_modrm;
    reg needs_data_transfer;
    reg is_wait_instruction;

    //=================================================================
    // Opcode Analysis
    //=================================================================

    task analyze_instruction;
        input [7:0] opcode;
        input [7:0] modrm;
        begin
            current_opcode = opcode;
            current_modrm = modrm;

            // Determine if this instruction needs data transfer
            // and what size
            case (opcode)
                8'h9B: begin // FWAIT/WAIT
                    is_wait_instruction = 1'b1;
                    needs_data_transfer = 1'b0;
                    fpu_data_size = 3'd0;
                end

                8'hD8: begin // FADD, FSUB, FMUL, FDIV, etc.
                    is_wait_instruction = 1'b0;
                    if (modrm[7:6] != 2'b11) begin
                        needs_data_transfer = 1'b1;
                        fpu_data_size = 3'd1; // 32-bit
                        transfer_total = 3'd2; // 2 words
                    end else begin
                        needs_data_transfer = 1'b0;
                    end
                end

                8'hD9: begin // FLD, FST, transcendentals, etc.
                    is_wait_instruction = 1'b0;
                    if (modrm[7:6] != 2'b11) begin
                        case (modrm[5:3])
                            3'b000: begin // FLD m32real
                                needs_data_transfer = 1'b1;
                                fpu_data_size = 3'd1; // 32-bit
                                transfer_total = 3'd2;
                            end
                            3'b010: begin // FST m32real
                                needs_data_transfer = 1'b0; // Will read later
                                fpu_data_size = 3'd1;
                                transfer_total = 3'd2;
                            end
                            3'b101: begin // FLDCW m16
                                needs_data_transfer = 1'b1;
                                fpu_data_size = 3'd0; // 16-bit
                                transfer_total = 3'd1;
                            end
                            3'b111: begin // FSTCW m16
                                needs_data_transfer = 1'b0;
                                fpu_data_size = 3'd0;
                                transfer_total = 3'd1;
                            end
                            default: begin
                                needs_data_transfer = 1'b0;
                            end
                        endcase
                    end else begin
                        needs_data_transfer = 1'b0;
                    end
                end

                8'hDB: begin // FLD m80, FSTP m80, FINIT, etc.
                    is_wait_instruction = 1'b0;
                    if (modrm[7:6] != 2'b11) begin
                        case (modrm[5:3])
                            3'b101: begin // FLD m80real
                                needs_data_transfer = 1'b1;
                                fpu_data_size = 3'd3; // 80-bit
                                transfer_total = 3'd5; // 5 words
                            end
                            3'b111: begin // FSTP m80real
                                needs_data_transfer = 1'b0;
                                fpu_data_size = 3'd3;
                                transfer_total = 3'd5;
                            end
                            default: begin
                                needs_data_transfer = 1'b0;
                            end
                        endcase
                    end else begin
                        needs_data_transfer = 1'b0;
                    end
                end

                8'hDD: begin // FLD m64, FST m64, FSTSW
                    is_wait_instruction = 1'b0;
                    if (modrm[7:6] != 2'b11) begin
                        case (modrm[5:3])
                            3'b000: begin // FLD m64real
                                needs_data_transfer = 1'b1;
                                fpu_data_size = 3'd2; // 64-bit
                                transfer_total = 3'd4; // 4 words
                            end
                            3'b010: begin // FST m64real
                                needs_data_transfer = 1'b0;
                                fpu_data_size = 3'd2;
                                transfer_total = 3'd4;
                            end
                            3'b111: begin // FSTSW m16
                                needs_data_transfer = 1'b0;
                                fpu_data_size = 3'd0;
                                transfer_total = 3'd1;
                            end
                            default: begin
                                needs_data_transfer = 1'b0;
                            end
                        endcase
                    end else begin
                        needs_data_transfer = 1'b0;
                    end
                end

                8'hDF: begin // FSTSW AX, etc.
                    is_wait_instruction = 1'b0;
                    if (modrm == 8'hE0) begin // FSTSW AX
                        needs_data_transfer = 1'b0;
                        fpu_data_size = 3'd0;
                        transfer_total = 3'd1;
                    end else begin
                        needs_data_transfer = 1'b0;
                    end
                end

                default: begin
                    is_wait_instruction = 1'b0;
                    needs_data_transfer = 1'b0;
                end
            endcase
        end
    endtask

    //=================================================================
    // State Machine
    //=================================================================

    always @(posedge clk or posedge reset) begin
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
                if (cpu_fpu_escape) begin
                    next_state = STATE_INSTR_DISPATCH;
                end
            end

            STATE_INSTR_DISPATCH: begin
                if (fpu_instr_ack) begin
                    if (is_wait_instruction) begin
                        next_state = STATE_WAIT_FPU;
                    end else if (needs_data_transfer && cpu_write) begin
                        next_state = STATE_DATA_TRANSFER;
                    end else begin
                        next_state = STATE_WAIT_FPU;
                    end
                end
            end

            STATE_DATA_TRANSFER: begin
                if (transfer_count >= transfer_total) begin
                    next_state = STATE_WAIT_FPU;
                end
            end

            STATE_WAIT_FPU: begin
                if (!fpu_busy) begin
                    // Only read result for memory store operations
                    // (modrm[7:6] != 11) or special register stores (FSTSW AX)
                    if ((current_modrm[7:6] != 2'b11) &&
                        (current_modrm[5:3] == 3'b010 || // FST
                         current_modrm[5:3] == 3'b111) ||// FSTP/FSTCW/FSTSW
                        current_modrm == 8'hE0) begin   // FSTSW AX
                        next_state = STATE_READ_RESULT;
                    end else begin
                        next_state = STATE_COMPLETE;
                    end
                end
            end

            STATE_READ_RESULT: begin
                if (fpu_data_ready || cpu_read) begin
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
    // Control Logic
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fpu_instr_valid <= 1'b0;
            fpu_opcode <= 8'h00;
            fpu_modrm <= 8'h00;
            fpu_data_write <= 1'b0;
            fpu_data_read <= 1'b0;
            fpu_data_in <= 80'h0;
            fpu_control_word <= 16'h037F;
            fpu_ctrl_write <= 1'b0;
            fpu_wait <= 1'b0;
            cpu_ready <= 1'b1;
            cpu_data_out <= 16'h0;
            data_accumulator <= 80'h0;
            transfer_count <= 3'd0;
        end else begin
            // Default: clear pulse signals
            fpu_instr_valid <= 1'b0;
            fpu_data_write <= 1'b0;
            fpu_data_read <= 1'b0;
            fpu_ctrl_write <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    cpu_ready <= 1'b1;
                    transfer_count <= 3'd0;
                    data_accumulator <= 80'h0;
                    fpu_wait <= 1'b0;

                    if (cpu_fpu_escape) begin
                        analyze_instruction(cpu_opcode, cpu_modrm);
                        cpu_ready <= 1'b0;
                    end
                end

                STATE_INSTR_DISPATCH: begin
                    fpu_instr_valid <= 1'b1;
                    fpu_opcode <= current_opcode;
                    fpu_modrm <= current_modrm;

                    if (fpu_instr_ack) begin
                        fpu_instr_valid <= 1'b0;

                        if (is_wait_instruction) begin
                            fpu_wait <= 1'b1;
                        end
                    end
                end

                STATE_DATA_TRANSFER: begin
                    if (cpu_write) begin
                        // Accumulate data words
                        case (transfer_count)
                            3'd0: data_accumulator[15:0]   <= cpu_data_in;
                            3'd1: data_accumulator[31:16]  <= cpu_data_in;
                            3'd2: data_accumulator[47:32]  <= cpu_data_in;
                            3'd3: data_accumulator[63:48]  <= cpu_data_in;
                            3'd4: data_accumulator[79:64]  <= cpu_data_in;
                        endcase
                        transfer_count <= transfer_count + 1;

                        if (transfer_count + 1 >= transfer_total) begin
                            // All data collected, write to FPU
                            fpu_data_in <= data_accumulator;
                            fpu_data_write <= 1'b1;
                        end
                    end
                end

                STATE_WAIT_FPU: begin
                    if (is_wait_instruction) begin
                        fpu_wait <= 1'b1;
                        if (fpu_ready) begin
                            fpu_wait <= 1'b0;
                        end
                    end
                end

                STATE_READ_RESULT: begin
                    fpu_data_read <= 1'b1;

                    if (fpu_data_ready) begin
                        // Provide data to CPU based on transfer size
                        case (fpu_data_size)
                            3'd0: cpu_data_out <= fpu_data_out[15:0];   // 16-bit
                            3'd1: cpu_data_out <= fpu_data_out[15:0];   // 32-bit (first word)
                            3'd2: cpu_data_out <= fpu_data_out[15:0];   // 64-bit (first word)
                            3'd3: cpu_data_out <= fpu_data_out[15:0];   // 80-bit (first word)
                        endcase
                    end
                end

                STATE_COMPLETE: begin
                    cpu_ready <= 1'b1;
                end
            endcase
        end
    end

endmodule
