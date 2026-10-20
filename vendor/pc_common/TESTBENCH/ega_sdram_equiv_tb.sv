// NEEDS: engine
//
// The EGA/VGA core on SDRAM against the same core on BRAM.
//
// Two complete video paths get the same I/O writes and the same memory
// contents:
//
//   ref   the reconciled core as it was before the SDRAM retiming
//         (TESTBENCH/ref_rtl, modules ref_*), BRAM frontends
//   new   ega_top with SDRAM_LEAD_DOTS / SDRAM_PRIV_EXTRA, ega_vram_sdram_frontend,
//         the F2 vram_fetch engines and a behavioural arbiter port with random
//         latency (pc_port_model)
//
// The picture must be the same, later by exactly the retiming: the new outputs
// (sync, blank, display enable, colour) have to equal the reference ones
// LEAD dots earlier on the classic EGA path (sampled on every dot) and EXTRA
// clocks earlier on the private VGA routes (sampled on every clock). The
// bench counts mismatches for a few shifts around the expected one, so a wrong
// constant shows as a clean minimum at another shift instead of just "fail".
//
// What it covers: text 80x25 (8 and 9 dot, 14.318 and 16.257 MHz), text 40x25
// (halved dot clock), 640x200 / 640x350 / 320x200 graphics, MDA mode 7, and
// the three private VGA routes. Memory is filled behind the frontends'
// backs so the two systems start from the same bytes; a few CPU writes and
// reads go through both frontends in vertical blank (no race with the beam,
// so the result has to be the same).
//
`timescale 1ns/1ps
`default_nettype wire

