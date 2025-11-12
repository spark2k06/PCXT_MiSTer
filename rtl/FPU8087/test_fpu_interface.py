#!/usr/bin/env python3
"""
FPU-CPU Interface Protocol Tests

This test suite validates the FPU-CPU interface signals and protocols
for 8086/8087 software compatibility. Tests verify instruction handshake,
data transfer, synchronization, and exception handling.
"""

import sys
from dataclasses import dataclass
from enum import Enum
from typing import List, Tuple, Optional

# ============================================================================
# Test Infrastructure
# ============================================================================

class TestResult(Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    SKIP = "SKIP"

@dataclass
class InterfaceSignals:
    """Represents the FPU-CPU interface signals at a point in time"""
    # Clock and reset
    clk: int = 0
    reset: int = 0

    # Instruction interface
    fpu_instr_valid: int = 0
    fpu_opcode: int = 0x00
    fpu_modrm: int = 0x00
    fpu_instr_ack: int = 0

    # Data transfer interface
    fpu_data_write: int = 0
    fpu_data_read: int = 0
    fpu_data_size: int = 0  # 0=16bit, 1=32bit, 2=64bit, 3=80bit
    fpu_data_in: int = 0
    fpu_data_out: int = 0
    fpu_data_ready: int = 0

    # Status and control
    fpu_busy: int = 0
    fpu_status_word: int = 0x0000
    fpu_control_word: int = 0x037F  # Default 8087 control word
    fpu_ctrl_write: int = 0
    fpu_exception: int = 0
    fpu_irq: int = 0

    # Synchronization
    fpu_wait: int = 0
    fpu_ready: int = 1  # Default to ready

class InterfaceSimulator:
    """Simulates FPU-CPU interface behavior"""

    def __init__(self):
        self.signals = InterfaceSignals()
        self.cycle = 0
        self.busy_cycles_remaining = 0
        self.data_buffer = 0
        self.stack = [0] * 8  # ST0-ST7
        self.stack_ptr = 0

    def tick(self) -> InterfaceSignals:
        """Advance one clock cycle"""
        self.cycle += 1

        # Handle reset
        if self.signals.reset:
            self.signals = InterfaceSignals()
            self.busy_cycles_remaining = 0
            self.data_buffer = 0
            self.stack = [0] * 8
            self.stack_ptr = 0
            return self.signals

        # Handle instruction acknowledgment (one cycle pulse)
        if self.signals.fpu_instr_valid and not self.signals.fpu_instr_ack:
            self.signals.fpu_instr_ack = 1
            self._process_instruction()
        else:
            self.signals.fpu_instr_ack = 0

        # Handle data write
        if self.signals.fpu_data_write:
            self.data_buffer = self.signals.fpu_data_in
            self.signals.fpu_data_ready = 1

        # Handle data read
        if self.signals.fpu_data_read:
            self.signals.fpu_data_out = self.data_buffer
            self.signals.fpu_data_ready = 1

        # Update busy status
        if self.busy_cycles_remaining > 0:
            self.signals.fpu_busy = 1
            self.signals.fpu_ready = 0
            self.busy_cycles_remaining -= 1
        else:
            self.signals.fpu_busy = 0
            self.signals.fpu_ready = 1

        return self.signals

    def _process_instruction(self):
        """Process FPU instruction and set busy cycles"""
        opcode = self.signals.fpu_opcode
        modrm = self.signals.fpu_modrm

        # Decode instruction and estimate execution time
        if opcode == 0xD9:  # FLD, FST, FLDCW, etc.
            if modrm & 0x38 == 0x00:  # FLD
                self.busy_cycles_remaining = 5
            elif modrm & 0x38 == 0x10:  # FST
                self.busy_cycles_remaining = 5
            elif modrm & 0x38 == 0x28:  # FLDCW
                self.busy_cycles_remaining = 2
            elif modrm == 0xE8:  # FLD1
                self.busy_cycles_remaining = 4
            elif modrm == 0xEE:  # FLDZ
                self.busy_cycles_remaining = 4
            elif modrm == 0xEB:  # FLDPI
                self.busy_cycles_remaining = 4
            elif modrm == 0xFA:  # FSQRT
                self.busy_cycles_remaining = 120
            elif modrm == 0xFE:  # FSIN
                self.busy_cycles_remaining = 250
            elif modrm == 0xFF:  # FCOS
                self.busy_cycles_remaining = 250
            elif modrm == 0xF2:  # FPTAN
                self.busy_cycles_remaining = 300
            elif modrm == 0xF3:  # FPATAN
                self.busy_cycles_remaining = 300
            else:
                self.busy_cycles_remaining = 10

        elif opcode == 0xD8:  # FADD, FSUB, FMUL, FDIV
            if modrm & 0xF8 == 0xC0:  # FADD ST(i)
                self.busy_cycles_remaining = 70
            elif modrm & 0xF8 == 0xE0:  # FSUB ST(i)
                self.busy_cycles_remaining = 70
            elif modrm & 0xF8 == 0xC8:  # FMUL ST(i)
                self.busy_cycles_remaining = 130
            elif modrm & 0xF8 == 0xF0:  # FDIV ST(i)
                self.busy_cycles_remaining = 215
            else:
                self.busy_cycles_remaining = 100

        elif opcode == 0xDB:  # Various including FINIT
            if modrm == 0xE3:  # FINIT
                self.busy_cycles_remaining = 50
            else:
                self.busy_cycles_remaining = 10

        elif opcode == 0xDD:  # FST 64-bit, FSTP, FSTSW
            self.busy_cycles_remaining = 8

        elif opcode == 0xDE:  # FCOMPP
            self.busy_cycles_remaining = 15

        elif opcode == 0xDF:  # FSTSW AX
            self.busy_cycles_remaining = 3

        else:
            self.busy_cycles_remaining = 10

# ============================================================================
# Test Cases
# ============================================================================

class InterfaceTests:
    """FPU-CPU Interface Test Suite"""

    def __init__(self):
        self.sim = InterfaceSimulator()
        self.test_results = []

    def reset_sim(self):
        """Reset simulator to initial state"""
        self.sim = InterfaceSimulator()

    def run_test(self, name: str, test_func) -> TestResult:
        """Run a single test"""
        print(f"\n{'='*60}")
        print(f"Test: {name}")
        print(f"{'='*60}")

        try:
            self.reset_sim()
            result = test_func()

            if result:
                print(f"✓ PASS: {name}")
                self.test_results.append((name, TestResult.PASS))
                return TestResult.PASS
            else:
                print(f"✗ FAIL: {name}")
                self.test_results.append((name, TestResult.FAIL))
                return TestResult.FAIL

        except Exception as e:
            print(f"✗ FAIL: {name} - Exception: {e}")
            self.test_results.append((name, TestResult.FAIL))
            return TestResult.FAIL

    # ========================================================================
    # Data Transfer Tests
    # ========================================================================

    def test_fld_handshake(self) -> bool:
        """Test FLD instruction handshake protocol"""
        print("Testing FLD instruction handshake...")

        # Cycle 0: Reset
        self.sim.signals.reset = 1
        self.sim.tick()
        self.sim.signals.reset = 0

        # Cycle 1: CPU issues FLD instruction
        self.sim.signals.fpu_instr_valid = 1
        self.sim.signals.fpu_opcode = 0xD9  # FLD
        self.sim.signals.fpu_modrm = 0x00   # FLD m32real
        self.sim.tick()

        # Cycle 2: Check ACK
        if not self.sim.signals.fpu_instr_ack:
            print("  FAIL: FPU did not acknowledge instruction")
            return False
        print("  ✓ FPU acknowledged instruction")

        # Cycle 3: CPU provides data
        self.sim.signals.fpu_instr_valid = 0
        self.sim.signals.fpu_data_write = 1
        self.sim.signals.fpu_data_size = 1  # 32-bit
        self.sim.signals.fpu_data_in = 0x3F800000  # 1.0 in IEEE 754
        self.sim.tick()

        # Cycle 4: Check busy
        self.sim.signals.fpu_data_write = 0
        self.sim.tick()

        if not self.sim.signals.fpu_busy:
            print("  FAIL: FPU should be busy during execution")
            return False
        print("  ✓ FPU is busy during execution")

        # Wait for completion
        cycles_waited = 0
        max_wait = 100
        while self.sim.signals.fpu_busy and cycles_waited < max_wait:
            self.sim.tick()
            cycles_waited += 1

        if cycles_waited >= max_wait:
            print(f"  FAIL: FPU remained busy for {max_wait} cycles")
            return False

        print(f"  ✓ FPU completed in {cycles_waited} cycles")
        return True

    def test_fst_data_transfer(self) -> bool:
        """Test FST data transfer to CPU"""
        print("Testing FST data transfer...")

        # Reset
        self.sim.signals.reset = 1
        self.sim.tick()
        self.sim.signals.reset = 0

        # Load data first (simulate ST0 has value)
        self.sim.data_buffer = 0x4000000000000000  # 2.0 in IEEE 754 double

        # Issue FST instruction
        self.sim.signals.fpu_instr_valid = 1
        self.sim.signals.fpu_opcode = 0xDD  # FST 64-bit
        self.sim.signals.fpu_modrm = 0x10   # FST m64real
        self.sim.tick()

        # Wait for execution
        self.sim.signals.fpu_instr_valid = 0
        max_wait = 100
        cycles = 0
        while self.sim.signals.fpu_busy and cycles < max_wait:
            self.sim.tick()
            cycles += 1

        # Read data
        self.sim.signals.fpu_data_read = 1
        self.sim.signals.fpu_data_size = 2  # 64-bit
        self.sim.tick()

        if not self.sim.signals.fpu_data_ready:
            print("  FAIL: Data not ready for read")
            return False

        print(f"  ✓ Data ready, value: 0x{self.sim.signals.fpu_data_out:016X}")
        return True

    def test_fxch_stack_exchange(self) -> bool:
        """Test FXCH register exchange"""
        print("Testing FXCH stack register exchange...")

        # Reset
        self.sim.signals.reset = 1
        self.sim.tick()
        self.sim.signals.reset = 0

        # Issue FXCH ST(1)
        self.sim.signals.fpu_instr_valid = 1
        self.sim.signals.fpu_opcode = 0xD9  # FXCH
        self.sim.signals.fpu_modrm = 0xC9   # FXCH ST(1)
        self.sim.tick()

        if not self.sim.signals.fpu_instr_ack:
            print("  FAIL: FXCH not acknowledged")
            return False

        print("  ✓ FXCH acknowledged")

        # FXCH should be fast (internal register exchange)
        self.sim.signals.fpu_instr_valid = 0
        max_wait = 50
        cycles = 0
        while self.sim.signals.fpu_busy and cycles < max_wait:
            self.sim.tick()
            cycles += 1

        if cycles >= max_wait:
            print(f"  FAIL: FXCH took too long ({max_wait} cycles)")
            return False

        print(f"  ✓ FXCH completed in {cycles} cycles")
        return True

    # ========================================================================
    # Arithmetic Operation Tests
    # ========================================================================

    def test_fadd_execution(self) -> bool:
        """Test FADD execution timing"""
        print("Testing FADD execution...")

        # Reset
        self.sim.signals.reset = 1
        self.sim.tick()
        self.sim.signals.reset = 0

        # Issue FADD ST(1)
        self.sim.signals.fpu_instr_valid = 1
        self.sim.signals.fpu_opcode = 0xD8  # FADD
        self.sim.signals.fpu_modrm = 0xC1   # FADD ST(1)
        self.sim.tick()

        if not self.sim.signals.fpu_instr_ack:
            print("  FAIL: FADD not acknowledged")
            return False

        # Check busy
        self.sim.signals.fpu_instr_valid = 0
        self.sim.tick()

        if not self.sim.signals.fpu_busy:
            print("  FAIL: FPU should be busy during FADD")
            return False

        print("  ✓ FPU busy during FADD")

        # Wait for completion
        max_wait = 200
        cycles = 0
        while self.sim.signals.fpu_busy and cycles < max_wait:
            self.sim.tick()
            cycles += 1

        if cycles >= max_wait:
            print(f"  FAIL: FADD took too long")
            return False

        print(f"  ✓ FADD completed in {cycles} cycles")
        return True

    def test_fdiv_long_execution(self) -> bool:
        """Test FDIV long execution time"""
        print("Testing FDIV long execution...")

        # Reset
        self.sim.signals.reset = 1
        self.sim.tick()
        self.sim.signals.reset = 0

        # Issue FDIV ST(1)
        self.sim.signals.fpu_instr_valid = 1
        self.sim.signals.fpu_opcode = 0xD8  # FDIV
        self.sim.signals.fpu_modrm = 0xF1   # FDIV ST(1)
        self.sim.tick()

        self.sim.signals.fpu_instr_valid = 0

        # Count busy cycles
        busy_cycles = 0
        max_wait = 500
        while self.sim.signals.fpu_busy and busy_cycles < max_wait:
            self.sim.tick()
            busy_cycles += 1

        if busy_cycles >= max_wait:
            print(f"  FAIL: FDIV timeout")
            return False

        # FDIV should take longer than FADD
        if busy_cycles < 100:
            print(f"  FAIL: FDIV completed too quickly ({busy_cycles} cycles)")
            return False

        print(f"  ✓ FDIV completed in {busy_cycles} cycles (realistic timing)")
        return True

    # ========================================================================
    # Transcendental Function Tests
    # ========================================================================

    def test_fsin_execution(self) -> bool:
        """Test FSIN transcendental execution"""
        print("Testing FSIN execution...")

        # Reset
        self.sim.signals.reset = 1
        self.sim.tick()
        self.sim.signals.reset = 0

        # Issue FSIN
        self.sim.signals.fpu_instr_valid = 1
        self.sim.signals.fpu_opcode = 0xD9  # FSIN
        self.sim.signals.fpu_modrm = 0xFE   # FSIN
        self.sim.tick()

        self.sim.signals.fpu_instr_valid = 0

        # FSIN should take many cycles
        busy_cycles = 0
        max_wait = 500
        while self.sim.signals.fpu_busy and busy_cycles < max_wait:
            self.sim.tick()
            busy_cycles += 1

        if busy_cycles >= max_wait:
            print(f"  FAIL: FSIN timeout")
            return False

        # FSIN should take longer than basic arithmetic
        if busy_cycles < 150:
            print(f"  FAIL: FSIN too fast ({busy_cycles} cycles)")
            return False

        print(f"  ✓ FSIN completed in {busy_cycles} cycles")
        return True

    # ========================================================================
    # Control Instruction Tests
    # ========================================================================

    def test_fldcw_control_write(self) -> bool:
        """Test FLDCW control word write"""
        print("Testing FLDCW control word write...")

        # Reset
        self.sim.signals.reset = 1
        self.sim.tick()
        self.sim.signals.reset = 0

        # Issue FLDCW
        self.sim.signals.fpu_instr_valid = 1
        self.sim.signals.fpu_opcode = 0xD9  # FLDCW
        self.sim.signals.fpu_modrm = 0x28   # FLDCW m16
        self.sim.tick()

        # Write control word
        self.sim.signals.fpu_instr_valid = 0
        self.sim.signals.fpu_ctrl_write = 1
        self.sim.signals.fpu_control_word = 0x027F  # Custom control word
        self.sim.tick()

        # Wait for completion
        self.sim.signals.fpu_ctrl_write = 0
        max_wait = 50
        cycles = 0
        while self.sim.signals.fpu_busy and cycles < max_wait:
            self.sim.tick()
            cycles += 1

        print(f"  ✓ FLDCW completed in {cycles} cycles")
        return True

    def test_fstsw_status_read(self) -> bool:
        """Test FSTSW status word read"""
        print("Testing FSTSW status word read...")

        # Reset
        self.sim.signals.reset = 1
        self.sim.tick()
        self.sim.signals.reset = 0

        # Set status word value (simulate FPU state)
        self.sim.signals.fpu_status_word = 0x3800  # Example status

        # Issue FSTSW AX
        self.sim.signals.fpu_instr_valid = 1
        self.sim.signals.fpu_opcode = 0xDF  # FSTSW
        self.sim.signals.fpu_modrm = 0xE0   # FSTSW AX
        self.sim.tick()

        self.sim.signals.fpu_instr_valid = 0

        # FSTSW should be very fast
        max_wait = 20
        cycles = 0
        while self.sim.signals.fpu_busy and cycles < max_wait:
            self.sim.tick()
            cycles += 1

        print(f"  ✓ FSTSW completed in {cycles} cycles")
        print(f"  Status word: 0x{self.sim.signals.fpu_status_word:04X}")
        return True

    # ========================================================================
    # Synchronization Tests
    # ========================================================================

    def test_fwait_with_busy_fpu(self) -> bool:
        """Test FWAIT synchronization with busy FPU"""
        print("Testing FWAIT with busy FPU...")

        # Reset
        self.sim.signals.reset = 1
        self.sim.tick()
        self.sim.signals.reset = 0

        # Start long operation (FSIN)
        self.sim.signals.fpu_instr_valid = 1
        self.sim.signals.fpu_opcode = 0xD9
        self.sim.signals.fpu_modrm = 0xFE  # FSIN
        self.sim.tick()

        self.sim.signals.fpu_instr_valid = 0

        # CPU executes FWAIT immediately after
        self.sim.signals.fpu_wait = 1

        # Count how long CPU must wait
        wait_cycles = 0
        max_wait = 500
        while not self.sim.signals.fpu_ready and wait_cycles < max_wait:
            if not self.sim.signals.fpu_busy:
                break
            self.sim.tick()
            wait_cycles += 1

        self.sim.signals.fpu_wait = 0

        if wait_cycles >= max_wait:
            print(f"  FAIL: FWAIT timeout")
            return False

        if wait_cycles < 100:
            print(f"  FAIL: FWAIT didn't wait long enough")
            return False

        print(f"  ✓ FWAIT correctly waited {wait_cycles} cycles for FPU")
        return True

    def test_fwait_with_ready_fpu(self) -> bool:
        """Test FWAIT with already ready FPU"""
        print("Testing FWAIT with ready FPU...")

        # Reset
        self.sim.signals.reset = 1
        self.sim.tick()
        self.sim.signals.reset = 0

        # FPU should be ready
        if not self.sim.signals.fpu_ready:
            print("  FAIL: FPU not ready after reset")
            return False

        # CPU executes FWAIT
        self.sim.signals.fpu_wait = 1
        self.sim.tick()

        # Should not wait (FPU already ready)
        if not self.sim.signals.fpu_ready:
            print("  FAIL: FPU not ready")
            return False

        print("  ✓ FWAIT returned immediately (FPU already ready)")
        return True

    # ========================================================================
    # Constant Load Tests
    # ========================================================================

    def test_fld1_constant_load(self) -> bool:
        """Test FLD1 constant loading"""
        print("Testing FLD1 constant load...")

        # Reset
        self.sim.signals.reset = 1
        self.sim.tick()
        self.sim.signals.reset = 0

        # Issue FLD1
        self.sim.signals.fpu_instr_valid = 1
        self.sim.signals.fpu_opcode = 0xD9
        self.sim.signals.fpu_modrm = 0xE8  # FLD1
        self.sim.tick()

        self.sim.signals.fpu_instr_valid = 0

        # Wait for completion
        max_wait = 50
        cycles = 0
        while self.sim.signals.fpu_busy and cycles < max_wait:
            self.sim.tick()
            cycles += 1

        if cycles >= max_wait:
            print(f"  FAIL: FLD1 timeout")
            return False

        print(f"  ✓ FLD1 completed in {cycles} cycles")
        return True

    def test_fldpi_constant_load(self) -> bool:
        """Test FLDPI constant loading"""
        print("Testing FLDPI constant load...")

        # Reset
        self.sim.signals.reset = 1
        self.sim.tick()
        self.sim.signals.reset = 0

        # Issue FLDPI
        self.sim.signals.fpu_instr_valid = 1
        self.sim.signals.fpu_opcode = 0xD9
        self.sim.signals.fpu_modrm = 0xEB  # FLDPI
        self.sim.tick()

        self.sim.signals.fpu_instr_valid = 0

        # Wait for completion
        max_wait = 50
        cycles = 0
        while self.sim.signals.fpu_busy and cycles < max_wait:
            self.sim.tick()
            cycles += 1

        if cycles >= max_wait:
            print(f"  FAIL: FLDPI timeout")
            return False

        print(f"  ✓ FLDPI completed in {cycles} cycles")
        return True

# ============================================================================
# Main Test Runner
# ============================================================================

def main():
    """Run all FPU-CPU interface tests"""

    print("=" * 60)
    print("FPU-CPU INTERFACE PROTOCOL TEST SUITE")
    print("=" * 60)
    print()

    tests = InterfaceTests()

    # Define all tests
    test_cases = [
        ("FLD Handshake Protocol", tests.test_fld_handshake),
        ("FST Data Transfer", tests.test_fst_data_transfer),
        ("FXCH Stack Exchange", tests.test_fxch_stack_exchange),
        ("FADD Execution", tests.test_fadd_execution),
        ("FDIV Long Execution", tests.test_fdiv_long_execution),
        ("FSIN Transcendental", tests.test_fsin_execution),
        ("FLDCW Control Write", tests.test_fldcw_control_write),
        ("FSTSW Status Read", tests.test_fstsw_status_read),
        ("FWAIT with Busy FPU", tests.test_fwait_with_busy_fpu),
        ("FWAIT with Ready FPU", tests.test_fwait_with_ready_fpu),
        ("FLD1 Constant Load", tests.test_fld1_constant_load),
        ("FLDPI Constant Load", tests.test_fldpi_constant_load),
    ]

    # Run all tests
    for name, test_func in test_cases:
        tests.run_test(name, test_func)

    # Print summary
    print("\n" + "=" * 60)
    print("TEST SUMMARY")
    print("=" * 60)

    passed = sum(1 for _, result in tests.test_results if result == TestResult.PASS)
    failed = sum(1 for _, result in tests.test_results if result == TestResult.FAIL)
    total = len(tests.test_results)

    for name, result in tests.test_results:
        symbol = "✓" if result == TestResult.PASS else "✗"
        print(f"{symbol} {result.value}: {name}")

    print(f"\nTotal: {passed}/{total} tests passed")

    if failed == 0:
        print("\n🎉 ALL TESTS PASSED! 🎉")
        print("=" * 60)
        return 0
    else:
        print(f"\n❌ {failed} TEST(S) FAILED")
        print("=" * 60)
        return 1

if __name__ == "__main__":
    sys.exit(main())
