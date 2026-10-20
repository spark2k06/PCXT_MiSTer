# Profile mister_pcxt_full: one PCXT core with both video families, CGA+Hercules
# and EGA+VGA 13h+. The card is chosen in the OSD and applied at the next reset.
# Sourced by config.tcl; see scripts/config_check.tcl for the valid combinations.
#
# The trimmed variant mister_pcxt_full_novga13 sets this before sourcing this
# file; a VERILOG_MACRO cannot be redefined once it has been assigned, so the
# variant has to pick the value up front.
if {![info exists pcxt_enable_vga13]} { set pcxt_enable_vga13 1 }

# Option layout of the OSD: the EGA one (it carries the card selector)
set_global_assignment -name VERILOG_MACRO "LAYOUT_EGA=1"

# Machine: a plain PCXT with Tandy 1000 sound only
set_global_assignment -name VERILOG_MACRO "SYSTEM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ROM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_VIDEO=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_AUDIO=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_KBD=0"

# Video: both families, the EGA with the VGA 13h+ extension (unless trimmed)
set_global_assignment -name VERILOG_MACRO "ENABLE_CGA=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_HGC=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_EGA=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_VGA13=$pcxt_enable_vga13"

# Memory
set_global_assignment -name VERILOG_MACRO "ENABLE_EMS=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_A000_UMB=1"
# UMB C400-CFFF belongs to the EGA BIOS slot
set_global_assignment -name VERILOG_MACRO "ENABLE_UMB=1"

# Sound. The Sound Blaster Pro at 220h is exclusive with C/MS at run time (see
# xtegactl.sv): the two collide on 226h/227h.
set_global_assignment -name VERILOG_MACRO "ENABLE_OPL2=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_CMS=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_SB=1"
# MPU-401 / MT32-pi and HPS USB MIDI support (set to 0 to omit it from the build).
set_global_assignment -name VERILOG_MACRO "ENABLE_MIDI=1"

# The EGA card's clocks leave the PLL with too many nets for the global lines
# (see config.tcl): ask for the SDRAM controller clock on one.
set pcxt_global_sdram_clock 1
