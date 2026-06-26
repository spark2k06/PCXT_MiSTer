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
