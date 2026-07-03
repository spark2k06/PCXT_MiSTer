# EGA Smoke Checklist

This checklist defines the minimum visual smoke set for EGA release-candidate
runs. It is not a substitute for deterministic register, VRAM, CRTC, or pixel
testbenches; it is the final platform-level check that BIOS-visible behavior,
video mode programming, scanout, palette, and CGA-compatible EGA behavior still
work together.

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
| `SMOKE-TEXT-03` | DOS text mode `03h` | Boot DOS text from the PCXT disk image. | 80-column text is stable, cursor location is coherent, attributes do not bleed between characters, and the EGA path owns the displayed output. | Text, scanout, integration |
| `SMOKE-EGA-0D` | EGA mode `0Dh` 320x200x16 | Use `egabios.asm`/BIOS mode set or a small DOS mode-set helper. | 320-wide graphics are centered, four EGA planes combine into 16 visible color indices, palette changes affect colors without changing geometry, and sprite/filled-area writes do not show stale latch data. | CPU memory, register, palette, scanout |
| `SMOKE-EGA-0E` | EGA mode `0Eh` 640x200x16 | Use a direct register-programming helper if BIOS does not expose the mode. | 640-wide graphics have double horizontal resolution versus `0Dh`, no every-other-pixel loss, and the same palette entries map consistently. | Scanout, palette, register |
| `SMOKE-EGA-10` | EGA mode `10h` 640x350x16 | Use a direct register-programming helper if BIOS does not expose the mode. | 350-line graphics are vertically stable, no bottom wrap occurs, CRTC overflow bits produce the expected height, and start address remains frame-latched. | CRTC, scanout, palette |
| `SMOKE-GAME-PREHISTORIK` | Known EGA game probe | Run Prehistorik from a recorded disk image. | EGA detection succeeds, INT `11h` equipment probing does not select a wrong adapter, mode `0Dh` starts, palette is plausible, and planar sprite writes do not leave masks or wrong colors. | Register, CPU memory, palette |
| `SMOKE-GAME-SCROLL` | Smooth EGA scrolling game | Run a documented EGA scroller from a recorded disk image. | Horizontal panning and start-address changes are smooth, no byte-boundary shimmer appears, and split-screen/status areas stay anchored. | CRTC, scanout, register |
| `SMOKE-GAME-MASKED` | Masked sprite game | Run a documented EGA sprite-heavy game from a recorded disk image. | Sprites preserve backgrounds, transparent regions remain transparent, and repeated movement does not accumulate plane corruption. | CPU memory, register |
| `SMOKE-CGA-TEXT-EGA` | CGA-compatible text through EGA | Run a CGA-era text program or mode-set case through the normal EGA boot path. | B8000 text remains stable through EGA ownership, 80-column layout and attributes are correct, and no standalone CGA adapter path is selected. | Text, CPU memory, integration |
| `SMOKE-CGA-GFX-EGA` | CGA-compatible graphics through EGA | Run a CGA-era graphics program that uses EGA-compatible CGA modes through the normal EGA boot path. | 2bpp pixels, palette/index mapping, memory aperture behavior, and frame timing are plausible without a separate CGA module. | CPU memory, palette, scanout |
| `SMOKE-RESET-EGA` | Reset after EGA boot | Reset after reaching DOS or a graphics smoke case. | Splash/text recovery is stable, EGA BIOS remains available, and no removed CGA/HGC/Tandy selection state is required. | Integration, CRTC |

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
Per clean-core guidance, RTL refactor tasks may continue with this smoke test
recorded as pending hardware validation.

## Clean-Core Smoke Matrix: ECC-601

This matrix supersedes the old non-EGA coexistence rows for this branch. CGA
software compatibility is validated as behavior inside the EGA model, not by
switching to a standalone CGA adapter. Hardware execution is still pending in
this development session because `jtagconfig` reports no available JTAG
hardware.

- Branch: `ega-mcga-clean-core`.
- Last RTL checkpoint before matrix creation: `9f0be9b`.
- Build check available in-session: Quartus A&E only.

| Case | Required Observation | ECC-601 Status | Notes |
| --- | --- | --- | --- |
| `SMOKE-BIOS-EGA` | EGA BIOS cold boot reaches the configured boot path. | `blocked` | Requires MiSTer hardware run. |
| `SMOKE-TEXT-03` | DOS 80-column text remains stable after boot. | `blocked` | Requires MiSTer hardware run. |
| `SMOKE-EGA-0D` | 320x200x16 EGA graphics render with correct plane/color behavior. | `blocked` | Requires MiSTer hardware run or captured DOS helper output. |
| `SMOKE-EGA-0E` | 640x200x16 EGA graphics render at the expected horizontal resolution. | `blocked` | Requires MiSTer hardware run or captured DOS helper output. |
| `SMOKE-EGA-10` | 640x350x16 EGA graphics are vertically stable. | `blocked` | Requires MiSTer hardware run or captured DOS helper output. |
| `SMOKE-GAME-PREHISTORIK` | A known EGA title detects EGA and renders plausible graphics. | `blocked` | Requires reproducible disk image and MiSTer hardware run. |
| `SMOKE-CGA-TEXT-EGA` | CGA-era text software works through EGA-owned B8000 behavior. | `blocked` | Requires MiSTer hardware run. |
| `SMOKE-CGA-GFX-EGA` | CGA-era graphics software works through EGA-owned 2bpp compatibility. | `blocked` | Requires MiSTer hardware run. |
| `SMOKE-RESET-EGA` | Reset recovers through the EGA splash/text path without video selection state. | `blocked` | Requires MiSTer hardware run. |

Post-phase status should be appended here after each hardware smoke run, using
the current commit hash, bitstream path, disk image checksum, and one result per
`SMOKE-*` row.

## Release-Candidate Minimum

A release-candidate run is not complete until:

1. `SMOKE-BIOS-EGA`, `SMOKE-TEXT-03`, `SMOKE-EGA-0D`, `SMOKE-EGA-0E`, and
   `SMOKE-EGA-10` have explicit pass/fail results.
2. At least one known EGA game case has a result.
3. At least one CGA-compatible text case and one CGA-compatible graphics case
   have results through EGA.
4. Every failure is classified and linked to an EGA task or a new follow-up.
