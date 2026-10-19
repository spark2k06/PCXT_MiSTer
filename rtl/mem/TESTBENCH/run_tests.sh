#!/usr/bin/env bash
#
# Run the memory-subsystem testbenches (SDRAM controller, arbiter, CPU port,
# memory map, ROM loader). They need Verilator 5 with --timing: the SDRAM
# model uses associative arrays and fork/join_none, which Icarus does not
# support.
#
#   ./run_tests.sh             every bench
#   ./run_tests.sh arbiter     benches whose name matches "arbiter"
#   VFLAGS=-DDQM_XS ./run_tests.sh   the chip's DQM taken from A[12:11], as on the
#                              MiSTer SDRAM XS/XSDS boards
#
# Every bench checks itself and prints "RESULT: PASS" or "RESULT: FAIL".
#
set -uo pipefail

BUILD_DIR=${TB_BUILD:-$HOME/.cache/pcxt-mem-tb}
FILTER=${1:-}

cd "$(dirname "$0")" || exit 1
TB=$(pwd)
MEM=$(cd .. && pwd)
ROOT=$(cd ../../.. && pwd)
mkdir -p "$BUILD_DIR"

PKG="$MEM/sdram_pkg.sv"
CTRL="$ROOT/platform/mister/sdram_ctrl.sv"
ARB="$MEM/sdram_arbiter.sv"
BRIDGE="$MEM/sdram_xbridge.sv"
PORT="$MEM/cpu_mem_port.sv"
MAP="$MEM/mem_map.sv"
LOADER="$MEM/rom_loader.sv"
MODEL="$TB/sdram_model.sv"
CPU8088="$ROOT/rtl/8088"
KFXT="$ROOT/rtl/KFPC-XT/HDL"
CPU="$CPU8088/wrappers/i8088.sv $CPU8088/mcl86_eu_core.sv $CPU8088/mcl86_ucode.sv $CPU8088/mcl86_biu_max.sv $CPU8088/mcl86_adder.sv"
XT="$KFXT/RAM.sv $KFXT/KFSDRAM/HDL/KFSDRAM.sv $KFXT/Ready.sv $KFXT/XT_CE_Generator.sv $KFXT/KF8288/HDL/KF8288.sv"
E2E="$PKG $CTRL $ARB $BRIDGE $PORT $MAP $MODEL $CPU $XT $TB/cpu_sdram_e2e_tb.sv"

