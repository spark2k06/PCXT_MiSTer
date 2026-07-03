# MCGA Gate Mode 13h Specification

This document defines the target behavior for adding MCGA-style video mode
`13h` (`320x200x256`) to the clean EGA-centered PCXT MiSTer core.

The feature is controlled by a new user-facing OSD option:

```text
MCGA Gate: Disabled, Enabled
```

When `MCGA Gate` is `Disabled`, the core must behave as the current clean EGA
core. When `MCGA Gate` is `Enabled`, the core must keep all current EGA and
CGA-compatible EGA behavior, and additionally expose MCGA-compatible mode
`13h`.

## 1. Background

The IBM EGA option ROM currently used by this project is not a VGA or MCGA BIOS.
The original IBM EGA ROM does not implement BIOS video mode `13h` as
`320x200x256`.

Mode `13h` belongs to the MCGA/VGA software interface:

- Resolution: `320x200`.
- Color depth: 8 bits per pixel.
- Visible colors: 256 simultaneous palette entries.
- CPU framebuffer: packed linear bytes at `A000:0000`.
- Framebuffer size: 64,000 bytes.

Many DOS games use BIOS only to enter mode `13h`, then draw by writing directly
to `A000:0000`. Therefore BIOS support alone is not enough; the RTL must provide
the memory, palette, and pixel pipeline expected by software.

## 2. Objective

Add a gated MCGA compatibility extension to the existing EGA-owned video core.

The final implementation must:

- Add an OSD `MCGA Gate` option.
- Keep `MCGA Gate=Disabled` as a strict clean-EGA compatibility mode.
- Add BIOS-visible mode `13h` only when `MCGA Gate=Enabled`.
- Render packed 8bpp `A000:0000` mode `13h` through the active video pipeline.
- Support the VGA/MCGA DAC/palette programming interface needed by mode `13h`
  software.
- Avoid resurrecting standalone CGA/HGC/Tandy video hardware.

## 3. Non-Goals

- Implement a full VGA adapter.
- Implement SVGA/VBE modes.
- Implement VGA text mode `03h` as a separate VGA text pipeline.
- Reintroduce standalone CGA, HGC, Tandy, or `cga_passthrough`.
- Make `MCGA Gate=Enabled` the default behavior before the mode is verified.
- Provide perfect compatibility with games that depend on undocumented VGA
  extensions outside MCGA/VGA mode `13h`.

## 4. Configuration Model

### 4.1 OSD Option

Add one OSD option in the video or hardware section:

```text
MCGA Gate, Disabled, Enabled
```

Recommended default:

```text
Disabled
```

The selected bit must be wired to the video subsystem as `mcga_enabled` or an
equivalent clearly named signal.

### 4.2 Behavior Matrix

| Setting | INT 10h mode 13h | A000 packed 8bpp | EGA modes | CGA-compatible EGA modes |
| --- | --- | --- | --- | --- |
| Disabled | Not advertised/supported | Disabled | Supported | Supported |
| Enabled | Supported | Supported | Supported | Supported |

`MCGA Gate` must not change any existing EGA/CGA-compatible behavior except
where mode `13h` explicitly takes ownership after software selects it.

## 5. BIOS And Software Interface

### 5.1 Required INT 10h Behavior

The implementation must provide mode `13h` through BIOS interrupt `10h`.

Minimum required services:

- `AH=00h, AL=13h`: set video mode `320x200x256` when `MCGA Gate=Enabled`.
- `AH=0Fh`: return current mode `13h` while mode `13h` is active.
- `AH=0Bh`: set border/background where compatible or ignore safely.
- `AH=0Ch`: write pixel, at least for mode `13h`.
- `AH=0Dh`: read pixel, at least for mode `13h`.
- `AH=10h` palette services needed by common games if they use BIOS instead of
  direct DAC ports.

The mode set path must update BIOS Data Area fields consistently:

- `0040:0049` current video mode = `13h`.
- `0040:004A` columns = `40`.
- `0040:004C` video page size = `FA00h` or an equivalent value consistent with
  64,000-byte packed mode.
- `0040:004E` current page offset = `0000h`.
- `0040:0084` rows minus one = `24` if DOS text assumptions require a sane
  value after mode set, or a documented MCGA-compatible value.
- `0040:0085` character height = `08h` if needed for BIOS compatibility.

### 5.2 Delivery Options

