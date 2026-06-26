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
    input  wire        dot_clock_div2,
    input  wire        blink_enable,
    input  wire        blink_state,
    input  wire [15:0] crtc_addr,
    input  wire [4:0]  scanline,
    input  wire [1:0]  char_map_a,
    input  wire [1:0]  char_map_b,
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
    reg [7:0] glyph_shift = 8'h00;
    reg       dot_repeat = 1'b0;

    wire       start_cell = display_enable && fetch_tick;
    wire [1:0] font_bank = attr_latch[3] ? char_map_b : char_map_a;
    wire       glyph_pixel = glyph_shift[7];
    wire [3:0] foreground_index = attr_latch[3:0];
    wire [3:0] background_index = blink_enable ? {1'b0, attr_latch[6:4]} : attr_latch[7:4];
    wire [3:0] visible_foreground_index =
        (blink_enable && attr_latch[7] && blink_state) ? background_index : foreground_index;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            char_latch <= 8'h00;
            attr_latch <= 8'h00;
            glyph_shift <= 8'h00;
            dot_repeat <= 1'b0;
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
                glyph_shift <= text_glyph_in;
                dot_repeat <= 1'b0;
            end

            if (ce_pix) begin
                if (!display_enable) begin
                    glyph_shift <= 8'h00;
                    dot_repeat <= 1'b0;
                    plane_index <= 4'h0;
                    pixel_valid <= 1'b0;
                end else begin
                    if (start_cell) begin
                        text_cell_addr <= crtc_addr;
                        text_font_addr <= {font_bank, 14'b00000000000000} +
                                          {3'b000, char_latch, 5'b00000} +
                                          {11'd0, scanline};
                        text_fetch_en <= 1'b1;
                    end

                    plane_index <= glyph_pixel ? visible_foreground_index : background_index;
                    pixel_valid <= 1'b1;

                    if (!text_data_valid) begin
                        if (dot_clock_div2) begin
                            dot_repeat <= ~dot_repeat;
                            if (dot_repeat)
                                glyph_shift <= {glyph_shift[6:0], 1'b0};
                        end else begin
                            dot_repeat <= 1'b0;
                            glyph_shift <= {glyph_shift[6:0], 1'b0};
                        end
                    end
                end
            end
        end
    end

endmodule
