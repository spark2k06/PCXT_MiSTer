# Quartus synthesis script for FPU units area analysis
package require ::quartus::project
package require ::quartus::flow

# List of units to synthesize
set units {
    "FPU_IEEE754_AddSub"
    "FPU_IEEE754_Multiply"
    "FPU_IEEE754_Divide"
    "FPU_SQRT_Newton"
    "FPU_Transcendental"
    "FPU_CORDIC_Wrapper"
    "CORDIC_Rotator"
    "FPU_ArithmeticUnit"
}

# Create synthesis directory
file mkdir synthesis_area_analysis

foreach unit $units {
    puts "\n========================================="
    puts "Synthesizing: $unit"
    puts "=========================================\n"
    
    set proj_name "synthesis_area_analysis/${unit}_area"
    
    # Create project
    if {[is_project_open]} {
        project_close
    }
    
    project_new $proj_name -overwrite
    
    # Set device (Cyclone V as example - adjust as needed)
    set_global_assignment -name FAMILY "Cyclone V"
    set_global_assignment -name DEVICE 5CEBA4F23C7
    
    # Add source files
    set_global_assignment -name VERILOG_FILE ${unit}.v
    
    # Add dependencies based on unit
    switch $unit {
        "FPU_SQRT_Newton" {
            set_global_assignment -name VERILOG_FILE FPU_IEEE754_Divide.v
            set_global_assignment -name VERILOG_FILE FPU_IEEE754_AddSub.v
            set_global_assignment -name VERILOG_FILE FPU_IEEE754_Multiply.v
            set_global_assignment -name VERILOG_FILE AddSubComp.v
        }
        "FPU_Transcendental" {
            set_global_assignment -name VERILOG_FILE FPU_CORDIC_Wrapper.v
            set_global_assignment -name VERILOG_FILE CORDIC_Rotator.v
            set_global_assignment -name VERILOG_FILE BarrelShifter.v
            set_global_assignment -name VERILOG_FILE FPU_Range_Reduction.v
            set_global_assignment -name VERILOG_FILE FPU_Atan_Table.v
        }
        "FPU_CORDIC_Wrapper" {
            set_global_assignment -name VERILOG_FILE CORDIC_Rotator.v
            set_global_assignment -name VERILOG_FILE BarrelShifter.v
        }
        "CORDIC_Rotator" {
            set_global_assignment -name VERILOG_FILE BarrelShifter.v
        }
        "FPU_ArithmeticUnit" {
            set_global_assignment -name VERILOG_FILE FPU_IEEE754_AddSub.v
            set_global_assignment -name VERILOG_FILE FPU_IEEE754_Multiply.v
            set_global_assignment -name VERILOG_FILE FPU_IEEE754_Divide.v
            set_global_assignment -name VERILOG_FILE FPU_SQRT_Newton.v
            set_global_assignment -name VERILOG_FILE FPU_Transcendental.v
            set_global_assignment -name VERILOG_FILE FPU_CORDIC_Wrapper.v
            set_global_assignment -name VERILOG_FILE CORDIC_Rotator.v
            set_global_assignment -name VERILOG_FILE BarrelShifter.v
            set_global_assignment -name VERILOG_FILE FPU_Range_Reduction.v
            set_global_assignment -name VERILOG_FILE FPU_Atan_Table.v
            set_global_assignment -name VERILOG_FILE AddSubComp.v
        }
    }
    
    # Set top entity
    set_global_assignment -name TOP_LEVEL_ENTITY $unit
    
    # Optimize for area
    set_global_assignment -name OPTIMIZATION_MODE "AGGRESSIVE AREA"
    
    # Export assignments
    export_assignments
    
    # Run synthesis only (skip fitting to save time)
    if {[catch {execute_module -tool map} result]} {
        puts "ERROR synthesizing $unit: $result"
    } else {
        puts "SUCCESS: $unit synthesized"
    }
    
    project_close
}

puts "\n========================================="
puts "Synthesis Complete"
puts "=========================================\n"
