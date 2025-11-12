#!/usr/bin/env python3
"""
Microsequencer Assembler for Intel 8087 FPU

This assembler generates microcode for the FPU microsequencer (sequencer.v).
It supports a simple assembly language with labels, directives, and comments.

Microinstruction Format (32 bits):
  [31:28] opcode     - Instruction type (NOP, EXEC, JUMP, CALL, RET, HALT)
  [27:24] micro_op   - Micro-operation (when opcode == EXEC)
  [23:16] immediate  - 8-bit immediate value
  [15:0]  next_addr  - Next address (or branch target)

Usage:
  python microasm.py input.asm -o output.hex
  python microasm.py input.asm -o output.bin -f binary
  python microasm.py input.asm -o output.v -f verilog
"""

import sys
import argparse
import re
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass
from enum import IntEnum


# ============================================================================
# Opcode and Micro-operation Definitions
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


# ============================================================================
# Instruction Class
# ============================================================================

@dataclass
class Instruction:
    """Represents a single microinstruction"""
    opcode: int
    micro_op: int
    immediate: int
    next_addr: int
    label: Optional[str] = None
    source_line: Optional[str] = None
    line_number: int = 0

    def encode(self) -> int:
        """Encode instruction to 32-bit value"""
        if self.opcode < 0 or self.opcode > 15:
            raise ValueError(f"Opcode out of range: {self.opcode}")
        if self.micro_op < 0 or self.micro_op > 15:
            raise ValueError(f"Micro-op out of range: {self.micro_op}")
        if self.immediate < 0 or self.immediate > 255:
            raise ValueError(f"Immediate out of range: {self.immediate}")
        if self.next_addr < 0 or self.next_addr > 65535:
            raise ValueError(f"Next address out of range: {self.next_addr}")

        return ((self.opcode & 0xF) << 28) | \
               ((self.micro_op & 0xF) << 24) | \
               ((self.immediate & 0xFF) << 16) | \
               (self.next_addr & 0xFFFF)

    def to_hex(self) -> str:
        """Convert to hexadecimal string"""
        return f"{self.encode():08X}"

    def to_binary(self) -> str:
        """Convert to binary string"""
        return f"{self.encode():032b}"


# ============================================================================
# Assembler Class
# ============================================================================

