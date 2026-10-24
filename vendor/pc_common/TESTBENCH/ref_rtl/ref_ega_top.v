// REFERENCE COPY for ega_sdram_equiv_tb: the EGA core as it was before the SDRAM
// retiming, modules renamed ref_*. Do not edit.
//============================================================================
//
//  PCXT MiSTer EGA top level
//
//============================================================================

// Strictly an IBM EGA: modes 0-7, 0Dh, 0Eh, 0Fh and 10h through the attribute
// controller, with no VGA extension (no mode 13h, Mode X, DAC or VGA readbacks).
//
// Shared library version (see vendor/pc_common/PINNED). The boot splash is not
// part of the common core: a core that wants one drives splashscreen and feeds
// the pixel through the ext_splash_* hooks (PCXT-EGA uses ega_splash_renderer,
// PCAT-286 its own). Everything else is reconciled from PCXT-EGA and PCAT-286.
`default_nettype wire

module ref_ega_top(
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
    // The geometry the CRTC is currently asked for, held still for a whole
    // frame. A 15 kHz television cannot scan more than about 240 lines
    // progressively, so anything above that is what the 480i conversion is
    // for; the width tells it whether to centre 640 dots or fill with 720.
    output ega_mode350_out,
    output [11:0] ega_active_dots_out,
    output [9:0] ega_active_lines_out,
    // Toggles once after a software-programmed timing/mode change reaches
    // vertical blank.  MiSTer uses this to re-evaluate its video_mode mapping.
    output reg ega_vmode_toggle_out,
    input splashscreen,
    // Splash hooks. While splashscreen is high the CRTC runs its power-on
    // geometry in a fixed 8-dot graphics rendering and the pixel comes from the
    // core's own renderer, which needs the character-rate timing below.
    input [3:0] ext_splash_pixel_index,
    input ext_splash_pixel_valid,
    output ext_splash_ce_pix,
    output ext_splash_display_enable,
    output [9:0] ext_splash_scanline,
    input prebios_video,
    input thin_font,
    input scandouble_en,
    input ega_enabled,
    input [1:0] ega_monitor_profile,
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

    // Horizontal Pel Panning is applied as a variable delay on the dot stream
    // against a fixed delay on everything else, so a shift of s dots to the
    // left is a dot delay of (EGA_PAN_MAX - s). EGA_PAN_MAX is the widest shift
    // the register can ask for: eight character dots, doubled when the
    // sequencer halves the dot clock.
    localparam integer EGA_PAN_MAX = 16;
    // The 8 dot character modes can also ask for one dot width of shift to the
    // *right* (panning values 8-15), so the delay line is two dots longer.
    localparam integer EGA_PAN_STAGES = EGA_PAN_MAX + 2;

    // Tap on the dot delay line, packed {pixel_valid, plane_index} per stage.
    function [4:0] ega_pan_pick;
        input [(5*EGA_PAN_STAGES)-1:0] pipe;
        input [4:0]                    idx;   // 0 = one dot ago
        begin
            case (idx)
                5'd0:  ega_pan_pick = pipe[4:0];
                5'd1:  ega_pan_pick = pipe[9:5];
                5'd2:  ega_pan_pick = pipe[14:10];
                5'd3:  ega_pan_pick = pipe[19:15];
                5'd4:  ega_pan_pick = pipe[24:20];
                5'd5:  ega_pan_pick = pipe[29:25];
                5'd6:  ega_pan_pick = pipe[34:30];
                5'd7:  ega_pan_pick = pipe[39:35];
                5'd8:  ega_pan_pick = pipe[44:40];
                5'd9:  ega_pan_pick = pipe[49:45];
                5'd10: ega_pan_pick = pipe[54:50];
                5'd11: ega_pan_pick = pipe[59:55];
                5'd12: ega_pan_pick = pipe[64:60];
                5'd13: ega_pan_pick = pipe[69:65];
                5'd14: ega_pan_pick = pipe[74:70];
                5'd15: ega_pan_pick = pipe[79:75];
                5'd16: ega_pan_pick = pipe[84:80];
                default: ega_pan_pick = pipe[89:85];
            endcase
        end
    endfunction

    // Dot clock selected by Miscellaneous Output bit 2, as on a real EGA:
    // 0 = 14.318181 MHz (CGA compatible modes), 1 = 16.257 MHz (350 line
    // modes and MDA compatible mode 7).
    wire ce_pix;
    wire ce_pix_early;
    wire ce_pix_2x;
    wire ega_dot_toggle;
    wire ega_hifreq_mode;
    wire ega_crtc_line_reset;
    wire ega_dot_line_lock;

    ref_ega_dot_clock ega_dot_clock_inst (
        .clk            (clk),
        .reset          (reset),
        .clock_select   (ega_hifreq_mode),
        .line_lock      (ega_dot_line_lock),
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
    //
    // The qualifier is split in two, because what has to be settled is not the
    // same for a read as for a write. The hazard above is an *address* hazard,
    // so bus_addr_settled is what every decode needs. bus_d only matters when
    // its value is about to be latched, which is a write.
    //
    // A read must not require bus_d to be settled, and this is not a style
    // preference: bus_d is not an input during a read. Peripherals.sv latches
    // video_io_data from internal_data_bus while either strobe is low, and on a
    // read internal_data_bus carries what this module is driving back, so our
    // own read data returns on bus_d a few clocks later. Gating a read on
    // bus_d == bus_d_q therefore gates it on its own result: the byte would
    // oscillate for the whole cycle.
    reg [14:0] bus_a_q = 15'd0;
    reg [7:0]  bus_d_q = 8'd0;
    reg        bus_iow_l_q = 1'b1;
    reg        bus_ior_l_q = 1'b1;
    reg        bus_aen_q = 1'b0;
    wire bus_addr_settled = (bus_a == bus_a_q) & (bus_aen == bus_aen_q);
    wire bus_write_settled = bus_addr_settled & (bus_d == bus_d_q)
                           & (bus_iow_l == bus_iow_l_q);

    // Everything derived from these two carries the qualifier, so the
    // sequencer, graphics controller, attribute controller, Miscellaneous
    // Output and the CRTC are all covered at once.
    wire ega_io_we = ~bus_iow_l & ~bus_aen & ega_enabled & bus_write_settled;
    wire ega_io_re = ~bus_ior_l & ~bus_aen & ega_enabled & bus_addr_settled;
    reg [7:0] ega_misc_output_reg = 8'h63;
    wire ega_color_io_select = ega_misc_output_reg[0];
    assign ega_hifreq_mode = ega_misc_output_reg[2];
    wire ega_color_crtc_cs = (bus_a[14:1] == (15'h03D4 >> 1));
    wire ega_mono_crtc_cs = (bus_a[14:1] == (15'h03B4 >> 1));
    wire ega_color_status_cs = (bus_a == 15'h03DA);
    wire ega_mono_status_cs = (bus_a == 15'h03BA);
    // The CRTC takes its own chip select rather than ega_io_we, and a stray
    // write here reprograms the display timing, so it needs the address
    // qualifier directly; the data half comes from ega_io_we at the write
    // itself. Reads go through the same select and simply start a clock later,
    // which the bus cycle has ample room for - and because this select also
    // drives bus_dir and the read mux for 3D5h, it must not carry the data
    // qualifier either, for the same reason ega_io_re does not.
    wire ega_crtc_cs = (ega_color_io_select ? ega_color_crtc_cs : ega_mono_crtc_cs) & ~bus_aen & ega_enabled & bus_addr_settled;
    wire ega_status_cs = (ega_color_io_select ? ega_color_status_cs : ega_mono_status_cs) & ~bus_aen & ega_enabled;
    wire ega_misc_write_cs = ((bus_a == 15'h03C2) || (bus_a == 15'h02C2)) & ~bus_aen & ega_enabled;
    // 3C2h is write-only here. Reading it returns Input Status Register 0, and
    // that byte is produced in the ISA clock domain by ega_switch_sense_host in
    // Peripherals.sv. Answering it from here as well would race: the selector
    // this side owns is ega_misc_output_reg, which is several clocks behind the
    // OUT that set it, and the ROM reads the switches immediately after writing
    // the selector. See the note on the instance in Peripherals.sv.
    wire ega_cfg_we = ega_enabled && ega_io_we && ((ega_io_addr == 16'h03C5) || (ega_io_addr == 16'h02C5) || (ega_io_addr == 16'h03CF) || (ega_io_addr == 16'h02CF));

    reg ega_video_active = 1'b0;
    reg ega_video_pending = 1'b0;
    reg ega_write_seen_since_vblank = 1'b0;
    reg ega_vblank_q = 1'b0;
    wire ega_splash_active = ega_enabled & splashscreen;
    // During a BIOS hold, keep the power-on CRTC geometry active for video
    // detection, but output black while no splash is being drawn.
    wire ega_prebios_active = ega_enabled & prebios_video;
    wire ega_prebios_black = ega_prebios_active & !ega_splash_active;
    // Monitor switches are not applied until the BIOS starts, so keep the
    // splash interval on the 5154/ECD profile even when CGA or MDA is pending.
    wire [1:0] ega_monitor_profile_effective = ega_splash_active
                                              ? 2'b00 : ega_monitor_profile;
    wire ega_display_sel = ega_enabled &
                           (ega_video_active | ega_splash_active | ega_prebios_active);
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
    wire [7:0] ega_crtc_r14_debug;
    wire [7:0] ega_crtc_r15_debug;
    wire [7:0] ega_crtc_r16_debug;
    wire [13:0] ega_crtc_addr;
    wire [15:0] ega_crtc_addr_full;
    wire [4:0] ega_row_addr;
    wire [7:0] ega_char_col;
    wire [6:0] ega_char_row;
    wire [9:0] ega_scanline_addr;
    wire [7:0] ega_h_displayed;
    wire [9:0] ega_v_displayed;
    wire [3:0] ega_hsync_width_crtc;
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
    wire [3:0] ega_attr_pixel_pan;
    wire [5:0] ega_red_compat;
    wire [5:0] ega_green_compat;
    wire [5:0] ega_blue_compat;
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
    wire [3:0] ega_plane_index = ega_splash_active ? ext_splash_pixel_index :
                                 ega_graphics_mode_active ? ega_graphics_plane_index : ega_text_plane_index;
    wire ega_pixel_valid = ega_splash_active ? ext_splash_pixel_valid :
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
    // 40 column text ran one dot late, so the leftmost dot column of every row
    // fell off the left edge and the panning tail fetch put an extra dot on the
    // right. Text sits three dots behind graphics at the full dot clock (11 vs
    // 8); with 4 here it does the same at the halved one (19 vs 16).
    localparam [4:0] EGA_VISIBLE_ADJ_TEXT_DIV2_A = 5'd4;
    localparam [4:0] EGA_VISIBLE_ADJ_TEXT_DIV2_B = 5'd4;
    localparam [4:0] EGA_VISIBLE_ADJ_GFX_1X_A    = 5'd3;
    localparam [4:0] EGA_VISIBLE_ADJ_GFX_1X_B    = 5'd3;
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

    // line_reset is a level for the final character of a line. Qualifying it
    // with the one-cycle CRTC character tick produces one phase-lock pulse on
    // the emitted dot that advances the CRTC to the next line.
    assign ega_dot_line_lock = ega_crtc_fetch_tick & ega_crtc_line_reset;
    wire [1:0] ega_render_mode = !ega_graphics_mode_active ? 2'd0 :
                                  ega_compat_2bpp_mode ? 2'd2 : 2'd1;
    wire ega_display_enable = ega_display_enable_crtc;
    reg [39:0] ega_display_enable_delay = 40'd0;
    wire ega_display_enable_visible = ega_display_enable_delay[ega_visible_delay_a] |
                                      ega_display_enable_delay[ega_visible_delay_b];
    // Pel panning displays the row starting a few dots in, so the pipeline has
    // to keep producing dots for one character past the point where it used to
    // stop - that is the extra character fetch a real EGA makes at the end of a
    // panned line, and it is what 86Box renders as "hdisp + scrollcache".
    wire ega_display_enable_tail = ega_display_enable_delay[ega_visible_delay_a + EGA_PAN_MAX] |
                                   ega_display_enable_delay[ega_visible_delay_b + EGA_PAN_MAX];
    wire ega_display_enable_render = ega_display_enable | ega_display_enable_visible |
                                     ega_display_enable_tail;

    // ------------------------------------------------------------ Pel Panning
    // Attribute controller index 13h. 86Box (vid_ega.c) turns the register into
    // a shift in dots as
    //
    //     scrollcache = (attrregs[0x13] & 0x0F);
    //     if (scrollcache >= 8) scrollcache = 0; else scrollcache++;
    //     if (seqregs[1] & 8)   scrollcache <<= 1;
    //     x_add = (overscan_x >> 1) - scrollcache;
    //
    // and then hands one dot width back at the top of both renderers, in the 8
    // dot character modes only ("compensate for 8dot scroll"). Net of the two,
    // an 8 dot mode shifts left by exactly the register value and a 9 dot mode
    // by the value plus one, with 8-15 meaning no shift - the classic EGA table
    // where 8 is the aligned position in 9 dot text. The doubling for the
    // halved dot clock is what makes a 320 wide mode pan one 320 wide pixel per
    // step rather than half of one.
    wire [4:0] ega_pan_scroll = (ega_attr_pixel_pan >= 4'd8) ? 5'd0
                                                             : ({1'b0, ega_attr_pixel_pan} + 5'd1);
    wire [5:0] ega_pan_scroll_dots = ega_dot_clock_div2_active ? {ega_pan_scroll, 1'b0}
                                                               : {1'b0, ega_pan_scroll};
    wire [5:0] ega_pan_compensate = ega_char_9dot_active ? 6'd0 :
                                    (ega_dot_clock_div2_active ? 6'd2 : 6'd1);
    // The delay that renders that shift, 0 to EGA_PAN_STAGES. Never negative:
    // ega_pan_scroll_dots is at most EGA_PAN_MAX.
    wire [4:0] ega_pan_delay_next = EGA_PAN_MAX + ega_pan_compensate - ega_pan_scroll_dots;

    reg  [4:0] ega_pan_delay = EGA_PAN_MAX;
    reg  [(5*EGA_PAN_STAGES)-1:0] ega_pan_pipe = {(5*EGA_PAN_STAGES){1'b0}};
    reg  [EGA_PAN_MAX-1:0] ega_pan_de_pipe = {EGA_PAN_MAX{1'b0}};
    reg  ega_display_enable_q = 1'b0;

    wire [4:0] ega_pan_sample = {ega_pixel_valid, ega_plane_index};
    wire [4:0] ega_pan_tap = (ega_pan_delay == 5'd0) ? ega_pan_sample
                                                     : ega_pan_pick(ega_pan_pipe, ega_pan_delay - 5'd1);
    wire [3:0] ega_plane_index_panned = ega_pan_tap[3:0];
    wire       ega_pixel_valid_panned = ega_pan_tap[4];
    // The window the attribute controller paints takes the fixed delay, so the
    // dot it shows first is the one generated ega_pan_delay_next dots into the
    // row, which is the shift asked for.
    wire       ega_display_enable_panned = ega_pan_de_pipe[EGA_PAN_MAX-1];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ega_pan_delay <= EGA_PAN_MAX;
            ega_pan_pipe <= {(5*EGA_PAN_STAGES){1'b0}};
            ega_pan_de_pipe <= {EGA_PAN_MAX{1'b0}};
            ega_display_enable_q <= 1'b0;
        end else if (ce_pix) begin
            ega_display_enable_q <= ega_display_enable;
            // One latch per scanline, at the start of the line, the way the
            // attribute controller reloads its panning counter. 86Box only
            // recomputes scrollcache once a frame, which is enough for the
            // scrolling case but would flatten the per scanline waves that were
            // a stock EGA effect, so this follows the hardware rather than the
            // emulator: a write during the active line lands on the next one,
            // never halfway through the one being painted.
            if (ega_display_enable & ~ega_display_enable_q)
                ega_pan_delay <= ega_pan_delay_next;
            ega_pan_pipe <= {ega_pan_pipe[(5*(EGA_PAN_STAGES-1))-1:0], ega_pan_sample};
            ega_pan_de_pipe <= {ega_pan_de_pipe[EGA_PAN_MAX-2:0], ega_display_enable_visible};
        end
    end

    // Delaying the dot stream by EGA_PAN_MAX would otherwise walk the picture
    // that far to the right of HSYNC. Everything the CRTC hands to the scaler
    // and to the analogue output takes the same delay, so the image keeps the
    // horizontal position it had before panning existed. The internal users of
    // these signals - the display activation state machine, the status register
    // - stay on the undelayed copies, which is where they belong.
    reg [EGA_PAN_MAX-1:0] ega_pan_hsync_pipe = {EGA_PAN_MAX{1'b0}};
    reg [EGA_PAN_MAX-1:0] ega_pan_vsync_pipe = {EGA_PAN_MAX{1'b0}};
    reg [EGA_PAN_MAX-1:0] ega_pan_hblank_pipe = {EGA_PAN_MAX{1'b1}};
    reg [EGA_PAN_MAX-1:0] ega_pan_vblank_pipe = {EGA_PAN_MAX{1'b0}};
    reg [EGA_PAN_MAX-1:0] ega_pan_vborder_pipe = {EGA_PAN_MAX{1'b0}};

    wire ega_visible_vblank = ~ega_vertical_display_enable_crtc;
    wire ega_hsync_out = ega_pan_hsync_pipe[EGA_PAN_MAX-1];
    wire ega_vsync_out_l = ega_pan_vsync_pipe[EGA_PAN_MAX-1];
    wire ega_hblank_out = ega_pan_hblank_pipe[EGA_PAN_MAX-1];
    wire ega_vblank_out = ega_pan_vblank_pipe[EGA_PAN_MAX-1];
    wire ega_vborder_out = ega_pan_vborder_pipe[EGA_PAN_MAX-1];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ega_pan_hsync_pipe <= {EGA_PAN_MAX{1'b0}};
            ega_pan_vsync_pipe <= {EGA_PAN_MAX{1'b0}};
            ega_pan_hblank_pipe <= {EGA_PAN_MAX{1'b1}};
            ega_pan_vblank_pipe <= {EGA_PAN_MAX{1'b0}};
            ega_pan_vborder_pipe <= {EGA_PAN_MAX{1'b0}};
        end else if (ce_pix) begin
            ega_pan_hsync_pipe <= {ega_pan_hsync_pipe[EGA_PAN_MAX-2:0], ega_hsync_int};
            ega_pan_vsync_pipe <= {ega_pan_vsync_pipe[EGA_PAN_MAX-2:0], ega_vsync_l};
            ega_pan_hblank_pipe <= {ega_pan_hblank_pipe[EGA_PAN_MAX-2:0], ega_hblank_crtc};
            ega_pan_vblank_pipe <= {ega_pan_vblank_pipe[EGA_PAN_MAX-2:0], ega_visible_vblank};
            ega_pan_vborder_pipe <= {ega_pan_vborder_pipe[EGA_PAN_MAX-2:0], ega_vblank_crtc};
        end
    end

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
    wire       ega_status_read = ega_status_cs & ~bus_ior_l & bus_addr_settled;
    wire       ega_blink_advance = ega_crtc_fetch_tick & ega_vert_blank_active_crtc & ~ega_vblank_crtc_q;
    wire       ega_blink_state = ega_blink_counter[4];


    ref_UM6845R ega_crtc (
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
        .line_reset(ega_crtc_line_reset),
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
        .crtc_r14_debug(ega_crtc_r14_debug),
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
        .V_DISP_REG(ega_v_displayed),
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
    // This CRTC instance treats R1 as the last displayed character, so the
    // reset value is one less than the number of visible characters. 79 gives
    // the 80 eight-dot characters (640 pixels) used by the splash renderer.
    defparam ega_crtc.H_DISP = 8'd79;
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
    // Three scanlines give a 15 kHz TV enough composite-sync energy to lock
    // vertically during the pre-BIOS splash. Software may overwrite R17 later.
    defparam ega_crtc.EGA_RESET_R17 = 8'h03;
    defparam ega_crtc.EGA_RESET_R18 = 8'hC7;
    defparam ega_crtc.EGA_RESET_R19 = 8'h28;

    ref_ega_sequencer ega_seq (
        .clk(clk),
        .reset(reset),
        .ce_pix(ce_pix),
        .ce_pix_early(ce_pix_early),
        .io_addr(ega_io_addr),
        .io_data_in(bus_d),
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

    ref_ega_gfx_ctrl ega_gfx (
        .clk(clk),
        .reset(reset),
        .io_addr(ega_io_addr),
        .io_data_in(bus_d),
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

    ref_ega_pixel ega_pixel_inst (
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

    ref_ega_text ega_text_inst (
        .clk(clk),
        .reset(reset),
        .ce_pix(ce_pix),
        .fetch_tick(ega_crtc_fetch_tick),
        .display_enable((ega_text_mode_active && !ega_splash_active) ? ega_display_enable_render : 1'b0),
        .dot_clock_div2(ega_dot_clock_div2_active),
        .char_9dot(ega_char_9dot_active),
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

    // The splash is drawn by the core, not by this module: the timing it needs
    // (dot enable, visible window, scanline) goes out and the pixel comes in
    // through the ext_splash_* ports, replacing the text/graphics pixel while
    // splashscreen is high. Nothing is fetched from VRAM for it.
    assign ext_splash_ce_pix = ce_pix;
    assign ext_splash_display_enable = ega_display_enable_visible;
    assign ext_splash_scanline = ega_scanline_addr;

    ref_ega_attrib_ctrl ega_attr (
        .clk(clk),
        .reset(reset),
        .ce_pix(ce_pix),
        .io_addr(ega_io_addr),
        .io_data_in(bus_d),
        .io_we(ega_io_we),
        .io_re(ega_io_re),
        .status_re(ega_status_read),
        .plane_index(ega_plane_index_panned),
        .pixel_valid(ega_pixel_valid_panned),
        .display_enable(ega_display_enable_panned),
        .text_mode(~ega_graphics_mode_active),
        .blink_state(ega_blink_state),
        .blink_enable_out(ega_attr_blink_enable),
        .mono_attributes_out(ega_attr_mono_attributes),
        .line_graphics_enable_out(ega_attr_line_graphics_enable),
        .pixel_pan_out(ega_attr_pixel_pan),
        .palette_64_mode(ega_misc_output_reg[7]),
        .color_out(ega_color_raw),
        .display_enable_out(ega_display_enable_raw),
        .video_enable_out(ega_attr_video_enable)
    );

    wire [7:0] ega_status_reg = {2'b00, ega_status_toggle,
                                 ega_status_vretrace_active, 2'b00,
                                 ega_blanking_active};

    wire [5:0] ega_dbl_color;
    wire ega_dbl_hsync;
    wire ega_vsync_sd_l;
    wire ega_vblank_sd;
    wire ega_display_enable_sd;

    // The line doubler needs an output enable at exactly twice the dot rate.
    // 2 x 16.257 MHz cannot be produced from the 28.636 MHz video clock, and
    // the 16.257 MHz modes scan at 18.4 - 21.9 kHz, well above the 15.7 kHz
    // that made doubling useful in the first place, so it is bypassed there.
    // Also permanently forced off: this build targets a 15 kHz CRT TV
    // directly, so the natively-compatible EGA/CGA modes must always pass
    // through undoubled rather than being scandoubled to ~31 kHz.
    wire ega_scandouble_active = 1'b0;

    ref_video_scandoubler #(.PIXEL_WIDTH(6), .H_TOTAL_MAX(912)) ega_scandoubler (
        .clk(clk),
        .ce_pix(ce_pix),
        .ce_2x(ce_pix_2x),
        .scandouble_en(ega_scandouble_active),
        .pixel_in(ega_color_raw),
        .hsync_in(ega_hsync_out),
        .vsync_in(ega_vsync_out_l),
        .vblank_in(ega_vblank_out),
        .display_enable_in(ega_display_enable_raw),
        .pixel_out(ega_dbl_color),
        .hsync_out(ega_dbl_hsync),
        .vsync_out(ega_vsync_sd_l),
        .vblank_out(ega_vblank_sd),
        .display_enable_out(ega_display_enable_sd)
    );

    wire ega_vsync = ~ega_vsync_out_l;
    wire [5:0] ega_video_selected = ega_scandouble_active ? ega_dbl_color : ega_color_raw;
    wire ega_vblank_rise = ~ega_vblank_q & ega_visible_vblank;
    reg ega_vmode_pending;

    ref_ega_vgaport ega_rgb_conv (
        .color(ega_video_selected),
        .palette_64_mode(ega_misc_output_reg[7]),
        .red(ega_red_compat),
        .green(ega_green_compat),
        .blue(ega_blue_compat)
    );

    // On the EGA direct-drive connector, bit 3 is not a blue component when
    // a 5151 is attached: pin 7 becomes Mono Video. Bit 4 is carried on pin 6
    // as the separate intensity signal. Feeding those pins through the normal
    // RGB conversion is what turns mode 7 text into dim blue/cyan. Rebuild the
    // two physical 5151 levels here instead: the six-bit equivalents of
    // classic normal and bright white (two-thirds and full scale).
    wire [5:0] ega_5151_luma;
    wire ega_5151_active = (ega_monitor_profile_effective == 2'd2);

    ref_ega_5151_output ega_5151_monitor (
        .color(ega_video_selected),
        .luma(ega_5151_luma)
    );

    reg [7:0] ega_bus_out_mux;
    // IBM EGA only reads status, display start/cursor and light-pen registers.
    // Sequencer, attributes, graphics and miscellaneous output are write-only.
    wire ega_crtc_readable = (ega_crtc_index_shadow >= 5'h0C && ega_crtc_index_shadow <= 5'h11);
    wire ega_crtc_read_cs = ega_crtc_cs & ~bus_ior_l & bus_a[0] & ega_crtc_readable;
    wire ega_bus_dir_sel = (ega_status_cs & ~bus_ior_l)
                         | ega_crtc_read_cs;

    always @(*) begin
        if (ega_status_cs & ~bus_ior_l)
            ega_bus_out_mux = ega_status_reg;
        else if (ega_crtc_read_cs)
            // No light pen is connected. EGA reads 10h/11h as the light-pen
            // position, not the retrace registers written at those indices.
            ega_bus_out_mux = (ega_crtc_index_shadow >= 5'h10) ?
                              8'h00 : ega_crtc_data_out;
        else
            ega_bus_out_mux = 8'hFF;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ega_vblank_q <= 1'b0;
            ega_cfg_toggle <= 1'b0;
            ega_vmode_toggle_out <= 1'b0;
            ega_vmode_pending <= 1'b0;
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
            bus_a_q <= 15'd0;
            bus_d_q <= 8'd0;
            bus_iow_l_q <= 1'b1;
            bus_ior_l_q <= 1'b1;
            bus_aen_q <= 1'b0;
            ega_text_fetch_phase <= 5'd0;
            ega_display_enable_delay <= 40'd0;
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

                ega_display_enable_delay <= {ega_display_enable_delay[38:0],
                                             ega_display_enable};
            end

            ega_vblank_q <= ega_visible_vblank;
            ega_status_read_q <= ega_status_read;
            ega_vblank_crtc_q <= ega_crtc_fetch_tick ? ega_vert_blank_active_crtc : ega_vblank_crtc_q;
            cpu_mem_write_evt_d <= cpu_mem_write_evt;
            if (ega_misc_write_cs && ega_io_we) begin
                ega_misc_output_reg <= bus_d;
                ega_vmode_pending <= 1'b1;
            end
            if (ega_crtc_cs && ega_io_we && !bus_a[0])
                ega_crtc_index_shadow <= bus_d[4:0];
            else if (ega_crtc_cs && ega_io_we && bus_a[0]) begin
                case (ega_crtc_index_shadow)
                    5'h00, 5'h01, 5'h02: begin
                        ega_crtc_h_timing_seen <= 1'b1;
                        ega_vmode_pending <= 1'b1;
                    end
                    5'h03: ega_vmode_pending <= 1'b1;
                    5'h04, 5'h06, 5'h07, 5'h10, 5'h12: begin
                        ega_crtc_v_timing_seen <= 1'b1;
                        ega_vmode_pending <= 1'b1;
                    end
                    5'h05, 5'h09: ega_vmode_pending <= 1'b1;
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
                ega_display_enable_delay <= 40'd0;
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
                    if (ega_vmode_pending) begin
                        ega_vmode_toggle_out <= ~ega_vmode_toggle_out;
                        ega_vmode_pending <= 1'b0;
                    end
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
    assign ega_fetch_en = ega_display_sel ?
                          (ega_graphics_mode_active & ega_ce_crt_fetch_early & ega_display_enable_render) : 1'b0;
    assign ega_text_fetch_en = ega_display_sel & ega_text_mode_active &
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
    assign ega_display_sel_out = ega_display_sel;

    assign bus_out = ega_bus_out_mux;
    assign bus_dir = ega_enabled ? ega_bus_dir_sel : 1'b0;
    assign ega_red   = ega_prebios_black ? 6'd0 :
                       ega_5151_active    ? ega_5151_luma : ega_red_compat;
    assign ega_green = ega_prebios_black ? 6'd0 :
                       ega_5151_active    ? ega_5151_luma : ega_green_compat;
    assign ega_blue  = ega_prebios_black ? 6'd0 :
                       ega_5151_active    ? ega_5151_luma : ega_blue_compat;
    assign hsync = ega_enabled ? ega_hsync_out : 1'b1;
    assign dbl_hsync = ega_enabled ? ega_dbl_hsync : 1'b1;
    assign hblank = ega_enabled ? (ega_scandouble_active ? ~ega_display_enable_sd : ega_hblank_out) : 1'b1;
    assign vsync = ega_enabled ? (ega_scandouble_active ? ~ega_vsync_sd_l : ega_vsync) : 1'b1;
    assign vblank = ega_enabled ? (ega_scandouble_active ? ega_vblank_sd : ega_vblank_out) : 1'b1;
    assign vblank_border = ega_enabled ? (ega_scandouble_active ? ega_vblank_sd : ega_vborder_out) : 1'b1;
    assign std_hsyncwidth = ega_enabled
                          ? (ega_hsync_width_crtc == (ega_dot_clock_div2_active ? EGA_STD_HSYNC_W_LO : EGA_STD_HSYNC_W_HI))
                          : 1'b0;
    assign de_o = ega_display_sel ? (ega_scandouble_active ? ega_display_enable_sd : ega_display_enable_raw) : 1'b0;

    assign ega_dot_toggle_out = ega_dot_toggle;
    assign ega_dot_clock_sel_out = ega_hifreq_mode;
    assign ega_scandouble_active_out = ega_scandouble_active;

    // How big a picture the CRTC is currently asked for. Characters times the
    // character width, written as a shift and an add so it does not land in a
    // DSP block for the sake of multiplying by eight or nine.
    wire [8:0]  ega_active_chars_now = {1'b0, ega_h_displayed} + 9'd1;
    wire [11:0] ega_active_cells_now = {ega_active_chars_now, 3'b000} +
                                       (ega_char_9dot_active ? {3'd0, ega_active_chars_now}
                                                             : 12'd0);
    // Counted in pixel enables, not in dots, because that is what everything
    // downstream counts. The 40 column modes halve the dot clock but not the
    // enable, so each of their dots arrives as two samples and a 320 dot line
    // is handed over as 640 - which is why the framework has always reported
    // them as 640 wide and been right to.
    //
    // Telling the capture 320 there would have it reserve half the words a
    // line needs, take the first half of every line and discard the rest.
    wire [11:0] ega_active_dots_now = ega_dot_clock_div2_active
                                    ? {ega_active_cells_now[10:0], 1'b0}
                                    : ega_active_cells_now;

    reg         ega_mode350 = 1'b0;
    reg [11:0]  ega_active_dots = 12'd0;
    reg [9:0]   ega_active_lines = 10'd0;

    // Sampled once per frame, at the same vertical blank the rest of the mode
    // change is applied on. A mode set writes the CRTC registers one at a time
    // and the geometry is nonsense in between; anything downstream that
    // switches on this would otherwise do it in the middle of a picture.
    //
    // The test is the geometry itself: more active scanlines than a 15 kHz
    // television can show progressively. No BIOS mode number, no monitor
    // switch, so a program that programs its own 350 line raster is caught
    // the same as the ones the option ROM sets up.
    always @(posedge clk) begin
        if (reset) begin
            ega_mode350      <= 1'b0;
            ega_active_dots  <= 12'd0;
            ega_active_lines <= 10'd0;
        end else if (ega_vblank_rise) begin
            ega_mode350      <= (ega_v_displayed > 10'd240);
            ega_active_dots  <= ega_active_dots_now;
            ega_active_lines <= ega_v_displayed;
        end
    end

    assign ega_mode350_out       = ega_mode350;
    assign ega_active_dots_out   = ega_active_dots;
    assign ega_active_lines_out  = ega_active_lines;
endmodule
