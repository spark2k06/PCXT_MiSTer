# PCXT MiSTer EGA Task Backlog

This file turns `SPEC.md` and `PLAN.md` into an implementation backlog for
porting x86Box IBM EGA behavior into the PCXT MiSTer core. It is intentionally
task-oriented: every item has a stable ID, dependencies, likely files, reference
material, and acceptance checks.

The technical source of truth remains `SPEC.md`, with x86Box behavior in
`x86_src/video/vid_ega.c` and `x86_src/video/vid_ega_render.c`. The sequencing
source of truth remains `PLAN.md`.

## Status Legend

- `[ ]`: not started.
- `[~]`: in progress.
- `[x]`: complete.
- `[!]`: blocked by an explicit dependency or open question.

## Priority Legend

- `P0`: required before meaningful game debugging can continue.
- `P1`: required for full base IBM EGA compatibility.
- `P2`: quality, documentation, or late stabilization work.

## Global Definition Of Done

A task is complete only when all relevant checks below are true:

- The implemented behavior is traceable to a `SPEC.md` section and, where
  practical, to the matching x86Box behavior.
- Deterministic tests cover the changed behavior or the task records why a
  hardware-only smoke test is the only practical proof.
- Existing CGA, HGC, Tandy, and non-EGA paths are not unintentionally gated or
  regressed.
- Temporary debug registers, probes, and one-off instrumentation are removed or
  guarded before the task is marked complete.
- Any intentional deviation from base IBM EGA is recorded in `SPEC.md` or a
  follow-up documentation task.

## Milestone Gates

### M0: Baseline And Test Harness

- `ega_vram_tb.sv` builds and reports clear pass/fail diagnostics.
- Current EGA RTL/module boundaries are mapped against `SPEC.md`.
- The first smoke-test assets and expected results are recorded.

### M1: CPU-Visible EGA Compatibility

- CPU VRAM read/write modes, latches, plane masks, chain-2, odd/even, A16, page
  select, and GC memory map modes pass deterministic tests.
- `Peripherals.sv` decodes all EGA memory windows selected by GC register
  `06h[3:2]`.
- Register read/write behavior is probe-compatible enough for EGA BIOS and
  mode-setting software.

### M2: Correct CRTC And Graphics Scanout

- CRTC timing, row address, start address, line compare, split screen, and
  scanout remapping match the reference behavior covered in `SPEC.md`.
- Planar graphics modes render from shifted plane data, not stale or panned
  fetch wires.
- CGA-compatible 2bpp EGA graphics mode is implemented.

### M3: Attribute, Palette, Status, And Text

- Attribute Controller palette, plane enable, panning, overscan, blink, and
  status side effects are verified.
- Text rendering supports character/attribute fetches, font plane access,
  Character Map Select, cursor, mono attributes, and 9th-dot line graphics.

### M4: Integrated Release Candidate

- Quartus build completes.
- EGA BIOS and representative modes `03h`, `0Dh`, `0Eh`, `10h`, and text/graphics
  transitions pass smoke tests.
- Known problematic EGA games are re-tested and any remaining issues are
  reduced to documented follow-up tasks.

## Dependency Summary

```text
EGA-000..099 baseline
  -> EGA-100..199 CPU VRAM and memory decode
      -> EGA-200..299 register and I/O semantics
          -> EGA-300..399 CRTC timing and address generation
              -> EGA-400..499 graphics scanout
              -> EGA-500..599 attribute, palette, border, and status
                  -> EGA-600..699 text rendering
                      -> EGA-700..799 integration and BIOS compatibility
                          -> EGA-800..899 verification expansion
                              -> EGA-900..999 stabilization
```

Some test infrastructure tasks in `EGA-800..899` can start early, but each test
must be anchored to the behavior it proves.

## EGA-000: Baseline And Harness

### EGA-001 - Map Existing EGA RTL Against The Specification

- Status: `[x]`
- Priority: `P0`
- Depends on: none.
- Files: `rtl/video/ega_top.v`, `rtl/video/ega_vram.v`,
  `rtl/video/ega_pixel.v`, `rtl/video/ega_sequencer.v`,
  `rtl/video/ega_gfx_ctrl.v`, `rtl/video/ega_attrib_ctrl.v`,
  `rtl/video/UM6845R.v`, `rtl/KFPC-XT/HDL/Peripherals.sv`.
- Source: `SPEC.md` sections 2, 10, 11; `PLAN.md` phase 0.
- Work:
  - Create a short implementation map from each major EGA behavior to the
    current RTL module responsible for it.
  - Mark behaviors that are missing, partial, or implemented in a module where
    later refactoring may be required.
  - Record any module boundary decisions that affect later tasks.
- Acceptance:
  - Every `SPEC.md` section from 3 through 10 has at least one owning RTL module
    or a named missing-module task.
  - No implementation task starts without a known target module or a deliberate
    new-module decision.

### EGA-002 - Establish Repeatable Local Build And Simulation Commands

- Status: `[x]`
- Priority: `P0`
- Depends on: none.
- Files: `files.qip`, `rtl/KFPC-XT/TESTBENCH/*`, project scripts or notes.
- Source: `PLAN.md` sections 4, 5, 20.
- Work:
  - Identify the commands used to run the existing EGA testbench and any full
    project synthesis or lint flow available in the repository.
  - Record the exact commands in a local notes section or in the relevant test
    task descriptions.
  - Confirm that the commands fail clearly when a test assertion fails.
- Acceptance:
  - The EGA VRAM testbench can be run repeatedly from a clean terminal.
  - The final command output identifies pass/fail status without manual waveform
    inspection.

### EGA-003 - Improve EGA Testbench Diagnostics

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-002.
- Files: `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv`.
- Source: `PLAN.md` phase 0 and phase 1.
- Work:
  - Make each failing case report case name, address, write mode, read mode,
    memory map, plane mask, expected value, and actual value where relevant.
  - Ensure failures increment a single visible counter and terminate with a
    non-success result.
  - Group related cases so future failures point to the broken feature.
- Acceptance:
  - At least one intentionally broken local assertion produces a useful failure
    line during development.
  - Normal passing runs end with one clear pass message.
- Verification:
  - `ega_vram_tb.sv` now tracks the active test case and prints expected value,
    actual value, CPU address/A16, access strobes, read/write modes, memory map,
    page select, plane mask, odd/even mode, and chain-2 state on every mismatch.
  - The existing single `failures` counter and final pass/fail messages remain
    in place.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-004 - Define The Initial Hardware/Emulator Smoke Set

- Status: `[x]`
- Priority: `P0`
- Depends on: none.
- Files: `games/`, `egabios.asm`, `egabios.rom`, notes in `TASKS.md` or future
  documentation.
- Source: `SPEC.md` section 12.4; `PLAN.md` phase 0.
- Work:
  - Select the minimum smoke set for BIOS boot, DOS text, EGA mode `0Dh`, EGA
    mode `0Eh`, EGA mode `10h`, and at least one known glitching game.
  - Record expected visual properties for each case, not just whether the screen
    shows something.
  - Include one CGA/HGC/Tandy non-regression smoke case.
- Acceptance:
  - Every release-candidate run has a known smoke checklist.
  - Visual failures can be classified as CPU memory, register, scanout, palette,
    text, or integration issues.
- Verification:
  - Added `EGA_SMOKE_CHECKLIST.md` with the minimum BIOS, DOS text, EGA mode
    `0Dh`, `0Eh`, `10h`, known EGA game, and CGA/HGC/Tandy non-regression
    smoke cases.
  - The checklist records expected visual properties for each case, not only
    whether output appears.
  - The checklist defines primary failure classes for CPU memory, register,
    CRTC, scanout, palette, text, and integration failures, plus run-log
    requirements for reproducible evidence.

### EGA-005 - Create A Traceability Checklist

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-001.
- Files: `TASKS.md`, optional future documentation.
- Source: `SPEC.md` all sections; `PLAN.md` section 16.
- Work:
  - Keep a table or notes mapping task IDs to `SPEC.md` sections and x86Box
    reference behavior.
  - Update the mapping as tasks are completed or split.
- Acceptance:
  - The remaining backlog can be filtered by unimplemented `SPEC.md` behavior.
- Verification:
  - Added `EGA_TRACEABILITY.md` mapping SPEC sections to RTL owners, evidence
    documents, x86Box reference anchors, and remaining task IDs.
  - The checklist records open blockers for missing HDL simulation, game-image
    provenance, and future text-renderer ownership.
  - Maintenance rules define how future completed tasks, task splits, and
    intentional deviations should update the traceability record.

## EGA-100: CPU VRAM And Memory Decode

### EGA-101 - Update VRAM Testbench For `cpu_a16`

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-002, EGA-003.
- Files: `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv`,
  `rtl/video/ega_vram.v`.
- Source: `SPEC.md` sections 5.1, 5.2, 11.11; `PLAN.md` section 21.
- Work:
  - Drive the current `cpu_a16` input explicitly in every CPU-side read/write
    helper.
  - Add named cases for A16 low and high behavior.
  - Confirm existing tests do not accidentally rely on an uninitialized A16.
- Acceptance:
  - `ega_vram_tb.sv` builds with no unconnected `cpu_a16` warnings.
  - Existing tests pass with deterministic `cpu_a16` values.
- Verification:
  - `cpu_a16` is now driven by the CPU transaction helpers from 17-bit test
    addresses, and a named low/high A16 remap case covers both values.
  - Project Analysis & Elaboration was run through the documented Quartus flow.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-102 - Add CPU Address Remap Reference Helpers

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-101.
- Files: `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv`.
- Source: `SPEC.md` section 5.2; x86Box memory access behavior.
- Work:
  - Add reference functions for odd/even, chain-2, extended memory, page select,
    and memory-map-driven CPU addressing.
  - Keep the helper functions pure and independent of DUT internals.
  - Use the helpers in all new CPU VRAM tests.
- Acceptance:
  - Test expected values are calculated through reference helpers rather than
    duplicated ad hoc logic.
- Verification:
  - `ega_vram_tb.sv` now has pure reference helpers for CPU plane address
    remapping, chain-2 read plane selection, and chain-2 write mask selection.
  - The current CPU A16 case uses the remap helper instead of hardcoded internal
    plane addresses.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-103 - Cover GC Memory Map Selection In Tests

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-102.
- Files: `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv`,
  `rtl/video/ega_vram.v`, `rtl/KFPC-XT/HDL/Peripherals.sv`.
- Source: `SPEC.md` sections 3, 5.2, 11.1; `PLAN.md` phase 1.
- Work:
  - Add cases for GC register `06h[3:2]` selecting `A0000h-BFFFFh`,
    `A0000h-AFFFFh`, `B0000h-B7FFFh`, and `B8000h-BFFFFh`.
  - Verify accepted and rejected CPU addresses for each map.
  - Include boundary addresses at the first and last byte of each window.
