# PCXT MiSTer EGA Porting Plan

> Superseded for the `ega-mcga-clean-core` branch: this historical EGA porting
> plan preserved the old CGA/HGC/Tandy coexistence model. The clean-core branch
> is governed by `EGA_CLEAN_CORE_SPEC.md`, `EGA_CLEAN_CORE_PLAN.md`, and
> `EGA_CLEAN_CORE_TASKS.md`, where EGA is the only active video hardware model
> and CGA compatibility lives inside EGA.

This plan turns `SPEC.md` into an implementation roadmap for bringing the PCXT
MiSTer EGA core into practical alignment with the x86Box EGA model.

The plan is intentionally implementation-oriented but does not prescribe every
line of RTL. Each phase defines:

- The problem being solved.
- The source-of-truth behavior from `SPEC.md`.
- The files likely to change.
- Concrete tasks.
- Acceptance criteria.
- Verification requirements.
- Dependencies and risks.

The recommended execution style is incremental: keep the core buildable after
each phase, add deterministic tests before broad game testing, and avoid mixing
unrelated phases in the same change unless a dependency makes that impossible.

## 1. Objectives

The final EGA implementation should provide:

- IBM EGA compatible CPU-visible register behavior.
- IBM EGA compatible planar VRAM access, including read latches and write
  modes 0, 1, and 2.
- Correct CPU memory decode for all EGA memory-map modes.
- Correct CRTC-controlled display address generation.
- Correct graphics scanout, including planar pixel shifting, panning, palette
  lookup, blink, plane enable, and CGA 2bpp shift/render mode.
- Correct text scanout, including character/attribute fetch, font-plane access,
  Character Map Select, 8/9-dot rendering, cursor, blink, and line graphics.
- Correct Input Status #1 behavior, including Attribute Controller flip-flop
  reset and IBM EGA bits `4/5` toggling.
- Correct EGA 16-color and 64-color digital RGB behavior.
- A verification suite that catches regressions without relying only on game
  behavior.

The implementation should stay focused on base IBM EGA. Compaq EGA, SuperEGA,
ATI EGA Wonder, JEGA/JVGA, VGA DAC palette behavior, and exact analog overscan
are out of scope for the first complete port.

## 2. Planning Assumptions

- `SPEC.md` is the canonical local specification for this plan.
- x86Box files under `x86_src` remain the practical source of truth for behavior
  that is ambiguous in existing RTL.
- The existing PCXT core already has partial EGA support:
  - `rtl/video/ega_vram.v` implements much of the CPU VRAM path.
  - `rtl/video/ega_sequencer.v`, `ega_gfx_ctrl.v`, and `ega_attrib_ctrl.v`
    implement partial register blocks.
  - `rtl/video/UM6845R.v` has EGA-oriented extensions.
  - `rtl/video/ega_pixel.v` implements a graphics pixel path that needs audit.
  - `rtl/KFPC-XT/HDL/Peripherals.sv` wires EGA into the PCXT memory and video
    system.
- `egabios.asm` is a smoke-test helper and BIOS shim, not the hardware source
  of truth.
- Historical assumption, superseded for `ega-mcga-clean-core`: old changes
  preserved CGA/HGC/Tandy behavior and the existing video mux. Clean-core work
  intentionally removes standalone CGA/HGC/Tandy hardware paths while keeping
  CGA-compatible behavior inside EGA.

## 3. Workstream Overview

The work is split into ten phases:

| Phase | Name | Main Outcome |
| --- | --- | --- |
| 0 | Baseline And Harness | Establish reproducible tests, known-good traces, and comparison points. |
| 1 | CPU VRAM And Memory Decode | Complete CPU-visible planar memory behavior and all GC memory-map modes. |
| 2 | Register And I/O Semantics | Make port decode, register read/write behavior, and status side effects match the spec. |
| 3 | CRTC Timing And Address Core | Align CRTC counters, protected writes, frame latching, split, and scanout address remap. |
| 4 | Graphics Scanout | Correct planar pixel generation, panning, plane enable, blink, and CGA 2bpp mode. |
| 5 | Attribute, Palette, Border, Status | Complete color pipeline and Input Status #1 behavior. |
| 6 | Text Renderer | Add complete EGA text scanout with font-plane access and cursor behavior. |
| 7 | PCXT Integration And BIOS Compatibility | Historical coexistence target, superseded by the clean-core EGA-only integration model. |
| 8 | Verification Expansion | Build deterministic and game-oriented validation coverage. |
| 9 | Stabilization And Documentation | Clean up debug paths, document behavior, and prepare implementation tasks for long-term maintenance. |

Phases 1 and 2 can partly overlap. Phases 3 through 6 should be sequenced more
strictly because scanout behavior depends on CRTC address generation and
register semantics.

## 4. Definition Of Done

The EGA port is complete when all of these are true:

- All explicit base IBM EGA requirements in `SPEC.md` are implemented or are
  documented with an accepted reason for deliberate deferral.
- CPU VRAM deterministic tests cover:
  - Read latches.
  - Read modes 0 and 1.
  - Write modes 0, 1, and 2.
  - ROP set/AND/OR/XOR.
  - Bit Mask.
  - Set/Reset and Enable Set/Reset.
  - Chain-2 read/write.
  - Extended-memory masking.
  - Page select.
  - All memory-map modes.
- Register tests cover:
  - Sequencer.
  - Graphics Controller.
  - Attribute Controller flip-flop.
  - Misc Output.
  - CRTC protected writes and readback.
  - Input Status #1 side effects.
- Scanout tests cover:
  - Mode `0Dh` 320x200x16.
  - A 640x200 graphics mode.
  - A 640x350 graphics mode.
  - At least one text mode.
  - Horizontal panning.
  - Start-address frame latching.
  - Split/line compare.
  - CRTC reset/display-disable blanking.
  - CGA 2bpp EGA graphics conversion.
  - Attribute plane enable.
  - Blink.
- The core still builds for the target Quartus flow.
- Existing non-EGA video modes still behave as before.
- Known EGA smoke-test games reach expected display behavior without the
  previously observed glitches.

