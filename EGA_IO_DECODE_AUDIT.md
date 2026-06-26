# EGA I/O Decode Audit

This audit maps the port list in `SPEC.md` section 3 to the current RTL in
`rtl/video/ega_top.v`, `rtl/video/ega_attrib_ctrl.v`,
`rtl/video/ega_sequencer.v`, `rtl/video/ega_gfx_ctrl.v`, and
`rtl/KFPC-XT/HDL/Peripherals.sv`.

## Summary

The core has explicit decode for the main Attribute Controller, Sequencer,
Graphics Controller, Misc Output write/readback, CRTC/status, and DAC-stub
ports. The main gaps found by this audit are:

- `3C2h` / `2C2h` read switch-sense behavior is not implemented.
- Feature Control ports are not implemented.
- DAC ports are intentionally stubbed and return `00h` on reads.

## Port Map

| Port | Direction | Current RTL behavior | Classification |
| --- | --- | --- | --- |
| `3C0h` / `2C0h` | write | `ega_attrib_ctrl` decodes exact address and toggles index/data phase on write pulses. | Implemented |
| `3C1h` / `2C1h` | read | `ega_attrib_ctrl` decodes exact address and returns the selected Attribute Controller register. | Implemented |
| `3C2h` / `2C2h` | write | `ega_top` decodes exact address as `ega_misc_write_cs` and latches `ega_misc_output_reg`. | Implemented |
| `3C2h` / `2C2h` | read | No switch-sense read path is present. `ega_misc_read_cs` covers `3CCh` / `2CCh`, not `3C2h` / `2C2h`. | Missing |
| `3C4h` / `2C4h` | write | `ega_sequencer` decodes exact address as Sequencer index. | Implemented |
| `3C5h` / `2C5h` | read/write | `ega_sequencer` decodes exact address as Sequencer data with readback. `ega_top` includes this in bus direction. | Implemented |
| `3CCh` / `2CCh` | read | `ega_top` decodes exact address as Misc Output readback. | Implemented |
| `3CEh` / `2CEh` | write | `ega_gfx_ctrl` decodes exact address as Graphics Controller index. | Implemented |
| `3CFh` / `2CFh` | read/write | `ega_gfx_ctrl` decodes exact address as Graphics Controller data with readback. `ega_top` includes this in bus direction. | Implemented |
| `3B4h/3B5h`, `3D4h/3D5h` | read/write | `ega_top` selects mono or color CRTC index/data ports from Misc Output bit `0`. Data reads are visible by EGA enable and port decode, independent of the active display mux. | Implemented |
| `3BAh`, `3DAh` | read | `ega_top` selects mono or color status from Misc Output bit `0`. Status reads reset the Attribute Controller flip-flop, toggle bits `5:4`, and are visible independent of the active display mux. | Implemented |
| `3C7h` / `2C7h` | read | `ega_top` decodes DAC read-index address and returns `00h`. | Stubbed |
| `3C8h` / `2C8h` | read/write | `ega_top` decodes DAC write-index address and returns `00h` on reads; writes have no state. | Stubbed |
| `3C9h` / `2C9h` | read/write | `ega_top` decodes DAC data address and returns `00h` on reads; writes have no state. | Stubbed |
| Feature Control | read/write | No explicit Feature Control decode was found in the current EGA RTL. | Missing |

## Bus Direction Notes

`ega_top` drives `bus_dir` for implemented readback paths through
`ega_bus_dir_sel`. Sequencer, Attribute Controller, Misc Output readback,
Graphics Controller, and DAC-stub reads are visible whenever selected.

CRTC data and Input Status #1 reads are not gated by `ega_display_sel`; they
remain visible through the selected EGA I/O aperture even when the display mux
has not yet switched to EGA.

## Follow-Up Tasks

- EGA-203 should use the active status port read to reset the Attribute
  Controller flip-flop.
- EGA-204 should decide whether `3C2h` switch-sense reads are required or
  intentionally stubbed.
- EGA-505 removed display-selection gating from register read visibility.
