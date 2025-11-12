// Copyright 2025, Waldo Alvarez, https://pipflow.com
/**
 * FPU_Core_Async.v
 *
 * Asynchronous FPU Core with Instruction Queue
 *
 * This module wraps FPU_Core and adds:
 * - 3-entry instruction queue for asynchronous operation
 * - BUSY signal generation (active HIGH, 8087-style)
 * - Queue flush on FINIT/FLDCW/exceptions
 *
 * Architecture:
 *   CPU → Instruction Queue → FPU_Core → Results
 *
 * Benefits:
 * - CPU can enqueue up to 3 instructions without waiting
 * - FPU executes queued instructions in background
 * - BUSY signal indicates pending work
 * - Queue flush ensures 8087-accurate behavior
 *
 * Date: 2025-11-10
 */

`timescale 1ns / 1ps

module FPU_Core_Async(
    input wire clk,
    input wire reset,

    // CPU Instruction interface
    input wire [7:0]  instruction,      // FPU instruction opcode
    input wire [2:0]  stack_index,      // Stack index (for ST(i) operands)
    input wire        execute,          // Start instruction execution
    output wire       ready,            // FPU ready for new instruction
    output wire       error,            // Exception occurred (unmasked)

    // Data interface
    input wire [79:0] data_in,          // Data input (for loads)
    output wire [79:0] data_out,        // Data output (for stores)
    input wire [31:0] int_data_in,      // Integer data input
    output wire [31:0] int_data_out,    // Integer data output

    // Memory operand format information (from decoder)
    input wire        has_memory_op,    // Instruction uses memory operand
    input wire [1:0]  operand_size,     // Memory operand size (0=word, 1=dword, 2=qword, 3=tbyte)
    input wire        is_integer,       // Memory operand is integer format
    input wire        is_bcd,           // Memory operand is BCD format

    // Control/Status interface
    input wire [15:0] control_in,       // Control word input
    input wire        control_write,    // Write control word
    output wire [15:0] status_out,      // Status word output
    output wire [15:0] control_out,     // Control word output
    output wire [15:0] tag_word_out,    // Tag word output

    // Asynchronous operation signals (8087-style)
    output wire       busy,             // BUSY (active HIGH, 8087-style)
    output wire       int_request       // INT signal (active HIGH, 8087-style)
);

    //=================================================================
    // Instruction Queue
    //=================================================================

    // Queue control signals
    reg queue_enqueue;
    reg queue_dequeue;
    reg queue_flush;

    // Queue status signals
    wire queue_full;
    wire queue_empty;
    wire [1:0] queue_count;

    // Queued instruction signals
    wire [7:0]  queued_instruction;
    wire [2:0]  queued_stack_index;
    wire        queued_has_memory_op;
    wire [1:0]  queued_operand_size;
    wire        queued_is_integer;
    wire        queued_is_bcd;
    wire [79:0] queued_data;

    FPU_Instruction_Queue instruction_queue (
        .clk(clk),
        .reset(reset),

        // Enqueue interface (from CPU)
        .enqueue(queue_enqueue),
        .instruction_in(instruction),
        .stack_index_in(stack_index),
        .has_memory_op_in(has_memory_op),
        .operand_size_in(operand_size),
        .is_integer_in(is_integer),
        .is_bcd_in(is_bcd),
        .data_in(data_in),
        .queue_full(queue_full),

        // Dequeue interface (to FPU_Core)
        .dequeue(queue_dequeue),
        .queue_empty(queue_empty),
        .instruction_out(queued_instruction),
        .stack_index_out(queued_stack_index),
        .has_memory_op_out(queued_has_memory_op),
        .operand_size_out(queued_operand_size),
        .is_integer_out(queued_is_integer),
        .is_bcd_out(queued_is_bcd),
        .data_out(queued_data),

        // Flush interface
        .flush_queue(queue_flush),
        .queue_count(queue_count)
    );

    //=================================================================
    // FPU Core
    //=================================================================

    // FPU Core control signals
    reg fpu_execute;
    wire fpu_ready;
    wire fpu_error;

    FPU_Core fpu_core (
        .clk(clk),
        .reset(reset),

        // Instruction interface (from queue)
        .instruction(queued_instruction),
        .stack_index(queued_stack_index),
        .execute(fpu_execute),
        .ready(fpu_ready),
        .error(fpu_error),

        // Data interface
        .data_in(queued_data),
        .data_out(data_out),
        .int_data_in(int_data_in),  // Pass through (immediate conversion)
        .int_data_out(int_data_out),

        // Memory operand format (from queue)
        .has_memory_op(queued_has_memory_op),
        .operand_size(queued_operand_size),
        .is_integer(queued_is_integer),
        .is_bcd(queued_is_bcd),

        // Control/Status interface
        .control_in(control_in),
        .control_write(control_write),
        .status_out(status_out),
        .control_out(control_out),
        .tag_word_out(tag_word_out),

        // Exception interface
        .int_request(int_request)
    );

    //=================================================================
    // Queue Control Logic
    //=================================================================

    // State machine for dequeue control
    localparam DEQUEUE_IDLE = 1'b0;
    localparam DEQUEUE_BUSY = 1'b1;

    reg dequeue_state;
    reg flush_pending;  // Track if executing instruction requires flush

    always @(posedge clk) begin
        if (reset) begin
            queue_enqueue <= 1'b0;
            queue_dequeue <= 1'b0;
            queue_flush <= 1'b0;
            fpu_execute <= 1'b0;
            dequeue_state <= DEQUEUE_IDLE;
            flush_pending <= 1'b0;
        end else begin
            // Default: deassert one-shot signals
            queue_enqueue <= 1'b0;
            queue_dequeue <= 1'b0;
            queue_flush <= 1'b0;
            fpu_execute <= 1'b0;

            // Enqueue logic: CPU wants to execute
            if (execute && !queue_full) begin
                queue_enqueue <= 1'b1;
            end

            // Dequeue state machine
            case (dequeue_state)
                DEQUEUE_IDLE: begin
                    // FPU is idle and queue has instructions - start next
                    if (fpu_ready && !queue_empty) begin
                        queue_dequeue <= 1'b1;
                        fpu_execute <= 1'b1;
                        dequeue_state <= DEQUEUE_BUSY;

                        // Check if this instruction requires queue flush after completion
                        // FINIT (0xF0), FNINIT (0xF6), FLDCW (0xF1)
                        if (queued_instruction == 8'hF0 ||
                            queued_instruction == 8'hF6 ||
                            queued_instruction == 8'hF1) begin
                            flush_pending <= 1'b1;
                        end
                    end
                end

                DEQUEUE_BUSY: begin
                    // Wait for FPU to complete (ready goes high)
                    if (fpu_ready) begin
                        dequeue_state <= DEQUEUE_IDLE;

                        // If this instruction required a flush, do it now
                        if (flush_pending) begin
                            queue_flush <= 1'b1;
                            flush_pending <= 1'b0;
                        end
                    end
                end
            endcase

            // Flush on exception (INT asserted) - immediate flush
            if (int_request) begin
                queue_flush <= 1'b1;
                flush_pending <= 1'b0;  // Clear any pending flush
            end

            // Reset dequeue state on flush
            if (queue_flush) begin
                dequeue_state <= DEQUEUE_IDLE;
            end
        end
    end

    //=================================================================
    // Output Signals
    //=================================================================

    // Ready: Can accept new instruction when queue not full
    assign ready = !queue_full;

    // Error: Pass through from FPU core
    assign error = fpu_error;

    // BUSY: Active HIGH when queue has work or FPU executing
    // 8087-style: BUSY (not BUSY# active low)
    assign busy = !queue_empty || (dequeue_state == DEQUEUE_BUSY);

    //=================================================================
    // Debug Info (for simulation)
    //=================================================================

    `ifdef SIMULATION
    always @(posedge clk) begin
        if (queue_enqueue) begin
            $display("[ASYNC] Enqueued instruction 0x%02h at time %t (queue count=%d)",
                     instruction, $time, queue_count + 1);
        end
        if (queue_dequeue) begin
            $display("[ASYNC] Dequeued instruction 0x%02h at time %t (queue count=%d)",
                     queued_instruction, $time, queue_count - 1);
        end
        if (queue_flush) begin
            $display("[ASYNC] Queue flushed at time %t (had %d entries)",
                     $time, queue_count);
        end
        if (busy && !$past(busy)) begin
            $display("[ASYNC] BUSY asserted at time %t", $time);
        end
        if (!busy && $past(busy)) begin
            $display("[ASYNC] BUSY deasserted at time %t", $time);
        end
    end
    `endif

endmodule
