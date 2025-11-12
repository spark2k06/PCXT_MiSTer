# FPU-CPU Interface Specification
## Intel 8087 Software Compatible Interface

### Overview
This document specifies the interface between the CPU and FPU8087 for software compatibility with Intel 8086/8087 floating-point instructions. The interface is designed specifically for the current CPU architecture while maintaining instruction-level compatibility.

---

## 1. Interface Signals

### 1.1 Clock and Reset
```verilog
input  wire        clk              // System clock
input  wire        reset            // Active high reset
```

### 1.2 Instruction Interface
```verilog
input  wire        fpu_instr_valid  // CPU signals valid FPU instruction
input  wire [7:0]  fpu_opcode       // FPU instruction opcode
input  wire [7:0]  fpu_modrm        // ModR/M byte for operand addressing
output wire        fpu_instr_ack    // FPU acknowledges instruction receipt
```

### 1.3 Data Transfer Interface
```verilog
// Memory/Register operand transfer
input  wire        fpu_data_write   // CPU writes data to FPU
input  wire        fpu_data_read    // CPU reads data from FPU
input  wire [2:0]  fpu_data_size    // Transfer size: 0=16bit, 1=32bit, 2=64bit, 3=80bit
input  wire [79:0] fpu_data_in      // Data from CPU (padded to 80 bits)
output wire [79:0] fpu_data_out     // Data to CPU
output wire        fpu_data_ready   // FPU data is ready for read
```

### 1.4 Status and Control
```verilog
output wire        fpu_busy         // FPU is executing instruction
output wire [15:0] fpu_status_word  // FPU status word (for FSTSW)
input  wire [15:0] fpu_control_word // FPU control word (for FLDCW)
input  wire        fpu_ctrl_write   // Write to control word
output wire        fpu_exception    // Unmasked exception occurred
output wire        fpu_irq          // Interrupt request to CPU
```

### 1.5 Synchronization
```verilog
input  wire        fpu_wait         // CPU executing FWAIT/WAIT
output wire        fpu_ready        // FPU ready (not busy, no exceptions)
```

---

## 2. Instruction Protocol

### 2.1 Instruction Execution Sequence

**Step 1: CPU Detects FPU Instruction**
- CPU decodes instruction with ESC prefix (0xD8-0xDF)
- Asserts `fpu_instr_valid`
- Provides `fpu_opcode` and `fpu_modrm`

**Step 2: FPU Acknowledges**
- FPU samples instruction on rising edge
- Asserts `fpu_instr_ack` for one cycle
- CPU can continue (unless WAIT required)

**Step 3: Data Transfer (if needed)**
- For memory operands, CPU handles address calculation
- CPU transfers data via `fpu_data_write` or `fpu_data_read`
- FPU processes data based on `fpu_data_size`

**Step 4: Execution**
- FPU asserts `fpu_busy` during execution
- CPU can execute other instructions (unless WAIT)
- FPU deasserts `fpu_busy` when complete

---

## 3. Supported Instructions

### 3.1 Data Transfer Instructions

| Instruction | Opcode | Description | Data Flow |
|------------|--------|-------------|-----------|
| **FLD m32real** | D9 /0 | Load 32-bit real | CPU→FPU |
| **FLD m64real** | DD /0 | Load 64-bit real | CPU→FPU |
| **FLD m80real** | DB /5 | Load 80-bit real | CPU→FPU |
| **FLD ST(i)** | D9 C0+i | Duplicate stack register | Internal |
| **FST m32real** | D9 /2 | Store 32-bit real | FPU→CPU |
| **FST m64real** | DD /2 | Store 64-bit real | FPU→CPU |
| **FST ST(i)** | DD D0+i | Store to stack register | Internal |
| **FSTP m80real** | DB /7 | Store 80-bit real and pop | FPU→CPU |
| **FXCH ST(i)** | D9 C8+i | Exchange registers | Internal |

### 3.2 Arithmetic Instructions

