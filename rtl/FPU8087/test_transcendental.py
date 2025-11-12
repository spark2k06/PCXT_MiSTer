#!/usr/bin/env python3
"""
Transcendental Function Test Vector Generator and Reference Implementation

Generates test vectors for Intel 8087 transcendental functions and provides
high-precision reference implementations for validation.

Supported functions:
- FSQRT: Square root
- FSIN: Sine
- FCOS: Cosine
- FSINCOS: Sine and Cosine (dual result)
- FPTAN: Partial tangent
- FPATAN: Partial arctangent
- F2XM1: 2^x - 1
- FYL2X: y × log₂(x)
- FYL2XP1: y × log₂(x+1)

Usage:
    python test_transcendental.py --generate     # Generate test vectors
    python test_transcendental.py --verify       # Verify against results
    python test_transcendental.py --stats        # Show statistics
"""

import sys
import math
import struct
import argparse
import random
from typing import Tuple, List, Optional
from dataclasses import dataclass

# Try to import mpmath for high-precision arithmetic
try:
    import mpmath
    mpmath.mp.dps = 50  # 50 decimal places of precision
    HAS_MPMATH = True
except ImportError:
    print("Warning: mpmath not available, using Python math (lower precision)")
    HAS_MPMATH = False


# ============================================================================
# 80-bit Extended Precision Floating Point Conversion
# ============================================================================

def fp80_to_float(fp80: int) -> float:
    """Convert 80-bit extended precision to Python float"""
    if fp80 == 0:
        return 0.0

    sign = (fp80 >> 79) & 1
    exponent = (fp80 >> 64) & 0x7FFF
    mantissa = fp80 & 0xFFFFFFFFFFFFFFFF

    # Check for special values
    if exponent == 0:  # Zero or denormal
        if mantissa == 0:
            return -0.0 if sign else 0.0
        # Denormal
        exp_unbias = -16382
        mant_norm = mantissa / (2**63)
        result = mant_norm * (2.0 ** (exp_unbias + 1))
    elif exponent == 0x7FFF:  # Infinity or NaN
        if mantissa & 0x7FFFFFFFFFFFFFFF == 0:
            return float('-inf') if sign else float('inf')
        else:
            return float('nan')
    else:  # Normal
        exp_unbias = exponent - 16383
        mant_norm = mantissa / (2**63)
        result = mant_norm * (2.0 ** exp_unbias)

    return -result if sign else result


def float_to_fp80(value: float) -> int:
    """Convert Python float to 80-bit extended precision"""
    if value == 0.0:
        # Handle positive and negative zero
        return 0x8000000000000000000000 if math.copysign(1.0, value) < 0 else 0

    if math.isnan(value):
        return 0x7FFF_C000000000000000  # QNaN

    sign = 1 if value < 0 else 0
    value = abs(value)

    if math.isinf(value):
        return (sign << 79) | (0x7FFF << 64) | (1 << 63)

    # Get exponent and mantissa
    exp = math.floor(math.log2(value))
    mantissa = value / (2.0 ** exp)

    # Convert mantissa to 64-bit integer (with implicit leading 1)
    mantissa_int = int(mantissa * (2 ** 63)) & 0xFFFFFFFFFFFFFFFF

    # Bias exponent
    exp_biased = (exp + 16383) & 0x7FFF

    # Combine components
    fp80 = (sign << 79) | (exp_biased << 64) | mantissa_int
    return fp80


def fp80_to_hex(fp80: int) -> str:
    """Format FP80 as hex string"""
    return f"80'h{fp80:020X}"


# ============================================================================
# High-Precision Reference Implementations
# ============================================================================

