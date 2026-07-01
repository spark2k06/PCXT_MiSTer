`timescale 1ns / 1ps

module ega_text_tb;

    timeunit 1ns;
    timeprecision 1ps;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg ce_pix = 1'b1;
    reg fetch_tick = 1'b0;
    reg display_enable = 1'b0;
    reg dot_clock_div2 = 1'b0;
    reg char_9dot = 1'b0;
    reg [3:0] h_pixel_pan = 4'd0;
    reg blink_enable = 1'b0;
    reg blink_state = 1'b0;
    reg mono_attributes = 1'b0;
    reg line_graphics_enable = 1'b0;
    reg cursor_active = 1'b0;
    reg [15:0] crtc_addr = 16'h0000;
    reg [4:0] scanline = 5'd0;
    reg [4:0] underline_scanline = 5'd0;
    reg [1:0] char_map_a = 2'b00;
    reg [1:0] char_map_b = 2'b00;
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
        .dot_clock_div2(dot_clock_div2),
        .char_9dot(char_9dot),
        .h_pixel_pan(h_pixel_pan),
        .blink_enable(blink_enable),
        .blink_state(blink_state),
        .mono_attributes(mono_attributes),
        .line_graphics_enable(line_graphics_enable),
        .cursor_active(cursor_active),
        .crtc_addr(crtc_addr),
        .scanline(scanline),
        .underline_scanline(underline_scanline),
        .char_map_a(char_map_a),
        .char_map_b(char_map_b),
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

    task automatic expect4(
        input [8*80-1:0] label,
        input [3:0] actual,
        input [3:0] expected
    );
        begin
            if (actual !== expected) begin
                $display("FAIL [%0s] %0s: expected %01x got %01x",
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
            dot_clock_div2 = 1'b0;
            char_9dot = 1'b0;
            h_pixel_pan = 4'd0;
            blink_enable = 1'b0;
            blink_state = 1'b0;
            mono_attributes = 1'b0;
            line_graphics_enable = 1'b0;
            cursor_active = 1'b0;
            crtc_addr = 16'h0000;
            scanline = 5'd0;
            underline_scanline = 5'd0;
            char_map_a = 2'b00;
            char_map_b = 2'b00;
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

    task automatic step_pixel;
        begin
            @(posedge clk);
            @(negedge clk);
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

        reset_dut();

        begin_test("character map select chooses A and B font banks");
        display_enable = 1'b1;
        scanline = 5'd3;
        char_map_a = 2'b10;
        char_map_b = 2'b01;
        provide_cell(8'h41, 8'h07, 8'h80);
        pulse_fetch(16'h0300);
        expect16("charset A font address", text_font_addr, 16'h8823);
        provide_cell(8'h42, 8'h08, 8'h80);
        pulse_fetch(16'h0301);
        expect16("charset B font address", text_font_addr, 16'h4843);

        reset_dut();

        begin_test("text glyph foreground and background colors");
        display_enable = 1'b1;
        provide_cell(8'h43, 8'h1E, 8'h80);
        step_pixel();
        expect4("set glyph bit selects foreground", plane_index, 4'hE);
        step_pixel();
        expect4("clear glyph bit selects background", plane_index, 4'h1);

        reset_dut();

        begin_test("text background intensity when blink disabled");
        display_enable = 1'b1;
        blink_enable = 1'b0;
        provide_cell(8'h44, 8'h9A, 8'h00);
        step_pixel();
        expect4("attribute bit 7 is background intensity", plane_index, 4'h9);

        reset_dut();

        begin_test("text blink hides foreground and masks background intensity");
        display_enable = 1'b1;
        blink_enable = 1'b1;
        blink_state = 1'b0;
        provide_cell(8'h45, 8'h9A, 8'h80);
        step_pixel();
        expect4("blink inactive keeps foreground", plane_index, 4'hA);
        blink_state = 1'b1;
        provide_cell(8'h45, 8'h9A, 8'h80);
        step_pixel();
        expect4("blink active uses background", plane_index, 4'h1);

        reset_dut();

        begin_test("9-dot line graphics repeats eighth column");
        display_enable = 1'b1;
        char_9dot = 1'b1;
        line_graphics_enable = 1'b1;
        provide_cell(8'hC4, 8'h0E, 8'h01);
        repeat (9) step_pixel();
        expect4("line graphics ninth dot repeats foreground", plane_index, 4'hE);

        reset_dut();

        begin_test("9-dot non-line character blanks ninth column");
        display_enable = 1'b1;
        char_9dot = 1'b1;
        line_graphics_enable = 1'b1;
        provide_cell(8'h41, 8'h1E, 8'h01);
        repeat (9) step_pixel();
        expect4("normal character ninth dot uses background", plane_index, 4'h1);

        reset_dut();

        begin_test("9-dot line graphics disabled blanks ninth column");
        display_enable = 1'b1;
        char_9dot = 1'b1;
        line_graphics_enable = 1'b0;
        provide_cell(8'hC4, 8'h2F, 8'h01);
        repeat (9) step_pixel();
        expect4("disabled line graphics ninth dot uses background", plane_index, 4'h2);

        reset_dut();

        begin_test("text cursor swaps foreground and background");
        display_enable = 1'b1;
        cursor_active = 1'b1;
        blink_state = 1'b1;
        provide_cell(8'h46, 8'h1E, 8'h80);
        step_pixel();
        expect4("cursor set glyph bit uses original background", plane_index, 4'h1);
        step_pixel();
        expect4("cursor clear glyph bit uses original foreground", plane_index, 4'hE);
        blink_state = 1'b0;
        provide_cell(8'h46, 8'h1E, 8'h80);
        step_pixel();
        expect4("cursor blink off leaves set glyph foreground", plane_index, 4'hE);

        reset_dut();

        begin_test("mono text attributes use MDA color table");
        display_enable = 1'b1;
        mono_attributes = 1'b1;
        provide_cell(8'h47, 8'h08, 8'h80);
        step_pixel();
        expect4("mono attr 08 foreground is black", plane_index, 4'h0);
        provide_cell(8'h47, 8'h78, 8'h00);
        step_pixel();
        expect4("mono attr 78 background is bright white", plane_index, 4'hF);
        blink_enable = 1'b1;
        blink_state = 1'b1;
        provide_cell(8'h47, 8'h87, 8'h80);
        step_pixel();
        expect4("mono blink hides foreground", plane_index, 4'h0);

        reset_dut();

        begin_test("mono underline forces foreground on underline scanline");
        display_enable = 1'b1;
        mono_attributes = 1'b1;
        scanline = 5'd12;
        underline_scanline = 5'd12;
        provide_cell(8'h48, 8'h01, 8'h00);
        step_pixel();
        expect4("mono underline draws foreground over clear glyph", plane_index, 4'h7);

        reset_dut();

        begin_test("text horizontal panning delays visible pixels");
        display_enable = 1'b1;
        h_pixel_pan = 4'd2;
        provide_cell(8'h49, 8'h1E, 8'hC0);
        step_pixel();
        expect4("first panned pixel comes from left history", plane_index, 4'h0);
        step_pixel();
        expect4("second panned pixel comes from left history", plane_index, 4'h0);
        step_pixel();
        expect4("third panned pixel is first glyph foreground", plane_index, 4'hE);
        step_pixel();
        expect4("fourth panned pixel is second glyph foreground", plane_index, 4'hE);

        reset_dut();

        begin_test("text panning does not change cell fetch addresses");
        display_enable = 1'b1;
        h_pixel_pan = 4'd3;
        pulse_fetch(16'h0555);
        expect1("panned first cell fetch", text_fetch_en, 1'b1);
        expect16("panned first cell address", text_cell_addr, 16'h0555);
        provide_cell(8'h4A, 8'h2F, 8'hF0);
        wait_pixels(7);
        pulse_fetch(16'h0000);
        expect1("panned split cell fetch", text_fetch_en, 1'b1);
        expect16("panned split cell address", text_cell_addr, 16'h0000);

        if (failures == 0) begin
            $display("PASS: ega_text_tb");
        end else begin
            $display("FAIL: ega_text_tb failures=%0d", failures);
            $fatal(1);
        end
        $finish;
    end

endmodule
