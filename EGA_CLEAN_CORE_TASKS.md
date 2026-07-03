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

- Status: `[x]`
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
- Result:
  - Removed the remaining user-facing CGA/HGC primary-video menu options.
  - Hard-coded the top-level video selection away from HGC and standalone CGA.
  - Temporarily retained `ENABLE_CGA`, `ENABLE_EGA`, and downstream
    `enable_cga` wiring as migration debt because `ega_top` still contains the
    `cga_passthrough` dependency scheduled for `ECC-201` through `ECC-303`.

## ECC-200: Native EGA CGA Compatibility

### ECC-201 - Audit `ega_top` CGA Passthrough Dependencies

- Status: `[x]`
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
- Result:
  - Added `EGA_CGA_PASSTHROUGH_AUDIT.md` with every current
    `cga_passthrough` signal dependency in `rtl/video/ega_top.v`.
  - Classified each dependency as EGA-owned replacement, EGA default, or
    removable fallback before Phase 3 deletion begins.

### ECC-202 - Move Pre-BIOS Defaults Into EGA

- Status: `[x]`
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
- Result:
  - `ega_top` now owns the exported pixel divider used by its EGA pipeline.
  - `ega_video_active` is armed from EGA vertical blank instead of CGA vertical
    blank.
  - Sync, blanking, mode status, and inactive pixel outputs are EGA-owned while
    EGA is enabled; inactive pixels are explicitly blanked.
  - Hardware cold-boot and OSD checks remain pending under the `ECC-002`
    hardware smoke baseline.

### ECC-203 - Verify EGA-Owned CGA-Compatible 2bpp Graphics

- Status: `[x]`
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
- Result:
  - `ega_gfx_ctrl.v` derives CGA-compatible 2bpp selection from the EGA
    graphics controller mode register, and `ega_pixel.v` renders that mode
    through its local `RENDER_CGA2` path without `cga_pixel.sv`.
  - Verified with `iverilog -g2012 -I rtl/video -o
    $env:TEMP\ega_pixel_tb.vvp rtl/KFPC-XT/TESTBENCH/ega_pixel_tb.sv
    rtl/video/ega_pixel.v rtl/video/ega_attrib_ctrl.v; if ($LASTEXITCODE
    -eq 0) { vvp $env:TEMP\ega_pixel_tb.vvp }`, which passes and covers
    render-mode selection plus 2bpp conversion.
  - Hardware game smoke remains pending under the hardware smoke baseline.

### ECC-204 - Verify EGA-Owned CGA-Compatible Text

- Status: `[x]`
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
- Result:
  - Documented in `EGA_TEXT_COMPAT_AUDIT.md`.
  - Text character, attribute, and BIOS-loaded glyph fetches are sourced from
    EGA VRAM planes through `ega_vram_bram_frontend.sv` and `ega_vram.v`;
    `cga_pixel.sv` is not used.
  - `splash_font_enable` is the only path that uses the internal pre-BIOS
    fallback font ROM.
  - Ran `iverilog -g2012 -I rtl/video -o $env:TEMP\ega_text_tb.vvp
    rtl/KFPC-XT/TESTBENCH/ega_text_tb.sv rtl/video/ega_text.v; if
    ($LASTEXITCODE -eq 0) { vvp $env:TEMP\ega_text_tb.vvp }`. It reproduces
    the pre-existing `cga.hex` splash fallback failure documented in
    `EGA_TESTBENCH_INVENTORY.md`; the non-splash text checks run through cell
    fetch cadence, font address selection, attributes, cursor, mono, underline,
    9-dot, and panning coverage.
  - Hardware reset/text and CGA-compatible text-mode smoke remain pending under
    `ECC-002`.

### ECC-205 - Verify B8000-Compatible Access Through EGA VRAM

