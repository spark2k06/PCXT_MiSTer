# MCGA Gate Mode 13h Baseline

This file records the clean EGA starting point for the gated MCGA mode `13h`
work. It supports task `MCGA-001` from `MCGA_GATE_MODE13_TASKS.md`.

## Baseline Commit

- Commit: `53bc3c2`
- Branch at recording time: `ega-mcga-clean-core`
- Baseline date: 2026-07-03

This commit contains the MCGA mode `13h` specification, plan, and task backlog,
but no RTL or BIOS behavior changes for MCGA mode `13h`.

## Build Artifacts

Latest clean EGA build artifacts are in `output_files/`:

| Artifact | Size | Timestamp |
| --- | ---: | --- |
| `PCXT.rbf` | 3,793,388 bytes | 2026-07-03 17:57:51 |
| `PCXT.sof` | 6,690,344 bytes | 2026-07-03 17:57:49 |
| `PCXT_EGATEST.rbf` | 4,043,396 bytes | 2026-07-03 14:38:10 |
| `PCXT_EGATEST8.rbf` | 4,074,168 bytes | 2026-07-03 13:20:23 |
| `PCXT_EGATEST9.rbf` | 4,043,396 bytes | 2026-07-03 14:38:10 |

The user-created archival copy `core-ega-clean/` is intentionally not part of
this baseline commit.

## Quartus Flow State

Source report: `output_files/PCXT.flow.rpt`

- Flow status: Successful
- Completion time: 2026-07-03 15:57:51
- Quartus Prime: 17.0.2 Build 602 07/19/2017 SJ Lite Edition
- Revision: `PCXT`
- Top-level entity: `sys_top`
- Device family: Cyclone V
- Device: `5CSEBA6U23I7`
- Timing models: Final

## Resource Summary

Source report: `output_files/PCXT.fit.summary`

| Resource | Usage |
| --- | ---: |
| Logic utilization | 21,411 / 41,910 ALMs (51%) |
| Total registers | 32,126 |
| Total pins | 145 / 314 (46%) |
| Block memory bits | 2,864,676 / 5,662,720 (51%) |
| RAM blocks | 375 / 553 (68%) |
| DSP blocks | 40 / 112 (36%) |
| PLLs | 4 / 6 (67%) |

## Timing Summary

Source report: `output_files/PCXT.sta.summary`

The baseline build has known negative setup/recovery slack in generated clock
domains. These are recorded as the pre-MCGA comparison point, not introduced by
the MCGA work.

Worst setup slack by model:

| Model | Clock/domain | Slack | TNS |
| --- | --- | ---: | ---: |
| Slow 1100mV 100C | `VCLK_SDIO` | -21.325 | -124.670 |
| Slow 1100mV -40C | `VCLK_SDIO` | -20.934 | -122.241 |
| Fast 1100mV 100C | `VCLK_SDIO` | -13.503 | -78.876 |
| Fast 1100mV -40C | `VCLK_SDIO` | -12.663 | -74.250 |

Worst recovery slack by model:

| Model | Clock/domain | Slack | TNS |
| --- | --- | ---: | ---: |
| Slow 1100mV 100C | `emu|pll_system_inst|...general[3]...divclk` | -9.915 | -625.759 |
| Slow 1100mV -40C | `emu|pll_system_inst|...general[3]...divclk` | -9.344 | -588.654 |
| Fast 1100mV 100C | `emu|pll_system_inst|...general[3]...divclk` | -5.245 | -330.628 |
| Fast 1100mV -40C | `emu|pll_system_inst|...general[3]...divclk` | -4.317 | -272.014 |

Hold, removal, and minimum pulse width checks have non-negative worst slack in
the summary.

## Clean EGA Behavior To Preserve

`MCGA Gate=Disabled` must preserve the current clean EGA-centered behavior:

- Existing EGA and CGA-compatible EGA modes remain owned by the EGA path.
- No standalone CGA, HGC, Tandy, or `cga_passthrough` path is reintroduced.
- The IBM EGA option ROM remains the current video BIOS baseline before MCGA
  integration work.
- Existing `output_files/PCXT.rbf` and `output_files/PCXT.sof` are the
  comparison artifacts for later MCGA resource and timing deltas.
