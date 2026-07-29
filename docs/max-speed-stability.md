# Specification: stabilising the "PC/AT 3.5MHz" (maximum) CPU speed setting

Status: **Phases 3, 4 (minimal), 5 implemented and confirmed stable on
hardware** — see §7. Phase 1 (boot guard) was implemented, tested, and then
**removed**: hardware testing showed the system boots reliably at the fastest
CPU speed with no Boot Speed option at all once Phases 3-5 were in place, so
the POST beeps were a symptom of RC2/RC3, not something that needed a
separate boot-time workaround. Phase 2 (decoupling the 8237 DMA controller
from the CPU clock) is deferred; it needs a cross-clock-enable redesign of
the HOLD/HLDA handshake in `Bus_Arbiter.sv` that is too invasive to land
without further hardware/simulation validation, though hardware testing did
not surface any disk errors that would require it.
Scope: `clk_select == 2'b11` (OSD *CPU Speed → PC/AT 3.5MHz*)
Branch at time of writing: `ega-test` (`1d465f6`)

---

## 1. Problem statement

The maximum CPU speed setting is useful — demanding games run noticeably
smoother — but it is not reliable. Reported symptoms:

1. Occasional disk read/write errors (floppy and IDE/XTIDE).
2. The BIOS emits POST error beeps when the machine *boots* with this speed
   already selected. Selecting the same speed *after* boot works fine.
3. Intermittent graphical glitches in some game scenes.

This document records what the RTL actually does at this setting, identifies
the mechanisms that make it fragile, and proposes a staged set of fixes.

Findings are labelled **[verified]** when they follow directly from the RTL,
and **[hypothesis]** when they are a plausible mechanism that still needs
hardware measurement to confirm.

---

## 2. What the setting actually does

### 2.1 Clock generation

`XT_CE_Generator` ([rtl/KFPC-XT/HDL/XT_CE_Generator.sv](../rtl/KFPC-XT/HDL/XT_CE_Generator.sv))
synthesises the virtual 8088 `CLK` pin from the single 50 MHz chipset clock
with a fractional accumulator (`cpu_edge_num / cpu_edge_den`).

| `clk_select` | OSD label       | num/den | Virtual 8088 CLK | Bus cycle (4 CLK) | Chipset clocks per CLK period |
|--------------|-----------------|---------|------------------|-------------------|-------------------------------|
| `2'b00`      | 4.77 MHz        | 21/110  | 4.7727 MHz       | 838 ns            | 10.48                         |
| `2'b01`      | 7.16 MHz        | 63/220  | 7.1591 MHz       | 559 ns            | 6.98                          |
| `2'b10`      | 9.54 MHz        | 21/55   | 9.5455 MHz       | 419 ns            | 5.24                          |
| `2'b11`      | PC/AT 3.5MHz    | 1/1     | **25.000 MHz**   | **160 ns**        | **2.00**                      |

**[verified]** With `cpu_edge_num = cpu_edge_den = 1` the accumulator fires on
*every* 50 MHz edge, so `cpu_clk_pin` toggles at 25 MHz and `cpu_ce_posedge` /
`cpu_ce_negedge` alternate on consecutive chipset clocks.

This is the architectural cliff: **in mode `2'b11` there are exactly two
chipset clocks per virtual CPU clock period, one per phase.** Every clock-enable
based handshake in the chipset, which at 4.77 MHz had ~10 chipset clocks of
slack per CPU clock, now has exactly one. Nothing in the chipset was designed
with that budget.

Note also that the OSD label is a *performance-equivalence* label, not the pin
rate — the virtual 8088 runs at 25 MHz, 5.24× the 4.77 MHz setting. This should
be clarified in the README to avoid confusion when debugging.

### 2.2 What else changes in mode `2'b11`

```systemverilog
2'b11:
begin
    cpu_edge_num = 9'd1;
    cpu_edge_den = 9'd1;
    cycle_accrate = 1'b0;                       // instruction cycle model OFF
    clock_cycle_counter_decrement_value = 8'd5;
    shift_read_timing = 1'b1;                   // sample read data on CLK falling edge
    ram_read_wait_cycle = 2'd1;                 // +1 wait tick on RAM reads
    // ram_write_wait_cycle stays 2'd0          // no wait on RAM writes
end
```

