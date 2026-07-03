# EGA Clean Core Plan

This plan turns `EGA_CLEAN_CORE_SPEC.md` into an implementation roadmap for the
single-video EGA core refactor.

The target is a clean EGA-centered PCXT MiSTer variant:

- EGA is the only active video hardware model.
- CGA compatibility is implemented inside the EGA model.
- Standalone CGA, HGC, and Tandy video paths are removed from this branch.
- `EGA Gate` disappears as a user-facing and functional concept.
- `MCGA Gate`, if introduced, is an inert placeholder for future work.

The plan is intentionally phased. Each phase should leave the tree buildable and
should be committed separately unless a dependency makes that impossible.

## 1. Working Rules

- Do not preserve standalone CGA/HGC/Tandy behavior in this branch.
- Do preserve CGA-compatible software behavior through EGA.
- Prefer removing video-card muxing over adding more conditions around it.
- Do not use `cga.v` as an EGA fallback once Phase 2 starts.
- Keep the splash, text, graphics, sync, blanking, and OSD signals owned by EGA.
- Track temporary compatibility shims as migration debt and remove them before
  declaring completion.

## 2. Phase Overview

| Phase | Name | Main Outcome |
| --- | --- | --- |
| 0 | Baseline And Recovery | Known-good behavior and recovery bitstream are recorded. |
| 1 | Configuration And Gate Cleanup | EGA becomes the always-on video target; old gate semantics are removed. |
| 2 | EGA Native CGA Compatibility | CGA-compatible behavior needed by games is moved into EGA-owned modules. |
| 3 | Remove `cga_passthrough` | `ega_top` no longer instantiates or depends on `cga.v`. |
| 4 | Collapse `Peripherals.sv` Video Mux | Bus, VRAM, RGB, sync, and OSD wiring become EGA-only. |
| 5 | Remove HGC/Tandy/CGA Compile Paths | Dead modules, QIP/QSF entries, macros, and menu options are removed. |
| 6 | Verification Expansion | Tests and smoke checks prove EGA and CGA-compatible behavior. |
| 7 | Documentation And Final Cleanup | Docs, comments, and remaining migration debt are closed. |

## 3. Phase 0: Baseline And Recovery

### Purpose

Freeze the known-good state before removing video coexistence paths.

### Likely Files

- `EGA_SMOKE_CHECKLIST.md`
- `EGA_TESTBENCH_INVENTORY.md`
- New or existing smoke notes under the repository root
- External `.rbf` or `.sof` artifacts outside git, if desired

### Tasks

- Record the current commit hash used as the clean-refactor starting point.
- Record the current working `.sof` and `.rbf` artifact names and timestamps.
- Capture screenshots or notes for:
  - Cold boot with EGA BIOS.
  - Splash through EGA.
  - EGA text after reset.
  - At least one EGA graphics game.
  - At least two CGA-compatible games running through EGA.
- Record current OSD resolution reports for those cases.
- Run the available focused testbenches and document known failures.

### Acceptance

- A baseline document exists and identifies the recovery artifact.
- The current EGA splash, text, graphics, and CGA-compatible behavior are
  documented.
- Known simulator limitations are listed so later failures are not mistaken for
  new regressions.

### Verification

- `git status --short` confirms only intentional documentation changes.
- `git diff --check` passes.

## 4. Phase 1: Configuration And Gate Cleanup

### Purpose

Make EGA the only active video target and remove the old runtime gate model.

### Likely Files

- Project `.qsf` files that define video macros.
- `rtl/KFPC-XT/HDL/Peripherals.sv`
- Top-level status/menu definition files.
- Any OSD config strings that expose `EGA Gate`, CGA, HGC, or Tandy options.

### Tasks

- Remove user-facing `EGA Gate` selection.
- Make EGA logically always enabled.
- Add `MCGA Gate` only if it is needed as a reserved UI placeholder; it must not
  affect RTL behavior.
- Remove runtime dependencies on toggling EGA on/off.
- Hard-code or remove old video macro assumptions where this does not yet break
  build structure.
- Document any temporarily retained macro as migration debt.

### Acceptance

- Boot no longer depends on enabling EGA through a runtime gate.
- EGA BIOS still runs.
- Splash still renders through EGA.
- OSD no longer presents functional CGA/HGC/Tandy/EGA selection controls.

### Verification

- Cold boot smoke test.
- Reset smoke test.
- EGA text smoke test.
- `rg "EGA Gate"` has no active implementation references.

## 5. Phase 2: EGA Native CGA Compatibility

### Purpose

Identify and port CGA-compatible behavior currently supplied by the standalone
CGA path into EGA-owned code before deleting the fallback.

### Likely Files

- `rtl/video/ega_top.v`
- `rtl/video/ega_pixel.v`
- `rtl/video/ega_text.v`
- `rtl/video/ega_attrib_ctrl.v`
- `rtl/video/ega_gfx_ctrl.v`
- `rtl/video/ega_sequencer.v`
- `rtl/video/UM6845R.v`
- `rtl/video/ega_vram.v`
- `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`

