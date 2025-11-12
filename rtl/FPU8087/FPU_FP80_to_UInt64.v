// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// IEEE 754 Extended Precision (80-bit) to 64-bit Unsigned Integer Converter
//
// Converts 80-bit extended precision to 64-bit unsigned integers
// with separate sign output.
//
// This module is designed for BCD conversion:
//   - FP80 → Binary (64-bit unsigned) → BCD
//
// Features:
// - All 4 rounding modes
// - Overflow detection (value too large for uint64)
// - Special value handling (±∞, NaN → exception)
// - Separate sign output
// - Exception flags
//=====================================================================

module FPU_FP80_to_UInt64(
    input wire clk,
    input wire reset,
    input wire enable,              // Start conversion

    // Input
    input wire [79:0] fp_in,        // 80-bit floating-point
    input wire [1:0]  rounding_mode,// 00=nearest, 01=down, 10=up, 11=truncate

    // Output
    output reg [63:0] uint_out,     // 64-bit unsigned integer
    output reg        sign_out,     // Sign bit
    output reg done,                // Conversion complete

    // Exception flags
    output reg flag_invalid,        // Invalid operation (∞, NaN)
    output reg flag_overflow,       // Result overflow (too large for uint64)
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
    reg [6:0]  shift_right;
    reg [63:0] uint_value;
    reg        round_up;

    //=================================================================
    // Conversion Logic
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            uint_out <= 64'd0;
            sign_out <= 1'b0;
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

                // Output sign
                sign_out = sign;

                // Check for special values
                if (exp == 15'h7FFF) begin
                    // ±∞ or NaN
                    flag_invalid = 1'b1;
                    uint_out = 64'hFFFFFFFFFFFFFFFF;  // Max value
                    done = 1'b1;
                end else if (exp == 15'd0) begin
                    // ±0 or denormal (treat as 0)
                    uint_out = 64'd0;
                    if (mant != 64'd0)
                        flag_inexact = 1'b1;  // Denormal rounded to 0
                    done = 1'b1;
                end else begin
                    // Normal number
                    // Unbias exponent
                    exp_unbiased = {2'b00, exp} - 17'sd16383;

                    // Check if exponent is too large (overflow)
                    if (exp_unbiased > 17'sd63) begin
                        // Value too large for uint64
                        flag_overflow = 1'b1;
                        uint_out = 64'hFFFFFFFFFFFFFFFF;  // Max value
                        done = 1'b1;
                    end else if (exp_unbiased < -17'sd1) begin
                        // Value < 1.0, rounds to 0 (with possible rounding)
                        round_up = 1'b0;

                        // Check rounding
                        case (rounding_mode)
                            2'b00: round_up = 1'b0;  // Round to nearest, fractional always rounds to 0
                            2'b01: round_up = 1'b0;  // Round down: always rounds to 0
                            2'b10: round_up = 1'b1;  // Round up: always rounds to 1
                            2'b11: round_up = 1'b0;  // Truncate to 0
                        endcase

                        if (round_up)
                            uint_out = 64'd1;
                        else
                            uint_out = 64'd0;

                        flag_inexact = 1'b1;
                        done = 1'b1;
                    end else begin
                        // exp_unbiased is in range [-1, 63]
                        // Need to shift mantissa right by (63 - exp_unbiased)
                        shift_right = 7'd63 - exp_unbiased[6:0];

                        // Shift mantissa
                        shifted_mant = mant >> shift_right;

                        // Extract integer part
                        uint_value = shifted_mant;

                        // Check for inexact (bits shifted out)
                        if (shift_right > 7'd0 && (mant & ((64'd1 << shift_right) - 64'd1)) != 64'd0) begin
                            flag_inexact = 1'b1;

                            // Apply rounding
                            round_up = 1'b0;
                            case (rounding_mode)
                                2'b00: begin // Round to nearest
                                    // Check guard bit (bit at position shift_right-1)
                                    if (shift_right > 7'd0 && mant[shift_right - 7'd1])
                                        round_up = 1'b1;
                                end
                                2'b01: round_up = 1'b0;       // Round down
                                2'b10: round_up = 1'b1;       // Round up
                                2'b11: round_up = 1'b0;       // Truncate
                            endcase

                            if (round_up) begin
                                // Check for overflow on rounding
                                if (uint_value == 64'hFFFFFFFFFFFFFFFF) begin
                                    flag_overflow = 1'b1;
                                end else begin
                                    uint_value = uint_value + 64'd1;
                                end
                            end
                        end

                        uint_out = uint_value;
                        done = 1'b1;
                    end
                end
            end else begin
                done = 1'b0;
            end
        end
    end

endmodule