The preferred long-term delivery is an option ROM or patched EGA option ROM
loaded by the core. A DOS TSR is acceptable as a bring-up path but must not be
the only supported integration if the goal is out-of-box game compatibility.

Supported development sequence:

1. Bring up RTL mode `13h` with direct register or testbench activation.
2. Add a small DOS TSR or `.COM` helper that hooks `INT 10h` and sets mode
   `13h`.
3. Move the hook into the video BIOS or a chained option ROM once stable.

### 5.3 TSR Feasibility

A TSR loaded from `AUTOEXEC.BAT` can intercept `INT 10h` and implement
`AH=00h, AL=13h`. A `CONFIG.SYS` device driver can also install the hook earlier.

Limitations:

- A TSR cannot make mode `13h` work without RTL support for packed 8bpp video.
- Some games may probe VGA/MCGA ports directly before or after calling BIOS.
- Games launched before the TSR loads will not see the extension.
- Boot-time software will not see the extension unless it is in an option ROM or
  early device driver.

## 6. Hardware Architecture

### 6.1 Ownership

MCGA mode `13h` must be implemented as an extension of the existing clean video
owner, not as a separate card mux.

The video ownership model becomes:

- EGA owns normal EGA and CGA-compatible modes.
- MCGA mode `13h` owns the active display only while:
  - `MCGA Gate=Enabled`, and
  - BIOS/register state selects mode `13h`.
- The top-level video output remains a single active path.

### 6.2 Mode State

Add explicit mode state:

```verilog
mcga_enabled
mcga_mode13_active
```

`mcga_mode13_active` must reset to `0`.

Mode `13h` activation must be impossible when `mcga_enabled=0`.

### 6.3 Framebuffer

Mode `13h` requires a packed 8bpp framebuffer:

- Base aperture: `A0000h`.
- Size: `64 KiB` minimum.
- Address mapping: CPU physical `A0000h + offset`.
- Pixel address: `y * 320 + x`.
- One byte per pixel.
- No planar write modes are required for the initial mode `13h` target.

The implementation may reuse existing EGA VRAM storage only if the mode `13h`
packed byte layout is preserved exactly for CPU reads/writes and rendering.
If reuse creates coupling with EGA planar semantics, add a dedicated mode `13h`
RAM block.

### 6.4 Memory Decode

When `mcga_mode13_active=1`:

- CPU writes to `A0000h-AFFFFh` update packed framebuffer bytes.
- CPU reads from `A0000h-AFFFFh` return packed framebuffer bytes.
- Writes outside the 64,000-byte visible range but within the 64 KiB aperture
  should be stored if RAM is 64 KiB; rendering ignores bytes beyond offset
  `0xF9FF`.
- EGA planar decode must not corrupt mode `13h` packed data.

When `mcga_mode13_active=0`:

- Existing EGA memory behavior must remain unchanged.

### 6.5 Pixel Pipeline

When `mcga_mode13_active=1`:

- Active area is `320x200`.
- Each fetched framebuffer byte is a palette index.
- Pixel color is read from the 256-entry DAC palette.
- Output is expanded to the core's RGB width.
- Horizontal/vertical sync and blanking must be stable and accepted by the
  MiSTer video path.

The initial implementation may use the existing EGA-compatible 320x200 timing if
it produces stable display output, but this choice must be documented. If games
or scaler behavior require VGA-like 70 Hz timing, implement explicit MCGA/VGA
mode `13h` timing.

## 7. DAC And Palette Interface

Mode `13h` software commonly programs VGA DAC ports directly. The implementation
must support at least:

| Port | Direction | Purpose |
| --- | --- | --- |
| `03C7h` | write | DAC read index |
| `03C8h` | write | DAC write index |
| `03C9h` | read/write | DAC data, 6-bit RGB components |

Required behavior:

- 256 palette entries.
- 3 components per entry: red, green, blue.
- Component width visible to software: 6 bits.
- Auto-increment DAC index after three component writes or reads.
- Reset/default palette must match standard VGA/MCGA expectations closely enough
  for games that do not program their own palette.

The hardware output may expand 6-bit DAC components to 8-bit or 6-bit internal
RGB by bit replication or scaling.

## 8. Register Compatibility

The minimal hardware target is BIOS-driven mode `13h` plus direct framebuffer
and DAC access.

Common direct-port compatibility should be evaluated and implemented where
required:

