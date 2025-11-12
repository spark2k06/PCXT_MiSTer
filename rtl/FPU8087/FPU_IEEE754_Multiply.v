// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// IEEE 754 Extended Precision (80-bit) Multiply Unit
//
// Implements proper floating-point multiplication according to
// IEEE 754 standard for 80-bit extended precision format.
//
// Format: [79:Sign][78:64:Exponent][63:Integer][62:0:Fraction]
//
// Features:
// - 64-bit × 64-bit mantissa multiplication
// - Proper exponent addition with bias correction
// - Normalization after multiplication
// - Rounding according to IEEE 754 modes
// - Special value handling (±0, ±∞, NaN)
// - Exception detection (invalid, overflow, underflow, inexact)
//=====================================================================

module FPU_IEEE754_Multiply(
    input wire clk,
    input wire reset,
    input wire enable,                  // Start operation

    // Operands
    input wire [79:0] operand_a,       // First operand (80-bit)
    input wire [79:0] operand_b,       // Second operand (80-bit)

    // Control
    input wire [1:0]  rounding_mode,   // 00=nearest, 01=down, 10=up, 11=truncate

    // Result
    output reg [79:0] result,          // Result (80-bit)
    output reg        done,            // Operation complete

    // Exception flags
    output reg        flag_invalid,    // Invalid operation (0×∞, NaN)
    output reg        flag_overflow,   // Result overflow
    output reg        flag_underflow,  // Result underflow
    output reg        flag_inexact     // Result not exact (rounded)
);

    //=================================================================
    // Internal States
    //=================================================================

    localparam STATE_IDLE       = 3'd0;
    localparam STATE_UNPACK     = 3'd1;
    localparam STATE_MULTIPLY   = 3'd2;
    localparam STATE_NORMALIZE  = 3'd3;
    localparam STATE_ROUND      = 3'd4;
    localparam STATE_PACK       = 3'd5;

    reg [2:0] state;

    //=================================================================
    // Unpacked Operands
    //=================================================================

    // Operand A
    reg        sign_a;
    reg [14:0] exp_a;
    reg [63:0] mant_a;
    reg        is_zero_a, is_inf_a, is_nan_a;

    // Operand B
    reg        sign_b;
    reg [14:0] exp_b;
    reg [63:0] mant_b;
    reg        is_zero_b, is_inf_b, is_nan_b;

    //=================================================================
    // Working Registers
    //=================================================================

    reg        result_sign;
    reg [15:0] result_exp;      // 16-bit to handle overflow/underflow
    reg [127:0] product;        // 64×64 = 128-bit product
    reg [66:0]  result_mant;    // Normalized result with guard/round/sticky

    reg        round_bit, sticky_bit;

    //=================================================================
    // Special Value Detection
    //=================================================================

    task detect_special_a;
        begin
            is_zero_a = (exp_a == 15'd0) && (mant_a == 64'd0);
            is_inf_a = (exp_a == 15'h7FFF) && (mant_a[62:0] == 63'd0) && (mant_a[63] == 1'b1);
            is_nan_a = (exp_a == 15'h7FFF) && ((mant_a[62:0] != 63'd0) || (mant_a[63] == 1'b0));
        end
    endtask

    task detect_special_b;
        begin
            is_zero_b = (exp_b == 15'd0) && (mant_b == 64'd0);
            is_inf_b = (exp_b == 15'h7FFF) && (mant_b[62:0] == 63'd0) && (mant_b[63] == 1'b1);
            is_nan_b = (exp_b == 15'h7FFF) && ((mant_b[62:0] != 63'd0) || (mant_b[63] == 1'b0));
        end
    endtask

    //=================================================================
    // Main State Machine
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
            done <= 1'b0;
            result <= 80'd0;
            flag_invalid <= 1'b0;
            flag_overflow <= 1'b0;
            flag_underflow <= 1'b0;
            flag_inexact <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    done <= 1'b0;
                    flag_invalid <= 1'b0;
                    flag_overflow <= 1'b0;
                    flag_underflow <= 1'b0;
                    flag_inexact <= 1'b0;

                    if (enable) begin
                        state <= STATE_UNPACK;
                    end
                end

                STATE_UNPACK: begin
                    // Unpack operand A
                    sign_a = operand_a[79];
                    exp_a = operand_a[78:64];
                    mant_a = operand_a[63:0];
                    detect_special_a;

                    // Unpack operand B
                    sign_b = operand_b[79];
                    exp_b = operand_b[78:64];
                    mant_b = operand_b[63:0];
                    detect_special_b;

                    // Calculate result sign (XOR of signs)
                    result_sign = sign_a ^ sign_b;

                    // Handle special cases
                    if (is_nan_a || is_nan_b) begin
                        // NaN propagation - return canonical NaN
                        result <= {1'b0, 15'h7FFF, 1'b1, 63'h4000000000000000};
                        flag_invalid <= 1'b1;
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if ((is_zero_a && is_inf_b) || (is_inf_a && is_zero_b)) begin
                        // 0 × ∞ = NaN (invalid operation)
                        result <= {1'b0, 15'h7FFF, 1'b1, 63'h4000000000000000};
                        flag_invalid <= 1'b1;
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (is_inf_a || is_inf_b) begin
                        // ∞ × finite = ∞
                        result <= {result_sign, 15'h7FFF, 1'b1, 63'd0};
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (is_zero_a || is_zero_b) begin
                        // 0 × anything = 0
                        result <= {result_sign, 79'd0};
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else begin
                        state <= STATE_MULTIPLY;
                    end
                end

                STATE_MULTIPLY: begin
                    // Add exponents and subtract bias
                    // exp_result = exp_a + exp_b - 16383
                    // NOTE: Check for underflow BEFORE subtraction to avoid wrap-around
                    if ({1'b0, exp_a} + {1'b0, exp_b} < 16'd16383) begin
                        // Underflow: exponent sum is less than bias
                        result <= {result_sign, 79'd0};
                        flag_underflow <= 1'b1;
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else begin
                        result_exp = {1'b0, exp_a} + {1'b0, exp_b} - 16'd16383;
                        // Multiply mantissas (64-bit × 64-bit = 128-bit)
                        product = mant_a * mant_b;
                        state <= STATE_NORMALIZE;
                    end
                end

                STATE_NORMALIZE: begin
                    // The product is 128 bits
                    // For normalized numbers with integer bit set:
                    //   mant_a[63]=1, mant_b[63]=1
                    //   product[127] or product[126] will be 1

                    if (product[127]) begin
                        // Product needs 128 bits, shift right by 1
                        // Integer bit is at position 127
                        // Format: [66:int][65:3:frac][2:guard][1:round][0:sticky]
                        result_mant = {product[127:62], |product[61:0]}; // 66 bits + sticky
                        result_exp = result_exp + 16'd1;
                    end else if (product[126]) begin
                        // Product fits in 127 bits, shift right by 0
                        // Integer bit is at position 126
                        // Format: [66:int][65:3:frac][2:guard][1:round][0:sticky]
                        result_mant = {product[126:61], |product[60:0]}; // 66 bits + sticky
                    end else begin
                        // Denormalized or zero product - shouldn't happen with normalized inputs
                        // Find the leading 1
                        integer i;
                        reg [6:0] shift_amount;
                        shift_amount = 7'd0;

                        for (i = 125; i >= 0; i = i - 1) begin
                            if (product[i] && shift_amount == 7'd0) begin
                                shift_amount = 7'd126 - i[6:0];
                            end
                        end

                        if (shift_amount > 0) begin
                            result_mant = {(product << shift_amount), 3'b000};
                            result_exp = result_exp - shift_amount;
                        end else begin
                            result_mant = {product[126:63], |product[62:0]};
                        end
                    end

                    // Check for overflow/underflow
                    // NOTE: Check overflow FIRST because large exponents (>32767) have bit[15]=1
                    // which would be incorrectly detected as underflow if checked first
                    if (result_exp >= 16'd32767) begin
                        // Overflow
                        result <= {result_sign, 15'h7FFF, 1'b1, 63'd0}; // ±∞
                        flag_overflow <= 1'b1;
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (result_exp[15]) begin
                        // Underflow (negative exponent after bias)
                        result <= {result_sign, 79'd0};
                        flag_underflow <= 1'b1;
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else begin
                        state <= STATE_ROUND;
                    end
                end

                STATE_ROUND: begin
                    // Extract guard, round, sticky bits from result_mant
                    // After normalization, integer bit is at position 66
                    // Bits 65:3 are fraction, bits 2:1:0 are guard/round/sticky
                    round_bit = result_mant[1];
                    sticky_bit = result_mant[0];

                    // Round according to mode
                    case (rounding_mode)
                        2'b00: begin // Round to nearest (ties to even)
                            if (round_bit && (sticky_bit || result_mant[2])) begin
                                result_mant = (result_mant >> 3) + 65'd1;
                                flag_inexact <= 1'b1;
                            end else begin
                                result_mant = result_mant >> 3;
                                if (round_bit || sticky_bit) flag_inexact <= 1'b1;
                            end
                        end
                        2'b01: begin // Round down (toward -∞)
                            if (result_sign && (round_bit || sticky_bit)) begin
                                result_mant = (result_mant >> 3) + 65'd1;
                                flag_inexact <= 1'b1;
                            end else begin
                                result_mant = result_mant >> 3;
                                if (round_bit || sticky_bit) flag_inexact <= 1'b1;
                            end
                        end
                        2'b10: begin // Round up (toward +∞)
                            if (!result_sign && (round_bit || sticky_bit)) begin
                                result_mant = (result_mant >> 3) + 65'd1;
                                flag_inexact <= 1'b1;
                            end else begin
                                result_mant = result_mant >> 3;
                                if (round_bit || sticky_bit) flag_inexact <= 1'b1;
                            end
                        end
                        2'b11: begin // Round toward zero (truncate)
                            result_mant = result_mant >> 3;
                            if (round_bit || sticky_bit) flag_inexact <= 1'b1;
                        end
                    endcase

                    // Check for rounding overflow
                    if (result_mant[64]) begin
                        result_mant = result_mant >> 1;
                        result_exp = result_exp + 16'd1;

                        if (result_exp >= 16'd32767) begin
                            result <= {result_sign, 15'h7FFF, 1'b1, 63'd0};
                            flag_overflow <= 1'b1;
                            done <= 1'b1;
                            state <= STATE_IDLE;
                        end else begin
                            state <= STATE_PACK;
                        end
                    end else begin
                        state <= STATE_PACK;
                    end
                end

                STATE_PACK: begin
                    // Pack result
                    result <= {result_sign, result_exp[14:0], result_mant[63:0]};
                    done <= 1'b1;
                    state <= STATE_IDLE;
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
