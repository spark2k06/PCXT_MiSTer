`timescale 1ns / 1ps

module ega_top_splash_tb;

    timeunit 1ns;
    timeprecision 1ps;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg text_data_valid = 1'b0;
    reg [7:0] text_char = 8'hDB;
    reg [7:0] text_attr = 8'h0E;
    integer cycles = 0;
    integer nonzero_pixels = 0;
    integer visible_pixels = 0;
    integer fetches = 0;
    integer de_crtc_cycles = 0;
    integer de_render_cycles = 0;
    integer text_ticks = 0;
    integer tick_de_crtc = 0;
    integer tick_de_render = 0;
    reg [15:0] max_text_cell_addr = 16'h0000;

    wire [4:0] clkdiv;
    wire [15:0] text_cell_addr;
    wire [15:0] text_font_addr;
    wire text_fetch_en;
    wire hsync;
    wire hblank;
    wire dbl_hsync;
    wire vsync;
    wire vblank;
    wire vblank_border;
    wire std_hsyncwidth;
    wire de_o;
    wire [3:0] video;
    wire [3:0] dbl_video;
    wire [6:0] comp_video;
    wire [5:0] ega_red;
    wire [5:0] ega_green;
    wire [5:0] ega_blue;
    wire ega_rgb_active;
    wire ega_display_sel;
    wire grph_mode;
    wire hres_mode;

    always #5 clk = ~clk;

    ega_top dut (
        .clk(clk),
        .reset(reset),
        .clkdiv(clkdiv),
        .bus_a(15'h0000),
        .bus_ior_l(1'b1),
        .bus_iow_l(1'b1),
        .bus_memr_l(1'b1),
        .bus_memw_l(1'b1),
        .bus_d(8'h00),
        .bus_out(),
        .bus_dir(),
        .bus_aen(1'b0),
        .bus_rdy(),
        .ram_we_l(),
        .ram_a(),
        .ram_d(8'h00),
        .ram_data_valid(1'b0),
        .ega_fetch_addr(),
        .ega_fetch_en(),
        .ega_plane0_data(8'h00),
        .ega_plane1_data(8'h00),
        .ega_plane2_data(8'h00),
        .ega_plane3_data(8'h00),
        .ega_fetch_data_valid(1'b0),
        .ega_text_cell_addr(text_cell_addr),
        .ega_text_font_addr(text_font_addr),
        .ega_text_fetch_en(text_fetch_en),
        .ega_text_char(text_char),
        .ega_text_attr(text_attr),
        .ega_text_glyph(8'h00),
        .ega_text_data_valid(text_data_valid),
        .cpu_mem_select(1'b0),
        .cpu_mem_write(1'b0),
        .ega_cfg_toggle(),
        .ega_plane_write_mask_out(),
        .ega_odd_even_mode_out(),
        .ega_cpu_access_slot_out(),
        .ega_chain2_write_out(),
        .ega_chain2_read_out(),
        .ega_extended_memory_out(),
        .ega_mem_map_sel_out(),
        .ega_page_select_out(),
        .ega_write_mode_out(),
        .ega_read_mode_out(),
        .ega_read_plane_sel_out(),
        .ega_color_compare_out(),
        .ega_color_dont_care_out(),
        .ega_bit_mask_out(),
        .ega_set_reset_out(),
        .ega_enable_set_reset_out(),
        .ega_rop_select_out(),
        .ega_rotate_count_out(),
        .ega_blink_counter_out(),
        .ega_blink_state_out(),
        .hsync(hsync),
        .hblank(hblank),
        .dbl_hsync(dbl_hsync),
        .vsync(vsync),
        .vblank(vblank),
        .vblank_border(vblank_border),
        .std_hsyncwidth(std_hsyncwidth),
        .de_o(de_o),
        .video(video),
        .dbl_video(dbl_video),
        .comp_video(comp_video),
        .ega_red(ega_red),
        .ega_green(ega_green),
        .ega_blue(ega_blue),
        .ega_rgb_active(ega_rgb_active),
        .ega_display_sel_out(ega_display_sel),
        .splashscreen(1'b1),
        .thin_font(1'b0),
        .scandouble_en(1'b0),
        .ega_enabled(1'b1),
        .grph_mode(grph_mode),
        .hres_mode(hres_mode),
        .crt_h_offset(4'h0),
        .crt_v_offset(3'h0),
        .vsync_width_osd(3'h0),
        .hsync_width_osd(3'h0)
    );

    always @(posedge clk) begin
        text_data_valid <= text_fetch_en;
        if (text_fetch_en) begin
            fetches <= fetches + 1;
            if (text_cell_addr > max_text_cell_addr)
                max_text_cell_addr <= text_cell_addr;
        end
        if (dut.ega_display_enable_crtc)
            de_crtc_cycles <= de_crtc_cycles + 1;
        if (dut.ega_display_enable_render)
            de_render_cycles <= de_render_cycles + 1;
        if (dut.ega_text_fetch_tick) begin
            text_ticks <= text_ticks + 1;
            if (dut.ega_display_enable_crtc)
                tick_de_crtc <= tick_de_crtc + 1;
            if (dut.ega_display_enable_render)
                tick_de_render <= tick_de_render + 1;
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        reset = 1'b0;

        for (cycles = 0; cycles < 800000; cycles = cycles + 1) begin
            @(posedge clk);
            if (de_o) begin
                visible_pixels = visible_pixels + 1;
                if (video != 4'h0)
                    nonzero_pixels = nonzero_pixels + 1;
            end
        end

        if (fetches == 0) begin
            $display("FAIL ega_top_splash_tb: no text fetches sel=%0d splash=%0d de_crtc=%0d de_render=%0d text_tick=%0d crtc_tick=%0d hcc=%0d row=%0d line=%0d de_crtc_cycles=%0d de_render_cycles=%0d text_ticks=%0d tick_de_crtc=%0d tick_de_render=%0d",
                     dut.ega_display_sel, dut.ega_splash_active, dut.ega_display_enable_crtc,
                     dut.ega_display_enable_render, dut.ega_text_fetch_tick,
                     dut.ega_crtc_fetch_tick, dut.ega_crtc.hcc, dut.ega_crtc.row, dut.ega_crtc.line,
                     de_crtc_cycles, de_render_cycles, text_ticks, tick_de_crtc, tick_de_render);
            $finish(1);
        end
        if (visible_pixels == 0) begin
            $display("FAIL ega_top_splash_tb: no visible pixels");
            $finish(1);
        end
        if (max_text_cell_addr >= 16'd2000) begin
            $display("FAIL ega_top_splash_tb: splash text address outside 80x25 range max=%0d",
                     max_text_cell_addr);
            $finish(1);
        end
        if (nonzero_pixels == 0) begin
            $display("FAIL ega_top_splash_tb: no nonzero splash pixels");
            $finish(1);
        end

        $display("PASS ega_top_splash_tb fetches=%0d visible=%0d nonzero=%0d",
                 fetches, visible_pixels, nonzero_pixels);
        $finish(0);
    end

endmodule
