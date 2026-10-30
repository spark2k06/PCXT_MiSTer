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
VFETCH="$MEM/vram_fetch.sv $MEM/vid_mux.sv"
RCLEAR="$MEM/ram_clear.sv"
VID="$ROOT/rtl/video"
VCARDS="$VID/UM6845R_cga.v $VID/cga.v $VID/cga_sequencer.v $VID/cga_pixel.sv $VID/cga_attrib.v $VID/cga_splash_renderer.v $VID/video_scandoubler_cga.v $ROOT/rtl/common/jtframe_dual_ram.v $VID/hgc.v $VID/hgc_sequencer.v $VID/hgc_pixel.v $VID/hgc_attrib.v $VID/crtc_vram_if.sv $VID/cga_vram_if.sv $VID/hgc_vram_if.sv $VID/vram.v"
MAPEGA="$MEM/mem_map_ega.sv"
TXNMUX="$MEM/sdram_txn_mux.sv"
MODEL="$TB/sdram_model.sv"
CPU8088="$ROOT/rtl/8088"
KFXT="$ROOT/rtl/KFPC-XT/HDL"
CPU="$CPU8088/wrappers/i8088.sv $CPU8088/mcl86_eu_core.sv $CPU8088/mcl86_ucode.sv $CPU8088/mcl86_biu_max.sv $CPU8088/mcl86_adder.sv"
XT="$KFXT/RAM.sv $KFXT/KFSDRAM/HDL/KFSDRAM.sv $KFXT/Ready.sv $KFXT/XT_CE_Generator.sv $KFXT/KF8288/HDL/KF8288.sv"
E2E="$PKG $CTRL $ARB $BRIDGE $PORT $MAP $MODEL $CPU $XT $TB/cpu_sdram_e2e_tb.sv"
# The cards on; sound and EMS options off (config.tcl has them on, they are not under test)
DEFS="-DENABLE_CGA=1 -DENABLE_HGC=1 -DENABLE_OPL2=0 -DENABLE_CMS=0 -DENABLE_MIDI=0 -DENABLE_EMS=0"
INCS="-I$KFXT/KF8237/HDL -I$KFXT/KF8253/HDL -I$KFXT/KF8255/HDL -I$KFXT/KF8259/HDL"
# Everything the machine is made of, as the qips list it (sys_video_files.lst), plus stubs
SYSV="$TB/sys_video_stubs.sv $MODEL $(tr -d '' < "$TB/sys_video_files.lst" | sed "s|^|$ROOT/|" | tr '\n' ' ') $TB/sys_video_tb.sv"

