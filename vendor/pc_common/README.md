# pc_common: EGA core shared by the PC cores

A pinned copy of the machine-independent EGA video core of the PCXT-EGA and
PCAT-286 cores, plus the frontends that put its
video memory in SDRAM. It is vendored: the files here are the files of one
snapshot, listed with their SHA-256 in `PINNED`, and `scripts/check_pc_common.sh`
fails if the tree and `PINNED` disagree.

**This copy is strictly an EGA.** The VGA extension of the original library (mode
13h, Mode X/unchained, the 12h and planar 0Dh private renderers, the 256-entry DAC
and its ports, the 3CDh mode port and the VGA-only register readbacks) was removed
from the project; what is left is what an IBM EGA does: modes 0-7, 0Dh, 0Eh, 0Fh
and 10h, the 64-colour attribute palette, pel panning, line compare, the 5151,
5153 and 5154 monitor profiles, both dot clocks, the scandoubler and the 350-line
capture/readout. Because of that this directory is a **fork**: it can no longer be
re-synced with PCAT-286, whose `ega_top` still carries the VGA ports.

## Where it comes from

| Source | Commit | What was taken |
|---|---|---|
| PCXT-EGA_MiSTer (MiSTer-devel) | `c6b4dc8` (2026-09-04) | the EGA core, the XT behaviour, the benches |
| PCAT-286_MiSTer (MiSTer-devel) | `c10f4ab` (2026-10-18, Release 20261810) | `ega_top` and the EGA files it corrected afterwards |

Reconciliation rule: the newest behaviour wins. Where the two files were
identical nothing was decided; where they differed the PCAT-286 file was taken for
the shared core and the PCXT-EGA one for what is XT bus business (which stays in the
core, not here). After that the VGA parts were
taken out: the EGA here is a strict IBM EGA.

What is **not** here, on purpose:

* the boot splash of either core (`ega_splash_renderer`, `vga_splash_*`): the
  core draws it and feeds the pixel through the `ext_splash_*` ports of `ega_top`;
* the 25.2 MHz VGA dot clock and its run-time clock mux (`vga_video_clock_mux`);
* the CPU-bus coupling (`vga_a000_cpu_frontend`, `ega_io_stretch`, XTEGACTL): that
  is the host machine's.

## Layout

```
rtl/ega/   CRTC (UM6845R), sequencer, graphics controller, attribute controller,
           text and pixel pipelines, monitor profiles, switch sense, fb15k capture
           and readout, scandoubler; ega_top is the core
rtl/mem/   ega_vram_sdram_frontend (video memory in SDRAM), vram_fetch_x (clock
           crossing of the F2 vram_fetch engine), pc_token_delay;
           ega_vram_bram_frontend is the BRAM backend and the benches' reference
rtl/pc_common.qip, rtl/pc_common_bram.qip   file lists for Quartus
TESTBENCH/ benches and run_tests.sh; ref_rtl/ is the core as it was before
           the SDRAM retiming, renamed ref_*, the oracle of ega_sdram_equiv_tb
PINNED     origin and SHA-256 of every file
```

`vendor/pc_common` needs three modules of the core's own memory subsystem
(`rtl/mem` of the host project): `vram_fetch`, `vid_mux` (the F2 engine and its
port mux) and the `sdram_pkg`
package they import. The library speaks the `sdram_port` protocol at the edges
and knows nothing else of the memory system.

## SDRAM retiming

The core reads the planes ahead of the display and the answer comes at a fixed,
longer latency. `ega_top` has one parameter that retimes the display side to match
(0 gives the BRAM behaviour):

* `SDRAM_LEAD_DOTS`   dots of extra latency on the EGA path (text, graphics)

It has to equal the matching parameters of `ega_vram_sdram_frontend`
(`LEAD_GFX`; `LEAD_CELL + LEAD_GLYPH - 3`). The whole picture, sync pulses
included, moves later by exactly that much and nothing else changes:
`TESTBENCH/ega_sdram_equiv_tb.sv` compares the two systems sample by sample.

Two engines (`vram_fetch` instances) serve the frontend: the main one (cells and
graphics; `MAIN_DEPTH` entries) and one for the glyph rows of text, whose address
depends on the cell. The delay lines (`pc_token_delay`, the output pipes of
`ega_top`) are registers on purpose (`AUTO_SHIFT_REGISTER_RECOGNITION OFF`): a
recognised shift register of a few dozen bits would take a whole M10K block each.

## Tests

```
TESTBENCH/run_tests.sh            every bench (Icarus); -v for Verilator
TESTBENCH/run_tests.sh equiv      the BRAM against SDRAM equivalence bench (Verilator)
```

A bench marked `// NEEDS: engine` also gets the F2 engine, the BRAM reference
(`ref_rtl/`) and the behavioural SDRAM port, and always runs under Verilator; one
marked `// NEEDS: icarus` always runs under Icarus (a construct Verilator 5.020
rejects or races on, also in the PCAT-286 original). The same equivalence bench
runs on the real arbiter, controller and chip model from the host project
(`rtl/mem/TESTBENCH/run_ega_system.sh`).
