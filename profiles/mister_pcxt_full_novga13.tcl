# Profile mister_pcxt_full_novga13: mister_pcxt_full without the VGA 13h+
# extension (first step of the area trimming). The EGA stays; the DAC and
# the packed 13h, Mode X and 0Dh modes go, and VGATSR.COM refuses to install.
# Sourced by config.tcl.

set pcxt_enable_vga13 0
source [file join [file dirname [info script]] mister_pcxt_full.tcl]
