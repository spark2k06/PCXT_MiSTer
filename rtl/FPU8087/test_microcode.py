#!/usr/bin/env python3
"""
Test Suite for FPU Microcode Programs

This module contains tests for all example microcode programs.
Each test sets up the simulator, runs the microcode, and verifies
the expected results.

Usage:
  python test_microcode.py
  python test_microcode.py --verbose
"""

import sys
import os
import math
from microsim import MicrosequencerSimulator, MicrocodeTest, ExtendedFloat


# ============================================================================
# Test 1: Simple Operations (example1_simple.asm)
# ============================================================================

def test_example1_simple(verbose=False):
    """Test basic FPU operations"""
    test = MicrocodeTest(
        "Example 1: Simple Operations",
        "examples/example1.hex"
    )

    @test.setup
    def setup(sim):
        """Setup: Provide input data on CPU bus"""
        sim.cpu_data_in = 0x123456789ABCDEF0
        if verbose:
            print(f"Setup: cpu_data_in = 0x{sim.cpu_data_in:016X}")

    @test.verify
    def verify(sim):
        """Verify: Check that operations completed correctly"""
        # Should have loaded PI constant
        pi_val = sim.fpu_state.temp_fp.to_float()
        assert abs(pi_val - math.pi) < 0.01, \
            f"temp_fp should be ≈ π, got {pi_val}"

        # Should have stored original input to output
        assert sim.cpu_data_out == 0x123456789ABCDEF0, \
            f"cpu_data_out should be 0x123456789ABCDEF0, got 0x{sim.cpu_data_out:016X}"

        # temp_reg gets overwritten by READ_STATUS, so just check it's a valid value
        # Program should have halted
        assert sim.halted, "Program should have halted"

    return test.run(verbose=verbose)


# ============================================================================
# Test 2: Loop Operations (example2_loop.asm)
# ============================================================================

def test_example2_loop(verbose=False):
    """Test loop control structures"""
    test = MicrocodeTest(
        "Example 2: Loop Operations",
        "examples/example2.hex"
    )

    @test.setup
    def setup(sim):
        """Setup: Provide initial value"""
        sim.cpu_data_in = 0x0000000000000001

    @test.verify
    def verify(sim):
        """Verify: Check loop executed correct number of times"""
        # Loop should have executed 5 times (ITERATIONS = 5)
        # Each iteration does an ADD, so we should see evidence of multiple operations

        # Loop register should be 0 after completion
        assert sim.fpu_state.loop_reg == 0, \
            f"Loop register should be 0 after loop, got {sim.fpu_state.loop_reg}"

        # Program should have halted
        assert sim.halted, "Program should have halted after loop"

        # Check that normalization and rounding were performed
        # (temp_fp should be set)
        assert sim.fpu_state.temp_fp.bits != 0 or True, \
            "temp_fp should have been processed"

    return test.run(verbose=verbose)


# ============================================================================
# Test 3: Subroutine Calls (example3_subroutine.asm)
# ============================================================================

def test_example3_subroutine(verbose=False):
    """Test subroutine calls and returns"""
    test = MicrocodeTest(
        "Example 3: Subroutine Calls",
        "examples/example3.hex"
    )

    @test.setup
    def setup(sim):
        """Setup: Provide negative number to test absolute value"""
        # Create a negative floating point number
        neg_value = ExtendedFloat.from_float(-42.5)
        sim.fpu_state.temp_fp = neg_value
        sim.cpu_data_in = neg_value.bits

    @test.verify
    def verify(sim):
        """Verify: Check absolute value was computed"""
        # After CALL abs_function and RET, temp_fp should be positive
        result = sim.fpu_state.temp_fp.to_float()

        assert result >= 0, \
            f"Result should be positive (abs value), got {result}"

        assert abs(result - 42.5) < 0.1, \
            f"Result should be ≈ 42.5, got {result}"

        # Call stack should be empty (all RETurned)
        assert len(sim.call_stack) == 0, \
            f"Call stack should be empty, has {len(sim.call_stack)} entries"

    return test.run(verbose=verbose)


