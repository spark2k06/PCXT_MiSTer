# Phase 8: Authentic 8087 Coprocessor Interface Architecture

**Date**: 2025-11-10
**Status**: 🔄 IN PROGRESS - Dedicated Coprocessor Ports

---

## Executive Summary

Phase 8 replaces the memory-mapped interface (0xFFE0-0xFFFF) with dedicated coprocessor ports, creating an authentic 8086+8087 architecture. This approach:

- ✅ **More Authentic**: Matches original 8087 coprocessor signaling
- ✅ **Better Performance**: Direct signals instead of memory cycles
- ✅ **Cleaner Design**: Explicit CPU-FPU communication
- ✅ **Simpler Microcode**: No memory address management needed

---

## Original 8087 Architecture

The Intel 8087 used a coprocessor bus interface with these key signals:

### 1. Instruction Stream Monitoring
- **8087 watches CPU bus**: FPU monitors address/data lines
- **ESC Detection**: FPU latches ESC opcodes (D8-DF)
- **ModR/M Capture**: FPU reads ModR/M byte from bus
- **Parallel Operation**: CPU and FPU work simultaneously

### 2. Control Signals
- **BUSY**: FPU asserts when executing, CPU polls via TEST pin
- **RQ/GT (Request/Grant)**: FPU requests bus for memory operands
- **ERROR**: FPU signals exceptions
- **INT**: Interrupt request for unmasked exceptions

### 3. Synchronization
- **WAIT Instruction**: CPU polls TEST pin (connected to BUSY)
- **Bus Arbitration**: RQ/GT protocol for memory access
- **Queue Status (QS0, QS1)**: CPU tells FPU about instruction fetch

---

## Phase 8 Simplified Coprocessor Interface

For s80x86 integration, we implement a simplified but authentic interface:

### Dedicated Port Signals

```verilog
// CPU to FPU - Instruction Dispatch
output wire [7:0]  fpu_opcode,         // ESC opcode (D8-DF)
output wire [7:0]  fpu_modrm,          // ModR/M byte
output wire        fpu_cmd_valid,      // Instruction valid pulse
output wire [19:0] fpu_mem_addr,       // Effective address for memory operands

// FPU to CPU - Status
input  wire        fpu_busy,           // FPU executing instruction
input  wire        fpu_error,          // Unmasked exception occurred
input  wire        fpu_int_request,    // Interrupt request (INT 16)

// FPU Memory Bus (shared with CPU)
input  wire        fpu_bus_request,    // FPU needs memory bus
output wire        fpu_bus_grant,      // CPU grants bus to FPU
```

### Key Differences from Memory-Mapped

| Aspect | Phase 7 (Memory-Mapped) | Phase 8 (Dedicated Ports) |
|--------|-------------------------|---------------------------|
| **Command Dispatch** | Write to 0xFFE0-0xFFE1 | Assert fpu_cmd_valid with opcode/modrm |
| **Status Check** | Read from 0xFFE2 | Sample fpu_busy signal |
| **Microcode Cycles** | ~8 cycles (2 writes + 1 read) | ~3 cycles (set signals) |
| **Performance** | Good | Excellent |
| **Authenticity** | Low (8087 used ports) | High (matches 8087) |

---

## Architecture Diagrams

### Phase 8 System Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                    s80x86 CPU Core                              │
│                                                                 │
│  ┌──────────────────┐                                          │
│  │ Microcode Unit   │                                          │
│  │  ESC Handler     │─────┐                                    │
│  │  WAIT Handler    │     │                                    │
│  └──────────────────┘     │                                    │
│                            ▼                                    │
│  ┌─────────────────────────────────────────┐                   │
│  │  CPU Control Logic                      │                   │
│  │  - ESC Detection (D8-DF)                │                   │
│  │  - ModR/M Extraction                    │                   │
│  │  - EA Calculation                       │                   │
│  └────┬────────────────────────────────────┘                   │
│       │                                                         │
│       │ Dedicated Coprocessor Ports                            │
│       │                                                         │
└───────┼─────────────────────────────────────────────────────────┘
        │
        │ fpu_opcode[7:0] ──────────────────────────┐
        │ fpu_modrm[7:0] ───────────────────────────┤
        │ fpu_cmd_valid ────────────────────────────┤
        │ fpu_mem_addr[19:0] ───────────────────────┤
        │                                            │
        │ fpu_busy ◄────────────────────────────────┤
        │ fpu_error ◄───────────────────────────────┤
        │ fpu_int_request ◄─────────────────────────┤
        │                                            │
        ▼                                            ▼
