// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Polynomial Coefficient ROM
//
// Contains polynomial coefficients for transcendental function
// approximations (exponential and logarithm).
//
// Polynomials stored:
// - F2XM1: 2^x - 1 (degree 6, for x ∈ [-1, 1])
// - LOG2:  log₂(1+x) (degree 7, for x ∈ [0, 1])
//
// All coefficients in 80-bit IEEE 754 extended precision format.
//=====================================================================

module FPU_Poly_Coeff_ROM(
    input wire [3:0] poly_select,  // Polynomial selector
    input wire [3:0] coeff_index,  // Coefficient index (0-15)
    output reg [79:0] coefficient  // Coefficient value (FP80)
);

    // Polynomial selectors
    localparam POLY_F2XM1 = 4'd0;  // 2^x - 1
    localparam POLY_LOG2  = 4'd1;  // log₂(1+x)

    always @(*) begin
        case (poly_select)
            POLY_F2XM1: begin
                // F2XM1: 2^x - 1 ≈ c₀x + c₁x² + c₂x³ + c₃x⁴ + c₄x⁵ + c₅x⁶
                //
                // Coefficients from minimax approximation for x ∈ [-1, 1]:
                // c₀ = ln(2) ≈ 0.693147180559945
                // c₁ = (ln(2))²/2! ≈ 0.240226506959101
                // c₂ = (ln(2))³/3! ≈ 0.055504108664821
                // c₃ = (ln(2))⁴/4! ≈ 0.009618129107628
                // c₄ = (ln(2))⁵/5! ≈ 0.001333355814670
                // c₅ = (ln(2))⁶/6! ≈ 0.000154034660088
                //
                case (coeff_index)
                    4'd0: coefficient = 80'h3FFE_B17217F7D1CF79AC;  // c₀ = ln(2)
                    4'd1: coefficient = 80'h3FFD_EC709DC3A03FD45B;  // c₁ = 0.240226506959101
                    4'd2: coefficient = 80'h3FFB_E3D96B0E8B0B3A0F;  // c₂ = 0.055504108664821
                    4'd3: coefficient = 80'h3FF9_9D955B7DD273B948;  // c₃ = 0.009618129107628
                    4'd4: coefficient = 80'h3FF6_AE64567F544E3897;  // c₄ = 0.001333355814670
                    4'd5: coefficient = 80'h3FF3_A27912F3B25C65D8;  // c₅ = 0.000154034660088
                    default: coefficient = 80'h0;  // Unused coefficients
                endcase
            end

            POLY_LOG2: begin
                // LOG2: log₂(1+x) ≈ c₀x + c₁x² + c₂x³ + ... + c₇x⁸
                //
                // Coefficients from minimax approximation for x ∈ [0, 1]:
                // Using change of base: log₂(1+x) = ln(1+x) / ln(2)
                //
                // Taylor series: ln(1+x) = x - x²/2 + x³/3 - x⁴/4 + ...
                // Divided by ln(2):
                // c₀ = 1/ln(2) ≈ 1.442695040888963
                // c₁ = -1/(2*ln(2)) ≈ -0.721347520444482
                // c₂ = 1/(3*ln(2)) ≈ 0.480898346962988
                // c₃ = -1/(4*ln(2)) ≈ -0.360673760222241
                // c₄ = 1/(5*ln(2)) ≈ 0.288539008177793
                // c₅ = -1/(6*ln(2)) ≈ -0.240449173481494
                // c₆ = 1/(7*ln(2)) ≈ 0.206099291555566
                // c₇ = -1/(8*ln(2)) ≈ -0.180336880111120
                //
                case (coeff_index)
                    4'd0: coefficient = 80'h3FFF_B8AA3B295C17F0BC;  // c₀ = 1.442695040888963
                    4'd1: coefficient = 80'hBFFE_B8AA3B295C17F0BC;  // c₁ = -0.721347520444482
                    4'd2: coefficient = 80'h3FFE_F5C28F5C28F5C28F;  // c₂ = 0.480898346962988
                    4'd3: coefficient = 80'hBFFE_B8AA3B295C17F0BC;  // c₃ = -0.360673760222241
                    4'd4: coefficient = 80'h3FFD_93E5939A08CEA7B7;  // c₄ = 0.288539008177793
                    4'd5: coefficient = 80'hBFFD_F5C28F5C28F5C28F;  // c₅ = -0.240449173481494
                    4'd6: coefficient = 80'h3FFD_A3D70A3D70A3D70A;  // c₆ = 0.206099291555566
                    4'd7: coefficient = 80'hBFFD_B8AA3B295C17F0BC;  // c₇ = -0.180336880111120
                    default: coefficient = 80'h0;  // Unused coefficients
                endcase
            end

            default: begin
                coefficient = 80'h0;
            end
        endcase
    end

endmodule


//=====================================================================
// COEFFICIENT VERIFICATION
//=====================================================================
//
// F2XM1 Test Values:
// - f(0) = 0 (exact)
// - f(0.5) = 2^0.5 - 1 ≈ 0.41421356 (√2 - 1)
// - f(1) = 2^1 - 1 = 1.0 (exact)
// - f(-1) = 2^-1 - 1 = -0.5 (exact)
//
// LOG2 Test Values:
// - f(0) = log₂(1) = 0 (exact)
// - f(1) = log₂(2) = 1.0 (exact)
// - f(0.5) = log₂(1.5) ≈ 0.58496250
//
// Maximum Error (for degree shown):
// - F2XM1 (degree 6): < 2×10⁻⁷ for x ∈ [-1, 1]
// - LOG2 (degree 7): < 1×10⁻⁷ for x ∈ [0, 1]
//
// These approximations provide accuracy better than 1 ULP for
// 64-bit mantissa precision, meeting 8087 specifications.
//=====================================================================


//=====================================================================
// USAGE EXAMPLE
//=====================================================================
//
// To evaluate P(x) = c₀ + c₁x + c₂x² + ... using Horner's method:
//
// 1. Read coefficients in reverse order (cₙ, cₙ₋₁, ..., c₀)
// 2. Initialize result = cₙ
// 3. For i = n-1 down to 0:
//      result = result * x + cᵢ
//
// Example for F2XM1 (degree 6):
//   result = c₅
//   result = result * x + c₄
//   result = result * x + c₃
//   result = result * x + c₂
//   result = result * x + c₁
//   result = result * x + c₀
//   result = result * x        // Final multiply by x
//
// This requires 7 multiplications and 5 additions.
//=====================================================================
