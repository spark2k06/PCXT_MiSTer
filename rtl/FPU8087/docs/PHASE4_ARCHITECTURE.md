# Phase 4: Instruction Queue Integration Architecture

**Date**: 2025-11-10
**Status**: 🔧 IN PROGRESS

---

## Overview

Phase 4 integrates the FPU_Instruction_Queue (from Phase 1) into FPU_Core.v to enable asynchronous CPU-FPU operation. This allows the CPU to continue executing while the FPU processes queued instructions.

---

## Current Architecture (Synchronous)

```
CPU ──execute──> FPU_Core (state machine)
    <──ready────
    ──data_in──>
    <──data_out─

Flow:
1. CPU asserts execute
2. FPU_Core processes instruction (blocks CPU)
3. FPU_Core asserts ready when done
4. Repeat
```

**Limitation**: CPU waits for FPU to complete each instruction

---

## Target Architecture (Asynchronous with Queue)

```
CPU ──execute──> Instruction_Queue ──dequeue──> FPU_Core (execution)
    <──ready────                     <──done────
    ──data_in──>
    <──data_out─
    <──BUSY─────

Flow:
1. CPU enqueues instruction (if queue not full)
2. CPU continues immediately (ready stays HIGH)
3. FPU dequeues and executes when idle
4. CPU can enqueue more (up to 3 instructions)
5. BUSY indicates FPU has pending work
```

**Benefit**: CPU doesn't wait for FPU execution

---

## Integration Strategy

### Option A: Queue at Interface (Selected)

Queue sits between CPU and existing FPU_Core state machine:

```
┌─────────────────────────────────────────────────────┐
│ FPU_Core Module                                      │
│                                                      │
│  CPU Interface                                       │
│       ↓                                              │
│  Instruction Queue (3 entries)                       │
│       ↓                                              │
│  Existing State Machine                              │
│  (STATE_IDLE, STATE_DECODE, STATE_EXECUTE, etc.)    │
│       ↓                                              │
│  Arithmetic Units                                    │
│       ↓                                              │
│  Exception Handler                                   │
└─────────────────────────────────────────────────────┘
```

**Advantages**:
- Minimal changes to existing state machine
- Queue is transparent to execution logic
- Easy to debug and test
- Maintains existing timing

**Implementation**:
- Add queue between execute input and state machine
- Modify state machine to dequeue when idle
- Generate BUSY from queue status

### Option B: Queue After Decode (Rejected)

Queue would sit after instruction decode, requiring major state machine restructuring.

**Rejected because**:
- Too invasive
- Complex control flow
- Hard to test
- Breaks existing structure

---

## Detailed Design

### 1. Module Interface Changes

Add BUSY signal:

```verilog
module FPU_Core(
    // ... existing signals ...

    // Asynchronous operation signals
    output wire busy             // BUSY (active HIGH, 8087-style)
);
```

