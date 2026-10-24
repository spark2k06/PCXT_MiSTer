# Profile mister_pcxt_cga: PCXT with CGA and Hercules/MDA. Reproduces the
# PCXT core that preceded the unified tree (CGA layout of the OSD).
# Sourced by config.tcl; see scripts/config_check.tcl for the valid combinations.

# Machine: a plain PCXT. The Tandy switches stay at 0 (the Tandy 1000 has its
# own profile, mister_tandy1000).
set_global_assignment -name VERILOG_MACRO "SYSTEM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ROM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_VIDEO=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_AUDIO=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_KBD=0"

# Video: CGA and Hercules, no EGA card
set_global_assignment -name VERILOG_MACRO "ENABLE_CGA=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_HGC=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_EGA=0"

# Memory
set_global_assignment -name VERILOG_MACRO "ENABLE_EMS=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_A000_UMB=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_UMB=0"

# Sound
set_global_assignment -name VERILOG_MACRO "ENABLE_OPL2=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_CMS=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_SB=0"
# MPU-401 / MT32-pi and HPS USB MIDI support (set to 0 to omit it from the build).
set_global_assignment -name VERILOG_MACRO "ENABLE_MIDI=1"