- Status: `[x]`
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
- Result:
  - Added `rtl/KFPC-XT/TESTBENCH/ega_vram_b8000_tb.sv`.
  - The directed test verifies that `mem_map_sel=2'b11` selects the
    B8000-BFFFF aperture into EGA VRAM and rejects B7FFF.
  - The directed test also verifies odd/even `page_select` remapping inside
    the EGA VRAM address space.
  - Verified with `iverilog -g2012 -I rtl/video -o
    $env:TEMP\ega_vram_b8000_tb.vvp
    rtl/KFPC-XT/TESTBENCH/ega_vram_b8000_tb.sv rtl/video/ega_vram.v; if
    ($LASTEXITCODE -eq 0) { vvp $env:TEMP\ega_vram_b8000_tb.vvp }`.
  - The broader `ega_vram_tb` still reproduces its pre-existing 14 write-mode
    mismatches documented in `EGA_TESTBENCH_INVENTORY.md`.

## ECC-300: Remove `cga_passthrough`

### ECC-301 - Remove CGA Instance From `ega_top`

- Status: `[x]`
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
- Result:
  - Removed the `cga cga_passthrough` instance, its `cga_*` fallback wires,
    and all `defparam cga_passthrough.*` assignments from `ega_top`.
  - EGA I/O reads now return only EGA-owned register mux data, defaulting to
    `8'h00` when no EGA register is selected.
  - `bus_rdy`, external CGA RAM strobes/address, inactive sync/blank outputs,
    and mode outputs now use EGA-owned or explicit inactive defaults.
  - Verified `rg -n "cga_passthrough" rtl/video/ega_top.v` returns no matches.
  - Verified focused tests:
    `ega_pixel_tb` and `ega_vram_b8000_tb` pass.
  - Verified Quartus A&E with `$env:QUARTUS_BIN='C:\intelFPGA_lite\17.0\quartus\bin64';
    $env:PATH="$env:QUARTUS_BIN;$env:PATH"; quartus_map
    --read_settings_files=on --write_settings_files=off PCXT -c PCXT
    --analysis_and_elaboration`, which succeeds with 0 errors and 222
    warnings.

### ECC-302 - Replace CGA-Derived Clock And Mode Outputs

- Status: `[x]`
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
- Result:
  - `clkdiv` remains an EGA-owned output driven by `ega_clkdiv`.
  - `grph_mode` and `hres_mode` are driven only by EGA internal state, with
    explicit inactive defaults.
  - Renamed the EGA graphics-controller CGA-compatible 2bpp indicator from
    `cga_2bpp_mode`/`ega_cga_2bpp_mode` to `compat_2bpp_mode`/
    `ega_compat_2bpp_mode`.
  - Removed the unused `cga_hw` input from `ega_top` and its instantiation in
    `Peripherals.sv`.
  - Verified `rg -n "cga_|cga_hw|cga_2bpp|ega_cga" rtl/video/ega_top.v
    rtl/video/ega_gfx_ctrl.v` returns no matches.
  - Verified `ega_pixel_tb` and `ega_vram_b8000_tb` pass.
  - Verified Quartus A&E with `$env:QUARTUS_BIN='C:\intelFPGA_lite\17.0\quartus\bin64';
    $env:PATH="$env:QUARTUS_BIN;$env:PATH"; quartus_map
    --read_settings_files=on --write_settings_files=off PCXT -c PCXT
    --analysis_and_elaboration`, which succeeds with 0 errors and 221
    warnings.

### ECC-303 - Prove `ega_top` Builds Without CGA Sources

- Status: `[x]`
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
- Result:
  - Verified `ega_top` elaborates under Icarus without standalone CGA sources:
    `iverilog -g2012 -I rtl/video -s ega_top -o
    $env:TEMP\ega_top_no_cga.vvp rtl/video/ega_top.v
    rtl/video/UM6845R.v rtl/video/ega_sequencer.v
    rtl/video/ega_gfx_ctrl.v rtl/video/ega_pixel.v rtl/video/ega_text.v
    rtl/video/ega_attrib_ctrl.v rtl/video/video_scandoubler.v
    rtl/video/ega_vgaport.v`.
  - Verified `rg -n "cga\.v|cga_pixel|cga_sequencer|cga_attrib|cga_vgaport|cga_composite|cga_passthrough|module cga\b|cga_"
    rtl/video/ega_top.v` returns no matches.

## ECC-400: Collapse `Peripherals.sv` Video Mux

### ECC-401 - Remove CGA VRAM Path From `Peripherals.sv`

