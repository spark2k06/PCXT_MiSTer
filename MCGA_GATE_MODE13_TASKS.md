# MCGA Gate Mode 13h Task Backlog

This file turns `MCGA_GATE_MODE13_SPEC.md` and
`MCGA_GATE_MODE13_PLAN.md` into an implementation backlog for the gated MCGA
mode `13h` feature.

The technical source of truth is `MCGA_GATE_MODE13_SPEC.md`. The sequencing
source of truth is `MCGA_GATE_MODE13_PLAN.md`.

## Status Legend

- `[ ]`: not started.
- `[~]`: in progress.
- `[x]`: complete.
- `[!]`: blocked by an explicit dependency or open question.

## Priority Legend

- `P0`: required for a coherent mode `13h` implementation.
- `P1`: required for compatibility, verification, or out-of-box use.
- `P2`: documentation, cleanup, or later hardening work.

## Global Definition Of Done

A task is complete only when all relevant checks below are true:

- The behavior matches `MCGA_GATE_MODE13_SPEC.md`.
- `MCGA Gate=Disabled` preserves the clean EGA behavior.
- `MCGA Gate=Enabled` affects only mode `13h` ownership.
- No standalone CGA/HGC/Tandy path or `cga_passthrough` is reintroduced.
- Deterministic tests or smoke notes cover the changed behavior.
- `git diff --check` passes.

## Milestone Gates

### MCGM0: Baseline And Research

- Current clean EGA build state is recorded.
- IBM EGA BIOS mode `13h` limitation is documented.
- Candidate DOS test software is identified.

### MCGM1: Gate Plumbing

- `MCGA Gate` is present in the OSD.
- The gate defaults to `Disabled`.
- The selected status bit is named and routed.
- The gate is inert until mode `13h` implementation starts.

### MCGM2: Mode Ownership

- `mcga_mode13_active` exists.
- Reset clears mode `13h`.
- Disabled gate blocks mode `13h`.
- Existing EGA ownership remains unchanged when inactive.

### MCGM3: Packed Framebuffer

- CPU reads/writes to `A0000h-AFFFFh` work as packed 8bpp while active.
- EGA planar memory behavior is preserved while inactive.

### MCGM4: DAC Palette

- DAC ports `03C7h`, `03C8h`, and `03C9h` work.
- 256 palette entries are available.
- Auto-increment behavior is tested.

### MCGM5: Pixel Rendering

- Packed bytes render as `320x200x256`.
- Mode `13h` output uses the single active video path.
- Switching out of mode `13h` restores EGA output.

### MCGM6: BIOS/TSR Integration

- `INT 10h AX=0013h` enters mode `13h` when enabled.
- Current mode reporting and minimal pixel/palette BIOS services work.
- Final delivery path is documented.

### MCGM7: Closure

- MCGA and EGA focused tests pass.
- DOS mode `13h` smoke passes.
- Full build produces `.rbf`.
- Resource, timing, and compatibility notes are recorded.

## Dependency Summary

```text
MCGA-000..099 baseline and research
  -> MCGA-100..199 OSD gate plumbing
      -> MCGA-200..299 mode state and decode
          -> MCGA-300..399 packed framebuffer
              -> MCGA-400..499 DAC palette
                  -> MCGA-500..599 pixel rendering
                      -> MCGA-600..699 BIOS/TSR integration
                          -> MCGA-700..799 verification and docs
```

## MCGA-000: Baseline And Research

### MCGA-001 - Record MCGA Starting Baseline

- Status: `[x]`
- Priority: `P0`
- Depends on: none.
- Files: `MCGA_GATE_MODE13_SPEC.md`, new baseline notes if needed.
- Source: `MCGA_GATE_MODE13_PLAN.md` Phase 0.
- Work:
  - Record current commit and latest full build artifact.
  - Record current FPGA resources and timing state.
  - Record the current clean EGA behavior that `MCGA Gate=Disabled` must
    preserve.
