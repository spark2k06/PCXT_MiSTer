# EGA CRTC Register Behavior Checklist

This checklist anchors Phase 3 CRTC work before scanout timing or display
address logic is changed. Register numbers are EGA CRTC index values in hex.
`UM6845R.v` internal names use decimal-oriented historical names; for example
index `17h` is currently stored in `R23_mode_control_e`.

Sources:

- `SPEC.md` sections 4.5, 6, and 9.
- `PLAN.md` phase 3.
- `rtl/video/UM6845R.v`.
- `rtl/video/ega_top.v`.

## Current Implementation Summary

- Index writes are masked to five bits through `addr <= DI[4:0]`.
- EGA write protection for indexes `00h..06h` and partial protection for
  `07h[4]` is implemented through `R17_v_sync_end_e[7]`, which is CRTC index
  `11h[7]`.
- The module provides broad readback for indexes `0Ah..18h`; indexes `00h..09h`
  mostly read as `00h`, except CRTC status behavior when reading the address
  register path.
- EGA extended vertical timing now composes the documented x86Box overflow bits
  for vertical total, display end, vertical retrace start, and split target.
- EGA display address generation now applies the x86Box render remap controlled
  by CRTC `14h` and `17h` before exporting the VRAM fetch address.

## Register Matrix

| Index | Register | Current storage / output | Current EGA behavior | Gap / owning task |
| --- | --- | --- | --- | --- |
| `00h` | Horizontal Total | `R0_h_total`; used by `eff_h_total` and `hcc_last`. | Stored and protected by `11h[7]`; EGA mode adds one when `ega_crtc_semantics` is active. No normal data readback. | Timing formula coverage belongs to EGA-302. |
| `01h` | Horizontal Displayed | `R1_h_displayed`; exported as `H_DISP_REG`; controls `hde` clear. | Stored and protected. `DISPLAYED_CHARS_PLUS1` instance parameter adapts displayed-character off-by-one behavior. | Horizontal displayed-width validation belongs to EGA-302/EGA-304. |
| `02h` | Horizontal Sync Position | `R2_h_sync_pos`; used by `hsync_on`. | Stored and protected. Current EGA output subtracts a fixed offset based on `hres_mode`. | Needs representative timing checks in EGA-302. |
| `03h` | Sync Widths | `{R3_v_sync_width, R3_h_sync_width}`. | Stored and protected. `R3_h_sync_width` drives HSYNC length; `R3_v_sync_width` is used only for non-EGA CRTC type. | Confirm IBM EGA expectations in EGA-302; EGA vertical retrace uses `11h[3:0]`. |
| `04h` | Vertical Total Low | `R4_v_total[6:0]`. | Stored and protected. Used only by non-extended fallback path. | EGA vertical total must compose from `06h` plus `07h[0]` and `07h[5]`; EGA-302. |
| `05h` | Vertical Total Adjust | `R5_v_total_adj[4:0]`. | Stored and protected. Used by frame adjustment logic. | Needs frame-adjust regression coverage in EGA-302. |
| `06h` | Vertical Displayed Low | `R6_v_displayed`. | Stored and protected. Used by non-extended fallback path. | EGA display end must compose from `12h` plus `07h[1]` and `07h[6]`; EGA-302. |
| `07h` | Overflow | `R7_v_sync_pos`. | Stored with partial protection: when `11h[7]` is set, only bit 4 can change. Active formulas use bits 0, 1, 2, 3, 4, 5, 6, and 7. | Formula composition is covered by EGA-302; split side effects are covered by EGA-306. |
| `08h` | Preset Row Scan / Interlace | `{R8_skew, R8_interlace}`. | Stored. Interlace participates in generic field/line logic. | Verify whether EGA interlace odd/even start-address adjustment is needed in EGA-305. |
| `09h` | Maximum Scan Line | `R9_v_max_line`; low five bits are exported as `V_MAXSCAN_REG`. | Full byte is stored. Low five bits drive scanline row length, bit `6` participates in split target composition, and bit `7` doubles row advance. | Covered by EGA-304/EGA-306. |
| `0Ah` | Cursor Start | `{R10_cursor_mode, R10_cursor_start}`. | Stored/readable. Generic cursor line logic uses `R10_cursor_start`. | Text cursor blink/disable behavior belongs to later text-render tasks; keep visible in EGA-301 traceability. |
| `0Bh` | Cursor End | `R11_cursor_end[4:0]`. | Stored/readable. Generic cursor line logic uses low five bits. | Bits `6:5` blink-delay semantics are not implemented; defer to text cursor task after CRTC address work. |
| `0Ch` | Start Address High | `R12_start_addr_h`; also writes `start_addr_latch[15:8]`. | Stored/readable. Writes update the pending latch immediately; visible EGA reloads use `start_addr_frame`, which updates only on `frame_new`. | Covered by EGA-305. |
| `0Dh` | Start Address Low | `R13_start_addr_l`; also writes `start_addr_latch[7:0]`. | Stored/readable. Same pending/visible split as `0Ch`. | Covered by EGA-305. |
| `0Eh` | Cursor Location High | `R14_cursor_h[5:0]`. | Stored/readable. EGA `CURSOR` compares against `cursor_addr_frame`, which updates only on `frame_new`; non-EGA keeps raw-register behavior. | Full EGA text cursor render behavior is outside Phase 3. |
| `0Fh` | Cursor Location Low | `R15_cursor_l`. | Stored/readable. Same frame-latched cursor address behavior as `0Eh`. | Covered by EGA-305. |
| `10h` | Vertical Retrace Start Low | `R16_v_sync_pos_e`; exported as `crtc_r10_debug`. | Stored/readable and used in EGA vertical sync start formula with overflow bit `07h[7]`. | Covered by EGA-302. |
| `11h` | Vertical Retrace End / Protect | `R17_v_sync_end_e`; exported as `crtc_r11_debug`. | Stored/readable. Bit `7` protects indexes `00h..06h` and partially protects `07h`. Bits `3:0` close the EGA status retrace window. | Implemented protection is covered by EGA-207/EGA-208; retrace-window timing still needs EGA-302 validation. |
| `12h` | Vertical Display End Low | `R18_v_display_end_e`. | Stored/readable and used in EGA display-end formula with overflow bit `07h[6]`. | Covered by EGA-302. |
| `13h` | Offset | `R19_offset_e`; row advance is `R19_offset_e << 1`, or `R19_offset_e << 2` when `09h[7]` is set. | Stored/readable. Nonzero value enables the EGA row-address path. | Covered by EGA-304. |
| `14h` | Underline Location / Address Mode | `R20_underline_loc_e`; exported as `crtc_r14_debug`. | Stored/readable. Bit `6` selects dword display-address remap. | Underline is later text-render work. |
| `15h` | Vertical Blank Start | `R21_v_blank_start_e`; exported as `crtc_r15_debug`. | Stored/readable. Used for EGA vertical blank start if extended timing is active. | Needs blanking/status coverage in EGA-302/EGA-307. |
| `16h` | Vertical Blank End | `R22_v_blank_end_e`; exported as `crtc_r16_debug`. | Stored/readable. Used for EGA vertical blank end if nonzero. | Needs blanking/status coverage in EGA-302/EGA-307. |
| `17h` | Mode Control | `R23_mode_control_e`; exported as `crtc_r17_debug`. | Stored/readable. Bits `0`, `1`, `5`, and `6` control display-address remap and scanline substitution. | Bit `7` reset/display-disable blanking remains EGA-307. |
| `18h` | Line Compare | `R24_line_compare_e`; readback defaults to `FFh` on reset. | Stored/readable. Current split target uses `{09h[6], 07h[4], 18h} + 1`; split resets saved/current address and scanline to page 0. | Covered by EGA-306. |

