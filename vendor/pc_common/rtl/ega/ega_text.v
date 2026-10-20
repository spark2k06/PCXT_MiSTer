//============================================================================
//
//  PCXT MiSTer EGA text cell pipeline
//
//  Memory side (shared library version). The character cell is asked for with
//  text_fetch_en at each character tick, together with the scanline and the
//  cursor flag (text_tag) it will be drawn with. The frontend answers one fixed
//  latency later, in a single event, with the cell (character, attribute), the
//  glyph row that goes with it (it reads the font itself: the address depends
//  on the character) and the tag that travelled along (text_data_valid).
//  Answers can overlap the next requests; there is no handshake.
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
    input  wire        char_9dot,
    input  wire        blink_enable,
    input  wire        blink_state,
    input  wire        mono_attributes,
    input  wire        line_graphics_enable,
    input  wire        cursor_active,
    input  wire [15:0] crtc_addr,
    input  wire [4:0]  scanline,
    input  wire [4:0]  underline_scanline,
    input  wire [7:0]  text_char_in,
    input  wire [7:0]  text_attr_in,
    input  wire [7:0]  text_glyph_in,
    input  wire        text_tag_in,
    input  wire        text_data_valid,
    output reg  [15:0] text_cell_addr,
    output reg  [4:0]  text_scanline,
    output reg         text_tag,
    output reg         text_fetch_en,
    output reg  [3:0]  plane_index,
    output reg         pixel_valid
);

    reg [7:0] attr_latch = 8'h00;
    reg [8:0] glyph_shift = 9'h000;
    reg       dot_repeat = 1'b0;
    reg       cursor_latch = 1'b0;

    wire       start_cell = display_enable && fetch_tick;
    wire [7:0] active_text_glyph = text_glyph_in;
    wire       glyph_pixel = glyph_shift[8];
    wire       pending_line_graphics_char = (text_char_in[7:5] == 3'b110);

    wire       pending_ninth_dot = char_9dot && line_graphics_enable &&
                                   pending_line_graphics_char && active_text_glyph[0];
    wire [3:0] foreground_index = attr_latch[3:0];
    wire [3:0] background_index = blink_enable ? {1'b0, attr_latch[6:4]} : attr_latch[7:4];
    wire [3:0] visible_foreground_index =
        (blink_enable && attr_latch[7] && blink_state) ? background_index : foreground_index;
    wire       cursor_visible = cursor_latch && blink_state;
    wire [3:0] cursor_foreground_index = attr_latch[7:4];
    wire [3:0] cursor_background_index = attr_latch[3:0];
    wire [3:0] active_foreground_index = cursor_visible ? cursor_foreground_index :
                                                         visible_foreground_index;
    wire [3:0] active_background_index = cursor_visible ? cursor_background_index :
                                                         background_index;
    wire       mono_blink_active = !cursor_visible && blink_enable && attr_latch[7] && blink_state;
    wire       mono_underline = mono_attributes && (scanline == underline_scanline) &&
                                (attr_latch[2:0] == 3'b001);
    wire [3:0] mono_bit_index = mono_attr_index(attr_latch, mono_blink_active, glyph_pixel);
    wire [3:0] mono_base_index = mono_underline ?
                                 mono_attr_index(attr_latch, mono_blink_active, 1'b1) :
                                 mono_bit_index;
    wire [3:0] mono_cursor_xor_index = mono_attr_index(attr_latch, 1'b0, 1'b1);
    wire [3:0] mono_active_index = cursor_visible ? (mono_base_index ^ mono_cursor_xor_index) :
                                                   mono_base_index;
    wire [3:0] color_active_index = glyph_pixel ? active_foreground_index : active_background_index;
    // Horizontal Pel Panning is not applied here: ega_top delays the finished
    // dot stream, which is the one place text, graphics and the splash all pass
    // through, so a single implementation covers every mode.
    wire [3:0] cell_index = mono_attributes ? mono_active_index : color_active_index;

    // The mono table follows x86Box's MDA-style EGA attribute handling:
    // selected attributes force black/white pairs before cursor XOR.
    function [3:0] mono_attr_index;
        input [7:0] attr;
        input       blink;
        input       foreground;
        begin
            if (!foreground) begin
                if ((attr == 8'h70) || (attr == 8'hF0) ||
                    (attr == 8'h78) || (attr == 8'hF8))
                    mono_attr_index = 4'hF;
                else
                    mono_attr_index = 4'h0;
            end else if ((attr == 8'h00) || (attr == 8'h08) ||
                         (attr == 8'h80) || (attr == 8'h88)) begin
                mono_attr_index = 4'h0;
            end else if ((attr == 8'h70) || (attr == 8'hF0)) begin
                mono_attr_index = blink ? 4'hF : 4'h0;
            end else if ((attr == 8'h78) || (attr == 8'hF8)) begin
                mono_attr_index = blink ? 4'hF : 4'h7;
            end else begin
                mono_attr_index = blink ? 4'h0 : (attr[3] ? 4'hF : 4'h7);
            end
        end
    endfunction

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            attr_latch <= 8'h00;
            glyph_shift <= 9'h000;
            dot_repeat <= 1'b0;
            cursor_latch <= 1'b0;
            text_cell_addr <= 16'h0000;
            text_scanline <= 5'd0;
            text_tag <= 1'b0;
            text_fetch_en <= 1'b0;
            plane_index <= 4'h0;
            pixel_valid <= 1'b0;
        end else begin
            text_fetch_en <= 1'b0;

            if (text_data_valid) begin
                attr_latch <= text_attr_in;
                glyph_shift <= {active_text_glyph, pending_ninth_dot};
                cursor_latch <= text_tag_in;
                dot_repeat <= 1'b0;
            end

            if (ce_pix) begin
                if (!display_enable) begin
                    glyph_shift <= 9'h000;
                    dot_repeat <= 1'b0;
                    cursor_latch <= 1'b0;
                    plane_index <= 4'h0;
                    pixel_valid <= 1'b0;
                end else begin
                    if (start_cell) begin
                        text_cell_addr <= crtc_addr;
                        text_scanline <= scanline;
                        text_tag <= cursor_active;
                        text_fetch_en <= 1'b1;
                    end

                    plane_index <= cell_index;
                    pixel_valid <= 1'b1;

                    if (!text_data_valid) begin
                        if (dot_clock_div2) begin
                            dot_repeat <= ~dot_repeat;
                            if (dot_repeat)
                                glyph_shift <= {glyph_shift[7:0], 1'b0};
                        end else begin
                            dot_repeat <= 1'b0;
                            glyph_shift <= {glyph_shift[7:0], 1'b0};
                        end
                    end
                end
            end
        end
    end

endmodule
