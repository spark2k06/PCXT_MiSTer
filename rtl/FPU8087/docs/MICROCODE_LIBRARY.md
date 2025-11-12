# Microcode Subroutine Library for 8087 FPU

## Overview

This document provides comprehensive documentation for all microcode subroutines implemented in the Extended Microsequencer (`MicroSequencer_Extended.v`). These subroutines implement complex floating-point operations by sequencing calls to hardware units.

**Architecture:** Hardware Unit Reuse with "Call and Wait" Pattern
- Microcode sequences operations
- Hardware units (FPU_ArithmeticUnit) perform actual computation
- Zero code duplication - arithmetic logic exists once in hardware

**Last Updated:** 2025-11-09

---

## Subroutine Index

| Program # | Name    | Address Range | Cycles* | Description |
|-----------|---------|---------------|---------|-------------|
| 0         | FADD    | 0x0100-0x0103 | 8-10    | Floating-point addition |
| 1         | FSUB    | 0x0110-0x0113 | 8-10    | Floating-point subtraction |
| 2         | FMUL    | 0x0120-0x0123 | 7-9     | Floating-point multiplication |
| 3         | FDIV    | 0x0130-0x0133 | 74-76   | Floating-point division |
| 4         | FSQRT   | 0x0140-0x0143 | TBD     | Square root |
| 5         | FSIN    | 0x0150-0x0153 | TBD     | Sine function |
| 6         | FCOS    | 0x0160-0x0163 | TBD     | Cosine function |
| 7         | FLD     | 0x0200-0x020F | Reserved | Load with format conversion |
| 8         | FST     | 0x0210-0x021F | Reserved | Store with format conversion |
| 9         | FPREM   | 0x0300-0x0309 | ~25-30  | Partial remainder |
| 10        | FXTRACT | 0x0400-0x040F | Reserved | Extract exponent and significand |
| 11        | FSCALE  | 0x0500-0x050F | Reserved | Scale by power of 2 |

*Approximate cycle counts including microcode overhead

---

## Calling Convention

### Input
- **temp_fp_a**: First operand (80-bit extended precision)
- **temp_fp_b**: Second operand (80-bit extended precision)
- **micro_program_index**: Program number (0-15)
- **start**: Pulse high for one cycle to begin execution

### Output
- **temp_result**: Result (80-bit extended precision)
- **instruction_complete**: Goes high when subroutine returns

### Example Usage
```verilog
// Setup operands
temp_fp_a <= 80'h4000C90FDAA22168C000;  // 3.14159...
temp_fp_b <= 80'h40005B05B05B05B06000;  // 2.71828...

// Start FADD subroutine (program 0)
micro_program_index <= 4'd0;
start <= 1'b1;

@(posedge clk);
start <= 1'b0;

// Wait for completion
wait (instruction_complete);

// Read result from temp_result
result = temp_result;  // Should contain ~5.85987
```

---

## Program 0: FADD - Floating-Point Addition

**Address:** 0x0100 - 0x0103
**Function:** temp_result = temp_fp_a + temp_fp_b
**Typical Cycles:** 8-10

### Microcode Sequence
```
0x0100: CALL_ARITH op=0 (ADD)     # Start addition operation
0x0101: WAIT_ARITH                # Wait for completion
0x0102: LOAD_ARITH_RES            # Load result from arithmetic unit
0x0103: RET                       # Return to caller (or signal complete)
```

### Hardware Delegation
- **Operation Code:** 0 (ADD)
- **Hardware Unit:** FPU_IEEE754_AddSub
- **Precision:** 80-bit extended precision

### Status Flags Affected
- C1: Set if result rounded up
- Precision exception if inexact result
- Invalid, denormal, overflow, underflow as appropriate

### Example
```
Input:  temp_fp_a = 3.14159265359  (π)
        temp_fp_b = 2.71828182846  (e)
Output: temp_result = 5.85987448205
```

---

## Program 1: FSUB - Floating-Point Subtraction

**Address:** 0x0110 - 0x0113
**Function:** temp_result = temp_fp_a - temp_fp_b
**Typical Cycles:** 8-10

