// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// IEEE 754 Extended Precision (80-bit) to Single Precision (32-bit) Converter
//
// Converts 80-bit extended precision to 32-bit single precision format.
//
// FP80 Format: [79:Sign][78:64:Exp][63:Int][62:0:Frac]
// FP32 Format: [31:Sign][30:23:Exp][22:0:Frac]
//
// Features:
// - All 4 rounding modes
// - Overflow/underflow detection (FP80 range → FP32 range)
// - Special value handling (±0, ±∞, NaN)
// - Exception flags
//=====================================================================

module FPU_FP80_to_FP32(
    input wire clk,
    input wire reset,
    input wire enable,              // Start conversion

    // Input
    input wire [79:0] fp80_in,      // 80-bit extended precision
    input wire [1:0]  rounding_mode,// 00=nearest, 01=down, 10=up, 11=truncate

    // Output
    output reg [31:0] fp32_out,     // 32-bit single precision
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
    reg [7:0]  exp_out;
    reg [22:0] frac_out;

    //=================================================================
    // Working Registers
    //=================================================================

    reg signed [16:0] exp_unbiased;  // Unbiased exponent
    reg [23:0] rounded_frac;         // 24 bits for rounding (1 int + 23 frac)
    reg        round_up;
    reg [39:0] discarded_bits;       // Bits lost in conversion

    //=================================================================
    // Conversion Logic
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fp32_out <= 32'd0;
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
                    exp_out = 8'hFF;
                    if (mant_in[62:0] == 63'd0 && mant_in[63] == 1'b1) begin
                        // ±∞
                        frac_out = 23'd0;
                    end else begin
                        // NaN
                        frac_out = {1'b1, mant_in[62:41]};  // Preserve some payload
                        flag_invalid = 1'b1;
                    end
                    fp32_out = {sign_out, exp_out, frac_out};
                    done = 1'b1;
                end else if (exp_in == 15'd0) begin
                    // ±0 or denormal
                    exp_out = 8'd0;
                    frac_out = 23'd0;
                    fp32_out = {sign_out, exp_out, frac_out};
                    if (mant_in != 64'd0)
                        flag_inexact = 1'b1;
                    done = 1'b1;
                end else begin
                    // Normal number
                    // Unbias FP80 exponent and check range for FP32
                    exp_unbiased = {2'b00, exp_in} - 17'sd16383;

                    // FP32 exponent range: -126 to +127
                    // Check for overflow
                    if (exp_unbiased > 17'sd127) begin
                        // Overflow to ±∞
                        exp_out = 8'hFF;
                        frac_out = 23'd0;
                        flag_overflow = 1'b1;
                        fp32_out = {sign_out, exp_out, frac_out};
                        done = 1'b1;
                    end else if (exp_unbiased < -17'sd126) begin
                        // Underflow to ±0 or denormal
                        if (exp_unbiased < -17'sd149) begin
                            // Too small even for denormal
                            exp_out = 8'd0;
                            frac_out = 23'd0;
                            flag_underflow = 1'b1;
                            flag_inexact = 1'b1;
                        end else begin
                            // Can represent as denormal
                            // Denormal: shift mantissa right by |exp_unbiased + 126|
                            exp_out = 8'd0;
                            rounded_frac = mant_in[63:40] >> (-exp_unbiased - 17'sd126);
                            frac_out = rounded_frac[22:0];
                            flag_underflow = 1'b1;
                            flag_inexact = 1'b1;
                        end
                        fp32_out = {sign_out, exp_out, frac_out};
                        done = 1'b1;
                    end else begin
                        // Normal range: convert exponent
                        // FP32 biased exp = exp_unbiased + 127
                        exp_out = exp_unbiased[7:0] + 8'd127;

                        // Extract mantissa: FP80 has 64 bits (1 int + 63 frac)
                        // FP32 needs 23-bit fraction (no explicit int bit)
                        // Take bits [62:40] as fraction, bits [39:0] are discarded
                        discarded_bits = mant_in[39:0];

                        // Check if rounding needed
                        if (discarded_bits != 40'd0) begin
                            flag_inexact = 1'b1;

                            // Apply rounding based on mode
                            round_up = 1'b0;
                            case (rounding_mode)
                                2'b00: begin // Round to nearest (check guard bit)
                                    // Guard bit is bit 39
                                    if (discarded_bits[39]) begin
                                        // Check round and sticky bits
                                        if (discarded_bits[38:0] != 39'd0)
                                            round_up = 1'b1;
                                        else
                                            round_up = mant_in[40];  // Tie: round to even
                                    end
                                end
                                2'b01: round_up = sign_in;   // Round down
                                2'b10: round_up = !sign_in;  // Round up
                                2'b11: round_up = 1'b0;      // Truncate
                            endcase

                            if (round_up) begin
                                rounded_frac = {1'b1, mant_in[62:40]} + 24'd1;
                                // Check for mantissa overflow
                                if (rounded_frac[24]) begin
                                    // Mantissa overflowed, increment exponent
                                    exp_out = exp_out + 8'd1;
                                    if (exp_out == 8'hFF) begin
                                        // Exponent overflow
                                        frac_out = 23'd0;
                                        flag_overflow = 1'b1;
                                    end else begin
                                        frac_out = rounded_frac[23:1];
                                    end
                                end else begin
                                    frac_out = rounded_frac[22:0];
                                end
                            end else begin
                                frac_out = mant_in[62:40];
                            end
                        end else begin
                            // Exact conversion
                            frac_out = mant_in[62:40];
                        end

                        fp32_out = {sign_out, exp_out, frac_out};
                        done = 1'b1;
                    end
                end
            end else begin
                done = 1'b0;
            end
        end
    end

endmodule
