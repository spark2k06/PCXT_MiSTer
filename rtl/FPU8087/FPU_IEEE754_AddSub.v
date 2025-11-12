// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// IEEE 754 Extended Precision (80-bit) Add/Subtract Unit
//
// Implements proper floating-point addition and subtraction according
// to IEEE 754 standard for 80-bit extended precision format.
//
// Format: [79:Sign][78:64:Exponent][63:Integer][62:0:Fraction]
// - Sign: 1 bit
// - Exponent: 15 bits, biased by 16383
// - Integer bit: 1 bit (explicit, unlike 32/64-bit formats)
// - Fraction: 63 bits
//
// Features:
// - Exponent alignment with guard, round, and sticky bits
// - Proper normalization after operation
// - Rounding according to IEEE 754 modes
// - Special value handling (±0, ±∞, NaN, denormals)
// - Exception detection (invalid, overflow, underflow, inexact)
//=====================================================================

module FPU_IEEE754_AddSub(
    input wire clk,
    input wire reset,
    input wire enable,                  // Start operation

    // Operands
    input wire [79:0] operand_a,       // First operand (80-bit)
    input wire [79:0] operand_b,       // Second operand (80-bit)
    input wire        subtract,        // 0=add, 1=subtract

    // Control
    input wire [1:0]  rounding_mode,   // 00=nearest, 01=down, 10=up, 11=truncate

    // Result
    output reg [79:0] result,          // Result (80-bit)
    output reg        done,            // Operation complete

    // Comparison outputs
    output reg        cmp_equal,       // operand_a == operand_b
    output reg        cmp_less,        // operand_a < operand_b
    output reg        cmp_greater,     // operand_a > operand_b

    // Exception flags
    output reg        flag_invalid,    // Invalid operation (NaN operand, ∞-∞)
    output reg        flag_overflow,   // Result overflow
    output reg        flag_underflow,  // Result underflow
    output reg        flag_inexact     // Result not exact (rounded)
);

    //=================================================================
    // Internal States
    //=================================================================

    localparam STATE_IDLE       = 3'd0;
    localparam STATE_UNPACK     = 3'd1;
    localparam STATE_ALIGN      = 3'd2;
    localparam STATE_ADD        = 3'd3;
    localparam STATE_NORMALIZE  = 3'd4;
    localparam STATE_ROUND      = 3'd5;
    localparam STATE_PACK       = 3'd6;

    reg [2:0] state;

    //=================================================================
    // Unpacked Operands
    //=================================================================

    // Operand A
    reg        sign_a;
    reg [14:0] exp_a;
    reg [63:0] mant_a;  // 64-bit: [63]=integer bit, [62:0]=fraction
    reg        is_zero_a, is_inf_a, is_nan_a, is_denorm_a;

    // Operand B
    reg        sign_b;
    reg [14:0] exp_b;
    reg [63:0] mant_b;
    reg        is_zero_b, is_inf_b, is_nan_b, is_denorm_b;

    //=================================================================
    // Working Registers
    //=================================================================

    reg        result_sign;
    reg [14:0] result_exp;
    reg [67:0] result_mant;  // 68-bit for carry + 64-bit mantissa + guard/round/sticky

    reg [14:0] exp_diff;
    reg [67:0] aligned_mant_a;  // Extended with guard, round, sticky bits
    reg [67:0] aligned_mant_b;

    reg [6:0]  norm_shift;  // Normalization shift amount (up to 66)
    reg        round_bit, sticky_bit;
    integer    i;  // Loop variable

    //=================================================================
    // Special Value Detection
    //=================================================================

    task detect_special_a;
        begin
            // Zero: exp=0, int=0, frac=0
            is_zero_a = (exp_a == 15'd0) && (mant_a == 64'd0);

            // Infinity: exp=max, int=1, frac=0
            is_inf_a = (exp_a == 15'h7FFF) && (mant_a[62:0] == 63'd0) && (mant_a[63] == 1'b1);

            // NaN: exp=max, frac!=0, or exp=max with int=0
            is_nan_a = (exp_a == 15'h7FFF) && ((mant_a[62:0] != 63'd0) || (mant_a[63] == 1'b0));

            // Denormal: exp=0, int=0, frac!=0 (unnormalized)
            is_denorm_a = (exp_a == 15'd0) && (mant_a[62:0] != 63'd0);
        end
    endtask

    task detect_special_b;
        begin
            is_zero_b = (exp_b == 15'd0) && (mant_b == 64'd0);
            is_inf_b = (exp_b == 15'h7FFF) && (mant_b[62:0] == 63'd0) && (mant_b[63] == 1'b1);
            is_nan_b = (exp_b == 15'h7FFF) && ((mant_b[62:0] != 63'd0) || (mant_b[63] == 1'b0));
            is_denorm_b = (exp_b == 15'd0) && (mant_b[62:0] != 63'd0);
        end
    endtask

    //=================================================================
    // Comparison Logic
    //=================================================================

    task do_comparison;
        begin
            // Handle special cases
            if (is_nan_a || is_nan_b) begin
                // NaN comparisons are unordered
                cmp_equal = 1'b0;
                cmp_less = 1'b0;
                cmp_greater = 1'b0;
            end else if (is_zero_a && is_zero_b) begin
                // +0 == -0
                cmp_equal = 1'b1;
                cmp_less = 1'b0;
                cmp_greater = 1'b0;
            end else if (sign_a != sign_b) begin
                // Different signs
                if (is_zero_a && is_zero_b) begin
                    cmp_equal = 1'b1;
                    cmp_less = 1'b0;
                    cmp_greater = 1'b0;
                end else if (sign_a == 1'b1) begin
                    // A is negative, B is positive
                    cmp_equal = 1'b0;
                    cmp_less = 1'b1;
                    cmp_greater = 1'b0;
                end else begin
                    // A is positive, B is negative
                    cmp_equal = 1'b0;
                    cmp_less = 1'b0;
                    cmp_greater = 1'b1;
                end
            end else begin
                // Same sign, compare magnitude
                if (exp_a > exp_b) begin
                    cmp_equal = 1'b0;
                    cmp_less = sign_a;      // If negative, larger exp = smaller value
                    cmp_greater = ~sign_a;
                end else if (exp_a < exp_b) begin
                    cmp_equal = 1'b0;
                    cmp_less = ~sign_a;
                    cmp_greater = sign_a;
                end else begin
                    // Same exponent, compare mantissa
                    if (mant_a > mant_b) begin
                        cmp_equal = 1'b0;
                        cmp_less = sign_a;
                        cmp_greater = ~sign_a;
                    end else if (mant_a < mant_b) begin
                        cmp_equal = 1'b0;
                        cmp_less = ~sign_a;
                        cmp_greater = sign_a;
                    end else begin
                        cmp_equal = 1'b1;
                        cmp_less = 1'b0;
                        cmp_greater = 1'b0;
                    end
                end
            end
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
            cmp_equal <= 1'b0;
            cmp_less <= 1'b0;
            cmp_greater <= 1'b0;
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
                    // Unpack operand A (use blocking assignments for immediate use)
                    sign_a = operand_a[79];
                    exp_a = operand_a[78:64];
                    mant_a = operand_a[63:0];
                    detect_special_a;

                    // Unpack operand B (flip sign for subtraction)
                    sign_b = subtract ? ~operand_b[79] : operand_b[79];
                    exp_b = operand_b[78:64];
                    mant_b = operand_b[63:0];
                    detect_special_b;

                    // Do comparison
                    do_comparison;

                    state <= STATE_ALIGN;
                end

                STATE_ALIGN: begin
                    // Handle special cases first
                    if (is_nan_a || is_nan_b) begin
                        // NaN propagation - return canonical NaN
                        result <= {1'b0, 15'h7FFF, 1'b1, 63'h4000000000000000}; // QNaN
                        flag_invalid <= 1'b1;
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (is_inf_a && is_inf_b && (sign_a != sign_b)) begin
                        // ∞ - ∞ = NaN (invalid operation)
                        result <= {1'b0, 15'h7FFF, 1'b1, 63'h4000000000000000}; // QNaN
                        flag_invalid <= 1'b1;
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (is_inf_a) begin
                        // A is infinity, result is infinity with sign of A
                        result <= {sign_a, 15'h7FFF, 1'b1, 63'd0};
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (is_inf_b) begin
                        // B is infinity, result is infinity with sign of B
                        result <= {sign_b, 15'h7FFF, 1'b1, 63'd0};
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (is_zero_a && is_zero_b) begin
                        // 0 + 0 = 0, sign handling for rounding mode
                        if (sign_a == sign_b) begin
                            result <= {sign_a, 79'd0};
                        end else begin
                            // +0 + -0 or -0 + +0
                            result <= {(rounding_mode == 2'b01) ? 1'b1 : 1'b0, 79'd0}; // -0 for round down, +0 otherwise
                        end
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (is_zero_a) begin
                        // A is zero, result is B
                        result <= {sign_b, exp_b, mant_b};
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (is_zero_b) begin
                        // B is zero, result is A
                        result <= {sign_a, exp_a, mant_a};
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else begin
                        // Normal case: align exponents
                        if (exp_a >= exp_b) begin
                            exp_diff = exp_a - exp_b;
                            result_exp = exp_a;

                            // A is larger or equal exponent
                            aligned_mant_a = {1'b0, mant_a, 3'b000};  // 68-bit with carry space

                            // Shift B right by exp_diff
                            if (exp_diff == 0) begin
                                aligned_mant_b = {1'b0, mant_b, 3'b000};
                            end else if (exp_diff < 68) begin
                                // Shift right and capture sticky bit
                                aligned_mant_b = ({1'b0, mant_b, 3'b000} >> exp_diff);
                                // Set sticky bit if any 1's were shifted out
                                sticky_bit = |({1'b0, mant_b, 3'b000} & ((68'd1 << exp_diff) - 68'd1));
                                if (sticky_bit) aligned_mant_b[0] = 1'b1;
                            end else begin
                                // Shift is too large, B becomes just sticky bit
                                aligned_mant_b = 68'd1;
                            end
                        end else begin
                            exp_diff = exp_b - exp_a;
                            result_exp = exp_b;

                            // B is larger exponent
                            aligned_mant_b = {1'b0, mant_b, 3'b000};

                            // Shift A right by exp_diff
                            if (exp_diff < 68) begin
                                aligned_mant_a = ({1'b0, mant_a, 3'b000} >> exp_diff);
                                sticky_bit = |({1'b0, mant_a, 3'b000} & ((68'd1 << exp_diff) - 68'd1));
                                if (sticky_bit) aligned_mant_a[0] = 1'b1;
                            end else begin
                                aligned_mant_a = 68'd1;
                            end
                        end

                        state <= STATE_ADD;
                    end
                end

                STATE_ADD: begin
                    if (sign_a == sign_b) begin
                        // Same sign: add mantissas
                        result_mant = aligned_mant_a + aligned_mant_b;
                        result_sign = sign_a;

                        // Check for carry out (overflow of mantissa)
                        if (result_mant[67]) begin
                            // Carry out: shift right and increment exponent
                            sticky_bit = result_mant[0];
                            result_mant = result_mant >> 1;
                            if (sticky_bit) result_mant[0] = 1'b1;
                            result_exp = result_exp + 15'd1;

                            // Check for exponent overflow
                            if (result_exp >= 15'h7FFF) begin
                                // Overflow to infinity
                                result <= {result_sign, 15'h7FFF, 1'b1, 63'd0};
                                flag_overflow <= 1'b1;
                                done <= 1'b1;
                                state <= STATE_IDLE;
                            end else begin
                                state <= STATE_NORMALIZE;
                            end
                        end else begin
                            state <= STATE_NORMALIZE;
                        end
                    end else begin
                        // Different signs: subtract mantissas
                        if (aligned_mant_a >= aligned_mant_b) begin
                            result_mant = aligned_mant_a - aligned_mant_b;
                            result_sign = sign_a;
                        end else begin
                            result_mant = aligned_mant_b - aligned_mant_a;
                            result_sign = sign_b;
                        end

                        // Check for zero result
                        if (result_mant == 68'd0) begin
                            // Result is zero
                            result <= {(rounding_mode == 2'b01) ? 1'b1 : 1'b0, 79'd0};
                            done <= 1'b1;
                            state <= STATE_IDLE;
                        end else begin
                            state <= STATE_NORMALIZE;
                        end
                    end
                end

                STATE_NORMALIZE: begin
                    // Find leading 1 in result_mant
                    // Integer bit should be at position 66 after normalization
                    // Count how many positions we need to shift left
                    norm_shift = 7'd0;

                    if (result_mant[66]) begin
                        // Already normalized - integer bit at position 66
                        norm_shift = 7'd0;
                    end else if (result_mant[65]) begin
                        norm_shift = 7'd1;
                    end else if (result_mant[64]) begin
                        norm_shift = 7'd2;
                    end else if (result_mant[63]) begin
                        norm_shift = 7'd3;
                    end else if (result_mant[62]) begin
                        norm_shift = 7'd4;
                    end else if (result_mant[61]) begin
                        norm_shift = 7'd5;
                    end else if (result_mant[60]) begin
                        norm_shift = 7'd6;
                    end else begin
                        // Need to count more carefully for larger shifts
                        norm_shift = 7'd64; // Max shift
                        for (i = 59; i >= 0; i = i - 1) begin
                            if (result_mant[i]) begin
                                norm_shift = 7'd66 - i[6:0];
                                i = -1; // Break loop
                            end
                        end
                    end

                    if (norm_shift > 0 && norm_shift < 64) begin
                        // Shift left to normalize
                        result_mant = result_mant << norm_shift;

                        // Check if we can subtract from exponent
                        if (result_exp > norm_shift) begin
                            result_exp = result_exp - norm_shift;
                        end else begin
                            // Underflow: result becomes denormal or zero
                            if (result_exp > 0) begin
                                // Shift less to avoid underflow
                                result_mant = result_mant >> (norm_shift - result_exp);
                                result_exp = 15'd0;
                                flag_underflow <= 1'b1;
                            end else begin
                                // Already underflowed
                                result <= {result_sign, 79'd0};
                                flag_underflow <= 1'b1;
                                done <= 1'b1;
                                state <= STATE_IDLE;
                            end
                        end
                    end

                    if (state == STATE_NORMALIZE) begin
                        state <= STATE_ROUND;
                    end
                end

                STATE_ROUND: begin
                    // Extract guard, round, sticky bits
                    // Guard bit is at position 2, round at 1, sticky at 0
                    round_bit = result_mant[1];
                    sticky_bit = result_mant[0];

                    // Round according to mode
                    // Note: We shift right by 3 to move integer bit from position 66 to 63
                    case (rounding_mode)
                        2'b00: begin // Round to nearest (ties to even)
                            if (round_bit && (sticky_bit || result_mant[2])) begin
                                // Round up
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
                        result_exp = result_exp + 15'd1;
                        if (result_exp >= 15'h7FFF) begin
                            // Overflow to infinity
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
                    result <= {result_sign, result_exp, result_mant[63:0]};
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