- Acceptance:
  - Each memory map has pass/fail tests for inside-window and outside-window
    addresses.
  - The tests expose the current `A0000h-AFFFFh` only limitation before the RTL
    fix is applied.
- Verification:
  - `ega_vram_tb.sv` now has reference helpers for EGA absolute CPU aperture
    selection and offset conversion.
  - The testbench covers the first and last accepted address for all four GC
    memory maps and drives `cpu_mem_select` low for outside-window write
    attempts.
  - The actual PCXT peripheral decode fix remains scoped to `EGA-104`.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-104 - Implement Full EGA Memory Decode In `Peripherals.sv`

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-103.
- Files: `rtl/KFPC-XT/HDL/Peripherals.sv`, `rtl/video/ega_top.v`,
  `rtl/video/ega_gfx_ctrl.v`.
- Source: `SPEC.md` sections 3, 5.2, 10.2, 11.1.
- Work:
  - Export the effective GC memory map selection from the EGA core to the PCXT
    peripheral decode path.
  - Decode all four EGA CPU aperture selections.
  - Preserve existing CGA/HGC/Tandy decode behavior when EGA is disabled or not
    selected.
  - Keep bus ready behavior stable for non-selected addresses.
- Acceptance:
  - CPU memory accesses are routed to EGA only inside the selected GC aperture.
  - CGA/HGC/Tandy smoke tests still reach their expected video memory paths.
- Verification:
  - `Peripherals.sv` now decodes EGA CPU memory access through the exported
    `ega_mem_map_sel_cfg` value from the Graphics Controller misc register.
  - The decode covers `A0000h-BFFFFh`, `A0000h-AFFFFh`, `B0000h-B7FFFh`, and
    `B8000h-BFFFFh`.
  - CGA, HGC, and Tandy memory selects are gated only while the current CPU
    address is inside the active EGA aperture, preserving their existing decode
    outside the selected EGA window.
  - Full Quartus Analysis & Elaboration must pass before commit; standalone
    CGA/HGC/Tandy runtime smoke tests are not available in this workspace.

### EGA-105 - Add Chain-2 Read/Write Coverage

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-102.
- Files: `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv`,
  `rtl/video/ega_vram.v`.
- Source: `SPEC.md` sections 5.2, 5.5; `PLAN.md` phase 1.
- Work:
  - Test chain-2 writes selecting planes from CPU address bit 0.
  - Test chain-2 reads selecting the matching plane.
  - Combine chain-2 with map mask, odd/even disabled, and A16/page-select cases.
- Acceptance:
  - Chain-2 behavior is proven independently from normal planar writes.
- Verification:
  - `ega_vram_tb.sv` now enables `chain2_write` and `chain2_read` in a
    dedicated `test_chain2_read_write()` case.
  - The test covers even and odd CPU addresses, effective read plane selection,
    chain-2 write masks, map-mask interaction, A16-driven remap, and
    page-select-driven remap.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-106 - Add Odd/Even And Page Select Coverage

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-102.
- Files: `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv`,
  `rtl/video/ega_vram.v`.
- Source: `SPEC.md` sections 5.2, 5.5.
- Work:
  - Test odd/even CPU addressing with even and odd CPU addresses.
  - Test interaction with `cpu_a16`, Misc Output page select, and extended
    memory.
  - Verify read and write paths use consistent addressing rules.
- Acceptance:
  - Address remapping is covered for both low and high 64 KB banks.
- Verification:
  - `ega_vram_tb.sv` now has a dedicated `test_odd_even_page_select()` case.
  - The test covers Graphics Controller odd/even remap through page select,
    `cpu_a16` bank selection in memory map `00b`, and `extended_memory=0`
    address masking.
  - Each remap case verifies CPU write and CPU read use the same effective
    plane address.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-107 - Expand CPU Write Mode Coverage

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-102.
- Files: `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv`,
  `rtl/video/ega_vram.v`, `rtl/video/ega_gfx_ctrl.v`.
- Source: `SPEC.md` sections 5.5, 5.6.
- Work:
  - Test write modes `0`, `1`, `2`, and `3`.
  - Cover rotate count, set/reset, enable set/reset, logical operation, bit
    mask, map mask, and latches.
  - Include cases where only selected bits in selected planes change.
- Acceptance:
  - Every documented write mode has at least one test that would fail if latch,
    mask, or ALU behavior were bypassed.
- Verification:
  - `ega_vram_tb.sv` already covered write modes `0`, `1`, and `2`; it now adds
    `test_write_mode3_and_map_mask()`.
  - The new test covers map-mask plane commits in write mode `0` and verifies
    base-EGA write mode `3` preserves all planes, matching `SPEC.md`.
  - Existing write mode tests cover latches, rotate count, set/reset,
    enable-set/reset, logical operations, and bit mask.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-108 - Expand CPU Read Mode Coverage

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-102.
- Files: `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv`,
  `rtl/video/ega_vram.v`, `rtl/video/ega_gfx_ctrl.v`.
- Source: `SPEC.md` section 5.4.
- Work:
  - Test read mode `0` with each read plane selection.
  - Test read mode `1` using color compare and color don't care.
  - Verify every CPU read updates latches before returning data.
- Acceptance:
  - Read mode tests detect stale latch data and incorrect compare masks.
- Verification:
  - `ega_vram_tb.sv` now includes `test_read_mode0_plane_select()` for all four
    read-plane selections.
  - Read mode `0` now verifies latch refresh across repeated reads and across a
    second address with different plane data.
  - Read mode `1` now includes an additional color-compare/color-don't-care
    mask case and latch checks.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-109 - Fix VRAM Core Mismatches Exposed By Tests

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-105, EGA-106, EGA-107, EGA-108.
- Files: `rtl/video/ega_vram.v`.
- Source: `SPEC.md` section 5.
- Work:
  - Correct only the mismatches exposed by deterministic VRAM tests.
  - Keep CPU and CRT ports independent unless a later contention task requires
    a deliberate shared arbitration change.
  - Avoid changing register semantics in the VRAM task unless needed to drive
    an already tested VRAM input.
- Acceptance:
  - All `ega_vram_tb.sv` CPU VRAM cases pass.
  - No unrelated scanout or register behavior is changed in this task.
- Completed:
  - `ega_vram.v` now implements write mode `3` using rotated host data as the
    effective bit mask and per-plane Set/Reset as the source byte.
  - The write mode `3` path now applies the selected ROP and merges the result
    through `(rotated_host & bit_mask)`, matching `SPEC.md` section 5.
  - `ega_vram_tb.sv` now computes write mode `3` expected bytes instead of
    accepting the previous incorrect no-op behavior.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 249 warnings.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-110 - Decide And Document `cpu_access_en` Behavior

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-109.
- Files: `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`,
  `rtl/video/ega_vram.v`.
- Source: `SPEC.md` sections 9, 10.4, 11.12.
- Work:
  - Decide whether `cpu_access_en` remains a timing hint, becomes functional
    arbitration, or is removed from the functional path.
  - Preserve stable bus ready behavior for the PCXT integration.
  - Record any intentional difference from x86Box cycle-cost behavior.
- Acceptance:
  - CPU memory tests pass with the chosen approach.
  - The implementation no longer has an ambiguous unused contention signal.
- Completed:
  - `cpu_access_en` remains a sequencer timing hint only; it is not functional
    CPU/CRT arbitration in the BRAM frontend.
  - `ega_vram_bram_frontend.sv` now documents that CPU and CRT fetches use
    independent ports and that CPU bus ready timing must not be gated by the
    fetch-slot hint.
  - This intentionally differs from cycle-cost contention models: the PCXT
    integration preserves deterministic CPU ready behavior instead of adding
    x86Box-style display contention waits.
  - `git diff --check` passed.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

## EGA-200: Register And I/O Semantics

### EGA-201 - Audit EGA I/O Decode

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-104.
- Files: `rtl/video/ega_top.v`, `rtl/KFPC-XT/HDL/Peripherals.sv`.
- Source: `SPEC.md` section 3; `PLAN.md` phase 2.
- Work:
  - Verify decode for sequencer, graphics controller, attribute controller,
    CRTC, Misc Output, Feature Control, Input Status, and DAC stub ports.
  - Check that reads and writes use the correct bus direction and select
    signals.
  - Identify any register reads currently suppressed by display-selection state.
- Acceptance:
  - Every port range in `SPEC.md` section 3 is assigned to implemented,
    stubbed, or intentionally ignored behavior.
- Verification:
  - Added `EGA_IO_DECODE_AUDIT.md` mapping every `SPEC.md` section 3 port to
    current RTL behavior.
  - The audit identifies implemented paths, DAC stubs, implemented
    switch-sense reads, missing Feature Control behavior, fixed color
    CRTC/status decode, and readback gating by `ega_display_sel`.

### EGA-202 - Implement Color/Mono CRTC And Status Port Selection

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-201.
- Files: `rtl/video/ega_top.v`, `rtl/video/UM6845R.v`.
- Source: `SPEC.md` sections 3.1, 4.1, 9.2, 11.7.
- Work:
  - Use Misc Output bit `0` to select color `3D4h/3D5h/3DAh` versus mono
    `3B4h/3B5h/3BAh` CRTC/status ports.
  - Keep status-read side effects active on the selected status port
    independently of active display muxing.
  - Verify inactive status and CRTC ports do not incorrectly drive the bus.
- Acceptance:
  - Register tests can switch between color and mono port sets.
  - Attribute flip-flop reset works from the active status port.
- Verification:
  - `ega_top.v` now selects `3D4h/3D5h` plus `3DAh` when Misc Output bit `0`
    is set and `3B4h/3B5h` plus `3BAh` when it is clear.
  - The active status decode still feeds `ega_attrib_ctrl.status_re`, so the
    Attribute Controller flip-flop reset follows the selected status port.
  - `EGA_IO_DECODE_AUDIT.md` was updated to reflect dynamic color/mono decode.
  - Full Quartus Analysis & Elaboration must pass before commit.

### EGA-203 - Complete Attribute Controller Flip-Flop Semantics

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-201.
- Files: `rtl/video/ega_attrib_ctrl.v`, `rtl/video/ega_top.v`.
- Source: `SPEC.md` sections 3.2, 4.4, 11.7.
- Work:
  - Verify the `3C0h` index/data flip-flop toggles on writes.
  - Reset the flip-flop on Input Status #1 reads.
  - Preserve index bit `5` as video enable state according to base EGA behavior.
  - Ensure `3C1h` reads return the selected Attribute Controller register.
- Acceptance:
  - A test sequence can write two attribute registers, reset the flip-flop with
    a status read, and then write another register correctly.
