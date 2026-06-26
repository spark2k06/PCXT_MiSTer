# EGA Attribute Controller Audit

This audit covers EGA-203 against `SPEC.md` sections 3.2 and 4.4, using
`rtl/video/ega_attrib_ctrl.v` and its integration in `rtl/video/ega_top.v`.

## Required Flip-Flop Behavior

The Attribute Controller address/data flip-flop is implemented by
`address_phase`:

- Reset initializes `address_phase` to address phase.
- A rising `status_re` pulse sets `address_phase` back to address phase.
- A write pulse to `3C0h` / `2C0h` toggles `address_phase`.
- In address phase, the write stores `io_data_in[4:0]` as `attr_index`.
- In data phase, the write stores `io_data_in` into the selected Attribute
  Controller register.

The status reset path is connected in `ega_top.v` through:

```verilog
.status_re(ega_status_cs & ~bus_ior_l)
```

After EGA-202, `ega_status_cs` follows Misc Output bit `0`, so the flip-flop
reset is driven by the active color or mono Input Status #1 port.

## Video Enable Bit

Index-phase writes preserve bit `5` as `video_enable_reg`. That state is
exported as `video_enable_out` and also gates active display output through
`display_enable_out`.

## Register Readback

Reads from `3C1h` / `2C1h` return the currently selected Attribute Controller
register:

- `00h..0Fh`: palette registers.
- `10h`: Mode Control.
- `11h`: Overscan/Border Color.
- `12h`: Color Plane Enable.
- `13h`: Horizontal Pixel Panning.
- `14h`: Color Select.

The readback mux is gated by `io_re && attr_read_cs`, so the Attribute
Controller does not drive unrelated reads.

## Expected Programming Sequence

A deterministic register test can prove EGA-203 with this sequence:

1. Read active Input Status #1 to force address phase.
2. Write `3C0h = 20h | 01h`; this selects palette index `01h` and keeps video
   enabled.
3. Write `3C0h = 2Ah`; this stores palette register `01h`.
4. Write `3C0h = 20h | 02h`; this selects palette index `02h`.
5. Write `3C0h = 15h`; this stores palette register `02h`.
6. Read active Input Status #1 again to force address phase.
7. Write `3C0h = 20h | 01h`, then read `3C1h`; expected value is `2Ah`.
8. Write `3C0h = 20h | 02h`, then read `3C1h`; expected value is `15h`.

This proves two register writes, status-read flip-flop reset, and selected
readback. EGA-208 should encode this sequence in an executable register
testbench once the register-test harness exists.

## Remaining Out Of Scope Items

The following Attribute Controller behaviors are intentionally covered by
later tasks rather than EGA-203:

- Full graphics/text Mode Control rendering effects.
- Blink/intensity behavior.
- Mono text attributes.
- 9th-dot line-graphics behavior.
- Complete horizontal panning timing.