`cycle_accrate = 0` forces `BIU_CLK_COUNTER_ZERO` to `1` in
[rtl/8088/i8088.v:117](../rtl/8088/i8088.v#L117), i.e. the MCL86 microcode
never waits for its per-instruction cycle counter. Instruction timing is
therefore unbounded and bears no fixed relation to any other timebase.

### 2.3 What does *not* change

**[verified]** `peripheral_ce` is fixed at 21/440 × 50 MHz = **2.3864 MHz**
regardless of `clk_select`, and `timer_clock` (8253 input) is
`peripheral_ce / 2` = **1.1932 MHz**. The PIT, PS/2 keyboard and the SPI/SD
clock divider are correctly speed-independent.

---

## 3. Root-cause analysis

### RC1 — The 8237 DMA controller is clocked by the CPU clock enables **[verified, high confidence]**

[rtl/KFPC-XT/HDL/Bus_Arbiter.sv:177](../rtl/KFPC-XT/HDL/Bus_Arbiter.sv#L177):

```systemverilog
KF8237 u_KF8237 (
    .clock          (clock),
    .cpu_ce_posedge (cpu_ce_posedge),   // <-- CPU speed, not peripheral_ce
    .cpu_ce_negedge (cpu_ce_negedge),
    ...
```

All three KF8237 sub-blocks take `cpu_clock_posedge` / `cpu_clock_negedge`
from the same source. In mode `2'b11` the DMA controller therefore runs at
**25 MHz instead of 4.77 MHz** — DMA bus cycles get 5.24× shorter.

Consequences:

* Floppy DMA transfers (`fdd_dma_req` / `fdd_dma_ack` / `fdd_dma_rw_ack`
  in [Peripherals.sv:1400-1490](../rtl/KFPC-XT/HDL/Peripherals.sv#L1400)) run at
  a rate the ao486-derived `floppy` model was never exercised at. The
  DRQ→DACK→data window shrinks by the same factor.
* During a DMA memory write, `MEMW` is asserted for ~2 DMA clocks ≈ **80 ns**
  ≈ 4 chipset clocks. See RC2 for why that is not enough.
* `dma_ready` in [Ready.sv:82](../rtl/KFPC-XT/HDL/Ready.sv#L82) is derived from
  `prev_ready_n_or_wait`, which is itself sampled on `cpu_ce_posedge` — so the
  DMA's wait-state path speeds up in lockstep and provides no extra margin.

On real hardware the DMA controller does *not* scale with the CPU. This is the
single most likely cause of symptom 1 (disk errors).

### RC2 — RAM writes have no closed-loop completion handshake **[verified mechanism, hypothesis on frequency]**

Four independent facts combine badly:

1. `bus_state` in [Ready.sv:33](../rtl/KFPC-XT/HDL/Ready.sv#L33) is
   `~io_read_n | ~io_write_n | (dma0_acknowledge_n & ~memory_read_n & address_enable_n)`.
   **`memory_write_n` is not in it** — a memory write never triggers the
   "assert wait at cycle start" branch.
2. `ram_write_wait_cycle = 0` even in mode `2'b11`, so
   [RAM.sv:366](../rtl/KFPC-XT/HDL/RAM.sv#L366) `memory_access_ready` degenerates
   to `access_ready`.
3. `access_ready` ([RAM.sv:329-341](../rtl/KFPC-XT/HDL/RAM.sv#L329)) is only
   deasserted when `refresh_mode` is *already* active. It does **not** go low
   when a new access starts; in `IDLE` it is loaded with the SDRAM's `idle`
   flag, i.e. `1`, and then holds `1` for the whole access. RAM readiness is
   open-loop and tuned by the fixed `ram_*_wait_cycle` constants.
4. `RAM_WRITE_1` aborts the transaction if the strobe disappears first:
   ```systemverilog
   RAM_WRITE_1: begin
       if (~write_command) next_state = WAIT;   // write silently dropped
       if (write_flag)     next_state = RAM_WRITE_2;
   end
   ```
   and `latch_data <= internal_data_bus` ([RAM.sv:110](../rtl/KFPC-XT/HDL/RAM.sv#L110))
   tracks the live bus every clock rather than latching once at cycle start.

Timing budget in mode `2'b11`:

* `MEMW` asserted ≈ 2 CPU clocks = **80 ns = 4 chipset clocks**.
* An SDRAM auto-refresh (`REFRESH_PALL` + `REFRESH`, `trp` + `trc`) occupies
  ≈ **6 chipset clocks**, and `sdram_force_refresh = 400` guarantees one every
  8 µs even when the bus never goes idle.
* The wait request path is `refresh_mode` → `access_ready` (1 clk) →
  `io_channel_ready` → `ready_n_or_wait` (1 clk) → `prev_ready_n_or_wait`
  (`cpu_ce_posedge`) → `processor_ready_ff_1` (`cpu_ce_posedge`) →
  `processor_ready_ff_2` (`cpu_ce_negedge`) ≈ **5 chipset clocks**.

So a write that collides with a refresh is told to wait *after* its `MEMW`
window has already closed → the write is dropped, or `latch_data` has already
moved on and the wrong byte is committed. At 4.77 MHz the same collision is
absorbed because `MEMW` is ~420 ns wide.

This mechanism explains all three symptoms at once: corrupted disk buffers,
POST memory-test failures, and one-off graphical artefacts.

### RC3 — I/O devices cannot request wait states at all **[verified]**

[PCXT.sv:988](../PCXT.sv#L988):

```systemverilog
.io_channel_ready (1'b1),
```

There is no IOCHRDY. Every I/O device — FDC, XT2IDE, KFMMC, UART, OPL2, RTC,
EMS — must answer inside the fixed bus cycle. Their response pipelines are
fixed-length in 50 MHz clocks (e.g. the FDC read path is
`IOR → fdd_io_read → fdd_io_read_1 → fdd_readdata → data_bus_out` ≈ 4–5 chipset
clocks; the IDE path adds `ide0_io_read_1`/`prev_ide0_io_read`/`ide0_address_1`),
while the window shrinks from ~600 ns at 4.77 MHz to ~120–160 ns here.

The margin is currently positive but thin, and it is *unconstrained* — nothing
in the design or the SDC prevents a future pipeline stage from pushing it
negative. Tight `rep insw` loops from XTIDE are the worst case.

### RC4 — Instruction timing fidelity is switched off **[verified]**

`cycle_accrate = 0` bypasses the microcode cycle counter entirely. Software
that meters time by instruction count rather than by the PIT — mid-scanline
register writes, PC-speaker routines, floppy/copy-protection timing loops —
has no defined behaviour at this setting. This is the most likely explanation
for symptom 3 in *specific scenes* (as opposed to random artefacts).

### RC5 — EGA/MCGA VRAM mixed-port read-during-write is undefined **[verified]**

[rtl/video/ega_vram.v](../rtl/video/ega_vram.v) instantiates four M10K
`altsyncram` blocks with `clock0 = clk` (chipset) and `clock1 = clk_vram`, and:

```
read_during_write_mode_mixed_ports = "DONT_CARE"
```

On Cyclone V, a port-B read of an address port A is writing in the same cycle
returns **undefined** data. The CPU write rate into VRAM rises ~5.24× in mode
`2'b11`, so same-address collisions with the CRT fetch become ~5× more likely.
The CPU side itself is properly handshaked (`cpu_ready` from `CPU_DONE` in
[ega_vram_bram_frontend.sv:101](../rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv#L101)),
so this is a display-side artefact, not a data-corruption one — consistent
with "intermittent glitches in some scenes".

### RC6 — POST always runs at maximum speed **[verified]** — explains symptom 2

[PCXT.sv:476-485](../PCXT.sv#L476):

```systemverilog
wire [1:0] clk_select_next = ((xtctl[3:2] == 2'b00) && ~xtctl[7]) ? status[18:17] : ...;

always @(posedge clk_chipset, posedge reset)
    if (reset)          clk_select <= 2'b00;
    else if (biu_done)  clk_select <= clk_select_next;
```

`clk_select` resets to `2'b00`, but it is reloaded from the OSD setting at the
*very first* `biu_done` — i.e. after the first bus cycle. The entire BIOS POST
therefore executes at 25 MHz, exercising precisely the marginal paths above
(memory test, DMA test, FDC/IDE probe). This matches the report exactly:
beeps at boot, but no problem when the same speed is selected once DOS is up.

### RC7 — The current build does not close timing **[verified]** — unrelated but relevant

`output_files/PCXT.sta.summary` for the last build:

```
Type  : Slow 1100mV 100C Model Setup 'emu|pll|pll_inst|...|counter[0]|divclk'   (clk_100)
Slack : -1.564
TNS   : -150.066
```

`clk_100` is the `ascal` video scaler `CORE_CLK` ([PCXT.sv:1096](../PCXT.sv#L1096)).
`clk_chipset` (`counter[1]`) does close, at +1.423 ns, so the CPU/chipset domain
is fine — but ~150 ns of total negative slack in the scaler domain is an
independent source of intermittent video artefacts. It must be fixed before any
remaining glitch can honestly be attributed to CPU speed.

---

## 4. Proposed solution

Staged, cheapest and highest-confidence first. Each stage is independently
shippable and independently testable.

### Phase 0 — Instrumentation (do this first)

**Status: not implemented.** Left as a recommendation for whoever runs the
hardware validation in §5 — none of it was needed to make the RTL changes in
Phases 1/3/4/5 below, but it is the right tool to *prove* they worked.


Without measurement, everything below is guesswork.

* Add a small debug block, gated behind a `` `define ``, exposing saturating
  counters on a scratch I/O port (or via the existing `mgmt` interface):
  * RAM writes aborted in `RAM_WRITE_1` (`~write_command` before `write_flag`),
  * accesses that started while `refresh_mode` was asserted,
  * `cpu_ce_posedge` events during `address_enable_n == 0` (DMA overlap),
  * EGA VRAM mixed-port address collisions.
* Add a stress image under `SW/`: a memory pattern walk (write/verify a
  known pattern over conventional RAM) plus a disk read-verify loop, run at
  each of the four speeds, reporting error counts.

Acceptance for every later phase: the same stress run at `2'b11` reports zero
errors over ≥ 10 minutes, and the counters stay at zero.

### Phase 1 — Boot at a safe speed (fixes symptom 2, ~20 lines)

**Status: implemented, hardware-tested, then reverted.** A `Boot Speed:
Safe (4.77MHz) / Selected` OSD option was added, holding `clk_select` at
`2'b00` for ~1s after reset before handing off to the OSD-selected speed.

Hardware testing (see §7) showed the POST beeps stopped after Phases 3-5
went in, **in both *Safe* and *Selected* modes** — i.e. once RAM writes stop
being silently dropped (RC2) and I/O gets its wait-state floor back (RC3),
POST is no longer marginal at the fastest speed and the workaround has
nothing left to guard against. It was removed rather than kept as
belt-and-braces, to avoid carrying a permanent ~1s boot delay and an extra
OSD option for a symptom that no longer reproduces. If POST instability ever
resurfaces on different hardware, this is the fix to bring back — the
approach below is unchanged, only its necessity was disproved.

```systemverilog
// PCXT.sv (removed)
logic [26:0] boot_guard_count;
logic        boot_guard;              // 1 while POST is assumed to be running

always @(posedge clk_chipset, posedge reset) begin
    if (reset) begin
        boot_guard_count <= '0;
        boot_guard       <= 1'b1;
    end
    else if (boot_guard) begin
        if (boot_guard_count == BOOT_GUARD_TICKS) boot_guard <= 1'b0;
        else boot_guard_count <= boot_guard_count + 1'b1;
    end
end

wire [1:0] clk_select_req = /* existing clk_select_next expression */;
wire [1:0] clk_select_next = boot_guard ? 2'b00 : clk_select_req;
```

### Phase 2 — Decouple the DMA controller from the CPU clock (fixes symptom 1)

Give `KF8237` its own clock enable that does **not** follow `clk_select`.

* Add `dma_ce_posedge` / `dma_ce_negedge` outputs to `XT_CE_Generator`, derived
  from a fixed 4.77 MHz accumulator (`21/110`), independent of `active_clk_select`.
* Route them to `KF8237` in `Bus_Arbiter.sv` in place of `cpu_ce_*`.
* The HOLD/HLDA handshake (`hold_request_ff_1/2`, `address_enable_n`,
  `dma_wait`) crosses between the two rates. Both are enables on the same
  50 MHz clock, so no CDC is needed, but the sequencing must be re-derived:
  `hold_request_ff_1` should be sampled on the *CPU* enable (the CPU releases
  the bus) and `hold_request_ff_2` / `address_enable_n` on the *DMA* enable
  (the DMA takes it).
* `dma_ready` in `Ready.sv` must be re-timed to `dma_ce_posedge` as well,
  otherwise the DMA samples readiness at CPU rate.

This restores authentic DMA behaviour — on real hardware DMA throughput does
not scale with CPU speed — and removes the 5× compression of the FDC transfer
window.

### Phase 3 — Make RAM access a real handshake (fixes the corruption mechanism)

**Status: implemented**, slightly simplified from the original proposal below
based on what the RTL actually needed:

* `Ready.sv`: added the `memory_write_n` term to `bus_state`, as proposed.
* `RAM.sv`: `latch_data` now updates only while `state == IDLE` (freezes the
  instant the access leaves IDLE) rather than needing a separate
  `prev_write_command` edge detector — same effect, one register fewer.
* `RAM.sv`: `access_ready` now follows the state machine directly (`0` outside
  `IDLE`/`COMPLETE_RAM_RW`, `idle & ~(write_command | read_command)` in
  `IDLE`, `1` at `COMPLETE_RAM_RW`) instead of the proposed `refresh_mode`
  branches.
* The `RAM_WRITE_1`/`RAM_WRITE_2` "abandon on `~write_command`" transitions
  were **left in place** rather than latched away: once `access_ready` tracks
  real completion, `memory_write_n` is held by the READY/wait-state path for
  the whole access under normal operation, so that abort path should no
  longer trigger — removing it outright would have deleted a defensive edge
  case without a way to confirm the replacement is airtight under every
  possible external-bus/HOLD interaction. Revisit if instrumentation (Phase 0)
  still shows aborted writes after this fix.

In [Ready.sv](../rtl/KFPC-XT/HDL/Ready.sv):

* Include `memory_write_n` in `bus_state` so memory writes get the same
  "wait at cycle start, release when ready" treatment as I/O and memory reads.

In [RAM.sv](../rtl/KFPC-XT/HDL/RAM.sv):

* Latch write data **once**, at the start of the access, instead of every clock:
  ```systemverilog
  always_ff @(posedge clock, posedge reset)
      if (reset)                              latch_data <= '0;
      else if (write_command & ~prev_write_command) latch_data <= internal_data_bus;
  ```
* Deassert `access_ready` as soon as a command is decoded and reassert it only
  at `COMPLETE_RAM_RW`, so readiness reflects the SDRAM actually finishing
  rather than a fixed constant:
  ```systemverilog
  else if (state == IDLE)
      access_ready <= idle & ~(write_command | read_command);
  ```
* Never abandon a write that has already been requested: hold `write_command`
  in a latch that clears on `write_flag`, so `RAM_WRITE_1` cannot fall through
  to `WAIT` when `MEMW` deasserts early.
* Keep `ram_read_wait_cycle` / `ram_write_wait_cycle` as a *minimum* floor, not
  as the completion criterion.

Because the wait path costs ~5 chipset clocks to reach the CPU, the READY logic
must assert "not ready" *by default* at the start of every RAM cycle and clear
it on completion — the current "ready unless proven otherwise" polarity cannot
be made safe at two chipset clocks per CPU clock.

**Also fixed** in `KFSDRAM.sv:110-111`: the refresh condition
`(~sdram_no_refresh) && (A && B) || C` had `&&`/`||` precedence such that the
forced-refresh term `C` bypassed `sdram_no_refresh`. Added the missing
parentheses. `sdram_no_refresh` defaults to (and is always instantiated as)
`1'b0` in this project, so this was dormant and the fix is a no-op today —
it only matters if something ever instantiates `KFSDRAM` with
`sdram_no_refresh = 1`.

### Phase 4 — Give I/O a wait mechanism (removes the RC3 cliff)

**Status: minimal version implemented.** Added an `io_settle_ready` block
inside `Chipset.sv` (ahead of the `READY` instantiation) that watches
`io_read_n`/`io_write_n`, and on the rising edge of a new I/O cycle holds
`io_channel_ready` low for `io_settle_ticks(clk_select)` extra chipset clocks
— `4` at `clk_select == 2'b11`, `0` otherwise (existing margin is already
generous at the other three speeds). This can only make I/O cycles longer,
never shorter, so it cannot regress anything that worked before; it recreates
the "one wait state on 8-bit I/O" behaviour real XT/AT hardware has and gives
the fixed-length FDC/IDE/KFMMC pipelines a bit of headroom back.

The **proper** per-device version (deriving a real `ready` from each
peripheral's own pipeline depth) is deferred — it touches every I/O device in
`Peripherals.sv` and needs the Phase 0 instrumentation to confirm it's
actually necessary once the minimal version is in.

### Phase 5 — Video

**Status: implemented** exactly as proposed.

* Set `read_during_write_mode_mixed_ports = "OLD_DATA"` on the four
  `altsyncram` blocks in `ega_vram.v`, so a collision yields the previous
  contents (a one-cycle-stale pixel) instead of undefined data. If the
  synthesised result is not acceptable, delay the CRT fetch address by one
  clock and bypass the CPU write data on address match.
* **Not done:** the `clk_100` / `ascal` setup failures reported in
  `output_files/PCXT.sta.summary` (−1.564 ns worst, −150 ns TNS). This needs a
  Quartus re-fit/STA pass, which wasn't available in this environment. It
  should be checked after a real build with the changes above, before
  attributing any residual glitch to the CPU speed setting.

### Phase 6 — Optional: an accurate maximum mode

**Status: not implemented**, left as a follow-up if Phase 4's minimal I/O
guard and Phase 3's RAM handshake are not enough for scenes that rely on
instruction-count timing.

Offer *Max speed: Fast / Accurate* in the OSD. "Accurate" would keep
`cycle_accrate = 1` with a scaled `clock_cycle_counter_decrement_value`
(≈ `8'd5` with `division_ratio = 0` gives roughly 5× the 4.77 MHz instruction
rate, matching what the bus is doing). Slower than the current setting, but it
restores a defined relationship between instruction timing and every other
timebase, which is what timing-sensitive scenes need.

---

## 5. Verification plan

| Test | Runs at | Pass criterion |
|------|---------|----------------|
| Cold boot × 20 with max speed pre-selected | `2'b11` | No POST beeps, boots to DOS every time |
| RAM pattern walk (Phase 0 tool), 10 min | all four | Zero mismatches; zero aborted-write counter |
| Floppy: format + full write/read/verify of a 1.44 MB image | all four | Zero errors |
| IDE/XTIDE: `rep insw`-heavy read of ≥ 100 MB with checksum | all four | Zero mismatches |
| Regression: existing game set, visual comparison against `2'b10` | `2'b11` | No new artefacts |
| Quartus STA | — | All clock domains ≥ 0 slack |

Compare every result against `2'b10` (9.54 MHz) as the control — if a failure
also occurs there, it is not a max-speed problem.

---

## 6. Summary

The maximum speed setting takes the virtual 8088 to 25 MHz, which leaves
**exactly two chipset clocks per CPU clock period**. Three parts of the design
assume much more than that:

* the 8237 DMA controller, which is clocked from the CPU enables and therefore
  runs 5.24× too fast (RC1 → disk errors),
* the RAM path, whose readiness is open-loop and whose write transaction can be
  silently dropped when an SDRAM refresh collides with the ~80 ns `MEMW` window
  (RC2 → corruption, POST failures, artefacts),
* the I/O path, which has no wait-state mechanism at all (RC3).

POST running at full speed (RC6) is why the beeps appeared only at boot; it
turned out to be a symptom of RC2/RC3 rather than a separate problem needing
its own fix (see Phase 1). The disabled instruction-cycle model (RC4) and the
undefined VRAM mixed-port read-during-write (RC5) account for the
scene-specific graphical glitches.

---

## 7. Implementation record

| Phase | Status | Files touched |
|-------|--------|----------------|
| 0 — Instrumentation | Not implemented | — |
| 1 — Boot guard | Implemented, hardware-tested, **then removed** — no longer reproducible once Phases 3-5 were in (see Phase 1 notes) | — |
| 2 — Decouple DMA clock | **Deferred** — needs a validated cross-rate HOLD/HLDA redesign in `Bus_Arbiter.sv`; hardware testing found no disk errors that would require it | — |
| 3 — RAM handshake | **Implemented, confirmed stable on hardware** | `Ready.sv`, `RAM.sv`, `Chipset.sv` (new port), `KFSDRAM.sv` (unrelated precedence fix) |
| 4 — I/O wait mechanism | **Implemented (minimal version only), confirmed stable on hardware** | `Chipset.sv` |
| 5 — Video RDW | **Implemented, confirmed stable on hardware** | `ega_vram.v` |
| 6 — Accurate max mode | Not implemented | — |

Verification performed before hardware testing (no Quartus access in the
development environment):

* Standalone syntax check of every changed file with `iverilog -g2012 -tnull`.
* Full elaboration of the `Chipset.sv` → `RAM.sv` / `READY` / `PERIPHERALS` /
  `ega_vram_bram_frontend.sv` → `ega_vram.v` / `KF8237.sv` / `KF8288.sv`
  instance tree: all of the modules touched by this work elaborate cleanly
  (the only remaining "unknown module" errors are for unrelated peripherals —
  `saa1099`, `jtopl2`, `uart_16750`, `dpram`, `rtc`, `LDST_SEQUENCER` — that
  were intentionally left out of the file list and are untouched by this
  change).
* `PCXT.sv` parses standalone with no syntax errors (elaboration against the
  real top level needs the MiSTer framework + Cyclone V primitives, which
  aren't available in that environment).

Hardware testing results (real Quartus build, real MiSTer):

* Cold boot at PC/AT 3.5MHz: no POST beeps, boots reliably. Confirmed the
  Phase 1 workaround was no longer needed and it was removed.
* Memory, floppy, IDE/XTIDE, and video all reported stable at PC/AT 3.5MHz.
* An intermittent RAM POST failure ("Faulty memory detected at N KiB") was
  observed **twice** across testing — once at 384 KiB, once at 368 KiB, both
  self-recovering (the machine continues POST and boots to DOS normally with
  the reduced conventional memory figure). Not reliably reproducible: dozens
  of subsequent cold boots did not reproduce it again.
  * The two addresses are 16 KiB apart, i.e. close together but not fixed —
    more consistent with a timing-dependent trigger (something that happens
    once, at a roughly fixed point in time after reset, and corrupts
    whatever byte the sequential memory test happens to be checking at that
    moment) than with a fixed hardware address.
  * The reset chain for the SDRAM controller (`reset_sdram`/`KFSDRAM`) was
    reviewed and has ample margin: `reset_sdram` is released no later than
    the CPU/chipset `reset` (its trigger condition, `RESET | !pll_locked`, is
    a subset of the CPU reset's conditions), and the SDRAM's own internal
    `INIT→PALL→CBR1→CBR2→MRS` sequence needs only ~10,010 `clk_chipset`
    cycles (~200µs), well inside the CPU's own 65,535-cycle (~1.3ms) reset
    holdoff. `RAM.sv`'s clock and the physical `SDRAM_CLK` pin are the same
    net (`SDRAM_CLK = clk_chipset`, `PCXT.sv:196`), so there is no
    clock-domain crossing between the controller and the rest of the
    chipset either. No race was found in this path.
  * An attempt to get a clean baseline by flashing a pre-fix release did not
    isolate the bug: that release fails at PC/AT 3.5MHz in a completely
    different and far more severe way (POST beeps every time, never reaches
    the RAM test screen, falls back to 40-column video), so it is not a
    usable control for this specific, much smaller residual glitch.
  * Leading hypothesis, unconfirmed: a real SDRAM signal-integrity/timing
    margin issue rather than an RTL logic bug — `KFSDRAM.sv`'s
    `sdram_trp = 16'd1-16'd1 = 0` (zero extra precharge-to-active cycles) is
    an aggressive setting that could be marginal on real silicon under
    power-up temperature/voltage variation. This would be independent of
    CPU speed and of the changes in this document.
  * **Left open** rather than chased further blind. Proper isolation needs
    the Phase 0 instrumentation (a saturating counter on aborted/mismatched
    RAM accesses, readable after the fact) so a recurrence can be tied to a
    specific mechanism instead of a screen photo.

Still open:

* Phase 0 instrumentation, specifically to chase the intermittent RAM POST
  failure above if it recurs with any regularity.
* A real Quartus STA pass specifically checking whether `clk_100`/`ascal`
  slack (§3, RC7) moved as a result of these changes.
* If disk errors ever do surface under different hardware or workloads, that
  would point at RC1 (DMA rate) and make Phase 2 the next thing to do —
  properly, with the Phase 0 instrumentation in place first.
