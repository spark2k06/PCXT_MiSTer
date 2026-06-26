# PCXT MiSTer EGA Implementation Specification

This document specifies the practical EGA behavior that should be ported into
the PCXT MiSTer core. The primary source of truth is the local x86Box source
tree under `x86_src`, especially:

- `x86_src/include/86box/vid_ega.h`
- `x86_src/include/86box/vid_ega_render_remap.h`
- `x86_src/video/vid_ega.c`
- `x86_src/video/vid_ega_render.c`
- `x86_src/video/video.c`

The current PCXT implementation lives mainly in:

- `rtl/video/ega_top.v`
- `rtl/video/ega_vram.v`
- `rtl/video/ega_sequencer.v`
- `rtl/video/ega_gfx_ctrl.v`
- `rtl/video/ega_attrib_ctrl.v`
- `rtl/video/ega_pixel.v`
- `rtl/video/ega_vgaport.v`
- `rtl/video/UM6845R.v`
- `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`
- `rtl/KFPC-XT/HDL/Peripherals.sv`
- `egabios.asm`

The goal is IBM EGA compatible behavior as modeled by x86Box, not VGA. VGA-only
features should not be added unless they are harmless compatibility stubs or are
explicitly required by the PCXT integration.

## 1. Scope And Compatibility Target

Implement a base IBM EGA-compatible adapter with 256 KiB planar VRAM:

- Four 64 KiB planes.
- CPU accesses mapped through the EGA graphics controller, sequencer, latches,
  odd/even addressing, page select, and memory map selection.
- Display generation from the same planar VRAM, including text and graphics
  paths.
- EGA attribute controller palette, overscan, plane enable, horizontal panning,
  blink, and video enable behavior.
- CRTC timing, address generation, vertical counters, split/line-compare, start
  address latching, status bits, and retrace behavior closely matching x86Box.
- EGA 16-color and 64-color digital RGB palette behavior, including the brown
  exception in 16-color mode.

The implementation may remain PCXT-specific in bus timing and MiSTer video
output, but the externally visible EGA register, memory, and scanout semantics
must match the x86Box model.

## 2. Architectural Model

x86Box keeps all EGA runtime state in `ega_t`. For HDL, this maps naturally to
the following state groups:

- Bus/register state:
  - Current CRTC index.
  - Current graphics-controller index.
  - Current sequencer index.
  - Current attribute-controller index and flip-flop phase.
  - Misc Output register.
  - Input Status #1 register bits.
- Derived register state:
  - Write mask.
  - Write mode.
  - Read mode.
  - Read plane.
  - Chain-2 read/write enables.
  - Odd/even CPU remapping enable.
  - Extended-memory enable.
  - Memory map select.
  - Page select.
  - Palette lookup entries.
  - Plane enable mask.
- VRAM state:
  - Four 8-bit planes.
  - Four read latches.
  - CPU address remapping before plane selection.
- Scanout state:
  - CRTC horizontal character counter.
  - CRTC scanline/row counters.
  - Display-enable, blanking, and retrace windows.
  - Start address latch, current memory address, row backup address.
  - Cursor address and cursor visibility state.
  - Blink counter.
  - Horizontal panning cache.
  - Line compare/split state.
- Render state:
  - Text renderer.
  - Graphics renderer.
  - Overscan renderer.
  - Blank renderer.

The important design rule is that CPU VRAM access and video scanout are not two
unrelated memories or protocols. They are two views over the same four-plane
state, with the CPU side passing through the latches and the scanout side
passing through CRTC address remapping and the attribute controller.

## 3. I/O Port Map

The base EGA port set is:

| Port | Direction | Function |
| --- | --- | --- |
| `3C0h` / `2C0h` | write | Attribute Controller index/data toggle |
| `3C1h` / `2C1h` | read | Attribute Controller data readback on compatible cards |
| `3C2h` / `2C2h` | write | Misc Output |
| `3C2h` / `2C2h` | read | EGA switch sense |
| `3C4h` / `2C4h` | write | Sequencer index |
| `3C5h` / `2C5h` | read/write | Sequencer data |
| `3CCh` / `2CCh` | read | Misc Output readback |
| `3CEh` / `2CEh` | write | Graphics Controller index |
| `3CFh` / `2CFh` | read/write | Graphics Controller data |
| `3B4h/3B5h`, `3D4h/3D5h` | read/write | CRTC index/data |
| `3BAh`, `3DAh` | read | Input Status #1, also resets Attribute Controller flip-flop |

x86Box also contains alternate `2xx` support and adapter-specific ports for
non-IBM EGA variants. The PCXT core should prioritize the IBM-compatible
`3xx` range and may keep the `2xx` aliases already present in the RTL if they
do not conflict with PCXT devices.

Strict IBM EGA readback is limited in x86Box; compatible cards expose more
register data. The PCXT core may expose stable readback for implemented
registers to support the local minimal BIOS and software probes, but write
semantics, status side effects, and VRAM behavior should remain aligned with
the x86Box EGA model.

### 3.1 Color/Mono CRTC Address Selection

x86Box remaps CRTC/status port ranges when Misc Output bit 0 selects mono I/O:

