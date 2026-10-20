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
        // The brown fix. In the 16 colour interpretation bits 3 and 5 carry no
        // weight at all, so every value that agrees with 06h on the bits that
        // do - 06h, 0Eh, 26h and 2Eh - is the same dark yellow and all four
        // have to become brown. 86Box masks with 17h for exactly this reason;
        // matching only 06h left the other three yellow, which a 64 entry
        // gradient walks straight through.
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

// The IBM 5151 does not consume RGB from the EGA connector. Pin 7 carries
// monochrome video (EGA colour-code bit 3) and pin 6 carries its intensity
// (bit 4). Keep this conversion separate from ega_vgaport so both text mode 7
// and graphics mode 0Fh retain the two authentic monochrome levels.
module ega_5151_output (
    input  wire [5:0] color,
    output wire [5:0] luma
);

    assign luma = !color[3] ? 6'd0 :
                  color[4]  ? 6'd63 : 6'd42;

endmodule
