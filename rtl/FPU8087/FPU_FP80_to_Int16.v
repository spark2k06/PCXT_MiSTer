// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// IEEE 754 Extended Precision (80-bit) to 16-bit Signed Integer Converter
//
// Converts 80-bit extended precision to 16-bit signed integers.
//
// Features:
// - All 4 rounding modes
// - Overflow detection (value too large for int16)
// - Special value handling (±∞, NaN → exception)
// - Exception flags
//=====================================================================

module FPU_FP80_to_Int16(
    input wire clk,
    input wire reset,
    input wire enable,              // Start conversion

    // Input
    input wire [79:0] fp_in,        // 80-bit floating-point
    input wire [1:0]  rounding_mode,// 00=nearest, 01=down, 10=up, 11=truncate

    // Output
    output reg signed [15:0] int_out,  // 16-bit signed integer
    output reg done,                   // Conversion complete

    // Exception flags
    output reg flag_invalid,        // Invalid operation (∞, NaN)
    output reg flag_overflow,       // Result overflow (too large for int16)
    output reg flag_inexact         // Result not exact (rounded)
);

    //=================================================================
    // Unpacked Input
    //=================================================================

    reg        sign;
    reg [14:0] exp;
    reg [63:0] mant;
    reg signed [16:0] exp_unbiased;  // 17-bit signed for calculations

    //=================================================================
    // Working Registers
    //=================================================================

    reg [63:0] shifted_mant;
    reg [5:0]  shift_right;
    reg signed [31:0] int_value;  // 32-bit for overflow detection
    reg        round_up;

    //=================================================================
    // Conversion Logic
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            int_out <= 16'd0;
            done <= 1'b0;
            flag_invalid <= 1'b0;
            flag_overflow <= 1'b0;
            flag_inexact <= 1'b0;
        end else begin
            if (enable) begin
                // Unpack
                sign = fp_in[79];
                exp = fp_in[78:64];
                mant = fp_in[63:0];

                // Clear flags
                flag_invalid = 1'b0;
                flag_overflow = 1'b0;
                flag_inexact = 1'b0;

                // Check for special values
                if (exp == 15'h7FFF) begin
                    // ±∞ or NaN
                    flag_invalid = 1'b1;
                    if (sign)
                        int_out = 16'sh8000;  // -32768 (most negative)
                    else
                        int_out = 16'sh7FFF;  // +32767 (most positive)
                    done = 1'b1;
                end else if (exp == 15'd0) begin
                    // ±0 or denormal (treat as 0)
                    int_out = 16'd0;
                    if (mant != 64'd0)
                        flag_inexact = 1'b1;  // Denormal rounded to 0
                    done = 1'b1;
                end else begin
                    // Normal number
                    // Unbias exponent
                    exp_unbiased = {2'b00, exp} - 17'sd16383;

                    // Check if exponent is too large (overflow)
                    if (exp_unbiased > 17'sd15) begin
                        // Value too large for int16
                        flag_overflow = 1'b1;
                        if (sign)
                            int_out = 16'sh8000;  // -32768
                        else
                            int_out = 16'sh7FFF;  // +32767
                        done = 1'b1;
                    end else if (exp_unbiased < -17'sd1) begin
                        // Value < 1.0, rounds to 0 (with possible rounding)
                        round_up = 1'b0;

                        // Check rounding
                        case (rounding_mode)
                            2'b00: round_up = 1'b0;  // Round to nearest, fractional always rounds to 0
                            2'b01: round_up = sign;  // Round down: negative rounds to -1
                            2'b10: round_up = !sign; // Round up: positive rounds to 1
                            2'b11: round_up = 1'b0;  // Truncate to 0
                        endcase

                        if (round_up)
                            int_out = sign ? -16'sd1 : 16'sd1;
                        else
                            int_out = 16'd0;

                        flag_inexact = 1'b1;
                        done = 1'b1;
                    end else begin
                        // exp_unbiased is in range [-1, 15]
                        // Need to shift mantissa right by (63 - exp_unbiased)
                        shift_right = 6'd63 - exp_unbiased[5:0];

                        // Shift mantissa
                        shifted_mant = mant >> shift_right;

                        // Extract integer part (lower 16 bits after shift)
                        int_value = shifted_mant[15:0];

                        // Check for inexact (bits shifted out)
                        if (shift_right > 6'd0 && (mant & ((64'd1 << shift_right) - 64'd1)) != 64'd0) begin
                            flag_inexact = 1'b1;

                            // Apply rounding
                            round_up = 1'b0;
                            case (rounding_mode)
                                2'b00: begin // Round to nearest
                                    // Check guard bit (bit at position shift_right-1)
                                    if (shift_right > 6'd0 && mant[shift_right - 6'd1])
                                        round_up = 1'b1;
                                end
                                2'b01: round_up = sign;       // Round down
                                2'b10: round_up = !sign;      // Round up
                                2'b11: round_up = 1'b0;       // Truncate
                            endcase

                            if (round_up)
                                int_value = int_value + 32'd1;
                        end

                        // Apply sign
                        if (sign)
                            int_value = -int_value;

                        // Check overflow after sign application
                        if (int_value > 32'sd32767 || int_value < -32'sd32768) begin
                            flag_overflow = 1'b1;
                            if (sign)
                                int_out = 16'sh8000;
                            else
                                int_out = 16'sh7FFF;
                        end else begin
                            int_out = int_value[15:0];
                        end

                        done = 1'b1;
                    end
                end
            end else begin
                done = 1'b0;
            end
        end
    end

endmodule
