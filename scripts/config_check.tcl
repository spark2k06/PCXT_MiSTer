# Build configuration check. Quartus runs this as the
# PRE_FLOW_SCRIPT_FILE of the project: it reads the VERILOG_MACRO assignments
# that config.tcl made for the chosen profile and aborts the flow when they
# describe a core that cannot be built.
#
# scripts/config_check_test.tcl exercises it with every profile and with
# deliberately wrong combinations.

# Value a macro takes when no profile sets it: the `ifndef defaults at the top
# of PCXT.sv. Keep the two in step.
proc pcxt_macro_defaults {} {
    return [dict create \
        SYSTEM_VARIANT_TANDY 0 \
        ENABLE_TANDY_VIDEO   0 \
        ENABLE_TANDY_AUDIO   0 \
        ENABLE_TANDY_KBD     0 \
        ENABLE_CGA           1 \
        ENABLE_HGC           0 \
        ENABLE_EGA           0 \
        ENABLE_VGA13         1 \
        ENABLE_OPL2          0 \
        ENABLE_CMS           0 \
        ENABLE_SB            0 \
        ENABLE_EMS           0 \
        ENABLE_UMB           0 \
        ENABLE_A000_UMB      0 \
        ENABLE_MIDI          1]
}

# Macros that are on/off switches (the rest carry a number or a name)
proc pcxt_switch_macros {} {
    return {
        SYSTEM_VARIANT_TANDY ROM_VARIANT_TANDY ROM_IS_TANDY ENABLE_TANDY_VIDEO
        ENABLE_TANDY_AUDIO ENABLE_TANDY_KBD ENABLE_CGA ENABLE_HGC ENABLE_EGA
        ENABLE_VGA13 ENABLE_OPL2 ENABLE_CMS ENABLE_SB ENABLE_EMS ENABLE_UMB
        ENABLE_A000_UMB ENABLE_MIDI LAYOUT_EGA
    }
}

proc pcxt_on {m name} {
    expr {[dict exists $m $name] && [dict get $m $name] == 1}
}

