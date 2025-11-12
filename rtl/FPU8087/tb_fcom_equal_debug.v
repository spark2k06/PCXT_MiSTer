`timescale 1ns / 1ps

module tb_fcom_equal_debug;

    reg clk, reset, execute;
    reg [7:0] instruction;
    reg [2:0] stack_index;
    reg [79:0] data_in;
    reg [31:0] int_data_in;
    reg [15:0] control_in;
    reg control_write;

    wire ready, error;
    wire [79:0] data_out;
    wire [15:0] status_out;

    localparam INST_FLD = 8'h20;
    localparam INST_FCOM = 8'h60;

    localparam FP_ONE = 80'h3FFF_8000000000000000;  // +1.0
    localparam FP_HALF = 80'h3FFE_8000000000000000;  // +0.5

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT
    FPU_Core dut (
        .clk(clk),
        .reset(reset),
        .execute(execute),
        .instruction(instruction),
        .stack_index(stack_index),
        .data_in(data_in),
        .int_data_in(int_data_in),
        .control_in(control_in),
        .control_write(control_write),
        .ready(ready),
        .error(error),
        .data_out(data_out),
        .status_out(status_out)
    );

    // Monitor arithmetic unit comparison outputs
    always @(posedge clk) begin
        if (dut.state == dut.STATE_EXECUTE && dut.current_inst == INST_FCOM) begin
            if (dut.arith_enable) begin
                $display("[%0t] FCOM: Arithmetic operation started", $time);
                $display("  operand_a (ST(0)) = 0x%020X", dut.arith_operand_a);
                $display("  operand_b (ST(i)) = 0x%020X", dut.arith_operand_b);
                $display("  operation = %d (should be 1 for SUB)", dut.arith_operation);
            end
            if (dut.arith_done) begin
                $display("[%0t] FCOM: Arithmetic done!", $time);
                $display("  cc_equal = %b", dut.arith_cc_equal);
                $display("  cc_less = %b", dut.arith_cc_less);
                $display("  cc_greater = %b", dut.arith_cc_greater);
                $display("  cc_unordered = %b", dut.arith_cc_unordered);
                $display("  Setting status codes:");
                $display("    status_c3 <= %b (arith_cc_equal)", dut.arith_cc_equal);
                $display("    status_c2 <= 0");
                $display("    status_c0 <= %b (arith_cc_less)", dut.arith_cc_less);
            end
        end
        if (dut.state == dut.STATE_STACK_OP && dut.current_inst == INST_FCOM) begin
            $display("[%0t] FCOM STATE_STACK_OP: Transitioning to DONE", $time);
        end
        if (dut.state == dut.STATE_DONE && dut.current_inst == INST_FCOM) begin
            $display("[%0t] FCOM STATE_DONE: ready=%b", $time, dut.ready);
            $display("  Final status_out = 0x%04X", status_out);
            $display("  C3=%b, C2=%b, C1=%b, C0=%b",
                     status_out[14], status_out[10], status_out[9], status_out[8]);
        end
    end

    // Test
    initial begin
        $dumpfile("fcom_equal_debug.vcd");
        $dumpvars(0, tb_fcom_equal_debug);

        reset = 1;
        execute = 0;
        instruction = 8'h00;
        stack_index = 3'd0;
        data_in = 80'd0;
        int_data_in = 32'd0;
        control_in = 16'h037F;
        control_write = 0;

        #20 reset = 0;
        #10;

        $display("\n========================================");
        $display("FCOM Equal/Less Debug Test");
        $display("========================================\n");

        // Test 1: Equal (1.0 == 1.0)
        $display("=== Test 1: Equal (1.0 == 1.0) ===");
        load_value(FP_ONE);
        load_value(FP_ONE);
        compare_values(3'd1);
        $display("Expected: C3=1, C2=0, C0=0 (equal)");
        $display("Actual:   C3=%b, C2=%b, C0=%b\n",
                 status_out[14], status_out[10], status_out[8]);

        // Reset stack
        #50;
        reset = 1;
        #20 reset = 0;
        #10;

        // Test 2: Less than (0.5 < 1.0)
        $display("=== Test 2: Less than (0.5 < 1.0) ===");
        load_value(FP_ONE);
        load_value(FP_HALF);
        compare_values(3'd1);
        $display("Expected: C3=0, C2=0, C0=1 (less than)");
        $display("Actual:   C3=%b, C2=%b, C0=%b\n",
                 status_out[14], status_out[10], status_out[8]);

        #100;
        $finish;
    end

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
        end
    endtask

    task compare_values;
        input [2:0] index;
        begin
            @(posedge clk);
            instruction = INST_FCOM;
            stack_index = index;
            execute = 1;
            @(posedge clk);
            execute = 0;
            wait(ready == 1);
            @(posedge clk);
        end
    endtask

endmodule
