#!/usr/bin/env python3
"""
FPU Microsequencer Simulator

This simulator executes microcode programs for the Intel 8087 FPU microsequencer.
It models the microsequencer state machine, FPU registers, and all micro-operations.

Usage:
  python microsim.py microcode.hex
  python microsim.py microcode.hex --verbose
  python microsim.py microcode.hex --test
"""

import sys
import argparse
import struct
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
from enum import IntEnum


# ============================================================================
# Opcode and Micro-operation Definitions (same as assembler)
# ============================================================================

class Opcode(IntEnum):
    """Main instruction opcodes"""
    NOP   = 0x0
    EXEC  = 0x1
    JUMP  = 0x2
    CALL  = 0x3
    RET   = 0x4
    HALT  = 0xF


class MicroOp(IntEnum):
    """Micro-operations (used when opcode == EXEC)"""
    # Basic operations (0x0-0xF)
    LOAD           = 0x1
    STORE          = 0x2
    SET_CONST      = 0x3
    ACCESS_CONST   = 0x4
    ADD_SUB        = 0x5  # immediate[0]: 0=add, 1=sub
    MUL            = 0x6  # Multiply temp_fp_a * temp_fp_b
    DIV            = 0x7  # Divide temp_fp_a / temp_fp_b
    SHIFT          = 0x8  # immediate[0]: 0=left, 1=right; immediate[7:1]=amount
    LOOP_INIT      = 0x9
    LOOP_DEC       = 0xA
    ABS            = 0xB
    NORMALIZE      = 0xC
    COMPARE        = 0xD  # Compare temp_fp_a with temp_fp_b, set flags
    REG_OPS        = 0xE  # immediate: 0=READ_STATUS, 1=READ_CONTROL, 2=READ_TAG, 3=WRITE_STATUS
    ROUND          = 0xF

    # Hardware unit interface operations (0x10-0x1F) - NEW!
    CALL_ARITH     = 0x10  # Start arithmetic operation
    WAIT_ARITH     = 0x11  # Wait for arithmetic completion
    LOAD_ARITH_RES = 0x12  # Load result from arithmetic unit
    CALL_STACK     = 0x13  # Execute stack operation
    WAIT_STACK     = 0x14  # Wait for stack completion
    LOAD_STACK_REG = 0x15  # Load from stack register
    STORE_STACK_REG= 0x16  # Store to stack register
    SET_STATUS     = 0x17  # Set status flags
    GET_STATUS     = 0x18  # Get status flags
    GET_CC         = 0x19  # Get condition codes


# ============================================================================
# FPU Extended Precision Float (80-bit) Helper
# ============================================================================

class ExtendedFloat:
    """Represents an 80-bit extended precision floating point number"""

    def __init__(self, value: int = 0):
        """Initialize from 80-bit integer representation"""
        self.bits = value & 0xFFFFFFFFFFFFFFFFFFFF

    @property
    def sign(self) -> int:
        """Get sign bit (bit 79)"""
        return (self.bits >> 79) & 1

    @property
    def exponent(self) -> int:
        """Get exponent (bits 78:64)"""
        return (self.bits >> 64) & 0x7FFF

    @property
    def mantissa(self) -> int:
        """Get mantissa (bits 63:0)"""
        return self.bits & 0xFFFFFFFFFFFFFFFF

    def to_float(self) -> float:
        """Convert to Python float (approximate)"""
        if self.bits == 0:
            return 0.0

        # Extract components
        sign = -1.0 if self.sign else 1.0
        exp = self.exponent - 0x3FFF  # Remove bias
        mant = self.mantissa / (2**63)  # Normalize

        if self.exponent == 0:  # Denormalized
            return sign * mant * (2 ** (exp + 1))
        elif self.exponent == 0x7FFF:  # Infinity or NaN
            return float('inf') * sign if self.mantissa == 0 else float('nan')
        else:  # Normalized
            return sign * mant * (2 ** exp)

    @classmethod
    def from_float(cls, value: float) -> 'ExtendedFloat':
        """Create from Python float (approximate)"""
        if value == 0.0:
            return cls(0)

        sign = 1 if value < 0 else 0
        value = abs(value)

        # Get exponent and mantissa
        import math
        if math.isinf(value):
            return cls((sign << 79) | (0x7FFF << 64))
        if math.isnan(value):
            return cls((sign << 79) | (0x7FFF << 64) | 1)

        exp = math.floor(math.log2(value))
        mant = int((value / (2 ** exp)) * (2 ** 63))

        exp_biased = (exp + 0x3FFF) & 0x7FFF

        bits = (sign << 79) | (exp_biased << 64) | (mant & 0xFFFFFFFFFFFFFFFF)
        return cls(bits)

    def __repr__(self):
        return f"ExtFloat(0x{self.bits:020X} ≈ {self.to_float()})"