- If Misc Output bit 0 is `1`, color ports are active (`3D4h/3D5h`, `3DAh`).
- If Misc Output bit 0 is `0`, mono ports are active (`3B4h/3B5h`, `3BAh`).
- x86Box implements this by XORing the CRTC/status range with `60h` when bit 0
  is clear.

The core should expose the active CRTC/status port range according to this bit.
The current RTL mostly routes through a fixed `IO_BASE_ADDR` and should be
checked against this requirement.

### 3.2 Attribute Controller Flip-Flop

The Attribute Controller uses a write-only index/data flip-flop at `3C0h`:

- A read from Input Status #1 (`3DAh` or active status port) resets the flip-flop
  to address phase.
- First write to `3C0h`: bits `4:0` select the attribute index; bit `5` is the
  palette/video-enable bit.
- Second write to `3C0h`: writes data to the selected attribute register.
- After every `3C0h` write the phase toggles.
- On SuperEGA only, x86Box masks bit 7 on writes because it reports flip-flop
  status on reads. Base IBM EGA does not require that extension.

Attribute-controller state must be independent of whether the EGA output is
currently selected by the MiSTer video mux. Guest software may probe status and
program palette before visible EGA output is active.

## 4. Register Specification

### 4.1 Misc Output Register (`3C2h` write, `3CCh` read)

x86Box-visible bits for base EGA:

| Bit | Meaning |
| --- | --- |
| `0` | I/O address select: `1` color (`3Dx`), `0` mono (`3Bx`) |
| `1` | RAM enable on Compaq EGA; base IBM x86Box keeps mapping active |
| `2` | Clock select: base IBM uses `0` = 14.31818 MHz, `1` = 16.257 MHz |
| `3` | Part of switch-sense select in x86Box |
| `5` | Page select used by CPU address remapping in odd/even modes |
| `7` | Vertical/palette mode: `0` selects 200-line doubled output and 16-color palette mapping; `1` selects high-resolution vertical mode and 64-color mapping |

The PCXT core currently initializes `ega_misc_output_reg` to `63h`; the minimal
BIOS writes `63h` for mode `0Dh`. That is acceptable for the current mode path,
but hardware behavior must still follow writes from the guest.

### 4.2 Sequencer Registers (`3C4h/3C5h`)

Base EGA registers are index `0..4`.

| Index | Name | Required behavior |
| --- | --- | --- |
| `00h` | Reset | Store/readback. x86Box does not model detailed asynchronous reset side effects for base behavior. |
| `01h` | Clocking Mode | Bit `0`: `0` = 9-dot character timing, `1` = 8-dot. Bit `3`: double-width/low-res mode. Bit `5`: screen blank. Timing and render mode must be recalculated when this changes. |
| `02h` | Map Mask | Bits `3:0` select writable planes. |
| `03h` | Character Map Select | Selects font banks. x86Box uses two 2-bit fields: charset B from bits `3:2`, charset A from bits `1:0`; each bank base is `bank * 10000h + 2` in interleaved VRAM. |
| `04h` | Memory Mode | Bit `1`: extended memory. If clear, CPU remapped address is masked to `3FFFh`. Bit `2`: disables chain-2 write when set; x86Box uses `chain2_write = !(bit2)`. |

The current `ega_sequencer.v` covers map mask, memory mode, clocking mode, and
fetch pacing, but text rendering does not yet consume Character Map Select.

### 4.3 Graphics Controller Registers (`3CEh/3CFh`)

Base EGA registers are index `0..8`.

| Index | Name | Required behavior |
| --- | --- | --- |
| `00h` | Set/Reset | Per-plane set/reset value. Bits `3:0` matter. |
| `01h` | Enable Set/Reset | Per-plane enable for Set/Reset. Bits `3:0` matter. |
| `02h` | Color Compare | Used by read mode 1. Bits `3:0` matter. |
| `03h` | Data Rotate | Bits `2:0` rotate CPU write data right. Bits `4:3` select ROP: set, AND, OR, XOR. |
| `04h` | Read Map Select | Bits `1:0` select the plane returned by read mode 0. |
| `05h` | Mode | Bits `1:0` write mode. Bit `3` read mode. Bit `4` chain-2 read. Bit `5` CGA 2bpp shift/render mode. |
| `06h` | Misc | Bit `0` graphics/text select. Bit `1` odd/even CPU address remapping. Bits `3:2` memory map select. |
| `07h` | Color Don't Care | Used by read mode 1. Bits `3:0` matter. |
| `08h` | Bit Mask | Per-bit write mask. |

Base EGA write modes required by x86Box are modes `0`, `1`, and `2`.
Write mode `3` is not implemented by x86Box's EGA path and should behave as a
no-op or remain unsupported unless a deliberate VGA extension is added.

### 4.4 Attribute Controller Registers

