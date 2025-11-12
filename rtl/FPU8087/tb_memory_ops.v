`timescale 1ns / 1ps

//=====================================================================
// Memory Operations Testbench for FPU_Core
//
// Tests memory operand format conversions:
// - FLD with different formats (int16, int32, int64, fp32, fp64, fp80, BCD)
// - FST with different formats
// - Verifies correct conversion using has_memory_op and format flags
//=====================================================================

module tb_memory_ops;

    reg clk;
    reg reset;
    reg [7:0] instruction;
    reg [2:0] stack_index;
    reg execute;
    reg has_memory_op;
    reg [1:0] operand_size;
    reg is_integer;
    reg is_bcd;
    wire ready;
    wire error;
    reg [79:0] data_in;
    wire [79:0] data_out;
    wire [15:0] status_out;
    wire [15:0] tag_word_out;

    integer test_count;
    integer pass_count;
    integer fail_count;

    // Instruction opcodes
    localparam INST_FLD  = 8'h20;  // Load (with format conversion based on flags)
    localparam INST_FST  = 8'h21;  // Store (with format conversion based on flags)
    localparam INST_FSTP = 8'h22;  // Store and pop

    // Instantiate FPU_Core
    FPU_Core dut (
        .clk(clk),
        .reset(reset),
        .instruction(instruction),
        .stack_index(stack_index),
        .execute(execute),
        .ready(ready),
        .error(error),
        .data_in(data_in),
        .data_out(data_out),
        .int_data_in(32'h0),
        .int_data_out(),
        .has_memory_op(has_memory_op),
        .operand_size(operand_size),
        .is_integer(is_integer),
        .is_bcd(is_bcd),
        .control_in(16'h037F),  // Default control word
        .control_write(1'b0),
        .status_out(status_out),
        .control_out(),
        .tag_word_out(tag_word_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // VCD dump
    initial begin
        $dumpfile("memory_ops_waves.vcd");
        $dumpvars(0, tb_memory_ops);
    end

    // Test stimulus
    initial begin
        // Initialize
        reset = 1;
        instruction = 8'h00;
        stack_index = 3'd0;
        execute = 0;
        has_memory_op = 0;
        operand_size = 2'd0;
        is_integer = 0;
        is_bcd = 0;
        data_in = 80'h0;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        $display("");
        $display("========================================");
        $display("Memory Operations Test Suite");
        $display("========================================");
        $display("");

        // Reset
        #20;
        reset = 0;
        #20;

        wait(ready);
        #10;

        //=================================================================
        // Test 1: FLD m32real (32-bit float)
        //=================================================================
        $display("Test 1: FLD m32real (load 32-bit float)");
        // Input: 3.14159 in IEEE 754 single precision = 0x40490FDB
        // When converted to FP80, mantissa is zero-padded (no precision gain)
        test_fld_memory(32'h40490FDB, 2'd1, 1'b0, 1'b0,  // size=dword, not int, not BCD
                       80'h4000C90FDB0000000000, "3.14159 (FP32)");
        $display("");

        //=================================================================
        // Test 2: FLD m64real (64-bit float)
        //=================================================================
        $display("Test 2: FLD m64real (load 64-bit float)");
        // Input: 2.718281828 in IEEE 754 double precision = 0x4005BF0A8B145769
        // When converted to FP80, mantissa is zero-padded (no precision gain)
        test_fld_memory(64'h4005BF0A8B145769, 2'd2, 1'b0, 1'b0,  // size=qword
                       80'h4000ADF85458A2BB4800, "2.71828 (FP64)");
        $display("");

        //=================================================================
        // Test 3: FLD m80real (80-bit float)
        //=================================================================
        $display("Test 3: FLD m80real (load 80-bit float)");
        // Input: 1.0 in FP80 format
        test_fld_memory(80'h3FFF8000000000000000, 2'd3, 1'b0, 1'b0,  // size=tbyte
                       80'h3FFF8000000000000000, "1.0 (FP80)");
        $display("");

        //=================================================================
        // Test 4: FILD m16int (16-bit signed integer)
        //=================================================================
        $display("Test 4: FILD m16int (load 16-bit signed integer)");
        // Input: 42 (decimal) = 0x002A
        test_fld_memory(16'h002A, 2'd0, 1'b1, 1'b0,  // size=word, integer
                       80'h4004A800000000000000, "42 (int16)");
        $display("");

        //=================================================================
        // Test 5: FILD m32int (32-bit signed integer)
        //=================================================================
        $display("Test 5: FILD m32int (load 32-bit signed integer)");
        // Input: 1000 (decimal) = 0x000003E8
        test_fld_memory(32'h000003E8, 2'd1, 1'b1, 1'b0,  // size=dword, integer
                       80'h4008FA00000000000000, "1000 (int32)");
        $display("");

        //=================================================================
        // Test 6: FST m32real (store as 32-bit float)
        //=================================================================
        $display("Test 6: FST m32real (store as 32-bit float)");
        // First load 5.0 onto stack
        load_fp80(80'h4001A000000000000000);  // 5.0
        wait(ready);
        #20;

        // Now store as FP32
        test_fst_memory(2'd1, 1'b0, 1'b0,  // size=dword, not int, not BCD
                       32'h40A00000, "5.0 → FP32");
        $display("");

        //=================================================================
        // Test 7: FST m64real (store as 64-bit float)
        //=================================================================
        $display("Test 7: FST m64real (store as 64-bit float)");
        // Load 7.5
        load_fp80(80'h4001F000000000000000);  // 7.5
        wait(ready);
        #20;

        // Store as FP64
        test_fst_memory(2'd2, 1'b0, 1'b0,  // size=qword
                       64'h401E000000000000, "7.5 → FP64");
        $display("");

        //=================================================================
        // Test 8: FIST m16int (store as 16-bit integer)
        //=================================================================
        $display("Test 8: FIST m16int (store as 16-bit signed integer)");
        // Load 100.0
        load_fp80(80'h4005C800000000000000);  // 100.0
        wait(ready);
        #20;

        // Store as int16
        test_fst_memory(2'd0, 1'b1, 1'b0,  // size=word, integer
                       16'h0064, "100.0 → int16");
        $display("");

        //=================================================================
        // Test 9: FIST m32int (store as 32-bit integer)
        //=================================================================
        $display("Test 9: FIST m32int (store as 32-bit signed integer)");
        // Load 12345.0
        load_fp80(80'h400CC0E4000000000000);  // 12345.0
        wait(ready);
        #20;

        // Store as int32
        test_fst_memory(2'd1, 1'b1, 1'b0,  // size=dword, integer
                       32'h00003039, "12345.0 → int32");
        $display("");

        //=================================================================
        // Summary
        //=================================================================
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests:  %0d", test_count);
        $display("Passed:       %0d", pass_count);
        $display("Failed:       %0d", fail_count);
        $display("");

        if (fail_count == 0) begin
            $display("*** ALL MEMORY OPERATION TESTS PASSED ***");
            $display("");
        end else begin
            $display("*** SOME TESTS FAILED ***");
            $display("");
        end

        $finish;
    end

    // Helper task: Test FLD with memory operand
    task test_fld_memory;
        input [79:0] mem_data;
        input [1:0] size;
        input is_int;
        input is_bcd_flag;
        input [79:0] expected_result;
        input [200*8:1] test_name;
        begin
            wait(ready);
            @(posedge clk);

            // Set up memory load
            data_in = mem_data;
            instruction = INST_FLD;
            stack_index = 3'd0;
            has_memory_op = 1'b1;
            operand_size = size;
            is_integer = is_int;
            is_bcd = is_bcd_flag;
            execute = 1'b1;

            @(posedge clk);
            execute = 1'b0;
            has_memory_op = 1'b0;

            // Wait for operation to complete
            wait(ready);
            #20;

            // Check result (top of stack)
            // Note: We can't directly read ST(0) from outside, so we'll store it
            @(posedge clk);
            instruction = INST_FST;
            has_memory_op = 1'b0;  // Register operation
            execute = 1'b1;
            @(posedge clk);
            execute = 1'b0;

            wait(ready);
            #10;

            if (data_out == expected_result) begin
                pass_count = pass_count + 1;
                $display("  PASS: %0s", test_name);
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL: %0s", test_name);
                $display("        Expected: %h", expected_result);
                $display("        Got:      %h", data_out);
            end
            test_count = test_count + 1;
        end
    endtask

    // Helper task: Load FP80 value onto stack
    task load_fp80;
        input [79:0] value;
        begin
            wait(ready);
            @(posedge clk);

            data_in = value;
            instruction = INST_FLD;
            stack_index = 3'd0;
            has_memory_op = 1'b0;  // Register load (no conversion)
            execute = 1'b1;

            @(posedge clk);
            execute = 1'b0;
        end
    endtask

    // Helper task: Test FST with memory operand
    task test_fst_memory;
        input [1:0] size;
        input is_int;
        input is_bcd_flag;
        input [79:0] expected_result;
        input [200*8:1] test_name;
        begin
            wait(ready);
            @(posedge clk);

            // Set up memory store
            instruction = INST_FST;
            stack_index = 3'd0;
            has_memory_op = 1'b1;
            operand_size = size;
            is_integer = is_int;
            is_bcd = is_bcd_flag;
            execute = 1'b1;

            @(posedge clk);
            execute = 1'b0;
            has_memory_op = 1'b0;

            // Wait for operation to complete
            wait(ready);
            #20;

            // Check result in data_out
            // Mask based on size
            case (size)
                2'd0: begin  // word (16-bit)
                    if (data_out[15:0] == expected_result[15:0]) begin
                        pass_count = pass_count + 1;
                        $display("  PASS: %0s", test_name);
                    end else begin
                        fail_count = fail_count + 1;
                        $display("  FAIL: %0s", test_name);
                        $display("        Expected: %h", expected_result[15:0]);
                        $display("        Got:      %h", data_out[15:0]);
                    end
                end
                2'd1: begin  // dword (32-bit)
                    if (data_out[31:0] == expected_result[31:0]) begin
                        pass_count = pass_count + 1;
                        $display("  PASS: %0s", test_name);
                    end else begin
                        fail_count = fail_count + 1;
                        $display("  FAIL: %0s", test_name);
                        $display("        Expected: %h", expected_result[31:0]);
                        $display("        Got:      %h", data_out[31:0]);
                    end
                end
                2'd2: begin  // qword (64-bit)
                    if (data_out[63:0] == expected_result[63:0]) begin
                        pass_count = pass_count + 1;
                        $display("  PASS: %0s", test_name);
                    end else begin
                        fail_count = fail_count + 1;
                        $display("  FAIL: %0s", test_name);
                        $display("        Expected: %h", expected_result[63:0]);
                        $display("        Got:      %h", data_out[63:0]);
                    end
                end
                2'd3: begin  // tbyte (80-bit)
                    if (data_out == expected_result) begin
                        pass_count = pass_count + 1;
                        $display("  PASS: %0s", test_name);
                    end else begin
                        fail_count = fail_count + 1;
                        $display("  FAIL: %0s", test_name);
                        $display("        Expected: %h", expected_result);
                        $display("        Got:      %h", data_out);
                    end
                end
            endcase
            test_count = test_count + 1;
        end
    endtask

endmodule