| Instruction | Opcode | Description |
|------------|--------|-------------|
| **FADD** | D8 C0+i | Add ST(0) + ST(i) → ST(0) |
| **FSUB** | D8 E0+i | Subtract ST(0) - ST(i) → ST(0) |
| **FMUL** | D8 C8+i | Multiply ST(0) × ST(i) → ST(0) |
| **FDIV** | D8 F0+i | Divide ST(0) ÷ ST(i) → ST(0) |
| **FSQRT** | D9 FA | Square root of ST(0) |
| **FABS** | D9 E1 | Absolute value of ST(0) |

### 3.3 Transcendental Instructions

| Instruction | Opcode | Description |
|------------|--------|-------------|
| **FSIN** | D9 FE | Sine of ST(0) |
| **FCOS** | D9 FF | Cosine of ST(0) |
| **FPTAN** | D9 F2 | Tangent of ST(0), push 1.0 |
| **FPATAN** | D9 F3 | Arctangent ST(1)/ST(0), pop |
| **F2XM1** | D9 F0 | 2^ST(0) - 1 |
| **FYL2X** | D9 F1 | ST(1) × log₂(ST(0)), pop |

### 3.4 Constant Load Instructions

| Instruction | Opcode | Description |
|------------|--------|-------------|
| **FLD1** | D9 E8 | Push +1.0 |
| **FLDZ** | D9 EE | Push +0.0 |
| **FLDPI** | D9 EB | Push π |
| **FLDL2E** | D9 EA | Push log₂(e) |
| **FLDLN2** | D9 ED | Push ln(2) |

### 3.5 Control Instructions

| Instruction | Opcode | Description | Data Flow |
|------------|--------|-------------|-----------|
| **FLDCW m16** | D9 /5 | Load control word | CPU→FPU |
| **FSTCW m16** | D9 /7 | Store control word | FPU→CPU |
| **FSTSW m16** | DD /7 | Store status word | FPU→CPU |
| **FSTSW AX** | DF E0 | Store status to AX | FPU→CPU |
| **FCLEX** | DB E2 | Clear exceptions | - |
| **FINIT** | DB E3 | Initialize FPU | - |
| **FWAIT** | 9B | Wait for FPU ready | Sync |
| **FNOP** | D9 D0 | No operation | - |

### 3.6 Comparison Instructions

| Instruction | Opcode | Description |
|------------|--------|-------------|
| **FCOM** | D8 D0+i | Compare ST(0) with ST(i) |
| **FCOMP** | D8 D8+i | Compare and pop |
| **FCOMPP** | DE D9 | Compare and pop twice |
| **FTST** | D9 E4 | Test ST(0) against 0.0 |

---

## 4. Timing Diagrams

### 4.1 FLD Instruction (Load from Memory)

```
Clock:     ___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___

instr_valid ______/‾‾‾‾‾‾‾\___________________________
opcode:     ------<  D9h  >----------------------------
modrm:      ------<  /0   >----------------------------
instr_ack:  __________/‾‾‾\___________________________

data_write: ______________/‾‾‾‾‾‾‾\___________________
data_size:  --------------<  32bit >-------------------
data_in:    --------------< value  >-------------------

fpu_busy:   __________________/‾‾‾‾‾‾‾‾‾‾‾\_____________
```

### 4.2 FADD Instruction (Stack Operation)

```
Clock:     ___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___

instr_valid ______/‾‾‾‾‾‾‾\___________________
opcode:     ------<  D8h  >--------------------
modrm:      ------<  C1h  >-------- (ST(1))
instr_ack:  __________/‾‾‾\_____________________

fpu_busy:   ______________/‾‾‾‾‾‾‾‾‾\_________
```

### 4.3 FWAIT Instruction (Synchronization)

```
Clock:     ___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___

fpu_wait:  ______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\___
fpu_busy:  ______/‾‾‾‾‾‾‾‾‾‾‾\_______________
fpu_ready: ‾‾‾‾‾‾\_____________/‾‾‾‾‾‾‾‾‾‾‾‾

CPU:       [FWAIT] [stalled...] [continue]
```

---

## 5. Data Format Transfer

### 5.1 32-bit Real (Single Precision)
```
IEEE 754 Single Precision → Extended Precision (80-bit)
[31:0] data_in → Convert → [79:0] internal FPU format
```

