//============================================================================
//
//  EGA Input Status Register 1 - display enable bit
//
//  The IBM EGA option ROM identifies the attached monitor by counting active
//  scanlines through bit 0 of 3DAh. It demands exactly 200 for a 200-line
//  monitor and exactly 350 for a 350-line one; anything else beeps 1 long +
//  3 short and leaves the card in whatever mode the measurement ran in.
//
//  Bit 0 is the inverted display enable, so it has to follow the vertical
//  display end (CRTC R18) and not the vertical blanking window (R21/R22).
//  Those two agree in the ROM's 350-line table, where blanking starts at line
//  350 exactly, but not in the 200-line tables, where the display ends at 200
//  and blanking does not start until 224. Sourcing the bit from blanking
//  therefore passed on 5154/ECD and failed on 5153/CGA.
//
//  Both of the ROM's own tables are replayed here.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_status_display_enable_tb;

    reg clk = 1'b0;
    always #17.462 clk = ~clk;

    reg reset = 1'b1;
    reg [14:0] bus_a = 15'h0000;
    reg [7:0]  bus_d = 8'h00;
    reg        bus_ior_l = 1'b1;
    reg        bus_iow_l = 1'b1;
    reg        bus_aen = 1'b0;

    wire [15:0] fetch_addr;
    wire        fetch_en;
    wire [15:0] text_cell_addr, text_font_addr;
    wire        text_fetch_en;
    reg  [7:0]  plane0=0, plane1=0, plane2=0, plane3=0;
    reg         fetch_valid = 1'b0;
    reg  [7:0]  text_char=0, text_attr=8'h0F, text_glyph=8'hFF;
    reg         text_valid = 1'b0;
    reg [4:0]   tv_d = 5'd0;
    wire text_tag;  reg [4:0] tg_d = 5'd0;  reg text_tag_back = 1'b0;
    wire hsync, hblank, vsync, vblank, de_o;
    wire [5:0] red, green, blue;
    wire [7:0] bus_out;
    wire       bus_dir;

    reg [15:0] fetch_addr_q; reg fetch_en_q; reg text_fetch_en_q;
    always @(posedge clk) begin
        fetch_en_q<=fetch_en; fetch_addr_q<=fetch_addr; fetch_valid<=fetch_en_q;
        plane0<=8'hAA; plane1<=8'h00; plane2<=8'h00; plane3<=8'h00;
        tv_d <= {tv_d[3:0], text_fetch_en}; text_valid <= tv_d[3];
        tg_d <= {tg_d[3:0], text_tag};  text_tag_back <= tg_d[3];
        text_char <= 8'h41; text_attr <= 8'h0F; text_glyph <= 8'hFF;
    end

    ega_top dut (
        .clk(clk), .reset(reset),
        .bus_a(bus_a), .bus_ior_l(bus_ior_l), .bus_iow_l(bus_iow_l), .bus_d(bus_d),
        .bus_out(bus_out), .bus_dir(bus_dir), .bus_aen(bus_aen),
        .ega_fetch_addr(fetch_addr), .ega_fetch_en(fetch_en),
        .ega_plane0_data(plane0), .ega_plane1_data(plane1),
        .ega_plane2_data(plane2), .ega_plane3_data(plane3),
        .ega_fetch_data_valid(fetch_valid),
        .ega_text_cell_addr(text_cell_addr), .ega_text_scanline(), .ega_text_tag(text_tag),
        .ega_text_fetch_en(text_fetch_en),
        .ega_text_char(text_char), .ega_text_attr(text_attr), .ega_text_glyph(text_glyph),
        .ega_text_data_valid(text_valid), .ega_text_tag_in(text_tag_back),
        .cpu_mem_select(1'b0), .cpu_mem_write(1'b0),
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
        .ega_enabled(1'b1), .ega_monitor_profile(2'b00),
        .crt_h_offset(4'd0), .crt_v_offset(3'd0),
        .vsync_width_osd(3'd0), .hsync_width_osd(3'd0)
    );

    task io_write(input [14:0] a, input [7:0] d);
        begin
            @(posedge clk); bus_a<=a; bus_d<=d; bus_aen<=1'b0;
            repeat(4) @(posedge clk);
            bus_iow_l<=1'b0; repeat(8) @(posedge clk); bus_iow_l<=1'b1;
            repeat(6) @(posedge clk);
        end
    endtask
    task crtc_write(input [7:0] i, input [7:0] d); begin io_write(15'h03D4,i); io_write(15'h03D5,d); end endtask
    task seq_write(input [7:0] i, input [7:0] d); begin io_write(15'h03C4,i); io_write(15'h03C5,d); end endtask

    // CRTC 00h..18h straight out of the option ROM's video parameter table at
    // C000:0717 (block 1 = 40x25 200 lines, block 7 = 80x25 350 lines).
    reg [7:0] tbl_200 [0:24];
    reg [7:0] tbl_350 [0:24];
    integer i;

    task load_tables;
        begin
            tbl_200[ 0]=8'h37; tbl_200[ 1]=8'h27; tbl_200[ 2]=8'h2D; tbl_200[ 3]=8'h37;
            tbl_200[ 4]=8'h31; tbl_200[ 5]=8'h15; tbl_200[ 6]=8'h04; tbl_200[ 7]=8'h11;
            tbl_200[ 8]=8'h00; tbl_200[ 9]=8'h07; tbl_200[10]=8'h06; tbl_200[11]=8'h07;
            tbl_200[12]=8'h00; tbl_200[13]=8'h00; tbl_200[14]=8'h00; tbl_200[15]=8'h00;
            tbl_200[16]=8'hE1; tbl_200[17]=8'h24; tbl_200[18]=8'hC7; tbl_200[19]=8'h14;
            tbl_200[20]=8'h08; tbl_200[21]=8'hE0; tbl_200[22]=8'hF0; tbl_200[23]=8'hA3;
            tbl_200[24]=8'hFF;

            tbl_350[ 0]=8'h60; tbl_350[ 1]=8'h4F; tbl_350[ 2]=8'h56; tbl_350[ 3]=8'h3A;
            tbl_350[ 4]=8'h51; tbl_350[ 5]=8'h60; tbl_350[ 6]=8'h70; tbl_350[ 7]=8'h1F;
            tbl_350[ 8]=8'h00; tbl_350[ 9]=8'h0D; tbl_350[10]=8'h0B; tbl_350[11]=8'h0C;
            tbl_350[12]=8'h00; tbl_350[13]=8'h00; tbl_350[14]=8'h00; tbl_350[15]=8'h00;
            tbl_350[16]=8'h5E; tbl_350[17]=8'h2E; tbl_350[18]=8'h5D; tbl_350[19]=8'h28;
            tbl_350[20]=8'h0D; tbl_350[21]=8'h5E; tbl_350[22]=8'h6E; tbl_350[23]=8'hA3;
            tbl_350[24]=8'hFF;
        end
    endtask

    task program_200; begin for (i=0;i<=24;i=i+1) crtc_write(i[7:0], tbl_200[i]); end endtask
    task program_350; begin for (i=0;i<=24;i=i+1) crtc_write(i[7:0], tbl_350[i]); end endtask

    task wait_frame_start;
        begin
            @(posedge clk);
            while (!(dut.ega_crtc_fetch_tick && dut.ega_crtc.frame_new)) @(posedge clk);
        end
    endtask

    // Exactly what the ROM's loop at C000:039E does: one tick per line where
    // the display enable bit goes active and then inactive again.
    task count_active_lines(output integer n);
        integer c;
        reg prev;
        begin
            wait_frame_start();
            c = 0;
            prev = dut.ega_blanking_active;
            @(posedge clk);
            while (!(dut.ega_crtc_fetch_tick && dut.ega_crtc.frame_new)) begin
                if (prev && !dut.ega_blanking_active) c = c + 1;
                prev = dut.ega_blanking_active;
                @(posedge clk);
            end
            n = c;
        end
    endtask

    integer errors = 0;
    integer lines;

    task check(input [255:0] label, input integer expected);
        begin
            count_active_lines(lines);      // settling frame after reprogramming
            count_active_lines(lines);
            if (lines !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: 3DAh bit 0 marks %0d active lines, the option ROM requires %0d",
                         label, lines, expected);
            end else begin
                $display("  %0s: %0d active lines", label, lines);
            end
        end
    endtask

    initial begin
        load_tables();
        repeat (20) @(posedge clk); reset <= 1'b0; repeat (20) @(posedge clk);

        io_write(15'h03C2, 8'h23);
        seq_write(8'h01, 8'h00);
        seq_write(8'h04, 8'h02);

        program_200();
        check("200-line table (5153/CGA)", 200);

        program_350();
        check("350-line table (5154/ECD)", 350);

        if (errors == 0)
            $display("[ega_status_display_enable_tb] RESULT: PASS");
        else
            $display("[ega_status_display_enable_tb] RESULT: FAIL (%0d)", errors);
        $finish;
    end

endmodule
