//============================================================================
//
//  PCXT MiSTer EGA graphical splash renderer
//
//  The ROM is 320x200 in packed 4-bit EGA pixels. Each source pixel is
//  doubled horizontally to fill the 640-pixel EGA text-timing display.
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
    output reg  [3:0]  pixel_index,
    output reg         pixel_valid
);

    localparam integer SPLASH_WIDTH = 320;
    localparam integer SPLASH_HEIGHT = 200;
    localparam integer SPLASH_BYTES_PER_LINE = SPLASH_WIDTH / 2;
    localparam integer SPLASH_ROM_SIZE = SPLASH_BYTES_PER_LINE * SPLASH_HEIGHT;
    localparam integer SPLASH_ROM_DEPTH = 32768;

    (* ramstyle = "M10K" *) reg [7:0] splash_rom [0:SPLASH_ROM_DEPTH-1];
    reg [9:0] pixel_x = 10'd0;
    reg       display_enable_q = 1'b0;
    reg [7:0] rom_data = 8'h00;
    reg       low_nibble_q = 1'b0;
    reg       pixel_valid_q = 1'b0;

    wire [14:0] line_addr = {scanline[7:0], 7'd0} + {scanline[7:0], 5'd0};
    wire [14:0] rom_addr = line_addr + {7'd0, pixel_x[9:2]};
    wire source_visible = enable && display_enable && (scanline < SPLASH_HEIGHT) &&
                          (pixel_x < (SPLASH_WIDTH * 2));
    wire [14:0] rom_read_addr = source_visible ? rom_addr : 15'd0;

    initial begin
        $readmemh("splash_ega_320x200.hex", splash_rom, 0, SPLASH_ROM_SIZE-1);
    end

    always @(posedge clk) begin
        if (ce_pix)
            rom_data <= splash_rom[rom_read_addr];
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pixel_x <= 10'd0;
            display_enable_q <= 1'b0;
            low_nibble_q <= 1'b0;
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

            low_nibble_q <= pixel_x[1];
            pixel_valid_q <= source_visible;
            pixel_index <= low_nibble_q ? rom_data[3:0] : rom_data[7:4];
            pixel_valid <= pixel_valid_q;
        end
    end

endmodule