## 5. Phase 0: Baseline And Harness

### 5.1 Purpose

Before changing behavior, establish repeatable evidence for what currently
works, what is broken, and how regressions will be detected.

### 5.2 Files To Inspect Or Extend

- `SPEC.md`
- `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv`
- Existing project scripts and Quartus build files:
  - `files.qip`
  - `rtl/video/video.qip`
  - `PCXT.qsf`
- Potential new testbench files under `rtl/KFPC-XT/TESTBENCH/`
- Optional helper scripts under a new test or tools directory, if the repo
  already has an accepted pattern for test utilities.

### 5.3 Tasks

1. Record the current EGA architecture.
   - Map every EGA-related signal from `Peripherals.sv` to `ega_top.v` and
     `ega_vram_bram_frontend.sv`.
   - Document the current clock domains:
     - CPU/system clock.
     - `clk_vga_cga`.
     - VRAM video port clock.
   - Confirm how wait states are generated for EGA CPU VRAM cycles.

2. Establish build and simulation commands.
   - Identify the fastest available simulator for the existing testbench.
   - Identify the Quartus project build path.
   - Create a short local note or script only if it matches repository style.

3. Extend baseline logging in testbenches, not production RTL.
   - Ensure failing tests print:
     - Register setup.
     - CPU address.
     - Effective memory-map mode.
     - Expected and actual plane data.

4. Collect known game/application smoke cases.
   - Minimum:
     - `egabios.asm` mode `0Dh` path.
     - Prehistorik detection path.
   - Add other known glitch cases when available.

5. Create a traceability checklist from `SPEC.md`.
   - Each requirement should map to one implementation area and one planned
     verification path.

### 5.4 Acceptance Criteria

- A developer can run at least the current EGA VRAM testbench and understand
  failures from its output.
- All current EGA modules and integration points are listed in the phase notes.
- The plan's later test expectations have a place to be implemented.

### 5.5 Risks

- The repository may not have a mature simulation workflow. If so, prioritize
  small SystemVerilog testbenches that can run outside the full FPGA build.
- If the testbench currently does not compile because of interface drift, fix
  the testbench before modifying RTL behavior.

## 6. Phase 1: CPU VRAM And Memory Decode

### 6.1 Purpose

Complete the CPU-visible EGA memory model before changing scanout. This is the
highest leverage area for game glitches because many EGA drawing routines rely
on read latches, write modes, and memory-map side effects.

### 6.2 Source Requirements

From `SPEC.md`:

- Section 5.1: physical four-plane organization.
- Section 5.2: `ega_remap_cpu_addr()` behavior.
- Section 5.3: read latches.
- Section 5.4: read modes.
- Section 5.5: chain-2 write mask.
- Section 5.6: write modes 0, 1, and 2.
- Section 10.1: outer PCXT memory decode must honor GC register `06h[3:2]`.
- Section 11 gap 1: current memory decode is incomplete.
- Section 11 gap 11: VRAM testbench must drive `cpu_a16` and add memory-map
  cases.

### 6.3 Likely Files

- `rtl/video/ega_vram.v`
- `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`
- `rtl/KFPC-XT/HDL/Peripherals.sv`
- `rtl/video/ega_top.v`
- `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv`

### 6.4 Tasks

1. Update the VRAM testbench interface.
   - Add `cpu_a16` to `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv`.
   - Drive it explicitly in every CPU read/write task.
   - Default it to `0` in reset/setup paths.

2. Build a reference function in the testbench.
   - Mirror x86Box `ega_remap_cpu_addr()` behavior in a testbench function.
   - Inputs:
     - CPU offset bits `15:0`.
     - CPU A16.
     - GC misc odd/even bit.
     - Sequencer extended memory bit.
     - GC memory map select.
     - Misc Output page select.
     - Card-is-64K flag fixed to false for current PCXT 256 KiB EGA.
   - Use it for all address-related expectations.

3. Add CPU address-remap tests.
   - Memory map `00b`: verify A16/A0 mux behavior for 128 KiB aperture.
   - Memory map `01b`: verify 64 KiB A000 aperture behavior.
   - Memory map `10b`: verify 32 KiB B000 aperture offset masking.
   - Memory map `11b`: verify 32 KiB B800 aperture offset masking.
   - Extended memory disabled: verify final address is masked to `3FFFh`.
   - Odd/even mode enabled: verify A0 mux cases.
   - Page select bit toggled: verify inverse page-select A0 behavior.

4. Add chain-2 read/write tests.
   - Even address with chain-2 write writes planes 0 and 2 only.
   - Odd address with chain-2 write writes planes 1 and 3 only.
   - Chain-2 read returns `{read_plane[1], cpu_addr[0]}`.

5. Add edge-case write-mode tests.
   - Write mode 0:
     - Rotate counts `0..7`.
     - ROP set/AND/OR/XOR.
     - Bit masks `00h`, `FFh`, `55h`, `AAh`, `3Ch`.
     - Enable Set/Reset patterns `0`, `Fh`, sparse masks.
   - Write mode 1:
     - Confirm host byte is ignored.
     - Confirm latches survive intervening writes.
   - Write mode 2:
     - Host bits `0..3` produce expected per-plane `FFh/00h`.
   - Write mode 3:
     - Confirm chosen behavior is no-op for base EGA, matching `SPEC.md`.

6. Fix any VRAM core mismatch found by tests.
   - Keep existing good behavior intact.
   - Add comments that name the x86Box source function when formulas are
     non-obvious.

7. Fix outer memory decode in `Peripherals.sv`.
   - Replace the current fixed `A0000h-AFFFFh` EGA select with decode driven by
     current GC memory map selection.
   - Required windows:
     - `00b`: `A0000h-BFFFFh`.
     - `01b`: `A0000h-AFFFFh`.
     - `10b`: `B0000h-B7FFFh`.
     - `11b`: `B8000h-BFFFFh`.
   - Preserve CGA/HGC interactions:
     - EGA enabled should own the selected EGA aperture.
     - CGA/HGC should still work when EGA is disabled or when their regions are
       outside the selected EGA aperture.

