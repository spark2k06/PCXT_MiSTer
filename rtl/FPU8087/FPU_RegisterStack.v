// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Intel 8087 FPU Register Stack
//
// Implements the 8-register stack (ST(0) through ST(7)) with:
// - 80-bit extended precision registers
// - Stack pointer management
// - Push/Pop operations
// - Tag word for register status
// - Direct register access
//
// Tag values:
// 00 = Valid (non-zero)
// 01 = Zero
// 10 = Special (NaN, Infinity, Denormal)
// 11 = Empty
//=====================================================================

module FPU_RegisterStack(
    input wire clk,
    input wire reset,

    // Stack operations
    input wire push,                    // Push operation (decrement SP)
    input wire pop,                     // Pop operation (increment SP)
    input wire inc_ptr,                 // Increment stack pointer (FINCSTP)
    input wire dec_ptr,                 // Decrement stack pointer (FDECSTP)
    input wire free_reg,                // Mark register as empty (FFREE)
    input wire [2:0] free_index,        // Index of register to free
    input wire init_stack,              // Initialize stack (FINIT) - reset SP and tags

    // Data interface
    input wire [79:0] data_in,          // Data to write
    input wire [2:0]  write_reg,        // Register to write (0-7)
    input wire        write_enable,     // Write enable

    output reg [79:0] st0,              // ST(0) - top of stack
    output reg [79:0] st1,              // ST(1)
    output reg [2:0]  read_reg,         // Register selector
    input wire [2:0]  read_sel,         // Read selection
    output reg [79:0] read_data,        // Read data output

    // Stack pointer
    output reg [2:0]  stack_ptr,        // Stack pointer (0-7)

    // Tag word (2 bits per register)
    output reg [15:0] tag_word,         // Tag word

    // Exception flags
    output reg        stack_overflow,   // Stack overflow
    output reg        stack_underflow   // Stack underflow
);

    //=================================================================
    // Register File
    //=================================================================

    reg [79:0] registers [0:7];         // 8 registers, 80 bits each
    reg [1:0]  tags [0:7];              // Tag for each register

    integer i;

    //=================================================================
    // Tag Generation
    //=================================================================

    function [1:0] generate_tag;
        input [79:0] value;
        reg [14:0] exp;
        reg [63:0] mant;
        begin
            exp = value[78:64];
            mant = value[63:0];

            if (exp == 15'd0 && mant == 64'd0) begin
                // Zero
                generate_tag = 2'b01;
            end else if (exp == 15'h7FFF) begin
                // Infinity or NaN
                generate_tag = 2'b10;
            end else if (exp == 15'd0 && mant != 64'd0) begin
                // Denormal
                generate_tag = 2'b10;
            end else begin
                // Valid
                generate_tag = 2'b00;
            end
        end
    endfunction

    //=================================================================
    // Physical to Logical Register Mapping
    //=================================================================

    function [2:0] physical_reg;
        input [2:0] logical_reg;
        begin
            physical_reg = (stack_ptr + logical_reg) & 3'b111;
        end
    endfunction

    //=================================================================
    // Main Logic
    //=================================================================

    // Temporary stack pointer for push/pop operations
    reg [2:0] new_stack_ptr;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            stack_ptr <= 3'd0;
            stack_overflow <= 1'b0;
            stack_underflow <= 1'b0;

            // Initialize all registers to zero with empty tag
            for (i = 0; i < 8; i = i + 1) begin
                registers[i] <= 80'd0;
                tags[i] <= 2'b11;  // Empty
            end
        end else begin
            // Clear exception flags
            stack_overflow <= 1'b0;
            stack_underflow <= 1'b0;

            // Handle FINIT: Initialize stack
            if (init_stack) begin
                stack_ptr <= 3'd0;
                // Mark all registers as empty
                for (i = 0; i < 8; i = i + 1) begin
                    tags[i] <= 2'b11;  // Empty
                end
            end

            // Calculate new stack pointer based on push/pop/inc/dec
            new_stack_ptr = stack_ptr;
            if (push) begin
                new_stack_ptr = stack_ptr - 3'd1;

                // Check for overflow (pushing into non-empty slot)
                if (tags[(new_stack_ptr + 3'd7) & 3'b111] != 2'b11) begin
                    stack_overflow <= 1'b1;
                end
            end else if (pop) begin
                // Check for underflow (popping from empty slot)
                if (tags[physical_reg(3'd0)] == 2'b11) begin
                    stack_underflow <= 1'b1;
                end

                // Mark current top as empty
                tags[physical_reg(3'd0)] <= 2'b11;

                new_stack_ptr = stack_ptr + 3'd1;
            end else if (inc_ptr) begin
                // FINCSTP: Increment stack pointer (no data transfer)
                new_stack_ptr = stack_ptr + 3'd1;
            end else if (dec_ptr) begin
                // FDECSTP: Decrement stack pointer (no data transfer)
                new_stack_ptr = stack_ptr - 3'd1;
            end

            // Update stack pointer
            stack_ptr <= new_stack_ptr;

            // Handle FFREE: Mark register as empty
            if (free_reg) begin
                tags[physical_reg(free_index)] <= 2'b11;  // Empty tag
            end

            // Handle write operation
            // For push+write: use NEW stack pointer (write to new ST(0) after push)
            // For pop+write: use OLD stack pointer (write before pop takes effect)
            // For write only: use current stack pointer
            if (write_enable) begin
                if (push) begin
                    // Push+write: use new stack pointer
                    registers[(new_stack_ptr + write_reg) & 3'b111] <= data_in;
                    tags[(new_stack_ptr + write_reg) & 3'b111] <= generate_tag(data_in);
                end else begin
                    // Pop+write or write only: use old (current) stack pointer
                    registers[physical_reg(write_reg)] <= data_in;
                    tags[physical_reg(write_reg)] <= generate_tag(data_in);
                end
            end
        end
    end

    //=================================================================
    // Combinational Outputs
    //=================================================================

    always @(*) begin
        // Top of stack (ST(0))
        st0 = registers[physical_reg(3'd0)];

        // Second register (ST(1))
        st1 = registers[physical_reg(3'd1)];

        // Read data based on selection
        read_data = registers[physical_reg(read_sel)];

        // Build tag word (2 bits per register)
        tag_word = {
            tags[physical_reg(3'd7)],
            tags[physical_reg(3'd6)],
            tags[physical_reg(3'd5)],
            tags[physical_reg(3'd4)],
            tags[physical_reg(3'd3)],
            tags[physical_reg(3'd2)],
            tags[physical_reg(3'd1)],
            tags[physical_reg(3'd0)]
        };
    end

endmodule