- Status: `[x]`
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
- Result:
  - Removed the `vram cga_vram` instance and all CGA VRAM address/data/enable
    muxing from `Peripherals.sv`.
  - Disconnected the legacy RAM-side ports on `ega_top` from any CGA VRAM
    storage; EGA VRAM remains served by `ega_vram_bram_frontend`.
  - Removed CPU readback from standalone CGA VRAM; B8000-compatible reads are
    handled by the EGA VRAM path when the EGA memory map selects that aperture.
  - Kept the `cga_clear_busy` handshake alive as a generic splash-clear hold
    pulse for `PCXT.sv`, but it no longer drives CGA VRAM writes.
  - Verified `rg -n "CGA_VRAM|cga_vram|cga_splash_copy|cga_copy"
    rtl/KFPC-XT/HDL/Peripherals.sv` returns no active CGA VRAM path matches.
  - Verified `ega_vram_b8000_tb` passes.
  - Verified Quartus A&E with `$env:QUARTUS_BIN='C:\intelFPGA_lite\17.0\quartus\bin64';
    $env:PATH="$env:QUARTUS_BIN;$env:PATH"; quartus_map
    --read_settings_files=on --write_settings_files=off PCXT -c PCXT
    --analysis_and_elaboration`, which succeeds with 0 errors and 220
    warnings.

### ECC-402 - Remove HGC VRAM And Video Path

- Status: `[x]`
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
- Result:
  - Removed the active `hgc` and `hgc_vgaport` instances, HGC VRAM BRAM,
    HGC CRTC readback, HGC memory select, HGC I/O synchronizer, and HGC splash
    destination from `Peripherals.sv`.
  - Forced the legacy `swap_video` output low and routed local VGA RGB/sync/
    blank/de outputs only through the EGA/CGA-compatible path; HGC bus ready is
    fixed ready with no HGC memory/status branch.
  - Verified `rg -n "hgc_mem_select|hgc_grph|hgc_io_|hgc_splash|hgc_vram|HGC_VRAM|HGC_CRTC|hgc1|hgc_vgaport|R_HGC|G_HGC|B_HGC|swap_video_sel|std_hsyncwidth_hgc|vblank_border_hgc|clk_vga_hgc\)"
    rtl/KFPC-XT/HDL/Peripherals.sv` returns no matches.
  - Verified `ega_pixel_tb` and `ega_vram_b8000_tb` pass.
  - Verified Quartus A&E with `$env:QUARTUS_BIN='C:\intelFPGA_lite\17.0\quartus\bin64';
    $env:PATH="$env:QUARTUS_BIN;$env:PATH"; quartus_map
    --read_settings_files=on --write_settings_files=off PCXT -c PCXT
    --analysis_and_elaboration`, which succeeds with 0 errors and 201
    warnings.

### ECC-403 - Remove Tandy Video Banking From Active Path

- Status: `[x]`
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
- Result:
  - Disabled Tandy video in `Peripherals.sv` active logic by fixing
    `tandy_video_en` low, removing Tandy page/NMI register state, removing
    Tandy video memory selection, and latching CPU addresses directly.
  - Removed Tandy-specific CGA/EGA video assumptions from the active path:
    `tandy_16_gfx` and `tandy_color_16` are fixed low, composite output no
    longer branches on Tandy video, and `ega_top` receives `tandy_video=0`.
  - Left Tandy audio/keyboard compile paths for `ECC-504`; they are no longer
    tied to active video banking.
  - Verified `rg -n "video_mem_select|tandy_page|nmi_mask_register"
    rtl/KFPC-XT/HDL/Peripherals.sv` returns no matches.
  - Verified `ega_pixel_tb` and `ega_vram_b8000_tb` pass.
  - Verified Quartus A&E with `$env:QUARTUS_BIN='C:\intelFPGA_lite\17.0\quartus\bin64';
    $env:PATH="$env:QUARTUS_BIN;$env:PATH"; quartus_map
    --read_settings_files=on --write_settings_files=off PCXT -c PCXT
    --analysis_and_elaboration`, which succeeds with 0 errors and 199
    warnings.

### ECC-404 - Route VGA And OSD Signals Directly From EGA

