# Asynchronous FPU Implementation Plan
## Parallel CPU-FPU Execution with FERR# Support

**Status**: Planning Phase
**Target**: Level 3 (Full) - Complete 8087 Emulation
**Date**: 2025-11-10

---

## Executive Summary

This plan outlines the transformation of the current synchronous FPU design into a fully asynchronous architecture that allows parallel CPU-FPU execution. The key goals are:

1. **CPU-FPU Parallelism**: CPU continues executing while FPU processes instructions
2. **Exception Signaling**: FERR# output for unmasked floating-point exceptions
3. **8087 Compatibility**: Full wait vs. no-wait instruction behavior
4. **Memory Coherency**: Proper ordering of memory operations
5. **Interrupt Support**: Optional IRQ13 integration for legacy systems

**Estimated Complexity**: High (3-4 weeks implementation + testing)
**Risk Level**: Medium-High (architectural changes, timing complexity)

---

## Part 1: Architecture Overview

### Current State (Synchronous)

```
CPU → [FPU_Core FSM] → Result
      ↑ blocks here until done
```

- Single FSM handles everything sequentially
- CPU waits for FPU completion (ready signal)
- No parallelism between CPU and FPU
- Simple but inefficient

### Target State (Asynchronous)

```
CPU → [Instruction Queue] → [FPU Pipeline] → [Result Buffer] → Memory/Stack
      ↓ continues immediately          ↓
      [Next Instruction]         [FERR# / BUSY#]
                                       ↓
                                 [Exception Handler]
```

- Decoupled CPU and FPU execution
- Instruction queuing for pipelining
- Result buffering for out-of-order completion
- Exception signaling via FERR#
- Synchronization at memory operations

---

## Part 2: Major Architectural Changes

### 2.1 Instruction Queue

**Purpose**: Buffer FPU instructions while previous operations execute

**Design**:
```verilog
module FPU_Instruction_Queue #(
    parameter QUEUE_DEPTH = 4  // 4 instructions deep (matches 8087)
)(
    input wire clk,
    input wire reset,

    // Enqueue interface (from CPU)
    input wire enqueue,
    input wire [7:0] instruction,
    input wire [2:0] stack_index,
    input wire has_memory_op,
    input wire [1:0] operand_size,
    input wire is_integer,
    input wire is_bcd,
    input wire [79:0] data_in,
    output wire queue_full,

    // Dequeue interface (to FPU pipeline)
    output wire queue_empty,
    output wire [7:0] next_instruction,
    output wire [2:0] next_stack_index,
    output wire next_has_memory_op,
    output wire [1:0] next_operand_size,
    output wire next_is_integer,
    output wire next_is_bcd,
    output wire [79:0] next_data_in,
    input wire dequeue
);

    // FIFO structure
    reg [7:0] inst_queue [0:QUEUE_DEPTH-1];
    reg [2:0] index_queue [0:QUEUE_DEPTH-1];
    reg [79:0] data_queue [0:QUEUE_DEPTH-1];
    // ... other fields

    reg [2:0] write_ptr;
    reg [2:0] read_ptr;
    reg [2:0] count;

    assign queue_full = (count == QUEUE_DEPTH);
    assign queue_empty = (count == 0);

    // Enqueue logic
    always @(posedge clk) begin
        if (reset) begin
            write_ptr <= 0;
            read_ptr <= 0;
            count <= 0;
        end else begin
            if (enqueue && !queue_full) begin
                inst_queue[write_ptr] <= instruction;
                index_queue[write_ptr] <= stack_index;
                data_queue[write_ptr] <= data_in;
                write_ptr <= write_ptr + 1;
                count <= count + 1;
            end

            if (dequeue && !queue_empty) begin
                read_ptr <= read_ptr + 1;
                count <= count - 1;
            end
        end
    end

    // Dequeue outputs
    assign next_instruction = inst_queue[read_ptr];
    assign next_stack_index = index_queue[read_ptr];
    assign next_data_in = data_queue[read_ptr];

endmodule
```

**Key Considerations**:
- **Queue Depth**: 4 matches Intel 8087, adjust if needed
- **Flush Mechanism**: Need to flush queue on exceptions or control flow changes
- **Ordering**: Maintain program order for correctness
- **Memory Operations**: May need special handling (see Section 2.4)

### 2.2 FPU Pipeline State Machine

**Purpose**: Execute FPU operations independently of CPU

