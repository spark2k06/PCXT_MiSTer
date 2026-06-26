//============================================================================
//
//  Pure EGA reference helpers for testbenches.
//
//============================================================================

package ega_reference_pkg;

    function automatic [7:0] ega_ref_rotate_right8(
        input [7:0] value,
        input [2:0] count
    );
        begin
            case (count)
                3'd0: ega_ref_rotate_right8 = value;
                3'd1: ega_ref_rotate_right8 = {value[0], value[7:1]};
                3'd2: ega_ref_rotate_right8 = {value[1:0], value[7:2]};
                3'd3: ega_ref_rotate_right8 = {value[2:0], value[7:3]};
                3'd4: ega_ref_rotate_right8 = {value[3:0], value[7:4]};
                3'd5: ega_ref_rotate_right8 = {value[4:0], value[7:5]};
                3'd6: ega_ref_rotate_right8 = {value[5:0], value[7:6]};
                default: ega_ref_rotate_right8 = {value[6:0], value[7]};
            endcase
        end
    endfunction

    function automatic [7:0] ega_ref_apply_rop(
        input [7:0] old_byte,
        input [7:0] src_byte,
        input [1:0] rop
    );
        begin
            case (rop)
                2'b01: ega_ref_apply_rop = old_byte & src_byte;
                2'b10: ega_ref_apply_rop = old_byte | src_byte;
                2'b11: ega_ref_apply_rop = old_byte ^ src_byte;
                default: ega_ref_apply_rop = src_byte;
            endcase
        end
    endfunction

    function automatic [7:0] ega_ref_write_mode0_byte(
        input [7:0] old_byte,
        input [7:0] host_byte,
        input       plane_set_reset,
        input       plane_enable_set_reset,
        input [7:0] bit_mask,
        input [1:0] rop,
        input [2:0] rotate_count
    );
        reg [7:0] rotated_host_byte;
        reg [7:0] src_byte;
        reg [7:0] alu_byte;
        begin
            rotated_host_byte = ega_ref_rotate_right8(host_byte, rotate_count);
            src_byte = plane_enable_set_reset ? {8{plane_set_reset}} : rotated_host_byte;
            alu_byte = ega_ref_apply_rop(old_byte, src_byte, rop);
            ega_ref_write_mode0_byte = (alu_byte & bit_mask) | (old_byte & ~bit_mask);
        end
    endfunction

    function automatic [7:0] ega_ref_write_mode1_byte(
        input [7:0] latch_byte
    );
        begin
            ega_ref_write_mode1_byte = latch_byte;
        end
    endfunction

    function automatic [7:0] ega_ref_write_mode2_byte(
        input [7:0] old_byte,
        input       plane_host_bit,
        input [7:0] bit_mask,
        input [1:0] rop
    );
        reg [7:0] src_byte;
        reg [7:0] alu_byte;
        begin
            src_byte = {8{plane_host_bit}};
            alu_byte = ega_ref_apply_rop(old_byte, src_byte, rop);
            ega_ref_write_mode2_byte = (alu_byte & bit_mask) | (old_byte & ~bit_mask);
        end
    endfunction

    function automatic [7:0] ega_ref_write_mode3_byte(
        input [7:0] old_byte,
        input [7:0] host_byte,
        input       plane_set_reset,
        input [7:0] bit_mask,
        input [1:0] rop,
        input [2:0] rotate_count
    );
        reg [7:0] rotated_host_byte;
        reg [7:0] effective_mask;
        reg [7:0] src_byte;
        reg [7:0] alu_byte;
        begin
            rotated_host_byte = ega_ref_rotate_right8(host_byte, rotate_count);
            effective_mask = rotated_host_byte & bit_mask;
            src_byte = {8{plane_set_reset}};
            alu_byte = ega_ref_apply_rop(old_byte, src_byte, rop);
            ega_ref_write_mode3_byte = (alu_byte & effective_mask) | (old_byte & ~effective_mask);
        end
    endfunction

    function automatic [7:0] ega_ref_read_mode0_byte(
        input [7:0] plane0_byte,
        input [7:0] plane1_byte,
        input [7:0] plane2_byte,
        input [7:0] plane3_byte,
        input [1:0] read_plane
    );
        begin
            case (read_plane)
                2'd0: ega_ref_read_mode0_byte = plane0_byte;
                2'd1: ega_ref_read_mode0_byte = plane1_byte;
                2'd2: ega_ref_read_mode0_byte = plane2_byte;
                default: ega_ref_read_mode0_byte = plane3_byte;
            endcase
        end
    endfunction

    function automatic [7:0] ega_ref_read_mode1_byte(
        input [7:0] plane0_byte,
        input [7:0] plane1_byte,
        input [7:0] plane2_byte,
        input [7:0] plane3_byte,
        input [7:0] compare_byte,
        input [7:0] dont_care_byte
    );
        reg [7:0] diff0;
        reg [7:0] diff1;
        reg [7:0] diff2;
        reg [7:0] diff3;
        begin
            diff0 = (plane0_byte ^ ((compare_byte[0]) ? 8'hFF : 8'h00)) &
                    ((dont_care_byte[0]) ? 8'hFF : 8'h00);
            diff1 = (plane1_byte ^ ((compare_byte[1]) ? 8'hFF : 8'h00)) &
                    ((dont_care_byte[1]) ? 8'hFF : 8'h00);
            diff2 = (plane2_byte ^ ((compare_byte[2]) ? 8'hFF : 8'h00)) &
                    ((dont_care_byte[2]) ? 8'hFF : 8'h00);
            diff3 = (plane3_byte ^ ((compare_byte[3]) ? 8'hFF : 8'h00)) &
                    ((dont_care_byte[3]) ? 8'hFF : 8'h00);
            ega_ref_read_mode1_byte = ~(diff0 | diff1 | diff2 | diff3);
        end
    endfunction

    function automatic [15:0] ega_ref_cpu_plane_addr(
        input [16:0] cpu_addr,
        input        odd_even_mode,
        input        extended_memory,
        input [1:0]  mem_map_sel,
        input        page_select
    );
        reg [15:0] remapped_addr;
        reg [2:0]  a0mux;
        begin
            remapped_addr = cpu_addr[15:0];
            a0mux = 3'b000;

            if (odd_even_mode)
                a0mux = a0mux | 3'b010;

            if (mem_map_sel == 2'b00)
                a0mux = a0mux | 3'b100;

            case (mem_map_sel)
                2'b10,
                2'b11: remapped_addr = remapped_addr & 16'h7FFF;
                default: remapped_addr = remapped_addr & 16'hFFFF;
            endcase

            case (a0mux)
                3'b010: begin
                    remapped_addr = remapped_addr & 16'hFFFE;
                    remapped_addr[0] = ~page_select;
                end
                3'b110: begin
                    remapped_addr = remapped_addr & 16'hFFFE;
                    remapped_addr[0] = cpu_addr[16];
                end
                default: begin
                end
            endcase

            if (!extended_memory)
                remapped_addr = remapped_addr & 16'h3FFF;

            ega_ref_cpu_plane_addr = remapped_addr;
        end
    endfunction

    function automatic [1:0] ega_ref_read_plane(
        input [16:0] cpu_addr,
        input [1:0]  read_plane,
        input        chain2_read
    );
        begin
            ega_ref_read_plane = chain2_read ? {read_plane[1], cpu_addr[0]} : read_plane;
        end
    endfunction

    function automatic [3:0] ega_ref_write_mask(
        input [16:0] cpu_addr,
        input [3:0]  map_mask,
        input        chain2_write
    );
        begin
            ega_ref_write_mask = chain2_write ? (map_mask & (4'b0101 << cpu_addr[0])) : map_mask;
        end
    endfunction

    function automatic [16:0] ega_ref_abs_to_offset(
        input [19:0] abs_addr
    );
        begin
            ega_ref_abs_to_offset = (abs_addr - 20'hA0000) & 17'h1FFFF;
        end
    endfunction

    function automatic ega_ref_cpu_window_select(
        input [19:0] abs_addr,
        input [1:0]  mem_map_sel
    );
        begin
            case (mem_map_sel)
                2'b00: ega_ref_cpu_window_select = (abs_addr >= 20'hA0000) && (abs_addr <= 20'hBFFFF);
                2'b01: ega_ref_cpu_window_select = (abs_addr >= 20'hA0000) && (abs_addr <= 20'hAFFFF);
                2'b10: ega_ref_cpu_window_select = (abs_addr >= 20'hB0000) && (abs_addr <= 20'hB7FFF);
                2'b11: ega_ref_cpu_window_select = (abs_addr >= 20'hB8000) && (abs_addr <= 20'hBFFFF);
                default: ega_ref_cpu_window_select = 1'b0;
            endcase
        end
    endfunction

    function automatic [18:0] ega_ref_scanout_addr(
        input [18:0] memaddr,
        input [4:0]  scanline,
        input        crtc14_dword_mode,
        input        crtc17_byte_mode,
        input        crtc17_word_ma15,
        input        crtc17_subst_ma13,
        input        crtc17_subst_ma14,
        input [18:0] vram_mask
    );
        reg [18:0] remapped;
        begin
            if (crtc14_dword_mode)
                remapped = ((memaddr << 2) & 19'h3FFF0) | ((memaddr >> 14) & 19'h0000C) | (memaddr & 19'h40000);
            else if (crtc17_byte_mode)
                remapped = memaddr;
            else if (crtc17_word_ma15)
                remapped = ((memaddr << 1) & 19'h3FFF8) | ((memaddr >> 15) & 19'h00004) | (memaddr & 19'h40000);
            else
                remapped = ((memaddr << 1) & 19'h3FFF8) | ((memaddr >> 13) & 19'h00004) | (memaddr & 19'h40000);

            if (crtc17_subst_ma13)
                remapped[13] = scanline[0];
            if (crtc17_subst_ma14)
                remapped[14] = scanline[1];

            ega_ref_scanout_addr = remapped & vram_mask;
        end
    endfunction

    function automatic [15:0] ega_ref_row_advance_addr(
        input [15:0] row_base,
        input [7:0]  crtc_offset
    );
        begin
            ega_ref_row_advance_addr = row_base + ({8'd0, crtc_offset} << 1);
        end
    endfunction

    function automatic [3:0] ega_ref_planar_pixel(
        input [7:0] plane0_byte,
        input [7:0] plane1_byte,
        input [7:0] plane2_byte,
        input [7:0] plane3_byte,
        input [2:0] pixel_index
    );
        reg [2:0] bit_index;
        begin
            bit_index = 3'd7 - pixel_index;
            ega_ref_planar_pixel = {
                plane3_byte[bit_index],
                plane2_byte[bit_index],
                plane1_byte[bit_index],
                plane0_byte[bit_index]
            };
        end
    endfunction

    function automatic [3:0] ega_ref_apply_plane_enable(
        input [3:0] pixel,
        input [3:0] plane_enable
    );
        begin
            ega_ref_apply_plane_enable = pixel & plane_enable;
        end
    endfunction

    function automatic [3:0] ega_ref_apply_graphics_blink(
        input [3:0] color,
        input [3:0] plane_mask,
        input       attr_blink_enable,
        input       blink_state
    );
        reg [3:0] blink_mask;
        reg [3:0] blink_value;
        begin
            blink_mask = attr_blink_enable ? 4'h8 : 4'h0;
            blink_value = (attr_blink_enable && blink_state) ? 4'h8 : 4'h0;
            ega_ref_apply_graphics_blink =
                ((color & plane_mask & ~blink_mask) |
                 ((color | ~plane_mask) & blink_mask & blink_value)) ^ blink_mask;
        end
    endfunction

    function automatic [5:0] ega_ref_palette_code(
        input [7:0] attr_palette_entry
    );
        begin
            ega_ref_palette_code = attr_palette_entry[5:0];
        end
    endfunction

    function automatic [17:0] ega_ref_rgb6(
        input [5:0] color,
        input       palette_64_mode
    );
        reg [5:0] red;
        reg [5:0] green;
        reg [5:0] blue;
        begin
            if (palette_64_mode) begin
                red = (color[2] ? 6'd42 : 6'd0) + (color[5] ? 6'd21 : 6'd0);
                green = (color[1] ? 6'd42 : 6'd0) + (color[4] ? 6'd21 : 6'd0);
                blue = (color[0] ? 6'd42 : 6'd0) + (color[3] ? 6'd21 : 6'd0);
            end else if ((color & 6'h17) == 6'h06) begin
                red = 6'd42;
                green = 6'd21;
                blue = 6'd0;
            end else begin
                red = (color[2] ? 6'd42 : 6'd0) + (color[4] ? 6'd21 : 6'd0);
                green = (color[1] ? 6'd42 : 6'd0) + (color[4] ? 6'd21 : 6'd0);
                blue = (color[0] ? 6'd42 : 6'd0) + (color[4] ? 6'd21 : 6'd0);
            end

            ega_ref_rgb6 = {red, green, blue};
        end
    endfunction

endpackage
