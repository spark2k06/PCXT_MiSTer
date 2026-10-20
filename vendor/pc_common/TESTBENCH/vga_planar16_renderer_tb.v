`timescale 1ns/1ps

// NEEDS: icarus (samples on the clock edge it drives; races under Verilator 5.020, also with the PCAT-286 original)
module vga_planar16_renderer_tb;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg enable = 1'b0;
    reg native_70hz = 1'b1;
    reg wide_640 = 1'b0;
    reg [4:0] crtc_max_scan = 5'd0;
    reg crtc_double_scan = 1'b0;
    reg [15:0] crtc_start_address = 16'h0000;
    reg [7:0] crtc_offset = 8'd22;
    reg [9:0] crtc_line_compare = 10'h3FF;
    reg [3:0] attr_pixel_pan = 4'd0;
    reg split_panning_suppress = 1'b0;
    reg [7:0] plane0 = 8'h00;
    reg [7:0] plane1 = 8'h00;
    reg [7:0] plane2 = 8'h00;
    reg [7:0] plane3 = 8'h00;
    reg data_valid = 1'b0;

    wire [15:0] vram_addr;
    wire vram_read_en;
    wire [3:0] plane_index;
    wire pixel_valid;
    integer errors = 0;

    always #5 clock = ~clock;

    vga_planar16_renderer dut (
        .clock(clock), .reset(reset), .enable(enable),
        .native_70hz(native_70hz), .wide_640(wide_640), .crt_h_offset(4'd0),
        .crt_v_offset(3'd0), .crtc_start_address(crtc_start_address),
        .crtc_offset(crtc_offset), .crtc_line_compare(crtc_line_compare),
        .crtc_max_scan(crtc_max_scan), .crtc_double_scan(crtc_double_scan),
        .attr_pixel_pan(attr_pixel_pan),
        .split_panning_suppress(split_panning_suppress),
        .vram_addr(vram_addr), .vram_read_en(vram_read_en),
        .vram_plane0(plane0), .vram_plane1(plane1),
        .vram_plane2(plane2), .vram_plane3(plane3),
        .vram_data_valid(data_valid), .plane_index(plane_index),
        .pixel_valid(pixel_valid), .de(), .hsync(), .vsync(),
        .hblank(), .vblank(), .pixel_toggle()
    );

    task check16;
        input [127:0] tag;
        input [15:0] got;
        input [15:0] expected;
        begin
            #1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL: %0s got=%h expected=%h", tag, got, expected);
            end
        end
    endtask

    task check4;
        input [127:0] tag;
        input [3:0] got;
        input [3:0] expected;
        begin
            #1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL: %0s got=%h expected=%h", tag, got, expected);
            end
        end
    endtask

    initial begin
        #20 reset = 1'b0;
        enable = 1'b1;

        // Freeze the timing coordinates to inspect address generation without
        // waiting through complete VGA frames.
        force dut.timing.h_count = 11'd0;
        // Native scans each 200-line source row twice, so physical lines 6
        // and 7 both fetch source row 3.
        force dut.timing.v_count = 10'd6;
        #1;
        check16("offset22 gives 44-byte rows", vram_addr, 16'd132);
        force dut.timing.v_count = 10'd7;
        #1;
        check16("native repeats the planar source row", vram_addr, 16'd132);

        dut.start_address_latched = 16'h0100;
        #1;
        check16("start address adds to row base", vram_addr, 16'h0184);

        attr_pixel_pan = 4'd7;
        force dut.timing.h_count = 11'd2; // native pixel_x=1; 1+7 crosses byte
        #1;
        check16("pel pan crosses byte boundary", vram_addr, 16'h0185);

        // Viking Child keeps its scrolling playfield at 2000h and programs
        // Line Compare 128h so physical line 297 restarts the fixed panel at
        // address zero. The reduced 320x200 raster sees that at output y=149.
        crtc_offset = 8'd20;
        attr_pixel_pan = 4'd0;
        crtc_start_address = 16'h2000;
        force dut.timing_vsync = 1'b1;
        @(posedge clock); #1;
        force dut.timing_vsync = 1'b0;
        @(posedge clock); #1;
        crtc_line_compare = 10'h128;
        force dut.pixel_x = 10'd0;
        force dut.pixel_y = 10'd148;
        #1;
        check16("Viking last scrolling line", vram_addr, 16'h3720);
        force dut.pixel_y = 10'd149;
        #1;
        check16("Viking panel starts at zero", vram_addr, 16'h0000);
        force dut.pixel_y = 10'd150;
        #1;
        check16("Viking panel advances one row", vram_addr, 16'h0028);

        attr_pixel_pan = 4'd7;
        split_panning_suppress = 1'b1;
        force dut.pixel_x = 10'd1;
        force dut.pixel_y = 10'd149;
        #1;
        check16("split suppresses panel panning", vram_addr, 16'h0000);

        crtc_line_compare = 10'h3FF;
        split_panning_suppress = 1'b0;
        dut.start_address_latched = 16'h0100;
        release dut.pixel_x;
        release dut.pixel_y;
        crtc_offset = 8'd19;
        attr_pixel_pan = 4'd0;
        force dut.timing.h_count = 11'd0;
        force dut.timing.v_count = 10'd6;
        #1;
        check16("unsupported offset falls back to 40", vram_addr, 16'h0178);

        // At source x=0, bit 7 from the four planes forms colour index 5.
        force dut.timing.v_count = 10'd0;
        plane0 = 8'h80;
        plane1 = 8'h00;
        plane2 = 8'h80;
        plane3 = 8'h00;
        data_valid = 1'b1;
        @(posedge clock); #1;
        check4("four planar bits form colour index", plane_index, 4'h5);
        if (!pixel_valid) begin
            errors = errors + 1;
            $display("FAIL: valid planar fetch did not assert pixel_valid");
        end

        // VGA mode 12h: 640 pixels, 80-byte rows, one Native clock per pixel
        // and one Native line per physical scanline.
        wide_640 = 1'b1;
        crtc_offset = 8'd40;
        crtc_line_compare = 10'h3FF;
        dut.start_address_latched = 16'h0000;
        force dut.timing.h_count = 11'd0;
        force dut.timing.v_count = 10'd6;
        #1;
        check16("mode 12h row 6", vram_addr, 16'd480);
        force dut.timing.h_count = 11'd639;
        #1;
        check16("mode 12h last byte of row 6", vram_addr, 16'd559);
        force dut.timing.v_count = 10'd479;
        #1;
        check16("mode 12h last byte of the screen", vram_addr, 16'd38399);
        // Pinball Fantasies' menu: R9 = C0h doubles every row (640x240).
        crtc_double_scan = 1'b1;
        force dut.timing.h_count = 11'd0;
        force dut.timing.v_count = 10'd7;
        #1;
        check16("scan doubling repeats row 3", vram_addr, 16'd240);
        crtc_max_scan = 5'd1;
        #1;
        check16("doubling composes with maximum scan line", vram_addr, 16'd80);
        crtc_max_scan = 5'd0;
        // Line Compare restarts at zero on the following physical scanline.
        crtc_line_compare = 10'd413;
        force dut.timing.v_count = 10'd413;
        #1;
        check16("last line above the split", vram_addr, 16'd16480);
        force dut.timing.v_count = 10'd414;
        #1;
        check16("split starts at address zero", vram_addr, 16'd0);
        force dut.timing.v_count = 10'd417;
        #1;
        check16("split advances in source rows", vram_addr, 16'd80);
        crtc_line_compare = 10'h3FF;
        crtc_double_scan = 1'b0;
        // A wider virtual row: Offset 41 is 82 bytes.
        crtc_offset = 8'd41;
        force dut.timing.v_count = 10'd2;
        #1;
        check16("offset 41 gives 82-byte rows", vram_addr, 16'd164);
        crtc_offset = 8'd40;
        // The 15 kHz raster: two clocks per pixel, every second scanline.
        native_70hz = 1'b0;
        force dut.timing.h_count = 11'd16;
        force dut.timing.v_count = 10'd3;
        #1;
        check16("TV mode 12h samples scanline 6", vram_addr, 16'd481);
        native_70hz = 1'b1;

        // One Native clock per pixel: the bit select must wait out the two
        // clock plane latency, so x=1's data still shows x=0's bit 7 first.
        plane0 = 8'h80; plane1 = 8'h00; plane2 = 8'h00; plane3 = 8'h00;
        force dut.timing.h_count = 11'd0;
        repeat (3) @(posedge clock);
        force dut.timing.h_count = 11'd1;
        @(posedge clock); #1;
        check4("select lags x=1 by one clock", plane_index, 4'h1);
        @(posedge clock); #1;
        check4("select reaches x=1 after two clocks", plane_index, 4'h0);
        wide_640 = 1'b0;

        release dut.timing.h_count;
        release dut.timing.v_count;

        if (errors == 0) $display("RESULT: PASS");
        else $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
