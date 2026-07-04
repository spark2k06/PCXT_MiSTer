`timescale 1ns / 1ps

module ega_vram_frontend_splash_tb;

    timeunit 1ns;
    timeprecision 1ps;

    logic clock = 1'b0;
    logic clk_video = 1'b0;
    logic reset = 1'b1;
    logic [15:0] text_cell_addr = 16'h0000;
    logic text_fetch_en = 1'b0;
    logic splash_text_active = 1'b0;
    wire [11:0] splash_text_char_addr;
    wire [11:0] splash_text_attr_addr;
    wire [7:0] text_char;
    wire [7:0] text_attr;
    wire [7:0] text_glyph;
    wire text_data_valid;
    wire [7:0] splash_text_char_data = (splash_text_char_addr == 12'h024) ? 8'h53 : 8'h00;
    wire [7:0] splash_text_attr_data = (splash_text_attr_addr == 12'h025) ? 8'h1E : 8'h00;

    integer failures = 0;

    always #5 clock = ~clock;
    always #7 clk_video = ~clk_video;

    ega_vram_bram_frontend dut (
        .clock(clock),
        .reset(reset),
        .clk_video(clk_video),
        .cpu_addr(16'h0000),
        .cpu_a16(1'b0),
        .cpu_din(8'h00),
        .cpu_read(1'b0),
        .cpu_write(1'b0),
        .cpu_dout(),
        .cpu_ready(),
        .video_addr(16'h0000),
        .video_read_en(1'b0),
        .video_plane0(),
        .video_plane1(),
        .video_plane2(),
        .video_plane3(),
        .video_data_valid(),
        .text_cell_addr(text_cell_addr),
        .text_font_addr(16'h0000),
        .text_fetch_en(text_fetch_en),
        .splash_text_active(splash_text_active),
        .splash_text_char_addr(splash_text_char_addr),
        .splash_text_attr_addr(splash_text_attr_addr),
        .splash_text_char_data(splash_text_char_data),
        .splash_text_attr_data(splash_text_attr_data),
        .text_char(text_char),
        .text_attr(text_attr),
        .text_glyph(text_glyph),
        .text_data_valid(text_data_valid),
        .splash_text_we(1'b0),
        .splash_text_addr(11'h000),
        .splash_text_attr(1'b0),
        .splash_text_data(8'h00),
        .cfg_toggle(1'b0),
        .plane_write_mask(4'h0),
        .odd_even_mode(1'b0),
        .cpu_access_en(1'b0),
        .chain2_write(1'b0),
        .chain2_read(1'b0),
        .extended_memory(1'b0),
        .mem_map_sel(2'b00),
        .page_select(1'b0),
        .write_mode(2'b00),
        .read_mode(2'b00),
        .read_plane_sel(2'b00),
        .color_compare(8'h00),
        .color_dont_care(8'h0F),
        .bit_mask(8'hFF),
        .set_reset(8'h00),
        .enable_set_reset(4'h0),
        .rop_select(2'b00),
        .rotate_count(3'b000)
    );

    task automatic expect8(input [8*48-1:0] label, input [7:0] actual, input [7:0] expected);
        begin
            if (actual !== expected) begin
                $display("FAIL %0s expected=%02h actual=%02h", label, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect12(input [8*48-1:0] label, input [11:0] actual, input [11:0] expected);
        begin
            if (actual !== expected) begin
                $display("FAIL %0s expected=%03h actual=%03h", label, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk_video);
        reset = 1'b0;
        repeat (2) @(posedge clk_video);

        splash_text_active = 1'b1;
        text_cell_addr = 16'h0012;
        text_fetch_en = 1'b1;
        @(posedge clk_video);
        text_fetch_en = 1'b0;
        @(posedge clk_video);
        @(negedge clk_video);

        if (!text_data_valid) begin
            $display("FAIL splash text fetch did not produce valid data");
            failures = failures + 1;
        end
        expect12("splash text char address", splash_text_char_addr, 12'h024);
        expect12("splash text attr address", splash_text_attr_addr, 12'h025);
        expect8("splash text char", text_char, 8'h53);
        expect8("splash text attr", text_attr, 8'h1E);

        if (failures == 0)
            $display("PASS ega_vram_frontend_splash_tb");
        else
            $display("FAIL ega_vram_frontend_splash_tb failures=%0d", failures);

        $finish(failures == 0 ? 0 : 1);
    end

endmodule