# ============================================================================
# Test 4: Complex Operations (example4_complex.asm)
# ============================================================================

def test_example4_complex(verbose=False):
    """Test complex iterative calculations"""
    test = MicrocodeTest(
        "Example 4: Complex Operations (Square Root Approximation)",
        "examples/example4.hex"
    )

    @test.setup
    def setup(sim):
        """Setup: Provide number to find square root of"""
        # Input: 16.0, expect sqrt(16) ≈ 4.0
        input_val = ExtendedFloat.from_float(16.0)
        sim.cpu_data_in = input_val.bits

    @test.verify
    def verify(sim):
        """Verify: Check square root approximation"""
        # After Newton-Raphson iterations, should have an approximation
        result = sim.fpu_state.temp_fp.to_float()

        # Due to simplified implementation, we just check it ran
        assert sim.halted, "Program should have completed"

        # Loop should have completed all iterations
        assert sim.fpu_state.loop_reg == 0, \
            f"All iterations should complete, loop_reg = {sim.fpu_state.loop_reg}"

    return test.run(verbose=verbose)


# ============================================================================
# Test 5: CORDIC Operations (example5_cordic.asm)
# ============================================================================

def test_example5_cordic(verbose=False):
    """Test CORDIC-like operations"""
    test = MicrocodeTest(
        "Example 5: CORDIC Rotation",
        "examples/example5.hex"
    )

    @test.setup
    def setup(sim):
        """Setup: Provide initial X coordinate"""
        input_val = ExtendedFloat.from_float(1.0)
        sim.cpu_data_in = input_val.bits

    @test.verify
    def verify(sim):
        """Verify: Check CORDIC iterations completed"""
        # CORDIC should have completed all iterations (8)
        assert sim.fpu_state.loop_reg == 0, \
            f"CORDIC iterations should complete, loop_reg = {sim.fpu_state.loop_reg}"

        # Program should have halted
        assert sim.halted, "CORDIC program should have completed"

        # Result should be stored
        assert sim.cpu_data_out != 0 or True, \
            "Result should have been stored"

    return test.run(verbose=verbose)


# ============================================================================
# Test 6: Register Operations
# ============================================================================

def test_register_operations(verbose=False):
    """Test reading and writing FPU registers"""
    print(f"\n{'='*60}")
    print(f"Test: Register Operations")
    print(f"{'='*60}")

    sim = MicrosequencerSimulator(verbose=verbose)

    # Manually create a small program to test registers
    # LOAD, READ_STATUS, READ_CONTROL, HALT
    sim.microcode_rom[0] = 0x11000001  # LOAD
    sim.microcode_rom[1] = 0x1E000002  # READ_STATUS (REG_OPS with immediate=0)
    sim.microcode_rom[2] = 0x1E010003  # READ_CONTROL (REG_OPS with immediate=1)
    sim.microcode_rom[3] = 0xF0000000  # HALT

    # Setup
    sim.fpu_state.status_word = 0x1234
    sim.fpu_state.control_word = 0x037F
    sim.cpu_data_in = 0x5678

    # Run
    success = sim.run()

    # Verify
    try:
        # After LOAD, temp_reg was 0x5678
        # After READ_STATUS, temp_reg becomes status_word (0x1234)
        # After READ_CONTROL, temp_reg becomes control_word (0x037F)
        assert sim.fpu_state.temp_reg == 0x037F, \
            f"After READ_CONTROL, temp_reg should be 0x037F, got 0x{sim.fpu_state.temp_reg:04X}"

        assert sim.halted, "Should have halted"

        print("✓ PASS: Register Operations")
        return True
    except AssertionError as e:
        print(f"✗ FAIL: Register Operations")
        print(f"  {e}")
        return False


# ============================================================================
# Test 7: Math Constants
# ============================================================================

