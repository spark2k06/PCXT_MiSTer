`timescale 1ns/1ps

// Replays the register writes of VGATSR's INT 10h AX=0012h/0013h handlers and
// of Pinball Fantasies (INTRO.PRG and TABLE1.PRG, see
// docs/vga-pinball-fantasies.md) and checks the route ega_top selects.
module vga_pinball_fantasies_route_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg reset = 1'b1;
    reg [14:0] bus_a = 15'd0;
    reg [7:0] bus_d = 8'd0;
    reg bus_iow_l = 1'b1;
    wire private_active;
    wire unchained_active;
    wire planar_memory_active;
    integer errors = 0;
    integer i;

    ega_top dut (
        .clk(clk), .reset(reset),
        .bus_a(bus_a), .bus_d(bus_d),
        .bus_ior_l(1'b1), .bus_iow_l(bus_iow_l), .bus_aen(1'b0),
        .ega_plane0_data(8'd0), .ega_plane1_data(8'd0),
        .ega_plane2_data(8'd0), .ega_plane3_data(8'd0),
        .ega_fetch_data_valid(1'b1),
        .ega_text_char(8'd0), .ega_text_attr(8'd0),
        .ega_text_glyph(8'd0), .ega_text_data_valid(1'b0), .ega_text_tag_in(1'b0),
        .vga_framebuffer_pixel(8'd0), .vga_framebuffer_data_valid(1'b0),
        .cpu_mem_select(1'b0), .cpu_mem_write(1'b0),
        .splashscreen(1'b0), .ext_splash_pixel_index(4'd0), .ext_splash_pixel_valid(1'b0), .prebios_video(1'b0),
        .thin_font(1'b0), .scandouble_en(1'b0),
        .ega_enabled(1'b1), .ega_monitor_profile(2'd0),
        .vga_enabled(1'b1), .vga_mode13_native(1'b0),
        .vga_mode13_set(1'b0), .vga_mode13_clear(1'b0),
        .crt_h_offset(4'd0), .crt_v_offset(3'd0),
        .vsync_width_osd(3'd0), .hsync_width_osd(3'd0),
        .vga_mode13_active_out(private_active),
        .vga_unchained256_active_out(unchained_active),
        .vga_planar_memory_active_out(planar_memory_active)
    );

    task io_write;
        input [14:0] port;
        input [7:0] value;
        begin
            @(negedge clk);
            bus_a = port; bus_d = value;
            repeat (4) @(negedge clk);
            bus_iow_l = 1'b0;
            repeat (8) @(negedge clk);
            bus_iow_l = 1'b1;
            repeat (6) @(negedge clk);
        end
    endtask

    task indexed_write;
        input [14:0] port;
        input [7:0] index;
        input [7:0] value;
        begin
            io_write(port, index);
            io_write(port + 15'd1, value);
        end
    endtask

    // planar640, unchained, private, planar memory
    task check_route;
        input expected_640;
        input expected_unchained;
        input [8*64-1:0] label;
        begin
            #1;
            if (dut.vga_planar640_active !== expected_640 ||
                unchained_active !== expected_unchained ||
                private_active !== (expected_640 | expected_unchained) ||
                planar_memory_active !== (expected_640 | expected_unchained) ||
                (expected_640 && dut.vga_256color_active !== 1'b0)) begin
                errors = errors + 1;
                $display("FAIL %0s: 640=%b unchained=%b private=%b planar=%b 256=%b",
                         label, dut.vga_planar640_active, unchained_active,
                         private_active, planar_memory_active,
                         dut.vga_256color_active);
            end
        end
    endtask

    task check_profile;
        input [2:0] expected;
        input [8*64-1:0] label;
        begin
            if (dut.vga_unchained_profile !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: profile=%0d expected=%0d", label,
                         dut.vga_unchained_profile, expected);
            end
        end
    endtask

    reg [7:0] mode12_crtc [0:24];
    reg [7:0] mode13_crtc [0:24];
    initial begin
        {mode12_crtc[0], mode12_crtc[1], mode12_crtc[2], mode12_crtc[3],
         mode12_crtc[4], mode12_crtc[5], mode12_crtc[6], mode12_crtc[7],
         mode12_crtc[8], mode12_crtc[9], mode12_crtc[10], mode12_crtc[11],
         mode12_crtc[12], mode12_crtc[13], mode12_crtc[14], mode12_crtc[15],
         mode12_crtc[16], mode12_crtc[17], mode12_crtc[18], mode12_crtc[19],
         mode12_crtc[20], mode12_crtc[21], mode12_crtc[22], mode12_crtc[23],
         mode12_crtc[24]} =
            {8'h5F, 8'h4F, 8'h50, 8'h82, 8'h54, 8'h80, 8'h0B, 8'h3E,
             8'h00, 8'h40, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
             8'hEA, 8'h8C, 8'hDF, 8'h28, 8'h00, 8'hE7, 8'h04, 8'hE3,
             8'hFF};
    end

    // VGATSR .set_mode12 after the EGA BIOS mode 0Dh call.
    task tsr_mode12;
        begin
            io_write(15'h03C2, 8'hE3);
            indexed_write(15'h03C4, 8'h01, 8'h01);
            indexed_write(15'h03C4, 8'h02, 8'h0F);
            indexed_write(15'h03C4, 8'h04, 8'h06);
            indexed_write(15'h03CE, 8'h05, 8'h00);
            indexed_write(15'h03CE, 8'h06, 8'h05);
            indexed_write(15'h03D4, 8'h11, 8'h0E);
            for (i = 0; i < 25; i = i + 1)
                if (i != 17) indexed_write(15'h03D4, i[7:0], mode12_crtc[i]);
            indexed_write(15'h03D4, 8'h11, 8'h8C);
            io_write(15'h03CD, 8'h12);
        end
    endtask

    // VGATSR .set_mode13 register baseline.
    task tsr_mode13;
        begin
            io_write(15'h03C2, 8'h63);
            indexed_write(15'h03C4, 8'h01, 8'h01);
            indexed_write(15'h03C4, 8'h02, 8'h0F);
            indexed_write(15'h03C4, 8'h04, 8'h0E);
            indexed_write(15'h03CE, 8'h05, 8'h40);
            indexed_write(15'h03CE, 8'h06, 8'h05);
            indexed_write(15'h03D4, 8'h11, 8'h0E);
            indexed_write(15'h03D4, 8'h01, 8'h4F);
            indexed_write(15'h03D4, 8'h06, 8'hBF);
            indexed_write(15'h03D4, 8'h07, 8'h1F);
            indexed_write(15'h03D4, 8'h09, 8'h41);
            indexed_write(15'h03D4, 8'h12, 8'h8F);
            indexed_write(15'h03D4, 8'h13, 8'h28);
            indexed_write(15'h03D4, 8'h14, 8'h40);
            indexed_write(15'h03D4, 8'h17, 8'hA3);
            indexed_write(15'h03D4, 8'h18, 8'hFF);
            indexed_write(15'h03D4, 8'h11, 8'h8E);
            io_write(15'h03CD, 8'h13);
        end
    endtask

    // INTRO.PRG 3885Ah + 3889Ah, TABLE1.PRG 6A5Fh + 6AB4h: unchained,
    // byte mode, then the 320x240 table with R9 = C0h.
    task game_unchained_240;
        begin
            indexed_write(15'h03D4, 8'h11, 8'h00);
            indexed_write(15'h03C4, 8'h04, 8'h06);
            indexed_write(15'h03D4, 8'h14, 8'h00);
            indexed_write(15'h03D4, 8'h17, 8'hE3);
            io_write(15'h03C2, 8'hE3);
            indexed_write(15'h03D4, 8'h06, 8'h0D);
            indexed_write(15'h03D4, 8'h07, 8'h3E);
            indexed_write(15'h03D4, 8'h09, 8'hC0);
            indexed_write(15'h03D4, 8'h10, 8'hEA);
            indexed_write(15'h03D4, 8'h11, 8'h0C);
            indexed_write(15'h03D4, 8'h12, 8'hDF);
            indexed_write(15'h03D4, 8'h14, 8'h00);
            indexed_write(15'h03D4, 8'h15, 8'hEA);
            indexed_write(15'h03D4, 8'h16, 8'h06);
            indexed_write(15'h03D4, 8'h17, 8'hE3);
        end
    endtask

    // INTRO.PRG 36AE0h/372D6h/373B1h: 640-pixel 16-colour planar.
    task game_planar640;
        input [7:0] r9;
        begin
            indexed_write(15'h03C4, 8'h04, 8'h06);
            indexed_write(15'h03D4, 8'h11, 8'h0C);
            indexed_write(15'h03D4, 8'h04, 8'h54);
            indexed_write(15'h03D4, 8'h06, 8'h0B);
            indexed_write(15'h03D4, 8'h07, 8'h3E);
            indexed_write(15'h03D4, 8'h09, 8'h40);
            indexed_write(15'h03D4, 8'h10, 8'hEA);
            indexed_write(15'h03D4, 8'h11, 8'h8C);
            indexed_write(15'h03D4, 8'h12, 8'hDF);
            indexed_write(15'h03D4, 8'h14, 8'h00);
            indexed_write(15'h03D4, 8'h15, 8'hE7);
            indexed_write(15'h03D4, 8'h16, 8'h04);
            indexed_write(15'h03D4, 8'h17, 8'hE3);
            indexed_write(15'h03CE, 8'h05, 8'h00);
            indexed_write(15'h03D4, 8'h09, r9);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset = 1'b0;

        // Plain INT 10h AX=0012h is now a displayed 640x480x16 mode.
        tsr_mode12;
        check_route(1'b1, 1'b0, "TSR mode 12h baseline");
        if (dut.ega_v_double_scan !== 1'b0) begin
            errors = errors + 1; $display("FAIL mode 12h must not double scan");
        end

        // First intro pass: INT 10h 12h then 13h, eagle at 320x240.
        tsr_mode13;
        #1 if (!private_active || planar_memory_active ||
               dut.vga_planar640_active || unchained_active) begin
            errors = errors + 1; $display("FAIL TSR mode 13h must be packed");
        end
        game_unchained_240;
        check_route(1'b0, 1'b1, "eagle: unchained 320x240");
        check_profile(3'd2, "eagle profile");
        if (dut.ega_v_double_scan !== 1'b1) begin
            errors = errors + 1; $display("FAIL eagle R9 = C0h must double scan");
        end

        // Digital Illusions logo (640x480) and menu (640x240) from that state.
        game_planar640(8'h40);
        check_route(1'b1, 1'b0, "logo: 640x480x16");
        game_planar640(8'hC0);
        check_route(1'b1, 1'b0, "menu: 640x240x16");
        if (dut.ega_v_double_scan !== 1'b1) begin
            errors = errors + 1; $display("FAIL menu R9 = C0h must double scan");
        end

        // The table's normal view.
        tsr_mode13;
        game_unchained_240;
        indexed_write(15'h03D4, 8'h01, 8'h4F);
        indexed_write(15'h03D4, 8'h13, 8'h2A);
        check_route(1'b0, 1'b1, "table: 320x240");
        check_profile(3'd2, "normal table profile");

        // Its high-resolution view, TABLE1.PRG 66F0h: 320x350.
        tsr_mode13;
        indexed_write(15'h03C4, 8'h04, 8'h06);
        io_write(15'h03C2, 8'hA7);
        indexed_write(15'h03D4, 8'h11, 8'h05);
        indexed_write(15'h03D4, 8'h06, 8'hBF);
        indexed_write(15'h03D4, 8'h07, 8'h1F);
        indexed_write(15'h03D4, 8'h09, 8'h40);
        indexed_write(15'h03D4, 8'h12, 8'h5D);
        indexed_write(15'h03D4, 8'h13, 8'h2A);
        indexed_write(15'h03D4, 8'h14, 8'h0F);
        indexed_write(15'h03D4, 8'h17, 8'hE3);
        indexed_write(15'h03D4, 8'h01, 8'h4F);
        indexed_write(15'h03D4, 8'h11, 8'hA5);
        check_route(1'b0, 1'b1, "hi-res table");
        check_profile(3'd4, "hi-res table profile");

        // TABLE1.PRG 69C8h: Line Compare 13Ch for the score panel, written as
        // R18 = 3Ch, R7 bit 4 = 1 and R9 bit 6 = 0.
        indexed_write(15'h03D4, 8'h11, 8'h25);
        indexed_write(15'h03D4, 8'h18, 8'h3C);
        indexed_write(15'h03D4, 8'h07, 8'h1F);
        indexed_write(15'h03D4, 8'h09, 8'h00);
        #1 if (dut.ega_crtc_line_compare_debug !== 10'h13C) begin
            errors = errors + 1;
            $display("FAIL panel Line Compare=%h", dut.ega_crtc_line_compare_debug);
        end
        // 15 kHz raster: output line 159 shows scanline 318, the panel's
        // second scanline, at address zero; line 158 is still the table.
        force dut.vga_unchained_renderer.timing.h_count = 11'd0;
        force dut.vga_unchained_renderer.timing.v_count = 10'd158;
        #1 if (dut.vga_unchained_renderer.below_split !== 1'b0) begin
            errors = errors + 1; $display("FAIL TV line 158 must be the table");
        end
        force dut.vga_unchained_renderer.timing.v_count = 10'd174;
        #1 if (dut.vga_unchained_renderer.below_split !== 1'b1 ||
               dut.vga_unchained_renderer.timing_active !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL TV line 174 must be visible panel: below=%b active=%b",
                     dut.vga_unchained_renderer.below_split,
                     dut.vga_unchained_renderer.timing_active);
        end
        release dut.vga_unchained_renderer.timing.h_count;
        release dut.vga_unchained_renderer.timing.v_count;

        // Back to DOS clears every private route.
        io_write(15'h03CD, 8'h00);
        check_route(1'b0, 1'b0, "leaving VGA");

        if (errors == 0) $display("RESULT: PASS");
        else $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
