# Wait vs No-Wait Instructions: 8087-Accurate Implementation

## Current Implementation Status

### Current Behavior (Synchronous)
Both wait and no-wait versions behave **identically** because:
- FPU operations complete synchronously within clock cycles
- No parallel CPU-FPU execution
- No pipelining or asynchronous operation
- `ready` signal indicates completion, but CPU always waits

### Original Intel 8087 Behavior

#### Wait Instructions (FINIT, FSTCW, FSTSW, FCLEX)
1. **Implicit FWAIT**: Internally executes FWAIT behavior first
2. **Exception Check**: Checks for pending unmasked exceptions
3. **Wait for Completion**: Waits for any in-progress FPU operation to finish
4. **FERR# Assertion**: If unmasked exception exists, asserts FERR# (Floating-point ERRor) signal
5. **CPU Block**: CPU execution blocks until FPU is ready
6. **Execute**: Then performs the actual instruction

#### No-Wait Instructions (FNINIT, FNSTCW, FNSTSW, FNCLEX)
1. **No FWAIT**: Does NOT wait for completion
2. **No Exception Check**: Does NOT check for pending exceptions
3. **Immediate Execution**: Executes immediately regardless of FPU state
4. **CPU Continue**: CPU can continue while FPU completes previous operation
5. **Risk**: May read stale/incomplete data if previous operation not finished

---

## What Would Be Required for 8087-Accurate Behavior

### 1. Asynchronous/Pipelined FPU Architecture

**Current**: Synchronous FSM, operations block until complete
**Required**:
- Separate execution pipeline that runs independently
- Allow CPU to issue new instructions while FPU still executing
- Multi-cycle operations tracked with busy flag

**Implementation**:
```verilog
// Add busy tracking
reg fpu_busy;           // FPU has operation in progress
reg [3:0] busy_countdown; // Cycles remaining for current operation

// Modified ready signal
assign ready = !fpu_busy || is_nowait_instruction;
```

**Impact**: Major architectural change, affects all instruction timing

---

### 2. Exception Checking for Wait Instructions

