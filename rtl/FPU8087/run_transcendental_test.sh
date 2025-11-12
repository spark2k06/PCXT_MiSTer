#!/bin/bash
# Compile and run transcendental function testbench

set -e  # Exit on error

echo "Compiling transcendental function testbench..."

cd /home/user/MyPC/Quartus/rtl/FPU8087

# Compile with Icarus Verilog
iverilog -g2009 -Wall -o tb_transcendental.vvp \
    tb_transcendental.v \
    FPU_Core.v \
    FPU_ArithmeticUnit.v \
    FPU_Transcendental.v \
    FPU_SQRT_Newton.v \
    FPU_CORDIC_Wrapper.v \
    FPU_Polynomial_Evaluator.v \
    FPU_Range_Reduction.v \
    FPU_Atan_Table.v \
    FPU_Poly_Coeff_ROM.v \
    CORDIC_Rotator.v \
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
    FPU_RegisterStack.v \
    FPU_StatusWord.v \
    FPU_ControlWord.v \
    AddSubComp.v \
    LZCbit.v \
    LZCByte.v \
    ByteShifter.v \
    BitShifter.v \
    RoundUnit.v \
    Normalizer.v \
    BarrelShifter.v \
    MathConstants.v \
    2>&1 | tee compile.log

if [ $? -eq 0 ]; then
    echo ""
    echo "Compilation successful!"
    echo ""
    echo "Running simulation..."
    vvp tb_transcendental.vvp | tee simulation.log
    echo ""
    echo "Simulation complete. Check simulation.log for results."
else
    echo ""
    echo "Compilation failed! Check compile.log for errors."
    exit 1
fi
