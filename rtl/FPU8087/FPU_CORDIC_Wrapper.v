// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// CORDIC Wrapper for FPU Transcendental Functions
//
// This module provides an 80-bit FP interface to the CORDIC engine
// for computing trigonometric functions (sin, cos, tan, atan).
//
// Modes:
// - ROTATION MODE: Compute sin/cos given angle
// - VECTORING MODE: Compute atan/magnitude given x,y coordinates
//
// The wrapper handles:
// - FP80 to fixed-point conversion
// - Range reduction (via FPU_Range_Reduction)
// - CORDIC iteration control
// - Fixed-point to FP80 conversion
// - Quadrant correction for sin/cos
//
// Precision: 50 iterations for ~64-bit mantissa accuracy
//=====================================================================

module FPU_CORDIC_Wrapper(
    input wire clk,
    input wire reset,

    // Control
    input wire enable,
    input wire mode,            // 0=rotation (sin/cos), 1=vectoring (atan)

    // Inputs (80-bit FP)
    input wire [79:0] angle_in,     // For rotation mode
    input wire [79:0] x_in,         // For vectoring mode
    input wire [79:0] y_in,         // For vectoring mode

    // Outputs (80-bit FP)
    output reg [79:0] sin_out,      // Rotation mode: sin result
    output reg [79:0] cos_out,      // Rotation mode: cos result
    output reg [79:0] atan_out,     // Vectoring mode: atan result
    output reg [79:0] magnitude_out,// Vectoring mode: magnitude result

    output reg done,
    output reg error
);

    //=================================================================
    // Parameters
    //=================================================================

    localparam NUM_ITERATIONS = 50;  // 50 iterations for high precision

    // CORDIC modes
    localparam MODE_ROTATION  = 1'b0;
    localparam MODE_VECTORING = 1'b1;

    // CORDIC gain K ≈ 1.646760258121 (accumulated from iterations)
    // To get direct sin/cos output, start with x = 1/K ≈ 0.6072529350088812
    // In FP80 format: sign=0, exp=0x3FFE, mant=0x9B74EDA81F6EB000
    localparam FP80_CORDIC_SCALE = 80'h3FFE_9B74EDA81F6EB000;  // 1/K for pre-scaling

    // Constants
    localparam FP80_ZERO = 80'h0000_0000000000000000;
    localparam FP80_ONE  = 80'h3FFF_8000000000000000;

    //=================================================================
    // State Machine
    //=================================================================

    localparam STATE_IDLE          = 4'd0;
    localparam STATE_RANGE_REDUCE  = 4'd1;
    localparam STATE_CONVERT_INPUT = 4'd2;
    localparam STATE_CORDIC_INIT   = 4'd3;
    localparam STATE_CORDIC_ITER   = 4'd4;
    localparam STATE_CONVERT_OUTPUT= 4'd5;
    localparam STATE_QUAD_CORRECT  = 4'd6;
    localparam STATE_DONE          = 4'd7;

    reg [3:0] state;
    reg [5:0] iteration_count;

    //=================================================================
    // Range Reduction (for rotation mode)
    //=================================================================

    reg range_reduce_enable;
    wire [79:0] angle_reduced;
    wire [1:0] quadrant;
    wire swap_sincos, negate_sin, negate_cos;
    wire range_reduce_done, range_reduce_error;

    FPU_Range_Reduction range_reducer (
        .clk(clk),
        .reset(reset),
        .enable(range_reduce_enable),
        .angle_in(angle_in),
        .angle_out(angle_reduced),
        .quadrant(quadrant),
        .swap_sincos(swap_sincos),
        .negate_sin(negate_sin),
        .negate_cos(negate_cos),
        .done(range_reduce_done),
        .error(range_reduce_error)
    );

    //=================================================================
    // Arctangent Table
    //=================================================================

    wire [5:0] atan_index;
    wire [79:0] atan_value;

    // Connect iteration_count directly to atan table for combinational lookup
    assign atan_index = iteration_count;

    FPU_Atan_Table atan_table (
        .index(atan_index),
        .atan_value(atan_value)
    );

    //=================================================================
    // CORDIC Working Registers (64-bit fixed-point)
    //
    // Format: Q2.62 (2 integer bits, 62 fractional bits)
    // Range: [-2, +2) with resolution of 2^-62
    //=================================================================

    reg signed [63:0] x_cordic, y_cordic, z_cordic;
    reg signed [63:0] x_next, y_next, z_next;
    reg signed [63:0] x_shifted, y_shifted;
    reg signed [63:0] atan_fixed;

    //=================================================================
    // Mode and quadrant registers
    //=================================================================

    reg cordic_mode;
    reg [1:0] result_quadrant;
    reg result_swap, result_negate_sin, result_negate_cos;

    //=================================================================
    // FP80 to Fixed-Point Conversion
    //
    // Simplified conversion for demonstration.
    // Real implementation needs full IEEE 754 unpacking.
    //=================================================================

    function signed [63:0] fp80_to_fixed;
        input [79:0] fp80_val;
        reg sign;
        reg [14:0] exponent;
        reg [63:0] mantissa;
        reg signed [63:0] result;
        integer shift_amount;
        begin
            sign = fp80_val[79];
            exponent = fp80_val[78:64];
            mantissa = fp80_val[63:0];

            if (exponent == 15'd0) begin
                // Zero or denormal
                result = 64'd0;
            end else begin
                // Normalized value
                // FP80: value = mantissa * 2^(exp - bias - 63) [mantissa has binary point after bit 63]
                // Q2.62: value_Q = value * 2^62
                // So: value_Q = mantissa * 2^(exp - bias - 63 + 62) = mantissa * 2^(exp - bias - 1)
                shift_amount = exponent - 16384;  // exponent - bias - 1, where bias=16383

                if (shift_amount >= 0) begin
                    result = mantissa << shift_amount;
                end else begin
                    result = mantissa >>> (-shift_amount);
                end

                if (sign) result = -result;
            end

            fp80_to_fixed = result;
        end
    endfunction

    //=================================================================
    // Fixed-Point to FP80 Conversion
    //
    // Converts Q2.62 fixed-point to FP80
    //=================================================================

    function [79:0] fixed_to_fp80;
        input signed [63:0] fixed_val;
        reg sign;
        reg [14:0] exponent;
        reg [63:0] mantissa;
        reg [63:0] abs_val;
        integer leading_zeros;
        integer i;
        begin
            if (fixed_val == 64'd0) begin
                fixed_to_fp80 = FP80_ZERO;
            end else begin
                sign = fixed_val[63];
                abs_val = sign ? -fixed_val : fixed_val;

                // Find leading one position (priority encoder)
                leading_zeros = 64;
                for (i = 63; i >= 0; i = i - 1) begin
                    if (abs_val[i] == 1'b1) begin
                        leading_zeros = 63 - i;
                        i = -1;  // Break loop
                    end
                end

                // Normalize mantissa
                mantissa = abs_val << leading_zeros;

                // Compute exponent
                // Q2.62 value represents: fixed_val / 2^62
                // FP80 mantissa has binary point after bit 63
                // FP80 value = mantissa * 2^(exp - bias - 63)
                // We want: mantissa * 2^(exp - bias - 63) = abs_val * 2^-62
                // After normalization: mantissa[63]=1, mantissa = abs_val << leading_zeros
                // So: (abs_val << leading_zeros) * 2^(exp - 16383 - 63) = abs_val * 2^-62
                // => exp - 16446 = -62 - leading_zeros
                // => exp = 16384 - leading_zeros
                exponent = 16384 - leading_zeros;

                fixed_to_fp80 = {sign, exponent, mantissa};
            end
        end
    endfunction

    //=================================================================
    // Main State Machine
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
            done <= 1'b0;
            error <= 1'b0;
            sin_out <= FP80_ZERO;
            cos_out <= FP80_ZERO;
            atan_out <= FP80_ZERO;
            magnitude_out <= FP80_ZERO;
            range_reduce_enable <= 1'b0;
            iteration_count <= 6'd0;
            cordic_mode <= MODE_ROTATION;
            x_cordic <= 64'd0;
            y_cordic <= 64'd0;
            z_cordic <= 64'd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    done <= 1'b0;
                    error <= 1'b0;
                    if (enable) begin
                        cordic_mode <= mode;
                        if (mode == MODE_ROTATION) begin
                            // Rotation mode: reduce angle first
                            range_reduce_enable <= 1'b1;
                            state <= STATE_RANGE_REDUCE;
                        end else begin
                            // Vectoring mode: skip range reduction
                            state <= STATE_CONVERT_INPUT;
                        end
                    end
                end

                STATE_RANGE_REDUCE: begin
                    range_reduce_enable <= 1'b0;
                    if (range_reduce_done) begin
                        if (range_reduce_error) begin
                            error <= 1'b1;
                            state <= STATE_DONE;
                        end else begin
                            // Save quadrant info for later correction
                            result_quadrant <= quadrant;
                            result_swap <= swap_sincos;
                            result_negate_sin <= negate_sin;
                            result_negate_cos <= negate_cos;
                            state <= STATE_CONVERT_INPUT;
                        end
                    end
                end

                STATE_CONVERT_INPUT: begin
                    if (cordic_mode == MODE_ROTATION) begin
                        // Rotation mode: x = 1/K, y = 0, z = angle
                        // Pre-scaling by 1/K gives direct cos(θ), sin(θ) output
                        x_cordic <= fp80_to_fixed(FP80_CORDIC_SCALE);
                        y_cordic <= 64'd0;
                        z_cordic <= fp80_to_fixed(angle_reduced);
                    end else begin
                        // Vectoring mode: x = x_in, y = y_in, z = 0
                        x_cordic <= fp80_to_fixed(x_in);
                        y_cordic <= fp80_to_fixed(y_in);
                        z_cordic <= 64'd0;
                    end
                    state <= STATE_CORDIC_INIT;
                end

                STATE_CORDIC_INIT: begin
                    iteration_count <= 6'd0;
                    state <= STATE_CORDIC_ITER;
                end

                STATE_CORDIC_ITER: begin
                    // Perform one CORDIC iteration
                    // Shift amounts
                    x_shifted = x_cordic >>> iteration_count;  // Arithmetic right shift
                    y_shifted = y_cordic >>> iteration_count;

                    // Convert atan table value to fixed-point (atan_index is wired to iteration_count)
                    atan_fixed = fp80_to_fixed(atan_value);

                    // CORDIC micro-rotation
                    if (cordic_mode == MODE_ROTATION) begin
                        // Rotation mode: rotate by z
                        if (z_cordic >= 0) begin
                            x_next = x_cordic - y_shifted;
                            y_next = y_cordic + x_shifted;
                            z_next = z_cordic - atan_fixed;
                        end else begin
                            x_next = x_cordic + y_shifted;
                            y_next = y_cordic - x_shifted;
                            z_next = z_cordic + atan_fixed;
                        end
                    end else begin
                        // Vectoring mode: rotate to zero y
                        if (y_cordic < 0) begin
                            x_next = x_cordic - y_shifted;
                            y_next = y_cordic + x_shifted;
                            z_next = z_cordic - atan_fixed;
                        end else begin
                            x_next = x_cordic + y_shifted;
                            y_next = y_cordic - x_shifted;
                            z_next = z_cordic + atan_fixed;
                        end
                    end

                    // Update registers
                    x_cordic <= x_next;
                    y_cordic <= y_next;
                    z_cordic <= z_next;

                    // Check iteration count
                    if (iteration_count >= NUM_ITERATIONS - 1) begin
                        state <= STATE_CONVERT_OUTPUT;
                    end else begin
                        iteration_count <= iteration_count + 1;
                    end
                end

                STATE_CONVERT_OUTPUT: begin
                    if (cordic_mode == MODE_ROTATION) begin
                        // Rotation mode: x ≈ cos(θ), y ≈ sin(θ)
                        cos_out <= fixed_to_fp80(x_cordic);
                        sin_out <= fixed_to_fp80(y_cordic);
                        state <= STATE_QUAD_CORRECT;
                    end else begin
                        // Vectoring mode: z ≈ atan(y/x), x*K ≈ magnitude
                        atan_out <= fixed_to_fp80(z_cordic);
                        magnitude_out <= fixed_to_fp80(x_cordic);
                        state <= STATE_DONE;
                    end
                end

                STATE_QUAD_CORRECT: begin
                    // Apply quadrant corrections
                    if (result_negate_sin) begin
                        sin_out[79] <= ~sin_out[79];  // Flip sign bit
                    end
                    if (result_negate_cos) begin
                        cos_out[79] <= ~cos_out[79];  // Flip sign bit
                    end
                    if (result_swap) begin
                        // Swap sin and cos
                        sin_out <= cos_out;
                        cos_out <= sin_out;
                    end
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
// This is a FUNCTIONAL CORDIC wrapper suitable for initial testing.
// Several simplifications have been made:
//
// 1. FP80 Conversion Functions:
//    - fp80_to_fixed: Simplified conversion, may have precision loss
//    - fixed_to_fp80: Incomplete normalization and rounding
//    - ENHANCEMENT: Use proper IEEE 754 pack/unpack modules
//
// 2. CORDIC Iterations:
//    - Fixed 50 iterations (good for most cases)
//    - ENHANCEMENT: Add early termination when z ≈ 0 (rotation)
//      or when y ≈ 0 (vectoring)
//
// 3. Quadrant Correction:
//    - Simple sign flipping for negate operations
//    - ENHANCEMENT: Use proper FP negate with rounding
//
// 4. Error Handling:
//    - Basic error propagation from range reduction
//    - ENHANCEMENT: Add overflow/underflow detection in conversions
//
// 5. Performance:
//    - Current: ~55 cycles (50 iterations + overhead)
//    - ENHANCEMENT: Pipeline CORDIC iterations for higher throughput
//
// TESTING STRATEGY:
// 1. Test with known angles: 0, π/6, π/4, π/3, π/2
// 2. Verify sin²(θ) + cos²(θ) = 1 identity
// 3. Compare against Python math.sin(), math.cos()
// 4. Measure ULP error across input range
//
// FUTURE ENHANCEMENTS:
// - Integrate with proper FP pack/unpack modules
// - Add exception flag outputs (invalid, overflow, underflow)
// - Optimize conversion functions for speed and accuracy
// - Add configurable iteration count for speed/accuracy trade-off
//=====================================================================
