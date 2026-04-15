//============================================================================
//
//  PCXT MiSTer EGA digital to analog converter
//
//============================================================================

`default_nettype wire

module ega_vgaport (
    input  wire [5:0] color,
    input  wire       palette_64_mode,
    output reg  [5:0] red,
    output reg  [5:0] green,
    output reg  [5:0] blue
);

    wire [5:0] red_64 = (color[2] ? 6'd42 : 6'd0) + (color[5] ? 6'd21 : 6'd0);
    wire [5:0] green_64 = (color[1] ? 6'd42 : 6'd0) + (color[4] ? 6'd21 : 6'd0);
    wire [5:0] blue_64 = (color[0] ? 6'd42 : 6'd0) + (color[3] ? 6'd21 : 6'd0);

    wire [5:0] red_16 = (color[2] ? 6'd42 : 6'd0) + (color[4] ? 6'd21 : 6'd0);
    wire [5:0] green_16 = (color[1] ? 6'd42 : 6'd0) + (color[4] ? 6'd21 : 6'd0);
    wire [5:0] blue_16 = (color[0] ? 6'd42 : 6'd0) + (color[4] ? 6'd21 : 6'd0);

    always @(*) begin
        if (palette_64_mode) begin
            red = red_64;
            green = green_64;
            blue = blue_64;
        end else if ((color & 6'h17) == 6'h06) begin
            red = 6'd42;
            green = 6'd21;
            blue = 6'd0;
        end else begin
            red = red_16;
            green = green_16;
            blue = blue_16;
        end
    end

endmodule
