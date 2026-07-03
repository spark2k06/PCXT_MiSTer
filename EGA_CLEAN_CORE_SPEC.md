# EGA Clean Core Specification

This document defines the target architecture for converting this PCXT MiSTer
variant into an EGA-centered video core. The goal is not to preserve the old
multi-video-card coexistence model. The goal is to make EGA the single video
hardware model and keep CGA compatibility inside that EGA model.

## 1. Objective

The final core should expose one primary video device: IBM EGA.

The implementation should remove the old CGA, HGC, Tandy video, Tandy audio,
Tandy keyboard, and user-facing video feature gate model from this variant.
Games and software that use CGA-compatible modes must still work, but they must
do so through EGA-compatible behavior, not through a separate CGA module.

The current `EGA Gate` concept should disappear. A future `MCGA Gate` option may
exist as a reserved configuration surface, but it must have no functional effect
until MCGA is actually implemented.

## 2. Non-Goals

- Preserve the old standalone CGA implementation in this branch.
- Preserve HGC or Tandy video behavior in this branch.
- Preserve Tandy audio or Tandy keyboard variant behavior in this branch.
- Keep runtime menu options for choosing between CGA, HGC, Tandy, and EGA.
- Keep compatibility by routing EGA through `cga.v` or CGA VRAM.
- Implement MCGA as part of this refactor.

Historical CGA/HGC/Tandy sources may be retained outside this branch or in an
external archive, but they are not maintenance targets for this variant.

## 3. Required Compatibility

EGA must remain compatible with software that uses CGA-era behavior through an
EGA card. This includes:

- CGA-compatible text modes.
- CGA-compatible graphics modes exposed by EGA.
- B8000-style text and graphics memory behavior as implemented by EGA.
- CGA-style 2bpp graphics rendering when EGA registers select that mode.
- BIOS and DOS software that probes for common CGA/EGA behavior.
- Existing EGA BIOS boot, text, graphics, palette, and status behavior.

The important distinction is architectural: CGA compatibility is an EGA feature,
not a separate CGA device.

## 4. Configuration Model

The target build should remove or hard-code the old video variant macros:

```tcl
set_global_assignment -name VERILOG_MACRO "SYSTEM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ROM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_VIDEO=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_AUDIO=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_KBD=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_CGA=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_HGC=0"
```

The cleaned core should not need these switches for video selection. If any are
temporarily left during the transition, they must be treated as migration debt
and removed before the refactor is considered complete.

The target state is:

- EGA is always compiled in.
- CGA is not compiled in as a separate device.
- HGC is not compiled in.
- Tandy video/audio/keyboard variants are not compiled in.
- User-facing video selection is removed or reduced to future reserved options.
- `MCGA Gate`, if added, is a no-op placeholder until MCGA work begins.

## 5. Architecture Rules

### 5.1 Single Video Owner

`ega_top` or its successor must own the complete video path:

- CPU-visible video I/O decode.
- CPU-visible video memory decode.
- Planar VRAM access.
- Text rendering.
- Graphics rendering.
- CGA-compatible EGA rendering.
- Splash rendering.
- RGB output and scandoubling.
- OSD-visible sync, blanking, and resolution behavior.

No EGA display path may depend on `cga.v`, CGA VRAM, HGC VRAM, Tandy banking, or
old video mux fallbacks.

### 5.2 Native EGA CGA Compatibility

CGA-compatible behavior should live in EGA modules or explicitly named EGA
compatibility helpers. Acceptable names should make ownership clear, for example:

- `ega_cga_compat_*`
- `ega_2bpp_*`
- `ega_b800_*`

Avoid names that imply a separate CGA card unless the module is being deleted.

### 5.3 No Hidden Passthrough

The cleaned core must not use a hidden CGA passthrough as a fallback for:

- Splash screen.
- Boot text.
- Initial video timings.
- CGA-compatible games.
- Blank or inactive EGA periods.
- OSD resolution stabilization.

Fallback behavior should be explicit inside the EGA path.

### 5.4 Reduced Conditional Compilation

The final RTL should prefer one clear EGA path over nested `ifdef` trees. During
the transition, conditional blocks are acceptable only to keep the build working.
They should be removed once their alternative path is gone.

## 6. Modules To Retire Or Absorb

The refactor should retire these old video ownership areas from this branch:

- `rtl/video/cga.v`
- `rtl/video/cga_pixel.sv`
- `rtl/video/cga_sequencer.v`
- `rtl/video/cga_attrib.v`
- `rtl/video/cga_vgaport.v`
- `rtl/video/cga_composite.v`
- `rtl/video/cga_vram.v`, if unused after EGA owns all video RAM behavior.
- HGC modules and HGC VRAM wiring.
- Tandy video banking and Tandy-specific CGA paths.
- Video menu/status options that only select removed hardware.

Some support blocks may stay if they are generic and renamed or documented as
generic, for example:

- Shared scandoubler.
- Generic RGB converters if not CGA-specific.
- Generic RAM primitives.
- Character ROM assets, if EGA still needs a boot/splash fallback font.

## 7. Integration Targets

### 7.1 `Peripherals.sv`

`Peripherals.sv` should eventually stop being a video-card mux. It should wire
one video subsystem into the bus:

- EGA memory decode.
- EGA I/O decode.
- EGA VRAM frontend.
- EGA RGB/sync output.
- EGA splash path.

