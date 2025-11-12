`timescale 1ns / 1ps

//=====================================================================
// Debug Testbench for FSTP Issue
//
// Tests basic constant loading and FSTP to identify stack read issue
//=====================================================================

module tb_fstp_debug;

    reg clk, reset;
    reg [7:0] instruction;
    reg [2:0] stack_index;
    reg execute;
    wire ready, error;
    reg [79:0] data_in;
    wire [79:0] data_out;
    reg [31:0] int_data_in;
    wire [31:0] int_data_out;
    reg has_memory_op;
    reg [1:0] operand_size;
    reg is_integer, is_bcd;
    reg [15:0] control_in;
    reg control_write;
    wire [15:0] status_out, control_out, tag_word_out;

    localparam INST_FLD1  = 8'h80;
    localparam INST_FLDZ  = 8'h81;
    localparam INST_FLDPI = 8'h82;
    localparam INST_FSTP  = 8'h22;

    FPU_Core uut (
        .clk(clk),
        .reset(reset),
        .instruction(instruction),
        .stack_index(stack_index),
        .execute(execute),
        .ready(ready),
        .error(error),
        .data_in(data_in),
        .data_out(data_out),
        .int_data_in(int_data_in),
        .int_data_out(int_data_out),
        .has_memory_op(has_memory_op),
        .operand_size(operand_size),
        .is_integer(is_integer),
        .is_bcd(is_bcd),
        .control_in(control_in),
        .control_write(control_write),
        .status_out(status_out),
        .control_out(control_out),
        .tag_word_out(tag_word_out)
    );

    always #5 clk = ~clk;

    task exec_inst;
        input [7:0] inst;
        input mem_op;
        begin
            @(posedge clk);
            instruction = inst;
            has_memory_op = mem_op;
            execute = 1'b1;
            @(posedge clk);
            execute = 1'b0;
            wait (ready);
            @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("tb_fstp_debug.vcd");
        $dumpvars(0, tb_fstp_debug);

        // Initialize
        clk = 0;
        reset = 1;
        execute = 0;
        instruction = 0;
        stack_index = 0;
        data_in = 0;
        int_data_in = 0;
        has_memory_op = 0;
        operand_size = 2'd3;  // 80-bit
        is_integer = 0;
        is_bcd = 0;
        control_in = 16'h037F;
        control_write = 0;

        repeat(3) @(posedge clk);
        reset = 0;
        @(posedge clk);

        $display("\n=== FSTP Debug Test ===\n");

        // Test 1: FLD1 → FSTP
        $display("Test 1: FLD1 (push +1.0)");
        exec_inst(INST_FLD1, 1'b0);  // No memory operand
        $display("  After FLD1: ST(0) should be +1.0");
        $display("  Stack register 0: %h", uut.register_stack.st0);

        $display("\nTest 1b: FSTP (store ST(0))");
        exec_inst(INST_FSTP, 1'b1);  // Memory operand
        $display("  data_out = %h", data_out);
        $display("  Expected = 3FFF8000000000000000");
        if (data_out == 80'h3FFF8000000000000000)
            $display("  ✓ PASS");
        else
            $display("  ✗ FAIL");

        // Test 2: FLDPI → FSTP
        $display("\nTest 2: FLDPI (push π)");
        exec_inst(INST_FLDPI, 1'b0);
        $display("  After FLDPI: ST(0) should be π");
        $display("  Stack register 0: %h", uut.register_stack.st0);

        $display("\nTest 2b: FSTP (store ST(0))");
        exec_inst(INST_FSTP, 1'b1);
        $display("  data_out = %h", data_out);
        $display("  Expected = 4000C90FDAA22168C235");
        if (data_out == 80'h4000C90FDAA22168C235)
            $display("  ✓ PASS");
        else
            $display("  ✗ FAIL");

        // Test 3: FLDZ → FSTP
        $display("\nTest 3: FLDZ (push 0.0)");
        exec_inst(INST_FLDZ, 1'b0);
        $display("  After FLDZ: ST(0) should be 0.0");
        $display("  Stack register 0: %h", uut.register_stack.st0);

        $display("\nTest 3b: FSTP (store ST(0))");
        exec_inst(INST_FSTP, 1'b1);
        $display("  data_out = %h", data_out);
        $display("  Expected = 00000000000000000000");
        if (data_out == 80'h00000000000000000000)
            $display("  ✓ PASS");
        else
            $display("  ✗ FAIL");

        #100;
        $display("\n=== Test Complete ===\n");
        $finish;
    end

    initial begin
        #10000;
        $display("\n❌ TIMEOUT!");
        $finish;
    end

endmodule
