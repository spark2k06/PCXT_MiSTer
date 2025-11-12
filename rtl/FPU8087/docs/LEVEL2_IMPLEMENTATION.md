# Level 2: Moderate Busy Tracking Implementation

## Overview

Level 2 implementation adds busy flag tracking to allow CPU continuation during no-wait instruction execution while wait instructions block when the FPU is busy. This provides partial 8087 compatibility with moderate architectural changes.

## Implementation Status

**Status**: ✅ Complete
**Date**: 2025-11-10

## Changes Made

### 1. Added Busy Tracking Infrastructure

**Location**: FPU_Core.v lines 909-911

```verilog
reg        fpu_busy;           // FPU has operation in progress
                               // Set when arith_enable goes high
                               // Cleared when operation completes (arith_done or state transition)
```

This register tracks whether the FPU is executing a multi-cycle operation.

**Note**: Previously included `busy_countdown` register, but this was **removed** to use `arith_done` signal instead of hardcoded cycle counting. This eliminates the need to maintain operation-specific cycle counts.

### 2. Created Helper Functions

#### `is_nowait_instruction()` (lines 890-899)
Classifies instructions as no-wait (FNINIT, FNSTCW, FNSTSW, FNCLEX).

**Note**: Previously had `get_operation_cycles()` function with hardcoded cycle counts, but this was **removed** in favor of using the actual `arith_done` signal to track operation completion. This approach:
- Eliminates maintenance burden of keeping cycle counts synchronized
- Automatically tracks actual operation timing
- Adapts to future timing changes without code updates
- Simplifies the implementation

### 3. Modified STATE_IDLE Logic (lines 1102-1131)

Wait instructions now check `fpu_busy` status:
- If `fpu_busy=1` and instruction is wait-type: CPU blocks (ready stays high)
- If `fpu_busy=1` and instruction is no-wait: CPU continues (ready goes low)
- Sets `fpu_busy=1` when starting new operation

### 4. Added Busy Flag Clearing on Operation Completion

Instead of using a countdown timer, `fpu_busy` is now cleared automatically when operations complete:

```verilog
// In each operation's completion path (when arith_done is true):
arith_enable <= 1'b0;
fpu_busy <= 1'b0;  // Clear busy when operation completes
state <= STATE_WRITEBACK;
```

This approach:
- Uses the actual `arith_done` signal to detect completion
- No hardcoded cycle counts needed
- Automatically adapts to actual operation timing
- Simplifies maintenance and reduces fragility

### 5. Instrumented All Arithmetic Operations

Added busy tracking to **all 25+ locations** where `arith_enable <= 1'b1`:

#### Main Operations (STATE_EXECUTE):
1. **FADD** (line 1206)
2. **FSUB** (line 1273)
3. **FMUL** (line 1318)
4. **FDIV** (line 1363)
5. **FILD16** (line 1392)
6. **FILD32** (line 1408)
7. **FIST16/FISTP16** (line 1425)
8. **FIST32/FISTP32** (line 1444)
9. **FLD32** (line 1463)
10. **FLD64** (line 1479)
11. **FST32/FSTP32** (line 1501)
12. **FST64/FSTP64** (line 1521)
13. **FSQRT** (line 1566)
14. **FSIN** (line 1585)
15. **FCOS** (line 1603)
16. **FCOM/FCOMP** (line 1905)
17. **FCOMPP** (line 1939)
18. **FSUBR/FSUBRP** (line 2122)
19. **FDIVR/FDIVRP** (line 2145)

#### Memory Conversion Operations (STATE_MEM_CONVERT):
20. **BCD → FP80** (line 2253) - 2 cycles
21. **Integer → FP80** (line 2288) - 2 cycles
22. **Float → FP80** (line 2319) - 2 cycles
23. **FP80 → BCD** (line 2344) - 2 cycles
24. **FP80 → Integer** (line 2382) - 2 cycles
25. **FP80 → Float** (line 2409) - 2 cycles

Each location now:
- **Sets** `fpu_busy <= 1'b1;` when starting the operation
- **Clears** `fpu_busy <= 1'b0;` when the operation completes (arith_done goes high)

## Behavioral Changes

### Before Level 2 (Level 0/1):
- All instructions wait for FPU completion
- No difference in timing between wait and no-wait instructions
- CPU always blocks until operation completes

### After Level 2:
- **Wait instructions** (FINIT, FSTCW, FSTSW, FCLEX):
  - Check `fpu_busy` flag before executing
  - Block CPU if FPU is busy (`ready` stays high)
  - Proceed only when `fpu_busy=0`

- **No-wait instructions** (FNINIT, FNSTCW, FNSTSW, FNCLEX):
  - Execute immediately regardless of `fpu_busy` state
  - CPU can continue to next instruction
  - May read stale/incomplete status if previous operation not done

## Limitations

### What Level 2 Provides:
✅ Busy flag tracking using actual operation completion signals
✅ Wait instructions check busy state
✅ No-wait instructions bypass busy check
✅ Automatic busy flag management
✅ Partial CPU-FPU parallelism
✅ Zero maintenance for operation timing changes

### What Level 2 Does NOT Provide:
❌ True asynchronous execution (still single-threaded FSM)
❌ Exception checking before wait instruction execution
❌ FERR# / BUSY# external signal outputs
❌ Hardware interrupt integration (IRQ13)
❌ Full FWAIT behavior integration
❌ Exception wait states

## Testing Requirements

Level 2 implementation should be tested with:

1. **Sequential operation test**: Start long operation (FDIV), immediately issue wait instruction → should block
2. **No-wait bypass test**: Start long operation, immediately issue no-wait instruction → should proceed
3. **Busy countdown test**: Verify busy flag clears after correct number of cycles
4. **Mixed instruction test**: Interleave wait and no-wait instructions with various operations
5. **Status word timing**: Verify FNSTSW can read status while operation in progress

## Future Enhancements (Level 3)

To achieve full 8087 compatibility:
- Add exception checking to wait instructions (from Level 1)
- Implement FWAIT behavior integration
- Add STATE_EXCEPTION_WAIT state
- Implement FERR# output signal
- Add true asynchronous pipeline
- Support hardware interrupt generation

## Summary

Level 2 successfully implements moderate busy tracking that differentiates wait vs no-wait instruction behavior. The implementation adds:
- **1 new register** (fpu_busy) - **Removed**: busy_countdown (replaced with arith_done signal)
- **1 helper function** (is_nowait_instruction) - **Removed**: get_operation_cycles (no longer needed)
- **25+ instrumentation points** across all arithmetic operations
- **Modified control flow** in STATE_IDLE
- **Automatic busy clearing** on operation completion

This provides significant improvement in wait/no-wait instruction accuracy while maintaining synchronous design simplicity. The use of `arith_done` signal instead of hardcoded cycle counts makes the implementation:
- **More maintainable**: No cycle counts to keep synchronized
- **More accurate**: Tracks actual operation timing
- **More robust**: Automatically adapts to timing changes
- **Simpler**: Less code and fewer registers
