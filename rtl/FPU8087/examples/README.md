# Microcode Examples for 8087 FPU Microsequencer

This directory contains example microcode programs for the Intel 8087 FPU microsequencer.

## Examples

### Example 1: Simple Operation (`example1_simple.asm`)
Demonstrates basic operations:
- Loading data from CPU bus
- Accessing mathematical constants
- Storing results
- Reading FPU status

**Assembling:**
```bash
python ../microasm.py example1_simple.asm -o example1.hex -l example1.lst
```

### Example 2: Loop (`example2_loop.asm`)
Shows loop control structures:
- Loop initialization
- Iterative calculations
- Loop decrement and conditional branching

**Assembling:**
```bash
python ../microasm.py example2_loop.asm -o example2.hex -f verilog
```

### Example 3: Subroutines (`example3_subroutine.asm`)
Demonstrates modular microcode:
- Subroutine calls (CALL instruction)
- Return from subroutine (RET instruction)
- Reusable code blocks

**Assembling:**
```bash
python ../microasm.py example3_subroutine.asm -o example3.hex -l example3.lst
```

### Example 4: Complex Operations (`example4_complex.asm`)
Implements square root approximation:
- Newton-Raphson iteration
- Multiple iterations
- Convergence logic

**Assembling:**
```bash
python ../microasm.py example4_complex.asm -o example4.hex
```

### Example 5: CORDIC (`example5_cordic.asm`)
Simplified CORDIC rotation algorithm:
- Iterative rotations
- Shift operations
- Vector manipulation

**Assembling:**
```bash
python ../microasm.py example5_cordic.asm -o example5.hex -l example5.lst
```

## Instruction Set Reference

### Control Flow
- `NOP` - No operation
- `JUMP addr` - Unconditional jump
- `CALL addr` - Call subroutine
- `RET` - Return from subroutine
- `HALT` - Stop execution

### Data Movement
- `LOAD` - Load from CPU bus into temp_reg
- `STORE` - Store temp_reg to CPU bus
- `SET_CONST imm` - Set constant index
- `ACCESS_CONST` - Load constant into temp_fp

### Arithmetic
- `ADD` - Add operands
- `SUB` - Subtract operands
- `ABS` - Absolute value
- `NORMALIZE` - Normalize floating point
- `ROUND mode` - Round with specified mode

### Bit Operations
- `SHIFT_LEFT amount` - Left shift by amount

### Loop Control
- `LOOP_INIT count` - Initialize loop counter
- `LOOP_DEC target` - Decrement and branch if not zero

### Register Access
- `READ_STATUS` - Read status word
- `READ_CONTROL` - Read control word
- `READ_TAG` - Read tag register
- `WRITE_STATUS` - Write status word

### Directives
- `.ORG addr` - Set origin address
- `.EQU name = value` - Define symbol
- `.ALIGN n` - Align to n-byte boundary

## Output Formats

The assembler supports multiple output formats:

1. **Hex** (`-f hex`): Human-readable hexadecimal with addresses
2. **Verilog** (`-f verilog`): For use with `$readmemh` in Verilog
3. **Binary** (`-f binary`): Raw binary output
4. **Listing** (`-f listing`): Assembly listing with addresses and encoding

## Usage Tips

1. **Use labels** for better readability and maintainability
2. **Define constants** with `.EQU` instead of magic numbers
3. **Comment extensively** - microcode can be hard to understand
4. **Test incrementally** - start simple and build up
5. **Generate listings** (`-l`) to verify encoding

## Loading Microcode into Verilog

To use the assembled microcode in your Verilog simulation:

```verilog
// In sequencer.v or testbench
initial begin
    $readmemh("example1.hex", microcode_rom);
end
```

## Advanced Topics

### Microcode Optimization
- Minimize jumps for better performance
- Use subroutines to reduce code size
- Unroll critical loops when possible
- Keep frequently-used code in low addresses

### Debugging
- Generate listings to check encoding
- Use verbose mode (`-v`) for statistics
- Verify labels resolve correctly
- Check for alignment issues

### Integration with HDL
- Use Verilog format for direct inclusion
- Generate separate ROMs for different programs
- Create jump tables for multi-function support