# name | top module | -G parameters | sources
BENCHES=(
    "sdram_ctrl|sdram_ctrl_tb||$PKG $CTRL $MODEL $TB/sdram_ctrl_tb.sv"
    # Realistic CPU: a new request 10..20 clocks after the last one ended
    # (an 8088 bus cycle at Max is about 18 clocks). The CPU latency limit is checked here.
    "arbiter_pcxt_egatext|sdram_arbiter_tb|-GSAME_BANK=0 -GVID_PERIOD=28 -GVID_LEN=0 -GVID_LEAD=112 -GCPU_GAP_MIN=10 -GCPU_GAP_MAX=20|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    "arbiter_pcxt_cgahgc|sdram_arbiter_tb|-GSAME_BANK=0 -GVID_PERIOD=32 -GVID_LEN=1 -GVID_LEAD=128 -GCPU_GAP_MIN=10 -GCPU_GAP_MAX=20|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    "arbiter_shared_tandy|sdram_arbiter_tb|-GSAME_BANK=1 -GVID_PERIOD=128 -GVID_LEN=1 -GVID_LEAD=256 -GCPU_GAP_MIN=10 -GCPU_GAP_MAX=20|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    "arbiter_shared_cgatext|sdram_arbiter_tb|-GSAME_BANK=1 -GVID_PERIOD=64 -GVID_LEN=0 -GVID_LEAD=128 -GCPU_GAP_MIN=10 -GCPU_GAP_MAX=20|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    # Stress: a CPU that never lets go, plus LDR and AUX. Correctness, VID latency,
    # underruns and starvation are checked; the CPU latency is only reported.
    "arbiter_stress_pcxt|sdram_arbiter_tb|-GSAME_BANK=0 -GVID_PERIOD=28 -GVID_LEN=0 -GVID_LEAD=112 -GCPU_GAP_MAX=4 -GEXTRA=1 -GLIMIT_CPU=64|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    "arbiter_stress_shared|sdram_arbiter_tb|-GSAME_BANK=1 -GVID_PERIOD=64 -GVID_LEN=0 -GVID_LEAD=128 -GCPU_GAP_MAX=0 -GEXTRA=1 -GLIMIT_CPU=64|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    # Rows with address bits 12:11 set (the chip's DQM pins on XS/XSDS boards):
    # correctness only. Run with and without VFLAGS=-DDQM_XS.
    "arbiter_highrows|sdram_arbiter_tb|-GSAME_BANK=1 -GVID_PERIOD=64 -GVID_LEN=0 -GVID_LEAD=128 -GCPU_GAP_MAX=0 -GEXTRA=1 -GLIMIT_CPU=64 -GHIGH_ROWS=1|$PKG $CTRL $ARB $MODEL $TB/sdram_arbiter_tb.sv"
    "cpu_mem_port|cpu_mem_port_tb||$PKG $CTRL $ARB $BRIDGE $PORT $MAP $MODEL $TB/cpu_mem_port_tb.sv"
    # Whole CPU on the old and the new memory path side by side.
    "e2e_optB_8088|cpu_sdram_e2e_tb|-GOPTION_A=0 -GIS8086=0|$E2E"
    "e2e_optB_8086|cpu_sdram_e2e_tb|-GOPTION_A=0 -GIS8086=1|$E2E"
    "e2e_optA_8088|cpu_sdram_e2e_tb|-GOPTION_A=1 -GIS8086=0|$E2E"
    "e2e_optA_8086|cpu_sdram_e2e_tb|-GOPTION_A=1 -GIS8086=1|$E2E"
    # The instruction mix 8088 MPH times at start-up, run from RAM
    "e2e_mph_check|cpu_sdram_e2e_tb|-GOPTION_A=0 -GIS8086=0 -GPROG=1|$E2E"
    "mem_map|mem_map_tb||$PKG $MAP $TB/mem_map_tb.sv"
    "rom_loader|rom_loader_tb||$PKG $LOADER $TB/rom_loader_tb.sv"
    # A build that is only a Tandy 1000, and one that chooses the machine at run time
    "rom_loader_tandy|rom_loader_tb|-GMODEL=1|$PKG $LOADER $TB/rom_loader_tb.sv"
    "rom_loader_both|rom_loader_tb|-GMODEL=2|$PKG $LOADER $TB/rom_loader_tb.sv"
    # A build that is only a PCjr (slot 4)
    "rom_loader_pcjr|rom_loader_tb|-GMODEL=3|$PKG $LOADER $TB/rom_loader_tb.sv"
    # Video fetch engines against the real arbiter and chip model, with the CPU writing
    # into the words being fetched (coherence, ordering, late pops, flush).
    "vram_fetch|vram_fetch_tb||$PKG $CTRL $ARB $MODEL $VFETCH $TB/vram_fetch_tb.sv"
    # A real CGA / HGC fed through the adapter and an engine, against an ideal memory.
    "video_chain_cga|video_fetch_chain_tb|-GCARD=0|$PKG $CTRL $ARB $MODEL $VFETCH $VCARDS $TB/video_fetch_chain_tb.sv"
    "video_chain_hgc|video_fetch_chain_tb|-GCARD=1|$PKG $CTRL $ARB $MODEL $VFETCH $VCARDS $TB/video_fetch_chain_tb.sv"
    # The same with the CPU hammering the video memory (a write every few clocks)
    "video_chain_cga_cmp|video_fetch_chain_tb|-GCARD=0 -GCMP=1|$PKG $CTRL $ARB $MODEL $VFETCH $VCARDS $TB/video_fetch_chain_tb.sv"
    "video_chain_hgc_cmp|video_fetch_chain_tb|-GCARD=1 -GCMP=1|$PKG $CTRL $ARB $MODEL $VFETCH $VCARDS $TB/video_fetch_chain_tb.sv"
    "video_chain_cga_busy|video_fetch_chain_tb|-GCARD=0 -GWR_GAP=2 -GTARGET=1 -GPHASES=2|$PKG $CTRL $ARB $MODEL $VFETCH $VCARDS $TB/video_fetch_chain_tb.sv"
    # The CGA as the Tandy 1000 video: 128 KiB block of the CPU image, page by 3DFh
    "video_chain_tandy|video_fetch_chain_tb|-GCARD=0 -GTANDY=1 -DENABLE_TANDY_VIDEO=1|$PKG $CTRL $ARB $MODEL $VFETCH $VCARDS $TB/video_fetch_chain_tb.sv"
    "video_chain_tandy_cmp|video_fetch_chain_tb|-GCARD=0 -GTANDY=1 -GCMP=1 -DENABLE_TANDY_VIDEO=1|$PKG $CTRL $ARB $MODEL $VFETCH $VCARDS $TB/video_fetch_chain_tb.sv"
    "video_chain_tandy_busy|video_fetch_chain_tb|-GCARD=0 -GTANDY=1 -GWR_GAP=2 -GTARGET=1 -GPHASES=5 -DENABLE_TANDY_VIDEO=1|$PKG $CTRL $ARB $MODEL $VFETCH $VCARDS $TB/video_fetch_chain_tb.sv"
    "video_chain_hgc_busy|video_fetch_chain_tb|-GCARD=1 -GWR_GAP=2 -GTARGET=1 -GPHASES=2|$PKG $CTRL $ARB $MODEL $VFETCH $VCARDS $TB/video_fetch_chain_tb.sv"
    # The whole machine around the video memory: CPU program, chipset, CGA, HGC, SDRAM.
    "sys_video_4_77|sys_video_tb|-GSPEED=0|$SYSV"
    "sys_video_max|sys_video_tb|-GSPEED=3|$SYSV"
    "vram_fetch_busy|vram_fetch_tb|-GWR_GAP=3 -GB_PERIOD=32 -GLATE_PCT=10|$PKG $CTRL $ARB $MODEL $VFETCH $TB/vram_fetch_tb.sv"
    # F3: the EGA card's memory map and the second master of the CPU port
    "mem_map_ega|mem_map_ega_tb||$PKG $MAPEGA $TB/mem_map_ega_tb.sv"
    "sdram_txn_mux|sdram_txn_mux_tb||$TXNMUX $TB/sdram_txn_mux_tb.sv"
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
        -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD -Wno-INITIALDLY -Wno-BLKANDNBLK $INCS $DEFS \
        --top-module "$top" $params -Mdir "$out" -o sim $sources > "$blog" 2>&1 \
        && cp "$CPU8088/mcl86_ucode.mem" "$TB/sys_video_prog.hex" "$VID/cga.hex" "$VID/hgc.hex" "$VID/splash_320x200.hex" "$out/"         && (cd "$out" && ./sim) > "$log" 2>&1
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