The old `ENABLE_CGA`, `ENABLE_HGC`, `ENABLE_TANDY_VIDEO`, and `swap_video`
branches should be removed or replaced by fixed EGA wiring.

### 7.2 `ega_top.v`

`ega_top.v` should stop instantiating `cga_passthrough`. Any behavior currently
borrowed from CGA must be made native:

- Pixel clock/divider ownership.
- Reset/default timing ownership.
- Text/graphics fallback ownership.
- CGA-compatible mode scanout.
- Bus-visible CRTC/status behavior, if currently inherited.

### 7.3 VRAM

There should be one EGA VRAM model for all EGA-visible modes. CGA-compatible
memory behavior must be expressed through EGA remapping, chain/odd-even modes,
and graphics controller behavior rather than through separate CGA RAM.

### 7.4 Splash

The splash screen must render through EGA. It may use a temporary internal font
before BIOS font loading, but the screen buffer must live in EGA-owned memory.

### 7.5 OSD And Resolution

The OSD should observe EGA-owned sync, blanking, and display enable signals.
Resolution reporting should not depend on CGA fallback timings.

## 8. Suggested Refactor Phases

### Phase 0: Baseline And Freeze

- Record current known-good EGA behavior.
- Record current CGA-compatible game smoke tests under EGA.
- Keep the latest working `.rbf` or `.sof` as an external recovery baseline.

Acceptance:

- Current EGA text, EGA graphics, CGA-compatible games under EGA, and splash
  behavior are documented with screenshots or notes.

### Phase 1: Remove Runtime Gate Semantics

- Make EGA the default and only active video path.
- Remove user-facing `EGA Gate` behavior.
- Add `MCGA Gate` only as an inert placeholder if desired.

Acceptance:

- Boot behavior no longer depends on toggling EGA on/off.
- EGA BIOS path remains active.

### Phase 2: Break `ega_top` CGA Passthrough

- Remove `cga_passthrough` from `ega_top`.
- Replace borrowed CGA timing/output defaults with EGA-owned defaults.
- Keep CGA-compatible rendering inside EGA.

Acceptance:

- EGA text mode boots.
- EGA graphics modes work.
- CGA-compatible games still display through EGA.

### Phase 3: Simplify `Peripherals.sv`

- Remove CGA/HGC/Tandy video muxing.
- Remove CGA/HGC/Tandy VRAM instances.
- Remove `swap_video` behavior if it only applies to removed hardware.
- Route all video memory and I/O through the EGA subsystem.

Acceptance:

- No separate CGA/HGC/Tandy VRAM is instantiated.
- OSD receives EGA sync and RGB only.

### Phase 4: Remove Macros And Dead Files

- Delete or stop compiling old CGA/HGC/Tandy modules.
- Remove obsolete QSF/QIP assignments.
- Remove obsolete menu strings and status bits.
- Remove dead `ifdef` branches.

Acceptance:

- Build no longer references removed video modules.
- `rg "ENABLE_CGA|ENABLE_HGC|ENABLE_TANDY_VIDEO|EGA Gate"` returns no active
  implementation references, except historical documentation if intentionally
  retained.

### Phase 5: Verification And Cleanup

- Expand EGA testbenches around CGA-compatible EGA modes.
- Add integration smoke checks for boot, splash, text, EGA graphics, and
  CGA-compatible games.
- Update documentation to reflect the single-video architecture.

Acceptance:

- Deterministic tests cover EGA VRAM, CRTC, text, graphics, status, and
  CGA-compatible rendering.
- Game smoke matrix includes representative EGA and CGA-compatible titles.

## 9. Verification Requirements

Minimum verification before considering the refactor complete:

- EGA BIOS boots consistently from cold start.
- Splash screen renders through EGA.
- EGA text mode is stable after reset.
- EGA graphics games render without vertical black lines or corrupted palette.
- CGA-compatible games render through EGA without requiring CGA hardware.
- OSD reports stable, expected resolutions.
- Existing focused testbenches pass or known pre-existing failures are
  documented.
- No removed video module is instantiated in the final build.

## 10. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| CGA-compatible games depended on old CGA module behavior. | Regressions in games that should still work on EGA. | Port required CGA-compatible behavior into EGA before deleting fallback. |
| Removing mux logic changes sync/blanking timing. | OSD may report wrong resolution or monitors may lose lock. | Move timing ownership to EGA first; test cold boot and reset. |
| Tandy/HGC side effects are accidentally still referenced. | Build complexity remains or dead paths interfere. | Use `rg` checkpoints and remove dead QIP/QSF assignments. |
| BIOS assumptions are hidden in old gate behavior. | Boot instability. | Keep EGA BIOS smoke tests and cold-reset tests at every phase. |
| Refactor touches too much at once. | Hard-to-debug regressions. | Commit by phase with one architectural boundary per commit. |

## 11. Completion Criteria

The clean EGA core refactor is complete when:

- EGA is the only active video hardware model in this branch.
- CGA compatibility is implemented inside EGA.
- CGA, HGC, and Tandy modules are not instantiated or selected.
- Old video configuration macros and menu options are removed from active code.
- `EGA Gate` no longer exists as a functional or user-facing concept.
- Any `MCGA Gate` surface is explicitly inert and documented as future work.
- Boot, text, graphics, splash, and CGA-compatible game smoke tests pass through
  the EGA path.
