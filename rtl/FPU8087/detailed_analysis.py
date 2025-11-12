#!/usr/bin/env python3
"""
Detailed analysis of large FPU units for microcode decomposition
"""

import re

def analyze_unit_structure(filename, unit_name):
    """Analyze the internal structure of a unit"""
    
    try:
        with open(filename, 'r') as f:
            content = f.read()
    except:
        return None
    
    print(f"\n{'='*80}")
    print(f"DETAILED ANALYSIS: {unit_name}")
    print(f"{'='*80}\n")
    
    # Find FSM states
    states = re.findall(r'localparam\s+(STATE_\w+)\s*=', content)
    if states:
        print(f"FSM States ({len(states)}):")
        for i, state in enumerate(states, 1):
            print(f"  {i}. {state}")
        print()
    
    # Find instantiated modules
    instances = re.findall(r'(\w+)\s+(\w+)\s*\(\s*\.', content)
    module_instances = {}
    for mod_type, inst_name in instances:
        if mod_type.startswith('FPU_') or mod_type == 'CORDIC_Rotator' or mod_type == 'BarrelShifter':
            if mod_type not in module_instances:
                module_instances[mod_type] = []
            module_instances[mod_type].append(inst_name)
    
    if module_instances:
        print("Instantiated Hardware Units:")
        for mod_type, instances in sorted(module_instances.items()):
            print(f"  {mod_type}: {len(instances)}x")
            for inst in instances:
                print(f"    - {inst}")
        print()
    
    # Count arithmetic operations
    mult_count = len(re.findall(r'\*(?!=)', content))
    add_count = len(re.findall(r'\+', content))
    sub_count = len(re.findall(r'-(?!=)', content))
    shift_count = len(re.findall(r'(<<|>>)', content))
    
    print("Arithmetic Operations:")
    print(f"  Multiplications: {mult_count}")
    print(f"  Additions: {add_count}")
    print(f"  Subtractions: {sub_count}")
    print(f"  Shifts: {shift_count}")
    print()
    
    # Look for iteration/loop structures
    iterations = re.findall(r'(iteration|counter|count)\s*(?:<=|=)', content)
    if iterations:
        print(f"Iterative structures found: {len(iterations)}")
        print()
    
    return {
        'states': len(states),
        'instances': module_instances,
        'mult': mult_count,
        'add': add_count,
        'shift': shift_count
    }

# Analyze the top 3 area consumers
units = [
    ('FPU_CORDIC_Wrapper.v', 'FPU_CORDIC_Wrapper'),
    ('FPU_SQRT_Newton.v', 'FPU_SQRT_Newton'),
    ('FPU_Transcendental.v', 'FPU_Transcendental'),
]

for filename, unit_name in units:
    analyze_unit_structure(filename, unit_name)

