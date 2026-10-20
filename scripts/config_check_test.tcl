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
