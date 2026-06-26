# EGA Graphics Controller Audit

This audit covers EGA-206 against `SPEC.md` section 4.3, using
`rtl/video/ega_gfx_ctrl.v`, `rtl/video/ega_top.v`, `rtl/video/ega_vram.v`, and
`rtl/KFPC-XT/HDL/Peripherals.sv`.

## Register Storage And Readback

`ega_gfx_ctrl.v` decodes:

- `3CEh` / `2CEh` as the Graphics Controller index port.
- `3CFh` / `2CFh` as the Graphics Controller data port.

The index is stored in `gfx_index[3:0]`. Data writes update registers `00h..08h`
and reads from the data port return the selected register:

| Index | Register | Reset | Current behavior |
| --- | --- | --- | --- |
| `00h` | Set/Reset | `00h` | Stored/readable; feeds per-plane CPU write data selection. |
| `01h` | Enable Set/Reset | `00h` | Stored/readable; bits `3:0` export as `enable_set_reset`. |
| `02h` | Color Compare | `00h` | Stored/readable; feeds read mode `1`. |
| `03h` | Data Rotate | `00h` | Stored/readable; bits `2:0` export rotate count, bits `4:3` export ROP. |
| `04h` | Read Map Select | `00h` | Stored/readable; bits `1:0` export read plane select. |
| `05h` | Mode | `00h` | Stored/readable; exports write mode, read mode, chain-2 read, and mode debug. |
| `06h` | Misc | `00h` | Stored/readable; exports odd/even CPU remap and memory-map selection. |
| `07h` | Color Don't Care | `0Fh` | Stored/readable; feeds read mode `1`. |
| `08h` | Bit Mask | `FFh` | Stored/readable; feeds CPU write masking. |

## Exported VRAM Effects

| Output | Source | Downstream evidence |
| --- | --- | --- |
| `write_mode` | Mode bits `1:0` | Connected through `ega_top` and `Peripherals.sv` to `ega_vram.write_mode`; covered by write-mode tests. |
| `read_mode` | Mode bit `3` | Connected to `ega_vram.read_mode`; covered by read-mode tests. |
| `read_plane_sel` | Read Map Select bits `1:0` | Connected to `ega_vram.read_plane_sel`; covered by read mode `0` plane-select tests. |
| `chain2_read` | Mode bit `4` | Connected to `ega_vram.chain2_read`; covered by chain-2 read tests. |
| `set_reset` / `enable_set_reset` | Registers `00h` / `01h` | Connected to `ega_vram`; covered by write mode `0` tests. |
| `rop_select` / `rotate_count` | Data Rotate bits `4:3` / `2:0` | Connected to `ega_vram`; covered by write mode `0` and `2` tests. |
| `color_compare` / `color_dont_care` | Registers `02h` / `07h` | Connected to `ega_vram`; covered by read mode `1` tests. |
| `bit_mask` | Register `08h` | Connected to `ega_vram`; covered by write-mode tests. |
| `odd_even_mode` | Misc bit `1` | Connected to `ega_vram.odd_even_mode`; covered by odd/even remap tests. |
| `mem_map_sel` | Misc bits `3:2` | Exported to `Peripherals.sv` for CPU aperture decode and to `ega_vram` for address masking; covered by memory-map tests. |

## Deterministic Test Sequence For EGA-208

An executable register testbench should cover:

1. Select and read each index `00h..08h` after reset, checking reset values.
2. Write distinct values to each index, then read them back through `3CFh`.
3. Verify `write_mode`, `read_mode`, `read_plane_sel`, `chain2_read`,
   `odd_even_mode`, and `mem_map_sel` outputs follow the programmed bits.
4. Perform one CPU write using set/reset, enable-set/reset, rotate, ROP, and bit
   mask to prove downstream write behavior.
5. Perform one read mode `1` access to prove color compare and color don't care.
6. Change `mem_map_sel` and verify PCXT memory decode selects the expected EGA
   aperture.

## Remaining Gaps

- Graphics Controller Misc bit `0` is stored/readable but not yet consumed by a
  graphics/text renderer selector.
- Graphics Controller Mode bit `5` is stored/readable but not yet consumed by a
  CGA-compatible 2bpp graphics conversion path.
- These scanout/render gaps are covered by EGA-403 and EGA-404 rather than the
  CPU VRAM register-path verification in EGA-206.
