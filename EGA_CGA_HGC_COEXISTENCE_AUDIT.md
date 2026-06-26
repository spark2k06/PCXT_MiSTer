# EGA / CGA / HGC / Tandy Coexistence Audit

## Scope

This audit rechecks the legacy video memory decode and output mux paths after
the EGA integration work. It focuses on preserving non-EGA behavior when EGA is
disabled and on documenting which device owns overlapping video apertures when
EGA is enabled.

Reviewed files:

- `rtl/KFPC-XT/HDL/Peripherals.sv`
- `PCXT.sv`
- `rtl/video/cga.v`
- `rtl/video/hgc.v`

## Memory Decode Priority

`Peripherals.sv` computes EGA VRAM selection as:

- `ENABLE_EGA` must be set at synthesis time.
- `ega_enabled` must be set by the runtime menu/status path.
- `enable_cga` must be active.
- The CPU cycle must be a memory cycle.
- `ega_memory_window_select(address, ega_mem_map_sel_cfg)` must match the
  Graphics Controller Misc memory-map selection.

When any of those conditions is false, `ega_mem_select` is `0`.

The legacy memory selects are all explicitly masked by `~ega_mem_select`:

- Tandy 128 KiB video window: `video_mem_select`
- CGA `B8000h-BFFFFh`: `cga_mem_select`
- HGC page-selected `B0000h-BFFFFh`: `hgc_mem_select`

This preserves legacy video memory access when EGA is disabled. When EGA is
enabled and its selected aperture overlaps legacy video memory, EGA has
intentional priority.

## CPU Read Priority

The CPU data-bus readback priority in `Peripherals.sv` is:

1. EGA VRAM when `ega_mem_select` is active.
2. CGA VRAM when `cga_mem_select` is active.
3. HGC VRAM when `hgc_mem_select` is active.
4. CGA/HGC CRTC I/O readbacks.

Because CGA/Tandy/HGC memory selects are already masked by `~ega_mem_select`,
the bus priority is consistent with the decode priority and does not create a
second conflicting owner.

## CGA And Tandy Path

The CGA/Tandy VRAM path remains enabled by `ENABLE_CGA`. Its CPU port is driven
by either splash copy, `cga_mem_select_1`, or `video_mem_select_1`.

For Tandy video:

- CPU writes use the Tandy-specific `video_mem_select` path when the Tandy
  window is active.
- The Tandy page register logic remains inside `cga_vram_addra`.
- EGA only masks the Tandy window when EGA is enabled and its current aperture
  selects the same CPU address range.

For CGA:

- The base `B8000h-BFFFFh` decode is unchanged except for the intentional
  `~ega_mem_select` guard.
- With `ega_enabled = 0`, that guard is inactive and CGA owns `B8000h-BFFFFh`
  as before.

## HGC Path

The HGC VRAM path remains enabled by `ENABLE_HGC` and `hgc_enable`. Its decode
uses the selected HGC graphics page in `B0000h-BFFFFh` and is masked by
`~ega_mem_select`.

With `ega_enabled = 0`, HGC owns its configured page as before. With EGA enabled
and mapped over `B0000h-B7FFFh` or the full `A0000h-BFFFFh` aperture, EGA has
priority, which matches the intended mutually exclusive video-memory ownership
for overlapping hardware.

## Output Mux

`Peripherals.sv` selects HGC output first when the HGC swap path is active. If
HGC is not selected, EGA RGB is used only when `ega_rgb_active` is true;
otherwise the normal CGA/Tandy path drives RGB.

The CGA module receives `cga_hw & ~ega_display_sel_cga` only when EGA support is
compiled in. If EGA is disabled at runtime, `ega_display_sel_cga` remains false,
so the CGA hardware path is not suppressed.

## Result

The current decode and muxing preserve non-EGA CGA, Tandy, and HGC behavior when
EGA is disabled. When EGA is enabled, overlapping memory apertures are resolved
by a single explicit priority: EGA first, then CGA/Tandy/HGC.

No RTL change is required for EGA-702. Platform smoke coverage should still boot
at least one CGA/Tandy mode and one HGC configuration after the EGA work, because
this audit is static and does not replace end-to-end video validation on the
target core.
