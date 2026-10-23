# Profile mister_pcjr: an IBM PCjr. The CGA with the PCjr video
# gate array (16 colour palette, 320x200x16, 640x200x4, 640x200x2 modes, video
# memory shared with the system RAM), the PCjr BIOS in ROM slot 4, the infrared
# keyboard through the NMI, IRQ5 on vertical retrace, the SN76489 of the Tandy
# and the 2F8h/3F8h serial ports of the PCjr.
# Sourced by config.tcl; see scripts/config_check.tcl for the valid combinations.

# Machine: a PCjr. CORE_NAME follows SYSTEM_VARIANT_PCJR ("PCjr"), so the OSD,
# the configuration file and the folder in MiSTer are its own.
set_global_assignment -name VERILOG_MACRO "SYSTEM_VARIANT_PCJR=1"
set_global_assignment -name VERILOG_MACRO "ROM_VARIANT_PCJR=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_PCJR=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_VIDEO=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_AUDIO=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_KBD=0"

# Video: the CGA family only (the PCjr modes live in the CGA); no Hercules, no EGA
set_global_assignment -name VERILOG_MACRO "ENABLE_CGA=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_HGC=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_EGA=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_VGA13=0"

# Memory
set_global_assignment -name VERILOG_MACRO "ENABLE_EMS=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_A000_UMB=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_UMB=0"

# Sound
set_global_assignment -name VERILOG_MACRO "ENABLE_OPL2=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_CMS=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_SB=0"
# No MPU-401 / MT32-pi / USB MIDI: a PCjr has no expansion slots (the reference core
# has none either), and the USER port is left to the serial port.
set_global_assignment -name VERILOG_MACRO "ENABLE_MIDI=0"

# Clock networks: keep the 114.5 MHz SDRAM controller clock on a global line (see
# config.tcl and mister_tandy1000).
set pcxt_global_sdram_clock 1