class MicroAssembler:
    """Assembler for microsequencer code"""

    def __init__(self):
        self.instructions: List[Instruction] = []
        self.labels: Dict[str, int] = {}
        self.symbols: Dict[str, int] = {}
        self.current_address = 0
        self.errors: List[str] = []
        self.warnings: List[str] = []

    def error(self, msg: str, line_num: int = 0):
        """Record an error"""
        if line_num:
            self.errors.append(f"Line {line_num}: {msg}")
        else:
            self.errors.append(msg)

    def warning(self, msg: str, line_num: int = 0):
        """Record a warning"""
        if line_num:
            self.warnings.append(f"Line {line_num}: {msg}")
        else:
            self.warnings.append(msg)

    def parse_number(self, s: str) -> Optional[int]:
        """Parse a number in various formats (decimal, hex, binary)"""
        s = s.strip().upper()
        try:
            if s.startswith('0X'):
                return int(s[2:], 16)
            elif s.startswith('0B'):
                return int(s[2:], 2)
            elif s.startswith('0O'):
                return int(s[2:], 8)
            elif s.isdigit():
                return int(s)
            else:
                return None
        except ValueError:
            return None

    def parse_operand(self, operand: str, line_num: int = 0) -> int:
        """Parse an operand (number, label, or symbol)"""
        operand = operand.strip()

        # Check if it's a symbol
        if operand in self.symbols:
            return self.symbols[operand]

        # Check if it's a label
        if operand in self.labels:
            return self.labels[operand]

        # Try to parse as number
        value = self.parse_number(operand)
        if value is not None:
            return value

        # Unknown operand
        self.error(f"Unknown operand: {operand}", line_num)
        return 0

    def parse_line(self, line: str, line_num: int) -> Optional[Instruction]:
        """Parse a single line of assembly"""
        # Remove comments
        if ';' in line:
            line = line[:line.index(';')]
        if '//' in line:
            line = line[:line.index('//')]

        line = line.strip()
        if not line:
            return None

        # Check for label (but don't register it - already done in pass 1)
        label = None
        if ':' in line:
            parts = line.split(':', 1)
            label = parts[0].strip()
            line = parts[1].strip() if len(parts) > 1 else ""

            if not line:
                return None

        # Check for directives
        if line.startswith('.'):
            self.parse_directive(line, line_num)
            return None

        # Parse instruction
        parts = re.split(r'[,\s]+', line)
        mnemonic = parts[0].upper()

        # Default values
        opcode = 0
        micro_op = 0
        immediate = 0
        next_addr = self.current_address + 1  # Default: next sequential address

        # Parse based on mnemonic
        if mnemonic == 'NOP':
            opcode = Opcode.NOP
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'HALT':
            opcode = Opcode.HALT

        elif mnemonic == 'JUMP' or mnemonic == 'JMP':
            opcode = Opcode.JUMP
            if len(parts) < 2:
                self.error("JUMP requires a target address", line_num)
            else:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'CALL':
            opcode = Opcode.CALL
            if len(parts) < 2:
                self.error("CALL requires a target address", line_num)
            else:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'RET':
            opcode = Opcode.RET

        # Micro-operations (EXEC instructions)
        elif mnemonic == 'LOAD':
            opcode = Opcode.EXEC
            micro_op = MicroOp.LOAD
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'STORE':
            opcode = Opcode.EXEC
            micro_op = MicroOp.STORE
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'SET_CONST':
            opcode = Opcode.EXEC
            micro_op = MicroOp.SET_CONST
            if len(parts) < 2:
                self.error("SET_CONST requires an immediate value", line_num)
            else:
                immediate = self.parse_operand(parts[1], line_num)
                if len(parts) > 2:
                    next_addr = self.parse_operand(parts[2], line_num)

        elif mnemonic == 'ACCESS_CONST':
            opcode = Opcode.EXEC
            micro_op = MicroOp.ACCESS_CONST
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'ADD':
            opcode = Opcode.EXEC
            micro_op = MicroOp.ADD_SUB
            immediate = 0  # 0 = add
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'SUB':
            opcode = Opcode.EXEC
            micro_op = MicroOp.ADD_SUB
            immediate = 1  # 1 = subtract
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'MUL':
            opcode = Opcode.EXEC
            micro_op = MicroOp.MUL
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'DIV':
            opcode = Opcode.EXEC
            micro_op = MicroOp.DIV
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'SHIFT_LEFT':
            opcode = Opcode.EXEC
            micro_op = MicroOp.SHIFT
            if len(parts) < 2:
                self.error("SHIFT_LEFT requires a shift amount", line_num)
            else:
                shift_amount = self.parse_operand(parts[1], line_num)
                immediate = (shift_amount << 1) | 0  # direction=0 (left)
                if len(parts) > 2:
                    next_addr = self.parse_operand(parts[2], line_num)

        elif mnemonic == 'SHIFT_RIGHT':
            opcode = Opcode.EXEC
            micro_op = MicroOp.SHIFT
            if len(parts) < 2:
                self.error("SHIFT_RIGHT requires a shift amount", line_num)
            else:
                shift_amount = self.parse_operand(parts[1], line_num)
                immediate = (shift_amount << 1) | 1  # direction=1 (right)
                if len(parts) > 2:
                    next_addr = self.parse_operand(parts[2], line_num)

        elif mnemonic == 'COMPARE':
            opcode = Opcode.EXEC
            micro_op = MicroOp.COMPARE
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'LOOP_INIT':
            opcode = Opcode.EXEC
            micro_op = MicroOp.LOOP_INIT
            if len(parts) < 2:
                self.error("LOOP_INIT requires a count value", line_num)
            else:
                immediate = self.parse_operand(parts[1], line_num)
                if len(parts) > 2:
                    next_addr = self.parse_operand(parts[2], line_num)

        elif mnemonic == 'LOOP_DEC':
            opcode = Opcode.EXEC
            micro_op = MicroOp.LOOP_DEC
            if len(parts) < 2:
                self.error("LOOP_DEC requires a target address", line_num)
            else:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'ABS':
            opcode = Opcode.EXEC
            micro_op = MicroOp.ABS
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'ROUND':
            opcode = Opcode.EXEC
            micro_op = MicroOp.ROUND
            if len(parts) < 2:
                self.error("ROUND requires a rounding mode", line_num)
            else:
                immediate = self.parse_operand(parts[1], line_num)
                if len(parts) > 2:
                    next_addr = self.parse_operand(parts[2], line_num)

        elif mnemonic == 'NORMALIZE':
            opcode = Opcode.EXEC
            micro_op = MicroOp.NORMALIZE
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'READ_STATUS':
            opcode = Opcode.EXEC
            micro_op = MicroOp.REG_OPS
            immediate = 0  # READ_STATUS
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'READ_CONTROL':
            opcode = Opcode.EXEC
            micro_op = MicroOp.REG_OPS
            immediate = 1  # READ_CONTROL
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'READ_TAG':
            opcode = Opcode.EXEC
            micro_op = MicroOp.REG_OPS
            immediate = 2  # READ_TAG
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        elif mnemonic == 'WRITE_STATUS':
            opcode = Opcode.EXEC
            micro_op = MicroOp.REG_OPS
            immediate = 3  # WRITE_STATUS
            if len(parts) > 1:
                next_addr = self.parse_operand(parts[1], line_num)

        else:
            self.error(f"Unknown mnemonic: {mnemonic}", line_num)
            return None

        return Instruction(
            opcode=opcode,
            micro_op=micro_op,
            immediate=immediate,
            next_addr=next_addr,
            label=label,
            source_line=line,
            line_number=line_num
        )

    def parse_directive(self, line: str, line_num: int):
        """Parse assembler directives"""
        # Remove comments first
        if ';' in line:
            line = line[:line.index(';')]
        if '//' in line:
            line = line[:line.index('//')]

        parts = line.split(None, 1)
        directive = parts[0].upper()

        if directive == '.ORG':
            if len(parts) < 2:
                self.error(".ORG requires an address", line_num)
            else:
                addr = self.parse_number(parts[1].strip())
                if addr is not None:
                    self.current_address = addr
                else:
                    self.error(f"Invalid address: {parts[1]}", line_num)

        elif directive == '.EQU' or directive == '.DEFINE':
            if len(parts) < 2:
                self.error(f"{directive} requires name and value", line_num)
            else:
                match = re.match(r'(\w+)\s*=\s*(.+)', parts[1])
                if match:
                    name, value = match.groups()
                    value = value.strip()
                    val = self.parse_number(value)
                    if val is not None:
                        self.symbols[name.upper()] = val
                    else:
                        self.error(f"Invalid value: {value}", line_num)
                else:
                    self.error(f"Invalid {directive} syntax", line_num)

        elif directive == '.ALIGN':
            if len(parts) < 2:
                alignment = 4
            else:
                alignment = self.parse_number(parts[1])
                if alignment is None:
                    self.error(f"Invalid alignment value", line_num)
                    return

            remainder = self.current_address % alignment
            if remainder != 0:
                self.current_address += (alignment - remainder)

        else:
            self.error(f"Unknown directive: {directive}", line_num)

    def assemble(self, source: str) -> bool:
        """Assemble source code"""
        # Reset state
        self.labels = {}
        self.instructions = []
        self.current_address = 0

        # First pass: collect labels and symbols
        lines = source.split('\n')
        temp_labels = {}
        temp_address = 0

        for line_num, line in enumerate(lines, 1):
            # Skip empty lines and comments
            line = line.strip()
            if not line or line.startswith(';') or line.startswith('//'):
                continue

            # Handle label-only lines
            if ':' in line:
                parts = line.split(':', 1)
                label = parts[0].strip()
                rest = parts[1].strip() if len(parts) > 1 else ""

                if label and label not in temp_labels:
                    temp_labels[label] = temp_address

                if not rest or rest.startswith(';') or rest.startswith('//'):
                    continue

            # Check for directives that affect address
            if line.startswith('.ORG'):
                match = re.match(r'\.ORG\s+(\S+)', line, re.IGNORECASE)
                if match:
                    addr = self.parse_number(match.group(1))
                    if addr is not None:
                        temp_address = addr
                continue
            elif line.startswith('.ALIGN'):
                match = re.match(r'\.ALIGN\s*(\d+)?', line, re.IGNORECASE)
                alignment = 4
                if match and match.group(1):
                    alignment = int(match.group(1))
                remainder = temp_address % alignment
                if remainder != 0:
                    temp_address += (alignment - remainder)
                continue
            elif line.startswith('.'):
                self.parse_directive(line, line_num)
                continue

            # Count instruction
            temp_address += 1

        # Copy labels
        self.labels = temp_labels

        # Second pass: generate code
        self.current_address = 0
        self.instructions = []

        for line_num, line in enumerate(lines, 1):
            instr = self.parse_line(line, line_num)
            if instr is not None:
                self.instructions.append(instr)
                self.current_address += 1

        return len(self.errors) == 0

    def generate_hex(self) -> str:
        """Generate Intel HEX format output"""
        lines = []
        for i, instr in enumerate(self.instructions):
            lines.append(f"{i:04X}: {instr.to_hex()}")
        return '\n'.join(lines)

    def generate_verilog(self) -> str:
        """Generate Verilog $readmemh format"""
        lines = []
        for instr in self.instructions:
            lines.append(instr.to_hex())
        return '\n'.join(lines)

    def generate_binary(self) -> bytes:
        """Generate binary output"""
        data = bytearray()
        for instr in self.instructions:
            value = instr.encode()
            data.extend(value.to_bytes(4, byteorder='big'))
        return bytes(data)

    def generate_listing(self) -> str:
        """Generate assembly listing with addresses and encoded values"""
        lines = []
        lines.append("Address  Encoded    Source")
        lines.append("-" * 60)
        for i, instr in enumerate(self.instructions):
            label = f"{instr.label}:" if instr.label else ""
            source = instr.source_line or ""
            lines.append(f"{i:04X}    {instr.to_hex()}   {label:15} {source}")
        return '\n'.join(lines)