8. Verify bus ready behavior.
   - Ensure every EGA CPU VRAM read/write completes exactly once.
   - Ensure no stuck wait state when memory-map selection changes.
   - Ensure reads return EGA data only for selected EGA windows.

### 6.5 Acceptance Criteria

- `ega_vram_tb.sv` passes all old and new VRAM tests.
- CPU memory decode reaches all EGA memory windows required by GC register
  `06h[3:2]`.
- Chain-2 and A16/page-select behavior is proven by deterministic tests.
- No changes to scanout are required to validate this phase.

### 6.6 Dependencies

- Requires existing register outputs for:
  - `ega_mem_map_sel_cfg`.
  - `ega_page_select_cfg`.
  - `ega_extended_memory_cfg`.
  - `ega_odd_even_mode_cfg`.
  - `ega_chain2_read_cfg`.
  - `ega_chain2_write_cfg`.

### 6.7 Risks

- Memory decode overlaps may expose old CGA/HGC assumptions.
- The PCXT memory system may need careful arbitration if EGA takes `B8000h`
  while CGA is also enabled.

## 7. Phase 2: Register And I/O Semantics

### 7.1 Purpose

Make CPU-visible EGA register programming and probing reliable. Games and BIOS
code often program EGA directly, so register behavior must not depend on the
MiSTer display mux selecting EGA output.

### 7.2 Source Requirements

From `SPEC.md`:

- Section 3: I/O port map.
- Section 3.1: color/mono CRTC address selection.
- Section 3.2: Attribute Controller flip-flop.
- Section 4: register specification.
- Section 9.2: Input Status #1 side effects.
- Section 10.2: I/O decode independent of output selection.
- Section 11 gaps 5, 6, and 7.

### 7.3 Likely Files

- `rtl/video/ega_top.v`
- `rtl/video/ega_sequencer.v`
- `rtl/video/ega_gfx_ctrl.v`
- `rtl/video/ega_attrib_ctrl.v`
- `rtl/video/UM6845R.v`
- New or extended register testbench files.

### 7.4 Tasks

1. Audit all EGA I/O decode gates.
   - Identify where `ega_display_sel` suppresses register reads.
   - Register reads/writes should require `ega_enabled`, not visible output
     selection.
   - Keep video output selection separate from hardware register state.

2. Implement active CRTC/status port range behavior.
   - Misc Output bit `0` selects color or mono CRTC/status ports.
   - Active color range:
     - `3D4h/3D5h`.
     - `3DAh`.
   - Active mono range:
     - `3B4h/3B5h`.
     - `3BAh`.
   - Preserve existing `2xx` aliases only if they are intentionally supported.

3. Complete Attribute Controller flip-flop behavior.
   - Status read resets to address phase.
   - `3C0h` write alternates address/data.
   - Address write captures:
     - Index bits `4:0`.
     - Palette/video-enable bit `5`.
   - Data write updates selected register.
   - Reads from `3C1h` return selected register when compatible readback is
     enabled.

4. Implement Misc Output read/write details.
   - Store all relevant bits.
   - Feed page select bit `5` to VRAM remap.
   - Feed bit `7` to 16-color/64-color palette mode.
   - Feed bit `0` to CRTC/status port selection.
   - Confirm bit `2` clock select reaches timing logic where needed.

5. Verify Sequencer register behavior.
   - Index mask is `0..4` for base EGA.
   - Store/readback reset, clocking mode, map mask, character map, memory mode.
   - Ensure Clocking Mode changes reset or realign fetch pacing safely.
   - Ensure Character Map Select state is exposed for the future text renderer.

6. Verify Graphics Controller register behavior.
   - Index mask is `0..8` for base EGA.
   - Store/readback all base registers.
   - Ensure outputs are stable across the CPU/video clock boundary.
   - Confirm `read_mode`, `write_mode`, `chain2_read`, `odd_even_mode`, and
     `mem_map_sel` match bit definitions in `SPEC.md`.

7. Add CRTC write protection.
   - If CRTC register `11h[7]` is set:
     - Writes to registers `00h..06h` are ignored.
     - Writes to register `07h` update only bit `4`.
   - Writes to base IBM indexes `19h..F6h` are ignored.
   - Index should be masked to `1Fh` for base EGA.

8. Add register-level tests.
   - Attribute flip-flop reset by status read.
   - Attribute index/data toggling.
   - Sequencer readback.
   - Graphics Controller readback.
   - CRTC protected writes.
   - Misc Output port range switching.
   - I/O reads work while `ega_enabled` is true even before EGA drives output.

### 7.5 Acceptance Criteria

- Register tests prove all base register side effects in this phase.
- EGA can be programmed through ports before it is visible on the output mux.
- CRTC/status active port range follows Misc Output bit `0`.
- Attribute Controller flip-flop behavior matches status-read side effects.

### 7.6 Dependencies

- Phase 1 should be complete or stable enough that register changes can feed
  memory decode without breaking CPU VRAM tests.

### 7.7 Risks

- Current BIOS shim may depend on broader readback than strict IBM EGA. The plan
  allows compatible readback, but write and side-effect behavior must remain
  x86Box-aligned.
- Changing I/O decode can affect CGA passthrough because EGA and CGA share some
  video integration paths.

## 8. Phase 3: CRTC Timing And Display Address Core

### 8.1 Purpose

Align CRTC-derived counters, address generation, frame latching, split, and
scanout address remapping with x86Box before refining pixel output.

### 8.2 Source Requirements

From `SPEC.md`:

- Section 4.5: CRTC derived values and protection.
- Section 6.1: scanout address remapping.
- Section 6.2: row advance.
- Section 6.3: start address and frame latching.
- Section 6.4: split/line compare.
- Section 9.1: dot clocks and CRTC character width.
- Section 9.2: vertical retrace window.
- Section 11 gap 4: scanout address remap is partially represented.

### 8.3 Likely Files

- `rtl/video/UM6845R.v`
- `rtl/video/ega_top.v`
- `rtl/video/ega_sequencer.v`
- New CRTC/address testbench.

### 8.4 Tasks

