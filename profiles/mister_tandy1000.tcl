# Profile mister_tandy1000: a Tandy 1000 (CGA plus the Tandy video modes, Tandy
# BIOS, Tandy keyboard and SN76489 sound). Reproduces the Tandy1000 core that
# preceded the unified tree, with its video memory shared with the system RAM
# instead of a copy of it in BRAM.
# Sourced by config.tcl; see scripts/config_check.tcl for the valid combinations.

# Machine: a Tandy 1000. CORE_NAME follows SYSTEM_VARIANT_TANDY ("Tandy1000"),
# so the OSD, the configuration file and the folder in MiSTer are its own.
set_global_assignment -name VERILOG_MACRO "SYSTEM_VARIANT_TANDY=1"
set_global_assignment -name VERILOG_MACRO "ROM_VARIANT_TANDY=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_VIDEO=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_AUDIO=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_KBD=1"

# Video: the CGA family only (the Tandy modes live in the CGA); no Hercules, no EGA
set_global_assignment -name VERILOG_MACRO "ENABLE_CGA=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_HGC=0"
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

# Clock networks: keep the 114.5 MHz SDRAM controller clock on a global line (see
# config.tcl). Left to the fitter it went onto a regional clock that does not
# reach the SDRAM_DQ pins (dq_in_q could not be packed into its I/O cells, setup
# -5.1 ns on the SDRAM read capture) in the first build of this profile.
set pcxt_global_sdram_clock 1

# Fitter seed: the one that closes timing in the four corners with this profile
# (it replaces the default SEED of PCXT.qsf, which config.tcl follows).
set_global_assignment -name SEED 2
