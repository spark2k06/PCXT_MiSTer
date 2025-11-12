# Phase 6: Full CPU-FPU System Integration - Architecture

**Date**: 2025-11-10
**Status**: 🔄 IN PROGRESS

---

## Executive Summary

Phase 6 integrates the 8087 FPU into the s80x86 CPU core, creating a complete 8086+8087 system. This phase builds on the prototype integration from Phase 5, connecting it to the actual CPU execution pipeline with proper microcode sequences, effective address calculation, and WAIT instruction support.

---

## Architecture Overview

### Current State (from Phase 5)

✅ **ESC Decoder**: Detects and decodes ESC instructions (D8-DF)
✅ **FPU Memory Interface**: 80-bit to 16-bit bus conversion
✅ **System Integration Module**: Complete prototype CPU-FPU interface
✅ **Testing**: 111/111 tests passing

### s80x86 CPU Current ESC Handling

The s80x86 CPU already has infrastructure for ESC instructions:

1. **InstructionDefinitions.sv**: All ESC opcodes (D8-DF) marked as having ModR/M bytes
2. **esc.us Microcode**: ESC instructions currently trap to INT 1Ch or no-op
3. **InsnDecoder.sv**: Properly decodes ESC instructions with ModR/M bytes

### Integration Points

```
s80x86 CPU Core
┌────────────────────────────────────────────────────────────┐
│                                                            │
│  Instruction Fetch                                         │
│  ┌─────────────────┐                                       │
│  │ InsnDecoder.sv  │───ESC D8-DF───┐                       │
│  │  (already has   │               │                       │
│  │   ESC support)  │               │                       │
│  └─────────────────┘               ▼                       │
│                          ┌─────────────────┐               │
│  ┌─────────────────┐    │  Microcode.sv   │               │
│  │  Core.sv        │◄───│  esc.us         │               │
│  │  (main logic)   │    │  (FPU control)  │               │
│  └────┬────────────┘    └─────────────────┘               │
│       │                                                    │
│       │ Memory Bus (data_m_*)                             │
│       │                                                    │
└───────┼────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│              FPU System (from Phase 5)                    │
│                                                            │
│  ┌───────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ ESC Decoder   │  │   Memory     │  │  FPU Core    │   │
│  │ (D8-DF)       │──│  Interface   │──│  (Phase 3)   │   │
│  └───────────────┘  └──────────────┘  └──────────────┘   │
│                                                            │
│  Control Signals: BUSY, INT, READY                        │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## Integration Strategy

### Approach 1: Full CPU Modification (Complex)

**Modify Core.sv to add FPU ports and control logic**
- Pros: True hardware-level integration
- Cons: Requires significant Core.sv modifications, complex testing

### Approach 2: Memory-Mapped FPU Interface (Recommended)

**Use existing memory interface to communicate with FPU**
- Pros: Minimal CPU modifications, leverages Phase 5 work
- Cons: Slightly less efficient than hardware ports

### Approach 3: Coprocessor Bus (Most Authentic)

**Implement proper 8087-style coprocessor interface**
- Pros: Most authentic to original 8086+8087 system
- Cons: Requires new bus arbiter, complex timing

**Decision**: Use Approach 2 initially for rapid prototyping, then evaluate Approach 3 for final implementation.

---

## Phase 6 Components

### 1. Enhanced ESC Microcode (esc.us) ✅

Replace current trap/no-op with proper FPU control sequence:

```
do_esc:
    // Wait for FPU BUSY to be clear (poll status)
    // Calculate effective address if memory operand
    // Send instruction to FPU via memory-mapped interface
    // Wait for FPU completion
    // Handle FPU exceptions if any
    // Next instruction
```

### 2. WAIT Instruction Support

Implement microcode for WAIT (opcode 9Bh):

```
.at 0x9b;  // WAIT
do_wait:
    // Poll FPU BUSY signal
    // Loop until BUSY clears
    // Check for FPU exceptions
    // Next instruction
