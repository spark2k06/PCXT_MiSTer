`timescale 1ns / 1ps

//=================================================================
// BCD Integration Debug Test
//
// Tests FBLD with detailed state machine monitoring
//=================================================================

module tb_bcd_debug;

    reg clk;
    reg reset;
    reg execute;
    reg [7:0] instruction;
    reg [2:0] stack_index;
    reg [79:0] data_in;
    reg [31:0] int_data_in;
    reg [15:0] control_in;
    reg control_write;

    wire ready;
    wire error;
    wire [79:0] data_out;
    wire [15:0] status_out;

    // Instruction opcodes
    localparam INST_FBLD  = 8'h36;  // Load BCD
    localparam INST_FST   = 8'h21;  // Store to read stack value

    // BCD test value: 1
    localparam BCD_1 = 80'h0_00_000000000000000001;

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
        .int_data_in(int_data_in),
        .control_in(control_in),
        .control_write(control_write),
        .ready(ready),
        .error(error),
        .data_out(data_out),
        .status_out(status_out)
    );

    // Monitor state changes
    always @(posedge clk) begin
        if (dut.state != dut.STATE_IDLE && dut.state != dut.STATE_DONE) begin
            $display("  [Time %0t] State=%0d, Inst=0x%02X", $time, dut.state, dut.current_inst);

            // Monitor BCD converter
            if (dut.bcd2bin_enable)
                $display("    BCD2BIN: enable=%b, done=%b, error=%b, out=0x%016X",
                         dut.bcd2bin_enable, dut.bcd2bin_done, dut.bcd2bin_error, dut.bcd2bin_binary_out);

            // Monitor arithmetic unit
            if (dut.arith_enable)
                $display("    ARITH: op=%0d, enable=%b, done=%b, uint64_in=0x%016X, result=0x%020X",
                         dut.arith_operation, dut.arith_enable, dut.arith_done,
                         dut.arith_uint64_in, dut.arith_result);

            // Monitor temp result
            if (dut.state == dut.STATE_WRITEBACK)
                $display("    WRITEBACK: temp_result=0x%020X", dut.temp_result);
        end
    end

    // Test sequence
    initial begin
        $dumpfile("bcd_debug.vcd");
        $dumpvars(0, tb_bcd_debug);

        // Initialize
        reset = 1;
        execute = 0;
        instruction = 8'h00;
        stack_index = 3'd0;
        data_in = 80'd0;
        int_data_in = 32'd0;
        control_in = 16'h037F;  // Default control word
        control_write = 0;

        #20 reset = 0;
        #10;

        $display("\n========================================");
        $display("BCD Integration Debug Test");
        $display("========================================\n");

        // Test: Load BCD 1
        $display("Test: FBLD 1");
        $display("  BCD Input: 0x%020X", BCD_1);

        @(posedge clk);
        data_in = BCD_1;
        instruction = INST_FBLD;
        execute = 1;
        @(posedge clk);
        execute = 0;

        // Wait for completion
        wait(ready == 1);
        @(posedge clk);

        $display("\n  Execution complete, reading ST(0)...\n");

        // Read ST(0)
        @(posedge clk);
        instruction = INST_FST;
        stack_index = 0;
        execute = 1;
        @(posedge clk);
        execute = 0;
        wait(ready == 1);
        @(posedge clk);

        $display("\n========================================");
        $display("Result: ST(0) = 0x%020X", data_out);
        $display("Expected:       0x3fff8000000000000000");
        if (data_out == 80'h3fff8000000000000000)
            $display("PASS");
        else
            $display("FAIL");
        $display("========================================\n");

        #100;
        $finish;
    end

endmodule
