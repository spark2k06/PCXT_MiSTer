#!/usr/bin/env python3
"""
FPU Area Analysis Tool
Analyzes Verilog modules to estimate relative area consumption
"""

import re
import os
from collections import defaultdict

def analyze_verilog_file(filename):
    """Analyze a Verilog file for area-consuming constructs"""
    
    if not os.path.exists(filename):
        return None
    
    with open(filename, 'r') as f:
        content = f.read()
    
    stats = {
        'filename': filename,
        'lines': len(content.split('\n')),
        'registers': 0,
        'wires': 0,
        'multipliers': 0,
        'adders': 0,
        'comparators': 0,
        'shifters': 0,
        'muxes': 0,
        'memories': 0,
        'fsm_states': 0,
        'case_statements': 0,
        'instances': [],
    }
    
    # Count registers (includes reg declarations)
    stats['registers'] = len(re.findall(r'\breg\s+\[?\d*:?\d*\]?\s+\w+', content))
    
    # Count wires
    stats['wires'] = len(re.findall(r'\bwire\s+\[?\d*:?\d*\]?\s+\w+', content))
    
    # Count multipliers (*, mantissa_product, etc.)
    stats['multipliers'] = len(re.findall(r'(\*|\bmantissa_product\b)', content))
    
    # Count adders (+, -, add, sub operations)
    stats['adders'] = len(re.findall(r'(\+|-|\badd\b|\bsub\b)', content))
    
    # Count comparators (==, !=, <, >, <=, >=)
    stats['comparators'] = len(re.findall(r'(==|!=|<=|>=|<|>)', content))
    
    # Count shifters (<<, >>, shift operations)
    stats['shifters'] = len(re.findall(r'(<<|>>|\bshift\b)', content))
    
    # Count multiplexers (? :, case, if statements)
    stats['muxes'] = len(re.findall(r'\?|case|if\s*\(', content))
    
    # Count memories/arrays
    stats['memories'] = len(re.findall(r'reg\s+\[.*?\]\s+\w+\s*\[', content))
    
    # Count FSM states
    stats['fsm_states'] = len(re.findall(r'localparam\s+STATE_\w+', content))
    
    # Count case statements
    stats['case_statements'] = len(re.findall(r'\bcase\s*\(', content))
    
    # Find module instantiations
    instances = re.findall(r'(\w+)\s+(\w+)\s*\(', content)
    for mod_type, inst_name in instances:
        if mod_type not in ['module', 'function', 'task', 'if', 'case', 'for', 'while', 'begin']:
            stats['instances'].append((mod_type, inst_name))
    
    return stats

def estimate_area_score(stats):
    """Estimate relative area score based on resource counts"""
    if stats is None:
        return 0
    
    # Weighted scoring (higher weight = more area)
    score = 0
    score += stats['registers'] * 10  # Registers cost area
    score += stats['multipliers'] * 500  # Multipliers are expensive!
    score += stats['adders'] * 50  # Adders cost moderate area
    score += stats['comparators'] * 20
    score += stats['shifters'] * 30  # Barrel shifters can be large
    score += stats['muxes'] * 5
    score += stats['memories'] * 200  # Memories are expensive
    score += stats['fsm_states'] * 15
    score += stats['case_statements'] * 10
    
    return score

def analyze_module_hierarchy(module_name, analyzed=None):
    """Recursively analyze module and its dependencies"""
    if analyzed is None:
        analyzed = {}
    
    if module_name in analyzed:
        return analyzed
    
    filename = f"{module_name}.v"
    stats = analyze_verilog_file(filename)
    
    if stats:
        analyzed[module_name] = stats
        
        # Recursively analyze instantiated modules
        for inst_type, inst_name in stats['instances']:
            if inst_type not in analyzed:
                analyze_module_hierarchy(inst_type, analyzed)
    
    return analyzed

# Main analysis
print("=" * 80)
print("FPU AREA ANALYSIS")
print("=" * 80)
print()

modules_to_analyze = [
    'FPU_IEEE754_AddSub',
    'FPU_IEEE754_Multiply', 
    'FPU_IEEE754_Divide',
    'FPU_SQRT_Newton',
    'FPU_Transcendental',
    'FPU_CORDIC_Wrapper',
    'CORDIC_Rotator',
    'FPU_ArithmeticUnit',
]

all_stats = {}
for module in modules_to_analyze:
    print(f"Analyzing {module}...")
    all_stats.update(analyze_module_hierarchy(module))

print()
print("=" * 80)
print("RESULTS - Sorted by Estimated Area")
print("=" * 80)
print()

# Calculate scores and sort
scored_modules = []
for module, stats in all_stats.items():
    if module in modules_to_analyze:  # Only show top-level modules
        score = estimate_area_score(stats)
        scored_modules.append((module, score, stats))

scored_modules.sort(key=lambda x: x[1], reverse=True)

print(f"{'Module':<35} {'Est. Area':<15} {'Regs':<8} {'Mults':<8} {'Adds':<8} {'Shift':<8} {'Mem':<8}")
print("-" * 100)

for module, score, stats in scored_modules:
    print(f"{module:<35} {score:<15} {stats['registers']:<8} {stats['multipliers']:<8} "
          f"{stats['adders']:<8} {stats['shifters']:<8} {stats['memories']:<8}")

print()
print("=" * 80)
print("DETAILED ANALYSIS")
print("=" * 80)
print()

for module, score, stats in scored_modules[:5]:  # Show top 5 in detail
    print(f"\n{module}:")
    print(f"  Estimated Area Score: {score}")
    print(f"  Lines of Code: {stats['lines']}")
    print(f"  Registers: {stats['registers']}")
    print(f"  Multipliers: {stats['multipliers']}")
    print(f"  Adders: {stats['adders']}")
    print(f"  Shifters: {stats['shifters']}")
    print(f"  Comparators: {stats['comparators']}")
    print(f"  FSM States: {stats['fsm_states']}")
    print(f"  Memories: {stats['memories']}")
    if stats['instances']:
        print(f"  Instantiated Modules: {len(stats['instances'])}")
        instance_types = {}
        for inst_type, _ in stats['instances']:
            instance_types[inst_type] = instance_types.get(inst_type, 0) + 1
        for inst_type, count in sorted(instance_types.items()):
            print(f"    - {inst_type}: {count}x")