┌────────────────────────────────────────────────────────────────┐
│              CPU_FPU_Coprocessor_Bridge (NEW)                  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Instruction Latch                                       │  │
│  │  - Capture opcode/modrm on cmd_valid                    │  │
│  │  - Hold until FPU acknowledges                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Status Aggregation                                      │  │
│  │  - Combine FPU busy/error/int signals                   │  │
│  │  - Generate TEST pin output                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Bus Arbiter                                             │  │
│  │  - Grant memory bus to FPU when requested               │  │
│  │  - CPU has priority                                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└────────────────────┬───────────────────────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────────────────────┐
│              FPU_System_Integration (Phase 5)                  │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ ESC Decoder  │  │   Memory     │  │  FPU Core    │         │
│  │ (D8-DF)      │──│  Interface   │──│  (Phase 3)   │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                 │
│  Signals: cpu_opcode, cpu_modrm, cpu_instruction_valid         │
│          fpu_busy, fpu_error, fpu_int                         │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
                     │
                     ▼
              System Memory Bus
```

---

## Detailed Signal Descriptions

### CPU to FPU Signals

#### 1. `fpu_opcode[7:0]`
- **Purpose**: ESC instruction opcode
- **Values**: 0xD8-0xDF (ESC range)
- **Timing**: Valid when `fpu_cmd_valid` asserted
- **Example**: 0xD8 for FADD

#### 2. `fpu_modrm[7:0]`
- **Purpose**: ModR/M byte specifying operation details
- **Format**: `[mod(2) | reg/op(3) | r/m(3)]`
- **Timing**: Valid when `fpu_cmd_valid` asserted
- **Example**: 0xC1 for ST(1) operand

#### 3. `fpu_cmd_valid`
- **Purpose**: Instruction dispatch strobe
- **Type**: Single-cycle pulse
- **Timing**: Asserted for 1 clock when CPU sends instruction
- **Protocol**: FPU latches opcode/modrm on rising edge

#### 4. `fpu_mem_addr[19:0]`
- **Purpose**: Effective address for memory operands
- **Valid When**: Memory operand detected (mod != 11)
- **Timing**: Stable before `fpu_cmd_valid`
- **Usage**: FPU uses for memory fetches/stores

### FPU to CPU Signals

#### 5. `fpu_busy`
- **Purpose**: FPU execution status
- **Values**: 1 = busy, 0 = ready
- **Connected To**: CPU TEST pin logic
- **WAIT Instruction**: Polls this signal
- **Timing**: Async, can change any cycle

#### 6. `fpu_error`
- **Purpose**: Unmasked exception flag
- **Values**: 1 = error, 0 = normal
- **Usage**: CPU can check after FPU completion
- **Cleared**: When CPU reads status

#### 7. `fpu_int_request`
- **Purpose**: Interrupt request (INT 16)
- **Type**: Level-triggered
- **Handler**: CPU INT 16 vector
- **Cleared**: When CPU acknowledges

### Bus Arbitration Signals

#### 8. `fpu_bus_request`
- **Purpose**: FPU requests memory bus
- **When**: FPU needs to fetch/store memory operand
- **Protocol**: Asserted until granted

#### 9. `fpu_bus_grant`
- **Purpose**: CPU grants bus to FPU
- **Timing**: CPU yields bus when idle
- **Duration**: Until FPU completes transfer

---

## Microcode Changes

### Phase 7 ESC Microcode (Memory-Mapped)

```
do_esc:
    // Write opcode to 0xFFE0
    b_sel IMMEDIATE, immediate 0xFFE0, alu_op SELB, mar_write;
    a_sel OPCODE, alu_op SELA, mdr_write;
    mem_write;                          // 3 cycles

    // Write ModR/M to 0xFFE1
    b_sel IMMEDIATE, immediate 0xFFE1, alu_op SELB, mar_write;
    a_sel MODRM, alu_op SELA, mdr_write;
    mem_write;                          // 3 cycles

    // Poll BUSY at 0xFFE2
do_esc_poll:
    b_sel IMMEDIATE, immediate 0xFFE2, alu_op SELB, mar_write;
    mem_read, tmp_wr_en;                // 2 cycles
    a_sel TMP, b_sel 0x8000, alu_op AND;
    jnz do_esc_poll;

    // Total: ~8+ cycles
