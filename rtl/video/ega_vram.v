//============================================================================
//
//  PCXT MiSTer EGA planar VRAM
//  Copyright (C) 2026
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

`default_nettype wire

module ega_vram (
    input  wire        clk,
    input  wire        clk_vram,
    input  wire [15:0] cpu_addr,
    input  wire        cpu_a16,
    input  wire [7:0]  cpu_data_in,
    output reg  [7:0]  cpu_data_out = 8'h00,
    input  wire        cpu_we,
    input  wire        cpu_re,
    input  wire        cpu_mem_select,
    input  wire [3:0]  plane_write_mask,
    input  wire        odd_even_mode,
    input  wire        chain2_write,
    input  wire        chain2_read,
    input  wire        extended_memory,
    input  wire [1:0]  mem_map_sel,
    input  wire        page_select,
    input  wire [1:0]  write_mode,
    input  wire [1:0]  read_mode,
    input  wire [1:0]  read_plane_sel,
    input  wire [7:0]  color_compare,
    input  wire [7:0]  color_dont_care,
    input  wire [7:0]  bit_mask,
    input  wire [7:0]  set_reset,
    input  wire [3:0]  enable_set_reset,
    input  wire [1:0]  rop_select,
    input  wire [2:0]  rotate_count,
    input  wire [15:0] crt_addr,
    input  wire        crt_re,
    input  wire [15:0] text_cell_addr,
    input  wire [15:0] text_font_addr,
    input  wire        text_re,
    output wire [7:0]  crt_plane0,
    output wire [7:0]  crt_plane1,
    output wire [7:0]  crt_plane2,
    output wire [7:0]  crt_plane3,
    output reg  [7:0]  latch_plane0 = 8'h00,
    output reg  [7:0]  latch_plane1 = 8'h00,
    output reg  [7:0]  latch_plane2 = 8'h00,
    output reg  [7:0]  latch_plane3 = 8'h00,
    output reg  [7:0]  debug_old_plane0 = 8'h00,
    output reg  [7:0]  debug_old_plane1 = 8'h00,
    output reg  [7:0]  debug_old_plane2 = 8'h00,
    output reg  [7:0]  debug_old_plane3 = 8'h00,
    output reg  [7:0]  debug_new_plane0 = 8'h00,
    output reg  [7:0]  debug_new_plane1 = 8'h00,
    output reg  [7:0]  debug_new_plane2 = 8'h00,
    output reg  [7:0]  debug_new_plane3 = 8'h00
);

    localparam integer EGA_PLANE_ADDR_WIDTH = 16;
    localparam integer EGA_PLANE_DEPTH = (1 << EGA_PLANE_ADDR_WIDTH); // 64 KB per plane, 256 KB total.

`ifndef ALTERA_RESERVED_QIS
    (* ramstyle = "M10K" *) reg [7:0] plane0[0:EGA_PLANE_DEPTH-1];
    (* ramstyle = "M10K" *) reg [7:0] plane1[0:EGA_PLANE_DEPTH-1];
    (* ramstyle = "M10K" *) reg [7:0] plane2[0:EGA_PLANE_DEPTH-1];
    (* ramstyle = "M10K" *) reg [7:0] plane3[0:EGA_PLANE_DEPTH-1];
`endif

    reg [15:0] cpu_addr_q = 16'h0000;
    reg        cpu_a16_q = 1'b0;
    reg [7:0]  cpu_data_in_q = 8'h00;
    reg        cpu_we_q = 1'b0;
    reg        cpu_re_q = 1'b0;
    reg        cpu_mem_select_q = 1'b0;
    reg [3:0]  plane_write_mask_q = 4'h0;
    reg        odd_even_mode_q = 1'b0;
    reg        chain2_write_q = 1'b0;
    reg        chain2_read_q = 1'b0;
    reg        extended_memory_q = 1'b0;
    reg [1:0]  mem_map_sel_q = 2'b00;
    reg        page_select_q = 1'b0;
    reg [1:0]  write_mode_q = 2'b00;
    reg [1:0]  read_mode_q = 2'b00;
    reg [1:0]  read_plane_sel_q = 2'b00;
    reg [7:0]  color_compare_q = 8'h00;
    reg [7:0]  color_dont_care_q = 8'h0F;
    reg [7:0]  bit_mask_q = 8'hFF;
    reg [7:0]  set_reset_q = 8'h00;
    reg [3:0]  enable_set_reset_q = 4'h0;
    reg [1:0]  rop_select_q = 2'b00;
    reg [2:0]  rotate_count_q = 3'b000;

`ifdef ALTERA_RESERVED_QIS
    wire [7:0] cpu_plane0_q;
    wire [7:0] cpu_plane1_q;
    wire [7:0] cpu_plane2_q;
    wire [7:0] cpu_plane3_q;

    wire [7:0] crt_plane0_s;
    wire [7:0] crt_plane1_s;
    wire [7:0] crt_plane2_s;
    wire [7:0] crt_plane3_s;