1. Build a CRTC reference checklist.
   - For each CRTC register `00h..18h`, identify:
     - Stored value.
     - Readback behavior.
     - Derived field.
     - Counter or address behavior affected.

2. Validate overflow-bit formulas.
   - `vtotal`.
   - `dispend`.
   - `vsyncstart`.
   - `split`.
   - Confirm current `UM6845R.v` formulas match `SPEC.md`.
   - Fix mismatches or document intentional timing adaptation.

3. Implement scanout address remap equivalent to `vid_ega_render_remap.h`.
   - Modes:
     - Byte mode.
     - Word mode using MA13.
     - Word mode using MA15.
     - Dword mode.
   - Row-scanline substitutions:
     - CRTC `17h[0]` controls MA13 substitution from `scanline[0]`.
     - CRTC `17h[1]` controls MA14 substitution from `scanline[1]`.
   - Keep representation conversion clear:
     - x86Box interleaved byte address.
     - HDL independent-plane address.

4. Validate row advance.
   - Independent-plane address advance should be `rowoffset << 1`.
   - Confirm interaction with low-res and high-res modes.
   - Confirm no off-by-one at end of row or frame.

5. Validate start-address frame latching.
   - Writes to CRTC `0Ch/0Dh` update latch immediately.
   - Visible fetch base changes only on frame reload.
   - Cursor address reloads on frame boundary.

6. Implement or verify split/line compare.
   - Use CRTC `18h`, `07h[4]`, and `09h[6]`.
   - Reset display address to 0 at split.
   - Reset scanline to 0.
   - Confirm interaction with interlace is at least compatible with x86Box's
     base behavior.

7. Validate CRTC reset/display-disable behavior.
   - CRTC register `17h[7]` clear should cause render paths to read zeros or
     output black according to text/graphics path.

8. Add CRTC/address tests.
   - Program representative mode timings.
   - Observe generated addresses for a few scanlines.
   - Verify start address changes at frame boundary.
   - Verify split resets address.
   - Verify remap variants with CRTC `14h` and `17h`.

### 8.5 Acceptance Criteria

- CRTC address generation matches x86Box formulas for representative modes.
- Start-address changes are frame-latched.
- Split/line compare behavior is deterministic and tested.
- CRTC reset bit blanks data through render path.
- Existing graphics mode still displays after changes.

### 8.6 Dependencies

- Phase 2 register behavior should be available for programming CRTC state.
- Phase 1 memory layout must be stable so address tests can inspect plane data.

### 8.7 Risks

- `UM6845R.v` is shared with non-EGA paths. Keep EGA-specific behavior guarded
  by `CRTC_TYPE` or equivalent.
- Sync pulse shaping and MiSTer output offsets may be intentionally different
  from x86Box timing. Separate display-output adaptation from internal EGA
  counter semantics.

## 9. Phase 4: Graphics Scanout

### 9.1 Purpose

Make planar graphics rendering match x86Box for EGA graphics modes. This phase
targets visible glitches in games using planar graphics, masks, scrolling, and
palette effects.

### 9.2 Source Requirements

From `SPEC.md`:

- Section 7.1: render mode selection.
- Section 7.2: horizontal display width.
- Section 7.4: graphics rendering.
- Section 7.5: CGA 2bpp graphics mode.
- Section 8: palette and RGB output.
- Section 11 gaps 3 and 8.

### 9.3 Likely Files

- `rtl/video/ega_pixel.v`
- `rtl/video/ega_attrib_ctrl.v`
- `rtl/video/ega_top.v`
- `rtl/video/UM6845R.v`
- New graphics scanout testbench.

### 9.4 Tasks

1. Fix or replace the graphics pixel shifter.
   - On fetch, load four plane bytes.
   - Output pixel color index bits as `{plane3, plane2, plane1, plane0}`.
   - Shift one bit per active dot.
   - In low-res/double-clock mode, repeat each pixel for the required second
     dot instead of advancing the shift register.
   - Ensure `pixel_valid` covers only valid shifted output.

2. Implement horizontal panning correctly for graphics.
   - Use Attribute Controller register `13h`.
   - Apply x86Box cache rule at vertical reset:
     - Values `0..7` become `value + 1`.
     - Values `8..15` become `0`.
     - Double in low-res mode.
   - Ensure panning does not corrupt fetch alignment at byte boundaries.

3. Implement graphics render mode selection.
   - If sequencer screen blank is active, output blank.
   - If Attribute Controller video enable is clear, output blank.
   - If Graphics Controller Misc bit `0` is set, use graphics path.

4. Add CGA 2bpp EGA graphics conversion.
   - Implement `egaremap2bpp` logic in hardware or a compact combinational
     function.
   - Enable it when Graphics Controller Mode bit `5` is set.
   - Match x86Box plane-byte remapping order.

5. Implement Sequencer Clocking Mode bit `2` graphics odd/even fetch behavior.
   - Follow x86Box's practical behavior, including the `secondcclk` toggle.
   - Add comments noting x86Box's FIXME if behavior is intentionally mirrored.

6. Apply Attribute Controller Color Plane Enable.
   - Mask final 4-bit color index with `attrregs[12h][3:0]`.
   - Ensure this happens before palette lookup.

7. Apply graphics blink behavior.
   - Use Attribute Mode Control bit `3`.
   - Use blink state bit `4`.
   - Match x86Box formula from `SPEC.md`.

8. Verify active display and blanking.
   - Pixels outside display enable should become overscan/border color.
   - CRTC reset/display-disable should output black or blank as specified.

9. Add graphics scanout tests.
   - Plane pattern to pixel index mapping.
   - Shift order.
   - Low-res pixel repeat.
   - Panning.
   - Plane enable mask.
   - CGA 2bpp conversion.
   - Blink high-bit behavior.

### 9.5 Acceptance Criteria

- Deterministic scanout tests prove pixel order and panning.
- Mode `0Dh` palette graphics produce expected color indices for known plane
  patterns.
- CGA 2bpp EGA mode conversion is covered by tests.
- The old observed pixel-shifter risk in `ega_pixel.v` is resolved.

