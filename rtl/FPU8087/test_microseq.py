#!/usr/bin/env python3
"""
Test script for extended microsequencer with hardware unit interface.
Tests the "call and wait" subroutine pattern.
"""

import sys
import os

# Add current directory to path to import microsim
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from microsim import MicrosequencerSimulator, ExtendedFloat, Opcode, MicroOp


def test_fadd_subroutine():
    """Test FADD subroutine (program 0)"""
    print("\n" + "="*70)
    print("Test: FADD Subroutine (3.14 + 2.71 = 5.85)")
    print("="*70)

    sim = MicrosequencerSimulator(verbose=True)

    # Set up operands
    sim.fpu_state.temp_fp_a = ExtendedFloat.from_float(3.14)
    sim.fpu_state.temp_fp_b = ExtendedFloat.from_float(2.71)

    print(f"\nSetup:")
    print(f"  temp_fp_a = {sim.fpu_state.temp_fp_a.to_float()}")
    print(f"  temp_fp_b = {sim.fpu_state.temp_fp_b.to_float()}")

    # Manually program the microcode ROM for this test
    # Program 0 (FADD subroutine) is already defined in MicroSequencer_Extended
    # We just need to call it from a main program

    # Main program at address 0
    # Format: {opcode[31:28], micro_op[27:23], immediate[22:15], next_addr[14:0]}
    OPCODE_CALL = 0x3
    OPCODE_HALT = 0xF

    # Address 0: CALL program 0 (FADD subroutine at 0x0100)
    sim.microcode_rom[0] = (OPCODE_CALL << 28) | (0 << 23) | (0 << 15) | 0x0100

    # Address 1: HALT (return point)
    sim.microcode_rom[1] = (OPCODE_HALT << 28) | (0 << 23) | (0 << 15) | 0

    # Run from address 0
    success = sim.run(start_addr=0)

    print(f"\nResults:")
    print(f"  temp_result = {sim.fpu_state.temp_result.to_float()}")
    print(f"  Expected    = 5.85")
    print(f"  Halted      = {sim.halted}")
    print(f"  Instructions executed = {sim.instruction_count}")

    # Verify result
    result = sim.fpu_state.temp_result.to_float()
    expected = 5.85
    tolerance = 0.01

    if abs(result - expected) < tolerance and success:
        print(f"\n✓ PASS: Result {result:.4f} matches expected {expected}")
        return True
    else:
        print(f"\n✗ FAIL: Result {result:.4f} does not match expected {expected}")
        return False


def test_fsqrt_subroutine():
    """Test FSQRT subroutine (program 4)"""
    print("\n" + "="*70)
    print("Test: FSQRT Subroutine (sqrt(16.0) = 4.0)")
    print("="*70)

    sim = MicrosequencerSimulator(verbose=True)

    # Set up operand (sqrt uses temp_fp_a only)
    sim.fpu_state.temp_fp_a = ExtendedFloat.from_float(16.0)

    print(f"\nSetup:")
    print(f"  temp_fp_a = {sim.fpu_state.temp_fp_a.to_float()}")

    # Main program
    OPCODE_CALL = 0x3
    OPCODE_HALT = 0xF

    # Address 0: CALL program 4 (FSQRT subroutine at 0x0140)
    sim.microcode_rom[0] = (OPCODE_CALL << 28) | (0 << 23) | (0 << 15) | 0x0140

    # Address 1: HALT
    sim.microcode_rom[1] = (OPCODE_HALT << 28) | (0 << 23) | (0 << 15) | 0

    # Run
    success = sim.run(start_addr=0)

    print(f"\nResults:")
    print(f"  temp_result = {sim.fpu_state.temp_result.to_float()}")
    print(f"  Expected    = 4.0")
    print(f"  Halted      = {sim.halted}")

    # Verify
    result = sim.fpu_state.temp_result.to_float()
    expected = 4.0
    tolerance = 0.01

    if abs(result - expected) < tolerance and success:
        print(f"\n✓ PASS: Result {result:.4f} matches expected {expected}")
        return True
    else:
        print(f"\n✗ FAIL: Result {result:.4f} does not match expected {expected}")
        return False


def test_fsin_subroutine():
    """Test FSIN subroutine (program 5)"""
    print("\n" + "="*70)
    print("Test: FSIN Subroutine (sin(π/2) ≈ 1.0)")
    print("="*70)

    sim = MicrosequencerSimulator(verbose=True)

    # Set up operand
    import math
    sim.fpu_state.temp_fp_a = ExtendedFloat.from_float(math.pi / 2)

    print(f"\nSetup:")
    print(f"  temp_fp_a = {sim.fpu_state.temp_fp_a.to_float()} (π/2)")

    # Main program
    OPCODE_CALL = 0x3
    OPCODE_HALT = 0xF

    # Address 0: CALL program 5 (FSIN subroutine at 0x0150)
    sim.microcode_rom[0] = (OPCODE_CALL << 28) | (0 << 23) | (0 << 15) | 0x0150

    # Address 1: HALT
    sim.microcode_rom[1] = (OPCODE_HALT << 28) | (0 << 23) | (0 << 15) | 0

    # Run
    success = sim.run(start_addr=0)

    print(f"\nResults:")
    print(f"  temp_result = {sim.fpu_state.temp_result.to_float()}")
    print(f"  Expected    = 1.0")
    print(f"  Halted      = {sim.halted}")

    # Verify
    result = sim.fpu_state.temp_result.to_float()
    expected = 1.0
    tolerance = 0.01

    if abs(result - expected) < tolerance and success:
        print(f"\n✓ PASS: Result {result:.4f} matches expected {expected}")
        return True
    else:
        print(f"\n✗ FAIL: Result {result:.4f} does not match expected {expected}")
        return False


def run_all_tests():
    """Run all microsequencer tests"""
    print("\n" + "="*70)
    print("Extended Microsequencer Test Suite")
    print("Testing hardware unit interface with 'call and wait' pattern")
    print("="*70)

    tests = [
        ("FADD Subroutine", test_fadd_subroutine),
        ("FSQRT Subroutine", test_fsqrt_subroutine),
        ("FSIN Subroutine", test_fsin_subroutine),
    ]

    results = []
    for name, test_fn in tests:
        try:
            result = test_fn()
            results.append((name, result))
        except Exception as e:
            print(f"\n✗ EXCEPTION in {name}: {e}")
            import traceback
            traceback.print_exc()
            results.append((name, False))

    # Summary
    print("\n" + "="*70)
    print("Test Summary")
    print("="*70)
    passed = sum(1 for _, result in results if result)
    total = len(results)

    for name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"{status}: {name}")

    print(f"\nTotal: {passed}/{total} tests passed")

    return passed == total


if __name__ == '__main__':
    success = run_all_tests()
    sys.exit(0 if success else 1)
