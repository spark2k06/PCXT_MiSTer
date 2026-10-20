#!/usr/bin/env bash
#
# Run the pc_common testbenches (EGA/VGA core, VRAM frontends).
#
#   ./run_tests.sh                 every bench, Icarus
#   ./run_tests.sh -v              every bench, Verilator
#   ./run_tests.sh cursor          benches whose name matches "cursor"
#   ./run_tests.sh -v -n status    Verilator, niced, name matches "status"
#
# Icarus compiles in seconds, so it wins while iterating on a bench. Verilator
# runs ~15x faster but pays tens of seconds of C++ compilation per bench, so it
# wins for a full pass and for anything that runs over a minute in Icarus.
# The equivalence bench (ega_sdram_equiv_tb, marked "NEEDS: engine") always runs
# with Verilator --binary --timing: it simulates two complete video paths for
# many frames.
#
# The suite is the union of the PCXT-EGA and PCAT-286 video benches, reconciled
# against the shared core (see ../PINNED), plus the benches of the SDRAM path.
# Benches that need an XT-specific module (ega_io_stretch, the splash renderer)
# stay with the core that owns the module.
#
set -uo pipefail

BUILD_DIR=${TB_BUILD:-$HOME/.cache/pc-common-tb}
BACKEND=icarus
NICE=""
JOBS=${TB_JOBS:-4}
FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        -v|--verilator) BACKEND=verilator ;;
        -i|--icarus)    BACKEND=icarus ;;
        -n|--nice)      NICE="nice -n 19" ;;
        -j)             shift; JOBS="$1" ;;
        -h|--help)      sed -n '2,20p' "$0"; exit 0 ;;
        *)              FILTER="$1" ;;
    esac
    shift
done

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
mkdir -p "$BUILD_DIR"

# The package of the library goes first: every frontend imports it.
# video_monochrome_converter is left out on purpose: it assigns whole arrays,
# which Icarus 12 cannot elaborate, and ega_top does not need it.
SOURCES=("rtl/ega/ega_vram_fns_pkg.sv")
for f in rtl/ega/*.v rtl/vga/*.v rtl/mem/*.sv rtl/mem/*.v; do
    [ -f "$f" ] || continue
    case "$f" in *video_monochrome_converter*|*ega_vram_fns_pkg*) continue ;; esac
    SOURCES+=("$f")
done

# The frontends instantiate the F2 engine (vram_fetch, behind vid_mux) and import
# sdram_pkg; those belong to the memory subsystem of the host project, one level
# above the vendor directory. A host that keeps them elsewhere sets ENGINE_DIR.
PROJECT=$(cd "$ROOT/../.." && pwd)
ENGINE_DIR=${ENGINE_DIR:-$PROJECT/rtl/mem}
ENGINE_SOURCES=()
for f in sdram_pkg.sv vram_fetch.sv vid_mux.sv; do
    [ -f "$ENGINE_DIR/$f" ] && ENGINE_SOURCES+=("$ENGINE_DIR/$f")
done

pass=0; fail=0; skip=0

for tb in TESTBENCH/*.v TESTBENCH/*.sv; do
    name=$(basename "$tb"); stem=${name%.*}
    if [ -n "$FILTER" ] && [[ "$stem" != *"$FILTER"* ]]; then continue; fi
    case "$name" in pc_port_model.sv) continue ;; esac     # a model, not a bench

    SRC=("${ENGINE_SOURCES[@]}" "${SOURCES[@]}")
    backend=$BACKEND
    # "NEEDS: engine" benches also need the BRAM reference copy of the core and the
    # behavioural SDRAM port
    if grep -q "^// *NEEDS: engine" "$tb"; then
        SRC+=(TESTBENCH/ref_rtl/*.v TESTBENCH/ref_rtl/*.sv TESTBENCH/pc_port_model.sv)
        backend=verilator
    fi
    # "NEEDS: icarus" benches use a construct Verilator 5.020 does not accept
    if grep -q "^// *NEEDS: icarus" "$tb"; then backend=icarus; fi

    log=$BUILD_DIR/$stem.log

    # The verdict greps the whole log, so truncate it: a run that once failed
    # must not keep reporting that failure after the bench is fixed.
    : > "$log"

    start=$(date +%s)

    if [ "$backend" = verilator ]; then
        # --public-flat-rw keeps hierarchical references alive; the benches read
        # internal signals and one of them forces the blink counter.
        # --binary --timing runs the Verilog benches as they are, no C++ harness.
        $NICE verilator --binary --timing --public-flat-rw -Wno-fatal -Wno-lint -Wno-style -j "$JOBS" \
            --Mdir "$BUILD_DIR/$stem.obj" -o "$stem" --top-module "$stem" \
            "${SRC[@]}" "$tb" > "$log" 2>&1 \
            && $NICE "$BUILD_DIR/$stem.obj/$stem" >> "$log" 2>&1
        rc=$?
    else
        $NICE iverilog -g2012 -s "$stem" -o "$BUILD_DIR/$stem.vvp" "$tb" "${SRC[@]}" > "$log" 2>&1 \
            && $NICE vvp "$BUILD_DIR/$stem.vvp" >> "$log" 2>&1
        rc=$?
    fi

    elapsed=$(( $(date +%s) - start ))

    if [ $rc -ne 0 ] && ! grep -qE 'RESULT|PASS|FAIL' "$log"; then
        printf '  %-34s BUILD FAIL  (%ss)  %s\n' "$stem" "$elapsed" "$log"
        skip=$((skip+1))
    elif grep -qE 'RESULT: FAIL|TIMEOUT|[1-9][0-9]* failed|^FAIL' "$log"; then
        printf '  %-34s FAIL        (%ss)\n' "$stem" "$elapsed"
        grep -E '^FAIL|TIMEOUT' "$log" | head -5 | sed 's/^/      /'
        fail=$((fail+1))
    else
        printf '  %-34s pass        (%ss)\n' "$stem" "$elapsed"
        pass=$((pass+1))
    fi
done

echo
echo "$BACKEND: $pass passed, $fail failed, $skip did not build"
[ $fail -eq 0 ] && [ $skip -eq 0 ]
