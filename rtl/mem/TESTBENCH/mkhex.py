#!/usr/bin/env python3
"""Turn a flat binary into a $readmemh file of 16-bit words (little endian),
skipping the zero runs: `@address` lines (in words) and one word per line."""
import sys

data = open(sys.argv[1], "rb").read()
if len(data) % 2:
    data += b"\0"
words = [data[i] | (data[i + 1] << 8) for i in range(0, len(data), 2)]
out = []
prev = None
for i, w in enumerate(words):
    if w == 0:
        continue
    if prev is None or i != prev + 1:
        out.append("@%X" % i)
    out.append("%04X" % w)
    prev = i
open(sys.argv[2], "w").write("\n".join(out) + "\n")
