# EGA Palette Indirection Audit

This audit covers EGA-501 against `SPEC.md` sections 4.4 and 8, using
`rtl/video/ega_attrib_ctrl.v`, `rtl/video/ega_vgaport.v`, and
`rtl/video/ega_top.v`.

## Attribute Palette Path

`ega_attrib_ctrl.v` stores Attribute Controller palette registers `00h..0Fh`
in `raw_palette[0:15]`. During active pixels:

1. The 4-bit planar pixel index from `ega_pixel.v` is masked by Attribute
   Controller Plane Enable register `12h[3:0]`.
2. The masked index selects one of the 16 `raw_palette` entries.
3. The selected palette entry bits `5:0` become `color_out`.

This means a CPU-visible plane color index can be remapped to a different EGA
digital color without changing VRAM plane data, which is the base EGA palette
indirection required by EGA-501.

## Misc Output Palette Width

`ega_top.v` connects Misc Output bit `7` to both palette consumers:

- `ega_attrib_ctrl.palette_64_mode`
- `ega_vgaport.palette_64_mode`

The attribute controller uses this bit for overscan width:

- `0`: overscan uses `{2'b00, overscan_reg[3:0]}`.
- `1`: overscan uses `overscan_reg[5:0]`.

Active pixels always use the 6-bit value stored in the selected Attribute
Controller palette register. The downstream RGB conversion chooses 16-color or
64-color interpretation from the same Misc Output bit.

## RGB Conversion

`ega_vgaport.v` implements the base EGA digital palette conversion:

| Mode | Source bits | Behavior |
| --- | --- | --- |
| 64-color | `color[2:0]` plus secondary intensity bits `color[5:3]` | Produces two-level-per-channel EGA RGB: primary contribution `42`, secondary contribution `21`. |
| 16-color | `color[2:0]` plus shared intensity bit `color[4]` | Produces IBM 16-color RGB with shared intensity. |
| 16-color brown fix | `(color & 6'h17) == 6'h06` | Converts low-intensity yellow to brown. |

Attribute Controller Color Select register `14h` is stored and read back, but
does not alter base IBM EGA RGB mapping. This matches `SPEC.md` section 4.1 and
the x86Box base EGA path.

## Deterministic Test Sequence For EGA-507

An executable palette/status testbench should cover:

1. Reset and verify palette entries `00h..0Fh` map identity values.
2. Program palette entry `02h` to a distinct value such as `06h`; feed planar
   pixel index `2`; verify RGB follows the programmed palette entry, not the
   raw plane index.
3. Program palette entry `02h` to a 64-color-only value such as `21h`; toggle
   Misc Output bit `7`; verify RGB changes between 16-color and 64-color
   interpretation.
4. Program overscan register `11h` with values that differ in bits `5:4`;
   verify border RGB ignores those bits when Misc Output bit `7` is clear and
   uses them when it is set.
5. Write and read Color Select register `14h`; verify active pixel RGB is
   unchanged on base IBM EGA behavior.
6. Program Plane Enable register `12h`; verify disabled plane bits are masked
   before palette lookup.

## Remaining Gaps

- No executable palette testbench can be run on this machine until a standalone
  HDL simulator is installed; see `TEST_TOOLS.md`.
- Overscan dimensions and border placement are separate scanout tasks; this
  audit only covers the overscan color value.
