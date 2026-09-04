#!/usr/bin/env bash
#
# Run the 8088 core testbenches.
#
#   ./run_tests.sh                 every bench
#   ./run_tests.sh -n              niced, to share the machine with a synthesis
#   ./run_tests.sh adder           benches whose name matches "adder"
#   ./run_tests.sh -w adder        dump a VCD next to the build (Icarus only)
#
# Its sibling in rtl/KFPC-XT covers the chipset. This one covers rtl/8088,
# the MCL86 core.
#
# cpu_8086_speed_tb covers the complete microcoded core with the BIU, 8288,
# READY, RAM, SDRAM model and the real clock-enable generator.
# cpu_8086_timing_tb uses the same complete CPU and clock profiles with an ideal
# memory bus to compare instruction/bus intervals in paired 8088 and 8086 runs;
# its .S workload requires GNU as and objcopy. The remaining benches pin the
# individual pieces this fork has changed against the behaviour they replaced.
#
# The BIU also has a focused whole-module bench: biu_prefetch_tb
# plays the EU on one side and the motherboard on the other, and characterises
# what the BIU puts on the bus. It was written before the 8086 work started
# touching the prefetch queue, so that the queue rework has something to be
# held to other than "the BIOS still boots".
#
set -uo pipefail

BUILD_DIR=${TB_BUILD:-$HOME/.cache/pcxt-8088-tb}
NICE=""
WAVE=""
FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--nice)  NICE="nice -n 19" ;;
        -w|--wave)  WAVE="-DIVERILOG" ;;
        -h|--help)  sed -n '2,18p' "$0"; exit 0 ;;
        *)          FILTER="$1" ;;
    esac
    shift
done

cd "$(dirname "$0")/.." || exit 1
mkdir -p "$BUILD_DIR"
cp mcl86_ucode.mem "$BUILD_DIR/mcl86_ucode.mem"

# Each bench names the sources it needs.
declare -A SOURCES=(
    [mcl86_adder_tb]="mcl86_adder.sv"
    [cpu_type_latch_tb]="cpu_type_latch.sv"
    [mcl86_fake286_flags_tb]="mcl86_eu_core.sv mcl86_ucode.sv mcl86_adder.sv"
    [biu_prefetch_tb]="mcl86_biu_max.sv"
    # Step 4 end-to-end: the BIU's request crosses the actual RAM.sv word
    # path and comes back from the SDRAM model, rather than from the BIU
    # bench's ideal combinational memory.
    [biu_ram_prefetch_tb]="mcl86_biu_max.sv ../KFPC-XT/HDL/RAM.sv ../KFPC-XT/HDL/Ready.sv ../KFPC-XT/HDL/XT_CE_Generator.sv ../KFPC-XT/HDL/KFSDRAM/HDL/KFSDRAM.sv"
    # Full CPU (EU + BIU) executing word traffic at every hardware speed.
    [cpu_8086_speed_tb]="wrappers/i8088.sv mcl86_eu_core.sv mcl86_ucode.sv mcl86_biu_max.sv mcl86_adder.sv ../KFPC-XT/HDL/RAM.sv ../KFPC-XT/HDL/Ready.sv ../KFPC-XT/HDL/XT_CE_Generator.sv ../KFPC-XT/HDL/KF8288/HDL/KF8288.sv ../KFPC-XT/HDL/KFSDRAM/HDL/KFSDRAM.sv"
    # Step 7: full CPU instruction workload and paired 8088/8086 bus accounting.
    [cpu_8086_timing_tb]="wrappers/i8088.sv mcl86_eu_core.sv mcl86_ucode.sv mcl86_biu_max.sv mcl86_adder.sv ../KFPC-XT/HDL/XT_CE_Generator.sv ../KFPC-XT/HDL/KF8288/HDL/KF8288.sv"
)

pass=0; fail=0; skip=0

for stem in $(printf '%s\n' "${!SOURCES[@]}" | sort); do
    if [ -n "$FILTER" ] && [[ "$stem" != *"$FILTER"* ]]; then continue; fi

    tb="TESTBENCH/$stem.sv"
    if [ ! -f "$tb" ]; then
        printf '  %-34s MISSING\n' "$stem"; skip=$((skip+1)); continue
    fi

    log=$BUILD_DIR/$stem.log

    # Every write below appends, and the pass/fail verdict greps the whole
    # file. Without this truncation a run that once failed keeps reporting
    # that failure from cache long after the bench was fixed.
    : > "$log"

    start=$(date +%s)

    if [ "$stem" = cpu_8086_timing_tb ]; then
        as --32 -o "$BUILD_DIR/cpu_8086_timing.o" \
            TESTBENCH/cpu_8086_timing.S > "$log" 2>&1 \
            && objcopy -O binary -j .text \
                "$BUILD_DIR/cpu_8086_timing.o" \
                "$BUILD_DIR/cpu_8086_timing.bin" >> "$log" 2>&1
        if [ $? -ne 0 ]; then
            printf '  %-34s BUILD FAIL  (%ss)  %s\n' "$stem" 0 "$log"
            skip=$((skip+1))
            continue
        fi
    fi

    $NICE iverilog -g2012 $WAVE -o "$BUILD_DIR/$stem.vvp" \
        "$tb" ${SOURCES[$stem]} >> "$log" 2>&1 \
        && (cd "$BUILD_DIR" && $NICE timeout 600 vvp "$BUILD_DIR/$stem.vvp") >> "$log" 2>&1
    rc=$?

    elapsed=$(( $(date +%s) - start ))

    if [ $rc -ne 0 ] && ! grep -qE 'RESULT|PASS|FAIL' "$log"; then
        printf '  %-34s BUILD FAIL  (%ss)  %s\n' "$stem" "$elapsed" "$log"
        skip=$((skip+1))
    elif grep -qE 'RESULT: FAIL|TIMEOUT|^FAIL|[1-9][0-9]* mismatches' "$log"; then
        printf '  %-34s FAIL        (%ss)\n' "$stem" "$elapsed"
        grep -E '^ *FAIL|TIMEOUT|RESULT: FAIL' "$log" | head -20 | sed 's/^/      /'
        fail=$((fail+1))
    else
        printf '  %-34s pass        (%ss)\n' "$stem" "$elapsed"
        pass=$((pass+1))
    fi
done

echo
echo "8088: $pass passed, $fail failed, $skip did not build"
[ $fail -eq 0 ] && [ $skip -eq 0 ]
