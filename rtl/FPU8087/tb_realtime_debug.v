`timescale 1ns / 1ps

//=====================================================================
// Real-time Debug Test
//
// Monitor FPU_Core state transitions in real-time
//=====================================================================

module tb_realtime_debug;

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

    // Real-time state monitor
    reg [3:0] prev_state;
    always @(posedge clk) begin
        if (uut.core.state != prev_state) begin
            $display("[%0t] State: %0d → %0d, inst=0x%02X, ready=%b",
                     $time, prev_state, uut.core.state,
                     uut.core.current_inst, cpu_ready);

            if (uut.core.state == 2) begin  // STATE_EXECUTE
                $display("       Entering STATE_EXECUTE with current_inst=0x%02X", uut.core.current_inst);
            end

            if (uut.core.state == 4) begin  // STATE_STACK_OP
                $display("       Stack signals: push=%b, write_en=%b, data=%h",
                         uut.core.stack_push, uut.core.stack_write_enable, uut.core.stack_data_in);
            end

            if (uut.core.state == 5) begin  // STATE_DONE
                $display("       ST(0) at STATE_DONE entry = %h", uut.core.st0);
            end

            prev_state = uut.core.state;
        end
    end

    // Monitor ready signal
    reg prev_ready;
    always @(posedge clk) begin
        if (cpu_ready != prev_ready) begin
            $display("[%0t] cpu_ready: %b → %b, ST(0)=%h", $time, prev_ready, cpu_ready, uut.core.st0);
            prev_ready = cpu_ready;
        end
    end

    initial begin
        $dumpfile("tb_realtime_debug.vcd");
        $dumpvars(0, tb_realtime_debug);

        clk = 0;
        reset = 1;
        cpu_execute = 0;
        cpu_data_in = 80'h0;
        cpu_control_in = 16'h037F;
        cpu_control_write = 0;
        cpu_int_data_in = 32'h0;
        prev_state = 0;
        prev_ready = 0;

        #20;
        reset = 0;
        #20;

        $display("\n=== Real-time Debug Test ===\n");

        $display("[%0t] Starting FLD1 (D9 E8)", $time);
        @(posedge clk);
        cpu_opcode = 8'hD9;
        cpu_modrm = 8'hE8;
        cpu_execute = 1'b1;
        @(posedge clk);
        cpu_execute = 1'b0;

        wait (cpu_ready);
        @(posedge clk);

        $display("[%0t] FLD1 complete", $time);
        $display("  ST(0) = %h (expected 3FFF8000000000000000)", uut.core.st0);
        $display("");

        #100;
        $finish;
    end

    initial begin
        #2000;
        $display("\n❌ TIMEOUT!");
        $finish;
    end

endmodule
