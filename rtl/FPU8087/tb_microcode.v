`timescale 1ns / 1ps

//============================================================================
// Testbench for Microcode Execution
//
// This testbench loads microcode from .hex files and executes them on the
// microsequencer, verifying correct operation against expected results.
//============================================================================

module tb_microcode;

    // Clock and reset
    reg clk;
    reg reset;

    // Microsequencer signals
    reg start;
    reg [3:0] micro_program_index;
    reg [63:0] cpu_data_in;
    wire [63:0] cpu_data_out;
    wire instruction_complete;

    // Test control
    integer test_num;
    integer passed_tests;
    integer failed_tests;
    reg [255:0] test_name;

    //------------------------------------------------------------------------
    // Instantiate the microsequencer
    //------------------------------------------------------------------------
    MicroSequencer uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .micro_program_index(micro_program_index),
        .cpu_data_in(cpu_data_in),
        .cpu_data_out(cpu_data_out),
        .instruction_complete(instruction_complete)
    );

    //------------------------------------------------------------------------
    // Clock generation (100 MHz = 10ns period)
    //------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //------------------------------------------------------------------------
    // Test stimulus
    //------------------------------------------------------------------------
    initial begin
        // Initialize
        reset = 1;
        start = 0;
        micro_program_index = 0;
        cpu_data_in = 64'h0;
        test_num = 0;
        passed_tests = 0;
        failed_tests = 0;

        $display("========================================");
        $display("FPU Microcode Test Suite");
        $display("========================================");

        // Reset sequence
        #20;
        reset = 0;
        #20;

        // Run tests
        run_test_example1();
        run_test_example2();
        run_test_simple_load_store();
        run_test_loop_operations();
        run_test_example6_sincos();
        run_test_example7_sqrt();
        run_test_example8_tan();
        run_test_example9_atan();
        run_test_example10_exp();
        run_test_example11_log();

        // Summary
        #100;
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests:  %0d", passed_tests + failed_tests);
        $display("Passed:       %0d", passed_tests);
        $display("Failed:       %0d", failed_tests);

        if (failed_tests == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
        end else begin
            $display("\n*** SOME TESTS FAILED ***\n");
        end

        $finish;
    end

    //------------------------------------------------------------------------
    // Test: Example 1 - Simple Operations
    //------------------------------------------------------------------------
    task run_test_example1;
        begin
            test_name = "Example 1: Simple Operations";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Load microcode from example1.hex
            load_microcode("examples/example1.hex");

            // Set input
            cpu_data_in = 64'h123456789ABCDEF0;

            // Start execution
            micro_program_index = 0;
            start = 1;
            #10;
            start = 0;

            // Wait for completion
            wait(instruction_complete == 1);
            #10;

            // Verify output
            if (cpu_data_out == 64'h123456789ABCDEF0) begin
                $display("  PASS: Output matches expected value");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Expected 0x123456789ABCDEF0, got 0x%h", cpu_data_out);
                failed_tests = failed_tests + 1;
            end

            // Reset for next test
            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Example 2 - Loop Operations
    //------------------------------------------------------------------------
    task run_test_example2;
        begin
            test_name = "Example 2: Loop Operations";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Load microcode from example2.hex
            load_microcode("examples/example2.hex");

            // Set input
            cpu_data_in = 64'h0000000000000001;

            // Start execution
            micro_program_index = 0;
            start = 1;
            #10;
            start = 0;

            // Wait for completion (with timeout)
            #10000; // Wait 10 microseconds
            if (instruction_complete == 1) begin
                $display("  PASS: Loop completed successfully");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Timeout waiting for completion");
                failed_tests = failed_tests + 1;
            end
            #10;

            // Reset for next test
            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Simple Load/Store
    //------------------------------------------------------------------------
    task run_test_simple_load_store;
        begin
            test_name = "Simple Load/Store";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Manually program a simple load/store sequence
            uut.microcode_rom[0] = {4'h1, 4'h1, 8'd0, 16'd1};  // EXEC LOAD
            uut.microcode_rom[1] = {4'h1, 4'h2, 8'd0, 16'd2};  // EXEC STORE
            uut.microcode_rom[2] = {4'hF, 4'h0, 8'd0, 16'd0};  // HALT

            // Set input
            cpu_data_in = 64'hDEADBEEFCAFEBABE;

            // Start execution
            micro_program_index = 0;
            start = 1;
            #10;
            start = 0;

            // Wait for completion
            wait(instruction_complete == 1);
            #10;

            // Verify output
            if (cpu_data_out == 64'hDEADBEEFCAFEBABE) begin
                $display("  PASS: Load/Store works correctly");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Expected 0xDEADBEEFCAFEBABE, got 0x%h", cpu_data_out);
                failed_tests = failed_tests + 1;
            end

            // Reset for next test
            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Loop Operations
    //------------------------------------------------------------------------
    task run_test_loop_operations;
        begin
            test_name = "Loop Operations";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Program a loop: initialize to 3, decrement until 0
            uut.microcode_rom[0] = {4'h1, 4'h9, 8'd3, 16'd1};  // EXEC LOOP_INIT 3
            uut.microcode_rom[1] = {4'h1, 4'h1, 8'd0, 16'd2};  // EXEC LOAD (placeholder)
            uut.microcode_rom[2] = {4'h1, 4'hA, 8'd0, 16'd1};  // EXEC LOOP_DEC -> jump to 1
            uut.microcode_rom[3] = {4'hF, 4'h0, 8'd0, 16'd0};  // HALT

            // Set input
            cpu_data_in = 64'h0000000000000042;

            // Start execution
            micro_program_index = 0;
            start = 1;
            #10;
            start = 0;

            // Wait for completion
            wait(instruction_complete == 1);
            #10;

            // Check that loop register is 0
            if (uut.loop_reg == 0) begin
                $display("  PASS: Loop executed 3 times correctly");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Loop register should be 0, got %0d", uut.loop_reg);
                failed_tests = failed_tests + 1;
            end

            // Reset for next test
            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    //------------------------------------------------------------------------
    // Helper task: Load microcode from hex file
    //------------------------------------------------------------------------
    task load_microcode;
        input [255:0] filename;
        integer file, status, addr, value;
        reg [255:0] line;
        begin
            $display("  Loading microcode from: %0s", filename);

            file = $fopen(filename, "r");
            if (file == 0) begin
                $display("  WARNING: Could not open file %0s", filename);
                $display("  Skipping file load (using pre-programmed code if available)");
            end else begin
                // Clear ROM first
                for (addr = 0; addr < 4096; addr = addr + 1) begin
                    uut.microcode_rom[addr] = 32'h0;
                end

                // Read file line by line
                while (!$feof(file)) begin
                    status = $fscanf(file, "%h: %h\n", addr, value);
                    if (status == 2) begin
                        uut.microcode_rom[addr] = value;
                        $display("    ROM[%04h] = %08h", addr, value);
                    end
                end

                $fclose(file);
                $display("  Microcode loaded successfully");
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Example 6 - CORDIC Sin/Cos
    //------------------------------------------------------------------------
    task run_test_example6_sincos;
        begin
            test_name = "Example 6: CORDIC Sin/Cos";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Load microcode from example6.hex
            load_microcode("examples/example6.hex");

            // Set input angle
            cpu_data_in = 64'h3FE0000000000000; // π/4 in IEEE754

            // Start execution
            micro_program_index = 0;
            start = 1;
            #10;
            start = 0;

            // Wait for completion (with timeout)
            #20000; // 20 microseconds
            if (instruction_complete == 1) begin
                $display("  PASS: CORDIC Sin/Cos completed");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Timeout waiting for completion");
                failed_tests = failed_tests + 1;
            end
            #10;

            // Reset for next test
            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Example 7 - Square Root
    //------------------------------------------------------------------------
    task run_test_example7_sqrt;
        begin
            test_name = "Example 7: Square Root";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Load microcode from example7.hex
            load_microcode("examples/example7.hex");

            // Set input value
            cpu_data_in = 64'h4000000000000000; // 2.0 in IEEE754

            // Start execution
            micro_program_index = 0;
            start = 1;
            #10;
            start = 0;

            // Wait for completion
            #20000;
            if (instruction_complete == 1) begin
                $display("  PASS: Square root completed");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Timeout waiting for completion");
                failed_tests = failed_tests + 1;
            end
            #10;

            // Reset for next test
            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Example 8 - Tangent
    //------------------------------------------------------------------------
    task run_test_example8_tan;
        begin
            test_name = "Example 8: Tangent";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Load microcode from example8.hex
            load_microcode("examples/example8.hex");

            // Set input angle
            cpu_data_in = 64'h3FD0000000000000; // π/8 in IEEE754

            // Start execution
            micro_program_index = 0;
            start = 1;
            #10;
            start = 0;

            // Wait for completion
            #20000;
            if (instruction_complete == 1) begin
                $display("  PASS: Tangent completed");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Timeout waiting for completion");
                failed_tests = failed_tests + 1;
            end
            #10;

            // Reset for next test
            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Example 9 - Arctangent
    //------------------------------------------------------------------------
    task run_test_example9_atan;
        begin
            test_name = "Example 9: Arctangent";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Load microcode from example9.hex
            load_microcode("examples/example9.hex");

            // Set input value
            cpu_data_in = 64'h3FF0000000000000; // 1.0 in IEEE754

            // Start execution
            micro_program_index = 0;
            start = 1;
            #10;
            start = 0;

            // Wait for completion
            #20000;
            if (instruction_complete == 1) begin
                $display("  PASS: Arctangent completed");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Timeout waiting for completion");
                failed_tests = failed_tests + 1;
            end
            #10;

            // Reset for next test
            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Example 10 - Exponential (F2XM1)
    //------------------------------------------------------------------------
    task run_test_example10_exp;
        begin
            test_name = "Example 10: Exponential";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Load microcode from example10.hex
            load_microcode("examples/example10.hex");

            // Set input value (x in range [-1, 1])
            cpu_data_in = 64'h3FE0000000000000; // 0.5 in IEEE754

            // Start execution
            micro_program_index = 0;
            start = 1;
            #10;
            start = 0;

            // Wait for completion
            #20000;
            if (instruction_complete == 1) begin
                $display("  PASS: Exponential completed");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Timeout waiting for completion");
                failed_tests = failed_tests + 1;
            end
            #10;

            // Reset for next test
            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Example 11 - Logarithm (FYL2X)
    //------------------------------------------------------------------------
    task run_test_example11_log;
        begin
            test_name = "Example 11: Logarithm";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Load microcode from example11.hex
            load_microcode("examples/example11.hex");

            // Set input value
            cpu_data_in = 64'h4000000000000000; // 2.0 in IEEE754

            // Start execution
            micro_program_index = 0;
            start = 1;
            #10;
            start = 0;

            // Wait for completion
            #20000;
            if (instruction_complete == 1) begin
                $display("  PASS: Logarithm completed");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Timeout waiting for completion");
                failed_tests = failed_tests + 1;
            end
            #10;

            // Reset for next test
            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    //------------------------------------------------------------------------
    // Waveform dump for debugging
    //------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_microcode.vcd");
        $dumpvars(0, tb_microcode);
    end

endmodule