**Design**: Separate from CPU control flow

```verilog
// New pipeline state machine (runs in parallel with CPU)
localparam PIPE_IDLE          = 3'd0;
localparam PIPE_FETCH         = 3'd1;  // Fetch from instruction queue
localparam PIPE_DECODE        = 3'd2;  // Decode and read operands
localparam PIPE_EXECUTE       = 3'd3;  // Arithmetic operation
localparam PIPE_WRITEBACK     = 3'd4;  // Write result to stack
localparam PIPE_EXCEPTION     = 3'd5;  // Handle exceptions

reg [2:0] pipeline_state;
```

**Pipeline Flow**:
```
IDLE → FETCH → DECODE → EXECUTE → WRITEBACK → IDLE
                ↓                      ↓
            [No Inst]             [Exception]
                ↓                      ↓
              IDLE                 EXCEPTION
```

**Critical Path**:
- Pipeline fetches next instruction from queue when not busy
- Executes independently
- Signals completion via done flag
- Asserts FERR# on unmasked exceptions

### 2.3 Result Buffer

**Purpose**: Store completed results until CPU/memory system is ready

**Design**:
```verilog
module FPU_Result_Buffer(
    input wire clk,
    input wire reset,

    // Write interface (from FPU pipeline)
    input wire result_valid,
    input wire [79:0] result_data,
    input wire [2:0] result_dest_index,
    input wire result_is_pop,
    input wire result_is_push,
    output wire result_buffer_full,

    // Read interface (to register stack)
    output wire pending_writeback,
    output wire [79:0] writeback_data,
    output wire [2:0] writeback_index,
    output wire writeback_is_pop,
    output wire writeback_is_push,
    input wire writeback_ack
);

    reg result_pending;
    reg [79:0] buffered_result;
    reg [2:0] buffered_index;
    reg buffered_is_pop;
    reg buffered_is_push;

    assign result_buffer_full = result_pending;
    assign pending_writeback = result_pending;

    always @(posedge clk) begin
        if (reset) begin
            result_pending <= 0;
        end else begin
            if (result_valid && !result_buffer_full) begin
                buffered_result <= result_data;
                buffered_index <= result_dest_index;
                buffered_is_pop <= result_is_pop;
                buffered_is_push <= result_is_push;
                result_pending <= 1;
            end

            if (writeback_ack && result_pending) begin
                result_pending <= 0;
            end
        end
    end

endmodule
```

**Considerations**:
- **Single Entry**: Start with 1-deep buffer, expand if needed
- **Multi-Entry**: Could use FIFO for more parallelism
- **Bypass Logic**: Direct path when buffer empty and stack ready

### 2.4 Memory Operation Synchronization

**Challenge**: Memory operations must execute in order and sync with CPU

**Solution**: Stall pipeline on memory operations

```verilog
// In pipeline state machine
PIPE_DECODE: begin
    if (current_inst_has_memory_op) begin
        // Memory operation - must sync with CPU
        if (cpu_memory_access_complete) begin
            pipeline_state <= PIPE_EXECUTE;
        end else begin
            // Stall until CPU completes memory access
            memory_sync_stall <= 1'b1;
            pipeline_state <= PIPE_DECODE;  // Stay in decode
        end
    end else begin
        // Register-only operation - can proceed
        pipeline_state <= PIPE_EXECUTE;
    end
end
```

**Memory Operation Protocol**:
1. FPU pipeline detects memory operation
2. Asserts `memory_request` to CPU
3. CPU completes current instruction
4. CPU performs memory access on behalf of FPU
5. CPU asserts `memory_complete`
6. FPU pipeline continues

**Alternative**: Shared memory bus arbiter (more complex but more flexible)

---

## Part 3: Exception Handling & FERR# Implementation

### 3.1 FERR# Signal Generation

**Purpose**: Signal unmasked floating-point exceptions to CPU

**Intel 8087 Behavior**:
- FERR# is active LOW
- Asserted when unmasked exception occurs
- Remains asserted until acknowledged
- CPU checks FERR# before executing next FPU instruction (in wait mode)

