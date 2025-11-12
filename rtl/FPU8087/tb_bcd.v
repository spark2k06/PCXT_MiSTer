`timescale 1ns / 1ps

//=================================================================
// BCD Conversion Test
//
// Tests FBLD (Load BCD) and FBSTP (Store BCD and Pop)
//=================================================================

module tb_bcd;

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
    localparam INST_FBSTP = 8'h37;  // Store BCD and pop
    localparam INST_FST   = 8'h21;  // Store to read stack value

    // BCD test values (18-digit packed BCD)
    // Format: [79:sign][78:72:unused][71:0:18 BCD digits]

    // Test 1: 0 (simplest case)
    localparam BCD_0 = 80'h0_00_000000000000000000;

    // Test 2: 1
    localparam BCD_1 = 80'h0_00_000000000000000001;

    // Test 3: 123
    localparam BCD_123 = 80'h0_00_000000000000000123;

    // Test 4: -456 (bit 79 set for negative)
    localparam BCD_NEG456 = 80'h80000000000000000456;

    // Test 5: Large number: 999,999,999,999,999,999 (max 18 digits)
    localparam BCD_MAX = 80'h0_00_999999999999999999;

    // Expected FP80 values (for reference)
    localparam FP80_0   = 80'h0000_0000000000000000;  // 0.0
    localparam FP80_1   = 80'h3FFF_8000000000000000;  // 1.0
    localparam FP80_123 = 80'h4005_F600000000000000;  // 123.0

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

    // Test sequence
    initial begin
        $dumpfile("bcd_test.vcd");
        $dumpvars(0, tb_bcd);

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
        $display("BCD Conversion Test");
        $display("========================================\n");

        // Test 1: Load BCD 0
        $display("Test 1: FBLD 0");
        fbld_value(BCD_0);
        read_st(0);
        if (data_out == FP80_0)
            $display("  PASS: 0 → FP80 correct");
        else
            $display("  FAIL: Expected %h, got %h", FP80_0, data_out);

        // Test 2: Load BCD 1
        $display("\nTest 2: FBLD 1");
        fbld_value(BCD_1);
        read_st(0);
        if (data_out == FP80_1)
            $display("  PASS: 1 → FP80 correct");
        else
            $display("  FAIL: Expected %h, got %h", FP80_1, data_out);

        // Test 3: Load BCD 123
        $display("\nTest 3: FBLD 123");
        fbld_value(BCD_123);
        read_st(0);
        if (data_out == FP80_123)
            $display("  PASS: 123 → FP80 correct");
        else
            $display("  FAIL: Expected %h, got %h", FP80_123, data_out);

        // Test 4: Load BCD -456
        $display("\nTest 4: FBLD -456");
        fbld_value(BCD_NEG456);
        read_st(0);
        $display("  Result: %h (sign=%b)", data_out, data_out[79]);
        if (data_out[79] == 1'b1)
            $display("  PASS: Sign bit correct (negative)");
        else
            $display("  FAIL: Sign bit should be 1 (negative)");

        // Test 5: Round-trip test (FBLD → FBSTP)
        $display("\nTest 5: Round-trip BCD → FP80 → BCD");
        fbld_value(BCD_123);
        fbstp_value();
        $display("  Original BCD: %h", BCD_123);
        $display("  After roundtrip: %h", data_out);
        if (data_out == BCD_123)
            $display("  PASS: Round-trip successful");
        else
            $display("  FAIL: Round-trip mismatch");

        #100;
        $display("\n========================================");
        $display("BCD Test Complete");
        $display("========================================\n");
        $finish;
    end

    // Helper task: Load BCD value
    task fbld_value;
        input [79:0] bcd_value;
        begin
            @(posedge clk);
            data_in = bcd_value;
            instruction = INST_FBLD;
            execute = 1;
            @(posedge clk);
            execute = 0;
            wait(ready == 1);
            @(posedge clk);
            $display("  Loaded BCD 0x%020X", bcd_value);
        end
    endtask

    // Helper task: Store BCD value (and pop)
    task fbstp_value;
        begin
            @(posedge clk);
            instruction = INST_FBSTP;
            execute = 1;
            @(posedge clk);
            execute = 0;
            wait(ready == 1);
            @(posedge clk);
            $display("  Stored BCD 0x%020X", data_out);
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

endmodule