- Sequencer index/data: `03C4h/03C5h`.
- Graphics controller index/data: `03CEh/03CFh`.
- CRT controller index/data: `03D4h/03D5h`.
- Attribute controller/index flip-flop: `03C0h/03C1h`.
- Input status register: `03DAh`.
- Misc output register: `03C2h`.

For the first complete mode `13h` target, unsupported VGA registers may return
safe defaults only if common mode `13h` games still work. Any omitted register
must be documented with a compatibility reason.

## 9. Interaction With Existing EGA

### 9.1 Disabled Gate

With `MCGA Gate=Disabled`:

- Mode `13h` must not enter packed 8bpp mode.
- Existing EGA BIOS behavior remains the source of truth.
- Existing EGA tests must pass unchanged.

### 9.2 Enabled Gate

With `MCGA Gate=Enabled`:

- EGA mode set behavior remains unchanged for modes other than `13h`.
- Selecting mode `13h` switches to MCGA packed mode.
- Leaving mode `13h` by selecting an EGA/CGA-compatible mode returns ownership
  to EGA.

### 9.3 Reset

Reset must clear `mcga_mode13_active`.

The `MCGA Gate` OSD setting may persist as an OSD status bit, but active video
mode must reset to the same initial clean EGA state as the current core.

## 10. Test Requirements

### 10.1 RTL Tests

Add focused tests for:

- `MCGA Gate=Disabled` rejects or ignores mode `13h` activation.
- `MCGA Gate=Enabled` allows mode `13h` activation.
- CPU write/read to `A0000h` returns packed bytes.
- Pixel fetch maps offset `y * 320 + x` to the expected DAC index.
- DAC port writes update palette entry RGB values.
- DAC auto-increment after three component writes.
- Switching out of mode `13h` restores EGA-owned memory/render behavior.

### 10.2 BIOS/Software Tests

Add a small DOS test program that:

- Calls `INT 10h` with `AX=0013h`.
- Writes a 256-color ramp into `A000:0000`.
- Programs DAC entries through `03C8h/03C9h`.
- Calls `INT 10h AH=0Fh` and verifies mode `13h`.
- Optionally returns to mode `03h`.

### 10.3 Hardware Smoke

Hardware smoke should include:

- Boot with `MCGA Gate=Disabled`, verify existing EGA behavior.
- Boot with `MCGA Gate=Enabled`, verify existing EGA behavior before selecting
  mode `13h`.
- Run a simple mode `13h` test pattern.
- Run at least one known mode `13h` game or demo.
- Return to text mode and verify stable output.

## 11. Implementation Phases

### Phase 0: Baseline

- Record current EGA clean-core commit and build artifact.
- Confirm the IBM EGA BIOS does not implement mode `13h`.
- Identify candidate mode `13h` test software.

### Phase 1: OSD Gate

- Add `MCGA Gate` to `CONF_STR`.
- Wire the selected status bit to the video subsystem.
- Verify that toggling the gate has no effect before MCGA mode is implemented.

### Phase 2: Packed Framebuffer

- Add packed 64 KiB `A0000h` memory behavior for mode `13h`.
- Add tests for CPU reads/writes.

### Phase 3: DAC

- Implement 256-entry DAC.
- Implement ports `03C7h`, `03C8h`, and `03C9h`.
- Add palette tests.

### Phase 4: Pixel Render

- Add mode `13h` timing and pixel fetch.
- Route packed pixels through the single active video path.
- Add render tests.

### Phase 5: BIOS/TSR

- Add development TSR or test hook for `INT 10h AX=0013h`.
- Move final behavior into option ROM or patched BIOS if required for out-of-box
  compatibility.

### Phase 6: Compatibility Closure

- Run DOS mode `13h` tests.
- Run at least one real game/demo.
- Document unsupported VGA behavior.
- Build full Quartus bitstream and record resources/timing.

## 12. Definition Of Done

The feature is complete when:

- `MCGA Gate` is visible in OSD and defaults to `Disabled`.
- `MCGA Gate=Disabled` preserves current clean EGA behavior.
- `MCGA Gate=Enabled` exposes working BIOS mode `13h`.
- `A000:0000` packed 8bpp writes render as `320x200x256`.
- DAC programming through `03C7h/03C8h/03C9h` works.
- Switching from mode `13h` back to EGA/CGA-compatible modes works.
- Focused RTL tests pass.
- A DOS test program passes.
- A full Quartus build produces a bitstream.
- Any remaining timing or compatibility limitations are documented.