### 9.6 Dependencies

- Phase 3 should provide correct scanout addresses.
- Phase 5 palette work can proceed in parallel if color-index tests are used
  before final RGB validation.

### 9.7 Risks

- Panning and fetch latency can produce one-byte or one-pixel artifacts if BRAM
  latency is not included in the shifter design.
- Low-res repeat behavior must be separated from 8-dot/9-dot text behavior.

## 10. Phase 5: Attribute, Palette, Border, And Status

### 10.1 Purpose

Complete the color and status behavior shared by graphics and text modes.

### 10.2 Source Requirements

From `SPEC.md`:

- Section 4.4: Attribute Controller registers.
- Section 8: palette and RGB output.
- Section 9.2: Input Status #1.
- Section 9.3: overscan.
- Section 11 gaps 5 and 7.

### 10.3 Likely Files

- `rtl/video/ega_attrib_ctrl.v`
- `rtl/video/ega_vgaport.v`
- `rtl/video/ega_top.v`
- `rtl/video/UM6845R.v`
- Register and scanout testbenches.

### 10.4 Tasks

1. Confirm base EGA palette indirection.
   - Palette registers `00h..0Fh` map to `raw_palette[i] & 3Fh`.
   - Attribute register `14h` is stored/readable but does not alter base IBM
     palette output.

2. Confirm 16-color and 64-color RGB mapping.
   - Misc Output bit `7` selects 16-color or 64-color mapping.
   - 16-color mapping includes the brown exception.
   - 64-color mapping uses separate high intensity bits per channel.

3. Implement overscan/border color behavior.
   - Attribute register `11h` selects border color.
   - Use 16-color or 64-color mapping according to Misc Output bit `7`.
   - Ensure border color appears when display enable is false.

4. Implement Input Status #1 bits.
   - Bit `0`: active when not displaying.
   - Bit `3`: active during vertical retrace status window.
   - Bits `4/5`: toggle on each IBM EGA status read.
   - Reading status resets Attribute Controller flip-flop.

5. Ensure status side effects are independent of display mux.
   - Status reads should work whenever `ega_enabled` is set.
   - Do not gate status readback with `ega_display_sel`.

6. Integrate blink state.
   - Generate blink counter at vertical display end or equivalent frame point.
   - Expose blink state to graphics and text render paths.
   - Keep blink behavior deterministic in tests.

7. Add tests.
   - Palette register to RGB mapping.
   - Brown exception.
   - 64-color mapping.
   - Overscan color.
   - Status bit `0` during display/blank.
   - Status bit `3` during retrace.
   - Status bits `4/5` toggle.
   - Status read resets Attribute Controller flip-flop.

### 10.5 Acceptance Criteria

- Attribute/palette tests prove 16-color and 64-color behavior.
- Status register tests prove bit and side-effect behavior.
- Border color is generated from Attribute Controller state.
- Graphics path can consume blink and plane-enable behavior.

### 10.6 Dependencies

- Phase 2 register semantics.
- Phase 3 status timing windows.
- Phase 4 graphics path for full visual validation.

### 10.7 Risks

- Status timing may differ from MiSTer output sync timing. Prefer internal CRTC
  status windows over post-scaler video output signals.

## 11. Phase 6: Text Renderer

### 11.1 Purpose

Add complete EGA text mode rendering. This closes the largest feature gap in
the current core and is required for software that switches between EGA text
and graphics without relying on CGA passthrough.

### 11.2 Source Requirements

From `SPEC.md`:

- Section 4.2: Sequencer Character Map Select.
- Section 4.4: Attribute Mode Control.
- Section 7.1: render mode selection.
- Section 7.2: horizontal display width.
- Section 7.3: text rendering.
- Section 9.4: blink and cursor.
- Section 11 gaps 2 and 9.

### 11.3 Likely Files

- New `rtl/video/ega_text.v` or equivalent.
- `rtl/video/ega_top.v`
- `rtl/video/ega_sequencer.v`
- `rtl/video/ega_attrib_ctrl.v`
- `rtl/video/UM6845R.v`
- `rtl/video/ega_vram.v` or frontend interface if extra fetch ports are needed.

### 11.4 Tasks

1. Decide text-renderer architecture.
   - Option A: integrate text fetch/render into `ega_pixel.v`.
   - Option B: add a dedicated `ega_text` module and select between text and
     graphics pixel sources in `ega_top.v`.
   - Prefer Option B if it keeps graphics shifter and text character pipeline
     easier to verify.

2. Define text fetch pipeline.
   - Character byte from plane 0.
   - Attribute byte from plane 1.
   - Font byte from plane 2.
   - Font address:
     - `font_bank_base + chr * 20h + scanline` in independent-plane storage.
   - Character Map Select:
     - Charset A from Sequencer register `03h[1:0]`.
     - Charset B from Sequencer register `03h[3:2]`.
     - Attribute bit `3` selects B when set, A otherwise.

3. Add required VRAM read support for text.
   - Text rendering needs character/attribute fetch plus font fetch.
   - Evaluate whether the existing single video read per CRTC character is
     enough.
   - If more reads are required, design a deterministic fetch schedule:
     - Character/attribute first.
     - Font byte before pixel output.
     - Preserve graphics fetch timing.
   - Avoid disrupting CPU VRAM read/write behavior.

4. Implement glyph rendering.
   - 8-dot and 9-dot modes from Sequencer Clocking Mode bit `0`.
   - Double-width mode from Sequencer Clocking Mode bit `3`.
   - Shift glyph byte left by one as x86Box does.
   - If Attribute Mode Control bit `2` is set and character is `C0h..DFh`,
     copy 8th glyph bit into 9th dot.

5. Implement text colors.
   - Foreground from `attr[3:0]`.
   - Background from `attr[7:4]`.
   - If blink is enabled and `attr[7]` is set:
     - Background uses `(attr >> 4) & 7`.
     - Foreground becomes background when blink is active.
   - Pass final 4-bit color through Attribute Controller palette.

