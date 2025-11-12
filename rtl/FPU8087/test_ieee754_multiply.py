#!/usr/bin/env python3
"""
Test vector generator for IEEE 754 Extended Precision (80-bit) Multiply Unit

Generates comprehensive test cases for FPU_IEEE754_Multiply.v
"""

import struct
import math

class IEEE754_80bit:
    """IEEE 754 Extended Precision (80-bit) representation"""

    BIAS = 16383  # Exponent bias for 80-bit format

    def __init__(self, sign=0, exponent=0, mantissa=0):
        self.sign = sign & 1
        self.exponent = exponent & 0x7FFF
        self.mantissa = mantissa & 0xFFFFFFFFFFFFFFFF

    @classmethod
    def from_float(cls, value):
        """Convert Python float to 80-bit representation (approximation)"""
        if math.isnan(value):
            return cls.nan()
        if math.isinf(value):
            return cls.infinity(value < 0)
        if value == 0.0:
            return cls.zero(math.copysign(1.0, value) < 0)

        sign = 1 if value < 0 else 0
        value = abs(value)

        # Get exponent and mantissa
        exponent = int(math.floor(math.log2(value)))
        mantissa_float = value / (2 ** exponent)

        # Convert to 80-bit format
        exp_80bit = exponent + cls.BIAS

        # Mantissa has explicit integer bit
        mant_80bit = int(mantissa_float * (2 ** 63))

        return cls(sign, exp_80bit, mant_80bit)

    @classmethod
    def zero(cls, negative=False):
        """Create +0 or -0"""
        return cls(1 if negative else 0, 0, 0)

    @classmethod
    def infinity(cls, negative=False):
        """Create +∞ or -∞"""
        return cls(1 if negative else 0, 0x7FFF, 0x8000000000000000)

    @classmethod
    def nan(cls, signaling=False):
        """Create NaN (quiet by default)"""
        # Quiet NaN: exponent all 1s, integer bit set, fraction non-zero
        return cls(0, 0x7FFF, 0xC000000000000000)

    def to_hex(self):
        """Convert to 80-bit hex string"""
        value = (self.sign << 79) | (self.exponent << 64) | self.mantissa
        return f"80'h{value:020X}"

    def __str__(self):
        return self.to_hex()


def generate_multiply_test(test_num, a, b, expected, description, rounding_mode=0):
    """Generate a single multiply test case"""
    print(f"// Test {test_num}: {description}")
    print(f"operand_a = {a};")
    print(f"operand_b = {b};")
    print(f"rounding_mode = 2'b{rounding_mode:02b};")
    print(f"enable = 1;")
    print(f"#10 enable = 0;")
    print(f"wait(done);")
    print(f"expected_result = {expected};")
    print(f'if (result == expected_result) begin')
    print(f'    $display("  PASS: {description}");')
    print(f'    passed_tests = passed_tests + 1;')
    print(f'end else begin')
    print(f'    $display("  FAIL: {description}");')
    print(f'    $display("    Expected: %h", expected_result);')
    print(f'    $display("    Got:      %h", result);')
    print(f'    failed_tests = failed_tests + 1;')
    print(f'end')
    print(f'#10;')
    print()


