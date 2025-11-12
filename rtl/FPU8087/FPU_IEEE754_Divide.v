// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// IEEE 754 Extended Precision (80-bit) Divide Unit
//
// Implements proper floating-point division according to
// IEEE 754 standard for 80-bit extended precision format.
//
// Format: [79:Sign][78:64:Exponent][63:Integer][62:0:Fraction]
//
// Features:
// - 64-bit ÷ 64-bit mantissa division
// - Proper exponent subtraction with bias correction
// - Normalization after division
// - Rounding according to IEEE 754 modes
// - Special value handling (±0, ±∞, NaN)
// - Exception detection (invalid, divide-by-zero, overflow, underflow, inexact)
//=====================================================================

module FPU_IEEE754_Divide(
    input wire clk,
    input wire reset,
    input wire enable,                  // Start operation

    // Operands
    input wire [79:0] operand_a,       // Dividend (80-bit)
    input wire [79:0] operand_b,       // Divisor (80-bit)

    // Control
    input wire [1:0]  rounding_mode,   // 00=nearest, 01=down, 10=up, 11=truncate

    // Result
    output reg [79:0] result,          // Result (80-bit)
    output reg        done,            // Operation complete

    // Exception flags
    output reg        flag_invalid,    // Invalid operation (0÷0, ∞÷∞)
    output reg        flag_div_by_zero,// Division by zero
    output reg        flag_overflow,   // Result overflow
    output reg        flag_underflow,  // Result underflow
    output reg        flag_inexact     // Result not exact (rounded)
);

    //=================================================================
    // Internal States
    //=================================================================

    localparam STATE_IDLE       = 3'd0;
    localparam STATE_UNPACK     = 3'd1;
    localparam STATE_DIVIDE     = 3'd2;
    localparam STATE_NORMALIZE  = 3'd3;
    localparam STATE_ROUND      = 3'd4;
    localparam STATE_PACK       = 3'd5;

    reg [2:0] state;

    //=================================================================
    // Unpacked Operands
    //=================================================================

    // Operand A (dividend)
    reg        sign_a;
    reg [14:0] exp_a;
    reg [63:0] mant_a;
    reg        is_zero_a, is_inf_a, is_nan_a;

    // Operand B (divisor)
    reg        sign_b;
    reg [14:0] exp_b;
    reg [63:0] mant_b;
    reg        is_zero_b, is_inf_b, is_nan_b;

    //=================================================================
    // Working Registers
    //=================================================================

    reg        result_sign;
    reg signed [16:0] result_exp;   // 17-bit signed to handle overflow/underflow
    reg signed [128:0] remainder;   // Signed partial remainder (129-bit for sign)
    reg [63:0]  divisor;            // Divisor
    reg [66:0]  quotient;           // Quotient with guard/round/sticky
    reg [66:0]  result_mant;        // Normalized result with guard/round/sticky

    reg        round_bit, sticky_bit;
    reg [6:0]  div_count;           // Division iteration counter

    // SRT Division specific registers
    reg signed [1:0] quotient_digits [0:66];  // Signed-digit quotient: {-1, 0, 1}
    reg [63:0]  divisor_half;       // divisor >> 1 for SRT selection
    integer     srt_i;              // Loop variable for quotient conversion

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
            flag_div_by_zero <= 1'b0;
            flag_overflow <= 1'b0;
            flag_underflow <= 1'b0;
            flag_inexact <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    done <= 1'b0;
                    flag_invalid <= 1'b0;
                    flag_div_by_zero <= 1'b0;
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
                    end else if ((is_zero_a && is_zero_b) || (is_inf_a && is_inf_b)) begin
                        // 0÷0 or ∞÷∞ = NaN (invalid operation)
                        result <= {1'b0, 15'h7FFF, 1'b1, 63'h4000000000000000};
                        flag_invalid <= 1'b1;
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (is_zero_b) begin
                        // x÷0 = ±∞ (divide by zero)
                        result <= {result_sign, 15'h7FFF, 1'b1, 63'd0};
                        flag_div_by_zero <= 1'b1;
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (is_inf_a) begin
                        // ∞÷finite = ±∞
                        result <= {result_sign, 15'h7FFF, 1'b1, 63'd0};
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (is_zero_a) begin
                        // 0÷finite = ±0
                        result <= {result_sign, 79'd0};
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else if (is_inf_b) begin
                        // finite÷∞ = ±0
                        result <= {result_sign, 79'd0};
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else begin
                        state <= STATE_DIVIDE;
                    end
                end

                STATE_DIVIDE: begin
                    // Calculate exponent: exp_a - exp_b + bias
                    // NOTE: Check for underflow/overflow BEFORE calculation
                    if ({1'b0, exp_a} + 17'd16383 < {1'b0, exp_b}) begin
                        // Underflow: exp_a - exp_b + bias < 0
                        result <= {result_sign, 79'd0};
                        flag_underflow <= 1'b1;
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end else begin
                        // result_exp = exp_a - exp_b + 16383 (using 17-bit signed arithmetic)
                        result_exp = {2'b00, exp_a} - {2'b00, exp_b} + 17'sd16383;

                        // SRT-2 Division Initialization
                        // SRT allows negative remainders, solving the mant_a < mant_b problem
                        divisor = mant_b;
                        divisor_half = mant_b >> 1;             // For SRT selection function

                        // Initialize all quotient digits to 0
                        for (srt_i = 0; srt_i <= 66; srt_i = srt_i + 1) begin
                            quotient_digits[srt_i] = 2'sd0;
                        end

                        // Pre-normalize: Handle quotient integer bit based on mant_a vs mant_b
                        // This ensures SRT starts with R < D and correct quotient range
                        if (mant_a >= mant_b) begin
                            quotient_digits[0] = 2'sd1;          // Q >= 1.0: set integer bit
                            remainder = {1'b0, mant_a - mant_b, 64'd0};  // R = mant_a - mant_b
                            div_count = 7'd1;                    // Start from bit 65
                            $display("[DIV_DEBUG] SRT-2 Init (mant_a >= mant_b): q[0]=1, R[127:64]=0x%016X",
                                     remainder[127:64]);
                        end else begin
                            quotient_digits[0] = 2'sd0;          // Q < 1.0: integer bit is 0
                            remainder = {1'b0, mant_a, 64'd0};   // R = mant_a (already < mant_b)
                            div_count = 7'd1;                    // Start from bit 65 (skip bit 66)
                            $display("[DIV_DEBUG] SRT-2 Init (mant_a < mant_b): q[0]=0, R[127:64]=0x%016X",
                                     remainder[127:64]);
                        end

                        state <= STATE_NORMALIZE;
                    end
                end

                STATE_NORMALIZE: begin
                    // SRT-2 Division Algorithm (67 iterations for 67-bit quotient)
                    // Quotient digits: {-1, 0, 1}
                    if (div_count < 7'd67) begin
                        if (div_count == 7'd0) begin
                            $display("[DIV_DEBUG] START SRT-2 Division: R[127:64]=0x%016X, D=0x%016X, D/2=0x%016X",
                                     remainder[127:64], divisor, divisor_half);
                        end

                        // SRT-2 Selection Function
                        // Compare current R with D/2 to select quotient digit
                        // Selection rules:
                        //   If R >= D/2: q = +1
                        //   If R < -D/2: q = -1
                        //   Otherwise: q = 0

                        // Select quotient digit BEFORE shifting
                        if (!remainder[128] && remainder[127:64] >= divisor_half) begin
                            // R is positive and >= D/2: select q = +1
                            quotient_digits[div_count] = 2'sd1;
                            if (div_count < 7'd5)
                                $display("[DIV_DEBUG] Iter %0d: R[127:64]=0x%016X >= D/2, q=+1",
                                         div_count, remainder[127:64]);
                        end else if (remainder[128] && (-remainder) > {1'b0, divisor_half, 64'd0}) begin
                            // R is negative and |R| > D/2: select q = -1
                            quotient_digits[div_count] = -2'sd1;
                            if (div_count < 7'd5)
                                $display("[DIV_DEBUG] Iter %0d: R[127:64]=0x%016X < -D/2, q=-1",
                                         div_count, remainder[127:64]);
                        end else begin
                            // |R| < D/2: select q = 0
                            quotient_digits[div_count] = 2'sd0;
                            if (div_count < 7'd5)
                                $display("[DIV_DEBUG] Iter %0d: |R| < D/2, q=0, R[127:64]=0x%016X",
                                         div_count, remainder[127:64]);
                        end

                        // Apply: R_next = 2*R - q*D
                        remainder = remainder << 1;  // 2*R
                        if (quotient_digits[div_count] == 2'sd1) begin
                            remainder = remainder - {1'b0, divisor, 64'd0};  // 2*R - D
                        end else if (quotient_digits[div_count] == -2'sd1) begin
                            remainder = remainder + {1'b0, divisor, 64'd0};  // 2*R + D
                        end
                        // If q=0, R_next = 2*R (already shifted)

                        div_count = div_count + 7'd1;
                    end else begin
                        // Division complete - Convert signed-digit quotient to binary
                        $display("[DIV_DEBUG] SRT-2 complete, converting signed-digit quotient to binary...");

                        // Convert: Start from MSB, accumulate quotient
                        // Q_binary = sum(q[i] * 2^(66-i)) for i=0 to 66
                        quotient = 67'd0;
                        for (srt_i = 0; srt_i <= 66; srt_i = srt_i + 1) begin
                            if (quotient_digits[srt_i] == 2'sd1) begin
                                // Add 2^(66-i) to quotient
                                quotient = quotient + (67'd1 << (66 - srt_i));
                            end else if (quotient_digits[srt_i] == -2'sd1) begin
                                // Subtract 2^(66-i) from quotient
                                quotient = quotient - (67'd1 << (66 - srt_i));
                            end
                            // If q[i] == 0, no change to quotient
                        end

                        result_mant = quotient;
                        $display("[DIV_DEBUG] Binary quotient=0x%017X, bit[66]=%b, bit[65]=%b",
                                 quotient, quotient[66], quotient[65]);

                        // Check if normalization is needed
                        // The quotient should have the integer bit at position 66
                        if (result_mant[66]) begin
                            // Already normalized
                            $display("[DIV_DEBUG] Already normalized at bit 66");
                        end else if (result_mant[65]) begin
                            // Need to shift left by 1
                            result_mant = result_mant << 1;
                            result_exp = result_exp - 17'sd1;
                            $display("[DIV_DEBUG] Shifted left by 1, new mant=0x%017X, exp=%0d", result_mant, result_exp);
                        end else begin
                            // Find leading 1 and shift
                            integer i;
                            reg [6:0] shift_amount;
                            shift_amount = 7'd0;

                            for (i = 64; i >= 0; i = i - 1) begin
                                if (result_mant[i] && shift_amount == 7'd0) begin
                                    shift_amount = 7'd66 - i[6:0];
                                end
                            end

                            if (shift_amount > 0 && shift_amount < 67) begin
                                result_mant = result_mant << shift_amount;
                                result_exp = result_exp - shift_amount;
                                $display("[DIV_DEBUG] Shifted left by %0d, new mant=0x%017X, exp=%0d", shift_amount, result_mant, result_exp);
                            end
                        end

                        // Check for overflow/underflow after normalization
                        // Check overflow FIRST to avoid misdetecting wrapped underflow
                        if (result_exp > 17'sd32766) begin
                            // Overflow
                            result <= {result_sign, 15'h7FFF, 1'b1, 63'd0}; // ±∞
                            flag_overflow <= 1'b1;
                            done <= 1'b1;
                            state <= STATE_IDLE;
                        end else if (result_exp < 17'sd1) begin
                            // Underflow
                            result <= {result_sign, 79'd0};
                            flag_underflow <= 1'b1;
                            done <= 1'b1;
                            state <= STATE_IDLE;
                        end else begin
                            state <= STATE_ROUND;
                        end
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
                        result_exp = result_exp + 17'sd1;

                        if (result_exp > 17'sd32766) begin
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
                    $display("[DIV_DEBUG] PACK: sign=%b, exp=0x%04X, mant[63:0]=0x%016X, mant[66:64]=0b%03b",
                             result_sign, result_exp[14:0], result_mant[63:0], result_mant[66:64]);
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