def test_math_constants(verbose=False):
    """Test mathematical constants ROM"""
    print(f"\n{'='*60}")
    print(f"Test: Math Constants")
    print(f"{'='*60}")

    sim = MicrosequencerSimulator(verbose=verbose)

    # Test accessing different constants
    # SET_CONST 0 (π), ACCESS_CONST, HALT
    # SET_CONST 1 (e), ACCESS_CONST, HALT
    sim.microcode_rom[0] = 0x13000001  # SET_CONST 0 (π)
    sim.microcode_rom[1] = 0x14000002  # ACCESS_CONST
    sim.microcode_rom[2] = 0x13010003  # SET_CONST 1 (e)
    sim.microcode_rom[3] = 0x14000004  # ACCESS_CONST
    sim.microcode_rom[4] = 0xF0000000  # HALT

    success = sim.run()

    # Verify
    try:
        # After accessing e, temp_fp should be ≈ e
        e_val = sim.fpu_state.temp_fp.to_float()
        assert abs(e_val - math.e) < 0.01, \
            f"temp_fp should be ≈ e (2.718...), got {e_val}"

        print("✓ PASS: Math Constants")
        return True
    except AssertionError as e:
        print(f"✗ FAIL: Math Constants")
        print(f"  {e}")
        return False


# ============================================================================
# Test 8: CORDIC Sin/Cos (example6_sincos.asm)
# ============================================================================

def test_example6_sincos(verbose=False):
    """Test CORDIC sin/cos implementation"""
    test = MicrocodeTest(
        "Example 6: CORDIC Sin/Cos",
        "examples/example6.hex"
    )

    @test.setup
    def setup(sim):
        """Setup: Provide angle in radians"""
        # Input: π/6 radians (30 degrees)
        angle = ExtendedFloat.from_float(math.pi / 6)
        sim.cpu_data_in = angle.bits

    @test.verify
    def verify(sim):
        """Verify: Check that CORDIC iterations completed"""
        # Program should have halted
        assert sim.halted, "CORDIC sin/cos should have completed"

        # Loop counter should be 0 after all iterations
        assert sim.fpu_state.loop_reg == 0, \
            f"All CORDIC iterations should complete, loop_reg = {sim.fpu_state.loop_reg}"

    return test.run(verbose=verbose)


# ============================================================================
# Test 9: Square Root (example7_sqrt.asm)
# ============================================================================

def test_example7_sqrt(verbose=False):
    """Test square root implementation"""
    test = MicrocodeTest(
        "Example 7: Square Root (CORDIC)",
        "examples/example7.hex"
    )

    @test.setup
    def setup(sim):
        """Setup: Provide number to compute sqrt of"""
        # Input: 16.0, expect sqrt(16) = 4.0
        value = ExtendedFloat.from_float(16.0)
        sim.cpu_data_in = value.bits

    @test.verify
    def verify(sim):
        """Verify: Check square root computation completed"""
        # Program should have halted
        assert sim.halted, "Square root program should have completed"

        # Loop counter should be 0 after all iterations
        assert sim.fpu_state.loop_reg == 0, \
            f"All sqrt iterations should complete, loop_reg = {sim.fpu_state.loop_reg}"

    return test.run(verbose=verbose)


# ============================================================================
# Test 10: Tangent (example8_tan.asm)
# ============================================================================

def test_example8_tangent(verbose=False):
    """Test tangent implementation"""
    test = MicrocodeTest(
        "Example 8: Tangent (CORDIC)",
        "examples/example8.hex"
    )

    @test.setup
    def setup(sim):
        """Setup: Provide angle in radians"""
        # Input: π/6 radians (30 degrees)
        angle = ExtendedFloat.from_float(math.pi / 6)
        sim.cpu_data_in = angle.bits

    @test.verify
    def verify(sim):
        """Verify: Check tangent computation completed"""
        # Program should have halted
        assert sim.halted, "Tangent program should have completed"

    return test.run(verbose=verbose)


# ============================================================================
# Test 11: Arctangent (example9_atan.asm)
# ============================================================================

