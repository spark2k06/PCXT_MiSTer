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
    input  wire        char_9dot,
    input  wire [3:0]  h_pixel_pan,
    input  wire        blink_enable,
    input  wire        blink_state,
    input  wire        mono_attributes,
    input  wire        line_graphics_enable,
    input  wire        cursor_active,
    input  wire [15:0] crtc_addr,
    input  wire [4:0]  scanline,
    input  wire [4:0]  underline_scanline,
    input  wire [1:0]  char_map_a,
    input  wire [1:0]  char_map_b,
    input  wire [7:0]  text_char_in,
    input  wire [7:0]  text_attr_in,
    input  wire [7:0]  text_glyph_in,
    input  wire        text_data_valid,
    input  wire        splash_font_enable,
    output reg  [15:0] text_cell_addr,
    output reg  [15:0] text_font_addr,
    output reg         text_fetch_en,
    output reg  [3:0]  plane_index,
    output reg         pixel_valid
);

    reg [7:0] attr_latch = 8'h00;
    reg [7:0] char_pending = 8'h00;
    reg [7:0] attr_pending = 8'h00;
    reg [8:0] glyph_shift = 9'h000;
    reg       dot_repeat = 1'b0;
    reg       cursor_latch = 1'b0;
    reg       cursor_pending = 1'b0;
    reg       display_enable_q = 1'b0;
    reg [3:0] pan_cache = 4'd0;
    reg [31:0] pan_history = 32'h00000000;
    reg [1:0] fetch_state = 2'd0;
    reg [7:0] splash_char_rom[0:4095];

    initial begin
        $readmemh("cga.hex", splash_char_rom, 0, 4095);
    end

    wire       start_cell = display_enable && fetch_tick;
    wire [1:0] pending_font_bank = text_attr_in[3] ? char_map_b : char_map_a;
    wire [7:0] splash_glyph =
        (scanline < 5'd8) ? splash_char_rom[{1'b1, char_pending, scanline[2:0]}] : 8'h00;
    wire [7:0] active_text_glyph = splash_font_enable ? splash_glyph : text_glyph_in;
    wire       glyph_pixel = glyph_shift[8];
    wire       pending_line_graphics_char = (char_pending[7:5] == 3'b110);
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
    wire [3:0] unpanned_index = mono_attributes ? mono_active_index : color_active_index;
    wire [3:0] sanitized_pan = h_pixel_pan[3] ? 4'd0 : h_pixel_pan;
    wire [3:0] active_pan = (display_enable && !display_enable_q) ? sanitized_pan : pan_cache;
    wire [3:0] panned_index = (active_pan == 4'd0) ? unpanned_index :
                              pan_history_pixel(pan_history, active_pan - 4'd1);

    function [3:0] pan_history_pixel;
        input [31:0] history;
        input [3:0]  index;
        begin
            case (index[2:0])
                3'd0: pan_history_pixel = history[3:0];
                3'd1: pan_history_pixel = history[7:4];
                3'd2: pan_history_pixel = history[11:8];
                3'd3: pan_history_pixel = history[15:12];
                3'd4: pan_history_pixel = history[19:16];
                3'd5: pan_history_pixel = history[23:20];
                3'd6: pan_history_pixel = history[27:24];
                3'd7: pan_history_pixel = history[31:28];
            endcase
        end
    endfunction

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
            char_pending <= 8'h00;
            attr_pending <= 8'h00;
            glyph_shift <= 9'h000;
            dot_repeat <= 1'b0;
            cursor_latch <= 1'b0;
            cursor_pending <= 1'b0;
            display_enable_q <= 1'b0;
            pan_cache <= 4'd0;
            pan_history <= 32'h00000000;
            fetch_state <= 2'd0;
            text_cell_addr <= 16'h0000;
            text_font_addr <= 16'h0000;
            text_fetch_en <= 1'b0;
            plane_index <= 4'h0;
            pixel_valid <= 1'b0;
        end else begin
            text_fetch_en <= 1'b0;

            if (text_data_valid) begin
                if (fetch_state == 2'd1) begin
                    char_pending <= text_char_in;
                    attr_pending <= text_attr_in;
                    text_font_addr <= {pending_font_bank, 14'b00000000000000} +
                                      {3'b000, text_char_in, 5'b00000} +
                                      {11'd0, scanline};
                    text_fetch_en <= 1'b1;
                    fetch_state <= 2'd2;
                end else if (fetch_state == 2'd2) begin
                    attr_latch <= attr_pending;
                    glyph_shift <= {active_text_glyph, pending_ninth_dot};
                    cursor_latch <= cursor_pending;
                    dot_repeat <= 1'b0;
                    fetch_state <= 2'd0;
                end
            end

            if (ce_pix) begin
                display_enable_q <= display_enable;

                if (!display_enable) begin
                    glyph_shift <= 9'h000;
                    dot_repeat <= 1'b0;
                    cursor_latch <= 1'b0;
                    cursor_pending <= 1'b0;
                    fetch_state <= 2'd0;
                    pan_cache <= 4'd0;
                    pan_history <= 32'h00000000;
                    plane_index <= 4'h0;
                    pixel_valid <= 1'b0;
                end else begin
                    if (!display_enable_q) begin
                        pan_cache <= sanitized_pan;
                        pan_history <= {28'h0000000, unpanned_index};
                    end else begin
                        pan_history <= {pan_history[27:0], unpanned_index};
                    end

                    if (start_cell && ((fetch_state == 2'd0) ||
                        ((fetch_state == 2'd2) && text_data_valid))) begin
                        text_cell_addr <= crtc_addr;
                        text_fetch_en <= 1'b1;
                        cursor_pending <= cursor_active;
                        fetch_state <= 2'd1;
                    end

                    plane_index <= panned_index;
                    pixel_valid <= 1'b1;

                    if (!(text_data_valid && (fetch_state == 2'd2))) begin
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
