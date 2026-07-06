# MCGA Mode 13h Delivery

## Decision

The MCGA mode `13h` BIOS extension is delivered as a DOS `.COM` TSR for this
branch.

The IBM EGA option ROM remains unmodified. The older `egabios.rom` development
image is not part of this path.

## User-Facing Path

For a DOS environment that should run mode `13h` software, load the TSR before
starting the program:

```bat
MCGATSR.COM
```

For a bootable DOS image intended to work out of the box, add the TSR to the
image and load it from `AUTOEXEC.BAT` before launching shells, menus, demos, or
games that may call `INT 10h`.

## Tradeoffs

Bundled TSR:

- Keeps the IBM EGA ROM original and avoids maintaining a patched ROM fork.
- Is reproducible with NASM as a small binary artifact.
- Can be installed or removed from DOS images without rebuilding the FPGA core.
- Requires DOS startup integration before mode `13h` programs run.
- Does not cover software that needs the hook before `AUTOEXEC.BAT` or before a
  DOS device driver could run.

Chained option ROM:

- Would be visible earlier than a TSR.
- Would need an option-ROM build, checksum, address allocation, and ROM loading
  path in the core.
- Is deferred until there is a demonstrated compatibility need that the TSR
  cannot cover.

Patched IBM EGA ROM:

- Would provide the earliest integration point.
- Would fork a known-good IBM ROM image and complicate provenance and rebuilds.
- Is not used for this branch.

## Reproducible Artifacts

Build the TSR and its smoke test from source:

```bat
nasm -O9 -f bin -o mcgatsr.com mcgatsr.asm
nasm -O9 -f bin -o mcgachk.com mcgachk.asm
nasm -O9 -f bin -o mcgaramp.com mcgaramp.asm
nasm -O9 -f bin -o mcgabar.com mcgabar.asm
```

Expected current binary sizes:

- `mcgatsr.com`: 561 bytes.
- `mcgachk.com`: 318 bytes.
- `mcgaramp.com`: 85 bytes.
- `mcgabar.com`: 217 bytes.

Smoke test sequence inside DOS:

```bat
MCGATSR.COM
MCGACHK.COM
MCGABAR.COM
```

`mcgachk.com` returns DOS exit code `0` only after display detection, mode
reporting, pixel write/read, and one DAC entry write/read pass.
