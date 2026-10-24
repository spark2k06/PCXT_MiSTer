# PCXT configuration. The macros of each build live in profiles/<profile>.tcl:
#
#   mister_pcxt_cga           CGA + Hercules (default; the PCXT core)
#   mister_pcxt_ega           EGA + Sound Blaster Pro (the PCXT core with EGA)
#   mister_pcxt_full          both video families, the card is chosen at reset
#   mister_tandy1000          Tandy 1000 (CGA + Tandy video, Tandy BIOS), CORE_NAME "Tandy1000"
#
# Pick one with the PCXT_PROFILE environment variable before running Quartus,
# for instance PCXT_PROFILE=mister_pcxt_full quartus_sh --flow compile PCXT
#
# scripts/config_check.tcl (PRE_FLOW_SCRIPT_FILE) rejects invalid combinations.

# Forget what an earlier evaluation of this file left behind (the Quartus GUI
# evaluates it repeatedly in one process).
foreach v [info vars pcxt_*] { unset $v }

set pcxt_profile mister_pcxt_cga
if {[info exists ::env(PCXT_PROFILE)] && $::env(PCXT_PROFILE) ne ""} {
    set pcxt_profile $::env(PCXT_PROFILE)
}
set pcxt_profile_file [file join [file dirname [info script]] profiles ${pcxt_profile}.tcl]
if {![file exists $pcxt_profile_file]} {
    error "config.tcl: no profile '${pcxt_profile}' (looked for $pcxt_profile_file)"
}
source $pcxt_profile_file

# Clock networks. The right-hand PLL (pll_system) can only drive the six global
# clock lines GCLK6-GCLK11, and with the EGA card's clocks seven nets want one
# (the PLL outputs, vga_tx_clk, h2f_user0_clk, h2f_rst_n). Left alone, the
# fitter put the 114.5 MHz SDRAM controller clock on a regional clock that does
# not reach the SDRAM_DQ pins: sdram_ctrl's dq_in_q registers could not go into
# their I/O cells ("nodes have conflicting location assignments") and the SDRAM
# I/O paths failed by 4-6 ns. Forcing that clock onto a global line closed them
# (the EGA builds). Freeing vga_tx_clk instead (GLOBAL_SIGNAL OFF) crashes
# Quartus 17.0.2's fitter (periph_pcc segfault), so do not add that one.
# Profiles with the EGA card ask for it with pcxt_global_sdram_clock.
if {[info exists pcxt_global_sdram_clock] && $pcxt_global_sdram_clock} {
    set_instance_assignment -name GLOBAL_SIGNAL "GLOBAL CLOCK" -to {emu:emu|pll_system:pll_system_inst|pll_system_0002:pll_system_inst|altera_pll:altera_pll_i|outclk_wire[2]}
}