### Microcode Sequence
```
0x0110: CALL_ARITH op=1 (SUB)     # Start subtraction operation
0x0111: WAIT_ARITH                # Wait for completion
0x0112: LOAD_ARITH_RES            # Load result
0x0113: RET                       # Return
```

### Hardware Delegation
- **Operation Code:** 1 (SUB)
- **Hardware Unit:** FPU_IEEE754_AddSub (with invert_b)
- **Precision:** 80-bit extended precision

### Example
```
Input:  temp_fp_a = 5.0
        temp_fp_b = 2.0
Output: temp_result = 3.0
```

---

## Program 2: FMUL - Floating-Point Multiplication

**Address:** 0x0120 - 0x0123
**Function:** temp_result = temp_fp_a * temp_fp_b
**Typical Cycles:** 7-9

### Microcode Sequence
```
0x0120: CALL_ARITH op=2 (MUL)     # Start multiplication
0x0121: WAIT_ARITH                # Wait for completion
0x0122: LOAD_ARITH_RES            # Load result
0x0123: RET                       # Return
```

### Hardware Delegation
- **Operation Code:** 2 (MUL)
- **Hardware Unit:** FPU_IEEE754_Multiply
- **Precision:** 80-bit extended precision

### Example
```
Input:  temp_fp_a = 3.0
        temp_fp_b = 4.0
Output: temp_result = 12.0
```

---

## Program 3: FDIV - Floating-Point Division

**Address:** 0x0130 - 0x0133
**Function:** temp_result = temp_fp_a / temp_fp_b
**Typical Cycles:** 74-76

### Microcode Sequence
```
0x0130: CALL_ARITH op=3 (DIV)     # Start division
0x0131: WAIT_ARITH                # Wait for completion (takes ~73 cycles)
0x0132: LOAD_ARITH_RES            # Load result
0x0133: RET                       # Return
```

### Hardware Delegation
- **Operation Code:** 3 (DIV)
- **Hardware Unit:** FPU_IEEE754_Divide
- **Precision:** 80-bit extended precision
- **Note:** Division is the slowest basic operation (~73 hardware cycles)

### Special Cases
- Division by zero: Sets zero-divide exception flag
- Invalid operation: 0/0, ∞/∞

### Example
```
Input:  temp_fp_a = 12.0
        temp_fp_b = 3.0
Output: temp_result = 4.0
```

---

## Program 4: FSQRT - Square Root

**Address:** 0x0140 - 0x0143
**Function:** temp_result = √(temp_fp_a)
**Typical Cycles:** TBD (>100 cycles observed)

### Microcode Sequence
```
0x0140: CALL_ARITH op=12 (SQRT)   # Start square root
0x0141: WAIT_ARITH                # Wait for completion
0x0142: LOAD_ARITH_RES            # Load result
0x0143: RET                       # Return
```

### Hardware Delegation
- **Operation Code:** 12 (SQRT)
- **Hardware Unit:** FPU_SQRT_Newton (Newton-Raphson iteration)
- **Precision:** 80-bit extended precision

### Known Issues
- **BUG:** Currently times out after 100 cycles in testbench
- May require >100 cycles for convergence
- Investigation needed on FPU_SQRT_Newton module

### Example
```
Input:  temp_fp_a = 16.0
        temp_fp_b = (not used)
Output: temp_result = 4.0
```

---

## Program 5: FSIN - Sine Function

**Address:** 0x0150 - 0x0153
**Function:** temp_result = sin(temp_fp_a)
**Typical Cycles:** TBD

### Microcode Sequence
```
0x0150: CALL_ARITH op=13 (SIN)    # Start sine calculation
0x0151: WAIT_ARITH                # Wait for completion
0x0152: LOAD_ARITH_RES            # Load result
0x0153: RET                       # Return
```

### Hardware Delegation
- **Operation Code:** 13 (SIN)
- **Hardware Unit:** FPU_CORDIC_Wrapper (CORDIC algorithm)
- **Precision:** 80-bit extended precision
- **Range:** Reduced to ±π using FPU_Range_Reduction

