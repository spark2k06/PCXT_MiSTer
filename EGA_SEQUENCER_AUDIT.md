# EGA Sequencer Register Audit

This audit covers EGA-205 against `SPEC.md` section 4.2, using
`rtl/video/ega_sequencer.v`, `rtl/video/ega_top.v`, `rtl/video/ega_vram.v`,
and `rtl/KFPC-XT/HDL/Peripherals.sv`.

## Register Storage And Readback

`ega_sequencer.v` decodes:

- `3C4h` / `2C4h` as the Sequencer index port.
- `3C5h` / `2C5h` as the Sequencer data port.

The index is stored in `seq_index[2:0]`. Data writes update registers `00h..04h`
and reads from the data port return the selected register:

| Index | Register | Reset | Current behavior |
| --- | --- | --- | --- |
| `00h` | Reset | `03h` | Stored/readable. |
| `01h` | Clocking Mode | `08h` | Stored/readable; bit `3` selects fetch phase length and `dot_clock_div2`. |
| `02h` | Map Mask | `0Fh` | Stored/readable; bits `3:0` export as `plane_write_mask`. |
| `03h` | Character Map Select | `00h` | Stored/readable; no text-render consumer yet. |
| `04h` | Memory Mode | `06h` | Stored/readable; exports `chain2_write` and `extended_memory`. |

## Exported Control Signals

| Output | Source | Downstream evidence |
| --- | --- | --- |
| `plane_write_mask` | `map_mask_reg[3:0]` | Exported from `ega_top` as `ega_plane_write_mask_out`, connected in `Peripherals.sv` to `ega_vram_bram_frontend.plane_write_mask`, then to `ega_vram.plane_write_mask`. |
| `chain2_write` | `~memory_mode_reg[2]` | Exported from `ega_top`, connected through `Peripherals.sv` to `ega_vram.chain2_write`, and covered by `test_chain2_read_write()`. |
| `extended_memory` | `memory_mode_reg[1]` | Exported from `ega_top`, connected through `Peripherals.sv` to `ega_vram.extended_memory`, and covered by address-remap tests. |
| `dot_clock_div2` | `clocking_mode_reg[3]` | Used in `ega_top` for low/high resolution timing selection and passed to `ega_pixel`. |
| `ce_crt_fetch` | fetch phase counter | Drives CRTC/fetch pacing in `ega_top`. |
| `ce_cpu_access` | inverse fetch phase pulse | Exported as `ega_cpu_access_slot_out`; currently consumed as a timing hint by the VRAM frontend path. |

## Deterministic Test Sequence For EGA-208

An executable register testbench should cover:

1. Select index `00h`, read `3C5h`, expect reset value `03h`.
2. Select index `01h`, write a value with bit `3` toggled, read it back, and
   verify `dot_clock_div2` follows bit `3`.
3. Select index `02h`, write `05h`, read it back, and verify
   `plane_write_mask == 4'h5`.
4. Select index `03h`, write a non-zero character-map value, read it back.
5. Select index `04h`, write values with bit `1` and bit `2` toggled, read them
   back, and verify `extended_memory` and `chain2_write`.

## Remaining Gaps

- `char_map_reg` has no downstream consumer until text rendering and font-plane
  fetches are implemented.
- The current design exports `ce_cpu_access`, but EGA-110 still has to decide
  whether that signal remains a timing hint, becomes functional arbitration, or
  is removed from the functional path.
