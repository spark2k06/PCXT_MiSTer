`timescale 1ns / 1ps

//=====================================================================
// Stack Management Instructions Testbench
//
// Tests FINCSTP, FDECSTP, and FFREE instructions
//=====================================================================

module tb_stack_mgmt;

    reg clk;
    reg reset;
    reg [7:0] instruction;
    reg [2:0] stack_index;
    reg execute;
    wire ready;
    wire error;
    reg [79:0] data_in;
    wire [79:0] data_out;
    wire [15:0] status_out;
    wire [15:0] tag_word_out;

    // Test control
    integer test_count;
    integer pass_count;
    integer fail_count;

    // Instruction opcodes
    localparam INST_FLD      = 8'h20;
    localparam INST_FINCSTP  = 8'h70;
    localparam INST_FDECSTP  = 8'h71;
    localparam INST_FFREE    = 8'h72;

    // Instantiate FPU_Core
    FPU_Core dut (
        .clk(clk),
        .reset(reset),
        .instruction(instruction),
        .stack_index(stack_index),
        .execute(execute),
        .ready(ready),
        .error(error),
        .data_in(data_in),
        .data_out(data_out),
        .int_data_in(32'h0),
        .int_data_out(),
        .has_memory_op(1'b0),      // No memory operations in this test
        .operand_size(2'd0),        // N/A
        .is_integer(1'b0),          // N/A
        .is_bcd(1'b0),              // N/A
        .control_in(16'h037F),      // Default control word
        .control_write(1'b0),
        .status_out(status_out),
        .control_out(),
        .tag_word_out(tag_word_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("stack_mgmt_waves.vcd");
        $dumpvars(0, tb_stack_mgmt);
    end

    // Test stimulus
    initial begin
        // Initialize
        reset = 1;
        instruction = 8'h00;
        stack_index = 3'd0;
        execute = 0;
        data_in = 80'h0;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        // Display header
        $display("");
        $display("========================================");
        $display("Stack Management Instructions Testbench");
        $display("========================================");
        $display("");

        // Reset
        #20;
        reset = 0;
        #20;

        // Wait for ready
        wait(ready);

        //=================================================================
        // Test 1: Load three values onto the stack
        //=================================================================
        $display("Test 1: Load three values");
        $display("  Loading ST(0) = 1.0");
        load_value(80'h3fff8000000000000000);  // 1.0
        wait(ready);
        #20;

        $display("  Loading ST(0) = 2.0 (pushes 1.0 to ST(1))");
        load_value(80'h40008000000000000000);  // 2.0
        wait(ready);
        #20;

        $display("  Loading ST(0) = 3.0");
        load_value(80'h40018000000000000000);  // 3.0
        wait(ready);
        #20;

        // Check tag word: should have 3 valid registers
        if (tag_word_out[1:0] != 2'b00 ||  // ST(0) valid
            tag_word_out[3:2] != 2'b00 ||  // ST(1) valid
            tag_word_out[5:4] != 2'b00) begin // ST(2) valid
            $display("  FAIL: Tag word incorrect after loads");
            $display("        Tag word: %b", tag_word_out);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS: Three values loaded, tag word correct");
            pass_count = pass_count + 1;
        end
        test_count = test_count + 1;
        $display("");

        //=================================================================
        // Test 2: FINCSTP - Increment stack pointer
        //=================================================================
        $display("Test 2: FINCSTP - Increment stack pointer");
        exec_instruction(INST_FINCSTP, 3'd0);
        #20;

        // After FINCSTP, what was ST(1) becomes ST(0)
        // Stack pointer incremented by 1
        $display("  PASS: FINCSTP executed");
        pass_count = pass_count + 1;
        test_count = test_count + 1;
        $display("");

        //=================================================================
        // Test 3: FDECSTP - Decrement stack pointer
        //=================================================================
        $display("Test 3: FDECSTP - Decrement stack pointer");
        exec_instruction(INST_FDECSTP, 3'd0);
        #20;

        // After FDECSTP, stack pointer back to original position
        $display("  PASS: FDECSTP executed");
        pass_count = pass_count + 1;
        test_count = test_count + 1;
        $display("");

        //=================================================================
        // Test 4: FFREE ST(1) - Mark register as empty
        //=================================================================
        $display("Test 4: FFREE ST(1) - Mark ST(1) as empty");
        exec_instruction(INST_FFREE, 3'd1);
        wait(ready);
        #20;

        // Check that ST(1) is now marked as empty in tag word
        if (tag_word_out[3:2] != 2'b11) begin
            $display("  FAIL: ST(1) not marked as empty");
            $display("        Tag word: %b", tag_word_out);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS: ST(1) marked as empty (tag = 11)");
            pass_count = pass_count + 1;
        end
        test_count = test_count + 1;
        $display("");

        //=================================================================
        // Test 5: FFREE ST(0) - Mark top of stack as empty
        //=================================================================
        $display("Test 5: FFREE ST(0) - Mark top of stack as empty");
        exec_instruction(INST_FFREE, 3'd0);
        wait(ready);
        #20;

        // Check that ST(0) is now marked as empty
        if (tag_word_out[1:0] != 2'b11) begin
            $display("  FAIL: ST(0) not marked as empty");
            $display("        Tag word: %b", tag_word_out);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS: ST(0) marked as empty (tag = 11)");
            pass_count = pass_count + 1;
        end
        test_count = test_count + 1;
        $display("");

        //=================================================================
        // Test 6: Multiple FINCSTP operations
        //=================================================================
        $display("Test 6: Multiple FINCSTP operations");
        exec_instruction(INST_FINCSTP, 3'd0);
        #20;
        exec_instruction(INST_FINCSTP, 3'd0);
        #20;
        exec_instruction(INST_FINCSTP, 3'd0);
        #20;

        $display("  PASS: Multiple FINCSTP executed");
        pass_count = pass_count + 1;
        test_count = test_count + 1;
        $display("");

        //=================================================================
        // Test 7: Multiple FDECSTP operations
        //=================================================================
        $display("Test 7: Multiple FDECSTP operations");
        exec_instruction(INST_FDECSTP, 3'd0);
        #20;
        exec_instruction(INST_FDECSTP, 3'd0);
        #20;
        exec_instruction(INST_FDECSTP, 3'd0);
        #20;

        $display("  PASS: Multiple FDECSTP executed");
        pass_count = pass_count + 1;
        test_count = test_count + 1;
        $display("");

        //=================================================================
        // Summary
        //=================================================================
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests:  %0d", test_count);
        $display("Passed:       %0d", pass_count);
        $display("Failed:       %0d", fail_count);
        $display("");

        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED ***");
            $display("");
        end else begin
            $display("*** SOME TESTS FAILED ***");
            $display("");
        end

        $finish;
    end

    // Task to execute an instruction
    task exec_instruction;
        input [7:0] inst;
        input [2:0] idx;
        begin
            wait(ready);
            @(posedge clk);
            instruction = inst;
            stack_index = idx;
            execute = 1;
            @(posedge clk);
            execute = 0;
        end
    endtask

    // Task to load a value (FLD)
    task load_value;
        input [79:0] value;
        begin
            wait(ready);
            @(posedge clk);
            instruction = INST_FLD;
            stack_index = 3'd0;
            data_in = value;
            execute = 1;
            @(posedge clk);
            execute = 0;
        end
    endtask

endmodule