def main():
    """Generate all multiply test cases"""

    print("=" * 70)
    print("IEEE 754 Extended Precision (80-bit) Multiply Test Vectors")
    print("=" * 70)
    print()

    test_num = 1

    # Test 1: 1.0 × 1.0 = 1.0
    print(f"// Test {test_num}: 1.0 × 1.0 = 1.0")
    a = IEEE754_80bit(0, 0x3FFF, 0x8000000000000000)  # 1.0
    b = IEEE754_80bit(0, 0x3FFF, 0x8000000000000000)  # 1.0
    result = IEEE754_80bit(0, 0x3FFF, 0x8000000000000000)  # 1.0
    generate_multiply_test(test_num, a, b, result, "1.0 × 1.0 = 1.0")
    test_num += 1

    # Test 2: 2.0 × 3.0 = 6.0
    print(f"// Test {test_num}: 2.0 × 3.0 = 6.0")
    a = IEEE754_80bit(0, 0x4000, 0x8000000000000000)  # 2.0
    b = IEEE754_80bit(0, 0x4000, 0xC000000000000000)  # 3.0 = 1.5 × 2^1
    result = IEEE754_80bit(0, 0x4001, 0xC000000000000000)  # 6.0 = 1.5 × 2^2
    generate_multiply_test(test_num, a, b, result, "2.0 × 3.0 = 6.0")
    test_num += 1

    # Test 3: 0.5 × 0.5 = 0.25
    print(f"// Test {test_num}: 0.5 × 0.5 = 0.25")
    a = IEEE754_80bit(0, 0x3FFE, 0x8000000000000000)  # 0.5
    b = IEEE754_80bit(0, 0x3FFE, 0x8000000000000000)  # 0.5
    result = IEEE754_80bit(0, 0x3FFD, 0x8000000000000000)  # 0.25
    generate_multiply_test(test_num, a, b, result, "0.5 × 0.5 = 0.25")
    test_num += 1

    # Test 4: -2.0 × 3.0 = -6.0 (sign handling)
    print(f"// Test {test_num}: -2.0 × 3.0 = -6.0")
    a = IEEE754_80bit(1, 0x4000, 0x8000000000000000)  # -2.0
    b = IEEE754_80bit(0, 0x4000, 0xC000000000000000)  # 3.0
    result = IEEE754_80bit(1, 0x4001, 0xC000000000000000)  # -6.0
    generate_multiply_test(test_num, a, b, result, "-2.0 × 3.0 = -6.0")
    test_num += 1

    # Test 5: -2.0 × -3.0 = 6.0 (negative × negative = positive)
    print(f"// Test {test_num}: -2.0 × -3.0 = 6.0")
    a = IEEE754_80bit(1, 0x4000, 0x8000000000000000)  # -2.0
    b = IEEE754_80bit(1, 0x4000, 0xC000000000000000)  # -3.0
    result = IEEE754_80bit(0, 0x4001, 0xC000000000000000)  # 6.0
    generate_multiply_test(test_num, a, b, result, "-2.0 × -3.0 = 6.0")
    test_num += 1

    # Test 6: 1.0 × 0.0 = 0.0
    print(f"// Test {test_num}: 1.0 × 0.0 = +0.0")
    a = IEEE754_80bit(0, 0x3FFF, 0x8000000000000000)  # 1.0
    b = IEEE754_80bit.zero()  # +0.0
    result = IEEE754_80bit.zero()  # +0.0
    generate_multiply_test(test_num, a, b, result, "1.0 × 0.0 = +0.0")
    test_num += 1

    # Test 7: -1.0 × 0.0 = -0.0
    print(f"// Test {test_num}: -1.0 × 0.0 = -0.0")
    a = IEEE754_80bit(1, 0x3FFF, 0x8000000000000000)  # -1.0
    b = IEEE754_80bit.zero()  # +0.0
    result = IEEE754_80bit.zero(negative=True)  # -0.0
    generate_multiply_test(test_num, a, b, result, "-1.0 × 0.0 = -0.0")
    test_num += 1

    # Test 8: 1.0 × +∞ = +∞
    print(f"// Test {test_num}: 1.0 × +∞ = +∞")
    a = IEEE754_80bit(0, 0x3FFF, 0x8000000000000000)  # 1.0
    b = IEEE754_80bit.infinity()  # +∞
    result = IEEE754_80bit.infinity()  # +∞
    generate_multiply_test(test_num, a, b, result, "1.0 × +∞ = +∞")
    test_num += 1

    # Test 9: -1.0 × +∞ = -∞
    print(f"// Test {test_num}: -1.0 × +∞ = -∞")
    a = IEEE754_80bit(1, 0x3FFF, 0x8000000000000000)  # -1.0
    b = IEEE754_80bit.infinity()  # +∞
    result = IEEE754_80bit.infinity(negative=True)  # -∞
    generate_multiply_test(test_num, a, b, result, "-1.0 × +∞ = -∞")
    test_num += 1

    # Test 10: 0.0 × ∞ = NaN (invalid operation)
    print(f"// Test {test_num}: 0.0 × ∞ = NaN (invalid)")
    a = IEEE754_80bit.zero()  # 0.0
    b = IEEE754_80bit.infinity()  # +∞
    result = IEEE754_80bit.nan()  # NaN
    print(f"operand_a = {a};")
    print(f"operand_b = {b};")
    print(f"rounding_mode = 2'b00;")
    print(f"enable = 1;")
    print(f"#10 enable = 0;")
    print(f"wait(done);")
    print(f'if (flag_invalid && result[78:64] == 15\'h7FFF && result[63]) begin')
    print(f'    $display("  PASS: 0.0 × ∞ = NaN (invalid)");')
    print(f'    passed_tests = passed_tests + 1;')
    print(f'end else begin')
    print(f'    $display("  FAIL: 0.0 × ∞ should set invalid flag and return NaN");')
    print(f'    $display("    Got: %h, invalid=%b", result, flag_invalid);')
    print(f'    failed_tests = failed_tests + 1;')
    print(f'end')
    print(f'#10;')
    print()
    test_num += 1

    # Test 11: NaN × 1.0 = NaN
    print(f"// Test {test_num}: NaN × 1.0 = NaN")
    a = IEEE754_80bit.nan()  # NaN
    b = IEEE754_80bit(0, 0x3FFF, 0x8000000000000000)  # 1.0
    print(f"operand_a = {a};")
    print(f"operand_b = {b};")
    print(f"rounding_mode = 2'b00;")
    print(f"enable = 1;")
    print(f"#10 enable = 0;")
    print(f"wait(done);")
    print(f'if (flag_invalid && result[78:64] == 15\'h7FFF && result[63]) begin')
    print(f'    $display("  PASS: NaN × 1.0 = NaN");')
    print(f'    passed_tests = passed_tests + 1;')
    print(f'end else begin')
    print(f'    $display("  FAIL: NaN × 1.0 should set invalid flag and return NaN");')
    print(f'    $display("    Got: %h, invalid=%b", result, flag_invalid);')
    print(f'    failed_tests = failed_tests + 1;')
    print(f'end')
    print(f'#10;')
    print()
    test_num += 1

    # Test 12: Very small × very small (underflow test)
    print(f"// Test {test_num}: Very small × very small (potential underflow)")
    a = IEEE754_80bit(0, 0x0001, 0x8000000000000000)  # Smallest normal
    b = IEEE754_80bit(0, 0x0001, 0x8000000000000000)  # Smallest normal
    result = IEEE754_80bit.zero()  # Underflows to zero
    print(f"operand_a = {a};")
    print(f"operand_b = {b};")
    print(f"rounding_mode = 2'b00;")
    print(f"enable = 1;")
    print(f"#10 enable = 0;")
    print(f"wait(done);")
    print(f'if (flag_underflow) begin')
    print(f'    $display("  PASS: Underflow detected for very small × very small");')
    print(f'    passed_tests = passed_tests + 1;')
    print(f'end else begin')
    print(f'    $display("  FAIL: Should detect underflow");')
    print(f'    $display("    Got: %h, underflow=%b", result, flag_underflow);')
    print(f'    failed_tests = failed_tests + 1;')
    print(f'end')
    print(f'#10;')
    print()
    test_num += 1

    # Test 13: Very large × very large (overflow test)
    print(f"// Test {test_num}: Very large × very large (overflow)")
    a = IEEE754_80bit(0, 0x7FFE, 0xFFFFFFFFFFFFFFFF)  # Near max
    b = IEEE754_80bit(0, 0x7FFE, 0x8000000000000000)  # Very large
    result = IEEE754_80bit.infinity()  # Overflows to +∞
    print(f"operand_a = {a};")
    print(f"operand_b = {b};")
    print(f"rounding_mode = 2'b00;")
    print(f"enable = 1;")
    print(f"#10 enable = 0;")
    print(f"wait(done);")
    print(f'if (flag_overflow && result[78:64] == 15\'h7FFF && result[63:0] == 64\'h8000000000000000) begin')
    print(f'    $display("  PASS: Overflow to +∞ for very large × very large");')
    print(f'    passed_tests = passed_tests + 1;')
    print(f'end else begin')
    print(f'    $display("  FAIL: Should overflow to +∞");')
    print(f'    $display("    Got: %h, overflow=%b", result, flag_overflow);')
    print(f'    failed_tests = failed_tests + 1;')
    print(f'end')
    print(f'#10;')
    print()
    test_num += 1

    # Test 14: 1.5 × 1.5 = 2.25 (requires normalization)
    print(f"// Test {test_num}: 1.5 × 1.5 = 2.25")
    a = IEEE754_80bit(0, 0x3FFF, 0xC000000000000000)  # 1.5
    b = IEEE754_80bit(0, 0x3FFF, 0xC000000000000000)  # 1.5
    result = IEEE754_80bit(0, 0x4000, 0x9000000000000000)  # 2.25 = 1.125 × 2^1
    generate_multiply_test(test_num, a, b, result, "1.5 × 1.5 = 2.25")
    test_num += 1

    # Test 15: 4.0 × 0.125 = 0.5
    print(f"// Test {test_num}: 4.0 × 0.125 = 0.5")
    a = IEEE754_80bit(0, 0x4001, 0x8000000000000000)  # 4.0
    b = IEEE754_80bit(0, 0x3FFC, 0x8000000000000000)  # 0.125
    result = IEEE754_80bit(0, 0x3FFE, 0x8000000000000000)  # 0.5
    generate_multiply_test(test_num, a, b, result, "4.0 × 0.125 = 0.5")
    test_num += 1

    print(f"\nTotal tests generated: {test_num - 1}")


if __name__ == "__main__":
    main()
