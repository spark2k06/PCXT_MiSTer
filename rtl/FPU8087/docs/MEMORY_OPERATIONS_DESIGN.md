# Memory Operations Design for 8087 FPU

## Overview

This document describes the design for implementing memory operations in the 8087 FPU.

---

## Current Status

The instruction decoder (`FPU_Instruction_Decoder.v`) already provides:
- `has_memory_op` - Flag indicating memory operation required
- `operand_size` - Memory operand size (0=word, 1=dword, 2=qword, 3=tbyte)
- `is_integer` - Integer format flag
- `is_bcd` - BCD format flag

What's missing:
- Memory bus interface in FPU_Core
- Memory read/write state machine
- Memory address handling
- Multi-cycle memory transfers

---

## Design Approach

### 1. Memory Bus Interface

Add the following signals to `FPU_Core` module:

```verilog
// Memory interface (new ports)
input wire [19:0]  mem_address,      // Memory address from CPU
input wire         mem_read_req,     // CPU requests memory read
input wire         mem_write_req,    // CPU requests memory write
input wire [1:0]   mem_size,         // 0=word, 1=dword, 2=qword, 3=tbyte
input wire [79:0]  mem_data_in,      // Data from memory
output reg [79:0]  mem_data_out,     // Data to memory
output reg         mem_ready,        // Memory operation complete
output reg         mem_valid         // Output data is valid
```

### 2. State Machine Extensions

Add new states to handle memory operations:

```verilog
localparam STATE_MEM_READ      = 4'd9;   // Reading from memory
localparam STATE_MEM_WRITE     = 4'd10;  // Writing to memory
localparam STATE_MEM_CONVERT   = 4'd11;  // Converting memory format
```

### 3. Operation Flow

**Memory Load Operation (e.g., FLD m32real, FILD m16int):**
```
STATE_DECODE → STATE_MEM_READ → STATE_MEM_CONVERT → STATE_STACK_OP → STATE_DONE
```

**Memory Store Operation (e.g., FST m64real, FIST m32int):**
```
STATE_DECODE → STATE_MEM_CONVERT → STATE_MEM_WRITE → STATE_DONE
```

**Memory Arithmetic Operation (e.g., FADD m32real):**
```
STATE_DECODE → STATE_MEM_READ → STATE_MEM_CONVERT → STATE_EXECUTE → STATE_WRITEBACK → STATE_DONE
```

### 4. Size Handling

| operand_size | Bytes | Format Examples |
|--------------|-------|-----------------|
| 2'd0         | 2     | int16, status word |
| 2'd1         | 4     | int32, FP32 |
| 2'd2         | 8     | int64, FP64 |
| 2'd3         | 10    | FP80, BCD80 |

### 5. Format Conversions

**On Memory Read:**
- int16 → FP80: Use existing `FPU_Int16_to_FP80`
- int32 → FP80: Use existing `FPU_Int32_to_FP80`
- int64 → FP80: Use existing `FPU_UInt64_to_FP80`
- FP32 → FP80: Use existing `FPU_FP32_to_FP80`
- FP64 → FP80: Use existing `FPU_FP64_to_FP80`
- BCD → FP80: Use existing `FPU_BCD_to_Binary` + `FPU_UInt64_to_FP80`

**On Memory Write:**
- FP80 → int16: Use existing `FPU_FP80_to_Int16`
- FP80 → int32: Use existing `FPU_FP80_to_Int32`
- FP80 → int64: Use existing `FPU_FP80_to_UInt64`
- FP80 → FP32: Use existing `FPU_FP80_to_FP32`
- FP80 → FP64: Use existing `FPU_FP80_to_FP64`
- FP80 → BCD: Use existing `FPU_FP80_to_UInt64` + `FPU_Binary_to_BCD`

---

## Implementation Plan

### Phase 1: Add Memory Interface (2-3 days)

1. Modify `FPU_Core.v`:
   - Add memory interface ports
   - Add memory address register
   - Add memory size register
   - Add memory operation flags

2. Modify `FPU8087_Integrated.v`:
   - Pass decoder flags to FPU_Core
   - Wire memory interface to CPU interface

### Phase 2: Implement Memory Read (2-3 days)

1. Add STATE_MEM_READ to state machine
2. Implement memory read logic:
   - Capture memory address
   - Request data from memory bus
   - Wait for data ready
   - Transition to conversion state

3. Add STATE_MEM_CONVERT for reads:
   - Based on operand_size and is_integer/is_bcd
   - Convert to FP80 format
   - Push to stack or use for arithmetic

### Phase 3: Implement Memory Write (2-3 days)

1. Add STATE_MEM_WRITE to state machine
2. Implement memory write logic:
   - Pop value from stack or get result
   - Convert from FP80 to target format
   - Write to memory bus
   - Signal completion

### Phase 4: Testing (2-3 days)

1. Create comprehensive memory operation tests:
   - FLD m32real, FLD m64real, FLD m80real
   - FST m32real, FST m64real, FST m80real
   - FILD m16int, FILD m32int, FILD m64int
   - FIST m16int, FIST m32int, FIST m64int
   - FADD m32real, FSUB m64real (memory operand arithmetic)
   - FBLD m80bcd, FBSTP m80bcd

2. Test edge cases:
   - Alignment requirements
   - Invalid memory addresses
   - Stack overflow/underflow during memory ops

---

## Simplified Alternative: Register-based Memory Operations

For initial implementation, we can use a simpler approach:

1. CPU loads/stores memory data via `data_in`/`data_out` ports (already exist)
2. FPU just needs to know:
   - Is this a memory operand?
   - What format is it in?
3. Conversion happens during DECODE state

**Benefits:**
- Minimal changes to FPU_Core
- Reuses existing data path
- Simpler testing
- Memory address calculation stays in CPU

**Flow:**
```
CPU: Calculate memory address, read data
CPU: Send data + format to FPU via data_in
FPU: Decode, convert format, execute
FPU: Send result back via data_out
CPU: Write result to memory if needed
```

This approach makes the FPU a pure computational unit, leaving memory management to the CPU.

---

## Recommended Approach

**Start with Simplified Register-Based Approach:**
1. Implement format detection in DECODE state
2. Add format conversion before arithmetic
3. Test with existing ports
4. Achieve 85-90% functionality quickly

**Later Add Full Memory Bus (if needed):**
1. Add memory bus interface
2. Add multi-cycle memory states
3. Achieve 100% compatibility

---

## Next Steps

1. Implement simplified register-based memory operations
2. Update decoder integration to pass format flags
3. Add format conversion in DECODE state
4. Create comprehensive tests
5. Verify all instructions work with memory operands

Estimated effort: 1-2 weeks for simplified approach, 3-4 weeks for full memory bus implementation.