**Implementation**:
```verilog
module FPU_Exception_Handler(
    input wire clk,
    input wire reset,

    // Exception inputs from arithmetic unit
    input wire exception_invalid,
    input wire exception_denormal,
    input wire exception_zero_div,
    input wire exception_overflow,
    input wire exception_underflow,
    input wire exception_precision,

    // Mask bits from control word
    input wire mask_invalid,
    input wire mask_denormal,
    input wire mask_zero_div,
    input wire mask_overflow,
    input wire mask_underflow,
    input wire mask_precision,

    // Exception acknowledgment
    input wire exception_ack,  // From FWAIT or wait-type instruction

    // FERR# output (active low)
    output reg ferr_n,

    // Internal exception pending flag
    output reg exception_pending
);

    wire unmasked_exception;

    // Detect unmasked exceptions
    assign unmasked_exception =
        (exception_invalid   && !mask_invalid)   ||
        (exception_denormal  && !mask_denormal)  ||
        (exception_zero_div  && !mask_zero_div)  ||
        (exception_overflow  && !mask_overflow)  ||
        (exception_underflow && !mask_underflow) ||
        (exception_precision && !mask_precision);

    always @(posedge clk) begin
        if (reset) begin
            ferr_n <= 1'b1;  // Inactive (active low)
            exception_pending <= 1'b0;
        end else begin
            // Set exception pending on unmasked exception
            if (unmasked_exception) begin
                exception_pending <= 1'b1;
                ferr_n <= 1'b0;  // Assert FERR# (active low)
            end

            // Clear on acknowledgment
            if (exception_ack) begin
                exception_pending <= 1'b0;
                ferr_n <= 1'b1;  // Deassert FERR#
            end
        end
    end

endmodule
```

### 3.2 Exception Checking State

**Purpose**: Implement proper FWAIT and wait-instruction behavior

**New State Machine State**:
```verilog
localparam STATE_EXCEPTION_CHECK = 4'd11;  // Check for pending exceptions

// In main FSM
STATE_IDLE: begin
    ready <= 1'b1;

    if (execute) begin
        current_inst <= instruction;

        // Check if this is a wait-type instruction
        if (is_wait_instruction(instruction)) begin
            // Must check for exceptions first
            state <= STATE_EXCEPTION_CHECK;
        end else if (is_nowait_instruction(instruction)) begin
            // No-wait: skip exception check
            state <= STATE_DECODE;
        end else begin
            // Default: proceed normally
            state <= STATE_DECODE;
        end
    end
end

STATE_EXCEPTION_CHECK: begin
    if (exception_pending) begin
        // Exception pending - stall and signal error
        ready <= 1'b0;  // Not ready for next instruction
        error <= 1'b1;  // Signal error to CPU
        // Stay in this state until exception cleared
        // CPU must handle exception (read status, clear, etc.)
    end else begin
        // No exception - proceed
        exception_ack <= 1'b1;  // Acknowledge check
        state <= STATE_DECODE;
    end
end
```

### 3.3 FWAIT Instruction Implementation

**Purpose**: Explicit wait for FPU completion and exception check

```verilog
INST_FWAIT: begin
    // Wait for FPU pipeline to complete all pending operations
    if (pipeline_idle && !exception_pending) begin
        // FPU idle and no exceptions - done
        state <= STATE_DONE;
    end else if (exception_pending) begin
        // Exception present - signal error
        error <= 1'b1;
        state <= STATE_EXCEPTION_CHECK;
    end else begin
        // FPU still busy - wait
        // Stay in this state
        state <= STATE_EXECUTE;
    end
end
```

### 3.4 Exception Acknowledgment Protocol

**Flow**:
```
1. FPU detects unmasked exception
   ↓
2. Sets exception_pending = 1
   ↓
3. Asserts FERR# = 0 (active low)
   ↓
4. Wait instruction executes
   ↓
5. Checks exception_pending
   ↓
6. If set: error <= 1, ready <= 0
   ↓
7. CPU reads status word (sees exception bits)
   ↓
8. CPU executes FCLEX or FNCLEX
   ↓
9. Clears exception bits and exception_pending
   ↓
10. Deasserts FERR# = 1
```

---

## Part 4: Synchronization & Ready Signal Logic

### 4.1 CPU Ready Signal

**Current (Synchronous)**:
```verilog
ready <= (state == STATE_IDLE);  // Simple
```

**Async (More Complex)**:
```verilog
// Ready when:
// 1. FPU can accept new instruction (queue not full), AND
// 2. No pending exceptions for wait-type instructions, AND
// 3. No memory sync required

assign ready = (state == STATE_IDLE) &&
               (!instruction_queue_full) &&
               (is_nowait_instruction(instruction) || !exception_pending) &&
               (!memory_sync_pending);
```