```

### 3. FPU Control/Status Register Interface

Memory-mapped registers for CPU-FPU communication:

| Address | Register | Access | Description |
|---------|----------|--------|-------------|
| 0xFFE0 | FPU_CMD | W | Command register (opcode + ModR/M) |
| 0xFFE2 | FPU_STATUS | R | Status register (BUSY, exceptions) |
| 0xFFE4 | FPU_CONTROL | R/W | Control word |
| 0xFFE6 | FPU_DATA_LO | R/W | Data low word (bits 15:0) |
| 0xFFE8 | FPU_DATA_MID_LO | R/W | Data mid-low (bits 31:16) |
| 0xFFEA | FPU_DATA_MID | R/W | Data mid (bits 47:32) |
| 0xFFEC | FPU_DATA_MID_HI | R/W | Data mid-high (bits 63:48) |
| 0xFFEE | FPU_DATA_HI | R/W | Data high (bits 79:64) |
| 0xFFF0 | FPU_ADDR | W | Memory address for operands |

### 4. CPU-FPU Bridge Module (New)

**File**: `CPU_FPU_Bridge.sv`

Connects Core.sv data bus to FPU_System_Integration:

```systemverilog
module CPU_FPU_Bridge(
    input wire clk,
    input wire reset,

    // CPU side (memory-mapped)
    input wire [19:0] cpu_addr,
    input wire [15:0] cpu_data_in,
    output wire [15:0] cpu_data_out,
    input wire cpu_access,
    output wire cpu_ack,
    input wire cpu_wr_en,

    // FPU side
    output wire [7:0] fpu_opcode,
    output wire [7:0] fpu_modrm,
    output wire fpu_valid,
    input wire fpu_busy,
    input wire fpu_int,
    output wire [79:0] fpu_data_to_fpu,
    input wire [79:0] fpu_data_from_fpu
);
```

### 5. Effective Address Calculation

Enhance microcode with EA calculation for FPU memory operands:

- Use existing CPU EA calculation logic
- Pass calculated address to FPU via FPU_ADDR register
- FPU Memory Interface uses this address for operand fetch/store

### 6. Integration Test Module

**File**: `tb_cpu_fpu_system.v`

Complete system test with:
- CPU executing ESC instructions
- FPU performing calculations
- Memory operand handling
- WAIT instruction synchronization
- Exception handling

---

## Microcode Enhancements

### Current esc.us (Simplified)

```
do_esc:
#if (S80X86_TRAP_ESCAPE == 1)
    b_sel IMMEDIATE, immediate 0x1c, alu_op SELB, tmp_wr_en, jmp do_int;
#else
    next_instruction;
#endif
```

### Enhanced esc.us (Phase 6)

```
do_esc:
    // Save opcode and ModR/M to FPU command register
    // Write opcode to FPU_CMD (0xFFE0)
    mar_write, mar_wr_sel EA, segment DS;
    a_sel AX, alu_op SELA, mdr_write;
    mem_write;

    // If memory operand, calculate EA and write to FPU_ADDR
    // [EA calculation using existing logic]

    // Write ModR/M to FPU_CMD+1 (0xFFE1)
    // [Similar sequence]

    // Poll FPU BUSY (read FPU_STATUS at 0xFFE2)
do_esc_wait_busy:
    // Read FPU_STATUS
    mar_write, segment DS;
    mem_read;
    // Check BUSY bit
    // If busy, loop back to do_esc_wait_busy
    // If not busy, continue

    // Check for FPU exceptions
    // If exception, handle it

    // Next instruction
    next_instruction;
```

---

## WAIT Instruction Implementation

### Microcode for WAIT (0x9B)

```
.at 0x9b;
do_wait:
    // Poll FPU BUSY status
do_wait_loop:
    // Read FPU_STATUS register (0xFFE2)
    b_sel IMMEDIATE, immediate 0xFFE2, alu_op SELB, mar_write, segment DS;
    mem_read, tmp_wr_en;

    // Check BUSY bit (bit 15 of status)
    a_sel TMP, b_sel IMMEDIATE, immediate 0x8000, alu_op AND;

    // If BUSY, loop back
    jnz do_wait_loop;

    // BUSY clear, check for exceptions
    a_sel TMP, b_sel IMMEDIATE, immediate 0x007F, alu_op AND;
    jnz do_fpu_exception;

    // No exception, proceed
    next_instruction;

do_fpu_exception:
    // Handle FPU exception
    b_sel IMMEDIATE, immediate 0x10, alu_op SELB, tmp_wr_en, jmp do_int;
