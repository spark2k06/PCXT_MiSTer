# EGA Clean Core Task Backlog

This file turns `EGA_CLEAN_CORE_SPEC.md` and `EGA_CLEAN_CORE_PLAN.md` into an
implementation backlog for the clean EGA-only video refactor.

The technical source of truth is `EGA_CLEAN_CORE_SPEC.md`. The sequencing source
of truth is `EGA_CLEAN_CORE_PLAN.md`.

## Status Legend

- `[ ]`: not started.
- `[~]`: in progress.
- `[x]`: complete.
- `[!]`: blocked by an explicit dependency or open question.

## Priority Legend

- `P0`: required before removing any active fallback or gate.
- `P1`: required for the clean EGA core to be considered complete.
- `P2`: documentation, cleanup, or later hardening work.

## Global Definition Of Done

A task is complete only when all relevant checks below are true:

- The behavior matches `EGA_CLEAN_CORE_SPEC.md`.
- The change keeps CGA-compatible software running through the EGA model.
- The change does not reintroduce a standalone CGA/HGC/Tandy runtime path.
- Deterministic tests or hardware smoke notes cover the changed behavior.
- Temporary migration shims are either removed or tracked by a later task.
- `git diff --check` passes.

## Milestone Gates

### CCM0: Baseline And Recovery

- Current working EGA behavior is documented.
- Recovery `.sof` or `.rbf` artifact is identified outside git.
- Known simulator limitations are recorded.

### CCM1: EGA Always-On Configuration

- `EGA Gate` is gone from active behavior.
- EGA BIOS and EGA splash still boot.
- Any `MCGA Gate` surface is explicitly inert.

### CCM2: Native EGA CGA Compatibility

- CGA-compatible modes run through EGA-owned logic.
- No splash, boot, inactive display, or game rendering path depends on `cga.v`.

### CCM3: No CGA Passthrough

- `ega_top` does not instantiate `cga`.
- `ega_top` elaborates without standalone CGA modules.

### CCM4: EGA-Only PCXT Video Integration

- `Peripherals.sv` is no longer a CGA/HGC/Tandy/EGA video mux.
- Only EGA owns active video memory, I/O, RGB, sync, blanking, and OSD output.

### CCM5: Dead Paths Removed

- Standalone CGA/HGC/Tandy modules are no longer compiled or instantiated.
- Old video feature macros and menu options are gone from active code.

### CCM6: Verification Complete

- Focused tests and hardware smoke checks cover EGA-native and CGA-compatible
  behavior.
- Documentation reflects the single-video architecture.

## Dependency Summary

```text
ECC-000..099 baseline and recovery
  -> ECC-100..199 configuration and gate cleanup
      -> ECC-200..299 native EGA CGA compatibility
          -> ECC-300..399 remove cga_passthrough
              -> ECC-400..499 collapse Peripherals video mux
                  -> ECC-500..599 remove dead compile paths
                      -> ECC-600..699 verification expansion
                          -> ECC-700..799 documentation and final cleanup
```

## ECC-000: Baseline And Recovery

### ECC-001 - Record Clean-Core Starting Point

- Status: `[x]`
- Priority: `P0`
- Depends on: none.
- Files: `EGA_CLEAN_CORE_PLAN.md`, new baseline notes if needed.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 0.
- Work:
  - Record the commit hash used as the clean-core starting point.
  - Record the current branch name.
  - Record the latest known-good `.sof` or `.rbf` artifact outside git.
- Acceptance:
  - The starting commit and recovery artifact are documented.
  - The artifact location is explicit enough to recover hardware testing.

### ECC-002 - Capture Current Hardware Smoke Baseline

- Status: `[!]`
- Priority: `P0`
- Depends on: `ECC-001`.
- Files: `EGA_SMOKE_CHECKLIST.md` or a new clean-core smoke note.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 0.
- Work:
  - Record cold boot behavior with EGA BIOS.
  - Record splash through EGA.
  - Record EGA text after reset.
  - Record at least one EGA graphics title.
  - Record at least two CGA-compatible titles running through EGA.
  - Record OSD resolution reports for each case.
- Acceptance:
  - Baseline smoke behavior is documented with enough detail to compare later
    regressions.
  - Any known visual defect is explicitly listed.

### ECC-003 - Record Current Focused Test Status

