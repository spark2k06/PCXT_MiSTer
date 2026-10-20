#!/usr/bin/env bash
#
# Run the sound-side testbenches.
#
#   ./run_tests.sh                 every bench
#   ./run_tests.sh -n              niced, to share the machine with a synthesis
#   ./run_tests.sh dma             benches whose name matches "dma"
#
# These run under Verilator, not Icarus, and that is deliberate rather than a
# preference: the benches here instantiate the real BUS_ARBITER, which brings
# the real KF8237 with it, and Icarus cannot elaborate that controller - it
# rejects the whole-array assignments in its priority encoder. The sibling
# runners in rtl/KFPC-XT and rtl/video stay on Icarus and skip the 8237
# entirely.
#
# Testing the DMA glue against a hand-written model of the DMA controller would
# have been easy and worthless: the glue's whole job is to match what this
# core's controller actually does on the bus. So these drive the real thing.
#
# Every bench here checks itself and prints PASS or FAIL.
#
set -uo pipefail

BUILD_DIR=${TB_BUILD:-$HOME/.cache/pcxt-sound-tb}
NICE=""
FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--nice)  NICE="nice -n 19" ;;
        -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
        *)          FILTER="$1" ;;
    esac
    shift
done

cd "$(dirname "$0")/../../.." || exit 1
mkdir -p "$BUILD_DIR"

# The chipset sources every sound bench needs to see a real DMA cycle.
BUS_SOURCES="rtl/KFPC-XT/HDL/Bus_Arbiter.sv \
             rtl/KFPC-XT/HDL/KF8237/HDL/KF8237.sv \
             rtl/KFPC-XT/HDL/KF8237/HDL/KF8237_Address_And_Count_Registers.sv \
             rtl/KFPC-XT/HDL/KF8237/HDL/KF8237_Bus_Control_Logic.sv \
             rtl/KFPC-XT/HDL/KF8237/HDL/KF8237_Priority_Encoder.sv \
             rtl/KFPC-XT/HDL/KF8237/HDL/KF8237_Timing_And_Control.sv \
             rtl/KFPC-XT/HDL/KF8288/HDL/KF8288.sv"

SB_SOURCES="rtl/sound/soundblaster.sv rtl/sound/sb_dsp.sv \
            rtl/sound/sb_dma_glue.sv rtl/sound/sb_mixer.sv rtl/sound/sb_volume.sv"

declare -A SOURCES=(
    [sb_dma_cycle_tb]="$BUS_SOURCES"
    [sb_dma_stream_tb]="rtl/sound/sb_dma_glue.sv $BUS_SOURCES"
    [sb_playback_tb]="$SB_SOURCES $BUS_SOURCES"
    [sb_stereo_tb]="$SB_SOURCES $BUS_SOURCES"
    [sb_mixer_tb]="$SB_SOURCES"
    [sb_fm_path_tb]="$SB_SOURCES"
    [sb_driver_poll_tb]="$SB_SOURCES $BUS_SOURCES"
    [sb_dma_id_tb]="$SB_SOURCES $BUS_SOURCES"
)

INCLUDES="-Irtl/KFPC-XT/HDL/KF8237/HDL"

pass=0; fail=0; skip=0

for stem in $(printf '%s\n' "${!SOURCES[@]}" | sort); do
    if [ -n "$FILTER" ] && [[ "$stem" != *"$FILTER"* ]]; then continue; fi

    tb="rtl/sound/TESTBENCH/$stem.sv"
    [ -f "$tb" ] || {
        printf '  %-34s MISSING\n' "$stem"; skip=$((skip+1)); continue
    }

    log=$BUILD_DIR/$stem.log

    # Truncate: the verdict greps the whole file, so a stale failure left here
    # would keep being reported long after the bench was fixed.
    : > "$log"

    start=$(date +%s)

    # -Wno-fatal because the vendored KF8237 carries width warnings this fork
    # does not touch. Real elaboration errors still stop the build.
    $NICE verilator --binary --timing -Wno-fatal -j 4 $INCLUDES \
        --top-module "$stem" --Mdir "$BUILD_DIR/$stem" -o "$stem" \
        "$tb" ${SOURCES[$stem]} > "$log" 2>&1 \
        && $NICE timeout 300 "$BUILD_DIR/$stem/$stem" >> "$log" 2>&1
    rc=$?

    elapsed=$(( $(date +%s) - start ))

    if [ $rc -ne 0 ] && ! grep -qE 'RESULT|PASS|FAIL' "$log"; then
        printf '  %-34s BUILD FAIL  (%ss)  %s\n' "$stem" "$elapsed" "$log"
        skip=$((skip+1))
    elif grep -qE 'RESULT: FAIL|TIMEOUT|^FAIL' "$log"; then
        printf '  %-34s FAIL        (%ss)\n' "$stem" "$elapsed"
        grep -E '^FAIL|TIMEOUT|RESULT: FAIL' "$log" | sed 's/^/      /'
        fail=$((fail+1))
    else
        printf '  %-34s pass        (%ss)\n' "$stem" "$elapsed"
        pass=$((pass+1))
    fi
done

echo
echo "sound: $pass passed, $fail failed, $skip did not build"
[ $fail -eq 0 ] && [ $skip -eq 0 ]
