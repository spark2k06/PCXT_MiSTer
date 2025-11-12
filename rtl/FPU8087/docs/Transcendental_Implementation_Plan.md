# Intel 8087 Transcendental Functions Implementation Plan
## Phase 4: Complete Transcendental Function Integration

**Date:** 2025-11-09
**Status:** In Progress
**Dependencies:** Phase 3 Complete (Basic arithmetic and format conversion working)

---

## Overview

This document outlines the implementation strategy for adding transcendental functions to the Intel 8087 FPU implementation. The 8087 supports 9 transcendental instructions:

| Instruction | Function | Algorithm | Cycles (Real 8087) |
|-------------|----------|-----------|-------------------|
| FSIN | sin(ST(0)) | CORDIC rotation | ~200-300 |
| FCOS | cos(ST(0)) | CORDIC rotation | ~200-300 |
| FSINCOS | sin & cos(ST(0)) | CORDIC rotation | ~250-350 |
| FPTAN | tan(ST(0)) → ST(1)/ST(0) | CORDIC + divide | ~200-250 |
| FPATAN | atan(ST(1)/ST(0)) | CORDIC vectoring | ~200-300 |
| FSQRT | √ST(0) | Newton-Raphson or CORDIC | ~180-200 |
| F2XM1 | 2^ST(0) - 1 | Polynomial approximation | ~200-300 |
| FYL2X | ST(1) × log₂(ST(0)) | Polynomial approximation | ~250-350 |
| FYL2XP1 | ST(1) × log₂(ST(0)+1) | Polynomial approximation | ~250-350 |

---

## Architecture Design

### 1. Operation Code Extension

Extend FPU_ArithmeticUnit to support operations 12-20:

```verilog
localparam OP_SQRT     = 4'd12;  // Square root
localparam OP_SIN      = 4'd13;  // Sine
localparam OP_COS      = 4'd14;  // Cosine
localparam OP_SINCOS   = 4'd15;  // Sine and Cosine (returns both)
```

For operations requiring >4 bits, we'll use a second parameter or extended encoding.

### 2. Module Hierarchy

```
FPU_ArithmeticUnit (modified)
├── FPU_IEEE754_AddSub (existing)
├── FPU_IEEE754_Multiply (existing)
├── FPU_IEEE754_Divide (existing)
├── Conversion units (existing)
└── FPU_Transcendental (NEW)
    ├── FPU_CORDIC_Wrapper (NEW)
    │   ├── CORDIC_Engine (from CORDIC_Rotator.v)
    │   ├── Range_Reduction (NEW)
    │   └── Atan_Table_ROM (NEW)
    ├── FPU_Polynomial_Evaluator (NEW)
    └── FPU_SQRT_Newton (NEW - optional, CORDIC alternative)
```

### 3. CORDIC Algorithm Details

#### Rotation Mode (for SIN/COS)

Given angle θ, compute sin(θ) and cos(θ):

```
Initialize:
  x = K = 0.6072529350088812 (CORDIC gain)
  y = 0
  z = θ

For i = 0 to N-1:
  d = sign(z)
  x_new = x - d × (y >> i)
  y_new = y + d × (x >> i)
  z_new = z - d × atan(2^-i)

Result:
  cos(θ) ≈ x_final
  sin(θ) ≈ y_final
```

**Key Requirements:**
- Arctangent lookup table (64 entries for 64-bit precision)
- Barrel shifter for efficient (x >> i) and (y >> i)
- 40-50 iterations for full precision
- Range reduction: reduce θ to [-π/4, π/4]

#### Vectoring Mode (for ATAN)

Given x and y, compute atan(y/x):

```
Initialize:
  x = x_in
  y = y_in
  z = 0

For i = 0 to N-1:
  d = -sign(y)
  x_new = x - d × (y >> i)
  y_new = y + d × (x >> i)
  z_new = z - d × atan(2^-i)

Result:
  atan(y_in/x_in) ≈ z_final
  magnitude ≈ K × x_final
```

### 4. Polynomial Approximation for Exp/Log

#### F2XM1: 2^x - 1

Range reduction:
- Input x assumed in range [-1, +1] (8087 spec)
- Use minimax polynomial or Chebyshev approximation

**Polynomial (degree 6):**
```
2^x - 1 ≈ c₀×x + c₁×x² + c₂×x³ + c₃×x⁴ + c₄×x⁵ + c₅×x⁶

Coefficients (approximate):
c₀ = 0.693147180559945  (ln(2))
c₁ = 0.240226506959101
c₂ = 0.055504108664821
c₃ = 0.009618129107628
c₄ = 0.001333355814670
c₅ = 0.000154034660088
```

#### FYL2X: y × log₂(x)

Range reduction:
1. Extract x = 2^E × M where M ∈ [1, 2)
2. Compute log₂(x) = E + log₂(M)
3. Use polynomial for log₂(M)
4. Multiply result by y