module ega_sdram_equiv_tb #(
    parameter int LEAD   = 16,     // classic path, dots
    parameter int EXTRA  = 16,     // private routes, clocks
    parameter int FRAMES = 1,      // frames compared per scenario
    parameter int SETTLE = 5,      // frames to let go before comparing
    parameter int ONLY   = -1,     // one scenario (0..5 classic, 200..202 private, 100 CPU), -2 the private ones, -1 all
    parameter int CPU_LAT_MAX = 22,
    parameter int VID_LAT_MAX = 22
);

    // ---------------------------------------------------------------- clocks
    // One generating process for both, so their edges coincide exactly (the PLL
    // case): the video clock is a quarter of the sdram clock.
    logic sclk = 1'b0, clk = 1'b0;
    logic clock = 1'b0;                       // chipset clock, asynchronous
    int   ph = 0;
    always begin
        #4.3656;
        sclk = ~sclk;
        ph = ph + 1;
        if (ph % 4 == 0) clk = ~clk;
    end
    always #10.0 clock = ~clock;

    logic reset = 1'b1;
    logic reset_n_sync = 1'b1;

    // ------------------------------------------------------- shared stimulus
    logic [14:0] bus_a = 15'h0000;
    logic [7:0]  bus_d = 8'h00;
    logic        bus_ior_l = 1'b1, bus_iow_l = 1'b1, bus_aen = 1'b0;
    logic [1:0]  monitor_profile = 2'b00;
    logic        vga_enabled = 1'b0;
    logic        cpu_mem_select = 1'b0, cpu_mem_write = 1'b0;

    // ============================================================ REF system
    wire [15:0] r_fetch_addr;  wire r_fetch_en;
    wire [7:0]  r_p0, r_p1, r_p2, r_p3;  wire r_fetch_valid;
    wire [15:0] r_cell_addr, r_font_addr;  wire r_text_en;
    wire [7:0]  r_t_char, r_t_attr, r_t_glyph;  wire r_t_valid;
    wire [15:0] r_fb_addr;  wire r_fb_en;  wire [7:0] r_fb_pixel;  wire r_fb_valid;
    wire r_cfg_toggle;  wire [3:0] r_wmask;  wire r_oe, r_c2w, r_c2r, r_ext, r_page, r_cpu_slot;
    wire [1:0] r_mms, r_wmode, r_rmode, r_rps, r_rop;  wire [7:0] r_cc, r_cdc, r_bm, r_sr;
    wire [3:0] r_esr;  wire [2:0] r_rot;
    wire r_hs, r_vs, r_hb, r_vb, r_de;  wire [5:0] r_red, r_green, r_blue;
    wire r_mode13_active;
    wire [7:0] r_cpu_dout;  wire r_cpu_ready;
    logic cpu_read_r = 1'b0, cpu_write_r = 1'b0;

    ref_ega_top ref_top (
        .clk(clk), .reset(reset),
        .bus_a(bus_a), .bus_ior_l(bus_ior_l), .bus_iow_l(bus_iow_l), .bus_d(bus_d),
        .bus_out(), .bus_dir(), .bus_aen(bus_aen),
        .ega_fetch_addr(r_fetch_addr), .ega_fetch_en(r_fetch_en),
        .ega_plane0_data(r_p0), .ega_plane1_data(r_p1), .ega_plane2_data(r_p2), .ega_plane3_data(r_p3),
        .ega_fetch_data_valid(r_fetch_valid),
        .ega_text_cell_addr(r_cell_addr), .ega_text_font_addr(r_font_addr), .ega_text_fetch_en(r_text_en),
        .ega_text_char(r_t_char), .ega_text_attr(r_t_attr), .ega_text_glyph(r_t_glyph),
        .ega_text_data_valid(r_t_valid),
        .vga_framebuffer_addr(r_fb_addr), .vga_framebuffer_read_en(r_fb_en),
        .vga_framebuffer_pixel(r_fb_pixel), .vga_framebuffer_data_valid(r_fb_valid),
        .cpu_mem_select(cpu_mem_select), .cpu_mem_write(cpu_mem_write),
        .ega_cfg_toggle(r_cfg_toggle), .ega_plane_write_mask_out(r_wmask), .ega_odd_even_mode_out(r_oe),
        .ega_cpu_access_slot_out(r_cpu_slot), .ega_chain2_write_out(r_c2w), .ega_chain2_read_out(r_c2r),
        .ega_extended_memory_out(r_ext), .ega_mem_map_sel_out(r_mms), .ega_page_select_out(r_page),
        .ega_write_mode_out(r_wmode), .ega_read_mode_out(r_rmode), .ega_read_plane_sel_out(r_rps),
        .ega_color_compare_out(r_cc), .ega_color_dont_care_out(r_cdc), .ega_bit_mask_out(r_bm),
        .ega_set_reset_out(r_sr), .ega_enable_set_reset_out(r_esr), .ega_rop_select_out(r_rop),
        .ega_rotate_count_out(r_rot), .ega_blink_counter_out(), .ega_blink_state_out(),
        .hsync(r_hs), .hblank(r_hb), .dbl_hsync(), .vsync(r_vs), .vblank(r_vb), .vblank_border(),
        .std_hsyncwidth(), .de_o(r_de), .ega_red(r_red), .ega_green(r_green), .ega_blue(r_blue),
        .ega_display_sel_out(), .ega_dot_toggle_out(), .ega_dot_clock_sel_out(),
        .ega_scandouble_active_out(), .ega_mode350_out(), .ega_active_dots_out(), .ega_active_lines_out(),
        .ega_vmode_toggle_out(),
        .prebios_video(1'b0), .splashscreen(1'b0), .ext_splash_pixel_index(4'd0), .ext_splash_pixel_valid(1'b0),
        .thin_font(1'b0), .scandouble_en(1'b0),
        .ega_enabled(1'b1), .ega_monitor_profile(monitor_profile), .vga_enabled(vga_enabled),
        .vga_mode13_native(1'b0), .vga_mode13_set(1'b0), .vga_mode13_clear(1'b0),
        .vga_mode13_active_out(r_mode13_active), .vga_unchained256_active_out(),
        .vga_mode13_wide_clock_out(), .vga_planar_memory_active_out(), .vga_mode13_pixel_toggle_out(),
        .crt_h_offset(4'd6), .crt_v_offset(3'd4), .vsync_width_osd(3'd0), .hsync_width_osd(3'd0)
    );

    ref_ega_vram_bram_frontend ref_fe (
        .clock(clk), .reset_cpu(reset), .clk_video(clk), .reset_video(reset),
        .cpu_addr(cpu_addr), .cpu_a16(cpu_a16), .cpu_din(cpu_din),
        .cpu_read(cpu_read_r), .cpu_write(cpu_write_r), .cpu_dout(r_cpu_dout), .cpu_ready(r_cpu_ready),
        .video_addr(r_fetch_addr), .video_read_en(r_fetch_en),
        .video_plane0(r_p0), .video_plane1(r_p1), .video_plane2(r_p2), .video_plane3(r_p3),
        .video_data_valid(r_fetch_valid),
        .text_cell_addr(r_cell_addr), .text_font_addr(r_font_addr), .text_fetch_en(r_text_en),
        .text_char(r_t_char), .text_attr(r_t_attr), .text_glyph(r_t_glyph), .text_data_valid(r_t_valid),
        .cfg_toggle(r_cfg_toggle), .plane_write_mask(r_wmask), .odd_even_mode(r_oe),
        .cpu_access_en(r_cpu_slot), .chain2_write(r_c2w), .chain2_read(r_c2r), .extended_memory(r_ext),
        .mem_map_sel(r_mms), .page_select(r_page), .write_mode(r_wmode), .read_mode(r_rmode),
        .read_plane_sel(r_rps), .color_compare(r_cc), .color_dont_care(r_cdc), .bit_mask(r_bm),
        .set_reset(r_sr), .enable_set_reset(r_esr), .rop_select(r_rop), .rotate_count(r_rot)
    );

    ref_vga_framebuffer ref_fb (
        .clk_cpu(clk), .reset_cpu(reset), .cpu_addr(16'd0), .cpu_din(8'd0), .cpu_read(1'b0),
        .cpu_write(1'b0), .cpu_dout(), .cpu_ready(),
        .clk_video(clk), .video_addr(r_fb_addr), .video_read_en(r_fb_en),
        .video_pixel(r_fb_pixel), .video_data_valid(r_fb_valid)
    );

    // ============================================================ NEW system
    wire [15:0] n_fetch_addr;  wire n_fetch_en;
    wire [7:0]  n_p0, n_p1, n_p2, n_p3;  wire n_fetch_valid;
    wire [15:0] n_cell_addr;  wire [4:0] n_scan;  wire n_tag, n_text_en;
    wire [7:0]  n_t_char, n_t_attr, n_t_glyph;  wire n_t_tag_in, n_t_valid;
    wire [15:0] n_fb_addr;  wire n_fb_en;  wire [7:0] n_fb_pixel;  wire n_fb_valid;
    wire n_cfg_toggle;  wire [3:0] n_wmask;  wire n_oe, n_c2w, n_c2r, n_ext, n_page, n_cpu_slot;
    wire [1:0] n_mms, n_wmode, n_rmode, n_rps, n_rop;  wire [7:0] n_cc, n_cdc, n_bm, n_sr;
    wire [3:0] n_esr;  wire [2:0] n_rot;
    wire [1:0] n_cma, n_cmb;  wire n_ce_pix, n_priv;
    wire n_hs, n_vs, n_hb, n_vb, n_de;  wire [5:0] n_red, n_green, n_blue;
    wire [7:0] n_cpu_dout;  wire n_cpu_ready;
    logic cpu_read_n = 1'b0, cpu_write_n = 1'b0;
    logic [15:0] cpu_addr = 16'd0;  logic cpu_a16 = 1'b0;  logic [7:0] cpu_din = 8'd0;

    ega_top #(.SDRAM_LEAD_DOTS(LEAD), .SDRAM_PRIV_EXTRA(EXTRA)) new_top (
        .clk(clk), .reset(reset),
        .bus_a(bus_a), .bus_ior_l(bus_ior_l), .bus_iow_l(bus_iow_l), .bus_d(bus_d),
        .bus_out(), .bus_dir(), .bus_aen(bus_aen),
        .ega_fetch_addr(n_fetch_addr), .ega_fetch_en(n_fetch_en),
        .ega_plane0_data(n_p0), .ega_plane1_data(n_p1), .ega_plane2_data(n_p2), .ega_plane3_data(n_p3),
        .ega_fetch_data_valid(n_fetch_valid),
        .ega_text_cell_addr(n_cell_addr), .ega_text_scanline(n_scan), .ega_text_tag(n_tag),
        .ega_text_fetch_en(n_text_en),
        .ega_text_char(n_t_char), .ega_text_attr(n_t_attr), .ega_text_glyph(n_t_glyph),
        .ega_text_tag_in(n_t_tag_in), .ega_text_data_valid(n_t_valid),
        .ega_char_map_a_out(n_cma), .ega_char_map_b_out(n_cmb), .ega_ce_pix_out(n_ce_pix),
        .ega_priv_route_out(n_priv),
        .vga_framebuffer_addr(n_fb_addr), .vga_framebuffer_read_en(n_fb_en),
        .vga_framebuffer_pixel(n_fb_pixel), .vga_framebuffer_data_valid(n_fb_valid),
        .cpu_mem_select(cpu_mem_select), .cpu_mem_write(cpu_mem_write),
        .ega_cfg_toggle(n_cfg_toggle), .ega_plane_write_mask_out(n_wmask), .ega_odd_even_mode_out(n_oe),
        .ega_cpu_access_slot_out(n_cpu_slot), .ega_chain2_write_out(n_c2w), .ega_chain2_read_out(n_c2r),
        .ega_extended_memory_out(n_ext), .ega_mem_map_sel_out(n_mms), .ega_page_select_out(n_page),
        .ega_write_mode_out(n_wmode), .ega_read_mode_out(n_rmode), .ega_read_plane_sel_out(n_rps),
        .ega_color_compare_out(n_cc), .ega_color_dont_care_out(n_cdc), .ega_bit_mask_out(n_bm),
        .ega_set_reset_out(n_sr), .ega_enable_set_reset_out(n_esr), .ega_rop_select_out(n_rop),
        .ega_rotate_count_out(n_rot), .ega_blink_counter_out(), .ega_blink_state_out(),
        .hsync(n_hs), .hblank(n_hb), .dbl_hsync(), .vsync(n_vs), .vblank(n_vb), .vblank_border(),
        .std_hsyncwidth(), .de_o(n_de), .ega_red(n_red), .ega_green(n_green), .ega_blue(n_blue),
        .ega_display_sel_out(), .ega_dot_toggle_out(), .ega_dot_clock_sel_out(),
        .ega_scandouble_active_out(), .ega_mode350_out(), .ega_active_dots_out(), .ega_active_lines_out(),
        .ega_vmode_toggle_out(),
        .prebios_video(1'b0), .splashscreen(1'b0), .ext_splash_pixel_index(4'd0), .ext_splash_pixel_valid(1'b0),
        .ext_splash_ce_pix(), .ext_splash_display_enable(), .ext_splash_scanline(),
        .thin_font(1'b0), .scandouble_en(1'b0),
        .ega_enabled(1'b1), .ega_monitor_profile(monitor_profile), .vga_enabled(vga_enabled),
        .vga_mode13_native(1'b0), .vga_mode13_set(1'b0), .vga_mode13_clear(1'b0),
        .vga_mode13_active_out(), .vga_unchained256_active_out(),
        .vga_mode13_wide_clock_out(), .vga_planar_memory_active_out(), .vga_mode13_pixel_toggle_out(),
        .crt_h_offset(4'd6), .crt_v_offset(3'd4), .vsync_width_osd(3'd0), .hsync_width_osd(3'd0)
    );

    // CPU transaction port and VID port of the model
    wire        m_start, m_we, m_busy, m_done;  wire [23:0] m_addr;  wire [1:0] m_len;
    wire [63:0] m_wdata, m_rdata;  wire [7:0] m_wbe;
    wire        vid_req, vid_ack, vid_rvalid, vid_rlast;  wire [23:0] vid_addr;  wire [1:0] vid_len;
    wire [15:0] vid_deadline, vid_rdata;
    wire        sn_valid;  wire [23:0] sn_addr;  wire [1:0] sn_len;  wire [63:0] sn_wdata;  wire [7:0] sn_wbe;
    int         vid_max_lat;
    wire [15:0] n_underruns;

    ega_vram_sdram_frontend #(.LEAD_GFX(LEAD)) new_fe (
        .clock(clock), .reset_cpu(reset),
        .cpu_addr(cpu_addr), .cpu_a16(cpu_a16), .cpu_din(cpu_din),
        .cpu_read(cpu_read_n), .cpu_write(cpu_write_n), .cpu_dout(n_cpu_dout), .cpu_ready(n_cpu_ready),
        .m_start(m_start), .m_we(m_we), .m_addr(m_addr), .m_len(m_len), .m_wdata(m_wdata), .m_wbe(m_wbe),
        .m_busy(m_busy), .m_done(m_done), .m_rdata(m_rdata),
        .clk_video(clk), .reset_video(reset), .dot_tick(n_ce_pix), .priv_route(n_priv),
        .video_addr(n_fetch_addr), .video_read_en(n_fetch_en),
        .video_plane0(n_p0), .video_plane1(n_p1), .video_plane2(n_p2), .video_plane3(n_p3),
        .video_data_valid(n_fetch_valid),
        .text_cell_addr(n_cell_addr), .text_scanline(n_scan), .text_tag(n_tag), .text_fetch_en(n_text_en),
        .char_map_a(n_cma), .char_map_b(n_cmb),
        .text_char(n_t_char), .text_attr(n_t_attr), .text_glyph(n_t_glyph),
        .text_tag_out(n_t_tag_in), .text_data_valid(n_t_valid),
        .fb_addr(n_fb_addr), .fb_read_en(n_fb_en), .fb_pixel(n_fb_pixel), .fb_data_valid(n_fb_valid),
        .cfg_toggle(n_cfg_toggle), .plane_write_mask(n_wmask), .odd_even_mode(n_oe),
        .cpu_access_en(n_cpu_slot), .chain2_write(n_c2w), .chain2_read(n_c2r), .extended_memory(n_ext),
        .mem_map_sel(n_mms), .page_select(n_page), .write_mode(n_wmode), .read_mode(n_rmode),
        .read_plane_sel(n_rps), .color_compare(n_cc), .color_dont_care(n_cdc), .bit_mask(n_bm),
        .set_reset(n_sr), .enable_set_reset(n_esr), .rop_select(n_rop), .rotate_count(n_rot),
        .sdram_clk(sclk), .sdram_reset(reset),
        .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
        .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast), .vid_rdata(vid_rdata),
        .snoop_valid(sn_valid), .snoop_addr(sn_addr), .snoop_len(sn_len),
        .snoop_wdata(sn_wdata), .snoop_wbe(sn_wbe),
        .underrun_count(n_underruns)
    );

    // -DPORT_MODEL=ega_real_stack runs the same bench on the real arbiter, controller
    // and chip model, with a CPU hammering bank 0 (rtl/mem/TESTBENCH, Verilator)
`ifndef PORT_MODEL
 `define PORT_MODEL pc_port_model
`endif
    wire [31:0] stack_chip_errors, stack_underruns;
    `PORT_MODEL #(.CPU_LAT_MAX(CPU_LAT_MAX), .VID_LAT_MAX(VID_LAT_MAX)) pm (
        .reset(reset), .chip_errors(stack_chip_errors), .vid_underruns_out(stack_underruns),
        .clock(clock), .m_start(m_start), .m_we(m_we), .m_addr(m_addr), .m_len(m_len),
        .m_wdata(m_wdata), .m_wbe(m_wbe), .m_busy(m_busy), .m_done(m_done), .m_rdata(m_rdata),
        .sclk(sclk), .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len),
        .vid_deadline(vid_deadline), .vid_ack(vid_ack), .vid_rvalid(vid_rvalid),
        .vid_rlast(vid_rlast), .vid_rdata(vid_rdata),
        .snoop_valid(sn_valid), .snoop_addr(sn_addr), .snoop_len(sn_len),
        .snoop_wdata(sn_wdata), .snoop_wbe(sn_wbe), .vid_max_lat(vid_max_lat)
    );

    // Highest fill of the engines' queues: a sizing figure for MAIN_DEPTH and the
    // glyph engine, not a check (a full queue delays a request, it loses nothing)
    int max_occ_main = 0, max_occ_glyph = 0;
    always @(posedge sclk) if (!reset) begin
        if (int'(new_fe.mf_occ) > max_occ_main)  max_occ_main  <= int'(new_fe.mf_occ);
        if (int'(new_fe.gf_occ) > max_occ_glyph) max_occ_glyph <= int'(new_fe.gf_occ);
    end

    // ============================================================ stimulus
    task automatic io_write(input [14:0] a, input [7:0] d);
        begin
            @(posedge clk); bus_a <= a; bus_d <= d; bus_aen <= 1'b0;
            repeat (4) @(posedge clk);
            bus_iow_l <= 1'b0; repeat (8) @(posedge clk); bus_iow_l <= 1'b1;
            repeat (6) @(posedge clk);
        end
    endtask

    logic mono_io = 1'b0;
    task automatic crtc_write(input [7:0] i, input [7:0] d);
        begin
            io_write(mono_io ? 15'h03B4 : 15'h03D4, i);
            io_write(mono_io ? 15'h03B5 : 15'h03D5, d);
        end
    endtask
    task automatic seq_write (input [7:0] i, input [7:0] d); begin io_write(15'h03C4, i); io_write(15'h03C5, d); end endtask
    task automatic gfx_write (input [7:0] i, input [7:0] d); begin io_write(15'h03CE, i); io_write(15'h03CF, d); end endtask
    task automatic attr_write(input [7:0] i, input [7:0] d);
        begin
            @(posedge clk); bus_a <= mono_io ? 15'h03BA : 15'h03DA; bus_ior_l <= 1'b0;
            repeat (8) @(posedge clk); bus_ior_l <= 1'b1; repeat (6) @(posedge clk);
            io_write(15'h03C0, i);
            io_write(15'h03C0, d);
            io_write(15'h03C0, 8'h20);
        end
    endtask

    localparam int MODES = 6;
    logic [7:0] tbl [0:MODES-1][0:24];
    logic [7:0] misc [0:MODES-1], seq1 [0:MODES-1], seq4 [0:MODES-1], attr10 [0:MODES-1];
    logic [7:0] gfx5 [0:MODES-1], gfx6 [0:MODES-1];
    logic       mono [0:MODES-1];
    logic [1:0] prof [0:MODES-1];
    string      mname [0:MODES-1];
    int i;

    task automatic load_tables;
        begin
            mname[0] = "gfx 640x200 (14.318 MHz)";
            misc[0]=8'h23; seq1[0]=8'h01; seq4[0]=8'h06; attr10[0]=8'h01; gfx5[0]=8'h00; gfx6[0]=8'h0D; mono[0]=1'b0; prof[0]=2'b00;
            {tbl[0][0],tbl[0][1],tbl[0][2],tbl[0][3],tbl[0][4],tbl[0][5],tbl[0][6],tbl[0][7],tbl[0][8],tbl[0][9],tbl[0][10],tbl[0][11],tbl[0][12],
             tbl[0][13],tbl[0][14],tbl[0][15],tbl[0][16],tbl[0][17],tbl[0][18],tbl[0][19],tbl[0][20],tbl[0][21],tbl[0][22],tbl[0][23],tbl[0][24]} =
                {8'h70,8'h4F,8'h59,8'h2D,8'h5E,8'h06,8'h04,8'h11,8'h00,8'h01,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'hE0,8'h23,8'hC7,8'h28,8'h00,8'hDF,8'hEF,8'hC2,8'hFF};

            mname[1] = "text 80x25 8-dot (14.318 MHz)";
            misc[1]=8'h23; seq1[1]=8'h01; seq4[1]=8'h03; attr10[1]=8'h08; gfx5[1]=8'h10; gfx6[1]=8'h0E; mono[1]=1'b0; prof[1]=2'b00;
            {tbl[1][0],tbl[1][1],tbl[1][2],tbl[1][3],tbl[1][4],tbl[1][5],tbl[1][6],tbl[1][7],tbl[1][8],tbl[1][9],tbl[1][10],tbl[1][11],tbl[1][12],
             tbl[1][13],tbl[1][14],tbl[1][15],tbl[1][16],tbl[1][17],tbl[1][18],tbl[1][19],tbl[1][20],tbl[1][21],tbl[1][22],tbl[1][23],tbl[1][24]} =
                {8'h70,8'h4F,8'h5C,8'h2F,8'h5F,8'h07,8'h04,8'h11,8'h00,8'h07,8'h06,8'h07,8'h00,8'h00,8'h00,8'h00,8'hE1,8'h24,8'hC7,8'h28,8'h08,8'hE0,8'hF0,8'hA3,8'hFF};

            mname[2] = "gfx 640x350 (16.257 MHz)";
            misc[2]=8'hA7; seq1[2]=8'h01; seq4[2]=8'h06; attr10[2]=8'h01; gfx5[2]=8'h00; gfx6[2]=8'h05; mono[2]=1'b0; prof[2]=2'b01;
            {tbl[2][0],tbl[2][1],tbl[2][2],tbl[2][3],tbl[2][4],tbl[2][5],tbl[2][6],tbl[2][7],tbl[2][8],tbl[2][9],tbl[2][10],tbl[2][11],tbl[2][12],
             tbl[2][13],tbl[2][14],tbl[2][15],tbl[2][16],tbl[2][17],tbl[2][18],tbl[2][19],tbl[2][20],tbl[2][21],tbl[2][22],tbl[2][23],tbl[2][24]} =
                {8'h5B,8'h4F,8'h53,8'h37,8'h52,8'h00,8'h6C,8'h1F,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h5E,8'h2B,8'h5D,8'h28,8'h0F,8'h5E,8'h0A,8'hA3,8'hFF};

            mname[3] = "MDA mode 7, 9-dot text (16.257 MHz)";
            misc[3]=8'hA6; seq1[3]=8'h00; seq4[3]=8'h03; attr10[3]=8'h0E; gfx5[3]=8'h10; gfx6[3]=8'h0A; mono[3]=1'b1; prof[3]=2'b10;
            {tbl[3][0],tbl[3][1],tbl[3][2],tbl[3][3],tbl[3][4],tbl[3][5],tbl[3][6],tbl[3][7],tbl[3][8],tbl[3][9],tbl[3][10],tbl[3][11],tbl[3][12],
             tbl[3][13],tbl[3][14],tbl[3][15],tbl[3][16],tbl[3][17],tbl[3][18],tbl[3][19],tbl[3][20],tbl[3][21],tbl[3][22],tbl[3][23],tbl[3][24]} =
                {8'h60,8'h4F,8'h56,8'h3A,8'h51,8'h60,8'h70,8'h1F,8'h00,8'h0D,8'h0B,8'h0C,8'h00,8'h00,8'h00,8'h00,8'h5E,8'h2B,8'h5D,8'h28,8'h0F,8'h5E,8'h0A,8'hA3,8'hFF};

            mname[4] = "text 40x25 350 lines (halved 16.257 MHz)";
            misc[4]=8'hA7; seq1[4]=8'h0B; seq4[4]=8'h03; attr10[4]=8'h08; gfx5[4]=8'h10; gfx6[4]=8'h0E; mono[4]=1'b0; prof[4]=2'b00;
            {tbl[4][0],tbl[4][1],tbl[4][2],tbl[4][3],tbl[4][4],tbl[4][5],tbl[4][6],tbl[4][7],tbl[4][8],tbl[4][9],tbl[4][10],tbl[4][11],tbl[4][12],
             tbl[4][13],tbl[4][14],tbl[4][15],tbl[4][16],tbl[4][17],tbl[4][18],tbl[4][19],tbl[4][20],tbl[4][21],tbl[4][22],tbl[4][23],tbl[4][24]} =
                {8'h2D,8'h27,8'h2B,8'h2D,8'h28,8'h6D,8'h6C,8'h1F,8'h00,8'h0D,8'h06,8'h07,8'h00,8'h00,8'h00,8'h00,8'h5E,8'h2B,8'h5D,8'h14,8'h0F,8'h5E,8'h0A,8'hA3,8'hFF};

            // 320x200x16 at the halved 14.318 MHz clock: the 640x200 table with
            // the horizontal totals halved
            mname[5] = "gfx 320x200 (halved 14.318 MHz)";
            misc[5]=8'h23; seq1[5]=8'h09; seq4[5]=8'h06; attr10[5]=8'h01; gfx5[5]=8'h00; gfx6[5]=8'h05; mono[5]=1'b0; prof[5]=2'b00;
            {tbl[5][0],tbl[5][1],tbl[5][2],tbl[5][3],tbl[5][4],tbl[5][5],tbl[5][6],tbl[5][7],tbl[5][8],tbl[5][9],tbl[5][10],tbl[5][11],tbl[5][12],
             tbl[5][13],tbl[5][14],tbl[5][15],tbl[5][16],tbl[5][17],tbl[5][18],tbl[5][19],tbl[5][20],tbl[5][21],tbl[5][22],tbl[5][23],tbl[5][24]} =
                {8'h38,8'h27,8'h2D,8'h2D,8'h2F,8'h06,8'h04,8'h11,8'h00,8'h01,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'hE0,8'h23,8'hC7,8'h14,8'h00,8'hDF,8'hEF,8'hC2,8'hFF};
        end
    endtask

    task automatic program_mode(input int mode);
        begin
            mono_io = mono[mode];
            monitor_profile <= prof[mode];
            io_write(15'h03C2, misc[mode]);
            seq_write(8'h01, seq1[mode]);
            seq_write(8'h02, 8'h03);
            seq_write(8'h03, 8'h00);
            seq_write(8'h04, seq4[mode]);
            for (i = 0; i <= 24; i = i + 1) crtc_write(i[7:0], tbl[mode][i]);
            for (i = 0; i <= 15; i = i + 1) attr_write(i[7:0], i[7:0]);
            attr_write(8'h10, attr10[mode]);
            attr_write(8'h11, 8'h00);
            attr_write(8'h12, 8'h0F);
            attr_write(8'h13, 8'h00);
            gfx_write(8'h05, gfx5[mode]);
            gfx_write(8'h06, gfx6[mode]);
            gfx_write(8'h08, 8'hFF);
            cpu_mem_select <= 1'b1; cpu_mem_write <= 1'b1;
            repeat (4) @(posedge clk);
            cpu_mem_select <= 1'b0; cpu_mem_write <= 1'b0;
        end
    endtask

    // ------------------------------------------------ memory contents, both
    function automatic logic [7:0] hashb(input int p, input int a, input int seed);
        logic [31:0] h;
        begin
            h = 32'(a) * 32'd2654435761 ^ 32'(p) * 32'd40503 ^ 32'(seed) * 32'd97;
            h = h ^ (h >> 15);
            h = h * 32'd2246822519;
            hashb = h[23:16];
        end
    endfunction

    localparam int PLANE_REL = 0;            // word 0 of the array is PLANE_BASE
    localparam int FB_REL    = 24'h20000;    // VGA13_BASE - PLANE_BASE

    logic [7:0] fb_lo, prev_fb;
    task automatic fill_memory(input int seed, input int density);
        begin
            for (int a = 0; a < 65536; a++) begin
                logic [7:0] b0, b1, b2, b3;
                b0 = hashb(0, a, seed);  b1 = hashb(1, a, seed);
                b2 = hashb(2, a, seed);  b3 = hashb(3, a, seed);
                // keep some structure: a share of the planes are zero
                if (density < 4 && (a % 7) == 0) begin b0 = 0; b1 = 0; end
                ref_fe.u_ega_vram.plane0[a] = b0;  ref_fe.u_ega_vram.plane1[a] = b1;
                ref_fe.u_ega_vram.plane2[a] = b2;  ref_fe.u_ega_vram.plane3[a] = b3;
                pm.poke(PLANE_REL + 2*a,     {b1, b0});
                pm.poke(PLANE_REL + 2*a + 1, {b3, b2});
            end
            for (int a = 0; a < 65536; a++) begin
                logic [7:0] p;
                p = hashb(7, a, seed) & ((a % 5 == 0) ? 8'h0F : 8'hFF);
                ref_fb.mem[a] = p;
                fb_lo = p;
                if (a % 2 == 1) pm.poke(FB_REL + a/2, {p, prev_fb});
                prev_fb = p;
            end
        end
    endtask

    // --------------------------------------------------------- the CPU path
    // video clocks (28.636 MHz) from the CPU strobe to cpu_ready of the new frontend
    int nrdy, rd_ready_max = 0, wr_ready_max = 0, rd_ready_n = 0, wr_ready_n = 0;
    longint rd_ready_sum = 0, wr_ready_sum = 0;
    task automatic cpu_access(input logic wr, input logic a16, input logic [15:0] a, input logic [7:0] d,
                              output logic [7:0] rd_r, output logic [7:0] rd_n);
        int t;
        begin
            @(posedge clk);
            cpu_addr <= a; cpu_a16 <= a16; cpu_din <= d;
            cpu_read_r <= ~wr;  cpu_write_r <= wr;
            cpu_read_n <= ~wr;  cpu_write_n <= wr;
            t = 0;  nrdy = -1;
            while (!(r_cpu_ready && n_cpu_ready) && t < 100000) begin
                @(posedge clk); t++;
                if (n_cpu_ready && nrdy < 0) nrdy = t;
            end
            if (nrdy < 0) nrdy = t;
            if (wr) begin if (nrdy > wr_ready_max) wr_ready_max = nrdy; wr_ready_sum += nrdy; wr_ready_n++; end
            else    begin if (nrdy > rd_ready_max) rd_ready_max = nrdy; rd_ready_sum += nrdy; rd_ready_n++; end
            rd_r = r_cpu_dout;  rd_n = n_cpu_dout;
            @(posedge clk);
            cpu_read_r <= 1'b0;  cpu_write_r <= 1'b0;
            cpu_read_n <= 1'b0;  cpu_write_n <= 1'b0;
            repeat (4) @(posedge clk);
            if (t >= 100000) $display("FAIL CPU access timed out");
        end
    endtask

    int cpu_errors = 0;
    task automatic cpu_test;
        logic [7:0] r, n;
        begin
            // planar write mode 0 of a pattern, then reads of every plane
            gfx_write(8'h05, 8'h00);           // write mode 0, read mode 0
            gfx_write(8'h08, 8'hFF);           // bit mask
            gfx_write(8'h01, 8'h00);           // no set/reset
            gfx_write(8'h03, 8'h00);           // rotate 0, replace
            seq_write(8'h02, 8'h0F);           // all planes
            for (int k = 0; k < 24; k++) begin
                cpu_access(1'b1, 1'b0, 16'h0100 + k, 8'(k * 37 + 5), r, n);
            end
            for (int pl = 0; pl < 4; pl++) begin
                gfx_write(8'h04, 8'(pl));
                for (int k = 0; k < 24; k++) begin
                    cpu_access(1'b0, 1'b0, 16'h0100 + k, 8'h00, r, n);
                    if (r !== n) begin
                        cpu_errors++;
                        if (cpu_errors < 10) $display("FAIL CPU read plane %0d addr %0d: ref %h new %h", pl, k, r, n);
                    end
                end
            end
            // write mode 2 with a bit mask, and read mode 1 compare
            gfx_write(8'h05, 8'h02);
            gfx_write(8'h08, 8'h3C);
            for (int k = 0; k < 8; k++) cpu_access(1'b1, 1'b0, 16'h0200 + k, 8'(k), r, n);
            gfx_write(8'h05, 8'h08);           // read mode 1
            gfx_write(8'h02, 8'h05);           // colour compare
            gfx_write(8'h07, 8'h0F);
            for (int k = 0; k < 8; k++) begin
                cpu_access(1'b0, 1'b0, 16'h0200 + k, 8'h00, r, n);
                if (r !== n) begin
                    cpu_errors++;
                    if (cpu_errors < 10) $display("FAIL CPU read mode 1 addr %0d: ref %h new %h", k, r, n);
                end
            end
            gfx_write(8'h05, 8'h00);
            gfx_write(8'h08, 8'hFF);
        end
    endtask

    // ------------------------------------------------------- the comparison
    // History of the reference samples, one entry per dot (classic) or per
    // clock (private), compared with the new sample at several shifts.
    localparam int NSH = 7;
    localparam int HIST = 64;
    logic [22:0] rh_dot [0:HIST-1];
    logic [22:0] rh_clk [0:HIST-1];
    int  hd_ptr = 0, hc_ptr = 0;
    longint mism_dot [0:NSH-1];
    longint mism_clk [0:NSH-1];
    longint cmp_dots = 0, cmp_clks = 0;
    logic   cmp_dot_en = 1'b0, cmp_clk_en = 1'b0;
    int     first_shown = 0;

    longint nz_pixels = 0, de_pixels = 0, distinct = 0;
    logic [17:0] last_rgb = 18'd0;
    wire [22:0] r_sample = {r_hs, r_vs, r_hb, r_vb, r_de, r_red, r_green, r_blue};
    wire [22:0] n_sample = {n_hs, n_vs, n_hb, n_vb, n_de, n_red, n_green, n_blue};
    wire        ref_ce = ref_top.ce_pix;

    always @(posedge clk) if (!reset) begin
        // per clock
        if (cmp_clk_en) begin
            cmp_clks <= cmp_clks + 1;
            if (r_de) begin
                de_pixels <= de_pixels + 1;
                if (|{r_red, r_green, r_blue}) nz_pixels <= nz_pixels + 1;
                if ({r_red, r_green, r_blue} != last_rgb) distinct <= distinct + 1;
                last_rgb <= {r_red, r_green, r_blue};
            end
            for (int s = 0; s < NSH; s++) begin
                int sh;  sh = EXTRA - 3 + s;
                if (n_sample !== rh_clk[(hc_ptr - sh + HIST) % HIST]) mism_clk[s] <= mism_clk[s] + 1;
            end
        end
        rh_clk[hc_ptr % HIST] <= r_sample;
        hc_ptr <= (hc_ptr + 1) % HIST;

        // per dot
        if (ref_ce) begin
            if (cmp_dot_en && r_de) begin
                de_pixels <= de_pixels + 1;
                if (|{r_red, r_green, r_blue}) nz_pixels <= nz_pixels + 1;
                if ({r_red, r_green, r_blue} != last_rgb) distinct <= distinct + 1;
                last_rgb <= {r_red, r_green, r_blue};
            end
            if (n_ce_pix !== 1'b1) begin
                if (first_shown < 5) $display("FAIL ce_pix differs between ref and new");
                first_shown++;
            end
            if (cmp_dot_en) begin
                cmp_dots <= cmp_dots + 1;
                for (int s = 0; s < NSH; s++) begin
                    int sh;  sh = LEAD - 3 + s;
                    if (n_sample !== rh_dot[(hd_ptr - sh + HIST) % HIST]) begin
                        mism_dot[s] <= mism_dot[s] + 1;
                        if (s == 3 && first_shown < 8) begin
                            $display("  mismatch at dot %0d (shift %0d): ref-delayed %h new %h  t=%0t",
                                     cmp_dots, sh, rh_dot[(hd_ptr - sh + HIST) % HIST], n_sample, $time);
                            first_shown++;
                        end
                    end
                end
            end
            rh_dot[hd_ptr % HIST] <= r_sample;
            hd_ptr <= (hd_ptr + 1) % HIST;
        end
    end

    // vsync edges of the reference mark frames
    int  frames_seen = 0;
    logic r_vs_q = 1'b0;
    always @(posedge clk) begin
        r_vs_q <= r_vs;
        if (r_vs && !r_vs_q) frames_seen <= frames_seen + 1;
    end

    task automatic wait_frames(input int n);
        int target;
        begin
            target = frames_seen + n;
            while (frames_seen < target) @(posedge clk);
        end
    endtask

    int total_fail = 0;
    task automatic compare_window(input string what, input logic dot_mode, input int nframes);
        longint base_m [0:NSH-1];
        longint nn;
        int expect_shift;
        begin
            for (int s = 0; s < NSH; s++) begin mism_dot[s] = 0; mism_clk[s] = 0; end
            cmp_dots = 0; cmp_clks = 0; first_shown = 0; nz_pixels = 0; de_pixels = 0; distinct = 0;
            repeat (100) @(posedge clk);
            cmp_dot_en = dot_mode;
            cmp_clk_en = ~dot_mode;
            wait_frames(nframes);
            cmp_dot_en = 1'b0; cmp_clk_en = 1'b0;
            @(posedge clk);
            nn = dot_mode ? cmp_dots : cmp_clks;
            $write("  %-44s %0d %s compared; mismatches by shift ", what, nn, dot_mode ? "dots" : "clks");
            for (int s = 0; s < NSH; s++)
                $write(" [%0d]=%0d", (dot_mode ? LEAD : EXTRA) - 3 + s, dot_mode ? mism_dot[s] : mism_clk[s]);
            $write("\n");
            $display("      picture: %0d active %s, %0d not black, %0d colour changes",
                     de_pixels, dot_mode ? "dots" : "clocks", nz_pixels, distinct);
            if ((dot_mode ? mism_dot[3] : mism_clk[3]) != 0) begin
                total_fail++;
                $display("FAIL %s: %0d mismatches at the expected shift", what,
                         dot_mode ? mism_dot[3] : mism_clk[3]);
            end
        end
    endtask

    // ------------------------------------------------------------ the run
    task automatic run_classic(input int mode, input int seed);
        begin
            fill_memory(seed, mode % 3);
            program_mode(mode);
            wait_frames(SETTLE);
            compare_window(mname[mode], 1'b1, FRAMES);
        end
    endtask

    // The private VGA routes: their raster is not driven by the CRTC and asks
    // for data on every clock, so they are compared clock by clock.
    task automatic run_private(input int kind, input int seed);
        string nm;
        begin
            vga_enabled = 1'b1;
            fill_memory(seed, 5);
            program_mode(5);
            case (kind)
                0: begin
                    nm = "VGA 13h packed (private raster)";
                    io_write(15'h03CD, 8'h13);
                end
                1: begin
                    nm = "VGA Mode X unchained 320x200";
                    seq_write(8'h04, 8'h06);          // chain 4 off
                    gfx_write(8'h05, 8'h40);          // 256-colour shift
                    gfx_write(8'h06, 8'h05);
                    crtc_write(8'h01, 8'h4F);
                    crtc_write(8'h09, 8'h40);
                    crtc_write(8'h07, 8'h11);
                    crtc_write(8'h18, 8'hFF);         // line compare 3FFh: no split
                    crtc_write(8'h0C, 8'h00);
                    crtc_write(8'h0D, 8'h00);
                    crtc_write(8'h13, 8'h28);
                    io_write(15'h03CD, 8'h13);
                end
                default: begin
                    nm = "VGA planar 16 colours 0Dh (private raster)";
                    crtc_write(8'h0C, 8'h00);
                    crtc_write(8'h0D, 8'h00);
                    crtc_write(8'h13, 8'h14);
                    io_write(15'h03CD, 8'h0D);
                end
            endcase
            wait_frames(3);
            compare_window(nm, 1'b0, FRAMES);
            io_write(15'h03CD, 8'h00);
            vga_enabled = 1'b0;
            wait_frames(2);
        end
    endtask

    initial begin
        for (int s = 0; s < NSH; s++) begin mism_dot[s] = 0; mism_clk[s] = 0; end
        load_tables();
        repeat (40) @(posedge clk);
        reset = 1'b0;
        repeat (40) @(posedge clk);

        for (int m = 0; m < MODES; m++)
            if (ONLY == -1 || ONLY == m) run_classic(m, 11 + m);

        for (int k = 0; k < 3; k++)
            if (ONLY == -1 || ONLY == -2 || ONLY == 200 + k) run_private(k, 31 + k);

        // CPU path (vertical blank is not needed: the picture is not compared)
        if (ONLY == -1 || ONLY == 100) begin
            cpu_test();
            $display("  CPU access through both frontends: %0d mismatches", cpu_errors);
            $display("  cpu_ready of the SDRAM frontend, in 28.636 MHz clocks after the strobe: reads %0d on average, %0d at most; writes %0d on average, %0d at most (the BRAM one: 2)",
                     rd_ready_n ? int'(rd_ready_sum / rd_ready_n) : 0, rd_ready_max,
                     wr_ready_n ? int'(wr_ready_sum / wr_ready_n) : 0, wr_ready_max);
            if (cpu_errors != 0) total_fail++;
        end

        $display("video underruns of the new path: %0d, longest VID read %0d sdram clocks",
                 n_underruns, vid_max_lat);
        $display("engine queues: highest fill main %0d, glyph %0d", max_occ_main, max_occ_glyph);
        if (n_underruns != 0) total_fail++;
        if (stack_chip_errors != 0) begin
            total_fail++;
            $display("FAIL the memory model reports %0d errors", stack_chip_errors);
        end
        if (total_fail == 0) $display("RESULT: PASS");
        else                 $display("RESULT: FAIL (%0d)", total_fail);
        $finish;
    end

    initial begin
        #4_000_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
