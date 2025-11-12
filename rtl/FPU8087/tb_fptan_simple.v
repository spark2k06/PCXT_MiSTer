`timescale 1ns / 1ps

module tb_fptan_simple;

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
    localparam INST_FPTAN = 8'h54;
    localparam FP_ZERO = 80'h0000_0000000000000000;

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

    // Monitor
    always @(posedge clk) begin
        if (dut.state == dut.STATE_EXECUTE && dut.current_inst == INST_FPTAN) begin
            $display("[%0t] FPTAN EXECUTE: arith_operation=%d, arith_enable=%b, arith_done=%b",
                     $time, dut.arith_operation, dut.arith_enable, dut.arith_done);
            if (dut.arith_done) begin
                $display("[%0t]   arith_result=0x%020X", $time, dut.arith_result);
                $display("[%0t]   arith_result_secondary=0x%020X", $time, dut.arith_result_secondary);
                $display("[%0t]   arith_has_secondary=%b", $time, dut.arith_has_secondary);
            end
        end
        if (dut.state == dut.STATE_WRITEBACK && dut.current_inst == INST_FPTAN) begin
            $display("[%0t] FPTAN WRITEBACK: temp_result=0x%020X, temp_result_secondary=0x%020X",
                     $time, dut.temp_result, dut.temp_result_secondary);
        end
        if (dut.state == dut.STATE_STACK_OP && dut.current_inst == INST_FPTAN) begin
            $display("[%0t] FPTAN STACK_OP: has_secondary_result=%b", $time, dut.has_secondary_result);
        end
    end

    initial begin
        $dumpfile("fptan_simple.vcd");
        $dumpvars(0, tb_fptan_simple);

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

        $display("\n=== Testing FPTAN with 0 ===");

        // Load 0
        @(posedge clk);
        data_in = FP_ZERO;
        instruction = INST_FLD;
        execute = 1;
        @(posedge clk);
        execute = 0;
        wait(ready == 1);
        @(posedge clk);
        $display("Loaded 0, ST(0)=0x%020X", dut.st0);

        // FPTAN
        @(posedge clk);
        instruction = INST_FPTAN;
        execute = 1;
        @(posedge clk);
        execute = 0;
        wait(ready == 1);
        @(posedge clk);

        $display("\nResult:");
        $display("  ST(0) = 0x%020X (should be 1.0)", dut.st0);
        $display("  ST(1) = 0x%020X (should be 0.0)", dut.st1);

        #100;
        $finish;
    end

endmodule
