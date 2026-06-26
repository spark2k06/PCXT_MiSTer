# EGA Video Selection And Activation Audit

## Scope

This audit covers the PCXT integration path that decides when EGA hardware is
programmable, when EGA VRAM is selected, and when the MiSTer VGA output is
driven by EGA RGB instead of the CGA passthrough path.

Reviewed files:

- `rtl/KFPC-XT/HDL/Peripherals.sv`
- `rtl/KFPC-XT/HDL/Chipset.sv`
- `PCXT.sv`
- `rtl/video/ega_top.v`

## Memory Decode

`Peripherals.sv` uses `ega_memory_window_select(address, ega_mem_map_sel_cfg)`
for the outer EGA VRAM aperture. The implemented map matches the EGA Graphics
Controller Misc register `06h[3:2]` windows:

- `00b`: `A0000h-BFFFFh`
- `01b`: `A0000h-AFFFFh`
- `10b`: `B0000h-B7FFFh`
- `11b`: `B8000h-BFFFFh`

`ega_mem_select` requires `ega_enabled`, `enable_cga`, a memory cycle, and the
selected window. CGA/Tandy/HGC VRAM selects are explicitly masked by
`~ega_mem_select`, so an enabled EGA aperture has priority over overlapping
legacy video memory regions.

## I/O Decode Before Display Selection

`ega_top.v` gates EGA I/O decode with `ega_enabled`, `~bus_aen`, and the active
port decode, not with `ega_display_sel`.

This means BIOS or game code can program these EGA registers before EGA is the
visible output source:

- Sequencer ports `3C4h/3C5h`
- Graphics Controller ports `3CEh/3CFh`
- Attribute Controller ports `3C0h/3C1h`
- Misc Output `3C2h` write and `3CCh` read
- Color/mono selected CRTC ports
- Color/mono selected Input Status #1
- DAC stub ports

The selected status read also resets the Attribute Controller flip-flop before
EGA display activation, because `ega_status_read` is based on selected status
port decode and `ega_enabled`, not the output mux.

## Output Mux

`ega_top.v` owns the internal CGA passthrough and EGA renderer mux:

- `ega_display_sel = ega_enabled & ega_video_active`
- when false, video, sync, blanking, mode flags, and CGA bus behavior come from
  the CGA passthrough path
- when true, RGB/sync/blanking/mode flags come from the EGA path

`Peripherals.sv` then uses `ega_rgb_active` to select `R_EGA/G_EGA/B_EGA` over
the normal CGA RGB path, unless the HGC swap path is selected. The EGA top-level
also drives `ega_display_sel_out`, which is fed back to keep CGA hardware from
driving conflicting behavior once EGA is active.

## Activation Heuristic

The current EGA output activation policy is intentionally outside the EGA
hardware model:

- CPU writes to selected EGA VRAM set `ega_video_pending`.
- `ega_video_active` becomes true on a later CGA vertical blank edge only if no
  EGA write was seen during that just-finished interval.
- `ega_enabled` false clears the activation state.

This policy can delay visible EGA output, but it does not suppress EGA register
I/O, status reads, CRTC programming, or EGA VRAM CPU access. That preserves the
core requirement that BIOS can program registers and memory before the first
selected frame.

The heuristic is still a compatibility risk: software that expects immediate
visible output after programming a mode may see CGA passthrough for one or more
frames. Keep this as a PCXT output-mux policy, not as part of the EGA hardware
model. Any future change should be isolated to `ega_video_active` /
`ega_video_pending` policy and must not reintroduce display-selection gating to
I/O or memory semantics.

## Acceptance Result

EGA BIOS and game code can program EGA registers and VRAM before the first EGA
selected frame:

- I/O decode depends on `ega_enabled`, not `ega_display_sel`.
- outer memory decode depends on `ega_enabled` and GC memory-map selection, not
  visible output selection.
- output selection only affects visible RGB/sync/blanking routing and CGA
  coexistence behavior.

Remaining follow-up risk belongs to later platform smoke tasks: validate whether
the delayed activation heuristic should be shortened or made configurable after
real BIOS/game smoke coverage exists.