### Tasks

- Audit every signal currently taken from `cga_passthrough` in `ega_top`.
- Classify each signal as:
  - Already EGA-owned.
  - Needs an EGA default.
  - Needs a CGA-compatible EGA mode implementation.
  - Should be removed.
- Ensure EGA owns reset/default timings for pre-BIOS and inactive periods.
- Ensure EGA graphics supports the CGA-compatible 2bpp render mode without
  delegating to CGA.
- Ensure EGA text supports CGA-compatible text behavior through EGA VRAM.
- Ensure B8000-style software behavior maps through EGA memory decode.
- Add or rename helpers with EGA ownership names, such as `ega_cga_compat_*`,
  only when that makes the boundary clearer.

### Acceptance

- CGA-compatible games still render when the standalone CGA display path is not
  selected.
- No splash, boot, or inactive display behavior depends on CGA.
- EGA-owned modules have clear responsibility for compatibility behavior.

### Verification

- Focused EGA graphics tests.
- Focused EGA text tests.
- EGA VRAM tests or directed checks for B8000-compatible access.
- Game smoke tests for representative CGA-compatible titles.

## 6. Phase 3: Remove `cga_passthrough`

### Purpose

Make `ega_top` independent from `cga.v`.

### Likely Files

- `rtl/video/ega_top.v`
- `rtl/video/video.qip`
- EGA testbenches that instantiate `ega_top`

### Tasks

- Remove the `cga cga_passthrough` instance from `ega_top`.
- Replace `cga_clkdiv`, `cga_bus_*`, `cga_ram_*`, `cga_hsync`, `cga_vsync`,
  `cga_blank`, `cga_video`, and mode fallback signals with EGA-owned signals.
- Decide whether `clkdiv` remains a generic EGA timing output or is renamed.
- Remove CGA bus fallback from EGA I/O read muxing.
- Make inactive display output explicit in EGA.
- Update testbench wiring for removed passthrough behavior.

### Acceptance

- `rtl/video/ega_top.v` no longer instantiates `cga`.
- `ega_top` elaborates without CGA sources, except for any intentionally shared
  generic asset such as a font ROM.
- EGA text and graphics still work.
- CGA-compatible games still work through EGA.

### Verification

- Icarus or Quartus analysis for `ega_top` without CGA modules, where possible.
- EGA text and graphics focused testbenches.
- Cold boot and reset smoke tests.
- CGA-compatible game smoke tests.

## 7. Phase 4: Collapse `Peripherals.sv` Video Mux

### Purpose

Stop wiring multiple video devices into the PCXT bus and VGA output.

### Likely Files

- `rtl/KFPC-XT/HDL/Peripherals.sv`
- `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`
- Top-level VGA/status wiring

### Tasks

- Remove CGA VRAM instantiation.
- Remove HGC VRAM instantiation.
- Remove Tandy video banking from the active path.
- Remove `swap_video` behavior if it only selects removed hardware.
- Route VGA RGB, sync, blanking, display enable, and OSD status directly from
  EGA.
- Route video memory access through the EGA VRAM frontend only.
- Route video I/O through EGA-owned decode only.
- Remove CGA/HGC/Tandy bus-ready paths once no longer used.

### Acceptance

- `Peripherals.sv` is no longer a video-card mux.
- No separate CGA/HGC/Tandy VRAM is instantiated.
- OSD receives EGA-owned resolution/sync data.
- Splash still renders through EGA.

### Verification

- Quartus analysis or full build.
- Cold boot smoke test.
- EGA text and graphics smoke tests.
- CGA-compatible game smoke tests.
- OSD resolution checks.

## 8. Phase 5: Remove HGC/Tandy/CGA Compile Paths

### Purpose

Delete or stop compiling old video hardware paths and obsolete configuration.

### Likely Files

- Project `.qsf` files.
- `rtl/video/video.qip`
- `files.qip`
- `rtl/video/cga*.v`
- `rtl/video/cga*.sv`
- HGC video files.
- Tandy-specific video/audio/keyboard files or references.
- Menu/status/config files.
- Documentation that describes the old active variant model.

### Tasks

- Remove obsolete QIP/QSF assignments for removed video modules.
- Remove active references to:
  - `ENABLE_CGA`
  - `ENABLE_HGC`
  - `ENABLE_TANDY_VIDEO`
  - `ENABLE_TANDY_AUDIO`
  - `ENABLE_TANDY_KBD`
  - `SYSTEM_VARIANT_TANDY`
  - `ROM_VARIANT_TANDY`
- Remove menu strings and status bits for removed video hardware.
- Delete old video modules if they are no longer referenced and are not kept as
  historical documentation.
- Rename or document any generic survivor that previously had a CGA/HGC/Tandy
  name.

### Acceptance

- Build files do not compile standalone CGA/HGC/Tandy video modules.
- Active RTL does not branch on removed video macros.
- User-facing config no longer exposes removed video hardware.
- `MCGA Gate`, if present, is clearly inert.

### Verification