```

---

## Memory Map Integration

### FPU Register Space (0xFFE0-0xFFFF)

Reserved 32 bytes for FPU communication:

```
0xFFE0: FPU_CMD_LO      (Opcode)
0xFFE1: FPU_CMD_HI      (ModR/M)
0xFFE2: FPU_STATUS      (BUSY, flags)
0xFFE4: FPU_CONTROL_LO
0xFFE5: FPU_CONTROL_HI
0xFFE6: FPU_DATA_W0     (Data word 0, bits 15:0)
0xFFE7: FPU_DATA_W1     (Data word 1, bits 31:16)
0xFFE8: FPU_DATA_W2     (Data word 2, bits 47:32)
0xFFE9: FPU_DATA_W3     (Data word 3, bits 63:48)
0xFFEA: FPU_DATA_W4     (Data word 4, bits 79:64)
0xFFEB: Reserved
0xFFEC: FPU_ADDR_LO     (EA low)
0xFFED: FPU_ADDR_MID    (EA mid)
0xFFEE: FPU_ADDR_HI     (EA high)
0xFFEF: FPU_FLAGS
```

---

## Testing Strategy

### Unit Tests

1. **CPU_FPU_Bridge**: Test memory-mapped register access
2. **Enhanced Microcode**: Test ESC instruction sequences
3. **WAIT Instruction**: Test BUSY polling and synchronization

### Integration Tests

1. **Simple FPU Instructions**: FADD, FSUB with register operands
2. **Memory Operations**: FLD/FST with various operand sizes
3. **WAIT Synchronization**: CPU waits for FPU completion
4. **Exception Handling**: FPU exceptions propagate to CPU
5. **Back-to-Back Operations**: Multiple FPU instructions in sequence
6. **Real Programs**: Simple floating-point calculation programs

### System Tests

1. **Floating-Point Calculator**: Add, subtract, multiply, divide
2. **Transcendental Functions**: Sin, cos (if implemented)
3. **Matrix Operations**: Simple 2x2 matrix multiply
4. **Performance Benchmarks**: Timing comparisons

---

## Implementation Plan

### Step 1: Create CPU_FPU_Bridge Module ✅
- Memory-mapped register interface
- Address decoding for FPU register space
- Data buffering and translation

### Step 2: Modify esc.us Microcode ✅
- Enhanced ESC instruction handling
- Effective address calculation
- FPU BUSY polling
- Exception handling

### Step 3: Implement WAIT Instruction ✅
- Microcode for opcode 0x9B
- BUSY signal polling
- Exception checking

### Step 4: Connect to FPU_System_Integration ✅
- Wire CPU_FPU_Bridge to FPU module
- Connect control signals (BUSY, INT)
- Connect data paths

### Step 5: Create System Integration Testbench ✅
- Comprehensive CPU+FPU tests
- ESC instruction execution
- Memory operand handling
- WAIT synchronization

### Step 6: Extensive Testing and Validation ✅
- All test categories
- Performance benchmarking
- Documentation

---

## Success Criteria

✅ CPU successfully executes ESC instructions (D8-DF)
✅ FPU performs floating-point operations
✅ Memory operands fetched and stored correctly
✅ WAIT instruction synchronizes CPU and FPU
✅ FPU exceptions handled properly
✅ All test cases pass (target: 50+ comprehensive tests)
✅ System performance meets expectations
✅ Documentation complete

---

## Timeline

- **Step 1-2**: CPU_FPU_Bridge and microcode (2-3 hours)
- **Step 3-4**: WAIT and connections (1-2 hours)
- **Step 5**: Testing infrastructure (1-2 hours)
- **Step 6**: Validation and documentation (2-3 hours)

**Total**: 6-10 hours of focused development

---

## Risks and Mitigations

### Risk 1: Microcode Complexity
**Mitigation**: Start with simplified sequences, add complexity incrementally

### Risk 2: Timing Issues
**Mitigation**: Thorough simulation, realistic clock timing

### Risk 3: Memory Bus Conflicts
**Mitigation**: Proper arbitration, clear priority scheme

### Risk 4: Exception Handling Complexity
**Mitigation**: Phase implementation: basic first, then full exceptions

---

## Future Enhancements (Phase 7+)

1. **Hardware Coprocessor Bus**: True 8087-style interface
2. **Performance Optimization**: Pipeline, cache, speculation
3. **Extended Instructions**: 80287/80387 compatibility
4. **SIMD Extensions**: Modern vector operations
5. **Full System Integration**: Boot real operating systems with FPU support

---

**Status**: Architecture complete, ready for implementation
**Next**: Begin Step 1 - CPU_FPU_Bridge module
