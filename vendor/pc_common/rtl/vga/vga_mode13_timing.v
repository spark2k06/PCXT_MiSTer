//============================================================================
//
//  VGA mode 13h 320x200 timing. The selectable Native profile restores the
//  original free-running ~31.5 kHz / 70 Hz Mode 13h scan; the 60 Hz profile
//  is the 15 kHz CRT-TV-compatible raster used by older builds.
//
//  The 60 Hz geometry below is the CGA/EGA 200-line raster, dot for dot: 1824
//  clk_28_636 clocks/line (912 CGA dots at 14.318 MHz, ~15.70 kHz) and 262
//  lines/frame (~59.9 Hz), with the active window, sync width and porches in
//  the same places. A TV therefore sees a signal geometrically identical to
//  the EGA/CGA modes this core already displays correctly, and centres it the
//  same way, instead of needing its own set of porches.
//
//  Each of the 320 source pixels is 4 clocks wide, so the active window is
//  1280 clocks - exactly the 640 dots CGA spends at 14.318 MHz. pixel_toggle
//  is emitted every 2 clocks, so the framework measures 640x200 here as well,
//  letting one MiSTer.ini video section and one set of OSD offsets cover both
//  paths.
//
//  The framebuffer is random-access, so only the raster that reads it
//  changes. The 15 kHz profile shows every source line once; Native doubles
//  each 200-line source row into the 400 physical scanlines of VGA mode 13h.
//
//============================================================================

