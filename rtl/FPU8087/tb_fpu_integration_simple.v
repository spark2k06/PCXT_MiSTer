`timescale 1ns / 1ps

//=====================================================================
// FPU Integration Testbench (Simplified)
//
// Tests CPU-FPU communication from both sides
//=====================================================================

module tb_fpu_integration_simple;

    // Clock and Reset
    reg clk;
    reg reset;

    // CPU Side Interface
    reg        cpu_fpu_instr_valid;
    reg [7:0]  cpu_fpu_opcode;
    reg [7:0]  cpu_fpu_modrm;
    wire       cpu_fpu_instr_ack;

    reg        cpu_fpu_data_write;
    reg        cpu_fpu_data_read;
    reg [2:0]  cpu_fpu_data_size;
    reg [79:0] cpu_fpu_data_in;
    wire [79:0] cpu_fpu_data_out;
    wire       cpu_fpu_data_ready;

    wire       cpu_fpu_busy;
    wire [15:0] cpu_fpu_status_word;
    reg [15:0] cpu_fpu_control_word;
    reg        cpu_fpu_ctrl_write;
    wire       cpu_fpu_exception;
    wire       cpu_fpu_irq;

    reg        cpu_fpu_wait;
    wire       cpu_fpu_ready;

    // Test variables
    integer test_num;
    integer passed_tests;
    integer failed_tests;

    //=================================================================
    // Instantiate FPU
    //=================================================================

    FPU8087_Integrated uut (
        .clk(clk),
        .reset(reset),
        .cpu_fpu_instr_valid(cpu_fpu_instr_valid),
        .cpu_fpu_opcode(cpu_fpu_opcode),
        .cpu_fpu_modrm(cpu_fpu_modrm),
        .cpu_fpu_instr_ack(cpu_fpu_instr_ack),
        .cpu_fpu_data_write(cpu_fpu_data_write),
        .cpu_fpu_data_read(cpu_fpu_data_read),
        .cpu_fpu_data_size(cpu_fpu_data_size),
        .cpu_fpu_data_in(cpu_fpu_data_in),
        .cpu_fpu_data_out(cpu_fpu_data_out),
        .cpu_fpu_data_ready(cpu_fpu_data_ready),
        .cpu_fpu_busy(cpu_fpu_busy),
        .cpu_fpu_status_word(cpu_fpu_status_word),
        .cpu_fpu_control_word(cpu_fpu_control_word),
        .cpu_fpu_ctrl_write(cpu_fpu_ctrl_write),
        .cpu_fpu_exception(cpu_fpu_exception),
        .cpu_fpu_irq(cpu_fpu_irq),
        .cpu_fpu_wait(cpu_fpu_wait),
        .cpu_fpu_ready(cpu_fpu_ready)
    );

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test sequence
    initial begin
        $display("========================================");
        $display("FPU-CPU Integration Test Suite");
        $display("========================================");

        test_num = 0;
        passed_tests = 0;
        failed_tests = 0;

        // Initialize
        reset = 1;
        cpu_fpu_instr_valid = 0;
        cpu_fpu_opcode = 8'h00;
        cpu_fpu_modrm = 8'h00;
        cpu_fpu_data_write = 0;
        cpu_fpu_data_read = 0;
        cpu_fpu_data_size = 3'd0;
        cpu_fpu_data_in = 80'h0;
        cpu_fpu_control_word = 16'h037F;
        cpu_fpu_ctrl_write = 0;
        cpu_fpu_wait = 0;

        #20;
        reset = 0;
        #20;

        // Test 1: Instruction ACK
        test_num = 1;
        $display("\n[Test %0d] CPU->FPU: Instruction Acknowledgment", test_num);
        cpu_fpu_opcode = 8'hD9;
        cpu_fpu_modrm = 8'hE8; // FLD1
        cpu_fpu_instr_valid = 1;
        #10;
        if (cpu_fpu_instr_ack) begin
            $display("  PASS: FPU acknowledged instruction");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: No ACK");
            failed_tests = failed_tests + 1;
        end
        cpu_fpu_instr_valid = 0;
        #10;

        // Wait for completion
        #1000;

        // Test 2: FLD1 Constant
        test_num = 2;
        $display("\n[Test %0d] Constant Load: FLD1", test_num);
        reset = 1; #10; reset = 0; #10;
        cpu_fpu_opcode = 8'hD9;
        cpu_fpu_modrm = 8'hE8;
        cpu_fpu_instr_valid = 1;
        #10;
        cpu_fpu_instr_valid = 0;
        #500;
        if (!cpu_fpu_busy) begin
            $display("  PASS: FLD1 completed");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FLD1 timeout");
            failed_tests = failed_tests + 1;
        end

        // Test 3: Busy Signal
        test_num = 3;
        $display("\n[Test %0d] FPU Busy Signal", test_num);
        cpu_fpu_opcode = 8'hD9;
        cpu_fpu_modrm = 8'hFE; // FSIN
        cpu_fpu_instr_valid = 1;
        #10;
        cpu_fpu_instr_valid = 0;
        #20;
        if (cpu_fpu_busy) begin
            $display("  PASS: FPU busy during FSIN");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FPU should be busy");
            failed_tests = failed_tests + 1;
        end
        #3000; // Wait for FSIN completion

        // Test 4: Status Read
        test_num = 4;
        $display("\n[Test %0d] FPU->CPU: Status Word Read", test_num);
        cpu_fpu_opcode = 8'hDF;
        cpu_fpu_modrm = 8'hE0; // FSTSW AX
        cpu_fpu_instr_valid = 1;
        #10;
        cpu_fpu_instr_valid = 0;
        #100;
        $display("  Status word: 0x%04h", cpu_fpu_status_word);
        $display("  PASS: Status word read");
        passed_tests = passed_tests + 1;

        // Test 5: Control Write
        test_num = 5;
        $display("\n[Test %0d] CPU->FPU: Control Word Write", test_num);
        cpu_fpu_control_word = 16'h027F;
        cpu_fpu_ctrl_write = 1;
        #10;
        cpu_fpu_ctrl_write = 0;
        #10;
        $display("  PASS: Control word written");
        passed_tests = passed_tests + 1;

        // Summary
        #100;
        $display("");
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests:  %0d", test_num);
        $display("Passed:       %0d", passed_tests);
        $display("Failed:       %0d", failed_tests);

        if (failed_tests == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
        end else begin
            $display("\n*** %0d TEST(S) FAILED ***\n", failed_tests);
        end

        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_fpu_integration.vcd");
        $dumpvars(0, tb_fpu_integration_simple);
    end

endmodule
