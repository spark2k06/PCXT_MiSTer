// Copyright 2025, Waldo Alvarez, https://pipflow.com
/**
 * FPU_Instruction_Queue.v
 *
 * 8087-Style Instruction Queue (Control Unit)
 *
 * Based on Intel 8087 architecture with 3-stage pipeline:
 * - Stage 1: Instruction decode
 * - Stage 2: Address calculation / operand fetch
 * - Stage 3: Execution (in NEU)
 *
 * Design matches real 8087 Control Unit behavior:
 * - 3-entry FIFO queue
 * - Flush on FINIT, FLDCW, exceptions
 * - Parallel enqueue/dequeue
 *
 * Date: 2025-11-10
 */

module FPU_Instruction_Queue #(
    parameter QUEUE_DEPTH = 3  // 3 stages to match 8087 CU
)(
    input wire clk,
    input wire reset,

    // Enqueue interface (from CPU/decoder)
    input wire enqueue,
    input wire [7:0] instruction_in,
    input wire [2:0] stack_index_in,
    input wire has_memory_op_in,
    input wire [1:0] operand_size_in,
    input wire is_integer_in,
    input wire is_bcd_in,
    input wire [79:0] data_in,
    output wire queue_full,

    // Dequeue interface (to NEU)
    input wire dequeue,
    output wire queue_empty,
    output wire [7:0] instruction_out,
    output wire [2:0] stack_index_out,
    output wire has_memory_op_out,
    output wire [1:0] operand_size_out,
    output wire is_integer_out,
    output wire is_bcd_out,
    output wire [79:0] data_out,

    // Flush interface (on FINIT, FLDCW, exception)
    input wire flush_queue,

    // Status
    output wire [1:0] queue_count  // Number of entries in queue (0-3)
);

    //=================================================================
    // Queue Storage
    //=================================================================

    // FIFO storage for instruction queue
    // Each entry contains all information needed to execute the instruction
    reg [7:0]  inst_queue [0:QUEUE_DEPTH-1];
    reg [2:0]  index_queue [0:QUEUE_DEPTH-1];
    reg        has_mem_queue [0:QUEUE_DEPTH-1];
    reg [1:0]  op_size_queue [0:QUEUE_DEPTH-1];
    reg        is_int_queue [0:QUEUE_DEPTH-1];
    reg        is_bcd_queue [0:QUEUE_DEPTH-1];
    reg [79:0] data_queue [0:QUEUE_DEPTH-1];

    //=================================================================
    // Queue Pointers
    //=================================================================

    // Write pointer: where next instruction will be written
    // Read pointer: where next instruction will be read from
    // Count: number of valid entries in queue
    reg [1:0] write_ptr;  // 2 bits for 0-3 (QUEUE_DEPTH=3 needs 2 bits)
    reg [1:0] read_ptr;
    reg [1:0] count;

    //=================================================================
    // Status Signals
    //=================================================================

    assign queue_full = (count >= QUEUE_DEPTH);
    assign queue_empty = (count == 0);
    assign queue_count = count;

    //=================================================================
    // Output Signals (combinational read from queue head)
    //=================================================================

    assign instruction_out = queue_empty ? 8'h00 : inst_queue[read_ptr];
    assign stack_index_out = queue_empty ? 3'h0  : index_queue[read_ptr];
    assign has_memory_op_out = queue_empty ? 1'b0 : has_mem_queue[read_ptr];
    assign operand_size_out = queue_empty ? 2'h0  : op_size_queue[read_ptr];
    assign is_integer_out = queue_empty ? 1'b0 : is_int_queue[read_ptr];
    assign is_bcd_out = queue_empty ? 1'b0 : is_bcd_queue[read_ptr];
    assign data_out = queue_empty ? 80'h0 : data_queue[read_ptr];

    //=================================================================
    // Queue Control Logic
    //=================================================================

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            // Reset all pointers and counters
            write_ptr <= 2'd0;
            read_ptr <= 2'd0;
            count <= 2'd0;

            // Clear queue contents (not strictly necessary but good practice)
            for (i = 0; i < QUEUE_DEPTH; i = i + 1) begin
                inst_queue[i] <= 8'h00;
                index_queue[i] <= 3'h0;
                has_mem_queue[i] <= 1'b0;
                op_size_queue[i] <= 2'h0;
                is_int_queue[i] <= 1'b0;
                is_bcd_queue[i] <= 1'b0;
                data_queue[i] <= 80'h0;
            end

        end else if (flush_queue) begin
            // Flush queue: reset pointers but don't clear data
            // This matches 8087 behavior on FINIT/FLDCW/exception
            write_ptr <= 2'd0;
            read_ptr <= 2'd0;
            count <= 2'd0;

        end else begin
            // Normal operation: handle enqueue and dequeue

            // Enqueue operation (write to queue)
            if (enqueue && !queue_full) begin
                inst_queue[write_ptr] <= instruction_in;
                index_queue[write_ptr] <= stack_index_in;
                has_mem_queue[write_ptr] <= has_memory_op_in;
                op_size_queue[write_ptr] <= operand_size_in;
                is_int_queue[write_ptr] <= is_integer_in;
                is_bcd_queue[write_ptr] <= is_bcd_in;
                data_queue[write_ptr] <= data_in;

                // Advance write pointer with wraparound
                if (write_ptr == QUEUE_DEPTH - 1)
                    write_ptr <= 2'd0;
                else
                    write_ptr <= write_ptr + 1;
            end

            // Dequeue operation (read from queue)
            if (dequeue && !queue_empty) begin
                // Advance read pointer with wraparound
                if (read_ptr == QUEUE_DEPTH - 1)
                    read_ptr <= 2'd0;
                else
                    read_ptr <= read_ptr + 1;
            end

            // Update count based on enqueue/dequeue
            if (enqueue && !queue_full && !(dequeue && !queue_empty)) begin
                // Enqueue only: increment count
                count <= count + 1;
            end else if (dequeue && !queue_empty && !(enqueue && !queue_full)) begin
                // Dequeue only: decrement count
                count <= count - 1;
            end
            // If both enqueue and dequeue: count stays the same

        end
    end

    //=================================================================
    // Debug Info (for simulation)
    //=================================================================

    `ifdef SIMULATION
    always @(posedge clk) begin
        if (enqueue && queue_full) begin
            $display("[WARNING] Attempt to enqueue to full queue at time %t", $time);
        end
        if (dequeue && queue_empty) begin
            $display("[WARNING] Attempt to dequeue from empty queue at time %t", $time);
        end
        if (flush_queue && count > 0) begin
            $display("[INFO] Queue flushed with %d entries at time %t", count, $time);
        end
    end
    `endif

endmodule
