# Specification: VGA-style palette handling under the VGA mode 13h option

Naming note: this option and every identifier behind it (`vga_dac.v`,
`vgatsr.asm`, `vga_mode13_*`, ...) were called "MCGA" until this was written.
86Box, whose code this core is modelled on, has no MCGA emulation at all —
even its one historically-MCGA machine (the PS/1 2011) is emulated as a VGA
variant. Real MCGA hardware does not have EGA's 16-colour planar graphics
modes (`0Dh`/`0Eh`/`10h`) at all, so a real MCGA could never run the mode
`0Dh` gameplay this document is about in the first place — that behaviour,
the DAC augmenting the EGA modes this core already had, is VGA, not MCGA.
Renamed throughout for accuracy; no logic changed.

Status: **Stages 1 and 2 implemented** (see §4 and §5). RTL: the 256-entry DAC
now feeds every mode, not just mode 13h, gated by a per-entry valid bit so the
option-off path is unchanged by construction. TSR: the DAC BIOS calls
(`INT 10h AH=10h AL=10h/12h/15h/17h`) are served in any mode, and `AL=93h` no
longer drops mode 13h on re-entry (RC6). Stage 3 items are unimplemented and
optional — build only what §6.2 asks for.

Confirmed on hardware: Titus the Fox gameplay now renders in the game's own
palette, which settles RC7 in favour of the mode `0Dh` theory. Making the DAC
BIOS calls live also exposed **RC8**, a register-preservation bug in
`read_one_dac` that hung every fade; fixed, awaiting a hardware run.

**RC9** below was that same exposure hitting the readback path, and it was the
one that actually broke the fades. **RC10** is a separate CDC hazard on the
`3CDh` control port that this work turned from harmless into destructive.

Still open, and **not** caused by this work: the build does not close timing.
`clk_100`, the `ascal` scaler domain, was at −1.564 ns / −150.066 ns TNS before
any of these changes and is at −1.671 ns / −155.022 ns after — the same domain,
which none of this logic is in. See RC7 in
[max-speed-stability.md](max-speed-stability.md); it needs fixing on its own
merits before any residual video glitch can honestly be blamed on anything here.
Scope: `status[29]` (OSD *VGA Mode 13h*), `rtl/video/*`, `SW/vga/vgatsr.asm`
Branch at time of writing: `ega-test` (`13b3093`)

Findings are labelled **[verified]** when they follow directly from the RTL or
from the 86Box reference sources, and **[hypothesis]** when they are a
plausible mechanism that still needs a run on hardware to confirm.

---

## 1. Problem statement

With the OSD option *VGA Mode 13h* on and `vgatsr.com` resident, some games
that detect a VGA and then use it only partially come out with the wrong
colours:

* **Titus the Fox** (`FOX.COM`) and **Prehistorik 2** (`GO.EXE`): the title /
  presentation screen is correct, but as soon as the game proper starts the
  picture is drawn with what looks like the stock EGA 16-colour palette
  instead of the palette the game intended. Shapes, tiles and sprites are all
  in the right place — only the colours are wrong.

The goal is to get these games right at the lowest possible cost, by moving
palette handling closer to a real VGA while the OSD option is on, and to keep
the current behaviour **bit-for-bit identical when the option is off**.

---

## 2. What the palette path does today

### 2.1 The EGA path **[verified]**

`ega_attrib_ctrl.v` → `video_scandoubler.v` → `ega_vgaport.v` → `ega_red/green/blue`:

