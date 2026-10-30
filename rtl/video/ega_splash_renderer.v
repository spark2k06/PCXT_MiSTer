//============================================================================
//
//  PCXT MiSTer EGA-path graphical splash renderer
//
//  One splash for every card: the ROM is the 320x200, 16-colour picture
//  (splash_rom, port B, two 4-bit RGBI pixels per byte).  Each source pixel is
//  doubled horizontally to fill the 640-pixel EGA text-timing display, and the
//  RGBI value goes out as the EGA palette index that holds the same colour in
//  the default attribute palette.
//
//============================================================================

`default_nettype wire

module ega_splash_renderer (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_pix,
    input  wire        enable,
    input  wire        display_enable,
    input  wire [9:0]  scanline,
    output wire [14:0] rom_addr,
    input  wire [7:0]  rom_q,           // registered every clock, one clock after rom_addr
    output reg  [3:0]  pixel_index,
    output reg         pixel_valid
);

    localparam integer SPLASH_WIDTH = 320;
    localparam integer SPLASH_HEIGHT = 200;
    reg [9:0] pixel_x = 10'd0;
    reg       display_enable_q = 1'b0;
    reg       source_sel_q = 1'b0;
    reg       pixel_valid_q = 1'b0;

    // 160 bytes per source line, four dots per byte.
    wire [14:0] line_addr = {scanline[7:0], 7'd0} + {2'b00, scanline[7:0], 5'd0};
    wire [14:0] byte_addr = line_addr + {7'd0, pixel_x[9:2]};
    wire source_visible = enable && display_enable && (scanline < SPLASH_HEIGHT) &&
                          (pixel_x < (SPLASH_WIDTH * 2));
    wire [14:0] read_addr = source_visible ? byte_addr : 15'd0;

    // The ROM port has no enable (see splash_rom), so its output would move
    // on every clock.  Between two dots it is given the address of the last
    // dot again: rom_q then holds the byte read on ce_pix, whatever the
    // spacing of the dot clock enables.
    reg [14:0] rom_addr_last = 15'd0;
    always @(posedge clk)
        if (ce_pix)
            rom_addr_last <= read_addr;

    assign rom_addr = ce_pix ? read_addr : rom_addr_last;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pixel_x <= 10'd0;
            display_enable_q <= 1'b0;
            source_sel_q <= 1'b0;
            pixel_valid_q <= 1'b0;
            pixel_index <= 4'h0;
            pixel_valid <= 1'b0;
        end else if (ce_pix) begin
            display_enable_q <= display_enable;

            if (!display_enable)
                pixel_x <= 10'd0;
            else if (!display_enable_q)
                pixel_x <= 10'd1;
            else
                pixel_x <= pixel_x + 10'd1;

            source_sel_q <= pixel_x[1];
            pixel_valid_q <= source_visible;
            pixel_index <= source_sel_q ? rom_q[3:0] : rom_q[7:4];
            pixel_valid <= pixel_valid_q;
        end
    end

endmodule