`else
    reg [7:0] cpu_plane0_q = 8'h00;
    reg [7:0] cpu_plane1_q = 8'h00;
    reg [7:0] cpu_plane2_q = 8'h00;
    reg [7:0] cpu_plane3_q = 8'h00;

    reg [7:0] crt_plane0_r = 8'h00;
    reg [7:0] crt_plane1_r = 8'h00;
    reg [7:0] crt_plane2_r = 8'h00;
    reg [7:0] crt_plane3_r = 8'h00;
`endif

    wire cpu_access = cpu_mem_select & (cpu_re | cpu_we);
    wire [15:0] cpu_addr_remapped = remap_cpu_addr(cpu_addr, cpu_a16, odd_even_mode, extended_memory, mem_map_sel, page_select, 1'b0); // card_is_64k mirrors 86Box ega_remap_cpu_addr (vid_ega.c:1137); this core has 256 KB.
    wire [15:0] cpu_addr_q_remapped = remap_cpu_addr(cpu_addr_q, cpu_a16_q, odd_even_mode_q, extended_memory_q, mem_map_sel_q, page_select_q, 1'b0);
    wire [EGA_PLANE_ADDR_WIDTH-1:0] cpu_plane_addr = cpu_addr_remapped[EGA_PLANE_ADDR_WIDTH-1:0];
    wire [EGA_PLANE_ADDR_WIDTH-1:0] cpu_plane_addr_qw = cpu_addr_q_remapped[EGA_PLANE_ADDR_WIDTH-1:0];
    wire [EGA_PLANE_ADDR_WIDTH-1:0] crt_plane0_addr = text_re ? text_cell_addr[EGA_PLANE_ADDR_WIDTH-1:0] : crt_addr[EGA_PLANE_ADDR_WIDTH-1:0];
    wire [EGA_PLANE_ADDR_WIDTH-1:0] crt_plane1_addr = text_re ? text_cell_addr[EGA_PLANE_ADDR_WIDTH-1:0] : crt_addr[EGA_PLANE_ADDR_WIDTH-1:0];
    wire [EGA_PLANE_ADDR_WIDTH-1:0] crt_plane2_addr = text_re ? text_font_addr[EGA_PLANE_ADDR_WIDTH-1:0] : crt_addr[EGA_PLANE_ADDR_WIDTH-1:0];
    wire [EGA_PLANE_ADDR_WIDTH-1:0] crt_plane3_addr = crt_addr[EGA_PLANE_ADDR_WIDTH-1:0];
    wire crt_read_en = crt_re | text_re;
    wire [1:0] effective_read_plane = chain2_read_q ? {read_plane_sel_q[1], cpu_addr_q[0]} : read_plane_sel_q;
    wire [3:0] effective_plane_write_mask = chain2_write_q ? (plane_write_mask_q & (4'b0101 << cpu_addr_q[0])) : plane_write_mask_q;

    wire       write_mode1 = (write_mode_q == 2'b01);
    wire [7:0] cpu_plane0_new = write_mode1
                              ? latch_plane0
                              : compute_write_byte(latch_plane0, cpu_data_in_q, set_reset_q[0], enable_set_reset_q[0], cpu_data_in_q[0], bit_mask_q, rop_select_q, write_mode_q, rotate_count_q);
    wire [7:0] cpu_plane1_new = write_mode1
                              ? latch_plane1
                              : compute_write_byte(latch_plane1, cpu_data_in_q, set_reset_q[1], enable_set_reset_q[1], cpu_data_in_q[1], bit_mask_q, rop_select_q, write_mode_q, rotate_count_q);
    wire [7:0] cpu_plane2_new = write_mode1
                              ? latch_plane2
                              : compute_write_byte(latch_plane2, cpu_data_in_q, set_reset_q[2], enable_set_reset_q[2], cpu_data_in_q[2], bit_mask_q, rop_select_q, write_mode_q, rotate_count_q);
    wire [7:0] cpu_plane3_new = write_mode1
                              ? latch_plane3
                              : compute_write_byte(latch_plane3, cpu_data_in_q, set_reset_q[3], enable_set_reset_q[3], cpu_data_in_q[3], bit_mask_q, rop_select_q, write_mode_q, rotate_count_q);

    wire write_plane0_commit = cpu_mem_select_q & cpu_we_q & effective_plane_write_mask[0];
    wire write_plane1_commit = cpu_mem_select_q & cpu_we_q & effective_plane_write_mask[1];
    wire write_plane2_commit = cpu_mem_select_q & cpu_we_q & effective_plane_write_mask[2];
    wire write_plane3_commit = cpu_mem_select_q & cpu_we_q & effective_plane_write_mask[3];

`ifdef ALTERA_RESERVED_QIS
    wire [EGA_PLANE_ADDR_WIDTH-1:0] plane0_cpu_addr = write_plane0_commit ? cpu_plane_addr_qw : cpu_plane_addr;
    wire [EGA_PLANE_ADDR_WIDTH-1:0] plane1_cpu_addr = write_plane1_commit ? cpu_plane_addr_qw : cpu_plane_addr;
    wire [EGA_PLANE_ADDR_WIDTH-1:0] plane2_cpu_addr = write_plane2_commit ? cpu_plane_addr_qw : cpu_plane_addr;
    wire [EGA_PLANE_ADDR_WIDTH-1:0] plane3_cpu_addr = write_plane3_commit ? cpu_plane_addr_qw : cpu_plane_addr;
`endif

`ifdef ALTERA_RESERVED_QIS
    assign crt_plane0 = crt_plane0_s;
    assign crt_plane1 = crt_plane1_s;
    assign crt_plane2 = crt_plane2_s;
    assign crt_plane3 = crt_plane3_s;
`else
    assign crt_plane0 = crt_plane0_r;
    assign crt_plane1 = crt_plane1_r;
    assign crt_plane2 = crt_plane2_r;
    assign crt_plane3 = crt_plane3_r;
`endif

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

    always @(posedge clk) begin
        cpu_addr_q <= cpu_addr;
        cpu_a16_q <= cpu_a16;
        cpu_data_in_q <= cpu_data_in;
        cpu_we_q <= cpu_mem_select & cpu_we;
        cpu_re_q <= cpu_mem_select & cpu_re;
        cpu_mem_select_q <= cpu_access;
        plane_write_mask_q <= plane_write_mask;
        odd_even_mode_q <= odd_even_mode;
        chain2_write_q <= chain2_write;
        chain2_read_q <= chain2_read;
        extended_memory_q <= extended_memory;
        mem_map_sel_q <= mem_map_sel;
        page_select_q <= page_select;
        write_mode_q <= write_mode;
        read_mode_q <= read_mode;
        read_plane_sel_q <= read_plane_sel;
        color_compare_q <= color_compare;
        color_dont_care_q <= color_dont_care;
        bit_mask_q <= bit_mask;
        set_reset_q <= set_reset;
        enable_set_reset_q <= enable_set_reset;
        rop_select_q <= rop_select;
        rotate_count_q <= rotate_count;
    end

`ifdef ALTERA_RESERVED_QIS
    altsyncram plane0_ram
    (
        .clock0         (clk),
        .clock1         (clk_vram),
        .clocken0       (1'b1),
        .clocken1       (1'b1),
        .clocken2       (1'b1),
        .clocken3       (1'b1),
        .aclr0          (1'b0),
        .aclr1          (1'b0),
        .address_a      (plane0_cpu_addr),
        .address_b      (crt_plane0_addr),
        .addressstall_a (1'b0),
        .addressstall_b (1'b0),
        .byteena_a      (1'b1),
        .byteena_b      (1'b1),
        .data_a         (cpu_plane0_new),
        .data_b         (8'h00),
        .wren_a         (write_plane0_commit),
        .wren_b         (1'b0),
        .rden_a         (cpu_access & ~write_plane0_commit),
        .rden_b         (crt_read_en),
        .q_a            (cpu_plane0_q),
        .q_b            (crt_plane0_s),
        .eccstatus      ()
    );
    defparam
        plane0_ram.address_reg_b = "CLOCK1",
        plane0_ram.clock_enable_input_a = "BYPASS",
        plane0_ram.clock_enable_input_b = "BYPASS",
        plane0_ram.clock_enable_output_a = "BYPASS",
        plane0_ram.clock_enable_output_b = "BYPASS",
        plane0_ram.indata_reg_b = "CLOCK1",
        plane0_ram.intended_device_family = "Cyclone V",
        plane0_ram.lpm_type = "altsyncram",
        plane0_ram.numwords_a = EGA_PLANE_DEPTH,
        plane0_ram.numwords_b = EGA_PLANE_DEPTH,
        plane0_ram.operation_mode = "BIDIR_DUAL_PORT",
        plane0_ram.outdata_aclr_a = "NONE",
        plane0_ram.outdata_aclr_b = "NONE",
        plane0_ram.outdata_reg_a = "UNREGISTERED",
        plane0_ram.outdata_reg_b = "UNREGISTERED",
        plane0_ram.power_up_uninitialized = "FALSE",
        plane0_ram.ram_block_type = "M10K",
        plane0_ram.read_during_write_mode_mixed_ports = "DONT_CARE",
        plane0_ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
        plane0_ram.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
        plane0_ram.widthad_a = EGA_PLANE_ADDR_WIDTH,
        plane0_ram.widthad_b = EGA_PLANE_ADDR_WIDTH,
        plane0_ram.width_a = 8,
        plane0_ram.width_b = 8,
        plane0_ram.width_byteena_a = 1,
        plane0_ram.width_byteena_b = 1,
        plane0_ram.wrcontrol_wraddress_reg_b = "CLOCK1";

    altsyncram plane1_ram
    (
        .clock0         (clk),
        .clock1         (clk_vram),
        .clocken0       (1'b1),
        .clocken1       (1'b1),
        .clocken2       (1'b1),
        .clocken3       (1'b1),
        .aclr0          (1'b0),
        .aclr1          (1'b0),
        .address_a      (plane1_cpu_addr),
        .address_b      (crt_plane1_addr),
        .addressstall_a (1'b0),
        .addressstall_b (1'b0),
        .byteena_a      (1'b1),
        .byteena_b      (1'b1),
        .data_a         (cpu_plane1_new),
        .data_b         (8'h00),
        .wren_a         (write_plane1_commit),
        .wren_b         (1'b0),
        .rden_a         (cpu_access & ~write_plane1_commit),
        .rden_b         (crt_read_en),
        .q_a            (cpu_plane1_q),
        .q_b            (crt_plane1_s),
        .eccstatus      ()
    );
    defparam
        plane1_ram.address_reg_b = "CLOCK1",
        plane1_ram.clock_enable_input_a = "BYPASS",
        plane1_ram.clock_enable_input_b = "BYPASS",
        plane1_ram.clock_enable_output_a = "BYPASS",
        plane1_ram.clock_enable_output_b = "BYPASS",
        plane1_ram.indata_reg_b = "CLOCK1",
        plane1_ram.intended_device_family = "Cyclone V",
        plane1_ram.lpm_type = "altsyncram",
        plane1_ram.numwords_a = EGA_PLANE_DEPTH,
        plane1_ram.numwords_b = EGA_PLANE_DEPTH,
        plane1_ram.operation_mode = "BIDIR_DUAL_PORT",
        plane1_ram.outdata_aclr_a = "NONE",
        plane1_ram.outdata_aclr_b = "NONE",
        plane1_ram.outdata_reg_a = "UNREGISTERED",
        plane1_ram.outdata_reg_b = "UNREGISTERED",
        plane1_ram.power_up_uninitialized = "FALSE",
        plane1_ram.ram_block_type = "M10K",
        plane1_ram.read_during_write_mode_mixed_ports = "DONT_CARE",
        plane1_ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
        plane1_ram.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
        plane1_ram.widthad_a = EGA_PLANE_ADDR_WIDTH,
        plane1_ram.widthad_b = EGA_PLANE_ADDR_WIDTH,
        plane1_ram.width_a = 8,
        plane1_ram.width_b = 8,
        plane1_ram.width_byteena_a = 1,
        plane1_ram.width_byteena_b = 1,
        plane1_ram.wrcontrol_wraddress_reg_b = "CLOCK1";

    altsyncram plane2_ram
    (
        .clock0         (clk),
        .clock1         (clk_vram),
        .clocken0       (1'b1),
        .clocken1       (1'b1),
        .clocken2       (1'b1),
        .clocken3       (1'b1),
        .aclr0          (1'b0),
        .aclr1          (1'b0),
        .address_a      (plane2_cpu_addr),
        .address_b      (crt_plane2_addr),
        .addressstall_a (1'b0),
        .addressstall_b (1'b0),
        .byteena_a      (1'b1),
        .byteena_b      (1'b1),
        .data_a         (cpu_plane2_new),
        .data_b         (8'h00),
        .wren_a         (write_plane2_commit),
        .wren_b         (1'b0),
        .rden_a         (cpu_access & ~write_plane2_commit),
        .rden_b         (crt_read_en),
        .q_a            (cpu_plane2_q),
        .q_b            (crt_plane2_s),
        .eccstatus      ()
    );
    defparam
        plane2_ram.address_reg_b = "CLOCK1",
        plane2_ram.clock_enable_input_a = "BYPASS",
        plane2_ram.clock_enable_input_b = "BYPASS",
        plane2_ram.clock_enable_output_a = "BYPASS",
        plane2_ram.clock_enable_output_b = "BYPASS",
        plane2_ram.indata_reg_b = "CLOCK1",
        plane2_ram.intended_device_family = "Cyclone V",
        plane2_ram.lpm_type = "altsyncram",
        plane2_ram.numwords_a = EGA_PLANE_DEPTH,
        plane2_ram.numwords_b = EGA_PLANE_DEPTH,
        plane2_ram.operation_mode = "BIDIR_DUAL_PORT",
        plane2_ram.outdata_aclr_a = "NONE",
        plane2_ram.outdata_aclr_b = "NONE",
        plane2_ram.outdata_reg_a = "UNREGISTERED",
        plane2_ram.outdata_reg_b = "UNREGISTERED",
        plane2_ram.power_up_uninitialized = "FALSE",
        plane2_ram.ram_block_type = "M10K",
        plane2_ram.read_during_write_mode_mixed_ports = "DONT_CARE",
        plane2_ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
        plane2_ram.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
        plane2_ram.widthad_a = EGA_PLANE_ADDR_WIDTH,
        plane2_ram.widthad_b = EGA_PLANE_ADDR_WIDTH,
        plane2_ram.width_a = 8,
        plane2_ram.width_b = 8,
        plane2_ram.width_byteena_a = 1,
        plane2_ram.width_byteena_b = 1,
        plane2_ram.wrcontrol_wraddress_reg_b = "CLOCK1";

    altsyncram plane3_ram
    (
        .clock0         (clk),
        .clock1         (clk_vram),
        .clocken0       (1'b1),
        .clocken1       (1'b1),
        .clocken2       (1'b1),
        .clocken3       (1'b1),
        .aclr0          (1'b0),
        .aclr1          (1'b0),
        .address_a      (plane3_cpu_addr),
        .address_b      (crt_plane3_addr),
        .addressstall_a (1'b0),
        .addressstall_b (1'b0),
        .byteena_a      (1'b1),
        .byteena_b      (1'b1),
        .data_a         (cpu_plane3_new),
        .data_b         (8'h00),
        .wren_a         (write_plane3_commit),
        .wren_b         (1'b0),
        .rden_a         (cpu_access & ~write_plane3_commit),
        .rden_b         (crt_read_en),
        .q_a            (cpu_plane3_q),
        .q_b            (crt_plane3_s),
        .eccstatus      ()
    );
    defparam
        plane3_ram.address_reg_b = "CLOCK1",
        plane3_ram.clock_enable_input_a = "BYPASS",
        plane3_ram.clock_enable_input_b = "BYPASS",
        plane3_ram.clock_enable_output_a = "BYPASS",
        plane3_ram.clock_enable_output_b = "BYPASS",
        plane3_ram.indata_reg_b = "CLOCK1",
        plane3_ram.intended_device_family = "Cyclone V",
        plane3_ram.lpm_type = "altsyncram",
        plane3_ram.numwords_a = EGA_PLANE_DEPTH,
        plane3_ram.numwords_b = EGA_PLANE_DEPTH,
        plane3_ram.operation_mode = "BIDIR_DUAL_PORT",
        plane3_ram.outdata_aclr_a = "NONE",
        plane3_ram.outdata_aclr_b = "NONE",
        plane3_ram.outdata_reg_a = "UNREGISTERED",
        plane3_ram.outdata_reg_b = "UNREGISTERED",
        plane3_ram.power_up_uninitialized = "FALSE",
        plane3_ram.ram_block_type = "M10K",
        plane3_ram.read_during_write_mode_mixed_ports = "DONT_CARE",
        plane3_ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
        plane3_ram.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
        plane3_ram.widthad_a = EGA_PLANE_ADDR_WIDTH,
        plane3_ram.widthad_b = EGA_PLANE_ADDR_WIDTH,
        plane3_ram.width_a = 8,
        plane3_ram.width_b = 8,
        plane3_ram.width_byteena_a = 1,
        plane3_ram.width_byteena_b = 1,
        plane3_ram.wrcontrol_wraddress_reg_b = "CLOCK1";
`else
    always @(posedge clk) begin
        if (cpu_access)
            cpu_plane0_q <= plane0[cpu_plane_addr];

        if (write_plane0_commit)
            plane0[cpu_plane_addr_qw] <= cpu_plane0_new;
    end

    always @(posedge clk) begin
        if (cpu_access)
            cpu_plane1_q <= plane1[cpu_plane_addr];

        if (write_plane1_commit)
            plane1[cpu_plane_addr_qw] <= cpu_plane1_new;
    end

    always @(posedge clk) begin
        if (cpu_access)
            cpu_plane2_q <= plane2[cpu_plane_addr];

        if (write_plane2_commit)
            plane2[cpu_plane_addr_qw] <= cpu_plane2_new;
    end

    always @(posedge clk) begin
        if (cpu_access)
            cpu_plane3_q <= plane3[cpu_plane_addr];

        if (write_plane3_commit)
            plane3[cpu_plane_addr_qw] <= cpu_plane3_new;
    end
`endif

    always @(posedge clk) begin
        // EGA latches are refreshed by reads; writes consume the last latched value.
        if (cpu_mem_select_q && cpu_re_q) begin
            latch_plane0 <= cpu_plane0_q;
            latch_plane1 <= cpu_plane1_q;
            latch_plane2 <= cpu_plane2_q;
            latch_plane3 <= cpu_plane3_q;

            if (read_mode_q == 2'b01) begin
                cpu_data_out <= read_mode1_byte(
                    cpu_plane0_q,
                    cpu_plane1_q,
                    cpu_plane2_q,
                    cpu_plane3_q,
                    color_compare_q,
                    color_dont_care_q
                );
            end else begin
                case (effective_read_plane)
                    2'b00: cpu_data_out <= cpu_plane0_q;
                    2'b01: cpu_data_out <= cpu_plane1_q;
                    2'b10: cpu_data_out <= cpu_plane2_q;
                    default: cpu_data_out <= cpu_plane3_q;
                endcase
            end
        end

        if (cpu_mem_select_q && cpu_we_q) begin
            debug_old_plane0 <= cpu_plane0_q;
            debug_old_plane1 <= cpu_plane1_q;
            debug_old_plane2 <= cpu_plane2_q;
            debug_old_plane3 <= cpu_plane3_q;
            debug_new_plane0 <= cpu_plane0_new;
            debug_new_plane1 <= cpu_plane1_new;
            debug_new_plane2 <= cpu_plane2_new;
            debug_new_plane3 <= cpu_plane3_new;
        end

    end

`ifndef ALTERA_RESERVED_QIS
    always @(posedge clk_vram) begin
        if (crt_read_en)
            crt_plane0_r <= plane0[crt_plane0_addr];
    end
    always @(posedge clk_vram) begin
        if (crt_read_en)
            crt_plane1_r <= plane1[crt_plane1_addr];
    end
    always @(posedge clk_vram) begin
        if (crt_read_en)
            crt_plane2_r <= plane2[crt_plane2_addr];
    end
    always @(posedge clk_vram) begin
        if (crt_read_en)
            crt_plane3_r <= plane3[crt_plane3_addr];
    end
`endif

endmodule
