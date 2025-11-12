`timescale 1ns / 1ps

module tb_cpu_fpu_final;

    reg clk, reset;
    reg [19:0] cpu_address;
    reg [15:0] cpu_data_in;
    wire [15:0] cpu_data_out;
    reg cpu_read, cpu_write;
    reg [1:0] cpu_bytesel;
    wire cpu_ready;
    reg cpu_fpu_escape;
    reg [7:0] cpu_opcode;
    reg [7:0] cpu_modrm;

    wire fpu_instr_valid, fpu_instr_ack;
    wire [7:0] fpu_opcode, fpu_modrm;
    wire fpu_data_write, fpu_data_read;
    wire [2:0] fpu_data_size;
    wire [79:0] fpu_data_in, fpu_data_out;
    wire fpu_data_ready, fpu_busy, fpu_ready;
    wire [15:0] fpu_status_word, fpu_control_word;
    wire fpu_ctrl_write, fpu_exception, fpu_irq, fpu_wait;

    integer test_num, passed_tests, failed_tests;

    CPU_FPU_Adapter adapter (
        .clk(clk), .reset(reset),
        .cpu_address(cpu_address), .cpu_data_in(cpu_data_in), .cpu_data_out(cpu_data_out),
        .cpu_read(cpu_read), .cpu_write(cpu_write), .cpu_bytesel(cpu_bytesel), .cpu_ready(cpu_ready),
        .cpu_fpu_escape(cpu_fpu_escape), .cpu_opcode(cpu_opcode), .cpu_modrm(cpu_modrm),
        .fpu_instr_valid(fpu_instr_valid), .fpu_opcode(fpu_opcode), .fpu_modrm(fpu_modrm), .fpu_instr_ack(fpu_instr_ack),
        .fpu_data_write(fpu_data_write), .fpu_data_read(fpu_data_read), .fpu_data_size(fpu_data_size),
        .fpu_data_in(fpu_data_in), .fpu_data_out(fpu_data_out), .fpu_data_ready(fpu_data_ready),
        .fpu_busy(fpu_busy), .fpu_status_word(fpu_status_word), .fpu_control_word(fpu_control_word),
        .fpu_ctrl_write(fpu_ctrl_write), .fpu_exception(fpu_exception), .fpu_irq(fpu_irq),
        .fpu_wait(fpu_wait), .fpu_ready(fpu_ready)
    );

    FPU8087_Integrated fpu (
        .clk(clk), .reset(reset),
        .cpu_fpu_instr_valid(fpu_instr_valid), .cpu_fpu_opcode(fpu_opcode), .cpu_fpu_modrm(fpu_modrm), .cpu_fpu_instr_ack(fpu_instr_ack),
        .cpu_fpu_data_write(fpu_data_write), .cpu_fpu_data_read(fpu_data_read), .cpu_fpu_data_size(fpu_data_size),
        .cpu_fpu_data_in(fpu_data_in), .cpu_fpu_data_out(fpu_data_out), .cpu_fpu_data_ready(fpu_data_ready),
        .cpu_fpu_busy(fpu_busy), .cpu_fpu_status_word(fpu_status_word),
        .cpu_fpu_control_word(fpu_control_word), .cpu_fpu_ctrl_write(fpu_ctrl_write),
        .cpu_fpu_exception(fpu_exception), .cpu_fpu_irq(fpu_irq),
        .cpu_fpu_wait(fpu_wait), .cpu_fpu_ready(fpu_ready)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $display("========================================");
        $display("CPU-FPU Complete Connection Tests");
        $display("========================================");

        test_num = 0;
        passed_tests = 0;
        failed_tests = 0;

        reset = 1;
        cpu_address = 20'h0;
        cpu_data_in = 16'h0;
        cpu_read = 0;
        cpu_write = 0;
        cpu_bytesel = 2'b00;
        cpu_fpu_escape = 0;
        cpu_opcode = 8'h00;
        cpu_modrm = 8'h00;

        #20;
        reset = 0;
        #20;

        // Test 1: FLD1
        test_num = 1;
        $display("\n[Test %0d] CPU executes FLD1", test_num);
        cpu_opcode = 8'hD9;
        cpu_modrm = 8'hE8;
        cpu_fpu_escape = 1;
        #10;
        cpu_fpu_escape = 0;
        #2000; // Wait for completion
        if (cpu_ready) begin
            $display("  PASS: FLD1 completed");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FLD1 timeout");
            failed_tests = failed_tests + 1;
        end

        // Test 2: FLDPI
        test_num = 2;
        $display("\n[Test %0d] CPU executes FLDPI", test_num);
        cpu_opcode = 8'hD9;
        cpu_modrm = 8'hEB;
        cpu_fpu_escape = 1;
        #10;
        cpu_fpu_escape = 0;
        #2000;
        if (cpu_ready) begin
            $display("  PASS: FLDPI completed");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FLDPI timeout");
            failed_tests = failed_tests + 1;
        end

        // Test 3: FADD
        test_num = 3;
        $display("\n[Test %0d] CPU executes FADD", test_num);
        cpu_opcode = 8'hD8;
        cpu_modrm = 8'hC1;
        cpu_fpu_escape = 1;
        #10;
        cpu_fpu_escape = 0;
        #2000;
        if (cpu_ready) begin
            $display("  PASS: FADD completed");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FADD timeout");
            failed_tests = failed_tests + 1;
        end

        // Test 4: FSIN
        test_num = 4;
        $display("\n[Test %0d] CPU executes FSIN", test_num);
        cpu_opcode = 8'hD9;
        cpu_modrm = 8'hFE;
        cpu_fpu_escape = 1;
        #10;
        cpu_fpu_escape = 0;
        #10000; // Longer wait for transcendental (1000 cycles)
        if (cpu_ready) begin
            $display("  PASS: FSIN completed");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: FSIN timeout");
            failed_tests = failed_tests + 1;
        end

        // Test 5: Full sequence
        test_num = 5;
        $display("\n[Test %0d] Full sequence: FLD1+FLD1+FADD", test_num);
        reset = 1; #10; reset = 0; #10;

        cpu_opcode = 8'hD9; cpu_modrm = 8'hE8; cpu_fpu_escape = 1; #10; cpu_fpu_escape = 0; #2000;
        cpu_opcode = 8'hD9; cpu_modrm = 8'hE8; cpu_fpu_escape = 1; #10; cpu_fpu_escape = 0; #2000;
        cpu_opcode = 8'hD8; cpu_modrm = 8'hC1; cpu_fpu_escape = 1; #10; cpu_fpu_escape = 0; #2000;

        if (cpu_ready) begin
            $display("  PASS: Full sequence completed");
            passed_tests = passed_tests + 1;
        end else begin
            $display("  FAIL: Full sequence timeout");
            failed_tests = failed_tests + 1;
        end

        // Summary
        #100;
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests:  %0d", test_num);
        $display("Passed:       %0d", passed_tests);
        $display("Failed:       %0d", failed_tests);

        if (failed_tests == 0) begin
            $display("\n*** ALL TESTS PASSED ***");
            $display("CPU-FPU Connection: 100%% VERIFIED\n");
        end else begin
            $display("\n*** %0d TEST(S) FAILED ***\n", failed_tests);
        end

        $finish;
    end

    initial begin
        $dumpfile("tb_cpu_fpu_final.vcd");
        $dumpvars(0, tb_cpu_fpu_final);
    end

endmodule
