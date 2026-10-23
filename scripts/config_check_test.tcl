# Self-test of scripts/config_check.tcl. Run from the project directory with
# Quartus' Tcl shell (or any Tcl 8.6 that can run the profile files):
#
#   quartus_sh -t scripts/config_check_test.tcl
#
# Every profile in profiles/ is evaluated through config.tcl against stubs of
# the Quartus commands, and its macros must pass the check. Then a list of
# wrong combinations must each be rejected for the expected reason.

set pcxt_check_no_main 1
source [file join [file dirname [info script]] config_check.tcl]

set failures 0
proc fail {msg} {
    global failures
    puts "FAIL: $msg"
    incr failures
}

# --- the profiles -----------------------------------------------------------
# config.tcl runs in a child interpreter whose Quartus commands record what a
# profile assigns instead of changing a project.
proc evaluate_profile {profile} {
    set ip [interp create]
    $ip eval {
        set ::macros [dict create]
        set ::instance_assignments {}
        proc set_global_assignment {args} {
            if {[lindex $args 0] eq "-name" && [lindex $args 1] eq "VERILOG_MACRO"} {
                set text [lindex $args 2]
                regexp {^([A-Za-z_][A-Za-z0-9_]*)=(.*)$} $text -> name value
                if {[dict exists $::macros $name]} {
                    error "macro $name assigned twice ([dict get $::macros $name], then [string trim $value {"}])"
                }
                dict set ::macros $name [string trim $value {"}]
            }
        }
        proc set_instance_assignment {args} { lappend ::instance_assignments $args }
    }
    $ip eval [list set ::env(PCXT_PROFILE) $profile]
    $ip eval [list source [file join [file dirname [info script]] .. config.tcl]]
    set result [list [$ip eval {set ::macros}] [$ip eval {set ::instance_assignments}]]
    interp delete $ip
    return $result
}

set profile_dir [file join [file dirname [info script]] .. profiles]
foreach f [lsort [glob -directory $profile_dir *.tcl]] {
    set profile [file rootname [file tail $f]]
    if {[catch {lassign [evaluate_profile $profile] macros instance} err]} {
        fail "$profile: $err"
        continue
    }
    lassign [pcxt_check_config $macros] errors warnings
    if {[llength $errors]} {
        fail "$profile rejected: [join $errors {; }]"
    } else {
        puts "ok:   $profile ([dict size $macros] macros, [llength $instance] instance assignment(s))"
    }
    foreach w $warnings { puts "      warning: $w" }
}

# The trimmed variants differ from mister_pcxt_full in exactly the macros they trim
lassign [evaluate_profile mister_pcxt_full]          full   _
lassign [evaluate_profile mister_pcxt_full_novga13]  novga  _
if {[dict get $novga ENABLE_VGA13] != 0 || [dict get $novga ENABLE_EGA] != 1} {
    fail "mister_pcxt_full_novga13 must keep the EGA and drop VGA 13h"
}
lassign [evaluate_profile mister_pcxt_cga] cga _
if {[dict get $cga ENABLE_EGA] != 0 || [dict exists $cga LAYOUT_EGA]} {
    fail "mister_pcxt_cga must be the CGA layout without an EGA card"
}

lassign [evaluate_profile mister_tandy1000] tandy1000 _
if {[dict get $tandy1000 SYSTEM_VARIANT_TANDY] != 1 || [dict get $tandy1000 ENABLE_TANDY_VIDEO] != 1
    || [dict get $tandy1000 ENABLE_HGC] != 0 || [dict get $tandy1000 ENABLE_EGA] != 0
    || [dict exists $tandy1000 LAYOUT_EGA]} {
    fail "mister_tandy1000 must be a Tandy machine with the CGA family only and the CGA layout"
}

foreach p {mister_pcxt_full mister_pcxt_full_novga13} {
    lassign [evaluate_profile $p] pm _
    if {[dict get $pm ENABLE_MODEL_TANDY] != 1 || [dict get $pm ENABLE_TANDY_VIDEO] != 1
        || [dict get $pm ENABLE_TANDY_KBD] != 1} {
        fail "$p must choose the machine in the OSD (Tandy video and keyboard built in)"
    }
}
foreach p {mister_pcxt_cga mister_pcxt_ega mister_tandy1000} {
    lassign [evaluate_profile $p] pm _
    if {[dict exists $pm ENABLE_MODEL_TANDY] && [dict get $pm ENABLE_MODEL_TANDY] != 0} {
        fail "$p has a fixed machine and must not choose it in the OSD"
    }
}

# --- wrong combinations -----------------------------------------------------
set base [dict create LAYOUT_EGA 1 ENABLE_CGA 1 ENABLE_HGC 1 ENABLE_EGA 1 ENABLE_VGA13 1 ENABLE_SB 1 ENABLE_OPL2 1]