- `rg "ENABLE_CGA|ENABLE_HGC|ENABLE_TANDY_VIDEO|ENABLE_TANDY_AUDIO|ENABLE_TANDY_KBD|SYSTEM_VARIANT_TANDY|ROM_VARIANT_TANDY"`
  returns no active implementation references.
- `rg "cga_passthrough|swap_video|hgc_|tandy_video"` returns no active
  references except intentional documentation or renamed generic assets.
- Quartus analysis or full build.

## 9. Phase 6: Verification Expansion

### Purpose

Replace confidence previously provided by old hardware paths with deterministic
EGA-owned tests and smoke coverage.

### Likely Files

- `rtl/KFPC-XT/TESTBENCH/`
- `EGA_SMOKE_CHECKLIST.md`
- `EGA_TESTBENCH_INVENTORY.md`
- `TEST_TOOLS.md`
- New clean-core verification notes

### Tasks

- Add or update tests for:
  - EGA VRAM B8000-compatible access.
  - EGA text rendering.
  - EGA graphics planar rendering.
  - EGA CGA-compatible 2bpp rendering.
  - CRTC default and programmed timing behavior.
  - Splash through EGA VRAM.
  - OSD-visible sync and blanking assumptions where testable.
- Build a smoke matrix with representative software:
  - BIOS cold boot.
  - DOS prompt/text.
  - EGA graphics title.
  - CGA-compatible title using text.
  - CGA-compatible title using graphics.
  - Reset after boot.

### Acceptance

- The smoke matrix covers both EGA-native and CGA-compatible behavior.
- Known simulator limitations are explicitly documented.
- Regressions in CGA-compatible EGA behavior can be caught without reinstating
  standalone CGA.

### Verification

- Focused testbench suite passes, except documented pre-existing blockers.
- Full build succeeds.
- Smoke matrix is updated after hardware testing.

## 10. Phase 7: Documentation And Final Cleanup

### Purpose

Make the repository reflect the new single-video architecture.

### Likely Files

- `README.md`
- `SPEC.md`
- `PLAN.md`, if superseded or amended.
- `EGA_TRACEABILITY.md`
- `EGA_CLEAN_CORE_SPEC.md`
- `EGA_CLEAN_CORE_PLAN.md`
- Any audit files whose assumptions changed.

### Tasks

- Mark old coexistence assumptions as superseded for this branch.
- Update architecture documentation to state that EGA is the only video model.
- Record intentional deviations from old CGA/HGC/Tandy behavior.
- Remove stale comments that describe active CGA/HGC/Tandy selection.
- Add final grep checkpoints to the documentation.

### Acceptance

- Documentation no longer implies that this branch preserves multi-video-card
  coexistence.
- Remaining references to CGA describe EGA compatibility, not standalone CGA
  hardware.
- The completion criteria from `EGA_CLEAN_CORE_SPEC.md` are all satisfied.

### Verification

- Documentation review.
- `git diff --check`.
- Final full build.
- Final hardware smoke pass.

## 11. Cross-Phase Checkpoints

Run these checks at the end of every phase:

```powershell
git status --short
git diff --check
rg "cga_passthrough|ENABLE_CGA|ENABLE_HGC|ENABLE_TANDY_VIDEO|EGA Gate"
```

Run these when touching EGA rendering or VRAM:

```powershell
iverilog -g2012 -I rtl/video -o $env:TEMP\ega_text_tb.vvp rtl/KFPC-XT/TESTBENCH/ega_text_tb.sv rtl/video/ega_text.v
vvp $env:TEMP\ega_text_tb.vvp

iverilog -g2012 -I rtl/video -o $env:TEMP\ega_pixel_tb.vvp rtl/KFPC-XT/TESTBENCH/ega_pixel_tb.sv rtl/video/ega_pixel.v rtl/video/ega_attrib_ctrl.v
vvp $env:TEMP\ega_pixel_tb.vvp
```

Run these when touching CRTC or display timing:

```powershell
iverilog -g2012 -I rtl/video -o $env:TEMP\ega_crtc_vertical_tb.vvp rtl/KFPC-XT/TESTBENCH/ega_crtc_vertical_tb.sv rtl/video/UM6845R.v
vvp $env:TEMP\ega_crtc_vertical_tb.vvp
```

Known limitation: some integrated Icarus runs may fail on pre-existing
SystemVerilog support issues in older modules. Such failures must be recorded
with the exact command and output, not silently ignored.

## 12. Definition Of Done

The clean EGA core refactor is done when:

- EGA is always present and is the only active video hardware model.
- CGA-compatible software runs through EGA-owned compatibility behavior.
- `ega_top` does not instantiate or depend on `cga.v`.
- `Peripherals.sv` no longer multiplexes CGA/HGC/Tandy video devices.
- Standalone CGA/HGC/Tandy modules are not compiled or instantiated.
- Old video macros and menu options are removed from active implementation.
- `EGA Gate` no longer exists in active implementation.
- `MCGA Gate`, if present, is a documented no-op.
- Splash, EGA text, EGA graphics, and CGA-compatible games pass hardware smoke
  checks through the EGA path.
