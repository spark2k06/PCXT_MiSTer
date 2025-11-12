#!/bin/bash

# Unified Format Converter Test Script (Icarus Verilog)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

RESULT_DIR="sim_results_unified_converter_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_DIR"

echo "================================================================"
echo "Compiling Unified Format Converter Testbench"
echo "================================================================"
echo ""

# Compile the design
iverilog -g2012 \
    -o "$RESULT_DIR/tb_unified_converter" \
    FPU_Format_Converter_Unified.v \
    tb_format_converter_unified.v \
    > "$RESULT_DIR/compile.log" 2>&1

# Check compilation result
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo ""
    echo "[ERROR] Compilation failed! See compile.log for details."
    cat "$RESULT_DIR/compile.log"
    exit 1
fi

echo "✓ Compilation successful"
echo ""
echo "================================================================"
echo "Running Unified Format Converter Simulation"
echo "================================================================"
echo ""

# Run simulation
cd "$RESULT_DIR"
vvp tb_unified_converter > simulation.log 2>&1
SIM_EXIT=$?

# Display results
cat simulation.log

echo ""
echo "================================================================"
echo "Simulation Complete"
echo "================================================================"
echo ""
echo "Results saved to: $RESULT_DIR"
echo ""

# Check if all tests passed
if grep -q "ALL TESTS PASSED" simulation.log; then
    echo "✓✓✓ SUCCESS: All unified converter tests passed! ✓✓✓"
    exit 0
else
    echo "⚠ Check simulation.log for test results"
    exit $SIM_EXIT
fi