proc expect_error {label macros pattern} {
    lassign [pcxt_check_config $macros] errors warnings
    foreach e $errors {
        if {[string match $pattern $e]} { puts "ok:   $label rejected"; return }
    }
    fail "$label: expected an error matching '$pattern', got {$errors}"
}

expect_error "EGA without LAYOUT_EGA" \
    [dict remove $base LAYOUT_EGA] "*ENABLE_EGA=1 needs LAYOUT_EGA=1*"
expect_error "Tandy ROM with the EGA layout" \
    [dict replace $base ROM_VARIANT_TANDY 1] "*LAYOUT_EGA=1 with a Tandy ROM*"
expect_error "ROM_IS_TANDY with the EGA layout" \
    [dict replace $base ROM_IS_TANDY 1] "*LAYOUT_EGA=1 with a Tandy ROM*"
expect_error "VGA13 without EGA" \
    [dict replace $base ENABLE_EGA 0] "*ENABLE_VGA13=1 needs ENABLE_EGA=1*"
expect_error "no video card" \
    [dict replace $base ENABLE_CGA 0 ENABLE_HGC 0 ENABLE_EGA 0 ENABLE_VGA13 0] "*without any video card*"
expect_error "EGA in a Tandy machine" \
    [dict replace $base SYSTEM_VARIANT_TANDY 1] "*SYSTEM_VARIANT_TANDY=1*"
set tandy_ok [dict create ENABLE_CGA 1 ENABLE_HGC 0 ENABLE_EGA 0 ENABLE_VGA13 0 SYSTEM_VARIANT_TANDY 1 ROM_VARIANT_TANDY 1 ENABLE_TANDY_VIDEO 1]
expect_error "Tandy video without the CGA"     [dict replace $tandy_ok ENABLE_CGA 0 ENABLE_HGC 1] "*ENABLE_TANDY_VIDEO=1 needs ENABLE_CGA=1*"
expect_error "Tandy video with Hercules"     [dict replace $tandy_ok ENABLE_HGC 1] "*ENABLE_TANDY_VIDEO=1 with ENABLE_HGC=1*"
expect_error "Tandy video with the EGA card"     [dict replace $tandy_ok ENABLE_EGA 1 LAYOUT_EGA 1] "*ENABLE_TANDY_VIDEO=1 with ENABLE_EGA=1*"
expect_error "a Tandy machine without Tandy video"     [dict replace $tandy_ok ENABLE_TANDY_VIDEO 0] "*SYSTEM_VARIANT_TANDY=1 needs ENABLE_TANDY_VIDEO=1*"
# The machine chosen in the OSD
set model_ok [dict merge $base [dict create ENABLE_TANDY_VIDEO 1 ENABLE_TANDY_KBD 1 ENABLE_TANDY_AUDIO 1 ENABLE_MODEL_TANDY 1]]
lassign [pcxt_check_config $model_ok] errors warnings
if {[llength $errors]} { fail "machine choice with both card families rejected: $errors" } else { puts "ok:   machine choice accepted" }
expect_error "machine choice without the EGA layout" [dict remove $model_ok LAYOUT_EGA] "*ENABLE_MODEL_TANDY=1 needs LAYOUT_EGA=1*"
expect_error "machine choice without the CGA"         [dict replace $model_ok ENABLE_CGA 0 ENABLE_HGC 0] "*ENABLE_MODEL_TANDY=1 needs ENABLE_CGA=1*"
expect_error "machine choice without Tandy video"     [dict replace $model_ok ENABLE_TANDY_VIDEO 0] "*ENABLE_MODEL_TANDY=1 needs ENABLE_TANDY_VIDEO=1*"
expect_error "machine choice without the Tandy keyboard" [dict replace $model_ok ENABLE_TANDY_KBD 0] "*ENABLE_MODEL_TANDY=1 needs ENABLE_TANDY_KBD=1*"
expect_error "machine choice without Tandy sound"     [dict replace $model_ok ENABLE_TANDY_AUDIO 0] "*ENABLE_MODEL_TANDY=1 needs ENABLE_TANDY_AUDIO=1*"
expect_error "machine choice with a fixed Tandy"      [dict replace $model_ok ROM_VARIANT_TANDY 1] "*ENABLE_MODEL_TANDY=1 with a Tandy machine fixed*"
expect_error "Tandy video in a PCXT without a Tandy BIOS slot" \
    [dict create ENABLE_CGA 1 ENABLE_TANDY_VIDEO 1] "*needs a Tandy BIOS slot*"
expect_error "a switch that is not 0 or 1" \
    [dict replace $base ENABLE_SB 2] "*ENABLE_SB must be 0 or 1*"

# The EGA-only profile has no CGA family at all and must still pass
lassign [pcxt_check_config [dict replace $base ENABLE_CGA 0 ENABLE_HGC 0]] errors warnings
if {[llength $errors]} { fail "EGA-only combination rejected: $errors" } else { puts "ok:   EGA only accepted" }

if {$failures} {
    puts "$failures check(s) failed"
    exit 1
}
puts "config_check_test: all checks passed"
