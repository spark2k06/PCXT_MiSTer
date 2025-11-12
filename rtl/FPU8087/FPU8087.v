// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Intel 8087 Floating Point Unit (FPU) - Top Level Module
//
// This module integrates all components of the 8087 FPU coprocessor:
// - 8 x 80-bit register stack (ST0-ST7)
// - Status, Control, and Tag registers
// - Microsequencer for instruction execution
// - Arithmetic units (Add/Sub/Compare)
// - Normalization and rounding units
// - Mathematical constants ROM
//=====================================================================

module FPU8087(
    input clk,
    input reset,

    // Interface to 8086/8088 CPU
    input [15:0] address,
    input [15:0] data_in,
    output reg [15:0] data_out,
    input read_enable,
    input write_enable,

    // Interrupt signal
    output reg interrupt_request,

    // Status signals
    output wire busy
);

    //=================================================================
    // Internal Registers and Wires
    //=================================================================

    // Stack registers
    wire [79:0] stack_read_data;
    reg [2:0] stack_read_addr;
    reg [2:0] stack_write_addr;
    reg [79:0] stack_write_data;
    reg stack_write_enable;

    // Status word
    wire [15:0] status_word;
    reg [15:0] status_write_data;
    reg status_write_enable;
    wire busy_bit;
    wire [3:0] condition_codes;
    wire [2:0] stack_top_ptr;
    wire error_summary_bit;
    wire stack_fault;
    wire precision_error;
    wire underflow_error;
    wire overflow_error;
    wire zero_divide_error;
    wire denormalized_error;
    wire invalid_operation_error;

    // Control word
    wire [15:0] control_word;
    reg [15:0] control_write_data;
    reg control_write_enable;
    wire [5:0] exception_masks;
    wire interrupt_enable_mask;
    wire infinity_control;
    wire [1:0] rounding_control;
    wire [1:0] precision_control;

    // Tag register
    wire [15:0] tag_word;
    reg [15:0] tag_write_data;
    reg tag_write_enable;
    wire [1:0] tag_ST0, tag_ST1, tag_ST2, tag_ST3;
    wire [1:0] tag_ST4, tag_ST5, tag_ST6, tag_ST7;

    // Microsequencer interface
    reg microseq_start;
    reg [3:0] microseq_program_index;
    wire microseq_complete;
    reg [63:0] microseq_data_in;
    wire [63:0] microseq_data_out;

    //=================================================================
    // Component Instantiation
    //=================================================================

    // FPU Stack Registers (8 x 80-bit)
    FPU_Stack_Registers stack_regs (
        .clk(clk),
        .reset(reset),
        .read_addr(stack_read_addr),
        .write_addr(stack_write_addr),
        .write_data(stack_write_data),
        .write_enable(stack_write_enable),
        .read_data(stack_read_data)
    );

    // Status Word Register
    FPU_Status_Word status_reg (
        .clk(clk),
        .reset(reset),
        .write_data(status_write_data),
        .write_enable(status_write_enable),
        .status_word(status_word),
        .busy_bit(busy_bit),
        .condition_codes(condition_codes),
        .stack_ptr(stack_top_ptr),
        .error_summary_bit(error_summary_bit),
        .stack_fault(stack_fault),
        .precision_error(precision_error),
        .underflow_error(underflow_error),
        .overflow_error(overflow_error),
        .zero_divide_error(zero_divide_error),
        .denormalized_error(denormalized_error),
        .invalid_operation_error(invalid_operation_error)
    );

    // Control Word Register
    FPU_Control_Word_Register control_reg (
        .clk(clk),
        .reset(reset),
        .write_data(control_write_data),
        .write_enable(control_write_enable),
        .control_word(control_word),
        .exception_masks(exception_masks),
        .interrupt_enable_mask(interrupt_enable_mask),
        .infinity_control(infinity_control),
        .rounding_control(rounding_control),
        .precision_control(precision_control)
    );

    // Tag Word Register
    FPU_Tag_Register tag_reg (
        .clk(clk),
        .reset(reset),
        .write_data(tag_write_data),
        .write_enable(tag_write_enable),
        .tag_register(tag_word),
        .tag_ST0(tag_ST0),
        .tag_ST1(tag_ST1),
        .tag_ST2(tag_ST2),
        .tag_ST3(tag_ST3),
        .tag_ST4(tag_ST4),
        .tag_ST5(tag_ST5),
        .tag_ST6(tag_ST6),
        .tag_ST7(tag_ST7)
    );

    // Microsequencer (controls FPU operations)
    MicroSequencer microseq (
        .clk(clk),
        .reset(reset),
        .start(microseq_start),
        .micro_program_index(microseq_program_index),
        .cpu_data_in(microseq_data_in),
        .cpu_data_out(microseq_data_out),
        .instruction_complete(microseq_complete)
    );

    //=================================================================
    // Bus Interface Logic
    //=================================================================

    assign busy = busy_bit;

    // Register address decoding (simplified)
    // In real 8087, these are accessed via I/O ports
    localparam ADDR_CONTROL = 16'h0000;
    localparam ADDR_STATUS  = 16'h0002;
    localparam ADDR_TAG     = 16'h0004;
    localparam ADDR_DATA_LO = 16'h0008;
    localparam ADDR_DATA_HI = 16'h000A;

    // Read operation
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            data_out <= 16'h0000;
        end else if (read_enable) begin
            case (address)
                ADDR_CONTROL: data_out <= control_word;
                ADDR_STATUS:  data_out <= status_word;
                ADDR_TAG:     data_out <= tag_word;
                ADDR_DATA_LO: data_out <= stack_read_data[15:0];
                ADDR_DATA_HI: data_out <= stack_read_data[31:16];
                default:      data_out <= 16'h0000;
            endcase
        end
    end

    // Write operation
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            control_write_enable <= 1'b0;
            status_write_enable <= 1'b0;
            tag_write_enable <= 1'b0;
            stack_write_enable <= 1'b0;
            microseq_start <= 1'b0;
        end else begin
            // Default: disable writes
            control_write_enable <= 1'b0;
            status_write_enable <= 1'b0;
            tag_write_enable <= 1'b0;
            stack_write_enable <= 1'b0;
            microseq_start <= 1'b0;

            if (write_enable) begin
                case (address)
                    ADDR_CONTROL: begin
                        control_write_data <= data_in;
                        control_write_enable <= 1'b1;
                    end
                    ADDR_STATUS: begin
                        status_write_data <= data_in;
                        status_write_enable <= 1'b1;
                    end
                    ADDR_TAG: begin
                        tag_write_data <= data_in;
                        tag_write_enable <= 1'b1;
                    end
                    // Additional cases for data writes would go here
                endcase
            end
        end
    end

    // Interrupt generation
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            interrupt_request <= 1'b0;
        end else begin
            // Generate interrupt when:
            // 1. An unmasked exception occurs
            // 2. Interrupt enable mask is set
            if (interrupt_enable_mask && error_summary_bit) begin
                interrupt_request <= 1'b1;
            end else begin
                interrupt_request <= 1'b0;
            end
        end
    end

endmodule
