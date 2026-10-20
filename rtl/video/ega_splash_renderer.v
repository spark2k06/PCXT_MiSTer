//============================================================================
//
//  PCXT MiSTer EGA-path graphical splash renderer
//
//  One splash for every card: the ROM is the 320x200, four-colour CGA bitmap
//  (splash_cga_320x200.hex, four 2-bit pixels per byte).  Each source pixel is
//  doubled horizontally to fill the 640-pixel EGA text-timing display, and the
//  four artwork colours go out as EGA palette indexes that hold the CGA RGBI
//  colours in the default attribute palette.
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
    localparam integer SPLASH_BYTES_PER_LINE = SPLASH_WIDTH / 4;
    localparam integer SPLASH_ROM_SIZE = SPLASH_BYTES_PER_LINE * SPLASH_HEIGHT;
    localparam integer SPLASH_ROM_DEPTH = 16384;

    (* ramstyle = "M10K" *) reg [7:0] splash_rom [0:SPLASH_ROM_DEPTH-1];
    reg [9:0] pixel_x = 10'd0;
    reg       display_enable_q = 1'b0;
    reg [7:0] rom_data = 8'h00;
    reg [1:0] source_sel_q = 2'd0;
    reg       pixel_valid_q = 1'b0;

    // 80 bytes per source line.
    wire [14:0] line_addr = {1'b0, scanline[7:0], 6'd0} + {3'b000, scanline[7:0], 4'd0};
    wire [14:0] rom_addr = line_addr + {8'd0, pixel_x[9:3]};
    wire source_visible = enable && display_enable && (scanline < SPLASH_HEIGHT) &&
                          (pixel_x < (SPLASH_WIDTH * 2));
    wire [14:0] rom_read_addr = source_visible ? rom_addr : 15'd0;

    initial begin
        $readmemh("splash_cga_320x200.hex", splash_rom, 0, SPLASH_ROM_SIZE-1);
    end

    // The artwork has four semantic colours: black, red, green and yellow.
    function [3:0] palette_index;
        input [1:0] source_pixel;
        begin
            case (source_pixel)
                2'd0:    palette_index = 4'h0;
                2'd1:    palette_index = 4'hC;
                2'd2:    palette_index = 4'hA;
                default: palette_index = 4'hE;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (ce_pix)
            rom_data <= splash_rom[rom_read_addr];
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pixel_x <= 10'd0;
            display_enable_q <= 1'b0;
            source_sel_q <= 2'd0;
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

            source_sel_q <= pixel_x[2:1];
            pixel_valid_q <= source_visible;
            pixel_index <= palette_index(source_sel_q == 2'd0 ? rom_data[7:6] :
                                         source_sel_q == 2'd1 ? rom_data[5:4] :
                                         source_sel_q == 2'd2 ? rom_data[3:2] :
                                                                rom_data[1:0]);
            pixel_valid <= pixel_valid_q;
        end
    end

endmodule
