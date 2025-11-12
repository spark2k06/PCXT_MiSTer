`timescale 1ns / 1ps

//=====================================================================
// Testbench for FPU8087 Trivial Instructions (Fixed)
// Uses correct FSTP m80 opcode for memory stores
//=====================================================================

module tb_fpu8087_trivial_fixed;

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

    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

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
        $display("FPU8087 Trivial Instructions Test (Fixed)");
        $display("Real 8087 Opcodes - Corrected FSTP");
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

        // FSTP m80 opcode: DB /7 (reg_op=111)
        // modrm: mod=00, reg_op=111, rm=000 = 00111000 = 0x38

        $display("Test 1: FLD1 (D9 E8) → FSTP m80 (DB 38)");
        exec(8'hD9, 8'hE8, 80'h0);  // FLD1
        exec(8'hDB, 8'h38, 80'h0);  // FSTP m80
        check(80'h3FFF8000000000000000, "FLD1 = +1.0");

        $display("\nTest 2: FLDZ (D9 EE) → FSTP m80");
        exec(8'hD9, 8'hEE, 80'h0);  // FLDZ
        exec(8'hDB, 8'h38, 80'h0);  // FSTP m80
        check(80'h00000000000000000000, "FLDZ = +0.0");

        $display("\nTest 3: FLDPI (D9 EB) → FSTP m80");
        exec(8'hD9, 8'hEB, 80'h0);  // FLDPI
        exec(8'hDB, 8'h38, 80'h0);  // FSTP m80
        check(80'h4000C90FDAA22168C235, "FLDPI = π");

        $display("\nTest 4: FLDL2T (D9 E9) → FSTP m80");
        exec(8'hD9, 8'hE9, 80'h0);  // FLDL2T
        exec(8'hDB, 8'h38, 80'h0);  // FSTP m80
        check(80'h4000D49A784BCD1B8AFE, "FLDL2T = log₂(10)");

        $display("\nTest 5: FLDLN2 (D9 ED) → FSTP m80");
        exec(8'hD9, 8'hED, 80'h0);  // FLDLN2
        exec(8'hDB, 8'h38, 80'h0);  // FSTP m80
        check(80'h3FFEB17217F7D1CF79AC, "FLDLN2 = ln(2)");

        // FLD m80: DB /5 (reg_op=101), modrm=0x28
        $display("\nTest 6: FLD m80(-2.5) → FABS → FSTP");
        exec(8'hDB, 8'h28, 80'hC000A000000000000000);  // FLD m80
        exec(8'hD9, 8'hE1, 80'h0);   // FABS
        exec(8'hDB, 8'h38, 80'h0);   // FSTP m80
        check(80'h4000A000000000000000, "FABS(-2.5) = +2.5");

        $display("\nTest 7: FLD m80(+3.0) → FCHS → FSTP");
        exec(8'hDB, 8'h28, 80'h4000C000000000000000);  // FLD m80
        exec(8'hD9, 8'hE0, 80'h0);   // FCHS
        exec(8'hDB, 8'h38, 80'h0);   // FSTP m80
        check(80'hC000C000000000000000, "FCHS(+3.0) = -3.0");

        $display("\nTest 8: FLD(+5.0) → FCHS → FCHS → FSTP");
        exec(8'hDB, 8'h28, 80'h4001A000000000000000);  // FLD m80
        exec(8'hD9, 8'hE0, 80'h0);   // FCHS
        exec(8'hD9, 8'hE0, 80'h0);   // FCHS
        exec(8'hDB, 8'h38, 80'h0);   // FSTP m80
        check(80'h4001A000000000000000, "FCHS(FCHS(+5.0)) = +5.0");

        $display("\nTest 9: FNOP (D9 D0)");
        exec(8'hD9, 8'hD0, 80'h0);
        if (!cpu_error) begin
            $display("  ✓ PASS: FNOP executed without error");
            pass_count = pass_count + 1;
        end else begin
            $display("  ✗ FAIL: FNOP raised error");
            fail_count = fail_count + 1;
        end

        $display("\nTest 10: FWAIT (9B)");
        exec(8'h9B, 8'h00, 80'h0);
        if (!cpu_error) begin
            $display("  ✓ PASS: FWAIT executed without error");
            pass_count = pass_count + 1;
        end else begin
            $display("  ✗ FAIL: FWAIT raised error");
            fail_count = fail_count + 1;
        end

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
