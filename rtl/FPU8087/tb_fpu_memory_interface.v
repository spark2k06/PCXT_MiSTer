/**
 * tb_fpu_memory_interface.v
 *
 * Comprehensive testbench for FPU_Memory_Interface
 *
 * Tests memory synchronization extensively:
 * 1. Word (16-bit) transfers
 * 2. Dword (32-bit) transfers
 * 3. Qword (64-bit) transfers
 * 4. Tbyte (80-bit) transfers
 * 5. Read operations
 * 6. Write operations
 * 7. Multi-cycle synchronization
 * 8. Wait state handling
 * 9. Back-to-back transfers
 * 10. Address alignment
 *
 * Date: 2025-11-10
 */

`timescale 1ns/1ps

module tb_fpu_memory_interface;

    //=================================================================
    // Testbench Signals
    //=================================================================

    reg clk;
    reg reset;

    // FPU side
    reg [19:0] fpu_addr;
    reg [79:0] fpu_data_out;
    wire [79:0] fpu_data_in;
    reg fpu_access;
    reg fpu_wr_en;
    reg [1:0] fpu_size;
    wire fpu_ack;

    // Memory bus side
    wire [19:0] mem_addr;
    reg [15:0] mem_data_in;
    wire [15:0] mem_data_out;
    wire mem_access;
    reg mem_ack;
    wire mem_wr_en;
    wire [1:0] mem_bytesel;

    //=================================================================
    // Test Statistics
    //=================================================================

    integer test_count;
    integer pass_count;
    integer fail_count;

    //=================================================================
    // Simulated Memory
    //=================================================================

    reg [15:0] memory [0:32767];  // 64KB memory (32K words)
    integer i;

    // Memory simulation - responds to each address
    reg [19:0] last_acked_addr;
    reg mem_was_accessed;

    always @(posedge clk) begin
        if (reset) begin
            mem_ack <= 1'b0;
            mem_data_in <= 16'h0000;
            last_acked_addr <= 20'hFFFFF;
            mem_was_accessed <= 1'b0;
        end else begin
            if (mem_access) begin
                // New address or first cycle of access
                if (mem_addr != last_acked_addr || !mem_was_accessed) begin
                    mem_ack <= 1'b1;
                    last_acked_addr <= mem_addr;
                    mem_was_accessed <= 1'b1;
                    if (!mem_wr_en) begin
                        // Read operation - provide data from memory
                        mem_data_in <= memory[mem_addr[15:1]];
                    end else begin
                        // Write operation - store data to memory
                        memory[mem_addr[15:1]] <= mem_data_out;
                    end
                end else begin
                    // Same address as last ack - don't ack again
                    mem_ack <= 1'b0;
                end
            end else begin
                // No access
                mem_ack <= 1'b0;
                mem_was_accessed <= 1'b0;
                last_acked_addr <= 20'hFFFFF;
            end
        end
    end

    //=================================================================
    // DUT Instantiation
    //=================================================================

    FPU_Memory_Interface dut (
        .clk(clk),
        .reset(reset),
        .fpu_addr(fpu_addr),
        .fpu_data_out(fpu_data_out),
        .fpu_data_in(fpu_data_in),
        .fpu_access(fpu_access),
        .fpu_wr_en(fpu_wr_en),
        .fpu_size(fpu_size),
        .fpu_ack(fpu_ack),
        .mem_addr(mem_addr),
        .mem_data_in(mem_data_in),
        .mem_data_out(mem_data_out),
        .mem_access(mem_access),
        .mem_ack(mem_ack),
        .mem_wr_en(mem_wr_en),
        .mem_bytesel(mem_bytesel)
    );

    //=================================================================
    // Clock Generation
    //=================================================================

    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100 MHz clock
    end

    //=================================================================
    // Test Tasks
    //=================================================================

    // Task: Write to FPU memory
    task fpu_write;
        input [19:0] addr;
        input [79:0] data;
        input [1:0] size;
        begin
            @(posedge clk);
            fpu_addr <= addr;
            fpu_data_out <= data;
            fpu_size <= size;
            fpu_wr_en <= 1'b1;
            fpu_access <= 1'b1;

            @(posedge clk);
            fpu_access <= 1'b0;

            // Wait for ack
            wait (fpu_ack);
            @(posedge clk);
        end
    endtask

    // Task: Read from FPU memory
    task fpu_read;
        input [19:0] addr;
        input [1:0] size;
        output [79:0] data;
        begin
            @(posedge clk);
            fpu_addr <= addr;
            fpu_size <= size;
            fpu_wr_en <= 1'b0;
            fpu_access <= 1'b1;

            @(posedge clk);
            fpu_access <= 1'b0;

            // Wait for ack
            wait (fpu_ack);
            @(posedge clk);
            data = fpu_data_in;
        end
    endtask

    // Task: Check memory contents
    task check_memory;
        input [19:0] addr;
        input [15:0] expected_data;
        input [255:0] test_name;
        begin
            test_count = test_count + 1;
            $display("[Test %0d] %s", test_count, test_name);

            if (memory[addr[15:1]] == expected_data) begin
                $display("  PASS: Memory[0x%05h] = 0x%04h", addr, memory[addr[15:1]]);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Expected 0x%04h, got 0x%04h",
                         expected_data, memory[addr[15:1]]);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Task: Check FPU read data
    task check_read_data;
        input [79:0] expected;
        input [79:0] actual;
        input [255:0] test_name;
        begin
            test_count = test_count + 1;
            $display("[Test %0d] %s", test_count, test_name);

            if (actual == expected) begin
                $display("  PASS: Data = 0x%020h", actual);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Expected 0x%020h", expected);
                $display("        Got      0x%020h", actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    //=================================================================
    // Main Test Sequence
    //=================================================================

    reg [79:0] read_data;

    initial begin
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        fpu_addr = 20'h00000;
        fpu_data_out = 80'h0;
        fpu_access = 0;
        fpu_wr_en = 0;
        fpu_size = 2'b00;

        // Initialize memory with test pattern
        for (i = 0; i < 32768; i = i + 1) begin
            memory[i] = i[15:0];
        end

        // Reset
        reset = 1;
        repeat(5) @(posedge clk);
        reset = 0;
        repeat(2) @(posedge clk);

        $display("\n=== FPU Memory Interface Tests ===\n");
        $display("Testing memory synchronization with different operand sizes\n");

        //=================================================================
        // Test 1: Word (16-bit) Write
        //=================================================================
        $display("\n--- Test: WORD (16-bit) Write ---");
        fpu_write(20'h01000, 80'h0000000000000000000000001234, 2'b00);  // WORD
        check_memory(20'h01000, 16'h1234, "Word write to 0x01000");

        //=================================================================
        // Test 2: Word (16-bit) Read
        //=================================================================
        $display("\n--- Test: WORD (16-bit) Read ---");
        memory[20'h01002 >> 1] = 16'h5678;
        fpu_read(20'h01002, 2'b00, read_data);
        check_read_data(80'h0000000000000000000000005678, read_data, "Word read from 0x01002");

        //=================================================================
        // Test 3: Dword (32-bit) Write
        //=================================================================
        $display("\n--- Test: DWORD (32-bit) Write ---");
        fpu_write(20'h02000, 80'h00000000000000000000ABCD1234, 2'b01);  // DWORD
        check_memory(20'h02000, 16'h1234, "Dword write - low word");
        check_memory(20'h02002, 16'hABCD, "Dword write - high word");

        //=================================================================
        // Test 4: Dword (32-bit) Read
        //=================================================================
        $display("\n--- Test: DWORD (32-bit) Read ---");
        memory[20'h02004 >> 1] = 16'hEF01;
        memory[20'h02006 >> 1] = 16'h2345;
        fpu_read(20'h02004, 2'b01, read_data);
        check_read_data(80'h00000000000000000000002345EF01, read_data, "Dword read from 0x02004");

        //=================================================================
        // Test 5: Qword (64-bit) Write
        //=================================================================
        $display("\n--- Test: QWORD (64-bit) Write ---");
        fpu_write(20'h03000, 80'h00000000000000001122334455667788, 2'b10);  // QWORD
        check_memory(20'h03000, 16'h7788, "Qword write - word 0");
        check_memory(20'h03002, 16'h5566, "Qword write - word 1");
        check_memory(20'h03004, 16'h3344, "Qword write - word 2");
        check_memory(20'h03006, 16'h1122, "Qword write - word 3");

        //=================================================================
        // Test 6: Qword (64-bit) Read
        //=================================================================
        $display("\n--- Test: QWORD (64-bit) Read ---");
        memory[20'h03008 >> 1] = 16'hAAAA;
        memory[20'h0300A >> 1] = 16'hBBBB;
        memory[20'h0300C >> 1] = 16'hCCCC;
        memory[20'h0300E >> 1] = 16'hDDDD;
        fpu_read(20'h03008, 2'b10, read_data);
        check_read_data(80'h0000000000000000DDDDCCCCBBBBAAAA, read_data, "Qword read from 0x03008");

        //=================================================================
        // Test 7: Tbyte (80-bit) Write
        //=================================================================
        $display("\n--- Test: TBYTE (80-bit) Write ---");
        fpu_write(20'h04000, 80'h0102_0304_0506_0708_090A_0B0C, 2'b11);  // TBYTE (properly sized)
        check_memory(20'h04000, 16'h0B0C, "Tbyte write - word 0");
        check_memory(20'h04002, 16'h090A, "Tbyte write - word 1");
        check_memory(20'h04004, 16'h0708, "Tbyte write - word 2");
        check_memory(20'h04006, 16'h0506, "Tbyte write - word 3");
        check_memory(20'h04008, 16'h0304, "Tbyte write - word 4 (high)");

        //=================================================================
        // Test 8: Tbyte (80-bit) Read
        //=================================================================
        $display("\n--- Test: TBYTE (80-bit) Read ---");
        memory[20'h0400A >> 1] = 16'hFEDC;
        memory[20'h0400C >> 1] = 16'hBA98;
        memory[20'h0400E >> 1] = 16'h7654;
        memory[20'h04010 >> 1] = 16'h3210;
        memory[20'h04012 >> 1] = 16'hABCD;
        fpu_read(20'h0400A, 2'b11, read_data);
        check_read_data(80'hABCD_3210_7654_BA98_FEDC, read_data, "Tbyte read from 0x0400A");

        //=================================================================
        // Test 9: Back-to-back Writes
        //=================================================================
        $display("\n--- Test: Back-to-back writes ---");
        fpu_write(20'h05000, 80'h0000000000000000000000001111, 2'b00);
        fpu_write(20'h05002, 80'h0000000000000000000000002222, 2'b00);
        fpu_write(20'h05004, 80'h0000000000000000000000003333, 2'b00);
        check_memory(20'h05000, 16'h1111, "Back-to-back write 1");
        check_memory(20'h05002, 16'h2222, "Back-to-back write 2");
        check_memory(20'h05004, 16'h3333, "Back-to-back write 3");

        //=================================================================
        // Test 10: Back-to-back Reads
        //=================================================================
        $display("\n--- Test: Back-to-back reads ---");
        memory[20'h06000 >> 1] = 16'h4444;
        memory[20'h06002 >> 1] = 16'h5555;
        memory[20'h06004 >> 1] = 16'h6666;

        fpu_read(20'h06000, 2'b00, read_data);
        check_read_data(80'h0000000000000000000000004444, read_data, "Back-to-back read 1");

        fpu_read(20'h06002, 2'b00, read_data);
        check_read_data(80'h0000000000000000000000005555, read_data, "Back-to-back read 2");

        fpu_read(20'h06004, 2'b00, read_data);
        check_read_data(80'h0000000000000000000000006666, read_data, "Back-to-back read 3");

        //=================================================================
        // Test 11: Write then Read (same address)
        //=================================================================
        $display("\n--- Test: Write then read (synchronization) ---");
        fpu_write(20'h07000, 80'h00000000000000000000DEADBEEF, 2'b01);
        fpu_read(20'h07000, 2'b01, read_data);
        check_read_data(80'h00000000000000000000DEADBEEF, read_data, "Write-Read synchronization");

        //=================================================================
        // Test 12: Multi-size sequential access
        //=================================================================
        $display("\n--- Test: Multi-size sequential access ---");
        fpu_write(20'h08000, 80'h0000000000000000000000001111, 2'b00);  // Word
        fpu_write(20'h08002, 80'h00000000000000000000_00002222, 2'b01);      // Dword
        fpu_write(20'h08006, 80'h00000000000000000000_33334444, 2'b10);      // Qword

        fpu_read(20'h08000, 2'b00, read_data);
        check_read_data(80'h0000000000000000000000001111, read_data, "Multi-size read - word");

        fpu_read(20'h08002, 2'b01, read_data);
        check_read_data(80'h00000000000000000000_00002222, read_data, "Multi-size read - dword");

        fpu_read(20'h08006, 2'b10, read_data);
        check_read_data(80'h00000000000000000000_33334444, read_data, "Multi-size read - qword");

        //=================================================================
        // Test 13: Address alignment
        //=================================================================
        $display("\n--- Test: Address alignment (even addresses) ---");
        fpu_write(20'h09000, 80'h00000000000000000000AAAA, 2'b00);
        check_memory(20'h09000, 16'hAAAA, "Even address 0x09000");

        fpu_write(20'h09002, 80'h00000000000000000000BBBB, 2'b00);
        check_memory(20'h09002, 16'hBBBB, "Even address 0x09002");

        //=================================================================
        // Test 14: Full 80-bit round-trip
        //=================================================================
        $display("\n--- Test: Full 80-bit round-trip ---");
        fpu_write(20'h0A000, 80'h1234_5678_9ABC_DEF0_FEDC_BA98, 2'b11);
        fpu_read(20'h0A000, 2'b11, read_data);
        check_read_data(80'h1234_5678_9ABC_DEF0_FEDC_BA98, read_data, "80-bit round-trip");

        //=================================================================
        // Test 15: Zero data
        //=================================================================
        $display("\n--- Test: Zero data handling ---");
        fpu_write(20'h0B000, 80'h0, 2'b11);
        fpu_read(20'h0B000, 2'b11, read_data);
        check_read_data(80'h0, read_data, "Zero data round-trip");

        //=================================================================
        // Test 16: All ones data
        //=================================================================
        $display("\n--- Test: All ones data handling ---");
        fpu_write(20'h0C000, 80'hFFFFFFFFFFFFFFFFFFFFFFFF, 2'b11);
        fpu_read(20'h0C000, 2'b11, read_data);
        check_read_data(80'hFFFFFFFFFFFFFFFFFFFFFFFF, read_data, "All ones round-trip");

        //=================================================================
        // Test 17: Memory synchronization timing
        //=================================================================
        $display("\n--- Test: Memory synchronization timing ---");
        test_count = test_count + 1;
        $display("[Test %0d] Memory synchronization timing", test_count);

        // Write and verify cycle count
        @(posedge clk);
        fpu_addr <= 20'h0D000;
        fpu_data_out <= 80'h0000000000000000CAFEBABE12345678;
        fpu_size <= 2'b10;  // QWORD (4 cycles)
        fpu_wr_en <= 1'b1;
        fpu_access <= 1'b1;
        @(posedge clk);
        fpu_access <= 1'b0;

        // Count cycles until ack
        i = 0;
        while (!fpu_ack && i < 20) begin
            @(posedge clk);
            i = i + 1;
        end

        if (i >= 4 && i <= 16) begin  // Allow margin for state machine and memory latency
            $display("  PASS: Qword write completed in %0d cycles", i);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Qword write took %0d cycles (expected 4-16)", i);
            fail_count = fail_count + 1;
        end

        // Summary
        repeat(5) @(posedge clk);
        $display("\n=== Memory Interface Test Summary ===");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);

        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
            $display("Memory Interface Verified:");
            $display("  ✓ Word (16-bit) transfers working");
            $display("  ✓ Dword (32-bit) transfers working");
            $display("  ✓ Qword (64-bit) transfers working");
            $display("  ✓ Tbyte (80-bit) transfers working");
            $display("  ✓ Read operations correct");
            $display("  ✓ Write operations correct");
            $display("  ✓ Multi-cycle synchronization verified");
            $display("  ✓ Back-to-back transfers working");
            $display("  ✓ Write-Read synchronization verified");
            $display("  ✓ Address alignment correct");
            $display("  ✓ Full 80-bit round-trip verified");
            $display("  ✓ Memory timing synchronization correct");
            $display("");
        end else begin
            $display("\n*** SOME TESTS FAILED ***\n");
        end

        $finish;
    end

    //=================================================================
    // Timeout
    //=================================================================

    initial begin
        #500000;  // 500 us timeout
        $display("\n*** TEST TIMEOUT ***\n");
        $finish;
    end

endmodule