**Current**: No pre-execution exception checking
**Required**:
- Check status word for unmasked exceptions before executing wait instructions
- Differentiate between wait and no-wait instruction handling
- Assert error signal (FERR# equivalent) if unmasked exception found

**Implementation**:
```verilog
// Exception checking function
function automatic has_unmasked_exceptions;
    input [15:0] status;
    input [15:0] control;
    reg [5:0] exception_bits;
    reg [5:0] mask_bits;
    begin
        // Extract exception flags [5:0] from status word
        exception_bits = status[5:0];

        // Extract mask bits from control word
        mask_bits = control[5:0];

        // Check if any exception is set and NOT masked
        has_unmasked_exceptions = |(exception_bits & ~mask_bits);
    end
endfunction

// In wait instruction handlers
INST_FINIT: begin
    if (has_unmasked_exceptions(status_out, control_out)) begin
        // Assert FERR# equivalent
        error <= 1'b1;
        // Wait for software exception handler
        state <= STATE_EXCEPTION_WAIT;
    end else begin
        // Proceed with FINIT
        stack_init_stack <= 1'b1;
        // ...
    end
end

// In no-wait instruction handlers
INST_FNINIT: begin
    // No exception checking - execute immediately
    stack_init_stack <= 1'b1;
    // ...
end
```

**Impact**: Moderate, adds exception checking logic to wait instructions only

---

### 3. FWAIT Behavior Integration

**Current**: FWAIT is a no-op
**Required**:
- FWAIT waits for `fpu_busy` to clear
- FWAIT checks for unmasked exceptions
- Wait instructions implicitly call FWAIT logic first

**Implementation**:
```verilog
// FWAIT state machine
INST_FWAIT: begin
    if (fpu_busy) begin
        // Wait for completion
        state <= STATE_FWAIT_BUSY;
    end else if (has_unmasked_exceptions(status_out, control_out)) begin
        // Check for exceptions after completion
        error <= 1'b1;
        state <= STATE_EXCEPTION_WAIT;
    end else begin
        state <= STATE_DONE;
    end
end

STATE_FWAIT_BUSY: begin
    if (!fpu_busy) begin
        // Check exceptions after operation completes
        if (has_unmasked_exceptions(status_out, control_out)) begin
            error <= 1'b1;
            state <= STATE_EXCEPTION_WAIT;
        end else begin
            state <= STATE_DONE;
        end
    end
    // Otherwise stay in this state
end

// Wait instructions use FWAIT first
INST_FINIT: begin
    state <= STATE_FWAIT_THEN_FINIT;
end

STATE_FWAIT_THEN_FINIT: begin
    if (!fpu_busy && !has_unmasked_exceptions(status_out, control_out)) begin
        // Now execute FINIT
        stack_init_stack <= 1'b1;
        status_clear_exc <= 1'b1;
        internal_control_in <= 16'h037F;
        internal_control_write <= 1'b1;
        state <= STATE_DONE;
    end
end
```

**Impact**: High, requires new states and wait logic

---

### 4. Busy Flag Management

**Current**: Busy flag in status word not properly managed
**Required**:
- Set busy flag when operation starts
- Clear busy flag when operation completes
- Multi-cycle operations keep busy flag set

**Implementation**:
```verilog
// In arithmetic operation start
if (arith_enable) begin
    status_set_busy <= 1'b1;
    busy_countdown <= get_operation_cycles(arith_operation);
    fpu_busy <= 1'b1;
end

// Countdown busy cycles
always @(posedge clk) begin
    if (fpu_busy && busy_countdown > 0) begin
        busy_countdown <= busy_countdown - 1;
        if (busy_countdown == 1) begin
            status_clear_busy <= 1'b1;
            fpu_busy <= 1'b0;
        end
    end
end

function [3:0] get_operation_cycles;
    input [3:0] operation;
    begin
        case (operation)
            OP_ADD, OP_SUB: get_operation_cycles = 4'd3;
            OP_MUL:         get_operation_cycles = 4'd5;
            OP_DIV:         get_operation_cycles = 4'd8;
            OP_SQRT:        get_operation_cycles = 4'd12;
            // Transcendental operations much longer
            OP_SIN, OP_COS: get_operation_cycles = 4'd15;
            default:        get_operation_cycles = 4'd1;
        endcase
    end
endfunction
```

**Impact**: Moderate, affects all arithmetic operations

---

### 5. CPU-FPU Interface Changes

**Current**: CPU waits for `ready` signal
**Required**:
- CPU can continue on no-wait instructions even if FPU busy
- CPU blocks on wait instructions until FPU ready
- External BUSY# pin output (for multi-processor systems)

**Implementation**:
```verilog
// Modified ready signal
assign ready = execute ? (is_nowait_instruction || !fpu_busy) : 1'b1;

// Classify instruction type
function automatic is_nowait_instruction;
    input [7:0] inst;
    begin
        is_nowait_instruction = (inst == INST_FNINIT) ||
                                (inst == INST_FNSTCW) ||
                                (inst == INST_FNSTSW) ||
                                (inst == INST_FNCLEX);
    end
endfunction

// External busy output
output wire busy_out;
assign busy_out = fpu_busy;
```

**Impact**: Low, changes interface signals

---

### 6. Exception Handler Support

**Required for Full 8087 Compatibility**:
- STATE_EXCEPTION_WAIT state that holds CPU
- FERR# signal output (or equivalent error flag)
- Software can clear exception flags and resume
- Hardware interrupt integration (IRQ13 on PC architecture)

**Implementation**:
```verilog
// Exception wait state
STATE_EXCEPTION_WAIT: begin
    // CPU blocked, error signal asserted
    // Wait for FCLEX/FNCLEX to clear exceptions
    if (status_clear_exc) begin
        error <= 1'b0;
        state <= STATE_DONE;
    end
    // Otherwise remain blocked
end

// Error output pin
output reg ferr_n;  // Active low floating-point error

always @(posedge clk or posedge reset) begin
    if (reset) begin
        ferr_n <= 1'b1;  // Inactive
    end else begin
        if (has_unmasked_exceptions(status_out, control_out)) begin
            ferr_n <= 1'b0;  // Assert error
        end else if (status_clear_exc) begin
            ferr_n <= 1'b1;  // Clear error
        end
    end
end
```

**Impact**: High, requires external interface changes

---

## Summary of Required Changes

### Level 1: Minimal (Exception Checking Only)
**Effort**: Low
**Changes**:
- Add exception checking to wait instructions
- No-wait instructions skip checking
- Still synchronous, no parallel execution

**Benefit**: Partial 8087 compatibility, exception handling more accurate

---

### Level 2: Moderate (Add Busy Tracking)
**Effort**: Moderate
**Changes**:
- Track multi-cycle operations with busy flag
- Wait instructions check busy + exceptions
- No-wait can proceed while busy
- CPU can continue for no-wait instructions

**Benefit**: More accurate timing, CPU not blocked unnecessarily

---

### Level 3: Full (Complete 8087 Emulation)
**Effort**: High
**Changes**:
- Asynchronous FPU pipeline
- Full FWAIT integration
- Exception wait states
- FERR# / BUSY# external signals
- Hardware interrupt support

**Benefit**: Complete 8087 compatibility, accurate historical behavior

---

## Recommendation

**For this implementation**: Stay with **current synchronous approach**

**Rationale**:
1. **Simplicity**: Synchronous design is easier to verify and debug
2. **Modern Context**: In modern SoC/FPGA designs, synchronous execution is standard
3. **Functional Completeness**: All instructions produce correct results
4. **No Real Benefit**: The wait/no-wait distinction only matters when:
   - CPU and FPU run in parallel (not the case in synchronous design)
   - Software relies on specific timing (very rare, mostly legacy code)
5. **Testing Complexity**: Asynchronous design requires much more complex test scenarios

**When Level 2/3 Would Be Needed**:
- Emulating actual 8086/8088 + 8087 system for historical accuracy
- Running legacy software that depends on wait/no-wait timing differences
- Multi-processor system where FPU is shared resource
- Performance optimization where CPU continues during long FPU operations

---

## Current Implementation Assessment

✅ **Functionally Correct**: All operations produce correct results
✅ **Interface Complete**: All instruction opcodes implemented
✅ **Exception Handling**: Proper exception flag management
✅ **Software Compatible**: Works for well-written FPU code

⚠️ **Not Timing-Accurate**: Wait and no-wait behave identically
⚠️ **No Parallel Execution**: CPU always waits for FPU
⚠️ **No FERR# Support**: No external error signaling

**Verdict**: Current implementation is **excellent for modern FPGA/SoC applications** where synchronous, deterministic behavior is desired.

---

## Example: Timing Difference in Real 8087

```assembly
; Real 8087 behavior example

; Scenario 1: Using no-wait instruction
FMUL  ST(0), ST(1)    ; Starts multiply (takes ~30 cycles on 8087)
FNSTSW AX             ; No-wait: reads status immediately
                      ; AX may show busy flag set
                      ; May show incomplete results
MOV [result], AX      ; Store potentially stale status
                      ; CPU continues while multiply finishes

; Scenario 2: Using wait instruction
FMUL  ST(0), ST(1)    ; Starts multiply
FSTSW AX              ; Wait: implicit FWAIT first
                      ; CPU blocks until multiply completes
                      ; Then reads status
MOV [result], AX      ; Store accurate status
                      ; Multiply is definitely complete
```

**In current implementation**: Both scenarios behave identically - CPU always waits.

**In real 8087**: Scenario 1 CPU continues, Scenario 2 CPU blocks.
