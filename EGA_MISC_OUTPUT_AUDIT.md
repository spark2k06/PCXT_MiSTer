# EGA Misc Output Audit

This audit covers EGA-204 against `SPEC.md` sections 4.1, 8, and 10, using
`rtl/video/ega_top.v`, `rtl/video/ega_vgaport.v`, and
`rtl/KFPC-XT/HDL/Peripherals.sv`.

## Register Storage And Readback

`ega_top.v` stores Misc Output in `ega_misc_output_reg`, reset to `63h`.

- Writes to `3C2h` / `2C2h` update the register through `ega_misc_write_cs`.
- Reads from `3CCh` / `2CCh` return `ega_misc_output_reg` through
  `ega_misc_read_cs`.
- The readback path is included in `ega_bus_dir_sel`, so Misc Output readback
  does not depend on `ega_display_sel`.

## Implemented Bit Effects

| Bit | Required role | Current RTL evidence |
| --- | --- | --- |
| `0` | Color/mono I/O select | Drives `ega_color_io_select`, selecting `3D4h/3D5h/3DAh` or `3B4h/3B5h/3BAh`. |
| `1` | RAM enable on some adapters | Stored/readable. Base IBM mapping remains active, matching the current practical core behavior. |
| `2` | Clock select | Stored/readable. No current downstream timing consumer was found. |
| `3` | Switch-sense select | Stored/readable. `3C2h` switch-sense reads are not implemented. |
| `5` | CPU odd/even page select | Exported as `ega_page_select_out` and consumed by `ega_vram_bram_frontend` as `page_select`. |
| `7` | 16-color versus 64-color palette width | Feeds `ega_attrib_ctrl.palette_64_mode` and `ega_vgaport.palette_64_mode`. |

## Memory Decode Visibility

Misc Output bit `5` reaches the VRAM path:

1. `ega_top.v` assigns `ega_page_select_out = ega_misc_output_reg[5]`.
2. `Peripherals.sv` connects this to `ega_page_select_cfg`.
3. `ega_vram_bram_frontend` passes it to `ega_vram.page_select`.
4. `ega_vram` uses it in odd/even CPU address remapping.

The deterministic VRAM tests already cover page-select remapping through
`test_odd_even_page_select()`.

## Port-Selection Visibility

Misc Output bit `0` reaches the CRTC/status decode in `ega_top.v`. EGA-202
verified that color ports are active when bit `0` is set and mono ports are
active when it is clear.

## Palette Width And DAC Stub Interaction

The base EGA palette path is not overridden by DAC state:

- `ega_attrib_ctrl` emits the effective 6-bit EGA color code.
- `ega_vgaport` converts that 6-bit code through either the 16-color or 64-color
  mapping selected by Misc Output bit `7`.
- DAC index/data ports are decoded in `ega_top.v`, return `00h` on reads, and
  do not store state that can override the base EGA palette path.

## Remaining Gaps

- Misc Output bit `2` clock-select timing behavior is not implemented beyond
  storage/readback.
- `3C2h` / `2C2h` switch-sense reads are not implemented; this was also noted
  in `EGA_IO_DECODE_AUDIT.md`.

These gaps should be handled by timing and switch-sense tasks if software
compatibility requires them. They do not block the current memory decode,
page-select, color/mono port selection, or palette-width behavior.
