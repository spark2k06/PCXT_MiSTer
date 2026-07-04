# MCGA Mode 13h Game/Demo Smoke

Date: 2026-07-04

## Candidate

The local mode `13h` visual demo is `mcga13ramp.com`.

It is a DOS `.COM` program that:

- Calls `INT 10h AX=0013h`.
- Programs 256 DAC entries through `INT 10h AX=1010h`.
- Fills `A000:0000` with a packed 8bpp color ramp.
- Waits for one key through `INT 16h`.
- Returns to text mode with `INT 10h AX=0003h`.

## Intended Smoke Procedure

Run inside DOS on the PCXT_MiSTer core with MCGA Gate enabled:

```bat
MCGA13TSR.COM
MCGA13CHK.COM
MCGA13RAMP.COM
```

Expected result:

- `MCGA13CHK.COM` prints `MCGA13CHK OK` and exits with code `0`.
- `MCGA13RAMP.COM` switches to a 320x200 packed 256-color screen.
- The visible image is a repeated horizontal 256-color ramp.
- Pressing one key returns to text mode.

## Current Session Result

The smoke was not executed visually in this session.

Available checks:

- The demo and TSR binaries rebuild reproducibly with NASM.
- RTL EGA/MCGA regression is recorded in `REGRESSION.md`.

Environment blockers:

- No local `dosbox`, `dosbox-x`, `qemu-system-i386`, or `qemu-system-x86_64`
  command was available from PowerShell.
- The WSL emulator probe did not return before timeout.
- No interactive MiSTer/DOS visual session is attached to this workspace.

This leaves the visual game/demo smoke pending for hardware, MiSTer, or a DOS
emulator run. The exact command sequence and expected visual result are defined
above.