- Acceptance:
  - Baseline identifies commit, `.rbf` or `.sof`, resources, and timing state.

### MCGA-002 - Document IBM EGA BIOS Mode 13h Gap

- Status: `[x]`
- Priority: `P0`
- Depends on: none.
- Files: `MCGA_GATE_MODE13_SPEC.md`, optional BIOS audit note.
- Source: `MCGA_GATE_MODE13_SPEC.md` sections 1 and 5.
- Work:
  - Record the IBM EGA option ROM path and disassembly evidence.
  - Document that mode `13h` is not implemented by the EGA BIOS.
  - Record whether BIOS, option ROM, or TSR delivery is preferred for final
    integration.
- Acceptance:
  - The implementation cannot assume existing BIOS support for mode `13h`.

### MCGA-003 - Identify DOS Mode 13h Test Targets

- Status: `[x]`
- Priority: `P1`
- Depends on: none.
- Files: MCGA smoke checklist or test inventory.
- Source: `MCGA_GATE_MODE13_PLAN.md` Phase 0.
- Work:
  - Identify a minimal DOS `.COM` test program target.
  - Identify one known mode `13h` game or demo.
  - Record expected visual output and exit path back to text mode.
- Acceptance:
  - Later phases have concrete software smoke targets.

## MCGA-100: OSD Gate Plumbing

### MCGA-101 - Add User-Facing MCGA Gate

- Status: `[x]`
- Priority: `P0`
- Depends on: `MCGA-001`.
- Files: `PCXT.sv`.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 4.
- Work:
  - Add `MCGA Gate, Disabled, Enabled` to `CONF_STR`.
  - Choose a stable unused `status` bit.
  - Default the option to `Disabled`.
- Acceptance:
  - OSD exposes `MCGA Gate`.
  - The option does not overlap existing status bits.

### MCGA-102 - Route Inert MCGA Enable Signal

- Status: `[x]`
- Priority: `P0`
- Depends on: `MCGA-101`.
- Files: `PCXT.sv`, `rtl/KFPC-XT/HDL/Chipset.sv`,
  `rtl/KFPC-XT/HDL/Peripherals.sv`, `rtl/video/ega_top.v`.
- Source: `MCGA_GATE_MODE13_PLAN.md` Phase 1.
- Work:
  - Name the selected OSD bit `mcga_enabled`.
  - Route it to the video subsystem boundary.
  - Keep it inert.
- Acceptance:
  - Toggling `MCGA Gate` has no functional effect yet.
  - Existing focused EGA tests pass.

## MCGA-200: Mode State And Decode

### MCGA-201 - Add MCGA Mode 13h State

- Status: `[x]`
- Priority: `P0`
- Depends on: `MCGA-102`.
- Files: `rtl/video/ega_top.v`, focused testbench.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 6.2.
- Work:
  - Add `mcga_mode13_active`.
  - Reset it to `0`.
  - Ensure activation requires `mcga_enabled`.
- Acceptance:
  - Tests prove disabled gate blocks mode `13h` activation.

### MCGA-202 - Define MCGA A000 Ownership Boundary

- Status: `[x]`
- Priority: `P0`
- Depends on: `MCGA-201`.
- Files: `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`,
  `rtl/video/ega_vram.v`, `rtl/video/ega_top.v`.
- Source: `MCGA_GATE_MODE13_SPEC.md` sections 6.3 and 6.4.
- Work:
  - Define when MCGA owns `A0000h-AFFFFh`.
  - Preserve EGA ownership when mode `13h` is inactive.
  - Add safe inactive defaults for any new muxing.
- Acceptance:
  - Existing EGA VRAM tests still pass.

## MCGA-300: Packed Framebuffer

### MCGA-301 - Implement Packed 8bpp Framebuffer Storage

