//============================================================================
//
//  Where each 200 line mode puts its picture relative to HSYNC.
//
//  On a 15 kHz TV the horizontal position of the image is set by the gap
//  between the sync pulse and the first displayed dot. If that gap differs
//  between modes, one CRT H offset setting cannot centre them all - which is
//  the reported symptom: 640x200 graphics and 40 column text sit correctly at
//  H5, while 80 column text at 200 lines runs off the left edge and does not
//  come back even at H15.
//
//  Each mode is programmed from the option ROM's own parameter block (video
//  parameter table at C000:0717), and the gap is counted in dots. The offset is
//  swept so the available range is measured rather than assumed.
//
//  This bench reports; it asserts only that the sweep actually moves the
//  picture and that the three modes agree once offset for, because what the
//  right absolute position is depends on the television.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_hpos_tb;

    reg clk = 1'b0;
    always #17.462 clk = ~clk;

    reg reset = 1'b1;
    reg [14:0] bus_a = 15'h0000;
    reg [7:0]  bus_d = 8'h00;
    reg        bus_ior_l = 1'b1;
    reg        bus_iow_l = 1'b1;
    reg        bus_aen = 1'b0;
    reg        cpu_mem_select = 1'b0;
    reg        cpu_mem_write = 1'b0;
    reg [3:0]  crt_h_offset = 4'd0;
    reg [2:0]  crt_v_offset = 3'd0;

    wire [15:0] fetch_addr;
    wire        fetch_en;
    wire [15:0] text_cell_addr, text_font_addr;
    wire        text_fetch_en;
    reg  [7:0]  plane0=0, plane1=0, plane2=0, plane3=0;
    reg         fetch_valid = 1'b0;
    reg  [7:0]  text_char=0, text_attr=0, text_glyph=0;
    reg         text_valid = 1'b0;
    reg [4:0]   tv_d = 5'd0;
    wire text_tag;  reg [4:0] tg_d = 5'd0;  reg text_tag_back = 1'b0;
    wire hsync, hblank, vsync, vblank, de_o;
    wire [5:0] red, green, blue;

    always @(posedge clk) begin
        fetch_valid <= fetch_en;
        tv_d <= {tv_d[3:0], text_fetch_en}; text_valid  <= tv_d[1];
        tg_d <= {tg_d[3:0], text_tag};  text_tag_back <= tg_d[1];
        plane0 <= 8'hAA; plane1 <= 8'h00; plane2 <= 8'h00; plane3 <= 8'h00;
        text_char <= 8'h41; text_attr <= 8'h07; text_glyph <= 8'hFF;
    end

    ega_top dut (
        .clk(clk), .reset(reset),
        .bus_a(bus_a), .bus_ior_l(bus_ior_l), .bus_iow_l(bus_iow_l), .bus_d(bus_d),
        .bus_out(), .bus_dir(), .bus_aen(bus_aen),
        .ega_fetch_addr(fetch_addr), .ega_fetch_en(fetch_en),
        .ega_plane0_data(plane0), .ega_plane1_data(plane1),
        .ega_plane2_data(plane2), .ega_plane3_data(plane3),
        .ega_fetch_data_valid(fetch_valid),
        .ega_text_cell_addr(text_cell_addr), .ega_text_scanline(), .ega_text_tag(text_tag),
        .ega_text_fetch_en(text_fetch_en),
        .ega_text_char(text_char), .ega_text_attr(text_attr), .ega_text_glyph(text_glyph),
        .ega_text_data_valid(text_valid), .ega_text_tag_in(text_tag_back),
        .vga_framebuffer_addr(), .vga_framebuffer_read_en(),
        .vga_framebuffer_pixel(8'h00), .vga_framebuffer_data_valid(1'b0),
        .cpu_mem_select(cpu_mem_select), .cpu_mem_write(cpu_mem_write),
        .ega_cfg_toggle(), .ega_plane_write_mask_out(), .ega_odd_even_mode_out(),
        .ega_cpu_access_slot_out(), .ega_chain2_write_out(), .ega_chain2_read_out(),
        .ega_extended_memory_out(), .ega_mem_map_sel_out(), .ega_page_select_out(),
        .ega_write_mode_out(), .ega_read_mode_out(), .ega_read_plane_sel_out(),
        .ega_color_compare_out(), .ega_color_dont_care_out(), .ega_bit_mask_out(),
        .ega_set_reset_out(), .ega_enable_set_reset_out(), .ega_rop_select_out(),
        .ega_rotate_count_out(), .ega_blink_counter_out(), .ega_blink_state_out(),
        .hsync(hsync), .hblank(hblank), .dbl_hsync(), .vsync(vsync), .vblank(vblank),
        .vblank_border(), .std_hsyncwidth(), .de_o(de_o),
        .ega_red(red), .ega_green(green), .ega_blue(blue),
        .ega_display_sel_out(), .ega_dot_toggle_out(), .ega_dot_clock_sel_out(),
        .ega_scandouble_active_out(),
        .prebios_video(1'b0), .splashscreen(1'b0), .ext_splash_pixel_index(4'd0), .ext_splash_pixel_valid(1'b0), .thin_font(1'b0), .scandouble_en(1'b0),
        .ega_enabled(1'b1), .ega_monitor_profile(2'b00), .vga_enabled(1'b0),
        .vga_mode13_set(1'b0), .vga_mode13_clear(1'b0), .vga_mode13_active_out(),
        .crt_h_offset(crt_h_offset), .crt_v_offset(crt_v_offset),
        .vsync_width_osd(3'd0), .hsync_width_osd(3'd0)
    );

    initial begin
        #500_000_000;
        $display("[ega_hpos_tb] TIMEOUT waiting for the display");
        $display("[ega_hpos_tb] RESULT: FAIL");
        $finish;
    end

    task io_write(input [14:0] a, input [7:0] d);
        begin
            @(posedge clk); bus_a<=a; bus_d<=d; bus_aen<=1'b0;
            repeat(4) @(posedge clk);
            bus_iow_l<=1'b0; repeat(8) @(posedge clk); bus_iow_l<=1'b1;
            repeat(6) @(posedge clk);
        end
    endtask
    task crtc_write(input [7:0] i, input [7:0] d); begin io_write(15'h03D4,i); io_write(15'h03D5,d); end endtask
    task seq_write (input [7:0] i, input [7:0] d); begin io_write(15'h03C4,i); io_write(15'h03C5,d); end endtask
    task gfx_write (input [7:0] i, input [7:0] d); begin io_write(15'h03CE,i); io_write(15'h03CF,d); end endtask
    task attr_write(input [7:0] i, input [7:0] d);
        begin
            @(posedge clk); bus_a<=15'h03DA; bus_ior_l<=1'b0;
            repeat(8) @(posedge clk); bus_ior_l<=1'b1; repeat(6) @(posedge clk);
            io_write(15'h03C0, i);
            io_write(15'h03C0, d);
            io_write(15'h03C0, 8'h20);
        end
    endtask

    // CRTC 00h..18h straight out of the option ROM's parameter table.
    reg [7:0] tbl [0:2][0:24];
    reg [7:0] seq1 [0:2];
    reg [7:0] seq4 [0:2];
    reg [7:0] attr10 [0:2];
    reg [7:0] gfx5 [0:2];
    reg [7:0] gfx6 [0:2];
    integer i, m, off;

    task load_tables;
        begin
            // 0: 40x25 text (block 1)
            seq1[0]=8'h0B; seq4[0]=8'h03; attr10[0]=8'h08; gfx5[0]=8'h10; gfx6[0]=8'h0E;
            tbl[0][ 0]=8'h37; tbl[0][ 1]=8'h27; tbl[0][ 2]=8'h2D; tbl[0][ 3]=8'h37;
            tbl[0][ 4]=8'h31; tbl[0][ 5]=8'h15; tbl[0][ 6]=8'h04; tbl[0][ 7]=8'h11;
            tbl[0][ 8]=8'h00; tbl[0][ 9]=8'h07; tbl[0][10]=8'h06; tbl[0][11]=8'h07;
            tbl[0][12]=8'h00; tbl[0][13]=8'h00; tbl[0][14]=8'h00; tbl[0][15]=8'h00;
            tbl[0][16]=8'hE1; tbl[0][17]=8'h24; tbl[0][18]=8'hC7; tbl[0][19]=8'h14;
            tbl[0][20]=8'h08; tbl[0][21]=8'hE0; tbl[0][22]=8'hF0; tbl[0][23]=8'hA3;
            tbl[0][24]=8'hFF;

            // 1: 80x25 text (block 3) - the mode that will not centre
            seq1[1]=8'h01; seq4[1]=8'h03; attr10[1]=8'h08; gfx5[1]=8'h10; gfx6[1]=8'h0E;
            tbl[1][ 0]=8'h70; tbl[1][ 1]=8'h4F; tbl[1][ 2]=8'h5C; tbl[1][ 3]=8'h2F;
            tbl[1][ 4]=8'h5F; tbl[1][ 5]=8'h07; tbl[1][ 6]=8'h04; tbl[1][ 7]=8'h11;
            tbl[1][ 8]=8'h00; tbl[1][ 9]=8'h07; tbl[1][10]=8'h06; tbl[1][11]=8'h07;
            tbl[1][12]=8'h00; tbl[1][13]=8'h00; tbl[1][14]=8'h00; tbl[1][15]=8'h00;
            tbl[1][16]=8'hE1; tbl[1][17]=8'h24; tbl[1][18]=8'hC7; tbl[1][19]=8'h28;
            tbl[1][20]=8'h08; tbl[1][21]=8'hE0; tbl[1][22]=8'hF0; tbl[1][23]=8'hA3;
            tbl[1][24]=8'hFF;

            // 2: 640x200 graphics (block 6)
            seq1[2]=8'h01; seq4[2]=8'h06; attr10[2]=8'h01; gfx5[2]=8'h00; gfx6[2]=8'h0D;
            tbl[2][ 0]=8'h70; tbl[2][ 1]=8'h4F; tbl[2][ 2]=8'h59; tbl[2][ 3]=8'h2D;
            tbl[2][ 4]=8'h5E; tbl[2][ 5]=8'h06; tbl[2][ 6]=8'h04; tbl[2][ 7]=8'h11;
            tbl[2][ 8]=8'h00; tbl[2][ 9]=8'h01; tbl[2][10]=8'h00; tbl[2][11]=8'h00;
            tbl[2][12]=8'h00; tbl[2][13]=8'h00; tbl[2][14]=8'h00; tbl[2][15]=8'h00;
            tbl[2][16]=8'hE0; tbl[2][17]=8'h23; tbl[2][18]=8'hC7; tbl[2][19]=8'h28;
            tbl[2][20]=8'h00; tbl[2][21]=8'hDF; tbl[2][22]=8'hEF; tbl[2][23]=8'hC2;
            tbl[2][24]=8'hFF;
        end
    endtask

    task program_mode(input integer mode);
        begin
            io_write(15'h03C2, 8'h23);
            seq_write(8'h01, seq1[mode]);
            seq_write(8'h02, 8'h03);
            seq_write(8'h03, 8'h00);
            seq_write(8'h04, seq4[mode]);
            for (i = 0; i <= 24; i = i + 1) crtc_write(i[7:0], tbl[mode][i]);

            // Horizontal registers 00h-05h stay exactly as the ROM sets them,
            // because they are what is being measured. The vertical ones are
            // cut down: the gap from sync to the first dot is a property of a
            // line, so a short frame measures it as well as a 262 line one and
            // the sweep costs a fraction of the simulated time.
            //
            // Not as short as it could be, though. The vertical sweep further
            // down delays VSYNC by up to eight scanlines, and in a 20 line frame
            // that runs into the next frame's display and every low setting
            // reads the same. 42 lines leaves the delay room to be seen.
            crtc_write(8'h06, 8'd40);   // vertical total
            crtc_write(8'h07, 8'h00);   // no overflow bits
            crtc_write(8'h10, 8'd30);   // vertical retrace start
            crtc_write(8'h11, 8'h24);
            crtc_write(8'h12, 8'd15);   // vertical display end
            crtc_write(8'h15, 8'd16);   // vertical blank start
            crtc_write(8'h16, 8'd35);   // vertical blank end
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
            repeat (3) @(negedge vblank);
        end
    endtask

    // Free-running dot counter reset by the sync pulse, recording where the
    // display starts. Sampling this can never block, unlike waiting on an edge
    // that a mis-programmed mode may never produce.
    integer dot_count = 0;
    integer de_start = -1;
    integer lit_start = -1;
    integer hs_width = -1;
    integer de_seen = 0;
    reg prev_hs = 1'b0;
    reg prev_de = 1'b0;

    // What the television shows is the first lit dot, not the display enable.
    // The pipeline hands the picture over some dots after DE rises and by a
    // different amount in text than in graphics, so DE is the wrong reference
    // for comparing where two modes land.
    wire lit = (red != 6'h00) || (green != 6'h00) || (blue != 6'h00);

    always @(posedge clk) begin
        if (dut.ce_pix) begin
            if (hsync && !prev_hs) dot_count <= 0;
            else                   dot_count <= dot_count + 1;
            prev_hs <= hsync;

            // Trailing edge: how long the pulse itself lasted. A television
            // measures its back porch from here, not from the leading edge,
            // so an over-wide pulse eats the porch and drags the picture left
            // however far the sync edge is moved.
            if (!hsync && prev_hs) hs_width <= dot_count;

            if (de_o && !prev_de) begin
                de_start  <= dot_count;
                lit_start <= lit ? dot_count : -1;
                de_seen   <= de_seen + 1;
            end else if (de_o && lit && lit_start < 0) begin
                lit_start <= dot_count;
            end
            prev_de <= de_o;
        end
    end

    // The vertical equivalent, counted in scanlines. Same argument as the
    // horizontal: where the picture sits is the gap from the sync pulse to the
    // first line of it, and every step of the offset control has to move that
    // gap or the setting is dead.
    // Held for a whole frame rather than reset at each VSYNC, so it can be read
    // at any point instead of racing the counter that produced it.
    integer vline = 0;
    integer v_de_at = -1;
    reg v_armed = 1'b0;
    reg pv_hs = 1'b0, pv_vs = 1'b0, pv_de = 1'b0;

    always @(posedge clk) begin
        if (dut.ce_pix) begin
            pv_hs <= hsync; pv_vs <= vsync; pv_de <= de_o;
            if (vsync && !pv_vs) begin
                vline   <= 0;
                v_armed <= 1'b1;
            end else begin
                if (hsync && !pv_hs) vline <= vline + 1;
                if (de_o && !pv_de && v_armed) begin
                    v_de_at <= vline;
                    v_armed <= 1'b0;
                end
            end
        end
    end

    // Dots between the start of the sync pulse and the first displayed dot.
    // This is what sets where the picture lands on a CRT.
    task measure_gap(output integer n, output integer l);
        integer seen_at_entry;                 // "before" is a SystemVerilog keyword
        begin
            seen_at_entry = de_seen;
            repeat (2) @(negedge vblank);      // let a couple of frames settle
            if (de_seen == seen_at_entry) begin
                n = -1; l = -1;                // nothing was displayed at all
            end else begin
                n = de_start;
                l = lit_start;
            end
        end
    endtask

    integer gap, litgap;
    integer gap_at [0:2][0:3];
    integer lit_at [0:2][0:3];
    integer width_at [0:2];
    integer vpos_at [0:7];
    integer errors = 0;
    reg [8*16-1:0] mode_name [0:2];

    initial begin
        mode_name[0] = "40 col text";
        mode_name[1] = "80 col text";
        mode_name[2] = "640x200 gfx";
        load_tables();

        repeat (20) @(posedge clk); reset <= 1'b0; repeat (20) @(posedge clk);

        $display("  dots from HSYNC to the first displayed dot");
        $display("  mode           H0    H5   H10   H15");
        for (m = 0; m < 3; m = m + 1) begin
            crt_h_offset <= 4'd0;
            program_mode(m);
            for (off = 0; off < 4; off = off + 1) begin
                crt_h_offset <= off[3:0] * 4'd5 > 4'd15 ? 4'd15 : off[3:0] * 4'd5;
                repeat (2) @(negedge vblank);
                measure_gap(gap, litgap);
                gap_at[m][off] = gap;
                lit_at[m][off] = litgap;
            end
            width_at[m] = hs_width;
            $display("  %0s  %4d  %4d  %4d  %4d", mode_name[m],
                     gap_at[m][0], gap_at[m][1], gap_at[m][2], gap_at[m][3]);
        end

        $display("");
        $display("  dots from HSYNC to the first LIT dot");
        $display("  mode           H0    H5   H10   H15   DE to picture");
        for (m = 0; m < 3; m = m + 1)
            $display("  %0s  %4d  %4d  %4d  %4d  %8d", mode_name[m],
                     lit_at[m][0], lit_at[m][1], lit_at[m][2], lit_at[m][3],
                     lit_at[m][0]-gap_at[m][0]);

        $display("");
        $display("  HSYNC pulse width, in dots and microseconds at 14.318 MHz");
        for (m = 0; m < 3; m = m + 1)
            $display("    %0s  %4d dots   %0d.%02d us   (standard is 64 dots / 4.47 us)",
                     mode_name[m], width_at[m],
                     (width_at[m]*100)/1432, ((width_at[m]*10000)/1432) % 100);

        $display("");
        // A television's AFC locks to the middle of the sync pulse, not to
        // either edge. Measured on hardware: after the retrace moved to 04h/05h
        // 80 column text went slightly right while every other mode went left,
        // which only the centre reference predicts - both edges moved left in
        // all three modes. So this is the number that says where the picture
        // actually lands.
        $display("  position as a television sees it: pulse CENTRE to the first LIT dot");
        $display("  mode           H0    H5   H10   H15");
        for (m = 0; m < 3; m = m + 1)
            $display("  %0s  %4d  %4d  %4d  %4d", mode_name[m],
                     lit_at[m][0]-width_at[m]/2, lit_at[m][1]-width_at[m]/2,
                     lit_at[m][2]-width_at[m]/2, lit_at[m][3]-width_at[m]/2);

        $display("");
        $display("  range of the offset control: %0d dots (40 col), %0d (80 col), %0d (gfx)",
                 gap_at[0][0]-gap_at[0][3], gap_at[1][0]-gap_at[1][3], gap_at[2][0]-gap_at[2][3]);
        $display("  80 col text sits %0d dots from 640x200 gfx and %0d from 40 col text, at H5",
                 gap_at[1][1]-gap_at[2][1], gap_at[1][1]-gap_at[0][1]);

        // Vertical sweep, on the last mode programmed. The bench cuts every
        // mode's vertical registers down to the same short frame, so one sweep
        // covers all of them.
        $display("");
        $display("  scanlines from VSYNC to the first displayed line");
        $display("  V0  V1  V2  V3  V4  V5  V6  V7");
        for (off = 0; off < 8; off = off + 1) begin
            crt_v_offset <= off[2:0];
            repeat (3) @(negedge vblank);
            vpos_at[off] = v_de_at;
        end
        $display("  %2d  %2d  %2d  %2d  %2d  %2d  %2d  %2d",
                 vpos_at[0], vpos_at[1], vpos_at[2], vpos_at[3],
                 vpos_at[4], vpos_at[5], vpos_at[6], vpos_at[7]);

        // Every setting has to be its own position. The EGA path used to bias
        // the value by two and saturate, so V5, V6 and V7 were one picture and
        // the control had five useful steps out of eight.
        for (off = 1; off < 8; off = off + 1)
            if (vpos_at[off] == vpos_at[off-1]) begin
                $display("FAIL V%0d and V%0d are both %0d scanlines: the step does nothing",
                         off-1, off, vpos_at[off]);
                errors = errors + 1;
            end

        $display("");
        for (m = 0; m < 3; m = m + 1)
            if (gap_at[m][0] < 0 || gap_at[m][0] == gap_at[m][3]) begin
                $display("FAIL %0s: the offset control did not move the picture", mode_name[m]);
                errors = errors + 1;
            end

        // The retrace comes from CRTC 04h/05h, so every mode should emit the
        // standard 64 dot pulse whatever its character width. Read as an
        // MC6845 sync width off 03h these were 103 to 119 dots instead.
        for (m = 0; m < 3; m = m + 1)
            if (width_at[m] < 60 || width_at[m] > 68) begin
                $display("FAIL %0s: HSYNC is %0d dots, expected 64", mode_name[m], width_at[m]);
                errors = errors + 1;
            end

        // The whole point of placing the pulse a fixed distance ahead of the
        // picture is that every mode then lands in the same place whatever its
        // parameter block asks for, so one CRT H offset centres them all. That
        // is the property to hold: what is left between modes is the rounding
        // of the lead to whole characters.
        for (m = 0; m < 3; m = m + 1)
            if (((lit_at[m][1]-width_at[m]/2) - (lit_at[2][1]-width_at[2]/2) >  16) ||
                ((lit_at[m][1]-width_at[m]/2) - (lit_at[2][1]-width_at[2]/2) < -16)) begin
                $display("FAIL %0s: sits %0d dots from %0s at H5, expected to agree",
                         mode_name[m],
                         (lit_at[m][1]-width_at[m]/2) - (lit_at[2][1]-width_at[2]/2),
                         mode_name[2]);
                errors = errors + 1;
            end

        // Every mode must get the same travel out of the offset control, or the
        // same OSD number means a different shift depending on the mode.
        for (m = 1; m < 3; m = m + 1)
            if ((gap_at[m][3]-gap_at[m][0]) !== (gap_at[0][3]-gap_at[0][0])) begin
                $display("FAIL %0s: offset travel is %0d dots, %0d for %0s",
                         mode_name[m], gap_at[m][3]-gap_at[m][0],
                         gap_at[0][3]-gap_at[0][0], mode_name[0]);
                errors = errors + 1;
            end

        $display("");
        if (errors == 0) $display("[ega_hpos_tb] RESULT: PASS");
        else             $display("[ega_hpos_tb] RESULT: FAIL");
        $finish;
    end

endmodule