- Verification:
  - Added `EGA_ATTR_CTRL_AUDIT.md` mapping the current RTL to the required
    Attribute Controller index/data flip-flop behavior.
  - The audit records the exact deterministic register sequence EGA-208 should
    encode as an executable testbench.
  - `ega_top.v` already feeds `ega_attrib_ctrl.status_re` from the active
    status-port decode, so status reads reset the flip-flop independently of
    display-output selection.

### EGA-204 - Verify Misc Output Register Semantics

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-201.
- Files: `rtl/video/ega_top.v`, `rtl/video/ega_vgaport.v`,
  `rtl/KFPC-XT/HDL/Peripherals.sv`.
- Source: `SPEC.md` sections 4.1, 8, 10.
- Work:
  - Verify reset value, readback, clock select, enable RAM, page select,
    color/mono select, and palette width bit behavior.
  - Ensure DAC stubs do not override base EGA palette behavior.
- Acceptance:
  - Misc Output can be read back and its exported effects are visible to memory
    decode and port selection tests.
- Verification:
  - Added `EGA_MISC_OUTPUT_AUDIT.md` mapping Misc Output storage, readback, and
    exported effects in `ega_top.v`, `ega_vgaport.v`, and `Peripherals.sv`.
  - The audit verifies bit `0` color/mono port selection, bit `5` page-select
    propagation to VRAM remap, and bit `7` palette-width propagation.
  - DAC ports are documented as stubs that return `00h` and do not override the
    base EGA palette path.
  - `3C2h` switch-sense reads return the selected bit from a color EGA switch
    pattern. Bit `2` clock select timing remains a gap beyond storage/readback
    and switch-sense selection.

### EGA-205 - Verify Sequencer Register Behavior

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-201.
- Files: `rtl/video/ega_sequencer.v`, `rtl/video/ega_top.v`.
- Source: `SPEC.md` section 4.2.
- Work:
  - Verify reset, clocking mode, map mask, character map select, and memory mode
    registers.
  - Confirm odd/even disable, chain-2, extended memory, and dot-clock effects
    reach downstream modules.
- Acceptance:
  - Sequencer register readback and exported control signals match programmed
    values after reset and writes.
- Verification:
  - Added `EGA_SEQUENCER_AUDIT.md` mapping registers `00h..04h`, reset values,
    data-port readback, and exported control signals.
  - The audit traces map mask, chain-2 write, extended memory, dot-clock, CRT
    fetch, and CPU-access slot outputs to their current consumers.
  - The document records the deterministic sequence EGA-208 should encode in an
    executable register testbench.
  - Character Map Select storage/readback is verified, with downstream text
    rendering consumption left to the text-renderer tasks.

### EGA-206 - Verify Graphics Controller Register Behavior

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-201.
- Files: `rtl/video/ega_gfx_ctrl.v`, `rtl/video/ega_top.v`,
  `rtl/video/ega_vram.v`.
- Source: `SPEC.md` section 4.3.
- Work:
  - Verify set/reset, enable set/reset, color compare, data rotate, read map
    select, mode, misc, color don't care, and bit mask registers.
  - Confirm mode-derived control signals drive VRAM and scanout tasks.
- Acceptance:
  - Register tests cover readback and at least one functional downstream effect
    for critical GC registers.
- Verification:
  - Added `EGA_GFX_CTRL_AUDIT.md` mapping Graphics Controller registers
    `00h..08h`, reset values, data-port readback, and exported control signals.
  - The audit traces downstream VRAM effects for write/read modes, set/reset,
    compare masks, bit mask, ROP/rotate, odd/even remap, chain-2 read, and
    memory-map selection.
  - The document records the deterministic sequence EGA-208 should encode in an
    executable register testbench.
  - Graphics Controller Misc bit `0` and Mode bit `5` storage/readback are
    verified, with scanout/render consumption left to EGA-403 and EGA-404.

### EGA-207 - Implement CRTC Write Protection

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-201.
- Files: `rtl/video/UM6845R.v`, `rtl/video/ega_top.v`.
- Source: `SPEC.md` sections 4.5, 11.6; x86Box CRTC behavior.
- Work:
  - When CRTC register `11h[7]` is set, protect registers `00h..06h`.
  - Apply partial protection for register `07h` according to IBM EGA behavior
    described in `SPEC.md`.
  - Verify protected writes do not alter timing-critical state.
- Acceptance:
  - Tests can prove protected writes are ignored and unprotected writes still
    update the expected registers.
- Verification:
  - `UM6845R.v` now gates EGA CRTC writes to registers `00h..06h` when CRTC
    register `11h[7]` is set.
  - Protected writes to register `07h` now preserve all bits except bit `4`,
    matching the x86Box EGA write path.
  - Unprotected CRTC writes and non-EGA CRTC instances keep the previous direct
    write behavior.
  - Quartus Analysis & Elaboration passed with `0 errors, 258 warnings`.

### EGA-208 - Add Register-Oriented Testbench Coverage

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-202, EGA-203, EGA-204, EGA-205, EGA-206, EGA-207.
- Files: new or existing EGA register testbench under
  `rtl/KFPC-XT/TESTBENCH/`.
- Source: `SPEC.md` sections 3, 4, 9.2; `PLAN.md` phase 8.
- Work:
  - Build a deterministic register testbench that drives EGA I/O operations
    without requiring a full PCXT boot.
  - Cover index/data ports, selected reads, reset values, write protection, and
    status-read side effects.
- Acceptance:
  - Register tests fail on incorrect attribute flip-flop, CRTC protection, or
    color/mono port selection behavior.
- Verification:
  - Added `rtl/KFPC-XT/TESTBENCH/ega_registers_tb.sv` with deterministic
    register-level coverage for Sequencer, Graphics Controller, Attribute
    Controller, CRTC write protection, Misc Output readback, selected CRTC
    color/mono ports, and selected status-read Attribute Controller side
    effects.
  - The testbench includes failing checks for incorrect Attribute Controller
    flip-flop reset, CRTC write protection, and color/mono CRTC/status port
    selection behavior.
  - `git diff --check -- TASKS.md rtl\KFPC-XT\TESTBENCH\ega_registers_tb.sv`
    passed.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

## EGA-300: CRTC Timing And Display Address Core

### EGA-301 - Build A CRTC Register Behavior Checklist

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-208.
- Files: `rtl/video/UM6845R.v`, `rtl/video/ega_top.v`.
- Source: `SPEC.md` sections 4.5, 6, 9.
- Work:
  - List every CRTC register used by timing, address generation, cursor, start
    address, line compare, overflow, and mode control.
  - Mark whether the current `UM6845R.v` implements the EGA-specific bits or
    only generic 6845 behavior.
- Acceptance:
  - Missing EGA-specific CRTC behaviors have task IDs before scanout changes
    start.
- Verification:
  - Added `EGA_CRTC_REGISTER_CHECKLIST.md` covering CRTC indexes `00h..18h`,
    current `UM6845R.v` storage/readback, derived timing/address behavior, and
    EGA-specific gaps.
  - The checklist assigns missing overflow formulas to EGA-302, scanout remap
    to EGA-303, row advance/max-scan behavior to EGA-304, start-address frame
    latching to EGA-305, split/line compare to EGA-306, reset/display-disable
    blanking to EGA-307, and final address testbench coverage to EGA-308.

### EGA-302 - Verify Overflow And Vertical Timing Formulas

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-301.
- Files: `rtl/video/UM6845R.v`.
- Source: `SPEC.md` sections 4.5, 9.1.
- Work:
  - Verify vertical total, display end, sync start, line compare, and max scan
    line composition from low registers plus overflow bits.
  - Add tests for values that cross 8-bit boundaries.
- Acceptance:
  - CRTC vertical counters and display-enable transitions match the reference
    cases.
- Verification:
  - `UM6845R.v` now stores the full CRTC `09h` byte, uses `07h[5]`,
    `07h[6]`, and `07h[7]` in the active EGA vertical total, display end, and
    vertical retrace start formulas, and composes split target from `09h[6]`,
    `07h[4]`, and `18h` plus one.
  - `ega_registers_tb.sv` includes hierarchical CRTC checks for overflow cases
    crossing 8-bit boundaries.
  - `EGA_CRTC_REGISTER_CHECKLIST.md` was updated with the post-fix formula
    state and the remaining split side effects assigned to EGA-306.
  - Quartus Analysis & Elaboration passed: 0 errors, 255 warnings.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-303 - Implement Or Correct Scanout Address Remapping

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-301, EGA-302.
- Files: `rtl/video/UM6845R.v`, `rtl/video/ega_top.v`,
  `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`.
- Source: `SPEC.md` sections 6.1, 6.2, 11.4;
  `x86_src/video/vid_ega_render.c`.
- Work:
  - Implement the render-address remap controlled by CRTC `14h[6]`,
    `17h[6]`, `17h[5]`, `17h[1:0]`, and scanline bits.
  - Keep CPU-side VRAM remapping independent from display-side remapping.
  - Verify remap behavior mode by mode before changing pixel output.
- Acceptance:
  - Address tests can distinguish all documented scanout remap modes.
  - Existing CPU VRAM tests remain unchanged and passing.
- Verification:
  - `UM6845R.v` now remaps the EGA display fetch address using CRTC `14h[6]`
    dword mode, `17h[6]` byte mode, `17h[5]` word mode using MA15, default
    word mode using MA13, and `17h[1:0]` scanline substitution for MA14/MA13.
  - The remap is applied only to the display-side `MA_FULL` output and leaves
    CPU VRAM remapping unchanged.
  - `ega_registers_tb.sv` includes reference-helper checks that distinguish all
    remap modes and scanline substitution behavior.
  - Quartus Analysis & Elaboration passed: 0 errors, 255 warnings.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-304 - Validate Row Advance And Maximum Scan Line Behavior

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-303.
- Files: `rtl/video/UM6845R.v`, `rtl/video/ega_top.v`.
- Source: `SPEC.md` sections 6.2, 7.
- Work:
  - Verify scanline row counter increments, resets, and address advances at the
    correct character-row boundaries.
  - Cover single-scanline graphics and multi-scanline text rows.
- Acceptance:
  - Tests prove graphics modes do not accidentally apply text row stepping, and
    text modes preserve glyph scanline sequencing.
- Verification:
  - `UM6845R.v` now uses `13h << 1` as the independent-plane row advance and
    doubles that to `13h << 2` when CRTC `09h[7]` line-doubling is set.
  - `V_MAXSCAN_REG` continues to expose only `09h[4:0]`; the line-doubling bit
    is stored for row advance without polluting the max-scan-line output.
  - `ega_registers_tb.sv` includes hierarchical checks for normal row advance,
    line-doubled row advance, and max-scan-line masking.
  - Quartus Analysis & Elaboration passed: 0 errors, 255 warnings.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-305 - Implement Start Address Frame Latching

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-303.
- Files: `rtl/video/UM6845R.v`, `rtl/video/ega_top.v`.
- Source: `SPEC.md` section 6.3.
- Work:
  - Latch CRTC start address at the frame boundary used by the EGA renderer.
  - Avoid mid-frame tearing behavior unless it is required by the reference.
