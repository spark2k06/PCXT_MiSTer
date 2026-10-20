# Profile mister_pcxt_ega: PCXT with the EGA card and VGA 13h+, and a Sound
# Blaster Pro. Reproduces the PCXT-EGA core (EGA layout of the OSD).
# Sourced by config.tcl; see scripts/config_check.tcl for the valid combinations.

# Option layout of the OSD: the EGA one (status bit map of PCXT-EGA)
set_global_assignment -name VERILOG_MACRO "LAYOUT_EGA=1"

# Machine: a plain PCXT with Tandy 1000 sound only (an SN76489 at 0C0h..0CFh;
# this profile has no Tandy video or keyboard).
set_global_assignment -name VERILOG_MACRO "SYSTEM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ROM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_VIDEO=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_AUDIO=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_KBD=0"

# Video: the EGA card alone, with the VGA 13h+ extension
set_global_assignment -name VERILOG_MACRO "ENABLE_CGA=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_HGC=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_EGA=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_VGA13=1"

# Memory
set_global_assignment -name VERILOG_MACRO "ENABLE_EMS=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_A000_UMB=0"
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
