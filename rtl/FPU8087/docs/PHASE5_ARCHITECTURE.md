# Phase 5: CPU-FPU System Integration Architecture

**Date**: 2025-11-10
**Status**: 🔧 IN PLANNING

---

## Overview

Phase 5 creates a complete CPU-FPU integration that demonstrates how an 8086 CPU communicates with the 8087 FPU coprocessor. Due to the complexity of modifying the existing s80x86 CPU core, this phase implements a **standalone integration module** that can be used as a reference for future full system integration.

---

## Integration Approach

### Option A: Full CPU Modification (NOT SELECTED)

Would require:
- Modifying Core.sv (21,000 lines) to add ESC instruction handling
- Modifying Microcode.sv (14,500 lines) for FPU operations
- Modifying InsnDecoder.sv (8,500 lines) for ESC opcode decoding
- Integration testing with entire system
- Risk of breaking existing CPU functionality

**Rejected because**: Too invasive, high risk, weeks of work

### Option B: Standalone Integration Module (SELECTED)

Creates a self-contained module that demonstrates the integration:
- CPU-FPU Bridge module that handles bus protocol
- ESC instruction decoder for FPU opcodes (D8-DF)
- System-level testbench with mock CPU
- Complete handshake protocol implementation
- Reference design for future full integration

