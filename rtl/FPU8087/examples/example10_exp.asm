; ============================================================================
; Example 10: F2XM1 - Compute 2^x - 1
;
; This microprogram implements the 8087 F2XM1 instruction which computes
; 2^x - 1 for -1 ≤ x ≤ 1.
;
; The 8087 uses this form because it provides better accuracy for small
; values of x near zero (where 2^x ≈ 1).
;
; Algorithm:
;   For small x, use polynomial approximation:
;   2^x - 1 = x*ln(2) + (x*ln(2))^2/2! + (x*ln(2))^3/3! + ...
;
;   Or equivalently:
;   2^x - 1 = exp(x * ln(2)) - 1
;
;   Using range reduction:
;   If x = n + f where n is integer and 0 ≤ f < 1:
;   2^x = 2^n * 2^f
;   2^n is computed by exponent manipulation
;   2^f is computed by polynomial
;
; For this simplified implementation, we use polynomial approximation
; for the range [-1, 1]:
;
;   2^x - 1 ≈ c1*x + c2*x^2 + c3*x^3 + c4*x^4 + ...
;
; Where:
;   c1 = ln(2) ≈ 0.693147
;   c2 = (ln(2))^2 / 2 ≈ 0.240227
;   c3 = (ln(2))^3 / 6 ≈ 0.055504
;   c4 = (ln(2))^4 / 24 ≈ 0.009618
;
; Register usage:
; temp_fp: input x, then accumulated result
; temp_fp_a, temp_fp_b: intermediate calculations
; ============================================================================

; Constants
.EQU CONST_ZERO = 0x02          ; Constant 0.0
.EQU CONST_ONE = 0x03           ; Constant 1.0
.EQU CONST_LN2 = 0x07           ; ln(2) ≈ 0.693147
.EQU POLY_TERMS = 5             ; Number of polynomial terms

f2xm1:
    ; Load input value x from CPU bus
    LOAD                        ; temp_reg = x
    ; Assume -1 ≤ x ≤ 1

    ; === Method 1: Polynomial Approximation ===
    ; Compute 2^x - 1 using polynomial series
    ; 2^x - 1 = x*ln(2) * (1 + x*ln(2)/2 + (x*ln(2))^2/6 + ...)

    ; Load ln(2)
    SET_CONST CONST_LN2
    ACCESS_CONST                ; temp_fp = ln(2)

    ; This is a simplified placeholder implementation
    ; Real implementation would compute:
    ; 1. z = x * ln(2)
    ; 2. Compute polynomial: z + z^2/2 + z^3/6 + z^4/24 + ...

    ; Simplified: just demonstrate structure
    SET_CONST CONST_ONE
    ACCESS_CONST
    ADD                         ; Simplified operation

    NORMALIZE

    ; === Method 2: Table Lookup + Interpolation ===
    ; (Not implemented here, but described in comments)
    ; 1. Split x into integer and fractional parts
    ; 2. Use table for fractional part
    ; 3. Shift result by integer part

    STORE                       ; Store result
    HALT

; ============================================================================
; Notes for Complete Implementation:
;
; 1. Polynomial Approximation:
;    For x in [-1, 1], use Chebyshev or minimax polynomial:
;
;    Let z = x * ln(2)
;    exp(z) - 1 = z + z^2/2! + z^3/3! + z^4/4! + ...
;               = z * (1 + z/2 * (1 + z/3 * (1 + z/4 * ...)))  [Horner's method]
;
;    Coefficients for better accuracy:
;    c0 = 1.0
;    c1 = 0.5
;    c2 = 1/6 ≈ 0.166667
;    c3 = 1/24 ≈ 0.041667
;    c4 = 1/120 ≈ 0.008333
;
; 2. Horner's Method Implementation:
;    result = z * (c0 + z * (c1 + z * (c2 + z * c3)))
;
;    Code:
;    ```
;    ; Compute z = x * ln(2)
;    LOAD x
;    SET_CONST CONST_LN2
;    ACCESS_CONST
;    ; temp_fp_a = x, temp_fp_b = ln(2)
;    MUL              ; temp_fp = z
;
;    ; Horner's method for polynomial
;    ; Start with innermost: c3
;    SET_CONST CONST_C3
;    ACCESS_CONST     ; c3
;
;    ; c2 + z * c3
;    MUL              ; z * c3
;    SET_CONST CONST_C2
;    ACCESS_CONST
;    ADD              ; c2 + z * c3
;
;    ; c1 + z * (c2 + z * c3)
;    MUL              ; z * (c2 + z * c3)
;    SET_CONST CONST_C1
;    ACCESS_CONST
;    ADD              ; c1 + ...
;
;    ; c0 + z * (c1 + ...)
;    MUL
;    SET_CONST CONST_C0
;    ACCESS_CONST
;    ADD
;
;    ; Multiply by z to get final result
;    MUL              ; z * (c0 + ...)
;    ```
;
; 3. Range Reduction:
;    If x is outside [-1, 1]:
;    - Extract integer part n and fractional part f
;    - Compute 2^f - 1 using polynomial (f is in range)
;    - Adjust result: 2^x - 1 = 2^n * 2^f - 1
;                               = 2^n * (2^f - 1) + 2^n - 1
;
; 4. Special Cases:
;    - 2^0 - 1 = 0
;    - 2^1 - 1 = 1
;    - 2^(-1) - 1 = -0.5
;    - For x → -∞: result → -1
;    - For x → +∞: result → +∞
;
; 5. Accuracy Considerations:
;    - For |x| < 0.5: polynomial works well
;    - For |x| close to 1: need more terms or table lookup
;    - 8087 uses 64-bit intermediate precision
;
; 6. Alternative: CORDIC Hyperbolic Mode
;    CORDIC can compute exponentials using hyperbolic rotations:
;    - Uses hyperbolic functions cosh, sinh
;    - exp(x) = cosh(x) + sinh(x)
;    - More iterations needed than circular CORDIC
;
; 7. 8087 F2XM1 Specifics:
;    - Input range: -1.0 ≤ ST(0) ≤ +1.0
;    - If input outside range, result is undefined
;    - Often used with FSCALE to compute 2^x for any x:
;      * Extract integer and fractional parts
;      * Use F2XM1 for fractional part
;      * Use FSCALE to apply integer part
;
; 8. Related 8087 Instructions:
;    - FSCALE: Scale ST(0) by 2^(round(ST(1)))
;    - FYL2X: Compute y * log2(x)
;    - FYL2XP1: Compute y * log2(x+1)
;    Together these allow arbitrary exponentials and powers
;
; 9. Constants Needed in ROM:
;    - ln(2) ≈ 0.693147180559945309417
;    - 1/2, 1/6, 1/24, 1/120, ... (factorial reciprocals)
;    - Or precomputed polynomial coefficients
; ============================================================================