- Status: `[x]`
- Priority: `P0`
- Depends on: `ECC-001`.
- Files: `EGA_TESTBENCH_INVENTORY.md`, `TEST_TOOLS.md`.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 0.
- Work:
  - Run available focused EGA testbenches.
  - Record passing tests.
  - Record pre-existing simulator or testbench blockers.
  - Include exact commands for failures that are kept as known limitations.
- Acceptance:
  - There is a current test status snapshot before removing fallback paths.
  - Known failures are not ambiguous.

## ECC-100: Configuration And Gate Cleanup

### ECC-101 - Remove User-Facing EGA Gate

- Status: `[x]`
- Priority: `P0`
- Depends on: `ECC-002`.
- Files: project config/menu files, `rtl/KFPC-XT/HDL/Peripherals.sv`.
- Source: `EGA_CLEAN_CORE_SPEC.md` sections 1 and 4.
- Work:
  - Remove the functional `EGA Gate` user option.
  - Make EGA logically always active for this branch.
  - Remove reset or boot paths that depend on toggling EGA on.
- Acceptance:
  - Cold boot no longer depends on an EGA enable option.
  - `rg "EGA Gate"` has no active implementation references.
  - EGA BIOS still boots.

### ECC-102 - Add Inert MCGA Gate Placeholder If Needed

- Status: `[x]`
- Priority: `P2`
- Depends on: `ECC-101`.
- Files: project config/menu files.
- Source: `EGA_CLEAN_CORE_SPEC.md` sections 1 and 4.
- Work:
  - Add `MCGA Gate` only if a future UI placeholder is desired.
  - Ensure it has no RTL effect.
  - Document it as reserved future work.
- Acceptance:
  - Toggling `MCGA Gate` does not change hardware behavior.
  - The placeholder is documented as inert.
- Result:
  - No `MCGA Gate` placeholder was added because no current UI or RTL surface
    needs it.
  - `rg "MCGA|M-CGA|mcga"` shows only clean-core planning documentation and
    the branch/baseline name; there is no active hardware behavior to gate.

### ECC-103 - Hard-Code EGA Video Selection

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-101`.
- Files: `rtl/KFPC-XT/HDL/Peripherals.sv`, project `.qsf` files.
- Source: `EGA_CLEAN_CORE_SPEC.md` section 4.
- Work:
  - Remove runtime decisions that choose CGA/HGC/Tandy over EGA.
  - Keep temporary macros only where required for incremental buildability.
  - Add follow-up notes for any retained macro.
- Acceptance:
  - EGA is the only selected active video path.
  - Any remaining old video macro is listed as migration debt.

## ECC-200: Native EGA CGA Compatibility

### ECC-201 - Audit `ega_top` CGA Passthrough Dependencies

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-103`.
- Files: `rtl/video/ega_top.v`, new audit notes if needed.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 2.
- Work:
  - List every signal sourced from `cga_passthrough`.
  - Classify each signal as EGA-owned, needs EGA default, needs
    CGA-compatible EGA implementation, or removable.
  - Identify the minimum implementation needed before deleting `cga_passthrough`.
- Acceptance:
  - Every `cga_passthrough` dependency has a planned replacement or deletion.
  - No Phase 3 removal starts with unknown signal ownership.

### ECC-202 - Move Pre-BIOS Defaults Into EGA

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-201`.
- Files: `rtl/video/ega_top.v`, `rtl/video/UM6845R.v`, `rtl/video/ega_sequencer.v`.
- Source: `EGA_CLEAN_CORE_SPEC.md` sections 5.1 and 7.2.
- Work:
  - Ensure reset/default timings are EGA-owned.
  - Ensure inactive display output is explicit in EGA.
  - Ensure splash and boot text do not require CGA fallback timing.
- Acceptance:
  - Cold boot and reset produce stable EGA-owned sync.
  - OSD resolution does not depend on CGA fallback.

### ECC-203 - Verify EGA-Owned CGA-Compatible 2bpp Graphics

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-201`.
- Files: `rtl/video/ega_pixel.v`, `rtl/video/ega_gfx_ctrl.v`,
  `rtl/video/ega_attrib_ctrl.v`, `rtl/KFPC-XT/TESTBENCH/`.
- Source: `EGA_CLEAN_CORE_SPEC.md` section 3.
- Work:
  - Confirm CGA-compatible 2bpp render mode is generated by EGA logic.
  - Add or update focused tests around 2bpp EGA rendering.
  - Smoke test at least one CGA-compatible graphics title through EGA.
