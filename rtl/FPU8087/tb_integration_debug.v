`timescale 1ns / 1ps

//=====================================================================
// Integration Debug Test
//
// Test FPU8087_Direct to identify where data is lost
//=====================================================================

module tb_integration_debug;

    reg clk, reset;
    reg [7:0] cpu_opcode, cpu_modrm;
    reg cpu_execute;
    wire cpu_ready, cpu_error;
    reg [79:0] cpu_data_in;
    wire [79:0] cpu_data_out;
    reg [31:0] cpu_int_data_in;
    wire [31:0] cpu_int_data_out;
    reg [15:0] cpu_control_in;
    reg cpu_control_write;
    wire [15:0] cpu_status_out, cpu_control_out, cpu_tag_word_out;

    FPU8087_Direct uut (
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

    initial begin
        $dumpfile("tb_integration_debug.vcd");
        $dumpvars(0, tb_integration_debug);

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

        $display("\n=== Integration Debug Test ===\n");

        $display("Test 1: FLD1 (D9 E8)");
        exec(8'hD9, 8'hE8, 80'h0);
        $display("  Decoder output: opcode=%02X, valid=%b", uut.decoded_opcode, uut.decoded_valid);
        $display("  FPU_Core state: %d", uut.core.state);
        $display("  FPU_Core temp_result: %h", uut.core.temp_result);
        $display("  Stack signals: push=%b, write_en=%b, data_in=%h",
                 uut.core.stack_push, uut.core.stack_write_enable, uut.core.stack_data_in);
        $display("  FPU_Core ST(0): %h", uut.core.st0);
        $display("  Stack pointer: %d", uut.core.register_stack.stack_ptr);
        $display("");

        $display("Test 2: FSTP m80 (DB 38)");
        $display("  Before FSTP:");
        $display("    ST(0) = %h", uut.core.st0);
        $display("    temp_operand_a = %h", uut.core.temp_operand_a);
        $display("    data_out = %h", uut.core.data_out);

        exec(8'hDB, 8'h38, 80'h0);

        $display("  After FSTP:");
        $display("    Decoder output: opcode=%02X, valid=%b, has_mem=%b",
                 uut.decoded_opcode, uut.decoded_valid, uut.decoded_has_memory_op);
        $display("    ST(0) = %h", uut.core.st0);
        $display("    temp_operand_a = %h", uut.core.temp_operand_a);
        $display("    data_out (internal) = %h", uut.core.data_out);
        $display("    cpu_data_out (output) = %h", cpu_data_out);
        $display("");

        if (cpu_data_out == 80'h3FFF8000000000000000)
            $display("  ✓ PASS");
        else
            $display("  ✗ FAIL - Expected 3FFF8000000000000000");

        #100;
        $finish;
    end

    initial begin
        #5000;
        $display("\n❌ TIMEOUT!");
        $finish;
    end

endmodule
