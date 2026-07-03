# MCGA Mode 13h Smoke Targets

This file supports `MCGA-003` from `MCGA_GATE_MODE13_TASKS.md`.

The repository currently does not include a known DOS game or VGA/MCGA demo
that exercises packed mode `13h`. The first smoke targets are therefore local,
reproducible DOS `.COM` programs to be added when `MCGA-701` is implemented.

## Target 1: Minimal Deterministic Test

- Program name: `MCGA13T.COM`
- Planned source path: `SW/MCGA/mcga13t.asm`
- Planned binary path: `SW/MCGA/mcga13t.com`
- CPU target: 8088-compatible real mode.
- Dependencies: BIOS `INT 10h`, direct writes to `A000:0000`, DAC ports
  `03C8h/03C9h`.

Expected sequence:

1. Save current video mode with `INT 10h AH=0Fh`.
2. Set mode `13h` with `INT 10h AX=0013h`.
3. Verify current mode reports `AL=13h` through `INT 10h AH=0Fh`.
4. Program a 256-entry DAC ramp through `03C8h/03C9h`.
5. Fill `A000:0000` with `pixel = x[7:0]` for every visible pixel.
6. Draw a few fixed sentinels:
   - top-left pixel `A000:0000 = 00h`;
   - top-right visible pixel `A000:013Fh = 3Fh`;
   - bottom-left visible pixel `A000:F8C0h = C0h`;
   - last visible pixel `A000:F9FFh = FFh`;
   - first non-visible byte `A000:FA00h = 5Ah`.
7. Read back representative framebuffer bytes and report pass/fail by writing a
   text byte pattern before returning to text mode.
8. Return to text mode `03h`.

Expected visual output:

- A stable 320x200 screen.
- Horizontal 256-color ramp repeated across each row.
- No visible effect from the byte written at offset `FA00h`.
- Return to text mode without corrupting the EGA-owned path.

Exit path:

- Wait for one keypress.
- Restore mode `03h`.
- Exit to DOS with `INT 21h AH=4Ch`.

## Target 2: Visual Demo Smoke

- Program name: `MCGA13D.COM`
- Planned source path: `SW/MCGA/mcga13d.asm`
- Planned binary path: `SW/MCGA/mcga13d.com`
- CPU target: 8088-compatible real mode.
- Dependencies: BIOS `INT 10h`, direct writes to `A000:0000`, DAC ports
  `03C7h/03C8h/03C9h`, optional keyboard polling.

Expected sequence:

1. Set mode `13h` with `INT 10h AX=0013h`.
2. Draw a static indexed pattern that covers:
   - all 256 palette entries;
   - horizontal and vertical edges;
   - diagonal address progression across multiple scanlines.
3. Animate the DAC palette only, leaving framebuffer bytes unchanged.
4. Read back one DAC entry through `03C7h/03C9h` and use a visible marker if it
   does not match the last programmed value.
5. Exit on keypress and restore mode `03h`.

Expected visual output:

- A stable full-screen indexed-color pattern.
- Smooth palette cycling without tearing the framebuffer contents.
- Correct screen edges with no wrap at the 64,000-byte visible boundary.

Exit path:

- Poll keyboard with BIOS `INT 16h`.
- Restore mode `03h`.
- Exit to DOS with `INT 21h AH=4Ch`.

## Later External Game Or Demo Candidate

After the local `.COM` tests pass, add one external game/demo smoke only if it
meets all of these constraints:

- can legally be obtained by the tester;
- is small enough to run on the PCXT core's CPU and memory configuration, or its
  higher CPU requirement is explicitly documented;
- uses BIOS `INT 10h AX=0013h` or direct mode `13h` VGA/MCGA programming;
- draws primarily through packed `A000:0000` bytes and DAC ports, not SVGA/VBE;
- has a deterministic first screen that can be visually described.

The preferred first external candidate class is a small public-domain or
shareware VGA mode `13h` demo, not a protected-mode game. Record the exact title,
version, source URL or media provenance, launch command, expected first screen,
and exit path before using it as a release smoke.

## Smoke Checklist Entries

| ID | Target | Purpose | Expected Result |
| --- | --- | --- | --- |
| `SMOKE-MCGA13-RAMP` | `MCGA13T.COM` | BIOS mode set, packed framebuffer, DAC ramp, visible boundary. | Ramp renders, readback passes, text mode returns. |
| `SMOKE-MCGA13-DEMO` | `MCGA13D.COM` | Sustained visible mode `13h` output and DAC animation. | Pattern remains stable, palette cycles, text mode returns. |
| `SMOKE-MCGA13-EXT` | External demo/game candidate | Compatibility beyond local tests. | Exact result recorded with title/version/provenance. |