6. Implement cursor.
   - Cursor address from CRTC `0Eh/0Fh`.
   - Cursor visible between CRTC `0Ah[4:0]` and `0Bh[4:0]`.
   - CRTC `0Ah[5]` disables cursor.
   - CRTC `0Bh[6:5]` controls cursor blink delay.
   - Cursor draw follows x86Box practical behavior, including foreground and
     background inversion.

7. Implement mono attributes if required for base EGA text compatibility.
   - Use x86Box MDA attribute table behavior when Attribute Mode Control bit
     `1` is set.
   - Include underline behavior from CRTC register `14h`.

8. Implement render mode selection.
   - GC Misc bit `0` clear selects text renderer.
   - Sequencer screen blank or Attribute video disable selects blank.
   - CRTC reset/display-disable returns zero character/attribute data.

9. Add text tests.
   - Character and attribute fetch.
   - Font bank select A/B.
   - 8-dot mode.
   - 9-dot mode.
   - Line graphics extension.
   - Blink.
   - Cursor.
   - Mono attribute path if implemented.

### 11.5 Acceptance Criteria

- Text-mode testbench renders expected color indices for controlled VRAM data.
- Character Map Select affects font selection.
- Cursor and blink behavior are visible and deterministic.
- Graphics mode still works after adding text path.

### 11.6 Dependencies

- Phase 3 scanout address generation.
- Phase 5 Attribute Controller and blink state.
- VRAM video fetch bandwidth analysis from Phase 0.

### 11.7 Risks

- Text mode may require extra VRAM reads per character. If the current BRAM
  frontend cannot support that, a small prefetch/cache stage may be needed.
- Font-plane addressing can be confused by x86Box's interleaved storage formula.
  Keep comments that show both formulas.

## 12. Phase 7: PCXT Integration And BIOS Compatibility

### 12.1 Purpose

Ensure the complete EGA model works inside the PCXT platform without breaking
existing video modes or relying on BIOS shortcuts.

### 12.2 Source Requirements

From `SPEC.md`:

- Section 10: PCXT integration requirements.
- Section 10.4: `egabios.asm` is a smoke-test helper, not a hardware limit.
- Section 12.4: game-oriented smoke tests.

### 12.3 Likely Files

- `rtl/KFPC-XT/HDL/Peripherals.sv`
- `rtl/KFPC-XT/HDL/Chipset.sv`
- `rtl/video/ega_top.v`
- `PCXT.sv`
- `egabios.asm` only if compatibility hooks need adjustment.

### 12.4 Tasks

1. Audit video mux behavior.
   - EGA register and memory behavior must be active when `ega_enabled`.
   - Visible output selection may remain delayed or policy-driven.
   - Ensure output selection cannot block EGA register programming.

2. Validate CGA/HGC coexistence.
   - EGA disabled:
     - CGA/HGC behavior unchanged.
   - EGA enabled:
     - EGA memory windows override only selected regions.
     - CGA passthrough remains available until EGA output selection changes.

3. Validate menu/status integration.
   - Confirm `EGA Gate` behavior.
   - Confirm EGA BIOS loading/protection remains functional.
   - Confirm enabling EGA does not expose A000 UMB simultaneously.

4. Keep BIOS shim minimal.
   - Do not add hardware behavior to BIOS if it belongs in RTL.
   - Use BIOS only for:
     - Detection hooks.
     - Known mode programming smoke path.

5. Add PCXT-level smoke tests if feasible.
   - Boot with EGA gate disabled.
   - Boot with EGA gate enabled.
   - Load EGA BIOS.
   - Program mode `0Dh`.
   - Confirm CPU writes to A000 reach EGA VRAM.
   - Confirm register programming before visible switch works.

### 12.5 Acceptance Criteria

- EGA can be enabled and programmed without preventing CGA boot flow.
- EGA BIOS mode `0Dh` path still works.
- Non-EGA modes remain usable.
- EGA register and memory state are not dependent on the output mux.

### 12.6 Dependencies

- Phases 1 and 2 for reliable memory/register state.
- Phases 4 through 6 for visible output validation.

### 12.7 Risks

- Existing software may rely on CGA memory at `B8000h` while EGA is enabled.
  Memory-map selection must decide which device responds, not a fixed global
  assumption.

## 13. Phase 8: Verification Expansion

### 13.1 Purpose

Create durable verification coverage so future EGA changes can be made without
reintroducing known glitches.

### 13.2 Test Layers

Use four layers:

1. Pure logic tests.
   - Small functions and modules:
     - VRAM remap.
     - Write-mode byte generation.
     - Read mode 1.
     - Palette conversion.
     - `egaremap2bpp`.

2. Module tests.
   - `ega_vram`.
   - Attribute Controller.
   - Graphics Controller.
   - Sequencer.
   - CRTC/address generator.
   - Pixel shifter.
   - Text renderer.

3. Integrated EGA tests.
   - Program registers.
   - Write VRAM.
   - Simulate scanout for selected lines.
   - Compare color-index streams or RGB streams.

4. Platform smoke tests.
   - BIOS mode path.
   - Known games.
   - CGA/HGC regression checks.

### 13.3 Reference Models

Where practical, embed compact reference functions in testbenches:

- `ega_remap_cpu_addr()`.
- `ega_recalc_remap_func()` equivalent for scanout.
- Write mode 0/1/2 expected output.
- Read mode 1 expected output.
- EGA 16-color and 64-color RGB conversion.
- `egaremap2bpp`.

Do not duplicate large chunks of x86Box source. Keep reference logic small and
traceable to `SPEC.md`.

### 13.4 Required Test Additions

1. Extend `ega_vram_tb.sv`.
   - Add all Phase 1 cases.

2. Add `ega_registers_tb.sv`.
   - Sequencer.
   - Graphics Controller.
   - Attribute Controller.
   - Misc Output.
   - Status side effects.

3. Add `ega_crtc_addr_tb.sv`.
   - Derived counters.
   - Start-address latching.
   - Split.
   - Scanout address remap.

4. Add `ega_pixel_tb.sv`.
   - Graphics shifter.
   - Panning.
   - CGA 2bpp.
   - Plane enable.

