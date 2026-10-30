//============================================================================
//
//  EGA pre-BIOS splash timing regression.
//
//  The splash picture is 320x200 and every source pixel is doubled
//  horizontally.
//  The CRTC must therefore expose exactly 640x200 active pixels. In
//  particular, the EGA CRTC interprets R1 as the last displayed character;
//  seeding R1 with 80 would expose 81 characters, or 648 pixels.
//
//  Run from rtl/video so the splash ROM can be loaded:
//    iverilog -g2012 -o splash_tb TESTBENCH/ega_splash_timing_tb.v \
//      UM6845R.v video_scandoubler.v ega_dot_clock.v ega_gfx_ctrl.v \
//      ega_sequencer.v ega_attrib_ctrl.v ega_pixel.v ega_text.v \
//      ega_splash_renderer.v splash_rom.v ega_vgaport.v ega_top.v
//    vvp splash_tb
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_splash_timing_tb;

    reg clk = 1'b0;
    always #17.462 clk = ~clk;   // 28.636363 MHz video clock

    reg reset = 1'b1;

    wire hblank;
    wire vblank;
    wire vsync;
    wire de_o;

    // F3 vehicle version: ega_top comes from vendor/pc_common and the splash is the
    // core's own: the renderer sits outside ega_top and is driven through the
    // ext_splash_* hooks. Run from the directory with splash_320x200.hex.
    wire [3:0] spl_pix;
    wire       spl_valid, spl_ce, spl_de;
    wire [9:0] spl_scan;
    wire [14:0] spl_rom_addr;
    wire [7:0]  spl_rom_q;
    ega_splash_renderer splash_renderer (
        .clk(clk), .reset(reset), .ce_pix(spl_ce), .enable(1'b1),
        .display_enable(spl_de), .scanline(spl_scan),
        .rom_addr(spl_rom_addr), .rom_q(spl_rom_q),
        .pixel_index(spl_pix), .pixel_valid(spl_valid)
    );
    splash_rom splash_rom (
        .clk(clk), .addr_a(15'd0), .q_a(),
        .addr_b(spl_rom_addr), .q_b(spl_rom_q)
    );

    ega_top dut (
        .clk(clk),
        .reset(reset),
        .bus_a(15'h0000),
        .bus_ior_l(1'b1),
        .bus_iow_l(1'b1),
        .bus_d(8'h00),
        .bus_out(),
        .bus_dir(),
        .bus_aen(1'b0),
        .ega_fetch_addr(),
        .ega_fetch_en(),
        .ega_plane0_data(8'h00),
        .ega_plane1_data(8'h00),
        .ega_plane2_data(8'h00),
        .ega_plane3_data(8'h00),
        .ega_fetch_data_valid(1'b0),
        .ega_text_cell_addr(),
        .ega_text_scanline(),
        .ega_text_tag(),
        .ega_text_fetch_en(),
        .ega_text_char(8'h00),
        .ega_text_attr(8'h00),
        .ega_text_glyph(8'h00),
        .ega_text_data_valid(1'b0),
        .ega_text_tag_in(1'b0),
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
        .hsync(),
        .hblank(hblank),
        .dbl_hsync(),
        .vsync(vsync),
        .vblank(vblank),
        .vblank_border(),
        .std_hsyncwidth(),
        .de_o(de_o),
        .ega_red(),
        .ega_green(),
        .ega_blue(),
        .ega_display_sel_out(),
        .ega_dot_toggle_out(),
        .ega_dot_clock_sel_out(),
        .ega_scandouble_active_out(),
        .ega_vmode_toggle_out(),
        .splashscreen(1'b1),
        .ext_splash_pixel_index(spl_pix),
        .ext_splash_pixel_valid(spl_valid),
        .ext_splash_ce_pix(spl_ce),
        .ext_splash_display_enable(spl_de),
        .ext_splash_scanline(spl_scan),
        .prebios_video(1'b0),
        .thin_font(1'b0),
        .scandouble_en(1'b0),
        .ega_enabled(1'b1),
        .ega_monitor_profile(2'b00),
        .crt_h_offset(4'd0),
        .crt_v_offset(3'd0),
        .vsync_width_osd(3'd0),
        .hsync_width_osd(3'd0)
    );

    wire ce_pix = dut.ce_pix;

    integer errors = 0;
    integer active_width = 0;
    integer active_lines = 0;
    integer frames_checked = 0;
    time vsync_start_time = 0;
    time vsync_duration = 0;
    time vsync_period = 0;
    reg vsync_measured = 1'b0;
    reg active_measured = 1'b0;
    reg armed = 1'b0;
    reg capturing = 1'b0;
    reg de_q = 1'b0;
    reg vblank_q = 1'b1;

    always @(posedge clk) begin
        if (ce_pix) begin
            if (armed && vblank_q && !vblank) begin
                capturing = 1'b1;
                active_width = 0;
                active_lines = 0;
            end

            if (capturing && de_o)
                active_width = active_width + 1;

            if (capturing && de_q && !de_o) begin
                active_lines = active_lines + 1;
                if (active_width != 640) begin
                    $display("FAIL: splash line %0d is %0d pixels wide, expected 640",
                             active_lines, active_width);
                    errors = errors + 1;
                end
                active_width = 0;
            end

            if (capturing && !vblank_q && vblank) begin
                capturing = 1'b0;
                frames_checked = frames_checked + 1;
                if (active_lines != 200) begin
                    $display("FAIL: splash has %0d active lines, expected 200",
                             active_lines);
                    errors = errors + 1;
                end

                active_measured = 1'b1;
            end

            de_q = de_o;
            vblank_q = vblank;
        end
    end

    // Content: every source pixel of the picture appears twice, in order, on
    // each of the 200 lines of a frame.
    reg [7:0] picture [0:31999];
    initial $readmemh("splash_320x200.hex", picture);

    function [3:0] expected;
        input integer line;
        input integer x;
        reg [7:0] b;
        begin
            b = picture[line * 160 + x / 2];
            expected = (x % 2) ? b[3:0] : b[7:4];
        end
    endfunction

    integer pic_line = -1;
    integer pic_dot = 0;
    integer pic_errors = 0;
    integer pic_lines_done = 0;
    reg     spl_valid_q = 1'b0;
    reg     pic_vblank_q = 1'b1;

    always @(posedge clk) begin
        if (spl_ce) begin
            if (!pic_vblank_q && vblank) begin
                if (armed && pic_line >= 0)
                    pic_lines_done = pic_line + 1;
                pic_line = -1;
            end
            if (spl_valid && !spl_valid_q) begin
                pic_line = pic_line + 1;
                pic_dot = 0;
            end
            if (spl_valid && armed && pic_line >= 0 && pic_line < 200) begin
                if (spl_pix !== expected(pic_line, pic_dot / 2)) begin
                    if (pic_errors < 8)
                        $display("FAIL: splash line %0d dot %0d is %h, expected %h",
                                 pic_line, pic_dot, spl_pix, expected(pic_line, pic_dot / 2));
                    pic_errors = pic_errors + 1;
                end
            end
            if (spl_valid)
                pic_dot = pic_dot + 1;
            spl_valid_q = spl_valid;
            pic_vblank_q = vblank;
        end
    end

    initial begin
        repeat (16) @(posedge clk);
        reset = 1'b0;
        // Ignore reset transients and the first frame while the CRTC pipelines
        // fill; measure the following complete visible field.
        repeat (2) @(posedge vblank);
        armed = 1'b1;
    end

    // Check the analogue timing as well as the active area. In particular, a
    // one-line VSYNC has the right frame rate but is too short for some 15 kHz
    // TVs to extract reliably from composite sync.
    initial begin
        wait (armed);
        @(negedge vsync);
        vsync_start_time = $time;
        @(posedge vsync);
        vsync_duration = $time - vsync_start_time;
        vsync_measured = 1'b1;
        @(negedge vsync);
        vsync_period = $time - vsync_start_time;
        wait (active_measured);

        $display("INFO: splash frame period is %0d ns (%0.4f Hz)",
                 vsync_period, 1000000000.0 / vsync_period);
        if (vsync_period < 16800000 || vsync_period > 16830000) begin
            $display("FAIL: splash frame period is outside the 59.5 Hz profile");
            errors = errors + 1;
        end
        if (vsync_duration < 190000 || vsync_duration > 192000) begin
            $display("FAIL: splash VSYNC is %0d ns, expected three scanlines",
                     vsync_duration);
            errors = errors + 1;
        end
        if (pic_errors != 0 || pic_lines_done != 200) begin
            $display("FAIL: %0d dots differ from the picture, %0d picture lines in the frame",
                     pic_errors, pic_lines_done);
            errors = errors + 1;
        end
        if (errors == 0)
            $display("PASS: splash active area is 640x200 and matches the picture (VSYNC %0d ns)",
                     vsync_duration);
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #70000000;
        $display("RESULT: FAIL (timeout, checked %0d frames)", frames_checked);
        $finish;
    end

endmodule
