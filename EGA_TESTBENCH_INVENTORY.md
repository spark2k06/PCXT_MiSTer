# EGA Testbench Coverage Inventory

## Scope

This inventory maps the existing deterministic EGA testbenches to the
verification-expansion tasks EGA-802 through EGA-805.

Reviewed files:

- `rtl/KFPC-XT/TESTBENCH/ega_registers_tb.sv`
- `rtl/KFPC-XT/TESTBENCH/ega_pixel_tb.sv`
- `rtl/KFPC-XT/TESTBENCH/ega_text_tb.sv`

No standalone HDL simulator from `TEST_TOOLS.md` is installed in this
environment, so this inventory is a static coverage review. Quartus Analysis &
Elaboration was already run for the integrated RTL during the EGA-704 work.

## EGA-802: Register Testbench

`ega_registers_tb.sv` exists and instantiates register-level DUTs plus a
top-level `ega_top` instance. It provides reusable `begin_test`, `expect8`,
`expect16`, `expect1`, and `expect_true` diagnostics.

Covered behavior includes:

- Sequencer reset defaults, indexed write/readback, map mask, character map
  select, chain-2, and extended-memory outputs.
- Graphics Controller reset defaults, indexed write/readback, write/read mode,
  chain-2 read, memory map, and odd/even outputs.
- Attribute Controller flip-flop behavior, indexed write/readback, palette,
  mode-control bits, blink, line graphics, horizontal panning, overscan,
  plane-enable masking, display-enable gating, and video-disable behavior.
- CRTC protected writes, overflow fields, row advance, start-address latching,
  split reset behavior, and sampled blanking outputs.
- Top-level Misc Output, color/mono CRTC selection, selected status read side
  effects, Attribute Controller flip-flop reset, status bit toggles, and
  blanking/retrace status bits.

This satisfies the EGA-802 requirement that register behavior can be tested
without launching the full chipset.

## EGA-803: CRTC Address Testbench

There is no separate `ega_crtc_addr_tb.sv` file. The current equivalent
coverage lives in `ega_registers_tb.sv`.

The existing CRTC coverage includes:

- `expected_scanout_addr` reference logic for byte, word, dword, MA13/MA15,
  and scanline substitution address modes.
- `expect_crtc_scanout` checks for scanout remapping.
- Overflow and vertical timing formulas.
- Row advance and maximum-scan-line behavior.
- Start-address frame latching.
- Split-screen address and scanline reset behavior.
- Sampled fetch address, row address, horizontal counter, vertical counter,
  display-enable, hblank, and vblank behavior.

This satisfies the EGA-803 requirement through an equivalent testbench rather
than a dedicated file.

## EGA-804: Pixel Testbench

`ega_pixel_tb.sv` exists and provides deterministic checks for graphics pixel
generation and Attribute Controller color output.

Covered behavior includes:

- Planar pixel assembly from four bitplanes.
- Low-resolution repeated pixels.
- Graphics horizontal panning.
- Text handoff versus planar graphics versus CGA-compatible graphics mode
  selection.
- CGA-compatible 2bpp routing.
- Display-disable and active-pixel blanking.
- Attribute palette remapping and plane-enable effects.

This satisfies the EGA-804 requirement that pixel output regressions are
cycle-deterministic.

## EGA-805: Text Testbench

`ega_text_tb.sv` exists and provides deterministic checks for text fetch,
font, attribute, cursor, panning, and monochrome behavior.

Covered behavior includes:

- 80-column and 40-column cell fetch cadence.
- Character Map Select font-bank addressing.
- Glyph foreground/background selection.
- Background intensity when blink is disabled.
- Blink hiding foreground pixels.
- 9-dot line-graphics repeat and non-line blanking behavior.
- Cursor foreground/background swap.
- MDA-style monochrome attribute mapping.
- Mono blink and underline behavior.
- Text horizontal panning without changing cell fetch addresses.

This satisfies the EGA-805 requirement that text renderer behavior is testable
without full system boot.

## Result

EGA-802, EGA-803, EGA-804, and EGA-805 are covered by existing deterministic
testbench sources. The remaining gap is execution: this environment lacks a
standalone HDL simulator, so these are recorded as static coverage-complete
tasks rather than freshly executed simulations.

