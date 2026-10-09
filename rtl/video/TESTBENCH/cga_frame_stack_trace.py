#!/usr/bin/env python3
"""Stimulus and checker for cga_frame_stack_tb.sv (CRTC Frame Stacking).

The reference program is the end credits of the Area 5150 demo ("Lake"),
which starts one CRTC frame per scanline.  The input is GloriousCow's IBM
5150 bus capture of it:
  https://github.com/dbalsom/marty_tools
  bus_sniffer/captures/area5150/area5150_lake_effect_01.csv.gz
Each row of that capture is one 4.77 MHz CPU cycle.  The capture misses A19,
so CGA memory at B8000h appears at 38000h.

  stim   Replays the CGA register writes of the capture as a timed write list
         for the bench (6 bench clocks per CPU cycle), optionally with the
         per-line code stretched and jittered to model a CPU that is not
         cycle-exact.  It also writes the VRAM contents and the expected
         200-line picture as the real CGA shows it.
  check  Turns the bench's raster dump into PNG files and compares the
         reconstructed frames with the expected picture.

Nothing derived from the demo is stored in the repository; run 'stim' on a
local copy of the capture.
"""
import argparse
import csv
import gzip
import random
import struct
import sys
import zlib

CYCLE_CLKS = 6          # 28.636 MHz bench clock / 4.77 MHz CPU clock
FRAME_CYCLES = 79648    # 262 lines x 912 hdots / 3 hdots per CPU cycle
MODE_SET_N = 342800     # just before CREDITS.COM programs its CGA mode
FIRST_FRAME_N = 536313  # scanline holding the first effect setup write
LOOP_FRAME_N = 615961   # first frame whose reflection table is complete
SNAP_N = 695609         # VRAM snapshot used for the expected picture

PAL = [(0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170),
       (170, 0, 0), (170, 0, 170), (170, 85, 0), (170, 170, 170),
       (85, 85, 85), (85, 85, 255), (85, 255, 85), (85, 255, 255),
       (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255)]


def write_png(path, rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)
        for p in row:
            raw += bytes(PAL[p] if isinstance(p, int) else p)

    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', len(rows[0]), len(rows), 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


def read_trace(path):
    """Return (CGA I/O writes, VRAM snapshot at SNAP_N) from the capture."""
    writes = []
    vram = bytearray(16384)
    snap = None
    cur = None
    with gzip.open(path, 'rt', newline='') as f:
        r = csv.reader(f)
        hdr = next(r)
        ix = {h: i for i, h in enumerate(hdr)}
        for row in r:
            n = int(float(row[ix['N']]))
            if snap is None and n >= SNAP_N:
                snap = bytes(vram)
            if row[ix['ALE']] == 'A':
                cur = (row[ix['BUSL']], int(row[ix['AL']].strip("'"), 16), n)
            if row[ix['T']] == 'T4' and cur:
                d = row[ix['D']].strip("'")
                if d:
                    kind, a, n0 = cur
                    if kind == 'IOW' and (a & 0xFFFF) in (0x3D4, 0x3D5, 0x3D8, 0x3D9):
                        writes.append((n0, a & 0xFFFF, int(d, 16)))
                    elif kind == 'MEMW' and 0x38000 <= a < 0x3C000:
                        vram[a - 0x38000] = int(d, 16)
                cur = None
    return writes, snap if snap is not None else bytes(vram)


def frame_addresses(writes, start, end):
    """Start addresses in the order the Lake code writes them in one frame."""
    regs = [0] * 18
    idx = 0
    addrs = None
    for n, port, d in writes:
        if port == 0x3D4:
            idx = d & 31
            continue
        if port != 0x3D5:
            continue
        if idx < 18:
            regs[idx] = d
        if not start <= n < end:
            continue
        if idx == 4 and d <= 1 and regs[9] == 0:
            addrs = [((regs[12] & 63) << 8) | regs[13]]
        elif idx == 4 and d > 1:
            if addrs:
                return addrs
        elif idx == 13 and addrs is not None:
            addrs.append(((regs[12] & 63) << 8) | regs[13])
    return addrs


def expected_picture(vram, font, addrs):
    """200 lines x 640 pixels: line i shows A(i)+1 .. A(i)+80, glyph row 0."""
    rows = []
    for i in range(200):
        row = []
        for c in range(80):
            ma = (addrs[i] + 1 + c) & 0x1FFF
            ch, at = vram[ma * 2], vram[ma * 2 + 1]
            bits = font[ch * 8]
            row += [(at & 15) if (bits >> (7 - b)) & 1 else (at >> 4) for b in range(8)]
        rows.append(row)
    return rows


def load_font(path):
    vals = [int(x, 16) for x in open(path).read().split()]
    return vals[2048:4096]  # the normal (thick) IBM CGA font


