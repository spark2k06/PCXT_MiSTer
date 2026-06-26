# EGA Text Renderer Architecture

## Decision

Use a dedicated `rtl/video/ega_text.v` renderer and select its output in
`ega_top.v` when Graphics Controller Misc register `06h[0]` selects text mode.
Keep `ega_pixel.v` as the graphics shifter for planar and CGA-compatible
graphics modes.

This keeps the graphics byte shifter independent from the text cell pipeline,
which needs different VRAM access patterns, font addressing, cursor handling,
and 8/9-dot character timing.

## Module Boundaries

- `ega_top.v`
  - Selects graphics versus text from `ega_graphics_mode`.
  - Feeds CRTC scanout address, row address, horizontal character position,
    display enable, blink state, Character Map Select, Attribute Controller
    mode bits, and fetched text bytes into `ega_text.v`.
  - Routes the selected 4-bit text color index through the existing Attribute
    Controller palette/RGB path.
- `ega_pixel.v`
  - Remains graphics-only after text mode is implemented.
  - Continues to consume planar bytes and emit a 4-bit graphics plane index plus
    `pixel_valid`.
- `ega_text.v`
  - Owns character/attribute/glyph pipeline state.
  - Emits a 4-bit attribute color index and pixel-valid/display-valid state.
  - Implements text foreground/background selection, blink, 8/9-dot character
    timing, and later cursor/mono/underline behavior.
- `ega_vram.v` and `ega_vram_bram_frontend.sv`
  - Provide explicit text scanout fetch results for character byte, attribute
    byte, and font row byte.
  - Preserve the existing CPU-side register/latch/write behavior.

## Text Fetch Model

The text renderer needs three bytes per displayed character cell:

1. Character byte from display memory at `text_addr * 2`.
2. Attribute byte from display memory at `text_addr * 2 + 1`.
3. Glyph row byte from plane 2 at `font_base + character * 20h + scanline`.

`text_addr` comes from the CRTC scanout address path already corrected for EGA
address remapping. `scanline` is the CRTC row address within the character.

The VRAM frontend should expose these as a registered bundle:

```text
text_fetch_en
text_cell_addr
text_scanline
text_font_a_base
text_font_b_base
text_char
text_attr
text_glyph
text_data_valid
```

EGA-602 should decide whether this bundle is produced by a small multi-cycle
read scheduler or by widening the existing CRT-side plane read path. The key
requirement is deterministic latency: `ega_text.v` must know which pixel cycle
receives a valid cell.

## Character Map Select

Sequencer register `03h` selects font banks:

- Character set A: bits `1:0`.
- Character set B: bits `3:2`.

The first implementation can select set A for all characters. EGA-604 must add
the attribute-driven set A/B choice according to the reference behavior, while
keeping the font address formula `bank_base + character * 20h + scanline`.

## Pixel Generation

For each text cell:

- Load the glyph row byte.
- Shift or index bits from bit 7 to bit 0.
- If 9-dot mode is active, emit an additional ninth pixel.
- If Attribute Controller Mode Control `10h[2]` enables line graphics and the
  character is `C0h..DFh`, repeat the 8th glyph bit into the ninth pixel.
  Otherwise blank the ninth pixel.

The emitted 4-bit index is:

- Foreground: attribute bits `3:0` when glyph/cursor pixel is on.
- Background: attribute bits `6:4` plus bit `7` as intensity when blink is
  disabled.
- Background with blink enabled: `{1'b0, attr[6:4]}` and `attr[7]` suppresses
  foreground pixels while blink is active.

The Attribute Controller palette remains the final color indirection point for
both graphics and text. Text mode should reuse the same palette/RGB conversion
path rather than duplicating RGB mapping in `ega_text.v`.

## Timing And Width

The renderer should support both 80-column and 40-column text timing:

- 80-column text consumes one 8/9-dot cell per CRTC character tick.
- 40-column text repeats or stretches cell pixels according to the programmed
  clocking/timing state, not by changing display memory addressing.

Horizontal panning is left to EGA-609. The first text pipeline should expose a
stable place to insert panning at the left edge of the active line.

## Blanking And Border

`ega_text.v` should emit valid active text pixels only while CRTC display enable
is active and Attribute Controller video enable allows output. Border/overscan
and sync-safe blanking remain handled by the existing Attribute Controller and
top-level hblank/vblank/de signals.

## Implementation Order

1. EGA-602: add deterministic text fetch outputs from VRAM/frontend.
2. EGA-603: add `ega_text.v` cell pipeline and top-level text/graphics select.
3. EGA-604: wire Character Map Select into font bank addressing.
4. EGA-605: implement text attribute color generation and blink behavior.
5. EGA-606..EGA-609: add 9th-dot, cursor, mono/underline, and panning details.

