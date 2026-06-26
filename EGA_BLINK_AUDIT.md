# EGA Blink State Audit

## Reference Behavior

x86Box keeps a 7-bit EGA blink counter and advances it at vertical display end:

- `x86_src/video/vid_ega.c`: `ega->blink = (ega->blink + 1) & 0x7f`.
- `x86_src/video/vid_ega_render.c`: text and graphics blink consumers test
  `ega->blink & 0x10`.

The practical RTL requirement is a frame-paced counter with a stable bit `4`
output that text, graphics blink, and cursor logic can share.

## RTL Implementation

`rtl/video/ega_top.v` now owns the shared blink source:

- `ega_blink_counter` is a 7-bit counter.
- `ega_vblank_crtc_q` detects the rising edge of CRTC vertical blank while
  `ega_ce_crt_fetch` is active.
- `ega_blink_counter` increments once per detected CRTC vertical blank entry.
- `ega_blink_state_out` exposes `ega_blink_counter[4]`.
- `ega_blink_counter_out` exposes the full counter for deterministic tests.
- Reset and `!ega_enabled` clear the counter and edge detector.

`rtl/KFPC-XT/HDL/Peripherals.sv` wires the two outputs internally as
`ega_blink_counter` and `ega_blink_state`, making the state available to future
graphics and text render paths.

`rtl/video/ega_attrib_ctrl.v` consumes `ega_blink_state` for graphics pixels.
When Attribute Mode Control bit `3` is set, it applies the x86Box graphics
blink formula from `x86_src/video/vid_ega_render.c` before Attribute Controller
palette indirection:

```text
blinkmask = attrblink ? 8 : 0
blinkval = attrblink && blinked ? 8 : 0
color = ((color & plane_mask & ~blinkmask) |
         ((color | ~plane_mask) & blinkmask & blinkval)) ^ blinkmask
```

`plane_mask` maps to Attribute Controller register `12h[3:0]`, already stored
as `plane_enable_reg`.

## Remaining Consumers

Graphics blink is implemented. Follow-up tasks must still consume
`ega_blink_state` in the remaining places that depend on Attribute Mode Control
bit `3` or CRTC cursor blink timing:

- Text foreground/background blink.
- Cursor blink delay behavior.

## Deterministic Test Targets

When a simulator is available, register or render tests should prove:

1. Counter resets to `0` on reset and while EGA is disabled.
2. Counter advances once, not per pixel, when CRTC vertical blank becomes active.
3. `ega_blink_state_out` follows counter bit `4`.
4. Text and graphics consumers use the same blink state.
