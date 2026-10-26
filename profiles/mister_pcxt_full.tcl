# Profile mister_pcxt_full: one PCXT core with both video families, CGA+Hercules
# and EGA. The card is chosen in the OSD and applied at the next reset.
# Sourced by config.tcl; see scripts/config_check.tcl for the valid combinations.

# Option layout of the OSD: the EGA one (it carries the card selector)
set_global_assignment -name VERILOG_MACRO "LAYOUT_EGA=1"

# Machine: a PCXT or a Tandy 1000, chosen in the OSD and applied at reset.
# The Tandy 1000 has the CGA with its Tandy video modes (shared RAM),
# the Tandy keyboard and sound, and its own BIOS slot; it has no Hercules and no
# EGA card, so the video-card entries of the menu are hidden when it is chosen.
set_global_assignment -name VERILOG_MACRO "SYSTEM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ROM_VARIANT_TANDY=0"
set_global_assignment -name VERILOG_MACRO "ENABLE_MODEL_TANDY=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_VIDEO=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_AUDIO=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_TANDY_KBD=1"
# and the IBM PCjr as the third machine: the CGA with its gate array, the infrared
# keyboard, the cartridges and the diskette adapter by programmed I/O. Like the
# Tandy 1000 it has only the CGA, and its own BIOS slot.
set_global_assignment -name VERILOG_MACRO "ENABLE_PCJR=1"

# Video: both families
set_global_assignment -name VERILOG_MACRO "ENABLE_CGA=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_HGC=1"
set_global_assignment -name VERILOG_MACRO "ENABLE_EGA=1"

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

# Fitter seed: the one that closes timing in the four corners with this profile
# (it replaces the default SEED of PCXT.qsf, which config.tcl follows).
set_global_assignment -name SEED 4
