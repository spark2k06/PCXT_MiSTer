// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// FPU-CPU Interface Module
//
// This module implements the interface between the CPU and FPU8087
// as specified in FPU_CPU_Interface_Specification.md.
//
// It handles:
// - Instruction decoding and dispatch
// - Data format conversions (16/32/64/80-bit)
// - Synchronization (FWAIT)
// - Exception handling
// - Status/Control register access
//=====================================================================

module FPU_CPU_Interface(
    // Clock and Reset
    input wire clk,
    input wire reset,

    // ========== CPU Side Interface ==========

    // Instruction Interface
    input wire        cpu_fpu_instr_valid,    // CPU signals valid FPU instruction
    input wire [7:0]  cpu_fpu_opcode,         // FPU instruction opcode (D8h-DFh)
    input wire [7:0]  cpu_fpu_modrm,          // ModR/M byte
    output reg        cpu_fpu_instr_ack,      // FPU acknowledges instruction

    // Memory Operation Format (from decoder)
    input wire        cpu_fpu_has_memory_op,  // Instruction uses memory operand
    input wire [1:0]  cpu_fpu_operand_size,   // Memory operand size (0=word, 1=dword, 2=qword, 3=tbyte)
    input wire        cpu_fpu_is_integer,     // Memory operand is integer format
    input wire        cpu_fpu_is_bcd,         // Memory operand is BCD format

    // Data Transfer Interface
    input wire        cpu_fpu_data_write,     // CPU writes data to FPU
    input wire        cpu_fpu_data_read,      // CPU reads data from FPU
    input wire [2:0]  cpu_fpu_data_size,      // 0=16bit, 1=32bit, 2=64bit, 3=80bit
    input wire [79:0] cpu_fpu_data_in,        // Data from CPU (80-bit max)
    output reg [79:0] cpu_fpu_data_out,       // Data to CPU
    output reg        cpu_fpu_data_ready,     // FPU data ready

    // Status and Control
    output wire       cpu_fpu_busy,           // FPU executing instruction
    output wire [15:0] cpu_fpu_status_word,   // FPU status word (FSTSW)
    input wire [15:0] cpu_fpu_control_word,   // FPU control word (FLDCW)
    input wire        cpu_fpu_ctrl_write,     // Write control word
    output wire       cpu_fpu_exception,      // Unmasked exception occurred
    output wire       cpu_fpu_irq,            // Interrupt request

    // Synchronization
    input wire        cpu_fpu_wait,           // CPU executing FWAIT
    output wire       cpu_fpu_ready,          // FPU ready (not busy)

    // ========== FPU Core Side Interface ==========

    // To FPU Core
    output reg        fpu_start,              // Start FPU operation
    output reg [7:0]  fpu_operation,          // Operation code
    output reg [7:0]  fpu_operand_select,     // Operand selection (ModR/M)
    output reg [79:0] fpu_operand_data,       // Operand data

    // Memory Operation Format (to core)
    output reg        fpu_has_memory_op,      // Instruction uses memory operand
    output reg [1:0]  fpu_operand_size,       // Memory operand size
    output reg        fpu_is_integer,         // Memory operand is integer
    output reg        fpu_is_bcd,             // Memory operand is BCD

    // From FPU Core
    input wire        fpu_operation_complete, // Operation completed
    input wire [79:0] fpu_result_data,        // Result data
    input wire [15:0] fpu_status,             // Status word
    input wire        fpu_error,              // Error occurred

    // Control registers
    output reg [15:0] fpu_control_reg,        // Control word to FPU
    output reg        fpu_control_update      // Update control word
);

    //=================================================================
    // Internal State Machine
    //=================================================================

    localparam STATE_IDLE       = 3'd0;
    localparam STATE_DECODE     = 3'd1;
    localparam STATE_DATA_WAIT  = 3'd2;
    localparam STATE_EXECUTE    = 3'd3;
    localparam STATE_RESULT     = 3'd4;
    localparam STATE_COMPLETE   = 3'd5;

    reg [2:0] state;
    reg [2:0] next_state;

    // Instruction decode registers
    reg [7:0] current_opcode;
    reg [7:0] current_modrm;
    reg [2:0] data_size_needed;
    reg needs_memory_operand;
    reg produces_result;

    // Data buffers
    reg [79:0] operand_buffer;
    reg [79:0] result_buffer;
    reg operand_ready;

    // Busy tracking
    reg internal_busy;

    //=================================================================
    // Output Assignments
    //=================================================================

    assign cpu_fpu_busy = internal_busy || (state != STATE_IDLE);
    assign cpu_fpu_ready = !cpu_fpu_busy;
    assign cpu_fpu_status_word = fpu_status;
    assign cpu_fpu_exception = fpu_error && !fpu_status[7]; // Error and not masked
    assign cpu_fpu_irq = cpu_fpu_exception; // Simplified for now

    //=================================================================
    // Instruction Decoder
    //=================================================================

    task decode_instruction;
        input [7:0] opcode;
        input [7:0] modrm;
        begin
            current_opcode = opcode;
            current_modrm = modrm;

            // Decode based on opcode (ESC instructions D8-DF)
            case (opcode)
                8'hD8: begin // FADD, FSUB, FMUL, FDIV, etc.
                    if (modrm[7:6] == 2'b11) begin
                        // Register operand - no memory needed
                        needs_memory_operand = 1'b0;
                        data_size_needed = 3'd0;
                    end else begin
                        // Memory operand - 32-bit
                        needs_memory_operand = 1'b1;
                        data_size_needed = 3'd1; // 32-bit
                    end
                    produces_result = 1'b0; // Result in stack
                end

                8'hD9: begin // FLD, FST, FLDCW, FSTCW, transcendentals
                    case (modrm[7:6])
                        2'b11: begin // Register or special
                            needs_memory_operand = 1'b0;
                            data_size_needed = 3'd0;

                            // Check for constants or transcendentals
                            if (modrm >= 8'hE8 && modrm <= 8'hEF) begin
                                // Constants (FLD1, FLDZ, FLDPI, etc.)
                                produces_result = 1'b0;
                            end else if (modrm >= 8'hF0 && modrm <= 8'hFF) begin
                                // Transcendentals (FSIN, FCOS, etc.)
                                produces_result = 1'b0;
                            end else begin
                                produces_result = 1'b0;
                            end
                        end
                        default: begin
                            // Memory operand
                            case (modrm[5:3])
                                3'b000: begin // FLD m32real
                                    needs_memory_operand = 1'b1;
                                    data_size_needed = 3'd1; // 32-bit
                                    produces_result = 1'b0;
                                end
                                3'b010: begin // FST m32real
                                    needs_memory_operand = 1'b0;
                                    data_size_needed = 3'd1;
                                    produces_result = 1'b1; // Read from stack
                                end
                                3'b101: begin // FLDCW m16
                                    needs_memory_operand = 1'b1;
                                    data_size_needed = 3'd0; // 16-bit
                                    produces_result = 1'b0;
                                end
                                3'b111: begin // FSTCW m16
                                    needs_memory_operand = 1'b0;
                                    data_size_needed = 3'd0;
                                    produces_result = 1'b1; // Control word
                                end
                                default: begin
                                    needs_memory_operand = 1'b0;
                                    data_size_needed = 3'd0;
                                    produces_result = 1'b0;
                                end
                            endcase
                        end
                    endcase
                end

                8'hDA: begin // FIADD, etc. (integer operations)
                    needs_memory_operand = (modrm[7:6] != 2'b11);
                    data_size_needed = 3'd1; // 32-bit integer
                    produces_result = 1'b0;
                end

                8'hDB: begin // FLD m80real, FSTP m80real, FINIT, etc.
                    if (modrm[7:6] == 2'b11) begin
                        // Special instructions (FINIT, FCLEX, etc.)
                        needs_memory_operand = 1'b0;
                        data_size_needed = 3'd0;
                        produces_result = 1'b0;
                    end else begin
                        case (modrm[5:3])
                            3'b101: begin // FLD m80real
                                needs_memory_operand = 1'b1;
                                data_size_needed = 3'd3; // 80-bit
                                produces_result = 1'b0;
                            end
                            3'b111: begin // FSTP m80real
                                needs_memory_operand = 1'b0;
                                data_size_needed = 3'd3;
                                produces_result = 1'b1; // 80-bit result
                            end
                            default: begin
                                needs_memory_operand = 1'b1;
                                data_size_needed = 3'd1;
                                produces_result = 1'b0;
                            end
                        endcase
                    end
                end

                8'hDC: begin // FADD, FSUB, FMUL, FDIV (64-bit memory or reverse)
                    if (modrm[7:6] == 2'b11) begin
                        needs_memory_operand = 1'b0;
                        data_size_needed = 3'd0;
                    end else begin
                        needs_memory_operand = 1'b1;
                        data_size_needed = 3'd2; // 64-bit
                    end
                    produces_result = 1'b0;
                end

                8'hDD: begin // FLD m64real, FST m64real, FSTSW
                    if (modrm[7:6] == 2'b11) begin
                        // Register operations
                        needs_memory_operand = 1'b0;
                        data_size_needed = 3'd0;
                        produces_result = 1'b0;
                    end else begin
                        case (modrm[5:3])
                            3'b000: begin // FLD m64real
                                needs_memory_operand = 1'b1;
                                data_size_needed = 3'd2; // 64-bit
                                produces_result = 1'b0;
                            end
                            3'b010: begin // FST m64real
                                needs_memory_operand = 1'b0;
                                data_size_needed = 3'd2;
                                produces_result = 1'b1;
                            end
                            3'b111: begin // FSTSW m16
                                needs_memory_operand = 1'b0;
                                data_size_needed = 3'd0; // 16-bit
                                produces_result = 1'b1; // Status word
                            end
                            default: begin
                                needs_memory_operand = 1'b0;
                                data_size_needed = 3'd0;
                                produces_result = 1'b0;
                            end
                        endcase
                    end
                end

                8'hDE: begin // FIADD, FISUB, etc. (16-bit integer)
                    if (modrm[7:6] == 2'b11) begin
                        needs_memory_operand = 1'b0;
                        data_size_needed = 3'd0;
                    end else begin
                        needs_memory_operand = 1'b1;
                        data_size_needed = 3'd0; // 16-bit integer
                    end
                    produces_result = 1'b0;
                end

                8'hDF: begin // FILD, FIST, FSTSW AX, etc.
                    if (modrm == 8'hE0) begin
                        // FSTSW AX - special case
                        needs_memory_operand = 1'b0;
                        data_size_needed = 3'd0;
                        produces_result = 1'b1; // Status to AX
                    end else if (modrm[7:6] == 2'b11) begin
                        needs_memory_operand = 1'b0;
                        data_size_needed = 3'd0;
                        produces_result = 1'b0;
                    end else begin
                        needs_memory_operand = 1'b1;
                        data_size_needed = 3'd0; // 16-bit
                        produces_result = 1'b0;
                    end
                end

                default: begin
                    needs_memory_operand = 1'b0;
                    data_size_needed = 3'd0;
                    produces_result = 1'b0;
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
                if (cpu_fpu_instr_valid) begin
                    next_state = STATE_DECODE;
                end
            end

            STATE_DECODE: begin
                if (needs_memory_operand) begin
                    next_state = STATE_DATA_WAIT;
                end else begin
                    next_state = STATE_EXECUTE;
                end
            end

            STATE_DATA_WAIT: begin
                if (cpu_fpu_data_write || operand_ready) begin
                    next_state = STATE_EXECUTE;
                end
            end

            STATE_EXECUTE: begin
                if (fpu_operation_complete) begin
                    if (produces_result) begin
                        next_state = STATE_RESULT;
                    end else begin
                        next_state = STATE_COMPLETE;
                    end
                end
            end

            STATE_RESULT: begin
                if (cpu_fpu_data_read) begin
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
            cpu_fpu_instr_ack <= 1'b0;
            cpu_fpu_data_ready <= 1'b0;
            cpu_fpu_data_out <= 80'h0;
            fpu_start <= 1'b0;
            fpu_operation <= 8'h00;
            fpu_operand_select <= 8'h00;
            fpu_operand_data <= 80'h0;
            fpu_has_memory_op <= 1'b0;
            fpu_operand_size <= 2'b00;
            fpu_is_integer <= 1'b0;
            fpu_is_bcd <= 1'b0;
            fpu_control_reg <= 16'h037F; // Default 8087 control word
            fpu_control_update <= 1'b0;
            internal_busy <= 1'b0;
            operand_buffer <= 80'h0;
            result_buffer <= 80'h0;
            operand_ready <= 1'b0;
            current_opcode <= 8'h00;
            current_modrm <= 8'h00;
        end else begin
            // Default: clear pulse signals
            cpu_fpu_instr_ack <= 1'b0;
            fpu_start <= 1'b0;
            fpu_control_update <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    internal_busy <= 1'b0;
                    cpu_fpu_data_ready <= 1'b0;
                    operand_ready <= 1'b0;

                    if (cpu_fpu_instr_valid) begin
                        // Acknowledge instruction
                        cpu_fpu_instr_ack <= 1'b1;
                    end

                    // Handle control word writes
                    if (cpu_fpu_ctrl_write) begin
                        fpu_control_reg <= cpu_fpu_control_word;
                        fpu_control_update <= 1'b1;
                    end
                end

                STATE_DECODE: begin
                    // Decode instruction
                    decode_instruction(cpu_fpu_opcode, cpu_fpu_modrm);
                    internal_busy <= 1'b1;

                    // Capture memory operation format flags from decoder
                    fpu_has_memory_op <= cpu_fpu_has_memory_op;
                    fpu_operand_size <= cpu_fpu_operand_size;
                    fpu_is_integer <= cpu_fpu_is_integer;
                    fpu_is_bcd <= cpu_fpu_is_bcd;
                end

                STATE_DATA_WAIT: begin
                    // Wait for memory operand
                    if (cpu_fpu_data_write) begin
                        operand_buffer <= cpu_fpu_data_in;
                        operand_ready <= 1'b1;
                    end
                end

                STATE_EXECUTE: begin
                    // Start FPU operation
                    if (!fpu_start && !fpu_operation_complete) begin
                        fpu_start <= 1'b1;
                        fpu_operation <= current_opcode;
                        fpu_operand_select <= current_modrm;
                        fpu_operand_data <= operand_ready ? operand_buffer : 80'h0;
                    end

                    // Capture result when complete
                    if (fpu_operation_complete) begin
                        result_buffer <= fpu_result_data;
                    end
                end

                STATE_RESULT: begin
                    // Provide result to CPU
                    cpu_fpu_data_out <= result_buffer;
                    cpu_fpu_data_ready <= 1'b1;
                end

                STATE_COMPLETE: begin
                    // Operation complete, return to idle
                    internal_busy <= 1'b0;
                    cpu_fpu_data_ready <= 1'b0;
                end
            endcase
        end
    end

endmodule