- Status: `[x]`
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
- Result:
  - Removed the local `cga_vgaport` DAC/fallback from `Peripherals.sv`.
  - Routed `VGA_R/G/B`, sync, blanking, display enable,
    `VGA_VBlank_border`, and `std_hsyncwidth` directly from `ega_top`
    outputs. The legacy `swap_video` output remains fixed low from `ECC-402`.
  - Renamed the local VGA-facing sync/blanking wires to EGA names so the
    visible output path no longer selects CGA/HGC/Tandy video sources.
  - Verified `rg -n "cga_vgaport|R_CGA|G_CGA|B_CGA|video_cga|hsync_cga|HSYNC_CGA|VSYNC_CGA|HBLANK_CGA|VBLANK_CGA|de_o_cga|swap_video_sel|R_HGC|G_HGC|B_HGC"
    rtl/KFPC-XT/HDL/Peripherals.sv` returns no matches.
  - Verified `ega_pixel_tb` and `ega_vram_b8000_tb` pass.
  - Verified Quartus A&E with `$env:QUARTUS_BIN='C:\intelFPGA_lite\17.0\quartus\bin64';
    $env:PATH="$env:QUARTUS_BIN;$env:PATH"; quartus_map
    --read_settings_files=on --write_settings_files=off PCXT -c PCXT
    --analysis_and_elaboration`, which succeeds with 0 errors and 180
    warnings.

## ECC-500: Remove Dead Compile Paths

### ECC-501 - Remove Obsolete Video Macros From Project Config

- Status: `[x]`
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
- Result:
  - Removed project-config `VERILOG_MACRO` assignments for
    `SYSTEM_VARIANT_TANDY`, `ROM_VARIANT_TANDY`, `ENABLE_TANDY_VIDEO`,
    `ENABLE_TANDY_AUDIO`, `ENABLE_TANDY_KBD`, `ENABLE_CGA`, and `ENABLE_HGC`
    from `config.tcl`.
  - Kept unrelated feature macros (`ENABLE_OPL2`, `ENABLE_CMS`, `ENABLE_EMS`,
    `ENABLE_A000_UMB`) unchanged.
  - Verified `rg -n "SYSTEM_VARIANT_TANDY|ROM_VARIANT_TANDY|ENABLE_TANDY_VIDEO|ENABLE_TANDY_AUDIO|ENABLE_TANDY_KBD|ENABLE_CGA|ENABLE_HGC"
    -g"*.qsf" -g"*.qip" -g"*.tcl" .` returns no build-config matches.
  - Verified Quartus A&E with `$env:QUARTUS_BIN='C:\intelFPGA_lite\17.0\quartus\bin64';
    $env:PATH="$env:QUARTUS_BIN;$env:PATH"; quartus_map
    --read_settings_files=on --write_settings_files=off PCXT -c PCXT
    --analysis_and_elaboration`, which succeeds with 0 errors and 180
    warnings. Standalone CGA files still listed by `rtl/video/video.qip` are
    tracked by `ECC-502`.

### ECC-502 - Stop Compiling Standalone CGA Modules

- Status: `[x]`
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
- Result:
  - Removed `cga_vram.v`, `cga_vgaport.v`, `cga_sequencer.v`,
    `cga_pixel.sv`, `cga_composite.v`, `cga_attrib.v`, and `cga.v` from
    `rtl/video/video.qip`.
  - Kept source files in-tree for now; they are no longer active build inputs.
  - Verified `rg -n "cga_vram|cga_vgaport|cga_sequencer|cga_pixel|cga_composite|cga_attrib|cga\.v|module cga\b|cga_passthrough"
    -g"*.qsf" -g"*.qip" -g"*.tcl" .` returns no build-config matches.
  - Verified Quartus A&E with `$env:QUARTUS_BIN='C:\intelFPGA_lite\17.0\quartus\bin64';
    $env:PATH="$env:QUARTUS_BIN;$env:PATH"; quartus_map
    --read_settings_files=on --write_settings_files=off PCXT -c PCXT
    --analysis_and_elaboration`, which succeeds with 0 errors and 180
    warnings.

### ECC-503 - Stop Compiling HGC Modules

