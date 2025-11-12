#!/bin/bash
# Test script for hybrid execution validation

set -e

echo "========================================"
echo "Compiling Hybrid Execution Test"
echo "========================================"

# Find all required modules
MODULES=(
    "FPU_ArithmeticUnit.v"
    "FPU_AddSub.v"
    "FPU_Multiplier.v"
    "FPU_Divider.v"
    "FPU_SquareRoot.v"
    "FPU_Transcendental.v"
    "fp80_to_fp32_converter.v"
    "fp80_to_fp64_converter.v"
    "fp32_to_fp80_converter.v"
    "fp64_to_fp80_converter.v"
    "int16_to_fp80_converter.v"
    "int32_to_fp80_converter.v"
    "fp80_to_int16_converter.v"
    "fp80_to_int32_converter.v"
    "uint64_to_fp80_converter.v"
    "fp80_to_uint64_converter.v"
    "bcd_to_binary_converter.v"
    "binary_to_bcd_converter.v"
    "MicroSequencer_Extended.v"
    "tb_hybrid_execution.v"
)

# Check for missing files
echo "Checking for required modules..."
for module in "${MODULES[@]}"; do
    if [ ! -f "$module" ]; then
        echo "WARNING: $module not found (may cause compilation errors)"
    fi
done

# Compile with Icarus Verilog
echo ""
echo "Compiling with Icarus Verilog..."
iverilog -g2009 -o hybrid_test.vvp \
    -I. \
    FPU_ArithmeticUnit.v \
    FPU_Transcendental.v \
    FPU_SQRT_Newton.v \
    FPU_CORDIC_Wrapper.v \
    FPU_Polynomial_Evaluator.v \
    FPU_Range_Reduction.v \
    FPU_Atan_Table.v \
    FPU_Poly_Coeff_ROM.v \
    CORDIC_Rotator.v \
    BarrelShifter.v \
    FPU_IEEE754_AddSub.v \
    FPU_IEEE754_Multiply.v \
    FPU_IEEE754_Divide.v \
    FPU_Int16_to_FP80.v \
    FPU_Int32_to_FP80.v \
    FPU_FP80_to_Int16.v \
    FPU_FP80_to_Int32.v \
    FPU_UInt64_to_FP80.v \
    FPU_FP80_to_UInt64.v \
    FPU_BCD_to_Binary.v \
    FPU_Binary_to_BCD.v \
    FPU_FP32_to_FP80.v \
    FPU_FP64_to_FP80.v \
    FPU_FP80_to_FP32.v \
    FPU_FP80_to_FP64.v \
    MicroSequencer_Extended.v \
    tb_hybrid_execution.v \
    2>&1 | tee compile.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo ""
    echo "*** Compilation FAILED - see compile.log ***"
    exit 1
fi

echo ""
echo "========================================"
echo "Running Simulation"
echo "========================================"
vvp hybrid_test.vvp | tee simulation.log

echo ""
echo "========================================"
echo "Simulation Complete"
echo "========================================"
echo "Check simulation.log for results"
