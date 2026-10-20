#!/usr/bin/env bash
#
# Bring vendor/pc_common to a snapshot of the shared library and write
# PINNED. The library is a directory with the same layout as vendor/pc_common
# (the MiSTer_PC_Common repository, checked out at the tag to pin, or the
# directory this one was made from):
#
#   scripts/sync_pc_common.sh <library dir> [label]
#
# No git submodules: the copy is the source of truth for the core that vendors it,
# PINNED says which snapshot it is, and scripts/check_pc_common.sh keeps it honest.
# Origin lines already in PINNED ("source ...", "version ...") are kept when the
# library directory has no PINNED of its own.
#
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$ROOT/vendor/pc_common"
SRC=${1:?usage: sync_pc_common.sh <library dir> [label]}
LABEL=${2:-}

[ -d "$SRC" ] || { echo "no such directory: $SRC"; exit 2; }
SRC=$(cd "$SRC" && pwd)

if [ "$SRC" != "$LIB" ]; then
    # replace the tree, keeping the old PINNED header for the origin lines
    HEADER=""
    [ -f "$LIB/PINNED" ] && HEADER=$(grep -v '^sha256' "$LIB/PINNED" || true)
    [ -f "$SRC/PINNED" ] && HEADER=$(grep -v '^sha256' "$SRC/PINNED" || true)
    rm -rf "$LIB"
    mkdir -p "$LIB"
    (cd "$SRC" && find . -type f ! -name PINNED -print0 | tar --null -T - -cf -) | tar -xf - -C "$LIB"
else
    HEADER=$(grep -v '^sha256' "$LIB/PINNED" || true)
fi

{
    if [ -n "$LABEL" ]; then
        echo "$HEADER" | grep -v '^version' || true
        echo "version $LABEL"
    else
        echo "$HEADER"
    fi
    (cd "$LIB" && find . -type f ! -name PINNED ! -name PINNED.new | sed 's#^\./##' | LC_ALL=C sort | while read -r f; do
        printf 'sha256 %s %s\n' "$(tr -d '\r' < "$f" | sha256sum | cut -d' ' -f1)" "$f"
    done)
} > "$LIB/PINNED.new"
mv "$LIB/PINNED.new" "$LIB/PINNED"
echo "pc_common: $(grep -c '^sha256' "$LIB/PINNED") files pinned"