**Selected because**:
- Non-invasive (doesn't modify existing CPU)
- Can be tested independently
- Demonstrates all integration concepts
- Practical completion within reasonable timeframe
- Provides reference for future integration

---

## 8087 CPU-FPU Interface Protocol

### Physical Signals

**From CPU to FPU**:
```
CLK        - System clock
RESET      - System reset
A[19:0]    - Address bus (20-bit for 8086 1MB addressing)
D[15:0]    - Data bus (bidirectional, 16-bit)
ALE        - Address Latch Enable (signals valid address)
RD#        - Read strobe (active low)
WR#        - Write strobe (active low)
M/IO#      - Memory vs I/O access
```

**From FPU to CPU**:
```
BUSY       - FPU busy (active HIGH, 8087-style)
INT        - Interrupt request (active HIGH)
RQ/GT#     - Request/Grant for bus mastership (not used in 8087)
```

**Bidirectional**:
```
D[15:0]    - Data bus (shared)
```

### ESC Instruction Format

8086 ESC instructions occupy opcodes D8-DF:

```
D8 - ESC 0 (FADD, FMUL, FCOM, FCOMP, FSUB, FSUBR, FDIV, FDIVR)
D9 - ESC 1 (FLD, FST, FSTP, FLDENV, FLDCW, FSTENV, FSTCW)
DA - ESC 2 (FIADD, FIMUL, FICOM, FICOMP, FISUB, FISUBR, FIDIV, FIDIVR)
DB - ESC 3 (FILD, FIST, FISTP, FLD extended real)
DC - ESC 4 (FADD, FMUL, FCOM, FCOMP, FSUB, FSUBR, FDIV, FDIVR - memory double)
DD - ESC 5 (FLD double, FST double, FSTP double, FRSTOR, FSAVE)
DE - ESC 6 (FIADD word, FIMUL word, FICOM word, etc.)
DF - ESC 7 (FILD word, FIST word, FISTP word, FBLD, FBSTP, FSTSW AX)
```

**Format**:
```
ESC opcode, ModR/M byte
11011xxx | mod xxx r/m
  ^^^^^      ^^^ ^^^
  D8-DF      reg  rm
```

**Examples**:
```
D9 C0    - FLD ST(0)        (push top of stack)
D8 C1    - FADD ST,ST(1)    (ST = ST + ST(1))
DD 06 00 00 - FLD [0000h]   (load double from memory)
DF E0    - FSTSW AX         (store status word to AX)
```

### CPU-FPU Handshake Protocol

**1. CPU Issues ESC Instruction**:
```
Cycle   Action
─────   ──────
1       CPU decodes ESC opcode (D8-DF)
2       CPU outputs address on bus (if memory operand)
3       CPU asserts ALE (address valid)
4       CPU waits for FPU to sample address
5       CPU asserts RD# or WR# (if memory access)
6       CPU checks BUSY signal
7       If BUSY LOW: Continue immediately
        If BUSY HIGH: Insert WAIT states
```

**2. FPU Executes Instruction**:
```
Cycle   Action
─────   ──────
1       FPU samples address/data during ALE
2       FPU decodes ESC instruction + ModR/M
3       FPU enqueues instruction if queue not full
4       FPU asserts BUSY if queue non-empty or executing
5       FPU performs operation (background)
6       FPU deasserts BUSY when complete
7       If exception: FPU asserts INT
```

**3. CPU Handles BUSY**:
```verilog
// Wait vs No-Wait Instructions
if (instruction_is_wait_type) begin
    // Instructions like FWAIT, FLD, FST
    // CPU MUST wait for BUSY to deassert
    while (fpu_busy) begin
        insert_wait_state();
    end
end else begin
    // Instructions like FADD, FMUL (no-wait forms)
    // CPU can continue immediately
    continue_execution();
end
```

**4. Exception Handling**:
```
FPU asserts INT when:
- Unmasked exception occurs
- INT stays asserted until FCLEX/FNCLEX

CPU response:
- NMI or IRQ depending on system
- Interrupt service routine executes
- ISR can read status with FSTSW
- ISR clears with FCLEX/FNCLEX
```

---

## Phase 5 Architecture Design

### System Block Diagram

```
┌──────────────────────────────────────────────────────────────┐
│ CPU-FPU Integration System (Phase 5)                         │
│                                                              │
│  ┌─────────────┐         ┌─────────────────┐               │
│  │ Mock CPU    │         │ CPU-FPU Bridge  │               │
│  │             │ ──Bus──>│                 │               │
│  │ - ESC inst  │ <─────  │ - ESC decoder   │               │
│  │ - Memory    │  BUSY   │ - Handshake     │               │
│  │ - I/O       │  INT    │ - Memory mux    │               │
│  └─────────────┘         └─────────────────┘               │
│                                   │                          │
│                                   v                          │
│                          ┌─────────────────┐                │
│                          │ FPU_Core_Async  │                │
│                          │                 │                │
│                          │ - Queue (3)     │                │
│                          │ - Execution     │                │
│                          │ - Exceptions    │                │
│                          └─────────────────┘                │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Memory Interface                                      │   │
│  │ - Operand fetch (FLD)                                │   │
│  │ - Operand store (FST)                                │   │
│  │ - Shared with CPU bus                                │   │
│  └─────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

### Module Hierarchy

```
CPU_FPU_System
├── Mock_CPU (test stimulus)
│   ├── ESC instruction generator
│   ├── Memory controller
│   └── BUSY/INT handler
├── CPU_FPU_Bridge
│   ├── ESC_Decoder (D8-DF detection)
│   ├── ModRM_Decoder (operand extraction)
│   ├── Bus_Controller (ALE, RD#, WR#)
│   └── Handshake_FSM (BUSY/INT protocol)
├── FPU_Core_Async (from Phase 4)
│   ├── FPU_Instruction_Queue
│   ├── FPU_Core
│   └── Queue control logic
└── Memory_Interface
    ├── Address decoder
    ├── Data buffer
    └── Wait state generator
```

---

## Module Specifications

### 1. ESC_Decoder Module

**Purpose**: Detect and decode ESC instructions (D8-DF)

**Interface**:
```verilog
module ESC_Decoder(
    input wire clk,
    input wire reset,

    // Instruction input
    input wire [7:0] opcode,         // From CPU
    input wire [7:0] modrm,          // ModR/M byte
    input wire valid,                // Opcode valid

    // Decoded outputs
    output reg is_esc,               // Is ESC instruction (D8-DF)
    output reg [2:0] esc_index,      // ESC index (0-7 for D8-DF)
    output reg [2:0] fpu_opcode,     // FPU opcode from ModR/M.reg
    output reg [2:0] stack_index,    // ST(i) from ModR/M.rm
    output reg has_memory_op,        // Memory operand present
    output reg [1:0] mod,            // ModR/M.mod field
    output reg [2:0] rm              // ModR/M.rm field
);
```

**Decoding Logic**:
```verilog
always @(posedge clk) begin
    is_esc <= (opcode[7:3] == 5'b11011);  // D8-DF
    esc_index <= opcode[2:0];               // 0-7
    fpu_opcode <= modrm[5:3];               // bits 5:3 = reg field
    stack_index <= modrm[2:0];              // bits 2:0 = r/m field
    has_memory_op <= (modrm[7:6] != 2'b11); // mod != 11 = memory
    mod <= modrm[7:6];
    rm <= modrm[2:0];
end
```

### 2. CPU_FPU_Bridge Module

**Purpose**: Interface between CPU bus and FPU

**Interface**:
```verilog
module CPU_FPU_Bridge(
    input wire clk,
    input wire reset,

    // CPU bus interface (8086-style)
    input wire [19:0] cpu_addr,
    inout wire [15:0] cpu_data,
    input wire cpu_ale,              // Address Latch Enable
    input wire cpu_rd_n,             // Read strobe (active low)
    input wire cpu_wr_n,             // Write strobe (active low)
    input wire cpu_m_io_n,           // Memory(0) vs I/O(1)

    // CPU control signals
    output wire cpu_busy,            // BUSY to CPU (active HIGH)
    output wire cpu_int,             // INT to CPU (active HIGH)

    // FPU interface
    output wire [7:0] fpu_instruction,
    output wire [2:0] fpu_stack_index,
    output wire fpu_execute,
    input wire fpu_ready,
    input wire fpu_error,

    output wire [79:0] fpu_data_in,
    input wire [79:0] fpu_data_out,

    output wire fpu_has_memory_op,
    output wire [1:0] fpu_operand_size,
    output wire fpu_is_integer,
    output wire fpu_is_bcd,

    input wire fpu_busy,
    input wire fpu_int,

    // Memory interface (for FPU operands)
    output wire [19:0] mem_addr,
    input wire [15:0] mem_data_in,
    output wire [15:0] mem_data_out,
    output wire mem_access,
    input wire mem_ack,
    output wire mem_wr_en
);
```

**Functionality**:
- Sample address/data on ALE edge
- Decode ESC instructions
- Format FPU instructions
- Handle memory operand fetch/store
- Manage BUSY/INT signals
- Coordinate CPU-FPU handshake

### 3. Mock_CPU Module

**Purpose**: Simulate CPU issuing ESC instructions (for testing)

**Interface**:
```verilog
module Mock_CPU(
    input wire clk,
    input wire reset,

    // CPU bus outputs
    output reg [19:0] cpu_addr,
    inout wire [15:0] cpu_data,
    output reg cpu_ale,
    output reg cpu_rd_n,
    output reg cpu_wr_n,
    output reg cpu_m_io_n,

    // CPU control inputs
    input wire cpu_busy,
    input wire cpu_int,

    // Test control
    input wire [7:0] test_opcode,
    input wire [7:0] test_modrm,
    input wire [19:0] test_addr,
    input wire [15:0] test_data,
    input wire test_execute,
    output reg test_complete
);
```

**Behavior**:
- Issue ESC instructions on command
- Respect BUSY signal (insert wait states)
- Handle INT signal (acknowledge exceptions)
- Simulate memory cycles for operands

### 4. Memory_Interface Module

**Purpose**: Provide memory access for FPU operands

**Interface**:
```verilog
module Memory_Interface(
    input wire clk,
    input wire reset,

    // FPU side
    input wire [19:0] fpu_addr,
    input wire [79:0] fpu_data_out,   // 80-bit from FPU
    output reg [79:0] fpu_data_in,    // 80-bit to FPU
    input wire fpu_access,
    input wire fpu_wr_en,
    input wire [1:0] fpu_size,        // 0=word, 1=dword, 2=qword, 3=tbyte
    output reg fpu_ack,

    // Memory bus
    output reg [19:0] mem_addr,
    input wire [15:0] mem_data_in,
    output reg [15:0] mem_data_out,
    output reg mem_access,
    input wire mem_ack,
    output reg mem_wr_en
);
```

**Functionality**:
- Convert 80-bit FPU transfers to 16-bit bus cycles
- Handle multi-cycle transfers for extended precision
- Generate proper sequencing for word/dword/qword/tbyte
- Wait state generation

---

## ESC Instruction Examples

### Example 1: FLD ST(0) - Load Top of Stack

**Assembly**: `FLD ST(0)`
**Encoding**: `D9 C0`
**Operation**: Push ST(0) (duplicate top of stack)

**CPU Actions**:
1. Fetch opcode D9
2. Fetch ModR/M C0
3. Decode as ESC instruction
4. No memory operand
5. Send to FPU
6. Continue (no-wait instruction)

**FPU Actions**:
1. Receive instruction D9 C0
2. Decode as FLD ST(0)
3. Push stack (ST(0) → ST(1), ST(0) = ST(0))
4. Complete in 1 cycle

### Example 2: FADD ST, ST(1) - Add Registers

**Assembly**: `FADD ST, ST(1)`
**Encoding**: `D8 C1`
**Operation**: ST(0) = ST(0) + ST(1)

**CPU Actions**:
1. Fetch opcode D8
2. Fetch ModR/M C1
3. Decode as ESC instruction
4. No memory operand
5. Send to FPU
6. Continue (no-wait instruction)

**FPU Actions**:
1. Receive instruction D8 C1
2. Enqueue instruction (async)
3. Execute addition (4 cycles)
4. ST(0) = ST(0) + ST(1)
5. BUSY HIGH during execution

### Example 3: FLD [1000h] - Load from Memory

**Assembly**: `FLD QWORD PTR [1000h]`
**Encoding**: `DD 06 00 10` (D9 for extended, DD for double)
**Operation**: Push memory qword onto stack

**CPU Actions**:
1. Fetch opcode DD
2. Fetch ModR/M 06
3. Decode as ESC instruction with memory operand
4. Fetch displacement 0010h
5. Calculate effective address = 1000h
6. Output address on bus
7. Assert ALE
8. **Wait for BUSY LOW** (wait instruction)
9. Assert RD#
10. Read memory (may take multiple cycles)
11. Send to FPU

**FPU Actions**:
1. Receive memory operand (64-bit double)
2. Convert to 80-bit extended
3. Push onto stack
4. BUSY HIGH during load and convert
5. BUSY LOW when complete

### Example 4: FWAIT - Wait for FPU

**Assembly**: `FWAIT`
**Encoding**: `9B`
**Operation**: Wait for FPU to complete

**CPU Actions**:
1. Fetch opcode 9B
2. Check FPU BUSY
3. While BUSY HIGH: insert wait states
4. When BUSY LOW: continue
5. Check INT: if HIGH, take interrupt

**FPU Actions**:
- No action (FWAIT is CPU instruction)
- BUSY reflects current FPU state

---

## Timing Diagrams

### ESC Instruction without Memory Operand

```
        ┌────┬────┬────┬────┬────┬────
CLK     ┘    └────┘    └────┘    └────
        ──────┬─────────────────────────
OPCODE  ──────┤ D8 ├───────────────────
        ──────┴─────┬───────────────────
MODRM   ────────────┤ C1 ├─────────────
        ──────┴─────┴─────────────────
ALE     ──┬─────────────────────────┬──
        ────────────────────────┬───────
ESC_DET ────────────────────────┴──────
        ────────────────────────┬───────
FPU_EXE ────────────────────────┴──────
        ────────────────────────────────
BUSY    ────────────────────────────────

CPU continues immediately (no-wait instruction)
```

### ESC Instruction with Memory Operand (FLD)

```
        ┌────┬────┬────┬────┬────┬────┬────┬────
CLK     ┘    └────┘    └────┘    └────┘    └────
        ──────┬──────────────────────────────────
OPCODE  ──────┤ DD ├─────────────────────────────
        ──────┴─────┬────────────────────────────
MODRM   ────────────┤ 06 ├───────────────────────
        ──────┴─────┴─────┬──────────────────────
ADDR    ────────────────────┤ 1000h ├────────────
        ──────────────┬─────┴────────────────────
ALE     ──────────────┴─────────────────────────
        ────────────────────────┬─────┬─────┬────
RD#     ────────────────────────┴─────┘     └────
        ────────────────────────────────────┬────
BUSY    ────────────────────────────────────┴────

CPU inserts wait states for memory access
FPU asserts BUSY during load/convert
```

### FWAIT with Busy FPU

```
        ┌────┬────┬────┬────┬────┬────┬────┬────
CLK     ┘    └────┘    └────┘    └────┘    └────
        ──────┬──────────────────────────────────
OPCODE  ──────┤ 9B ├─────────────────────────────
        ────────────────────────────────────┬────
BUSY    ────────────────────────────────────┴────
        ────────────────────────────┬────────────
WAIT    ────────────────────────────┴────────────

CPU halts until BUSY deasserts
Multiple wait states inserted
CPU resumes when BUSY LOW
```

---

## Test Strategy

### Test Levels

**1. Unit Tests** (Module-level):
- ESC_Decoder: All D8-DF opcodes
- Memory_Interface: Word/dword/qword/tbyte transfers
- Handshake_FSM: BUSY/INT protocol states

**2. Integration Tests** (System-level):
- CPU-FPU Bridge with mock CPU
- ESC instruction execution
- Memory operand fetch/store
- BUSY wait state insertion
- INT exception handling

**3. Compliance Tests** (8087 compatibility):
- ESC opcode coverage (D8-DF)
- Wait vs no-wait behavior
- Exception handling
- Stack operations
- Memory transfers

### Test Cases

**TC1**: ESC Instruction Decode
- Input: D8 C1 (FADD ST, ST(1))
- Expected: is_esc=1, esc_index=0, fpu_opcode=0, stack_index=1

**TC2**: Memory Operand Fetch (FLD qword)
- Input: DD 06 00 10 (FLD [1000h])
- Expected: Memory read at 1000h, 4 cycles, FPU receives 64-bit data

**TC3**: BUSY Handshake
- Input: Multiple instructions, queue fills
- Expected: BUSY asserts, CPU waits, BUSY deasserts, CPU continues

**TC4**: Exception Handling
- Input: Invalid operation (unmasked)
- Expected: INT asserts, CPU takes interrupt, ISR reads status

**TC5**: Asynchronous Operation
- Input: 3 instructions enqueued
- Expected: CPU continues, FPU executes in background, BUSY indicates status

---

## Implementation Plan

### Step 1: ESC Decoder (Simple)
- Create ESC_Decoder module
- Test with all D8-DF opcodes
- Verify ModR/M decoding

### Step 2: Mock CPU (Moderate)
- Create Mock_CPU test module
- ESC instruction generator
- Bus cycle simulator
- BUSY/INT handling

### Step 3: Memory Interface (Moderate)
- Create Memory_Interface module
- Multi-cycle transfer logic
- 80-bit to 16-bit conversion
- Test with different sizes

### Step 4: CPU-FPU Bridge (Complex)
- Create CPU_FPU_Bridge module
- Integrate ESC decoder
- Bus interface logic
- Handshake FSM
- Memory operand handling

### Step 5: System Integration (Complex)
- Integrate all modules
- Connect to FPU_Core_Async
- System-level testbench
- Comprehensive testing

### Step 6: Documentation (Moderate)
- Architecture documentation
- Integration guide
- Test results
- Future integration notes

---

## Success Criteria

Phase 5 is complete when:

1. ✅ ESC decoder recognizes all D8-DF opcodes
2. ✅ CPU-FPU bridge handles bus protocol correctly
3. ✅ BUSY signal properly controls CPU wait states
4. ✅ INT signal handled for exceptions
5. ✅ Memory operands fetched/stored correctly
6. ✅ Asynchronous operation demonstrated
7. ✅ All integration tests passing
8. ✅ 8087 protocol compliance verified
9. ✅ Documentation complete

---

## Future Work

### Full System Integration

When ready to integrate into real s80x86 CPU:

**1. Core.sv Modifications**:
- Add FPU signals to module interface
- Connect to CPU_FPU_Bridge

**2. InsnDecoder.sv Modifications**:
- Add ESC opcode detection (D8-DF)
- Forward to FPU path instead of invalid instruction

**3. Microcode.sv Modifications**:
- Add FPU instruction sequences
- Handle BUSY wait states
- Implement FWAIT microcode

**4. Top.sv Integration**:
- Instantiate CPU_FPU_Bridge
- Instantiate FPU_Core_Async
- Connect memory interfaces
- Route BUSY/INT to CPU

---

## Performance Estimates

### Resource Usage

**ESC_Decoder**: ~100 LUTs, 50 FFs
**CPU_FPU_Bridge**: ~500 LUTs, 200 FFs
**Memory_Interface**: ~300 LUTs, 150 FFs
**Total Added**: ~900 LUTs, 400 FFs

**With FPU_Core_Async**: ~1500 LUTs, 700 FFs total

### Timing

**Critical Paths**:
- ESC decode: ~5 ns
- Bus handshake: ~10 ns
- Memory interface: ~8 ns
- Should meet 100 MHz with margin

---

## References

- Intel 8086 Family User's Manual
- Intel 8087 Data Sheet (1980)
- 8086/8087 Application Notes
- Phases 1-4 Documentation
- s80x86 CPU Core Documentation

---

**Phase 5 Architecture**: APPROVED
**Implementation**: READY TO BEGIN
**Complexity**: VERY HIGH (system integration)
**Estimated Time**: 3-5 days

**Note**: This is a reference implementation demonstrating CPU-FPU integration concepts. Full integration into the s80x86 CPU is future work requiring extensive CPU modifications.