| Index | Name | Required behavior |
| --- | --- | --- |
| `00h..0Fh` | Palette entries | Base IBM EGA maps each entry to a 6-bit color by `attrregs[i] & 3Fh`. |
| `10h` | Mode Control | Bit `0` graphics/text attribute interpretation. Bit `1` mono attributes. Bit `2` line graphics enable for 9th-dot text chars `C0h..DFh`. Bit `3` blink/intensity behavior. Bit `7` affects extended chipsets only in x86Box, not base IBM. |
| `11h` | Overscan/Border Color | Selects overscan color; uses 16-color or 64-color lookup depending on Misc Output bit 7. |
| `12h` | Color Plane Enable | Bits `3:0` mask rendered plane color index. Bits `5:4` are used by Compaq color mux status only. |
| `13h` | Horizontal Pixel Panning | x86Box caches this at vertical reset: values `0..7` become `value + 1`; values `8..15` become `0`; doubled in low-res/double-width mode. |
| `14h` | Color Select | Base IBM EGA stores/readbacks it but does not alter `egapal`; x86Box only uses it for chipset variants. |

The current RTL correctly ignores Color Select for base IBM color calculation.
It still needs complete blink, mono text, line-graphics, and panning behavior
as specified by the x86Box render path.

### 4.5 CRTC Registers

x86Box models CRTC indexes `00h..18h` for base EGA. Important behavior:

- Index writes:
  - Base IBM masks the selected CRTC index with `1Fh`.
  - Registers `00h..06h` are protected from writes when CRTC register `11h`
    bit `7` is set.
  - Register `07h` is partly protected when register `11h` bit `7` is set:
    only bit `4` is writable; all other bits retain their old value.
  - Indexes `19h..F6h` are ignored on base IBM EGA.
- Readback:
  - Base IBM x86Box behavior only guarantees a limited subset, mainly
    start-address/cursor-related registers.
  - x86Box's `EGA_TYPE_OTHER` path exposes broader CRTC readback.
  - The PCXT implementation may provide broader stable readback for practical
    compatibility, but must preserve the write-protection and timing side
    effects described above.

Derived values in `ega_recalctimings()`:

- `vtotal = crtc[06h] + overflow bit8 from crtc[07h].bit0 + overflow bit9 from crtc[07h].bit5 + 2`
- `dispend = crtc[12h] + overflow bit8 from crtc[07h].bit1 + overflow bit9 from crtc[07h].bit6 + 1`
- `vsyncstart = crtc[10h] + overflow bit8 from crtc[07h].bit2 + overflow bit9 from crtc[07h].bit7 + 1`
- `split = crtc[18h] + overflow bit8 from crtc[07h].bit4 + overflow bit9 from crtc[09h].bit6 + 1`
- `hdisp = crtc[01h] + 1`, then scaled by text/graphics and low-res mode.
- `rowoffset = crtc[13h]`.
- `rowcount = crtc[09h] & 1Fh`.
- `linedbl = crtc[09h].bit7`.
- `memaddr_latch = (crtc[0Ch] << 8) | crtc[0Dh]`.

Start-address writes update `memaddr_latch` immediately, but the visible
fetch base is reloaded on the next vertical frame boundary in x86Box. The
current RTL comment in `ega_top.v` already acknowledges this; the CRTC/scanout
state should preserve that behavior.

CRTC register `17h` bit `7` is the CRTC reset/display enable gate used by
x86Box renderers. If clear, text and graphics render paths read zeros instead
of VRAM data.

## 5. CPU VRAM Access

### 5.1 Physical Organization

x86Box allocates `40000h` bytes and stores planes interleaved:

- Logical remapped CPU address `A` becomes byte offset `A << 2`.
- Plane 0 byte is at `(A << 2) | 0`.
- Plane 1 byte is at `(A << 2) | 1`.
- Plane 2 byte is at `(A << 2) | 2`.
- Plane 3 byte is at `(A << 2) | 3`.

The HDL may store four independent 64 KiB arrays, but every CPU and scanout
operation must be equivalent to this interleaved model.

### 5.2 CPU Address Remapping

Before plane selection, x86Box remaps the CPU address in `ega_remap_cpu_addr()`:

1. Start with the CPU offset inside the active memory mapping.
2. Compute `a0mux`:
   - Add bit `1` if Graphics Controller register `06h` bit `1` is set
     (odd/even mode).
   - Add bit `0` if the card has 64 KiB or less VRAM.
   - Add bit `2` if memory map select is `00b` (`128K at A0000`).
3. Apply memory map select from Graphics Controller register `06h` bits `3:2`:
   - `00b`: 128 KiB window at `A0000h`; mask CPU offset to `FFFFh`.
   - `01b`: 64 KiB window at `A0000h`; mask CPU offset to `FFFFh`.
   - `10b`: 32 KiB window at `B0000h`; mask CPU offset to `7FFFh`.
   - `11b`: 32 KiB window at `B8000h`; mask CPU offset to `7FFFh`.
4. Apply A0 mux:
   - `0`, `1`, `4`, `5`, `7`: A0 remains CPU A0.
   - `2`: A0 becomes inverse of Misc Output bit `5` page select.
   - `3`: A0 becomes CPU A14.
   - `6`: A0 becomes CPU A16.
5. If Sequencer register `04h` bit `1` is clear, mask the final address to
   `3FFFh`.

For the current 256 KiB PCXT target, the `card_is_64k` branch can remain false,
but the A16 path is still required for 128 KiB mapping behavior.

