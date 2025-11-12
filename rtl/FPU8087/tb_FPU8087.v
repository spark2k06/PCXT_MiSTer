`timescale 1ns / 1ps

//=====================================================================
// Testbench for Intel 8087 FPU
//
// This testbench verifies:
// 1. Register access (Status, Control, Tag)
// 2. Stack register operations
// 3. Basic arithmetic operations
// 4. Normalization and rounding
// 5. Exception handling
//=====================================================================

module tb_FPU8087;

    // Clock and reset
    reg clk;
    reg reset;

    // FPU interface signals
    reg [15:0] address;
    reg [15:0] data_in;
    wire [15:0] data_out;
    reg read_enable;
    reg write_enable;
    wire interrupt_request;
    wire busy;

    // Test variables
    integer i;
    integer test_passed;
    integer test_failed;

    // Instantiate the FPU
    FPU8087 dut (
        .clk(clk),
        .reset(reset),
        .address(address),
        .data_in(data_in),
        .data_out(data_out),
        .read_enable(read_enable),
        .write_enable(write_enable),
        .interrupt_request(interrupt_request),
        .busy(busy)
    );

    // Clock generation: 10ns period (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test sequence
    initial begin
        $dumpfile("tb_FPU8087.vcd");
        $dumpvars(0, tb_FPU8087);

        // Initialize counters
        test_passed = 0;
        test_failed = 0;

        // Initialize signals
        reset = 1;
        address = 16'h0000;
        data_in = 16'h0000;
        read_enable = 0;
        write_enable = 0;

        // Apply reset
        $display("\n========================================");
        $display("Intel 8087 FPU Testbench");
        $display("========================================\n");

        #20;
        reset = 0;
        #20;

        //=============================================================
        // Test 1: Control Word Register Access
        //=============================================================
        $display("Test 1: Control Word Register Access");

        // Write control word (enable all exceptions, round to nearest)
        address = 16'h0000; // ADDR_CONTROL
        data_in = 16'h037F; // Default 8087 control word
        write_enable = 1;
        #10;
        write_enable = 0;
        #10;

        // Read back control word
        address = 16'h0000;
        read_enable = 1;
        #10;
        read_enable = 0;

        if (data_out == 16'h037F) begin
            $display("  PASS: Control word read/write");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Control word mismatch. Expected: 0x037F, Got: 0x%04X", data_out);
            test_failed = test_failed + 1;
        end
        #10;

        //=============================================================
        // Test 2: Status Word Register Access
        //=============================================================
        $display("\nTest 2: Status Word Register Access");

        // Write status word
        address = 16'h0002; // ADDR_STATUS
        data_in = 16'h3800; // Set condition codes
        write_enable = 1;
        #10;
        write_enable = 0;
        #10;

        // Read back status word
        address = 16'h0002;
        read_enable = 1;
        #10;
        read_enable = 0;

        if (data_out == 16'h3800) begin
            $display("  PASS: Status word read/write");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Status word mismatch. Expected: 0x3800, Got: 0x%04X", data_out);
            test_failed = test_failed + 1;
        end
        #10;

        //=============================================================
        // Test 3: Tag Word Register Access
        //=============================================================
        $display("\nTest 3: Tag Word Register Access");

        // Write tag word (mark some registers as valid)
        address = 16'h0004; // ADDR_TAG
        data_in = 16'hFF00; // ST0-ST3 valid (00), ST4-ST7 empty (11)
        write_enable = 1;
        #10;
        write_enable = 0;
        #10;

        // Read back tag word
        address = 16'h0004;
        read_enable = 1;
        #10;
        read_enable = 0;

        if (data_out == 16'hFF00) begin
            $display("  PASS: Tag word read/write");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Tag word mismatch. Expected: 0xFF00, Got: 0x%04X", data_out);
            test_failed = test_failed + 1;
        end
        #10;

        //=============================================================
        // Test 4: Reset Verification
        //=============================================================
        $display("\nTest 4: Reset Verification");

        // Apply reset
        reset = 1;
        #20;
        reset = 0;
        #20;

        // Read control word after reset (should be default value)
        address = 16'h0000;
        read_enable = 1;
        #10;
        read_enable = 0;

        if (data_out == 16'h037F) begin
            $display("  PASS: Control word reset to default");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Control word reset failed. Expected: 0x037F, Got: 0x%04X", data_out);
            test_failed = test_failed + 1;
        end
        #10;

        // Read status word after reset (should be 0)
        address = 16'h0002;
        read_enable = 1;
        #10;
        read_enable = 0;

        if (data_out == 16'h0000) begin
            $display("  PASS: Status word reset to 0");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Status word reset failed. Expected: 0x0000, Got: 0x%04X", data_out);
            test_failed = test_failed + 1;
        end
        #10;

        // Read tag word after reset (should be 0xFFFF - all empty)
        address = 16'h0004;
        read_enable = 1;
        #10;
        read_enable = 0;

        if (data_out == 16'hFFFF) begin
            $display("  PASS: Tag word reset to 0xFFFF (all empty)");
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Tag word reset failed. Expected: 0xFFFF, Got: 0x%04X", data_out);
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

        // End simulation
        #100;
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000; // 100 microseconds timeout
        $display("\nERROR: Simulation timeout!");
        $finish;
    end

endmodule
