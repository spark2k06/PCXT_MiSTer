`timescale 1ns / 1ps

module tb_fcom_debug;

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
    localparam INST_FST  = 8'h22;

    localparam FP_ONE = 80'h3FFF_8000000000000000;  // +1.0
    localparam FP_TWO = 80'h4000_8000000000000000;  // +2.0

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
        if (dut.state == dut.STATE_EXECUTE) begin
            $display("[%0t] STATE_EXECUTE: inst=0x%02X, current_inst=0x%02X, data_in=0x%020X, temp_result=0x%020X",
                     $time, instruction, dut.current_inst, data_in, dut.temp_result);
        end
        if (dut.state == dut.STATE_WRITEBACK) begin
            $display("[%0t] STATE_WRITEBACK: temp_result=0x%020X",
                     $time, dut.temp_result);
        end
        if (dut.state == dut.STATE_STACK_OP) begin
            $display("[%0t] STATE_STACK_OP: inst=0x%02X, push=%b, write_en=%b, write_reg=%d, data_in=0x%020X, temp_result=0x%020X",
                     $time, dut.current_inst, dut.stack_push, dut.stack_write_enable,
                     dut.stack_write_reg, dut.stack_data_in, dut.temp_result);
        end
        if (dut.state == dut.STATE_DECODE) begin
            $display("[%0t] STATE_DECODE: st0=0x%020X, stack_read_data=0x%020X",
                     $time, dut.st0, dut.stack_read_data);
        end
        if (dut.state == dut.STATE_EXECUTE && dut.current_inst == INST_FCOM) begin
            $display("[%0t] STATE_EXECUTE FCOM: temp_a=0x%020X, temp_b=0x%020X",
                     $time, dut.temp_operand_a, dut.temp_operand_b);
            if (dut.arith_done) begin
                $display("[%0t]   arith_done! cc_equal=%b, cc_less=%b, cc_greater=%b, cc_unordered=%b",
                         $time, dut.arith_cc_equal, dut.arith_cc_less,
                         dut.arith_cc_greater, dut.arith_cc_unordered);
            end
        end
    end

    // Test
    initial begin
        $dumpfile("fcom_debug.vcd");
        $dumpvars(0, tb_fcom_debug);

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
        $display("FCOM Debug Test");
        $display("========================================\n");

        // Load 1.0
        $display("Loading 1.0");
        @(posedge clk);
        data_in = FP_ONE;
        instruction = INST_FLD;
        execute = 1;
        @(posedge clk);
        execute = 0;
        wait(ready == 1);
        @(posedge clk);
        $display("Loaded 1.0\n");

        // Load 2.0
        $display("Loading 2.0");
        @(posedge clk);
        data_in = FP_TWO;
        instruction = INST_FLD;
        execute = 1;
        @(posedge clk);
        execute = 0;
        wait(ready == 1);
        @(posedge clk);
        $display("Loaded 2.0\n");

        // Compare ST(0)=2.0 with ST(1)=1.0
        $display("Comparing ST(0)=2.0 with ST(1)=1.0");
        @(posedge clk);
        instruction = INST_FCOM;
        stack_index = 3'd1;
        execute = 1;
        @(posedge clk);
        execute = 0;
        wait(ready == 1);
        @(posedge clk);

        $display("\nResult: C3=%b, C2=%b, C0=%b",
                 status_out[14], status_out[10], status_out[8]);
        $display("Expected: C3=0, C2=0, C0=0 (2.0 > 1.0)\n");

        #100;
        $finish;
    end

endmodule
