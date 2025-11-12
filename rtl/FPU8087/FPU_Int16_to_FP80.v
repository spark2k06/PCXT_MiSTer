// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// 16-bit Signed Integer to IEEE 754 Extended Precision (80-bit) Converter
//
// Converts 16-bit signed integers to 80-bit extended precision format.
//
// Features:
// - Handles positive and negative integers
// - Proper normalization
// - Zero handling
// - Single-cycle operation
//=====================================================================

module FPU_Int16_to_FP80(
    input wire clk,
    input wire reset,
    input wire enable,              // Start conversion

    // Input
    input wire signed [15:0] int_in,  // 16-bit signed integer

    // Output
    output reg [79:0] fp_out,       // 80-bit floating-point
    output reg done                 // Conversion complete
);

    //=================================================================
    // Internal Registers
    //=================================================================

    reg        result_sign;
    reg [14:0] result_exp;
    reg [63:0] result_mant;
    reg [15:0] abs_value;
    reg [5:0]  shift_amount;
    integer    i;

    //=================================================================
    // Conversion Logic
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fp_out <= 80'd0;
            done <= 1'b0;
        end else begin
            if (enable) begin
                // Handle zero
                if (int_in == 16'd0) begin
                    fp_out <= 80'd0;  // +0.0
                    done <= 1'b1;
                end else begin
                    // Get sign and absolute value
                    if (int_in < 0) begin
                        result_sign = 1'b1;
                        abs_value = -int_in;
                    end else begin
                        result_sign = 1'b0;
                        abs_value = int_in;
                    end

                    // Find leading 1 position (normalization)
                    shift_amount = 6'd0;
                    for (i = 15; i >= 0; i = i - 1) begin
                        if (abs_value[i] && shift_amount == 6'd0) begin
                            shift_amount = 6'd15 - i[5:0];
                        end
                    end

                    // Calculate exponent: bias + (15 - shift_amount)
                    // The integer bit will be at position 15 after shift
                    result_exp = 15'd16383 + (15'd15 - {9'd0, shift_amount});

                    // Normalize mantissa: shift so MSB is at position 63 (integer bit)
                    // We need to shift left by (63 - (15 - shift_amount))
                    // = (63 - 15 + shift_amount) = 48 + shift_amount
                    result_mant = {abs_value, 48'd0} << shift_amount;

                    // Pack result
                    fp_out <= {result_sign, result_exp, result_mant};
                    done <= 1'b1;
                end
            end else begin
                done <= 1'b0;
            end
        end
    end

endmodule