The current `rtl/video/ega_vram.v` implements the same basic remap function and
now has a `cpu_a16` input. The outer memory decode in `Peripherals.sv` currently
selects only `A0000h-AFFFFh`; that is not enough for full x86Box behavior,
because memory map `00b` is a 128 KiB aperture and map modes `10b/11b` require
`B0000h/B8000h` CPU visibility.

### 5.3 Read Latches

Every CPU read loads all four latches from the remapped address, regardless of
which plane is returned:

- `la = plane0[A]`
- `lb = plane1[A]`
- `lc = plane2[A]`
- `ld = plane3[A]`

Write mode 1 writes these latched values back to a later selected address.
Correct latch behavior is essential for masked blits, hardware scrolling,
transparent sprite writes, and many DOS game drawing routines.

Writes do not refresh the latches in x86Box. A write consumes the previously
latched values.

### 5.4 CPU Read Modes

Read mode 0:

- If chain-2 read is enabled, effective read plane is
  `{read_plane[1], cpu_addr[0]}`.
- Otherwise effective read plane is Graphics Controller register `04h[1:0]`.
- Return the selected latched plane byte.

Read mode 1:

For each plane byte loaded into the latch:

```text
temp0 = plane0 ^ (color_compare[0] ? FFh : 00h)
temp0 = temp0 & (color_dont_care[0] ? FFh : 00h)
...
return ~(temp0 | temp1 | temp2 | temp3)
```

Only bits `3:0` of Color Compare and Color Don't Care participate. This is
equivalent to returning `1` for each pixel bit where all cared planes match the
compare color.

### 5.5 CPU Write Plane Mask

Start with Sequencer Map Mask bits `3:0`.

If chain-2 write is enabled, x86Box applies:

```text
writemask2 = writemask & (0101b << cpu_addr[0])
```

Thus even CPU offsets can write planes 0 and 2; odd CPU offsets can write
planes 1 and 3.

### 5.6 CPU Write Modes

All writes first remap the address, shift it to the four-plane byte group, and
discard the write if it is outside `vram_limit`.

Write mode 0:

1. Rotate host byte right by Data Rotate bits `2:0`.
2. For each plane:
   - If Enable Set/Reset for that plane is set, source byte is `FFh` if the
     plane's Set/Reset bit is `1`, otherwise `00h`.
   - Otherwise source byte is the rotated host byte.
3. Apply ROP selected by Data Rotate bits `4:3`:
   - `00b`: source
   - `01b`: source AND latch
   - `10b`: source OR latch
   - `11b`: source XOR latch
4. Apply Bit Mask:
   - New byte = `(rop_result & bit_mask) | (latch & ~bit_mask)`.
5. Commit only planes enabled by `writemask2`.

x86Box has a fast path when bit mask is `FFh`, ROP is set, and Enable Set/Reset
is zero. The result is equivalent to writing the rotated host byte to each
enabled plane.

Write mode 1:

- Ignore the host byte.
- Write the four latches to the enabled planes.

Write mode 2:

1. For each plane, expand the corresponding low host-data bit into `FFh` or
   `00h`.
2. Apply the same ROP and Bit Mask operation as mode 0.
3. Commit only enabled planes.

Write mode 3:

- x86Box's EGA implementation does not implement it. Treat as no write for
  base EGA unless a deliberate VGA-compatible extension is designed.

The current `ega_vram.v` implements modes 0, 1, 2 and read mode 1 close to
x86Box, including latch preservation on writes. Keep this as the reference for
future changes.

## 6. Display Address Generation

### 6.1 Scanout Address Remapping

x86Box display rendering does not use the CPU remap function. It uses
`ega_recalc_remap_func()` from `vid_ega_render_remap.h`, selected by CRTC
registers:

1. If CRTC register `14h` bit `6` is set:
   - Dword mode:
   - `out = ((in << 2) & 3FFF0h) | ((in >> 14) & 0Ch) | (in & ~3FFFFh)`
2. Else if CRTC register `17h` bit `6` is set:
   - Byte mode:
   - `out = in`
3. Else if CRTC register `17h` bit `5` is set and VRAM is larger than 64 KiB:
   - Word mode using MA15:
   - `out = ((in << 1) & 3FFF8h) | ((in >> 15) & 04h) | (in & ~3FFFFh)`
4. Else:
   - Word mode using MA13:
   - `out = ((in << 1) & 3FFF8h) | ((in >> 13) & 04h) | (in & ~3FFFFh)`

Then row-scanline substitution is applied:

- If CRTC register `17h` bit `0` is clear, output MA13 is replaced by
  `scanline[0]`.
- If CRTC register `17h` bit `1` is clear, output MA14 is replaced by
  `scanline[1]`.

The renderer masks the final address with `vrammask`.

This remap is required for correct 200-line/350-line addressing, odd/even row
layout, and split/line-compare effects. It is separate from the CPU remap.

### 6.2 Row Advance

x86Box advances display memory by `rowoffset << 3` interleaved bytes at the end
of each character row:

```text
memaddr_backup += crtc[13h] << 3
memaddr = memaddr_backup
```

