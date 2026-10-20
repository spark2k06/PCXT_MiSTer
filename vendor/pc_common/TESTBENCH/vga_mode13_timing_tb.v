`timescale 1ns/1ps

module vga_mode13_timing_tb;
    reg clock = 1'b0;
    always #5 clock = ~clock;

    reg reset = 1'b1;
    reg enable = 1'b1;
    reg native_70hz = 1'b0;
    reg [2:0] mode_x_profile = 3'd0;
    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire [9:0] scan_y;
    wire active;
    wire hsync;
    wire vsync;
    wire status_blank;
    integer pulses;
    reg status_blank_q;
    integer errors = 0;

    vga_mode13_timing dut (
        .clock(clock), .reset(reset), .enable(enable),
        .native_70hz(native_70hz), .mode_x_profile(mode_x_profile),
        .crt_h_offset(4'd0), .crt_v_offset(3'd0),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .scan_y(scan_y), .active(active),
        .hblank(), .vblank(), .hsync(hsync), .vsync(vsync), .status_blank(status_blank),
        .line_start(), .frame_start(), .pixel_toggle()
    );

    task check;
        input condition;
        input [8*64-1:0] message;
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("FAIL: %0s (h=%0d v=%0d)", message, dut.h_count, dut.v_count);
            end
        end
    endtask

    task reset_timing;
        input native;
        input [2:0] profile;
        begin
            native_70hz = native;
            mode_x_profile = profile;
            reset = 1'b1;
            repeat (2) @(posedge clock);
            reset = 1'b0;
        end
    endtask

    // Counts Input Status #1 bit 0 rising edges (display -> blank) over one
    // frame, the way Pinball Fantasies' sound driver measures the raster.
    task check_status_lines;
        input native;
        input [2:0] profile;
        input integer expected;
        begin
            reset_timing(native, profile);
            pulses = 0;
            status_blank_q = 1'b1;
            @(posedge clock);
            while (!(dut.h_count == 0 && dut.v_count == 0)) @(posedge clock);
            @(posedge clock);
            while (!(dut.h_count == 0 && dut.v_count == 0)) begin
                #1;
                if (status_blank && !status_blank_q) pulses = pulses + 1;
                status_blank_q = status_blank;
                @(posedge clock);
            end
            if (pulses != expected) begin
                errors = errors + 1;
                $display("FAIL: native=%0d profile=%0d status lines=%0d expected=%0d",
                         native, profile, pulses, expected);
            end
        end
    endtask

    initial begin
        // Native is 912x449 at the adapter's 28.636 MHz: 31.40 kHz, 69.9 Hz,
        // with the 200 source rows double-scanned into a 640x400 picture.
        reset_timing(1'b1, 3'd0);
        // The reset release shares a clock edge with this initial block, so
        // the first counted generator edge follows it by one simulation tick.
        repeat (911) @(posedge clock);
        #1 check((dut.h_count == 0) && (dut.v_count == 1),
                  "native line total must be 912 clocks");
        repeat (912 * 448) @(posedge clock);
        #1 check((dut.h_count == 0) && (dut.v_count == 0),
                  "native frame total must be 912 x 449 clocks");

        force dut.h_count = 11'd638; force dut.v_count = 10'd0; #1;
        check(active && (pixel_x == 10'd319), "native active width must be 640 pixels");
        force dut.h_count = 11'd640; #1;
        check(!active, "native active area must end at clock 640");
        force dut.h_count = 11'd672; #1;
        check(hsync, "native HSYNC must start at clock 672");
        force dut.h_count = 11'd768; #1;
        check(!hsync, "native HSYNC must be 96 clocks wide");
        force dut.h_count = 11'd0;
        force dut.v_count = 10'd398; #1;
        check(active && (pixel_y == 10'd199),
              "native line 398 must show source row 199");
        force dut.v_count = 10'd399; #1;
        check(active && (pixel_y == 10'd199),
              "native line 399 must repeat source row 199");
        force dut.v_count = 10'd400; #1;
        check(!active, "native active area must end at line 400");
        force dut.v_count = 10'd412; #1;
        check(vsync, "native VSYNC must start at line 412");
        force dut.v_count = 10'd413; #1;
        check(vsync, "native VSYNC must last two lines");
        force dut.v_count = 10'd414; #1;
        check(!vsync, "native VSYNC must be 2 lines wide");
        release dut.h_count; release dut.v_count;

        // Native 360x200 uses the same 912 clocks at 28.636 MHz; its 720 active
        // output clocks share the same 912-clock line.
        reset_timing(1'b1, 3'd1);
        repeat (911) @(posedge clock);
        #1 check((dut.h_count == 0) && (dut.v_count == 1),
                  "native 360 line total must remain 912 clocks");
        force dut.h_count = 11'd718; force dut.v_count = 10'd0; #1;
        check(active && (pixel_x == 10'd359),
              "native 360 active width must be 720 clocks");
        force dut.h_count = 11'd720; #1;
        check(!active, "native 360 active area must end at clock 720");
        force dut.h_count = 11'd744; #1;
        check(hsync, "native 360 HSYNC must start at clock 744");
        force dut.h_count = 11'd840; #1;
        check(!hsync, "native 360 HSYNC must be 96 clocks wide");
        release dut.h_count; release dut.v_count;

        // Changing profiles live must recognize counts beyond a newly smaller
        // raster as terminal instead of waiting for the counter to overflow.
        native_70hz = 1'b1;
        force dut.h_count = 11'd1000; #1;
        check(dut.h_last, "live Native switch must clamp an oversized line");
        native_70hz = 1'b0;
        force dut.v_count = 10'd300; #1;
        check(dut.v_last, "live 60Hz switch must clamp an oversized frame");
        release dut.h_count; release dut.v_count;

        // 60 Hz retains the existing TV-compatible 1824x262 raster.
        reset_timing(1'b0, 3'd0);
        repeat (1823) @(posedge clock);
        #1 check((dut.h_count == 0) && (dut.v_count == 1),
                  "60Hz line total must be 1824 clocks");
        repeat (1824 * 261) @(posedge clock);
        #1 check((dut.h_count == 0) && (dut.v_count == 0),
                  "60Hz frame total must be 1824 x 262 clocks");

        // 360x200 keeps both 60 Hz totals while widening the source and the
        // visible output to 360 and 720 pixels respectively.
        reset_timing(1'b0, 3'd1);
        force dut.h_count = 11'd1438; force dut.v_count = 10'd0; #1;
        check(active && (pixel_x == 10'd359), "360x200 active width must be 360 source pixels");
        force dut.h_count = 11'd1440; #1;
        check(!active, "360x200 active area must end at clock 1440");
        release dut.h_count; release dut.v_count;

        // 320x240 intentionally uses the direct 262-line 15 kHz raster so
        // it can be tested on televisions without a capture/scaler path.
        reset_timing(1'b0, 3'd2);
        force dut.h_count = 11'd1278; force dut.v_count = 10'd239; #1;
        check(active && (pixel_x == 10'd319) && (pixel_y == 10'd239),
              "320x240 must include source pixel 319,239");
        force dut.v_count = 10'd240; #1;
        check(!active, "320x240 active area must end at line 240");
        force dut.v_count = 10'd248; #1;
        check(vsync, "320x240 60Hz VSYNC must start at line 248");
        force dut.v_count = 10'd251; #1;
        check(!vsync, "320x240 60Hz VSYNC must be 3 lines wide");
        release dut.h_count; release dut.v_count;

        // Native 320x240 is Mode X's real 60 Hz VGA frame: 912x525, each of
        // the 240 source rows on two of the 480 scanlines.
        reset_timing(1'b1, 3'd2);
        #1 check((dut.h_total == 11'd912) && (dut.v_total == 10'd525),
                 "native 320x240 frame must be 912x525");
        force dut.h_count = 11'd0; force dut.v_count = 10'd479; #1;
        check(active && (pixel_y == 10'd239) && (scan_y == 10'd479),
              "native 320x240 must end on source row 239, scanline 479");
        force dut.v_count = 10'd480; #1;
        check(!active, "native 320x240 active area must end at line 480");
        force dut.v_count = 10'd490; #1;
        check(vsync, "native 320x240 VSYNC must start at line 490");
        release dut.h_count; release dut.v_count;

        // Dyna Blaster presents 256x232 logical pixels. Native doubles both
        // dimensions into a 512x464 picture on a 525-line 60 Hz VGA frame.
        reset_timing(1'b1, 3'd3);
        #1 check((dut.h_total == 11'd912) && (dut.v_total == 10'd525),
                 "native Dyna frame must be 912x525");
        force dut.h_count = 11'd510; force dut.v_count = 10'd462; #1;
        check(active && pixel_x == 10'd255 && pixel_y == 10'd231,
              "native Dyna must include source pixel 255,231");
        force dut.h_count = 11'd512; #1;
        check(!active, "native Dyna must blank at clock 512");
        force dut.h_count = 11'd592; #1;
        check(hsync, "native Dyna HSYNC must start at clock 592");
        force dut.h_count = 11'd688; #1;
        check(!hsync, "native Dyna HSYNC must be 96 clocks wide");
        force dut.h_count = 11'd0; force dut.v_count = 10'd463; #1;
        check(active && pixel_y == 10'd231,
              "native Dyna must repeat source row 231");
        force dut.v_count = 10'd464; #1;
        check(!active, "native Dyna must blank at line 464");
        force dut.v_count = 10'd482; #1;
        check(vsync, "native Dyna VSYNC must start at line 482");
        force dut.v_count = 10'd484; #1;
        check(!vsync, "native Dyna VSYNC must be two lines wide");
        release dut.h_count; release dut.v_count;

        // The TV route retains the established 1824x262, 15.7 kHz frame and
        // emits each source row once.
        reset_timing(1'b0, 3'd3);
        #1 check((dut.h_total == 11'd1824) && (dut.v_total == 10'd262),
                 "TV Dyna frame must be 1824x262");
        force dut.h_count = 11'd1022; force dut.v_count = 10'd231; #1;
        check(active && pixel_x == 10'd255 && pixel_y == 10'd231,
              "TV Dyna must include source pixel 255,231");
        force dut.h_count = 11'd1024; #1;
        check(!active, "TV Dyna must blank at clock 1024");
        force dut.h_count = 11'd1296; #1;
        check(hsync, "TV Dyna HSYNC must start at clock 1296");
        force dut.h_count = 11'd1456; #1;
        check(!hsync, "TV Dyna HSYNC must be 160 clocks wide");
        force dut.h_count = 11'd0; force dut.v_count = 10'd232; #1;
        check(!active, "TV Dyna must blank at line 232");
        force dut.v_count = 10'd240; #1;
        check(vsync, "TV Dyna VSYNC must start at line 240");
        force dut.v_count = 10'd243; #1;
        check(!vsync, "TV Dyna VSYNC must be three lines wide");
        release dut.h_count; release dut.v_count;

        // 320x350 (Pinball Fantasies high resolution): Native is VGA's
        // 350-line 70 Hz frame, 912x449, and shows every physical scanline.
        reset_timing(1'b1, 3'd4);
        #1 check((dut.h_total == 11'd912) && (dut.v_total == 10'd449),
                 "native 320x350 frame must be 912x449");
        force dut.h_count = 11'd638; force dut.v_count = 10'd349; #1;
        check(active && pixel_x == 10'd319 && scan_y == 10'd349,
              "native 320x350 must include source pixel 319 on scanline 349");
        force dut.v_count = 10'd350; #1;
        check(!active, "native 320x350 must blank at line 350");
        force dut.h_count = 11'd0; force dut.v_count = 10'd387; #1;
        check(vsync, "native 320x350 VSYNC must start at line 387");
        force dut.v_count = 10'd389; #1;
        check(!vsync, "native 320x350 VSYNC must be two lines wide");
        release dut.h_count; release dut.v_count;

        // On TV the same picture is 175 lines of the 262-line field, each the
        // first scanline of a physical pair.
        reset_timing(1'b0, 3'd4);
        #1 check((dut.h_total == 11'd1824) && (dut.v_total == 10'd262),
                 "TV 320x350 frame must be 1824x262");
        force dut.h_count = 11'd0; force dut.v_count = 10'd174; #1;
        check(active && scan_y == 10'd348,
              "TV 320x350 line 174 must show scanline 348");
        force dut.v_count = 10'd175; #1;
        check(!active, "TV 320x350 must blank at line 175");
        force dut.v_count = 10'd213; #1;
        check(vsync, "TV 320x350 VSYNC must start at line 213");
        force dut.v_count = 10'd229; #1;
        check(!vsync, "TV 320x350 VSYNC must be 16 lines wide");
        release dut.h_count; release dut.v_count;

        // 640x480 (VGA mode 12h): Native is the 60 Hz 912x525 VGA frame with
        // one clock per source pixel and every scanline shown.
        reset_timing(1'b1, 3'd5);
        #1 check((dut.h_total == 11'd912) && (dut.v_total == 10'd525),
                 "native 640x480 frame must be 912x525");
        force dut.h_count = 11'd639; force dut.v_count = 10'd479; #1;
        check(active && pixel_x == 10'd639 && scan_y == 10'd479,
              "native 640x480 must include pixel 639 on scanline 479");
        force dut.h_count = 11'd640; #1;
        check(!active, "native 640x480 must blank at clock 640");
        force dut.h_count = 11'd0; force dut.v_count = 10'd490; #1;
        check(vsync, "native 640x480 VSYNC must start at line 490");
        force dut.v_count = 10'd492; #1;
        check(!vsync, "native 640x480 VSYNC must be two lines wide");
        release dut.h_count; release dut.v_count;
        // TV: 1280 active clocks are two per pixel; 240 of the 480 lines.
        reset_timing(1'b0, 3'd5);
        #1 check((dut.h_total == 11'd1824) && (dut.v_total == 10'd262),
                 "TV 640x480 frame must be 1824x262");
        force dut.h_count = 11'd1279; force dut.v_count = 10'd239; #1;
        check(active && pixel_x == 10'd639 && scan_y == 10'd478,
              "TV 640x480 must include pixel 639 on scanline 478");
        force dut.v_count = 10'd240; #1;
        check(!active, "TV 640x480 must blank at line 240");
        release dut.h_count; release dut.v_count;

        // Every other profile reports the physical scanline it samples.
        reset_timing(1'b0, 3'd2);
        force dut.h_count = 11'd0; force dut.v_count = 10'd239; #1;
        check(scan_y == 10'd478, "TV 320x240 line 239 must show scanline 478");
        release dut.h_count; release dut.v_count;
        reset_timing(1'b1, 3'd0);
        force dut.h_count = 11'd0; force dut.v_count = 10'd399; #1;
        check(scan_y == 10'd399, "native 320x200 line 399 is scanline 399");
        release dut.h_count; release dut.v_count;

        // One bit 0 pulse per physical VGA scanline on every raster.
        check_status_lines(1'b0, 3'd0, 400);
        check_status_lines(1'b0, 3'd2, 480);
        check_status_lines(1'b0, 3'd4, 350);
        check_status_lines(1'b0, 3'd5, 480);
        check_status_lines(1'b1, 3'd0, 400);
        check_status_lines(1'b1, 3'd2, 480);
        check_status_lines(1'b1, 3'd4, 350);
        check_status_lines(1'b1, 3'd5, 480);

        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
