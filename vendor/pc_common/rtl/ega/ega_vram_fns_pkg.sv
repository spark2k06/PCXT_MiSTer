//
// EGA plane access functions shared by the SDRAM frontend and the BRAM version:
// CPU aperture remapping, write-mode ALU, read mode 1 colour compare.
// Taken verbatim from ega_vram.v so the two backends cannot drift apart.
//
package ega_vram_fns_pkg;

// CPU aperture remapping follows x86Box vid_ega.c ega_remap_cpu_addr:
// odd/even, 64K, and A000-BFFF map modes all feed the A0 mux.
function [15:0] remap_cpu_addr;
    input [15:0] inaddr;
    input        inaddr_a16;
    input        odd_even_mode_sel;
    input        extended_memory_sel;
    input [1:0]  mem_map_sel_in;
    input        page_select_in;
    input        card_is_64k;
    reg   [15:0] addr;
    reg   [2:0]  a0mux;
    begin
        addr = inaddr;
        a0mux = 3'b000;

        if (odd_even_mode_sel)
            a0mux = a0mux | 3'b010;

        if (card_is_64k)
            a0mux = a0mux | 3'b001;

        if (mem_map_sel_in == 2'b00)
            a0mux = a0mux | 3'b100;

        case (mem_map_sel_in)
            2'b10,
            2'b11: addr = addr & 16'h7FFF;
            default: addr = addr & 16'hFFFF;
        endcase

        case (a0mux)
            3'b010: begin
                addr = addr & 16'hFFFE;
                addr[0] = ~page_select_in;
            end
            3'b011: begin
                addr = addr & 16'hFFFE;
                addr[0] = inaddr[14];
            end
            3'b110: begin
                addr = addr & 16'hFFFE;
                addr[0] = inaddr_a16;
            end
            default: begin
            end
        endcase

        if (!extended_memory_sel)
            addr = addr & 16'h3FFF;

        remap_cpu_addr = addr;
    end
endfunction

function [7:0] rotate_right8;
    input [7:0] value;
    input [2:0] count;
    begin
        case (count)
            3'd0: rotate_right8 = value;
            3'd1: rotate_right8 = {value[0], value[7:1]};
            3'd2: rotate_right8 = {value[1:0], value[7:2]};
            3'd3: rotate_right8 = {value[2:0], value[7:3]};
            3'd4: rotate_right8 = {value[3:0], value[7:4]};
            3'd5: rotate_right8 = {value[4:0], value[7:5]};
            3'd6: rotate_right8 = {value[5:0], value[7:6]};
            default: rotate_right8 = {value[6:0], value[7]};
        endcase
    end
endfunction

function [7:0] apply_rop;
    input [7:0] old_byte;
    input [7:0] src_byte;
    input [1:0] rop;
    begin
        case (rop)
            2'b01: apply_rop = old_byte & src_byte;
            2'b10: apply_rop = old_byte | src_byte;
            2'b11: apply_rop = old_byte ^ src_byte;
            default: apply_rop = src_byte;
        endcase
    end
endfunction

// Implements EGA write modes 0, 2, and 3 after latch capture. Mode 1 is
// handled outside this helper because it writes the latched byte unchanged.
function [7:0] compute_write_byte;
    input [7:0] old_byte;
    input [7:0] host_byte;
    input       plane_set_reset;
    input       plane_enable_set_reset;
    input       plane_host_bit;
    input [7:0] mask_byte;
    input [1:0] rop;
    input [1:0] write_mode_sel;
    input [2:0] rotate_count_sel;
    reg   [7:0] rotated_host_byte;
    reg   [7:0] effective_mask;
    reg   [7:0] src_byte;
    reg   [7:0] alu_byte;
    begin
        rotated_host_byte = rotate_right8(host_byte, rotate_count_sel);
        effective_mask = mask_byte;
        src_byte = 8'h00;
        alu_byte = old_byte;
        case (write_mode_sel)
            2'b00: begin
                src_byte = plane_enable_set_reset ? {8{plane_set_reset}} : rotated_host_byte;
                alu_byte = apply_rop(old_byte, src_byte, rop);
                compute_write_byte = (alu_byte & mask_byte) | (old_byte & ~mask_byte);
            end
            2'b10: begin
                src_byte = {8{plane_host_bit}};
                alu_byte = apply_rop(old_byte, src_byte, rop);
                compute_write_byte = (alu_byte & mask_byte) | (old_byte & ~mask_byte);
            end
            2'b11: begin
                effective_mask = rotated_host_byte & mask_byte;
                src_byte = {8{plane_set_reset}};
                alu_byte = apply_rop(old_byte, src_byte, rop);
                compute_write_byte = (alu_byte & effective_mask) | (old_byte & ~effective_mask);
            end
            default: begin
                compute_write_byte = old_byte;
            end
        endcase
    end
endfunction

// Read mode 1 compares each assembled planar pixel against Color Compare,
// masked by Color Don't Care, and returns one match bit per pixel.
function [7:0] read_mode1_byte;
    input [7:0] plane0_byte;
    input [7:0] plane1_byte;
    input [7:0] plane2_byte;
    input [7:0] plane3_byte;
    input [7:0] compare_byte;
    input [7:0] dont_care_byte;
    integer bit_index;
    reg [3:0] pixel_bits;
    reg [3:0] care_mask;
    reg [3:0] compare_mask;
    begin
        care_mask = dont_care_byte[3:0];
        compare_mask = compare_byte[3:0];
        read_mode1_byte = 8'h00;

        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            pixel_bits = {
                plane3_byte[7 - bit_index],
                plane2_byte[7 - bit_index],
                plane1_byte[7 - bit_index],
                plane0_byte[7 - bit_index]
            };
            read_mode1_byte[7 - bit_index] = (((pixel_bits ^ compare_mask) & care_mask) == 4'h0);
        end
    end
endfunction


endpackage