Because x86Box stores planes interleaved, `rowoffset << 3` corresponds to
`rowoffset * 2` character addresses before the final `<< 2` plane byte group.
An HDL implementation with independent plane RAMs should advance the plane
address by `rowoffset << 1`.

The current `UM6845R.v` EGA mode uses `R19_offset_e << 1` as `ega_row_advance`,
which matches the independent-plane representation. Keep this distinction
explicit.

### 6.3 Start Address And Frame Latching

At vertical sync start, x86Box reloads:

```text
memaddr = memaddr_backup = memaddr_latch
cursoraddr = (crtc[0Eh] << 8) | crtc[0Fh]
memaddr <<= 2
memaddr_backup <<= 2
cursoraddr <<= 2
```

If interlace odd/even state requires it, x86Box adds `rowoffset << 1` before
the final shift.

The visible start address must not change in the middle of a frame merely
because registers `0Ch/0Dh` were written. It changes on the frame reload.

### 6.4 Split / Line Compare

x86Box computes:

```text
split = crtc[18h]
if crtc[07h].bit4: split |= 100h
if crtc[09h].bit6: split |= 200h
split += 1
```

When the vertical counter reaches `split`, x86Box resets display memory address
to the start of display page 0:

- Normally `memaddr = memaddr_backup = 0`.
- In one interlace odd/even case, `memaddr = memaddr_backup = rowoffset << 1`.
- Then both are shifted left by 2 in x86Box's interleaved storage.
- `scanline` resets to 0.

There is a TODO in x86Box about a hardware bug where the first scanline is
drawn twice when the split happens; this does not need to be reproduced unless
a known game depends on it.

## 7. Render Modes

### 7.1 Mode Selection

x86Box chooses the renderer during timing recalculation:

- If Sequencer Clocking Mode bit `5` (`scrblank`) is set, render blank.
- If Attribute Controller palette/video enable bit `5` is clear, render blank.
- Else if Graphics Controller Misc bit `0` is clear, render text.
- Else render graphics.

The current core primarily renders planar graphics. A complete implementation
needs an actual text render path that consumes character/attribute bytes and
font data from EGA VRAM.

### 7.2 Horizontal Display Width

x86Box starts from `hdisp = crtc[01h] + 1`.

For text mode:

- If Sequencer Clocking Mode bit `3` is set:
  - Multiply by `16` when bit `0` is `1`, or `18` when bit `0` is `0`.
- Else:
  - Multiply by `8` when bit `0` is `1`, or `9` when bit `0` is `0`.

For graphics mode:

- Multiply by `16` when Sequencer Clocking Mode bit `3` is set.
- Otherwise multiply by `8`.

The hardware implementation may generate pixels directly, but the number of
visible pixels per CRTC character must match these rules.

### 7.3 Text Rendering

For each visible character:

1. Compute `addr = scanout_remap(memaddr) & vrammask`.
2. If CRTC register `17h` bit `7` is clear, use `chr = attr = 0`.
3. Otherwise:
   - `chr = vram[addr + 0]` (plane 0 in interleaved x86Box layout).
   - `attr = vram[addr + 1]` (plane 1).
4. Font address:
   - If `attr[3]` is set, use charset B.
   - Else use charset A.
   - `charaddr = charset + chr * 80h`.
   - Glyph byte = `vram[charaddr + (scanline << 2)]` (plane 2).
5. Shift glyph byte left by one before rendering.
6. If Attribute Mode Control bit `2` is set and `chr` is in `C0h..DFh`, copy
   the 8th glyph bit into the 9th dot.
7. Color selection:
   - Normal:
     - FG = palette lookup of `attr[3:0]`.
     - BG = palette lookup of `attr[7:4]`.
   - Cursor draw inverts by swapping foreground/background in the x86Box path.
   - If Attribute Mode Control bit `3` enables blink and `attr[7]` is set:
     - BG uses `(attr >> 4) & 7`.
     - When blink is active, FG becomes BG.
8. If Attribute Mode Control bit `1` enables mono attributes, use the x86Box
   MDA attribute table, including underline on CRTC register `14h`.
9. Increment `memaddr` by 4 interleaved bytes per character.

For HDL with four independent planes:

- Character byte comes from plane 0 at character address.
- Attribute byte comes from plane 1 at character address.
- Font byte comes from plane 2 at `font_bank_base + chr * 20h + scanline`
  when converted from x86Box's interleaved `chr * 80h + scanline * 4` formula.

### 7.4 Graphics Rendering

For each 8-pixel group:

1. Compute `addr = scanout_remap(memaddr) & vrammask`.
2. If Sequencer Clocking Mode bit `2` is set, x86Box's graphics renderer uses
   an odd/even-like fetch pattern and toggles a `secondcclk` bit. This behavior
   has an x86Box FIXME for planes 1 and 3, but it is still the practical source
   of truth.
3. Otherwise read four plane bytes at the same address.
4. If Graphics Controller Mode bit `5` is set, convert CGA 2bpp chunky data to
   planar data using `egaremap2bpp`.
