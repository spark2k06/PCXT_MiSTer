//============================================================================
//
//  XTCTL identification block regression.
//
//  The block must answer 8990h..8997h on reads only, stay silent for its
//  neighbours (XTEGACTL below, anything above), stay silent during a DMA
//  cycle, and report the live card/RTC/counter inputs.
//
//    iverilog -g2012 -o xtctl_id_tb TESTBENCH/xtctl_id_tb.sv HDL/xtctl_id.sv
//    vvp xtctl_id_tb
//
//============================================================================

`timescale 1ns/1ps

module xtctl_id_tb;

    logic        clock = 1'b0;
    logic        reset = 1'b1;
    always #5 clock = ~clock;

    logic [15:0] address          = 16'h0000;
    logic        address_enable_n = 1'b0;
    logic        io_read_n        = 1'b1;
    wire   [7:0] data_out;
    wire         output_enable;

    logic        tandy_machine    = 1'b0;
    logic        pcjr_machine     = 1'b0;
    logic  [1:0] video_card       = 2'd1;
    logic        vga13_active     = 1'b0;
    logic [15:0] rtc_port         = 16'h02C0;
    logic [15:0] video_underruns  = 16'd0;
    logic  [7:0] cpu_latency_max  = 8'd0;

    xtctl_id #(
        .CAPABILITIES (8'hA5)
    ) dut (
        .clock            (clock),
        .reset            (reset),
        .address          (address),
        .address_enable_n (address_enable_n),
        .io_read_n        (io_read_n),
        .data_out         (data_out),
        .output_enable    (output_enable),
        .tandy_machine    (tandy_machine),
        .pcjr_machine     (pcjr_machine),
        .video_card       (video_card),
        .vga13_active     (vga13_active),
        .rtc_port         (rtc_port),
        .video_underruns  (video_underruns),
        .cpu_latency_max  (cpu_latency_max)
    );

    integer errors = 0;

    task automatic fail(input string msg);
        begin
            $display("FAIL: %s", msg);
            errors = errors + 1;
        end
    endtask

    task automatic rd(input [15:0] a, output [7:0] d, output logic oe);
        begin
            address   = a;
            io_read_n = 1'b0;
            #1;
            d  = data_out;
            oe = output_enable;
            io_read_n = 1'b1;
            #1;
        end
    endtask

    task automatic expect_reg(input [15:0] a, input [7:0] want, input string name);
        logic [7:0] d;
        logic oe;
        begin
            rd(a, d, oe);
            if (!oe)        fail($sformatf("%s: no output enable", name));
            else if (d !== want) fail($sformatf("%s: read %02h, wanted %02h", name, d, want));
        end
    endtask

    task automatic expect_silent(input [15:0] a, input string name);
        logic [7:0] d;
        logic oe;
        begin
            rd(a, d, oe);
            if (oe) fail($sformatf("%s: drove the bus", name));
        end
    endtask

    initial begin
        repeat (2) @(posedge clock);
        reset = 1'b0;

        expect_reg(16'h8990, 8'h00, "model");
        expect_reg(16'h8991, 8'h01, "video card CGA");
        expect_reg(16'h8992, 8'h01, "version");
        expect_reg(16'h8993, 8'hC0, "rtc low");
        expect_reg(16'h8994, 8'h02, "rtc high");
        expect_reg(16'h8995, 8'hA5, "capabilities");
        expect_reg(16'h8996, 8'h00, "underruns");
        expect_reg(16'h8997, 8'h00, "latency");

        // the machine chosen at reset
        tandy_machine = 1'b1;
        expect_reg(16'h8990, 8'h01, "model Tandy 1000");
        // a PCjr is a member of the Tandy video family: it reports 02h
        pcjr_machine = 1'b1;
        expect_reg(16'h8990, 8'h02, "model PCjr");
        pcjr_machine = 1'b0;
        tandy_machine = 1'b0;

        // live inputs
        video_card = 2'd3; vga13_active = 1'b1; rtc_port = 16'h0340;
        video_underruns = 16'd7; cpu_latency_max = 8'd42;
        expect_reg(16'h8991, 8'h83, "EGA with 13h");
        expect_reg(16'h8993, 8'h40, "moved rtc low");
        expect_reg(16'h8994, 8'h03, "moved rtc high");
        expect_reg(16'h8996, 8'h07, "underruns");
        expect_reg(16'h8997, 8'd42, "latency");

        // the underrun counter saturates instead of wrapping to a small value
        video_underruns = 16'h0123;
        expect_reg(16'h8996, 8'hFF, "saturated underruns");

        // neighbours and write cycles
        expect_silent(16'h898F, "last XTEGACTL port");
        expect_silent(16'h8998, "first port above");
        expect_silent(16'h8888, "legacy XTCTL");
        address = 16'h8990;
        io_read_n = 1'b1;
        #1;
        if (output_enable) fail("answered with no read strobe");
        address_enable_n = 1'b1;
        expect_silent(16'h8990, "DMA cycle");
        address_enable_n = 1'b0;

        if (errors == 0)
            $display("RESULT: PASS (XTCTL ID registers decode, saturate and stay read-only)");
        else
            $display("RESULT: FAIL (%0d checks)", errors);
        $finish;
    end

endmodule
