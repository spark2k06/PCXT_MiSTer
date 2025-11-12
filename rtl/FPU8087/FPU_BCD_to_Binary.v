// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// BCD to Binary Converter
//
// Converts 18-digit packed BCD (Intel 8087 format) to 64-bit binary
//
// Input Format (80 bits):
//   [79]     : Sign (0=positive, 1=negative)
//   [78:72]  : Unused (should be 0)
//   [71:0]   : 18 BCD digits (4 bits each)
//              Digit 17 (most significant) in bits [71:68]
//              Digit 0 (least significant) in bits [3:0]
//
// Output: 64-bit unsigned binary + sign
//
// Max BCD value: 999999999999999999 (18 digits)
// Max binary:    0x0DE0_B6B3_A763_FFFF
//=====================================================================

module FPU_BCD_to_Binary(
    input wire clk,
    input wire reset,
    input wire enable,

    input wire [79:0] bcd_in,       // Packed BCD input

    output reg [63:0] binary_out,   // Binary output
    output reg        sign_out,     // Sign bit
    output reg        done,
    output reg        error         // Invalid BCD digit detected
);

    //=================================================================
    // State Machine
    //=================================================================

    localparam STATE_IDLE    = 2'd0;
    localparam STATE_CONVERT = 2'd1;
    localparam STATE_DONE    = 2'd2;

    reg [1:0] state;
    reg [4:0] digit_count;      // 0-17 (18 digits)
    reg [63:0] accumulator;     // Running total

    //=================================================================
    // BCD Digit Extraction
    //=================================================================

    function [3:0] get_bcd_digit;
        input [79:0] bcd_value;
        input [4:0]  digit_index;
        reg [6:0] bit_pos;
        begin
            bit_pos = digit_index * 4;
            get_bcd_digit = bcd_value[bit_pos +: 4];
        end
    endfunction

    //=================================================================
    // BCD Digit Validation
    //=================================================================

    function is_valid_bcd_digit;
        input [3:0] digit;
        begin
            is_valid_bcd_digit = (digit <= 4'd9);
        end
    endfunction

    //=================================================================
    // Multiply by 10 (shift + add)
    //=================================================================

    function [63:0] multiply_by_10;
        input [63:0] value;
        reg [63:0] shifted_2;
        reg [63:0] shifted_8;
        begin
            // value * 10 = (value << 1) + (value << 3)
            //            = value * 2 + value * 8
            shifted_2 = value << 1;
            shifted_8 = value << 3;
            multiply_by_10 = shifted_2 + shifted_8;
        end
    endfunction

    //=================================================================
    // Main Conversion Logic
    //=================================================================

    reg [3:0] current_digit;
    reg [79:0] bcd_data;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
            binary_out <= 64'd0;
            sign_out <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
            digit_count <= 5'd0;
            accumulator <= 64'd0;
            bcd_data <= 80'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    done <= 1'b0;
                    error <= 1'b0;

                    if (enable) begin
                        // Capture input
                        bcd_data <= bcd_in;
                        sign_out <= bcd_in[79];

                        // Check for invalid unused bits
                        if (bcd_in[78:72] != 7'd0) begin
                            error <= 1'b1;
                            state <= STATE_DONE;
                        end else begin
                            // Start conversion from most significant digit (digit 17)
                            digit_count <= 5'd17;
                            accumulator <= 64'd0;
                            state <= STATE_CONVERT;
                        end
                    end
                end

                STATE_CONVERT: begin
                    // Get current digit
                    current_digit = get_bcd_digit(bcd_data, digit_count);

                    // Validate digit
                    if (!is_valid_bcd_digit(current_digit)) begin
                        error <= 1'b1;
                        state <= STATE_DONE;
                    end else begin
                        // Move to next digit
                        if (digit_count == 5'd0) begin
                            // Finished all digits - output final result
                            binary_out <= multiply_by_10(accumulator) + {60'd0, current_digit};
                            state <= STATE_DONE;
                        end else begin
                            // Multiply accumulator by 10 and add current digit
                            accumulator <= multiply_by_10(accumulator) + {60'd0, current_digit};
                            digit_count <= digit_count - 1;
                        end
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
