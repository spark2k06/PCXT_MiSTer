# EGA Smoke Checklist

This checklist defines the minimum visual smoke set for EGA release-candidate
runs. It is not a substitute for deterministic register, VRAM, CRTC, or pixel
testbenches; it is the final platform-level check that BIOS-visible behavior,
video mode programming, scanout, palette, and non-EGA coexistence still work
together.

## Local Assets

| Asset | Purpose | Availability |
| --- | --- | --- |
| `egabios.rom` | EGA BIOS option ROM and mode-programming smoke path. | Present in repository root. |
| `egabios.asm` | Source reference for the minimal EGA BIOS path. | Present in repository root. |
| `games/PCXT/hd_image.zip` | Existing PCXT disk-image smoke asset. | Present under `games/PCXT/`. |

If a named game is not inside `games/PCXT/hd_image.zip`, prepare a separate
test image and record its exact source, checksum, and launch command in the run
log. Do not treat an untracked local disk image as reproducible evidence.

## Minimum Smoke Matrix

| ID | Case | Setup | Expected Visual Properties | Primary Failure Class |
| --- | --- | --- | --- | --- |
| `SMOKE-BIOS-EGA` | EGA BIOS boot/probe | Boot with `egabios.rom` enabled. | System reaches DOS or the configured boot path without corrupt text, snow-like planar artifacts, or hangs during video probe. | Integration, register, CPU memory |
| `SMOKE-TEXT-03` | DOS text mode `03h` | Boot DOS text from the PCXT disk image. | 80-column text is stable, cursor location is coherent, attributes do not bleed between characters, and CGA/HGC/Tandy modes are not selected accidentally. | Text, scanout, integration |
| `SMOKE-EGA-0D` | EGA mode `0Dh` 320x200x16 | Use `egabios.asm`/BIOS mode set or a small DOS mode-set helper. | 320-wide graphics are centered, four EGA planes combine into 16 visible color indices, palette changes affect colors without changing geometry, and sprite/filled-area writes do not show stale latch data. | CPU memory, register, palette, scanout |
| `SMOKE-EGA-0E` | EGA mode `0Eh` 640x200x16 | Use a direct register-programming helper if BIOS does not expose the mode. | 640-wide graphics have double horizontal resolution versus `0Dh`, no every-other-pixel loss, and the same palette entries map consistently. | Scanout, palette, register |
| `SMOKE-EGA-10` | EGA mode `10h` 640x350x16 | Use a direct register-programming helper if BIOS does not expose the mode. | 350-line graphics are vertically stable, no bottom wrap occurs, CRTC overflow bits produce the expected height, and start address remains frame-latched. | CRTC, scanout, palette |
| `SMOKE-GAME-PREHISTORIK` | Known EGA game probe | Run Prehistorik from a recorded disk image. | EGA detection succeeds, INT `11h` equipment probing does not select a wrong adapter, mode `0Dh` starts, palette is plausible, and planar sprite writes do not leave masks or wrong colors. | Register, CPU memory, palette |
| `SMOKE-GAME-SCROLL` | Smooth EGA scrolling game | Run a documented EGA scroller from a recorded disk image. | Horizontal panning and start-address changes are smooth, no byte-boundary shimmer appears, and split-screen/status areas stay anchored. | CRTC, scanout, register |
| `SMOKE-GAME-MASKED` | Masked sprite game | Run a documented EGA sprite-heavy game from a recorded disk image. | Sprites preserve backgrounds, transparent regions remain transparent, and repeated movement does not accumulate plane corruption. | CPU memory, register |
| `SMOKE-CGA-BASE` | Non-EGA CGA regression | Boot or run a known CGA mode from the PCXT disk image with EGA disabled or bypassed. | CGA output uses the expected memory aperture and colors; EGA decode must not steal CGA VRAM or I/O. | Integration, CPU memory |
| `SMOKE-HGC-TANDY` | Non-EGA HGC/Tandy regression | Run one existing HGC or Tandy smoke case where configured. | The selected non-EGA adapter still produces its expected text/graphics output without EGA register side effects. | Integration |

