`timescale 1ns/1ps

// Replays the register signature written after Dyna Blaster's INT 10h/12h.
// The private mode marker must leave the EGA path in place until the complete
// unchained 256x232 setup is present, then switch both raster and VRAM route.
module vga_dyna_blaster_route_tb;
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

    task check_route;
        input expected;
        input [8*64-1:0] label;
        begin
            #1;
            if (private_active !== expected || unchained_active !== expected ||
                planar_memory_active !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: private=%b unchained=%b planar=%b expected=%b",
                         label, private_active, unchained_active,
                         planar_memory_active, expected);
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset = 1'b0;
        io_write(15'h03CD, 8'h12);
        check_route(1'b0, "mode 12h marker alone");

        indexed_write(15'h03C4, 8'h04, 8'h06); // Chain-4 off
        indexed_write(15'h03CE, 8'h05, 8'h40); // 256-colour shift
        indexed_write(15'h03CE, 8'h06, 8'h05); // graphics A000h aperture
        indexed_write(15'h03D4, 8'h11, 8'h0C); // unlock CRTC 00h-07h
        indexed_write(15'h03D4, 8'h01, 8'h3F); // 64 chars = 256 pixels
        indexed_write(15'h03D4, 8'h07, 8'h3E); // overflow
        indexed_write(15'h03D4, 8'h09, 8'h41); // two scans per source row
        indexed_write(15'h03D4, 8'h12, 8'hCF); // 464 physical lines
        indexed_write(15'h03D4, 8'h13, 8'h40); // 128 bytes per plane row
        indexed_write(15'h03D4, 8'h14, 8'h00); // doubleword mode off
        check_route(1'b0, "mode control byte-address bit still missing");
        indexed_write(15'h03D4, 8'h17, 8'hE3); // byte addressing
        check_route(1'b1, "complete 256x232 signature");
        if (dut.vga_unchained_profile !== 2'd3) begin
            errors = errors + 1;
            $display("FAIL Dyna profile=%0d", dut.vga_unchained_profile);
        end

        indexed_write(15'h03D4, 8'h13, 8'h20);
        check_route(1'b1, "direct-width row stride");
        indexed_write(15'h03D4, 8'h01, 8'h4F);
        check_route(1'b0, "leaving Dyna timing signature");
        indexed_write(15'h03D4, 8'h01, 8'h3F);
        check_route(1'b1, "restoring Dyna timing signature");
        io_write(15'h03CD, 8'h00);
        check_route(1'b0, "leaving private mode 12h");

        if (errors == 0) $display("RESULT: PASS");
        else $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
