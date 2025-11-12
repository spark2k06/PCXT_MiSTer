`timescale 1ns / 1ps

//=====================================================================
// Testbench for FPU8087 Trivial Instructions
// Tests constants, FABS, FCHS with proper stack operations
//=====================================================================

module tb_fpu8087_trivial;

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

    // Clock
    always #5 clk = ~clk;

    // Test counters
    integer pass_count = 0;
    integer fail_count = 0;

    // Execute FPU instruction
    task exec;
        input [7:0] opcode;
        input [7:0] modrm;
        input [79:0] data;
        begin
            @(posedge clk);
            cpu_opcode = opcode;
            cpu_modrm = modrm;
            cpu_data_in = data;
            cpu_execute = 1'b1;
            @(posedge clk);
            cpu_execute = 1'b0;
            wait (cpu_ready);
            @(posedge clk);
        end
    endtask

    // Check result
    task check;
        input [79:0] expected;
        input [255:0] name;
        begin
            if (cpu_data_out == expected) begin
                $display("  ✓ PASS: %s", name);
                pass_count = pass_count + 1;
            end else begin
                $display("  ✗ FAIL: %s", name);
                $display("    Expected: %020X", expected);
                $display("    Got:      %020X", cpu_data_out);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $display("========================================");
        $display("FPU8087 Trivial Instructions Test");
        $display("Real 8087 Opcodes with Stack Operations");
        $display("========================================\n");

        clk = 0;
        reset = 1;
        cpu_execute = 0;
        cpu_data_in = 80'h0;
        cpu_control_in = 16'h037F;
        cpu_control_write = 0;
        cpu_int_data_in = 32'h0;

        #20;
        reset = 0;
        #20;

        //=================================================================
        // Test 1: FLD1 → FSTP (Load 1.0, Store and Pop)
        //=================================================================
        $display("Test 1: FLD1 (D9 E8) → FSTP m80 (DB ED)");
        exec(8'hD9, 8'hE8, 80'h0);  // FLD1
        exec(8'hDB, 8'hED, 80'h0);  // FSTP m80 (pops to memory/data_out)
        check(80'h3FFF8000000000000000, "FLD1 = +1.0");

        //=================================================================
        // Test 2: FLDZ → FSTP (Load 0.0, Store and Pop)
        //=================================================================
        $display("\nTest 2: FLDZ (D9 EE) → FSTP m80");
        exec(8'hD9, 8'hEE, 80'h0);  // FLDZ
        exec(8'hDB, 8'hED, 80'h0);  // FSTP m80
        check(80'h00000000000000000000, "FLDZ = +0.0");

        //=================================================================
        // Test 3: FLDPI → FSTP (Load π, Store and Pop)
        //=================================================================
        $display("\nTest 3: FLDPI (D9 EB) → FSTP m80");
        exec(8'hD9, 8'hEB, 80'h0);  // FLDPI
        exec(8'hDB, 8'hED, 80'h0);  // FSTP m80
        check(80'h4000C90FDAA22168C235, "FLDPI = π ≈ 3.14159");

        //=================================================================
        // Test 4: FLDL2T → FSTP (Load log₂(10))
        //=================================================================
        $display("\nTest 4: FLDL2T (D9 E9) → FSTP m80");
        exec(8'hD9, 8'hE9, 80'h0);  // FLDL2T
        exec(8'hDB, 8'hED, 80'h0);  // FSTP m80
        check(80'h4000D49A784BCD1B8AFE, "FLDL2T = log₂(10) ≈ 3.322");

        //=================================================================
        // Test 5: FLDLN2 → FSTP (Load ln(2))
        //=================================================================
        $display("\nTest 5: FLDLN2 (D9 ED) → FSTP m80");
        exec(8'hD9, 8'hED, 80'h0);  // FLDLN2
        exec(8'hDB, 8'hED, 80'h0);  // FSTP m80
        check(80'h3FFEB17217F7D1CF79AC, "FLDLN2 = ln(2) ≈ 0.693");

        //=================================================================
        // Test 6: FLD(2.5) → FABS → FSTP (Absolute value)
        //=================================================================
        $display("\nTest 6: FLD m80(-2.5) → FABS (D9 E1) → FSTP");
        exec(8'hDB, 8'hED, 80'hC000A000000000000000);  // FLD m80 (-2.5)
        exec(8'hD9, 8'hE1, 80'h0);   // FABS
        exec(8'hDB, 8'hED, 80'h0);   // FSTP m80
        check(80'h4000A000000000000000, "FABS(-2.5) = +2.5");

        //=================================================================
        // Test 7: FLD(3.0) → FCHS → FSTP (Change sign)
        //=================================================================
        $display("\nTest 7: FLD m80(+3.0) → FCHS (D9 E0) → FSTP");
        exec(8'hDB, 8'hED, 80'h4000C000000000000000);  // FLD m80 (+3.0)
        exec(8'hD9, 8'hE0, 80'h0);   // FCHS
        exec(8'hDB, 8'hED, 80'h0);   // FSTP m80
        check(80'hC000C000000000000000, "FCHS(+3.0) = -3.0");

        //=================================================================
        // Test 8: FCHS twice = identity
        //=================================================================
        $display("\nTest 8: FLD(5.0) → FCHS → FCHS → FSTP");
        exec(8'hDB, 8'hED, 80'h4001A000000000000000);  // FLD m80 (+5.0)
        exec(8'hD9, 8'hE0, 80'h0);   // FCHS (-5.0)
        exec(8'hD9, 8'hE0, 80'h0);   // FCHS (+5.0)
        exec(8'hDB, 8'hED, 80'h0);   // FSTP m80
        check(80'h4001A000000000000000, "FCHS(FCHS(+5.0)) = +5.0");

        //=================================================================
        // Test 9: FNOP does nothing
        //=================================================================
        $display("\nTest 9: FNOP (D9 D0) - No Operation");
        exec(8'hD9, 8'hD0, 80'h0);   // FNOP
        if (!cpu_error) begin
            $display("  ✓ PASS: FNOP executed without error");
            pass_count = pass_count + 1;
        end else begin
            $display("  ✗ FAIL: FNOP raised error");
            fail_count = fail_count + 1;
        end

        //=================================================================
        // Test 10: FWAIT does nothing
        //=================================================================
        $display("\nTest 10: FWAIT (9B) - Wait for FPU");
        exec(8'h9B, 8'h00, 80'h0);   // FWAIT
        if (!cpu_error) begin
            $display("  ✓ PASS: FWAIT executed without error");
            pass_count = pass_count + 1;
        end else begin
            $display("  ✗ FAIL: FWAIT raised error");
            fail_count = fail_count + 1;
        end

        //=================================================================
        // Results
        //=================================================================
        $display("\n========================================");
        $display("Test Results:");
        $display("  Total: %0d", pass_count + fail_count);
        $display("  Pass:  %0d", pass_count);
        $display("  Fail:  %0d", fail_count);
        $display("========================================");

        if (fail_count == 0) begin
            $display("✓ ALL TESTS PASSED\n");
        end else begin
            $display("✗ SOME TESTS FAILED\n");
        end

        $finish;
    end

endmodule
