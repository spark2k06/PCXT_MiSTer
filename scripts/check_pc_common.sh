#!/usr/bin/env bash
#
# CI check: vendor/pc_common has to be exactly the snapshot named in
# vendor/pc_common/PINNED. Fails on a file that changed, one that went missing and
# one that is not in the list. Hashes are over the LF form of the file, so a
# checkout with CRLF conversion does not matter.
#
#   scripts/check_pc_common.sh
#
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$ROOT/vendor/pc_common"
PINNED="$LIB/PINNED"
[ -f "$PINNED" ] || { echo "no $PINNED"; exit 2; }

hash_file() { tr -d '\r' < "$1" | sha256sum | cut -d' ' -f1; }

fail=0
declare -A listed
while read -r tag sum path; do
    [ "$tag" = "sha256" ] || continue
    listed[$path]=1
    if [ ! -f "$LIB/$path" ]; then echo "MISSING  $path"; fail=1; continue; fi
    got=$(hash_file "$LIB/$path")
    if [ "$got" != "$sum" ]; then echo "CHANGED  $path"; fail=1; fi
done < "$PINNED"

while IFS= read -r f; do
    rel=${f#"$LIB/"}
    [ "$rel" = "PINNED" ] && continue
    if [ -z "${listed[$rel]:-}" ]; then echo "EXTRA    $rel"; fail=1; fi
done < <(find "$LIB" -type f | sort)

if [ $fail -eq 0 ]; then echo "pc_common: tree matches PINNED ($(grep -c '^sha256' "$PINNED") files)"; fi
exit $fail
