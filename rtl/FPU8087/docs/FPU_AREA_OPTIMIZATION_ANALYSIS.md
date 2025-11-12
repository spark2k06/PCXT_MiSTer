# FPU Area Optimization Analysis

**Date**: 2025-11-10
**Objective**: Identify opportunities for area reduction through resource sharing

## Current Architecture Overview

### Instantiated Units in FPU_ArithmeticUnit

| Unit | Lines | Function | Usage Frequency |
|------|-------|----------|----------------|
| FPU_IEEE754_AddSub | 512 | Add/Subtract | High (common) |
| FPU_IEEE754_Multiply | 324 | Multiply | High (common) |
| FPU_IEEE754_Divide | 433 | Divide (SRT-2) | Medium |
| FPU_Transcendental | 586 | Router for trig/exp/log | Low |
| FPU_CORDIC_Wrapper | 438 | Sin/Cos computation | Low |
| FPU_Range_Reduction | 392 | Angle reduction | Low |
| FPU_Polynomial_Evaluator | 334 | F2XM1/FYL2X | Very Low |
| FPU_Int16_to_FP80 | ~100 | Int16 → FP80 | Low |
| FPU_Int32_to_FP80 | ~120 | Int32 → FP80 | Low |
| FPU_UInt64_to_FP80 | ~130 | UInt64 → FP80 | Very Low (BCD) |
| FPU_FP80_to_Int16 | 179 | FP80 → Int16 | Low |
| FPU_FP80_to_Int32 | 179 | FP80 → Int32 | Low |
| FPU_FP80_to_UInt64 | 175 | FP80 → UInt64 | Very Low (BCD) |
| FPU_FP32_to_FP80 | ~120 | FP32 → FP80 | Medium (loads) |
| FPU_FP64_to_FP80 | ~130 | FP64 → FP80 | Medium (loads) |
| FPU_FP80_to_FP32 | 212 | FP80 → FP32 | Medium (stores) |
| FPU_FP80_to_FP64 | 212 | FP80 → FP64 | Medium (stores) |

**Total Estimated Lines**: ~5,000+ lines of hardware

## Optimization Opportunities

### Priority 1: High Impact, Low Risk

#### 1.1 Unified Format Converter

**Current**: 12+ separate format conversion modules
**Proposal**: Single parameterized format converter with mode selection

**Similar Operations**:
- **FP80 → FPxx** family (FP32, FP64):
  - Extract exponent/mantissa from FP80
  - Round to target precision
  - Repack to target format
  - Check overflow/underflow
  - **Code similarity**: ~80%

- **FPxx → FP80** family (FP32, FP64):
  - Unpack source format
  - Extend precision to FP80
  - Normalize
  - **Code similarity**: ~85%

- **FP80 → Intxx** family (Int16, Int32, UInt64):
  - Extract and denormalize mantissa
  - Shift by exponent
  - Round and check range
  - **Code similarity**: ~75%

- **Intxx → FP80** family (Int16, Int32, UInt64):
  - Find leading 1 (normalization)
  - Calculate exponent
  - Pack to FP80 format
  - **Code similarity**: ~80%

**Proposed Architecture**:
```verilog
module FPU_Format_Converter_Unified(
    input [3:0] mode,  // 16 possible conversions
    input [79:0] fp80_in,
    input [63:0] fp64_in,
    input [31:0] fp32_in,
    input [63:0] int64_in,
    input [31:0] int32_in,
    input [15:0] int16_in,
    output reg [79:0] fp80_out,
    output reg [63:0] fp64_out,
    output reg [31:0] fp32_out,
    output reg [63:0] int64_out,
    output reg [31:0] int32_out,
    output reg [15:0] int16_out,
    // ...
);
```

**Estimated Savings**:
- Current: ~1,600 lines (12 modules × ~133 lines avg)
- Unified: ~600 lines
- **Area Reduction**: ~60%
- **Risk**: Low (proven technique in FPGAs)

#### 1.2 Multiplier/Divider Resource Sharing

**Current**: Separate multiply (324 lines) and divide (433 lines) units
**Observation**: Only one arithmetic operation executes at a time

**Similarities**:
- Both use iterative shift-add/subtract algorithms
- Both have 64-bit datapaths
- Both perform normalization
- Both calculate exponents
- **Shared logic**: ~40%

**Proposed Architecture**:
```verilog
module FPU_MulDiv_Unified(
    input operation,  // 0=multiply, 1=divide
    input [79:0] operand_a,
    input [79:0] operand_b,
    output [79:0] result,
    // ...
);

// Shared resources:
// - 128-bit accumulator/remainder register
// - 64-bit quotient/product register
// - Barrel shifter for alignment
// - Normalization logic
// - Rounding logic
```

**Implementation Strategy**:
- Use state machine to multiplex operations
- Multiplication: iterative partial products (Wallace tree or booth)
- Division: SRT-2 algorithm (already implemented)
- Share accumulator, shifters, and rounding logic

**Estimated Savings**:
- Current: 757 lines (324 + 433)
- Unified: ~550 lines
- **Area Reduction**: ~25%
- **Performance**: Same latency (operations never simultaneous)
- **Risk**: Medium (requires careful state machine design)

### Priority 2: Medium Impact, Low Risk

#### 2.1 CORDIC/Polynomial Evaluator Sharing

**Current**: CORDIC (438 lines) + Polynomial (334 lines) = 772 lines
**Usage**: Transcendental functions (rarely used)

**Observation**:
- CORDIC: Iterative rotation for sin/cos
- Polynomial: Iterative multiply-accumulate for exp/log
- Both use 64-bit fixed-point arithmetic
- Both perform ~50 iterations
- **Never used simultaneously**

