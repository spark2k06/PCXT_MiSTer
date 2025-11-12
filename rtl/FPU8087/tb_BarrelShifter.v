`timescale 1ns / 1ps

//=====================================================================
// Testbench for Barrel Shifter
//
// Tests all three barrel shifter variants:
// 1. BarrelShifter64 - 64-bit combinational shifter
// 2. BarrelShifter80 - 80-bit combinational shifter
// 3. BarrelShifter64_Pipelined - 64-bit pipelined shifter
//
// Verifies:
// - Left shifts (logical)
// - Right shifts (logical)
// - Right shifts (arithmetic/sign-extended)
// - Various shift amounts from 0 to max
//=====================================================================

module tb_BarrelShifter;

    // Clock and reset for pipelined version
    reg clk;
    reg reset;

    // Test signals for 64-bit shifter
    reg [63:0] data_in_64;
    reg [5:0] shift_amount_64;
    reg shift_direction_64;
    reg arithmetic_64;
    wire [63:0] data_out_64;

    // Test signals for 80-bit shifter
    reg [79:0] data_in_80;
    reg [6:0] shift_amount_80;
    reg shift_direction_80;
    reg arithmetic_80;
    wire [79:0] data_out_80;

    // Test signals for pipelined shifter
    reg [63:0] data_in_pipe;
    reg [5:0] shift_amount_pipe;
    reg shift_direction_pipe;
    reg arithmetic_pipe;
    wire [63:0] data_out_pipe;

    // Test counters
    integer test_passed;
    integer test_failed;
    integer i;

    // Instantiate the barrel shifters
    BarrelShifter64 dut_64 (
        .data_in(data_in_64),
        .shift_amount(shift_amount_64),
        .shift_direction(shift_direction_64),
        .arithmetic(arithmetic_64),
        .data_out(data_out_64)
    );

    BarrelShifter80 dut_80 (
        .data_in(data_in_80),
        .shift_amount(shift_amount_80),
        .shift_direction(shift_direction_80),
        .arithmetic(arithmetic_80),
        .data_out(data_out_80)
    );

    BarrelShifter64_Pipelined dut_pipe (
        .clk(clk),
        .reset(reset),
        .data_in(data_in_pipe),
        .shift_amount(shift_amount_pipe),
        .shift_direction(shift_direction_pipe),
        .arithmetic(arithmetic_pipe),
        .data_out(data_out_pipe)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test sequence
    initial begin
        $dumpfile("tb_BarrelShifter.vcd");
        $dumpvars(0, tb_BarrelShifter);

        test_passed = 0;
        test_failed = 0;

        $display("\n========================================");
        $display("Barrel Shifter Testbench");
        $display("========================================\n");

        // Initialize
        reset = 1;
        data_in_64 = 64'h0;
        shift_amount_64 = 6'b0;
        shift_direction_64 = 1'b0;
        arithmetic_64 = 1'b0;
        data_in_80 = 80'h0;
        shift_amount_80 = 7'b0;
        shift_direction_80 = 1'b0;
        arithmetic_80 = 1'b0;
        data_in_pipe = 64'h0;
        shift_amount_pipe = 6'b0;
        shift_direction_pipe = 1'b0;
        arithmetic_pipe = 1'b0;

        #20;
        reset = 0;
        #10;

        //=============================================================
        // Test 64-bit Barrel Shifter
        //=============================================================
        $display("Testing 64-bit Barrel Shifter");
        $display("========================================\n");

        //-------------------------------------------------------------
        // Test 1: No shift (shift by 0)
        //-------------------------------------------------------------
        $display("Test 1: No shift (shift amount = 0)");
        data_in_64 = 64'hA5A5A5A5A5A5A5A5;
        shift_amount_64 = 6'd0;
        shift_direction_64 = 1'b0; // Left
        arithmetic_64 = 1'b0;
        #10;

        if (data_out_64 == 64'hA5A5A5A5A5A5A5A5) begin
            $display("  PASS: No shift preserves data");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Expected 0xA5A5A5A5A5A5A5A5, Got 0x%016X", data_out_64);
            test_failed = test_failed + 1;
        end
        #10;

        //-------------------------------------------------------------
        // Test 2: Left shift by 1
        //-------------------------------------------------------------
        $display("\nTest 2: Left shift by 1");
        data_in_64 = 64'h0000000000000001;
        shift_amount_64 = 6'd1;
        shift_direction_64 = 1'b0; // Left
        arithmetic_64 = 1'b0;
        #10;

        if (data_out_64 == 64'h0000000000000002) begin
            $display("  PASS: Left shift by 1");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Expected 0x0000000000000002, Got 0x%016X", data_out_64);
            test_failed = test_failed + 1;
        end
        #10;

        //-------------------------------------------------------------
        // Test 3: Left shift by 8
        //-------------------------------------------------------------
        $display("\nTest 3: Left shift by 8");
        data_in_64 = 64'h00000000000000FF;
        shift_amount_64 = 6'd8;
        shift_direction_64 = 1'b0; // Left
        arithmetic_64 = 1'b0;
        #10;

        if (data_out_64 == 64'h000000000000FF00) begin
            $display("  PASS: Left shift by 8");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Expected 0x000000000000FF00, Got 0x%016X", data_out_64);
            test_failed = test_failed + 1;
        end
        #10;

        //-------------------------------------------------------------
        // Test 4: Left shift by 32
        //-------------------------------------------------------------
        $display("\nTest 4: Left shift by 32");
        data_in_64 = 64'h00000000DEADBEEF;
        shift_amount_64 = 6'd32;
        shift_direction_64 = 1'b0; // Left
        arithmetic_64 = 1'b0;
        #10;

        if (data_out_64 == 64'hDEADBEEF00000000) begin
            $display("  PASS: Left shift by 32");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Expected 0xDEADBEEF00000000, Got 0x%016X", data_out_64);
            test_failed = test_failed + 1;
        end
        #10;

        //-------------------------------------------------------------
        // Test 5: Logical right shift by 1
        //-------------------------------------------------------------
        $display("\nTest 5: Logical right shift by 1");
        data_in_64 = 64'h8000000000000000;
        shift_amount_64 = 6'd1;
        shift_direction_64 = 1'b1; // Right
        arithmetic_64 = 1'b0; // Logical
        #10;

        if (data_out_64 == 64'h4000000000000000) begin
            $display("  PASS: Logical right shift by 1");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Expected 0x4000000000000000, Got 0x%016X", data_out_64);
            test_failed = test_failed + 1;
        end
        #10;

        //-------------------------------------------------------------
        // Test 6: Logical right shift by 8
        //-------------------------------------------------------------
        $display("\nTest 6: Logical right shift by 8");
        data_in_64 = 64'hFF00000000000000;
        shift_amount_64 = 6'd8;
        shift_direction_64 = 1'b1; // Right
        arithmetic_64 = 1'b0; // Logical
        #10;

        if (data_out_64 == 64'h00FF000000000000) begin
            $display("  PASS: Logical right shift by 8");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Expected 0x00FF000000000000, Got 0x%016X", data_out_64);
            test_failed = test_failed + 1;
        end
        #10;

        //-------------------------------------------------------------
        // Test 7: Arithmetic right shift by 1 (positive number)
        //-------------------------------------------------------------
        $display("\nTest 7: Arithmetic right shift by 1 (positive)");
        data_in_64 = 64'h4000000000000000;
        shift_amount_64 = 6'd1;
        shift_direction_64 = 1'b1; // Right
        arithmetic_64 = 1'b1; // Arithmetic
        #10;

        if (data_out_64 == 64'h2000000000000000) begin
            $display("  PASS: Arithmetic right shift (positive)");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Expected 0x2000000000000000, Got 0x%016X", data_out_64);
            test_failed = test_failed + 1;
        end
        #10;

        //-------------------------------------------------------------
        // Test 8: Arithmetic right shift by 1 (negative number)
        //-------------------------------------------------------------
        $display("\nTest 8: Arithmetic right shift by 1 (negative)");
        data_in_64 = 64'h8000000000000000;
        shift_amount_64 = 6'd1;
        shift_direction_64 = 1'b1; // Right
        arithmetic_64 = 1'b1; // Arithmetic (sign extend)
        #10;

        if (data_out_64 == 64'hC000000000000000) begin
            $display("  PASS: Arithmetic right shift (negative, sign extended)");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Expected 0xC000000000000000, Got 0x%016X", data_out_64);
            test_failed = test_failed + 1;
        end
        #10;

        //-------------------------------------------------------------
        // Test 9: Arithmetic right shift by 8 (negative number)
        //-------------------------------------------------------------
        $display("\nTest 9: Arithmetic right shift by 8 (negative)");
        data_in_64 = 64'hFF00000000000000;
        shift_amount_64 = 6'd8;
        shift_direction_64 = 1'b1; // Right
        arithmetic_64 = 1'b1; // Arithmetic
        #10;

        if (data_out_64 == 64'hFFFF000000000000) begin
            $display("  PASS: Arithmetic right shift by 8 (sign extended)");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Expected 0xFFFF000000000000, Got 0x%016X", data_out_64);
            test_failed = test_failed + 1;
        end
        #10;

        //-------------------------------------------------------------
        // Test 10: Maximum left shift (63 bits)
        //-------------------------------------------------------------
        $display("\nTest 10: Maximum left shift (63 bits)");
        data_in_64 = 64'h0000000000000001;
        shift_amount_64 = 6'd63;
        shift_direction_64 = 1'b0; // Left
        arithmetic_64 = 1'b0;
        #10;

        if (data_out_64 == 64'h8000000000000000) begin
            $display("  PASS: Maximum left shift");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Expected 0x8000000000000000, Got 0x%016X", data_out_64);
            test_failed = test_failed + 1;
        end
        #10;

        //=============================================================
        // Test 80-bit Barrel Shifter
        //=============================================================
        $display("\n\nTesting 80-bit Barrel Shifter");
        $display("========================================\n");

        //-------------------------------------------------------------
        // Test 11: 80-bit left shift by 16
        //-------------------------------------------------------------
        $display("Test 11: 80-bit left shift by 16");
        data_in_80 = 80'h0000000000000000FFFF;
        shift_amount_80 = 7'd16;
        shift_direction_80 = 1'b0; // Left
        arithmetic_80 = 1'b0;
        #10;

        if (data_out_80 == 80'h00000000000000FFFF0000) begin
            $display("  PASS: 80-bit left shift by 16");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Expected 0x00000000000000FFFF0000, Got 0x%020X", data_out_80);
            test_failed = test_failed + 1;
        end
        #10;

        //-------------------------------------------------------------
        // Test 12: 80-bit arithmetic right shift
        //-------------------------------------------------------------
        $display("\nTest 12: 80-bit arithmetic right shift by 4");
        data_in_80 = 80'hF0000000000000000000;
        shift_amount_80 = 7'd4;
        shift_direction_80 = 1'b1; // Right
        arithmetic_80 = 1'b1; // Arithmetic
        #10;

        if (data_out_80 == 80'hFF000000000000000000) begin
            $display("  PASS: 80-bit arithmetic right shift");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Expected 0xFF000000000000000000, Got 0x%020X", data_out_80);
            test_failed = test_failed + 1;
        end
        #10;

        //=============================================================
        // Test Summary
        //=============================================================
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Tests Passed: %0d", test_passed);
        $display("Tests Failed: %0d", test_failed);
        $display("Total Tests:  %0d", test_passed + test_failed);

        if (test_failed == 0) begin
            $display("\nALL TESTS PASSED!");
        end else begin
            $display("\nSOME TESTS FAILED!");
        end
        $display("========================================\n");

        #100;
        $finish;
    end

    // Timeout watchdog
    initial begin
        #50000;
        $display("\nERROR: Simulation timeout!");
        $finish;
    end

endmodule
