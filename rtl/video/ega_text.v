//============================================================================
//
//  PCXT MiSTer EGA text cell pipeline
//
//============================================================================

`default_nettype wire

module ega_text (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_pix,
    input  wire        fetch_tick,
    input  wire        display_enable,
    input  wire [15:0] crtc_addr,
    input  wire [4:0]  scanline,
    input  wire [7:0]  text_char_in,
    input  wire [7:0]  text_attr_in,
    input  wire [7:0]  text_glyph_in,
    input  wire        text_data_valid,
    output reg  [15:0] text_cell_addr,
    output reg  [15:0] text_font_addr,
    output reg         text_fetch_en,
    output reg  [3:0]  plane_index,
    output reg         pixel_valid
);

    reg [7:0] char_latch = 8'h00;
    reg [7:0] attr_latch = 8'h00;
    reg [7:0] glyph_latch = 8'h00;

    wire       start_cell = display_enable && fetch_tick;
    wire       glyph_pixel_seed = glyph_latch[7];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            char_latch <= 8'h00;
            attr_latch <= 8'h00;
            glyph_latch <= 8'h00;
            text_cell_addr <= 16'h0000;
            text_font_addr <= 16'h0000;
            text_fetch_en <= 1'b0;
            plane_index <= 4'h0;
            pixel_valid <= 1'b0;
        end else begin
            text_fetch_en <= 1'b0;

            if (text_data_valid) begin
                char_latch <= text_char_in;
                attr_latch <= text_attr_in;
                glyph_latch <= text_glyph_in;
            end

            if (ce_pix) begin
                if (!display_enable) begin
                    plane_index <= 4'h0;
                    pixel_valid <= 1'b0;
                end else begin
                    if (start_cell) begin
                        text_cell_addr <= crtc_addr;
                        text_font_addr <= {3'b000, char_latch, 5'b00000} + {11'd0, scanline};
                        text_fetch_en <= 1'b1;
                    end

                    // EGA-603 establishes the character/attribute cell
                    // pipeline. Full glyph and attribute color generation are
                    // implemented by the following text renderer tasks.
                    plane_index <= glyph_pixel_seed ? attr_latch[3:0] : attr_latch[7:4];
                    pixel_valid <= 1'b1;
                end
            end
        end
    end

endmodule