- Status: `[x]`
- Priority: `P0`
- Depends on: `MCGA-202`.
- Files: new or existing RTL under `rtl/video/`.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 6.3.
- Work:
  - Add 64 KiB packed 8bpp storage.
  - Define read/write ports needed by CPU and renderer.
  - Keep layout one byte per pixel.
- Acceptance:
  - Storage supports all offsets `0000h-FFFFh`.

### MCGA-302 - Decode CPU A000 Packed Reads And Writes

- Status: `[x]`
- Priority: `P0`
- Depends on: `MCGA-301`.
- Files: `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`, focused testbench.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 6.4.
- Work:
  - Route CPU writes to packed framebuffer while mode `13h` is active.
  - Route CPU reads from packed framebuffer while mode `13h` is active.
  - Ignore MCGA packed path while inactive.
- Acceptance:
  - Directed tests prove packed readback.
  - EGA planar read/write tests still pass.

### MCGA-303 - Verify Pixel Address Mapping

- Status: `[x]`
- Priority: `P1`
- Depends on: `MCGA-302`.
- Files: focused testbench.
- Source: `MCGA_GATE_MODE13_SPEC.md` sections 6.3 and 10.1.
- Work:
  - Verify offset `y * 320 + x`.
  - Verify visible limit `0xF9FF`.
  - Verify bytes beyond visible range do not render.
- Acceptance:
  - Pixel address tests pass.

## MCGA-400: DAC Palette

### MCGA-401 - Implement 256-Entry DAC

- Status: `[x]`
- Priority: `P0`
- Depends on: `MCGA-301`.
- Files: new or existing RTL under `rtl/video/`.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 7.
- Work:
  - Add 256 entries of 6-bit RGB components.
  - Add deterministic reset/default palette.
  - Add RGB expansion for output.
- Acceptance:
  - Testbench can write and sample palette entries.

### MCGA-402 - Implement DAC Ports 03C7h 03C8h 03C9h

- Status: `[ ]`
- Priority: `P0`
- Depends on: `MCGA-401`.
- Files: I/O decode RTL, DAC RTL, focused testbench.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 7.
- Work:
  - Implement DAC read index at `03C7h`.
  - Implement DAC write index at `03C8h`.
  - Implement DAC data reads/writes at `03C9h`.
  - Implement component and entry auto-increment.
- Acceptance:
  - Port-level DAC tests pass.

## MCGA-500: Pixel Rendering

### MCGA-501 - Add Mode 13h Timing

- Status: `[ ]`
- Priority: `P0`
- Depends on: `MCGA-201`.
- Files: `rtl/video/ega_top.v` or new timing RTL.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 6.5.
- Work:
  - Define `320x200` active display.
  - Choose EGA-compatible or VGA-like timing.
  - Document the timing choice.
- Acceptance:
  - Timing produces stable blanking and sync in simulation.

### MCGA-502 - Render Packed Pixels Through DAC

- Status: `[ ]`
- Priority: `P0`
- Depends on: `MCGA-303`, `MCGA-402`, `MCGA-501`.
- Files: `rtl/video/ega_top.v`, renderer RTL, focused testbench.
- Source: `MCGA_GATE_MODE13_SPEC.md` sections 6.5 and 10.1.
- Work:
  - Fetch packed framebuffer bytes.
  - Convert bytes through DAC palette.
  - Route RGB through the single active output path.
- Acceptance:
  - Known packed byte and DAC entry produce expected RGB.

### MCGA-503 - Verify Switching Between EGA And MCGA Output

- Status: `[ ]`
- Priority: `P1`
- Depends on: `MCGA-502`.
- Files: focused testbench.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 9.
- Work:
  - Enter mode `13h`.
  - Leave mode `13h` by selecting an EGA/CGA-compatible mode.
  - Verify EGA output ownership returns.
- Acceptance:
  - Switching test passes.
  - Existing EGA pixel/text tests still pass.

## MCGA-600: BIOS Or TSR Integration

### MCGA-601 - Add Development INT 10h Mode 13h Hook