# name | top module | -G parameters | sources
BENCHES=(
    "sdram_ctrl|sdram_ctrl_tb||$PKG $CTRL $MODEL $TB/sdram_ctrl_tb.sv"
    # Realistic CPU: a new request 10..20 clocks after the last one ended
    # (an 8088 bus cycle at Max is about 18 clocks). The CPU latency limit is checked here.
    "arbiter_pcxt_egatext|sdram_arbiter_tb|-GSAME_BANK=0 -GVID_PERIOD=28 -GVID_LEN=0 -GVID_LEAD=112 -GCPU_GAP_MIN=10 -GCPU_GAP_MAX=20|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    "arbiter_pcxt_cgahgc|sdram_arbiter_tb|-GSAME_BANK=0 -GVID_PERIOD=32 -GVID_LEN=1 -GVID_LEAD=128 -GCPU_GAP_MIN=10 -GCPU_GAP_MAX=20|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    "arbiter_pcxt_vga13|sdram_arbiter_tb|-GSAME_BANK=0 -GVID_PERIOD=73 -GVID_LEN=2 -GVID_LEAD=146 -GCPU_GAP_MIN=10 -GCPU_GAP_MAX=20|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    "arbiter_shared_tandy|sdram_arbiter_tb|-GSAME_BANK=1 -GVID_PERIOD=128 -GVID_LEN=1 -GVID_LEAD=256 -GCPU_GAP_MIN=10 -GCPU_GAP_MAX=20|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    "arbiter_shared_cgatext|sdram_arbiter_tb|-GSAME_BANK=1 -GVID_PERIOD=64 -GVID_LEN=0 -GVID_LEAD=128 -GCPU_GAP_MIN=10 -GCPU_GAP_MAX=20|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    # Stress: a CPU that never lets go, plus LDR and AUX. Correctness, VID latency,
    # underruns and starvation are checked; the CPU latency is only reported.
    "arbiter_stress_pcxt|sdram_arbiter_tb|-GSAME_BANK=0 -GVID_PERIOD=28 -GVID_LEN=0 -GVID_LEAD=112 -GCPU_GAP_MAX=4 -GEXTRA=1 -GLIMIT_CPU=64|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    "arbiter_stress_shared|sdram_arbiter_tb|-GSAME_BANK=1 -GVID_PERIOD=64 -GVID_LEN=0 -GVID_LEAD=128 -GCPU_GAP_MAX=0 -GEXTRA=1 -GLIMIT_CPU=64|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    # Rows with address bits 12:11 set (the chip's DQM pins on XS/XSDS boards):
    # correctness only. Run with and without VFLAGS=-DDQM_XS.
    "arbiter_highrows|sdram_arbiter_tb|-GSAME_BANK=1 -GVID_PERIOD=64 -GVID_LEN=0 -GVID_LEAD=128 -GCPU_GAP_MAX=0 -GEXTRA=1 -GLIMIT_CPU=64 -GHIGH_ROWS=1|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    "arbiter_highrows_vga13|sdram_arbiter_tb|-GSAME_BANK=0 -GVID_PERIOD=73 -GVID_LEN=2 -GVID_LEAD=146 -GCPU_GAP_MIN=10 -GCPU_GAP_MAX=20 -GLIMIT_CPU=64 -GHIGH_ROWS=1|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    "cpu_mem_port|cpu_mem_port_tb||$PKG $CTRL $ARB $BRIDGE $PORT $MAP $MODEL $TB/cpu_mem_port_tb.sv"
    # Whole CPU on the old and the new memory path side by side.
    "e2e_optB_8088|cpu_sdram_e2e_tb|-GOPTION_A=0 -GIS8086=0|$E2E"
    "e2e_optB_8086|cpu_sdram_e2e_tb|-GOPTION_A=0 -GIS8086=1|$E2E"
    "e2e_optA_8088|cpu_sdram_e2e_tb|-GOPTION_A=1 -GIS8086=0|$E2E"
    "e2e_optA_8086|cpu_sdram_e2e_tb|-GOPTION_A=1 -GIS8086=1|$E2E"
    "mem_map|mem_map_tb||$PKG $MAP $TB/mem_map_tb.sv"
    "rom_loader|rom_loader_tb||$PKG $LOADER $TB/rom_loader_tb.sv"
)

pass=0; fail=0; skip=0

for entry in "${BENCHES[@]}"; do
    IFS='|' read -r name top params sources <<< "$entry"
    if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi

    missing=""
    for f in $sources; do [ -f "$f" ] || missing="$missing $(basename "$f")"; done
    if [ -n "$missing" ]; then
        printf '  %-24s MISSING%s\n' "$name" "$missing"; skip=$((skip+1)); continue
    fi

    out=$BUILD_DIR/$name
    log=$BUILD_DIR/$name.log
    blog=$BUILD_DIR/$name.build.log
    : > "$log"
    start=$(date +%s)
    verilator --binary --timing --timescale 1ns/1ps -Wno-fatal -Wno-lint -Wno-style ${VFLAGS:-} \
        -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD -Wno-INITIALDLY \
        --top-module "$top" $params -Mdir "$out" -o sim $sources > "$blog" 2>&1 \
        && cp "$CPU8088/mcl86_ucode.mem" "$out/"         && (cd "$out" && ./sim) > "$log" 2>&1
    rc=$?
    [ -s "$log" ] || cp "$blog" "$log"
    elapsed=$(( $(date +%s) - start ))

    if grep -q 'RESULT: PASS' "$log" && [ $rc -eq 0 ]; then
        printf '  %-24s pass  (%ss)\n' "$name" "$elapsed"
        grep -vE 'RESULT|\$finish' "$log" | sed 's/^/      /'
        pass=$((pass+1))
    elif grep -q 'RESULT: FAIL' "$log"; then
        printf '  %-24s FAIL  (%ss)  %s\n' "$name" "$elapsed" "$log"
        grep -E 'ERROR|FAIL' "$log" | head -10 | sed 's/^/      /'
        fail=$((fail+1))
    else
        printf '  %-24s BUILD/RUN FAIL  (%ss)  %s\n' "$name" "$elapsed" "$log"
        grep -E '%Error|Error' "$log" | head -10 | sed 's/^/      /'
        skip=$((skip+1))
    fi
done

echo
echo "mem: $pass passed, $fail failed, $skip did not build"
[ $fail -eq 0 ] && [ $skip -eq 0 ]