**Proposed Architecture**:
```verilog
module FPU_Transcendental_Engine(
    input [2:0] mode,  // CORDIC_ROT, CORDIC_VEC, POLY_F2XM1, etc.
    input [79:0] operand,
    output [79:0] result,
    // Shared 64-bit datapath for iterations
);
```

**Shared Resources**:
- 64-bit accumulator registers (X, Y, Z)
- Barrel shifter for micro-rotations
- Lookup tables (angle table / coefficient ROM)
- Iteration counter (50 cycles)

**Estimated Savings**:
- Current: 772 lines
- Unified: ~550 lines
- **Area Reduction**: ~30%
- **Risk**: Low (both are iterative algorithms)

#### 2.2 BCD Conversion Optimization

**Current**: Separate BCD→Binary (161 lines) and Binary→BCD modules
**Usage**: FBLD/FBSTP instructions only (very rare)

**Options**:
1. **Microcode Implementation**: Move BCD conversion to software
   - Similar to SQRT microcode approach
   - **Area Savings**: 100% (eliminate hardware)
   - **Performance**: Acceptable (rarely used)

2. **Unified BCD Engine**: Single bidirectional converter
   - **Area Savings**: ~40%
   - **Performance**: Same

**Recommendation**: Microcode implementation
- BCD operations are extremely rare in modern code
- Conversion algorithm is straightforward (divide by 10 iteratively)
- Can reuse division hardware via microcode

### Priority 3: Low Impact, Higher Risk

#### 3.1 Adder Reuse for Multiplication

**Proposal**: Use AddSub unit's adder for multiplication partial products
**Challenge**: Different bit widths and timing requirements
**Estimated Savings**: ~15%
**Risk**: High (may impact critical path)
**Recommendation**: Profile first, implement only if critical

#### 3.2 Transcendental Microcode (Already Implemented!)

**Status**: SQRT already moved to microcode (committed)
**Result**: Eliminated FPU_SQRT_Newton (445 lines)
**Area Savings**: ~8-10%

**Future Opportunities**:
- Move SIN/COS to polynomial microcode (slower but smaller)
- Eliminate CORDIC entirely
- **Trade-off**: Performance vs. area

## Recommended Implementation Plan

### Phase 1: Low-Hanging Fruit (Weeks 1-2)
1. ✅ **SQRT Microcode** (DONE - 445 lines saved)
2. **Unified Format Converter** (~1000 lines saved)
   - Combine FP80↔FP32/FP64 converters first
   - Then add integer conversions
   - Test with existing test suite

**Expected Area Reduction**: 20-25%

### Phase 2: Core Arithmetic (Weeks 3-4)
3. **MulDiv Unified Unit** (~200 lines saved)
   - Implement shared datapath
   - Multiplex multiply/divide operations
   - Validate with hybrid testbench (tb_hybrid)

**Expected Additional Reduction**: 8-10%

### Phase 3: Transcendental (Week 5)
4. **CORDIC/Polynomial Merger** (~220 lines saved)
   - Combine iterative engines
   - Share fixed-point datapath
   - Test with tb_transcendental_microcode

5. **BCD Microcode** (~160 lines saved)
   - Implement BCD conversion in microsequencer
   - Eliminate hardware converters

**Expected Additional Reduction**: 10-12%

## Total Estimated Area Reduction

| Phase | Optimization | Lines Saved | Area Reduction |
|-------|-------------|-------------|----------------|
| Done | SQRT Microcode | 445 | 8-10% |
| 1 | Format Converters | 1000 | 18-20% |
| 2 | MulDiv Unified | 200 | 8-10% |
| 3 | Transcendental | 380 | 10-12% |
| **Total** | **All Phases** | **~2025** | **40-50%** |

**Note**: Area reduction percentages are cumulative but not additive due to overhead and routing.

## Risks and Mitigations

### Technical Risks

1. **Critical Path Impact**
   - **Risk**: Resource sharing may increase combinational delay
   - **Mitigation**: Pipeline shared resources, maintain state machines
   - **Validation**: Synthesize and check Fmax after each change

2. **Functional Regression**
   - **Risk**: Refactoring may introduce bugs
   - **Mitigation**: Maintain comprehensive test suite
   - **Tests**: tb_hybrid (5/5), tb_transcendental (10/10)

3. **Multiplexing Overhead**
   - **Risk**: Control logic for sharing adds area
   - **Mitigation**: Use simple enable signals, avoid complex arbitration
   - **Monitor**: Compare actual synthesis results vs. estimates

### Project Risks

1. **Testing Burden**
   - **Risk**: Each change requires full regression
   - **Mitigation**: Automated test scripts
   - **Current Status**: tb_hybrid and tb_transcendental provide good coverage

2. **Schedule Impact**
   - **Risk**: Optimization may delay other features
   - **Mitigation**: Phase 1 provides most benefit, stop if needed

## Conclusion

**High-Confidence Optimizations**:
1. ✅ SQRT Microcode (DONE - 8-10% saved)
2. Unified Format Converter (18-20% potential)
3. MulDiv Unified (8-10% potential)

**Realistic Total Reduction**: 35-40% area savings with Phase 1-2

**Best ROI**: Focus on Phase 1 (Format Converters)
- Highest line count reduction
- Lowest risk (well-understood technique)
- Minimal performance impact

**Recommendation**: Implement Phase 1 immediately, then reassess based on:
- Actual synthesis area results
- Critical path timing
- Project schedule constraints
