# EGA RGB Mapping Audit

This audit covers EGA-502 against `SPEC.md` section 8, using
`rtl/video/ega_vgaport.v`, `rtl/video/ega_attrib_ctrl.v`, and
`rtl/video/ega_top.v`.

## Conversion Rules

`ega_vgaport.v` receives the 6-bit EGA digital color selected by the Attribute
Controller. It does not inspect VRAM plane indexes directly.

| Misc Output bit `7` | Mapping | Current RTL |
| --- | --- | --- |
| `0` | 16-color mapping for 200-line EGA modes | Uses RGB primary bits `2:0`, shared intensity bit `4`, and the IBM brown exception. |
| `1` | 64-color mapping for high-resolution EGA modes | Uses RGB primary bits `2:0` plus secondary intensity bits `5:3`. |

Both mappings use 6-bit output levels:

- Primary contribution: `42`.
- Secondary/intensity contribution: `21`.
- Full channel level: `63`.

## Standard 16-Color Expectations

Standard 16-color software should program Attribute Controller palette entries
so the visible 4-bit color indexes select these 6-bit EGA color codes:

| Visible index | EGA color code | Expected RGB6 | Notes |
| --- | --- | --- | --- |
| `0` | `00h` | `00,00,00` | Black |
| `1` | `01h` | `00,00,42` | Blue |
| `2` | `02h` | `00,42,00` | Green |
| `3` | `03h` | `00,42,42` | Cyan |
| `4` | `04h` | `42,00,00` | Red |
| `5` | `05h` | `42,00,42` | Magenta |
| `6` | `06h` | `42,21,00` | Brown exception |
| `7` | `07h` | `42,42,42` | Light gray |
| `8` | `10h` | `21,21,21` | Dark gray |
| `9` | `11h` | `21,21,63` | Bright blue |
| `Ah` | `12h` | `21,63,21` | Bright green |
| `Bh` | `13h` | `21,63,63` | Bright cyan |
| `Ch` | `14h` | `63,21,21` | Bright red |
| `Dh` | `15h` | `63,21,63` | Bright magenta |
| `Eh` | `16h` | `63,63,21` | Yellow |
| `Fh` | `17h` | `63,63,63` | White |

The reset identity palette only initializes Attribute Controller entries to
`00h..0Fh`. Standard high-intensity indexes require mode-set software or the
EGA BIOS to program entries `08h..0Fh` to `10h..17h`.

## 64-Color Spot Checks

The 64-color path is formulaic. These spot checks cover all bit groups:

| EGA color code | Expected RGB6 | Covered bits |
| --- | --- | --- |
| `00h` | `00,00,00` | No primary or secondary bits. |
| `07h` | `42,42,42` | Primary RGB bits `2:0`. |
| `38h` | `21,21,21` | Secondary RGB bits `5:3`. |
| `3Fh` | `63,63,63` | Primary plus secondary on all channels. |
| `21h` | `21,00,42` | Red secondary plus blue primary. |
| `12h` | `00,63,00` | Green primary plus green secondary. |

## DAC Stub Independence

Base EGA does not have a VGA RAMDAC. `ega_top.v` decodes `3C7h`, `3C8h`, and
`3C9h` as compatibility stubs and returns `00h` for reads, but those ports do
not feed `ega_vgaport.v` or the Attribute Controller palette. Therefore EGA
RGB output is determined only by:

1. VRAM plane bits selected into a 4-bit pixel index.
2. Attribute Controller Plane Enable masking.
3. Attribute Controller palette registers `00h..0Fh`.
4. Misc Output bit `7` selecting 16-color versus 64-color interpretation.

## Deterministic Test Sequence For EGA-507

An executable RGB mapping test should:

1. Drive each standard 16-color EGA code in the table above with
   `palette_64_mode = 0` and compare RGB6.
2. Drive the 64-color spot checks with `palette_64_mode = 1`.
3. Verify `06h` produces brown in 16-color mode and not the 64-color yellowish
   value.
4. Write/read DAC stub ports `3C7h..3C9h`, then repeat at least one palette
   mapping check to prove DAC stub state cannot affect base EGA RGB.
5. Program an Attribute Controller palette entry to remap one visible index to
   a different EGA color code and verify the RGB output follows the entry.

## Remaining Gaps

- This audit verifies the static RTL mapping. The executable version belongs in
  EGA-507 once a standalone HDL simulator is available.