# ============================================================================
# FPU State
# ============================================================================

@dataclass
class FPUState:
    """Complete FPU state"""
    # Stack registers (8 x 80-bit)
    stack: List[ExtendedFloat]

    # Control and status registers
    status_word: int = 0
    control_word: int = 0x037F  # Default 8087 value
    tag_word: int = 0xFFFF  # All empty

    # Temporary registers
    temp_reg: int = 0  # 64-bit general purpose
    temp_fp: ExtendedFloat = None  # 80-bit FP
    temp_fp_a: ExtendedFloat = None  # Operand A
    temp_fp_b: ExtendedFloat = None  # Operand B
    temp_result: ExtendedFloat = None  # Result storage

    # Math constant index
    math_const_index: int = 0

    # Loop register
    loop_reg: int = 0

    # Hardware unit simulation state (NEW)
    arith_busy: bool = False
    arith_result: ExtendedFloat = None
    arith_cycles_remaining: int = 0
    arith_cc_less: bool = False
    arith_cc_equal: bool = False
    arith_cc_greater: bool = False
    arith_cc_unordered: bool = False

    def __init__(self):
        self.stack = [ExtendedFloat(0) for _ in range(8)]
        self.temp_fp = ExtendedFloat(0)
        self.temp_fp_a = ExtendedFloat(0)
        self.temp_fp_b = ExtendedFloat(0)
        self.temp_result = ExtendedFloat(0)
        self.arith_result = ExtendedFloat(0)

    @property
    def stack_top(self) -> int:
        """Get stack top pointer from status word"""
        return (self.status_word >> 11) & 0x7

    def set_stack_top(self, value: int):
        """Set stack top pointer in status word"""
        self.status_word = (self.status_word & ~(0x7 << 11)) | ((value & 0x7) << 11)


# ============================================================================
# Microsequencer Simulator
# ============================================================================