### 4.2 Synchronization Points

**Must Synchronize**:
1. **Memory Operations**: CPU and FPU must coordinate
2. **Exception Checking**: Wait instructions must wait for exception resolution
3. **Stack Pointer Changes**: FINCSTP, FDECSTP must take effect immediately
4. **Control Register Changes**: FLDCW must flush pipeline

**Synchronization Mechanism**:
```verilog
// Flush pipeline on control changes
INST_FLDCW: begin
    // Flush instruction queue
    queue_flush <= 1'b1;

    // Wait for pipeline to drain
    if (pipeline_idle) begin
        // Now safe to update control word
        internal_control_in <= data_in[15:0];
        internal_control_write <= 1'b1;
        state <= STATE_DONE;
    end else begin
        // Wait for pipeline to complete
        state <= STATE_EXECUTE;  // Stay here
    end
end
```

---

## Part 5: BUSY# Signal Implementation

### 5.1 BUSY# Signal Purpose

**8087 Specification**:
- BUSY# is active LOW
- Indicates FPU is executing an instruction
- Used by CPU to implement FWAIT
- External signal for hardware synchronization

**Implementation**:
```verilog
// BUSY# signal generation
assign busy_n = !(pipeline_state != PIPE_IDLE || !instruction_queue_empty);

// In top-level module
output wire busy_n;  // Active low busy signal

// Alternative: use fpu_busy register from Level 2
assign busy_n = !fpu_busy;
```

### 5.2 BUSY# Usage

**By CPU**:
- Check BUSY# before executing wait-type instructions
- Implement FWAIT by polling BUSY#
- Hardware synchronization

**Example**:
```verilog
// CPU wait logic
if (fpu_instruction && is_wait_type) begin
    if (!busy_n) begin  // Active low, so !busy_n means busy
        // FPU busy - stall CPU
        cpu_stall <= 1'b1;
    end else begin
        // FPU ready - proceed
        cpu_stall <= 1'b0;
    end
end
```

---

## Part 6: Implementation Phases

### Phase 1: Pipeline Infrastructure (Week 1)

**Goals**:
- Implement instruction queue
- Create separate pipeline state machine
- Add result buffer
- Basic enqueue/dequeue logic

**Deliverables**:
- `FPU_Instruction_Queue.v`
- `FPU_Pipeline_Control.v`
- `FPU_Result_Buffer.v`
- Unit tests for each module

**Testing**:
- Queue operations (enqueue, dequeue, full, empty)
- Pipeline state transitions
- Result buffering

### Phase 2: Exception Handling (Week 2)

**Goals**:
- Implement FERR# generation
- Add exception pending logic
- Create exception check state
- Implement FWAIT

**Deliverables**:
- `FPU_Exception_Handler.v`
- Modified `FPU_Core.v` with exception checking
- FWAIT implementation
- Exception test suite

**Testing**:
- Exception detection and FERR# assertion
- Wait instruction blocking
- Exception acknowledgment
- FWAIT behavior

### Phase 3: Memory Synchronization (Week 3)

**Goals**:
- Implement memory operation protocol
- Add memory sync stalls
- Handle memory ordering

**Deliverables**:
- Memory request/complete handshake
- Modified memory operation handlers
- Memory ordering tests

**Testing**:
- Memory load/store sequencing
- Mixed register/memory operations
- Memory exception handling

### Phase 4: Integration & Validation (Week 4)

**Goals**:
- Integrate all components
- Full system testing
- Performance validation
- 8087 compliance testing

**Deliverables**:
- Fully integrated async FPU
- Comprehensive test suite
- Performance benchmarks
- Compliance report

**Testing**:
- Parallel CPU-FPU execution
- Exception scenarios
- Real-world workloads
- Timing analysis

---

## Part 7: Instruction Classification

### 7.1 Wait-Type Instructions

**Require Exception Check**:
```verilog
function automatic is_wait_instruction;
    input [7:0] inst;
    begin
        is_wait_instruction =
            (inst == INST_FINIT)  ||
            (inst == INST_FSTCW)  ||
            (inst == INST_FSTSW)  ||
            (inst == INST_FCLEX)  ||
            (inst == INST_FWAIT)  ||
            // All arithmetic operations
            (inst == INST_FADD)   ||
            (inst == INST_FSUB)   ||
            (inst == INST_FMUL)   ||
            (inst == INST_FDIV)   ||
            // ... etc
            1'b0;
    end
endfunction
```

