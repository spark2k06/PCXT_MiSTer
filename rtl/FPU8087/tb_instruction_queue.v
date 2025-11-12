/**
 * tb_instruction_queue.v
 *
 * Testbench for FPU_Instruction_Queue module
 *
 * Tests:
 * 1. Basic enqueue/dequeue
 * 2. Full queue behavior
 * 3. Empty queue behavior
 * 4. Wraparound
 * 5. Flush operation
 * 6. Simultaneous enqueue/dequeue
 *
 * Date: 2025-11-10
 */

`timescale 1ns/1ps

module tb_instruction_queue;

    //=================================================================
    // Testbench Signals
    //=================================================================

    reg clk;
    reg reset;

    // Enqueue interface
    reg enqueue;
    reg [7:0] instruction_in;
    reg [2:0] stack_index_in;
    reg has_memory_op_in;
    reg [1:0] operand_size_in;
    reg is_integer_in;
    reg is_bcd_in;
    reg [79:0] data_in;
    wire queue_full;

    // Dequeue interface
    reg dequeue;
    wire queue_empty;
    wire [7:0] instruction_out;
    wire [2:0] stack_index_out;
    wire has_memory_op_out;
    wire [1:0] operand_size_out;
    wire is_integer_out;
    wire is_bcd_out;
    wire [79:0] data_out;

    // Flush interface
    reg flush_queue;

    // Status
    wire [1:0] queue_count;

    //=================================================================
    // Test Statistics
    //=================================================================

    integer test_count;
    integer pass_count;
    integer fail_count;

    //=================================================================
    // DUT Instantiation
    //=================================================================

    FPU_Instruction_Queue #(
        .QUEUE_DEPTH(3)
    ) dut (
        .clk(clk),
        .reset(reset),
        .enqueue(enqueue),
        .instruction_in(instruction_in),
        .stack_index_in(stack_index_in),
        .has_memory_op_in(has_memory_op_in),
        .operand_size_in(operand_size_in),
        .is_integer_in(is_integer_in),
        .is_bcd_in(is_bcd_in),
        .data_in(data_in),
        .queue_full(queue_full),
        .dequeue(dequeue),
        .queue_empty(queue_empty),
        .instruction_out(instruction_out),
        .stack_index_out(stack_index_out),
        .has_memory_op_out(has_memory_op_out),
        .operand_size_out(operand_size_out),
        .is_integer_out(is_integer_out),
        .is_bcd_out(is_bcd_out),
        .data_out(data_out),
        .flush_queue(flush_queue),
        .queue_count(queue_count)
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

    // Task: Enqueue an instruction
    task enqueue_instruction;
        input [7:0] inst;
        input [2:0] idx;
        input has_mem;
        input [1:0] size;
        input is_int;
        input is_bcd_val;
        input [79:0] data;
        begin
            @(posedge clk);
            enqueue <= 1'b1;
            instruction_in <= inst;
            stack_index_in <= idx;
            has_memory_op_in <= has_mem;
            operand_size_in <= size;
            is_integer_in <= is_int;
            is_bcd_in <= is_bcd_val;
            data_in <= data;
            @(posedge clk);
            enqueue <= 1'b0;
        end
    endtask

    // Task: Dequeue an instruction
    task dequeue_instruction;
        begin
            @(posedge clk);
            dequeue <= 1'b1;
            @(posedge clk);
            dequeue <= 1'b0;
        end
    endtask

    // Task: Flush queue
    task flush;
        begin
            @(posedge clk);
            flush_queue <= 1'b1;
            @(posedge clk);
            flush_queue <= 1'b0;
        end
    endtask

    // Task: Check status
    task check_status;
        input [1:0] expected_count;
        input expected_empty;
        input expected_full;
        input [255:0] test_name;
        begin
            test_count = test_count + 1;
            $display("[Test %0d] %s", test_count, test_name);

            if (queue_count == expected_count &&
                queue_empty == expected_empty &&
                queue_full == expected_full) begin
                $display("  PASS: count=%d, empty=%b, full=%b",
                         queue_count, queue_empty, queue_full);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Expected count=%d empty=%b full=%b, Got count=%d empty=%b full=%b",
                         expected_count, expected_empty, expected_full,
                         queue_count, queue_empty, queue_full);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Task: Check dequeued instruction
    task check_instruction;
        input [7:0] expected_inst;
        input [2:0] expected_idx;
        input [79:0] expected_data;
        input [255:0] test_name;
        begin
            test_count = test_count + 1;
            $display("[Test %0d] %s", test_count, test_name);

            if (instruction_out == expected_inst &&
                stack_index_out == expected_idx &&
                data_out == expected_data) begin
                $display("  PASS: inst=0x%02h, idx=%d, data=0x%h",
                         instruction_out, stack_index_out, data_out);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Expected inst=0x%02h idx=%d data=0x%h",
                         expected_inst, expected_idx, expected_data);
                $display("        Got inst=0x%02h idx=%d data=0x%h",
                         instruction_out, stack_index_out, data_out);
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

        enqueue = 0;
        instruction_in = 0;
        stack_index_in = 0;
        has_memory_op_in = 0;
        operand_size_in = 0;
        is_integer_in = 0;
        is_bcd_in = 0;
        data_in = 0;
        dequeue = 0;
        flush_queue = 0;

        // Reset
        reset = 1;
        repeat(5) @(posedge clk);
        reset = 0;
        repeat(2) @(posedge clk);

        $display("\n=== FPU Instruction Queue Tests ===\n");

        // Test 1: Initial state (empty)
        check_status(2'd0, 1'b1, 1'b0, "Initial state - empty queue");

        // Test 2: Enqueue one instruction
        enqueue_instruction(8'h20, 3'd0, 1'b0, 2'd0, 1'b0, 1'b0, 80'h12345678);
        @(posedge clk);
        check_status(2'd1, 1'b0, 1'b0, "After enqueue 1 - count=1");

        // Test 3: Check first instruction output
        check_instruction(8'h20, 3'd0, 80'h12345678, "Verify first instruction");

        // Test 4: Enqueue second instruction
        enqueue_instruction(8'h21, 3'd1, 1'b0, 2'd1, 1'b0, 1'b0, 80'h00AB_CDEF);
        @(posedge clk);
        check_status(2'd2, 1'b0, 1'b0, "After enqueue 2 - count=2");

        // Test 5: Enqueue third instruction (queue full)
        enqueue_instruction(8'h22, 3'd2, 1'b1, 2'd2, 1'b1, 1'b0, 80'hDEAD_BEEF);
        @(posedge clk);
        check_status(2'd3, 1'b0, 1'b1, "After enqueue 3 - queue full");

        // Test 6: Try to enqueue to full queue (should fail silently)
        enqueue_instruction(8'h23, 3'd3, 1'b0, 2'd0, 1'b0, 1'b0, 80'h99887766);
        @(posedge clk);
        check_status(2'd3, 1'b0, 1'b1, "Try enqueue to full - still full");

        // Test 7: Dequeue first instruction
        dequeue_instruction();
        @(posedge clk);
        check_status(2'd2, 1'b0, 1'b0, "After dequeue 1 - count=2");
        check_instruction(8'h21, 3'd1, 80'h00AB_CDEF, "Verify second instruction");

        // Test 8: Dequeue second instruction
        dequeue_instruction();
        @(posedge clk);
        check_status(2'd1, 1'b0, 1'b0, "After dequeue 2 - count=1");
        check_instruction(8'h22, 3'd2, 80'hDEAD_BEEF, "Verify third instruction");

        // Test 9: Enqueue while one entry present (test wraparound)
        enqueue_instruction(8'h30, 3'd5, 1'b0, 2'd0, 1'b0, 1'b0, 80'hCAFE_BABE);
        @(posedge clk);
        check_status(2'd2, 1'b0, 1'b0, "After enqueue (wraparound) - count=2");

        // Test 10: Flush queue
        flush();
        @(posedge clk);
        check_status(2'd0, 1'b1, 1'b0, "After flush - empty queue");

        // Test 11: Enqueue after flush
        enqueue_instruction(8'h40, 3'd0, 1'b0, 2'd0, 1'b0, 1'b0, 80'h11111111);
        @(posedge clk);
        check_status(2'd1, 1'b0, 1'b0, "After enqueue post-flush - count=1");
        check_instruction(8'h40, 3'd0, 80'h11111111, "Verify instruction after flush");

        // Test 12: Simultaneous enqueue and dequeue
        @(posedge clk);
        enqueue <= 1'b1;
        dequeue <= 1'b1;
        instruction_in <= 8'h50;
        stack_index_in <= 3'd6;
        data_in <= 80'h22222222;
        @(posedge clk);
        enqueue <= 1'b0;
        dequeue <= 1'b0;
        @(posedge clk);
        check_status(2'd1, 1'b0, 1'b0, "Simultaneous enq/deq - count unchanged");
        check_instruction(8'h50, 3'd6, 80'h22222222, "Verify simultaneous operation");

        // Test 13: Dequeue to empty
        dequeue_instruction();
        @(posedge clk);
        check_status(2'd0, 1'b1, 1'b0, "After dequeue to empty - empty queue");

        // Test 14: Try to dequeue from empty (should not crash)
        dequeue_instruction();
        @(posedge clk);
        check_status(2'd0, 1'b1, 1'b0, "Try dequeue from empty - still empty");

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
