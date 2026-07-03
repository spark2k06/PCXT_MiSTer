# PCXT MiSTer Test Tooling Guide

This document records the FPGA/test tools currently available from
`C:\intelFPGA_lite\17.0` and the exact workflows that were verified on this
machine. Its purpose is to make later EGA implementation tasks testable with
repeatable commands and minimal setup friction.

Validation environment:

- Date: 2026-06-26.
- Shell: Windows PowerShell.
- Repository root: `D:\GitHub\PCXT_MiSTer`.
- Intel FPGA Lite root: `C:\intelFPGA_lite\17.0`.
- Quartus version observed: `17.0.0 Build 595 04/25/2017 SJ Lite Edition`.

## 1. Required Shell Setup

Use this setup at the start of every PowerShell session before running Quartus
commands from this repository:

```powershell
cd D:\GitHub\PCXT_MiSTer

$env:INTELFPGA_ROOT = 'C:\intelFPGA_lite\17.0'
$env:QUARTUS_ROOTDIR = "$env:INTELFPGA_ROOT\quartus"
$env:QUARTUS_BIN = "$env:QUARTUS_ROOTDIR\bin64"
$env:PATH = "$env:QUARTUS_BIN;$env:PATH"
```

The `PATH` update is required, not just convenient. Calling
`quartus_map.exe` by absolute path while `quartus\bin64` was not in `PATH`
allowed the project to start elaborating, but failed later with:

```text
Error (272000): Can't open DLL "cbx_altsyncram.dll"
```

The DLL exists at `C:\intelFPGA_lite\17.0\quartus\bin64\cbx_altsyncram.dll`.
After prepending `quartus\bin64` to `PATH`, the same Analysis & Elaboration
check completed successfully.

## 2. Installed Tool Inventory

These tools were found and called successfully:

| Tool | Path | Verified command | Result |
| --- | --- | --- | --- |
| Quartus Shell | `quartus\bin64\quartus_sh.exe` | `quartus_sh --version` | 17.0.0 Build 595 Lite |
| Analysis & Synthesis | `quartus\bin64\quartus_map.exe` | `quartus_map --version` | 17.0.0 Build 595 Lite |
| Fitter | `quartus\bin64\quartus_fit.exe` | `quartus_fit --version` | 17.0.0 Build 595 Lite |
| Assembler | `quartus\bin64\quartus_asm.exe` | `quartus_asm --version` | 17.0.0 Build 595 Lite |
| TimeQuest | `quartus\bin64\quartus_sta.exe` | `quartus_sta --version` | 17.0.0 Build 595 Lite |
| Convert Programming File | `quartus\bin64\quartus_cpf.exe` | `quartus_cpf --version` | 17.0.0 Build 595 Lite |
| Quartus Simulator front-end | `quartus\bin64\quartus_sim.exe` | `quartus_sim --version` | 17.0.0 Build 595 Lite |
| Programmer | `quartus\bin64\quartus_pgm.exe` | `quartus_pgm --version` | 17.0.0 Build 595 Lite |
| JTAG config | `quartus\bin64\jtagconfig.exe` | `jtagconfig --version` | 17.0.0 Build 595 Standard |

These tools were not found:

- `vsim.exe`
- `vlog.exe`
- `vlib.exe`
- `iverilog.exe`
- `vvp.exe`
- `verilator.exe`

No ModelSim/Questa/Icarus/Verilator executable is currently available in
`PATH` or under `C:\intelFPGA_lite\17.0`.

## 3. Fast Quartus Integration Check

Use this after RTL changes when you want a quick Quartus syntax/elaboration
check without running the full fitter.

### Step 1: Generate `build_id.v`

`PCXT.sv` includes `build_id.v`. A standalone `quartus_map
--analysis_and_elaboration` does not run the project pre-flow script, so generate
the file explicitly first:

```powershell
quartus_sh -t sys\build_id.tcl compile PCXT PCXT
```

Verified result:

```text
Info: Command: quartus_sh -t sys\build_id.tcl compile PCXT PCXT
Info: Generated: D:/GitHub/PCXT_MiSTer/build_id.v: `define BUILD_DATE "260626"
Info: Quartus Prime Shell was successful. 0 errors, 1 warning
```

This also generates `jtag.cdf`.

### Step 2: Run Analysis & Elaboration

```powershell
quartus_map --read_settings_files=on --write_settings_files=off PCXT -c PCXT --analysis_and_elaboration
```

Verified result after the required `PATH` setup:

```text
Info: Quartus Prime Analysis & Elaboration was successful. 0 errors, 258 warnings
Info: Elapsed time: 00:01:18
```

The generated summary was:

```text
Analysis & Elaboration Status : Successful - Fri Jun 26 08:59:20 2026
Quartus Prime Version : 17.0.0 Build 595 04/25/2017 SJ Lite Edition
Revision Name : PCXT
Top-level Entity Name : sys_top
Family : Cyclone V
```

Important observations:

- The warning `Tcl Script File rtl/pll_system.sip not found` was observed and
  did not block Analysis & Elaboration.
- The EGA files from `rtl/video/video.qip` were read, including
  `ega_gfx_ctrl.v`, `ega_sequencer.v`, `ega_attrib_ctrl.v`, `ega_pixel.v`,
  `ega_vgaport.v`, `ega_vram.v`, and `ega_top.v`.
- Without `build_id.v`, this check fails at `PCXT.sv(252)` with:

```text
Error (10054): Verilog HDL File I/O error at PCXT.sv(252): can't open Verilog Design File "build_id.v"
```

## 4. Full Quartus Build Flow

Use the full flow before treating a change as hardware-ready:

```powershell
quartus_sh --flow compile PCXT -c PCXT
```

Quartus documents this form through:

```powershell
quartus_sh --help=flow
```

Observed supported flows:

- `compile`
- `implement`
- `finalize`
- `recompile`
- `signalprobe`
- `export_database`
- `import_database`

The full `compile` flow should run the pre-flow script from `sys/sys.tcl`:

```tcl
set_global_assignment -name PRE_FLOW_SCRIPT_FILE "quartus_sh:sys/build_id.tcl"
```

Expected major stages:

```powershell
quartus_map PCXT -c PCXT
quartus_fit PCXT -c PCXT
quartus_asm PCXT -c PCXT
quartus_sta PCXT -c PCXT --do_report_timing
```

For regular development, prefer the fast Analysis & Elaboration check first.
Run the full flow when:

- A change crosses module boundaries.
- A change affects clocks, RAM inference, top-level ports, QSF assignments, or
  generated IP.
- A milestone is ready for hardware smoke testing.

## 5. TimeQuest Timing Checks

TimeQuest is available:

```powershell
quartus_sta --version
quartus_sta --help
```

Run timing after a successful fit:

```powershell
quartus_sta PCXT -c PCXT --do_report_timing
```

Useful documented options from `quartus_sta --help`:

- `-c <revision name>` or `--rev=<revision name>`
- `--do_report_timing`
- `--multicorner=on|off`
- `--model=fast|slow`
- `--post_map`
- `--report_script=<value>`
- `--sdc=<value>`

Do not use TimeQuest as a substitute for functional tests. It proves timing
constraints and timing closure, not EGA register or pixel correctness.

## 6. Programming And JTAG Checks

The Programmer and JTAG utilities are installed:

```powershell
quartus_pgm --version
jtagconfig --version
```

Current hardware check:

```powershell
jtagconfig
```

Observed result on this machine:

```text
No JTAG hardware available
```

That means the tool is installed, but no board/cable was visible during
validation.

After a successful full compile, the normal generated programming artifacts are
expected under `output_files/`. The project also generates `jtag.cdf` through
`sys/build_id.tcl`. With hardware attached, use the generated CDF or a direct
programmer command. Example patterns:

```powershell
jtagconfig
quartus_pgm jtag.cdf
```

or, when using a direct SOF operation:

```powershell
quartus_pgm -m jtag -o "p;output_files\PCXT.sof"
```

Validate the exact JTAG cable and device chain with `jtagconfig` before
programming. The direct SOF command may need a cable selector or device-chain
position once actual hardware is connected.

## 7. HDL Simulation Status

The repository contains SystemVerilog testbenches, for example:

- `rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv`
- `rtl/KFPC-XT/TESTBENCH/Chipset_tb.sv`
- `rtl/KFPC-XT/TESTBENCH/Ready_tb.sv`

However, no standalone HDL simulator executable was found in the Intel FPGA
Lite 17.0 tree or in `PATH`. Specifically, `vsim`, `vlog`, `vlib`, `iverilog`,
`vvp`, and `verilator` were not available.

Update for the 2026-07-03 clean-core baseline: `iverilog` and `vvp` are now
available in `PATH` from `C:\iverilog\bin`. Focused EGA testbench execution
status is recorded in `EGA_TESTBENCH_INVENTORY.md` under `ECC-003 Baseline
Execution Snapshot`.

`quartus_sim.exe` exists, but the verified installation does not include the
usual ModelSim/Questa command-line compiler/run tools used for SystemVerilog
testbench workflows. Treat `quartus_sim` as a Quartus simulation front-end, not
as a confirmed replacement for `vlog`/`vsim` for the current testbenches.

### Integrated EGA Smoke Testbench

`rtl/KFPC-XT/TESTBENCH/Chipset_tb.sv` now includes an optional integrated EGA
smoke flow guarded by `EGA_CHIPSET_SMOKE`. The default legacy chipset sequence
is unchanged unless that macro is defined.

The smoke flow:

- Enables the EGA gate at the `CHIPSET` boundary.
- Programs a minimal graphics-mode register set through chipset I/O cycles.
- Writes a planar pattern through A0000h memory cycles.
- Waits for EGA display selection, EGA fetch activity, and non-zero VGA RGB.
- Fails the simulation with `$fatal(1)` if any integrated check fails.

The file was syntax-checked with Quartus Analyze Current File after generating
`build_id.v`:

```powershell
quartus_sh -t sys\build_id.tcl compile PCXT PCXT
quartus_map PCXT --analyze_file=rtl/KFPC-XT/TESTBENCH/Chipset_tb.sv
quartus_map PCXT --verilog_macro="EGA_CHIPSET_SMOKE=1" --analyze_file=rtl/KFPC-XT/TESTBENCH/Chipset_tb.sv
```

Verified result:

```text
Info: Quartus Prime Analyze Current File was successful. 0 errors, 3 warnings
```

Running the smoke still requires a standalone HDL simulator. Once available,
compile `Chipset_tb.sv` with `EGA_CHIPSET_SMOKE` defined in addition to the
project RTL sources.

### Current EGA Testbench Status

`rtl/video/ega_vram.v` has a `cpu_a16` input:

```verilog
input  wire        cpu_a16,
```

`rtl/KFPC-XT/TESTBENCH/ega_vram_tb.sv` now drives that input from 17-bit CPU
transaction helper addresses. Running the testbench still requires a standalone
HDL simulator, which was not found in this Intel FPGA Lite installation.

### Recommended Simulator Workflow Once A Simulator Is Installed

ModelSim/Questa-style flow:

```powershell
vlib work
vlog -sv rtl\video\ega_vram.v rtl\KFPC-XT\TESTBENCH\ega_vram_tb.sv
vsim -c work.ega_vram_tb -do "run -all; quit -f"
```

Icarus-style flow, if installed separately:

```powershell
New-Item -ItemType Directory -Force simulation | Out-Null
iverilog -g2012 -o simulation\ega_vram_tb.vvp rtl\video\ega_vram.v rtl\KFPC-XT\TESTBENCH\ega_vram_tb.sv
vvp simulation\ega_vram_tb.vvp
```

Use simulator exit codes and the testbench final pass/fail message as the
acceptance signal. Do not rely only on waveform inspection for regression
checks.

## 8. Vendor Simulation Libraries

Quartus simulation library sources are present under:

```text
C:\intelFPGA_lite\17.0\quartus\eda\sim_lib
```

Observed files include:

- `altera_mf.v`
- `altera_mf.vhd`
- `altera_lnsim.sv`
- `cyclonev_atoms.v`
- `cyclonev_atoms.vhd`
- `cyclonev_hps_atoms.sv`

These are useful when an external simulator is installed and a testbench needs
Intel primitives or inferred megafunction models. For pure logic unit tests,
prefer keeping testbenches independent from vendor libraries.

## 9. Recommended Test Sequence By Change Type

### Pure EGA Logic Change

1. Run the relevant unit testbench once a simulator is installed.
2. Run the fast Quartus Analysis & Elaboration check:

```powershell
quartus_sh -t sys\build_id.tcl compile PCXT PCXT
quartus_map --read_settings_files=on --write_settings_files=off PCXT -c PCXT --analysis_and_elaboration
```

3. Inspect `output_files\PCXT.map.summary`.

### EGA Register, VRAM, Or PCXT Integration Change

1. Run relevant unit tests where available.
2. Run Analysis & Elaboration.
3. Run full compile if the change affects `PCXT.sv`, `Peripherals.sv`,
   `Chipset.sv`, clocks, RAM inference, or top-level muxing.

### Milestone Or Release-Candidate Check

1. Run all deterministic unit testbenches.
2. Run:

```powershell
quartus_sh --flow compile PCXT -c PCXT
```

3. Run:

```powershell
quartus_sta PCXT -c PCXT --do_report_timing
```

4. Check `output_files\PCXT.flow.rpt`, `output_files\PCXT.map.summary`, fitter
   reports, and TimeQuest reports.
5. If hardware is available, check JTAG with `jtagconfig` and program using
   `jtag.cdf` or the generated `output_files\PCXT.sof`.

## 10. Generated Files And Cleanup

The verified commands can generate ignored files and directories:

- `build_id.v`
- `jtag.cdf`
- `db/`
- `output_files/`
- `incremental_db/` after fuller builds

`clean.bat` removes many generated artifacts, but it ends with `pause`, so it
is inconvenient for automated or agent-driven runs.

PowerShell cleanup pattern from the repository root:

```powershell
if ((Get-Location).Path -ne 'D:\GitHub\PCXT_MiSTer') {
    throw 'Run cleanup only from D:\GitHub\PCXT_MiSTer'
}