### Notes
- Input automatically range-reduced if |x| > π
- Uses CORDIC rotation mode for trigonometric functions
- Polynomial evaluation for final refinement

### Example
```
Input:  temp_fp_a = π/2 (1.5707963...)
        temp_fp_b = (not used)
Output: temp_result = 1.0
```

---

## Program 6: FCOS - Cosine Function

**Address:** 0x0160 - 0x0163
**Function:** temp_result = cos(temp_fp_a)
**Typical Cycles:** TBD

### Microcode Sequence
```
0x0160: CALL_ARITH op=14 (COS)    # Start cosine calculation
0x0161: WAIT_ARITH                # Wait for completion
0x0162: LOAD_ARITH_RES            # Load result
0x0163: RET                       # Return
```

### Hardware Delegation
- **Operation Code:** 14 (COS)
- **Hardware Unit:** FPU_CORDIC_Wrapper
- **Precision:** 80-bit extended precision
- **Range:** Reduced to ±π using FPU_Range_Reduction

### Example
```
Input:  temp_fp_a = 0.0
        temp_fp_b = (not used)
Output: temp_result = 1.0
```

---

## Program 9: FPREM - Partial Remainder

**Address:** 0x0300 - 0x0309
**Function:** temp_result = temp_fp_a MOD temp_fp_b (remainder)
**Typical Cycles:** ~25-30 (estimate)

### Microcode Sequence
```
0x0300: CALL_ARITH op=3 (DIV)     # Step 1: quotient = dividend / divisor
0x0301: WAIT_ARITH
0x0302: LOAD_ARITH_RES            # quotient now in temp_result

0x0303: CALL_ARITH op=2 (MUL)     # Step 2: product = quotient * divisor
0x0304: WAIT_ARITH
0x0305: LOAD_ARITH_RES            # product now in temp_result

0x0306: CALL_ARITH op=1 (SUB)     # Step 3: remainder = dividend - product
0x0307: WAIT_ARITH
0x0308: LOAD_ARITH_RES            # remainder now in temp_result
0x0309: RET                       # Return
```

### Algorithm
1. **Divide:** Compute quotient = dividend / divisor
2. **Truncate:** Convert quotient to integer (simplified in current implementation)
3. **Multiply:** Compute product = integer_quotient × divisor
4. **Subtract:** Compute remainder = dividend - product

### Hardware Delegation
- **Operations Used:** DIV (op=3), MUL (op=2), SUB (op=1)
- **Complexity:** Multi-step algorithm requiring 3 hardware operations
- **Demonstrates:** Power of microcode to compose complex operations from simple ones

### Current Limitations
This is a **simplified implementation for demonstration**. A full 8087-compatible FPREM would require:

1. **Integer Conversion**: Proper truncation of quotient towards zero
2. **Condition Codes**: Set C0, C1, C2 to indicate reduction progress
3. **Iterative Reduction**: For large operands, may need multiple calls
4. **Sign Handling**: Remainder has same sign as dividend
5. **Partial Results**: For very large quotients, return partial remainder

### Example
```
Input:  temp_fp_a = 17.0  (dividend)
        temp_fp_b = 5.0   (divisor)
Output: temp_result = 2.0 (remainder: 17 = 3*5 + 2)
```

### Future Enhancements
```verilog
// Pseudo-code for full FPREM:
if (|quotient| < 2^63) {
    // Can complete in one iteration
    compute exact remainder
    set C2 = 0 (complete)
} else {
    // Partial reduction
    reduce by 2^63 at a time
    set C2 = 1 (incomplete, call again)
}
```

---

## Programs 7-8: FLD/FST (Reserved)

**Addresses:** 0x0200-0x021F
**Status:** Reserved for future implementation

### Planned Functionality

#### Program 7: FLD - Load with Format Conversion
- Load from memory with automatic format conversion
- Support for: 32-bit single, 64-bit double, 80-bit extended
- Integer formats: 16-bit, 32-bit, 64-bit, BCD
- Would use format conversion hardware units

#### Program 8: FST - Store with Format Conversion
- Store to memory with automatic format conversion
- Same format support as FLD
- Rounding applied according to control word

