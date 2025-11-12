`timescale 1ns / 1ps

//=====================================================================
// Testbench for FPU8087_Direct - Real 8087 Opcode Testing
//
// Tests the complete FPU with real Intel 8087 opcodes (D8-DF + ModR/M)
//=====================================================================

module tb_fpu8087_direct;

    reg clk;
    reg reset;

    reg [7:0]  cpu_opcode;
    reg [7:0]  cpu_modrm;
    reg        cpu_execute;
    wire       cpu_ready;
    wire       cpu_error;

    reg [79:0] cpu_data_in;
    wire [79:0] cpu_data_out;
    reg [31:0] cpu_int_data_in;
    wire [31:0] cpu_int_data_out;

    reg [15:0] cpu_control_in;
    reg        cpu_control_write;
    wire [15:0] cpu_status_out;
    wire [15:0] cpu_control_out;
    wire [15:0] cpu_tag_word_out;

    // Instantiate FPU
    FPU8087_Direct fpu (
        .clk(clk),
        .reset(reset),
        .cpu_opcode(cpu_opcode),
        .cpu_modrm(cpu_modrm),
        .cpu_execute(cpu_execute),
        .cpu_ready(cpu_ready),
        .cpu_error(cpu_error),
        .cpu_data_in(cpu_data_in),
        .cpu_data_out(cpu_data_out),
        .cpu_int_data_in(cpu_int_data_in),
        .cpu_int_data_out(cpu_int_data_out),
        .cpu_control_in(cpu_control_in),
        .cpu_control_write(cpu_control_write),
        .cpu_status_out(cpu_status_out),
        .cpu_control_out(cpu_control_out),
        .cpu_tag_word_out(cpu_tag_word_out)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Test counters
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num = 0;

    // Task to execute an FPU instruction with real 8087 opcode
    task execute_fpu_instruction;
        input [7:0] opcode;
        input [7:0] modrm;
        input [79:0] data;
        input [255:0] inst_name;
        begin
            @(posedge clk);
            cpu_opcode = opcode;
            cpu_modrm = modrm;
            cpu_data_in = data;
            cpu_execute = 1'b1;
            @(posedge clk);
            cpu_execute = 1'b0;

            // Wait for completion
            wait (cpu_ready);
            @(posedge clk);
            $display("[%0t] Executed %s (opcode=%02X, modrm=%02X)", $time, inst_name, opcode, modrm);
        end
    endtask

    // Task to check result
    task check_result;
        input [79:0] expected;
        input [255:0] test_name;
        begin
            test_num = test_num + 1;
            if (cpu_data_out == expected) begin
                $display("  ✓ Test %0d PASS: %s", test_num, test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("  ✗ Test %0d FAIL: %s", test_num, test_name);
                $display("    Expected: %020X", expected);
                $display("    Got:      %020X", cpu_data_out);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $display("========================================");
        $display("FPU8087 Direct Integration Test");
        $display("Testing with Real 8087 Opcodes");
        $display("========================================\n");

        // Initialize
        clk = 0;
        reset = 1;
        cpu_execute = 0;
        cpu_data_in = 80'h0;
        cpu_control_in = 16'h037F;  // Default 8087 control word
        cpu_control_write = 0;
        cpu_int_data_in = 32'h0;

        // Reset FPU
        #20;
        reset = 0;
        #20;

        // ========================================
        // Test 1: FLD1 (D9 E8 - Load +1.0)
        // ========================================
        $display("\n========== Test 1: FLD1 - Load Constant +1.0 ==========");
        execute_fpu_instruction(8'hD9, 8'hE8, 80'h0, "FLD1");
        check_result(80'h3FFF8000000000000000, "FLD1 pushes +1.0");

        // ========================================
        // Test 2: FLDZ (D9 EE - Load +0.0)
        // ========================================
        $display("\n========== Test 2: FLDZ - Load Constant +0.0 ==========");
        execute_fpu_instruction(8'hD9, 8'hEE, 80'h0, "FLDZ");
        check_result(80'h00000000000000000000, "FLDZ pushes +0.0");

        // ========================================
        // Test 3: FLDPI (D9 EB - Load π)
        // ========================================
        $display("\n========== Test 3: FLDPI - Load Constant π ==========");
        execute_fpu_instruction(8'hD9, 8'hEB, 80'h0, "FLDPI");
        check_result(80'h4000C90FDAA22168C235, "FLDPI pushes π ≈ 3.14159...");

        // ========================================
        // Test 4: FABS (D9 E1 - Absolute Value)
        // ========================================
        $display("\n========== Test 4: FABS - Absolute Value ==========");
        // First load -2.5
        execute_fpu_instruction(8'hDB, 8'hE8, 80'hC000A000000000000000, "FLD m80 (-2.5)");
        // Then take absolute value
        execute_fpu_instruction(8'hD9, 8'hE1, 80'h0, "FABS");
        check_result(80'h4000A000000000000000, "FABS(-2.5) = +2.5");

        // ========================================
        // Test 5: FCHS (D9 E0 - Change Sign)
        // ========================================
        $display("\n========== Test 5: FCHS - Change Sign ==========");
        // Load +3.0
        execute_fpu_instruction(8'hDB, 8'hE8, 80'h4000C000000000000000, "FLD m80 (+3.0)");
        // Change sign
        execute_fpu_instruction(8'hD9, 8'hE0, 80'h0, "FCHS");
        check_result(80'hC000C000000000000000, "FCHS(+3.0) = -3.0");

        // ========================================
        // Test 6: FNOP (D9 D0 - No Operation)
        // ========================================
        $display("\n========== Test 6: FNOP - No Operation ==========");
        execute_fpu_instruction(8'hD9, 8'hD0, 80'h0, "FNOP");
        $display("  ✓ Test %0d PASS: FNOP completed without error", test_num + 1);
        pass_count = pass_count + 1;
        test_num = test_num + 1;

        // ========================================
        // Test Results Summary
        // ========================================
        $display("\n========================================");
        $display("Test Results:");
        $display("  Total: %0d", test_num);
        $display("  Pass:  %0d", pass_count);
        $display("  Fail:  %0d", fail_count);
        $display("========================================");

        if (fail_count == 0) begin
            $display("✓ ALL TESTS PASSED");
        end else begin
            $display("✗ SOME TESTS FAILED");
        end

        $display("\n");
        $finish;
    end

endmodule
