# MCGA Mode 13h Regression Log

Date: 2026-07-04

## RTL Regression

Command run from the repository root:

```powershell
$root = 'D:/GitHub/PCXT_MiSTer'
$common = @(
  "$root/rtl/KFPC-XT/TESTBENCH/ega_reference_pkg.sv",
  "$root/rtl/video/UM6845R.v",
  "$root/rtl/video/ega_attrib_ctrl.v",
  "$root/rtl/video/ega_gfx_ctrl.v",
  "$root/rtl/video/ega_pixel.v",
  "$root/rtl/video/ega_sequencer.v",
  "$root/rtl/video/ega_text.v",
  "$root/rtl/video/ega_top.v",
  "$root/rtl/video/ega_vgaport.v",
  "$root/rtl/video/ega_vram.v",
  "$root/rtl/video/vram.v",
  "$root/rtl/video/splash_rom.v",
  "$root/rtl/video/video_scandoubler.v",
  "$root/rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv",
  "$root/rtl/video/mcga_a000_cpu_frontend.v",
  "$root/rtl/video/mcga_dac.v",
  "$root/rtl/video/mcga_dac_io.v",
  "$root/rtl/video/mcga_framebuffer.v",
  "$root/rtl/video/mcga_mode13_address.v",
  "$root/rtl/video/mcga_mode13_ctrl.v",
  "$root/rtl/video/mcga_mode13_renderer.v",
  "$root/rtl/video/mcga_mode13_timing.v"
)
```

For each `rtl/KFPC-XT/TESTBENCH/{ega,mcga}_*_tb.sv`:

```powershell
iverilog -g2012 -I "$root/rtl/video" -I "$root/rtl/KFPC-XT/TESTBENCH" -o $env:TEMP\<test>.vvp @common <test>
Push-Location "$root/rtl/video"
vvp $env:TEMP\<test>.vvp
Pop-Location
```

Results:

| Test | Result |
| --- | --- |
| `ega_crtc_vertical_tb.sv` | PASS |
| `ega_pixel_tb.sv` | PASS |
| `ega_registers_tb.sv` | Icarus compile limitation |
| `ega_text_tb.sv` | PASS |
| `ega_top_splash_tb.sv` | PASS |
| `ega_vgaport_tb.sv` | PASS |
| `ega_vram_b8000_tb.sv` | PASS |
| `ega_vram_frontend_splash_tb.sv` | PASS |
| `ega_vram_splash_tb.sv` | PASS |
| `ega_vram_tb.sv` | PASS |
| `mcga_a000_cpu_frontend_tb.sv` | PASS |
| `mcga_dac_io_tb.sv` | PASS |
| `mcga_dac_tb.sv` | PASS |
| `mcga_ega_switch_tb.sv` | PASS |
| `mcga_framebuffer_tb.sv` | PASS |
| `mcga_mode13_address_tb.sv` | PASS |
| `mcga_mode13_bios_ctrl_tb.sv` | PASS |
| `mcga_mode13_ctrl_tb.sv` | PASS |
| `mcga_mode13_renderer_tb.sv` | PASS |
| `mcga_mode13_timing_tb.sv` | PASS |

`ega_registers_tb.sv` does not elaborate under the local Icarus Verilog build:

```text
rtl/KFPC-XT/TESTBENCH/ega_registers_tb.sv:642: error: automatically allocated variables may not be referenced in procedural force statements.
rtl/KFPC-XT/TESTBENCH/ega_registers_tb.sv:643: error: automatically allocated variables may not be referenced in procedural force statements.
```

This is a testbench/tool limitation, not a new RTL failure from MCGA mode `13h`.

## DOS Artifacts

Command run through WSL NASM:

```powershell
wsl.exe -d Ubuntu-24.04 -- bash -lc "cd /mnt/d/GitHub/PCXT_MiSTer && nasm -O9 -f bin -o SW/mcga/mcgatsr.com SW/mcga/mcgatsr.asm && nasm -O9 -f bin -o SW/mcga/mcgachk.com SW/mcga/mcgachk.asm && nasm -O9 -f bin -o SW/mcga/mcgaramp.com SW/mcga/mcgaramp.asm && nasm -O9 -f bin -o SW/mcga/mcgabar.com SW/mcga/mcgabar.asm"
```

Results:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `mcgatsr.com` | 561 | `7cbdebbab3048b57eef2b45780f0210ec217c1ef2050f2afd529aa0b0bb41ef5` |
| `mcgachk.com` | 318 | `3ca30752db2d1461744dcf5389d3111128ced6b3e0e79626a27f0a5ee8284733` |
| `mcgaramp.com` | 85 | `8ea1ef217308e4324cd5c383a5d0a31121b061abcf4f7eae9b835b9866bd1a4b` |
| `mcgabar.com` | 217 | `348ce167b40f8c696575226d48ed75fbcbe6cef91be48873bb9456cd869eeaf0` |

DOS execution was not run in this environment. The intended in-DOS sequence is:

```bat
MCGATSR.COM
MCGACHK.COM
MCGABAR.COM
MCGARAMP.COM
```
