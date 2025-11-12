// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Range Reduction Module for Trigonometric Functions
//
// This module reduces arbitrary angles to the CORDIC convergence
// domain [-π/4, π/4] using quadrant mapping and trigonometric identities.
//
// CORDIC convergence domain: approximately ±99.88° (±1.743 radians)
// Target reduction range: [-π/4, π/4] for optimal accuracy
//
// Algorithm:
// 1. Reduce angle to [0, 2π) using modulo operation
// 2. Determine quadrant (I, II, III, IV)
// 3. Map to [-π/4, π/4] using symmetry
// 4. Return quadrant info for sign correction
//
// Trigonometric Identities Used:
// - sin(θ + π/2) = cos(θ)
// - sin(θ + π) = -sin(θ)
// - sin(θ + 3π/2) = -cos(θ)
// - cos(θ + π/2) = -sin(θ)
// - cos(θ + π) = -cos(θ)
// - cos(θ + 3π/2) = sin(θ)
//=====================================================================

module FPU_Range_Reduction(
    input wire clk,
    input wire reset,
    input wire enable,

    // Input angle (80-bit FP)
    input wire [79:0] angle_in,

    // Reduced angle output
    output reg [79:0] angle_out,

    // Quadrant and sign information
    output reg [1:0] quadrant,      // 0=I, 1=II, 2=III, 3=IV
    output reg       swap_sincos,   // 1 if sin and cos should be swapped
    output reg       negate_sin,    // 1 if sin result should be negated
    output reg       negate_cos,    // 1 if cos result should be negated

    output reg done,
    output reg error                // Error if angle is ±∞ or NaN
);

    //=================================================================
    // Constants (80-bit FP format)
    //=================================================================

    // Mathematical constants
    localparam FP80_PI        = 80'h4000_C90FDAA22168C235;  // π
    localparam FP80_PI_OVER_2 = 80'h3FFF_C90FDAA22168C235;  // π/2
    localparam FP80_PI_OVER_4 = 80'h3FFE_C90FDAA22168C235;  // π/4
    localparam FP80_3PI_OVER_2= 80'h4000_96CBE3F9990E91A8;  // 3π/2
    localparam FP80_2PI       = 80'h4001_C90FDAA22168C235;  // 2π

    localparam FP80_ZERO      = 80'h0000_0000000000000000;  // 0.0
    localparam FP80_ONE       = 80'h3FFF_8000000000000000;  // 1.0

    //=================================================================
    // State Machine
    //=================================================================

    localparam STATE_IDLE           = 3'd0;
    localparam STATE_CHECK_SPECIAL  = 3'd1;
    localparam STATE_REDUCE_2PI     = 3'd2;
    localparam STATE_DETERMINE_QUAD = 3'd3;
    localparam STATE_REDUCE_TO_PI4  = 3'd4;
    localparam STATE_DONE           = 3'd5;

    reg [2:0] state;

    //=================================================================
    // Internal signals
    //=================================================================

    // Extract components from input angle
    wire sign_in = angle_in[79];
    wire [14:0] exp_in = angle_in[78:64];
    wire [63:0] mant_in = angle_in[63:0];

    // Special value detection
    wire is_zero = (exp_in == 15'd0) && (mant_in == 64'd0);
    wire is_inf  = (exp_in == 15'h7FFF) && (mant_in[63] == 1'b1) && (mant_in[62:0] == 63'd0);
    wire is_nan  = (exp_in == 15'h7FFF) && ((mant_in[63] == 1'b0) || (mant_in[62:0] != 63'd0));

    // Working registers
    reg [79:0] angle_temp;
    reg [79:0] angle_abs;
    reg angle_negative;

    //=================================================================
    // FP Comparison Helper Function
    // Returns 1 if a >= b (both assumed positive normalized)
    //=================================================================
    function fp_gte;
        input [79:0] a;
        input [79:0] b;
        reg [14:0] exp_a, exp_b;
        reg [63:0] mant_a, mant_b;
        begin
            exp_a = a[78:64];
            exp_b = b[78:64];
            mant_a = a[63:0];
            mant_b = b[63:0];

            if (exp_a > exp_b)
                fp_gte = 1'b1;
            else if (exp_a < exp_b)
                fp_gte = 1'b0;
            else
                fp_gte = (mant_a >= mant_b);
        end
    endfunction

    //=================================================================
    // FP Subtraction Helper Function (a - b, both positive)
    // Simplified subtraction for normalized positive values
    //=================================================================
    function [79:0] fp_sub;
        input [79:0] a;
        input [79:0] b;
        reg [14:0] exp_a, exp_b;
        reg [63:0] mant_a, mant_b;
        reg [14:0] exp_diff;
        reg [63:0] mant_b_shifted;
        reg [63:0] result_mant;
        reg [14:0] result_exp;
        integer shift_amt;
        begin
            exp_a = a[78:64];
            exp_b = b[78:64];
            mant_a = a[63:0];
            mant_b = b[63:0];

            // Handle same exponent case (most common for our constants)
            if (exp_a == exp_b) begin
                result_exp = exp_a;
                result_mant = mant_a - mant_b;

                // Normalize result if needed (leading 1 might have shifted)
                if (result_mant[63] == 1'b0 && result_mant != 64'd0) begin
                    // Find leading 1 and normalize
                    shift_amt = 0;
                    while (result_mant[63] == 1'b0 && shift_amt < 63) begin
                        result_mant = result_mant << 1;
                        shift_amt = shift_amt + 1;
                    end
                    result_exp = result_exp - shift_amt;
                end

                fp_sub = {1'b0, result_exp, result_mant};
            end else if (exp_a > exp_b) begin
                // a > b: align mantissas
                exp_diff = exp_a - exp_b;
                if (exp_diff < 64)
                    mant_b_shifted = mant_b >> exp_diff;
                else
                    mant_b_shifted = 64'd0;

                result_mant = mant_a - mant_b_shifted;
                result_exp = exp_a;

                // Normalize if needed
                if (result_mant[63] == 1'b0 && result_mant != 64'd0) begin
                    shift_amt = 0;
                    while (result_mant[63] == 1'b0 && shift_amt < 63) begin
                        result_mant = result_mant << 1;
                        shift_amt = shift_amt + 1;
                    end
                    result_exp = result_exp - shift_amt;
                end

                fp_sub = {1'b0, result_exp, result_mant};
            end else begin
                // This shouldn't happen if a >= b
                fp_sub = FP80_ZERO;
            end
        end
    endfunction

    //=================================================================
    // Range Reduction State Machine
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
            angle_out <= FP80_ZERO;
            quadrant <= 2'd0;
            swap_sincos <= 1'b0;
            negate_sin <= 1'b0;
            negate_cos <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
            angle_temp <= FP80_ZERO;
            angle_abs <= FP80_ZERO;
            angle_negative <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    done <= 1'b0;
                    error <= 1'b0;
                    if (enable) begin
                        angle_temp <= angle_in;
                        angle_negative <= sign_in;
                        // Compute absolute value
                        angle_abs <= {1'b0, angle_in[78:0]};
                        state <= STATE_CHECK_SPECIAL;
                    end
                end

                STATE_CHECK_SPECIAL: begin
                    // Check for special values
                    if (is_zero) begin
                        // Angle is zero
                        angle_out <= FP80_ZERO;
                        quadrant <= 2'd0;
                        swap_sincos <= 1'b0;
                        negate_sin <= 1'b0;
                        negate_cos <= 1'b0;
                        state <= STATE_DONE;
                    end else if (is_inf || is_nan) begin
                        // Error: infinite or NaN angle
                        error <= 1'b1;
                        state <= STATE_DONE;
                    end else begin
                        // Normal angle, proceed to quadrant determination
                        state <= STATE_DETERMINE_QUAD;
                    end
                end

                STATE_REDUCE_2PI: begin
                    // For angles in [0, 2π), this is a no-op
                    // Future: implement modulo 2π for very large angles
                    state <= STATE_DETERMINE_QUAD;
                end

                STATE_DETERMINE_QUAD: begin
                    // Determine which octant and reduce to [-π/4, π/4]
                    // Handle angles in [0, 2π) range

                    // Octant mapping:
                    // [0, π/4): Quadrant I, no reduction needed
                    // [π/4, π/2): Quadrant I, reduce by subtracting from π/2, swap
                    // [π/2, 3π/4): Quadrant II, subtract π/2, swap
                    // [3π/4, π): Quadrant II, subtract from π
                    // [π, 5π/4): Quadrant III, subtract π
                    // [5π/4, 3π/2): Quadrant III, subtract from 3π/2, swap
                    // [3π/2, 7π/4): Quadrant IV, subtract 3π/2, swap
                    // [7π/4, 2π): Quadrant IV, subtract from 2π

                    if (!fp_gte(angle_abs, FP80_PI_OVER_4)) begin
                        // [0, π/4): Use angle as-is
                        angle_out <= angle_abs;
                        swap_sincos <= 1'b0;
                        negate_sin <= angle_negative;
                        negate_cos <= 1'b0;
                    end else if (!fp_gte(angle_abs, FP80_PI_OVER_2)) begin
                        // [π/4, π/2): angle' = π/2 - angle, swap sin/cos
                        angle_out <= fp_sub(FP80_PI_OVER_2, angle_abs);
                        swap_sincos <= 1'b1;
                        negate_sin <= angle_negative;
                        negate_cos <= 1'b0;
                    end else if (!fp_gte(angle_abs, FP80_PI)) begin
                        // [π/2, π): angle' = angle - π/2, swap, negate cos
                        angle_temp <= fp_sub(angle_abs, FP80_PI_OVER_2);

                        // Determine if closer to π/2 or π
                        if (!fp_gte(fp_sub(angle_abs, FP80_PI_OVER_2), FP80_PI_OVER_4)) begin
                            // [π/2, 3π/4): angle' = angle - π/2, swap
                            angle_out <= fp_sub(angle_abs, FP80_PI_OVER_2);
                            swap_sincos <= 1'b1;
                            negate_sin <= angle_negative;
                            negate_cos <= 1'b1;  // Quadrant II: cos is negative
                        end else begin
                            // [3π/4, π): angle' = π - angle
                            angle_out <= fp_sub(FP80_PI, angle_abs);
                            swap_sincos <= 1'b0;
                            negate_sin <= angle_negative;
                            negate_cos <= 1'b1;  // Quadrant II: cos is negative
                        end
                    end else if (!fp_gte(angle_abs, FP80_3PI_OVER_2)) begin
                        // [π, 3π/2): Quadrant III - subtract π
                        angle_temp <= fp_sub(angle_abs, FP80_PI);

                        if (!fp_gte(fp_sub(angle_abs, FP80_PI), FP80_PI_OVER_4)) begin
                            // [π, 5π/4): angle' = angle - π
                            angle_out <= fp_sub(angle_abs, FP80_PI);
                            swap_sincos <= 1'b0;
                            negate_sin <= ~angle_negative;  // Flip sign in QIII
                            negate_cos <= 1'b1;  // Quadrant III: cos is negative
                        end else begin
                            // [5π/4, 3π/2): angle' = 3π/2 - angle, swap
                            angle_out <= fp_sub(FP80_3PI_OVER_2, angle_abs);
                            swap_sincos <= 1'b1;
                            negate_sin <= ~angle_negative;  // Flip sign in QIII
                            negate_cos <= 1'b1;  // Quadrant III: cos is negative
                        end
                    end else if (!fp_gte(angle_abs, FP80_2PI)) begin
                        // [3π/2, 2π): Quadrant IV - subtract 3π/2
                        angle_temp <= fp_sub(angle_abs, FP80_3PI_OVER_2);

                        if (!fp_gte(fp_sub(angle_abs, FP80_3PI_OVER_2), FP80_PI_OVER_4)) begin
                            // [3π/2, 7π/4): angle' = angle - 3π/2, swap
                            angle_out <= fp_sub(angle_abs, FP80_3PI_OVER_2);
                            swap_sincos <= 1'b1;
                            negate_sin <= ~angle_negative;  // Flip sign in QIV
                            negate_cos <= 1'b0;  // Quadrant IV: cos is positive
                        end else begin
                            // [7π/4, 2π): angle' = 2π - angle
                            angle_out <= fp_sub(FP80_2PI, angle_abs);
                            swap_sincos <= 1'b0;
                            negate_sin <= ~angle_negative;  // Flip sign in QIV
                            negate_cos <= 1'b0;  // Quadrant IV: cos is positive
                        end
                    end else begin
                        // angle >= 2π: use modulo (simplified: just wrap once)
                        angle_temp <= fp_sub(angle_abs, FP80_2PI);
                        // Recursively reduce (in real implementation, loop)
                        // For now, assume angle < 4π
                        angle_out <= fp_sub(angle_abs, FP80_2PI);
                        swap_sincos <= 1'b0;
                        negate_sin <= angle_negative;
                        negate_cos <= 1'b0;
                    end

                    state <= STATE_DONE;
                end

                STATE_REDUCE_TO_PI4: begin
                    // This state is now handled in DETERMINE_QUAD
                    state <= STATE_DONE;
                end

                STATE_DONE: begin
                    done <= 1'b1;
                    if (~enable) begin
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule


//=====================================================================
// IMPLEMENTATION NOTES
//=====================================================================
//
// This is a SIMPLIFIED range reduction module. A complete implementation
// requires the following enhancements:
//
// 1. Payne-Hanek Reduction for Large Angles:
//    - Handle angles > 2π accurately
//    - Use extended precision π representation
//    - Iterative subtraction of π/2 multiples
//
// 2. Floating-Point Comparison:
//    - Compare angle with π/4, π/2, 3π/4, π boundaries
//    - Determine exact quadrant
//    - Handle denormals and edge cases
//
// 3. Floating-Point Subtraction:
//    - Subtract π/2, π, or 3π/2 as needed
//    - Use existing FPU_IEEE754_AddSub module
//    - Maintain precision during reduction
//
// 4. Quadrant Mapping Table:
//    - Quadrant I [0, π/2):        no swap, sin+, cos+
//    - Quadrant II [π/2, π):       swap,    sin+, cos-
//    - Quadrant III [π, 3π/2):     no swap, sin-, cos-
//    - Quadrant IV [3π/2, 2π):     swap,    sin-, cos+
//
// 5. Sign Handling:
//    - Negative angles: reduce |θ| then apply sign to sin
//    - Preserve sign through quadrant rotations
//
// For the initial Phase 4 implementation, this simplified version
// assumes input angles are already in a reasonable range (< 2π).
// This allows CORDIC testing to proceed while the full range
// reduction is developed in a later iteration.
//
// FUTURE ENHANCEMENT: Integrate with FPU_IEEE754_AddSub for proper
// FP subtraction and comparison operations.
//=====================================================================