5. If CRTC register `17h` bit `7` is clear, output black.
6. Otherwise, for each pair of pixel bits:
   - x86Box uses `edatlookup` to combine two bits from plane 0 and plane 1,
     then two bits from plane 2 and plane 3.
   - The final 4-bit color index for each pixel is `{plane3, plane2, plane1, plane0}`.
7. Apply Attribute Controller Color Plane Enable:
   - `color = color & plane_mask` for normal pixels.
8. Apply blink behavior in graphics mode according to x86Box:
   - `blinkmask = attrblink ? 8 : 0`.
   - `blinkval = attrblink && blinked ? 8 : 0`.
   - `color = ((color & plane_mask & ~blinkmask) | ((color | ~plane_mask) & blinkmask & blinkval)) ^ blinkmask`.
9. Convert the 4-bit color index through the Attribute Controller palette.

The current `ega_pixel.v` should be reviewed carefully: it declares shift
registers, but the non-load path currently drives `plane_index` from the panned
fetch wires rather than the shift registers. The intended behavior is to shift
one bit per pixel clock, repeating pixels only in low-resolution/double-clock
mode.

### 7.5 CGA 2bpp Graphics Mode

When Graphics Controller Mode bit `5` is set, x86Box remaps bytes:

```text
dat0 = egaremap2bpp[edat1]      | (egaremap2bpp[edat0]      << 4)
dat1 = egaremap2bpp[edat1 >> 1] | (egaremap2bpp[edat0 >> 1] << 4)
dat2 = egaremap2bpp[edat3]      | (egaremap2bpp[edat2]      << 4)
dat3 = egaremap2bpp[edat3 >> 1] | (egaremap2bpp[edat2 >> 1] << 4)
```

`egaremap2bpp[x]` maps source bits `0,2,4,6` to output bits `0,1,2,3`.

This mode is not optional if compatibility with software using EGA CGA-style
shift modes is desired.

## 8. Palette And RGB Output

### 8.1 Base Palette Indirection

For base IBM EGA:

```text
egapal[i] = attrregs[i] & 3Fh
```

Attribute register `14h` Color Select does not modify `egapal` on base IBM EGA
in x86Box. It is only used for chipset variants.

### 8.2 64-Color Mapping

64-color mode is selected when Misc Output bit `7` is `1`.

For each 6-bit color `c`:

```text
R = bit2(c) * AAh + bit5(c) * 55h
G = bit1(c) * AAh + bit4(c) * 55h
B = bit0(c) * AAh + bit3(c) * 55h
```

The current `ega_vgaport.v` expresses this in 6-bit DAC-ish levels as
`42 + 21`.

### 8.3 16-Color Mapping

16-color mode is selected when Misc Output bit `7` is `0`, the mode used for
200-line EGA modes in x86Box.

For each 6-bit color `c`, x86Box effectively uses:

```text
R = bit2(c) * AAh + bit4(c) * 55h
G = bit1(c) * AAh + bit4(c) * 55h
B = bit0(c) * AAh + bit4(c) * 55h
```

With the IBM brown exception:

```text
if ((c & 17h) == 06h) RGB = AA,55,00
```

The current `ega_vgaport.v` implements this exception.

### 8.4 DAC Ports

Base EGA does not have a VGA RAMDAC at `3C7h..3C9h`. The current top-level
returns `00h` for those ports. That is acceptable as a compatibility stub, but
software-visible color behavior must come from the Attribute Controller and
EGA digital palette, not from VGA DAC state.

## 9. Timing, Status, And Blanking

### 9.1 Dot Clocks

x86Box IBM EGA timing:

- If Misc Output bit `2` is set: 16.257 MHz dot clock family.
- Else: 14.31818 MHz dot clock family (`157500000 / 11`).
- Sequencer Clocking Mode bit `0` selects whether the CRTC character is 8 or 9
  dots.
- Sequencer Clocking Mode bit `3` doubles horizontal pixel width in low-res
  modes.

The MiSTer implementation can use the existing CGA/video clock domain, but the
observable CRTC counters, displayed width, retrace status, and fetch cadence
must match the register-programmed EGA model.

### 9.2 Input Status #1

x86Box behavior on `3DAh`/active status read:

- Resets the Attribute Controller flip-flop to address phase.
- Bit `0`: display disabled / not displaying. x86Box sets it during horizontal
  blank/off time and clears it during active display.
- Bit `3`: vertical retrace. x86Box opens it at vertical sync start and closes
  it after a short programmable scanline window using CRTC register `11h[3:0]`.
- On IBM EGA, x86Box toggles bits `4` and `5` on every status read to satisfy
  the IBM EGA BIOS self-test.
- On Compaq EGA, bits `4` and `5` are derived from a color mux; this is not
  needed for the base PCXT target unless Compaq mode is added.

The current `ega_top.v` status register exposes bit `0` and bit `3` only.
For BIOS/game compatibility, implement the IBM `0x30` toggle behavior unless
testing proves it conflicts with the MiSTer integration.

### 9.3 Overscan

x86Box derives overscan dimensions from mode state:

