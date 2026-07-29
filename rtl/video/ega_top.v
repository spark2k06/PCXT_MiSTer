//============================================================================
//
//  PCXT MiSTer EGA top level
//
//============================================================================

`default_nettype wire

module ega_top(
    input clk,
    input reset,
    input [14:0] bus_a,
    input bus_ior_l,
    input bus_iow_l,
    input [7:0] bus_d,
    output [7:0] bus_out,
    output bus_dir,
    input bus_aen,
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
    output [15:0] vga_framebuffer_addr,
    output vga_framebuffer_read_en,
    input [7:0] vga_framebuffer_pixel,
    input vga_framebuffer_data_valid,
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
    output [5:0] ega_red,
    output [5:0] ega_green,
    output [5:0] ega_blue,
    output ega_display_sel_out,
    output ega_dot_toggle_out,
    output ega_dot_clock_sel_out,
    output ega_scandouble_active_out,
    input splashscreen,
    input thin_font,
    input scandouble_en,
    input ega_enabled,
    input vga_enabled,
    input vga_mode13_set,
    input vga_mode13_clear,
    output vga_mode13_active_out,
    input [3:0] crt_h_offset,
    input [2:0] crt_v_offset,
    input [2:0] vsync_width_osd,
    input [2:0] hsync_width_osd
    );

    parameter BLINK_MAX = 0;
    parameter USE_BUS_WAIT = 0;
    parameter NO_DISPLAY_DISABLE = 0;
    parameter IO_BASE_ADDR = 16'h3d0;

    localparam [3:0] EGA_STD_HSYNC_W_HI = 4'd10;
    localparam [3:0] EGA_STD_HSYNC_W_LO = 4'd5;

    // Dot clock selected by Miscellaneous Output bit 2, as on a real EGA:
    // 0 = 14.318181 MHz (CGA compatible modes), 1 = 16.257 MHz (350 line
    // modes and MDA compatible mode 7).
    wire ce_pix;
    wire ce_pix_early;
    wire ce_pix_2x;
    wire ega_dot_toggle;
    wire ega_hifreq_mode;

    ega_dot_clock ega_dot_clock_inst (
        .clk            (clk),
        .reset          (reset),
        .clock_select   (ega_hifreq_mode),
        .ce_dot         (ce_pix),
        .ce_dot_early   (ce_pix_early),
        .ce_dot_2x      (ce_pix_2x),
        .dot_toggle     (ega_dot_toggle)
    );

    wire [15:0] ega_io_addr = {1'b0, bus_a};

    // bus_a, bus_d and the strobes reach this module through independent
    // two-stage synchronisers (Peripherals.sv), one per bit, so they do not
    // all resolve on the same video clock. While an address changes, the
    // decoders below can see an address that was never on the bus: 0x3C5 ->
    // 0x3CF, a pair the BIOS and every EGA program write constantly, passes
    // through 0x3CD when bit 3 lands a cycle before bit 1, and 0x3C5 -> 0x3C2
    // passes through 0x3C0 and 0x3C7. Landing on the wrong register is bad
    // enough in the attribute controller; on Miscellaneous Output it changes
    // the dot clock out from under the CRTC.
    //
    // Qualifying with two identical consecutive samples makes every decode
    // below immune: a transient lasts one video clock, a real I/O cycle holds
    // the bus for the best part of a microsecond. The cost is that a strobe
    // starts one clock late, which the sequencer and graphics controller do
    // not care about (they write by level, so it is idempotent) and the
    // attribute controller does not either (it already edge-detects).
    reg [14:0] bus_a_q = 15'd0;
    reg [7:0]  bus_d_q = 8'd0;
    reg        bus_iow_l_q = 1'b1;
    reg        bus_ior_l_q = 1'b1;
    reg        bus_aen_q = 1'b0;
    wire bus_settled = (bus_a == bus_a_q) & (bus_d == bus_d_q)
                     & (bus_iow_l == bus_iow_l_q) & (bus_ior_l == bus_ior_l_q)
                     & (bus_aen == bus_aen_q);

    // Everything derived from these two carries the qualifier, so the
    // sequencer, graphics controller, attribute controller, Miscellaneous
    // Output, the CRTC and the DAC are all covered at once.
    wire ega_io_we = ~bus_iow_l & ~bus_aen & ega_enabled & bus_settled;
    wire ega_io_re = ~bus_ior_l & ~bus_aen & ega_enabled & bus_settled;
    reg [7:0] ega_misc_output_reg = 8'h63;
    wire ega_color_io_select = ega_misc_output_reg[0];
    assign ega_hifreq_mode = ega_misc_output_reg[2];
    wire ega_color_crtc_cs = (bus_a[14:1] == (15'h03D4 >> 1));
    wire ega_mono_crtc_cs = (bus_a[14:1] == (15'h03B4 >> 1));
    wire ega_color_status_cs = (bus_a == 15'h03DA);
    wire ega_mono_status_cs = (bus_a == 15'h03BA);
    // The CRTC takes its own chip select rather than ega_io_we, and a stray
    // write here reprograms the display timing, so it needs the qualifier
    // directly. Reads go through the same select and simply start a clock
    // later, which the bus cycle has ample room for.
    wire ega_crtc_cs = (ega_color_io_select ? ega_color_crtc_cs : ega_mono_crtc_cs) & ~bus_aen & ega_enabled & bus_settled;
    wire ega_status_cs = (ega_color_io_select ? ega_color_status_cs : ega_mono_status_cs) & ~bus_aen & ega_enabled;
    wire ega_seq_data_cs = ((bus_a == 15'h03C5) || (bus_a == 15'h02C5)) & ~bus_aen & ega_enabled;
    wire ega_attr_read_cs = ((bus_a == 15'h03C1) || (bus_a == 15'h02C1)) & ~bus_aen & ega_enabled;
    wire ega_misc_write_cs = ((bus_a == 15'h03C2) || (bus_a == 15'h02C2)) & ~bus_aen & ega_enabled;
    wire ega_switch_sense_cs = ((bus_a == 15'h03C2) || (bus_a == 15'h02C2)) & ~bus_aen & ega_enabled;
    wire ega_misc_read_cs = ((bus_a == 15'h03CC) || (bus_a == 15'h02CC)) & ~bus_aen & ega_enabled;
    wire ega_gfx_data_cs = ((bus_a == 15'h03CF) || (bus_a == 15'h02CF)) & ~bus_aen & ega_enabled;
    // 3C7-3C9 belong to the VGA mode 13h DAC, which a real IBM EGA does not have
    // at all: its palette lives in the attribute controller. Leaving them answering
    // with mode 13h switched off makes the card read as a VGA to anything probing
    // the DAC, so gate them on the OSD option. Gate on vga_enabled rather than
    // mode13_active, so software can still load the palette before setting the mode.
    wire ega_dac_read_index_cs = ((bus_a == 15'h03C7) || (bus_a == 15'h02C7)) & ~bus_aen & ega_enabled & vga_enabled;
    wire ega_dac_write_index_cs = ((bus_a == 15'h03C8) || (bus_a == 15'h02C8)) & ~bus_aen & ega_enabled & vga_enabled;
    wire ega_dac_data_cs = ((bus_a == 15'h03C9) || (bus_a == 15'h02C9)) & ~bus_aen & ega_enabled & vga_enabled;
    wire vga_mode13_bios_ctrl_cs = (bus_a == 15'h03CD) & ~bus_aen & ega_enabled;
    // Readback on the same port: guest software cannot otherwise tell whether the
    // OSD has VGA mode 13h available, and must not claim VGA on a machine that
    // will never render it. 0x13 echoes the value used to enter the mode.
    wire [7:0] vga_mode13_status = vga_enabled ? 8'h13 : 8'h00;
    wire vga_mode13_bios_set = vga_mode13_bios_ctrl_cs & ega_io_we & (bus_d == 8'h13);
    wire vga_mode13_bios_clear = vga_mode13_bios_ctrl_cs & ega_io_we & (bus_d != 8'h13);
    wire vga_mode13_enter = vga_mode13_set | vga_mode13_bios_set;
    wire vga_mode13_exit = vga_mode13_clear | vga_mode13_bios_clear;
    wire [7:0] vga_dac_io_data_out;
    wire [7:0] vga_dac_sample_index;
    wire [7:0] vga_renderer_dac_index;
    wire       vga_dac_sample_valid;
    wire [5:0] vga_dac_sample_red;
    wire [5:0] vga_dac_sample_green;
    wire [5:0] vga_dac_sample_blue;
    wire [7:0] vga_dac_sample_red_8;
    wire [7:0] vga_dac_sample_green_8;
    wire [7:0] vga_dac_sample_blue_8;
    // Covered by the qualifier on ega_io_we: without it a momentary 0x3C8
    // would reseat the write index and smear the rest of a palette load across
    // the wrong entries.
    wire vga_dac_read_index_write_raw = ega_dac_read_index_cs & ega_io_we;
    wire vga_dac_write_index_write_raw = ega_dac_write_index_cs & ega_io_we;
    wire vga_dac_data_write_raw = ega_dac_data_cs & ega_io_we;
    wire vga_dac_read_index_read_raw = ega_dac_read_index_cs & ega_io_re;
    wire vga_dac_write_index_read_raw = ega_dac_write_index_cs & ega_io_re;
    wire vga_dac_data_read_raw = ega_dac_data_cs & ega_io_re;
    reg vga_dac_read_index_write_q = 1'b0;
    reg vga_dac_write_index_write_q = 1'b0;
    reg vga_dac_data_write_q = 1'b0;
    wire vga_dac_read_index_write_evt = vga_dac_read_index_write_raw & ~vga_dac_read_index_write_q;
    wire vga_dac_write_index_write_evt = vga_dac_write_index_write_raw & ~vga_dac_write_index_write_q;
    wire vga_dac_data_write_evt = vga_dac_data_write_raw & ~vga_dac_data_write_q;
    wire ega_cfg_we = ega_enabled && ega_io_we && ((ega_io_addr == 16'h03C5) || (ega_io_addr == 16'h02C5) || (ega_io_addr == 16'h03CF) || (ega_io_addr == 16'h02CF));

    reg ega_video_active = 1'b0;
    reg ega_video_pending = 1'b0;
    reg ega_write_seen_since_vblank = 1'b0;
    wire vga_mode13_active;
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
    wire ega_ce_crt_fetch_early;
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
    wire [5:0] ega_red_compat;
    wire [5:0] ega_green_compat;
    wire [5:0] ega_blue_compat;
    wire [5:0] vga_red;
    wire [5:0] vga_green;
    wire [5:0] vga_blue;
    wire       vga_de;
    wire       vga_hsync;
    wire       vga_vsync;
    wire       vga_hblank;
    wire       vga_vblank;
    wire [5:0] ega_color_raw;
    wire ega_display_enable_raw;
    wire ega_attr_video_enable;
    wire [3:0] ega_graphics_plane_index;
    wire ega_graphics_pixel_valid;
    wire [3:0] ega_text_plane_index;
    wire ega_text_pixel_valid;
    wire [3:0] ega_splash_pixel_index;
    wire ega_splash_pixel_valid;
    wire ega_graphics_mode_active = ega_splash_active ? 1'b0 : ega_graphics_mode;
    wire ega_dot_clock_div2_active = ega_splash_active ? 1'b0 : ega_dot_clock_div2;
    wire ega_char_9dot_active = ega_splash_active ? 1'b0 : ega_char_9dot;
    wire [3:0] ega_plane_index = ega_splash_active ? ega_splash_pixel_index :
                                 ega_graphics_mode_active ? ega_graphics_plane_index : ega_text_plane_index;
    wire ega_pixel_valid = ega_splash_active ? ega_splash_pixel_valid :
                           ega_graphics_mode_active ? ega_graphics_pixel_valid : ega_text_pixel_valid;
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
    localparam [4:0] EGA_VISIBLE_ADJ_TEXT_1X_A   = 5'd0;
    localparam [4:0] EGA_VISIBLE_ADJ_TEXT_1X_B   = 5'd0;
    localparam [4:0] EGA_VISIBLE_ADJ_TEXT_DIV2_A = 5'd3;
    localparam [4:0] EGA_VISIBLE_ADJ_TEXT_DIV2_B = 5'd3;
    localparam [4:0] EGA_VISIBLE_ADJ_GFX_1X_A    = 5'd1;
    localparam [4:0] EGA_VISIBLE_ADJ_GFX_1X_B    = 5'd1;
    localparam [4:0] EGA_VISIBLE_ADJ_GFX_DIV2_A  = 5'd7;
    localparam [4:0] EGA_VISIBLE_ADJ_GFX_DIV2_B  = 5'd7;

    wire [4:0] ega_visible_base_delay = ega_graphics_mode_active ? ega_graphics_fetch_phase_last :
                                                                   ega_text_fetch_phase_last;
    wire [4:0] ega_visible_extra_delay = ega_dot_clock_div2_active ? 5'd8 : 5'd4;
    wire [4:0] ega_visible_adjust_a =
        ega_graphics_mode_active ?
            (ega_dot_clock_div2_active ? EGA_VISIBLE_ADJ_GFX_DIV2_A : EGA_VISIBLE_ADJ_GFX_1X_A) :
            (ega_dot_clock_div2_active ? EGA_VISIBLE_ADJ_TEXT_DIV2_A : EGA_VISIBLE_ADJ_TEXT_1X_A);
    wire [4:0] ega_visible_adjust_b =
        ega_graphics_mode_active ?
            (ega_dot_clock_div2_active ? EGA_VISIBLE_ADJ_GFX_DIV2_B : EGA_VISIBLE_ADJ_GFX_1X_B) :
            (ega_dot_clock_div2_active ? EGA_VISIBLE_ADJ_TEXT_DIV2_B : EGA_VISIBLE_ADJ_TEXT_1X_B);
    wire [4:0] ega_visible_delay_a = ega_visible_base_delay + ega_visible_extra_delay - ega_visible_adjust_a;
    wire [4:0] ega_visible_delay_b = ega_visible_base_delay + ega_visible_extra_delay - ega_visible_adjust_b;

    wire ega_crtc_fetch_tick = (!ega_graphics_mode_active && (ega_splash_active || ega_char_9dot_active)) ? ega_text_fetch_tick :
                                                                                                          ega_ce_crt_fetch;
    wire [1:0] ega_render_mode = !ega_graphics_mode_active ? 2'd0 :
                                  ega_compat_2bpp_mode ? 2'd2 : 2'd1;
    wire ega_display_enable = ega_display_enable_crtc;
    reg [25:0] ega_display_enable_delay = 26'd0;
    wire ega_display_enable_visible = ega_display_enable_delay[ega_visible_delay_a] |
                                      ega_display_enable_delay[ega_visible_delay_b];
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
    // Reading the status register is what resets the attribute controller's
    // address/data flip-flop, so it is a read with a side effect. A transient
    // decode landing here between an ATC index write and its data write turns
    // the data write into an index write, which is one way attributes come out
    // wrong. The bus_out mux keeps using the unqualified select, so only the
    // side effect moves, never the read data.
    wire       ega_status_read = ega_status_cs & ~bus_ior_l & bus_settled;
    wire       ega_blink_advance = ega_crtc_fetch_tick & ega_vert_blank_active_crtc & ~ega_vblank_crtc_q;
    wire       ega_blink_state = ega_blink_counter[4];
    wire [7:0] ega_status_reg = {2'b00, ega_status_toggle, ega_status_vretrace_active, 2'b00, ega_blanking_active};

    vga_mode13_ctrl vga_mode13_state (
        .clk(clk),
        .reset(reset),
        .vga_enabled(vga_enabled),
        .mode13_set(vga_mode13_enter),
        .mode13_clear(vga_mode13_exit),
        .vga_mode13_active(vga_mode13_active)
    );

    UM6845R ega_crtc (
        .CLOCK(clk),
        .CLKEN(ega_crtc_fetch_tick),
        .PIXEL_CE(ce_pix),
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

    // Reset to an 80-column text base so the pre-BIOS graphical splash has
    // stable EGA-compatible sync before BIOS programs its final mode timings.
    defparam ega_crtc.H_TOTAL = 8'd112;
    defparam ega_crtc.H_DISP = 8'd80;
    defparam ega_crtc.H_SYNCPOS = 8'd90;
    defparam ega_crtc.H_SYNCWIDTH = 4'd10;
    defparam ega_crtc.V_TOTAL = 7'd31;
    defparam ega_crtc.V_TOTALADJ = 5'd6;
    // EGA extended timing uses R7 as overflow bits, R6 as vertical-total low,
    // and R18/R16 as display-end and sync-start low bytes. Seed a 262-line,
    // 200-visible-line frame for the splash before BIOS programs the CRTC.
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
        .ce_pix_early(ce_pix_early),
        .io_addr(ega_io_addr),
        .io_data_in(bus_d),
        .io_data_out(ega_seq_data_out),
        .io_we(ega_io_we),
        .io_re(ega_io_re),
        .plane_write_mask(ega_plane_write_mask),
        .chain2_write(ega_chain2_write),
        .extended_memory(ega_extended_memory),
        .ce_crt_fetch(ega_ce_crt_fetch),
        .ce_crt_fetch_early(ega_ce_crt_fetch_early),
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
        .display_enable((ega_text_mode_active && !ega_splash_active) ? ega_display_enable_render : 1'b0),
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
        .text_cell_addr(ega_text_cell_addr),
        .text_font_addr(ega_text_font_addr),
        .text_fetch_en(ega_text_fetch_en_raw),
        .plane_index(ega_text_plane_index),
        .pixel_valid(ega_text_pixel_valid)
    );

    ega_splash_renderer ega_splash_renderer_inst (
        .clk            (clk),
        .reset          (reset),
        .ce_pix         (ce_pix),
        .enable         (ega_splash_active),
        .display_enable (ega_display_enable_visible),
        .scanline       (ega_scanline_addr),
        .pixel_index    (ega_splash_pixel_index),
        .pixel_valid    (ega_splash_pixel_valid)
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

    vga_dac_io vga_dac_io_inst (
        .clock              (clk),
        .reset              (reset),
        .load_defaults      (vga_mode13_enter),
        .invalidate         (vga_mode13_exit),
        .palette_64_mode    (ega_misc_output_reg[7]),
        .read_index_write   (vga_dac_read_index_write_evt),
        .write_index_write  (vga_dac_write_index_write_evt),
        .data_write         (vga_dac_data_write_evt),
        .read_index_read    (vga_dac_read_index_read_raw),
        .write_index_read   (vga_dac_write_index_read_raw),
        .data_read          (vga_dac_data_read_raw),
        .io_data_in         (bus_d),
        .io_data_out        (vga_dac_io_data_out),
        .sample_index       (vga_dac_sample_index),
        .sample_red         (vga_dac_sample_red),
        .sample_green       (vga_dac_sample_green),
        .sample_blue        (vga_dac_sample_blue),
        .sample_red_8       (vga_dac_sample_red_8),
        .sample_green_8     (vga_dac_sample_green_8),
        .sample_blue_8      (vga_dac_sample_blue_8),
        .sample_valid       (vga_dac_sample_valid)
    );

    // VGA mode 13h renders through its own dedicated index into the shared
    // DAC; every other mode reuses the same 256-entry DAC to let a VGA-aware
    // EGA program page its 16/256-colour palette through the same ports,
    // falling back to the classic EGA DAC-less palette (ega_vgaport) for any
    // entry the program never touched. See docs/vga-vga-palette.md. The mux
    // source for the non-mode13h case (ega_video_selected) is only available
    // after the scandoubler below, so this wire is driven further down.
    wire ega_dac_hit = vga_enabled & ~vga_mode13_active & vga_dac_sample_valid;

    vga_mode13_renderer vga_renderer (
        .clock                  (clk),
        .reset                  (reset),
        .enable                 (vga_mode13_active),
        .framebuffer_addr       (vga_framebuffer_addr),
        .framebuffer_read_en    (vga_framebuffer_read_en),
        .framebuffer_pixel      (vga_framebuffer_pixel),
        .framebuffer_data_valid (vga_framebuffer_data_valid),
        .dac_index              (vga_renderer_dac_index),
        .dac_red                (vga_dac_sample_red),
        .dac_green              (vga_dac_sample_green),
        .dac_blue               (vga_dac_sample_blue),
        .red                    (vga_red),
        .green                  (vga_green),
        .blue                   (vga_blue),
        .de                     (vga_de),
        .hsync                  (vga_hsync),
        .vsync                  (vga_vsync),
        .hblank                 (vga_hblank),
        .vblank                 (vga_vblank)
    );

    wire [5:0] ega_dbl_color;
    wire ega_dbl_hsync;
    wire ega_vsync_sd_l;
    wire ega_vblank_sd;
    wire ega_display_enable_sd;
    wire ega_visible_vblank = ~ega_vertical_display_enable_crtc;

    // The line doubler needs an output enable at exactly twice the dot rate.
    // 2 x 16.257 MHz cannot be produced from the 28.636 MHz video clock, and
    // the 16.257 MHz modes scan at 18.4 - 21.9 kHz, well above the 15.7 kHz
    // that made doubling useful in the first place, so it is bypassed there.
    wire ega_scandouble_active = scandouble_en & ~ega_hifreq_mode;

    video_scandoubler #(.PIXEL_WIDTH(6), .H_TOTAL_MAX(912)) ega_scandoubler (
        .clk(clk),
        .ce_pix(ce_pix),
        .ce_2x(ce_pix_2x),
        .scandouble_en(ega_scandouble_active),
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
    wire [5:0] ega_video_selected = ega_scandouble_active ? ega_dbl_color : ega_color_raw;
    wire ega_vblank_rise = ~ega_vblank_q & ega_visible_vblank;
    assign vga_dac_sample_index = vga_mode13_active ? vga_renderer_dac_index
                                                       : {2'b00, ega_video_selected};

    ega_vgaport ega_rgb_conv (
        .color(ega_video_selected),
        .palette_64_mode(ega_misc_output_reg[7]),
        .red(ega_red_compat),
        .green(ega_green_compat),
        .blue(ega_blue_compat)
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
                         | (vga_mode13_bios_ctrl_cs & ~bus_ior_l)
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
            ega_bus_out_mux = vga_dac_io_data_out;
        else if (vga_mode13_bios_ctrl_cs & ~bus_ior_l)
            ega_bus_out_mux = vga_mode13_status;
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
            vga_dac_read_index_write_q <= 1'b0;
            vga_dac_write_index_write_q <= 1'b0;
            vga_dac_data_write_q <= 1'b0;
            bus_a_q <= 15'd0;
            bus_d_q <= 8'd0;
            bus_iow_l_q <= 1'b1;
            bus_ior_l_q <= 1'b1;
            bus_aen_q <= 1'b0;
            ega_text_fetch_phase <= 5'd0;
            ega_display_enable_delay <= 26'd0;
        end else begin
            bus_a_q <= bus_a;
            bus_d_q <= bus_d;
            bus_iow_l_q <= bus_iow_l;
            bus_ior_l_q <= bus_ior_l;
            bus_aen_q <= bus_aen;
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
            vga_dac_read_index_write_q <= vga_dac_read_index_write_raw;
            vga_dac_write_index_write_q <= vga_dac_write_index_write_raw;
            vga_dac_data_write_q <= vga_dac_data_write_raw;
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
    assign ega_fetch_addr = ega_crtc_addr_full;
    // Issued one clock ahead of the character dot: the plane data has a fixed
    // two clock latency, and on the 16.257 MHz enable the next dot can be one
    // clock away, in which case data launched on the tick itself would arrive
    // a dot late and shift that character by one pixel.
    assign ega_fetch_en = (!vga_mode13_active && ega_display_sel) ? (ega_graphics_mode_active & ega_ce_crt_fetch_early & ega_display_enable_render) : 1'b0;
    assign ega_text_fetch_en = !vga_mode13_active & ega_display_sel & ega_text_mode_active &
                               !ega_splash_active & ega_text_fetch_en_raw;
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
    assign vga_mode13_active_out = vga_mode13_active;
    assign ega_display_sel_out = vga_mode13_active ? vga_de : ega_display_sel;

    assign bus_out = ega_bus_out_mux;
    assign bus_dir = ega_enabled ? ega_bus_dir_sel : 1'b0;
    assign ega_red   = vga_mode13_active ? vga_red
                     : ega_dac_hit        ? vga_dac_sample_red   : ega_red_compat;
    assign ega_green = vga_mode13_active ? vga_green
                     : ega_dac_hit        ? vga_dac_sample_green : ega_green_compat;
    assign ega_blue  = vga_mode13_active ? vga_blue
                     : ega_dac_hit        ? vga_dac_sample_blue  : ega_blue_compat;
    assign hsync = ega_enabled ? (vga_mode13_active ? vga_hsync : ega_hsync_int) : 1'b1;
    assign dbl_hsync = ega_enabled ? (vga_mode13_active ? vga_hsync : ega_dbl_hsync) : 1'b1;
    assign hblank = ega_enabled ? (vga_mode13_active ? vga_hblank : (ega_scandouble_active ? ~ega_display_enable_sd : ega_hblank_crtc)) : 1'b1;
    assign vsync = ega_enabled ? (vga_mode13_active ? vga_vsync : (ega_scandouble_active ? ~ega_vsync_sd_l : ega_vsync)) : 1'b1;
    assign vblank = ega_enabled ? (vga_mode13_active ? vga_vblank : (ega_scandouble_active ? ega_vblank_sd : ega_visible_vblank)) : 1'b1;
    assign vblank_border = ega_enabled ? (vga_mode13_active ? vga_vblank : (ega_scandouble_active ? ega_vblank_sd : ega_vblank_crtc)) : 1'b1;
    assign std_hsyncwidth = ega_enabled
                          ? (ega_hsync_width_crtc == (ega_dot_clock_div2_active ? EGA_STD_HSYNC_W_LO : EGA_STD_HSYNC_W_HI))
                          : 1'b0;
    assign de_o = vga_mode13_active ? vga_de :
                  (ega_display_sel ? (ega_scandouble_active ? ega_display_enable_sd : ega_display_enable_raw) : 1'b0);

    assign ega_dot_toggle_out = ega_dot_toggle;
    assign ega_dot_clock_sel_out = ega_hifreq_mode;
    assign ega_scandouble_active_out = ega_scandouble_active;
endmodule