5. Add `ega_text_tb.sv`.
   - Text fetch and render.
   - Font banks.
   - Cursor.
   - Blink.

6. Add an integrated smoke test.
   - Program a minimal mode `0Dh` register set.
   - Write a known VRAM pattern.
   - Capture a line or frame fragment.
   - Compare against expected color-index output.

### 13.5 Acceptance Criteria

- Each new behavior has a deterministic test before being considered complete.
- Tests are fast enough to run during normal development.
- Test output points to the failing behavior, not only to a mismatched final
  frame.

### 13.6 Risks

- Full-frame visual tests can be brittle. Prefer line-level color-index checks
  for deterministic coverage, with visual/game tests as final smoke coverage.

## 14. Phase 9: Stabilization And Documentation

### 14.1 Purpose

Turn the implementation into maintainable core code, remove temporary debug
paths, and document intentional deviations.

### 14.2 Likely Files

- Modified RTL files from prior phases.
- `SPEC.md`
- `PLAN.md`
- `README.md` if user-facing EGA behavior needs a note.
- Testbench files.

### 14.3 Tasks

1. Remove or gate temporary debug signals.
   - Keep useful debug outputs only if they are stable and documented.
   - Avoid leaving unused debug state that consumes resources.

2. Add source comments for non-obvious x86Box mappings.
   - CPU address remap.
   - Scanout address remap.
   - Text font address conversion.
   - Status bit `0x30` toggle.
   - CRTC protected writes.

3. Document intentional deviations.
   - MiSTer output timing adaptation.
   - Overscan sizing adaptation.
   - Compatible register readback beyond strict IBM EGA.
   - VGA DAC stubs.

4. Re-run full verification.
   - All deterministic tests.
   - Quartus build.
   - EGA smoke tests.
   - Non-EGA video smoke tests.

5. Prepare implementation task list for tracking.
   - Split remaining work into issue-sized items if any work remains.
   - Link each task back to `SPEC.md` and this plan.

### 14.4 Acceptance Criteria

- No temporary debug-only behavior remains in production paths.
- The implementation is documented enough that future changes can identify the
  relevant x86Box behavior.
- All tests and builds expected for the project pass.

## 15. Dependency Graph

High-level dependencies:

```text
Phase 0: Baseline
  -> Phase 1: CPU VRAM and memory decode
      -> Phase 2: Register and I/O semantics
          -> Phase 3: CRTC timing and address core
              -> Phase 4: Graphics scanout
              -> Phase 5: Attribute/palette/status
                  -> Phase 6: Text renderer
                      -> Phase 7: PCXT integration and BIOS compatibility
                          -> Phase 8: Verification expansion
                              -> Phase 9: Stabilization
```

Parallel opportunities:

- Phase 5 palette conversion tests can start while Phase 4 graphics scanout is
  underway.
- Phase 8 test infrastructure can be built throughout the project, but each
  behavior-specific test depends on its target module being sufficiently stable.
- Phase 7 integration checks can begin early for memory and register behavior,
  then repeat after graphics and text scanout are complete.

## 16. Traceability Matrix

| SPEC.md Area | Plan Coverage | Primary Files |
| --- | --- | --- |
| Scope and compatibility target | Phases 1-9 | All EGA RTL and tests |
| I/O port map | Phase 2 | `ega_top.v`, register modules |
| Attribute flip-flop | Phases 2, 5 | `ega_attrib_ctrl.v`, `ega_top.v` |
| Misc Output | Phases 2, 5 | `ega_top.v`, `ega_vgaport.v` |
| Sequencer | Phases 2, 4, 6 | `ega_sequencer.v`, scanout modules |
| Graphics Controller | Phases 1, 2, 4 | `ega_gfx_ctrl.v`, `ega_vram.v`, `ega_pixel.v` |
| CRTC | Phases 2, 3 | `UM6845R.v`, `ega_top.v` |
| CPU VRAM access | Phase 1 | `ega_vram.v`, `ega_vram_bram_frontend.sv`, `Peripherals.sv` |
| Display address generation | Phase 3 | `UM6845R.v`, `ega_top.v` |
| Graphics rendering | Phase 4 | `ega_pixel.v`, `ega_attrib_ctrl.v` |
| Text rendering | Phase 6 | New text module, `ega_top.v`, VRAM frontend |
| Palette/RGB | Phase 5 | `ega_attrib_ctrl.v`, `ega_vgaport.v` |
| Timing/status/blanking | Phases 3, 5 | `UM6845R.v`, `ega_top.v` |
| PCXT integration | Phase 7 | `Peripherals.sv`, `Chipset.sv`, `PCXT.sv` |
| Verification matrix | Phase 8 | Testbenches |
| Non-goals | All phases | Scope control |

## 17. Risk Register

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Outer memory decode conflicts with CGA/HGC | Breaks existing video modes | Add explicit decode priority tests and smoke-test non-EGA modes. |
| VRAM video fetch bandwidth is insufficient for text mode | Text renderer cannot fetch character, attribute, and font bytes in time | Add a prefetch/cache pipeline or schedule multi-cycle fetches before pixel output. |
| Pixel panning causes byte-boundary artifacts | Scrolling glitches in games | Test panning `0..15` with known plane patterns. |
| CRTC timing changes affect MiSTer output sync | Display instability | Keep internal EGA counters separate from output sync shaping. |
| Broader register readback diverges from strict IBM behavior | Probe-dependent software differences | Allow compatible readback only where useful; preserve write side effects. |
| Status bit timing is tied to post-scaler video signals | BIOS/game polling glitches | Derive status from internal EGA CRTC windows. |
| Text renderer changes graphics fetch path | Regression in graphics games | Keep text and graphics paths separately tested and selected by GC Misc bit `0`. |
| Testbenches drift from x86Box formulas | False confidence | Keep compact reference functions traceable to `SPEC.md` and x86Box function names. |

## 18. Suggested Milestone Boundaries

Use these as practical merge or checkpoint boundaries:

### Milestone A: CPU-Compatible EGA Memory

Includes:

- Phase 1 complete.
- Register outputs needed for memory decode stable.
- `ega_vram_tb.sv` expanded and passing.