module vga_mode13_timing(
    input  wire        clock,
    input  wire        reset,
    input  wire        enable,
    input  wire        native_70hz,
    // 0 320x200, 1 360x200, 2 320x240, 3 256x232, 4 320x350, 5 640x480.
    input  wire [2:0]  mode_x_profile,
    input  wire [3:0]  crt_h_offset,
    input  wire [2:0]  crt_v_offset,
    output wire [9:0]  pixel_x,
    output wire [9:0]  pixel_y,
    // Physical VGA scanline represented by the current output line. The 15 kHz
    // profiles sample every second one; Native line-doubled profiles show each.
    output wire [9:0]  scan_y,
    output wire        active,
    output wire        hblank,
    output wire        vblank,
    output wire        hsync,
    output wire        vsync,
    // Input Status #1 bit 0 as a VGA would raise it: once per physical
    // scanline. Where an output line stands for two scanlines it carries two
    // display-enable windows, one per half line.
    output wire        status_blank,
    output wire        line_start,
    output wire        frame_start,
    output reg         pixel_toggle
);

    // 320 source pixels x 4 clocks = the 1280 clocks CGA spends on its 640
    // dots; the porches are CGA's 80/80/112 dots, also doubled, less the 16
    // clocks of bias described below.
    localparam [10:0] TV_H_ACTIVE = 11'd1280;
    localparam [10:0] TV_H_FRONT  = 11'd144;
    localparam [10:0] TV_H_SYNC   = 11'd160;
    localparam [10:0] TV_H_BACK   = 11'd240;
    localparam [10:0] TV_H_TOTAL  = TV_H_ACTIVE + TV_H_FRONT + TV_H_SYNC + TV_H_BACK;

    // CGA's 200-line field: 24 lines of front porch, a 16-line VSYNC and 22
    // lines of back porch around the 200 active lines, again with a 1-line
    // bias applied.
    localparam [9:0] TV_V_ACTIVE = 10'd200;
    localparam [9:0] TV_V_FRONT  = 10'd25;
    localparam [9:0] TV_V_SYNC   = 10'd16;
    localparam [9:0] TV_V_BACK   = 10'd21;
    localparam [9:0] TV_V_TOTAL  = TV_V_ACTIVE + TV_V_FRONT + TV_V_SYNC + TV_V_BACK;

    // The PCAT video adapter clocks this raster from the 28.636 MHz video
    // clock only; there is no 25.2 MHz VGA dot clock in its domain. The
    // PCXT-derived 800-clock line therefore ran at 35.8 kHz here: 79.7 Hz
    // for a 449-line frame and 68.2 Hz for a 525-line one, which a 60 Hz
    // HDMI output can only follow by dropping or repeating frames - the
    // judder seen on Pinball Fantasies' scrolling table. Every Native profile
    // now uses a 912-clock line: 31.40 kHz, 69.9 Hz at 449 lines and 59.8 Hz
    // at 525, the VGA rates. A 320-wide source pixel stays two clocks wide.
    localparam [10:0] NATIVE_H_ACTIVE = 11'd640;
    localparam [10:0] NATIVE_H_FRONT  = 11'd32;
    localparam [10:0] NATIVE_H_SYNC   = 11'd96;
    localparam [10:0] NATIVE_H_TOTAL  = 11'd912;
    // 360x200 needs 720 active output clocks within the same line.
    localparam [10:0] NATIVE_WIDE_H_ACTIVE = 11'd720;
    localparam [10:0] NATIVE_WIDE_H_FRONT  = 11'd24;
    localparam [10:0] NATIVE_WIDE_H_TOTAL  = 11'd912;
    // Mode 13h is 320x200 in memory but a VGA scans every row twice: 640x400
    // visible dots at 70 Hz. Keeping only 200 active output lines places
    // VSYNC immediately below the picture and leaves half the frame blank,
    // which a monitor centres as a short, displaced image.
    localparam [9:0]  NATIVE_V_ACTIVE = 10'd400;
    localparam [9:0]  NATIVE_V_FRONT  = 10'd12;
    localparam [9:0]  NATIVE_V_SYNC   = 10'd2;
    localparam [9:0]  NATIVE_V_BACK   = 10'd35;
    localparam [9:0]  NATIVE_V_TOTAL  = NATIVE_V_ACTIVE + NATIVE_V_FRONT + NATIVE_V_SYNC + NATIVE_V_BACK;

    localparam [2:0] PROFILE_360X200 = 3'd1;
    localparam [2:0] PROFILE_320X240 = 3'd2;
    localparam [2:0] PROFILE_256X232 = 3'd3;
    localparam [2:0] PROFILE_320X350 = 3'd4;
    localparam [2:0] PROFILE_640X480 = 3'd5;
    wire mode_x_360 = (mode_x_profile == PROFILE_360X200);
    wire mode_x_240 = (mode_x_profile == PROFILE_320X240);
    wire mode_x_256 = (mode_x_profile == PROFILE_256X232);
    wire mode_x_350 = (mode_x_profile == PROFILE_320X350);
    // 640x480 (VGA mode 12h) is the only profile with one source pixel per
    // output pixel: one clock on Native, two on the 15 kHz raster. Its 480
    // physical scanlines use the 60 Hz 525-line VGA frame on Native and the
    // 240-line TV raster of the 320x240 profile, one line per physical pair.
    wire mode_x_640 = (mode_x_profile == PROFILE_640X480);
    // Native scans every source row of every profile twice, like a VGA: the
    // 200-line profiles in the 70 Hz 449-line frame, 320x240 in the 60 Hz
    // 525-line frame that Mode X really uses. 320x240 used to be emitted as
    // 240 lines of a 70 Hz frame, which a 60 Hz HDMI scaler can only follow
    // by dropping one frame in seven - a visible judder on scrolling games.
    wire native_line_double = native_70hz;

    // 320x350 is VGA's 350-line 70 Hz frame: 350 + 37 + 2 + 60 = 449 lines,
    // the same total as the 400-line profile, so Native shows every physical
    // scanline. A 15 kHz TV cannot carry 350 lines in one field; it receives
    // 175 lines, each the first of a physical pair, centred like 200-line
    // output (12 more lines of back porch, 13 more of front porch).

    // 360-wide mode borrows blank time for its wider active area; 320x240
    // borrows vertical blank time. The 60 Hz path remains a 15.70 kHz / 59.9
    // Hz TV raster; Native uses a 912-clock, 31.4 kHz line.
    wire [10:0] h_active = mode_x_256 ? (native_70hz ? 11'd512 : 11'd1024) :
                           mode_x_360 ? (native_70hz ? NATIVE_WIDE_H_ACTIVE : 11'd1440)
                                       : (native_70hz ? NATIVE_H_ACTIVE : TV_H_ACTIVE);
    wire [10:0] h_front  = mode_x_256 ? (native_70hz ? 11'd80 : 11'd272) :
                           mode_x_360 ? (native_70hz ? NATIVE_WIDE_H_FRONT : 11'd112)
                                       : (native_70hz ? NATIVE_H_FRONT : TV_H_FRONT);
    wire [10:0] h_sync   = native_70hz ? NATIVE_H_SYNC : TV_H_SYNC;
    wire [10:0] h_total  = native_70hz ? NATIVE_H_TOTAL : TV_H_TOTAL;
    wire [9:0]  v_active = mode_x_256       ? (native_70hz ? 10'd464 : 10'd232)
                          : mode_x_640      ? (native_70hz ? 10'd480 : 10'd240)
                          : mode_x_240      ? (native_70hz ? 10'd480 : 10'd240)
                          : mode_x_350      ? (native_70hz ? 10'd350 : 10'd175)
                          : native_line_double ? NATIVE_V_ACTIVE
                                             : TV_V_ACTIVE;
    // 240 direct lines leave only 22 raster lines blank in the 262-line 60 Hz
    // profile. This is deliberately exposed for hardware testing; an eight
    // line front porch still leaves CRT V offsets 0..7 safe from underflow.
    // Centre the 464-line Native picture within the standard 480-line VGA
    // field. On TV, leave 19 lines after sync before the next active picture,
    // close to the established 200-line profile's 21-line back porch.
    wire [9:0]  v_front  = mode_x_256 ? (native_70hz ? 10'd18 : 10'd8) :
                           mode_x_240 ? (native_70hz ? 10'd10 : 10'd8) :
                           mode_x_640 ? (native_70hz ? 10'd10 : 10'd8) :
                           mode_x_350 ? (native_70hz ? 10'd37 : 10'd38)
                                       : (native_70hz ? NATIVE_V_FRONT : TV_V_FRONT);
    wire [9:0]  v_sync   = mode_x_256 ? (native_70hz ? 10'd2 : 10'd3) :
                           mode_x_240 ? (native_70hz ? 10'd2 : 10'd3) :
                           mode_x_640 ? (native_70hz ? 10'd2 : 10'd3)
                                       : (native_70hz ? NATIVE_V_SYNC : TV_V_SYNC);
    // 256x232 uses the 525-line VGA 60 Hz frame: 464 displayed scanlines.
    wire [9:0]  v_total  = native_70hz ? ((mode_x_256 || mode_x_640 || mode_x_240) ? 10'd525
                                                                    : NATIVE_V_TOTAL)
                                           : TV_V_TOTAL;

    // CRT H/V offset (PCXT-EGA.sv OSD), matching how the EGA CRTC applies the
    // same two settings. There, a higher offset takes delay off HSYNC/VSYNC
    // (UM6845R.v hsync_delay_index / vsync_delay_index), which lengthens the
    // sync-to-picture gap that positions the image on a CRT - so a higher
    // offset moves the picture right and down. Shrinking the front porch moves
    // SYNC earlier here for the same effect, and in the same steps the EGA path
    // uses: 4 clocks (2 dots, its 640-wide hres_mode) and 1 line.
    //
    // The porches above are then biased 16 clocks right and 1 line up from
    // pure CGA geometry, measured on a 15 kHz TV, so that the OSD values which
    // centre the EGA path centre this one too and a single setting serves both.
    // H_TOTAL/V_TOTAL are untouched by the offsets, so the TV never loses lock
    // while adjusting.
    wire [10:0] eff_h_front = native_70hz ? h_front : h_front - {5'd0, crt_h_offset, 2'd0};
    wire [9:0]  eff_v_front = native_70hz ? v_front : v_front - {7'd0, crt_v_offset};

    reg [10:0] h_count = 11'd0;
    reg [9:0]  v_count = 10'd0;

    // A live raster change can make the current count larger than the new
    // total. Treat that as the last position too, so Native/60Hz switching
    // recovers at the next line/frame boundary instead of waiting for wrap.
    wire h_last = (h_count >= h_total - 11'd1);
    wire v_last = (v_count >= v_total - 10'd1);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            h_count <= 11'd0;
            v_count <= 10'd0;
        end else if (!enable) begin
            h_count <= 11'd0;
            v_count <= 10'd0;
        end else if (h_last) begin
            h_count <= 11'd0;
            if (v_last)
                v_count <= 10'd0;
            else
                v_count <= v_count + 10'd1;
        end else begin
            h_count <= h_count + 11'd1;
        end
    end

    // Native doubles every source pixel; the 60 Hz profile quadruples it to
    // preserve its 640-pixel active width on the 15 kHz raster. Native also
    // repeats every 200-line source row, yielding the real 640x400 mode 13h
    // image instead of a vertically compressed 640x200 one.
    assign pixel_x = mode_x_640  ? (native_70hz ? h_count[9:0] : h_count[10:1]) :
                     native_70hz ? {1'b0, h_count[10:1]} : {1'b0, h_count[10:2]};
    assign pixel_y = native_line_double ? {1'b0, v_count[9:1]} : v_count;
    assign scan_y  = native_line_double ? v_count : {v_count[8:0], 1'b0};
    assign active = enable && (h_count < h_active) && (v_count < v_active);
    assign hblank = !enable || (h_count >= h_active);
    assign vblank = !enable || (v_count >= v_active);
    assign hsync = enable &&
                   (h_count >= (h_active + eff_h_front)) &&
                   (h_count <  (h_active + eff_h_front + h_sync));
    assign vsync = enable &&
                   (v_count >= (v_active + eff_v_front)) &&
                   (v_count <  (v_active + eff_v_front + v_sync));
    wire [10:0] half_h_total = {1'b0, h_total[10:1]};
    wire [10:0] half_h_active = {1'b0, h_active[10:1]};
    wire status_h_display = native_line_double ? (h_count < h_active) :
                            ((h_count < half_h_active) ||
                             ((h_count >= half_h_total) &&
                              (h_count < half_h_total + half_h_active)));
    assign status_blank = !enable || (v_count >= v_active) || !status_h_display;
    assign line_start = enable && (h_count == 11'd0);
    assign frame_start = line_start && (v_count == 10'd0);

    // pixel_toggle flips once per physical output pixel. Standard Native uses
    // the 28.636 MHz clock on every profile; the 60 Hz profile emits
    // one pixel every two clocks so its 1280 active clocks remain 640 pixels.
    wire [10:0] out_pixel_x = native_70hz ? h_count : {1'b0, h_count[10:1]};

    reg [10:0] out_pixel_x_q = 11'd0;
    wire      pixel_tick = enable && (out_pixel_x != out_pixel_x_q);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            out_pixel_x_q <= 10'd0;
            pixel_toggle  <= 1'b0;
        end else begin
            out_pixel_x_q <= out_pixel_x;
            if (pixel_tick)
                pixel_toggle <= ~pixel_toggle;
        end
    end

endmodule
