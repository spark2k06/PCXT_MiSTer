# Phase 2: Exception Handling Implementation Plan

## Current State Analysis

### ✅ Already Implemented
1. **Exception Detection** - Arithmetic units detect:
   - Invalid operation
   - Denormalized operand
   - Zero divide
   - Overflow
   - Underflow
   - Precision (inexact)

2. **Status Word** - Exception flags accumulate (sticky bits)
3. **Control Word** - Exception masks exist for all exception types
4. **Basic Exception Reporting** - Flags set in status word

### ❌ Missing Implementation

1. **Masked vs Unmasked Response**
   - Current: Exceptions are detected and flags set
   - Missing: Different behavior for masked vs unmasked exceptions
   - Need: IEEE 754 default responses for masked exceptions

2. **NaN Propagation**
   - Current: Partial implementation in arithmetic units
   - Missing: Consistent NaN propagation across all operations
   - Need: Proper QNaN/SNaN handling

3. **Condition Code Consistency**
   - Current: C0-C3 set by comparison operations
   - Missing: Consistent CC updates for all operations
   - Need: C1 for rounding direction, consistent semantics

4. **Trap Mechanism**
   - Current: None (only polling via status word)
   - Missing: Signal to CPU for unmasked exceptions
   - Need: `error` output properly connected

---

## Implementation Tasks

### Task 1: Masked vs Unmasked Exception Response

**IEEE 754 Default Responses for Masked Exceptions:**

| Exception | Masked Response | Unmasked Response |
|-----------|----------------|-------------------|
| **Invalid** | Return QNaN | Set error, return QNaN |
| **Overflow** | Return ±Infinity | Set error, return ±Infinity |
| **Underflow** | Return ±0 or denormal | Set error, return result |
| **Zero Divide** | Return ±Infinity | Set error, return ±Infinity |
| **Denormal** | Continue with denormal | Set error, continue |
| **Precision** | Return rounded result | Set error, return rounded result |

**Implementation:**
- Add exception response logic in FPU_Core FSM
- Check exception flags against masks
- Set `error` output for unmasked exceptions
- Override result with IEEE 754 defaults when needed

---

### Task 2: NaN Propagation Rules

**IEEE 754 NaN Rules:**

1. **QNaN Propagation:**
   - QNaN + anything = QNaN
   - Preserve payload if possible
   - If multiple NaNs, return first QNaN

2. **SNaN Handling:**
   - SNaN triggers invalid exception
   - SNaN converted to QNaN
   - SNaN + anything = QNaN (with invalid exception)

3. **Special Cases:**
   - 0 × Infinity = QNaN (invalid)
   - Infinity - Infinity = QNaN (invalid)
   - Infinity / Infinity = QNaN (invalid)
   - 0 / 0 = QNaN (invalid)
   - sqrt(negative) = QNaN (invalid)

**Implementation:**
- Add NaN detection function
- Add NaN propagation logic before arithmetic operations
- Check for invalid NaN-producing operations
- Ensure consistent NaN bit pattern (FP80: 0x7FFF_C000_0000_0000_0000 for QNaN)

---

### Task 3: Condition Code Consistency

**Intel 8087 Condition Code Semantics:**

| Operation | C3 | C2 | C1 | C0 | Notes |
|-----------|----|----|----|----|-------|
| **Arithmetic** | ? | ? | Rounding | ? | C1 = 1 if rounded up |
| **Compare** | = | < | ? | > | Standard comparison |
| **FXAM** | Sign | Class | Class | Class | Operand classification |
| **Transcendental** | ? | ? | Reduction | ? | C1 = number of times reduced |

**C1 Rounding Indicator:**
- C1 = 0: Rounded down or exact
- C1 = 1: Rounded up

**Implementation:**
- Add C1 rounding tracking to all arithmetic operations
- Ensure consistent CC updates in FSM
- Add CC setting for transcendental operations
- Document CC behavior for each instruction type

---

### Task 4: Test Suite for Exception Handling

**Test Cases Needed:**

1. **Masked Exception Tests:**
   - Invalid: sqrt(-1) with mask → QNaN
   - Overflow: HUGE × HUGE with mask → +Inf
   - Underflow: TINY / HUGE with mask → +0
   - Zero Divide: 1.0 / 0.0 with mask → +Inf

2. **Unmasked Exception Tests:**
   - Same operations without mask → error signal set

3. **NaN Propagation Tests:**
   - QNaN + 1.0 → QNaN
   - SNaN + 1.0 → QNaN + invalid exception
   - 0 × Inf → QNaN + invalid exception
   - Inf - Inf → QNaN + invalid exception

4. **Condition Code Tests:**
   - Arithmetic operations set C1 properly
   - Comparisons set C0-C3 correctly
   - FXAM classification works

---

## Implementation Strategy

### Phase 2A: Exception Response (Week 1, Days 1-3)
1. Add exception response logic module
2. Integrate with FPU_Core FSM
3. Test masked/unmasked behavior
4. Document changes

### Phase 2B: NaN Propagation (Week 1, Days 4-5)
1. Add NaN detection functions
2. Add pre-operation NaN checks
3. Implement invalid operation detection
4. Test NaN propagation

### Phase 2C: Condition Codes (Week 2, Days 1-2)
1. Add C1 rounding tracking
2. Update CC logic for all operations
3. Test CC consistency
4. Document CC semantics

### Phase 2D: Testing (Week 2, Days 3-5)
1. Create comprehensive test suite
2. Run exception tests
3. Verify IEEE 754 compliance
4. Performance testing

---

## Success Criteria

✅ **Exception Response:**
- Masked exceptions return IEEE 754 defaults
- Unmasked exceptions set error signal
- Exception flags accumulate correctly

✅ **NaN Propagation:**
- QNaN propagates through all operations
- SNaN triggers invalid exception
- Invalid operations produce QNaN

✅ **Condition Codes:**
- C1 indicates rounding direction
- All operations update CCs consistently
- Comparison semantics match 8087

✅ **Testing:**
- All test cases pass
- IEEE 754 compliance verified
- No regressions in existing functionality

---

## Files to Modify

1. **FPU_Core.v** - Main FSM with exception response logic
2. **FPU_ArithmeticUnit.v** - NaN handling improvements (if needed)
3. **MicroSequencer_Extended_BCD.v** - CC updates (if needed)
4. **tb_exception_handling.v** - NEW: Comprehensive test suite

---

## Estimated Effort

- **Task 1 (Exception Response):** 2-3 days
- **Task 2 (NaN Propagation):** 2 days
- **Task 3 (Condition Codes):** 1-2 days
- **Task 4 (Testing):** 2-3 days

**Total:** 7-10 days (1-2 weeks)

---

**Document Version:** 1.0
**Date:** 2025-11-10
**Status:** ⏳ Planning Complete, Ready for Implementation