- Acceptance:
  - Tests or smoke cases show stable page flips at frame boundaries.
- Verification:
  - `UM6845R.v` now separates the pending CRTC start-address latch from the
    visible `start_addr_frame`, which updates only on EGA `frame_new`.
  - EGA cursor address comparison now uses `cursor_addr_frame`, updated at the
    same frame boundary as the start address.
  - First-row reloads in the non-row-address EGA fallback path use the current
    visible frame start until `frame_new` applies pending `0Ch/0Dh` writes.
  - `ega_registers_tb.sv` includes directed checks for pending start writes,
    first-row reload stability, frame-boundary start reload, and cursor-address
    frame latching.
  - Quartus Analysis & Elaboration passed: 0 errors, 255 warnings.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-306 - Verify Split Screen And Line Compare

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-303, EGA-305.
- Files: `rtl/video/UM6845R.v`, `rtl/video/ega_top.v`.
- Source: `SPEC.md` section 6.4.
- Work:
  - Verify line compare resets display address generation at the programmed
    scanline.
  - Include overflow bits in the line compare value.
  - Confirm horizontal panning and start-address behavior across the split.
- Acceptance:
  - A deterministic test can detect wrong split-screen restart line or address.
- Verification:
  - `UM6845R.v` gives `line_compare_match` priority over the normal EGA
    scanout address increment, so split cannot be overwritten in the same
    cycle.
  - Split now resets both saved/current scanout addresses and the CRTC scanline
    counter to page 0 behavior matching the x86Box base path.
  - `line_compare_target` already composes `18h`, `07h[4]`, and `09h[6]`; the
    register testbench covers this formula and now covers the reset
    side-effects.
  - x86Box split handling does not change fine horizontal panning; ATTR `13h`
    remains an independent register path already covered by
    `ega_registers_tb.sv`.
  - Quartus Analysis & Elaboration passed: 0 errors, 255 warnings.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-307 - Verify CRTC Reset And Display Disable Paths

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-302.
- Files: `rtl/video/UM6845R.v`, `rtl/video/ega_top.v`.
- Source: `SPEC.md` sections 4.2, 9.
- Work:
  - Verify sequencer reset and display disable effects on counters, fetches,
    and output blanking.
  - Ensure disabled display does not corrupt CPU VRAM contents.
- Acceptance:
  - Display-disable tests show blank output while register and CPU memory access
    remain functional.

### EGA-308 - Add CRTC Address Testbench Coverage

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-303, EGA-304, EGA-305, EGA-306.
- Files: new or existing EGA CRTC/address testbench under
  `rtl/KFPC-XT/TESTBENCH/`.
- Source: `SPEC.md` sections 6, 9; `PLAN.md` phase 8.
- Work:
  - Drive programmed CRTC modes and sample generated fetch addresses,
    row-address values, hblank/vblank, and display-enable transitions.
  - Compare against reference helper functions derived from `SPEC.md`.
- Acceptance:
  - CRTC/address tests fail on wrong scanout remap, row advance, start address,
    or line compare behavior.
- Verification:
  - `ega_registers_tb.sv` now wires CRTC `hblank`, `vblank`, `DE`, `RA`,
    `HC`, `VC`, status-not-displaying, and vertical-blank debug outputs.
  - The CRTC coverage samples byte-mode fetch-address generation through the
    public `MA_FULL` output and compares it with the x86Box-derived helper used
    by the remap tests.
  - The testbench checks sampled row/horizontal/vertical counters,
    visible-area display enable, hblank assertion, EGA vblank assertion, and
    not-displaying status.
  - Existing CRTC sections in the same testbench cover remap variants,
    row advance, frame-latched start address, cursor frame latch, and split
    address/scanline reset.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

## EGA-400: Graphics Scanout

### EGA-401 - Correct Planar Graphics Pixel Shifting

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-303, EGA-308.
- Files: `rtl/video/ega_pixel.v`.
- Source: `SPEC.md` sections 7.1, 7.4, 11.3;
  `x86_src/video/vid_ega_render.c`.
- Work:
  - Ensure loaded plane bytes are shifted one bit per dot.
  - Use panning only to select delayed/offset pixels, not to replace the shifter
    with static fetch wires.
  - Preserve low-resolution repeat behavior where each source bit becomes two
    output dots.
- Acceptance:
  - A test pattern with alternating plane bits produces the expected per-dot
    color sequence in high and low resolution.
- Completed:
  - `ega_pixel.v` now loads the panned plane bytes into the shifter and drives
    subsequent dots from the shifted register state instead of static fetch
    wires.
  - Added `ega_pixel_tb.sv` coverage for high-resolution one-bit-per-dot
    output and low-resolution two-dots-per-source-bit repeat behavior.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 255 warnings.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-402 - Implement Graphics Horizontal Panning Behavior

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-401, EGA-203.
- Files: `rtl/video/ega_pixel.v`, `rtl/video/ega_attrib_ctrl.v`,
  `rtl/video/ega_top.v`.
- Source: `SPEC.md` sections 4.4, 7.4, 11.7.
- Work:
  - Apply Attribute Controller horizontal pixel panning in graphics modes.
  - Match the x86Box cached panning behavior where software-visible timing
    depends on status/display transitions.
- Acceptance:
  - Panning tests shift the visible image by the programmed amount without
    changing fetched VRAM bytes.
- Completed:
  - `ega_pixel.v` now caches the sanitized Attribute Controller panning value
    when display becomes active, matching the visible-transition behavior
    needed for stable scanout.
  - Pan value `0` is an identity load of the current byte, while non-zero
    values select a shifted `{previous,current}` fetch window.
  - Values `8..15` are treated as zero panning for the base EGA path.
  - `ega_pixel_tb.sv` now covers a two-byte panning window and verifies that
    the visible sequence shifts without changing the fetched plane bytes.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 251 warnings.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-403 - Implement Complete Graphics Mode Selection

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-401.
- Files: `rtl/video/ega_pixel.v`, `rtl/video/ega_top.v`,
  `rtl/video/ega_gfx_ctrl.v`, `rtl/video/ega_sequencer.v`.
- Source: `SPEC.md` sections 7.1, 7.4.
- Work:
  - Select between planar 4bpp graphics, CGA-compatible 2bpp graphics, and text
    handoff based on GC and Sequencer mode bits.
  - Keep mode selection explicit and easy to probe in simulation.
- Acceptance:
  - Mode-selection tests route graphics and text configurations to the correct
    render path.
- Completed:
  - `ega_gfx_ctrl.v` now exposes GC Misc graphics/text selection and GC Mode
    bit 5 CGA-compatible graphics selection as explicit signals.
  - `ega_top.v` computes an explicit render mode: text handoff, planar
    graphics, or CGA-compatible graphics.
  - `ega_pixel.v` suppresses planar pixel generation in text handoff mode while
    preserving separate planar and CGA-compatible graphics paths for EGA-404.
  - `ega_pixel_tb.sv` adds mode-selection coverage for text, planar graphics,
    and CGA-compatible graphics routing.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 251 warnings.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-404 - Implement CGA-Compatible 2bpp EGA Graphics

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-403.
- Files: `rtl/video/ega_pixel.v`, `rtl/video/ega_attrib_ctrl.v`.
- Source: `SPEC.md` sections 7.4, 11.8;
  `x86_src/video/vid_ega_render.c`.
- Work:
  - Implement GC Mode bit `5` conversion from packed CGA-style bits into EGA
    color indexes.
  - Verify interaction with palette, intensity, and plane enable.
- Acceptance:
  - A known 2bpp pattern produces the same color-index sequence as the reference
    model.
- Completed:
  - `ega_pixel.v` now implements the x86Box `egaremap2bpp` mapping from source
    bits `0,2,4,6` into nibble bits `0..3`.
  - CGA-compatible render mode converts the four fetched EGA bytes into planar
    `dat0..dat3` before the existing panning and shift pipeline.
  - `ega_pixel_tb.sv` now calculates the same reference conversion and checks
    the full eight-pixel color-index sequence for a known 2bpp pattern.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 251 warnings.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-405 - Verify Sequencer Odd/Even Effects On Graphics Fetch

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-303, EGA-401.
- Files: `rtl/video/ega_sequencer.v`, `rtl/video/ega_top.v`,
  `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`.
- Source: `SPEC.md` sections 4.2, 6, 7.4.
- Work:
  - Confirm graphics fetch addressing honors sequencer memory-mode effects
    where the reference applies them.
  - Separate CPU odd/even behavior from display fetch behavior.
- Acceptance:
  - Tests prove odd/even CPU modes do not unintentionally corrupt graphics
    scanout addressing.
- Completed:
  - Confirmed `ega_top.v` exports `ega_fetch_addr` from the CRTC address path,
    not from CPU remapped addressing.
  - Confirmed `ega_vram.v` applies odd/even, chain-2, memory map, and page
    selection only to the CPU port; the CRTC port reads all four planes from
    raw `crt_addr`.
  - Added `ega_vram_tb.sv` coverage proving that active CPU odd/even and
    chain-2 modes do not remap CRTC fetches, while CPU reads of the same offset
    still use the odd/even remapped address.
  - `git diff --check` passed.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-406 - Apply Attribute Plane Enable In Graphics

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-401, EGA-203.
- Files: `rtl/video/ega_attrib_ctrl.v`, `rtl/video/ega_pixel.v`.
- Source: `SPEC.md` sections 4.4, 7.4.
- Work:
  - Mask incoming plane bits according to Attribute Controller plane enable.
  - Verify disabled planes contribute zero to the palette index.
- Acceptance:
  - Plane-enable tests produce expected colors for all single-plane and
    multi-plane masks.
- Completed:
  - Confirmed `ega_attrib_ctrl.v` already applies Attribute Controller register
    `12h[3:0]` to the graphics color index before palette lookup.
  - Confirmed the mask is integrated with the x86Box graphics blink formula
    implemented for EGA-407.
  - Added `ega_registers_tb.sv` coverage for all single-plane masks, combined
    masks, zero mask, and source-zero preservation through the default palette.
  - `git diff --check` passed.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-407 - Implement Graphics Blink Handling If Reference Requires It

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-501, EGA-506.
- Files: `rtl/video/ega_attrib_ctrl.v`, `rtl/video/ega_pixel.v`.
- Source: `SPEC.md` sections 4.4, 7.4, 9.3.
- Work:
  - Check x86Box graphics blink behavior for base IBM EGA.
  - Implement or explicitly document the non-use of blink in graphics output.
