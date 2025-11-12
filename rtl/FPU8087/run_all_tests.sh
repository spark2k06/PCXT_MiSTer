#!/bin/bash
# run_all_tests.sh
#
# Comprehensive test runner for 8087 FPU implementation
# Runs all unit tests and integration tests
#
# Date: 2025-11-10

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test results
declare -a TEST_RESULTS

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  8087 FPU Test Suite${NC}"
echo -e "${BLUE}  Running all unit and integration tests${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to run a test
run_test() {
    local test_name="$1"
    local verilog_files="$2"

    echo -e "${YELLOW}Running: ${test_name}${NC}"
    echo "----------------------------------------"

    # Compile
    if iverilog -g2012 -DSIMULATION -o /tmp/${test_name}.vvp ${verilog_files} 2>&1 | tee /tmp/${test_name}_compile.log; then
        echo -e "${GREEN}✓ Compilation successful${NC}"
    else
        echo -e "${RED}✗ Compilation failed${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("${RED}FAIL${NC} - ${test_name} (compilation)")
        return 1
    fi

    # Run simulation
    if vvp /tmp/${test_name}.vvp 2>&1 | tee /tmp/${test_name}_run.log; then
        # Check if all tests passed
        if grep -q "ALL TESTS PASSED" /tmp/${test_name}_run.log; then
            echo -e "${GREEN}✓ All tests passed${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            TEST_RESULTS+=("${GREEN}PASS${NC} - ${test_name}")
        elif grep -q "SOME TESTS FAILED" /tmp/${test_name}_run.log; then
            echo -e "${RED}✗ Some tests failed${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            TEST_RESULTS+=("${RED}FAIL${NC} - ${test_name}")
        else
            echo -e "${YELLOW}⚠ Test completion status unclear${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            TEST_RESULTS+=("${YELLOW}WARN${NC} - ${test_name}")
        fi
    else
        echo -e "${RED}✗ Simulation failed${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("${RED}FAIL${NC} - ${test_name} (simulation)")
        return 1
    fi

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
}

# Phase 1: Instruction Queue Tests
echo -e "${BLUE}=== Phase 1: Instruction Queue ===${NC}"
run_test "tb_instruction_queue" "tb_instruction_queue.v FPU_Instruction_Queue.v"

# Phase 2: Exception Handler Tests
echo -e "${BLUE}=== Phase 2: Exception Handler ===${NC}"
run_test "tb_exception_handler" "tb_exception_handler.v FPU_Exception_Handler.v"

# Phase 3: Integration Tests
echo -e "${BLUE}=== Phase 3: Exception Integration ===${NC}"
run_test "tb_fpu_exception_integration" "tb_fpu_exception_integration.v FPU_Exception_Handler.v"

# Phase 4: Asynchronous Operation Tests
echo -e "${BLUE}=== Phase 4: Asynchronous Operation ===${NC}"
run_test "tb_fpu_async_operation" "tb_fpu_async_operation.v FPU_Instruction_Queue.v"

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Test Results:"
for result in "${TEST_RESULTS[@]}"; do
    echo -e "  $result"
done
echo ""
echo "Statistics:"
echo -e "  Total test suites: ${TOTAL_TESTS}"
echo -e "  ${GREEN}Passed: ${PASSED_TESTS}${NC}"
echo -e "  ${RED}Failed: ${FAILED_TESTS}${NC}"
echo ""

# Individual test counts
echo "Detailed Test Counts:"
if [ -f /tmp/tb_instruction_queue_run.log ]; then
    IQ_TESTS=$(grep "Total Tests:" /tmp/tb_instruction_queue_run.log | awk '{print $3}')
    IQ_PASSED=$(grep "Passed:" /tmp/tb_instruction_queue_run.log | awk '{print $2}')
    echo -e "  Instruction Queue: ${IQ_PASSED}/${IQ_TESTS} tests passed"
fi

if [ -f /tmp/tb_exception_handler_run.log ]; then
    EH_TESTS=$(grep "Total Tests:" /tmp/tb_exception_handler_run.log | awk '{print $3}')
    EH_PASSED=$(grep "Passed:" /tmp/tb_exception_handler_run.log | awk '{print $2}')
    echo -e "  Exception Handler: ${EH_PASSED}/${EH_TESTS} tests passed"
fi

if [ -f /tmp/tb_fpu_exception_integration_run.log ]; then
    INT_TESTS=$(grep "Total Tests:" /tmp/tb_fpu_exception_integration_run.log | awk '{print $3}')
    INT_PASSED=$(grep "Passed:" /tmp/tb_fpu_exception_integration_run.log | awk '{print $2}')
    echo -e "  Integration Tests: ${INT_PASSED}/${INT_TESTS} tests passed"
fi

if [ -f /tmp/tb_fpu_async_operation_run.log ]; then
    ASYNC_TESTS=$(grep "Total Tests:" /tmp/tb_fpu_async_operation_run.log | awk '{print $3}')
    ASYNC_PASSED=$(grep "Passed:" /tmp/tb_fpu_async_operation_run.log | awk '{print $2}')
    echo -e "  Async Operation Tests: ${ASYNC_PASSED}/${ASYNC_TESTS} tests passed"
fi

echo ""

# Final result
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  ✓ ALL TEST SUITES PASSED${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  ✗ SOME TEST SUITES FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi
