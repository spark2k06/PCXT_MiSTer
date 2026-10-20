//============================================================================
//
//  VGA mode 13h packed-pixel renderer
//
//============================================================================

// DATA_EXTRA: clocks the framebuffer data arrives later than from the BRAM
// framebuffer (the SDRAM frontend reads ahead and answers at a fixed, longer
// latency). Everything that travels with the pixel is delayed alike, so the
// picture only moves as a whole. 0 is the BRAM timing.
module vga_mode13_renderer #(
    parameter DATA_EXTRA = 0
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        enable,
    input  wire        native_70hz,
    input  wire [3:0]  crt_h_offset,
    input  wire [2:0]  crt_v_offset,

    output wire [15:0] framebuffer_addr,
    output wire        framebuffer_read_en,
    input  wire [7:0]  framebuffer_pixel,
    input  wire        framebuffer_data_valid,

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
    wire timing_active;
    wire timing_hblank;
    wire timing_vblank;
    wire timing_status_blank;
    wire timing_hsync;
    wire timing_vsync;
    wire address_render_en;

    wire render_en_q;
    wire timing_pixel_toggle;

    vga_mode13_timing timing (
        .clock          (clock),
        .reset          (reset),
        .enable         (enable),
        .native_70hz    (native_70hz),
        .mode_x_profile (3'd0),
        .crt_h_offset   (crt_h_offset),
        .crt_v_offset   (crt_v_offset),
        .pixel_x        (pixel_x),
        .pixel_y        (pixel_y),
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

    vga_mode13_address address (
        .pixel_x            (pixel_x),
        .pixel_y            (pixel_y),
        .framebuffer_addr   (framebuffer_addr),
        .render_en          (address_render_en)
    );

    assign framebuffer_read_en = timing_active & address_render_en;
    assign dac_index = framebuffer_data_valid ? framebuffer_pixel : 8'h00;
    assign de = framebuffer_data_valid & render_en_q;
    assign red = de ? dac_red : 6'h00;
    assign green = de ? dac_green : 6'h00;
    assign blue = de ? dac_blue : 6'h00;

    // The BRAM version registers these once, next to the pixel it reads in the
    // same clock; with a longer data path, DATA_EXTRA clocks more.
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(0)) u_render_en (.clk(clock), .reset(reset), .d(framebuffer_read_en), .q(render_en_q));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(0)) u_hsync     (.clk(clock), .reset(reset), .d(timing_hsync),  .q(hsync));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(0)) u_vsync     (.clk(clock), .reset(reset), .d(timing_vsync),  .q(vsync));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(1)) u_hblank    (.clk(clock), .reset(reset), .d(timing_hblank), .q(hblank));
    pc_delay #(.W(1), .N(1 + DATA_EXTRA), .INIT(1)) u_vblank    (.clk(clock), .reset(reset), .d(timing_vblank), .q(vblank));
    pc_delay #(.W(1), .N(DATA_EXTRA),     .INIT(0)) u_ptoggle   (.clk(clock), .reset(reset), .d(timing_pixel_toggle), .q(pixel_toggle));

    always @(posedge clock or posedge reset) begin
        if (reset)
            status_blank <= 1'b1;
        else
            status_blank <= timing_status_blank;
    end

endmodule