## Derived Behavior Checklist

### Write Protection

- Implemented: indexes `00h..06h` ignore data writes while `11h[7]` is set.
- Implemented: index `07h` preserves all bits except bit `4` while `11h[7]`
  is set.
- Covered by: EGA-207 and `ega_registers_tb.sv` from EGA-208.

### Vertical Timing Formulas

Expected x86Box formulas from `SPEC.md`:

- `vtotal = {07h[5], 07h[0], 06h} + 2`
- `dispend = {07h[6], 07h[1], 12h} + 1`
- `vsyncstart = {07h[7], 07h[2], 10h} + 1`
- `split = {09h[6], 07h[4], 18h} + 1`

Current active RTL formulas:

- `eff_v_total = {07h[5], 07h[0], 06h} + 2`
- `eff_v_displayed = {07h[6], 07h[1], 12h} + 1`
- `eff_v_sync_pos = {07h[7], 07h[2], 10h} + 1`
- `line_compare_target = {09h[6], 07h[4], 18h} + 1`

Formula coverage is assigned to EGA-302; split address/scanline side effects
remain assigned to EGA-306.

### Display Address Remap

Expected x86Box remap inputs:

- `14h[6]`: dword mode.
- `17h[6]`: byte mode.
- `17h[5]`: word mode using MA15 on cards larger than 64 KiB.
- Default: word mode using MA13.
- `17h[0]`: if clear, replace MA13 with `scanline[0]`.
- `17h[1]`: if clear, replace MA14 with `scanline[1]`.

