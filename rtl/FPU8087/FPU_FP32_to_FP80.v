// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// IEEE 754 Single Precision (32-bit) to Extended Precision (80-bit) Converter
//
// Converts 32-bit single precision to 80-bit extended precision format.
//
// FP32 Format: [31:Sign][30:23:Exp][22:0:Frac]
// FP80 Format: [79:Sign][78:64:Exp][63:Int][62:0:Frac]
//
// Features:
// - Special value handling (±0, ±∞, NaN)
// - Denormalized number handling
// - Exponent rebasing (127 → 16383)
// - Single-cycle operation
//=====================================================================

module FPU_FP32_to_FP80(
    input wire clk,
    input wire reset,
    input wire enable,              // Start conversion

    // Input
    input wire [31:0] fp32_in,      // 32-bit single precision

    // Output
    output reg [79:0] fp80_out,     // 80-bit extended precision
    output reg done                 // Conversion complete
);

    //=================================================================
    // Unpacked FP32
    //=================================================================

    reg        sign_in;
    reg [7:0]  exp_in;
    reg [22:0] frac_in;

    //=================================================================
    // Output Components
    //=================================================================

    reg        sign_out;
    reg [14:0] exp_out;
    reg [63:0] mant_out;

    //=================================================================
    // Working Registers
    //=================================================================

    reg [5:0] shift_amount;
    integer   i;

    //=================================================================
    // Conversion Logic
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fp80_out <= 80'd0;
            done <= 1'b0;
        end else begin
            if (enable) begin
                // Unpack FP32
                sign_in = fp32_in[31];
                exp_in = fp32_in[30:23];
                frac_in = fp32_in[22:0];

                // Copy sign
                sign_out = sign_in;

                // Handle different cases
                if (exp_in == 8'd0) begin
                    // Zero or denormalized
                    if (frac_in == 23'd0) begin
                        // ±0
                        exp_out = 15'd0;
                        mant_out = 64'd0;
                    end else begin
                        // Denormalized number: exp = -126, no implicit 1
                        // Need to normalize it for FP80
                        // Find leading 1 in fraction
                        shift_amount = 6'd0;
                        for (i = 22; i >= 0; i = i - 1) begin
                            if (frac_in[i] && shift_amount == 6'd0) begin
                                shift_amount = 6'd22 - i[5:0];
                            end
                        end

                        // Exponent for denormalized FP32 is -126
                        // After normalizing, exp = -126 - shift_amount
                        // Convert to FP80: 16383 + (-126 - shift_amount)
                        exp_out = 15'd16383 - 15'd126 - {9'd0, shift_amount};

                        // Normalize mantissa: shift left so MSB becomes integer bit
                        // Integer bit will be at position 63
                        mant_out = {frac_in, 41'd0} << (shift_amount + 6'd1);
                    end
                end else if (exp_in == 8'd255) begin
                    // ±∞ or NaN
                    exp_out = 15'h7FFF;
                    if (frac_in == 23'd0) begin
                        // ±∞
                        mant_out = 64'h8000000000000000;  // Integer bit set, fraction 0
                    end else begin
                        // NaN - preserve some fraction bits as payload
                        mant_out = {1'b1, frac_in, 40'd0};  // Quiet NaN
                    end
                end else begin
                    // Normalized number
                    // Convert exponent: FP32 bias 127 → FP80 bias 16383
                    // FP32 exp = exp_in - 127
                    // FP80 exp = (exp_in - 127) + 16383 = exp_in + 16256
                    exp_out = {7'd0, exp_in} + 15'd16256;

                    // Convert mantissa: add explicit integer bit (1.fraction)
                    // FP32 has 23-bit fraction, FP80 needs 64-bit mantissa (1 integer + 63 fraction)
                    mant_out = {1'b1, frac_in, 40'd0};  // Integer bit = 1, shift fraction left
                end

                // Pack FP80
                fp80_out = {sign_out, exp_out, mant_out};
                done = 1'b1;
            end else begin
                done = 1'b0;
            end
        end
    end

endmodule
