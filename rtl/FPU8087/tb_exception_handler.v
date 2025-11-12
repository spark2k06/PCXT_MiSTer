/**
 * tb_exception_handler.v
 *
 * Testbench for FPU_Exception_Handler module
 *
 * Tests:
 * 1. Exception latching
 * 2. INT assertion on unmasked exceptions
 * 3. INT not asserted on masked exceptions
 * 4. Exception clearing (FCLEX)
 * 5. Sticky exception bits
 * 6. Multiple simultaneous exceptions
 * 7. Mask changes after exception
 * 8. Priority handling
 *
 * Date: 2025-11-10
 */

`timescale 1ns/1ps

module tb_exception_handler;

    //=================================================================
    // Testbench Signals
    //=================================================================

    reg clk;
    reg reset;

    // Exception inputs
    reg exception_invalid;
    reg exception_denormal;
    reg exception_zero_div;
    reg exception_overflow;
    reg exception_underflow;
    reg exception_precision;

    // Mask bits
    reg mask_invalid;
    reg mask_denormal;
    reg mask_zero_div;
    reg mask_overflow;
    reg mask_underflow;
    reg mask_precision;

    // Control
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

    FPU_Exception_Handler dut(
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

    // Task: Apply exception and latch
    task apply_exception;
        input invalid;
        input denormal;
        input zero_div;
        input overflow;
        input underflow;
        input precision;
        begin
            @(posedge clk);
            exception_invalid <= invalid;
            exception_denormal <= denormal;
            exception_zero_div <= zero_div;
            exception_overflow <= overflow;
            exception_underflow <= underflow;
            exception_precision <= precision;
            exception_latch <= 1'b1;
            @(posedge clk);
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

    // Task: Set masks
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

    // Task: Clear exceptions
    task clear_exceptions;
        begin
            @(posedge clk);
            exception_clear <= 1'b1;
            @(posedge clk);
            exception_clear <= 1'b0;
            @(posedge clk);
        end
    endtask

    // Task: Check INT and exception state
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

        $display("\n=== FPU Exception Handler Tests ===\n");

        // Test 1: Initial state (no exceptions)
        check_state(1'b0, 1'b0, 6'h00, "Initial state - no exceptions");

        // Test 2: Masked exception (should latch but not assert INT)
        set_masks(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);  // All masked
        apply_exception(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);  // Invalid
        check_state(1'b0, 1'b0, 6'h01, "Masked invalid - no INT");

        // Test 3: Clear masked exception
        clear_exceptions();
        check_state(1'b0, 1'b0, 6'h00, "After clear - exceptions gone");

        // Test 4: Unmasked exception (should latch and assert INT)
        set_masks(1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);  // Invalid unmasked
        apply_exception(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);  // Invalid
        check_state(1'b1, 1'b1, 6'h01, "Unmasked invalid - INT asserted");

        // Test 5: INT remains asserted until cleared
        repeat(3) @(posedge clk);
        check_state(1'b1, 1'b1, 6'h01, "INT stays asserted");

        // Test 6: Clear exception deasserts INT
        clear_exceptions();
        check_state(1'b0, 1'b0, 6'h00, "After clear - INT deasserted");

        // Test 7: Multiple masked exceptions
        set_masks(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);  // All masked
        apply_exception(1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0);  // Inv+Den+ZDiv
        check_state(1'b0, 1'b0, 6'h07, "Multiple masked - no INT");

        // Test 8: Unmask exception after latching - 8087 behavior
        // In real 8087, INT only asserts when exception OCCURS, not on mask change
        // So just unmasking a latched masked exception does NOT assert INT
        set_masks(1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);  // Invalid unmasked
        @(posedge clk);
        check_state(1'b0, 1'b0, 6'h07, "Unmask after latch - no INT (8087 behavior)");

        // Test 9: Clear and test another exception type (overflow)
        clear_exceptions();
        set_masks(1'b1, 1'b1, 1'b1, 1'b0, 1'b1, 1'b1);  // Overflow unmasked
        apply_exception(1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);  // Overflow
        check_state(1'b1, 1'b1, 6'h08, "Unmasked overflow - INT asserted");

        // Test 10: Sticky exceptions (multiple latch cycles)
        clear_exceptions();
        set_masks(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);  // All unmasked
        apply_exception(1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);  // Invalid
        check_state(1'b1, 1'b1, 6'h01, "First exception");

        apply_exception(1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);  // Zero divide
        check_state(1'b1, 1'b1, 6'h05, "Sticky - both exceptions present");

        // Test 11: Precision exception (lowest priority)
        clear_exceptions();
        set_masks(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0);  // Only precision unmasked
        apply_exception(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1);  // Precision
        check_state(1'b1, 1'b1, 6'h20, "Unmasked precision - INT asserted");

        // Test 12: All exceptions simultaneously
        clear_exceptions();
        set_masks(1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);  // All unmasked
        apply_exception(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);  // All exceptions
        check_state(1'b1, 1'b1, 6'h3F, "All exceptions - INT asserted");

        // Test 13: Mask all after exceptions latched - 8087 behavior
        // In real 8087, INT is sticky - once set, stays set until FCLEX
        // Masking doesn't clear INT
        set_masks(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);  // Mask all
        @(posedge clk);
        check_state(1'b1, 1'b1, 6'h3F, "All masked - INT stays set (sticky)");

        // Test 14: Unmask after masking - INT already set, stays set
        set_masks(1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);  // Unmask invalid
        @(posedge clk);
        check_state(1'b1, 1'b1, 6'h3F, "Unmask - INT still set (never cleared)");

        // Test 15: Denormal exception
        clear_exceptions();
        set_masks(1'b1, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1);  // Denormal unmasked
        apply_exception(1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);  // Denormal
        check_state(1'b1, 1'b1, 6'h02, "Unmasked denormal - INT asserted");

        // Test 16: Underflow exception
        clear_exceptions();
        set_masks(1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b1);  // Underflow unmasked
        apply_exception(1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);  // Underflow
        check_state(1'b1, 1'b1, 6'h10, "Unmasked underflow - INT asserted");

        // Summary
        repeat(5) @(posedge clk);
        $display("\n=== Test Summary ===");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);

        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
        end else begin
            $display("\n*** SOME TESTS FAILED ***\n");
        end

        $finish;
    end

    //=================================================================
    // Timeout
    //=================================================================

    initial begin
        #100000;  // 100 us timeout
        $display("\n*** TEST TIMEOUT ***\n");
        $finish;
    end

endmodule