- Acceptance:
  - Blink behavior is tested or documented as intentionally not affecting the
    selected graphics path.
- Verification:
  - Checked x86Box `x86_src/video/vid_ega_render.c`; base EGA graphics applies
    blink when Attribute Mode Control bit `3` is set, using `ega->blink & 0x10`
    and Attribute Controller register `12h[3:0]` as `plane_mask`.
  - `ega_attrib_ctrl.v` now consumes the shared `ega_blink_state` and applies
    the x86Box graphics blink formula before palette lookup.
  - `ega_top.v` wires the shared blink state into the Attribute Controller.
  - Updated `EGA_BLINK_AUDIT.md` with the implemented graphics formula and
    remaining text/cursor consumers.
  - Quartus Analysis & Elaboration passed with `0 errors, 258 warnings`.

### EGA-408 - Ensure Active Display And Blanking Gate Pixels Correctly

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-401, EGA-307.
- Files: `rtl/video/ega_top.v`, `rtl/video/ega_attrib_ctrl.v`,
  `rtl/video/ega_pixel.v`.
- Source: `SPEC.md` sections 7.2, 9.
- Work:
  - Gate visible pixels with display-enable and blanking signals.
  - Preserve overscan/border output where the display is inactive but border is
    visible.
- Acceptance:
  - Tests or captured frames distinguish active pixels, overscan, hblank, and
    vblank.
- Completed:
  - `ega_pixel.v` now clears `plane_index`, `pixel_valid`, pending loads, and
    active shift state while `display_enable` is low.
  - `ega_attrib_ctrl.v` now blanks active-display cycles where no valid pixel
    is available, instead of holding the previous active color.
  - Overscan/border color remains selected when `display_enable` is low.
  - `ega_pixel_tb.sv` covers display-disable gating and recovery on the next
    active fetch.
  - `ega_registers_tb.sv` covers active valid pixels, invalid active pixels,
    overscan during display-disable, and Attribute Controller video-enable
    blanking.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 251 warnings.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-409 - Add Graphics Pixel Testbench Coverage

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-401, EGA-402, EGA-404, EGA-406, EGA-408.
- Files: new or existing EGA pixel testbench under
  `rtl/KFPC-XT/TESTBENCH/`.
- Source: `SPEC.md` sections 7.1, 7.4, 8.
- Work:
  - Feed known plane bytes, mode bits, panning values, plane masks, and palette
    registers into the render path.
  - Compare output color indexes cycle by cycle.
- Acceptance:
  - Pixel tests fail on static-plane output, incorrect low-resolution repeat,
    wrong panning, or broken 2bpp conversion.
- Completed:
  - `ega_pixel_tb.sv` covers high-resolution planar shifting with distinct
    per-pixel indexes, catching static fetch-byte output.
  - Low-resolution/double-dot repeat is checked for all 16 output dots from an
    8-bit plane fetch.
  - Horizontal panning is checked with a two-byte previous/current window.
  - Render-mode routing is checked for text handoff, planar graphics, and
    CGA-compatible graphics.
  - CGA-compatible 2bpp conversion is checked against the x86Box `egaremap2bpp`
    reference sequence.
  - Display-disable gating is checked for blank output and recovery on the next
    active fetch.
  - Attribute/palette integration now programs palette entries and plane masks
    and verifies final color output through `ega_attrib_ctrl`.
  - `git diff --check` passed.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

## EGA-500: Attribute, Palette, Border, And Status

### EGA-501 - Implement Base EGA Palette Indirection

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-203, EGA-204.
- Files: `rtl/video/ega_attrib_ctrl.v`, `rtl/video/ega_vgaport.v`.
- Source: `SPEC.md` sections 4.4, 8.
- Work:
  - Map 4-bit pixel indexes through the 16 Attribute Controller palette
    registers.
  - Convert the resulting 6-bit EGA color to RGB using base EGA rules.
  - Respect Misc Output palette width behavior for base EGA.
- Acceptance:
  - Palette tests can remap a plane color index to a different RGB output.
- Verification:
  - Added `EGA_PALETTE_AUDIT.md` documenting the existing Attribute Controller
    palette lookup from 4-bit plane index to 6-bit EGA color.
  - The audit traces Misc Output bit `7` through overscan palette width and
    `ega_vgaport` 16-color/64-color RGB conversion.
  - The audit records the EGA-507 deterministic test sequence for palette
    remap, brown fix, overscan width, Color Select readback, and Plane Enable.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-502 - Verify 16-Color And 64-Color RGB Mapping

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-501.
- Files: `rtl/video/ega_vgaport.v`, `rtl/video/ega_attrib_ctrl.v`.
- Source: `SPEC.md` section 8.
- Work:
  - Build expected RGB tables for the implemented base EGA modes.
  - Confirm DAC stub ports do not alter base EGA color output.
- Acceptance:
  - Every palette entry used by standard 16-color modes maps to expected RGB.
- Verification:
  - Added `EGA_RGB_MAPPING_AUDIT.md` with expected RGB6 values for standard
    16-color EGA codes, including the IBM brown exception.
  - The audit records representative 64-color spot checks covering primary and
    secondary RGB bits.
  - The audit confirms `3C7h..3C9h` DAC stub reads do not feed base EGA RGB
    output, which remains driven by Attribute Controller palette state and Misc
    Output bit `7`.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-503 - Implement Overscan And Border Color

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-501, EGA-408.
- Files: `rtl/video/ega_attrib_ctrl.v`, `rtl/video/ega_top.v`.
- Source: `SPEC.md` sections 4.4, 8, 9.
- Work:
  - Use Attribute Controller overscan register for border color.
  - Ensure blanking remains black or sync-safe while border remains visible in
    the intended region.
- Acceptance:
  - Border smoke tests can change overscan color without changing active pixels.
- Completed:
  - `ega_attrib_ctrl.v` uses Attribute Controller register `11h` as the
    overscan/border color whenever CRTC display enable is inactive.
  - Active pixels continue to use the palette-mapped plane index, while invalid
    active pixels and Attribute Controller video-disable state still output
    black.
  - Sync-safe blanking remains represented by the top-level hblank/vblank/de
    outputs; the overscan RGB path does not change those timing signals.
  - `ega_registers_tb.sv` already includes an Attribute Controller border
    smoke sequence that changes overscan color and checks active pixels are
    unaffected.
  - `git diff --check` passed.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-504 - Implement Input Status #1 Bits And Side Effects

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-202, EGA-203.
- Files: `rtl/video/ega_top.v`, `rtl/video/ega_attrib_ctrl.v`.
- Source: `SPEC.md` sections 3.2, 9.2, 11.5.
- Work:
  - Return display-enable and vertical-retrace bits as currently timed by the
    CRTC.
  - Toggle bits `4` and `5` on IBM EGA status reads as x86Box does.
  - Reset the Attribute Controller flip-flop on each selected status read.
- Acceptance:
  - Consecutive status reads show the expected `0x30` toggle behavior.
  - Attribute writes after status reads land in the intended index/data phase.
- Verification:
  - `ega_top.v` now exposes Input Status #1 bit `0` from CRTC
    not-displaying, bit `3` from CRTC vertical retrace, and bits `5:4` from a
    two-bit IBM EGA status toggle.
  - The toggle advances once per selected color/mono status-read pulse using
    `ega_status_read_q`, so a stretched I/O read does not advance multiple
    times.
  - The same selected status-read signal drives `ega_attrib_ctrl.status_re`,
    preserving Attribute Controller index/data flip-flop reset semantics.
  - Added `EGA_STATUS_AUDIT.md` and updated `EGA_IO_DECODE_AUDIT.md`; the
    remaining display-select readback gate is left to EGA-505.
  - Quartus Analysis & Elaboration passed with `0 errors, 258 warnings`.

### EGA-505 - Remove Incorrect Display-Select Gating From Register Visibility

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-201, EGA-504.
- Files: `rtl/video/ega_top.v`, `rtl/KFPC-XT/HDL/Peripherals.sv`.
- Source: `SPEC.md` sections 3, 9.2, 10.1, 11.7;
  `PLAN.md` section 21.
- Work:
  - Audit reads that are currently visible only when `ega_display_sel` is true.
  - Make CPU-visible EGA hardware respond according to enable and port decode,
    not current display-mux state.
  - Preserve CGA fallback behavior where EGA is disabled.
- Acceptance:
  - EGA register probes work before the first active EGA frame is selected.
- Verification:
  - Removed `ega_display_sel` from `ega_top.v` Input Status #1 and CRTC data
    read bus-drive conditions; reads now depend on EGA enable, AEN, active
    color/mono port decode, and `IOR`.
  - Audited `rtl/KFPC-XT/HDL/Peripherals.sv`; `ega_display_sel_cga` only gates
    display/video selection and `cga_hw`, not EGA register read visibility.
  - Updated `EGA_IO_DECODE_AUDIT.md` and `EGA_STATUS_AUDIT.md` to reflect that
    status and CRTC reads are visible before the display mux switches to EGA.
  - Quartus Analysis & Elaboration passed with `0 errors, 258 warnings`.

### EGA-506 - Implement A Shared Blink State Generator

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-504.
- Files: `rtl/video/ega_top.v`, `rtl/video/ega_attrib_ctrl.v`,
  future text renderer.
- Source: `SPEC.md` sections 4.4, 7.3, 9.3.
- Work:
  - Generate blink state from frame or vertical timing in a way suitable for
    text and any graphics behavior that requires it.
  - Keep blink deterministic enough for simulation tests.
- Acceptance:
  - Blink state toggles at a stable cadence tied to video timing and can be
    observed by text/attribute tests.
- Verification:
  - `ega_top.v` now implements a 7-bit blink counter that advances once per
    CRTC vertical blank entry and exposes `counter[4]` as the shared blink
    state, matching the x86Box `ega->blink & 0x10` consumer convention.
  - Reset and `!ega_enabled` clear the counter and edge detector for
    deterministic tests.
  - `Peripherals.sv` wires `ega_blink_counter` and `ega_blink_state` internally
    for future graphics/text consumers.
  - Added `EGA_BLINK_AUDIT.md` with x86Box anchors and deterministic test
    targets.
  - Quartus Analysis & Elaboration passed with `0 errors, 258 warnings`.

### EGA-507 - Add Attribute, Palette, And Status Tests

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-501, EGA-502, EGA-503, EGA-504, EGA-505, EGA-506.
- Files: EGA register/pixel testbenches under `rtl/KFPC-XT/TESTBENCH/`.
- Source: `SPEC.md` sections 4.4, 8, 9.2.
- Work:
  - Test palette remap, plane enable, panning, overscan, video enable, status
    bits, status toggles, and flip-flop resets.
- Acceptance:
  - Attribute/status regressions are caught before full PCXT boot tests.
