`timescale 1ns / 1ps

//=================================================================
// Binary to BCD Converter Test
//=================================================================

module tb_binary_to_bcd;

    reg clk;
    reg reset;
    reg enable;
    reg [63:0] binary_in;
    reg        sign_in;

    wire [79:0] bcd_out;
    wire        done;
    wire        error;

    // DUT
    FPU_Binary_to_BCD dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .binary_in(binary_in),
        .sign_in(sign_in),
        .bcd_out(bcd_out),
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
        $dumpfile("binary_to_bcd_test.vcd");
        $dumpvars(0, tb_binary_to_bcd);

        reset = 1;
        enable = 0;
        binary_in = 64'd0;
        sign_in = 1'b0;

        #20 reset = 0;
        #10;

        $display("\n========================================");
        $display("Binary to BCD Converter Test");
        $display("========================================\n");

        // Test 1: 0
        test_conversion(64'd0, 1'b0, 80'h00000000000000000000, "0");

        // Test 2: 1
        test_conversion(64'd1, 1'b0, 80'h00000000000000000001, "1");

        // Test 3: 123
        test_conversion(64'd123, 1'b0, 80'h00000000000000000123, "123");

        // Test 4: -456 (456 with sign bit)
        test_conversion(64'd456, 1'b1, 80'h80000000000000000456, "-456");

        // Test 5: 999
        test_conversion(64'd999, 1'b0, 80'h00000000000000000999, "999");

        #100;
        $display("\n========================================");
        $display("Test Complete");
        $display("========================================\n");
        $finish;
    end

    task test_conversion;
        input [63:0] binary;
        input        sign;
        input [79:0] expected_bcd;
        input [127:0] description;
        begin
            @(posedge clk);
            binary_in = binary;
            sign_in = sign;
            enable = 1;
            @(posedge clk);
            enable = 1;  // Keep enable high

            // Wait for done
            wait(done == 1);
            @(posedge clk);
            enable = 0;

            $display("Test: %s", description);
            $display("  Binary Input:  %0d (0x%016X)", binary, binary);
            $display("  Sign:          %b", sign);
            $display("  BCD Output:    0x%020X", bcd_out);
            $display("  Expected:      0x%020X", expected_bcd);
            $display("  Error:         %b", error);

            // Check sign bit
            if (bcd_out[79] == sign)
                $display("  Sign bit: PASS");
            else
                $display("  Sign bit: FAIL (expected %b, got %b)", sign, bcd_out[79]);

            // Check BCD digits (ignore sign bit differences in comparison for now)
            if (bcd_out[71:0] == expected_bcd[71:0] && bcd_out[79] == sign)
                $display("  PASS\n");
            else
                $display("  FAIL\n");

            @(posedge clk);
            @(posedge clk);
        end
    endtask

endmodule
