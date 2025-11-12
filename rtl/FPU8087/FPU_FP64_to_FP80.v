// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// IEEE 754 Double Precision (64-bit) to Extended Precision (80-bit) Converter
//
// Converts 64-bit double precision to 80-bit extended precision format.
//
// FP64 Format: [63:Sign][62:52:Exp][51:0:Frac]
// FP80 Format: [79:Sign][78:64:Exp][63:Int][62:0:Frac]
//
// Features:
// - Special value handling (±0, ±∞, NaN)
// - Denormalized number handling
// - Exponent rebasing (1023 → 16383)
// - Single-cycle operation
//=====================================================================

module FPU_FP64_to_FP80(
    input wire clk,
    input wire reset,
    input wire enable,              // Start conversion

    // Input
    input wire [63:0] fp64_in,      // 64-bit double precision

    // Output
    output reg [79:0] fp80_out,     // 80-bit extended precision
    output reg done                 // Conversion complete
);

    //=================================================================
    // Unpacked FP64
    //=================================================================

    reg        sign_in;
    reg [10:0] exp_in;
    reg [51:0] frac_in;

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
                // Unpack FP64
                sign_in = fp64_in[63];
                exp_in = fp64_in[62:52];
                frac_in = fp64_in[51:0];

                // Copy sign
                sign_out = sign_in;

                // Handle different cases
                if (exp_in == 11'd0) begin
                    // Zero or denormalized
                    if (frac_in == 52'd0) begin
                        // ±0
                        exp_out = 15'd0;
                        mant_out = 64'd0;
                    end else begin
                        // Denormalized number: exp = -1022, no implicit 1
                        // Need to normalize it for FP80
                        // Find leading 1 in fraction
                        shift_amount = 6'd0;
                        for (i = 51; i >= 0; i = i - 1) begin
                            if (frac_in[i] && shift_amount == 6'd0) begin
                                shift_amount = 6'd51 - i[5:0];
                            end
                        end

                        // Exponent for denormalized FP64 is -1022
                        // After normalizing, exp = -1022 - shift_amount
                        // Convert to FP80: 16383 + (-1022 - shift_amount)
                        exp_out = 15'd16383 - 15'd1022 - {9'd0, shift_amount};

                        // Normalize mantissa: shift left so MSB becomes integer bit
                        // Integer bit will be at position 63
                        mant_out = {frac_in, 12'd0} << (shift_amount + 6'd1);
                    end
                end else if (exp_in == 11'd2047) begin
                    // ±∞ or NaN
                    exp_out = 15'h7FFF;
                    if (frac_in == 52'd0) begin
                        // ±∞
                        mant_out = 64'h8000000000000000;  // Integer bit set, fraction 0
                    end else begin
                        // NaN - preserve fraction bits as payload
                        mant_out = {1'b1, frac_in, 11'd0};  // Quiet NaN
                    end
                end else begin
                    // Normalized number
                    // Convert exponent: FP64 bias 1023 → FP80 bias 16383
                    // FP64 exp = exp_in - 1023
                    // FP80 exp = (exp_in - 1023) + 16383 = exp_in + 15360
                    exp_out = {4'd0, exp_in} + 15'd15360;

                    // Convert mantissa: add explicit integer bit (1.fraction)
                    // FP64 has 52-bit fraction, FP80 needs 64-bit mantissa (1 integer + 63 fraction)
                    mant_out = {1'b1, frac_in, 11'd0};  // Integer bit = 1, shift fraction left
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