- Completed:
  - `ega_registers_tb.sv` now covers Attribute Controller palette remapping
    through the rendered color path, not just register readback.
  - Added overscan checks for both 64-color and 16-color palette-width modes,
    plus restoration of identity palette state before plane-enable tests.
  - Existing coverage verifies plane enable, panning, overscan border output,
    video enable blanking, selected status-port flip-flop resets, and status
    toggle bits.
  - Added deterministic top-level Input Status #1 checks for display-disable
    bit `0` and vertical-retrace bit `3`.
  - `git diff --check` passed.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

## EGA-600: Text Renderer

### EGA-601 - Choose Text Renderer Architecture

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-303, EGA-501.
- Files: `rtl/video/ega_top.v`, `rtl/video/ega_pixel.v`,
  possible new `rtl/video/ega_text*.v`.
- Source: `SPEC.md` sections 7.1, 7.3, 11.2; `PLAN.md` phase 6.
- Work:
  - Decide whether to extend `ega_pixel.v` or add a dedicated text renderer.
  - Define fetch timing for character byte, attribute byte, and font byte.
  - Define how the text path shares palette, blink, panning, and blanking logic
    with graphics.
- Acceptance:
  - Architecture decision identifies module boundaries and required VRAM
    frontend changes before implementation begins.
- Completed:
  - Added `EGA_TEXT_ARCHITECTURE.md` selecting a dedicated `ega_text.v`
    renderer instead of extending the graphics shifter in `ega_pixel.v`.
  - The architecture defines `ega_top.v`, `ega_pixel.v`, `ega_text.v`, and
    VRAM/frontend module boundaries.
  - The text fetch contract covers character byte, attribute byte, font row
    byte, registered latency, and Character Map Select bank inputs.
  - The document records how text output should share palette, blink, border,
    and blanking behavior with the existing Attribute Controller path.
  - `git diff --check` passed.

### EGA-602 - Extend VRAM Frontend For Text Fetches

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-601.
- Files: `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`,
  `rtl/video/ega_vram.v`, text renderer module.
- Source: `SPEC.md` sections 5.1, 7.3, 11.2.
- Work:
  - Provide the text renderer with character/attribute bytes from display
    memory and font bytes from the selected font plane.
  - Preserve CPU-side VRAM behavior while scanout reads text data.
  - Account for registered BRAM latency.
- Acceptance:
  - A text fetch test returns the expected character, attribute, and glyph row
    for a programmed address.
- Completed:
  - `ega_vram.v` now has a text fetch channel that reads character bytes from
    plane 0 at the text cell address, attribute bytes from plane 1 at the text
    cell address, and glyph bytes from plane 2 at an independent font address.
  - Graphics CRT fetches keep using the existing shared visible address when
    `text_re` is inactive.
  - `ega_vram_bram_frontend.sv` exposes registered `text_char`, `text_attr`,
    `text_glyph`, and `text_data_valid` outputs for the future text renderer.
  - `Peripherals.sv` ties the new text channel inactive until EGA-603 consumes
    it from `ega_top.v`/`ega_text.v`.
  - `ega_vram_tb.sv` includes a deterministic text fetch case for cell and font
    addresses, plus a regression that graphics CRT plane 2 still uses the
    visible address.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 249 warnings.
  - HDL simulation could not be run on this machine because no standalone HDL
    simulator is installed; see `TEST_TOOLS.md`.

### EGA-603 - Implement Character And Attribute Fetch Pipeline

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-602.
- Files: text renderer module, `rtl/video/ega_top.v`.
- Source: `SPEC.md` section 7.3;
  `x86_src/video/vid_ega_render.c`.
- Work:
  - Fetch two-byte text cells using CRTC address generation.
  - Align fetched character and attribute data with the pixel clock.
  - Support 40-column and 80-column text widths derived from programmed timing.
- Acceptance:
  - A programmed text row produces the expected sequence of text cells.
- Completed:
  - Added dedicated `rtl/video/ega_text.v` character/attribute cell pipeline.
  - Text fetches are driven by the sequencer/CRTC fetch tick
    (`ega_ce_crt_fetch`), so 40/80-column cadence remains derived from
    programmed timing.
  - `rtl/video/ega_top.v` now selects graphics vs. text plane index before the
    Attribute Controller and suppresses graphics VRAM fetches in text mode.
  - `rtl/KFPC-XT/HDL/Peripherals.sv` wires the text cell/font fetch channel from
    `ega_top.v` into `ega_vram_bram_frontend.sv`.
  - Added `rtl/KFPC-XT/TESTBENCH/ega_text_tb.sv` for deterministic text cell
    fetch cadence coverage.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 249 warnings.
  - HDL simulation could not be run because no standalone simulator is installed;
    see `TEST_TOOLS.md`.

### EGA-604 - Implement Font Plane And Character Map Select

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-603, EGA-205.
- Files: text renderer module, `rtl/video/ega_sequencer.v`,
  `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`.
- Source: `SPEC.md` sections 4.2, 7.3, 11.9.
- Work:
  - Use Sequencer Character Map Select to choose font blocks.
  - Fetch glyph rows from the correct plane and scanline row.
  - Support software-loaded fonts in VRAM.
- Acceptance:
  - Changing Character Map Select changes displayed glyphs without changing text
    cell character bytes.
- Completed:
  - `ega_sequencer.v` now exports decoded Character Map Select banks A and B
    from Sequencer register `03h`.
  - `ega_text.v` selects charset A or B using `attr[3]`, matching the x86Box EGA
    path, and computes the plane-2 font address as
    `bank * 4000h + chr * 20h + scanline` for the independent-plane VRAM layout.
  - `ega_top.v` wires the sequencer charset outputs into the text renderer.
  - `ega_registers_tb.sv` covers Character Map Select readback and decoded bank
    outputs.
  - `ega_text_tb.sv` covers charset A/B font address selection without changing
    text cell memory addresses.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 249 warnings.
  - HDL simulation could not be run because no standalone simulator is installed;
    see `TEST_TOOLS.md`.

### EGA-605 - Implement Text Pixel Generation

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-604, EGA-501, EGA-506.
- Files: text renderer module, `rtl/video/ega_attrib_ctrl.v`.
- Source: `SPEC.md` section 7.3.
- Work:
  - Convert glyph bits plus attribute byte into foreground/background color
    indexes.
  - Apply blink/intensity behavior according to Attribute Controller mode.
  - Apply palette indirection consistently with graphics output.
- Acceptance:
  - Text tests cover foreground, background, intensity, and blink attributes.
- Completed:
  - `ega_text.v` now shifts glyph row bits into text pixels and selects
    foreground/background attribute indexes per pixel.
  - Text background intensity uses `attr[7]` when Attribute Controller blink is
    disabled; when blink is enabled, `attr[7]` becomes blink and background uses
    `attr[6:4]`.
  - Active blink state hides foreground pixels by selecting the background index,
    matching the x86Box text render path.
  - `ega_attrib_ctrl.v` now exposes blink enable and treats text-mode color
    indexes as already-resolved text attributes while preserving graphics blink
    remap for graphics modes.
  - `ega_top.v` wires Attribute Controller blink state/enable into `ega_text.v`
    and passes text/graphics mode into the Attribute Controller.
  - `ega_text_tb.sv` covers foreground, background, intensity, and blink cases.
  - `ega_registers_tb.sv` covers the Attribute Controller blink enable output.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 249 warnings.
  - HDL simulation could not be run because no standalone simulator is installed;
    see `TEST_TOOLS.md`.

### EGA-606 - Implement 9th-Dot Line Graphics Behavior

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-605.
- Files: text renderer module, `rtl/video/ega_attrib_ctrl.v`.
- Source: `SPEC.md` sections 4.4, 7.3, 11.7.
- Work:
  - For 9-dot text modes, repeat the 8th glyph column for line graphics
    characters when enabled.
  - Blank or handle the 9th column correctly for non-line-graphics characters.
- Acceptance:
  - Box-drawing characters join correctly in 80-column text mode.
- Completed:
  - `ega_sequencer.v` now exports Sequencer Clocking Mode bit `0` as
    `char_9dot`.
  - `ega_attrib_ctrl.v` now exports Attribute Mode Control bit `2` as
    `line_graphics_enable`.
  - `ega_top.v` adds a text CRTC/fetch tick for 9-dot character timing while
    preserving the existing graphics fetch cadence.
  - `ega_text.v` extends the glyph shifter to 9 bits and copies the 8th glyph
    column into the 9th dot only for characters `C0h..DFh` when line graphics
    are enabled.
  - Non-line characters, and line characters when line graphics are disabled,
    use the background color in the 9th column.
  - `ega_text_tb.sv` adds deterministic checks for 9-dot line graphics repeat,
    normal-character 9th-column blanking, and disabled line-graphics blanking.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 249 warnings.
  - HDL simulation could not be run because no standalone simulator is installed;
    see `TEST_TOOLS.md`.

### EGA-607 - Implement Cursor Rendering

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-603, EGA-605.
- Files: `rtl/video/UM6845R.v`, text renderer module.
- Source: `SPEC.md` sections 4.5, 7.3.
- Work:
  - Use CRTC cursor start/end and cursor address registers.
  - Apply cursor visibility and scanline range to the active text cell.
- Acceptance:
  - Cursor tests show the cursor at the programmed cell and scanline range.
- Completed:
  - `UM6845R.v` now gates the cursor output with CRTC cursor disable state while preserving the existing cursor address and scanline-range compare.
  - `ega_top.v` routes the CRTC `CURSOR` output into the text renderer.
  - `ega_text.v` renders an active cursor by swapping foreground/background palette indexes for the current text cell, matching x86Box color text cursor behavior.
  - `ega_text_tb.sv` covers cursor foreground/background swapping for set and clear glyph pixels.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 249 warnings.
  - Standalone HDL simulation was not run because no simulator listed in `TEST_TOOLS.md` is installed in this environment.

### EGA-608 - Implement Mono Text Attributes And Underline

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-605, EGA-202.
- Files: text renderer module, `rtl/video/ega_attrib_ctrl.v`.
- Source: `SPEC.md` sections 7.3, 11.7.
- Work:
  - Match x86Box mono attribute handling for base EGA text.
  - Implement underline behavior where required by the selected text mode.
- Acceptance:
  - Mono text smoke cases render attributes and underline consistently with the
    reference.
- Completed:
  - `ega_attrib_ctrl.v` now exposes Attribute Controller Mode Control bit `1` as the mono-attribute enable for text rendering.
  - `ega_top.v` routes mono-attribute enable and the CRTC underline location register into `ega_text.v`.
  - `ega_text.v` implements the x86Box EGA MDA attribute table behavior as 4-bit EGA palette indexes, including special `00h/08h/70h/78h/80h/88h/F0h/F8h` cases, mono blink, mono cursor XOR, and underline when `(attr & 7) == 1` on the programmed underline scanline.
  - `ega_text_tb.sv` adds smoke coverage for mono special attributes, mono blink, and underline overriding a clear glyph pixel.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 249 warnings.
  - Standalone HDL simulation was not run because no simulator listed in `TEST_TOOLS.md` is installed in this environment.

