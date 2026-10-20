#!/usr/bin/env bash
#
# Benches of the EGA path that belong to the core and not to the library: the
# XT I/O stretch, the splash against ega_top and the credits overlay.  They use
# the sources of this tree and the PC-common library.
#
#   ./run_ega_tests.sh
#
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
BUILD=${TB_BUILD:-$HOME/.cache/pcxt-ega-core-tb}
mkdir -p "$BUILD"
LIB=$ROOT/vendor/pc_common
VIDTB=$ROOT/rtl/video/TESTBENCH

LIBSRC=("$LIB/rtl/ega/ega_vram_fns_pkg.sv")
for f in "$LIB"/rtl/ega/*.v "$LIB"/rtl/vga/*.v; do
    case "$f" in *video_monochrome_converter*) continue ;; esac
    LIBSRC+=("$f")
done
STRETCH=$ROOT/rtl/KFPC-XT/HDL/ega_io_stretch.sv
SPLASH=$ROOT/rtl/video/ega_splash_renderer.v
CREDITS=$ROOT/rtl/common/jtframe_credits.v

pass=0; fail=0
run() {   # name, bench dir, workdir, sources...
    local name=$1 dir=$2 wd=$3; shift 3
    local log=$BUILD/$name.log
    ( cd "$wd" && iverilog -g2012 -s "$name" -o "$BUILD/$name.vvp" "$dir"/$name.* "$@" && vvp "$BUILD/$name.vvp" ) > "$log" 2>&1
    if grep -qE 'FAIL|TIMEOUT|error' "$log" || ! grep -qE 'PASS|passed|RESULT' "$log"; then
        printf '  %-34s FAIL   %s\n' "$name" "$log"; fail=$((fail+1))
    else
        printf '  %-34s pass\n' "$name"; pass=$((pass+1))
    fi
}

run ega_io_read_ready_tb          "$HERE" "$ROOT" "$STRETCH"
run ega_io_stretch_tb             "$HERE" "$ROOT" "$STRETCH" "${LIBSRC[@]}"
run ega_switch_sense_io_path_tb   "$HERE" "$ROOT" "$STRETCH" "${LIBSRC[@]}"
run ega_splash_timing_tb          "$VIDTB" "$ROOT/rtl/video" "$SPLASH" "${LIBSRC[@]}"
run jtframe_credits_alignment_tb  "$VIDTB" "$ROOT" "$CREDITS"
run jtframe_credits_pause_tb      "$VIDTB" "$ROOT" "$CREDITS"

echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