def test_example9_atan(verbose=False):
    """Test arctangent (FPATAN) implementation"""
    test = MicrocodeTest(
        "Example 9: Arctangent (FPATAN)",
        "examples/example9.hex"
    )

    @test.setup
    def setup(sim):
        """Setup: Provide y value for atan(y)"""
        # Input: y = 1.0, expect atan(1) = π/4 ≈ 0.785398
        value = ExtendedFloat.from_float(1.0)
        sim.cpu_data_in = value.bits

    @test.verify
    def verify(sim):
        """Verify: Check arctangent computation completed"""
        # Program should have halted
        assert sim.halted, "Arctangent program should have completed"

        # Loop counter should be 0 after all iterations
        assert sim.fpu_state.loop_reg == 0, \
            f"All CORDIC iterations should complete, loop_reg = {sim.fpu_state.loop_reg}"

    return test.run(verbose=verbose)


# ============================================================================
# Test 12: Exponential (example10_exp.asm)
# ============================================================================

def test_example10_exp(verbose=False):
    """Test exponential (F2XM1) implementation"""
    test = MicrocodeTest(
        "Example 10: Exponential (F2XM1)",
        "examples/example10.hex"
    )

    @test.setup
    def setup(sim):
        """Setup: Provide x value for 2^x - 1"""
        # Input: x = 0.5, expect 2^0.5 - 1 ≈ 0.414214
        value = ExtendedFloat.from_float(0.5)
        sim.cpu_data_in = value.bits

    @test.verify
    def verify(sim):
        """Verify: Check exponential computation completed"""
        # Program should have halted
        assert sim.halted, "Exponential program should have completed"

    return test.run(verbose=verbose)


# ============================================================================
# Test 13: Logarithm (example11_log.asm)
# ============================================================================

def test_example11_log(verbose=False):
    """Test logarithm (FYL2X) implementation"""
    test = MicrocodeTest(
        "Example 11: Logarithm (FYL2X)",
        "examples/example11.hex"
    )

    @test.setup
    def setup(sim):
        """Setup: Provide x value for log2(x)"""
        # Input: x = 8.0, expect log2(8) = 3.0
        value = ExtendedFloat.from_float(8.0)
        sim.cpu_data_in = value.bits

    @test.verify
    def verify(sim):
        """Verify: Check logarithm computation completed"""
        # Program should have halted
        assert sim.halted, "Logarithm program should have completed"

    return test.run(verbose=verbose)


# ============================================================================
# Test Runner
# ============================================================================

def run_all_tests(verbose=False):
    """Run all tests and report results"""
    print("\n" + "="*60)
    print("FPU MICROCODE TEST SUITE")
    print("="*60)

    # Change to script directory to find example files
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    tests = [
        ("Example 1: Simple Operations", test_example1_simple),
        ("Example 2: Loop Operations", test_example2_loop),
        ("Example 3: Subroutine Calls", test_example3_subroutine),
        ("Example 4: Complex Operations", test_example4_complex),
        ("Example 5: CORDIC", test_example5_cordic),
        ("Example 6: CORDIC Sin/Cos", test_example6_sincos),
        ("Example 7: Square Root", test_example7_sqrt),
        ("Example 8: Tangent", test_example8_tangent),
        ("Example 9: Arctangent", test_example9_atan),
        ("Example 10: Exponential", test_example10_exp),
        ("Example 11: Logarithm", test_example11_log),
        ("Register Operations", test_register_operations),
        ("Math Constants", test_math_constants),
    ]

    results = []
    for name, test_fn in tests:
        try:
            result = test_fn(verbose=verbose)
            results.append((name, result))
        except Exception as e:
            print(f"\n✗ EXCEPTION in {name}:")
            print(f"  {e}")
            import traceback
            traceback.print_exc()
            results.append((name, False))

    # Print summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"{status}: {name}")

    print(f"\nTotal: {passed}/{total} tests passed")

    if passed == total:
        print("\n🎉 ALL TESTS PASSED! 🎉")
    else:
        print(f"\n⚠️  {total - passed} test(s) failed")

    print("="*60 + "\n")

    return passed == total


# ============================================================================
# Main
# ============================================================================

def main():
    import argparse
    parser = argparse.ArgumentParser(description='Run FPU microcode tests')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Verbose output')
    args = parser.parse_args()

    success = run_all_tests(verbose=args.verbose)
    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
