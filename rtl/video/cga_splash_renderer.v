//============================================================================
//
//  PCXT MiSTer CGA graphical splash renderer
//
//  The source image is a 320x200, four-colour CGA bitmap.  The boot splash
//  keeps the existing CGA timing, whose active aperture is 1280 clocks wide;
//  each source pixel is therefore held for four 28.636 MHz clocks.  The
//  resulting RGBI stream is still consumed by cga_vgaport, so composite mode
//  sees the real CGA colour transitions and carrier phase.
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
    input  wire       composite,
    output reg  [3:0] pixel_index
);

    localparam integer SPLASH_WIDTH = 320;
    localparam integer SPLASH_HEIGHT = 200;
    localparam integer SPLASH_BYTES_PER_LINE = SPLASH_WIDTH / 4;
    localparam integer SPLASH_ROM_SIZE = SPLASH_BYTES_PER_LINE * SPLASH_HEIGHT;

    // Four 2-bit source pixels per byte.  Keep the array larger than the
    // used area so Quartus can infer the same convenient M10K geometry even
    // if the generated asset is replaced later.
    (* ramstyle = "M10K" *) reg [7:0] splash_rom [0:16383];

    reg [9:0] pixel_x = 10'd0;
    reg [8:0] scanline = 9'd0;
    reg       display_enable_q = 1'b0;
    reg [13:0] rom_read_addr = 14'd0;
    // Keep the RAM result separate from the byte currently being displayed.
    // The inferred M10K may update its registered output between two pixel
    // enables; exposing that result directly would tear the last source pixel
    // of a group while the four-cycle CGA pixel is still being emitted.
    reg [7:0] rom_prefetch_data = 8'h00;
    reg [7:0] rom_data = 8'h00;

    wire pixel_ce = (clkdiv[1:0] == 2'b11);
    wire [6:0] byte_x = pixel_x[9:2];
    wire [13:0] line_addr = scanline * SPLASH_BYTES_PER_LINE;

    initial begin
        $readmemh("splash_cga_320x200.hex", splash_rom, 0, SPLASH_ROM_SIZE-1);
    end

    function [3:0] cga_palette_index;
        input [1:0] source_pixel;
        begin
            // The artwork has four semantic colours: black, red, green and
            // yellow.  CGA RGBI uses C/A/E for bright red/green/yellow; 9 is
            // bright blue, not red.  The composite decoder rotates the hue
            // of the bright-red entry, so use the calibrated dark-red entry
            // there while retaining the correct RGBI palette.
            case (source_pixel)
                2'd0: cga_palette_index = 4'h0;
                2'd1: cga_palette_index = composite ? 4'h4 : 4'hC;
                2'd2: cga_palette_index = 4'hA;
                default: cga_palette_index = 4'hE;
            endcase
        end
    endfunction

    // Keep the ROM read in its own single synchronous port.  The address is
    // updated two pixel enables before the four-pixel group needs it.  This
    // leaves enough time for the registered address and output of an inferred
    // M10K, avoiding a stale byte at each group boundary.
    always @(posedge clk) begin
        if (reset) begin
            rom_read_addr <= 14'd0;
            rom_prefetch_data <= 8'h00;
            rom_data <= 8'h00;
        end else begin
            if (vblank) begin
                rom_read_addr <= 14'd0;
            end else if (!display_enable) begin
                if (display_enable_q) begin
                    if (scanline < SPLASH_HEIGHT-1) begin
                        rom_read_addr <= (scanline + 1'b1) * SPLASH_BYTES_PER_LINE;
                    end else begin
                        rom_read_addr <= 14'd0;
                    end
                end else begin
                    rom_read_addr <= line_addr;
                end
            end else if (enable && pixel_ce) begin
                // Start the next byte read early in the current byte.  This
                // gives the registered M10K result several master clocks to
                // settle before it is latched at the group boundary.
                if (pixel_x[1:0] == 2'b00 && pixel_x < SPLASH_WIDTH-1) begin
                    rom_read_addr <= line_addr + byte_x + 1'b1;
                end
            end

            // The RAM-facing register may change at any master-clock edge,
            // but the video-facing byte must remain stable for all four
            // clocks of a source pixel group.
            rom_prefetch_data <= splash_rom[rom_read_addr];
            if (!display_enable)
                rom_data <= splash_rom[rom_read_addr];
            else if (enable && pixel_ce && pixel_x[1:0] == 2'b11)
                rom_data <= rom_prefetch_data;
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
            case (pixel_x[1:0])
                2'd0: pixel_index = cga_palette_index(rom_data[7:6]);
                2'd1: pixel_index = cga_palette_index(rom_data[5:4]);
                2'd2: pixel_index = cga_palette_index(rom_data[3:2]);
                default: pixel_index = cga_palette_index(rom_data[1:0]);
            endcase
        end
    end

endmodule
