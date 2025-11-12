# FPU 8087 Integration for PCXT_MiSTer

## Description

This integration incorporates a complete implementation of the Intel 8087 mathematical coprocessor (FPU) into the PCXT MiSTer project. The implementation is based on [Waldo Alvarez's MyPC project](https://github.com/waldoalvarez00/MyPC), which includes a fully functional 8087 FPU with IEEE 754 support.

## FPU Features

- ✅ **Complete 8087 instruction set**: Arithmetic operations, transcendental functions (SIN, COS, TAN, ATAN, LOG), and BCD operations
- ✅ **IEEE 754 compliance**: Standard floating-point implementation
- ✅ **Register stack**: 8 registers of 80 bits (ST0-ST7)
- ✅ **Multi-format operations**: Integers (16/32 bits), floating-point (32/64/80 bits), BCD
- ✅ **Transcendental functions**: Implemented using CORDIC algorithm
- ✅ **Full validation**: 165/165 tests passed in the original project

## Integration Architecture

### Module Structure

```
PCXT.sv (Top-level)
└── i8088 (CPU)
    ├── PFQ signals exposed for ESC detection
    └── i8088_FPU_Adapter (CPU-FPU Adapter)
        └── FPU8087_Integrated (FPU Core)
            ├── FPU_Instruction_Decoder (Instruction decoder)
            ├── FPU_CPU_Interface (CPU interface)
            └── FPU_Core_Wrapper (Operations core)
                ├── FPU_ArithmeticUnit (Arithmetic unit)
                ├── FPU_Transcendental (Transcendental functions)
                ├── FPU_Format_Converter_Unified (Format conversion)
                └── FPU_RegisterStack (Register stack)
```

### ESC Instruction Detection

Coprocessor instructions (ESC, opcodes D8h-DFh) are detected by monitoring the 8088 CPU's **Prefetch Queue (PFQ)**:

1. **PFQ Monitoring**: The adapter watches `fpu_pfq_top_byte` to detect ESC instructions
2. **ModR/M Capture**: The next PFQ byte contains the ModR/M byte needed to decode the operation
3. **Send to FPU**: The complete instruction (opcode + ModR/M) is sent to the FPU decoder
4. **CPU Control**: While the FPU processes, the `fpu_wait` signal halts the CPU (similar to the READY signal)

### CPU-FPU Interface Signals

#### From CPU (i8088.v):
```verilog
output [7:0]  fpu_pfq_top_byte   // Current byte from prefetch queue
output        fpu_pfq_empty      // Empty queue indicator
output [15:0] fpu_pfq_addr       // Prefetch address
input         fpu_wait           // Wait signal from FPU
```

#### In Adapter (i8088_FPU_Adapter.v):
```verilog
output        fpu_cpu_wait       // WAIT signal to CPU
output        fpu_detected_esc   // Debug: ESC instruction detected
output        fpu_active         // Debug: FPU processing
output [15:0] fpu_status_word    // FPU status word
```

## Modified Files

### Original Project Files
- **`rtl/8088/i8088.v`**: Added FPU interface signals and READY combination with fpu_wait
- **`PCXT.sv`**: FPU adapter instantiation and connections
- **`files.qip`**: Added reference to `rtl/FPU8087/FPU8087.qip`

### New Files
- **`rtl/FPU8087/`**: Directory with all FPU modules (132 .v/.sv files)
- **`rtl/FPU8087/i8088_FPU_Adapter.v`**: Specific adapter for PCXT i8088
- **`rtl/FPU8087/FPU8087.qip`**: File list for Quartus

## Operation

### FPU Instruction Execution Flow

```
1. CPU executes ESC instruction (e.g., D8 C1 - FADD ST(0), ST(1))
2. Adapter detects D8h in PFQ
3. Adapter captures C1h (ModR/M) from next byte
4. Adapter sends {D8h, C1h} to FPU_Instruction_Decoder
5. Decoder identifies: FADD, operands ST(0) and ST(1)
6. FPU_Core executes addition
7. fpu_wait keeps CPU waiting during execution
8. Result written to ST(0)
9. fpu_wait deactivates, CPU continues
```

### Adapter States

```
IDLE          → Waiting for ESC instruction
CAPTURE_ESC   → ESC opcode detected and captured
WAIT_MODRM    → Waiting for ModR/M byte
SEND_TO_FPU   → Sending instruction to FPU
WAIT_FPU      → FPU executing (cpu_wait active)
COMPLETE      → Instruction complete, return to IDLE
```

## BIOS Detection

The BIOS already includes 8087 detection code in:
- **`SW/8088_bios/src/cpu.inc`**: Coprocessor test routines
- **`SW/8088_bios/src/messages.inc`**: "Intel 8087" message

The detection test:
```assembly
; BIOS writes to control word and reads back
; If it gets 03FFh, the 8087 is present
cmp word [test_word], 03FFh
je fpu_detected
```

Once the FPU hardware is integrated and responds correctly, the BIOS will detect it automatically without modifications.

## Implementation Status

### ✅ Completed
- [x] Import of all FPU modules from MyPC
- [x] Creation of i8088_FPU_Adapter
- [x] Modification of i8088.v to expose PFQ signals
- [x] Integration in PCXT.sv
- [x] Configuration of .qip files for Quartus

### 🚧 Pending / Future Improvements
- [ ] Complete connection of FPU memory interface to system bus
- [ ] Implementation of memory data transfers (FLOAD, FSTORE)
- [ ] Testing with FPU programs (e.g., floating-point benchmarks)
- [ ] Timing and performance optimization
- [ ] Validation with period-accurate software (AutoCAD, etc.)

## Compilation

FPU modules are automatically included in Quartus compilation through:
```
files.qip → rtl/FPU8087/FPU8087.qip → [132 .v/.sv files]
```

## References

- **Original Project**: [MyPC - Waldo Alvarez](https://github.com/waldoalvarez00/MyPC)
- **Intel 8087 Documentation**: Intel 8087 Numeric Data Processor Datasheet
- **IEEE 754**: Standard for Floating-Point Arithmetic

## Credits

- **8087 FPU Implementation**: Waldo Alvarez (https://pipflow.com)
- **PCXT_MiSTer Project**: spark2k06 and contributors
- **MCL86 (8088 Core)**: Ted Fried, MicroCore Labs
- **FPU Integration**: Adaptation for PCXT_MiSTer

## License

FPU modules maintain the original copyright of Waldo Alvarez.
Integration follows the PCXT_MiSTer project license.
