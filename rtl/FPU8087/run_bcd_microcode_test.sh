#!/bin/bash

#=====================================================================
# FPU Core BCD Microcode Integration Test Runner
#
# Tests FBLD and FBSTP instructions using the integrated microsequencer
#=====================================================================

echo "========================================"
echo "FPU BCD Microcode Integration Test"
echo "========================================"

# Set paths
FPU_DIR="."
TB_FILE="tb_fpu_core_bcd_microcode.v"
OUTPUT="tb_fpu_core_bcd_microcode"
VCD_FILE="tb_fpu_core_bcd_microcode.vcd"

# Clean previous outputs
rm -f $OUTPUT
rm -f $VCD_FILE
rm -f bcd_microcode_compile.log

# List of all required Verilog files
VERILOG_FILES=(
    # Core integration module
    "FPU_Core.v"

    # Component modules
    "FPU_RegisterStack.v"
    "StackRegister.v"
    "FPU_StatusWord.v"
    "FPU_ControlWord.v"
    "FPU_ArithmeticUnit.v"

    # BCD converter modules
    "FPU_BCD_to_Binary.v"
    "FPU_Binary_to_BCD.v"

    # Microsequencer
    "MicroSequencer_Extended_BCD.v"

    # IEEE 754 arithmetic modules
    "FPU_IEEE754_AddSub.v"
    "FPU_IEEE754_MulDiv_Unified.v"
    "FPU_IEEE754_Multiply.v"
    "FPU_IEEE754_Divide.v"

    # Integer conversion modules
    "FPU_Int16_to_FP80.v"
    "FPU_Int32_to_FP80.v"
    "FPU_FP80_to_Int16.v"
    "FPU_FP80_to_Int32.v"
    "FPU_UInt64_to_FP80.v"
    "FPU_FP80_to_UInt64.v"

    # FP format conversion modules
    "FPU_Format_Converter_Unified.v"

    # Transcendental modules
    "FPU_Transcendental.v"
    "FPU_CORDIC_Wrapper.v"
    "FPU_Polynomial_Evaluator.v"
    "FPU_Poly_Coeff_ROM.v"
    "FPU_Range_Reduction.v"
    "FPU_Atan_Table.v"
    "FPU_SQRT_Newton.v"

    # Testbench
    "$TB_FILE"
)

# Check if all files exist
echo "Checking for required files..."
all_exist=true
for file in "${VERILOG_FILES[@]}"; do
    if [ ! -f "$FPU_DIR/$file" ]; then
        echo "WARNING: Missing file: $file (continuing anyway)"
    fi
done

echo "Starting compilation..."
echo ""

# Compile with Icarus Verilog
echo "Compiling FPU BCD Microcode testbench..."
echo ""

iverilog -g2012 -o $OUTPUT -s tb_fpu_core_bcd_microcode \
    ${VERILOG_FILES[@]} 2>&1 | tee bcd_microcode_compile.log

# Check compilation result
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "COMPILATION FAILED!"
    echo "========================================"
    echo "Check bcd_microcode_compile.log for details"
    exit 1
fi

echo ""
echo "Compilation successful!"
echo ""

# Run simulation
echo "========================================"
echo "Running BCD Microcode Integration Tests..."
echo "========================================"
echo ""

vvp $OUTPUT | tee bcd_microcode_test_results.txt

# Check test result
echo ""
echo "========================================"
echo "Simulation Complete"
echo "========================================"
echo ""
echo "Check bcd_microcode_test_results.txt for results"
echo "VCD waveform: $VCD_FILE"

exit 0