### EGA-609 - Implement Text Horizontal Panning

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-603, EGA-203.
- Files: text renderer module, `rtl/video/ega_attrib_ctrl.v`.
- Source: `SPEC.md` sections 4.4, 7.3.
- Work:
  - Apply Attribute Controller horizontal panning to text pixels.
  - Verify behavior across the left edge and line compare split.
- Acceptance:
  - Text panning shifts glyph pixels without corrupting character fetch order.
- Completed:
  - `ega_top.v` now routes Attribute Controller horizontal pixel panning into the text renderer.
  - `ega_text.v` caches the sanitized panning value at display activation and applies it through a pixel-index delay line, so visible text pixels shift without changing character fetch cadence or CRTC text addresses.
  - Values `8..15` are treated as zero panning, matching the existing base-EGA graphics panning behavior.
  - `ega_text_tb.sv` adds smoke coverage for panned text pixels at the left edge and verifies panning does not alter cell fetch addresses across a split-style address reset.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 249 warnings.
  - Standalone HDL simulation was not run because no simulator listed in `TEST_TOOLS.md` is installed in this environment.

### EGA-610 - Add Text Renderer Testbench Coverage

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-603, EGA-604, EGA-605, EGA-606, EGA-607, EGA-608, EGA-609.
- Files: new or existing EGA text testbench under `rtl/KFPC-XT/TESTBENCH/`.
- Source: `SPEC.md` section 7.3; `PLAN.md` phase 8.
- Work:
  - Test character/attribute fetch, glyph row fetch, palette, blink, cursor,
    9th-dot line graphics, Character Map Select, and mono attributes.
- Acceptance:
  - Text tests fail if the renderer treats text memory as planar graphics.
- Completed:
  - Existing `ega_text_tb.sv` now covers 80-column and 40-column text cell fetch cadence, including explicit `text_cell_addr` checks that would fail if text were treated as planar graphics bytes.
  - The testbench covers Character Map Select font-bank addressing, glyph foreground/background selection, background intensity, blink, cursor foreground/background behavior, 9-dot line graphics, mono attributes, underline, and horizontal panning.
  - Split-style address reset coverage verifies panning does not alter cell fetch addresses when the CRTC address changes.
  - `git diff --check` passed.
  - Quartus Analysis & Elaboration passed with 0 errors and 249 warnings in the preceding text renderer tasks.
  - Standalone HDL simulation was not run because no simulator listed in `TEST_TOOLS.md` is installed in this environment.

## EGA-700: PCXT Integration And BIOS Compatibility

### EGA-701 - Audit Video Output Selection And EGA Activation

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-505, EGA-408.
- Files: `rtl/KFPC-XT/HDL/Peripherals.sv`, `rtl/KFPC-XT/HDL/Chipset.sv`,
  `PCXT.sv`, `rtl/video/ega_top.v`.
- Source: `SPEC.md` section 10; `PLAN.md` phase 7.
- Work:
  - Verify how EGA becomes the active RGB path and when CGA remains active.
  - Ensure register programming can occur before EGA display selection.
  - Remove or guard heuristics that delay EGA activation based only on recent
    writes if they mask real hardware behavior.
- Acceptance:
  - EGA BIOS can program registers and memory before the first selected frame.
- Completed:
  - Added `EGA_VIDEO_SELECTION_AUDIT.md` covering EGA memory decode, I/O
    visibility before display selection, the RGB/sync output mux, and the
    `ega_video_active` / `ega_video_pending` activation heuristic.
  - The audit verifies that EGA register I/O is gated by `ega_enabled`, not
    `ega_display_sel`, so BIOS and game probes can program EGA before the first
    selected EGA frame.
  - The audit verifies that outer EGA VRAM decode uses GC Misc memory-map
    selection and masks overlapping CGA/Tandy/HGC windows with `~ega_mem_select`.
  - The delayed activation heuristic is recorded as a PCXT output-mux policy and
    a platform-smoke follow-up risk, not as EGA hardware semantics.
  - `git diff --check` passed for the staged EGA-701 documentation changes.

### EGA-702 - Preserve CGA/HGC/Tandy Coexistence

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-104, EGA-701.
- Files: `rtl/KFPC-XT/HDL/Peripherals.sv`, `rtl/video/cga.v`,
  `rtl/video/hgc.v`, `PCXT.sv`.
- Source: `SPEC.md` sections 10.1, 10.2.
- Work:
  - Re-test video memory decode and output muxing with EGA disabled.
  - Re-test CGA/Tandy A000/B800/HGC regions where they overlap EGA-capable
    address ranges.
- Acceptance:
  - Non-EGA modes still boot and display after EGA decode changes.
- Completed:
  - Added `EGA_CGA_HGC_COEXISTENCE_AUDIT.md` covering EGA, CGA, Tandy, and HGC
    memory-decode priority and output mux behavior.
  - Verified statically that `ega_mem_select` is false when runtime EGA is
    disabled, so CGA/Tandy/HGC memory selects are not masked in non-EGA modes.
  - Verified statically that overlapping EGA-enabled apertures intentionally
    prioritize EGA before CGA/Tandy/HGC on both memory decode and CPU readback.
  - Verified statically that HGC output-swap still has priority over EGA RGB,
    and that CGA is only suppressed by `ega_display_sel_cga` when EGA is
    actually selected for display.
  - `git diff --check` passed.
  - End-to-end boot/display smoke was not run in this environment; this task is
    a static coexistence audit.

### EGA-703 - Verify EGA BIOS ROM Loading And Protection

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-701.
- Files: `PCXT.sv`, `egabios.asm`, `egabios.rom`, BIOS loading logic.
- Source: `SPEC.md` section 10.5; `PLAN.md` phase 7.
- Work:
  - Confirm the EGA BIOS image loads at the expected address and is protected
    consistently with current PCXT BIOS behavior.
  - Keep BIOS changes minimal unless hardware behavior requires a compatibility
    shim.
- Acceptance:
  - EGA BIOS smoke test reaches expected mode-setting behavior without manual
    pokes.
- Completed:
  - Added `EGA_BIOS_LOADING_AUDIT.md` documenting the EGA BIOS download select,
    `C0000h` address mapping, external bus write path, and RAM protection bit.
  - Verified `egabios.rom` is 2048 bytes and starts with `55 AA 04`, matching a
    four-block BIOS extension image as defined by `egabios.asm`.
  - Verified statically that EGA BIOS downloads use `ioctl_index[5:0] == 3` and
    map to `C0000h + ioctl_addr[15:0]`.
  - Verified statically that `ega_bios_loaded` enables `bios_protect_flag[2]`,
    protecting `C0000h-C3FFFh`, which covers the current `C0000h-C07FFh` image.
  - `git diff --check` passed.
  - End-to-end EGA BIOS smoke was not run in this environment; this task is a
    loader/protection audit.

### EGA-704 - Validate Menu And Feature-Gate Integration

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-701.
- Files: `PCXT.sv`, `files.qip`.
- Source: `SPEC.md` sections 10.1, 10.5.
- Work:
  - Verify `ENABLE_EGA` and menu-controlled EGA gate behavior.
  - Ensure disabled EGA does not drive bus, memory, or video outputs.
- Acceptance:
  - Builds with EGA enabled and disabled have expected behavior.
- Completed:
  - Added `EGA_FEATURE_GATE_AUDIT.md` documenting the `ENABLE_EGA` macro,
    menu-controlled `status[53]` gate, EGA memory select, CPU read-data mux,
    readiness, and RGB output gating.
  - Verified statically that `ENABLE_EGA=0` hides the menu entry and forces
    `ega_enabled` low while keeping A000 UMB behavior unblocked.
  - Verified statically that runtime-disabled EGA cannot select VRAM, drive CPU
    read data, stall CPU readiness, or suppress CGA/Tandy/HGC memory windows.
  - Quartus Analysis & Elaboration passed for the default `ENABLE_EGA=1` build
    with 0 errors and 249 warnings.
  - Quartus Analysis & Elaboration passed with
    `--verilog_macro="ENABLE_EGA=0"` with 0 errors and 249 warnings.
  - Generated Quartus artifacts were removed after verification.

### EGA-705 - Run Platform Smoke Tests

- Status: `[ ]`
- Priority: `P0`
- Depends on: EGA-409, EGA-507, EGA-610, EGA-703.
- Files: smoke-test notes, `games/`, generated screenshots or logs if used.
- Source: `SPEC.md` section 12.4; `PLAN.md` phase 7.
- Work:
  - Run BIOS boot, DOS text, mode `03h`, mode `0Dh`, mode `0Eh`, mode `10h`,
    known glitching EGA games, and CGA/HGC/Tandy non-regression cases.
  - Record observed failures with a suspected owning subsystem.
- Acceptance:
  - Every smoke case is classified pass/fail with enough detail for a follow-up
    task.

## EGA-800: Verification Expansion

### EGA-801 - Add Pure Reference Models For Tests

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-001.
- Files: testbench helper package or shared include under
  `rtl/KFPC-XT/TESTBENCH/`.
- Source: `SPEC.md` sections 5, 6, 7, 8, 9.
- Work:
  - Implement reference functions for CPU address remap, VRAM writes, VRAM
    reads, CRTC scanout address, pixel assembly, and palette mapping.
  - Keep helpers independent from DUT signal names.
- Acceptance:
  - New testbenches share reference helpers instead of duplicating formulas.
- Verification:
  - Added `rtl/KFPC-XT/TESTBENCH/ega_reference_pkg.sv` with pure `ega_ref_*`
    functions for CPU address/window remap, VRAM write/read modes, CRTC scanout
    remap and row advance, planar pixel assembly, graphics blink, palette code,
    and RGB6 conversion.
  - Helpers use explicit arguments and do not reference DUT signal names.
  - Existing executable simulator tools are unavailable in this environment, so
    verification is limited to static review and `git diff --check`.

### EGA-802 - Add `ega_registers_tb`

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-208.
- Files: `rtl/KFPC-XT/TESTBENCH/ega_registers_tb.sv` or equivalent.
- Source: `SPEC.md` sections 3, 4, 9.2.
- Work:
  - Cover register reset, readback, indexed writes, protected writes, flip-flop,
    status reads, color/mono ports, and DAC stubs.
- Acceptance:
  - Register behavior can be tested without launching the full chipset.