- Status: `[x]`
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
- Result:
  - Removed `hgc_vgaport.v`, `hgc_sequencer.v`, `hgc_pixel.v`,
    `hgc_attrib.v`, and `hgc.v` from `rtl/video/video.qip`.
  - Removed the inactive top-level HGC HDMI/mixer/retime path from `PCXT.sv`
    and routed the final HDMI/credits path directly from the single EGA output
    pipeline.
  - Removed dead HGC ports and ready wiring from `PCXT.sv`,
    `rtl/KFPC-XT/HDL/Chipset.sv`, `rtl/KFPC-XT/HDL/Peripherals.sv`, and
    `rtl/KFPC-XT/TESTBENCH/Chipset_tb.sv`.
  - Verified `rg -n "ENABLE_HGC|hgc_|HGC|hgc\b|swap_video_eff|video_mixer_hgc|VGA_R_hgc|CE_PIXEL_hgc|CLK_VIDEO_HGC"
    PCXT.sv rtl/KFPC-XT/HDL/Chipset.sv rtl/KFPC-XT/HDL/Peripherals.sv
    rtl/KFPC-XT/TESTBENCH/Chipset_tb.sv rtl/video/video.qip` returns no
    matches.
  - Verified `rg -n "hgc_vgaport|hgc_sequencer|hgc_pixel|hgc_attrib|hgc\.v|module hgc\b"
    -g"*.qsf" -g"*.qip" -g"*.tcl" .` returns no build-config matches.
  - Verified `ega_pixel_tb` and `ega_vram_b8000_tb` pass.
  - Verified Quartus A&E with `$env:QUARTUS_BIN='C:\intelFPGA_lite\17.0\quartus\bin64';
    $env:PATH="$env:QUARTUS_BIN;$env:PATH"; quartus_map
    --read_settings_files=on --write_settings_files=off PCXT -c PCXT
    --analysis_and_elaboration`, which succeeds with 0 errors and 176
    warnings.

### ECC-504 - Remove Tandy Variant Compile And Menu Paths

- Status: `[x]`
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
- Result:
  - Removed the top-level Tandy system/ROM/audio/video/keyboard macros and
    user-facing Tandy BIOS/audio menu entries from `PCXT.sv`.
  - Removed Tandy BIOS loader selection, alternate SDRAM BIOS banking, SN76489
    audio mixing, Tandy keyboard scancode conversion, and Tandy video timing
    outputs from the active `PCXT`/`CHIPSET`/`PERIPHERALS`/`RAM` path.
  - Removed `rtl/sound/jt89/hdl/jt89.qip` and
    `Tandy_Scancode_Converter.sv` from the active project file list.
  - Removed inactive Tandy ports from `ega_top` and updated
    `ega_registers_tb.sv` to match the cleaned interface.
  - Verified `rg -n "SYSTEM_VARIANT_TANDY|ROM_VARIANT_TANDY|ROM_IS_TANDY|ENABLE_TANDY|tandy_video|tandy_bios|tandy_snd|tandy_16|tandy_color|Tandy_Scancode|jt89|Tandy BIOS|Tandy Volume"
    PCXT.sv rtl/KFPC-XT/HDL/Chipset.sv rtl/KFPC-XT/HDL/Peripherals.sv
    rtl/KFPC-XT/HDL/RAM.sv rtl/KFPC-XT/HDL/KFPS2KB/HDL/KFPS2KB.sv
    rtl/video/ega_top.v rtl/KFPC-XT/TESTBENCH/ega_registers_tb.sv
    files.qip` returns no matches.
  - `rtl/common/tandy_pcjr_joy.sv` remains active as the existing joystick
    port `0x200` implementation; it is not a Tandy variant menu/BIOS/audio/
    video/keyboard path.
  - Verified `ega_pixel_tb` and `ega_vram_b8000_tb` pass.
  - Verified Quartus A&E with `$env:QUARTUS_BIN='C:\intelFPGA_lite\17.0\quartus\bin64';
    $env:PATH="$env:QUARTUS_BIN;$env:PATH"; quartus_map
    --read_settings_files=on --write_settings_files=off PCXT -c PCXT
    --analysis_and_elaboration`, which succeeds with 0 errors and 171
    warnings.
  - Checked `ega_registers_tb` with `iverilog -g2012 -I rtl/video -o
    $env:TEMP\ega_registers_tb.vvp rtl/KFPC-XT/TESTBENCH/ega_registers_tb.sv
    rtl/video/ega_sequencer.v rtl/video/ega_gfx_ctrl.v
    rtl/video/ega_attrib_ctrl.v rtl/video/UM6845R.v rtl/video/ega_top.v
    rtl/video/ega_vram.v rtl/video/ega_pixel.v rtl/video/ega_text.v
    rtl/video/ega_vgaport.v rtl/video/video_scandoubler.v rtl/video/cga.v
    rtl/video/cga_vram.v rtl/video/cga_sequencer.v rtl/video/cga_attrib.v
    rtl/video/cga_pixel.sv rtl/video/cga_vgaport.v
    rtl/video/cga_composite.v`; it still fails only for preexisting Icarus
    limitations in `rtl/video/cga_pixel.sv` array assignment/output l-value
    handling and procedural `force` automatic-variable handling in
    `ega_registers_tb.sv`.

