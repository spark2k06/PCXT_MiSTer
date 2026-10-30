//============================================================================
//
//  PCXT MiSTer CGA graphical splash renderer
//
//  The source image is the 320x200, 16-colour splash ROM (splash_rom, port
//  A), two RGBI pixels per byte.  The boot splash keeps the existing CGA
//  timing, whose active aperture is 1280 clocks wide; each source pixel is
//  therefore held for four 28.636 MHz clocks.  The resulting RGBI stream is
//  still consumed by cga_vgaport, so composite mode sees the real CGA colour
//  transitions and carrier phase.
//
//============================================================================

`default_nettype wire

module cga_splash_renderer (
    input  wire       clk,
    input  wire       reset,
    input  wire       enable,
    input  wire [4:0] clkdiv,
    input  wire       display_enable,
    input  wire       vblank,
    output wire [14:0] rom_addr,
    input  wire [7:0] rom_q,
    output reg  [3:0] pixel_index
);

    localparam integer SPLASH_WIDTH = 320;
    localparam integer SPLASH_HEIGHT = 200;
    localparam integer SPLASH_BYTES_PER_LINE = SPLASH_WIDTH / 2;

    reg [9:0] pixel_x = 10'd0;
    reg [8:0] scanline = 9'd0;
    reg       display_enable_q = 1'b0;
    reg [14:0] rom_read_addr = 15'd0;
    // Keep the ROM result (rom_q, registered in the M10K) separate from the
    // byte currently being displayed.  rom_q may change between two pixel
    // enables; exposing it directly would tear the second source pixel of a
    // byte while the four-cycle CGA pixel is still being emitted.
    reg [7:0] rom_data = 8'h00;

    wire pixel_ce = (clkdiv[1:0] == 2'b11);
    wire [8:0] byte_x = pixel_x[9:1];
    wire [14:0] line_addr = scanline * SPLASH_BYTES_PER_LINE;

    assign rom_addr = rom_read_addr;

    // The address is updated one pixel enable before the two-pixel byte
    // needs it, which leaves three master clocks for the registered address
    // and output of the M10K, avoiding a stale byte at each byte boundary.
    always @(posedge clk) begin
        if (reset) begin
            rom_read_addr <= 15'd0;
            rom_data <= 8'h00;
        end else begin
            if (vblank) begin
                rom_read_addr <= 15'd0;
            end else if (!display_enable) begin
                if (display_enable_q) begin
                    if (scanline < SPLASH_HEIGHT-1) begin
                        rom_read_addr <= (scanline + 1'b1) * SPLASH_BYTES_PER_LINE;
                    end else begin
                        rom_read_addr <= 15'd0;
                    end
                end else begin
                    rom_read_addr <= line_addr;
                end
            end else if (enable && pixel_ce) begin
                // Start the next byte read early in the current byte.  This
                // gives the registered M10K result several master clocks to
                // settle before it is latched at the group boundary.
                if (pixel_x[0] == 1'b0 && pixel_x < SPLASH_WIDTH-1) begin
                    rom_read_addr <= line_addr + byte_x + 1'b1;
                end
            end

            // rom_q may change at any master-clock edge, but the
            // video-facing byte must remain stable for both source pixels.
            if (!display_enable)
                rom_data <= rom_q;
            else if (enable && pixel_ce && pixel_x[0] == 1'b1)
                rom_data <= rom_q;
        end
    end

    // Track the source position independently from the synchronous ROM read.
    always @(posedge clk) begin
        if (reset) begin
            pixel_x <= 10'd0;
            scanline <= 9'd0;
            display_enable_q <= 1'b0;
        end else begin
            display_enable_q <= display_enable;

            if (vblank) begin
                scanline <= 9'd0;
                pixel_x <= 10'd0;
            end else if (!display_enable) begin
                pixel_x <= 10'd0;
                if (display_enable_q && scanline < SPLASH_HEIGHT-1)
                    scanline <= scanline + 1'b1;
            end else if (enable && pixel_ce && pixel_x < SPLASH_WIDTH-1) begin
                pixel_x <= pixel_x + 1'b1;
            end
        end
    end

    always @(*) begin
        if (!enable || !display_enable || scanline >= SPLASH_HEIGHT) begin
            pixel_index = 4'h0;
        end else begin
            // The ROM holds RGBI indexes: they go out unchanged.
            pixel_index = pixel_x[0] ? rom_data[3:0] : rom_data[7:4];
        end
    end

endmodule