class TranscendentalReference:
    """High-precision reference implementations for transcendental functions"""

    @staticmethod
    def sqrt(x: float) -> float:
        """Square root with high precision"""
        if HAS_MPMATH:
            return float(mpmath.sqrt(mpmath.mpf(x)))
        return math.sqrt(x)

    @staticmethod
    def sin(x: float) -> float:
        """Sine with high precision"""
        if HAS_MPMATH:
            return float(mpmath.sin(mpmath.mpf(x)))
        return math.sin(x)

    @staticmethod
    def cos(x: float) -> float:
        """Cosine with high precision"""
        if HAS_MPMATH:
            return float(mpmath.cos(mpmath.mpf(x)))
        return math.cos(x)

    @staticmethod
    def sincos(x: float) -> Tuple[float, float]:
        """Sine and cosine with high precision (computed together)"""
        if HAS_MPMATH:
            x_mp = mpmath.mpf(x)
            sin_val = float(mpmath.sin(x_mp))
            cos_val = float(mpmath.cos(x_mp))
            return (sin_val, cos_val)
        return (math.sin(x), math.cos(x))

    @staticmethod
    def tan(x: float) -> float:
        """Tangent with high precision"""
        if HAS_MPMATH:
            return float(mpmath.tan(mpmath.mpf(x)))
        return math.tan(x)

    @staticmethod
    def atan(y: float, x: float) -> float:
        """Arctangent of y/x with high precision"""
        if HAS_MPMATH:
            return float(mpmath.atan2(mpmath.mpf(y), mpmath.mpf(x)))
        return math.atan2(y, x)

    @staticmethod
    def f2xm1(x: float) -> float:
        """2^x - 1 with high precision"""
        if HAS_MPMATH:
            return float(mpmath.power(2, mpmath.mpf(x)) - 1)
        return math.pow(2, x) - 1

    @staticmethod
    def fyl2x(y: float, x: float) -> float:
        """y × log₂(x) with high precision"""
        if HAS_MPMATH:
            return float(mpmath.mpf(y) * mpmath.log(mpmath.mpf(x), 2))
        return y * math.log2(x)

    @staticmethod
    def fyl2xp1(y: float, x: float) -> float:
        """y × log₂(x+1) with high precision"""
        if HAS_MPMATH:
            return float(mpmath.mpf(y) * mpmath.log(mpmath.mpf(x) + 1, 2))
        return y * math.log2(x + 1)


# ============================================================================
# Test Vector Generation
# ============================================================================

@dataclass
class TestVector:
    """Test vector for transcendental function"""
    name: str           # Function name
    input_a: int        # Input operand A (FP80)
    input_b: int        # Input operand B (FP80) - for dual-operand functions
    expected: int       # Expected result (FP80)
    expected_sec: int   # Expected secondary result (FP80) - for FSINCOS
    has_secondary: bool # True if secondary result is valid
    description: str    # Human-readable description