## ECC-003 Baseline Execution Snapshot

Updated on 2026-07-03 for the clean-core baseline. `iverilog` and `vvp` are now
available in `PATH`:

```text
Icarus Verilog version 12.0 (devel) (s20150603-1539-g2693dd32b)
Icarus Verilog runtime version 12.0 (devel) (s20150603-1539-g2693dd32b)
```

Passing focused tests:

```powershell
iverilog -g2012 -I rtl/video -o $env:TEMP\ega_pixel_tb.vvp rtl/KFPC-XT/TESTBENCH/ega_pixel_tb.sv rtl/video/ega_pixel.v rtl/video/ega_attrib_ctrl.v
vvp $env:TEMP\ega_pixel_tb.vvp
```

Result: `PASS ega_pixel_tb`.

```powershell
iverilog -g2012 -I rtl/video -o $env:TEMP\ega_crtc_vertical_tb.vvp rtl/KFPC-XT/TESTBENCH/ega_crtc_vertical_tb.sv rtl/video/UM6845R.v
vvp $env:TEMP\ega_crtc_vertical_tb.vvp
```

Result: `PASS: ega_crtc_vertical_tb`.

Known baseline failures or blockers:

```powershell
iverilog -g2012 -I rtl/video -o $env:TEMP\ega_text_tb.vvp rtl/KFPC-XT/TESTBENCH/ega_text_tb.sv rtl/video/ega_text.v
vvp $env:TEMP\ega_text_tb.vvp
```

Result: fails because `rtl/video/ega_text.v` calls `$readmemh("cga.hex", ...)`
and no `cga.hex` file is present in the repository. The failing check is
`splash font fallback uses CGA ROM glyphs`, with `expected e got X`.

```powershell
iverilog -g2012 -I rtl/video -o $env:TEMP\ega_vram_tb.vvp rtl/video/ega_vram.v rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv
vvp $env:TEMP\ega_vram_tb.vvp
```

Result: executes but fails with `ega_vram_tb FAILED with 14 mismatches`.
The first failing group is `write modes 0 and 2`; observed examples include
`write mode0 plane0 expected=3c actual=12` and
`write mode2 plane1 expected=f0 actual=34`.

```powershell
iverilog -g2012 -I rtl/video -o $env:TEMP\ega_vram_b8000_tb.vvp rtl/KFPC-XT/TESTBENCH/ega_vram_b8000_tb.sv rtl/video/ega_vram.v
vvp $env:TEMP\ega_vram_b8000_tb.vvp
```

Result: passes. This directed check covers the EGA VRAM B8000-BFFFF memory-map
selection plus odd/even page-select remapping for CGA-compatible text aperture
access.

```powershell
iverilog -g2012 -I rtl/video -o $env:TEMP\ega_registers_tb.vvp rtl/KFPC-XT/TESTBENCH/ega_registers_tb.sv rtl/video/ega_sequencer.v rtl/video/ega_gfx_ctrl.v rtl/video/ega_attrib_ctrl.v rtl/video/UM6845R.v rtl/video/ega_top.v rtl/video/ega_vram.v rtl/video/ega_pixel.v rtl/video/ega_text.v rtl/video/ega_vgaport.v rtl/video/video_scandoubler.v rtl/video/cga.v rtl/video/cga_vram.v rtl/video/cga_sequencer.v rtl/video/cga_attrib.v rtl/video/cga_pixel.sv rtl/video/cga_vgaport.v rtl/video/cga_composite.v
vvp $env:TEMP\ega_registers_tb.vvp
```

Result: blocked during Icarus elaboration. The relevant diagnostics are:

```text
rtl/KFPC-XT/TESTBENCH/ega_registers_tb.sv:638: error: automatically allocated variables may not be referenced in procedural force statements.
rtl/KFPC-XT/TESTBENCH/ega_registers_tb.sv:639: error: automatically allocated variables may not be referenced in procedural force statements.
rtl/video/cga_pixel.sv:57: sorry: Assignment to an entire array or to an array slice is not yet supported.
rtl/video/cga_pixel.sv:73: error: video is not a valid l-value in ega_registers_tb.top_dut.cga_passthrough.pixel.
```
