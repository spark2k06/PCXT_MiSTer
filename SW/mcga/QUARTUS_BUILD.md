# MCGA Quartus Build Log

Date: 2026-07-04

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
Flow Status: Successful - Sat Jul  4 20:32:50 2026
Analysis & Synthesis: 00:03:35, peak virtual memory 3103 MB
Fitter: 00:15:41, peak virtual memory 4635 MB
Assembler: 00:00:25, peak virtual memory 1826 MB
TimeQuest Timing Analyzer: 00:01:24, peak virtual memory 2908 MB
Total: 00:21:05
```

Generated bitstream:

```text
output_files/PCXT.rbf
Size: 4,212,048 bytes
SHA-256: 930BDD4FBBA647B047E2F984924FEDFAC6816A3434444B4D6FC6CC8925AC7F51
```

## Resource Summary

From `output_files/PCXT.fit.summary`:

| Resource | Use |
| --- | ---: |
| Logic utilization | 26,167 / 41,910 ALMs (62%) |
| Total registers | 36,834 |
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
Slack: -21.248
```

Worst recovery line observed:

```text
Slow 1100mV 100C Model Recovery 'emu|pll_system_inst|pll_system_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk'
Slack: -14.944
```

These timing violations should be treated as timing-closure work. They did not
prevent Quartus from generating `output_files/PCXT.rbf`.
