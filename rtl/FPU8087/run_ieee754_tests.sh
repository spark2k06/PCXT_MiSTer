#!/bin/bash
#=====================================================================
# IEEE 754 Arithmetic Test Runner
#
# Runs all IEEE 754 extended precision (80-bit) arithmetic tests:
# - Add/Subtract unit (15 tests)
# - Multiply unit (15 tests)
# - Divide unit (15 tests)
#
# Total: 45 tests
#=====================================================================

echo "=========================================="
echo "IEEE 754 Arithmetic Test Suite"
echo "=========================================="
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_TESTS=45

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#=====================================================================
# Test 1: Add/Subtract Unit
#=====================================================================

echo "=========================================="
echo "Test Suite 1: IEEE 754 Add/Subtract"
echo "=========================================="
echo ""

# Compile
echo "Compiling Add/Subtract unit..."
iverilog -o tb_ieee754_addsub -g2012 FPU_IEEE754_AddSub.v tb_ieee754_addsub.v 2>&1 | grep -i "error"
if [ $? -eq 0 ]; then
    echo -e "${RED}COMPILATION FAILED${NC}"
    exit 1
fi

# Run tests
echo "Running Add/Subtract tests..."
./tb_ieee754_addsub > addsub_test_results.txt 2>&1

# Parse results
PASSED=$(grep "Passed:" addsub_test_results.txt | awk '{print $2}')
FAILED=$(grep "Failed:" addsub_test_results.txt | awk '{print $2}')

echo "  Passed: $PASSED/15"
echo "  Failed: $FAILED/15"

if [ "$FAILED" -eq 0 ]; then
    echo -e "  ${GREEN}✓ ALL TESTS PASSED${NC}"
else
    echo -e "  ${RED}✗ SOME TESTS FAILED${NC}"
fi

TOTAL_PASSED=$((TOTAL_PASSED + PASSED))
TOTAL_FAILED=$((TOTAL_FAILED + FAILED))

echo ""

#=====================================================================
# Test 2: Multiply Unit
#=====================================================================

echo "=========================================="
echo "Test Suite 2: IEEE 754 Multiply"
echo "=========================================="
echo ""

# Compile
echo "Compiling Multiply unit..."
iverilog -o tb_ieee754_multiply -g2012 FPU_IEEE754_Multiply.v tb_ieee754_multiply.v 2>&1 | grep -i "error"
if [ $? -eq 0 ]; then
    echo -e "${RED}COMPILATION FAILED${NC}"
    exit 1
fi

# Run tests
echo "Running Multiply tests..."
./tb_ieee754_multiply > multiply_test_results.txt 2>&1

# Parse results
PASSED=$(grep "Passed:" multiply_test_results.txt | awk '{print $2}')
FAILED=$(grep "Failed:" multiply_test_results.txt | awk '{print $2}')

echo "  Passed: $PASSED/15"
echo "  Failed: $FAILED/15"

if [ "$FAILED" -eq 0 ]; then
    echo -e "  ${GREEN}✓ ALL TESTS PASSED${NC}"
else
    echo -e "  ${RED}✗ SOME TESTS FAILED${NC}"
fi

TOTAL_PASSED=$((TOTAL_PASSED + PASSED))
TOTAL_FAILED=$((TOTAL_FAILED + FAILED))

echo ""

#=====================================================================
# Test 3: Divide Unit
#=====================================================================

echo "=========================================="
echo "Test Suite 3: IEEE 754 Divide"
echo "=========================================="
echo ""

# Compile
echo "Compiling Divide unit..."
iverilog -o tb_ieee754_divide -g2012 FPU_IEEE754_Divide.v tb_ieee754_divide.v 2>&1 | grep -i "error"
if [ $? -eq 0 ]; then
    echo -e "${RED}COMPILATION FAILED${NC}"
    exit 1
fi

# Run tests
echo "Running Divide tests..."
./tb_ieee754_divide > divide_test_results.txt 2>&1

# Parse results
PASSED=$(grep "Passed:" divide_test_results.txt | awk '{print $2}')
FAILED=$(grep "Failed:" divide_test_results.txt | awk '{print $2}')

echo "  Passed: $PASSED/15"
echo "  Failed: $FAILED/15"

if [ "$FAILED" -eq 0 ]; then
    echo -e "  ${GREEN}✓ ALL TESTS PASSED${NC}"
else
    echo -e "  ${RED}✗ SOME TESTS FAILED${NC}"
fi

TOTAL_PASSED=$((TOTAL_PASSED + PASSED))
TOTAL_FAILED=$((TOTAL_FAILED + FAILED))

echo ""

#=====================================================================
# Summary
#=====================================================================

echo "=========================================="
echo "IEEE 754 Arithmetic Test Summary"
echo "=========================================="
echo ""
echo "Total Tests:  $TOTAL_TESTS"
echo "Total Passed: $TOTAL_PASSED"
echo "Total Failed: $TOTAL_FAILED"
echo ""

if [ "$TOTAL_FAILED" -eq 0 ]; then
    echo -e "${GREEN}*** ALL 45 TESTS PASSED! ***${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}*** $TOTAL_FAILED TESTS FAILED ***${NC}"
    echo ""
    exit 1
fi
