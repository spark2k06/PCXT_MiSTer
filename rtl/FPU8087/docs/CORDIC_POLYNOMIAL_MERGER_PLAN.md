# CORDIC/Polynomial Merger Implementation Plan

**Date**: 2025-11-10
**Target**: Merge FPU_CORDIC_Wrapper (438 lines) + FPU_Polynomial_Evaluator (334 lines) → ~550 lines
**Savings**: ~220 lines (~30% reduction)
**Status**: Implementation Plan

## Analysis

### Current Architecture

**FPU_CORDIC_Wrapper (438 lines)**:
- Modes: ROTATION (sin/cos), VECTORING (atan)
- Algorithm: Iterative CORDIC rotations (50 iterations)
- Datapath: 64-bit fixed-point (Q2.62 format)
- Operations per iteration: Shift + Add/Sub
- Resources: x, y, z registers + atan table

**FPU_Polynomial_Evaluator (334 lines)**:
- Modes: F2XM1 (2^x-1), LOG2 (log₂(1+x))
- Algorithm: Horner's method (6-7 iterations)
- Datapath: FP80 using existing multiply/add units
- Operations per iteration: Multiply + Add
- Resources: accumulator + coefficient ROM

**Total**: 772 lines

### Merger Strategy

The key challenge is that these modules use different data formats:
- CORDIC: 64-bit fixed-point (shift-add operations)
- Polynomial: FP80 (complex multiply-add operations)

**Approach**: Structural consolidation rather than datapath sharing.

## Unified Architecture

```verilog
module FPU_Transcendental_Unified(
    input wire clk,
    input wire reset,
    input wire enable,
    input wire [3:0] operation_mode,  // Mode selector

    // Unified inputs
    input wire [79:0] operand_a,      // Primary operand
    input wire [79:0] operand_b,      // Secondary operand (for ATAN)

    // Unified outputs
    output reg [79:0] result_primary,
    output reg [79:0] result_secondary,  // For sin/cos dual output
    output reg        has_secondary,
    output reg        done,
    output reg        error
);

    // Operation modes
    localparam MODE_SIN     = 4'd0;  // CORDIC rotation
    localparam MODE_COS     = 4'd1;  // CORDIC rotation
    localparam MODE_SINCOS  = 4'd2;  // CORDIC rotation (both)
    localparam MODE_ATAN    = 4'd3;  // CORDIC vectoring
    localparam MODE_F2XM1   = 4'd4;  // Polynomial
    localparam MODE_LOG2    = 4'd5;  // Polynomial

    // Shared state machine
    localparam STATE_IDLE          = 4'd0;
    localparam STATE_PREPARE       = 4'd1;  // Mode-specific prep
    localparam STATE_ITERATE       = 4'd2;  // Core iteration
    localparam STATE_FINALIZE      = 4'd3;  // Mode-specific finalization
    localparam STATE_DONE          = 4'd4;

    reg [3:0] state;
    reg [5:0] iteration_count;
    reg [3:0] current_mode;

    // CORDIC datapath (used when mode < 4)
    reg signed [63:0] cordic_x, cordic_y, cordic_z;

    // Polynomial datapath (used when mode >= 4)
    reg [79:0] poly_accumulator;
    reg [79:0] poly_x;
    reg [3:0]  poly_coeff_idx;

    // Shared conversion functions
    function [63:0] fp80_to_fixed(...);
    function [79:0] fixed_to_fp80(...);

    always @(posedge clk) begin
        case (state)
            STATE_IDLE: /* Load mode and prepare */

            STATE_PREPARE: begin
                if (current_mode < MODE_F2XM1) begin
                    // CORDIC preparation
                    // - Range reduction for sin/cos
                    // - Convert FP80 to fixed-point
                    // - Initialize x, y, z
                end else begin
                    // Polynomial preparation
                    // - Load first coefficient
                    // - Initialize accumulator
                end
            end

            STATE_ITERATE: begin
                if (current_mode < MODE_F2XM1) begin
                    // CORDIC iteration
                    // - Shift x, y by iteration_count
                    // - Conditional add/sub based on z or y sign
                    // - Update x, y, z
                    iteration_count <= iteration_count + 1;
                    if (iteration_count >= 50)
                        state <= STATE_FINALIZE;
                end else begin
                    // Polynomial iteration (Horner's method)
                    // - Multiply accumulator by x
                    // - Wait for multiply done
                    // - Add next coefficient
                    // - Wait for add done
                    poly_coeff_idx <= poly_coeff_idx - 1;
                    if (poly_coeff_idx == 0)
                        state <= STATE_FINALIZE;
                end
            end

            STATE_FINALIZE: begin
                if (current_mode < MODE_F2XM1) begin
                    // CORDIC finalization
                    // - Convert fixed-point to FP80
                    // - Quadrant correction for sin/cos
                end else begin
                    // Polynomial finalization
                    // - Result already in accumulator
                end
                state <= STATE_DONE;
            end

            STATE_DONE: /* Output results */
        endcase
    end
endmodule
```

## Savings Breakdown

| Component | Current | Unified | Savings |
|-----------|---------|---------|---------|
| **Module declarations** | 2×40 = 80 | 50 | -30 |
| **Shared state machine** | 2×100 = 200 | 120 | -80 |
| **Conversion functions** | 2×80 = 160 | 90 | -70 |
| **CORDIC datapath** | 180 | 170 | -10 |
| **Polynomial datapath** | 150 | 120 | -30 |
| **Control logic** | 2×0 = 0 | 0 | 0 |
| **Total** | 772 | 550 | **-222** |