### 7.2 No-Wait Instructions

**Skip Exception Check**:
```verilog
function automatic is_nowait_instruction;
    input [7:0] inst;
    begin
        is_nowait_instruction =
            (inst == INST_FNINIT)  ||
            (inst == INST_FNSTCW)  ||
            (inst == INST_FNSTSW)  ||
            (inst == INST_FNCLEX);
    end
endfunction
```

### 7.3 Synchronizing Instructions

**Must Flush Pipeline**:
```verilog
function automatic is_synchronizing_instruction;
    input [7:0] inst;
    begin
        is_synchronizing_instruction =
            (inst == INST_FLDCW)   ||  // Changes control word
            (inst == INST_FINIT)   ||  // Resets FPU
            (inst == INST_FNINIT)  ||
            (inst == INST_FWAIT);      // Explicit sync
    end
endfunction
```

---

## Part 8: Testing Strategy

### 8.1 Unit Tests

**Per-Module Testing**:

1. **Instruction Queue**:
   - Enqueue/dequeue operations
   - Full/empty conditions
   - Wraparound behavior
   - Flush operation

2. **Exception Handler**:
   - Exception detection
   - FERR# assertion/deassertion
   - Acknowledgment protocol
   - Multiple simultaneous exceptions

3. **Pipeline Control**:
   - State transitions
   - Stall conditions
   - Result generation

4. **Result Buffer**:
   - Write/read operations
   - Full condition
   - Bypass logic

### 8.2 Integration Tests

**System-Level Scenarios**:

1. **Parallel Execution**:
```assembly
FLD1              ; Load 1.0
FLD1              ; Load 1.0 (queue while prev executing)
FADD              ; Add (execute in parallel with CPU)
MOV AX, 1234h     ; CPU continues
MOV BX, 5678h     ; CPU continues
FWAIT             ; Sync point
FSTP result       ; Store result
```

2. **Exception Handling**:
```assembly
FLDZ              ; Load 0.0
FLDZ              ; Load 0.0
FDIV              ; Divide by zero (exception)
FWAIT             ; Should detect exception, assert FERR#
; CPU should stall here
FSTSW AX          ; Read status (sees exception bit)
FCLEX             ; Clear exception
```

3. **Mixed Wait/No-Wait**:
```assembly
FLD1
FDIV ST(0), ST(0) ; Generate exception
FNSTSW AX         ; No-wait: reads status immediately (may miss exception)
FSTSW BX          ; Wait: checks exception first
```

### 8.3 Compliance Tests

**8087 Specification Conformance**:

1. **Timing Tests**:
   - Verify CPU-FPU overlap
   - Measure parallel execution speedup
   - Validate queue depth behavior

2. **Exception Tests**:
   - All 6 exception types
   - Masked vs unmasked
   - Exception priority
   - Multiple exceptions

3. **Synchronization Tests**:
   - Memory ordering
   - Control word changes
   - Stack pointer updates

### 8.4 Regression Tests

**Ensure Level 1 & 2 Still Work**:
- Run all existing control instruction tests
- Run all arithmetic tests
- Run all conversion tests
- Ensure no behavioral regressions

---

## Part 9: Performance Considerations

### 9.1 Expected Speedup