Value:

- Masked sprite and planar write bugs become easier to isolate.
- Memory-map behavior no longer blocks later scanout work.

### Milestone B: Probe-Compatible EGA Registers

Includes:

- Phase 2 complete.
- Status read side effects at least partially implemented.
- Register tests passing.

Value:

- BIOS and games can program/probe EGA reliably.

### Milestone C: Correct Graphics Scanout

Includes:

- Phases 3, 4, and core Phase 5 palette/status behavior.
- Graphics scanout tests passing.
- Mode `0Dh` smoke path visually stable.

Value:

- Main EGA graphics game glitches can be investigated against a mostly correct
  hardware model.

### Milestone D: Complete Text And Mixed-Mode Support

Includes:

- Phase 6 complete.
- Text tests passing.
- Mode switches between text and graphics stable.

Value:

- EGA behaves like an adapter, not only like a graphics framebuffer.

### Milestone E: Integrated Release Candidate

Includes:

- Phases 7, 8, and 9 complete.
- Deterministic tests passing.
- Quartus build passing.
- Known EGA and non-EGA smoke tests passing.

Value:

- Ready for broader manual testing and release builds.

## 19. Implementation Notes By Existing Module

### `rtl/video/ega_vram.v`

Keep as the central CPU VRAM behavior block.

Planned work:

- Preserve existing latch behavior.
- Expand tests for A16 and memory-map modes.
- Confirm write mode 3 policy.
- Add comments tying `remap_cpu_addr` to x86Box `ega_remap_cpu_addr()`.

### `rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv`

Keep as the CPU/video clock boundary and wait-state wrapper.

Planned work:

- Confirm config synchronization after new register outputs are added.
- Decide whether text scanout needs additional video fetch scheduling.
- Clarify unused `cpu_access_en` behavior or wire it deliberately.

### `rtl/KFPC-XT/HDL/Peripherals.sv`

Main integration point for CPU memory windows and video mux.

Planned work:

- Replace fixed EGA `A0000h-AFFFFh` decode with GC memory-map-driven decode.
- Preserve CGA/HGC/Tandy behavior.
- Verify bus ready integration.

### `rtl/video/ega_top.v`

Top-level EGA register, CRTC, scanout, and output mux coordinator.

Planned work:

- Separate EGA hardware active state from MiSTer output selection.
- Complete I/O readback independent of `ega_display_sel`.
- Route active CRTC/status port based on Misc Output bit `0`.
- Add status bit `0x30` toggle.
- Select text versus graphics renderer.

### `rtl/video/ega_sequencer.v`

Sequencer register block and fetch pacing.

Planned work:

- Preserve map mask and memory mode.
- Ensure Character Map Select is exported to text renderer.
- Verify clocking mode bits drive both graphics and text width behavior.

### `rtl/video/ega_gfx_ctrl.v`

Graphics Controller register block.

Planned work:

- Preserve write/read mode outputs.
- Ensure GC Misc bit `0` drives render mode selection.
- Ensure GC Mode bit `5` drives CGA 2bpp graphics conversion.

### `rtl/video/ega_attrib_ctrl.v`

Attribute Controller and palette-index stage.

Planned work:

- Complete flip-flop side effects.
- Implement full panning cache behavior.
- Provide blink/plane-enable behavior for graphics and text.
- Keep Color Select stored but non-effective for base IBM EGA palette.

### `rtl/video/ega_pixel.v`

Graphics pixel shifter.

Planned work:

- Fix shift-register usage.
- Add low-res repeat behavior.
- Integrate panning safely.
- Add CGA 2bpp conversion support either here or in a nearby graphics render
  module.

### `rtl/video/UM6845R.v`

CRTC counter and address generator.

Planned work:

- Add or verify protected writes.
- Verify x86Box overflow formulas.
- Implement scanout remap modes exactly or through an equivalent helper.
- Preserve EGA-specific behavior behind `CRTC_TYPE`.

### `rtl/video/ega_vgaport.v`

EGA digital RGB converter.

Planned work:

- Keep current 16-color/64-color mapping and brown exception.
- Add direct tests for all 64 codes and selected 16-color cases.

### `egabios.asm`

Minimal compatibility BIOS shim.

Planned work:

- Keep as smoke-test input.
- Avoid moving hardware semantics into BIOS.
- Update only if hardware register behavior changes require a cleaner probe or
  mode-programming sequence.

## 20. Execution Checklist

Use this checklist during implementation:

- Before editing:
  - Identify the `SPEC.md` section being implemented.
  - Identify the deterministic test that will prove it.
  - Check current git status for unrelated user changes.

- During editing:
  - Keep changes scoped to one phase or tightly related dependency.
  - Prefer existing module boundaries unless a new module clearly reduces
    complexity.
  - Add comments only for formulas and hardware behavior that are not obvious.

- Before finishing a phase:
  - Run relevant testbenches.
  - Inspect any modified register or memory decode paths.
  - Confirm non-target video paths were not accidentally gated by EGA changes.
  - Update documentation if behavior intentionally differs from strict IBM EGA.

- Before release-candidate testing:
  - Run all deterministic tests.
  - Run Quartus build.
  - Run EGA BIOS/mode `0Dh` smoke test.
  - Run known EGA game tests.
  - Run CGA/HGC/Tandy smoke tests.

## 21. Expected Order Of First Concrete Tasks

The first implementation tasks should be:

1. Fix and extend `ega_vram_tb.sv` for the current `cpu_a16` interface.
2. Add memory-map and chain-2 test coverage.
3. Fix any discovered `ega_vram.v` mismatches.
4. Update `Peripherals.sv` EGA memory decode for all GC memory map modes.
5. Add register/I/O tests for Attribute Controller flip-flop and status reads.
6. Remove `ega_display_sel` gating from register readback where it suppresses
   EGA hardware visibility.
7. Add CRTC protected writes.
8. Add scanout address remap tests before modifying pixel rendering.

This order maximizes early confidence in CPU-visible behavior, which is the
foundation for diagnosing the visible glitches reported in games.