## Implementation Steps

### Phase 1: Create Unified Module Structure (Done: 0%)
1. Define unified interface
2. Create mode-based state machine
3. Add shared conversion functions
4. Integrate both datapaths with mode switching

### Phase 2: Implement CORDIC Path (Done: 0%)
1. Port CORDIC initialization
2. Port CORDIC iteration logic
3. Port range reduction integration
4. Port quadrant correction
5. Test: sin, cos, atan operations

### Phase 3: Implement Polynomial Path (Done: 0%)
1. Port polynomial initialization
2. Port Horner's method iteration
3. Port coefficient ROM access
4. Test: F2XM1, LOG2 operations

### Phase 4: Integration and Testing (Done: 0%)
1. Create unified testbench
2. Test all 6 modes comprehensively
3. Verify against original modules
4. Performance comparison
5. Area analysis

### Phase 5: Documentation and Commit (Done: 0%)
1. Document architecture
2. Create test report
3. Update FPU_Transcendental to use unified module
4. Commit and push

## Testing Strategy

### Comprehensive Test Suite

**Test File**: `tb_transcendental_unified.v`

**Test Coverage** (Minimum 30 tests):
1. **SIN Tests** (6 tests)
   - sin(0) = 0
   - sin(π/6) = 0.5
   - sin(π/4) = 0.707...
   - sin(π/2) = 1.0
   - sin(π) = 0
   - sin(3π/2) = -1.0

2. **COS Tests** (6 tests)
   - cos(0) = 1.0
   - cos(π/6) = 0.866...
   - cos(π/4) = 0.707...
   - cos(π/2) = 0
   - cos(π) = -1.0
   - cos(2π) = 1.0

3. **SINCOS Tests** (3 tests)
   - sincos(π/4) both outputs
   - sincos(π/6) both outputs
   - sincos(π/3) both outputs

4. **ATAN Tests** (5 tests)
   - atan(0) = 0
   - atan(1) = π/4
   - atan(√3) = π/3
   - atan(-1) = -π/4
   - atan(large) ≈ π/2

5. **F2XM1 Tests** (5 tests)
   - 2^0 - 1 = 0
   - 2^1 - 1 = 1
   - 2^0.5 - 1 ≈ 0.414
   - 2^-1 - 1 = -0.5
   - 2^2 - 1 = 3

6. **LOG2 Tests** (5 tests)
   - log₂(1) = 0
   - log₂(2) = 1
   - log₂(4) = 2
   - log₂(1.5) ≈ 0.585
   - log₂(0.5) = -1

**Total**: 30+ comprehensive tests

### Test Methodology

```verilog
task test_sin;
    input [79:0] angle;
    input [79:0] expected_result;
    input [255:0] test_name;
    begin
        operation_mode = MODE_SIN;
        operand_a = angle;
        enable = 1'b1;
        @(posedge clk);
        enable = 1'b0;

        wait (done);
        @(posedge clk);

        if (result_matches(result_primary, expected_result, tolerance)) begin
            $display("PASS: %s", test_name);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: %s - Expected %h, Got %h",
                     test_name, expected_result, result_primary);
            fail_count = fail_count + 1;
        end
    end
endtask
```

## Challenges and Solutions

### Challenge 1: Different Data Formats
**Problem**: CORDIC uses fixed-point, Polynomial uses FP80
**Solution**: Keep separate datapaths, share control logic only

### Challenge 2: Different Iteration Counts
**Problem**: CORDIC needs 50 iterations, Polynomial needs 6-7
**Solution**: Mode-based iteration limit

### Challenge 3: Different Resources
**Problem**: CORDIC needs atan table, Polynomial needs coefficient ROM
**Solution**: Mode-based resource access

### Challenge 4: Complex State Machines
**Problem**: Both have multi-state FSMs
**Solution**: Unified state machine with mode-specific branches

## Expected Results

**Area Savings**: ~222 lines (30% reduction)
**Performance**: No degradation (operations never simultaneous)
**Functionality**: 100% compatible with original modules
**Test Coverage**: 30+ comprehensive tests, all passing

## Alternative: Microcode Approach

If the structural merger doesn't achieve sufficient savings, consider moving transcendental operations to microcode (similar to SQRT and BCD):

**Microcode Programs**:
- FSIN: Call CORDIC in rotation mode
- FCOS: Call CORDIC in rotation mode
- FSINCOS: Call CORDIC, return both results
- FPATAN: Call CORDIC in vectoring mode
- F2XM1: Call Polynomial with F2XM1 coefficients
- FYL2X: Call Polynomial with LOG2 coefficients, then multiply

**Savings**: ~70 lines of orchestration logic replaced with microcode
**Total with Merger + Microcode**: ~290 lines saved

## Conclusion

The CORDIC/Polynomial merger is feasible and will achieve the target ~220 line savings through:
1. Structural consolidation
2. Shared state machine
3. Shared conversion functions
4. Unified interface

The merger maintains both algorithms intact while eliminating redundant infrastructure.

**Next Step**: Implement FPU_Transcendental_Unified.v with comprehensive testing.

---

**Status**: Ready for implementation
**Estimated Effort**: 2-3 hours for full implementation + testing
**Risk**: Low (structural consolidation, no algorithm changes)