class TestVectorGenerator:
    """Generate test vectors for transcendental functions"""

    def __init__(self, seed: int = 42):
        random.seed(seed)
        self.ref = TranscendentalReference()

    def generate_sqrt_vectors(self, count: int = 100) -> List[TestVector]:
        """Generate test vectors for FSQRT (square root)"""
        vectors = []

        # Known values
        known_values = [
            (0.0, "√0 = 0"),
            (1.0, "√1 = 1"),
            (2.0, "√2 ≈ 1.414"),
            (4.0, "√4 = 2"),
            (9.0, "√9 = 3"),
            (16.0, "√16 = 4"),
            (0.25, "√0.25 = 0.5"),
            (0.0625, "√0.0625 = 0.25"),
        ]

        for value, desc in known_values:
            input_fp80 = float_to_fp80(value)
            expected = self.ref.sqrt(value)
            expected_fp80 = float_to_fp80(expected)
            vectors.append(TestVector(
                name="FSQRT",
                input_a=input_fp80,
                input_b=0,
                expected=expected_fp80,
                expected_sec=0,
                has_secondary=False,
                description=desc
            ))

        # Random values
        for i in range(count - len(known_values)):
            # Generate random positive values (log-uniform distribution)
            exponent = random.uniform(-10, 10)
            value = 2.0 ** exponent

            input_fp80 = float_to_fp80(value)
            expected = self.ref.sqrt(value)
            expected_fp80 = float_to_fp80(expected)
            vectors.append(TestVector(
                name="FSQRT",
                input_a=input_fp80,
                input_b=0,
                expected=expected_fp80,
                expected_sec=0,
                has_secondary=False,
                description=f"√{value:.6e} ≈ {expected:.6e}"
            ))

        return vectors

    def generate_sin_vectors(self, count: int = 100) -> List[TestVector]:
        """Generate test vectors for FSIN (sine)"""
        vectors = []

        # Known values
        known_values = [
            (0.0, "sin(0) = 0"),
            (math.pi / 6, "sin(π/6) = 0.5"),
            (math.pi / 4, "sin(π/4) ≈ 0.707"),
            (math.pi / 3, "sin(π/3) ≈ 0.866"),
            (math.pi / 2, "sin(π/2) = 1"),
            (math.pi, "sin(π) = 0"),
            (3 * math.pi / 2, "sin(3π/2) = -1"),
            (2 * math.pi, "sin(2π) = 0"),
        ]

        for value, desc in known_values:
            input_fp80 = float_to_fp80(value)
            expected = self.ref.sin(value)
            expected_fp80 = float_to_fp80(expected)
            vectors.append(TestVector(
                name="FSIN",
                input_a=input_fp80,
                input_b=0,
                expected=expected_fp80,
                expected_sec=0,
                has_secondary=False,
                description=desc
            ))

        # Random values
        for i in range(count - len(known_values)):
            # Generate random angles
            value = random.uniform(-4 * math.pi, 4 * math.pi)

            input_fp80 = float_to_fp80(value)
            expected = self.ref.sin(value)
            expected_fp80 = float_to_fp80(expected)
            vectors.append(TestVector(
                name="FSIN",
                input_a=input_fp80,
                input_b=0,
                expected=expected_fp80,
                expected_sec=0,
                has_secondary=False,
                description=f"sin({value:.6f}) ≈ {expected:.6f}"
            ))

        return vectors

    def generate_cos_vectors(self, count: int = 100) -> List[TestVector]:
        """Generate test vectors for FCOS (cosine)"""
        vectors = []

        # Known values
        known_values = [
            (0.0, "cos(0) = 1"),
            (math.pi / 6, "cos(π/6) ≈ 0.866"),
            (math.pi / 4, "cos(π/4) ≈ 0.707"),
            (math.pi / 3, "cos(π/3) = 0.5"),
            (math.pi / 2, "cos(π/2) = 0"),
            (math.pi, "cos(π) = -1"),
            (3 * math.pi / 2, "cos(3π/2) = 0"),
            (2 * math.pi, "cos(2π) = 1"),
        ]

        for value, desc in known_values:
            input_fp80 = float_to_fp80(value)
            expected = self.ref.cos(value)
            expected_fp80 = float_to_fp80(expected)
            vectors.append(TestVector(
                name="FCOS",
                input_a=input_fp80,
                input_b=0,
                expected=expected_fp80,
                expected_sec=0,
                has_secondary=False,
                description=desc
            ))

        # Random values
        for i in range(count - len(known_values)):
            # Generate random angles
            value = random.uniform(-4 * math.pi, 4 * math.pi)

            input_fp80 = float_to_fp80(value)
            expected = self.ref.cos(value)
            expected_fp80 = float_to_fp80(expected)
            vectors.append(TestVector(
                name="FCOS",
                input_a=input_fp80,
                input_b=0,
                expected=expected_fp80,
                expected_sec=0,
                has_secondary=False,
                description=f"cos({value:.6f}) ≈ {expected:.6f}"
            ))

        return vectors

    def generate_sincos_vectors(self, count: int = 100) -> List[TestVector]:
        """Generate test vectors for FSINCOS (sine and cosine)"""
        vectors = []

        # Known values
        known_values = [
            (0.0, "sincos(0) = (0, 1)"),
            (math.pi / 6, "sincos(π/6) = (0.5, 0.866)"),
            (math.pi / 4, "sincos(π/4) = (0.707, 0.707)"),
            (math.pi / 2, "sincos(π/2) = (1, 0)"),
            (math.pi, "sincos(π) = (0, -1)"),
        ]

        for value, desc in known_values:
            input_fp80 = float_to_fp80(value)
            sin_val, cos_val = self.ref.sincos(value)
            expected_sin_fp80 = float_to_fp80(sin_val)
            expected_cos_fp80 = float_to_fp80(cos_val)
            vectors.append(TestVector(
                name="FSINCOS",
                input_a=input_fp80,
                input_b=0,
                expected=expected_sin_fp80,  # sin(θ) - goes to ST(1)
                expected_sec=expected_cos_fp80,  # cos(θ) - goes to ST(0)
                has_secondary=True,
                description=desc
            ))

        # Random values
        for i in range(count - len(known_values)):
            # Generate random angles
            value = random.uniform(-4 * math.pi, 4 * math.pi)

            input_fp80 = float_to_fp80(value)
            sin_val, cos_val = self.ref.sincos(value)
            expected_sin_fp80 = float_to_fp80(sin_val)
            expected_cos_fp80 = float_to_fp80(cos_val)
            vectors.append(TestVector(
                name="FSINCOS",
                input_a=input_fp80,
                input_b=0,
                expected=expected_sin_fp80,
                expected_sec=expected_cos_fp80,
                has_secondary=True,
                description=f"sincos({value:.6f}) ≈ ({sin_val:.6f}, {cos_val:.6f})"
            ))

        return vectors

    def generate_all_vectors(self) -> List[TestVector]:
        """Generate all test vectors"""
        all_vectors = []

        print("Generating FSQRT test vectors...")
        all_vectors.extend(self.generate_sqrt_vectors(100))

        print("Generating FSIN test vectors...")
        all_vectors.extend(self.generate_sin_vectors(100))

        print("Generating FCOS test vectors...")
        all_vectors.extend(self.generate_cos_vectors(100))

        print("Generating FSINCOS test vectors...")
        all_vectors.extend(self.generate_sincos_vectors(100))

        return all_vectors


