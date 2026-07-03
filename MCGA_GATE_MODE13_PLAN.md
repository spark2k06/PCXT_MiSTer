# MCGA Gate Mode 13h Plan

This plan turns `MCGA_GATE_MODE13_SPEC.md` into an implementation roadmap for
adding gated MCGA-compatible mode `13h` (`320x200x256`) to the clean EGA core.

The target is not a full VGA implementation. The target is a controlled MCGA
mode `13h` extension:

- `MCGA Gate=Disabled` preserves current clean EGA behavior.
- `MCGA Gate=Enabled` allows BIOS-visible mode `13h`.
- Mode `13h` uses packed 8bpp framebuffer bytes at `A000:0000`.
- DAC ports `03C7h`, `03C8h`, and `03C9h` provide a 256-entry palette.
- EGA and CGA-compatible EGA modes remain owned by the existing EGA path.

The plan is intentionally phased. Each phase should leave the tree buildable and
should be committed separately unless a dependency makes that impossible.

## 1. Working Rules

- Do not reintroduce standalone CGA, HGC, Tandy, or `cga_passthrough`.
- Keep EGA as the owner of existing EGA and CGA-compatible behavior.
- Treat MCGA mode `13h` as an explicit gated extension, not a new global video
  mux.
- Keep `MCGA Gate=Disabled` as the default and regression baseline.
- Prefer focused RTL tests before DOS/game smoke tests.
- Document every unsupported VGA register that is intentionally left as a safe
  default.
- A TSR may be used for bring-up, but final out-of-box behavior should be BIOS
  or option-ROM based if compatibility requires it.

## 2. Phase Overview

| Phase | Name | Main Outcome |
| --- | --- | --- |
| 0 | Baseline And Research | Current EGA build and IBM EGA BIOS limits are documented. |
| 1 | OSD Gate Plumbing | `MCGA Gate` exists and is wired, but still inert. |
| 2 | Mode State And Decode | `mcga_mode13_active` exists and A000 ownership is gated. |
| 3 | Packed Framebuffer | 64 KiB packed 8bpp memory works for CPU reads/writes. |
| 4 | DAC Palette | 256-entry DAC and ports `03C7h/03C8h/03C9h` work. |
| 5 | Pixel Rendering | Mode `13h` renders `320x200x256` through the active output. |
| 6 | BIOS Or TSR Integration | `INT 10h AX=0013h` enters mode `13h` when enabled. |
| 7 | Verification And Compatibility | Tests, DOS smoke, game smoke, and build closure are recorded. |
| 8 | Documentation Cleanup | User-facing docs and remaining limitations are updated. |

## 3. Phase 0: Baseline And Research

### Purpose

Freeze the pre-MCGA state and confirm the BIOS/software assumptions that drive
the implementation.

### Likely Files

- `MCGA_GATE_MODE13_SPEC.md`
- New baseline note if needed
- Existing build reports under `output_files/`
- IBM EGA ROM under `output_files/` or external source paths

### Tasks

- Record the clean EGA commit and latest full build artifact.
- Record current FPGA resources and timing state.
- Document that the IBM EGA option ROM does not implement mode `13h`.
- Identify one minimal DOS mode `13h` test program and one game/demo candidate.

### Acceptance

- Baseline notes are sufficient to compare post-MCGA behavior.
- No RTL behavior changes are made in this phase.

### Verification

- `git status --short` shows only documentation changes.
- `git diff --check` passes.

## 4. Phase 1: OSD Gate Plumbing

### Purpose

Expose `MCGA Gate` without changing video behavior.

### Likely Files

- `PCXT.sv`
- Documentation and smoke checklist files

### Tasks

- Add `MCGA Gate, Disabled, Enabled` to `CONF_STR`.
- Allocate a stable `status` bit and name it `mcga_enabled`.
- Route `mcga_enabled` to the video subsystem boundary.
- Keep the signal inert until later phases.

### Acceptance

- OSD shows the option.
- Default is `Disabled`.
- Toggling the option does not change EGA behavior yet.
- Existing focused EGA tests still pass.

### Verification

- Focused EGA testbenches.
- Quartus analysis and elaboration.

## 5. Phase 2: Mode State And Decode

### Purpose

Introduce explicit MCGA mode ownership without implementing rendering yet.

### Likely Files

- `rtl/video/ega_top.v`
- `rtl/KFPC-XT/HDL/Peripherals.sv`
- `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`
- Focused testbenches

### Tasks

- Add `mcga_mode13_active`.
- Ensure reset clears `mcga_mode13_active`.
- Ensure mode `13h` activation is impossible when `mcga_enabled=0`.
- Define the A000 ownership boundary for MCGA mode.
- Preserve existing EGA memory behavior when inactive.

### Acceptance

- `mcga_mode13_active` is observable in tests.
- Disabled gate prevents mode `13h` activation.
- Existing EGA memory tests still pass.

### Verification

- New mode-state testbench.
- Existing EGA VRAM focused tests.
- Quartus analysis and elaboration.

## 6. Phase 3: Packed Framebuffer

### Purpose

Provide the CPU-visible packed memory model required by mode `13h`.

### Likely Files

- New or existing MCGA framebuffer RTL under `rtl/video/`
- `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`
- Focused testbenches

### Tasks

