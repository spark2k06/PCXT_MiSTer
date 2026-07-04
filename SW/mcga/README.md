# MCGA Mode 13h TSR

`mcga13tsr.com` is a development DOS TSR for MCGA mode `13h` bring-up with the
unmodified IBM EGA option ROM.

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

Build commands:

```bat
nasm -O9 -f bin -o mcga13tsr.com mcga13tsr.asm
nasm -O9 -f bin -o mcga13chk.com mcga13chk.asm
```

DOS test sequence:

```bat
MCGA13TSR.COM
MCGA13CHK.COM
```

The `03CDh` control port is a development hook, not a final VGA-compatible
hardware interface.
