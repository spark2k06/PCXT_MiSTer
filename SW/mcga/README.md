# MCGA Mode 13h TSR

`mcga13tsr.com` is a development DOS TSR for MCGA mode `13h` bring-up with the
unmodified IBM EGA option ROM.

It hooks `INT 10h` and handles:

- `AX=0013h`: enables the RTL mode `13h` path through temporary port `03CDh`
  and updates the BIOS Data Area for `320x200x256`.
- `AH=0Fh`: reports mode `13h` while the TSR-owned mode is active.
- Any other `AH=00h` mode set: clears the temporary RTL mode `13h` path and
  chains to the existing video BIOS.

Build command:

```bat
nasm -O9 -f bin -o mcga13tsr.com mcga13tsr.asm
```

The `03CDh` control port is a development hook, not a final VGA-compatible
hardware interface.