- Implement 64 KiB packed 8bpp storage.
- Decode CPU reads/writes to `A0000h-AFFFFh` while mode `13h` is active.
- Store one byte per pixel.
- Keep bytes beyond visible offset `0xF9FF` readable/writable but not rendered.
- Prevent EGA planar write logic from corrupting MCGA packed bytes.

### Acceptance

- CPU writes to packed offsets read back unchanged.
- Address `y * 320 + x` maps to the expected byte.
- Switching out of mode `13h` restores EGA memory ownership.

### Verification

- Packed framebuffer read/write testbench.
- Existing EGA B8000/A000 tests.

## 7. Phase 4: DAC Palette

### Purpose

Implement the palette interface expected by mode `13h` software.

### Likely Files

- New or existing DAC RTL under `rtl/video/`
- `rtl/video/ega_top.v`
- I/O decode logic
- Focused testbenches

### Tasks

- Implement 256 palette entries.
- Implement DAC write index port `03C8h`.
- Implement DAC read index port `03C7h`.
- Implement DAC data port `03C9h`.
- Auto-increment index after three component accesses.
- Define and load a standard default palette.

### Acceptance

- Direct port writes update palette entries.
- Direct port reads return palette entries.
- Auto-increment behavior matches VGA/MCGA expectations.
- RGB expansion is deterministic and documented.

### Verification

- DAC register testbench.
- Mode `13h` palette ramp test.

## 8. Phase 5: Pixel Rendering

### Purpose

Render packed framebuffer bytes as `320x200x256` output.

### Likely Files

- `rtl/video/ega_top.v`
- New mode `13h` renderer if needed
- Existing video timing modules
- Focused testbenches

### Tasks

- Add active-area counters for `320x200`.
- Fetch one byte per pixel from packed framebuffer.
- Convert byte to RGB through DAC palette.
- Route MCGA pixels through the existing single video output path.
- Define sync and blanking timing.
- Document whether initial timing reuses EGA-compatible 320x200 or implements
  VGA-like 70 Hz timing.

### Acceptance

- Render test maps known framebuffer bytes to expected RGB output.
- `MCGA Gate=Disabled` rendering is unchanged.
- Leaving mode `13h` returns output ownership to EGA.

### Verification

- Pixel render testbench.
- Existing EGA pixel/text/splash tests.
- Quartus analysis and elaboration.

## 9. Phase 6: BIOS Or TSR Integration

### Purpose

Make software able to enter mode `13h` through `INT 10h`.

### Likely Files

- `egabios.asm` or a new option ROM/TSR source under `SW/` or `x86_src/`
- ROM build scripts
- BIOS loading documentation

### Tasks

- Add a development TSR or BIOS hook for `INT 10h AX=0013h`.
- Update BIOS Data Area fields for mode `13h`.
- Implement `INT 10h AH=0Fh` current mode reporting.
- Implement pixel read/write BIOS functions `AH=0Ch` and `AH=0Dh`.
- Implement or safely handle relevant `AH=10h` palette services.
- Decide whether final delivery is a patched option ROM or bundled TSR.

### Acceptance

- DOS can call `INT 10h AX=0013h` and enter mode `13h` when gate is enabled.
- DOS receives sane mode data from `AH=0Fh`.
- Mode `13h` remains unavailable or inert when gate is disabled.

### Verification

- DOS mode `13h` `.COM` test.
- BIOS/TSR binary reproducibility check.

## 10. Phase 7: Verification And Compatibility

### Purpose

Prove the feature works and identify remaining compatibility gaps.

### Likely Files

- New MCGA testbench inventory/checklist
- `EGA_SMOKE_CHECKLIST.md` or MCGA-specific smoke checklist
- Build reports under `output_files/`

### Tasks

- Run all focused EGA regression tests.
- Run all new MCGA testbenches.
- Run DOS mode `13h` test program.
- Run at least one known mode `13h` game/demo.
- Run full Quartus build.
- Record resources, timing, warnings, and generated `.rbf`.
- Document unsupported VGA behaviors.

### Acceptance

- Required deterministic tests pass or limitations are documented.
- Full build completes and produces a bitstream.
- Known compatibility gaps are explicit.

## 11. Phase 8: Documentation Cleanup

### Purpose

Make the repository describe the final MCGA-gated behavior accurately.

### Likely Files

- `README.md`
- `MCGA_GATE_MODE13_SPEC.md`
- `MCGA_GATE_MODE13_PLAN.md`
- `MCGA_GATE_MODE13_TASKS.md`
- Smoke/test inventory documents

### Tasks

- Update user-facing docs for `MCGA Gate`.
- Document mode `13h` support and limitations.
- Document how BIOS/TSR integration is delivered.
- Close any temporary bring-up notes.

### Acceptance

- Documentation matches implemented behavior.
- No task remains open except explicitly blocked hardware smoke.

## 12. Definition Of Done

The roadmap is complete when:

- `MCGA Gate` exists and defaults to `Disabled`.
- `Disabled` preserves the clean EGA core.
- `Enabled` allows mode `13h`.
- Packed A000 8bpp framebuffer works.
- DAC programming works.
- Mode `13h` renders visibly and correctly.
- DOS software can enter mode `13h` through BIOS or the chosen final hook.
- Focused EGA and MCGA tests pass.
- Full Quartus build produces an `.rbf`.
- Timing/resource/compatibility limitations are documented.
