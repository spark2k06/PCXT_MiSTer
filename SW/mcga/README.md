# MCGA Mode 13h TSR

`mcga13tsr.com` is a development DOS TSR for MCGA mode `13h` bring-up with the
unmodified IBM EGA option ROM.

The TSR keeps `40h` paragraphs resident. Do not use older builds that kept only
`20h` paragraphs resident; those can be overwritten by later DOS programs and
leave the `INT 10h` hook corrupted.

See `DELIVERY.md` for the selected integration path and tradeoffs. See
`COMPATIBILITY.md` for supported behavior and limits. See `REGRESSION.md` for
the current EGA/MCGA regression log. See `SMOKE.md` for the mode `13h` visual
smoke procedure and current run status. See `QUARTUS_BUILD.md` for the latest
full-build result.

It hooks `INT 10h` and handles:

- `AX=0013h`: enables the RTL mode `13h` path through temporary port `03CDh`
  and updates the BIOS Data Area for `320x200x256`.
- `AH=0Fh`: reports mode `13h` while the TSR-owned mode is active.
- `AH=0Ch`: writes one mode `13h` pixel to page 0.
- `AH=0Dh`: reads one mode `13h` pixel from page 0.
- `AX=1010h`/`1012h`: writes one DAC entry or a DAC block.
- `AX=1015h`/`1017h`: reads one DAC entry or a DAC block.
- Any other `AH=00h` mode set: clears the temporary RTL mode `13h` path and
  chains to the existing video BIOS.

`mcga13chk.com` is a DOS smoke test for the TSR. It sets mode `13h`, checks
`AH=0Fh`, validates `AH=0Ch`/`0Dh` pixel write/read, checks one DAC entry, and
returns to text mode.

`mcga13ramp.com` is a visual DOS smoke program. It sets mode `13h`, programs a
256-entry DAC ramp through `INT 10h`, fills `A000:0000` with a packed color
ramp, waits for one key, and returns to text mode.

`mcga13bar.com` is a simpler diagnostic. It sets mode `13h`, verifies
`INT 10h AH=0Fh` reports `AL=13h`, programs the DAC through
`INT 10h AX=1010h`, and draws 64 vertical bars from a 4x4x4 RGB cube directly
into `A000:0000`. If the TSR does not report mode `13h`, it returns to text
mode and prints an error.

Build commands:

```bat
nasm -O9 -f bin -o mcga13tsr.com mcga13tsr.asm
nasm -O9 -f bin -o mcga13chk.com mcga13chk.asm
nasm -O9 -f bin -o mcga13ramp.com mcga13ramp.asm
nasm -O9 -f bin -o mcga13bar.com mcga13bar.asm
```

DOS test sequence:

```bat
MCGA13TSR.COM
MCGA13CHK.COM
MCGA13BAR.COM
MCGA13RAMP.COM
```

The `03CDh` control port is a development hook, not a final VGA-compatible
hardware interface.