1. `ega_attrib_ctrl` takes the 4-bit pixel index, applies the plane-enable
   mask and blink logic and looks it up in the 16 attribute palette registers
   (`raw_palette`), producing a **6-bit** colour code
   ([ega_attrib_ctrl.v:67](../rtl/video/ega_attrib_ctrl.v#L67)).
2. Colour Select (ATC index `14h`) is latched and readable but deliberately
   does **not** affect the output — that matches a base IBM EGA
   ([ega_attrib_ctrl.v:65-67](../rtl/video/ega_attrib_ctrl.v#L65)).
3. `ega_vgaport` converts those 6 bits to RGB with two different rules,
   selected by `palette_64_mode`, which this core derives from Miscellaneous
   Output bit 7 ([ega_top.v:622](../rtl/video/ega_top.v#L622)):
   * bit 7 = 1 (350-line modes): full `rgbRGB`, i.e. `red = 42*R + 21*r`.
   * bit 7 = 0 (200-line CGA-compatible modes): bit 4 acts as a shared
     intensity for all three guns, bit 3 is ignored, plus a special case that
     turns code `06h` into brown.

So on the EGA path the palette is **six bits wide and there is no DAC at all**.
That is correct for an IBM EGA: its palette lives in the attribute controller.

### 2.2 The VGA mode 13h path **[verified]**

`vga_mode13_renderer` reads the packed framebuffer and uses the pixel byte
directly as an index into `vga_dac` (256 entries × 6 bits per gun), whose
ports `3C7h/3C8h/3C9h` are decoded in `ega_top` and gated on `vga_enabled`
([ega_top.v:139-141](../rtl/video/ega_top.v#L139)). Entering mode 13h
(`out 3CDh, 13h` from the TSR) pulses `reset_palette`, which reloads the
standard 256-colour VGA default table.

The two paths meet only at the very end, in a mux on `vga_mode13_active`
([ega_top.v:804-806](../rtl/video/ega_top.v#L804)).

### 2.3 What software sees

With `vgatsr.com` resident the machine answers **"VGA present"** to
`INT 10h AH=1Ah` and reports colour EGA to `AH=12h/BL=10h`. Ports
`3C7h-3C9h` answer. Everything else — the video BIOS underneath, the CRTC,
the attribute controller — is an EGA.

That is the whole problem: we tell software it is a VGA, and software then
uses VGA facilities in modes where this core still behaves exactly like an EGA.

---

## 3. Root-cause analysis

### RC1 — The DAC is wired only to the mode 13h renderer **[verified]** — main cause

`vga_dac` has a single sample port and it is consumed by
`vga_mode13_renderer` alone. In any other mode the DAC contents are written,
stored and then completely ignored: `ega_red/green/blue` come from
`ega_vgaport`.

On a real VGA the DAC is in the path for **every** mode. The 16-colour modes
go through it as

```
pixel[3:0] → ATC palette register → 6-bit value → (+ Colour Select) → 8-bit DAC index → RGB
```

which 86Box implements literally as
`pallook[egapal[index] & dac_mask]` (`src/video/vid_svga_render.c:321`), with

```c
egapal[c] = (attrregs[0x10] & 0x80) ? ((attrregs[c] & 0x0f) | ((attrregs[0x14] & 0x0f) << 4))
                                    : ((attrregs[c] & 0x3f) | ((attrregs[0x14] & 0x0c) << 4));
```

(`src/video/vid_svga.c:249-254`).

**Consequence:** a game that detects VGA, switches to a 16-colour mode
(`0Dh`, `0Eh`, `10h`) for gameplay and then sets its colours through the DAC
gets the stock EGA palette on this core. This matches the reported symptom
exactly, including the fact that the 256-colour presentation screen — the one
place where the DAC *is* in the path — looks right.

### RC2 — The TSR only serves the DAC BIOS calls while mode 13h is active **[verified]**

`int10_hook` gates the whole `AH=10h` group on `current_mode == 13h`
([vgatsr.asm:144-157](../SW/vga/vgatsr.asm#L144)). Outside mode 13h the
call is chained to the EGA BIOS, which does not implement the DAC
subfunctions at all (`AL=10h/12h/15h/17h` are VGA additions). So
`INT 10h AX=1012h` — the single most common way for a game to load 16 palette
entries on a VGA — is **silently dropped** in mode `0Dh`.

Even after RC1 is fixed, a game that uses the BIOS rather than the ports would
still see nothing happen.

### RC3 — The attribute palette holds EGA-200-line codes, not VGA codes **[verified]**

The IBM EGA BIOS programs the attribute palette of the 200-line modes with the
CGA-compatible set (`00h`-`07h`, `10h`-`17h`); this core's power-on default
mirrors it ([ega_attrib_ctrl.v:77-84](../rtl/video/ega_attrib_ctrl.v#L77)). A
VGA BIOS instead programs `00h,01h,02h,03h,04h,05h,14h,07h,38h..3Fh` for every
16-colour mode and loads DAC entries `00h-3Fh` with the 64 EGA `rgbRGB`
colours.

| Colour | VGA ATC value | EGA 200-line ATC value | RGB (6-bit) |
|--------|---------------|------------------------|-------------|
| 0 black        | `00` | `00` | 0, 0, 0 |
| 1 blue         | `01` | `01` | 0, 0, 42 |
| 2 green        | `02` | `02` | 0, 42, 0 |
| 3 cyan         | `03` | `03` | 0, 42, 42 |
| 4 red          | `04` | `04` | 42, 0, 0 |
| 5 magenta      | `05` | `05` | 42, 0, 42 |
| 6 brown        | `14` | `06` | 42, 21, 0 |
| 7 light grey   | `07` | `07` | 42, 42, 42 |
| 8 dark grey    | `38` | `10` | 21, 21, 21 |
| 9 light blue   | `39` | `11` | 21, 21, 63 |
| 10 light green | `3A` | `12` | 21, 63, 21 |
| 11 light cyan  | `3B` | `13` | 21, 63, 63 |
| 12 light red   | `3C` | `14` | 63, 21, 21 |
| 13 light mag.  | `3D` | `15` | 63, 21, 63 |
| 14 yellow      | `3E` | `16` | 63, 63, 21 |
| 15 white       | `3F` | `17` | 63, 63, 63 |

Note the collision on row 6/12: code `14h` means *brown* under the VGA
convention and *light red* under the EGA 200-line one. **No single DAC default
table can serve both conventions**, which is why the design below never tries
to; it keeps the EGA interpretation for every entry software has not
explicitly written.

This only matters for games that write the DAC at the VGA indices
(`00h..05h, 14h, 07h, 38h..3Fh`) while leaving the attribute palette as the
BIOS set it. Games that first force the attribute palette to the identity
`00h..0Fh` (the usual idiom, `INT 10h AX=1002h`) are unaffected.

### RC4 — The PEL mask register (`3C6h`) does not exist **[verified]**

`3C6h` is not decoded anywhere in `ega_top`. Reads float and writes are lost.
Software uses it for fades and, quite often, as a VGA presence test (write a
value, read it back). 86Box models it as an AND on the DAC index, not on the
RGB output (`src/video/vid_svga.c:342`).

### RC5 — DAC port readback details differ from a VGA **[verified, minor]**

* Reading `3C7h` returns the read index; a real VGA returns the **DAC state**
  register (`0` = write mode, `3` = read mode) (`src/video/vid_svga.c:556`).
* `vga_dac_io` keeps **separate** read and write index counters; a VGA has one
  shared `dac_addr`, where writing `3C7h` loads `val + 1` and reads at `3C9h`
  return entry `dac_addr - 1` (`src/video/vid_svga.c:344-348`).

Read-modify-write fade loops that use `3C7h` for reading and `3C8h` for writing
work either way, so this is fidelity, not a known break.

### RC6 — `AX=0093h` drops out of mode 13h **[verified, robustness]**

`int10_hook` compares the full `AL` against `13h`
([vgatsr.asm:70-71](../SW/vga/vgatsr.asm#L70)). Bit 7 of `AL` is the
standard "do not clear video memory" flag, so a game re-entering mode 13h with
`AX=0093h` is treated as *some other mode*: the TSR clears `3CDh`, the core
leaves mode 13h and the screen goes black.

Related: nothing clears the mode 13h framebuffer on a mode set, so `AX=0013h`
leaves the previous image behind — the opposite deviation.

### RC8 — `AX=1015h` destroys BH, which hangs fade loops **[verified]**

Found after Stage 2 landed: with the DAC subfunctions reachable outside mode
13h, Titus the Fox stopped completing its fades — the logo fades forever and
the game never proceeds. Forcing the fade off (`MTF /v /f`) avoided it.

`read_one_dac` pushed only `AX`:

```asm
read_one_dac:
    push ax
    ...
    mov bh, al        ; red, never restored
    ...
    mov dh, bh
    pop ax
```

`INT 10h AX=1015h` returns `DH`/`CH`/`CL` and nothing else; a real VGA BIOS
leaves `BX` and `DL` untouched. Borrowing `BH` as scratch and never putting it
back overwrites the caller's register with a colour component on every call.
A fade loop that keeps its step counter in `BH` — the usual place for it —
then never reaches its last step:

```asm
    mov bh, 64
step:
    mov bl, 0
colour:
    mov ax, 1015h
    int 10h           ; BH = red value, counter gone
    ...
    dec bh            ; never reaches zero
    jnz step
```

The other three handlers (`set_one_dac`, `set_dac_block`, `read_dac_block`)
already save and restore everything they touch; `read_one_dac` was the only
one that did not, which is why this never showed up while the group was
gated to mode 13h.

Fixed by pushing `BX` and `DX`, carrying red through `AL` across the `pop dx`
so `DL` survives, and restoring both. `.set_mode13` had the same class of bug
in a milder form — a gratuitous `xor bh, bh` on a call (`AH=00h`) that has no
`BH` return value — and lost it in the same pass. The two remaining
`xor bh, bh` sites, `AH=0Fh` and `AH=12h/BL=10h`, are documented outputs and
stay.

**Rule for this file:** an `INT 10h` handler preserves every register that is
not a documented output. There is no VGA BIOS underneath to paper over a slip.

### RC9 — Readback and the picture disagreed, which *is* the gradient **[verified]**

RC8 was real but was not the whole story: fades still misbehaved after it.

The valid-bit design (§4.2) deliberately does not reload the DAC RAM on a mode
set — that is what keeps the EGA path untouched. The consequence is that after
`invalidate` the RAM still holds the **256-colour VGA default table** from the
last mode 13h entry, while the screen shows `ega_vgaport` colours. The two
disagree, and the first version of this document dismissed that as harmless
because the normal order is write-then-read.

It is not harmless, because the usual way to fade is exactly the other order:

```
read all 256 entries  ->  scale them  ->  write them back
```

Before Stage 2, that read was a no-op in a 16-colour mode and the game's own
buffer carried the fade. With the DAC calls live, the read now returns the VGA
default table — whose entries 0x10-0x1F are a **greyscale ramp** and whose
entries 0x20-0xF7 are a **hue ring**. The game scales that and writes it back,
which marks every entry valid, and the display promptly picks it up. A gradient
appears on a 16-colour screen out of nowhere, and a loop that expects the
palette to converge on something it recognises never terminates.

Confirmed in simulation: straight after a mode 13h default load, entry 20 reads
back `0E 0E 0E` — a step of the greyscale ramp.

The fix restores the invariant a real VGA has, that palette RAM and picture
always agree, by giving the **read** port the same fallback the display already
had: an entry that was never written reads back the colour `ega_vgaport` is
putting on screen for that code, under the live `palette_64_mode` rule.
Entries at or above `0x40` read back black, matching a VGA BIOS, which fills
only `0x00-0x3F` for 16-colour modes. Written entries keep winning, so nothing
about mode 13h or about a game that loads its palette first changes.

Doing it on the read port rather than by loading a table at `invalidate` time
also sidesteps a real ordering trap: the TSR writes `3CDh` *before* it chains
to the video BIOS, so at that instant Miscellaneous Output bit 7 — and with it
`palette_64_mode` — still describes the mode being left, not the one being
entered. A live fallback always uses the current rule.

### RC10 — A transient address can hit port `3CDh` **[verified]**

Reported after RC9 landed: the core became unstable. BIOS text often came up
with wrong attributes or a broken 80-column mode and needed several resets,
and in Titus the palette would be correct and then snap back to the EGA
default mid-game.

`ega_top` receives `bus_a`, `bus_d` and the strobes through **independent
per-bit two-stage synchronisers** ([Peripherals.sv:928-950](../rtl/KFPC-XT/HDL/Peripherals.sv#L928)).
Bits of a multi-bit bus do not all resolve on the same video clock, so while
an address changes the decoders can observe an address that was **never on the
bus**. The damaging case needs no exotic sequence:

```
0x3C5  sequencer data          0b011_1100_0101
0x3CF  graphics controller     0b011_1100_1111   XOR = bits 1 and 3
0x3CD  VGA control port       0b011_1100_1101   = 0x3C5 with bit 3 early
```

The BIOS and every EGA program write that pair constantly, and `bus_iow_l` is
still low across the transition, so the decode reads as a write to `3CDh`.

Both outcomes are harmful, and they map one to one onto the two symptoms:

* **Transient data is not `13h`** → `vga_mode13_exit` → since RC1 this
  invalidates all 256 DAC entries, so the game's palette vanishes and the
  screen reverts to `ega_vgaport` colours. **This is new**: before, clearing
  mode 13h while it was already clear was a no-op, which is why the hazard
  went unnoticed for so long.
* **Transient data happens to be `13h`** → `vga_mode13_enter` → the core
  switches to the VGA timing generator behind the BIOS's back and stays
  there, which is what wrecks text mode until a reset. **This one predates
  all of this work**, but `vga_mode13_ctrl` gates entry on `vga_enabled`
  ([vga_mode13_ctrl.v:19-21](../rtl/video/vga_mode13_ctrl.v#L19)), and the
  OSD option ships disabled — so it only becomes reachable once the option is
  left on, which is exactly what testing this work required.

Both reproduced in simulation against `ega_top` by injecting a single-clock
`0x3CD` on a `3C5 -> 3CF` transition: the palette went from 16 valid entries
to 0, and a second injection carrying `13h` entered mode 13h from text mode.

Fixed by qualifying the side-effecting VGA decodes with `bus_settled`, which
requires two identical consecutive samples of address, data, strobe and AEN.
A real I/O cycle holds the bus for far longer than one video clock, so nothing
legitimate is lost, and the same qualifier now guards the DAC index and data
ports, where a transient `0x3C8` would have reseated the write index and
smeared the rest of a palette load across the wrong entries.

**Extended to the older EGA decodes in a follow-up**, once the VGA fix was
confirmed on hardware to help. Those had always taken the raw synchronised bus,
and they are exposed to the same thing — `0x3C5 -> 0x3C2` passes through
`0x3C0`, `0x3C1`, `0x3C3`, `0x3C4`, `0x3C6` and `0x3C7`. The worst landing spot
is **Miscellaneous Output at `0x3C2`**, whose bit 2 selects the dot clock and
bit 7 the palette rule: a stray write there retimes the whole display, which is
the other half of the "80-column mode comes up wrong" report. Reproduced —
against the previous commit a one-clock `0x3C2` transient during a `3C0` write
reprogrammed Miscellaneous Output from `63h` to `A5h`, turning on the
16.257 MHz dot clock behind the CRTC's back.

Rather than qualify each decode, the qualifier moved to the two roots,
`ega_io_we` and `ega_io_re`, so the sequencer, graphics controller, attribute
controller, Miscellaneous Output and the DAC are all covered at once. The CRTC
select and the status-register read carry it directly, since neither derives
from those. Cost: a strobe starts one clock late. The sequencer and graphics
controller write by level so it is idempotent, the attribute controller already
edge-detects, and a real cycle holds the bus for the best part of a microsecond
against a 35 ns clock. Verified end to end through `ega_top` that attribute,
sequencer and graphics-controller writes still land and that reads still return
data with the strobes qualified.

Reading the status register is a read *with a side effect* — it resets the
attribute controller's address/data flip-flop — so it is qualified too. A
transient landing there between an ATC index write and its data write turns the
data write into an index write, which is one way attributes come out wrong. The
`bus_out` mux keeps the unqualified select, so only the side effect moves,
never the read data.

### RC7 — What the two games actually do **[hypothesis]**

The evidence says gameplay is **not** in mode 13h:

* The presentation screen is right, and the only thing special about it is
  that it is the one screen rendered through the DAC.
* `TITRE.SQZ`/`TITREEGA.SQZ` and `MENU.SQZ`/`MENUEGA.SQZ` come in VGA and EGA
  variants, but **no `LEVELx.SQZ` file has an EGA variant** — level artwork is
  shared between both video paths, i.e. it is 16-colour planar EGA artwork in
  both cases.
* The two screenshots have different active-area geometry, consistent with a
  switch between the mode 13h timing generator (640×200 active, `H_TOTAL` 912,
  `V_TOTAL` 449, [vga_mode13_timing.v:22-32](../rtl/video/vga_mode13_timing.v#L22))
  and the EGA CRTC.

So the working theory is: **256-colour title in mode 13h, then mode `0Dh` for
gameplay with the level palette pushed into the VGA DAC**. Static analysis
cannot confirm it — `FOX.COM` contains no `CD 10` bytes at all and `GO.EXE`'s
code is packed — so §5.0 defines a cheap way to confirm it on the machine
itself.

---

## 4. Design

### 4.1 Invariant to preserve

> With the OSD option off, output must be bit-for-bit what it is today.

The design gets this for free: with `vga_enabled == 0` the DAC ports do not
decode ([ega_top.v:139-141](../rtl/video/ega_top.v#L139)), so no DAC entry can
ever be written, so every entry stays *invalid* and the EGA path keeps using
`ega_vgaport` exactly as now. The new mux is additionally qualified with
`vga_enabled`.

### 4.2 Key idea — per-entry validity

Instead of trying to preload the DAC with an "EGA-compatible" default table
(impossible, see RC3), each of the 256 DAC entries carries a **valid** bit:

| Event | Effect on the valid bits |
|-------|--------------------------|
| Hard reset | all cleared |
| `out 3CDh, 13h` (enter mode 13h) | 256-colour VGA table loaded, **all set** |
| `out 3CDh, <not 13h>` (any other mode set through the TSR) | all cleared |
| Write of a DAC entry via `3C9h` | that entry set |

and the EGA path picks its RGB as

```
valid[index] ? DAC[index] : ega_vgaport(index[5:0], palette_64_mode)
```

Properties:

* No TSR, or a mode where software never touched the DAC → every entry invalid
  → **today's EGA rendering, exactly**, including the `palette_64_mode`
  switch and the `06h` → brown special case.
* Mode 13h → all entries valid → **today's mode 13h rendering, exactly**.
* A game that sets 16 DAC entries in mode `0Dh` → those 16 indices come from
  the DAC, everything else keeps the EGA interpretation.
* A mode set through the TSR invalidates the palette, which is what a VGA BIOS
  does when it reloads the DAC — so leaving a game back to the DOS prompt does
  not leave the text screen painted in the game's colours.

Cost: 256 flip-flops plus one 256:1 1-bit mux and an 18-bit 2:1 mux, on top of
a DAC that already costs ~4600 flip-flops.

---

## 5. Staged plan

### Stage 0 — Confirm RC7 before writing RTL (no code, ~10 min)

1. Run Titus the Fox **without** `vgatsr.com` (pure EGA). Expected: the EGA
   title screen appears and **gameplay colours are correct**. That alone
   proves the EGA rendering path is fine and that the regression is entirely
   in the "we told it we are a VGA" path.
2. Repeat with the TSR resident to reproduce the fault.

### Stage 0b — Optional: mode trace in the TSR (~40 lines of asm)

If §5.0 is not conclusive, make the resident hook record `AL` of every
`INT 10h AH=00h` into a 16-byte ring buffer, and make `vgatsr.com`, when run
a second time and finding itself already installed, print that buffer instead
of refusing. A trace of `03 13 0D ...` confirms RC7 outright; a trace of
`03 13 13 ...` refutes it and the investigation moves to what the game does to
the DAC *inside* mode 13h.

### Stage 1 — Put the DAC in the EGA path (the actual fix)

**`rtl/video/vga_dac.v`**

* Rename `reset_palette` → `load_defaults` (same behaviour: load the 256-entry
  VGA table) and add `invalidate`.
* Add `reg [255:0] entry_valid;` maintained as:

```verilog
always @(posedge clock or posedge reset) begin
    if (reset) begin
        // existing default load
        entry_valid <= 256'd0;
    end else if (load_defaults) begin
        // existing default load
        entry_valid <= {256{1'b1}};
    end else if (invalidate) begin
        entry_valid <= 256'd0;
    end else if (write_en) begin
        // existing
        entry_valid[write_index] <= 1'b1;
    end else if (component_write_en) begin
        // existing
        entry_valid[component_write_index] <= 1'b1;
    end
end

assign sample_valid = entry_valid[sample_index];
```

  Note the ordering: `invalidate` must lose to `load_defaults`, because
  entering mode 13h asserts the enter event only.

**`rtl/video/vga_dac_io.v`**

* Pass `invalidate` through, expose `sample_valid`.
* Leave the index/component counters untouched on `invalidate`: a VGA mode set
  does not reset the DAC address pointer.

**`rtl/video/vga_mode13_renderer.v`**

* Nothing to change inside the module. In `ega_top` its `.dac_index` port moves
  from driving `vga_dac_sample_index` directly to driving a new
  `vga_renderer_dac_index` wire, and `vga_dac_sample_index` becomes an
  `assign`.

**`rtl/video/ega_top.v`**

```verilog
wire [7:0] vga_renderer_dac_index;   // was driven straight into the DAC

// One sample port, muxed: the two renderers are mutually exclusive.
assign vga_dac_sample_index = vga_mode13_active ? vga_renderer_dac_index
                                                  : {2'b00, ega_video_selected};

wire ega_dac_hit = vga_enabled & ~vga_mode13_active & vga_dac_sample_valid;

assign ega_red   = vga_mode13_active ? vga_red
                 : ega_dac_hit        ? vga_dac_sample_red   : ega_red_compat;
assign ega_green = vga_mode13_active ? vga_green
                 : ega_dac_hit        ? vga_dac_sample_green : ega_green_compat;
assign ega_blue  = vga_mode13_active ? vga_blue
                 : ega_dac_hit        ? vga_dac_sample_blue  : ega_blue_compat;
```

  and wire `.invalidate (vga_mode13_exit)` on `vga_dac_io_inst`
  (`vga_mode13_exit` already exists and is exactly "the TSR reported a mode
  set that is not 13h").

  `ega_video_selected` is the post-scandoubler 6-bit colour
  ([ega_top.v:617](../rtl/video/ega_top.v#L617)), so the lookup lands after
  line doubling and adds no latency, exactly where `ega_vgaport` sits today.

**Timing note.** This inserts a 256:1 × 18-bit read into the EGA pixel path,
which then crosses into the 57.272 MHz mixer domain in `PCXT.sv`. If the path
becomes critical, the cheapest fix is to register the DAC output for the EGA
path and delay `hsync`/`hblank`/`vsync`/`vblank`/`de_o` by the same single
`clk` cycle — a uniform 35 ns shift of colour and sync together is invisible.
A second option is a dedicated 64-entry read port for the EGA path (the EGA
index never exceeds `3Fh` unless Stage 3's Colour Select support is built),
at the cost of duplicating part of the output mux.

### Stage 2 — TSR: serve the DAC BIOS calls in every mode

**`SW/vga/vgatsr.asm`**, in `.check_palette`, replace the
`cmp byte [cs:current_mode], 13h` gate with an availability check:

```asm
.check_palette:
    cmp ah, 10h
    jne .chain
    ; The DAC subfunctions are VGA-only; the EGA BIOS underneath does not
    ; implement them and drops them silently. Serve them in every mode, not
    ; just 13h, so 16-colour modes on a machine that answers "VGA" to AH=1Ah
    ; can actually load a palette.
    push ax
    call vga_available
    pop ax
    jne .chain
    cmp al, 10h
    je .set_one_dac
    ...
```

`AL=00h..03h` (attribute palette) keep chaining to the EGA BIOS, which is
correct: on a VGA those functions do not touch the DAC either.

Also fix RC6 in the same pass:

```asm
int10_hook:
    cmp ah, 00h
    jne .check_get_mode
    ; Bit 7 of AL is the "do not clear video memory" flag, part of the mode
    ; number on any VGA BIOS; games do use 93h to re-enter mode 13h without a
    ; flash. Masking it keeps that from being read as a different mode.
    push ax
    and al, 7Fh
    cmp al, 13h
    pop ax
    jne .clear_and_chain
```

(`POP` does not disturb the compare flags, the same assumption `vga_available`
already documents.)

Stages 1 + 2 are the whole fix if the games use the identity attribute palette,
which is the usual idiom.

### Stage 3 — Optional refinements, in order of value

Each item is independent; build only what the Stage 4 results ask for.

1. **PEL mask, `3C6h`** (RC4). 8-bit register, resets to `FFh`, decoded next to
   `3C7h-3C9h` and gated on `vga_enabled`; AND it into the DAC index in both
   paths, not into the RGB. ~10 flip-flops, fixes fades and one common VGA
   presence test.
2. **Attribute palette normalisation** (RC3). After chaining a mode set for
   `00h`-`03h`, `0Dh`, `0Eh` and `10h`, have the TSR rewrite ATC registers
   `00h`-`0Fh` with the VGA set `00,01,02,03,04,05,14,07,38..3F`, and pair it
   with a `load_defaults` variant that fills DAC entries `00h-3Fh` with the
   64-colour `rgbRGB` table and marks them valid. Verified against the table
   in RC3, this reproduces the current 16 colours exactly. **Only build this
   if Stage 4 shows colours 8-15 (or brown) still wrong while 0-7 are right**,
   and note the trade-off: from then on the machine interprets attribute codes
   the way a VGA does, so EGA software that writes `10h`-`17h` meaning
   "CGA bright" renders them as `rgbRGB` — which is exactly what would happen
   on a real VGA, but is a change from today.
3. **Colour Select / P54S** (`ATC 10h` bit 7, `ATC 14h`). Build the 8-bit DAC
   index the way 86Box does (RC1). Requires widening `color_out` and
   `video_scandoubler`'s `PIXEL_WIDTH` from 6 to 8 — the line buffers stay
   within the same M10K count (912 × 8 = 7296 bits). Lets 16-colour software
   do palette paging and fast fades.
4. **`INT 10h AH=12h/BL=31h`** (default palette loading enable/disable). When a
   game disables it, mode sets must **not** invalidate the palette. Implement
   by extending the `3CDh` protocol: `02h` = leave mode 13h but keep the DAC
   entries valid; the TSR writes `02h` instead of `00h` while the flag is off.
5. **DAC readback fidelity** (RC5): return the DAC state at `3C7h`, and
   collapse the read/write indices into a single shared counter with the
   `val + (addr & 1)` load rule.
6. **Clear the framebuffer on `AX=0013h`** (RC6, second half): `rep stosw` of
   32000 words at `A000h`, skipped when `AL` bit 7 is set.
7. **Cosmetic**: the EGA path feeds the mixer as `{r, 2'b00}`
   ([PCXT.sv:1401](../PCXT.sv#L1401)) while mode 13h uses `{r, r[5:4]}`
   ([PCXT.sv:1425](../PCXT.sv#L1425)); white is `FCh` on one path and `FFh` on
   the other. Aligning them is one line and makes the DAC path consistent
   across modes.

---

## 6. Verification plan

### 6.1 Non-regression (must pass before anything else)

| Test | Expected |
|------|----------|
| OSD option **off**, boot to DOS, run an EGA game (mode `0Dh`/`10h`) and a CGA-compat game | Pixel-identical to the current build. Guaranteed structurally: no DAC entry can be written, so `ega_dac_hit` is always 0. |
| OSD option **on**, no TSR loaded | Same as above — the ports decode but nothing writes them. |
| OSD option on, TSR loaded, boot splash and text mode | Unchanged. |
| A mode 13h title screen (`TITRE.SQZ`, any 256-colour demo) | Unchanged. |
| Exit a mode 13h game back to the DOS prompt | Text colours normal (this is what the invalidate-on-mode-set rule buys). |

### 6.2 Reading the result on the failing games

Run Titus the Fox and Prehistorik 2 with the TSR after Stages 1 + 2:

| Observation | Conclusion | Next step |
|-------------|------------|-----------|
| Gameplay colours correct | RC7 confirmed, RC1 + RC2 were the whole story | Done; Stage 3 is optional polish |
| Colours 0-7 right, 8-15 stock EGA | The game writes the DAC at VGA indices without normalising the attribute palette | Stage 3 item 2 |
| Only brown/colour 6 wrong | Same, limited to the `06h`/`14h` collision | Stage 3 item 2 |
| Nothing changes at all | The game neither writes the DAC ports nor calls `AX=1012h` in that mode | Re-run Stage 0b; the palette is going somewhere else (attribute controller with `rgbRGB` codes, or Colour Select paging → Stage 3 item 3) |
| Colours change but flicker or reset each level | A mode set is invalidating a palette the game does not reload | Stage 3 item 4 |
| A fade never finishes and the game hangs | A handler is clobbering a caller register the fade uses as a counter | Audit register preservation, as in RC8 |
| A gradient the game never drew appears during a fade | Readback is handing out DAC RAM the picture does not use | RC9 — readback must take the display's fallback |

### 6.3 Regression sweep for Stage 3 item 2, if built

Because it changes how attribute codes are interpreted, re-check a spread of
plain EGA titles (a 200-line 16-colour game, a 640×350 mode `10h` game and a
CGA-compatible one) with the TSR resident, and confirm that not loading the
TSR still gives the untouched EGA behaviour.

---

## 7. Cost summary

| Stage | Files | Rough size | Risk |
|-------|-------|-----------|------|
| 0 / 0b | — / `vgatsr.asm` | 0 / ~40 lines asm | none |
| 1 | `vga_dac.v`, `vga_dac_io.v`, `ega_top.v` | ~40 lines RTL, +256 FF | low — structurally inert when the option is off; watch fMAX |
| 2 | `vgatsr.asm` | ~12 lines asm | low |
| 3.1 PEL mask | `ega_top.v`, `vga_dac_io.v` | ~20 lines | low |
| 3.2 ATC normalisation | `vgatsr.asm`, `vga_dac.v` | ~50 lines | **medium — changes EGA colour interpretation while resident** |
| 3.3 Colour Select | `ega_attrib_ctrl.v`, `ega_top.v`, `video_scandoubler.v` | ~25 lines | low-medium (touches the pixel path width) |
| 3.4-3.7 | various | small | low |

Footnote on area: `vga_dac`'s reset/default loop assigns all 256 entries in a
single cycle, which forces Quartus to infer flip-flops (~4600 of them) rather
than memory. If area ever gets tight, loading the defaults from a small
sequential state machine over 256 cycles would let the palette live in MLAB/M10K
instead — at the price of a synchronous read, which would need the pipeline
compensation described in Stage 1's timing note. Out of scope here.
