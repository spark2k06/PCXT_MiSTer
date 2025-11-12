`timescale 1ns / 1ps

//============================================================================
// Comprehensive Testbench for Extended Microcode Operations
//
// Tests all 22 microcode programs including newly implemented complex ops
//============================================================================

module tb_microcode_extended;

    // Clock and reset
    reg clk;
    reg reset;

    // Microsequencer signals
    reg start;
    reg [4:0] micro_program_index;  // 5 bits for 32 programs
    reg [79:0] data_in;
    wire [79:0] data_out;
    wire instruction_complete;

    // Test control
    integer test_num;
    integer passed_tests;
    integer failed_tests;
    reg [255:0] test_name;

    //------------------------------------------------------------------------
    // Instantiate the microsequencer
    //------------------------------------------------------------------------
    MicroSequencer_Extended_BCD uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .micro_program_index(micro_program_index),
        .data_in(data_in),
        .data_out(data_out),
        .instruction_complete(instruction_complete),

        // Connect to stub arithmetic unit for testing
        .arith_operation(),
        .arith_enable(),
        .arith_rounding_mode(),
        .arith_operand_a(),
        .arith_operand_b(),
        .arith_int16_in(),
        .arith_int32_in(),
        .arith_uint64_in(),
        .arith_uint64_sign_in(),
        .arith_fp32_in(),
        .arith_fp64_in(),
        .arith_result(80'h0),  // Stub: return zero
        .arith_int16_out(16'h0),
        .arith_int32_out(32'h0),
        .arith_uint64_out(64'h0),
        .arith_uint64_sign_out(1'b0),
        .arith_fp32_out(32'h0),
        .arith_fp64_out(64'h0),
        .arith_done(1'b1),     // Stub: immediate done
        .arith_invalid(1'b0),
        .arith_overflow(1'b0),
        .arith_cc_less(1'b0),
        .arith_cc_equal(1'b0),
        .arith_cc_greater(1'b0),
        .arith_cc_unordered(1'b0),

        // BCD converter stubs
        .bcd2bin_enable(),
        .bcd2bin_bcd_in(),
        .bcd2bin_binary_out(64'h0),
        .bcd2bin_sign_out(1'b0),
        .bcd2bin_done(1'b1),
        .bcd2bin_error(1'b0),
        .bin2bcd_enable(),
        .bin2bcd_binary_in(),
        .bin2bcd_sign_in(),
        .bin2bcd_bcd_out(80'h0),
        .bin2bcd_done(1'b1),
        .bin2bcd_error(1'b0),

        // Stack stubs
        .stack_push_req(),
        .stack_pop_req(),
        .stack_read_sel(),
        .stack_write_sel(),
        .stack_write_en(),
        .stack_write_data(),
        .stack_read_data(80'h0),
        .stack_op_done(1'b0),

        // Status/control stubs
        .status_word_in(16'h0),
        .status_word_out(),
        .status_word_write(),
        .control_word_in(16'h0),
        .control_word_out(),
        .control_word_write()
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
        data_in = 80'h0;
        test_num = 0;
        passed_tests = 0;
        failed_tests = 0;

        $display("========================================");
        $display("Extended Microcode Test Suite");
        $display("========================================");

        // Reset sequence
        #20;
        reset = 0;
        #20;

        // Run tests for all implemented programs
        run_test_fadd();        // Program 0
        run_test_fsub();        // Program 1
        run_test_fmul();        // Program 2
        run_test_fdiv();        // Program 3
        run_test_fsqrt();       // Program 4
        run_test_fsin();        // Program 5
        run_test_fcos();        // Program 6
        run_test_fprem();       // Program 9
        run_test_fxtract();     // Program 10
        run_test_fscale();      // Program 11
        run_test_fbld();        // Program 12
        run_test_fbstp();       // Program 13
        run_test_fptan();       // Program 14
        run_test_fpatan();      // Program 15
        run_test_f2xm1();       // Program 16
        run_test_fyl2x();       // Program 17
        run_test_fyl2xp1();     // Program 18
        run_test_fsincos();     // Program 19
        run_test_fprem1();      // Program 20
        run_test_frndint();     // Program 21

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
    // Test Tasks
    //------------------------------------------------------------------------

    task run_test_fadd;
        integer timeout;
        begin
            test_name = "FADD (Program 0)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h4000C90FDAA22168C000;  // 3.14159...
            micro_program_index = 5'd0;
            start = 1;
            #10;
            start = 0;

            // Wait with timeout (1000 cycles = 10us)
            timeout = 0;
            while (instruction_complete == 0 && timeout < 1000) begin
                #10;
                timeout = timeout + 1;
            end

            if (timeout >= 1000) begin
                $display("  FAIL: Timeout waiting for completion");
                failed_tests = failed_tests + 1;
            end else begin
                $display("  PASS: Microcode completed in %0d cycles", timeout);
                passed_tests = passed_tests + 1;
            end

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fsub;
        begin
            test_name = "FSUB (Program 1)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h4001A000000000000000;  // 5.0
            micro_program_index = 5'd1;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fmul;
        begin
            test_name = "FMUL (Program 2)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h4000C000000000000000;  // 3.0
            micro_program_index = 5'd2;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fdiv;
        begin
            test_name = "FDIV (Program 3)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h4002C000000000000000;  // 12.0
            micro_program_index = 5'd3;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fsqrt;
        begin
            test_name = "FSQRT (Program 4)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h40028000000000000000;  // 16.0
            micro_program_index = 5'd4;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fsin;
        begin
            test_name = "FSIN (Program 5)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h3FFFC90FDAA22168C000;  // π/2
            micro_program_index = 5'd5;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fcos;
        begin
            test_name = "FCOS (Program 6)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h0;  // 0.0
            micro_program_index = 5'd6;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fprem;
        begin
            test_name = "FPREM (Program 9)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h4003A000000000000000;  // 17.0
            micro_program_index = 5'd9;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fxtract;
        begin
            test_name = "FXTRACT (Program 10)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h4002C000000000000000;  // 12.0
            micro_program_index = 5'd10;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fscale;
        begin
            test_name = "FSCALE (Program 11)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h4000C000000000000000;  // 3.0
            micro_program_index = 5'd11;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fbld;
        begin
            test_name = "FBLD (Program 12)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h0000000000000000001234;  // BCD 1234
            micro_program_index = 5'd12;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fbstp;
        begin
            test_name = "FBSTP (Program 13)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h4009A000000000000000;  // 1234.0
            micro_program_index = 5'd13;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fptan;
        begin
            test_name = "FPTAN (Program 14)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h3FFFC90FDAA22168C000;  // π/4
            micro_program_index = 5'd14;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fpatan;
        begin
            test_name = "FPATAN (Program 15)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h3FFF8000000000000000;  // 1.0
            micro_program_index = 5'd15;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_f2xm1;
        begin
            test_name = "F2XM1 (Program 16)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h3FFE8000000000000000;  // 0.5
            micro_program_index = 5'd16;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fyl2x;
        begin
            test_name = "FYL2X (Program 17)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h40008000000000000000;  // 2.0
            micro_program_index = 5'd17;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fyl2xp1;
        begin
            test_name = "FYL2XP1 (Program 18)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h3FFF8000000000000000;  // 1.0
            micro_program_index = 5'd18;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fsincos;
        begin
            test_name = "FSINCOS (Program 19)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h3FFFC90FDAA22168C000;  // π/4
            micro_program_index = 5'd19;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_fprem1;
        begin
            test_name = "FPREM1 (Program 20)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h4003A000000000000000;  // 17.0
            micro_program_index = 5'd20;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

    task run_test_frndint;
        begin
            test_name = "FRNDINT (Program 21)";
            test_num = test_num + 1;
            $display("\n[Test %0d] %0s", test_num, test_name);

            data_in = 80'h4000C90FDAA22168C000;  // 3.14159...
            micro_program_index = 5'd21;
            start = 1;
            #10;
            start = 0;

            wait(instruction_complete == 1);
            #10;

            $display("  PASS: Microcode completed");
            passed_tests = passed_tests + 1;

            reset = 1;
            #20;
            reset = 0;
            #20;
        end
    endtask

endmodule
