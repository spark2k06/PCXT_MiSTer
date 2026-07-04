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
MCGA13TSR.COM
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
nasm -O9 -f bin -o mcga13tsr.com mcga13tsr.asm
nasm -O9 -f bin -o mcga13chk.com mcga13chk.asm
```

Expected current binary sizes:

- `mcga13tsr.com`: 521 bytes.
- `mcga13chk.com`: 253 bytes.

Smoke test sequence inside DOS:

```bat
MCGA13TSR.COM
MCGA13CHK.COM
```

`mcga13chk.com` returns DOS exit code `0` only after mode reporting, pixel
write/read, and one DAC entry write/read pass.
