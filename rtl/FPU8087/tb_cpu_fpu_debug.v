`timescale 1ns / 1ps

module tb_cpu_fpu_debug;

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
        $display("Debug: Simple FLD1 test");

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

        $display("T=%0t: Starting FLD1", $time);
        $display("  Initial state: cpu_ready=%b, fpu_busy=%b, fpu_ready=%b", cpu_ready, fpu_busy, fpu_ready);

        cpu_opcode = 8'hD9;
        cpu_modrm = 8'hE8; // FLD1
        cpu_fpu_escape = 1;
        #10;
        $display("T=%0t: cpu_fpu_escape=1", $time);
        $display("  fpu_instr_valid=%b, fpu_instr_ack=%b", fpu_instr_valid, fpu_instr_ack);

        #10;
        cpu_fpu_escape = 0;
        $display("T=%0t: cpu_fpu_escape=0", $time);
        $display("  fpu_instr_valid=%b, fpu_instr_ack=%b", fpu_instr_valid, fpu_instr_ack);
        $display("  adapter.state=%d", adapter.state);

        #100;
        $display("T=%0t: After 100ns", $time);
        $display("  fpu_busy=%b, fpu_ready=%b, cpu_ready=%b", fpu_busy, fpu_ready, cpu_ready);
        $display("  adapter.state=%d", adapter.state);

        #1000;
        $display("T=%0t: After 1000ns", $time);
        $display("  fpu_busy=%b, fpu_ready=%b, cpu_ready=%b", fpu_busy, fpu_ready, cpu_ready);
        $display("  adapter.state=%d", adapter.state);

        if (cpu_ready) begin
            $display("SUCCESS: FLD1 completed");
        end else begin
            $display("FAIL: cpu_ready still low, state=%d", adapter.state);
        end

        #100;
        $finish;
    end

    initial begin
        $dumpfile("tb_cpu_fpu_debug.vcd");
        $dumpvars(0, tb_cpu_fpu_debug);
    end

endmodule