Remove-Item -LiteralPath build_id.v,jtag.cdf -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath db,incremental_db,output_files,simulation -Recurse -Force -ErrorAction SilentlyContinue
```

After Quartus runs, always check for accidental project metadata changes:

```powershell
git status --short
git diff -- PCXT.qsf
```

During validation, opening the project through Quartus changed only
`LAST_QUARTUS_VERSION` in `PCXT.qsf`; that generated metadata change was not
needed for testing and should not be committed unless intentionally accepted.

## 11. Troubleshooting

### `build_id.v` Is Missing

Symptom:

```text
can't open Verilog Design File "build_id.v"
```

Fix:

```powershell
quartus_sh -t sys\build_id.tcl compile PCXT PCXT
```

### `cbx_altsyncram.dll` Cannot Be Opened

Symptom:

```text
Error (272000): Can't open DLL "cbx_altsyncram.dll"
```

Fix:

```powershell
$env:PATH = 'C:\intelFPGA_lite\17.0\quartus\bin64;' + $env:PATH
```

Then rerun the Quartus command.

### `vlog`, `vsim`, `iverilog`, Or `verilator` Is Not Found

This is the current validated machine state. Install or add a simulator to
`PATH` before trying to run the SystemVerilog testbenches.

### JTAG Reports No Hardware

Symptom:

```text
No JTAG hardware available
```

Check board power, USB cable, driver installation, and whether the JTAG server
is running. The installed `jtagconfig.exe` is functional, but no hardware was
visible during validation.

### `quartus_sh --tcl_eval` Is Awkward From PowerShell

For project scripts and multi-command flows, prefer:

```powershell
quartus_sh -t path\to\script.tcl arg1 arg2
```

This was the verified path for `sys\build_id.tcl`. Use `--tcl_eval` only for
small one-off commands after confirming quoting in the current shell.

## 12. Practical Bottom Line

Current machine capabilities:

- Quartus command-line tools are installed and functional.
- Fast project Analysis & Elaboration is usable and verified when `PATH` is set
  correctly and `build_id.v` is generated first.
- Full compile/timing/programming commands are available, but full compile was
  not run during this validation pass.
- JTAG tooling is installed, but no hardware was connected.
- No standalone HDL simulator is installed, so EGA unit testbenches cannot yet
  be executed from this Intel FPGA Lite installation alone.

For the EGA backlog, the immediate friction reducers are:

1. Always initialize the PowerShell environment with `quartus\bin64` in `PATH`.
2. Use `quartus_map --analysis_and_elaboration` as the quick Quartus regression
   gate after generating `build_id.v`.
3. Install or expose a real HDL simulator before starting the unit-test-heavy
   EGA tasks in `TASKS.md`.