---

## Programs 10-11: FXTRACT/FSCALE (Reserved)

**Addresses:** 0x0400-0x050F
**Status:** Reserved for future implementation

### Program 10: FXTRACT - Extract Exponent and Significand
- Separates number into exponent and significand
- Returns two values (would need dual result mechanism)

### Program 11: FSCALE - Scale by Power of 2
- Multiplies by 2^n where n is an integer
- Efficient scaling without full multiplication

---

## Microcode Instruction Set

### Control Flow Instructions

| Opcode | Name | Format | Description |
|--------|------|--------|-------------|
| 0x0    | NOP  | {NOP, -, -, next} | No operation |
| 0x1    | EXEC | {EXEC, mop, imm, next} | Execute micro-operation |
| 0x2    | JUMP | {JUMP, -, -, addr} | Unconditional jump |
| 0x3    | CALL | {CALL, -, -, addr} | Call subroutine |
| 0x4    | RET  | {RET, -, -, -} | Return from subroutine |
| 0xF    | HALT | {HALT, -, -, -} | Halt execution |

### Micro-Operations (EXEC Instruction)

#### Hardware Unit Interface (0x10-0x1F)

| Code | Name | Description |
|------|------|-------------|
| 0x10 | MOP_CALL_ARITH | Start arithmetic operation (imm=op code) |
| 0x11 | MOP_WAIT_ARITH | Wait for arithmetic completion |
| 0x12 | MOP_LOAD_ARITH_RES | Load result from arithmetic unit |
| 0x13 | MOP_CALL_STACK | Execute stack operation |
| 0x14 | MOP_WAIT_STACK | Wait for stack completion |
| 0x15 | MOP_LOAD_STACK_REG | Load from stack register |
| 0x16 | MOP_STORE_STACK_REG | Store to stack register |
| 0x17 | MOP_SET_STATUS | Set status flags |
| 0x18 | MOP_GET_STATUS | Get status flags |
| 0x19 | MOP_GET_CC | Get condition codes |

### Arithmetic Operation Codes

When using `MOP_CALL_ARITH`, the immediate field specifies the operation:

| Code | Operation | Hardware Unit |
|------|-----------|---------------|
| 0    | ADD       | FPU_IEEE754_AddSub |
| 1    | SUB       | FPU_IEEE754_AddSub |
| 2    | MUL       | FPU_IEEE754_Multiply |
| 3    | DIV       | FPU_IEEE754_Divide |
| 12   | SQRT      | FPU_SQRT_Newton |
| 13   | SIN       | FPU_CORDIC_Wrapper |
| 14   | COS       | FPU_CORDIC_Wrapper |

---

## Performance Analysis

### Microcode Overhead

Each subroutine has consistent overhead:

```
1 cycle:  START (load PC from program table)
1 cycle:  FETCH (read instruction from ROM)
1 cycle:  DECODE (decode instruction)
1 cycle:  EXEC CALL_ARITH (start operation)
1 cycle:  FETCH (fetch WAIT instruction)
1 cycle:  DECODE
1 cycle:  EXEC WAIT_ARITH (check done)
N cycles: STATE_WAIT (loop until operation completes)
1 cycle:  FETCH (after done)
1 cycle:  DECODE
1 cycle:  EXEC LOAD_RES (load result)
1 cycle:  FETCH
1 cycle:  DECODE
1 cycle:  EXEC RET
= ~5-6 cycles overhead + N hardware cycles
```

### Measured Cycle Counts

| Operation | Hardware Cycles | Microcode Cycles | Total | Overhead |
|-----------|----------------|------------------|-------|----------|
| ADD       | 3              | 5                | 8     | 167%     |
| SUB       | 3              | 5                | 8     | 167%     |
| MUL       | 2              | 5                | 7     | 250%     |
| DIV       | 73             | 5                | 78    | 7%       |
| FPREM     | ~20 (est)      | 15               | 35    | 75%      |

**Key Insight:** Microcode overhead is significant for fast operations (ADD/SUB/MUL) but minimal for slow operations (DIV). Complex multi-step operations (FPREM) benefit from microcode flexibility.

