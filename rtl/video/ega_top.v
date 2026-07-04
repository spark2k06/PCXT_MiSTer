//============================================================================
//
//  PCXT MiSTer EGA top level
//
//============================================================================

`default_nettype wire

module ega_top(
    input clk,
    input reset,
    output [4:0] clkdiv,
    input [14:0] bus_a,
    input bus_ior_l,
    input bus_iow_l,
    input bus_memr_l,
    input bus_memw_l,
    input [7:0] bus_d,
    output [7:0] bus_out,
    output bus_dir,
    input bus_aen,
    output bus_rdy,
    output ram_we_l,
    output [18:0] ram_a,
    input [7:0] ram_d,
    input ram_data_valid,
    output [15:0] ega_fetch_addr,
    output ega_fetch_en,
    input [7:0] ega_plane0_data,
    input [7:0] ega_plane1_data,
    input [7:0] ega_plane2_data,
    input [7:0] ega_plane3_data,
    input ega_fetch_data_valid,
    output [15:0] ega_text_cell_addr,
    output [15:0] ega_text_font_addr,
    output ega_text_fetch_en,
    input [7:0] ega_text_char,
    input [7:0] ega_text_attr,
    input [7:0] ega_text_glyph,
    input ega_text_data_valid,
    input cpu_mem_select,
    input cpu_mem_write,
    output reg ega_cfg_toggle,
    output [3:0] ega_plane_write_mask_out,
    output ega_odd_even_mode_out,
    output ega_cpu_access_slot_out,
    output ega_chain2_write_out,
    output ega_chain2_read_out,
    output ega_extended_memory_out,
    output [1:0] ega_mem_map_sel_out,
    output ega_page_select_out,
    output [1:0] ega_write_mode_out,
    output [1:0] ega_read_mode_out,
    output [1:0] ega_read_plane_sel_out,
    output [7:0] ega_color_compare_out,
    output [7:0] ega_color_dont_care_out,
    output [7:0] ega_bit_mask_out,
    output [7:0] ega_set_reset_out,
    output [3:0] ega_enable_set_reset_out,
    output [1:0] ega_rop_select_out,
    output [2:0] ega_rotate_count_out,
    output [6:0] ega_blink_counter_out,
    output ega_blink_state_out,
    output hsync,
    output hblank,
    output dbl_hsync,
    output vsync,
    output vblank,
    output vblank_border,
    output std_hsyncwidth,
    output de_o,
    output [3:0] video,
    output [3:0] dbl_video,
    output [6:0] comp_video,
    output [5:0] ega_red,
    output [5:0] ega_green,
    output [5:0] ega_blue,
    output ega_rgb_active,
    output ega_display_sel_out,
    input splashscreen,
    input thin_font,
    input scandouble_en,
    input ega_enabled,
    output grph_mode,
    output hres_mode,
    input [3:0] crt_h_offset,
    input [2:0] crt_v_offset,
    input [2:0] vsync_width_osd,
    input [2:0] hsync_width_osd
    );

    parameter MDA_70HZ = 0;
    parameter BLINK_MAX = 0;
    parameter USE_BUS_WAIT = 0;
    parameter NO_DISPLAY_DISABLE = 0;
    parameter IO_BASE_ADDR = 16'h3d0;

    localparam [3:0] EGA_STD_HSYNC_W_HI = 4'd10;
    localparam [3:0] EGA_STD_HSYNC_W_LO = 4'd5;

    reg [4:0] ega_clkdiv = 5'd0;

    always @(posedge clk or posedge reset) begin
        if (reset)
            ega_clkdiv <= 5'd0;
        else
            ega_clkdiv <= ega_clkdiv + 5'd1;
    end

    assign clkdiv = ega_clkdiv;
    assign bus_rdy = 1'b1;

    wire ce_pix = ega_clkdiv[0];
    wire [15:0] ega_io_addr = {1'b0, bus_a};
    wire ega_io_we = ~bus_iow_l & ~bus_aen & ega_enabled;
    wire ega_io_re = ~bus_ior_l & ~bus_aen & ega_enabled;
    reg [7:0] ega_misc_output_reg = 8'h63;
    wire ega_color_io_select = ega_misc_output_reg[0];
    wire ega_color_crtc_cs = (bus_a[14:1] == (15'h03D4 >> 1));
    wire ega_mono_crtc_cs = (bus_a[14:1] == (15'h03B4 >> 1));
    wire ega_color_status_cs = (bus_a == 15'h03DA);
    wire ega_mono_status_cs = (bus_a == 15'h03BA);
    wire ega_crtc_cs = (ega_color_io_select ? ega_color_crtc_cs : ega_mono_crtc_cs) & ~bus_aen & ega_enabled;
    wire ega_status_cs = (ega_color_io_select ? ega_color_status_cs : ega_mono_status_cs) & ~bus_aen & ega_enabled;
    wire ega_seq_data_cs = ((bus_a == 15'h03C5) || (bus_a == 15'h02C5)) & ~bus_aen & ega_enabled;
    wire ega_attr_read_cs = ((bus_a == 15'h03C1) || (bus_a == 15'h02C1)) & ~bus_aen & ega_enabled;
    wire ega_misc_write_cs = ((bus_a == 15'h03C2) || (bus_a == 15'h02C2)) & ~bus_aen & ega_enabled;
    wire ega_switch_sense_cs = ((bus_a == 15'h03C2) || (bus_a == 15'h02C2)) & ~bus_aen & ega_enabled;
    wire ega_misc_read_cs = ((bus_a == 15'h03CC) || (bus_a == 15'h02CC)) & ~bus_aen & ega_enabled;
    wire ega_gfx_data_cs = ((bus_a == 15'h03CF) || (bus_a == 15'h02CF)) & ~bus_aen & ega_enabled;
    wire ega_dac_read_index_cs = ((bus_a == 15'h03C7) || (bus_a == 15'h02C7)) & ~bus_aen & ega_enabled;
    wire ega_dac_write_index_cs = ((bus_a == 15'h03C8) || (bus_a == 15'h02C8)) & ~bus_aen & ega_enabled;
    wire ega_dac_data_cs = ((bus_a == 15'h03C9) || (bus_a == 15'h02C9)) & ~bus_aen & ega_enabled;
    wire ega_cfg_we = ega_enabled && ega_io_we && ((ega_io_addr == 16'h03C5) || (ega_io_addr == 16'h02C5) || (ega_io_addr == 16'h03CF) || (ega_io_addr == 16'h02CF));

    reg ega_video_active = 1'b0;
    reg ega_video_pending = 1'b0;
    reg ega_write_seen_since_vblank = 1'b0;
    reg ega_vblank_q = 1'b0;
    wire ega_splash_active = ega_enabled & splashscreen;
    wire ega_display_sel = ega_enabled & (ega_video_active | ega_splash_active);
    reg [4:0] ega_crtc_index_shadow = 5'd0;
    reg       ega_crtc_h_timing_seen = 1'b0;
    reg       ega_crtc_v_timing_seen = 1'b0;
    wire      ega_crtc_timing_ready = ega_crtc_h_timing_seen & ega_crtc_v_timing_seen;

    wire [7:0] ega_crtc_data_out;
    wire ega_hsync_int;
    wire ega_hblank_crtc;
    wire ega_vblank_crtc;
    wire ega_vsync_l;
    wire ega_display_enable_crtc;
    wire ega_vertical_display_enable_crtc;
    wire ega_status_vretrace_crtc;
    wire ega_status_not_displaying_crtc;
    wire ega_vert_blank_active_crtc;
    wire [3:0] ega_scanline_mod16_debug;
    wire [3:0] ega_vslines_debug;
    wire [7:0] ega_crtc_r10_debug;
    wire [7:0] ega_crtc_r11_debug;
    wire [7:0] ega_crtc_r12_debug;
    wire [7:0] ega_crtc_r13_debug;
    wire [7:0] ega_crtc_r14_debug;
    wire [7:0] ega_crtc_r17_debug;
    wire [7:0] ega_crtc_r15_debug;
    wire [7:0] ega_crtc_r16_debug;
    wire [13:0] ega_crtc_addr;
    wire [15:0] ega_crtc_addr_full;
    wire [4:0] ega_row_addr;
    wire [7:0] ega_char_col;
    wire [6:0] ega_char_row;
    wire [9:0] ega_scanline_addr;
    wire [7:0] ega_h_displayed;
    wire [4:0] ega_v_maxscan;
    wire [3:0] ega_hsync_width_crtc;
    wire [7:0] ega_seq_data_out;
    wire [7:0] ega_seq_map_mask_debug;
    wire [7:0] ega_seq_memory_mode_debug;
    wire [1:0] ega_char_map_a;
    wire [1:0] ega_char_map_b;
    wire ega_char_9dot;
    wire [3:0] ega_plane_write_mask;
    wire ega_chain2_write;
    wire ega_extended_memory;
    wire ega_ce_crt_fetch;
    wire ega_ce_cpu_access_unused;
    wire ega_dot_clock_div2;
    wire [7:0] ega_gfx_data_out;
    wire [7:0] ega_gfx_mode_debug;
    wire ega_graphics_mode;
    wire ega_compat_2bpp_mode;
    wire [1:0] ega_write_mode;
    wire [1:0] ega_read_mode;
    wire [1:0] ega_read_plane_sel;
    wire [7:0] ega_color_compare;
    wire [7:0] ega_color_dont_care;
    wire [7:0] ega_bit_mask;
    wire [7:0] ega_set_reset;
    wire [3:0] ega_enable_set_reset;
    wire [1:0] ega_rop_select;
    wire [2:0] ega_rotate_count;
    wire ega_odd_even_mode;
    wire ega_chain2_read;
    wire [1:0] ega_mem_map_sel;
    wire [7:0] ega_attr_data_out;
    wire [5:0] ega_color_raw;
    wire ega_display_enable_raw;
    wire ega_attr_video_enable;
    wire [3:0] ega_graphics_plane_index;
    wire ega_graphics_pixel_valid;
    wire [3:0] ega_text_plane_index;
    wire ega_text_pixel_valid;
    wire ega_graphics_mode_active = ega_splash_active ? 1'b0 : ega_graphics_mode;
    wire ega_dot_clock_div2_active = ega_splash_active ? 1'b0 : ega_dot_clock_div2;
    wire ega_char_9dot_active = ega_splash_active ? 1'b0 : ega_char_9dot;
    wire [3:0] ega_plane_index = ega_graphics_mode_active ? ega_graphics_plane_index : ega_text_plane_index;
    wire ega_pixel_valid = ega_graphics_mode_active ? ega_graphics_pixel_valid : ega_text_pixel_valid;
    wire [1:0] ega_render_mode_debug_unused;
    wire ega_hres_mode_int = ~ega_dot_clock_div2_active;
    wire ega_attr_blink_enable;
    wire ega_attr_mono_attributes;
    wire ega_attr_line_graphics_enable;
    wire ega_cursor_active;
    wire ega_text_mode_active = !ega_graphics_mode_active;
    wire ega_text_fetch_en_raw;
    reg [4:0] ega_text_fetch_phase = 5'd0;
    wire [4:0] ega_text_fetch_phase_last =
        ega_dot_clock_div2_active ? (ega_char_9dot_active ? 5'd17 : 5'd15) :
                                    (ega_char_9dot_active ? 5'd8  : 5'd7);
    wire ega_text_fetch_tick = ce_pix && (ega_text_fetch_phase == ega_text_fetch_phase_last);
    wire [4:0] ega_graphics_fetch_phase_last = ega_dot_clock_div2_active ? 5'd15 : 5'd7;
    wire [4:0] ega_visible_base_delay = ega_graphics_mode_active ? ega_graphics_fetch_phase_last :
                                                                   ega_text_fetch_phase_last;
    wire [4:0] ega_visible_delay = ega_visible_base_delay + (ega_dot_clock_div2_active ? 5'd8 : 5'd4);
    wire ega_crtc_fetch_tick = (!ega_graphics_mode_active && (ega_splash_active || ega_char_9dot_active)) ? ega_text_fetch_tick :
                                                                                                          ega_ce_crt_fetch;
    wire [1:0] ega_render_mode = !ega_graphics_mode_active ? 2'd0 :
                                  ega_compat_2bpp_mode ? 2'd2 : 2'd1;
    wire ega_display_enable = ega_display_enable_crtc;
    reg [25:0] ega_display_enable_delay = 26'd0;
    wire ega_display_enable_visible = ega_display_enable_delay[ega_visible_delay];
    wire ega_display_enable_render = ega_display_enable | ega_display_enable_visible;
    wire ega_blanking_active = ega_status_not_displaying_crtc;
    wire ega_status_vretrace_active = ega_status_vretrace_crtc;

    reg cpu_mem_write_evt_d = 1'b0;
    wire cpu_mem_write_evt = cpu_mem_select & cpu_mem_write;
    wire cpu_mem_write_stretched = cpu_mem_write_evt | cpu_mem_write_evt_d;
    reg        ega_status_read_q = 1'b0;
    reg [1:0]  ega_status_toggle = 2'b00;
    reg        ega_vblank_crtc_q = 1'b0;
    reg [6:0]  ega_blink_counter = 7'h00;
    wire       ega_status_read = ega_status_cs & ~bus_ior_l;
    wire       ega_blink_advance = ega_crtc_fetch_tick & ega_vert_blank_active_crtc & ~ega_vblank_crtc_q;
    wire       ega_blink_state = ega_blink_counter[4];
    wire [7:0] ega_status_reg = {2'b00, ega_status_toggle, ega_status_vretrace_active, 2'b00, ega_blanking_active};

    UM6845R ega_crtc (
        .CLOCK(clk),
        .CLKEN(ega_crtc_fetch_tick),
        .nRESET(~reset),
        .CRTC_TYPE(1'b1),
        .ENABLE(1'b1),
        .nCS(~ega_crtc_cs),
        .R_nW(bus_iow_l),
        .RS(bus_a[0]),
        .DI(bus_d),
        .DO(ega_crtc_data_out),
        .hblank(ega_hblank_crtc),
        .vblank(ega_vblank_crtc),
        .line_reset(),
        .VSYNC(ega_vsync_l),
        .HSYNC(ega_hsync_int),
        .DE(ega_display_enable_crtc),
        .VDE(ega_vertical_display_enable_crtc),
        .status_vretrace(ega_status_vretrace_crtc),
        .status_not_displaying(ega_status_not_displaying_crtc),
        .vert_blank_active(ega_vert_blank_active_crtc),
        .scanline_mod16_debug(ega_scanline_mod16_debug),
        .vslines_debug(ega_vslines_debug),
        .crtc_r10_debug(ega_crtc_r10_debug),
        .crtc_r11_debug(ega_crtc_r11_debug),
        .crtc_r12_debug(ega_crtc_r12_debug),
        .crtc_r13_debug(ega_crtc_r13_debug),
        .crtc_r14_debug(ega_crtc_r14_debug),
        .crtc_r17_debug(ega_crtc_r17_debug),
        .crtc_r15_debug(ega_crtc_r15_debug),
        .crtc_r16_debug(ega_crtc_r16_debug),
        .CURSOR(ega_cursor_active),
        .MA(ega_crtc_addr),
        .MA_FULL(ega_crtc_addr_full),
        .RA(ega_row_addr),
        .HC(ega_char_col),
        .VC(ega_char_row),
        .VSCAN(ega_scanline_addr),
        .H_DISP_REG(ega_h_displayed),
        .V_MAXSCAN_REG(ega_v_maxscan),
        .hsync_width(ega_hsync_width_crtc),
        .crt_h_offset(crt_h_offset),
        .crt_v_offset(crt_v_offset),
        .vsync_width_osd(vsync_width_osd),
        .hsync_width_osd(hsync_width_osd),
        .hres_mode(ega_hres_mode_int)
    );

    // Reset to an 80-column text base so the pre-BIOS splash can be shown
    // through EGA VRAM before the EGA BIOS programs its final mode timings.
    defparam ega_crtc.H_TOTAL = 8'd112;
    defparam ega_crtc.H_DISP = 8'd80;
    defparam ega_crtc.H_SYNCPOS = 8'd90;
    defparam ega_crtc.H_SYNCWIDTH = 4'd10;
    defparam ega_crtc.V_TOTAL = 7'd31;
    defparam ega_crtc.V_TOTALADJ = 5'd6;
    // EGA extended timing uses R7 as overflow bits, R6 as vertical-total low,
    // and R18/R16 as display-end and sync-start low bytes. Seed a 262-line,
    // 200-visible-line text frame so the splash has sane sync before BIOS.
    defparam ega_crtc.V_DISP = 8'd4;
    defparam ega_crtc.V_SYNCPOS = 7'd1;
    defparam ega_crtc.V_MAXSCAN = 5'd7;
    defparam ega_crtc.C_START = 7'd6;
    defparam ega_crtc.C_END = 5'd7;
    defparam ega_crtc.DISPLAYED_CHARS_PLUS1 = 1;
    defparam ega_crtc.EGA_RESET_R16 = 8'hDF;
    defparam ega_crtc.EGA_RESET_R18 = 8'hC7;
    defparam ega_crtc.EGA_RESET_R19 = 8'h28;

    ega_sequencer ega_seq (
        .clk(clk),
        .reset(reset),
        .ce_pix(ce_pix),
        .io_addr(ega_io_addr),
        .io_data_in(bus_d),
        .io_data_out(ega_seq_data_out),
        .io_we(ega_io_we),
        .io_re(ega_io_re),
        .plane_write_mask(ega_plane_write_mask),
        .chain2_write(ega_chain2_write),
        .extended_memory(ega_extended_memory),
        .ce_crt_fetch(ega_ce_crt_fetch),
        .ce_cpu_access(ega_ce_cpu_access_unused),
        .dot_clock_div2(ega_dot_clock_div2),
        .char_9dot(ega_char_9dot),
        .char_map_a(ega_char_map_a),
        .char_map_b(ega_char_map_b),
        .map_mask_debug(ega_seq_map_mask_debug),
        .memory_mode_debug(ega_seq_memory_mode_debug)
    );

    ega_gfx_ctrl ega_gfx (
        .clk(clk),
        .reset(reset),
        .io_addr(ega_io_addr),
        .io_data_in(bus_d),
        .io_data_out(ega_gfx_data_out),
        .io_we(ega_io_we),
        .io_re(ega_io_re),
        .write_mode(ega_write_mode),
        .read_mode(ega_read_mode),
        .read_plane_sel(ega_read_plane_sel),
        .color_compare(ega_color_compare),
        .color_dont_care(ega_color_dont_care),
        .bit_mask(ega_bit_mask),
        .set_reset(ega_set_reset),
        .enable_set_reset(ega_enable_set_reset),
        .rop_select(ega_rop_select),
        .rotate_count(ega_rotate_count),
        .odd_even_mode(ega_odd_even_mode),
        .chain2_read(ega_chain2_read),
        .graphics_mode(ega_graphics_mode),
        .compat_2bpp_mode(ega_compat_2bpp_mode),
        .mem_map_sel(ega_mem_map_sel),
        .mode_debug(ega_gfx_mode_debug)
    );

    ega_pixel ega_pixel_inst (
        .clk(clk),
        .ce_pix(ce_pix),
        .plane0_data(ega_plane0_data),
        .plane1_data(ega_plane1_data),
        .plane2_data(ega_plane2_data),
        .plane3_data(ega_plane3_data),
        .fetch_en(ega_fetch_data_valid),
        .dot_clock_div2(ega_dot_clock_div2_active),
        .display_enable(ega_display_enable_render),
        .render_mode(ega_render_mode),
        .plane_index(ega_graphics_plane_index),
        .pixel_valid(ega_graphics_pixel_valid),
        .render_mode_debug(ega_render_mode_debug_unused)
    );

    ega_text ega_text_inst (
        .clk(clk),
        .reset(reset),
        .ce_pix(ce_pix),
        .fetch_tick(ega_crtc_fetch_tick),
        .display_enable(ega_text_mode_active ? ega_display_enable_render : 1'b0),
        .dot_clock_div2(ega_dot_clock_div2_active),
        .char_9dot(ega_char_9dot_active),
        .h_pixel_pan(4'd0),
        .blink_enable(ega_attr_blink_enable),
        .blink_state(ega_blink_state),
        .mono_attributes(ega_attr_mono_attributes),
        .line_graphics_enable(ega_attr_line_graphics_enable),
        .cursor_active(ega_splash_active ? 1'b0 : ega_cursor_active),
        .crtc_addr(ega_fetch_addr),
        .scanline(ega_row_addr),
        .underline_scanline(ega_crtc_r14_debug[4:0]),
        .char_map_a(ega_char_map_a),
        .char_map_b(ega_char_map_b),
        .text_char_in(ega_text_char),
        .text_attr_in(ega_text_attr),
        .text_glyph_in(ega_text_glyph),
        .text_data_valid(ega_text_data_valid),
        .splash_font_enable(ega_splash_active),
        .text_cell_addr(ega_text_cell_addr),
        .text_font_addr(ega_text_font_addr),
        .text_fetch_en(ega_text_fetch_en_raw),
        .plane_index(ega_text_plane_index),
        .pixel_valid(ega_text_pixel_valid)
    );

    ega_attrib_ctrl ega_attr (
        .clk(clk),
        .reset(reset),
        .ce_pix(ce_pix),
        .io_addr(ega_io_addr),
        .io_data_in(bus_d),
        .io_data_out(ega_attr_data_out),
        .io_we(ega_io_we),
        .io_re(ega_io_re),
        .status_re(ega_status_read),
        .plane_index(ega_plane_index),
        .pixel_valid(ega_pixel_valid),
        .display_enable(ega_display_enable_visible),
        .text_mode(~ega_graphics_mode_active),
        .blink_state(ega_blink_state),
        .blink_enable_out(ega_attr_blink_enable),
        .mono_attributes_out(ega_attr_mono_attributes),
        .line_graphics_enable_out(ega_attr_line_graphics_enable),
        .palette_64_mode(ega_misc_output_reg[7]),
        .color_out(ega_color_raw),
        .display_enable_out(ega_display_enable_raw),
        .video_enable_out(ega_attr_video_enable)
    );

    wire [5:0] ega_dbl_color;
    wire ega_dbl_hsync;
    wire ega_vsync_sd_l;
    wire ega_vblank_sd;
    wire ega_display_enable_sd;
    wire ega_visible_vblank = ~ega_vertical_display_enable_crtc;
    video_scandoubler #(.PIXEL_WIDTH(6), .H_TOTAL_MAX(912)) ega_scandoubler (
        .clk(clk),
        .ce_pix(ce_pix),
        .ce_2x(1'b1),
        .scandouble_en(scandouble_en),
        .pixel_in(ega_color_raw),
        .hsync_in(ega_hsync_int),
        .vsync_in(ega_vsync_l),
        .vblank_in(ega_visible_vblank),
        .display_enable_in(ega_display_enable_raw),
        .pixel_out(ega_dbl_color),
        .hsync_out(ega_dbl_hsync),
        .vsync_out(ega_vsync_sd_l),
        .vblank_out(ega_vblank_sd),
        .display_enable_out(ega_display_enable_sd)
    );

    wire ega_vsync = ~ega_vsync_l;
    wire [5:0] ega_video_selected = scandouble_en ? ega_dbl_color : ega_color_raw;
    wire [3:0] ega_video_real = ega_color_raw[3:0];
    wire [6:0] ega_comp_video = {1'b0, ega_color_raw};
    wire ega_vblank_rise = ~ega_vblank_q & ega_visible_vblank;

    ega_vgaport ega_rgb_conv (
        .color(ega_video_selected),
        .palette_64_mode(ega_misc_output_reg[7]),
        .red(ega_red),
        .green(ega_green),
        .blue(ega_blue)
    );

    // IBM EGA switch-sense readback for a color display switch pattern (1001b).
    reg [7:0] ega_switch_sense_reg;
    always @(*) begin
        case (ega_misc_output_reg[3:2])
            2'b00: ega_switch_sense_reg = 8'h10;
            2'b01: ega_switch_sense_reg = 8'h00;
            2'b10: ega_switch_sense_reg = 8'h00;
            2'b11: ega_switch_sense_reg = 8'h10;
        endcase
    end

    reg [7:0] ega_bus_out_mux;
    wire ega_bus_dir_sel = (ega_status_cs & ~bus_ior_l)
                         | (ega_seq_data_cs & ~bus_ior_l)
                         | (ega_attr_read_cs & ~bus_ior_l)
                         | (ega_switch_sense_cs & ~bus_ior_l)
                         | (ega_misc_read_cs & ~bus_ior_l)
                         | (ega_gfx_data_cs & ~bus_ior_l)
                         | (ega_dac_read_index_cs & ~bus_ior_l)
                         | (ega_dac_write_index_cs & ~bus_ior_l)
                         | (ega_dac_data_cs & ~bus_ior_l)
                         | (ega_crtc_cs & ~bus_ior_l & bus_a[0]);

    always @(*) begin
        if (ega_status_cs & ~bus_ior_l)
            ega_bus_out_mux = ega_status_reg;
        else if (ega_seq_data_cs & ~bus_ior_l)
            ega_bus_out_mux = ega_seq_data_out;
        else if (ega_attr_read_cs & ~bus_ior_l)
            ega_bus_out_mux = ega_attr_data_out;
        else if (ega_switch_sense_cs & ~bus_ior_l)
            ega_bus_out_mux = ega_switch_sense_reg;
        else if (ega_misc_read_cs & ~bus_ior_l)
            ega_bus_out_mux = ega_misc_output_reg;
        else if (ega_gfx_data_cs & ~bus_ior_l)
            ega_bus_out_mux = ega_gfx_data_out;
        else if ((ega_dac_read_index_cs | ega_dac_write_index_cs | ega_dac_data_cs) & ~bus_ior_l)
            ega_bus_out_mux = 8'h00;
        else if (ega_crtc_cs & ~bus_ior_l & bus_a[0])
            ega_bus_out_mux = ega_crtc_data_out;
        else
            ega_bus_out_mux = 8'h00;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ega_vblank_q <= 1'b0;
            ega_cfg_toggle <= 1'b0;
            ega_status_read_q <= 1'b0;
            ega_status_toggle <= 2'b00;
            ega_vblank_crtc_q <= 1'b0;
            ega_blink_counter <= 7'h00;
            ega_misc_output_reg <= 8'h63;
            ega_video_active <= 1'b0;
            ega_video_pending <= 1'b0;
            ega_write_seen_since_vblank <= 1'b0;
            ega_crtc_index_shadow <= 5'd0;
            ega_crtc_h_timing_seen <= 1'b0;
            ega_crtc_v_timing_seen <= 1'b0;
            ega_text_fetch_phase <= 5'd0;
            ega_display_enable_delay <= 26'd0;
        end else begin
            if (ce_pix) begin
                if (ega_text_fetch_phase == ega_text_fetch_phase_last) begin
                    ega_text_fetch_phase <= 5'd0;
                end else begin
                    ega_text_fetch_phase <= ega_text_fetch_phase + 5'd1;
                end

                ega_display_enable_delay <= {ega_display_enable_delay[24:0],
                                             ega_display_enable};
            end

            ega_vblank_q <= ega_visible_vblank;
            ega_status_read_q <= ega_status_read;
            ega_vblank_crtc_q <= ega_crtc_fetch_tick ? ega_vert_blank_active_crtc : ega_vblank_crtc_q;
            cpu_mem_write_evt_d <= cpu_mem_write_evt;
            if (ega_misc_write_cs && ega_io_we)
                ega_misc_output_reg <= bus_d;
            if (ega_crtc_cs && ega_io_we && !bus_a[0])
                ega_crtc_index_shadow <= bus_d[4:0];
            else if (ega_crtc_cs && ega_io_we && bus_a[0]) begin
                case (ega_crtc_index_shadow)
                    5'h00, 5'h01, 5'h02: ega_crtc_h_timing_seen <= 1'b1;
                    5'h04, 5'h06, 5'h07, 5'h10, 5'h12: ega_crtc_v_timing_seen <= 1'b1;
                    default: begin
                    end
                endcase
            end
            if (ega_cfg_we)
                ega_cfg_toggle <= ~ega_cfg_toggle;
            if (ega_status_read && !ega_status_read_q)
                ega_status_toggle <= ~ega_status_toggle;
            if (ega_blink_advance)
                ega_blink_counter <= ega_blink_counter + 7'd1;

            if (!ega_enabled) begin
                ega_status_read_q <= 1'b0;
                ega_status_toggle <= 2'b00;
                ega_vblank_crtc_q <= 1'b0;
                ega_blink_counter <= 7'h00;
                ega_text_fetch_phase <= 5'd0;
                ega_display_enable_delay <= 26'd0;
            end

            if (!ega_enabled) begin
                ega_video_active <= 1'b0;
                ega_video_pending <= 1'b0;
                ega_write_seen_since_vblank <= 1'b0;
                ega_crtc_index_shadow <= 5'd0;
                ega_crtc_h_timing_seen <= 1'b0;
                ega_crtc_v_timing_seen <= 1'b0;
            end
            else begin
                if (cpu_mem_write_stretched) begin
                    ega_video_pending <= 1'b1;
                    ega_write_seen_since_vblank <= 1'b1;
                end

                if (ega_vblank_rise) begin
                    if (ega_crtc_timing_ready & ega_video_pending & ~ega_write_seen_since_vblank & ~cpu_mem_write_stretched) begin
                        ega_video_active <= 1'b1;
                        ega_video_pending <= 1'b0;
                    end

                    ega_write_seen_since_vblank <= cpu_mem_write_stretched;
                end
            end
        end
    end

    // Match 86Box more closely: writes to CRTC start address update the
    // latch immediately, but the visible fetch base only changes for the
    // next frame after vertical blank has completed.
    wire [4:0] ega_splash_text_row = ega_scanline_addr[7:3];
    wire [15:0] ega_splash_text_addr =
        {5'd0, ega_splash_text_row, 6'd0} +
        {7'd0, ega_splash_text_row, 4'd0} +
        {8'd0, ega_char_col};
    assign ega_fetch_addr = ega_splash_active ? ega_splash_text_addr : ega_crtc_addr_full;
    assign ega_fetch_en = ega_display_sel ? (ega_graphics_mode_active & ega_ce_crt_fetch & ega_display_enable_render) : 1'b0;
    assign ega_text_fetch_en = ega_display_sel & ega_text_mode_active & ega_text_fetch_en_raw;
    assign ega_plane_write_mask_out = ega_plane_write_mask;
    assign ega_odd_even_mode_out = ega_odd_even_mode;
    assign ega_cpu_access_slot_out = ega_ce_cpu_access_unused;
    assign ega_chain2_write_out = ega_chain2_write;
    assign ega_chain2_read_out = ega_chain2_read;
    assign ega_extended_memory_out = ega_extended_memory;
    assign ega_mem_map_sel_out = ega_mem_map_sel;
    assign ega_page_select_out = ega_misc_output_reg[5];
    assign ega_write_mode_out = ega_write_mode;
    assign ega_read_mode_out = ega_read_mode;
    assign ega_read_plane_sel_out = ega_read_plane_sel;
    assign ega_color_compare_out = ega_color_compare;
    assign ega_color_dont_care_out = ega_color_dont_care;
    assign ega_bit_mask_out = ega_bit_mask;
    assign ega_set_reset_out = ega_set_reset;
    assign ega_enable_set_reset_out = ega_enable_set_reset;
    assign ega_rop_select_out = ega_rop_select;
    assign ega_rotate_count_out = ega_rotate_count;
    assign ega_blink_counter_out = ega_blink_counter;
    assign ega_blink_state_out = ega_blink_state;
    assign ega_rgb_active = ega_display_sel;
    assign ega_display_sel_out = ega_display_sel;

    assign bus_out = ega_bus_out_mux;
    assign bus_dir = ega_enabled ? ega_bus_dir_sel : 1'b0;
    assign ram_we_l = 1'b0;
    assign ram_a = 19'd0;
    assign hsync = ega_enabled ? ega_hsync_int : 1'b1;
    assign dbl_hsync = ega_enabled ? ega_dbl_hsync : 1'b1;
    assign hblank = ega_enabled ? (scandouble_en ? ~ega_display_enable_sd : ega_hblank_crtc) : 1'b1;
    assign vsync = ega_enabled ? (scandouble_en ? ~ega_vsync_sd_l : ega_vsync) : 1'b1;
    assign vblank = ega_enabled ? (scandouble_en ? ega_vblank_sd : ega_visible_vblank) : 1'b1;
    assign vblank_border = ega_enabled ? (scandouble_en ? ega_vblank_sd : ega_vblank_crtc) : 1'b1;
    assign std_hsyncwidth = ega_enabled
                          ? (ega_hsync_width_crtc == (ega_dot_clock_div2_active ? EGA_STD_HSYNC_W_LO : EGA_STD_HSYNC_W_HI))
                          : 1'b0;
    assign de_o = ega_display_sel ? (scandouble_en ? ega_display_enable_sd : ega_display_enable_raw) : 1'b0;
    assign video = ega_display_sel ? ega_video_real : 4'd0;
    assign dbl_video = ega_display_sel ? ega_dbl_color[3:0] : 4'd0;
    assign comp_video = ega_display_sel ? ega_comp_video : 7'd0;
    assign grph_mode = ega_enabled ? ega_graphics_mode_active : 1'b0;
    assign hres_mode = ega_enabled ? ega_hres_mode_int : 1'b0;
endmodule