### 5.2 64-bit Real (Double Precision)
```
IEEE 754 Double Precision → Extended Precision (80-bit)
[63:0] data_in → Convert → [79:0] internal FPU format
```

### 5.3 80-bit Real (Extended Precision)
```
IEEE 754 Extended Precision (native FPU format)
[79:0] data_in → Direct load
```

### 5.4 16-bit Integer
```
16-bit signed integer → Extended Precision
[15:0] integer → Convert → [79:0] FP format
```

---

## 6. Exception Handling

### 6.1 Exception Types
1. **Invalid Operation (IE)** - Invalid operand
2. **Denormalized Operand (DE)** - Denormal number
3. **Zero Divide (ZE)** - Division by zero
4. **Overflow (OE)** - Result too large
5. **Underflow (UE)** - Result too small
6. **Precision (PE)** - Result not exact

### 6.2 Exception Response
```verilog
if (exception_occurred && !exception_masked) {
    fpu_exception = 1;
    fpu_irq = interrupt_enable ? 1 : 0;
    // CPU can read status word to identify exception
}
```

---

## 7. Software Compatibility Notes

### 7.1 Instruction Recognition
- CPU recognizes ESC opcodes (D8h-DFh) as FPU instructions
- ModR/M byte determines specific operation
- CPU handles memory address calculation for memory operands

### 7.2 Wait States
- FPU operations are asynchronous
- CPU must check `fpu_busy` or use FWAIT for synchronization
- Memory operands transfer immediately, computation is pipelined

### 7.3 Stack Management
- 8-register stack (ST0-ST7) with wraparound
- Stack pointer managed by FPU
- PUSH decrements pointer, POP increments

### 7.4 Rounding Control
- Four modes: Round to nearest (even), Down, Up, Toward zero
- Controlled via bits [11:10] of control word
- Affects all arithmetic operations

---

## 8. Implementation Requirements

### 8.1 CPU Side
- Decode ESC instructions (D8h-DFh)
- Extract ModR/M byte
- Calculate effective address for memory operands
- Transfer operands via data interface
- Poll `fpu_busy` for FWAIT
- Handle `fpu_irq` for exceptions

### 8.2 FPU Side
- Decode instruction opcodes
- Manage register stack
- Execute arithmetic/transcendental operations via microcode
- Format conversion (32/64/80-bit ↔ internal)
- Exception detection and masking
- Status word updates

---

## 9. Test Requirements

### 9.1 Basic Data Transfer Tests
- [ ] FLD from memory (32-bit, 64-bit, 80-bit)
- [ ] FST to memory (32-bit, 64-bit, 80-bit)
- [ ] FLD/FST stack registers
- [ ] FXCH register exchange

### 9.2 Arithmetic Tests
- [ ] FADD, FSUB, FMUL, FDIV with memory operands
- [ ] FADD, FSUB, FMUL, FDIV with stack operands
- [ ] FSQRT, FABS

### 9.3 Transcendental Tests
- [ ] FSIN, FCOS with various angles
- [ ] FPTAN, FPATAN
- [ ] F2XM1, FYL2X

### 9.4 Control Tests
- [ ] FLDCW, FSTCW control word access
- [ ] FSTSW status word read
- [ ] FCLEX exception clearing
- [ ] FINIT initialization

### 9.5 Synchronization Tests
- [ ] FWAIT with busy FPU
- [ ] FWAIT with ready FPU
- [ ] Asynchronous operation without FWAIT

### 9.6 Exception Tests
- [ ] Division by zero detection
- [ ] Overflow/underflow detection
- [ ] Invalid operation detection
- [ ] Exception masking

---

## 10. Interface Validation

### 10.1 Signal Integrity
- All signals registered at clock edges
- No combinatorial loops
- Reset initializes to safe state

### 10.2 Protocol Compliance
- Handshake signals (valid/ack) one cycle
- Data stable during transfer
- Busy signal accurate during execution

### 10.3 Performance
- Single-cycle instruction acceptance
- Pipelined data transfers
- Minimal wait states for common operations

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-11-09 | FPU Team | Initial specification |