- `overscan_y = max((rowcount + 1) << 1, 16)`.
- If 200-line/doubled vertical mode is active, overscan Y is doubled.
- `overscan_x = 16` in 8-dot modes, `18` in 9-dot modes.
- If Sequencer Clocking Mode bit `3` is set, overscan X is doubled.

For MiSTer, exact border dimensions may be adapted to output constraints, but
the border color and active display gating should match EGA state.

### 9.4 Blink And Cursor

At vertical display end, x86Box:

- Computes cursor visibility from CRTC cursor start/end and blink delay.
- Increments `blink = (blink + 1) & 7Fh`.
- Uses blink bit `4` for text/graphics blink state.
- Forces a full redraw periodically in text mode.

Cursor behavior:

- Cursor address is `(crtc[0Eh] << 8) | crtc[0Fh]`, shifted into interleaved
  storage in x86Box.
- Cursor is visible between CRTC register `0Ah[4:0]` and `0Bh[4:0]`.
- CRTC register `0Ah` bit `5` disables cursor.
- CRTC register `0Bh[6:5]` controls cursor blink delay in x86Box.

The current render path does not implement text cursor inversion.

## 10. PCXT Integration Requirements

### 10.1 Memory Decode

The outer PCXT memory decode must honor Graphics Controller register `06h`
memory map selection:

- Map `00b`: decode `A0000h-BFFFFh` as a 128 KiB aperture.
- Map `01b`: decode `A0000h-AFFFFh` as a 64 KiB aperture.
- Map `10b`: decode `B0000h-B7FFFh` as a 32 KiB aperture.
- Map `11b`: decode `B8000h-BFFFFh` as a 32 KiB aperture.

The current `Peripherals.sv` EGA select is limited to `A0000h-AFFFFh`, which
means the VRAM remap function can be correct internally while the CPU never
reaches the required outer windows.

### 10.2 I/O Decode

I/O register reads/writes must work whenever `ega_enabled` is set, regardless of
whether EGA is currently driving the VGA output. The current `ega_display_sel`
gate should not suppress register readback required for probing.

### 10.3 Output Selection

The current `ega_video_active`/`ega_video_pending` mechanism is a PCXT display
mux policy, not EGA hardware. Keep it outside the EGA hardware model:

- It may decide when MiSTer output switches from CGA to EGA.
- It must not alter CPU memory semantics.
- It must not alter I/O register semantics.
- It must not prevent status reads, palette writes, or CRTC programming.

### 10.4 EGA BIOS

`egabios.asm` is a minimal compatibility BIOS for mode `0Dh` and game probing.
It is not a hardware source of truth.

Use it as:

- A known mode-programming sequence for current smoke tests.
- A reference for required BIOS-visible probes such as INT 11h and INT 10h
  function `12h`.

Do not use it to limit hardware implementation. Games can bypass BIOS and
program EGA registers directly.

## 11. Current Core Gap Analysis

This section describes observed differences between the current RTL and the
x86Box reference. It is intentionally diagnostic, not an implementation plan.

1. CPU memory decode is incomplete.
   - `Peripherals.sv` selects only `A0000h-AFFFFh`.
   - x86Box supports `A0000h-BFFFFh`, `A0000h-AFFFFh`, `B0000h-B7FFFh`, and
     `B8000h-BFFFFh` according to GC register `06h[3:2]`.

2. Text mode rendering is missing.
   - x86Box has a complete `ega_render_text()` path.
   - Current scanout appears graphics-oriented and does not consume character
     bytes, attribute bytes, font plane, Character Map Select, cursor, mono
     attributes, or 9th-dot line graphics.

3. Graphics pixel shifting should be audited.
   - `ega_pixel.v` declares shift registers but the non-load path currently
     drives `plane_index` from panned fetch wires rather than the shift
     registers.
   - Expected behavior is one shifted bit per dot, with repeat only in
     low-resolution mode.

4. Scanout address remapping is only partially represented.
   - x86Box has a separate render remap controlled by CRTC `14h[6]`,
     `17h[6]`, `17h[5]`, `17h[1:0]`, and scanline bits.
   - `UM6845R.v` handles EGA row advance and line compare, but it should be
     verified against `vid_ega_render_remap.h` mode by mode.

5. Status register bits `4` and `5` are missing.
   - x86Box toggles `0x30` on each IBM EGA status read.
   - Current `ega_status_reg` returns only bit `0` and bit `3`.

6. CRTC write protection should be verified.
   - x86Box protects registers `00h..06h` and partially protects `07h` when
     CRTC `11h[7]` is set.
   - Current `UM6845R.v` appears to write CRTC registers directly.

7. Attribute Controller behavior is incomplete.
   - Palette/index flip-flop and plane enable exist.
   - Missing or incomplete: blink effects, text mono attributes, line graphics,
     full x86Box horizontal panning cache behavior, and status-read interaction
     independent of display select.

8. CGA 2bpp EGA graphics mode is missing.
   - x86Box implements GC Mode bit `5` conversion in `ega_render_graphics()`.

9. Character Map Select is not used by scanout.
   - `ega_sequencer.v` stores `char_map_reg`, but without text rendering it has
     no display effect.

10. VGA DAC ports are stubs.
    - This is acceptable for base EGA, but the implementation must avoid
      accidentally depending on DAC state for EGA colors.

