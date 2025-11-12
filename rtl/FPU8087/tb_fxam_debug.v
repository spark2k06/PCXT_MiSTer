`timescale 1ns / 1ps

module tb_fxam_debug;

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
    localparam INST_FXAM = 8'h64;

    localparam FP_ZERO = 80'h0000_0000000000000000;
    localparam FP_ONE = 80'h3FFF_8000000000000000;

    wire cc_c3 = status_out[14];
    wire cc_c2 = status_out[10];
    wire cc_c1 = status_out[9];
    wire cc_c0 = status_out[8];

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

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

    // Monitor FXAM execution
    always @(posedge clk) begin
        if (dut.state == dut.STATE_EXECUTE && dut.current_inst == INST_FXAM) begin
            $display("[%0t] FXAM STATE_EXECUTE:", $time);
            $display("  temp_operand_a = 0x%020X", dut.temp_operand_a);
            $display("  Exponent [78:64] = 0x%04X (%d)", dut.temp_operand_a[78:64], dut.temp_operand_a[78:64]);
            $display("  Mantissa [63:0]  = 0x%016X", dut.temp_operand_a[63:0]);
            $display("  Sign [79] = %b", dut.temp_operand_a[79]);
        end
    end

    initial begin
        $dumpfile("fxam_debug.vcd");
        $dumpvars(0, tb_fxam_debug);

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
        $display("FXAM Debug Test");
        $display("========================================\n");

        // Test: FXAM with zero
        $display("=== Test 1: FXAM with zero ===");
        load_value(FP_ZERO);
        $display("After loading zero, ST(0) = 0x%020X", dut.st0);
        exec_fxam();
        $display("Result: C3=%b, C2=%b, C1=%b, C0=%b\n", cc_c3, cc_c2, cc_c1, cc_c0);

        // Test: FXAM with normal number
        $display("=== Test 2: FXAM with normal number (1.0) ===");
        load_value(FP_ONE);
        $display("After loading 1.0, ST(0) = 0x%020X", dut.st0);
        exec_fxam();
        $display("Result: C3=%b, C2=%b, C1=%b, C0=%b\n", cc_c3, cc_c2, cc_c1, cc_c0);

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

    task exec_fxam;
        begin
            @(posedge clk);
            instruction = INST_FXAM;
            execute = 1;
            @(posedge clk);
            execute = 0;
            wait(ready == 1);
            @(posedge clk);
        end
    endtask

endmodule