# ============================================================================
# Main Program
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='Microsequencer Assembler for Intel 8087 FPU'
    )
    parser.add_argument('input', help='Input assembly file')
    parser.add_argument('-o', '--output', help='Output file')
    parser.add_argument('-f', '--format',
                       choices=['hex', 'verilog', 'binary', 'listing'],
                       default='hex',
                       help='Output format (default: hex)')
    parser.add_argument('-l', '--listing', help='Generate listing file')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Verbose output')

    args = parser.parse_args()

    # Read input file
    try:
        with open(args.input, 'r') as f:
            source = f.read()
    except IOError as e:
        print(f"Error reading {args.input}: {e}", file=sys.stderr)
        return 1

    # Assemble
    assembler = MicroAssembler()
    success = assembler.assemble(source)

    # Display warnings
    if assembler.warnings:
        print("Warnings:", file=sys.stderr)
        for warning in assembler.warnings:
            print(f"  {warning}", file=sys.stderr)

    # Display errors
    if assembler.errors:
        print("Errors:", file=sys.stderr)
        for error in assembler.errors:
            print(f"  {error}", file=sys.stderr)
        return 1

    # Generate output
    if args.format == 'hex':
        output = assembler.generate_hex()
    elif args.format == 'verilog':
        output = assembler.generate_verilog()
    elif args.format == 'binary':
        output = assembler.generate_binary()
    elif args.format == 'listing':
        output = assembler.generate_listing()

    # Write output
    if args.output:
        try:
            mode = 'wb' if args.format == 'binary' else 'w'
            with open(args.output, mode) as f:
                f.write(output)
            if args.verbose:
                print(f"Output written to {args.output}")
        except IOError as e:
            print(f"Error writing {args.output}: {e}", file=sys.stderr)
            return 1
    else:
        if args.format != 'binary':
            print(output)

    # Generate listing if requested
    if args.listing:
        try:
            with open(args.listing, 'w') as f:
                f.write(assembler.generate_listing())
            if args.verbose:
                print(f"Listing written to {args.listing}")
        except IOError as e:
            print(f"Error writing {args.listing}: {e}", file=sys.stderr)

    # Print statistics
    if args.verbose:
        print(f"\nAssembly complete:")
        print(f"  Instructions: {len(assembler.instructions)}")
        print(f"  Labels: {len(assembler.labels)}")
        print(f"  Symbols: {len(assembler.symbols)}")

    return 0


if __name__ == '__main__':
    sys.exit(main())