**Theoretical Maximum**:
- Sequential (current): `T_cpu + T_fpu`
- Parallel (async): `max(T_cpu, T_fpu)`
- Speedup: `1 / (1 - p)` where p = FPU utilization (Amdahl's Law)

**Realistic Expectations**:
- **Heavy FP workloads**: 30-50% speedup
- **Mixed workloads**: 10-20% speedup
- **Light FP workloads**: <5% speedup

**Limiting Factors**:
- Memory operations (must sync)
- Exception checks (must wait)
- Queue depth (limits parallelism)

### 9.2 Resource Usage

**Additional Hardware**:
- **Instruction Queue**: ~400 LUTs (4 deep x 100-bit wide)
- **Result Buffer**: ~100 LUTs
- **Exception Handler**: ~50 LUTs
- **Pipeline FSM**: ~100 LUTs
- **Total**: ~650 additional LUTs (~5% of typical FPGA)

**Timing Impact**:
- May increase critical path slightly
- Extra muxing for queue/buffer access
- Expect <10% Fmax reduction

### 9.3 Optimization Opportunities

**After Basic Implementation**:

1. **Deeper Queue**: 8 entries instead of 4
2. **Multi-Entry Result Buffer**: Allow multiple results pending
3. **Out-of-Order Completion**: Faster ops bypass slower ones
4. **Dedicated Memory Unit**: Separate memory access pipeline
5. **Scoreboarding**: Track dependencies between instructions

---

## Part 10: Risks & Mitigations

### 10.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Timing closure failure | Medium | High | Incremental timing optimization, pipeline balancing |
| Memory coherency bugs | High | High | Extensive testing, formal verification |
| Exception handling bugs | Medium | Medium | Unit tests for all exception scenarios |
| Queue overflow | Low | Medium | Proper flow control, queue depth tuning |
| Result buffer corruption | Low | High | Bypass logic testing, state machine verification |

### 10.2 Validation Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Incomplete test coverage | Medium | High | Code coverage analysis, directed testing |
| 8087 spec ambiguity | Low | Medium | Reference to Intel datasheets, existing emulators |
| Regression in existing features | Low | High | Full regression suite on every change |

### 10.3 Schedule Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Underestimated complexity | Medium | High | Phase-based approach, early prototype |
| Debugging time | High | Medium | Incremental development, good instrumentation |
| Integration issues | Medium | Medium | Early integration, continuous testing |

---

## Part 11: Alternatives & Trade-offs

### 11.1 Simplified Async (Hybrid Approach)

**Concept**: Limited parallelism without full pipelining

**Features**:
- No instruction queue (single instruction in flight)
- FPU executes in background
- CPU continues only after starting FPU operation
- Simpler than full async

**Pros**:
- Easier to implement (~1 week vs 4 weeks)
- Lower resource usage
- Some parallelism benefit

**Cons**:
- Limited speedup (only 1 instruction overlap)
- Still need FERR# and exception handling

**Recommendation**: Consider if full async is too complex

### 11.2 Software Exception Polling

**Concept**: Skip FERR# hardware, rely on software polling

**Approach**:
- No FERR# output signal
- CPU polls status word regularly
- Exception detection in software

**Pros**:
- Simpler hardware
- Flexible exception handling

**Cons**:
- Higher latency for exception detection
- More CPU overhead
- Not 8087 compliant

**Recommendation**: Only if FERR# not required by system

### 11.3 Synchronous with Better Scheduling

**Concept**: Keep synchronous but optimize instruction order

**Approach**:
- Compiler/assembler optimizes FPU instruction placement
- Interleave FPU and CPU instructions manually
- Still fundamentally synchronous

**Pros**:
- No hardware changes
- Zero risk
- Can achieve some benefit

**Cons**:
- Limited by compiler
- No automatic parallelism
- Not true async

**Recommendation**: Always do this regardless of async implementation

---

## Part 12: Success Criteria

### 12.1 Functional Requirements

✅ **Must Have**:
- [ ] Parallel CPU-FPU execution verified
- [ ] FERR# signal correctly asserted on unmasked exceptions
- [ ] Wait instructions check exceptions before executing
- [ ] FWAIT properly synchronizes and checks exceptions
- [ ] No-wait instructions execute without exception check
- [ ] Memory operations maintain program order
- [ ] All Level 1 & 2 tests still pass
- [ ] Exception acknowledgment protocol works correctly

### 12.2 Performance Requirements

✅ **Targets**:
- [ ] >20% speedup on FP-heavy workloads
- [ ] <10% Fmax degradation
- [ ] <10% additional FPGA resource usage
- [ ] Memory operations within 10% of baseline latency

### 12.3 Compliance Requirements

✅ **8087 Compatibility**:
- [ ] FERR# timing matches Intel spec
- [ ] BUSY# timing matches Intel spec
- [ ] Exception priority correct
- [ ] All 6 exception types handled
- [ ] Wait vs no-wait behavior matches spec

---

## Part 13: Next Steps

### Immediate Actions (This Week)

1. **Review this plan** with stakeholders
2. **Prototype instruction queue** in isolation
3. **Create test infrastructure** for async testing
4. **Measure baseline performance** for comparison

### Phase 1 Kickoff (Next Week)

1. Implement `FPU_Instruction_Queue.v`
2. Create unit tests
3. Begin pipeline state machine design
4. Document design decisions

### Decision Points

**Before Phase 1**:
- Approve queue depth (4 vs 8 entries)
- Decide on result buffer depth (1 vs multi-entry)
- Confirm FERR# / BUSY# pin assignments

**Before Phase 2**:
- Review Phase 1 results
- Adjust schedule based on actual complexity
- Decide on simplified vs full async

**Before Phase 3**:
- Evaluate need for IRQ13 support
- Decide on memory sync protocol
- Assess timing closure risk

---

## Appendix A: Signal Reference

### A.1 New Signals

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `ferr_n` | Output | 1 | Floating-point error (active low) |
| `busy_n` | Output | 1 | FPU busy (active low) |
| `queue_full` | Internal | 1 | Instruction queue full |
| `queue_empty` | Internal | 1 | Instruction queue empty |
| `pipeline_idle` | Internal | 1 | Pipeline has no pending operations |
| `exception_pending` | Internal | 1 | Unmasked exception awaiting acknowledgment |
| `memory_sync_pending` | Internal | 1 | Memory operation synchronization required |
| `result_valid` | Internal | 1 | Valid result ready for writeback |

### A.2 Modified Signals

| Signal | Current | New Behavior |
|--------|---------|--------------|
| `ready` | CPU can execute next FPU inst | CPU can enqueue next FPU inst |
| `execute` | Start FPU operation now | Enqueue FPU operation |
| `error` | Unmasked exception occurred | Exception pending or queue full |

---

## Appendix B: State Machine Summary

### B.1 Main CPU-Facing FSM

```
IDLE → EXCEPTION_CHECK → DECODE → EXECUTE → WRITEBACK → STACK_OP → DONE → IDLE
  ↑                                                                         ↓
  └─────────────────────────────────────────────────────────────────────────┘
```

### B.2 Pipeline FSM (New)

```
PIPE_IDLE → PIPE_FETCH → PIPE_DECODE → PIPE_EXECUTE → PIPE_WRITEBACK → PIPE_IDLE
              ↑    ↓                          ↓
              │    └─[queue empty]    [exception]
              │                              ↓
              │                        PIPE_EXCEPTION
              └────────────────────────────────┘
```

---

## Appendix C: Code Templates

### C.1 Top-Level Async FPU

```verilog
module FPU_Core_Async(
    input wire clk,
    input wire reset,

    // CPU interface
    input wire execute,
    input wire [7:0] instruction,
    output reg ready,
    output reg error,

    // New async signals
    output wire ferr_n,    // Floating-point error (active low)
    output wire busy_n,    // FPU busy (active low)

    // ... other existing signals ...
);

    // Instruction queue
    wire queue_full, queue_empty;
    wire [7:0] queued_instruction;
    wire queue_dequeue;

    FPU_Instruction_Queue inst_queue(
        .clk(clk),
        .reset(reset),
        .enqueue(execute && !queue_full),
        .instruction(instruction),
        .queue_full(queue_full),
        .queue_empty(queue_empty),
        .next_instruction(queued_instruction),
        .dequeue(queue_dequeue)
    );

    // Exception handler
    wire exception_pending;

    FPU_Exception_Handler exc_handler(
        .clk(clk),
        .reset(reset),
        .exception_invalid(arith_invalid),
        .exception_zero_div(arith_zero_div),
        .mask_invalid(mask_invalid),
        .mask_zero_div(mask_zero_div),
        .exception_ack(exception_ack),
        .ferr_n(ferr_n),
        .exception_pending(exception_pending)
    );

    // Pipeline control
    reg [2:0] pipeline_state;
    wire pipeline_idle = (pipeline_state == PIPE_IDLE);
    assign busy_n = pipeline_idle && queue_empty;

    // Ready when can accept new instruction
    assign ready = !queue_full &&
                   (!is_wait_instruction(instruction) || !exception_pending);

endmodule
```

---

## Conclusion

This plan provides a comprehensive roadmap for implementing asynchronous FPU execution with full 8087 compatibility. The phased approach allows for incremental development and testing while managing risk.

**Key Takeaways**:
1. **Complexity is high** but manageable with proper planning
2. **Performance gains are real** for FP-heavy workloads
3. **Testing is critical** - exception handling is subtle
4. **Phase-based approach** reduces risk
5. **Alternatives exist** if full async proves too complex

**Recommendation**: Proceed with Phase 1 (pipeline infrastructure) to validate the approach before committing to full implementation.