- Acceptance:
  - CGA-compatible graphics do not require `cga_pixel.sv`.
  - Focused or hardware evidence covers the 2bpp path.

### ECC-204 - Verify EGA-Owned CGA-Compatible Text

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-201`.
- Files: `rtl/video/ega_text.v`, `rtl/video/ega_vram.v`,
  `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`.
- Source: `EGA_CLEAN_CORE_SPEC.md` sections 3 and 7.3.
- Work:
  - Confirm text cell and attribute fetches come from EGA-owned memory.
  - Confirm font behavior is correct after BIOS font loading.
  - Keep splash fallback font limited to pre-BIOS splash behavior.
  - Smoke test one CGA-compatible text-mode program through EGA.
- Acceptance:
  - Text does not require CGA VRAM or `cga_pixel.sv`.
  - EGA BIOS text remains stable after reset.

### ECC-205 - Verify B8000-Compatible Access Through EGA VRAM

- Status: `[ ]`
- Priority: `P1`
- Depends on: `ECC-203`, `ECC-204`.
- Files: `rtl/KFPC-XT/HDL/Peripherals.sv`, `rtl/video/ega_vram.v`,
  `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`.
- Source: `EGA_CLEAN_CORE_SPEC.md` section 3.
- Work:
  - Confirm B8000-style software accesses are handled by EGA memory decode.
  - Add directed checks for relevant memory-map and odd/even behavior.
  - Document any required BIOS or register setup assumptions.
- Acceptance:
  - CGA-compatible software reaches EGA VRAM without standalone CGA RAM.
  - Directed tests or hardware smoke notes cover the path.

## ECC-300: Remove `cga_passthrough`

### ECC-301 - Remove CGA Instance From `ega_top`

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-202`, `ECC-203`, `ECC-204`.
- Files: `rtl/video/ega_top.v`.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 3.
- Work:
  - Delete the `cga cga_passthrough` instance.
  - Replace `cga_*` fallback wires with EGA-owned signals.
  - Remove CGA bus read fallback from the EGA top-level mux.
- Acceptance:
  - `rg "cga_passthrough" rtl/video/ega_top.v` returns no matches.
  - `ega_top` does not require `cga.v` to elaborate.

### ECC-302 - Replace CGA-Derived Clock And Mode Outputs

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-301`.
- Files: `rtl/video/ega_top.v`, consumers of `clkdiv`, `grph_mode`, `hres_mode`.
- Source: `EGA_CLEAN_CORE_SPEC.md` section 7.2.
- Work:
  - Make `clkdiv` an EGA-owned timing output or replace it with a clearer
    interface.
  - Ensure `grph_mode`, `hres_mode`, and related status outputs come from EGA.
  - Remove mode fallback to old CGA status.
- Acceptance:
  - Mode/status outputs remain stable for OSD and downstream logic.
  - No `cga_*` mode output remains in `ega_top`.

### ECC-303 - Prove `ega_top` Builds Without CGA Sources

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-301`, `ECC-302`.
- Files: `rtl/video/ega_top.v`, test or build scripts.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 3.
- Work:
  - Run Icarus analysis or Quartus analysis without standalone CGA modules.
  - Record any simulator limitation separately from RTL errors.
- Acceptance:
  - `ega_top` has no dependency on `cga.v`, `cga_pixel.sv`,
    `cga_sequencer.v`, `cga_attrib.v`, `cga_vgaport.v`, or
    `cga_composite.v`.

## ECC-400: Collapse `Peripherals.sv` Video Mux

