# PCXT MiSTer documentation

This directory contains the project-level technical documentation. It follows
the same principle as the core itself: describe the hardware that is actually
present, keep optional paths explicit, and separate emulated PC/XT behaviour
from MiSTer output plumbing.

## Documents

* [`report/CORE_REPORT.html`](report/CORE_REPORT.html) — visual technical report of the whole core: the machines, architecture, CGA/Tandy/PCjr, HGC/MDA and EGA video, 15 kHz output, memory, OSD and startup.
* [`8086-adaptation.md`](8086-adaptation.md) — source-of-truth notes for the selectable 8088/8086 implementation.
* [`../vendor/pc_common/README.md`](../vendor/pc_common/README.md) — the EGA card: origin, SDRAM retiming and benches.
* [`../rtl/common/jtframe_credits.md`](../rtl/common/jtframe_credits.md) — credits asset format and the project integration.
* [`../SW/XTCTL/README.txt`](../SW/XTCTL/README.txt) — legacy XTCTL utility and its runtime overrides.

The root [`README.md`](../README.md) is the user-facing entry point. It includes
quick start, ROM, video, memory, build and repository notes.

## Scope of the technical report

The report documents the unified core: the IBM PC/XT, the Tandy 1000 and the
IBM PCjr, MCL86/KFPC-XT integration, the memory system, CGA/Tandy/PCjr, HGC/MDA
and EGA video, composite colour, 480i/240p conversion, memory and audio
features, and the startup splash. The EGA card has its own notes in
`vendor/pc_common/README.md`.
