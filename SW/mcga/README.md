# MCGA Mode 13h TSR

`mcgatsr.com` is a development DOS TSR for MCGA mode `13h` bring-up with the
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
- `AH=12h`/`BL=10h`: reports EGA/VGA-style adapter information for old
  display detection code.
- `AX=1A00h`: reports a VGA color display-combination code so games that
  probe for VGA/MCGA before setting mode `13h` can continue.
- `AH=0Ch`: writes one mode `13h` pixel to page 0.
- `AH=0Dh`: reads one mode `13h` pixel from page 0.
- `AX=1010h`/`1012h`: writes one DAC entry or a DAC block.
- `AX=1015h`/`1017h`: reads one DAC entry or a DAC block.
- Any other `AH=00h` mode set: clears the temporary RTL mode `13h` path and
  chains to the existing video BIOS.

`mcgachk.com` is a DOS smoke test for the TSR. It checks display detection,
sets mode `13h`, checks `AH=0Fh`, validates `AH=0Ch`/`0Dh` pixel write/read,
checks one DAC entry, and returns to text mode.

`mcgaramp.com` is a visual DOS smoke program. It sets mode `13h`, programs a
256-entry DAC ramp through `INT 10h`, fills `A000:0000` with a packed color
ramp, waits for one key, and returns to text mode.

`mcgabar.com` is a simpler diagnostic. It sets mode `13h`, verifies
`INT 10h AH=0Fh` reports `AL=13h`, programs the DAC through
`INT 10h AX=1010h`, and draws 64 vertical bars from a 4x4x4 RGB cube directly
into `A000:0000`. If the TSR does not report mode `13h`, it returns to text
mode and prints an error.

Build commands:

```bat
nasm -O9 -f bin -o mcgatsr.com mcgatsr.asm
nasm -O9 -f bin -o mcgachk.com mcgachk.asm
nasm -O9 -f bin -o mcgaramp.com mcgaramp.asm
nasm -O9 -f bin -o mcgabar.com mcgabar.asm
```

DOS test sequence:

```bat
MCGATSR.COM
MCGACHK.COM
MCGABAR.COM
MCGARAMP.COM
```

The `03CDh` control port is a development hook, not a final VGA-compatible
hardware interface.