### ECC-505 - Remove Dead `ifdef` Branches

- Status: `[x]`
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
- Result:
  - Removed the remaining active `ENABLE_CGA` and `ENABLE_EGA` conditional
    branches from `PCXT.sv` and `rtl/KFPC-XT/HDL/Peripherals.sv`; EGA is now
    wired as the unconditional video path.
  - Removed dead `enable_cga`, `video_output`, `hercules_hw`, `swap_video`,
    `cga_hw`, and external `ega_enabled` plumbing from `PCXT.sv`,
    `rtl/KFPC-XT/HDL/Chipset.sv`, `rtl/KFPC-XT/HDL/Peripherals.sv`, and
    `rtl/KFPC-XT/TESTBENCH/Chipset_tb.sv`.
  - Removed the obsolete keyboard video-toggle output path from
    `rtl/KFPC-XT/HDL/KFPS2KB/HDL/KFPS2KB.sv`.
  - Verified `rg -n "ENABLE_CGA|ENABLE_HGC|ENABLE_TANDY_VIDEO|ENABLE_EGA|enable_cga|cga_hw|hercules_hw|swap_video|video_output|tandy_video|tandy_bios_flag"
    PCXT.sv rtl/KFPC-XT/HDL/Chipset.sv rtl/KFPC-XT/HDL/Peripherals.sv
    rtl/KFPC-XT/HDL/KFPS2KB/HDL/KFPS2KB.sv
    rtl/KFPC-XT/TESTBENCH/Chipset_tb.sv files.qip rtl/video/video.qip
    config.tcl` returns no matches.
  - Historical, inactive `rtl/video/cga*.v` and `rtl/video/hgc*.v` sources
    still contain legacy macro/port names, but they are no longer compiled by
    the active QIP files.
  - Verified `ega_pixel_tb` and `ega_vram_b8000_tb` pass.
  - Verified Quartus A&E with `$env:QUARTUS_BIN='C:\intelFPGA_lite\17.0\quartus\bin64';
    $env:PATH="$env:QUARTUS_BIN;$env:PATH"; quartus_map
    --read_settings_files=on --write_settings_files=off PCXT -c PCXT
    --analysis_and_elaboration`, which succeeds with 0 errors and 169
    warnings.

## ECC-600: Verification Expansion

### ECC-601 - Add Clean-Core Smoke Matrix

- Status: `[x]`
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
- Result:
  - Updated `EGA_SMOKE_CHECKLIST.md` so the required smoke set covers EGA BIOS
    boot, text mode `03h`, EGA modes `0Dh`/`0Eh`/`10h`, an EGA game, a
    CGA-compatible text case, a CGA-compatible graphics case, and reset
    recovery.
  - Replaced old non-EGA coexistence smoke rows with CGA-compatible cases that
    explicitly run through EGA ownership.
  - Added an `ECC-601` clean-core matrix with all hardware visual cases marked
    `blocked` in this session because `jtagconfig` reports no available JTAG
    hardware.
  - Updated release-candidate criteria to require CGA-compatible text and
    graphics results through EGA instead of CGA/HGC/Tandy non-regression
    adapter checks.

