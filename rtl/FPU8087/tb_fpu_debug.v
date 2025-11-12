`timescale 1ns / 1ps

//=====================================================================
// FPU Core Debug Testbench
// Focused tests to debug specific issues
//=====================================================================

module tb_fpu_debug;

    reg clk, reset;
    always #5 clk = ~clk;

    reg [7:0] instruction;
    reg [2:0] stack_index;
    reg execute;
    wire ready;
    wire error;

    reg [79:0] data_in;
    wire [79:0] data_out;
    reg [31:0] int_data_in;
    wire [31:0] int_data_out;

    reg [15:0] control_in;
    reg control_write;
    wire [15:0] status_out;
    wire [15:0] control_out;
    wire [15:0] tag_word_out;

    // Instruction opcodes
    localparam INST_FADD = 8'h10;
    localparam INST_FADDP = 8'h11;
    localparam INST_FMUL = 8'h14;
    localparam INST_FILD32 = 8'h31;

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
        .int_data_in(int_data_in),
        .int_data_out(int_data_out),
        .control_in(control_in),
        .control_write(control_write),
        .status_out(status_out),
        .control_out(control_out),
        .tag_word_out(tag_word_out)
    );

    task exec_instruction;
        input [7:0] inst;
        input [2:0] idx;
        begin
            @(posedge clk);
            instruction = inst;
            stack_index = idx;
            execute = 1'b1;
            @(posedge clk);
            execute = 1'b0;
            wait(ready == 1'b1);
            @(posedge clk);
        end
    endtask

    task load_int32;
        input signed [31:0] value;
        begin
            int_data_in = value;
            exec_instruction(INST_FILD32, 3'd0);
        end
    endtask

    task display_stack;
        begin
            $display("Stack: ST(0)=%h, ST(1)=%h, SP=%0d",
                     dut.st0, dut.st1, dut.stack_pointer);
            $display("  temp_result=%h, temp_int32=%0d",
                     dut.temp_result, $signed(dut.temp_int32));
            $display("  Phys regs[5]=%h, regs[6]=%h, regs[7]=%h",
                     dut.register_stack.registers[5],
                     dut.register_stack.registers[6],
                     dut.register_stack.registers[7]);
        end
    endtask

    initial begin
        $display("========================================");
        $display("FPU Core Debug Test");
        $display("========================================\n");

        clk = 0;
        reset = 1;
        execute = 0;
        instruction = 8'h00;
        stack_index = 3'd0;
        int_data_in = 32'd0;
        control_in = 16'h037F;
        control_write = 0;

        #20 reset = 0;
        #20;

        //=====================================================
        // Debug Test 1: Simple multiply sequence (Test 4 scenario)
        //=====================================================
        $display("Debug Test 1: Multiply sequence");
        $display("------------------------------");

        load_int32(32'd42);
        display_stack();

        load_int32(32'd10);
        display_stack();

        $display("Before FADD:");
        display_stack();
        exec_instruction(INST_FADD, 3'd1);  // ST(0) = ST(0) + ST(1)
        $display("After FADD (expect ST(0)=52):");
        display_stack();

        $display("\n=== Before loading 2 ===");
        $display("arith_operation=%0d, arith_enable=%b", dut.arith_operation, dut.arith_enable);
        load_int32(32'd2);
        $display("\n=== After loading 2 ===");
        $display("arith_operation=%0d, arith_enable=%b, arith_done=%b",
                 dut.arith_operation, dut.arith_enable, dut.arithmetic_unit.done);
        $display("int32_to_fp_result=%h, int32_to_fp_done=%b",
                 dut.arithmetic_unit.int32_to_fp_result,
                 dut.arithmetic_unit.int32_to_fp_done);
        $display("After loading 2:");
        display_stack();

        $display("Before FMUL (should be 2*52=104):");
        $display("  ST(0)=%h (should be 2)", dut.st0);
        $display("  ST(1)=%h (should be 52)", dut.st1);
        exec_instruction(INST_FMUL, 3'd1);  // ST(0) = ST(0) * ST(1)
        $display("After FMUL:");
        display_stack();
        $display("");

        //=====================================================
        // Debug Test 2: FADDP sequence (Test 10 scenario)
        //=====================================================
        $display("\nDebug Test 2: FADDP sequence");
        $display("------------------------------");
        reset = 1;
        #20 reset = 0;
        #20;

        load_int32(32'd5);
        display_stack();

        load_int32(32'd7);
        $display("After loading 5 and 7:");
        display_stack();

        $display("Before FADDP (should compute 5+7=12):");
        $display("  ST(0)=%h (7)", dut.st0);
        $display("  ST(1)=%h (5)", dut.st1);
        exec_instruction(INST_FADDP, 3'd1);  // Add ST(0)+ST(1), pop
        $display("After FADDP:");
        display_stack();

        $display("\n========================================");
        $finish;
    end

    initial begin
        #100000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
