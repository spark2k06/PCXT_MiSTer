#!/usr/bin/env bash
#
# Compile build profiles with Quartus 17.0.2 (Docker image raetro/quartus:17.0)
# and print a table of ALM, M10K and the worst slack of the four timing corners.
#
#   scripts/build_profiles.sh                 every profile in profiles/
#   scripts/build_profiles.sh mister_pcjr ... only the ones named
#
# Each profile is compiled in its own copy of the tree under $WORK (default
# ~/pcxt_build), up to $JOBS at a time (default 3), and keeps its output there:
# $WORK/<profile>/output_files/PCXT.rbf. The fitter seed comes from the
# profile itself (profiles/<profile>.tcl), so nothing is edited in PCXT.qsf.
#
# SKIP_BUILD=1 only prints the table of what is already in $WORK.
#
# A profile passes when every setup and hold slack, in the four corners, is
# not negative. The script exits 1 if one fails or does not compile.
#
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-$HOME/pcxt_build}
JOBS=${JOBS:-3}
IMAGE=${QUARTUS_IMAGE:-raetro/quartus:17.0}

if [ $# -gt 0 ]; then
    PROFILES=("$@")
else
    PROFILES=()
    for f in "$ROOT"/profiles/*.tcl; do PROFILES+=("$(basename "$f" .tcl)"); done
fi

build() {
    local p=$1 dir=$WORK/$1
    docker run --rm -v "$WORK":/w alpine rm -rf "/w/$p" > /dev/null 2>&1
    mkdir -p "$dir"
    (cd "$ROOT" && tar --exclude=.git --exclude=db --exclude=output_files \
        --exclude=incremental_db --exclude='*.rbf' -cf - .) | tar -xf - -C "$dir"
    local s=$SECONDS
    docker run --rm -e PCXT_PROFILE="$p" -v "$dir":/build -w /build "$IMAGE" \
        quartus_sh --flow compile PCXT > "$dir/build.log" 2>&1
    echo "EXIT=$? ELAPSED=$((SECONDS - s))" >> "$dir/build.log"
}

mkdir -p "$WORK"
running=0
for p in "${PROFILES[@]}"; do
    [ "${SKIP_BUILD:-0}" = 1 ] && continue
    build "$p" &
    running=$((running + 1))
    if [ "$running" -ge "$JOBS" ]; then wait -n; running=$((running - 1)); fi
    sleep 20   # stagger the starts so the copies do not fight for the disk
done
wait

printf '\n%-22s %-16s %-6s %-8s %-8s %-8s %-8s %s\n' \
    profile ALM M10K S100C S-40C Hold seed result
status=0
for p in "${PROFILES[@]}"; do
    dir=$WORK/$p
    sta=$dir/output_files/PCXT.sta.summary
    fit=$dir/output_files/PCXT.fit.summary
    if ! grep -q 'EXIT=0' "$dir/build.log" || [ ! -f "$sta" ]; then
        printf '%-22s did not compile (see %s/build.log)\n' "$p" "$dir"; status=1; continue
    fi
    alm=$(sed -n 's/^Logic utilization (in ALMs) : //p' "$fit" | sed 's/ \/ [0-9,]* ( */ (/; s/ *)/)/')
    m10k=$(sed -n 's/^Total RAM Blocks : //p' "$fit" | sed 's/ \/ .*//')
    seed=$(sed -n 's/^set_global_assignment -name SEED //p' "$ROOT/profiles/$p.tcl" | tail -n 1)
    read -r s100 s40 hold < <(awk '
        /^Type/ { c = $3 "_" $5 "_" $7 }
        /^Slack/ { v = $3 + 0; if (!(c in m) || v < m[c]) m[c] = v }
        END {
            h = 1e9
            for (k in m) if (k ~ /Hold/ && m[k] < h) h = m[k]
            print m["Slow_100C_Setup"], m["Slow_-40C_Setup"], h
        }' "$sta")
    ok=PASS
    for v in $s100 $s40 $hold; do
        awk -v x="$v" 'BEGIN { exit !(x < 0) }' && ok=FAIL
    done
    # the fast corners have a large setup margin, but a negative one still fails
    awk '/^Type/ { c = $3 } /^Slack/ { if (c == "Fast" && $3 + 0 < 0) bad = 1 } END { exit !bad }' "$sta" && ok=FAIL
    [ "$ok" = PASS ] || status=1
    printf '%-22s %-16s %-6s %-8s %-8s %-8s %-8s %s\n' \
        "$p" "$alm" "$m10k" "$s100" "$s40" "$hold" "${seed:-5}" "$ok"
done
exit $status
