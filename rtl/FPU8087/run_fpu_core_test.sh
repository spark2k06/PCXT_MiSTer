#!/bin/bash

#=====================================================================
# FPU Core Integration Test Runner
#
# Compiles and runs the FPU_Core integration testbench
# Requires: Icarus Verilog
#=====================================================================

echo "========================================"
echo "FPU Core Integration Test"
echo "========================================"

# Set paths
FPU_DIR="."
TB_FILE="tb_fpu_core.v"
OUTPUT="tb_fpu_core"
VCD_FILE="fpu_core_test.vcd"

# Clean previous outputs
rm -f $OUTPUT
rm -f $VCD_FILE
rm -f fpu_core_compile.log

# List of all required Verilog files
VERILOG_FILES=(
    # Core integration module
    "FPU_Core.v"

    # Component modules
    "FPU_RegisterStack.v"
    "FPU_StatusWord.v"
    "FPU_ControlWord.v"
    "FPU_ArithmeticUnit.v"

    # IEEE 754 arithmetic modules
    "FPU_IEEE754_AddSub.v"
    "FPU_IEEE754_Multiply.v"
    "FPU_IEEE754_Divide.v"

    # Integer conversion modules
    "FPU_Int16_to_FP80.v"
    "FPU_Int32_to_FP80.v"
    "FPU_FP80_to_Int16.v"
    "FPU_FP80_to_Int32.v"

    # FP format conversion modules
    "FPU_FP32_to_FP80.v"
    "FPU_FP64_to_FP80.v"
    "FPU_FP80_to_FP32.v"
    "FPU_FP80_to_FP64.v"

    # Testbench
    "$TB_FILE"
)

# Check if all files exist
echo "Checking for required files..."
all_exist=true
for file in "${VERILOG_FILES[@]}"; do
    if [ ! -f "$FPU_DIR/$file" ]; then
        echo "ERROR: Missing file: $file"
        all_exist=false
    fi
done

if [ "$all_exist" = false ]; then
    echo "ERROR: Some required files are missing!"
    exit 1
fi

echo "All required files found."
echo ""

# Compile with Icarus Verilog
echo "Compiling FPU Core testbench..."
echo "Command: iverilog -o $OUTPUT ${VERILOG_FILES[@]}"
echo ""

iverilog -g2012 -o $OUTPUT -s tb_fpu_core \
    ${VERILOG_FILES[@]} 2>&1 | tee fpu_core_compile.log

# Check compilation result
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "COMPILATION FAILED!"
    echo "========================================"
    echo "Check fpu_core_compile.log for details"
    exit 1
fi

echo ""
echo "Compilation successful!"
echo ""

# Run simulation
echo "========================================"
echo "Running FPU Core Integration Tests..."
echo "========================================"
echo ""

vvp $OUTPUT | tee fpu_core_test_results.txt

# Check test result
if grep -q "ALL TESTS PASSED" fpu_core_test_results.txt; then
    echo ""
    echo "========================================"
    echo "✓ ALL TESTS PASSED!"
    echo "========================================"
    exit 0
else
    echo ""
    echo "========================================"
    echo "✗ SOME TESTS FAILED"
    echo "========================================"
    echo "Check fpu_core_test_results.txt for details"
    exit 1
fi