def cmd_stim(a):
    writes, vram = read_trace(a.trace)
    rnd = random.Random(a.seed)
    out = []
    base = a.offset
    # Up to the first effect frame: the capture as-is.
    for n, port, d in writes:
        if MODE_SET_N <= n < FIRST_FRAME_N:
            out.append((n - MODE_SET_N + base, port, d))
    # Effect frames start on the PIT period; the code inside each frame can be
    # slower or faster than the real 304 cycles per scanline and jittery.  On
    # a 5150 the effect's interrupt handler returns only about 400 cycles
    # before the next PIT interrupt, so slower code also stretches the frame:
    # --overrun spaces the frames by the stretched handler instead.
    period = FRAME_CYCLES
    if a.overrun:
        period = max(FRAME_CYCLES, int((FRAME_CYCLES - 400) * a.scale))
    first = [(n - FIRST_FRAME_N, p, d) for n, p, d in writes
             if FIRST_FRAME_N <= n < FIRST_FRAME_N + FRAME_CYCLES]
    loop = [(n - LOOP_FRAME_N, p, d) for n, p, d in writes
            if LOOP_FRAME_N <= n < LOOP_FRAME_N + FRAME_CYCLES]
    t0 = FIRST_FRAME_N - MODE_SET_N + base
    frames = [first] + [loop] * a.loops
    for k, ev in enumerate(frames):
        fbase = t0 + k * period + a.latency + rnd.randint(-a.frame_jitter, a.frame_jitter)
        for rel, p, d in ev:
            t = fbase + int(rel * a.scale) + rnd.randint(-a.jitter, a.jitter)
            out.append((t, p, d))
    # Leave the effect: BIOS 80x25 colour text, then let the raster run.
    t = t0 + len(frames) * period
    for r, v in enumerate([113, 80, 90, 10, 31, 6, 25, 28, 2, 7, 6, 7, 0, 0]):
        out.append((t, 0x3D4, r))
        out.append((t + 5, 0x3D5, v))
        t += 30
    end = t + a.tail * FRAME_CYCLES
    # Keep the order and leave room for a whole bus cycle between writes.
    last = -10
    with open(a.out + '.stim', 'w') as f:
        for t, p, d in out:
            t = max(t, last + 5)
            last = t
            f.write(f"{t * CYCLE_CLKS} {p:03x} {d:02x}\n")
        f.write(f"{end * CYCLE_CLKS} 000 00\n")
    with open(a.out + '.vram.hex', 'w') as f:
        for b in vram:
            f.write(f"{b:02x}\n")
    addrs = frame_addresses(writes, LOOP_FRAME_N, LOOP_FRAME_N + FRAME_CYCLES)
    pic = expected_picture(vram, load_font(a.font), addrs)
    with open(a.out + '.expected', 'w') as f:
        for row in pic:
            f.write(''.join('%x' % p for p in row) + '\n')
    write_png(a.out + '.expected.png', pic)
    print(f"{len(out)} writes, {len(frames)} effect frames of {period} cycles, end at cycle {end}")


def read_dump(path):
    """Frames from the bench dump: lists of (vblank, pixel string) lines."""
    frames, cur = [], []
    for line in open(path):
        line = line.rstrip('\n')
        if line == 'F':
            if cur:
                frames.append(cur)
            cur = []
        elif line:
            cur.append((line[0] == 'V', line[1:]))
    if cur:
        frames.append(cur)
    return frames


def cmd_check(a):
    expected = [l.strip() for l in open(a.expected)]
    frames = read_dump(a.dump)
    probe = 60  # a distinctive line of the picture
    good = []
    for fi, fr in enumerate(frames):
        if a.png and fi in a.png:
            rows = [[int(c, 16) for c in px[:912].ljust(912, '0')] for _, px in fr]
            if rows:
                write_png(f"{a.dump}.f{fi}.png", rows)
        hit = None
        for y, (_, px) in enumerate(fr):
            x = px.find(expected[probe])
            if x >= 0:
                hit = (y - probe, x)
                break
        if hit is None:
            print(f"frame {fi}: {len(fr)} lines, picture not found")
            continue
        y0, x0 = hit
        bad = sum(1 for i in range(200)
                  if not (0 <= y0 + i < len(fr)) or fr[y0 + i][1][x0:x0 + 640] != expected[i])
        # Outside the picture the area may hold only the border colour, or
        # black during blanking.
        above = fr[y0 - 1][1] if y0 > 0 else ''
        blank = (above[x0] if x0 < len(above) else '') + '0'
        extra = sum(1 for y, (_, px) in enumerate(fr)
                    if not y0 <= y < y0 + 200 and px[x0:x0 + 640].strip(blank))
        print(f"frame {fi}: {len(fr)} lines, picture at line {y0} pixel {x0}, "
              f"{200 - bad}/200 lines match, {extra} stray lines")
        if bad == 0 and extra == 0 and len(fr) == 262:
            good.append(fi)
    print('matching frames:', good)
    if a.require and len(good) < a.require:
        sys.exit(1)


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('stim')
    s.add_argument('trace')
    s.add_argument('out', help='output prefix')
    s.add_argument('--font', required=True, help='rtl/video/cga.hex')
    s.add_argument('--loops', type=int, default=6)
    s.add_argument('--tail', type=int, default=6, help='frames after the effect')
    s.add_argument('--scale', type=float, default=1.0, help='stretch of the effect code')
    s.add_argument('--jitter', type=int, default=0, help='+/- CPU cycles per write')
    s.add_argument('--latency', type=int, default=0, help='extra ISR latency, cycles')
    s.add_argument('--frame-jitter', type=int, default=0, help='+/- ISR latency per frame')
    s.add_argument('--overrun', action='store_true',
                   help='frames last as long as the stretched handler (no PIT lock)')
    s.add_argument('--offset', type=int, default=0, help='start offset, cycles')
    s.add_argument('--seed', type=int, default=1)
    c = sub.add_parser('check')
    c.add_argument('dump')
    c.add_argument('expected')
    c.add_argument('--png', type=int, nargs='*', help='frames to save as PNG')
    c.add_argument('--require', type=int, default=0, help='minimum matching frames')
    a = p.parse_args()
    {'stim': cmd_stim, 'check': cmd_check}[a.cmd](a)


if __name__ == '__main__':
    main()
