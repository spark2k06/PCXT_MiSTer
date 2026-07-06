# MCGA Quartus Build Log

Date: 2026-07-06

## Command

Run from PowerShell through WSL Docker:

```powershell
wsl.exe -d Ubuntu-24.04 -- docker run --rm -v /mnt/d/GitHub/PCXT_MiSTer:/build -w /build --entrypoint /bin/bash raetro/quartus:17.0 -lc "/opt/intelFPGA/quartus/bin/quartus_sh --flow compile PCXT"
```

Container image:

```text
raetro/quartus:17.0
```

Quartus version from the report:

```text
17.0.2 Build 602 07/19/2017 SJ Lite Edition
```

## Result

Full compilation completed successfully.

Flow report:

```text
Flow Status: Successful - Mon Jul  6 06:35:09 2026
Analysis & Synthesis: 00:03:07, peak virtual memory 2347 MB
Fitter: 00:16:46, peak virtual memory 4792 MB
Assembler: 00:00:26, peak virtual memory 1826 MB
TimeQuest Timing Analyzer: 00:01:33, peak virtual memory 2903 MB
Total: 00:21:52
```

Generated bitstream:

```text
output_files/PCXT.rbf
Size: 4,216,368 bytes
SHA-256: 5949A4721EC1A4D8FF3973A5EFF9045C1F3E080116F0A04B5EDEA2119D637CB3
```

## Resource Summary

From `output_files/PCXT.fit.summary`:

| Resource | Use |
| --- | ---: |
| Logic utilization | 26,199 / 41,910 ALMs (63%) |
| Total registers | 36,797 |
| Total pins | 145 / 314 (46%) |
| Total block memory bits | 3,913,507 / 5,662,720 (69%) |
| Total RAM blocks | 505 / 553 (91%) |
| Total DSP blocks | 40 / 112 (36%) |
| Total PLLs | 4 / 6 (67%) |

## Timing Notes

The build produces an `.rbf`, but TimeQuest still reports negative setup and
recovery slack in existing clock domains. Worst setup line observed in
`output_files/PCXT.sta.summary`:

```text
Slow 1100mV 100C Model Setup 'VCLK_SDIO'
Slack: -21.326
```

Worst recovery line observed:

```text
Slow 1100mV 100C Model Recovery 'emu|pll_system_inst|pll_system_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk'
Slack: -13.843
```

These timing violations should be treated as timing-closure work. They did not
prevent Quartus from generating `output_files/PCXT.rbf`.
