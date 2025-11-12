#!/usr/bin/env python3
"""
Comprehensive Unit Tests for IEEE 754 Extended Precision Add/Subtract

Tests the FPU_IEEE754_AddSub module with extensive test vectors including:
- Basic arithmetic
- Special values (±0, ±∞, NaN)
- Edge cases (overflow, underflow, cancellation)
- Rounding modes
- Comparison operations
"""

import struct
import math
import sys

class IEEE754_80bit:
    """IEEE 754 Extended Precision (80-bit) floating point representation"""

    def __init__(self, sign=0, exponent=0, mantissa=0):
        self.sign = sign & 1
        self.exponent = exponent & 0x7FFF
        self.mantissa = mantissa & 0xFFFFFFFFFFFFFFFF

    @classmethod
    def from_float(cls, value):
        """Convert Python float to 80-bit representation (approximate)"""
        if math.isnan(value):
            return cls(0, 0x7FFF, 0x4000000000000000)  # QNaN
        elif math.isinf(value):
            if value > 0:
                return cls(0, 0x7FFF, 0x8000000000000000)  # +∞
            else:
                return cls(1, 0x7FFF, 0x8000000000000000)  # -∞
        elif value == 0.0:
            sign = 1 if math.copysign(1.0, value) < 0 else 0
            return cls(sign, 0, 0)
        else:
            sign = 1 if value < 0 else 0
            abs_val = abs(value)

            # Get exponent
            if abs_val >= 1.0:
                exp = 0
                temp = abs_val
                while temp >= 2.0:
                    temp /= 2.0
                    exp += 1
            else:
                exp = 0
                temp = abs_val
                while temp < 1.0:
                    temp *= 2.0
                    exp -= 1

            # Bias exponent
            biased_exp = exp + 16383

            # Get mantissa (normalized, with integer bit)
            mantissa_val = int(temp * (2**63))

            return cls(sign, biased_exp, mantissa_val)

    def to_hex(self):
        """Convert to 80-bit hex string for Verilog"""
        value = (self.sign << 79) | (self.exponent << 64) | self.mantissa
        return f"80'h{value:020X}"

    def to_binary(self):
        """Convert to 80-bit binary string"""
        value = (self.sign << 79) | (self.exponent << 64) | self.mantissa
        return f"{value:080b}"

    def __str__(self):
        if self.exponent == 0x7FFF:
            if self.mantissa & 0x7FFFFFFFFFFFFFFF != 0:
                return "NaN"
            else:
                return "-∞" if self.sign else "+∞"
        elif self.exponent == 0 and self.mantissa == 0:
            return "-0" if self.sign else "+0"
        else:
            return self.to_hex()

# Test vectors: (operand_a, operand_b, subtract, expected_result, description)
test_vectors = []

# Test 1: Simple addition - 1.0 + 1.0 = 2.0
one = IEEE754_80bit(0, 16383, 0x8000000000000000)  # 1.0
two = IEEE754_80bit(0, 16384, 0x8000000000000000)  # 2.0
test_vectors.append((one, one, 0, two, "1.0 + 1.0 = 2.0"))

# Test 2: Simple subtraction - 2.0 - 1.0 = 1.0
test_vectors.append((two, one, 1, one, "2.0 - 1.0 = 1.0"))

# Test 3: Subtraction to zero - 1.0 - 1.0 = 0.0
zero = IEEE754_80bit(0, 0, 0)
test_vectors.append((one, one, 1, zero, "1.0 - 1.0 = 0.0"))

# Test 4: Addition with zero - 1.0 + 0.0 = 1.0
test_vectors.append((one, zero, 0, one, "1.0 + 0.0 = 1.0"))

# Test 5: Negative addition - (-1.0) + (-1.0) = -2.0
neg_one = IEEE754_80bit(1, 16383, 0x8000000000000000)  # -1.0
neg_two = IEEE754_80bit(1, 16384, 0x8000000000000000)  # -2.0
test_vectors.append((neg_one, neg_one, 0, neg_two, "(-1.0) + (-1.0) = -2.0"))

# Test 6: Mixed signs - 1.0 + (-1.0) = 0.0
test_vectors.append((one, neg_one, 0, zero, "1.0 + (-1.0) = 0.0"))

# Test 7: Infinity + finite = infinity
inf_pos = IEEE754_80bit(0, 0x7FFF, 0x8000000000000000)  # +∞
test_vectors.append((inf_pos, one, 0, inf_pos, "+∞ + 1.0 = +∞"))

# Test 8: Infinity + Infinity (same sign) = Infinity
test_vectors.append((inf_pos, inf_pos, 0, inf_pos, "+∞ + +∞ = +∞"))

# Test 9: Infinity - Infinity = NaN (invalid)
nan = IEEE754_80bit(0, 0x7FFF, 0xC000000000000000)  # QNaN
# This should trigger invalid flag
test_vectors.append((inf_pos, inf_pos, 1, nan, "+∞ - +∞ = NaN (invalid)"))

# Test 10: Zero + Zero = Zero
test_vectors.append((zero, zero, 0, zero, "0.0 + 0.0 = 0.0"))

