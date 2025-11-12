#!/bin/bash
# Compile and run instruction decoder testbench

set -e  # Exit on error

echo "Compiling instruction decoder testbench..."

cd /home/user/MyPC/Quartus/rtl/FPU8087

# Compile with Icarus Verilog
iverilog -g2009 -Wall -o tb_decoder.vvp \
    tb_instruction_decoder.v \
    FPU_Instruction_Decoder.v \
    2>&1 | tee decoder_compile.log

if [ $? -eq 0 ]; then
    echo ""
    echo "Compilation successful!"
    echo ""
    echo "Running simulation..."
    vvp tb_decoder.vvp | tee decoder_test.log
    echo ""
    echo "Simulation complete. Check decoder_test.log for results."
else
    echo ""
    echo "Compilation failed! Check decoder_compile.log for errors."
    exit 1
fi