**BUSY Signal**:
- Active HIGH (8087 convention, not BUSY# active low)
- Asserts when: queue non-empty OR FPU executing
- Deasserts when: queue empty AND FPU idle

### 2. Instruction Queue Instantiation

```verilog
// Instruction queue signals
reg queue_enqueue;
reg queue_dequeue;
reg queue_flush;
wire queue_full;
wire queue_empty;
wire [1:0] queue_count;
wire [7:0] queued_instruction;
wire [2:0] queued_stack_index;
wire queued_has_memory_op;
wire [1:0] queued_operand_size;
wire queued_is_integer;
wire queued_is_bcd;
wire [79:0] queued_data;

FPU_Instruction_Queue instruction_queue (
    .clk(clk),
    .reset(reset),

    // Enqueue interface (from CPU)
    .enqueue(queue_enqueue),
    .instruction_in(instruction),
    .stack_index_in(stack_index),
    .has_memory_op_in(has_memory_op),
    .operand_size_in(operand_size),
    .is_integer_in(is_integer),
    .is_bcd_in(is_bcd),
    .data_in(data_in),
    .queue_full(queue_full),

    // Dequeue interface (to execution)
    .dequeue(queue_dequeue),
    .queue_empty(queue_empty),
    .instruction_out(queued_instruction),
    .stack_index_out(queued_stack_index),
    .has_memory_op_out(queued_has_memory_op),
    .operand_size_out(queued_operand_size),
    .is_integer_out(queued_is_integer),
    .is_bcd_out(queued_is_bcd),
    .data_out(queued_data),

    // Flush interface
    .flush_queue(queue_flush),
    .queue_count(queue_count)
);
```

### 3. Control Logic

#### Enqueue Logic (CPU → Queue)

```verilog
always @(posedge clk) begin
    if (reset) begin
        queue_enqueue <= 1'b0;
        ready <= 1'b1;
    end else begin
        // Default
        queue_enqueue <= 1'b0;

        // CPU wants to execute instruction
        if (execute && !queue_full) begin
            queue_enqueue <= 1'b1;
            ready <= 1'b1;  // Immediately ready for next
        end else if (execute && queue_full) begin
            ready <= 1'b0;  // Must wait, queue full
        end else begin
            ready <= 1'b1;  // Ready to accept
        end
    end
end
```

#### Dequeue Logic (Queue → Execution)

```verilog
always @(posedge clk) begin
    if (reset) begin
        queue_dequeue <= 1'b0;
    end else begin
        // Default
        queue_dequeue <= 1'b0;

        // State machine is idle and queue has instructions
        if (state == STATE_IDLE && !queue_empty && !fpu_busy) begin
            queue_dequeue <= 1'b1;
            // Load instruction from queue
            current_inst <= queued_instruction;
            current_index <= queued_stack_index;
            // Start execution
            state <= STATE_DECODE;
        end
    end
end
```

#### BUSY Signal Generation

```verilog
assign busy = !queue_empty || fpu_busy || (state != STATE_IDLE);
```

**BUSY is HIGH when**:
- Queue has pending instructions, OR
- FPU is currently executing (state != IDLE), OR
- fpu_busy flag is set (Level 2 tracking)

### 4. Queue Flush Logic

Flush queue on:
1. **FINIT/FNINIT**: Complete FPU initialization
2. **FLDCW**: Control word change may affect behavior
3. **Exceptions**: Unmasked exception requires pipeline flush

```verilog
always @(posedge clk) begin
    if (reset) begin
        queue_flush <= 1'b0;
    end else begin
        // Default
        queue_flush <= 1'b0;

        // Flush on FINIT/FNINIT
        if (current_inst == INST_FINIT || current_inst == INST_FNINIT) begin
            queue_flush <= 1'b1;
        end

        // Flush on FLDCW (control word change)
        if (current_inst == INST_FLDCW) begin
            queue_flush <= 1'b1;
        end

        // Flush on unmasked exception
        if (exception_pending) begin
            queue_flush <= 1'b1;
        end
    end
end
```

### 5. State Machine Modifications

**Minimal changes needed**:

1. **STATE_IDLE**: Check queue and dequeue if available
2. **Instruction capture**: Use queued_* signals instead of direct inputs
3. **Ready signal**: Manage based on queue status

**No changes needed**:
- STATE_DECODE, STATE_EXECUTE, STATE_WRITEBACK remain the same
- Exception handling remains the same
- Arithmetic units remain the same

---

## Timing Diagrams

### Synchronous Operation (Current)

```
Clock:     0      1      2      3      4      5      6
          ─┴─┬─┴─┬─┴─┬─┴─┬─┴─┬─┴─┬─┴─┬─┴─
execute:   0  1  0  0  0  1  0  0  0  0  0
          ───┴──┬──┬──┬──┬──┴──┬──┬──┬──┬──
ready:     1  0  0  0  1  1  0  0  0  1  1
          ───┴──────────┬──────┴──────────┬─
state:    IDLE  DECODE  EXECUTE  IDLE  DECODE...

CPU blocks:  ████████████  (waits 3 cycles)
```

### Asynchronous Operation (Target)

```
Clock:     0      1      2      3      4      5      6
          ─┴─┬─┴─┬─┴─┬─┴─┬─┴─┬─┴─┬─┴─┬─┴─
execute:   0  1  0  1  0  1  0  0  0  0  0
          ───┴──┬──┬──┴──┬──┴──┬──┬──┬──┬──
ready:     1  1  1  1  0  0  1  1  1  1  1
          ───────────────┴──────────────────
queue:     0  1  2  3  3  3  2  1  0  0  0
          ───────┴──┴──┴──────────────┴─────
BUSY:      0  1  1  1  1  1  1  1  0  0  0
          ───────────────────────────────────
state:    IDLE  IDLE  DECODE  EXECUTE  IDLE

CPU blocks:        ██  (waits 1 cycle when queue full)
CPU continues: ✓   ✓   ✓   ✗   ✗   ✓
```

**Improvement**: CPU can enqueue 3 instructions immediately, only blocks on 4th

---

## Performance Analysis

### Synchronous (Current)

```
Instruction sequence: FADD, FMUL, FSUB
FADD cycles: 4 (example)
FMUL cycles: 5 (example)
FSUB cycles: 4 (example)
Total: 4 + 5 + 4 = 13 cycles
CPU utilization: 0% (CPU waits entire time)
```

### Asynchronous (Phase 4)

```
Instruction sequence: FADD, FMUL, FSUB
Enqueue FADD: 1 cycle (CPU free immediately)
Enqueue FMUL: 1 cycle (CPU free immediately)
Enqueue FSUB: 1 cycle (CPU free immediately)
FPU executes: 4 + 5 + 4 = 13 cycles (in background)
Total CPU time: 3 cycles
CPU utilization: 77% (10/13 cycles doing other work)
```

**Speedup**: Up to 4x for instruction sequences (depends on queue depth and instruction latency)

---

## Flush Conditions

### 1. FINIT/FNINIT

**Reason**: Complete FPU reset, all pending operations invalidated

```verilog
if (current_inst == INST_FINIT || current_inst == INST_FNINIT) begin
    queue_flush <= 1'b1;
end
```

### 2. FLDCW

**Reason**: Control word change may affect rounding, precision, or exception masks of pending instructions

```verilog
if (current_inst == INST_FLDCW) begin
    queue_flush <= 1'b1;
end
```

### 3. Exceptions

**Reason**: Unmasked exception requires immediate attention, pending operations may be invalid

```verilog
if (exception_pending) begin
    queue_flush <= 1'b1;
end
```

**Note**: 8087 flushes pipeline on exceptions to ensure consistent state

---

## Testing Strategy

### Unit Tests (Instruction Queue)

Already complete from Phase 1:
- ✅ 18/18 tests passing
- ✅ Enqueue/dequeue verified
- ✅ Wraparound verified
- ✅ Flush verified

### Integration Tests (Phase 4)

New tests needed:
1. Queue enqueue from CPU interface
2. Queue dequeue to execution
3. BUSY signal generation
4. Queue flush on FINIT
5. Queue flush on FLDCW
6. Queue flush on exception
7. Asynchronous operation (3 instructions enqueued)
8. Queue full handling
9. Multiple instruction execution

**Test File**: `tb_fpu_async_operation.v`

---

## Risk Assessment

### Risk 1: Timing Issues

**Risk**: Queue dequeue and state machine start might conflict
**Mitigation**: Careful one-cycle handshake design
**Severity**: Medium

### Risk 2: Flush Timing

**Risk**: Flush during instruction execution could corrupt state
**Mitigation**: Flush only when safe (IDLE state or specific instructions)
**Severity**: High

### Risk 3: Ready Signal Complexity

**Risk**: Ready signal depends on queue and execution state
**Mitigation**: Simple logic: ready = !queue_full
**Severity**: Low

### Risk 4: Data Capture

**Risk**: data_in captured at wrong time (CPU vs queue)
**Mitigation**: Capture data_in when enqueuing, store in queue
**Severity**: Medium

---

## Implementation Plan

### Step 1: Add BUSY Signal (Simple)

- Add to module interface
- Generate from queue status
- Test with existing code

### Step 2: Instantiate Queue (Moderate)

- Add queue instance
- Wire signals
- No functional change yet

### Step 3: Add Enqueue Logic (Moderate)

- Detect execute signal
- Enqueue to queue
- Modify ready signal

### Step 4: Add Dequeue Logic (Complex)

- Detect idle state
- Dequeue from queue
- Start execution

### Step 5: Add Flush Logic (Moderate)

- Detect flush conditions
- Pulse queue_flush
- Handle edge cases

### Step 6: Test Integration (Complex)

- Create comprehensive tests
- Verify asynchronous operation
- Verify flush behavior

---

## Success Criteria

Phase 4 is complete when:

1. ✅ BUSY signal implemented (active HIGH)
2. ✅ Instruction queue integrated
3. ✅ Asynchronous operation working
4. ✅ Queue flush on FINIT/FLDCW/exceptions
5. ✅ All tests passing
6. ✅ No regressions in Phase 1-3 tests
7. ✅ Documentation complete

---

## Next Phase Preview

### Phase 5: Full System Integration (Future)

- CPU-FPU handshake protocol
- Memory interface for FPU
- DMA support for large transfers
- Performance benchmarking
- 8087 compliance testing with real programs

---

## References

- Phase 1: PHASE1_COMPLETE.md (Instruction Queue)
- Phase 2: PHASE2_COMPLETE.md (Exception Handler)
- Phase 3: PHASE3_COMPLETE.md (Exception Integration)
- 8087 Architecture: 8087_ARCHITECTURE_RESEARCH.md
- Intel 8087 Data Sheet (1980)

---

**Phase 4 Architecture**: APPROVED
**Implementation**: READY TO BEGIN
**Complexity**: HIGH (state machine integration)
**Estimated Time**: 1-2 days
