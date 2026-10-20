//============================================================================
//
//  Bounded VGA planar 16-colour renderer: 320x200 and 640x480
//
//  This is the VGA counterpart of the core's fixed Mode-X output profiles,
//  not a generic programmable VGA CRTC. It keeps the established Native/60Hz
//  rasters while honouring the display controls used by scrolling VGA
//  planar software: Start Address, Offset, Horizontal Pel Panning and
//  Line Compare split-screen restart.
//
//  wide_640 selects VGA mode 12h's geometry instead of mode 0Dh's: one source
//  pixel per output pixel, 80-byte rows and 480 physical scanlines, of which
//  R9 Scan Doubling and Maximum Scan Line select the source rows. Pinball
//  Fantasies shows its logo at 640x480 (R9 = 40h) and its menu at 640x240
//  (R9 = C0h) this way.
//
//============================================================================

// DATA_EXTRA: clocks the plane data arrives later than from the BRAM VRAM
// (SDRAM frontend); everything that travels with the pixel is delayed alike.
module vga_planar16_renderer #(
    parameter DATA_EXTRA = 0
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        enable,
    input  wire        native_70hz,
    input  wire        wide_640,
    input  wire [3:0]  crt_h_offset,
    input  wire [2:0]  crt_v_offset,
    input  wire [15:0] crtc_start_address,
    input  wire [7:0]  crtc_offset,
    input  wire [9:0]  crtc_line_compare,
    input  wire [4:0]  crtc_max_scan,
    input  wire        crtc_double_scan,
    input  wire [3:0]  attr_pixel_pan,
    input  wire        split_panning_suppress,

    output wire [15:0] vram_addr,
    output wire        vram_read_en,
    input  wire [7:0]  vram_plane0,
    input  wire [7:0]  vram_plane1,
    input  wire [7:0]  vram_plane2,
    input  wire [7:0]  vram_plane3,
    input  wire        vram_data_valid,

    output wire [3:0]  plane_index,
    output wire        pixel_valid,
    output wire        de,
    output wire        hsync,
    output wire        vsync,
    output wire        hblank,
    output wire        vblank,
    output reg         status_blank,
    output wire        pixel_toggle
);

    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire [9:0] scan_y;
    wire timing_active;
    wire timing_hblank;
    wire timing_vblank;
    wire timing_status_blank;
    wire timing_hsync;
    wire timing_vsync;

    reg [15:0] start_address_latched = 16'h0000;
    wire [2:0] bit_select_q;
    wire [2:0] bit_select_q2;
    wire       render_en_q;
    wire       render_en_q2;
    wire       timing_pixel_toggle;
    reg        timing_vsync_q = 1'b0;

    //------------------------------------------------------------------------
    // 320x200 (mode 0Dh)
    //------------------------------------------------------------------------

    // In VGA byte mode the CRTC Offset is in words. Standard mode 0Dh uses
    // 20 (40 bytes); scrolling variants commonly use 21..23. Keep this
    // deliberately narrow and fall back to the BIOS stride outside it.
    wire offset_in_range = (crtc_offset >= 8'd20) &&
                           (crtc_offset <= 8'd23);
    wire [7:0] stride_bytes = offset_in_range ?
                              {crtc_offset[6:0], 1'b0} : 8'd40;

    // VGA Line Compare restarts the display address at zero on the following
    // physical scanline. The fixed 320x200 raster samples one line from each
    // doubled pair, hence the first lower output line is
    // ceil((LineCompare + 1) / 2). This is the split-screen arrangement used
    // by Viking Child: the scrolling playfield starts at 2000h while the
    // fixed control panel remains at address zero.
    wire split_active = (crtc_line_compare < 10'd400);
    wire [10:0] line_compare_plus_two = {1'b0, crtc_line_compare} + 11'd2;
    wire [9:0] split_start_y = line_compare_plus_two[10:1];
    wire below_split = split_active && (pixel_y >= split_start_y);
    wire [10:0] physical_y = {pixel_y, 1'b0};
    wire [10:0] split_physical_y = {1'b0, crtc_line_compare} + 11'd1;
    wire [10:0] source_physical_y = below_split ?
                                      (physical_y - split_physical_y) : physical_y;
    wire [9:0] source_y = source_physical_y[10:1];

    //------------------------------------------------------------------------
    // 640x480 (mode 12h)
    //------------------------------------------------------------------------

    // The timing reports the physical scanline itself: every one on Native,
    // every second one on the 15 kHz raster.
    wire wide_split_active = (crtc_line_compare < 10'd480);
    wire wide_below_split = wide_split_active && (scan_y > crtc_line_compare);
    wire [9:0] wide_physical_y = wide_below_split ?
                                 (scan_y - crtc_line_compare - 10'd1) : scan_y;
    // Scan Doubling halves first. Maximum Scan Line is accepted where its
    // repeat count is a power of two (0, 1, 3, 7); mode 12h software uses 0.
    wire [9:0] wide_doubled_y = crtc_double_scan ? {1'b0, wide_physical_y[9:1]}
                                                 : wide_physical_y;
    reg  [9:0] wide_source_y;
    always @(*) begin
        case (crtc_max_scan[2:0])
            3'd1: wide_source_y = {1'b0, wide_doubled_y[9:1]};
            3'd3: wide_source_y = {2'b0, wide_doubled_y[9:2]};
            3'd7: wide_source_y = {3'b0, wide_doubled_y[9:3]};
            default: wide_source_y = wide_doubled_y;
        endcase
    end

    // Mode 12h uses Offset 40 (80 bytes); 41..47 give the wider virtual rows
    // of scrolling software. row * stride is 80 * row plus up to 14 * row,
    // all shifts and adds: no multiplier is inferred.
    wire wide_offset_in_range = (crtc_offset >= 8'd40) && (crtc_offset <= 8'd47);
    wire [2:0] wide_extra_words = wide_offset_in_range ? crtc_offset[2:0] : 3'd0;
    wire [17:0] wide_y = {8'b0, wide_source_y};
    wire [17:0] wide_row_base = (wide_y << 6) + (wide_y << 4) +
                                (wide_extra_words[0] ? (wide_y << 1) : 18'd0) +
                                (wide_extra_words[1] ? (wide_y << 2) : 18'd0) +
                                (wide_extra_words[2] ? (wide_y << 3) : 18'd0);

    //------------------------------------------------------------------------
    // Shared address generation
    //------------------------------------------------------------------------

    wire below_any_split = wide_640 ? wide_below_split : below_split;

    // Attribute Mode Control bit 5 resets pel panning below Line Compare.
    wire [2:0] pan_pixels = (below_any_split && split_panning_suppress) ? 3'd0 :
                                                                          attr_pixel_pan[2:0];
    wire [10:0] source_x = {1'b0, pixel_x} + {8'd0, pan_pixels};

    // The accepted strides are 40, 42, 44 and 46 bytes. Explicit shift/add
    // cases keep this small and prevent inference of a generic multiplier.
    reg [17:0] row_base;
    always @(*) begin
        case (stride_bytes)
            8'd40: row_base = ({8'b0, source_y} << 5) +
                               ({8'b0, source_y} << 3);
            8'd42: row_base = ({8'b0, source_y} << 5) +
                               ({8'b0, source_y} << 3) +
                               ({8'b0, source_y} << 1);
            8'd44: row_base = ({8'b0, source_y} << 5) +
                               ({8'b0, source_y} << 3) +
                               ({8'b0, source_y} << 2);
            default: row_base = ({8'b0, source_y} << 5) +
                                ({8'b0, source_y} << 3) +
                                ({8'b0, source_y} << 2) +
                                ({8'b0, source_y} << 1);
        endcase
    end

    wire [17:0] byte_offset = (wide_640 ? wide_row_base : row_base) +
                              {10'b0, source_x[10:3]};
    wire [16:0] display_base = below_any_split ? 17'h00000 :
                                                {1'b0, start_address_latched};
    wire [16:0] plane_address = display_base +
                                {1'b0, byte_offset[15:0]};

    vga_mode13_timing timing (
        .clock          (clock),
        .reset          (reset),
        .enable         (enable),
        .native_70hz    (native_70hz),
        .mode_x_profile (wide_640 ? 3'd5 : 3'd0),
        .crt_h_offset   (crt_h_offset),
        .crt_v_offset   (crt_v_offset),
        .pixel_x        (pixel_x),
        .pixel_y        (pixel_y),
        .scan_y         (scan_y),
        .active         (timing_active),
        .hblank         (timing_hblank),
        .vblank         (timing_vblank),
        .hsync          (timing_hsync),
        .vsync          (timing_vsync),
        .status_blank   (timing_status_blank),
        .line_start     (),
        .frame_start    (),
        .pixel_toggle   (timing_pixel_toggle)
    );

    // Plane data returns two clocks after its address. The 320-pixel path
    // has two or four clocks per pixel and keeps its established one-clock
    // bit select; at 640 a Native pixel is one clock wide, so the select must
    // follow the data's full two-clock latency or each byte's first pixel
    // would show the previous byte. The render enable follows the same delay,
    // keeping the last pixel of each line.
    wire [2:0] bit_select = wide_640 ? bit_select_q2 : bit_select_q;

    assign vram_addr = plane_address[15:0];
    assign vram_read_en = timing_active;
    assign plane_index = vram_data_valid ?
                         {vram_plane3[bit_select],
                          vram_plane2[bit_select],
                          vram_plane1[bit_select],
                          vram_plane0[bit_select]} : 4'h0;
    assign pixel_valid = vram_data_valid & (wide_640 ? render_en_q2 : render_en_q);
    assign de = pixel_valid;

    pc_delay #(.W(3), .N(1 + DATA_EXTRA), .INIT(7)) u_bit_sel  (.clk(clock), .reset(reset), .d(3'd7 - source_x[2:0]), .q(bit_select_q));
    pc_delay #(.W(3), .N(1),              .INIT(7)) u_bit_sel2 (.clk(clock), .reset(reset), .d(bit_select_q), .q(bit_select_q2));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(0)) u_render_en  (.clk(clock), .reset(reset), .d(vram_read_en), .q(render_en_q));
    pc_delay #(.W(1), .N(1),              .INIT(0)) u_render_en2 (.clk(clock), .reset(reset), .d(render_en_q), .q(render_en_q2));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(0)) u_hsync   (.clk(clock), .reset(reset), .d(timing_hsync),  .q(hsync));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(0)) u_vsync   (.clk(clock), .reset(reset), .d(timing_vsync),  .q(vsync));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(1)) u_hblank  (.clk(clock), .reset(reset), .d(timing_hblank), .q(hblank));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(1)) u_vblank  (.clk(clock), .reset(reset), .d(timing_vblank), .q(vblank));
    pc_delay #(.W(1), .N(DATA_EXTRA),     .INIT(0)) u_ptoggle (.clk(clock), .reset(reset), .d(timing_pixel_toggle), .q(pixel_toggle));

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            start_address_latched <= 16'h0000;
            timing_vsync_q <= 1'b0;
            status_blank <= 1'b1;
        end else begin
            if (timing_vsync && !timing_vsync_q)
                start_address_latched <= crtc_start_address;

            timing_vsync_q <= timing_vsync;
            status_blank <= timing_status_blank;
        end
    end

endmodule