# Returns {errors warnings} for a dict of macro name -> value (as the profile
# set them; macros it left out take the defaults above).
proc pcxt_check_config {assigned} {
    set m [dict merge [pcxt_macro_defaults] $assigned]
    set errors   {}
    set warnings {}

    # An on/off macro must be 0 or 1; everything below reads them as booleans.
    foreach name [pcxt_switch_macros] {
        if {[dict exists $m $name] && ![regexp {^[01]$} [dict get $m $name]]} {
            lappend errors "$name must be 0 or 1 (it is '[dict get $m $name]')"
        }
    }
    if {[llength $errors]} { return [list $errors $warnings] }

    set tandy      [pcxt_on $m SYSTEM_VARIANT_TANDY]
    set cga        [pcxt_on $m ENABLE_CGA]
    set hgc        [pcxt_on $m ENABLE_HGC]
    set ega        [pcxt_on $m ENABLE_EGA]
    set layout_ega [pcxt_on $m LAYOUT_EGA]

    # The ROM is the Tandy one when ROM_IS_TANDY says so, else when
    # ROM_VARIANT_TANDY does, else when the machine is a Tandy (PCXT.sv).
    if {[dict exists $m ROM_IS_TANDY]} {
        set rom_tandy [pcxt_on $m ROM_IS_TANDY]
    } elseif {[dict exists $m ROM_VARIANT_TANDY]} {
        set rom_tandy [pcxt_on $m ROM_VARIANT_TANDY]
    } else {
        set rom_tandy $tandy
    }

    # Video cards
    if {!$tandy && !$cga && !$hgc && !$ega} {
        lappend errors "PCXT without any video card: set ENABLE_CGA, ENABLE_HGC or ENABLE_EGA"
    }
    if {[pcxt_on $m ENABLE_VGA13] && !$ega} {
        lappend errors "ENABLE_VGA13=1 needs ENABLE_EGA=1 (the VGA 13h+ extension rides on the EGA card); set ENABLE_VGA13=0"
    }
    if {$ega && !$layout_ega} {
        lappend errors "ENABLE_EGA=1 needs LAYOUT_EGA=1: the CGA layout of the OSD has no status bits for the EGA options"
    }
    # Tandy video: the video memory is the system RAM, the CGA window
    # is a view of a block of it. The Hercules and EGA windows would collide
    # with it, and a Tandy machine without its video is not one.
    set tandy_video [pcxt_on $m ENABLE_TANDY_VIDEO]
    if {$tandy_video && !$cga} {
        lappend errors "ENABLE_TANDY_VIDEO=1 needs ENABLE_CGA=1 (the Tandy video modes live in the CGA)"
    }
    if {$tandy_video && $hgc} {
        lappend errors "ENABLE_TANDY_VIDEO=1 with ENABLE_HGC=1: the Tandy video RAM is shared system RAM, there is no Hercules card in a Tandy 1000"
    }
    if {$tandy_video && $ega} {
        lappend errors "ENABLE_TANDY_VIDEO=1 with ENABLE_EGA=1: the EGA card is a PCXT card"
    }
    if {$tandy && !$tandy_video} {
        lappend errors "SYSTEM_VARIANT_TANDY=1 needs ENABLE_TANDY_VIDEO=1"
    }
    if {$ega && $tandy} {
        lappend errors "ENABLE_EGA=1 with SYSTEM_VARIANT_TANDY=1: the EGA card is a PCXT card"
    }
    if {$layout_ega && $rom_tandy} {
        lappend errors "LAYOUT_EGA=1 with a Tandy ROM (ROM_IS_TANDY/ROM_VARIANT_TANDY/SYSTEM_VARIANT_TANDY): the EGA layout has no Tandy BIOS slot"
    }
    if {$layout_ega && $tandy} {
        lappend errors "LAYOUT_EGA=1 with SYSTEM_VARIANT_TANDY=1: the EGA layout is a PCXT menu"
    }

    # Options that live with a card
    if {[pcxt_on $m ENABLE_UMB] && !$ega} {
        lappend warnings "ENABLE_UMB=1 without ENABLE_EGA: UMB C400-CFFF is the EGA BIOS slot, the option has no effect"
    }
    if {[pcxt_on $m ENABLE_A000_UMB] && !$cga && !$hgc && !$tandy} {
        lappend warnings "ENABLE_A000_UMB=1 without a CGA or Hercules card: the option is hidden in the OSD"
    }
    if {[pcxt_on $m ENABLE_SB] && ![pcxt_on $m ENABLE_OPL2]} {
        lappend warnings "ENABLE_SB=1 without ENABLE_OPL2: the Sound Blaster has no FM"
    }
    return [list $errors $warnings]
}

# Macros of the open project as a dict. Each VERILOG_MACRO value is NAME=VALUE;
# a quoted VALUE keeps its quotes out of the dict.
proc pcxt_project_macros {} {
    set d [dict create]
    foreach_in_collection a [get_all_global_assignments -name VERILOG_MACRO] {
        set text [lindex $a 2]
        if {[regexp {^([A-Za-z_][A-Za-z0-9_]*)=(.*)$} $text -> name value]} {
            dict set d $name [string trim $value {"}]
        }
    }
    return $d
}

if {![info exists pcxt_check_no_main]} {
    load_package project
    # As a pre-flow script Quartus runs this in a shell of its own with the
    # arguments "<flow> <project> <revision>", and nothing opened.
    set pcxt_opened 0
    if {![is_project_open]} {
        lassign $quartus(args) pcxt_flow pcxt_project pcxt_revision
        project_open -revision $pcxt_revision $pcxt_project
        set pcxt_opened 1
    }
    lassign [pcxt_check_config [pcxt_project_macros]] errors warnings
    if {$pcxt_opened} { project_close }
    foreach w $warnings { post_message -type warning "config_check: $w" }
    foreach e $errors   { post_message -type error   "config_check: $e" }
    if {[llength $errors]} {
        error "config_check: [llength $errors] invalid combination(s) of build macros"
    }
    post_message -type info "config_check: build macros are consistent"
}
