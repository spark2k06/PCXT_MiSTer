//============================================================================
//
//  VGA unchained 256-colour renderer (Mode-X family subset)
//
//  Four consecutive pixels live at the same byte address in planes 0..3.
//  Within the bounded Mode-X profiles, CRTC Offset supplies the row stride,
//  Start Address supplies the scrolling base, Attribute Controller index 13h
//  supplies horizontal pel panning, and Line Compare restarts at address zero.
//    plane   = x modulo 4
//
//============================================================================

// DATA_EXTRA: clocks the plane data arrives later than from the BRAM VRAM
// (SDRAM frontend); everything that travels with the pixel is delayed alike.
module vga_unchained256_renderer #(
    parameter DATA_EXTRA = 0
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        enable,
    input  wire        native_70hz,
    input  wire [2:0]  mode_x_profile,
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

    output wire [7:0]  dac_index,
    input  wire [5:0]  dac_red,
    input  wire [5:0]  dac_green,
    input  wire [5:0]  dac_blue,

    output wire [5:0]  red,
    output wire [5:0]  green,
    output wire [5:0]  blue,
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
    wire frame_start;

    reg [15:0] start_address_latched = 16'h0000;
    wire [1:0] plane_select_q;
    wire       render_en_q;
    wire       timing_pixel_toggle;
    reg        timing_vsync_q = 1'b0;

    // The profiles retain the planar four-pixels-per-byte layout. CRTC Offset
    // is measured in words in this byte-addressed VGA configuration. Dyna
    // Blaster uses 64 (128 bytes per plane row) for a 512-pixel virtual map
    // viewed through its 256-pixel window, and 32 for a direct-width page.
    wire mode_x_360 = (mode_x_profile == 3'd1);
    wire mode_x_256 = (mode_x_profile == 3'd3);
    wire [7:0] profile_stride = mode_x_256 ? 8'd128 :
                                mode_x_360 ? 8'd90 : 8'd80;
    wire offset_in_range = (crtc_offset >= 8'd40) && (crtc_offset <= 8'd45);
    wire [7:0] stride_bytes = mode_x_256 ?
                              ((crtc_offset == 8'd32) ? 8'd64 : 8'd128) :
                              offset_in_range ? {crtc_offset[6:0], 1'b0} :
                                                profile_stride;

    // The CRTC counts physical VGA scanlines and the timing reports which one
    // each output line shows: every second one on the 15 kHz profiles, each of
    // them on the Native line-doubled ones. The line after the compare starts
    // the lower part of the screen at address zero, exactly like VGA.
    // The VGA BIOS baseline deliberately leaves Line Compare at 3ffh, beyond
    // its 400 physical scanlines.  It means "no split".  Treat a compare at
    // or below the visible raster as a real split; without this guard a stale
    // Mode-X compare becomes a bogus lower screen while a program is changing
    // modes or returning to EGA.
    wire [9:0] profile_physical_lines = mode_x_256 ? 10'd464 :
                                        (mode_x_profile == 3'd2) ? 10'd480 :
                                        (mode_x_profile == 3'd4) ? 10'd350 :
                                                                      10'd400;
    wire split_active = (crtc_line_compare < profile_physical_lines);
    wire below_split = split_active && (scan_y > crtc_line_compare);
    wire [10:0] physical_y = {1'b0, scan_y};
    wire [10:0] split_physical_y = {1'b0, crtc_line_compare} + 11'd1;
    wire [10:0] source_physical_y = below_split ?
                                      (physical_y - split_physical_y) : physical_y;
    // R9 bit 7 (Scan Doubling) scans every row twice before Maximum Scan Line
    // repeats it. Pinball Fantasies' 320x240 mode uses R9 = 80h: 480 physical
    // scanlines, 240 source rows, no maximum-scan-line repeat at all.
    wire [10:0] scan_row_y = crtc_double_scan ? {1'b0, source_physical_y[10:1]}
                                              : source_physical_y;

    // Retain the CRTC's 0..7 Maximum Scan Line repeat semantics inside the
    // fixed output raster. Do not use Verilog division here: Quartus combines the four
    // constant divisors into one generic lpm_divide. The reciprocal networks
    // below are exact over the complete 11-bit input range and contain only
    // shifts and additions, so this bounded feature consumes no DSP/divider.
    function [9:0] divide_by_3;
        input [10:0] value;
        reg [20:0] wide;
        begin
            // floor(value / 3) = floor(value * 683 / 2^11), value < 2048.
            wide = ({10'd0, value} << 9) + ({10'd0, value} << 7) +
                   ({10'd0, value} << 5) + ({10'd0, value} << 3) +
                   ({10'd0, value} << 1) +  {10'd0, value};
            divide_by_3 = wide[20:11];
        end
    endfunction

    function [9:0] divide_by_5;
        input [10:0] value;
        reg [21:0] wide;
        begin
            // floor(value / 5) = floor(value * 1639 / 2^13).
            wide = ({11'd0, value} << 10) + ({11'd0, value} << 9) +
                   ({11'd0, value} << 6)  + ({11'd0, value} << 5) +
                   ({11'd0, value} << 2)  + ({11'd0, value} << 1) +
                    {11'd0, value};
            divide_by_5 = wide[21:13];
        end
    endfunction

    function [9:0] divide_by_7;
        input [10:0] value;
        reg [22:0] wide;
        begin
            // floor(value / 7) = floor(value * 2341 / 2^14).
            wide = ({12'd0, value} << 11) + ({12'd0, value} << 8) +
                   ({12'd0, value} << 5)  + ({12'd0, value} << 2) +
                    {12'd0, value};
            divide_by_7 = wide[22:14];
        end
    endfunction

    function [9:0] source_line_from_physical;
        input [10:0] physical_line;
        input [4:0] max_scan;
        begin
            case (max_scan[2:0])
                3'd0: source_line_from_physical = physical_line;
                3'd1: source_line_from_physical = physical_line >> 1;
                3'd2: source_line_from_physical = divide_by_3(physical_line);
                3'd3: source_line_from_physical = physical_line >> 2;
                3'd4: source_line_from_physical = divide_by_5(physical_line);
                3'd5: source_line_from_physical = divide_by_3(physical_line) >> 1;
                3'd6: source_line_from_physical = divide_by_7(physical_line);
                default: source_line_from_physical = physical_line >> 3;
            endcase
        end
    endfunction
    wire [9:0] source_y = source_line_from_physical(scan_row_y,
                                                     crtc_max_scan);

    // Mode-X 320-wide programs use values 0,2,4,6 in the pel-panning
    // register: the VGA dot value is halved to obtain a source pixel shift.
    // Attribute Mode Control bit 5 suppresses that panning below Line Compare.
    wire [2:0] pan_pixels = (below_split && split_panning_suppress) ? 3'd0 :
                                                                    attr_pixel_pan[3:1];
    wire [10:0] source_x = {1'b0, pixel_x} + {8'd0, pan_pixels};

    // Shift/add cases deliberately avoid a variable multiplier and therefore
    // cannot consume a DSP block. All accepted strides are even VGA offsets.
    reg [18:0] row_base;
    always @(*) begin
        case (stride_bytes)
            8'd64: row_base = {3'b0, source_y, 6'b0};
            8'd128: row_base = {2'b0, source_y, 7'b0};
            8'd80: row_base = ({9'b0, source_y} << 6) + ({9'b0, source_y} << 4);
            8'd82: row_base = ({9'b0, source_y} << 6) + ({9'b0, source_y} << 4) + ({9'b0, source_y} << 1);
            8'd84: row_base = ({9'b0, source_y} << 6) + ({9'b0, source_y} << 4) + ({9'b0, source_y} << 2);
            8'd86: row_base = ({9'b0, source_y} << 6) + ({9'b0, source_y} << 4) + ({9'b0, source_y} << 2) + ({9'b0, source_y} << 1);
            8'd88: row_base = ({9'b0, source_y} << 6) + ({9'b0, source_y} << 4) + ({9'b0, source_y} << 3);
            default: row_base = ({9'b0, source_y} << 6) + ({9'b0, source_y} << 4) + ({9'b0, source_y} << 3) + ({9'b0, source_y} << 1);
        endcase
    end
    wire [18:0] pixel_offset = row_base + {10'b0, source_x[10:2]};
    wire [16:0] display_base = below_split ? 17'h00000 : {1'b0, start_address_latched};
    wire [16:0] plane_address = display_base +
                                {1'b0, pixel_offset[15:0]};

    wire [7:0] selected_plane = (plane_select_q == 2'd0) ? vram_plane0 :
                                (plane_select_q == 2'd1) ? vram_plane1 :
                                (plane_select_q == 2'd2) ? vram_plane2 :
                                                                  vram_plane3;

    vga_mode13_timing timing (
        .clock          (clock),
        .reset          (reset),
        .enable         (enable),
        .native_70hz    (native_70hz),
        .mode_x_profile (mode_x_profile),
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
        .frame_start    (frame_start),
        .pixel_toggle   (timing_pixel_toggle)
    );

    assign vram_addr = plane_address[15:0];
    assign vram_read_en = timing_active;
    assign dac_index = vram_data_valid ? selected_plane : 8'h00;
    assign de = vram_data_valid & render_en_q;
    assign red = de ? dac_red : 6'h00;
    assign green = de ? dac_green : 6'h00;
    assign blue = de ? dac_blue : 6'h00;

    pc_delay #(.W(2), .N(1 + DATA_EXTRA), .INIT(0)) u_plane_sel (.clk(clock), .reset(reset), .d(source_x[1:0]), .q(plane_select_q));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(0)) u_render_en (.clk(clock), .reset(reset), .d(vram_read_en), .q(render_en_q));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(0)) u_hsync     (.clk(clock), .reset(reset), .d(timing_hsync),  .q(hsync));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(0)) u_vsync     (.clk(clock), .reset(reset), .d(timing_vsync),  .q(vsync));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(1)) u_hblank    (.clk(clock), .reset(reset), .d(timing_hblank), .q(hblank));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(1)) u_vblank    (.clk(clock), .reset(reset), .d(timing_vblank), .q(vblank));
    pc_delay #(.W(1), .N(DATA_EXTRA),     .INIT(0)) u_ptoggle   (.clk(clock), .reset(reset), .d(timing_pixel_toggle), .q(pixel_toggle));

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            start_address_latched <= 16'h0000;
            timing_vsync_q <= 1'b0;
            status_blank <= 1'b1;
        end else begin
            // VGA latches the display start at vertical retrace. Programs such
            // as Cute Demo write it before polling 3DAh, then write pel
            // panning inside retrace; delaying this until the following frame
            // leaves one visibly mismatched page/pan frame.
            if (timing_vsync && !timing_vsync_q)
                start_address_latched <= crtc_start_address;

            timing_vsync_q <= timing_vsync;
            status_blank <= timing_status_blank;
        end
    end

endmodule