## Failure Classification

Use one primary class per observed failure, then add secondary tags only when
needed:

| Class | Use When |
| --- | --- |
| CPU memory | Wrong VRAM aperture, plane selection, latch behavior, write mode, read mode, mask, or ROP effect. |
| Register | I/O port visibility, index/data readback, flip-flop, write protection, status side effect, or mode-programming state is wrong. |
| CRTC | Timing, overflow bits, start address, cursor address, split/line compare, panning source, or frame latching is wrong. |
| Scanout | Correct VRAM data exists but pixels are shifted, missing, wrapped, blanked incorrectly, or fetched from the wrong display address. |
| Palette | Color index is correct but RGB/intensity/overscan/palette indirection is wrong. |
| Text | Character glyph, font plane, attribute, underline, cursor, blink, or 9th-dot behavior is wrong. |
| Integration | Adapter selection, BIOS ROM loading, menu/config wiring, reset, coexistence, or non-EGA decode is wrong. |

## Run Log Requirements

Each smoke run should record:

- Git commit and branch.
- Quartus build or A&E status.
- Disk image or game image path and checksum.
- BIOS ROM path and checksum.
- Exact launch/programming steps.
- Result for every `SMOKE-*` row: `pass`, `fail`, `blocked`, or `not run`.
- One screenshot or capture per failed visual case when practical.
- Primary failure class and follow-up task ID for each failure.

## Clean-Core Baseline Run: ECC-002

This baseline must be collected on MiSTer hardware before using it as pass/fail
evidence for the clean EGA refactor. It is intentionally recorded as pending in
this repository because this development session cannot execute hardware smoke
tests.

- Branch: `ega-mcga-clean-core`.
- Starting commit: `8d1c719fe2a5d78d19e711cdeec842d6b9c129a8`.
- Recovery artifact: `D:\GitHub\PCXT_MiSTer\output_files\PCXT_EGATEST9.rbf`.
- Companion SOF: `D:\GitHub\PCXT_MiSTer\output_files\PCXT.sof`.

| Case | Required Observation | Baseline Status | Notes |
| --- | --- | --- | --- |
| Cold boot with EGA BIOS | Boot reaches the expected DOS or configured boot path. | `blocked` | Requires MiSTer hardware run. |
| Splash through EGA | Splash is visible and stable through the EGA path. | `blocked` | Requires MiSTer hardware run and screenshot/capture. |
| EGA text after reset | Mode `03h` text is stable after reset. | `blocked` | Requires MiSTer hardware run. |
| EGA graphics title | At least one EGA graphics title renders correctly. | `blocked` | Record title, image checksum, and OSD mode. |
| CGA-compatible title 1 through EGA | A CGA-era graphics or text title renders through EGA compatibility. | `blocked` | Record title, image checksum, and OSD mode. |
| CGA-compatible title 2 through EGA | A second CGA-era title renders through EGA compatibility. | `blocked` | Record title, image checksum, and OSD mode. |

Hardware access check performed from `D:\GitHub\PCXT_MiSTer`:

```powershell
$env:INTELFPGA_ROOT='C:\intelFPGA_lite\17.0'
$env:QUARTUS_ROOTDIR="$env:INTELFPGA_ROOT\quartus"
$env:PATH="$env:QUARTUS_ROOTDIR\bin64;$env:PATH"
jtagconfig
```

Result:

```text
No JTAG hardware available
```

This blocks collecting the `ECC-002` hardware smoke baseline in this session.
`ECC-101` is intentionally not started because it depends on `ECC-002`.

## Release-Candidate Minimum

A release-candidate run is not complete until:

1. `SMOKE-BIOS-EGA`, `SMOKE-TEXT-03`, `SMOKE-EGA-0D`, `SMOKE-EGA-0E`, and
   `SMOKE-EGA-10` have explicit pass/fail results.
2. At least one known EGA game case has a result.
3. At least one CGA/HGC/Tandy non-regression case has a result.
4. Every failure is classified and linked to an EGA task or a new follow-up.