### ECC-401 - Remove CGA VRAM Path From `Peripherals.sv`

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-303`, `ECC-205`.
- Files: `rtl/KFPC-XT/HDL/Peripherals.sv`.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 4.
- Work:
  - Remove CGA VRAM instantiation and copy/clear paths that target CGA.
  - Route all active video memory behavior through the EGA VRAM frontend.
  - Keep splash path EGA-owned.
- Acceptance:
  - No CGA VRAM instance remains.
  - Splash still renders through EGA.
  - CGA-compatible titles still render through EGA.

### ECC-402 - Remove HGC VRAM And Video Path

- Status: `[ ]`
- Priority: `P1`
- Depends on: `ECC-401`.
- Files: `rtl/KFPC-XT/HDL/Peripherals.sv`, HGC build references.
- Source: `EGA_CLEAN_CORE_SPEC.md` sections 2 and 6.
- Work:
  - Remove HGC instance and HGC VRAM instance from active wiring.
  - Remove HGC RGB/sync muxing.
  - Remove HGC bus-ready and status paths.
- Acceptance:
  - No active HGC module is instantiated.
  - VGA output is not muxed with HGC.

### ECC-403 - Remove Tandy Video Banking From Active Path

- Status: `[ ]`
- Priority: `P1`
- Depends on: `ECC-401`.
- Files: `rtl/KFPC-XT/HDL/Peripherals.sv`, Tandy config references.
- Source: `EGA_CLEAN_CORE_SPEC.md` sections 2 and 6.
- Work:
  - Remove Tandy video page banking from active video memory paths.
  - Remove Tandy-specific CGA path assumptions.
  - Track Tandy audio and keyboard removal separately if they are still active.
- Acceptance:
  - Active video memory paths no longer branch on Tandy video state.
  - `ENABLE_TANDY_VIDEO` is no longer needed for active video logic.

### ECC-404 - Route VGA And OSD Signals Directly From EGA

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-401`, `ECC-402`.
- Files: `rtl/KFPC-XT/HDL/Peripherals.sv`.
- Source: `EGA_CLEAN_CORE_SPEC.md` section 7.5.
- Work:
  - Route RGB, sync, blanking, display enable, resolution, and status outputs
    from EGA only.
  - Remove `swap_video` if it only applies to removed hardware.
- Acceptance:
  - OSD observes EGA-owned sync and blanking.
  - No old video mux selects VGA output.

## ECC-500: Remove Dead Compile Paths

### ECC-501 - Remove Obsolete Video Macros From Project Config

- Status: `[ ]`
- Priority: `P1`
- Depends on: `ECC-404`.
- Files: project `.qsf` files, `files.qip`, `rtl/video/video.qip`.
- Source: `EGA_CLEAN_CORE_SPEC.md` section 4.
- Work:
  - Remove active uses of old video macros from build configuration.
  - Remove or hard-code any remaining configuration values that only selected
    removed hardware.
- Acceptance:
  - Old video macros are not required to build the clean EGA core.

### ECC-502 - Stop Compiling Standalone CGA Modules

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-303`, `ECC-401`.
- Files: `rtl/video/video.qip`, `files.qip`, CGA module files.
- Source: `EGA_CLEAN_CORE_SPEC.md` section 6.
- Work:
  - Remove standalone CGA module assignments from active build files.
  - Delete CGA files if desired after verifying no active references remain.
  - Preserve or rename generic assets only when still needed by EGA.
- Acceptance:
  - Build files do not compile standalone CGA modules.
  - `rg "module cga\\b|cga_passthrough"` returns no active implementation use.

### ECC-503 - Stop Compiling HGC Modules

- Status: `[ ]`
- Priority: `P1`
- Depends on: `ECC-402`.
- Files: `rtl/video/video.qip`, `files.qip`, HGC module files.
- Source: `EGA_CLEAN_CORE_SPEC.md` section 6.
- Work:
  - Remove HGC assignments from active build files.
  - Delete HGC files if desired after verifying no active references remain.
- Acceptance:
  - Build files do not compile HGC modules.
  - No active HGC references remain in RTL.

### ECC-504 - Remove Tandy Variant Compile And Menu Paths

- Status: `[ ]`
- Priority: `P1`
- Depends on: `ECC-403`.
- Files: project `.qsf` files, menu/status/config files, Tandy-specific RTL.
- Source: `EGA_CLEAN_CORE_SPEC.md` sections 2 and 4.
- Work:
  - Remove active `SYSTEM_VARIANT_TANDY`, `ROM_VARIANT_TANDY`,
    `ENABLE_TANDY_VIDEO`, `ENABLE_TANDY_AUDIO`, and `ENABLE_TANDY_KBD`
    references.
  - Remove user-facing Tandy variant controls.
- Acceptance:
  - Tandy variant macros are not needed for this branch.
  - User-facing config no longer exposes Tandy hardware.

### ECC-505 - Remove Dead `ifdef` Branches

- Status: `[ ]`
- Priority: `P1`
- Depends on: `ECC-501`, `ECC-502`, `ECC-503`, `ECC-504`.
- Files: RTL files touched by prior phases.
- Source: `EGA_CLEAN_CORE_SPEC.md` section 5.4.
- Work:
  - Remove old conditional compilation blocks for deleted video hardware.
  - Simplify wiring that was only needed for coexistence.
  - Keep one clear EGA path.
- Acceptance:
  - Active RTL is not structured as a multi-video-card build.
  - `rg "ENABLE_CGA|ENABLE_HGC|ENABLE_TANDY_VIDEO"` returns no active
    implementation references.

## ECC-600: Verification Expansion

### ECC-601 - Add Clean-Core Smoke Matrix

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-404`.
- Files: new smoke matrix document or `EGA_SMOKE_CHECKLIST.md`.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 6.
- Work:
  - Define required boot, text, EGA graphics, CGA-compatible text, and
    CGA-compatible graphics smoke cases.
  - Record pass/fail status after each major phase.