11. The VRAM testbench should be updated.
    - `ega_vram.v` has a `cpu_a16` input; the testbench should drive it and add
      explicit A16/page-select/memory-map cases.

12. The `cpu_access_en` / display-fetch contention path is not functionally
    used by `ega_vram_bram_frontend.sv`.
    - x86Box models CPU cycle cost, not exact bus contention.
    - For PCXT, this is acceptable if bus wait states remain stable, but it
      should be deliberate.

## 12. Recommended Verification Matrix

Create small, deterministic tests before relying only on game testing.

### 12.1 CPU VRAM Tests

Required cases:

- Read mode 0 loads all latches and returns selected plane.
- Read mode 1 matches x86Box formula for varied Color Compare and Color Don't
  Care values.
- Write mode 0:
  - Rotate counts `0..7`.
  - ROP set/AND/OR/XOR.
  - Bit Mask values `00h`, `FFh`, and sparse masks.
  - Enable Set/Reset combinations.
- Write mode 1 copies prior latches and ignores host byte.
- Write mode 2 expands host bits `0..3`.
- Chain-2 write masks even/odd CPU addresses correctly.
- Chain-2 read selects `{read_plane[1], cpu_addr[0]}`.
- Extended-memory clear masks address to `3FFFh`.
- Memory map modes `00b..11b`, including CPU A16 behavior.
- Page select bit `5` in Misc Output affects odd/even A0 mux.

The existing `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv` covers latch basics, write
modes 0/1/2, read mode 1, and consecutive writes. Extend it rather than
replacing it.

### 12.2 Register Tests

Required cases:

- Attribute flip-flop reset by status read.
- Attribute index/data alternating writes.
- Attribute palette enable bit changes render enable.
- Attribute register `14h` readback does not alter base IBM palette.
- Sequencer map mask and memory mode outputs.
- Graphics Controller readback for registers `0..8`.
- CRTC protected writes with `11h[7]`.
- Misc Output bit `0` switches active CRTC/status port range.
- Status reads toggle bits `4/5` and reset attribute flip-flop.

### 12.3 Scanout Tests

Required cases:

- 320x200x16 mode `0Dh` programmed by `egabios.asm`.
- 640x200x16 mode `0Eh` or direct register equivalent.
- 640x350x16 mode `10h` direct register equivalent.
- Text mode using EGA font plane and attribute bytes.
- Horizontal panning values `0..15`.
- Start address changes at frame boundary, not mid-frame.
- Split/line-compare reset to address 0.
- CRTC reset bit `17h[7]` blanks rendered data.
- GC Mode bit `5` CGA 2bpp conversion.
- Attribute plane enable masks color bits.
- Blink on/off periods for text and graphics.

### 12.4 Game-Oriented Smoke Tests

Use games known to exercise specific behavior:

- Prehistorik:
  - EGA BIOS detection.
  - INT 11h equipment word.
  - Mode `0Dh`.
  - Planar writes and palette.
- Games with smooth EGA scrolling:
  - Horizontal panning.
  - Start address changes.
  - Split screen.
- Games with masked sprites:
  - Read latches.
  - Write mode 1.
  - Write mode 2.
  - Bit Mask and ROP.
- Games with EGA text screens:
  - Character map selection.
  - Text attributes.
  - Cursor.

## 13. Implementation Guidance

The safest porting sequence is:

1. Keep `ega_vram.v` as the CPU VRAM reference block and add missing memory-map
   test coverage.
2. Fix outer memory decode so all GC memory map modes can reach the VRAM block.
3. Make all EGA I/O registers visible while `ega_enabled`, independent of video
   output selection.
4. Bring CRTC register semantics into alignment with x86Box:
   - Protection.
   - Overflow bits.
   - Start address latch.
   - Status windows.
   - Scanout remap.
   - Split/line compare.
5. Correct the graphics pixel shifter and add CGA 2bpp shift-mode support.
6. Add the text renderer:
   - Plane 0 character bytes.
   - Plane 1 attributes.
   - Plane 2 font data.
   - Sequencer Character Map Select.
   - Cursor and blink.
   - 9-dot line graphics.
7. Complete Attribute Controller render effects:
   - Panning cache.
   - Plane enable.
   - Blink.
   - Overscan color.
8. Add status bit `0x30` toggle and verify BIOS self-tests/probes.
9. Re-run deterministic testbenches and then game smoke tests.

Each step should preserve the x86Box formulas in this document. If the HDL must
represent state differently, add comments that name the corresponding x86Box
field or function.

## 14. Non-Goals For The First Complete Port

These are present in x86Box but should not block the base PCXT EGA target:

- Compaq EGA-specific color mux and monitor ID ports.
- Chips & Technologies SuperEGA extended registers.
- ATI EGA Wonder EEPROM and extended chipset behavior.
- JEGA/JVGA behavior.
- VGA-compatible DAC palette behavior.
- Exact analog monitor overscan sizing, as long as active display, border color,
  and sync/status behavior remain compatible.

Do not remove hooks that make these extensions possible later, but keep the
first complete implementation focused on base IBM EGA behavior.
