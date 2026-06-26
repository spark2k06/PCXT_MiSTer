`timescale 1ns / 1ps

module ega_text_tb;

    timeunit 1ns;
    timeprecision 1ps;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg ce_pix = 1'b1;
    reg fetch_tick = 1'b0;
    reg display_enable = 1'b0;
    reg [15:0] crtc_addr = 16'h0000;
    reg [4:0] scanline = 5'd0;
    reg [7:0] text_char_in = 8'h00;
    reg [7:0] text_attr_in = 8'h00;
    reg [7:0] text_glyph_in = 8'h00;
    reg text_data_valid = 1'b0;

    wire [15:0] text_cell_addr;
    wire [15:0] text_font_addr;
    wire text_fetch_en;
    wire [3:0] plane_index;
    wire pixel_valid;

    integer failures = 0;
    reg [8*80-1:0] current_test = "initialization";

    ega_text dut (
        .clk(clk),
        .reset(reset),
        .ce_pix(ce_pix),
        .fetch_tick(fetch_tick),
        .display_enable(display_enable),
        .crtc_addr(crtc_addr),
        .scanline(scanline),
        .text_char_in(text_char_in),
        .text_attr_in(text_attr_in),
        .text_glyph_in(text_glyph_in),
        .text_data_valid(text_data_valid),
        .text_cell_addr(text_cell_addr),
        .text_font_addr(text_font_addr),
        .text_fetch_en(text_fetch_en),
        .plane_index(plane_index),
        .pixel_valid(pixel_valid)
    );

    always #5 clk = ~clk;

    task automatic begin_test(input [8*80-1:0] name);
        begin
            current_test = name;
            $display("TEST: %0s", current_test);
        end
    endtask

    task automatic expect16(
        input [8*80-1:0] label,
        input [15:0] actual,
        input [15:0] expected
    );
        begin
            if (actual !== expected) begin
                $display("FAIL [%0s] %0s: expected %04x got %04x",
                         current_test, label, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect1(
        input [8*80-1:0] label,
        input actual,
        input expected
    );
        begin
            if (actual !== expected) begin
                $display("FAIL [%0s] %0s: expected %0d got %0d",
                         current_test, label, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task automatic reset_dut;
        begin
            reset = 1'b1;
            fetch_tick = 1'b0;
            display_enable = 1'b0;
            crtc_addr = 16'h0000;
            scanline = 5'd0;
            text_char_in = 8'h00;
            text_attr_in = 8'h00;
            text_glyph_in = 8'h00;
            text_data_valid = 1'b0;
            repeat (4) @(negedge clk);
            reset = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic provide_cell(
        input [7:0] chr,
        input [7:0] attr,
        input [7:0] glyph
    );
        begin
            @(negedge clk);
            text_char_in = chr;
            text_attr_in = attr;
            text_glyph_in = glyph;
            text_data_valid = 1'b1;
            @(negedge clk);
            text_data_valid = 1'b0;
        end
    endtask

    task automatic wait_pixels(input integer count);
        integer i;
        begin
            for (i = 0; i < count; i = i + 1)
                @(posedge clk);
            @(negedge clk);
        end
    endtask

    task automatic pulse_fetch(input [15:0] addr);
        begin
            @(negedge clk);
            crtc_addr = addr;
            fetch_tick = 1'b1;
            @(negedge clk);
            fetch_tick = 1'b0;
        end
    endtask

    initial begin
        reset_dut();

        begin_test("80-column text cell fetch cadence");
        scanline = 5'd4;
        display_enable = 1'b1;
        pulse_fetch(16'h0123);
        expect1("first cell fetch", text_fetch_en, 1'b1);
        expect16("first cell address", text_cell_addr, 16'h0123);
        provide_cell(8'h41, 8'h1E, 8'hA5);
        wait_pixels(7);
        pulse_fetch(16'h0124);
        expect1("second 80-column cell fetch", text_fetch_en, 1'b1);
        expect16("second 80-column cell address", text_cell_addr, 16'h0124);

        reset_dut();

        begin_test("40-column text cell fetch cadence");
        display_enable = 1'b1;
        pulse_fetch(16'h0200);
        expect1("first 40-column cell fetch", text_fetch_en, 1'b1);
        expect16("first 40-column cell address", text_cell_addr, 16'h0200);
        provide_cell(8'h42, 8'h2F, 8'h5A);
        wait_pixels(15);
        pulse_fetch(16'h0201);
        expect1("second 40-column cell fetch", text_fetch_en, 1'b1);
        expect16("second 40-column cell address", text_cell_addr, 16'h0201);

        if (failures == 0) begin
            $display("PASS: ega_text_tb");
        end else begin
            $display("FAIL: ega_text_tb failures=%0d", failures);
            $fatal(1);
        end
        $finish;
    end

endmodule