# Test 11: Large + small (tests alignment)
large = IEEE754_80bit(0, 16400, 0x8000000000000000)  # 2^17
small = IEEE754_80bit(0, 16383, 0x8000000000000000)  # 1.0
# Result should be approximately 2^17 (small is lost in precision)
test_vectors.append((large, small, 0, large, "Large + small (precision loss)"))

# Test 12: Alternating sum (tests cancellation)
point_five = IEEE754_80bit(0, 16382, 0x8000000000000000)  # 0.5
test_vectors.append((one, point_five, 1, point_five, "1.0 - 0.5 = 0.5"))

# Test 13: Negative zero handling
neg_zero = IEEE754_80bit(1, 0, 0)  # -0.0
test_vectors.append((zero, neg_zero, 0, zero, "0.0 + (-0.0) = 0.0"))

# Test 14: Very small number (near underflow)
tiny = IEEE754_80bit(0, 1, 0x8000000000000000)  # Very small
test_vectors.append((tiny, tiny, 0, IEEE754_80bit(0, 2, 0x8000000000000000), "tiny + tiny"))

# Test 15: Maximum finite value
max_val = IEEE754_80bit(0, 0x7FFE, 0xFFFFFFFFFFFFFFFF)  # Max finite
# Adding 1 should still be max (or overflow depending on implementation)
test_vectors.append((max_val, one, 0, max_val, "max + 1 (no overflow in this case)"))

print("=" * 70)
print("IEEE 754 Extended Precision Add/Subtract Test Vectors")
print("=" * 70)
print()

print(f"Total test vectors: {len(test_vectors)}")
print()

for i, (op_a, op_b, sub, expected, desc) in enumerate(test_vectors, 1):
    print(f"Test {i}: {desc}")
    print(f"  Operand A:  {op_a.to_hex()}")
    print(f"  Operand B:  {op_b.to_hex()}")
    print(f"  Operation:  {'SUBTRACT' if sub else 'ADD'}")
    print(f"  Expected:   {expected.to_hex()}")
    print()

# Generate Verilog testbench code
print("=" * 70)
print("Verilog Test Stimulus Code")
print("=" * 70)
print()

for i, (op_a, op_b, sub, expected, desc) in enumerate(test_vectors, 1):
    print(f"        // Test {i}: {desc}")
    print(f"        test_num = {i};")
    print(f"        operand_a = {op_a.to_hex()};")
    print(f"        operand_b = {op_b.to_hex()};")
    print(f"        subtract = 1'b{sub};")
    print(f"        enable = 1;")
    print(f"        #10 enable = 0;")
    print(f"        wait(done);")
    print(f"        #10;")
    print(f"        expected_result = {expected.to_hex()};")
    print(f"        if (result == expected_result) begin")
    print(f"            $display(\"  PASS: Test {i} - {desc}\");")
    print(f"            passed_tests = passed_tests + 1;")
    print(f"        end else begin")
    print(f"            $display(\"  FAIL: Test {i} - {desc}\");")
    print(f"            $display(\"    Got:      %h\", result);")
    print(f"            $display(\"    Expected: %h\", expected_result);")
    print(f"            failed_tests = failed_tests + 1;")
    print(f"        end")
    print()

print()
print("=" * 70)
print("Additional Special Value Tests")
print("=" * 70)
print()

# More comprehensive special value tests
special_tests = [
    ("NaN + anything = NaN", nan, one, 0, nan),
    ("anything + NaN = NaN", one, nan, 0, nan),
    ("-∞ + finite = -∞", IEEE754_80bit(1, 0x7FFF, 0x8000000000000000), one, 0,
     IEEE754_80bit(1, 0x7FFF, 0x8000000000000000)),
    ("+∞ + -∞ = NaN", inf_pos, IEEE754_80bit(1, 0x7FFF, 0x8000000000000000), 0, nan),
]

for desc, op_a, op_b, sub, expected in special_tests:
    print(f"Test: {desc}")
    print(f"  A: {op_a.to_hex()}, B: {op_b.to_hex()}, Expected: {expected.to_hex()}")
    print()

print()
print("=" * 70)
print("Comparison Test Vectors")
print("=" * 70)
print()

comparison_tests = [
    (one, one, "equal", "1.0 == 1.0"),
    (one, two, "less", "1.0 < 2.0"),
    (two, one, "greater", "2.0 > 1.0"),
    (neg_one, one, "less", "-1.0 < 1.0"),
    (zero, neg_zero, "equal", "0.0 == -0.0"),
]

for op_a, op_b, expected, desc in comparison_tests:
    print(f"Test: {desc}")
    print(f"  A: {op_a.to_hex()}, B: {op_b.to_hex()}, Expected: {expected}")
    print()

print()
print("Tests generated successfully!")
print(f"Total basic tests: {len(test_vectors)}")
print(f"Total special tests: {len(special_tests)}")
print(f"Total comparison tests: {len(comparison_tests)}")
print(f"Grand total: {len(test_vectors) + len(special_tests) + len(comparison_tests)} tests")
