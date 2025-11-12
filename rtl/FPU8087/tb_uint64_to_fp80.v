`timescale 1ns / 1ps

//=================================================================
// UInt64 to FP80 Converter Test
//=================================================================

module tb_uint64_to_fp80;

    reg clk;
    reg reset;
    reg enable;
    reg [63:0] uint_in;
    reg        sign_in;

    wire [79:0] fp_out;
    wire        done;

    // DUT
    FPU_UInt64_to_FP80 dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .uint_in(uint_in),
        .sign_in(sign_in),
        .fp_out(fp_out),
        .done(done)
    );

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test
    initial begin
        $dumpfile("uint64_to_fp80_test.vcd");
        $dumpvars(0, tb_uint64_to_fp80);

        reset = 1;
        enable = 0;
        uint_in = 64'd0;
        sign_in = 1'b0;

        #20 reset = 0;
        #10;

        $display("\n========================================");
        $display("UInt64 to FP80 Converter Test");
        $display("========================================\n");

        // Test 1: 0
        test_conversion(64'd0, 1'b0, 80'h0000_0000000000000000, "0");

        // Test 2: 1
        test_conversion(64'd1, 1'b0, 80'h3FFF_8000000000000000, "1");

        // Test 3: 123
        test_conversion(64'd123, 1'b0, 80'h4005_F600000000000000, "123");

        // Test 4: -456 (456 with sign bit)
        test_conversion(64'd456, 1'b1, 80'hC007_E400000000000000, "-456");

        // Test 5: Large number
        test_conversion(64'd999999999, 1'b0, 80'h0000_0000000000000000, "999999999");

        #100;
        $display("\n========================================");
        $display("Test Complete");
        $display("========================================\n");
        $finish;
    end

    task test_conversion;
        input [63:0] uint_val;
        input        sign_val;
        input [79:0] expected_fp;
        input [127:0] description;
        begin
            @(posedge clk);
            uint_in = uint_val;
            sign_in = sign_val;
            enable = 1;
            @(posedge clk);
            enable = 1;  // Keep enable high

            // Wait for done
            wait(done == 1);
            @(posedge clk);
            enable = 0;

            $display("Test: %s", description);
            $display("  UInt64 Input:  %0d (0x%016X)", uint_val, uint_val);
            $display("  Sign:          %b", sign_val);
            $display("  FP80 Output:   0x%020X", fp_out);
            if (expected_fp != 80'h0000_0000000000000000)
                $display("  Expected:      0x%020X", expected_fp);

            // Check sign bit
            if (fp_out[79] == sign_val)
                $display("  Sign bit: PASS");
            else
                $display("  Sign bit: FAIL (expected %b, got %b)", sign_val, fp_out[79]);

            // For non-zero values, check exponent makes sense
            if (uint_val != 64'd0) begin
                $display("  Exponent:      0x%04X (%0d)", fp_out[78:64], fp_out[78:64]);
                $display("  Mantissa:      0x%016X", fp_out[63:0]);
            end

            @(posedge clk);
            @(posedge clk);
        end
    endtask

endmodule