- Acceptance:
  - Smoke coverage proves both EGA-native and CGA-compatible behavior.

### ECC-602 - Add B8000-Compatible EGA VRAM Tests

- Status: `[ ]`
- Priority: `P1`
- Depends on: `ECC-205`.
- Files: `rtl/KFPC-XT/TESTBENCH/`, `rtl/video/ega_vram.v`,
  `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 6.
- Work:
  - Add directed checks for B8000-compatible access through EGA decode.
  - Cover relevant odd/even, map, and text/graphics cases.
- Acceptance:
  - Regressions in CGA-compatible EGA memory access are caught by tests.

### ECC-603 - Add CGA-Compatible EGA Render Tests

- Status: `[ ]`
- Priority: `P1`
- Depends on: `ECC-203`.
- Files: `rtl/KFPC-XT/TESTBENCH/`, `rtl/video/ega_pixel.v`.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 6.
- Work:
  - Add focused tests for EGA CGA-compatible 2bpp rendering.
  - Cover palette/index output for representative byte patterns.
- Acceptance:
  - Render behavior no longer relies only on game smoke testing.

### ECC-604 - Add Splash Through EGA Regression Test

- Status: `[ ]`
- Priority: `P1`
- Depends on: `ECC-204`, `ECC-401`.
- Files: `rtl/KFPC-XT/TESTBENCH/`, `rtl/video/ega_text.v`,
  `rtl/video/ega_vram.v`.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 6.
- Work:
  - Add a persistent test for splash text writes into EGA plane 0/1.
  - Add a persistent test for splash font fallback if practical.
- Acceptance:
  - The EGA splash path is covered by committed tests.

## ECC-700: Documentation And Final Cleanup

### ECC-701 - Mark Old Coexistence Documentation As Superseded

- Status: `[ ]`
- Priority: `P2`
- Depends on: `ECC-505`.
- Files: `PLAN.md`, `EGA_TRACEABILITY.md`, coexistence audit docs.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 7.
- Work:
  - Update documents that still say CGA/HGC/Tandy behavior must be preserved.
  - Link to `EGA_CLEAN_CORE_SPEC.md` and `EGA_CLEAN_CORE_PLAN.md`.
- Acceptance:
  - Documentation no longer gives contradictory maintenance goals for this
    branch.

### ECC-702 - Update README For Clean EGA Core

- Status: `[ ]`
- Priority: `P2`
- Depends on: `ECC-505`.
- Files: `README.md`, related user-facing docs.
- Source: `EGA_CLEAN_CORE_SPEC.md` section 11.
- Work:
  - State that this branch is EGA-centered.
  - State that CGA compatibility is implemented through EGA.
  - Remove or revise references to active CGA/HGC/Tandy selection.
- Acceptance:
  - User-facing docs describe the actual clean-core behavior.

### ECC-703 - Final Grep And Build Closure

- Status: `[ ]`
- Priority: `P0`
- Depends on: `ECC-601`, `ECC-602`, `ECC-603`, `ECC-604`, `ECC-701`.
- Files: all active RTL and build files.
- Source: `EGA_CLEAN_CORE_PLAN.md` Definition Of Done.
- Work:
  - Run final grep checks for removed gates, macros, and module references.
  - Run final focused tests.
  - Run Quartus analysis or full build.
  - Record final hardware smoke results.
- Acceptance:
  - Definition of Done in `EGA_CLEAN_CORE_PLAN.md` is satisfied.
  - No active standalone CGA/HGC/Tandy path remains.