```

### Phase 8 ESC Microcode (Dedicated Ports)

```
do_esc:
    // Send instruction to FPU via dedicated ports
    fpu_opcode_write, fpu_opcode_sel OPCODE;      // 1 cycle
    fpu_modrm_write, fpu_modrm_sel MODRM;         // 1 cycle
    fpu_cmd_valid_pulse;                           // 1 cycle

    // If memory operand, provide EA
    if (mod != 11)
        fpu_mem_addr_write, fpu_mem_addr_sel EA;  // 1 cycle

    // Poll BUSY via dedicated signal
do_esc_poll:
    test_fpu_busy;                                 // 1 cycle
    jnz do_esc_poll;

    // Check error
    test_fpu_error;
    jnz do_fpu_exception;

    // Total: ~3-5 cycles (vs 8+ in Phase 7)
```

**Performance Improvement**: 40-60% faster ESC instruction handling

---

## Implementation Components

### 1. CPU_FPU_Coprocessor_Bridge.v (New)

Replaces `CPU_FPU_Bridge.v` with simplified design:

```verilog
module CPU_FPU_Coprocessor_Bridge(
    input wire clk,
    input wire reset,

    // CPU Side - Dedicated Coprocessor Ports
    input wire [7:0] cpu_fpu_opcode,
    input wire [7:0] cpu_fpu_modrm,
    input wire cpu_fpu_cmd_valid,
    input wire [19:0] cpu_fpu_mem_addr,
    output wire cpu_fpu_busy,
    output wire cpu_fpu_error,
    output wire cpu_fpu_int,

    // FPU Side
    output reg [7:0] fpu_opcode,
    output reg [7:0] fpu_modrm,
    output reg fpu_instruction_valid,
    output reg [19:0] fpu_mem_addr,
    input wire fpu_busy,
    input wire fpu_error,
    input wire fpu_int_request,

    // Bus Arbitration
    input wire fpu_bus_request,
    output wire fpu_bus_grant
);
```

**Key Features**:
- Simple pass-through for most signals
- Instruction latching on `cmd_valid` pulse
- Bus arbitration logic
- No memory decode, no address checking

### 2. Updated CPU Core Integration

Add coprocessor port registers to Core.sv:

```verilog
// FPU coprocessor interface (new registers)
reg [7:0] fpu_opcode_reg;
reg [7:0] fpu_modrm_reg;
reg fpu_cmd_valid_reg;
reg [19:0] fpu_mem_addr_reg;
wire fpu_busy_signal;
wire fpu_error_signal;
wire fpu_int_signal;
```

Microcode can directly control these registers:
- `fpu_opcode_write` signal sets `fpu_opcode_reg`
- `fpu_cmd_valid_pulse` generates 1-cycle pulse
- `test_fpu_busy` reads `fpu_busy_signal` for conditional jump

### 3. Microcode Additions

Add new microcode control signals in `microassembler`:

```c
// New FPU control signals
#define FPU_OPCODE_WRITE    (1 << 24)
#define FPU_MODRM_WRITE     (1 << 25)
#define FPU_CMD_VALID       (1 << 26)
#define FPU_MEM_ADDR_WRITE  (1 << 27)
#define TEST_FPU_BUSY       (1 << 28)
#define TEST_FPU_ERROR      (1 << 29)
```

New microcode operations:
```
fpu_opcode_write, fpu_opcode_sel OPCODE;
fpu_modrm_write, fpu_modrm_sel MODRM;
fpu_cmd_valid_pulse;
test_fpu_busy;
```

---

## Compatibility Analysis

### With Original 8087

| Feature | Real 8087 | Phase 8 Implementation | Match |
|---------|-----------|------------------------|-------|
| **Instruction Monitoring** | Watches CPU bus | Explicit opcode/modrm ports | ⚠️ Simplified |
| **BUSY Signal** | Via TEST pin | Via dedicated wire | ✅ Yes |
| **Queue Status** | QS0, QS1 signals | Not needed (explicit dispatch) | ⚠️ Simplified |
| **Bus Request/Grant** | RQ/GT protocol | Simplified arbitration | ⚠️ Simplified |
| **INT 16** | Yes | Yes | ✅ Yes |
| **Parallel Operation** | Yes | Yes | ✅ Yes |
| **Memory Operands** | Via bus | Via bus + EA register | ✅ Yes |

**Compatibility Rating**: High (90%)
- Core coprocessor concept preserved
- Simplified for FPGA implementation
- All essential features present

### With Existing Tests

All Phase 6 tests remain compatible:
- Tests use abstract instruction dispatch
- No dependency on memory-mapped addresses
- Only testbench changes needed (wire connections)

---

## Performance Comparison

### ESC Instruction Latency

| Phase | Command Dispatch | BUSY Poll | Total Cycles |
|-------|------------------|-----------|--------------|
| Phase 7 (Memory) | 6 cycles (2 writes) | 2 cycles/poll | 8+ |
| **Phase 8 (Ports)** | **3 cycles (set regs)** | **1 cycle/poll** | **4+** |
| **Improvement** | **50%** | **50%** | **~50%** |

### WAIT Instruction Performance

| Phase | BUSY Poll Cycle | Typical Latency |
|-------|-----------------|-----------------|
| Phase 7 | 2 cycles | ~6 cycles |
| **Phase 8** | **1 cycle** | **~3 cycles** |
| **Improvement** | **50%** | **~50%** |

### System Throughput

Estimated instruction throughput @ 1MHz:

| Metric | Phase 7 | Phase 8 | Improvement |
|--------|---------|---------|-------------|
| ESC/sec | ~55,000 | ~85,000 | +54% |
| Mixed Code | ~70,000 | ~95,000 | +36% |
| FPU Utilization | ~60% | ~75% | +25% |

---

## Migration Path

### From Phase 7 to Phase 8

1. **Remove Memory-Mapped Interface**
   - Delete address range 0xFFE0-0xFFFF handling
   - Remove `CPU_FPU_Bridge.v` (Phase 7 version)

2. **Add Coprocessor Ports to Core.sv**
   - Add FPU port registers
   - Connect to microcode control signals

3. **Create CPU_FPU_Coprocessor_Bridge.v**
   - Simple pass-through bridge
   - Bus arbitration logic

4. **Update Microcode**
   - Replace memory operations with port operations
   - Use dedicated FPU control signals

5. **Update Tests**
   - Change port connections in testbench
   - No test logic changes needed

---

## Benefits Over Phase 7

### 1. Performance
- ✅ **50% faster** ESC dispatch
- ✅ **50% faster** BUSY polling
- ✅ **~40% higher** system throughput

### 2. Simplicity
- ✅ **No address decoding** needed
- ✅ **Simpler microcode** (fewer cycles)
- ✅ **Direct signal paths** (less logic)

### 3. Authenticity
- ✅ **More like real 8087** coprocessor interface
- ✅ **Dedicated TEST pin** logic
- ✅ **Bus arbitration** protocol

### 4. Hardware Efficiency
- ✅ **Less FPGA resources** (no memory decoder)
- ✅ **Faster timing** (shorter critical path)
- ✅ **Lower power** (fewer memory cycles)

---

## Testing Strategy

### Unit Tests

1. **Port Communication**
   - Write opcode/modrm to ports
   - Verify FPU receives instruction
   - Check cmd_valid pulse generation

2. **BUSY Signal**
   - Assert fpu_busy
   - Verify CPU waits
   - Check WAIT instruction polls correctly

3. **Bus Arbitration**
   - FPU requests bus
   - CPU grants when idle
   - Verify memory access

### Integration Tests

Reuse all Phase 6 tests (27 tests):
- Only testbench wiring changes
- Test logic remains identical
- Expected: **27/27 passing**

---

## Success Criteria

✅ All Phase 6 tests passing (27/27)
✅ ESC instruction dispatch < 5 cycles
✅ WAIT instruction overhead < 4 cycles
✅ No memory-mapped addresses used
✅ Dedicated coprocessor ports functional
✅ Performance improvement > 40%
✅ More authentic to 8087 architecture

---

## Timeline

- **Step 1**: CPU_FPU_Coprocessor_Bridge.v (1 hour)
- **Step 2**: Core.sv port integration (1 hour)
- **Step 3**: Microcode updates (1 hour)
- **Step 4**: Update CPU_FPU_Integrated_System.v (1 hour)
- **Step 5**: Test and validate (1 hour)
- **Step 6**: Documentation (1 hour)

**Total**: 6 hours

---

## Conclusion

Phase 8 transforms the integration from a memory-mapped design to an authentic coprocessor architecture, matching the original 8086+8087 philosophy while improving performance by 40-50%.

This approach:
- ✅ More authentic to historical 8087
- ✅ Better performance
- ✅ Simpler design
- ✅ Maintains all test compatibility

**Ready for implementation.**

---

**Status**: Architecture complete, ready for implementation
**Next**: Implement CPU_FPU_Coprocessor_Bridge.v
