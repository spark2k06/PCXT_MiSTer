# Intel 8087 Architecture Research
## Real Hardware Behavior Analysis

**Date**: 2025-11-10
**Purpose**: Guide Phase 1 implementation with accurate 8087 behavior

---

## 1. Real 8087 Architecture

### 1.1 Actual Hardware Structure

The Intel 8087 consists of two main units operating in parallel:

```
┌─────────────────────────────────────────────┐
│              Intel 8087 FPU                  │
├──────────────────────┬──────────────────────┤
│   Control Unit (CU)  │  Numeric Execution   │
│                      │   Unit (NEU)         │
│  - Instruction queue │  - Arithmetic unit   │
│  - Bus interface     │  - Register stack    │
│  - Address calc      │  - Constant ROM      │
│  - Exception logic   │  - Exponent unit     │
└──────────────────────┴──────────────────────┘
         ↓                      ↓
    [Handles I/O]         [Does math]
```

### 1.2 Control Unit (CU)

**Responsibilities**:
- Interface with 8086/8088 CPU
- Instruction queue (up to 3 instructions)
- Address calculation for memory operands
- Exception detection and signaling
- Bus arbitration

**Key Behavior**:
- CU can fetch and decode while NEU executes
- CU handles all ESC instruction decoding
- CU performs address calculations in parallel

### 1.3 Numeric Execution Unit (NEU)

**Responsibilities**:
- 80-bit register stack (8 registers)
- Arithmetic operations
- Transcendental functions
- Data conversions

**Key Behavior**:
- NEU executes one instruction at a time
- Can work while CU fetches next instruction
- Signals completion back to CU

---

## 2. Instruction Pipeline Depth

### 2.1 Actual 8087 Pipeline Stages

The 8087 has **3 instructions** in flight simultaneously:

```
Stage 1 (CU):  Instruction Fetch & Decode
Stage 2 (CU):  Operand Address Calculation
Stage 3 (NEU): Execution
```

**Example Timeline**:
```
Cycle 1:  [FADD decode] [nothing]      [nothing]
Cycle 2:  [FSUB decode] [FADD addr]    [nothing]
Cycle 3:  [FMUL decode] [FSUB addr]    [FADD execute]
Cycle 4:  [FDIV decode] [FMUL addr]    [FSUB execute]
```

### 2.2 Instruction Queue Depth

**Real 8087**: Can have up to 3 instructions in various stages:
- 1 being decoded (CU)
- 1 with address calculated (CU)
- 1 executing (NEU)

**Implementation Decision**:
Use a **3-entry instruction queue** to match real 8087 behavior, not 4 as initially planned.

---

## 3. Signal Timing

### 3.1 BUSY Signal (8087 has BUSY, not BUSY#)

**Pin Name**: BUSY (active HIGH on 8087, not active low!)
**Behavior**:
- Asserted when NEU is executing
- CU can still fetch/decode while BUSY is high
- Used by CPU for FWAIT implementation

**Timing**:
```
FINIT    ____/‾‾‾‾‾\____
BUSY     _____/‾‾‾‾‾‾‾‾‾\___
         ^     ^         ^
      start  execution  end
```

**Correction**: The 8087 uses active-HIGH BUSY, not active-low BUSY#.

### 3.2 Exception Signaling (INT vs FERR#)

**8087 (original)**:
- Uses **INT** signal (interrupt request)
- Connected to CPU's interrupt controller
- Generates interrupt on unmasked exception
- No FERR# signal

**80287/80387**:
- Added **ERROR#** (later FERR#) signal
- Removed INT signal (used IRQ13 instead)
- FERR# is active LOW

**Implementation Decision**:
For 8087 compatibility, use **INT** output (active high interrupt request), not FERR#.

---

## 4. Synchronization Behavior

### 4.1 Wait vs No-Wait Instructions

**Real 8087 Behavior**:

**Wait Instructions** (e.g., FINIT, FSAVE, FSTSW):
1. CPU issues ESC opcode
2. 8087 checks for pending exceptions
3. If exception: asserts INT, 8087 stalls
4. CPU handles interrupt
5. If no exception: 8087 executes instruction
6. 8087 waits for instruction completion before accepting next

