`timescale 1ns / 1ps

//=====================================================================
// FPU Integration Testbench
//
// Tests CPU-FPU communication from both sides:
// - CPU to FPU: instruction dispatch, data write
// - FPU to CPU: status read, data read, synchronization
//=====================================================================

module tb_fpu_integration;

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
    reg [255:0] test_name;

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

    //=================================================================
    // Clock Generation
    //=================================================================

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock
    end

    //=================================================================
    // Test Sequence
    //=================================================================

    initial begin
        $display("========================================");
        $display("FPU-CPU Integration Test Suite");
        $display("========================================");

        // Initialize
        test_num = 0;
        passed_tests = 0;
        failed_tests = 0;

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

        // Run tests
        test_cpu_to_fpu_instruction_ack();
        test_cpu_to_fpu_fld_data_transfer();
        test_fpu_to_cpu_fst_data_transfer();
        test_fpu_to_cpu_status_read();
        test_cpu_to_fpu_control_write();
        test_fpu_busy_signal();
        test_fwait_synchronization();
        test_constant_load_fld1();
        test_constant_load_fldpi();
        test_transcendental_timing();
        test_arithmetic_timing();
        test_full_load_compute_store();

        // Summary
        #100;
        $display("");
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests:  %0d", test_num);
        $display("Passed:       %0d", passed_tests);
        $display("Failed:       %0d", failed_tests);
        $display("");

        if (failed_tests == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** %0d TEST(S) FAILED ***", failed_tests);
        end

        $display("");
        $finish;
    end

    //=================================================================
    // Test Tasks
    //=================================================================

    //------------------------------------------------------------------------
    // Test: CPU to FPU - Instruction Acknowledgment
    //------------------------------------------------------------------------
    task test_cpu_to_fpu_instruction_ack;
        begin
            test_num = test_num + 1;
            test_name = "CPU->FPU: Instruction Acknowledgment";
            $display("\n[Test %0d] %0s", test_num, test_name);

            // CPU sends instruction
            cpu_fpu_opcode = 8'hD9;     // FLD1
            cpu_fpu_modrm = 8'hE8;      // FLD1
            cpu_fpu_instr_valid = 1;
            #10;

            // Check ACK
            if (cpu_fpu_instr_ack) begin
                $display("  PASS: FPU acknowledged instruction");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: FPU did not acknowledge instruction");
                failed_tests = failed_tests + 1;
            end

            cpu_fpu_instr_valid = 0;
            #10;
        end
    endtask

    //------------------------------------------------------------------------
    // Test: CPU to FPU - FLD Data Transfer
    //------------------------------------------------------------------------
    task test_cpu_to_fpu_fld_data_transfer;
        begin
            test_num = test_num + 1;
            test_name = "CPU->FPU: FLD Data Transfer";
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Reset FPU
            reset = 1;
            #10;
            reset = 0;
            #10;

            // CPU sends FLD instruction
            cpu_fpu_opcode = 8'hD9;
            cpu_fpu_modrm = 8'h00;      // FLD m32real
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;

            // CPU writes data
            cpu_fpu_data_in = 80'h3FFF8000000000000000; // 1.0 in extended precision
            cpu_fpu_data_size = 3'd1;  // 32-bit (will be converted)
            cpu_fpu_data_write = 1;
            #10;
            cpu_fpu_data_write = 0;

            // Wait for completion
            repeat (100) begin
                if (!cpu_fpu_busy) begin
                    disable wait_fld;
                end
                #10;
            end

            wait_fld: begin
                if (!cpu_fpu_busy) begin
                    $display("  PASS: FLD completed, data transferred to FPU");
                    passed_tests = passed_tests + 1;
                end else begin
                    $display("  FAIL: FLD did not complete");
                    failed_tests = failed_tests + 1;
                end
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Test: FPU to CPU - FST Data Transfer
    //------------------------------------------------------------------------
    task test_fpu_to_cpu_fst_data_transfer;
        begin
            test_num = test_num + 1;
            test_name = "FPU->CPU: FST Data Transfer";
            $display("\n[Test %0d] %0s", test_num, test_name);

            // First load a value (FLD1)
            cpu_fpu_opcode = 8'hD9;
            cpu_fpu_modrm = 8'hE8;      // FLD1
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;

            // Wait for FLD1 to complete
            repeat (100) begin
                if (!cpu_fpu_busy) disable wait_fld1;
                #10;
            end
            wait_fld1: #10;

            // Now FST the value
            cpu_fpu_opcode = 8'hD9;
            cpu_fpu_modrm = 8'h10;      // FST m32real
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;

            // Wait for FST to complete
            repeat (100) begin
                if (!cpu_fpu_busy) disable wait_fst;
                #10;
            end
            wait_fst: #10;

            // Read result
            cpu_fpu_data_read = 1;
            #10;

            if (cpu_fpu_data_ready) begin
                $display("  PASS: FST completed, data: 0x%h", cpu_fpu_data_out);
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: FST data not ready");
                failed_tests = failed_tests + 1;
            end

            cpu_fpu_data_read = 0;
            #10;
        end
    endtask

    //------------------------------------------------------------------------
    // Test: FPU to CPU - Status Word Read
    //------------------------------------------------------------------------
    task test_fpu_to_cpu_status_read;
        begin
            test_num = test_num + 1;
            test_name = "FPU->CPU: Status Word Read";
            $display("\n[Test %0d] %0s", test_num, test_name);

            // FSTSW AX
            cpu_fpu_opcode = 8'hDF;
            cpu_fpu_modrm = 8'hE0;      // FSTSW AX
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;

            // Wait for completion
            repeat (50) begin
                if (!cpu_fpu_busy) disable wait_fstsw;
                #10;
            end
            wait_fstsw: #10;

            // Status word should be available
            $display("  Status word: 0x%04h", cpu_fpu_status_word);

            if (cpu_fpu_status_word[15] == 1'b0) begin
                $display("  PASS: Status word read, busy bit clear");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Status word busy bit still set");
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Test: CPU to FPU - Control Word Write
    //------------------------------------------------------------------------
    task test_cpu_to_fpu_control_write;
        begin
            test_num = test_num + 1;
            test_name = "CPU->FPU: Control Word Write";
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Write control word
            cpu_fpu_control_word = 16'h027F;  // Custom control word
            cpu_fpu_ctrl_write = 1;
            #10;
            cpu_fpu_ctrl_write = 0;
            #10;

            $display("  PASS: Control word written: 0x%04h", cpu_fpu_control_word);
            passed_tests = passed_tests + 1;
        end
    endtask

    //------------------------------------------------------------------------
    // Test: FPU Busy Signal
    //------------------------------------------------------------------------
    task test_fpu_busy_signal;
        begin
            test_num = test_num + 1;
            test_name = "FPU Busy Signal";
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Check initial state
            if (cpu_fpu_busy) begin
                $display("  FAIL: FPU should not be busy initially");
                failed_tests = failed_tests + 1;
            end else begin
                // Start a long operation (FSIN)
                cpu_fpu_opcode = 8'hD9;
                cpu_fpu_modrm = 8'hFE;  // FSIN
                cpu_fpu_instr_valid = 1;
                #10;
                cpu_fpu_instr_valid = 0;
                #10;

                // Check if busy
                if (cpu_fpu_busy) begin
                    $display("  PASS: FPU busy during FSIN execution");

                    // Wait for completion
                    repeat (500) begin
                        if (!cpu_fpu_busy) disable wait_fsin;
                        #10;
                    end
                    wait_fsin: begin
                        $display("  PASS: FPU no longer busy after completion");
                        passed_tests = passed_tests + 1;
                    end
                end else begin
                    $display("  FAIL: FPU should be busy during execution");
                    failed_tests = failed_tests + 1;
                end
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Test: FWAIT Synchronization
    //------------------------------------------------------------------------
    task test_fwait_synchronization;
        begin
            test_num = test_num + 1;
            test_name = "FWAIT Synchronization";
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Start a long operation
            cpu_fpu_opcode = 8'hD9;
            cpu_fpu_modrm = 8'hFE;      // FSIN
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;
            #20;

            // CPU executes FWAIT
            cpu_fpu_wait = 1;

            // Wait for ready
            repeat (500) begin
                if (cpu_fpu_ready) disable wait_ready;
                #10;
            end
            wait_ready: begin
                $display("  PASS: FWAIT completed, FPU ready");
                passed_tests = passed_tests + 1;
            end

            cpu_fpu_wait = 0;
            #10;
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Constant Load FLD1
    //------------------------------------------------------------------------
    task test_constant_load_fld1;
        begin
            test_num = test_num + 1;
            test_name = "Constant Load: FLD1";
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Reset
            reset = 1;
            #10;
            reset = 0;
            #10;

            // FLD1
            cpu_fpu_opcode = 8'hD9;
            cpu_fpu_modrm = 8'hE8;
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;

            // Wait for completion
            repeat (100) begin
                if (!cpu_fpu_busy) disable wait_fld1_const;
                #10;
            end
            wait_fld1_const: begin
                $display("  PASS: FLD1 completed");
                passed_tests = passed_tests + 1;
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Constant Load FLDPI
    //------------------------------------------------------------------------
    task test_constant_load_fldpi;
        begin
            test_num = test_num + 1;
            test_name = "Constant Load: FLDPI";
            $display("\n[Test %0d] %0s", test_num, test_name);

            // FLDPI
            cpu_fpu_opcode = 8'hD9;
            cpu_fpu_modrm = 8'hEB;
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;

            // Wait for completion
            repeat (100) begin
                if (!cpu_fpu_busy) disable wait_fldpi;
                #10;
            end
            wait_fldpi: begin
                $display("  PASS: FLDPI completed");
                passed_tests = passed_tests + 1;
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Transcendental Timing
    //------------------------------------------------------------------------
    task test_transcendental_timing;
        integer cycles;
        begin
            test_num = test_num + 1;
            test_name = "Transcendental Timing (FSIN)";
            $display("\n[Test %0d] %0s", test_num, test_name);

            // FSIN
            cpu_fpu_opcode = 8'hD9;
            cpu_fpu_modrm = 8'hFE;
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;

            // Count cycles
            cycles = 0;
            repeat (500) begin
                if (!cpu_fpu_busy) disable wait_fsin_timing;
                #10;
                cycles = cycles + 1;
            end
            wait_fsin_timing: begin
                $display("  FSIN completed in %0d cycles", cycles);
                if (cycles >= 200) begin
                    $display("  PASS: FSIN timing realistic");
                    passed_tests = passed_tests + 1;
                end else begin
                    $display("  FAIL: FSIN completed too quickly");
                    failed_tests = failed_tests + 1;
                end
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Arithmetic Timing
    //------------------------------------------------------------------------
    task test_arithmetic_timing;
        integer cycles;
        begin
            test_num = test_num + 1;
            test_name = "Arithmetic Timing (FDIV)";
            $display("\n[Test %0d] %0s", test_num, test_name);

            // FDIV ST(0), ST(1)
            cpu_fpu_opcode = 8'hD8;
            cpu_fpu_modrm = 8'hF1;
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;

            // Count cycles
            cycles = 0;
            repeat (500) begin
                if (!cpu_fpu_busy) disable wait_fdiv;
                #10;
                cycles = cycles + 1;
            end
            wait_fdiv: begin
                $display("  FDIV completed in %0d cycles", cycles);
                if (cycles >= 150) begin
                    $display("  PASS: FDIV timing realistic");
                    passed_tests = passed_tests + 1;
                end else begin
                    $display("  FAIL: FDIV completed too quickly");
                    failed_tests = failed_tests + 1;
                end
            end
        end
    endtask

    //------------------------------------------------------------------------
    // Test: Full Load-Compute-Store Sequence
    //------------------------------------------------------------------------
    task test_full_load_compute_store;
        begin
            test_num = test_num + 1;
            test_name = "Full Load-Compute-Store Sequence";
            $display("\n[Test %0d] %0s", test_num, test_name);

            // Reset
            reset = 1;
            #10;
            reset = 0;
            #10;

            // 1. Load value 1
            cpu_fpu_opcode = 8'hD9;
            cpu_fpu_modrm = 8'hE8;      // FLD1
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;
            repeat (100) begin
                if (!cpu_fpu_busy) disable wait_load1;
                #10;
            end
            wait_load1: $display("  Step 1: Loaded value");

            // 2. Load value 2
            cpu_fpu_opcode = 8'hD9;
            cpu_fpu_modrm = 8'hE8;      // FLD1
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;
            repeat (100) begin
                if (!cpu_fpu_busy) disable wait_load2;
                #10;
            end
            wait_load2: $display("  Step 2: Loaded second value");

            // 3. Add them
            cpu_fpu_opcode = 8'hD8;
            cpu_fpu_modrm = 8'hC1;      // FADD ST(0), ST(1)
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;
            repeat (150) begin
                if (!cpu_fpu_busy) disable wait_add;
                #10;
            end
            wait_add: $display("  Step 3: Added values");

            // 4. Store result
            cpu_fpu_opcode = 8'hD9;
            cpu_fpu_modrm = 8'h10;      // FST m32real
            cpu_fpu_instr_valid = 1;
            #10;
            cpu_fpu_instr_valid = 0;
            repeat (100) begin
                if (!cpu_fpu_busy) disable wait_store;
                #10;
            end
            wait_store: #10;

            // 5. Read result
            cpu_fpu_data_read = 1;
            #10;

            if (cpu_fpu_data_ready) begin
                $display("  Step 4: Stored result: 0x%h", cpu_fpu_data_out);
                $display("  PASS: Full sequence completed");
                passed_tests = passed_tests + 1;
            end else begin
                $display("  FAIL: Result not available");
                failed_tests = failed_tests + 1;
            end

            cpu_fpu_data_read = 0;
            #10;
        end
    endtask

    //=================================================================
    // Waveform Dump
    //=================================================================

    initial begin
        $dumpfile("tb_fpu_integration.vcd");
        $dumpvars(0, tb_fpu_integration);
    end

endmodule
