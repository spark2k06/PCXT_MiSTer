`timescale 1ns / 1ps

//=================================================================
// BCD to Binary Converter Test
//=================================================================

module tb_bcd_to_binary;

    reg clk;
    reg reset;
    reg enable;
    reg [79:0] bcd_in;

    wire [63:0] binary_out;
    wire        sign_out;
    wire        done;
    wire        error;

    // DUT
    FPU_BCD_to_Binary dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .bcd_in(bcd_in),
        .binary_out(binary_out),
        .sign_out(sign_out),
        .done(done),
        .error(error)
    );

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test
    initial begin
        $dumpfile("bcd_to_binary_test.vcd");
        $dumpvars(0, tb_bcd_to_binary);

        reset = 1;
        enable = 0;
        bcd_in = 80'd0;

        #20 reset = 0;
        #10;

        $display("\n========================================");
        $display("BCD to Binary Converter Test");
        $display("========================================\n");

        // Test 1: 0
        test_conversion(80'h0_00_000000000000000000, 64'd0, 1'b0, "0");

        // Test 2: 1
        test_conversion(80'h0_00_000000000000000001, 64'd1, 1'b0, "1");

        // Test 3: 123
        test_conversion(80'h0_00_000000000000000123, 64'd123, 1'b0, "123");

        // Test 4: -456
        test_conversion(80'h8_00_000000000000000456, 64'd456, 1'b1, "-456");

        // Test 5: 999
        test_conversion(80'h0_00_000000000000000999, 64'd999, 1'b0, "999");

        #100;
        $display("\n========================================");
        $display("Test Complete");
        $display("========================================\n");
        $finish;
    end

    task test_conversion;
        input [79:0] bcd;
        input [63:0] expected_binary;
        input        expected_sign;
        input [127:0] description;
        begin
            @(posedge clk);
            bcd_in = bcd;
            enable = 1;
            @(posedge clk);
            enable = 1;  // Keep enable high

            // Wait for done
            wait(done == 1);
            @(posedge clk);
            enable = 0;

            $display("Test: %s", description);
            $display("  BCD Input:       0x%020X", bcd);
            $display("  Expected Binary: %0d (0x%016X)", expected_binary, expected_binary);
            $display("  Actual Binary:   %0d (0x%016X)", binary_out, binary_out);
            $display("  Expected Sign:   %b", expected_sign);
            $display("  Actual Sign:     %b", sign_out);
            $display("  Error:           %b", error);

            if (binary_out == expected_binary && sign_out == expected_sign && !error)
                $display("  PASS");
            else
                $display("  FAIL");

            @(posedge clk);
            @(posedge clk);
        end
    endtask

endmodule
