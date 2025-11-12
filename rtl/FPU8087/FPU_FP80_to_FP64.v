// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// IEEE 754 Extended Precision (80-bit) to Double Precision (64-bit) Converter
//
// Converts 80-bit extended precision to 64-bit double precision format.
//
// FP80 Format: [79:Sign][78:64:Exp][63:Int][62:0:Frac]
// FP64 Format: [63:Sign][62:52:Exp][51:0:Frac]
//
// Features:
// - All 4 rounding modes
// - Overflow/underflow detection (FP80 range → FP64 range)
// - Special value handling (±0, ±∞, NaN)
// - Exception flags
//=====================================================================

module FPU_FP80_to_FP64(
    input wire clk,
    input wire reset,
    input wire enable,              // Start conversion

    // Input
    input wire [79:0] fp80_in,      // 80-bit extended precision
    input wire [1:0]  rounding_mode,// 00=nearest, 01=down, 10=up, 11=truncate

    // Output
    output reg [63:0] fp64_out,     // 64-bit double precision
    output reg done,                // Conversion complete

    // Exception flags
    output reg flag_invalid,        // Invalid operation (NaN)
    output reg flag_overflow,       // Result overflow
    output reg flag_underflow,      // Result underflow
    output reg flag_inexact         // Result not exact (rounded)
);

    //=================================================================
    // Unpacked FP80
    //=================================================================

    reg        sign_in;
    reg [14:0] exp_in;
    reg [63:0] mant_in;

    //=================================================================
    // Output Components
    //=================================================================

    reg        sign_out;
    reg [10:0] exp_out;
    reg [51:0] frac_out;

    //=================================================================
    // Working Registers
    //=================================================================

    reg signed [16:0] exp_unbiased;  // Unbiased exponent
    reg [52:0] rounded_frac;         // 53 bits for rounding (1 int + 52 frac)
    reg        round_up;
    reg [10:0] discarded_bits;       // Bits lost in conversion

    //=================================================================
    // Conversion Logic
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fp64_out <= 64'd0;
            done <= 1'b0;
            flag_invalid <= 1'b0;
            flag_overflow <= 1'b0;
            flag_underflow <= 1'b0;
            flag_inexact <= 1'b0;
        end else begin
            if (enable) begin
                // Unpack FP80
                sign_in = fp80_in[79];
                exp_in = fp80_in[78:64];
                mant_in = fp80_in[63:0];

                // Clear flags
                flag_invalid = 1'b0;
                flag_overflow = 1'b0;
                flag_underflow = 1'b0;
                flag_inexact = 1'b0;

                // Copy sign
                sign_out = sign_in;

                // Handle special values
                if (exp_in == 15'h7FFF) begin
                    // ±∞ or NaN
                    exp_out = 11'h7FF;
                    if (mant_in[62:0] == 63'd0 && mant_in[63] == 1'b1) begin
                        // ±∞
                        frac_out = 52'd0;
                    end else begin
                        // NaN
                        frac_out = {1'b1, mant_in[62:12]};  // Preserve some payload
                        flag_invalid = 1'b1;
                    end
                    fp64_out = {sign_out, exp_out, frac_out};
                    done = 1'b1;
                end else if (exp_in == 15'd0) begin
                    // ±0 or denormal
                    exp_out = 11'd0;
                    frac_out = 52'd0;
                    fp64_out = {sign_out, exp_out, frac_out};
                    if (mant_in != 64'd0)
                        flag_inexact = 1'b1;
                    done = 1'b1;
                end else begin
                    // Normal number
                    // Unbias FP80 exponent and check range for FP64
                    exp_unbiased = {2'b00, exp_in} - 17'sd16383;

                    // FP64 exponent range: -1022 to +1023
                    // Check for overflow
                    if (exp_unbiased > 17'sd1023) begin
                        // Overflow to ±∞
                        exp_out = 11'h7FF;
                        frac_out = 52'd0;
                        flag_overflow = 1'b1;
                        fp64_out = {sign_out, exp_out, frac_out};
                        done = 1'b1;
                    end else if (exp_unbiased < -17'sd1022) begin
                        // Underflow to ±0 or denormal
                        if (exp_unbiased < -17'sd1074) begin
                            // Too small even for denormal
                            exp_out = 11'd0;
                            frac_out = 52'd0;
                            flag_underflow = 1'b1;
                            flag_inexact = 1'b1;
                        end else begin
                            // Can represent as denormal
                            // Denormal: shift mantissa right by |exp_unbiased + 1022|
                            exp_out = 11'd0;
                            rounded_frac = mant_in[63:11] >> (-exp_unbiased - 17'sd1022);
                            frac_out = rounded_frac[51:0];
                            flag_underflow = 1'b1;
                            flag_inexact = 1'b1;
                        end
                        fp64_out = {sign_out, exp_out, frac_out};
                        done = 1'b1;
                    end else begin
                        // Normal range: convert exponent
                        // FP64 biased exp = exp_unbiased + 1023
                        exp_out = exp_unbiased[10:0] + 11'd1023;

                        // Extract mantissa: FP80 has 64 bits (1 int + 63 frac)
                        // FP64 needs 52-bit fraction (no explicit int bit)
                        // Take bits [62:11] as fraction, bits [10:0] are discarded
                        discarded_bits = mant_in[10:0];

                        // Check if rounding needed
                        if (discarded_bits != 11'd0) begin
                            flag_inexact = 1'b1;

                            // Apply rounding based on mode
                            round_up = 1'b0;
                            case (rounding_mode)
                                2'b00: begin // Round to nearest (check guard bit)
                                    // Guard bit is bit 10
                                    if (discarded_bits[10]) begin
                                        // Check round and sticky bits
                                        if (discarded_bits[9:0] != 10'd0)
                                            round_up = 1'b1;
                                        else
                                            round_up = mant_in[11];  // Tie: round to even
                                    end
                                end
                                2'b01: round_up = sign_in;   // Round down
                                2'b10: round_up = !sign_in;  // Round up
                                2'b11: round_up = 1'b0;      // Truncate
                            endcase

                            if (round_up) begin
                                rounded_frac = {1'b1, mant_in[62:11]} + 53'd1;
                                // Check for mantissa overflow
                                if (rounded_frac[53]) begin
                                    // Mantissa overflowed, increment exponent
                                    exp_out = exp_out + 11'd1;
                                    if (exp_out == 11'h7FF) begin
                                        // Exponent overflow
                                        frac_out = 52'd0;
                                        flag_overflow = 1'b1;
                                    end else begin
                                        frac_out = rounded_frac[52:1];
                                    end
                                end else begin
                                    frac_out = rounded_frac[51:0];
                                end
                            end else begin
                                frac_out = mant_in[62:11];
                            end
                        end else begin
                            // Exact conversion
                            frac_out = mant_in[62:11];
                        end

                        fp64_out = {sign_out, exp_out, frac_out};
                        done = 1'b1;
                    end
                end
            end else begin
                done = 1'b0;
            end
        end
    end

endmodule