**Polynomial for log₂(M) where M ∈ [1, 2):**
```
log₂(M) ≈ c₀×(M-1) + c₁×(M-1)² + c₂×(M-1)³ + ... + c₇×(M-1)⁸

Coefficients (approximate):
c₀ = 1.442695040888963  (1/ln(2))
c₁ = -0.721347520444482
c₂ = 0.480898346962988
c₃ = -0.360673760222241
```

### 5. Square Root

Two options:

**Option A: Newton-Raphson**
- Faster (10-15 iterations)
- Requires FP division
- Formula: x_{n+1} = (x_n + S/x_n) / 2

**Option B: CORDIC Hyperbolic Mode**
- Uses existing CORDIC infrastructure
- ~40-50 iterations
- No division required

**Decision:** Implement Option A (Newton-Raphson) as primary, Option B as future enhancement.

---

## Implementation Steps

### Step 1: Create Arctangent Lookup Table ROM

File: `FPU_Atan_Table.v`

```verilog
module FPU_Atan_Table(
    input wire [5:0] index,        // 0-63
    output reg [79:0] atan_value   // atan(2^-index)
);

    // 64-entry ROM with atan(2^-i) values in FP80 format
    always @(*) begin
        case (index)
            6'd0:  atan_value = 80'h3FFE_C90FDAA22168C235; // atan(1.0) = π/4
            6'd1:  atan_value = 80'h3FFD_ED63382B0DDA7B45; // atan(0.5)
            // ... (64 entries total)
        endcase
    end
endmodule
```

### Step 2: Create CORDIC Wrapper

File: `FPU_CORDIC_Wrapper.v`

This module:
1. Unpacks FP80 inputs to sign/exp/mantissa
2. Performs range reduction
3. Runs CORDIC iterations
4. Packs result back to FP80

Interfaces with existing `CORDIC_Engine` from CORDIC_Rotator.v.

### Step 3: Create Polynomial Evaluator

File: `FPU_Polynomial_Evaluator.v`

Uses Horner's method for efficient polynomial evaluation:
```
P(x) = c₀ + x(c₁ + x(c₂ + x(c₃ + ...)))
```

Requires:
- FP multiply (use existing FPU_IEEE754_Multiply)
- FP add (use existing FPU_IEEE754_AddSub)
- Coefficient ROM
- State machine for iterative computation

### Step 4: Create Newton-Raphson Square Root

File: `FPU_SQRT_Newton.v`

Implements:
```
x_{n+1} = (x_n + S/x_n) / 2
```

Uses existing multiply and divide units.

### Step 5: Create FPU_Transcendental Top Module

File: `FPU_Transcendental.v`

Multiplexes between:
- CORDIC wrapper (for sin/cos/tan/atan)
- Polynomial evaluator (for exp/log)
- Newton-Raphson (for sqrt)

### Step 6: Integrate into FPU_ArithmeticUnit

Modify `FPU_ArithmeticUnit.v`:
1. Add transcendental operation codes
2. Instantiate FPU_Transcendental
3. Route inputs/outputs
4. Extend multiplexer logic

### Step 7: Add Instructions to FPU_Core

Modify `FPU_Core.v`:
1. Add instruction opcodes (FSIN, FCOS, etc.)
2. Add state machine transitions for transcendentals
3. Handle stack operations (FSINCOS pushes, FPTAN pushes)

---

## Precision Requirements

### Target Accuracy

- **Basic arithmetic:** Correctly rounded (exact within 0.5 ULP)
- **Square root:** < 0.5 ULP error
- **Trigonometric (sin/cos/tan):** < 1 ULP error for inputs in range [-π/4, π/4]
- **Arctangent:** < 1 ULP error
- **Exponential/Log:** < 1 ULP error for most inputs, up to 2 ULP for worst cases

### CORDIC Iteration Count

For 64-bit mantissa precision:
- **Minimum:** 40 iterations (adequate for most cases)
- **Recommended:** 50 iterations (better precision)
- **Maximum:** 64 iterations (overkill, no practical benefit)

**Decision:** Use 50 iterations as default.

### Polynomial Degree

- **F2XM1:** Degree 6 polynomial (7 coefficients)
- **FYL2X:** Degree 7 polynomial (8 coefficients)

---

## Testing Strategy

### Unit Tests

1. **Atan Table:** Verify all 64 entries match reference values
2. **CORDIC Wrapper:** Test sin/cos for known angles (0, π/6, π/4, π/3, π/2)
3. **Polynomial Evaluator:** Test 2^x and log₂(x) with reference values
4. **Newton-Raphson:** Test sqrt for perfect squares and known values

### Integration Tests

