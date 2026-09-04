#!/usr/bin/env bash
#
# Run the chipset-side testbenches.
#
#   ./run_tests.sh                 every bench
#   ./run_tests.sh -n              niced, to share the machine with a synthesis
#   ./run_tests.sh bios            benches whose name matches "bios"
#   ./run_tests.sh -w Ready        dump a VCD next to the build (Icarus only)
#
# It covers the chipset and the peripherals under it, including the vendored
# KFPC-XT cores in HDL/*/.
#
# Two kinds of bench live here and they are not equally strong:
#
#   The PCXT-written ones check themselves and print PASS or FAIL. A pass means
#   the property held.
#
#   The vendored kitune-san ones mostly only run to $finish and leave a
#   waveform to look at. A pass there means it elaborated and terminated, no
#   more. KFPS2KB is the exception: its F12 section checks itself.
#
# Not run here:
#
#   Chipset_tb needs most of the design (sound, uart, common, the whole video
#   tree) and does not build from this directory.
#   KF8237's four benches fail to elaborate on Icarus with "this assignment
#   requires an explicit cast", in vendored code this fork does not touch.
#   KF8259_In_Service and KF8259_Interrupt_Request connect with .* to signals
#   their modules no longer have - upstream drift, not this fork's.
#
set -uo pipefail

BUILD_DIR=${TB_BUILD:-$HOME/.cache/pcxt-chipset-tb}
NICE=""
WAVE=""
FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--nice)  NICE="nice -n 19" ;;
        -w|--wave)  WAVE="-DIVERILOG" ;;
        -h|--help)  sed -n '2,30p' "$0"; exit 0 ;;
        *)          FILTER="$1" ;;
    esac
    shift
done

cd "$(dirname "$0")/.." || exit 1
mkdir -p "$BUILD_DIR"

# Each bench names the sources it needs. The vendored peripherals carry package
# headers their own directory has to be on the include path for.
declare -A SOURCES=(
    [ram_refresh_collision_tb]="HDL/RAM.sv HDL/KFSDRAM/HDL/KFSDRAM.sv"
    [ram_lookahead_tb]="HDL/RAM.sv HDL/KFSDRAM/HDL/KFSDRAM.sv"
    [Ready_tb]="HDL/Ready.sv"
    [CGA_Bus_Wait_tb]="HDL/CGA_Bus_Wait.sv"
    [Bus_Arbiter_Hold_tb]="HDL/Bus_Arbiter.sv"
    [splash_f12_pause_tb]="HDL/splash_f12_pause.sv"
    [bios_hold_notice_tb]="HDL/bios_hold_notice.sv"
    [rom_presence_latch_tb]="HDL/rom_presence_latch.sv"
    [KF8253_tb]="HDL/KF8253/HDL/KF8253.sv HDL/KF8253/HDL/KF8253_Counter.sv HDL/KF8253/HDL/KF8253_Control_Logic.sv"
    [KF8255_tb]="HDL/KF8255/HDL/KF8255.sv HDL/KF8255/HDL/KF8255_Group.sv HDL/KF8255/HDL/KF8255_Port.sv HDL/KF8255/HDL/KF8255_Port_C.sv HDL/KF8255/HDL/KF8255_Control_Logic.sv"
    [KF8259_tb]="HDL/KF8259/HDL/KF8259.sv HDL/KF8259/HDL/KF8259_Bus_Control_Logic.sv HDL/KF8259/HDL/KF8259_Control_Logic.sv HDL/KF8259/HDL/KF8259_In_Service.sv HDL/KF8259/HDL/KF8259_Interrupt_Request.sv HDL/KF8259/HDL/KF8259_Priority_Resolver.sv"
    [KF8259_Bus_Control_Logic_tb]="HDL/KF8259/HDL/KF8259_Bus_Control_Logic.sv"
    [KF8288_tb]="HDL/KF8288/HDL/KF8288.sv"
    [KFPS2KB_tb]="HDL/KFPS2KB/HDL/KFPS2KB.sv HDL/KFPS2KB/HDL/KFPS2KB_Shift_Register.sv HDL/KFPS2KB/HDL/KFPS2KB_Send_Data.sv"
)

# Where each bench file lives, since the vendored ones keep their own TESTBENCH.
find_tb() {
    local stem=$1 hit
    for hit in "TESTBENCH/$stem.sv" HDL/*/TESTBENCH/"$stem.sv"; do
        [ -f "$hit" ] && { echo "$hit"; return 0; }
    done
    return 1
}

INCLUDES=""
for dir in HDL/*/HDL; do
    [ -n "$(echo "$dir"/*.svh 2>/dev/null | grep -v '\*')" ] && INCLUDES="$INCLUDES -I$dir"
done

pass=0; fail=0; skip=0

for stem in $(printf '%s\n' "${!SOURCES[@]}" | sort); do
    if [ -n "$FILTER" ] && [[ "$stem" != *"$FILTER"* ]]; then continue; fi

    tb=$(find_tb "$stem") || {
        printf '  %-34s MISSING\n' "$stem"; skip=$((skip+1)); continue
    }

    log=$BUILD_DIR/$stem.log

    # Every write below appends, and the pass/fail verdict greps the whole
    # file. Without this truncation a run that once failed keeps reporting
    # that failure from cache long after the bench was fixed.
    : > "$log"

    start=$(date +%s)

    # Built without -DIVERILOG unless -w is given: the vendored benches guard
    # their $dumpfile with it, and a VCD per run is noise in a batch.
    $NICE iverilog -g2012 $WAVE $INCLUDES -o "$BUILD_DIR/$stem.vvp" \
        "$tb" ${SOURCES[$stem]} > "$log" 2>&1 \
        && (cd "$BUILD_DIR" && $NICE timeout 300 vvp "$BUILD_DIR/$stem.vvp") >> "$log" 2>&1
    rc=$?

    elapsed=$(( $(date +%s) - start ))

    # A bench that stops with $fatal exits non-zero and may print neither
    # RESULT nor PASS, so match its ERROR/FATAL lines too - otherwise a real
    # regression is filed as a toolchain problem and quietly ignored.
    if [ $rc -ne 0 ] && ! grep -qE 'RESULT|PASS|FAIL|^ERROR|^FATAL' "$log"; then
        printf '  %-34s BUILD FAIL  (%ss)  %s\n' "$stem" "$elapsed" "$log"
        skip=$((skip+1))
    elif grep -qE 'RESULT: FAIL|TIMEOUT|^FAIL|^ERROR|^FATAL|[1-9][0-9]* failed' "$log"; then
        printf '  %-34s FAIL        (%ss)\n' "$stem" "$elapsed"
        grep -E '^FAIL|TIMEOUT|RESULT: FAIL|^ERROR|^FATAL' "$log" | sed 's/^/      /'
        fail=$((fail+1))
    else
        printf '  %-34s pass        (%ss)\n' "$stem" "$elapsed"
        pass=$((pass+1))
    fi
done

echo
echo "chipset: $pass passed, $fail failed, $skip did not build"
[ $fail -eq 0 ] && [ $skip -eq 0 ]