class MicrosequencerSimulator:
    """Simulates the FPU microsequencer"""

    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.microcode_rom: List[int] = [0] * 4096
        self.fpu_state = FPUState()

        # Microsequencer state
        self.pc = 0
        self.call_stack: List[int] = []
        self.halted = False
        self.instruction_count = 0
        self.max_instructions = 10000  # Safety limit

        # Math constants ROM (simplified)
        self.math_constants = self._init_math_constants()

        # CPU bus interface
        self.cpu_data_in = 0
        self.cpu_data_out = 0

        # Initialize microcode subroutine library
        self._init_microcode_subroutines()

    def _init_math_constants(self) -> List[ExtendedFloat]:
        """Initialize mathematical constants"""
        import math
        constants = [ExtendedFloat(0)] * 64  # Expanded to 64 entries

        # Common constants (indices 0-9)
        constants[0] = ExtendedFloat.from_float(math.pi)       # π
        constants[1] = ExtendedFloat.from_float(math.e)        # e
        constants[2] = ExtendedFloat.from_float(0.0)           # 0.0
        constants[3] = ExtendedFloat.from_float(1.0)           # 1.0
        constants[4] = ExtendedFloat.from_float(2.0)           # 2.0
        constants[5] = ExtendedFloat.from_float(3.0)           # 3.0
        constants[6] = ExtendedFloat.from_float(math.pi/4)     # π/4
        constants[7] = ExtendedFloat.from_float(math.log(2))   # ln(2) ≈ 0.693147
        constants[8] = ExtendedFloat.from_float(0.5)           # 0.5
        constants[9] = ExtendedFloat.from_float(0.6072529350088812)  # K (CORDIC scaling factor)

        # Additional useful constants (indices 10-15)
        constants[10] = ExtendedFloat.from_float(1.0 / math.log(2))  # 1/ln(2) ≈ 1.442695 (for log2)
        constants[11] = ExtendedFloat.from_float(math.log10(2))      # log10(2) ≈ 0.301030
        constants[12] = ExtendedFloat.from_float(1.0 / 6.0)          # 1/6 (for Taylor series)
        constants[13] = ExtendedFloat.from_float(1.0 / 24.0)         # 1/24 (for Taylor series)
        constants[14] = ExtendedFloat.from_float(1.0 / 120.0)        # 1/120 (for Taylor series)
        constants[15] = ExtendedFloat.from_float(1.0 / 720.0)        # 1/720 (for Taylor series)

        # Arctangent table for CORDIC (atan(2^-i) for i=0 to 15) (indices 16-31)
        for i in range(16):
            constants[16 + i] = ExtendedFloat.from_float(math.atan(2.0 ** (-i)))

        # Extended arctangent table (indices 32-47) for higher precision
        for i in range(16, 32):
            constants[32 + (i - 16)] = ExtendedFloat.from_float(math.atan(2.0 ** (-i)))

        # Polynomial coefficients and other constants (indices 48-63)
        # These can be used for various approximations
        constants[48] = ExtendedFloat.from_float(math.sqrt(2))       # √2 ≈ 1.414214
        constants[49] = ExtendedFloat.from_float(1.0 / math.sqrt(2)) # 1/√2 ≈ 0.707107
        constants[50] = ExtendedFloat.from_float(math.pi / 2)        # π/2
        constants[51] = ExtendedFloat.from_float(2.0 * math.pi)      # 2π
        constants[52] = ExtendedFloat.from_float(math.log(10))       # ln(10) ≈ 2.302585
        constants[53] = ExtendedFloat.from_float(1.0 / 3.0)          # 1/3
        constants[54] = ExtendedFloat.from_float(1.0 / 5.0)          # 1/5
        constants[55] = ExtendedFloat.from_float(1.0 / 7.0)          # 1/7

        return constants

    def _init_microcode_subroutines(self):
        """
        Initialize microcode subroutine library.
        Matches MicroSequencer_Extended.v ROM initialization.

        Format: {opcode[31:28], micro_op[27:23], immediate[22:15], next_addr[14:0]}
        """
        OPCODE_EXEC = 0x1
        OPCODE_RET = 0x4
        MOP_CALL_ARITH = 0x10
        MOP_WAIT_ARITH = 0x11
        MOP_LOAD_ARITH_RES = 0x12

        # Program 0: FADD (0x0100-0x0103)
        self.microcode_rom[0x0100] = (OPCODE_EXEC << 28) | (MOP_CALL_ARITH << 23) | (0 << 15) | 0x0101
        self.microcode_rom[0x0101] = (OPCODE_EXEC << 28) | (MOP_WAIT_ARITH << 23) | (0 << 15) | 0x0102  # Fixed: advance to 0x0102 when done
        self.microcode_rom[0x0102] = (OPCODE_EXEC << 28) | (MOP_LOAD_ARITH_RES << 23) | (0 << 15) | 0x0103
        self.microcode_rom[0x0103] = (OPCODE_RET << 28) | (0 << 23) | (0 << 15) | 0

        # Program 1: FSUB (0x0110-0x0113)
        self.microcode_rom[0x0110] = (OPCODE_EXEC << 28) | (MOP_CALL_ARITH << 23) | (1 << 15) | 0x0111
        self.microcode_rom[0x0111] = (OPCODE_EXEC << 28) | (MOP_WAIT_ARITH << 23) | (0 << 15) | 0x0112
        self.microcode_rom[0x0112] = (OPCODE_EXEC << 28) | (MOP_LOAD_ARITH_RES << 23) | (0 << 15) | 0x0113
        self.microcode_rom[0x0113] = (OPCODE_RET << 28) | (0 << 23) | (0 << 15) | 0

        # Program 2: FMUL (0x0120-0x0123)
        self.microcode_rom[0x0120] = (OPCODE_EXEC << 28) | (MOP_CALL_ARITH << 23) | (2 << 15) | 0x0121
        self.microcode_rom[0x0121] = (OPCODE_EXEC << 28) | (MOP_WAIT_ARITH << 23) | (0 << 15) | 0x0122
        self.microcode_rom[0x0122] = (OPCODE_EXEC << 28) | (MOP_LOAD_ARITH_RES << 23) | (0 << 15) | 0x0123
        self.microcode_rom[0x0123] = (OPCODE_RET << 28) | (0 << 23) | (0 << 15) | 0

        # Program 3: FDIV (0x0130-0x0133)
        self.microcode_rom[0x0130] = (OPCODE_EXEC << 28) | (MOP_CALL_ARITH << 23) | (3 << 15) | 0x0131
        self.microcode_rom[0x0131] = (OPCODE_EXEC << 28) | (MOP_WAIT_ARITH << 23) | (0 << 15) | 0x0132
        self.microcode_rom[0x0132] = (OPCODE_EXEC << 28) | (MOP_LOAD_ARITH_RES << 23) | (0 << 15) | 0x0133
        self.microcode_rom[0x0133] = (OPCODE_RET << 28) | (0 << 23) | (0 << 15) | 0

        # Program 4: FSQRT (0x0140-0x0143)
        self.microcode_rom[0x0140] = (OPCODE_EXEC << 28) | (MOP_CALL_ARITH << 23) | (12 << 15) | 0x0141
        self.microcode_rom[0x0141] = (OPCODE_EXEC << 28) | (MOP_WAIT_ARITH << 23) | (0 << 15) | 0x0142
        self.microcode_rom[0x0142] = (OPCODE_EXEC << 28) | (MOP_LOAD_ARITH_RES << 23) | (0 << 15) | 0x0143
        self.microcode_rom[0x0143] = (OPCODE_RET << 28) | (0 << 23) | (0 << 15) | 0

        # Program 5: FSIN (0x0150-0x0153)
        self.microcode_rom[0x0150] = (OPCODE_EXEC << 28) | (MOP_CALL_ARITH << 23) | (13 << 15) | 0x0151
        self.microcode_rom[0x0151] = (OPCODE_EXEC << 28) | (MOP_WAIT_ARITH << 23) | (0 << 15) | 0x0152
        self.microcode_rom[0x0152] = (OPCODE_EXEC << 28) | (MOP_LOAD_ARITH_RES << 23) | (0 << 15) | 0x0153
        self.microcode_rom[0x0153] = (OPCODE_RET << 28) | (0 << 23) | (0 << 15) | 0

        # Program 6: FCOS (0x0160-0x0163)
        self.microcode_rom[0x0160] = (OPCODE_EXEC << 28) | (MOP_CALL_ARITH << 23) | (14 << 15) | 0x0161
        self.microcode_rom[0x0161] = (OPCODE_EXEC << 28) | (MOP_WAIT_ARITH << 23) | (0 << 15) | 0x0162
        self.microcode_rom[0x0162] = (OPCODE_EXEC << 28) | (MOP_LOAD_ARITH_RES << 23) | (0 << 15) | 0x0163
        self.microcode_rom[0x0163] = (OPCODE_RET << 28) | (0 << 23) | (0 << 15) | 0

    def load_hex_file(self, filename: str):
        """Load microcode from hex file"""
        try:
            with open(filename, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue

                    # Parse line: "ADDR: VALUE" or just "VALUE"
                    if ':' in line:
                        addr_str, value_str = line.split(':', 1)
                        addr = int(addr_str.strip(), 16)
                        value = int(value_str.strip(), 16)
                    else:
                        # Sequential loading
                        addr = len([x for x in self.microcode_rom if x != 0])
                        value = int(line.strip(), 16)

                    if 0 <= addr < len(self.microcode_rom):
                        self.microcode_rom[addr] = value

            if self.verbose:
                count = sum(1 for x in self.microcode_rom if x != 0)
                print(f"Loaded {count} microinstructions from {filename}")

        except Exception as e:
            print(f"Error loading {filename}: {e}", file=sys.stderr)
            raise

    def decode_instruction(self, instr: int) -> Tuple[int, int, int, int]:
        """Decode a 32-bit microinstruction

        Format (extended for hardware unit support):
        [31:28] - opcode (4 bits)
        [27:23] - micro_op (5 bits - extended!)
        [22:15] - immediate (8 bits)
        [14:0]  - next_addr (15 bits)
        """
        opcode = (instr >> 28) & 0xF
        micro_op = (instr >> 23) & 0x1F  # Extended to 5 bits
        immediate = (instr >> 15) & 0xFF
        next_addr = instr & 0x7FFF  # 15 bits
        return opcode, micro_op, immediate, next_addr

    def execute_instruction(self, instr: int) -> bool:
        """Execute a single microinstruction. Returns True if should continue."""
        opcode, micro_op, immediate, next_addr = self.decode_instruction(instr)

        if self.verbose:
            print(f"PC={self.pc:04X}: Instr={instr:08X} Op={opcode:X} MicroOp={micro_op:X} Imm={immediate:02X} Next={next_addr:04X}")

        # Execute based on opcode
        if opcode == Opcode.NOP:
            self.pc = next_addr if next_addr != 0 else self.pc + 1

        elif opcode == Opcode.HALT:
            if self.verbose:
                print("HALT: Microprogram complete")
            self.halted = True
            return False

        elif opcode == Opcode.JUMP:
            if self.verbose:
                print(f"  JUMP to {next_addr:04X}")
            self.pc = next_addr

        elif opcode == Opcode.CALL:
            if self.verbose:
                print(f"  CALL {next_addr:04X} (return addr={self.pc + 1:04X})")
            self.call_stack.append(self.pc + 1)
            self.pc = next_addr

        elif opcode == Opcode.RET:
            if self.call_stack:
                ret_addr = self.call_stack.pop()
                if self.verbose:
                    print(f"  RET to {ret_addr:04X}")
                self.pc = ret_addr
            else:
                if self.verbose:
                    print("  RET: Call stack empty!")
                self.pc = 0

        elif opcode == Opcode.EXEC:
            self._execute_micro_op(micro_op, immediate, next_addr)

        else:
            if self.verbose:
                print(f"  Unknown opcode: {opcode}")
            self.pc = next_addr if next_addr != 0 else self.pc + 1

        return True

    def _execute_micro_op(self, micro_op: int, immediate: int, next_addr: int):
        """Execute a micro-operation"""

        if micro_op == MicroOp.LOAD:
            # Load from CPU bus into temp_reg
            self.fpu_state.temp_reg = self.cpu_data_in
            if self.verbose:
                print(f"  LOAD: temp_reg = 0x{self.cpu_data_in:016X}")

        elif micro_op == MicroOp.STORE:
            # Store temp_reg to CPU bus
            self.cpu_data_out = self.fpu_state.temp_reg
            if self.verbose:
                print(f"  STORE: cpu_data_out = 0x{self.cpu_data_out:016X}")

        elif micro_op == MicroOp.SET_CONST:
            # Set math constant index
            self.fpu_state.math_const_index = immediate & 0x1F
            if self.verbose:
                print(f"  SET_CONST: index = {self.fpu_state.math_const_index}")

        elif micro_op == MicroOp.ACCESS_CONST:
            # Access math constant
            idx = self.fpu_state.math_const_index
            self.fpu_state.temp_fp = self.math_constants[idx]
            if self.verbose:
                print(f"  ACCESS_CONST: temp_fp = {self.fpu_state.temp_fp}")

        elif micro_op == MicroOp.ADD_SUB:
            # Add or subtract (immediate[0] = 0:add, 1:sub)
            is_sub = immediate & 1
            a_val = self.fpu_state.temp_fp_a.to_float()
            b_val = self.fpu_state.temp_fp_b.to_float()

            if is_sub:
                result = a_val - b_val
                if self.verbose:
                    print(f"  SUB: {a_val} - {b_val} = {result}")
            else:
                result = a_val + b_val
                if self.verbose:
                    print(f"  ADD: {a_val} + {b_val} = {result}")

            self.fpu_state.temp_fp = ExtendedFloat.from_float(result)

        elif micro_op == MicroOp.MUL:
            # Multiply temp_fp_a * temp_fp_b
            a_val = self.fpu_state.temp_fp_a.to_float()
            b_val = self.fpu_state.temp_fp_b.to_float()
            result = a_val * b_val
            self.fpu_state.temp_fp = ExtendedFloat.from_float(result)
            if self.verbose:
                print(f"  MUL: {a_val} * {b_val} = {result}")

        elif micro_op == MicroOp.DIV:
            # Divide temp_fp_a / temp_fp_b
            a_val = self.fpu_state.temp_fp_a.to_float()
            b_val = self.fpu_state.temp_fp_b.to_float()
            if b_val == 0:
                result = float('inf') if a_val >= 0 else float('-inf')
            else:
                result = a_val / b_val
            self.fpu_state.temp_fp = ExtendedFloat.from_float(result)
            if self.verbose:
                print(f"  DIV: {a_val} / {b_val} = {result}")

        elif micro_op == MicroOp.SHIFT:
            # Shift operation (left or right)
            direction = immediate & 1  # 0=left, 1=right
            shift_amount = (immediate >> 1) & 0x7F
            if direction == 0:
                # Left shift
                self.fpu_state.temp_reg = (self.fpu_state.temp_reg << shift_amount) & 0xFFFFFFFFFFFFFFFF
                if self.verbose:
                    print(f"  SHIFT_LEFT: {shift_amount} bits")
            else:
                # Right shift
                self.fpu_state.temp_reg = self.fpu_state.temp_reg >> shift_amount
                if self.verbose:
                    print(f"  SHIFT_RIGHT: {shift_amount} bits")

        elif micro_op == MicroOp.LOOP_INIT:
            # Initialize loop counter
            self.fpu_state.loop_reg = immediate
            if self.verbose:
                print(f"  LOOP_INIT: count = {immediate}")

        elif micro_op == MicroOp.LOOP_DEC:
            # Decrement loop counter and jump if not zero
            if self.fpu_state.loop_reg > 0:
                self.fpu_state.loop_reg -= 1
                if self.verbose:
                    print(f"  LOOP_DEC: count = {self.fpu_state.loop_reg}, jumping to {next_addr:04X}")
                self.pc = next_addr
                return  # Don't increment PC at end
            else:
                if self.verbose:
                    print(f"  LOOP_DEC: count = 0, continuing")
                self.pc = self.pc + 1
                return

        elif micro_op == MicroOp.ABS:
            # Absolute value
            val = self.fpu_state.temp_fp.to_float()
            result = abs(val)
            self.fpu_state.temp_fp = ExtendedFloat.from_float(result)
            if self.verbose:
                print(f"  ABS: |{val}| = {result}")

        elif micro_op == MicroOp.ROUND:
            # Round (simplified - just use Python rounding)
            val = self.fpu_state.temp_fp.to_float()
            result = round(val)
            self.fpu_state.temp_fp = ExtendedFloat.from_float(result)
            if self.verbose:
                print(f"  ROUND: round({val}) = {result}")

        elif micro_op == MicroOp.NORMALIZE:
            # Normalize (simplified - already normalized in conversion)
            if self.verbose:
                print(f"  NORMALIZE: {self.fpu_state.temp_fp}")

        elif micro_op == MicroOp.COMPARE:
            # Compare temp_fp_a with temp_fp_b and set flags
            a_val = self.fpu_state.temp_fp_a.to_float()
            b_val = self.fpu_state.temp_fp_b.to_float()

            # Set condition codes in status word (bits 14, 10, 9, 8 = C3, C2, C1, C0)
            # C3 C2 C1 C0
            #  0  0  0  0 : a > b
            #  0  0  0  1 : a < b
            #  1  0  0  0 : a == b
            #  1  1  1  1 : unordered (NaN)
            if a_val > b_val:
                cc = 0b0000
            elif a_val < b_val:
                cc = 0b0001
            else:  # a_val == b_val
                cc = 0b1000

            # Update status word with condition codes
            # C3=bit 14, C2=bit 10, C1=bit 9, C0=bit 8
            self.fpu_state.status_word = (self.fpu_state.status_word & 0x3CFF) | \
                                        ((cc & 0x1) << 8) | \
                                        ((cc & 0x2) << 8) | \
                                        ((cc & 0x4) << 8) | \
                                        ((cc & 0x8) << 11)

            if self.verbose:
                print(f"  COMPARE: {a_val} vs {b_val}, flags={cc:04b}")

        elif micro_op == MicroOp.REG_OPS:
            # Consolidated register operations
            reg_op = immediate & 0xF

            if reg_op == 0:  # READ_STATUS
                self.fpu_state.temp_reg = self.fpu_state.status_word & 0xFFFF
                if self.verbose:
                    print(f"  READ_STATUS: 0x{self.fpu_state.status_word:04X}")

            elif reg_op == 1:  # READ_CONTROL
                self.fpu_state.temp_reg = self.fpu_state.control_word & 0xFFFF
                if self.verbose:
                    print(f"  READ_CONTROL: 0x{self.fpu_state.control_word:04X}")

            elif reg_op == 2:  # READ_TAG
                self.fpu_state.temp_reg = self.fpu_state.tag_word & 0xFFFF
                if self.verbose:
                    print(f"  READ_TAG: 0x{self.fpu_state.tag_word:04X}")

            elif reg_op == 3:  # WRITE_STATUS
                self.fpu_state.status_word = self.fpu_state.temp_reg & 0xFFFF
                if self.verbose:
                    print(f"  WRITE_STATUS: 0x{self.fpu_state.status_word:04X}")

        # =====================================================================
        # Hardware Unit Interface Operations (NEW!)
        # =====================================================================

        elif micro_op == MicroOp.CALL_ARITH:
            # Start arithmetic operation (simulates FPU_ArithmeticUnit)
            arith_op = immediate & 0x1F
            self._start_arithmetic_operation(arith_op)
            if self.verbose:
                print(f"  CALL_ARITH: op={arith_op} started")

        elif micro_op == MicroOp.WAIT_ARITH:
            # Wait for arithmetic completion
            if self.fpu_state.arith_cycles_remaining > 0:
                self.fpu_state.arith_cycles_remaining -= 1

            if self.fpu_state.arith_cycles_remaining == 0:
                # Arithmetic complete - advance to next instruction
                self.fpu_state.arith_busy = False
                if self.verbose:
                    print(f"  WAIT_ARITH: complete, result={self.fpu_state.arith_result}")
                # Will advance to next_addr at end of function
            else:
                # Still waiting - loop at current PC
                self.pc = self.pc
                if self.verbose:
                    print(f"  WAIT_ARITH: waiting ({self.fpu_state.arith_cycles_remaining} cycles left)")
                return  # Don't advance PC - return early to loop

        elif micro_op == MicroOp.LOAD_ARITH_RES:
            # Load result from arithmetic unit
            self.fpu_state.temp_result = self.fpu_state.arith_result
            if self.verbose:
                print(f"  LOAD_ARITH_RES: temp_result = {self.fpu_state.temp_result}")

        elif micro_op == MicroOp.LOAD_STACK_REG:
            # Load from stack register
            stack_idx = immediate & 0x7
            self.fpu_state.temp_result = self.fpu_state.stack[stack_idx]
            if self.verbose:
                print(f"  LOAD_STACK_REG: ST({stack_idx}) = {self.fpu_state.temp_result}")

        elif micro_op == MicroOp.STORE_STACK_REG:
            # Store to stack register
            stack_idx = immediate & 0x7
            self.fpu_state.stack[stack_idx] = self.fpu_state.temp_result
            if self.verbose:
                print(f"  STORE_STACK_REG: ST({stack_idx}) = {self.fpu_state.temp_result}")

        elif micro_op == MicroOp.GET_STATUS:
            # Get status word
            self.fpu_state.temp_reg = self.fpu_state.status_word & 0xFFFF
            if self.verbose:
                print(f"  GET_STATUS: 0x{self.fpu_state.status_word:04X}")

        elif micro_op == MicroOp.SET_STATUS:
            # Set status word
            self.fpu_state.status_word = self.fpu_state.temp_reg & 0xFFFF
            if self.verbose:
                print(f"  SET_STATUS: 0x{self.fpu_state.status_word:04X}")

        elif micro_op == MicroOp.GET_CC:
            # Get condition codes
            self.fpu_state.temp_reg = (
                (1 if self.fpu_state.arith_cc_less else 0) |
                ((1 if self.fpu_state.arith_cc_equal else 0) << 1) |
                ((1 if self.fpu_state.arith_cc_greater else 0) << 2) |
                ((1 if self.fpu_state.arith_cc_unordered else 0) << 3)
            )
            if self.verbose:
                print(f"  GET_CC: L={self.fpu_state.arith_cc_less} "
                      f"E={self.fpu_state.arith_cc_equal} "
                      f"G={self.fpu_state.arith_cc_greater} "
                      f"U={self.fpu_state.arith_cc_unordered}")

        else:
            if self.verbose:
                print(f"  Unknown micro-op: {micro_op}")

        # Default: advance to next address
        self.pc = next_addr

    def _start_arithmetic_operation(self, arith_op: int):
        """
        Simulate starting an arithmetic operation (FPU_Arith met Unit).
        Maps operation codes to FP operations and sets busy state.

        Operation codes match FPU_ArithmeticUnit.v:
        0=ADD, 1=SUB, 2=MUL, 3=DIV, 4=INT16_TO_FP, 5=INT32_TO_FP,
        6=FP_TO_INT16, 7=FP_TO_INT32, 8=FP32_TO_FP80, 9=FP64_TO_FP80,
        10=FP80_TO_FP32, 11=FP80_TO_FP64, 12=SQRT, 13=SIN, 14=COS
        """
        import math

        self.fpu_state.arith_busy = True

        a_val = self.fpu_state.temp_fp_a.to_float()
        b_val = self.fpu_state.temp_fp_b.to_float()
        result = 0.0

        # Map operation code to arithmetic function
        if arith_op == 0:  # ADD
            result = a_val + b_val
            self.fpu_state.arith_cycles_remaining = 3
        elif arith_op == 1:  # SUB
            result = a_val - b_val
            self.fpu_state.arith_cycles_remaining = 3
        elif arith_op == 2:  # MUL
            result = a_val * b_val
            self.fpu_state.arith_cycles_remaining = 5
        elif arith_op == 3:  # DIV
            if b_val == 0:
                result = float('inf') if a_val >= 0 else float('-inf')
            else:
                result = a_val / b_val
            self.fpu_state.arith_cycles_remaining = 10
        elif arith_op == 12:  # SQRT
            if a_val < 0:
                result = float('nan')
            else:
                result = math.sqrt(a_val)
            self.fpu_state.arith_cycles_remaining = 8
        elif arith_op == 13:  # SIN
            result = math.sin(a_val)
            self.fpu_state.arith_cycles_remaining = 15
        elif arith_op == 14:  # COS
            result = math.cos(a_val)
            self.fpu_state.arith_cycles_remaining = 15
        else:
            # Unsupported operation - just pass through
            result = a_val
            self.fpu_state.arith_cycles_remaining = 1

        # Store result and set condition codes
        self.fpu_state.arith_result = ExtendedFloat.from_float(result)

        # Update condition codes (for comparison operations)
        if math.isnan(a_val) or math.isnan(b_val) or math.isnan(result):
            self.fpu_state.arith_cc_unordered = True
            self.fpu_state.arith_cc_less = False
            self.fpu_state.arith_cc_equal = False
            self.fpu_state.arith_cc_greater = False
        else:
            self.fpu_state.arith_cc_unordered = False
            self.fpu_state.arith_cc_less = (a_val < b_val)
            self.fpu_state.arith_cc_equal = (a_val == b_val)
            self.fpu_state.arith_cc_greater = (a_val > b_val)

    def run(self, start_addr: int = 0) -> bool:
        """Run microcode starting at given address"""
        self.pc = start_addr
        self.halted = False
        self.instruction_count = 0

        if self.verbose:
            print(f"\n{'='*60}")
            print(f"Starting execution at address 0x{start_addr:04X}")
            print(f"{'='*60}\n")

        while not self.halted and self.instruction_count < self.max_instructions:
            if self.pc >= len(self.microcode_rom):
                if self.verbose:
                    print(f"PC out of range: {self.pc:04X}")
                break

            instr = self.microcode_rom[self.pc]
            if instr == 0:
                if self.verbose:
                    print(f"Encountered zero instruction at {self.pc:04X}")
                break

            if not self.execute_instruction(instr):
                break

            self.instruction_count += 1

        if self.verbose:
            print(f"\n{'='*60}")
            print(f"Execution complete: {self.instruction_count} instructions")
            print(f"{'='*60}\n")

        return self.halted

    def print_state(self):
        """Print current FPU state"""
        print("\n=== FPU State ===")
        print(f"Status Word:  0x{self.fpu_state.status_word:04X}")
        print(f"Control Word: 0x{self.fpu_state.control_word:04X}")
        print(f"Tag Word:     0x{self.fpu_state.tag_word:04X}")
        print(f"Temp Reg:     0x{self.fpu_state.temp_reg:016X}")
        print(f"Temp FP:      {self.fpu_state.temp_fp}")
        print(f"Loop Reg:     {self.fpu_state.loop_reg}")
        print(f"CPU Out:      0x{self.cpu_data_out:016X}")
        print()


# ============================================================================
# Test Framework
# ============================================================================

class MicrocodeTest:
    """Test case for microcode execution"""

    def __init__(self, name: str, hex_file: str):
        self.name = name
        self.hex_file = hex_file
        self.setup_fn = None
        self.verify_fn = None

    def setup(self, fn):
        """Decorator for setup function"""
        self.setup_fn = fn
        return fn

    def verify(self, fn):
        """Decorator for verification function"""
        self.verify_fn = fn
        return fn

    def run(self, verbose: bool = False) -> bool:
        """Run the test"""
        print(f"\n{'='*60}")
        print(f"Test: {self.name}")
        print(f"{'='*60}")

        sim = MicrosequencerSimulator(verbose=verbose)

        # Setup
        if self.setup_fn:
            self.setup_fn(sim)

        # Load and run
        sim.load_hex_file(self.hex_file)
        success = sim.run()

        # Print state
        if verbose:
            sim.print_state()

        # Verify
        if self.verify_fn:
            try:
                self.verify_fn(sim)
                print(f"✓ PASS: {self.name}")
                return True
            except AssertionError as e:
                print(f"✗ FAIL: {self.name}")
                print(f"  {e}")
                return False
        else:
            if success:
                print(f"✓ PASS: {self.name} (halted normally)")
                return True
            else:
                print(f"✗ FAIL: {self.name} (did not halt)")
                return False


# ============================================================================
# Main Program
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='FPU Microsequencer Simulator'
    )
    parser.add_argument('hexfile', nargs='?', help='Microcode hex file to execute')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Verbose execution trace')
    parser.add_argument('-t', '--test', action='store_true',
                       help='Run test suite')
    parser.add_argument('-s', '--start', type=lambda x: int(x, 0), default=0,
                       help='Start address (default: 0)')

    args = parser.parse_args()

    if args.test:
        # Run test suite
        from test_microcode import run_all_tests
        success = run_all_tests(verbose=args.verbose)
        return 0 if success else 1

    if not args.hexfile:
        parser.print_help()
        return 1

    # Run single program
    sim = MicrosequencerSimulator(verbose=args.verbose)
    sim.load_hex_file(args.hexfile)
    success = sim.run(start_addr=args.start)

    sim.print_state()

    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
