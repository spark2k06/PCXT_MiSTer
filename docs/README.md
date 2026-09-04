# PCXT MiSTer documentation

This directory contains the project-level technical documentation. It follows
the same principle as the core itself: describe the hardware that is actually
present, keep optional paths explicit, and separate emulated PC/XT behaviour
from MiSTer output plumbing.

## Documents

* [`report/CORE_REPORT.html`](report/CORE_REPORT.html) — visual technical report covering architecture, CGA, HGC/MDA, 15 kHz output, memory, OSD and startup.
* [`8086-adaptation.md`](8086-adaptation.md) — source-of-truth notes for the selectable 8088/8086 implementation.
* [`../rtl/common/jtframe_credits.md`](../rtl/common/jtframe_credits.md) — credits asset format and the project integration.
* [`../SW/XTCTL/README.txt`](../SW/XTCTL/README.txt) — legacy XTCTL utility and its runtime overrides.

The root [`README.md`](../README.md) is the user-facing entry point. It includes
quick start, ROM, video, memory, build and repository notes.

## Scope of the technical report

The report documents the current `PCXT.qsf` / `config.tcl` design: IBM PC/XT
compatibility, MCL86/KFPC-XT integration, CGA and HGC/MDA video, composite
colour, HGC/MDA 480i/240p conversion, optional memory and audio features, and
the CGA-only startup splash. It intentionally does not describe hardware that
is not part of this core.