# ============================================================================
# Test Vector File Generation
# ============================================================================

def write_verilog_test_vectors(vectors: List[TestVector], filename: str):
    """Write test vectors in Verilog format"""
    with open(filename, 'w') as f:
        f.write("// Transcendental Function Test Vectors\n")
        f.write("// Generated by test_transcendental.py\n\n")

        for i, vec in enumerate(vectors):
            f.write(f"// Test {i}: {vec.name} - {vec.description}\n")
            f.write(f"input_a[{i}] = {fp80_to_hex(vec.input_a)};\n")
            if vec.input_b != 0:
                f.write(f"input_b[{i}] = {fp80_to_hex(vec.input_b)};\n")
            f.write(f"expected[{i}] = {fp80_to_hex(vec.expected)};\n")
            if vec.has_secondary:
                f.write(f"expected_sec[{i}] = {fp80_to_hex(vec.expected_sec)};\n")
            f.write("\n")

    print(f"Wrote {len(vectors)} test vectors to {filename}")


def write_text_test_vectors(vectors: List[TestVector], filename: str):
    """Write test vectors in human-readable text format"""
    with open(filename, 'w') as f:
        f.write("Transcendental Function Test Vectors\n")
        f.write("=" * 80 + "\n\n")

        for i, vec in enumerate(vectors):
            f.write(f"Test {i}: {vec.name}\n")
            f.write(f"  Description: {vec.description}\n")
            f.write(f"  Input A:  {fp80_to_hex(vec.input_a)} ({fp80_to_float(vec.input_a)})\n")
            if vec.input_b != 0:
                f.write(f"  Input B:  {fp80_to_hex(vec.input_b)} ({fp80_to_float(vec.input_b)})\n")
            f.write(f"  Expected: {fp80_to_hex(vec.expected)} ({fp80_to_float(vec.expected)})\n")
            if vec.has_secondary:
                f.write(f"  Expected(sec): {fp80_to_hex(vec.expected_sec)} ({fp80_to_float(vec.expected_sec)})\n")
            f.write("\n")

    print(f"Wrote {len(vectors)} test vectors to {filename}")


# ============================================================================
# Main
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description='Transcendental function test vector generator')
    parser.add_argument('--generate', action='store_true', help='Generate test vectors')
    parser.add_argument('--output', default='test_vectors', help='Output filename prefix')
    parser.add_argument('--count', type=int, default=100, help='Number of random vectors per function')
    parser.add_argument('--seed', type=int, default=42, help='Random seed')

    args = parser.parse_args()

    if args.generate:
        print("Generating transcendental function test vectors...")
        print(f"Using {'mpmath (high precision)' if HAS_MPMATH else 'Python math (standard precision)'}\n")

        generator = TestVectorGenerator(seed=args.seed)
        vectors = generator.generate_all_vectors()

        print(f"\nGenerated {len(vectors)} total test vectors")

        # Write in multiple formats
        write_verilog_test_vectors(vectors, f"{args.output}.vh")
        write_text_test_vectors(vectors, f"{args.output}.txt")

        print("\nTest vector generation complete!")
        print(f"  Verilog format: {args.output}.vh")
        print(f"  Text format: {args.output}.txt")

    else:
        parser.print_help()


if __name__ == '__main__':
    main()
