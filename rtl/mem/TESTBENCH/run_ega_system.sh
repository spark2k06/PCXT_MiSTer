#!/usr/bin/env bash
#
# The EGA/VGA equivalence bench of vendor/pc_common (the core on BRAM against the
# core on SDRAM, same stimulus, same picture shifted by the retiming) on the REAL
# memory stack: frontend -> sdram_txn_mux -> xbridge -> arbiter -> controller ->
# chip model, with a second master hammering bank 0 like an 8088 at Max.
# Fails on any difference of the picture, video underruns or errors of the chip
# model. Verilator 5 with --timing.
#
#   ./run_ega_system.sh                  all scenarios
#   ./run_ega_system.sh -GONLY=1         one scenario (index), as for the bench parameter
#   VFLAGS=-DDQM_XS ./run_ega_system.sh  the chip's DQM taken from A[12:11] (XS boards)
#
set -uo pipefail
BUILD_DIR=${TB_BUILD:-$HOME/.cache/pcxt-mem-tb}/ega_system
mkdir -p "$BUILD_DIR"
TB=$(cd "$(dirname "$0")" && pwd)
MEM=$(cd "$TB/.." && pwd)
ROOT=$(cd "$TB/../../.." && pwd)
LIB=$ROOT/vendor/pc_common

SRC=("$MEM/sdram_pkg.sv" "$MEM/sdram_arbiter.sv" "$MEM/sdram_xbridge.sv" "$MEM/sdram_txn_mux.sv"
     "$MEM/vram_fetch.sv" "$MEM/vid_mux.sv" "$ROOT/platform/mister/sdram_ctrl.sv"
     "$TB/sdram_model.sv" "$TB/ega_real_stack.sv"
     "$LIB/rtl/ega/ega_vram_fns_pkg.sv")
for f in "$LIB"/rtl/ega/*.v "$LIB"/rtl/vga/*.v "$LIB"/rtl/mem/*.sv; do
    case "$f" in *video_monochrome_converter*) continue ;; esac
    SRC+=("$f")
done
SRC+=("$LIB"/TESTBENCH/ref_rtl/*.v "$LIB"/TESTBENCH/ref_rtl/*.sv)

verilator --binary --timing --public-flat-rw -Wno-fatal -Wno-lint -Wno-style -j "${TB_JOBS:-8}" \
    --Mdir "$BUILD_DIR" -o ega_system_tb --top-module ega_sdram_equiv_tb \
    -DPORT_MODEL=ega_real_stack ${VFLAGS:-} "$@" \
    "${SRC[@]}" "$LIB/TESTBENCH/ega_sdram_equiv_tb.sv" > "$BUILD_DIR/build.log" 2>&1 \
    || { grep -E '%Error' "$BUILD_DIR/build.log" | head -20; echo "BUILD FAIL ($BUILD_DIR/build.log)"; exit 1; }

stdbuf -oL "$BUILD_DIR/ega_system_tb" 2>&1 | tee "$BUILD_DIR/run.log"
grep -q "RESULT: PASS" "$BUILD_DIR/run.log"
