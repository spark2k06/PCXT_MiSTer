# MCGA Mode 13h Compatibility

## Supported Behavior

Mode `13h` is selected only after the TSR or BIOS control path requests it.
Until then, the normal EGA-compatible path remains active.

With `MCGATSR.COM` installed, the current target is:

- BIOS mode set: `INT 10h AX=0013h`.
- Mode report while active: `INT 10h AH=0Fh` returns `AL=13h`, `AH=40`,
  `BH=0`.
- Display detection helpers: `INT 10h AX=1A00h` reports VGA color display
  combination code `08h`; `INT 10h AH=12h`/`BL=10h` reports 256 KB of
  EGA/VGA-style video memory.
- Packed framebuffer: `A000:0000`, one byte per pixel, 320x200, 64,000 bytes.
- Pixel BIOS helpers: `INT 10h AH=0Ch` write pixel and `AH=0Dh` read pixel for
  page 0.
- DAC ports: `03C7h`, `03C8h`, and `03C9h` with 6-bit RGB components and
  component/index auto-increment behavior.
- BIOS DAC helpers in the TSR: `AX=1010h`, `1012h`, `1015h`, and `1017h`.
- Return to normal EGA/text modes by calling another `INT 10h AH=00h` mode set;
  the TSR clears the temporary MCGA mode control port and chains to the IBM EGA
  ROM.

## Delivery Limits

The IBM EGA option ROM is not modified. The mode `13h` BIOS extension is
provided by `MCGATSR.COM`.

Consequences:

- Programs started before the TSR is loaded do not see mode `13h` support.
- Boot-time software does not see mode `13h` support.
- DOS images intended to work out of the box must load `MCGATSR.COM` from
  `AUTOEXEC.BAT` before launching mode `13h` software.
- A future option ROM or device-driver path may be needed if a real program
  needs the hook earlier than `AUTOEXEC.BAT`.

## Unsupported VGA/SVGA Behavior

This is not a full VGA implementation. The following are not compatibility
claims for this branch:

- SVGA or VBE modes.
- VGA mode X or planar VGA 256-color modes.
- VGA text mode `03h` as a separate VGA text pipeline.
- Undocumented VGA behavior outside the mode `13h` path.
- Full VGA register compatibility for all sequencer, graphics controller, CRTC,
  attribute controller, and miscellaneous-output registers.
- Software that relies on probing VGA hardware beyond the BIOS detection calls
  listed above before using BIOS mode `13h`.

Existing EGA register behavior remains owned by the EGA implementation. MCGA
mode `13h` adds the packed framebuffer and DAC behavior needed by common
BIOS-driven mode `13h` software, but it does not make the core a general VGA
card.

## Current Verification Limits

- RTL EGA/MCGA regression is recorded in `REGRESSION.md`.
- The DOS `.COM` artifacts rebuild reproducibly.
- Visual smoke procedure is documented in `SMOKE.md`, but was not run in this
  workspace because no DOS emulator or interactive MiSTer session was attached.
- Full Quartus compile currently fails before bitstream generation; see
  `QUARTUS_BUILD.md`.