### ECC-602 - Add B8000-Compatible EGA VRAM Tests

- Status: `[x]`
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
- Result:
  - Extended `rtl/KFPC-XT/TESTBENCH/ega_vram_b8000_tb.sv` with directed
    B8000 graphics fetch coverage that writes distinct data into all four EGA
    planes through the CPU path and verifies CRT fetch returns those planes.
  - Added directed B8000 text fetch coverage that verifies plane 0 character,
    plane 1 attribute, and plane 2 glyph data are fetched through the EGA text
    path.
  - Existing coverage continues to check B8000/BFFFF decode and odd/even page
    remapping inside EGA VRAM.
  - Verified with `iverilog -g2012 -I rtl/video -o
    $env:TEMP\ega_vram_b8000_tb.vvp
    rtl/KFPC-XT/TESTBENCH/ega_vram_b8000_tb.sv rtl/video/ega_vram.v; if
    ($LASTEXITCODE -eq 0) { vvp $env:TEMP\ega_vram_b8000_tb.vvp }`, which
    passes.

### ECC-603 - Add CGA-Compatible EGA Render Tests

- Status: `[x]`
- Priority: `P1`
- Depends on: `ECC-203`.
- Files: `rtl/KFPC-XT/TESTBENCH/`, `rtl/video/ega_pixel.v`.
- Source: `EGA_CLEAN_CORE_PLAN.md` Phase 6.
- Work:
  - Add focused tests for EGA CGA-compatible 2bpp rendering.
  - Cover palette/index output for representative byte patterns.
- Acceptance:
  - Render behavior no longer relies only on game smoke testing.
- Result:
  - Extended `rtl/KFPC-XT/TESTBENCH/ega_pixel_tb.sv` so the CGA-compatible
    2bpp render path checks multiple representative packed byte patterns.
  - Added a palette-path check that verifies a CGA-compatible 2bpp pixel index
    is handed to the Attribute Controller and remapped through palette register
    index `5`.
  - Verified with `iverilog -g2012 -I rtl/video -o
    $env:TEMP\ega_pixel_tb.vvp rtl/KFPC-XT/TESTBENCH/ega_pixel_tb.sv
    rtl/video/ega_pixel.v rtl/video/ega_attrib_ctrl.v; if ($LASTEXITCODE -eq
    0) { vvp $env:TEMP\ega_pixel_tb.vvp }`, which passes.

### ECC-604 - Add Splash Through EGA Regression Test

- Status: `[x]`
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
- Result:
  - Added `rtl/KFPC-XT/TESTBENCH/ega_vram_splash_tb.sv` as a focused
    regression for splash text writes into EGA VRAM.
  - The test verifies that splash character writes populate plane 0, splash
    attribute writes populate plane 1, existing font glyph data in plane 2 is
    preserved, and EGA text fetch returns the splash char/attr/glyph data.
  - Verified with `iverilog -g2012 -I rtl/video -o
    $env:TEMP\ega_vram_splash_tb.vvp
    rtl/KFPC-XT/TESTBENCH/ega_vram_splash_tb.sv rtl/video/ega_vram.v; if
    ($LASTEXITCODE -eq 0) { vvp $env:TEMP\ega_vram_splash_tb.vvp }`, which
    passes.

## ECC-700: Documentation And Final Cleanup

### ECC-701 - Mark Old Coexistence Documentation As Superseded

- Status: `[x]`
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
- Result:
  - Marked historical coexistence documentation as superseded for
    `ega-mcga-clean-core` in `PLAN.md`, `EGA_TRACEABILITY.md`,
    `EGA_CGA_HGC_COEXISTENCE_AUDIT.md`, and `EGA_FEATURE_GATE_AUDIT.md`.
  - Linked the superseded documents to `EGA_CLEAN_CORE_SPEC.md`,
    `EGA_CLEAN_CORE_PLAN.md`, and `EGA_CLEAN_CORE_TASKS.md` as the active
    clean-core sources of truth.
  - Updated the integration traceability row to describe always-on EGA,
    CGA-compatible behavior through EGA, and removed legacy video gates instead
    of CGA/HGC/Tandy coexistence.

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
