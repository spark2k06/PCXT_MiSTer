// Graphics Gremlin
//
// Copyright (c) 2021 Eric Schlaepfer
// This work is licensed under the Creative Commons Attribution-ShareAlike 4.0
// International License. To view a copy of this license, visit
// http://creativecommons.org/licenses/by-sa/4.0/ or send a letter to Creative
// Commons, PO Box 1866, Mountain View, CA 94042, USA.
//
`default_nettype wire
module cga_pixel(
    input clk,
    input[4:0] clk_seq,
    input hres_mode,
    input grph_mode,
    input bw_mode,
    input mode_640,
    input tandy_16_mode,
    input thin_font,
    input[7:0] vram_data,
    input vram_read_char,
    input vram_read_att,
    input disp_pipeline,
    input charrom_read,
    input display_enable,
    input cursor,
    input[4:0] row_addr,
    input blink_enabled,
    input blink,
    input hsync,
    input vsync,
    input video_enabled,
    input[7:0] cga_color_reg,
    input[3:0] tandy_palette_color,
    input[3:0] tandy_newcolor,
    input tandy_palette_set,
    input[3:0] tandy_bordercol,
	 input tandy_color_4,
	 input tandy_color_16,
    // IBM PCjr gate array: its palette, mask and 640x200x2 mode
    input pcjr_video,
    input pcjr_mode_640x200x2,
    input[3:0] pcjr_palette_mask,
    output logic[3:0] video
    );

    reg[7:0] attr_byte;
    reg[7:0] char_byte;
	 reg[7:0] char_byte_del;
    reg[7:0] attr_byte_del;
    reg[7:0] charbits;
    reg[1:0] cursor_del;
    reg[1:0] display_enable_del;
    reg pix;
    reg pix_delay;
    reg[1:0] pix_bits;
    reg[1:0] pix_bits_old;
    reg[3:0] tandy_bits;
	 reg overscan;
	 
    reg[3:0] pcjr_mode06_bits_left = 4'd0;
    reg[15:0] pcjr_mode06_shift = 16'd0;
    reg[15:0] pcjr_mode06_pending_word = 16'd0;
    reg pcjr_mode06_pending_valid = 1'b0;

    reg[3:0] tandy_palette[0:15];
    initial begin
        tandy_palette[0]  = 4'h0;
        tandy_palette[1]  = 4'h1;
        tandy_palette[2]  = 4'h2;
        tandy_palette[3]  = 4'h3;
        tandy_palette[4]  = 4'h4;
        tandy_palette[5]  = 4'h5;
        tandy_palette[6]  = 4'h6;
        tandy_palette[7]  = 4'h7;
        tandy_palette[8]  = 4'h8;
        tandy_palette[9]  = 4'h9;
        tandy_palette[10] = 4'ha;
        tandy_palette[11] = 4'hb;
        tandy_palette[12] = 4'hc;
        tandy_palette[13] = 4'hd;
        tandy_palette[14] = 4'he;
        tandy_palette[15] = 4'hf;
    end
	 
    wire pix_640;
    wire[10:0] rom_addr;
    wire load_shifter;
    wire [2:0] charpix_sel;
    reg[3:0] video_out;

    // Character ROM
    reg[7:0] char_rom[0:4095];
    initial $readmemh("cga.hex", char_rom, 0, 4095);

    wire pcjr_mode06_pix = pcjr_mode06_shift[15];

    // The index into the palette in a PCjr mode: the 16 colours and the text
    // attribute as they are, the 4 colour modes from the two bits of the
    // pixel, 640x200x2 from the serialiser of its 16 bit words
    wire [3:0] pcjr_pixel_index =
        !grph_mode ? video_out :
        tandy_color_16 ? video_out :
        pcjr_mode_640x200x2 ? {3'b000, pcjr_mode06_pix} :
        (mode_640 && !tandy_color_4) ? {3'b000, pix_640} :
        {2'b00, video_out[2:1]};
    // The palette mask applies to text, 16 colour and 640x200x4; not to
    // 320x200x4 (fixed entries 0-3) nor to 640x200x2 (entries 0-1)
    wire pcjr_apply_mask = ~grph_mode || tandy_color_16 || (tandy_color_4 && mode_640);
    wire [3:0] pcjr_masked_index = pcjr_apply_mask ? (pcjr_pixel_index & pcjr_palette_mask) : pcjr_pixel_index;

    always_comb
    begin
        if (tandy_16_mode) begin
				if (pcjr_video) begin
					if (overscan)
						video = video_out;
					else
						video = tandy_palette[pcjr_masked_index];
				end else if (overscan)
					video = tandy_color_4 ? video_out : tandy_palette[video_out];
				else if (tandy_color_4)
					video = tandy_palette[{ 2'b00, video_out[2:1] }];
				else if (mode_640)
					video = tandy_palette[{ 2'b000, pix_640 }];
				else
					video = tandy_palette[video_out];
		  end else
				video = video_out;		  
    end
	 

    // Latch character and attribute data from VRAM
    // at appropriate times
    always @ (posedge clk)
    begin
	     if (tandy_palette_set)
		     tandy_palette[tandy_palette_color] = tandy_newcolor;
			  
        if (vram_read_char) begin
            char_byte <= vram_data;
        end
        if (vram_read_att) begin
            attr_byte <= vram_data;
        end
    end

    // Fetch pixel data for graphics modes
    wire [2:0]muxin;
    assign muxin = hres_mode ? (clk_seq[3:1] + 3'd6) : (clk_seq[4:2] + 3'd7);
	 
    always @ (posedge clk)
        char_byte_del <= char_byte;
	 
    always @ (*)
    begin
        if (video_enabled) begin
            // Hi-res vs low-res needs different adjustments
            // Normal CGA is low res only in graphics mode
            // Tandy uses "high res" mode for both 320x200x16
            // and 640x200x4 color modes
            case (muxin)
                3'd0: pix_bits <= tandy_color_4 ? { attr_byte[7], char_byte_del[7] } : char_byte_del[7:6];
                3'd1: pix_bits <= tandy_color_4 ? { attr_byte[6], char_byte_del[6] } : char_byte_del[5:4];
                3'd2: pix_bits <= tandy_color_4 ? { attr_byte[5], char_byte_del[5] } : char_byte_del[3:2];
                3'd3: pix_bits <= tandy_color_4 ? { attr_byte[4], char_byte_del[4] } : char_byte_del[1:0];
                3'd4: pix_bits <= tandy_color_4 ? { attr_byte[3], char_byte_del[3] } : attr_byte[7:6];
                3'd5: pix_bits <= tandy_color_4 ? { attr_byte[2], char_byte_del[2] } : attr_byte[5:4];
                3'd6: pix_bits <= tandy_color_4 ? { attr_byte[1], char_byte_del[1] } : attr_byte[3:2];
                3'd7: pix_bits <= tandy_color_4 ? { attr_byte[0], char_byte_del[0] } : attr_byte[1:0];
                default: pix_bits <= 2'b0;
            endcase
        end else begin
            pix_bits <= 2'b0;
        end
    end

    // Add a pipeline delay to the attribute byte data, cursor, and display
    // enable so they line up with the displayed character
    always @ (posedge clk)
    begin
        if (disp_pipeline) begin
            attr_byte_del <= video_enabled ? attr_byte : 8'd0;
            display_enable_del <= {display_enable_del[0], display_enable};
            cursor_del <= {cursor_del[0], cursor};
        end
    end

    // Look up character byte in our character ROM table
    assign rom_addr = {char_byte, row_addr[2:0]};
    wire pattern_chr = (char_byte >= 8'hB0 && char_byte <= 8'hDF);
	 
    always @ (posedge clk)
    begin
        // Only load character bits at this point
        if (charrom_read) begin
            if (row_addr > 5'd7)
                charbits <= pattern_chr ? char_rom[{~thin_font, 11'b0} | {char_byte, 3'd7}] : 8'b0;
            else
                charbits <= char_rom[{~thin_font, 11'b0} | rom_addr];
        end
    end

    // This must be a mux. Using a shift register causes very weird
    // issues with the character ROM and Yosys turns it into a bunch
    // of flip-flops instead of a ROM.
	 	 
	 assign charpix_sel = hres_mode ? (clk_seq[3:1] + 3'd6) : (clk_seq[4:2] + 3'd7);  
	 
    always @ (*)
    begin
        if (video_enabled) begin
            // Hi-res vs low-res needs different adjustments
            case (charpix_sel)
                5'd0: pix <= charbits[7];
                5'd1: pix <= charbits[6];
                5'd2: pix <= charbits[5];
                5'd3: pix <= charbits[4];
                5'd4: pix <= charbits[3];
                5'd5: pix <= charbits[2];
                5'd6: pix <= charbits[1];
                5'd7: pix <= charbits[0];
                default: pix <= 0;
            endcase
        end else begin
            pix <= 0;
        end
    end

    // In 640x200 mode, alternate between the two bits from
    // the shift register outputs at specific times in the sequence
    // A 640-dot CGA pixel is one bit held for two master-clock cycles.
    // pix_bits is ordered as {first_bit, second_bit}; select the first bit
    // for clk_seq[1:0]=00/01 and the second for 10/11.  The previous
    // +7 phase offset emitted {second, first, first, second}, shifting every
    // artifact transition by one half-pixel.
    assign pix_640 = clk_seq[1] ? pix_bits[0] : pix_bits[1];
	 
	 // In Tandy 320x200x16 and 160x200x16 modes, concatenate two adjacent pixels
    wire temp;
    assign temp = clk_seq[1:0] == 2'b00;
    always @ (posedge clk)
    begin
        if (clk_seq[0]) begin
            if (muxin[0]) begin
                tandy_bits <= {pix_bits_old, pix_bits};
            end else begin
                pix_bits_old <= pix_bits;
            end
        end
    end

    // PCjr 640x200x2 is a 16 bit 1 bpp stream, MSB first. The next word is
    // captured on the pipeline event, then loaded and shifted on the pixel
    // cadence of the 640 pixel output path.
    wire pcjr_mode06_emit = clk_seq[0];
    always @ (posedge clk)
    begin
        if (pcjr_video && pcjr_mode_640x200x2) begin
            if (disp_pipeline) begin
                pcjr_mode06_pending_word <= {char_byte_del, attr_byte};
                pcjr_mode06_pending_valid <= 1'b1;
            end
            if (pcjr_mode06_emit) begin
                if (pcjr_mode06_pending_valid) begin
                    pcjr_mode06_shift <= pcjr_mode06_pending_word;
                    pcjr_mode06_bits_left <= 4'd15;
                    pcjr_mode06_pending_valid <= 1'b0;
                end else if (pcjr_mode06_bits_left != 4'd0) begin
                    pcjr_mode06_shift <= {pcjr_mode06_shift[14:0], 1'b0};
                    pcjr_mode06_bits_left <= pcjr_mode06_bits_left - 1'b1;
                end
            end
        end else begin
            pcjr_mode06_shift <= 16'd0;
            pcjr_mode06_bits_left <= 4'd0;
            pcjr_mode06_pending_word <= 16'd0;
            pcjr_mode06_pending_valid <= 1'b0;
        end
    end

    // Add one clk cycle delay to match up pixel data with attribute byte
    // data.
    always @ (posedge clk)
    begin
        pix_delay <= pix;
    end

    // Applies video attributes, generates final video
    cga_attrib attrib (
        .clk(clk),
        .att_byte(attr_byte_del),
        .row_addr(row_addr),
        .cga_color_reg(cga_color_reg),
        .grph_mode(grph_mode),
        .bw_mode(bw_mode),
        .mode_640(mode_640),
        // The PCjr uses the gate array palette and border in the low
        // resolution modes too (320x200x4, text)
        .tandy_16_mode((tandy_16_mode && hres_mode) || pcjr_video),
        .display_enable(display_enable_del[0]),
        .blink_enabled(blink_enabled),
        .blink(blink),
        .cursor(cursor_del[0]),
        .hsync(hsync),
        .vsync(vsync),
        .pix_in(pix_delay),
        .c0(pix_bits[0]),
        .c1(pix_bits[1]),
        .pix_640(pix_640),
        .pix_tandy(tandy_bits),
        .tandy_bordercol(tandy_bordercol),
        .tandy_color_4(tandy_color_4),
		  .tandy_color_16(tandy_color_16),
        .pcjr_video(pcjr_video),
        .pcjr_mode_640x200x2(pcjr_mode_640x200x2),
        .pix_out(video_out),
        .overscan(overscan)
    );

endmodule
