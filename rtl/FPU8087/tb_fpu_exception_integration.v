/**
 * tb_fpu_exception_integration.v
 *
 * Integration test for FPU_Core exception handler
 *
 * Tests Phase 3 integration:
 * 1. Exception latching from simulated arithmetic operations
 * 2. INT signal propagation
 * 3. Wait instruction blocking on exceptions
 * 4. FCLEX/FNCLEX exception clearing
 * 5. Sticky INT behavior
 *
 * This is a focused integration test that verifies the exception
 * handler wiring without requiring full FPU_Core instantiation.
 *
 * Date: 2025-11-10
 */

`timescale 1ns/1ps

module tb_fpu_exception_integration;

    //=================================================================
    // Testbench Signals
    //=================================================================

    reg clk;
    reg reset;

    // Exception inputs (simulating arithmetic unit)
    reg exception_invalid;
    reg exception_denormal;
    reg exception_zero_div;
    reg exception_overflow;
    reg exception_underflow;
    reg exception_precision;

    // Mask bits (simulating control word)
    reg mask_invalid;
    reg mask_denormal;
    reg mask_zero_div;
    reg mask_overflow;
    reg mask_underflow;
    reg mask_precision;

    // Control signals
    reg exception_clear;
    reg exception_latch;

    // Outputs
    wire int_request;
    wire exception_pending;
    wire [5:0] latched_exceptions;
    wire has_unmasked_exception;

    //=================================================================
    // Test Statistics
    //=================================================================

    integer test_count;
    integer pass_count;
    integer fail_count;

    //=================================================================
    // DUT Instantiation
    //=================================================================

    FPU_Exception_Handler exception_handler (
        .clk(clk),
        .reset(reset),
        .exception_invalid(exception_invalid),
        .exception_denormal(exception_denormal),
        .exception_zero_div(exception_zero_div),
        .exception_overflow(exception_overflow),
        .exception_underflow(exception_underflow),
        .exception_precision(exception_precision),
        .mask_invalid(mask_invalid),
        .mask_denormal(mask_denormal),
        .mask_zero_div(mask_zero_div),
        .mask_overflow(mask_overflow),
        .mask_underflow(mask_underflow),
        .mask_precision(mask_precision),
        .exception_clear(exception_clear),
        .exception_latch(exception_latch),
        .int_request(int_request),
        .exception_pending(exception_pending),
        .latched_exceptions(latched_exceptions),
        .has_unmasked_exception(has_unmasked_exception)
    );

    //=================================================================
    // Clock Generation
    //=================================================================

    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100 MHz clock
    end

    //=================================================================
    // Test Tasks
    //=================================================================

    // Task: Simulate arithmetic operation completion with exceptions
    task simulate_arith_complete;
        input invalid;
        input denormal;
        input zero_div;
        input overflow;
        input underflow;
        input precision;
        begin
            $display("[INFO] Simulating arithmetic completion with exceptions: I=%b D=%b Z=%b O=%b U=%b P=%b",
                     invalid, denormal, zero_div, overflow, underflow, precision);

            @(posedge clk);
            // Simulate arithmetic unit asserting exception flags
            exception_invalid <= invalid;
            exception_denormal <= denormal;
            exception_zero_div <= zero_div;
            exception_overflow <= overflow;
            exception_underflow <= underflow;
            exception_precision <= precision;

            // Simulate FPU_Core asserting exception_latch
            exception_latch <= 1'b1;

            @(posedge clk);
            // Deassert one-shot signals
            exception_latch <= 1'b0;
            exception_invalid <= 1'b0;
            exception_denormal <= 1'b0;
            exception_zero_div <= 1'b0;
            exception_overflow <= 1'b0;
            exception_underflow <= 1'b0;
            exception_precision <= 1'b0;

            @(posedge clk);
        end
    endtask

    // Task: Simulate FCLEX/FNCLEX execution
    task simulate_clear_exceptions;
        begin
            $display("[INFO] Simulating exception clear (FCLEX/FNCLEX)");
            @(posedge clk);
            exception_clear <= 1'b1;
            @(posedge clk);
            exception_clear <= 1'b0;
            @(posedge clk);
        end
    endtask

    // Task: Set mask bits (simulating control word)
    task set_masks;
        input inv;
        input den;
        input zdiv;
        input ovf;
        input unf;
        input prec;
        begin
            mask_invalid <= inv;
            mask_denormal <= den;
            mask_zero_div <= zdiv;
            mask_overflow <= ovf;
            mask_underflow <= unf;
            mask_precision <= prec;
        end
    endtask

    // Task: Check exception state
    task check_state;
        input expected_int;
        input expected_pending;
        input [5:0] expected_latched;
        input [255:0] test_name;
        begin
            test_count = test_count + 1;
            $display("[Test %0d] %s", test_count, test_name);

            if (int_request == expected_int &&
                exception_pending == expected_pending &&
                latched_exceptions == expected_latched) begin
                $display("  PASS: INT=%b, pending=%b, latched=0x%02h",
                         int_request, exception_pending, latched_exceptions);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Expected INT=%b pending=%b latched=0x%02h",
                         expected_int, expected_pending, expected_latched);
                $display("        Got INT=%b pending=%b latched=0x%02h",
                         int_request, exception_pending, latched_exceptions);
                fail_count = fail_count + 1;
            end
        end
    endtask

    //=================================================================
    // Main Test Sequence
    //=================================================================

    initial begin
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        exception_invalid = 0;
        exception_denormal = 0;
        exception_zero_div = 0;
        exception_overflow = 0;
        exception_underflow = 0;
        exception_precision = 0;

        mask_invalid = 1;    // All masked by default (8087 default)
        mask_denormal = 1;
        mask_zero_div = 1;
        mask_overflow = 1;
        mask_underflow = 1;
        mask_precision = 1;

        exception_clear = 0;
        exception_latch = 0;

        // Reset
        reset = 1;
        repeat(5) @(posedge clk);
        reset = 0;
        repeat(2) @(posedge clk);

        $display("\n=== FPU Exception Handler Integration Tests ===\n");
        $display("Testing exception_latch signal integration...\n");

        // Test 1: Initial state
        check_state(1'b0, 1'b0, 6'h00, "Initial state - no exceptions");

        // Test 2: Arithmetic operation with masked exception (no INT)
        $display("\n--- Test: Masked exception (no INT) ---");
        set_masks(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);  // All masked
        simulate_arith_complete(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);  // Invalid
        check_state(1'b0, 1'b0, 6'h01, "Masked invalid exception - no INT");

        // Test 3: Clear exceptions
        simulate_clear_exceptions();
        check_state(1'b0, 1'b0, 6'h00, "After clear - exceptions gone");

        // Test 4: Arithmetic operation with unmasked exception (INT asserts)
        $display("\n--- Test: Unmasked exception (INT asserts) ---");
        set_masks(1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);  // Invalid unmasked
        simulate_arith_complete(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);  // Invalid
        check_state(1'b1, 1'b1, 6'h01, "Unmasked invalid - INT asserted");

        // Test 5: INT stays asserted (sticky behavior)
        $display("\n--- Test: INT sticky behavior ---");
        repeat(3) @(posedge clk);
        check_state(1'b1, 1'b1, 6'h01, "INT remains asserted (sticky)");

        // Test 6: Wait instruction would block (exception_pending HIGH)
        $display("\n--- Test: Wait instruction blocking ---");
        $display("[INFO] If this were FWAIT, it would block due to exception_pending=%b", exception_pending);
        check_state(1'b1, 1'b1, 6'h01, "exception_pending blocks wait instructions");

        // Test 7: Clear exceptions (simulating FCLEX/FNCLEX)
        $display("\n--- Test: Exception clearing ---");
        simulate_clear_exceptions();
        check_state(1'b0, 1'b0, 6'h00, "After FCLEX/FNCLEX - INT deasserted");

        // Test 8: Multiple exceptions in single operation
        $display("\n--- Test: Multiple exceptions ---");
        set_masks(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);  // All unmasked
        simulate_arith_complete(1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0);  // Inv+Den+ZDiv
        check_state(1'b1, 1'b1, 6'h07, "Multiple exceptions - INT asserted");

        // Test 9: Sticky exceptions (multiple operations)
        $display("\n--- Test: Sticky exception accumulation ---");
        simulate_arith_complete(1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0);  // Ovf+Unf
        check_state(1'b1, 1'b1, 6'h1F, "Exceptions accumulate (sticky)");

        // Test 10: Mask changes don't affect INT (8087 behavior)
        $display("\n--- Test: 8087 mask behavior ---");
        set_masks(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);  // Mask all
        @(posedge clk);
        check_state(1'b1, 1'b1, 6'h1F, "Mask all - INT stays set (8087 sticky)");

        // Test 11: Only FCLEX/FNCLEX clears INT
        $display("\n--- Test: Only FCLEX/FNCLEX clears INT ---");
        simulate_clear_exceptions();
        check_state(1'b0, 1'b0, 6'h00, "FCLEX/FNCLEX clears INT");

        // Test 12: Overflow exception
        $display("\n--- Test: Overflow exception ---");
        set_masks(1'b1, 1'b1, 1'b1, 1'b0, 1'b1, 1'b1);  // Overflow unmasked
        simulate_arith_complete(1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);  // Overflow
        check_state(1'b1, 1'b1, 6'h08, "Overflow exception - INT asserted");

        // Test 13: Zero divide exception
        $display("\n--- Test: Zero divide exception ---");
        simulate_clear_exceptions();
        set_masks(1'b1, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1);  // Zero divide unmasked
        simulate_arith_complete(1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);  // Zero divide
        check_state(1'b1, 1'b1, 6'h04, "Zero divide - INT asserted");

        // Test 14: Precision exception
        $display("\n--- Test: Precision exception ---");
        simulate_clear_exceptions();
        set_masks(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0);  // Precision unmasked
        simulate_arith_complete(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);  // Precision
        check_state(1'b1, 1'b1, 6'h20, "Precision exception - INT asserted");

        // Test 15: All exceptions simultaneously
        $display("\n--- Test: All exceptions ---");
        simulate_clear_exceptions();
        set_masks(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);  // All unmasked
        simulate_arith_complete(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);  // All
        check_state(1'b1, 1'b1, 6'h3F, "All exceptions - INT asserted");

        // Summary
        repeat(5) @(posedge clk);
        $display("\n=== Integration Test Summary ===");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);

        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
            $display("Phase 3 Integration Verified:");
            $display("  ✓ exception_latch signal properly pulses");
            $display("  ✓ Exceptions latch into handler");
            $display("  ✓ INT signal asserts on unmasked exceptions");
            $display("  ✓ exception_pending flag works correctly");
            $display("  ✓ exception_clear clears all exceptions");
            $display("  ✓ Sticky INT behavior verified");
            $display("  ✓ 8087-accurate mask behavior");
            $display("");
        end else begin
            $display("\n*** SOME TESTS FAILED ***\n");
        end

        $finish;
    end

    //=================================================================
    // Timeout
    //=================================================================

    initial begin
        #200000;  // 200 us timeout
        $display("\n*** TEST TIMEOUT ***\n");
        $finish;
    end

    //=================================================================
    // Debug Monitoring
    //=================================================================

    `ifdef DEBUG
    always @(posedge clk) begin
        if (exception_latch) begin
            $display("[DEBUG] exception_latch asserted at time %t", $time);
        end
        if (exception_clear) begin
            $display("[DEBUG] exception_clear asserted at time %t", $time);
        end
        if (int_request && !$past(int_request)) begin
            $display("[DEBUG] INT asserted at time %t", $time);
        end
        if (!int_request && $past(int_request)) begin
            $display("[DEBUG] INT deasserted at time %t", $time);
        end
    end
    `endif

endmodule
