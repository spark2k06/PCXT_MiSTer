// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Intel 8087 FPU Status Word
//
// 16-bit status word format:
// [15]    : Busy (B)
// [14]    : Condition Code C3
// [13:11] : Stack Top Pointer
// [10]    : Condition Code C2
// [9]     : Condition Code C1
// [8]     : Condition Code C0
// [7]     : Exception Summary (ES)
// [6]     : Stack Fault (SF)
// [5]     : Precision Exception (PE)
// [4]     : Underflow Exception (UE)
// [3]     : Overflow Exception (OE)
// [2]     : Zero Divide Exception (ZE)
// [1]     : Denormalized Operand Exception (DE)
// [0]     : Invalid Operation Exception (IE)
//=====================================================================

module FPU_StatusWord(
    input wire clk,
    input wire reset,

    // Stack pointer
    input wire [2:0] stack_ptr,

    // Condition codes
    input wire c3,
    input wire c2,
    input wire c1,
    input wire c0,
    input wire cc_write,                // Write condition codes

    // Exception flags
    input wire invalid,                 // Invalid operation
    input wire denormal,                // Denormalized operand
    input wire zero_divide,             // Division by zero
    input wire overflow,                // Overflow
    input wire underflow,               // Underflow
    input wire precision,               // Precision (inexact)
    input wire stack_fault,             // Stack overflow/underflow

    // Control
    input wire clear_exceptions,        // Clear exception flags
    input wire set_busy,                // Set busy flag
    input wire clear_busy,              // Clear busy flag

    // Output
    output reg [15:0] status_word
);

    //=================================================================
    // Status Word Bits
    //=================================================================

    reg busy;
    reg cond_c3, cond_c2, cond_c1, cond_c0;
    reg exc_invalid, exc_denormal, exc_zero_div;
    reg exc_overflow, exc_underflow, exc_precision;
    reg exc_stack_fault;

    //=================================================================
    // Exception Summary
    //=================================================================

    wire exception_summary;
    assign exception_summary = exc_invalid | exc_denormal | exc_zero_div |
                               exc_overflow | exc_underflow | exc_precision;

    //=================================================================
    // Main Logic
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy <= 1'b0;
            cond_c3 <= 1'b0;
            cond_c2 <= 1'b0;
            cond_c1 <= 1'b0;
            cond_c0 <= 1'b0;
            exc_invalid <= 1'b0;
            exc_denormal <= 1'b0;
            exc_zero_div <= 1'b0;
            exc_overflow <= 1'b0;
            exc_underflow <= 1'b0;
            exc_precision <= 1'b0;
            exc_stack_fault <= 1'b0;
        end else begin
            // Busy flag control
            if (set_busy)
                busy <= 1'b1;
            if (clear_busy)
                busy <= 1'b0;

            // Condition codes
            if (cc_write) begin
                cond_c3 <= c3;
                cond_c2 <= c2;
                cond_c1 <= c1;
                cond_c0 <= c0;
            end

            // Exception flag accumulation
            if (clear_exceptions) begin
                exc_invalid <= 1'b0;
                exc_denormal <= 1'b0;
                exc_zero_div <= 1'b0;
                exc_overflow <= 1'b0;
                exc_underflow <= 1'b0;
                exc_precision <= 1'b0;
                exc_stack_fault <= 1'b0;
            end else begin
                // Sticky exception flags (OR in new exceptions)
                if (invalid) exc_invalid <= 1'b1;
                if (denormal) exc_denormal <= 1'b1;
                if (zero_divide) exc_zero_div <= 1'b1;
                if (overflow) exc_overflow <= 1'b1;
                if (underflow) exc_underflow <= 1'b1;
                if (precision) exc_precision <= 1'b1;
                if (stack_fault) exc_stack_fault <= 1'b1;
            end
        end
    end

    //=================================================================
    // Status Word Assembly
    //=================================================================

    always @(*) begin
        status_word = {
            busy,               // [15] Busy
            cond_c3,            // [14] C3
            stack_ptr,          // [13:11] Stack pointer
            cond_c2,            // [10] C2
            cond_c1,            // [9] C1
            cond_c0,            // [8] C0
            exception_summary,  // [7] Exception summary
            exc_stack_fault,    // [6] Stack fault
            exc_precision,      // [5] Precision
            exc_underflow,      // [4] Underflow
            exc_overflow,       // [3] Overflow
            exc_zero_div,       // [2] Zero divide
            exc_denormal,       // [1] Denormalized
            exc_invalid         // [0] Invalid
        };
    end

endmodule