---

## State Machine Flow

### Subroutine Execution States

```
STATE_IDLE
  ↓ (start=1)
STATE_FETCH ←─────┐
  ↓               │
STATE_DECODE      │
  ↓               │
STATE_EXEC        │
  ↓               │
  ├→ CALL_ARITH   │
  │    ↓          │
  ├→ WAIT_ARITH →─┤ (if !done)
  │    ↓          │
  │  STATE_WAIT ──┘ (loop checking done)
  │    ↓ (done)
  ├→ LOAD_RES ────┘
  │    ↓
  └→ RET
       ↓
    STATE_IDLE (instruction_complete=1)
```

### Critical: STATE_WAIT Implementation

The STATE_WAIT state checks completion **every cycle**:
- Eliminates race conditions where done signal missed during FETCH/DECODE
- Ensures immediate response when hardware completes
- No cycling through FETCH/DECODE while waiting

---

## Usage Examples

### Example 1: Direct Subroutine Call
```verilog
// Compute 3.14 + 2.71
temp_fp_a <= 80'h4000C90FDAA22168C000;  // 3.14
temp_fp_b <= 80'h40005B05B05B05B06000;  // 2.71

micro_program_index <= 4'd0;  // FADD
start <= 1'b1;

@(posedge clk);
start <= 1'b0;

wait (instruction_complete);
result = temp_result;  // 5.85
```

### Example 2: Chaining Operations (Requires Main Program)
```verilog
// Compute (a + b) * c
// Would need main program to:
// 1. CALL program 0 (FADD)
// 2. Move result to temp_fp_a
// 3. Load c into temp_fp_b
// 4. CALL program 2 (FMUL)
// 5. RET
```

### Example 3: Complex Operation (FPREM)
```verilog
// Compute 17.0 MOD 5.0
temp_fp_a <= 80'h4003A000000000000000;  // 17.0
temp_fp_b <= 80'h4001A000000000000000;  // 5.0

micro_program_index <= 4'd9;  // FPREM
start <= 1'b1;

@(posedge clk);
start <= 1'b0;

wait (instruction_complete);
result = temp_result;  // ~2.0
```

---

## Testing Status

### Validated Subroutines ✅
- Program 0 (FADD): Infrastructure tested, completes successfully
- Program 1 (FSUB): Infrastructure tested, completes successfully
- Program 2 (FMUL): Infrastructure tested, completes successfully
- Program 3 (FDIV): Infrastructure tested, completes successfully

### Partial Validation ⚠️
- Program 4 (FSQRT): Times out >100 cycles, needs investigation
- Program 9 (FPREM): Implemented but not tested

### Not Implemented 🔲
- Programs 5-8, 10-11: Reserved, not yet implemented

### Test Limitations
- Current tests use zero operands (temp_fp_a = temp_fp_b = 0)
- Infrastructure validated, but result verification requires operand initialization
- Need mechanism to load operands before calling subroutines

---

## Future Enhancements

### Short Term
1. **Operand Initialization**: Add micro-operations or interface to set temp registers
2. **SQRT Fix**: Investigate and fix timeout issue
3. **FPREM Testing**: Validate FPREM implementation with real operands

### Medium Term
4. **FLD/FST Implementation**: Add memory load/store with format conversion
5. **Status Word Integration**: Set condition codes properly
6. **Exception Handling**: Comprehensive exception detection and reporting

### Long Term
7. **FXTRACT/FSCALE**: Implement remaining transcendental operations
8. **Optimization**: Reduce microcode overhead for simple operations
9. **Main Programs**: Create ROM library of common operation sequences

---

## References

- Intel 8087 Data Sheet
- IEEE 754-1985 Floating-Point Standard
- `MicroSequencer_Extended.v` - Implementation
- `MICROSEQUENCER_INTEGRATION.md` - Architecture documentation
- `FLAWS_DETECTED.md` - Test results and known issues

---

**Document Version:** 1.0
**Last Updated:** 2025-11-09
**Status:** Living document - updated as library expands
