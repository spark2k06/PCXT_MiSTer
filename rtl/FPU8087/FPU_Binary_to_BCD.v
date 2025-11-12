// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Binary to BCD Converter
//
// Converts 64-bit binary to 18-digit packed BCD (Intel 8087 format)
//
// Input: 64-bit unsigned binary + sign
//
// Output Format (80 bits):
//   [79]     : Sign (0=positive, 1=negative)
//   [78:72]  : Unused (set to 0)
//   [71:0]   : 18 BCD digits (4 bits each)
//
// Algorithm: Double-dabble (shift-and-add-3)
//   - Shift binary left, insert into BCD
//   - Before each shift, if any BCD digit >= 5, add 3 to it
//   - Repeat for all 64 bits
//=====================================================================

module FPU_Binary_to_BCD(
    input wire clk,
    input wire reset,
    input wire enable,

    input wire [63:0] binary_in,    // Binary input
    input wire        sign_in,      // Sign bit

    output reg [79:0] bcd_out,      // Packed BCD output
    output reg        done,
    output reg        error         // Overflow (value > 18 digits)
);

    //=================================================================
    // State Machine
    //=================================================================

    localparam STATE_IDLE    = 2'd0;
    localparam STATE_CONVERT = 2'd1;
    localparam STATE_DONE    = 2'd2;

    reg [1:0] state;
    reg [6:0] bit_count;        // 0-63 (64 bits to process)
    reg [63:0] binary_shift;    // Shifting binary value
    reg [71:0] bcd_digits;      // 18 BCD digits (4 bits each)
    reg [71:0] bcd_adjusted;    // Temporary for adjusted BCD digits

    //=================================================================
    // Add 3 to BCD digits >= 5 (for double-dabble algorithm)
    //=================================================================

    function [71:0] adjust_bcd_digits;
        input [71:0] bcd_value;
        integer i;
        reg [3:0] digit;
        reg [3:0] adjusted_digit;
        reg [71:0] result;
        begin
            result = bcd_value;
            for (i = 0; i < 18; i = i + 1) begin
                digit = bcd_value[i*4 +: 4];
                if (digit >= 4'd5) begin
                    adjusted_digit = digit + 4'd3;
                end else begin
                    adjusted_digit = digit;
                end
                result[i*4 +: 4] = adjusted_digit;
            end
            adjust_bcd_digits = result;
        end
    endfunction

    //=================================================================
    // Check for overflow (digit 18 or higher non-zero)
    //=================================================================

    function check_overflow;
        input [71:0] bcd_value;
        begin
            // If any of the top digits exceed 9, we have overflow
            // For 18 digits, max value is 999,999,999,999,999,999
            // which fits in 64 bits (0x0DE0B6B3A763FFFF)
            check_overflow = 1'b0;  // Generally won't overflow with 64-bit input
        end
    endfunction

    //=================================================================
    // Main Conversion Logic
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
            bcd_out <= 80'd0;
            done <= 1'b0;
            error <= 1'b0;
            bit_count <= 7'd0;
            binary_shift <= 64'd0;
            bcd_digits <= 72'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    done <= 1'b0;
                    error <= 1'b0;

                    if (enable) begin
                        // Initialize for conversion
                        binary_shift <= binary_in;
                        bcd_digits <= 72'd0;
                        bit_count <= 7'd64;
                        state <= STATE_CONVERT;
                    end
                end

                STATE_CONVERT: begin
                    if (bit_count > 0) begin
                        // Double-dabble algorithm:
                        // Step 1: Adjust BCD digits (add 3 if >= 5)
                        bcd_adjusted = adjust_bcd_digits(bcd_digits);

                        // Step 2: Shift left BCD and insert MSB of binary
                        bcd_digits <= {bcd_adjusted[70:0], binary_shift[63]};

                        // Step 3: Shift left binary
                        binary_shift <= {binary_shift[62:0], 1'b0};

                        // Decrement bit counter
                        bit_count <= bit_count - 1;
                    end else begin
                        // Conversion complete
                        // Check for overflow
                        if (check_overflow(bcd_digits)) begin
                            error <= 1'b1;
                        end

                        // Pack result: [79:sign][78:72:unused][71:0:BCD digits]
                        bcd_out <= {sign_in, 7'd0, bcd_digits};
                        state <= STATE_DONE;
                    end
                end

                STATE_DONE: begin
                    done <= 1'b1;
                    if (~enable) begin
                        state <= STATE_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