**No-Wait Instructions** (e.g., FNINIT, FNSAVE, FNSTSW):
1. CPU issues ESC opcode
2. 8087 does NOT check for exceptions
3. 8087 starts execution immediately
4. CPU continues (doesn't wait)
5. Next ESC instruction can be queued

### 4.2 FWAIT Instruction

**CPU Behavior**:
```assembly
FWAIT  ; 9B opcode
```

**What happens**:
1. CPU executes 9B (FWAIT) opcode
2. CPU checks 8087 BUSY signal
3. If BUSY=1: CPU stalls until BUSY=0
4. If BUSY=0: CPU checks TEST# pin (exception check)
5. If TEST#=0 (exception): CPU vectors to interrupt
6. If no exception: CPU continues

**Key Insight**: FWAIT is a **CPU instruction**, not an FPU instruction!

### 4.3 Memory Operations

**Real 8087**:
- Memory reads: CU calculates address, fetches data
- Memory writes: NEU completes, CU writes result
- CPU and 8087 share the bus (need arbitration)

**Synchronization**:
- Memory operations cause bus cycles
- CPU must grant bus to 8087
- Natural synchronization through bus arbitration

---

## 5. Exception Priority

### 5.1 Exception Types (in priority order)

| Priority | Exception | Bit | Description |
|----------|-----------|-----|-------------|
| 1 (highest) | Invalid Operation | 0 | Invalid operand or operation |
| 2 | Denormalized Operand | 1 | Denormal detected |
| 3 | Zero Divide | 2 | Division by zero |
| 4 | Overflow | 3 | Result too large |
| 5 | Underflow | 4 | Result too small |
| 6 (lowest) | Precision | 5 | Result not exact |

**Behavior**:
- Only highest priority exception is reported
- Multiple exceptions: highest priority wins
- Status word shows all exceptions, but interrupt uses highest

---

## 6. Queue Flush Conditions

### 6.1 When 8087 Flushes Pipeline

**Must flush on**:
1. **FINIT / FNINIT**: Complete reset
2. **FLDCW**: Control word change affects pending operations
3. **Exceptions**: Unmasked exception stops pipeline
4. **FWAIT with exception**: Must complete before continuing

**Can continue on**:
1. **FNSTSW**: Read status doesn't affect pipeline
2. **FNSTCW**: Read control doesn't affect pipeline
3. **Arithmetic operations**: Can queue normally

---

## 7. Implementation Guidelines for Phase 1

### 7.1 Instruction Queue Design

**Based on real 8087**:
```verilog
module FPU_Instruction_Queue_8087 #(
    parameter QUEUE_DEPTH = 3  // 3 stages like real 8087
)(
    input wire clk,
    input wire reset,

    // Enqueue (from CPU interface)
    input wire enqueue,
    input wire [7:0] instruction,
    input wire [2:0] stack_index,
    input wire has_memory_op,
    input wire [79:0] data_in,
    output wire queue_full,

    // Dequeue (to NEU)
    output wire queue_empty,
    output reg [7:0] current_instruction,
    output reg [2:0] current_stack_index,
    output reg current_has_memory_op,
    output reg [79:0] current_data_in,
    input wire dequeue,

    // Flush (on FINIT, FLDCW, exception)
    input wire flush_queue
);
```

### 7.2 Control Unit vs NEU Split

**CU Responsibilities** (lightweight, fast):
- Decode instruction
- Check for flush conditions
- Calculate memory addresses
- Queue management

**NEU Responsibilities** (heavyweight, slow):
- Arithmetic operations
- Stack access
- Exception detection
- Result writeback

### 7.3 BUSY Signal Generation

```verilog
// BUSY is active HIGH (not active low!)
// BUSY = 1 when NEU is executing
reg neu_executing;
assign busy = neu_executing;  // Active HIGH like real 8087

always @(posedge clk) begin
    if (reset) begin
        neu_executing <= 1'b0;
    end else begin
        // Set when NEU starts operation
        if (neu_start) begin
            neu_executing <= 1'b1;
        end

        // Clear when operation completes
        if (neu_done) begin
            neu_executing <= 1'b0;
        end
    end
end
```

### 7.4 Exception Signaling (INT not FERR#)

```verilog
// Use INT signal (active HIGH) like real 8087
// Not FERR# (that's 80287+)
reg interrupt_request;
assign int_req = interrupt_request;  // Active HIGH

always @(posedge clk) begin
    if (reset) begin
        interrupt_request <= 1'b0;
    end else begin
        // Set on unmasked exception
        if (unmasked_exception && !interrupt_request) begin
            interrupt_request <= 1'b1;
        end

        // Clear on acknowledgment (FCLEX)
        if (exception_clear) begin
            interrupt_request <= 1'b0;
        end
    end
end
```

---

## 8. Key Differences: Plan vs Reality

| Aspect | Initial Plan | Real 8087 | Decision |
|--------|--------------|-----------|----------|
| Queue depth | 4 entries | 3 stages | **Use 3** |
| BUSY signal | Active LOW (BUSY#) | Active HIGH (BUSY) | **Active HIGH** |
| Exception signal | FERR# (80387) | INT (8087) | **Use INT** |
| Pipeline model | Simple FIFO | CU + NEU split | **Split CU/NEU** |
| Signal names | Modern (FERR#, BUSY#) | Period (INT, BUSY) | **Period correct** |

---

## 9. Phase 1 Revised Goals

### 9.1 What to Implement

✅ **Control Unit (CU)**:
- 3-stage instruction queue
- Instruction decode logic
- Queue management (enqueue/dequeue/flush)
- BUSY signal generation (active HIGH)

✅ **NEU Interface**:
- Start signal to NEU
- Done signal from NEU
- Execution state tracking

✅ **Exception Handler**:
- INT signal generation (active HIGH)
- Exception pending flag
- Unmasked exception detection

### 9.2 What to Defer

❌ **Phase 2**:
- Full exception acknowledgment
- FWAIT implementation
- Exception state machine

❌ **Phase 3**:
- Memory synchronization
- Bus arbitration
- Address calculation

---

## 10. Design Decisions Summary

### Final Decisions for Phase 1:

1. **Queue Depth**: 3 entries (matches 8087 CU pipeline)
2. **BUSY Signal**: Active HIGH, named `busy` not `busy_n`
3. **Exception Signal**: INT (active HIGH), not FERR#
4. **Architecture**: Split CU and NEU conceptually
5. **Pipeline Model**: Fetch → Decode → Execute (3 stages)
6. **Flush Logic**: FINIT, FLDCW, exceptions flush queue
7. **Signal Naming**: Period-accurate (8087 names)

---

## References

- Intel 8087 Data Sheet (1980)
- Intel 8087 Application Notes (AP-113)
- "The 8087 Primer" by Stephen Morse
- 8086/8088 User's Manual (8087 chapter)

---

## Next Step

Implement the revised Phase 1 with these 8087-accurate design decisions.