Current RTL:

- Emits `MA_FULL = ega_display_addr`, where EGA mode uses the remapped
  independent-plane VRAM address and non-EGA mode preserves `row_addr_r`.
- In EGA row-address mode, increments `row_addr_r` by one CRTC character and
  advances saved row address by `13h << 1` at row boundaries, or `13h << 2`
  when CRTC `09h[7]` line-doubling is set.
- Applies `14h`/`17h` remap modes to `row_addr_r << 2`, converts the resulting
  x86Box interleaved byte address back to the independent-plane VRAM address
  exported as `MA_FULL`, and applies row-scanline MA13/MA14 substitution.

Covered by EGA-303.

### Start Address And Frame Latch

Current RTL:

- Writes to `0Ch/0Dh` update `start_addr_latch` immediately.
- In EGA row-address mode, `frame_new` reloads `row_addr` and `row_addr_r` from
  `start_addr_latch`.
- `start_addr_frame` tracks the visible EGA frame start and updates only on
  `frame_new`, so first-row reloads in the non-row-address fallback path keep
  the current frame address after mid-frame writes.
- `cursor_addr_frame` applies the same frame-boundary rule to EGA cursor
  address compares.

Remaining text cursor scope:

- Future cursor-render tasks still need to validate text cursor shape, blink,
  and disable behavior.

### Split / Line Compare

Current RTL:

- Compares `frame_scanline_cnt` against `{09h[6], 07h[4], 18h} + 1`.
- In EGA row-address mode, split reset has priority over the normal scanout
  address increment and resets both `row_addr` and `row_addr_r` to zero.
- Split also resets the CRTC scanline counter to zero, matching the base
  x86Box page-0 split behavior.

Deferred behavior:

- The x86Box interlace odd/even exception (`rowoffset << 1`) is not implemented
  yet because the current EGA scanout path does not model that interlace mode.
- Verify behavior when split occurs outside or at the visible range.

Out-of-visible-range coverage is assigned to EGA-308.

### CRTC Reset / Display Disable

Expected x86Box behavior:

- CRTC `17h[7]` clear causes render paths to read zeros or output black instead
  of live VRAM data.

Current RTL:

- `R23_mode_control_e[7]` is stored but not used by the EGA graphics/text render
  path or fetch path.

Missing behavior is assigned to EGA-307.

## Task Coverage

- EGA-302: overflow-bit formulas, vertical timing, horizontal displayed/sync
  representative cases, and retrace-window validation.
- EGA-303: scanout address remap controlled by CRTC `14h` and `17h`, separate
  from CPU VRAM remap.
- EGA-304: row advance, maximum scan line, and text/graphics row stepping.
- EGA-305: start-address and cursor-address frame latching.
- EGA-306: split/line compare, including `07h[4]`, `09h[6]`, and reset effects.
- EGA-307: CRTC `17h[7]` reset/display-disable blanking behavior.
- EGA-308: deterministic CRTC/address testbench coverage for remap variants,
  row advance, frame latching, split reset, sampled counters, blanking, and
  display-enable outputs.
