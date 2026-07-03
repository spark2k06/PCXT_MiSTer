# EGA-Owned CGA-Compatible Text Audit

Date: 2026-07-03

Scope: ECC-204.

## Ownership Summary

- `ega_text.v` owns text cell cadence, character/attribute latching, font
  address generation, blink, cursor, 9-dot line graphics, mono attributes, and
  horizontal panning.
- `ega_vram_bram_frontend.sv` maps EGA VRAM planes into the text pipeline:
  plane 0 is `text_char`, plane 1 is `text_attr`, and plane 2 is
  `text_glyph`.
- `ega_vram.v` routes text reads through EGA VRAM addresses:
  `text_cell_addr` selects planes 0 and 1 for character and attribute bytes,
  while `text_font_addr` selects plane 2 for the BIOS-loaded glyph byte.
- Splash text writes target EGA VRAM planes 0 and 1. The only non-VRAM text
  source is the pre-BIOS splash fallback font selected by
  `splash_font_enable`.

## Source Evidence

- `rtl/video/ega_text.v`: text input ports are `text_char_in`,
  `text_attr_in`, `text_glyph_in`, and `text_data_valid`; no CGA VRAM or
  `cga_pixel.sv` dependency is used by the text pipeline.
- `rtl/video/ega_text.v`: post-BIOS glyph data uses `text_glyph_in`; the
  internal `splash_char_rom` is selected only when `splash_font_enable` is
  asserted.
- `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`: plane outputs from `ega_vram`
  are assigned directly to `text_char`, `text_attr`, and `text_glyph`.
- `rtl/video/ega_vram.v`: text fetches use EGA plane addresses, with plane 0/1
  addressed by `text_cell_addr` and plane 2 addressed by `text_font_addr`.

## Verification

Command:

```powershell
iverilog -g2012 -I rtl/video -o $env:TEMP\ega_text_tb.vvp rtl/KFPC-XT/TESTBENCH/ega_text_tb.sv rtl/video/ega_text.v; if ($LASTEXITCODE -eq 0) { vvp $env:TEMP\ega_text_tb.vvp }
```

Result:

- The testbench compiles and runs all text checks.
- The non-splash text checks cover 80-column and 40-column cell fetch cadence,
  character map selection, foreground/background attributes, blink, 9-dot line
  graphics, cursor handling, mono attributes, underline, and horizontal
  panning.
- The run fails in the pre-existing splash fallback case because
  `ega_text.v` calls `$readmemh("cga.hex", ...)` and no `cga.hex` asset is
  present in the repository:

```text
ERROR: rtl/video/ega_text.v:54: $readmemh: Unable to open cga.hex for reading.
FAIL [splash font fallback uses CGA ROM glyphs] splash full block glyph selects foreground: expected e got X
FAIL: ega_text_tb failures=1
```

This failure is limited to pre-BIOS splash fallback font loading. It does not
show a dependency on standalone CGA VRAM or `cga_pixel.sv` for BIOS-loaded EGA
text.

## Pending Hardware Smoke

Hardware smoke for reset-stable EGA text and a CGA-compatible text-mode program
remains pending under `ECC-002`.
