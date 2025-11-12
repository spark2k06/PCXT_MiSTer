`timescale 1ns / 1ps

//=================================================================
// Simple FXCH (Exchange) Test
//=================================================================

module tb_fxch;

    reg clk;
    reg reset;
    reg execute;
    reg [7:0] instruction;
    reg [2:0] stack_index;
    reg [79:0] data_in;
    reg [15:0] control_in;
    reg control_write;

    wire ready;
    wire error;
    wire [79:0] data_out;
    wire [15:0] status_out;

    // Instruction opcodes
    localparam INST_FLD  = 8'h20;
    localparam INST_FST  = 8'h21;
    localparam INST_FXCH = 8'h23;

    // FP80 constants
    localparam FP80_1  = 80'h3FFF_8000000000000000;  // 1.0
    localparam FP80_2  = 80'h4000_8000000000000000;  // 2.0
    localparam FP80_3  = 80'h4000_C000000000000000;  // 3.0
    localparam FP80_4  = 80'h4001_8000000000000000;  // 4.0

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT instantiation
    FPU_Core dut (
        .clk(clk),
        .reset(reset),
        .execute(execute),
        .instruction(instruction),
        .stack_index(stack_index),
        .data_in(data_in),
        .int_data_in(32'd0),
        .control_in(control_in),
        .control_write(control_write),
        .ready(ready),
        .error(error),
        .data_out(data_out),
        .status_out(status_out)
    );

    // Test sequence
    initial begin
        $dumpfile("fxch_test.vcd");
        $dumpvars(0, tb_fxch);

        // Initialize
        reset = 1;
        execute = 0;
        instruction = 8'h00;
        stack_index = 3'd0;
        data_in = 80'd0;
        control_in = 16'h037F;  // Default control word
        control_write = 0;

        #20 reset = 0;
        #10;

        $display("\n========================================");
        $display("FXCH Test - Exchange Stack Registers");
        $display("========================================\n");

        // Load values onto stack: ST(0)=1.0, ST(1)=2.0, ST(2)=3.0, ST(3)=4.0
        $display("Step 1: Loading values onto stack");
        load_value(FP80_1); // ST(0) = 1.0
        load_value(FP80_2); // ST(0) = 2.0, ST(1) = 1.0
        load_value(FP80_3); // ST(0) = 3.0, ST(1) = 2.0, ST(2) = 1.0
        load_value(FP80_4); // ST(0) = 4.0, ST(1) = 3.0, ST(2) = 2.0, ST(3) = 1.0

        // Verify initial stack
        $display("\nInitial Stack:");
        read_st(0); // Should be 4.0
        read_st(1); // Should be 3.0
        read_st(2); // Should be 2.0
        read_st(3); // Should be 1.0

        // Test FXCH ST(0), ST(1)
        $display("\nTest 1: FXCH ST(0), ST(1)");
        exchange(1);
        read_st(0); // Should be 3.0 (was ST(1))
        read_st(1); // Should be 4.0 (was ST(0))

        // Test FXCH ST(0), ST(2)
        $display("\nTest 2: FXCH ST(0), ST(2)");
        exchange(2);
        read_st(0); // Should be 2.0 (was ST(2))
        read_st(2); // Should be 3.0 (was ST(0))

        // Test FXCH ST(0), ST(3)
        $display("\nTest 3: FXCH ST(0), ST(3)");
        exchange(3);
        read_st(0); // Should be 1.0 (was ST(3))
        read_st(3); // Should be 2.0 (was ST(0))

        #100;
        $display("\n========================================");
        $display("FXCH Test Complete");
        $display("========================================\n");
        $finish;
    end

    // Helper task: Load value
    task load_value;
        input [79:0] value;
        begin
            @(posedge clk);
            data_in = value;
            instruction = INST_FLD;
            execute = 1;
            @(posedge clk);
            execute = 0;
            wait(ready == 1);
            @(posedge clk);
            $display("  Loaded 0x%020X", value);
        end
    endtask

    // Helper task: Read ST(i)
    task read_st;
        input [2:0] index;
        begin
            @(posedge clk);
            instruction = INST_FST;
            stack_index = index;
            execute = 1;
            @(posedge clk);
            execute = 0;
            wait(ready == 1);
            @(posedge clk);
            $display("  ST(%0d) = 0x%020X", index, data_out);
        end
    endtask

    // Helper task: Exchange ST(0) with ST(i)
    task exchange;
        input [2:0] index;
        begin
            @(posedge clk);
            instruction = INST_FXCH;
            stack_index = index;
            execute = 1;
            @(posedge clk);
            execute = 0;
            wait(ready == 1);
            @(posedge clk);
            $display("  Exchanged ST(0) <-> ST(%0d)", index);
        end
    endtask

endmodule
