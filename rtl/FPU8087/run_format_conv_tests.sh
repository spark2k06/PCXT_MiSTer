#!/bin/bash
#=====================================================================
# Format Conversion Test Runner
#
# Runs all format conversion tests:
# - Integer ↔ FP80 (30 tests)
# - FP32/64 ↔ FP80 (20 tests)
#
# Total: 50 tests
#=====================================================================

echo "=========================================="
echo "Format Conversion Test Suite"
echo "=========================================="
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_TESTS=50

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

#=====================================================================
# Test 1: Integer ↔ FP80
#=====================================================================

echo "=========================================="
echo "Test Suite 1: Integer ↔ FP80"
echo "=========================================="
echo ""

echo "Compiling Integer ↔ FP80 tests..."
iverilog -o tb_format_conv_int -g2012 FPU_Int16_to_FP80.v FPU_Int32_to_FP80.v FPU_FP80_to_Int16.v FPU_FP80_to_Int32.v tb_format_conv_int.v 2>&1 | grep -i "error"
if [ $? -eq 0 ]; then
    echo -e "${RED}COMPILATION FAILED${NC}"
    exit 1
fi

echo "Running Integer ↔ FP80 tests..."
./tb_format_conv_int > int_conv_results.txt 2>&1

PASSED=$(grep "Passed:" int_conv_results.txt | awk '{print $2}')
FAILED=$(grep "Failed:" int_conv_results.txt | awk '{print $2}')

echo "  Passed: $PASSED/30"
echo "  Failed: $FAILED/30"

if [ "$FAILED" -eq 0 ]; then
    echo -e "  ${GREEN}✓ ALL TESTS PASSED${NC}"
else
    echo -e "  ${RED}✗ SOME TESTS FAILED${NC}"
fi

TOTAL_PASSED=$((TOTAL_PASSED + PASSED))
TOTAL_FAILED=$((TOTAL_FAILED + FAILED))

echo ""

#=====================================================================
# Test 2: FP32/64 ↔ FP80
#=====================================================================

echo "=========================================="
echo "Test Suite 2: FP32/64 ↔ FP80"
echo "=========================================="
echo ""

echo "Compiling FP32/64 ↔ FP80 tests..."
iverilog -o tb_format_conv_fp -g2012 FPU_FP32_to_FP80.v FPU_FP64_to_FP80.v FPU_FP80_to_FP32.v FPU_FP80_to_FP64.v tb_format_conv_fp.v 2>&1 | grep -i "error"
if [ $? -eq 0 ]; then
    echo -e "${RED}COMPILATION FAILED${NC}"
    exit 1
fi

echo "Running FP32/64 ↔ FP80 tests..."
./tb_format_conv_fp > fp_conv_results.txt 2>&1

PASSED=$(grep "Passed:" fp_conv_results.txt | awk '{print $2}')
FAILED=$(grep "Failed:" fp_conv_results.txt | awk '{print $2}')

echo "  Passed: $PASSED/20"
echo "  Failed: $FAILED/20"

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
echo "Format Conversion Test Summary"
echo "=========================================="
echo ""
echo "Total Tests:  $TOTAL_TESTS"
echo "Total Passed: $TOTAL_PASSED"
echo "Total Failed: $TOTAL_FAILED"
echo ""

if [ "$TOTAL_FAILED" -eq 0 ]; then
    echo -e "${GREEN}*** ALL 50 TESTS PASSED! ***${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}*** $TOTAL_FAILED TESTS FAILED ***${NC}"
    echo ""
    exit 1
fi