- Status: `[ ]`
- Priority: `P1`
- Depends on: `MCGA-502`.
- Files: `egabios.asm` or new TSR/option ROM source.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 5.
- Work:
  - Implement `INT 10h AX=0013h` for bring-up.
  - Program mode `13h` state through the chosen hardware interface.
  - Update BIOS Data Area fields.
- Acceptance:
  - DOS software can enter mode `13h` when `MCGA Gate=Enabled`.

### MCGA-602 - Implement Minimal Mode 13h BIOS Services

- Status: `[ ]`
- Priority: `P1`
- Depends on: `MCGA-601`.
- Files: BIOS/TSR source and DOS test.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 5.1.
- Work:
  - Implement `AH=0Fh` current mode reporting.
  - Implement `AH=0Ch` write pixel.
  - Implement `AH=0Dh` read pixel.
  - Implement or safely handle required `AH=10h` palette services.
- Acceptance:
  - DOS test validates mode report and pixel read/write.

### MCGA-603 - Decide Final BIOS Delivery

- Status: `[ ]`
- Priority: `P1`
- Depends on: `MCGA-602`.
- Files: documentation, ROM build scripts if needed.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 5.2.
- Work:
  - Decide between patched EGA ROM, chained option ROM, or bundled TSR.
  - Document tradeoffs and final delivery path.
  - Make final artifact reproducible.
- Acceptance:
  - Out-of-box compatibility path is explicit.

## MCGA-700: Verification And Documentation

### MCGA-701 - Add DOS Mode 13h Test Program

- Status: `[ ]`
- Priority: `P1`
- Depends on: `MCGA-602`.
- Files: `SW/`, `x86_src/`, or test assets.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 10.2.
- Work:
  - Build a DOS test that sets mode `13h`.
  - Draw a 256-color ramp.
  - Program DAC entries.
  - Return to text mode.
- Acceptance:
  - Test binary is reproducible and documented.

### MCGA-702 - Run Full EGA And MCGA Regression Set

- Status: `[ ]`
- Priority: `P0`
- Depends on: `MCGA-503`, `MCGA-701`.
- Files: test inventory or smoke checklist.
- Source: `MCGA_GATE_MODE13_PLAN.md` Phase 7.
- Work:
  - Run existing EGA focused tests.
  - Run new MCGA focused tests.
  - Run DOS mode `13h` test when possible.
  - Record exact commands and results.
- Acceptance:
  - Required tests pass or limitations are documented.

### MCGA-703 - Run Game Or Demo Smoke

- Status: `[ ]`
- Priority: `P1`
- Depends on: `MCGA-701`.
- Files: smoke checklist.
- Source: `MCGA_GATE_MODE13_SPEC.md` section 10.3.
- Work:
  - Run at least one known mode `13h` game/demo.
  - Verify visual output.
  - Verify return to text mode if possible.
- Acceptance:
  - Game/demo smoke result is documented.

### MCGA-704 - Run Full Quartus Build And Record Resources

- Status: `[ ]`
- Priority: `P0`
- Depends on: `MCGA-702`.
- Files: build reports, task notes.
- Source: `MCGA_GATE_MODE13_PLAN.md` Phase 7.
- Work:
  - Run full Quartus build.
  - Confirm `.rbf` generation.
  - Record resources, timing, warnings, and command used.
- Acceptance:
  - Build completes or exact blocker is documented.

### MCGA-705 - Document Compatibility Limits

- Status: `[ ]`
- Priority: `P1`
- Depends on: `MCGA-702`, `MCGA-703`.
- Files: `README.md`, MCGA docs.
- Source: `MCGA_GATE_MODE13_SPEC.md` sections 8 and 12.
- Work:
  - Document supported mode `13h` behavior.
  - Document unsupported VGA/SVGA registers or services.
  - Document BIOS/TSR delivery behavior.
- Acceptance:
  - User-facing docs match implementation.