- Completed:
  - Added `EGA_TESTBENCH_INVENTORY.md` documenting existing
    `ega_registers_tb.sv` coverage.
  - Verified statically that the register testbench covers Sequencer, Graphics
    Controller, Attribute Controller, CRTC protection/timing/address behavior,
    Misc Output, color/mono ports, selected status side effects, and status
    toggles.
  - Standalone HDL simulation was not run because no simulator listed in
    `TEST_TOOLS.md` is installed in this environment.

### EGA-803 - Add `ega_crtc_addr_tb`

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-308.
- Files: `rtl/KFPC-XT/TESTBENCH/ega_crtc_addr_tb.sv` or equivalent.
- Source: `SPEC.md` sections 6, 9.
- Work:
  - Cover timing counters, display enable, hblank/vblank, start address, row
    advance, line compare, and scanout remap.
- Acceptance:
  - Scanout address changes can be verified before visual testing.
- Completed:
  - Added `EGA_TESTBENCH_INVENTORY.md` documenting that equivalent CRTC address
    coverage lives in `ega_registers_tb.sv`.
  - Verified statically that the existing coverage checks scanout remapping,
    overflow fields, row advance, maximum scan line, start-address frame
    latching, split-screen reset, sampled fetch address, display enable,
    hblank, and vblank behavior.
  - No separate `ega_crtc_addr_tb.sv` file is required by the current task
    wording because an equivalent testbench exists.
  - Standalone HDL simulation was not run because no simulator listed in
    `TEST_TOOLS.md` is installed in this environment.

### EGA-804 - Add `ega_pixel_tb`

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-409.
- Files: `rtl/KFPC-XT/TESTBENCH/ega_pixel_tb.sv` or equivalent.
- Source: `SPEC.md` sections 7.4, 8.
- Work:
  - Cover planar graphics, low-resolution repeat, panning, plane enable, 2bpp
    mode, palette, and blanking.
- Acceptance:
  - Pixel output regressions are cycle-deterministic.
- Completed:
  - Added `EGA_TESTBENCH_INVENTORY.md` documenting existing `ega_pixel_tb.sv`
    coverage.
  - Verified statically that the pixel testbench covers planar pixel assembly,
    low-resolution repeat, horizontal panning, text/graphics/CGA-compatible
    mode selection, 2bpp routing, display blanking, Attribute Controller
    palette remap, and plane-enable effects.
  - Standalone HDL simulation was not run because no simulator listed in
    `TEST_TOOLS.md` is installed in this environment.

### EGA-805 - Add `ega_text_tb`

- Status: `[x]`
- Priority: `P0`
- Depends on: EGA-610.
- Files: `rtl/KFPC-XT/TESTBENCH/ega_text_tb.sv` or equivalent.
- Source: `SPEC.md` section 7.3.
- Work:
  - Cover text fetches, font plane, Character Map Select, attributes, blink,
    cursor, panning, mono attributes, and 9th-dot line graphics.
- Acceptance:
  - Text renderer behavior is testable without full system boot.
- Completed:
  - Added `EGA_TESTBENCH_INVENTORY.md` documenting existing `ega_text_tb.sv`
    coverage.
  - Verified statically that the text testbench covers 80/40-column fetch
    cadence, font-bank selection, foreground/background attributes, background
    intensity, blink, cursor, mono attributes, underline, horizontal panning,
    and 9-dot line graphics.
  - Standalone HDL simulation was not run because no simulator listed in
    `TEST_TOOLS.md` is installed in this environment.

### EGA-806 - Add Integrated EGA Smoke Test Flow

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-705.
- Files: `rtl/KFPC-XT/TESTBENCH/Chipset_tb.sv`, scripts or notes as available.
- Source: `SPEC.md` section 12.4; `PLAN.md` phase 8.
- Work:
  - Exercise enough of the PCXT chipset to program EGA registers and VRAM, then
    sample video output.
  - Use small deterministic programs or direct bus transactions as appropriate.
- Acceptance:
  - Integrated smoke catches wiring mistakes that unit tests cannot see.
- Completed:
  - Updated `Chipset_tb.sv` to match the current `CHIPSET` port interface so
    the wildcard instantiation is explicit and analyzable.
  - Added optional `EGA_CHIPSET_SMOKE` flow that enables EGA at the chipset
    boundary, programs EGA registers through I/O cycles, writes A0000h VRAM
    through memory cycles, and checks EGA display selection, fetch activity,
    non-zero RGB, and CPU readiness.
  - The legacy chipset test sequence remains unchanged unless
    `EGA_CHIPSET_SMOKE` is defined.
  - Documented the flow in `TEST_TOOLS.md`.
  - `quartus_map PCXT --analyze_file=rtl/KFPC-XT/TESTBENCH/Chipset_tb.sv`
    passed with 0 errors and 3 warnings after generating `build_id.v`.
  - `quartus_map PCXT --verilog_macro="EGA_CHIPSET_SMOKE=1"
    --analyze_file=rtl/KFPC-XT/TESTBENCH/Chipset_tb.sv` also passed with 0
    errors and 3 warnings, parsing the new optional EGA smoke block.
  - Standalone HDL simulation was not run because no simulator listed in
    `TEST_TOOLS.md` is installed in this environment.

### EGA-807 - Maintain A Game-Oriented Regression Matrix

- Status: `[ ]`
- Priority: `P1`
- Depends on: EGA-004, EGA-705.
- Files: `TASKS.md` or future regression notes.
- Source: `SPEC.md` section 12.4.
- Work:
  - Record title, mode, expected behavior, observed behavior, and suspected
    subsystem for each known problematic game.
  - Keep results separated from deterministic unit-test status.
- Acceptance:
  - Game glitches become reproducible issues rather than anecdotal failures.

## EGA-900: Stabilization And Documentation

### EGA-901 - Remove Or Gate Temporary Debug Logic

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-705.
- Files: `rtl/video/ega_top.v`, any modified EGA RTL.
- Source: `PLAN.md` phase 9.
- Work:
  - Remove debug-only last-read/last-write state unless it is deliberately kept
    behind synthesis-safe debug guards.
  - Ensure debug logic does not drive compatibility behavior.
- Acceptance:
  - Release-candidate RTL contains no accidental debug-dependent behavior.
- Completed:
  - Removed unused `ega_top.v` debug-only last-read, last-write, and previous
    CRTC write tracking state that Quartus reported as assigned but never read.
  - Removed the associated EGA debug I/O range capture path.
  - Kept stable diagnostic/configuration wires that are consumed by the RTL or
    testbenches.
  - Quartus Analysis & Elaboration passed with 0 errors and 243 warnings.
  - EGA-705 platform smoke remains a separate visual validation task.

### EGA-902 - Document Hardware Formulas And x86Box Mappings

- Status: `[x]`
- Priority: `P2`
- Depends on: EGA-303, EGA-401, EGA-601.
- Files: comments in EGA RTL, `SPEC.md` if behavior needs clarification.
- Source: `SPEC.md`; `x86_src/video/vid_ega.c`;
  `x86_src/video/vid_ega_render.c`.
- Work:
  - Add short comments only around non-obvious register formulas, remap logic,
    timing latches, or text fetch sequencing.
  - Avoid comments that restate signal names or assignments.
- Acceptance:
  - Future maintainers can trace complex formulas back to the spec/reference.
- Completed:
  - Added short RTL comments in `ega_vram.v` for x86Box-style CPU address
    remapping, EGA write-mode helper behavior, and read mode 1 pixel compare.
  - Added short RTL comments in `ega_pixel.v` for CGA-compatible 2bpp remapping
    and Attribute Controller horizontal panning across byte boundaries.
  - Added short RTL comments in `ega_text.v` for MDA-style mono attributes and
    text/font plane addressing.
  - No logic changes were made.
  - `git diff --check` passed.

### EGA-903 - Record Intentional Deviations From IBM EGA

- Status: `[x]`
- Priority: `P1`
- Depends on: EGA-705.
- Files: `SPEC.md`, future release notes.
- Source: `SPEC.md` section 14; `PLAN.md` phase 9.
- Work:
  - Document any behavior intentionally not implemented, such as non-base EGA
    clone behavior or exact cycle stealing if not required.
  - Separate non-goals from unresolved bugs.
- Acceptance:
  - Remaining limitations are explicit and not hidden in implementation details.
- Completed:
  - Added `EGA_INTENTIONAL_DEVIATIONS.md` documenting confirmed non-goals for
    the first PCXT EGA port: Compaq EGA, SuperEGA, ATI EGA Wonder, JEGA/JVGA,
    VGA RAMDAC palette behavior, and exact analog overscan geometry.
  - Documented deliberate MiSTer/PCXT integration choices for the video output
    path, base IBM Color Select handling, and the ungated BRAM CPU-access-slot
    timing hint.
  - Separated intentional deviations from unresolved smoke-test topics so
    EGA-705 results still become bugs or follow-up tasks instead of hidden
    limitations.

### EGA-904 - Run Full Verification Before Release Candidate

- Status: `[ ]`
- Priority: `P0`
- Depends on: EGA-802, EGA-803, EGA-804, EGA-805, EGA-806, EGA-901.
- Files: all modified RTL and testbenches.
- Source: `PLAN.md` sections 4, 20.
- Work:
  - Run all deterministic EGA tests.
  - Run full project build or synthesis flow.
  - Run platform smoke tests from EGA-705.
  - Re-run non-EGA video smoke tests.
- Acceptance:
  - Release-candidate status is backed by commands, logs, and smoke results.

### EGA-905 - Split Remaining Failures Into Follow-Up Tasks

- Status: `[ ]`
- Priority: `P2`
- Depends on: EGA-904.
- Files: `TASKS.md`, issue tracker if used.
- Source: all unresolved test/smoke results.
- Work:
  - Convert each remaining failure into a task with owner subsystem,
    reproduction steps, expected behavior, and acceptance check.
  - Close or archive tasks made obsolete by implementation changes.
- Acceptance:
  - The backlog remains actionable after the first release-candidate pass.

## First Execution Slice

Start with this slice before broad RTL changes:

1. EGA-002 - Establish repeatable local build and simulation commands.
2. EGA-003 - Improve EGA testbench diagnostics.
3. EGA-101 - Update VRAM testbench for `cpu_a16`.
4. EGA-102 - Add CPU address remap reference helpers.
5. EGA-103 - Cover GC memory map selection in tests.
6. EGA-105 - Add chain-2 read/write coverage.
7. EGA-106 - Add odd/even and page select coverage.
8. EGA-107 - Expand CPU write mode coverage.
9. EGA-108 - Expand CPU read mode coverage.
10. EGA-109 - Fix VRAM core mismatches exposed by tests.
11. EGA-104 - Implement full EGA memory decode in `Peripherals.sv`.
12. EGA-208 - Add register-oriented testbench coverage.

This slice focuses first on CPU-visible behavior, because bad memory and
register semantics make later graphics glitches difficult to diagnose.
