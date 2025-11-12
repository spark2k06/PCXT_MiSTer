// Copyright 2025, Waldo Alvarez, https://pipflow.com
/**
 * FPU_Exception_Handler.v
 *
 * 8087-Style Exception Handler with INT Signal
 *
 * Based on Intel 8087 specification:
 * - Uses INT (interrupt request) signal, NOT FERR#
 * - INT is active HIGH (not active low like later 80287/80387 FERR#)
 * - Exception signaling follows 8087 priority order
 * - Acknowledgment via FCLEX/FNCLEX instructions
 *
 * 8087 Exception Behavior:
 * - Wait instructions check for pending exceptions before executing
 * - No-wait instructions skip exception check
 * - INT asserted when unmasked exception occurs
 * - INT remains asserted until FCLEX/FNCLEX executed
 *
 * Exception Priority (highest to lowest):
 * 1. Invalid Operation (bit 0)
 * 2. Denormalized Operand (bit 1)
 * 3. Zero Divide (bit 2)
 * 4. Overflow (bit 3)
 * 5. Underflow (bit 4)
 * 6. Precision (bit 5)
 *
 * Date: 2025-11-10
 */

module FPU_Exception_Handler(
    input wire clk,
    input wire reset,

    // Exception inputs from arithmetic unit
    input wire exception_invalid,
    input wire exception_denormal,
    input wire exception_zero_div,
    input wire exception_overflow,
    input wire exception_underflow,
    input wire exception_precision,

    // Mask bits from control word
    input wire mask_invalid,
    input wire mask_denormal,
    input wire mask_zero_div,
    input wire mask_overflow,
    input wire mask_underflow,
    input wire mask_precision,

    // Exception acknowledgment (from FCLEX/FNCLEX)
    input wire exception_clear,

    // Exception latch enable (when operation completes)
    input wire exception_latch,

    // INT signal output (active HIGH per 8087 spec)
    output reg int_request,

    // Internal exception status
    output reg exception_pending,
    output wire [5:0] latched_exceptions,

    // Highest priority unmasked exception
    output wire has_unmasked_exception
);

    //=================================================================
    // Exception Latches
    //=================================================================
    // Exceptions are latched when operation completes
    // They persist until cleared by FCLEX/FNCLEX

    reg exception_invalid_latched;
    reg exception_denormal_latched;
    reg exception_zero_div_latched;
    reg exception_overflow_latched;
    reg exception_underflow_latched;
    reg exception_precision_latched;

    assign latched_exceptions = {
        exception_precision_latched,
        exception_underflow_latched,
        exception_overflow_latched,
        exception_zero_div_latched,
        exception_denormal_latched,
        exception_invalid_latched
    };

    //=================================================================
    // Unmasked Exception Detection
    //=================================================================
    // An exception causes INT if it is set AND not masked
    // Priority doesn't affect INT assertion - any unmasked exception triggers it

    wire unmasked_invalid;
    wire unmasked_denormal;
    wire unmasked_zero_div;
    wire unmasked_overflow;
    wire unmasked_underflow;
    wire unmasked_precision;

    assign unmasked_invalid   = exception_invalid_latched   && !mask_invalid;
    assign unmasked_denormal  = exception_denormal_latched  && !mask_denormal;
    assign unmasked_zero_div  = exception_zero_div_latched  && !mask_zero_div;
    assign unmasked_overflow  = exception_overflow_latched  && !mask_overflow;
    assign unmasked_underflow = exception_underflow_latched && !mask_underflow;
    assign unmasked_precision = exception_precision_latched && !mask_precision;

    // Any unmasked exception triggers INT
    assign has_unmasked_exception = unmasked_invalid   ||
                                   unmasked_denormal  ||
                                   unmasked_zero_div  ||
                                   unmasked_overflow  ||
                                   unmasked_underflow ||
                                   unmasked_precision;

    //=================================================================
    // Exception Latching and INT Generation
    //=================================================================

    always @(posedge clk) begin
        if (reset) begin
            // Clear all exception latches on reset
            exception_invalid_latched   <= 1'b0;
            exception_denormal_latched  <= 1'b0;
            exception_zero_div_latched  <= 1'b0;
            exception_overflow_latched  <= 1'b0;
            exception_underflow_latched <= 1'b0;
            exception_precision_latched <= 1'b0;

            // Deassert INT (active HIGH)
            int_request <= 1'b0;
            exception_pending <= 1'b0;

        end else if (exception_clear) begin
            // FCLEX or FNCLEX executed - clear all exceptions
            exception_invalid_latched   <= 1'b0;
            exception_denormal_latched  <= 1'b0;
            exception_zero_div_latched  <= 1'b0;
            exception_overflow_latched  <= 1'b0;
            exception_underflow_latched <= 1'b0;
            exception_precision_latched <= 1'b0;

            // Deassert INT
            int_request <= 1'b0;
            exception_pending <= 1'b0;

        end else if (exception_latch) begin
            // Operation completed - latch any exceptions
            // OR with existing exceptions (sticky bits)
            exception_invalid_latched   <= exception_invalid_latched   || exception_invalid;
            exception_denormal_latched  <= exception_denormal_latched  || exception_denormal;
            exception_zero_div_latched  <= exception_zero_div_latched  || exception_zero_div;
            exception_overflow_latched  <= exception_overflow_latched  || exception_overflow;
            exception_underflow_latched <= exception_underflow_latched || exception_underflow;
            exception_precision_latched <= exception_precision_latched || exception_precision;

            // 8087 Behavior: INT asserts when an unmasked exception OCCURS
            // Check if NEW exceptions being latched are unmasked
            // INT is sticky - once set, stays set until FCLEX (doesn't respond to mask changes)
            if ((exception_invalid   && !mask_invalid)   ||
                (exception_denormal  && !mask_denormal)  ||
                (exception_zero_div  && !mask_zero_div)  ||
                (exception_overflow  && !mask_overflow)  ||
                (exception_underflow && !mask_underflow) ||
                (exception_precision && !mask_precision)) begin
                // New unmasked exception - assert INT
                int_request <= 1'b1;
                exception_pending <= 1'b1;
            end
            // else: INT stays at current value (sticky behavior)

        end
        // else: INT and latched exceptions stay at current values
        // Mask changes do NOT affect INT - only FCLEX can clear it
    end

    //=================================================================
    // Debug Info (for simulation)
    //=================================================================

    `ifdef SIMULATION
    always @(posedge clk) begin
        if (exception_latch && has_unmasked_exception) begin
            $display("[EXCEPTION] Unmasked exception at time %t:", $time);
            if (unmasked_invalid)   $display("  - Invalid Operation");
            if (unmasked_denormal)  $display("  - Denormalized Operand");
            if (unmasked_zero_div)  $display("  - Zero Divide");
            if (unmasked_overflow)  $display("  - Overflow");
            if (unmasked_underflow) $display("  - Underflow");
            if (unmasked_precision) $display("  - Precision");
            $display("  INT asserted (active HIGH)");
        end

        if (exception_clear) begin
            $display("[EXCEPTION] Exceptions cleared at time %t", $time);
        end
    end
    `endif

endmodule