1. **FPU_Transcendental:** Test all operations end-to-end
2. **FPU_ArithmeticUnit:** Verify operation multiplexing works
3. **FPU_Core:** Test instruction execution for all transcendentals

### Python Reference Emulator

Enhance `microsim.py`:
1. Add high-precision reference implementations
2. Compare Verilog results against Python math library
3. Generate test vectors with expected results

### Accuracy Validation

Compare against:
1. **Python math library:** math.sin(), math.cos(), math.sqrt(), etc.
2. **GNU MPFR:** Arbitrary precision library (for ULP error calculation)
3. **Real 8087:** If available, compare against hardware

### Performance Validation

Target cycle counts (approximate):
- FSQRT: ~200 cycles (15 Newton-Raphson iterations)
- FSIN/FCOS: ~300 cycles (50 CORDIC iterations + overhead)
- FSINCOS: ~350 cycles (compute both)
- FPATAN: ~300 cycles (50 CORDIC iterations)
- F2XM1: ~250 cycles (7 polynomial terms × ~35 cycles each)
- FYL2X: ~300 cycles (range reduction + polynomial + multiply)

---

## File Summary

### New Files to Create

| File | Lines (est) | Purpose |
|------|-------------|---------|
| `FPU_Atan_Table.v` | 150 | Arctangent lookup table ROM |
| `FPU_Range_Reduction.v` | 200 | Range reduction for trig functions |
| `FPU_CORDIC_Wrapper.v` | 400 | CORDIC integration with FP80 interface |
| `FPU_Polynomial_Evaluator.v` | 350 | Polynomial approximation engine |
| `FPU_Poly_Coeff_ROM.v` | 150 | Polynomial coefficient storage |
| `FPU_SQRT_Newton.v` | 250 | Newton-Raphson square root |
| `FPU_Transcendental.v` | 500 | Top-level transcendental module |
| `tb_transcendental.v` | 600 | Comprehensive testbench |
| `test_transcendental.py` | 400 | Python test vector generator |

**Total:** ~3000 lines of new Verilog + tests

### Files to Modify

| File | Changes |
|------|---------|
| `FPU_ArithmeticUnit.v` | Add transcendental operations (+150 lines) |
| `FPU_Core.v` | Add transcendental instructions (+200 lines) |
| `microsim.py` | Enhanced transcendental emulation (+200 lines) |

---

## Implementation Timeline

| Task | Duration | Dependencies |
|------|----------|--------------|
| 1. Atan table ROM | 2 hours | None |
| 2. Range reduction module | 4 hours | Atan table |
| 3. CORDIC wrapper | 8 hours | CORDIC_Rotator.v, Atan table |
| 4. Polynomial evaluator | 6 hours | Existing arithmetic units |
| 5. Newton-Raphson sqrt | 4 hours | Existing multiply/divide |
| 6. FPU_Transcendental top | 6 hours | All transcendental modules |
| 7. Integrate into ArithmeticUnit | 3 hours | FPU_Transcendental |
| 8. Add instructions to Core | 4 hours | Modified ArithmeticUnit |
| 9. Create testbenches | 8 hours | All modules |
| 10. Python reference emulator | 6 hours | None (parallel) |
| 11. Run tests and debug | 12 hours | All above |
| **Total** | **~63 hours** | **~8 days** |

---

## Risk Mitigation

### Risk 1: CORDIC Precision Insufficient

**Mitigation:**
- Test with 40, 50, 60, and 64 iterations
- Measure ULP error for each
- Select minimum iteration count that meets < 1 ULP requirement

### Risk 2: Polynomial Approximation Accuracy

**Mitigation:**
- Use Chebyshev or minimax polynomials (better than Taylor)
- Test across full input range
- Increase polynomial degree if needed

### Risk 3: Range Reduction Introduces Errors

**Mitigation:**
- Use exact range reduction where possible
- Test boundary cases (e.g., near ±π/2 for sin/cos)
- Use extended precision for intermediate calculations

### Risk 4: Resource Usage Too High

**Mitigation:**
- Reuse existing arithmetic units (multiply/divide) in polynomial evaluator
- Use iterative approach (not pipelined) to save area
- Share resources between different transcendental functions

---

## Success Criteria

✅ All 9 transcendental instructions execute correctly
✅ Accuracy < 1 ULP for 99% of test inputs
✅ All Python reference tests pass
✅ Icarus Verilog simulation completes without errors
✅ Cycle counts within 2× of real 8087 performance
✅ FPGA resource usage < 50% increase over Phase 3

---

## References

1. Intel 8087 Datasheet (1980)
2. "CORDIC Arithmetic" by Jack E. Volder (1959)
3. "Elementary Functions: Algorithms and Implementation" by Jean-Michel Muller
4. IEEE 754-1985 Standard
5. "Handbook of Floating-Point Arithmetic" by Muller et al.

---

**END OF PLAN**
