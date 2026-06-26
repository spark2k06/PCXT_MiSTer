`timescale 1ns / 1ps

module ega_registers_tb;

    timeunit 1ns;
    timeprecision 1ps;

    reg clk = 1'b0;
    reg reset = 1'b1;
    integer failures = 0;
    reg [8*80-1:0] current_test = "initialization";

    always #5 clk = ~clk;

    task automatic begin_test(input [8*80-1:0] name);
        begin
            current_test = name;
            $display("TEST: %0s", current_test);
        end
    endtask

    task automatic expect8(
        input [8*80-1:0] label,
        input [7:0] actual,
        input [7:0] expected
    );
        begin
            if (actual !== expected) begin
                $display("FAIL [%0s] %0s: expected %02x got %02x",
                         current_test, label, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect1(
        input [8*80-1:0] label,
        input actual,
        input expected
    );
        begin
            if (actual !== expected) begin
                $display("FAIL [%0s] %0s: expected %0d got %0d",
                         current_test, label, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect16(
        input [8*80-1:0] label,
        input [15:0] actual,
        input [15:0] expected
    );
        begin
            if (actual !== expected) begin
                $display("FAIL [%0s] %0s: expected %04x got %04x",
                         current_test, label, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task automatic expect_true(
        input [8*80-1:0] label,
        input condition
    );
        begin
            if (!condition) begin
                $display("FAIL [%0s] %0s", current_test, label);
                failures = failures + 1;
            end
        end
    endtask

    reg [15:0] io_addr = 16'h0000;
    reg [7:0]  io_data_in = 8'h00;
    reg        io_we = 1'b0;
    reg        io_re = 1'b0;

    wire [7:0] seq_data_out;
    wire [3:0] seq_plane_write_mask;
    wire       seq_chain2_write;
    wire       seq_extended_memory;
    wire       seq_ce_crt_fetch;
    wire       seq_ce_cpu_access;
    wire       seq_dot_clock_div2;
    wire       seq_char_9dot;
    wire [1:0] seq_char_map_a;
    wire [1:0] seq_char_map_b;
    wire [7:0] seq_map_mask_debug;
    wire [7:0] seq_memory_mode_debug;

    ega_sequencer seq_dut (
        .clk(clk),
        .reset(reset),
        .ce_pix(1'b1),
        .io_addr(io_addr),
        .io_data_in(io_data_in),
        .io_data_out(seq_data_out),
        .io_we(io_we),
        .io_re(io_re),
        .plane_write_mask(seq_plane_write_mask),
        .chain2_write(seq_chain2_write),
        .extended_memory(seq_extended_memory),
        .ce_crt_fetch(seq_ce_crt_fetch),
        .ce_cpu_access(seq_ce_cpu_access),
        .dot_clock_div2(seq_dot_clock_div2),
        .char_9dot(seq_char_9dot),
        .char_map_a(seq_char_map_a),
        .char_map_b(seq_char_map_b),
        .map_mask_debug(seq_map_mask_debug),
        .memory_mode_debug(seq_memory_mode_debug)
    );

    wire [7:0] gfx_data_out;
    wire [1:0] gfx_write_mode;
    wire [1:0] gfx_read_mode;
    wire [1:0] gfx_read_plane_sel;
    wire [7:0] gfx_color_compare;
    wire [7:0] gfx_color_dont_care;
    wire [7:0] gfx_bit_mask;
    wire [7:0] gfx_set_reset;
    wire [3:0] gfx_enable_set_reset;
    wire [1:0] gfx_rop_select;
    wire [2:0] gfx_rotate_count;
    wire       gfx_odd_even_mode;
    wire       gfx_chain2_read;
    wire [1:0] gfx_mem_map_sel;
    wire [7:0] gfx_mode_debug;

    ega_gfx_ctrl gfx_dut (
        .clk(clk),
        .reset(reset),
        .io_addr(io_addr),
        .io_data_in(io_data_in),
        .io_data_out(gfx_data_out),
        .io_we(io_we),
        .io_re(io_re),
        .write_mode(gfx_write_mode),
        .read_mode(gfx_read_mode),
        .read_plane_sel(gfx_read_plane_sel),
        .color_compare(gfx_color_compare),
        .color_dont_care(gfx_color_dont_care),
        .bit_mask(gfx_bit_mask),
        .set_reset(gfx_set_reset),
        .enable_set_reset(gfx_enable_set_reset),
        .rop_select(gfx_rop_select),
        .rotate_count(gfx_rotate_count),
        .odd_even_mode(gfx_odd_even_mode),
        .chain2_read(gfx_chain2_read),
        .mem_map_sel(gfx_mem_map_sel),
        .mode_debug(gfx_mode_debug)
    );

    reg        attr_status_re = 1'b0;
    reg [3:0] attr_plane_index = 4'h0;
    reg        attr_pixel_valid = 1'b1;
    reg        attr_display_enable = 1'b1;
    reg        attr_text_mode = 1'b0;
    reg        attr_palette_64_mode = 1'b1;
    wire       attr_blink_enable;
    wire       attr_line_graphics_enable;
    wire [7:0] attr_data_out;
    wire [3:0] attr_pixel_pan_out;
    wire [5:0] attr_color_out;
    wire       attr_display_enable_out;
    wire       attr_video_enable_out;

    ega_attrib_ctrl attr_dut (
        .clk(clk),
        .reset(reset),
        .ce_pix(1'b1),
        .io_addr(io_addr),
        .io_data_in(io_data_in),
        .io_data_out(attr_data_out),
        .io_we(io_we),
        .io_re(io_re),
        .status_re(attr_status_re),
        .plane_index(attr_plane_index),
        .pixel_valid(attr_pixel_valid),
        .display_enable(attr_display_enable),
        .text_mode(attr_text_mode),
        .blink_state(1'b0),
        .palette_64_mode(attr_palette_64_mode),
        .blink_enable_out(attr_blink_enable),
        .line_graphics_enable_out(attr_line_graphics_enable),
        .pixel_pan_out(attr_pixel_pan_out),
        .color_out(attr_color_out),
        .display_enable_out(attr_display_enable_out),
        .video_enable_out(attr_video_enable_out)
    );

    reg        crtc_enable = 1'b1;
    reg        crtc_ncs = 1'b1;
    reg        crtc_rw = 1'b1;
    reg        crtc_rs = 1'b0;
    reg [7:0]  crtc_di = 8'h00;
    wire [7:0] crtc_do;
    wire [13:0] crtc_ma;
    wire [15:0] crtc_ma_full;
    wire        crtc_hblank;
    wire        crtc_vblank;
    wire        crtc_de;
    wire [4:0]  crtc_ra;
    wire [7:0]  crtc_hc;
    wire [6:0]  crtc_vc;
    wire [7:0] crtc_h_displayed;
    wire [4:0] crtc_v_maxscan;
    wire [7:0] crtc_r11_debug;
    wire       crtc_status_not_displaying;
    wire       crtc_vert_blank_active;

    UM6845R crtc_dut (
        .CLOCK(clk),
        .CLKEN(1'b1),
        .nCLKEN(1'b0),
        .nRESET(~reset),
        .CRTC_TYPE(1'b1),
        .ENABLE(crtc_enable),
        .nCS(crtc_ncs),
        .R_nW(crtc_rw),
        .RS(crtc_rs),
        .DI(crtc_di),
        .DO(crtc_do),
        .hblank(crtc_hblank),
        .vblank(crtc_vblank),
        .line_reset(),
        .VSYNC(),
        .HSYNC(),
        .DE(crtc_de),
        .FIELD(),
        .CURSOR(),
        .MA(crtc_ma),
        .MA_FULL(crtc_ma_full),
        .RA(crtc_ra),
        .HC(crtc_hc),
        .VC(crtc_vc),
        .H_DISP_REG(crtc_h_displayed),
        .V_MAXSCAN_REG(crtc_v_maxscan),
        .hsync_width(),
        .status_vretrace(),
        .status_not_displaying(crtc_status_not_displaying),
        .vert_blank_active(crtc_vert_blank_active),
        .scanline_mod16_debug(),
        .vslines_debug(),
        .crtc_r10_debug(),
        .crtc_r11_debug(crtc_r11_debug),
        .crtc_r12_debug(),
        .crtc_r13_debug(),
        .crtc_r14_debug(),
        .crtc_r17_debug(),
        .crtc_r15_debug(),
        .crtc_r16_debug(),
        .crt_h_offset(4'h0),
        .crt_v_offset(3'h0),
        .vsync_width_osd(3'h0),
        .hsync_width_osd(3'h0),
        .hres_mode(1'b0)
    );

    wire [4:0] top_clkdiv;
    reg [14:0] top_bus_a = 15'h0000;
    reg        top_bus_ior_l = 1'b1;
    reg        top_bus_iow_l = 1'b1;
    reg        top_bus_memr_l = 1'b1;
    reg        top_bus_memw_l = 1'b1;
    reg [7:0]  top_bus_d = 8'h00;
    wire [7:0] top_bus_out;
    wire       top_bus_dir;
    wire       top_bus_rdy;
    wire       top_ram_we_l;
    wire [18:0] top_ram_a;
    wire [15:0] top_ega_fetch_addr;
    wire        top_ega_fetch_en;
    wire [15:0] top_ega_text_cell_addr;
    wire [15:0] top_ega_text_font_addr;
    wire        top_ega_text_fetch_en;
    wire [3:0] top_ega_plane_write_mask;
    wire       top_ega_odd_even_mode;
    wire       top_ega_cpu_access_slot;
    wire       top_ega_chain2_write;
    wire       top_ega_chain2_read;
    wire       top_ega_extended_memory;
    wire [1:0] top_ega_mem_map_sel;
    wire       top_ega_page_select;
    wire [1:0] top_ega_write_mode;
    wire [1:0] top_ega_read_mode;
    wire [1:0] top_ega_read_plane_sel;
    wire [7:0] top_ega_color_compare;
    wire [7:0] top_ega_color_dont_care;
    wire [7:0] top_ega_bit_mask;
    wire [7:0] top_ega_set_reset;
    wire [3:0] top_ega_enable_set_reset;
    wire [1:0] top_ega_rop_select;
    wire [2:0] top_ega_rotate_count;
    wire [6:0] top_ega_blink_counter;
    wire       top_ega_blink_state;
    wire       top_hsync;
    wire       top_hblank;
    wire       top_dbl_hsync;
    wire       top_vsync;
    wire       top_vblank;
    wire       top_vblank_border;
    wire       top_std_hsyncwidth;
    wire       top_de_o;
    wire [3:0] top_video;
    wire [3:0] top_dbl_video;
    wire [6:0] top_comp_video;
    wire [5:0] top_ega_red;
    wire [5:0] top_ega_green;
    wire [5:0] top_ega_blue;
    wire       top_ega_rgb_active;
    wire       top_ega_display_sel;
    wire       top_grph_mode;
    wire       top_hres_mode;
    wire       top_tandy_color_16;

    ega_top top_dut (
        .clk(clk),
        .reset(reset),
        .clkdiv(top_clkdiv),
        .bus_a(top_bus_a),
        .bus_ior_l(top_bus_ior_l),
        .bus_iow_l(top_bus_iow_l),
        .bus_memr_l(top_bus_memr_l),
        .bus_memw_l(top_bus_memw_l),
        .bus_d(top_bus_d),
        .bus_out(top_bus_out),
        .bus_dir(top_bus_dir),
        .bus_aen(1'b0),
        .bus_rdy(top_bus_rdy),
        .ram_we_l(top_ram_we_l),
        .ram_a(top_ram_a),
        .ram_d(8'h00),
        .ram_data_valid(1'b0),
        .ega_fetch_addr(top_ega_fetch_addr),
        .ega_fetch_en(top_ega_fetch_en),
        .ega_plane0_data(8'h00),
        .ega_plane1_data(8'h00),
        .ega_plane2_data(8'h00),
        .ega_plane3_data(8'h00),
        .ega_fetch_data_valid(1'b0),
        .ega_text_cell_addr(top_ega_text_cell_addr),
        .ega_text_font_addr(top_ega_text_font_addr),
        .ega_text_fetch_en(top_ega_text_fetch_en),
        .ega_text_char(8'h00),
        .ega_text_attr(8'h00),
        .ega_text_glyph(8'h00),
        .ega_text_data_valid(1'b0),
        .cpu_mem_select(1'b0),
        .cpu_mem_write(1'b0),
        .ega_cfg_toggle(),
        .ega_plane_write_mask_out(top_ega_plane_write_mask),
        .ega_odd_even_mode_out(top_ega_odd_even_mode),
        .ega_cpu_access_slot_out(top_ega_cpu_access_slot),
        .ega_chain2_write_out(top_ega_chain2_write),
        .ega_chain2_read_out(top_ega_chain2_read),
        .ega_extended_memory_out(top_ega_extended_memory),
        .ega_mem_map_sel_out(top_ega_mem_map_sel),
        .ega_page_select_out(top_ega_page_select),
        .ega_write_mode_out(top_ega_write_mode),
        .ega_read_mode_out(top_ega_read_mode),
        .ega_read_plane_sel_out(top_ega_read_plane_sel),
        .ega_color_compare_out(top_ega_color_compare),
        .ega_color_dont_care_out(top_ega_color_dont_care),
        .ega_bit_mask_out(top_ega_bit_mask),
        .ega_set_reset_out(top_ega_set_reset),
        .ega_enable_set_reset_out(top_ega_enable_set_reset),
        .ega_rop_select_out(top_ega_rop_select),
        .ega_rotate_count_out(top_ega_rotate_count),
        .ega_blink_counter_out(top_ega_blink_counter),
        .ega_blink_state_out(top_ega_blink_state),
        .hsync(top_hsync),
        .hblank(top_hblank),
        .dbl_hsync(top_dbl_hsync),
        .vsync(top_vsync),
        .vblank(top_vblank),
        .vblank_border(top_vblank_border),
        .std_hsyncwidth(top_std_hsyncwidth),
        .de_o(top_de_o),
        .video(top_video),
        .dbl_video(top_dbl_video),
        .comp_video(top_comp_video),
        .ega_red(top_ega_red),
        .ega_green(top_ega_green),
        .ega_blue(top_ega_blue),
        .ega_rgb_active(top_ega_rgb_active),
        .ega_display_sel_out(top_ega_display_sel),
        .splashscreen(1'b0),
        .thin_font(1'b0),
        .tandy_video(1'b0),
        .scandouble_en(1'b0),
        .ega_enabled(1'b1),
        .grph_mode(top_grph_mode),
        .hres_mode(top_hres_mode),
        .tandy_color_16(top_tandy_color_16),
        .cga_hw(1'b0),
        .crt_h_offset(4'h0),
        .crt_v_offset(3'h0),
        .vsync_width_osd(3'h0),
        .hsync_width_osd(3'h0)
    );

    task automatic reset_duts;
        begin
            io_addr = 16'h0000;
            io_data_in = 8'h00;
            io_we = 1'b0;
            io_re = 1'b0;
            attr_status_re = 1'b0;
            attr_plane_index = 4'h0;
            attr_pixel_valid = 1'b1;
            attr_display_enable = 1'b1;
            attr_text_mode = 1'b0;
            attr_palette_64_mode = 1'b1;
            crtc_ncs = 1'b1;
            crtc_rw = 1'b1;
            crtc_rs = 1'b0;
            crtc_di = 8'h00;
            top_bus_a = 15'h0000;
            top_bus_d = 8'h00;
            top_bus_ior_l = 1'b1;
            top_bus_iow_l = 1'b1;
            top_bus_memr_l = 1'b1;
            top_bus_memw_l = 1'b1;
            reset = 1'b1;
            repeat (4) @(negedge clk);
            reset = 1'b0;
            repeat (4) @(negedge clk);
        end
    endtask

    task automatic io_write(input [15:0] addr, input [7:0] data);
        begin
            @(negedge clk);
            io_addr = addr;
            io_data_in = data;
            io_re = 1'b0;
            io_we = 1'b1;
            @(negedge clk);
            io_we = 1'b0;
            io_addr = 16'h0000;
            io_data_in = 8'h00;
        end
    endtask

    task automatic io_read(input [15:0] addr, output [7:0] data);
        begin
            @(negedge clk);
            io_addr = addr;
            io_re = 1'b1;
            io_we = 1'b0;
            #1 data = seq_data_out | gfx_data_out | attr_data_out;
            @(negedge clk);
            io_re = 1'b0;
            io_addr = 16'h0000;
        end
    endtask

    task automatic attr_status_read;
        begin
            @(negedge clk);
            attr_status_re = 1'b1;
            @(negedge clk);
            attr_status_re = 1'b0;
        end
    endtask

    task automatic attr_write_reg(
        input [4:0] index,
        input [7:0] data
    );
        begin
            attr_status_read();
            io_write(16'h03C0, {2'b01, index});
            io_write(16'h03C0, data);
        end
    endtask

    task automatic attr_select_index(
        input [4:0] index,
        input       video_enable
    );
        begin
            attr_status_read();
            io_write(16'h03C0, {2'b00, video_enable, index});
        end
    endtask

    task automatic crtc_write(input rs, input [7:0] data);
        begin
            @(negedge clk);
            crtc_ncs = 1'b0;
            crtc_rw = 1'b0;
            crtc_rs = rs;
            crtc_di = data;
            @(negedge clk);
            crtc_ncs = 1'b1;
            crtc_rw = 1'b1;
            crtc_rs = 1'b0;
            crtc_di = 8'h00;
        end
    endtask

    task automatic top_io_write(input [15:0] addr, input [7:0] data);
        begin
            @(negedge clk);
            top_bus_a = addr[14:0];
            top_bus_d = data;
            top_bus_ior_l = 1'b1;
            top_bus_iow_l = 1'b0;
            @(negedge clk);
            top_bus_iow_l = 1'b1;
            top_bus_a = 15'h0000;
            top_bus_d = 8'h00;
        end
    endtask

    task automatic top_io_read(input [15:0] addr, output [7:0] data);
        begin
            @(negedge clk);
            top_bus_a = addr[14:0];
            top_bus_ior_l = 1'b0;
            top_bus_iow_l = 1'b1;
            #1 data = top_bus_out;
            @(negedge clk);
            top_bus_ior_l = 1'b1;
            top_bus_a = 15'h0000;
        end
    endtask

    task automatic select_and_read_attr(
        input [4:0] index,
        output [7:0] data
    );
        begin
            attr_status_read();
            io_write(16'h03C0, {2'b01, index});
            io_read(16'h03C1, data);
        end
    endtask

    task automatic top_select_and_read_attr(
        input [15:0] status_port,
        input [4:0] index,
        output [7:0] data
    );
        reg [7:0] ignored;
        begin
            top_io_read(status_port, ignored);
            top_io_write(16'h03C0, {2'b01, index});
            top_io_read(16'h03C1, data);
        end
    endtask

    task automatic expect_attr_plane_enable(
        input [8*80-1:0] label,
        input [3:0] plane_index_value,
        input [3:0] plane_enable_value,
        input [5:0] expected_color
    );
        begin
            attr_write_reg(5'h12, {4'h0, plane_enable_value});
            attr_plane_index = plane_index_value;
            @(posedge clk);
            #1 expect8(label, {2'b00, attr_color_out}, {2'b00, expected_color});
        end
    endtask

    task automatic expect_attr_output(
        input [8*80-1:0] label,
        input [3:0] plane_index_value,
        input       pixel_valid_value,
        input       display_enable_value,
        input [5:0] expected_color,
        input       expected_display_enable
    );
        begin
            attr_plane_index = plane_index_value;
            attr_pixel_valid = pixel_valid_value;
            attr_display_enable = display_enable_value;
            @(posedge clk);
            #1;
            expect8({label, " color"}, {2'b00, attr_color_out}, {2'b00, expected_color});
            expect1({label, " display enable"}, attr_display_enable_out, expected_display_enable);
        end
    endtask

    function automatic [15:0] expected_scanout_addr(
        input [15:0] raw_addr,
        input [4:0]  scanline,
        input [7:0]  crtc_14h,
        input [7:0]  crtc_17h
    );
        reg [19:0] in_addr;
        reg [19:0] out_addr;
        begin
            in_addr = {2'b00, raw_addr, 2'b00};

            if (crtc_14h[6])
                out_addr = ((in_addr << 2) & 20'h3FFF0) |
                           ((in_addr >> 14) & 20'h0000C) |
                           (in_addr & 20'hC0000);
            else if (crtc_17h[6])
                out_addr = in_addr;
            else if (crtc_17h[5])
                out_addr = ((in_addr << 1) & 20'h3FFF8) |
                           ((in_addr >> 15) & 20'h00004) |
                           (in_addr & 20'hC0000);
            else
                out_addr = ((in_addr << 1) & 20'h3FFF8) |
                           ((in_addr >> 13) & 20'h00004) |
                           (in_addr & 20'hC0000);

            if (!crtc_17h[0])
                out_addr = (out_addr & 20'hF7FFF) |
                           (scanline[0] ? 20'h08000 : 20'h00000);
            if (!crtc_17h[1])
                out_addr = (out_addr & 20'hEFFFF) |
                           (scanline[1] ? 20'h10000 : 20'h00000);

            expected_scanout_addr = out_addr[17:2];
        end
    endfunction

    task automatic expect_crtc_scanout(
        input [8*80-1:0] label,
        input [15:0] raw_addr,
        input [4:0]  scanline,
        input [7:0]  crtc_14h,
        input [7:0]  crtc_17h
    );
        begin
            crtc_write(1'b0, 8'h14);
            crtc_write(1'b1, crtc_14h);
            crtc_write(1'b0, 8'h17);
            crtc_write(1'b1, crtc_17h);
            force crtc_dut.row_addr_r = raw_addr;
            force crtc_dut.line = scanline;
            #1 expect16(label, crtc_ma_full,
                        expected_scanout_addr(raw_addr, scanline, crtc_14h, crtc_17h));
            release crtc_dut.row_addr_r;
            release crtc_dut.line;
        end
    endtask

    initial begin
        reg [7:0] read_value;
        reg [7:0] status_a;
        reg [7:0] status_b;

        reset_duts();

        begin_test("sequencer reset and index/data readback");
        io_write(16'h03C4, 8'h00);
        io_read(16'h03C5, read_value);
        expect8("SEQ reset register", read_value, 8'h03);
        io_write(16'h03C4, 8'h01);
        io_read(16'h03C5, read_value);
        expect8("SEQ clocking register", read_value, 8'h08);
        io_write(16'h03C4, 8'h02);
        io_read(16'h03C5, read_value);
        expect8("SEQ map mask reset", read_value, 8'h0F);
        io_write(16'h03C5, 8'h05);
        io_read(16'h03C5, read_value);
        expect8("SEQ map mask write", read_value, 8'h05);
        expect8("SEQ plane mask output", {4'h0, seq_plane_write_mask}, 8'h05);
        io_write(16'h03C4, 8'h03);
        io_write(16'h03C5, 8'h0D);
        io_read(16'h03C5, read_value);
        expect8("SEQ character map select readback", read_value, 8'h0D);
        expect8("SEQ character map outputs",
                {4'h0, seq_char_map_b, seq_char_map_a}, 8'h0D);
        io_write(16'h03C4, 8'h04);
        io_write(16'h03C5, 8'h02);
        expect1("SEQ chain-2 write follows memory mode bit 2", seq_chain2_write, 1'b1);
        expect1("SEQ extended memory follows memory mode bit 1", seq_extended_memory, 1'b1);

        begin_test("graphics controller reset and readback");
        io_write(16'h03CE, 8'h07);
        io_read(16'h03CF, read_value);
        expect8("GC color don't care reset", read_value, 8'h0F);
        io_write(16'h03CE, 8'h08);
        io_read(16'h03CF, read_value);
        expect8("GC bit mask reset", read_value, 8'hFF);
        io_write(16'h03CE, 8'h05);
        io_write(16'h03CF, 8'h18);
        io_read(16'h03CF, read_value);
        expect8("GC mode readback", read_value, 8'h18);
        expect8("GC mode debug", gfx_mode_debug, 8'h18);
        expect8("GC write/read mode outputs", {4'h0, gfx_chain2_read, gfx_read_mode[0], gfx_write_mode}, 8'h0C);
        io_write(16'h03CE, 8'h06);
        io_write(16'h03CF, 8'h0A);
        expect8("GC memory map and odd/even outputs", {3'b000, gfx_mem_map_sel, gfx_odd_even_mode, 2'b00}, 8'h14);

        begin_test("attribute controller flip-flop and readback");
        attr_status_read();
        io_write(16'h03C0, 8'h22);
        io_write(16'h03C0, 8'h2A);
        select_and_read_attr(5'h02, read_value);
        expect8("ATTR palette register 02h", read_value, 8'h2A);
        attr_status_read();
        io_write(16'h03C0, 8'h30);
        io_write(16'h03C0, 8'h09);
        select_and_read_attr(5'h10, read_value);
        expect8("ATTR mode control register", read_value, 8'h09);
        expect1("ATTR blink enable output", attr_blink_enable, 1'b1);
        expect1("ATTR line graphics output", attr_line_graphics_enable, 1'b0);
        attr_status_read();
        io_write(16'h03C0, 8'h33);
        io_write(16'h03C0, 8'h07);
        select_and_read_attr(5'h13, read_value);
        expect8("ATTR pixel panning register", read_value, 8'h07);
        expect8("ATTR pixel pan output", {4'h0, attr_pixel_pan_out}, 8'h07);

        begin_test("attribute palette remap and overscan width");
        attr_write_reg(5'h02, 8'h2A);
        attr_write_reg(5'h11, 8'h35);
        attr_write_reg(5'h12, 8'h0F);
        attr_palette_64_mode = 1'b1;
        expect_attr_output("ATTR palette remaps plane index", 4'h2, 1'b1, 1'b1, 6'h2A, 1'b1);
        expect_attr_output("ATTR 64-color overscan", 4'h2, 1'b1, 1'b0, 6'h35, 1'b0);
        attr_palette_64_mode = 1'b0;
        expect_attr_output("ATTR 16-color overscan truncates", 4'h2, 1'b1, 1'b0, 6'h05, 1'b0);
        attr_palette_64_mode = 1'b1;
        attr_write_reg(5'h02, 8'h02);
        attr_display_enable = 1'b1;

        begin_test("attribute plane enable masks graphics color index");
        attr_write_reg(5'h10, 8'h01);
        expect_attr_plane_enable("ATTR plane enable mask 0001", 4'hF, 4'h1, 6'h01);
        expect_attr_plane_enable("ATTR plane enable mask 0010", 4'hF, 4'h2, 6'h02);
        expect_attr_plane_enable("ATTR plane enable mask 0100", 4'hF, 4'h4, 6'h04);
        expect_attr_plane_enable("ATTR plane enable mask 1000", 4'hF, 4'h8, 6'h08);
        expect_attr_plane_enable("ATTR plane enable mask 0101", 4'hF, 4'h5, 6'h05);
        expect_attr_plane_enable("ATTR plane enable mask 1010", 4'hF, 4'hA, 6'h0A);
        expect_attr_plane_enable("ATTR plane enable mask 0000", 4'hF, 4'h0, 6'h00);
        expect_attr_plane_enable("ATTR plane enable preserves source zeroes", 4'hA, 4'hF, 6'h0A);

        begin_test("attribute active display and border gating");
        attr_write_reg(5'h10, 8'h01);
        attr_write_reg(5'h11, 8'h2A);
        attr_write_reg(5'h12, 8'h0F);
        expect_attr_output("ATTR active valid pixel", 4'h6, 1'b1, 1'b1, 6'h06, 1'b1);
        expect_attr_output("ATTR active invalid pixel blanks", 4'h9, 1'b0, 1'b1, 6'h00, 1'b1);
        expect_attr_output("ATTR display disable selects overscan", 4'h9, 1'b1, 1'b0, 6'h2A, 1'b0);
        attr_select_index(5'h10, 1'b0);
        expect_attr_output("ATTR video disabled blanks active area", 4'h7, 1'b1, 1'b1, 6'h00, 1'b0);
        attr_write_reg(5'h10, 8'h01);
        attr_pixel_valid = 1'b1;
        attr_display_enable = 1'b1;

        begin_test("CRTC EGA write protection");
        crtc_write(1'b0, 8'h01);
        crtc_write(1'b1, 8'h28);
        expect8("CRTC H displayed initial write", crtc_h_displayed, 8'h28);
        crtc_write(1'b0, 8'h11);
        crtc_write(1'b1, 8'h80);
        expect8("CRTC protection register", crtc_r11_debug, 8'h80);
        crtc_write(1'b0, 8'h01);
        crtc_write(1'b1, 8'h34);
        expect8("CRTC protected register 01h", crtc_h_displayed, 8'h28);
        crtc_write(1'b0, 8'h11);
        crtc_write(1'b1, 8'h00);
        crtc_write(1'b0, 8'h01);
        crtc_write(1'b1, 8'h34);
        expect8("CRTC unprotected register 01h", crtc_h_displayed, 8'h34);

        begin_test("CRTC overflow timing formulas");
        crtc_write(1'b0, 8'h06);
        crtc_write(1'b1, 8'hAA);
        crtc_write(1'b0, 8'h12);
        crtc_write(1'b1, 8'h55);
        crtc_write(1'b0, 8'h10);
        crtc_write(1'b1, 8'h33);
        crtc_write(1'b0, 8'h18);
        crtc_write(1'b1, 8'hFE);
        crtc_write(1'b0, 8'h09);
        crtc_write(1'b1, 8'h40);
        crtc_write(1'b0, 8'h07);
        crtc_write(1'b1, 8'hF7);
        expect16("CRTC vtotal uses overflow bits 07h[5,0]",
                 {6'd0, crtc_dut.eff_v_total}, 16'h03AC);
        expect16("CRTC display end uses overflow bits 07h[6,1]",
                 {6'd0, crtc_dut.eff_v_displayed}, 16'h0356);
        expect16("CRTC vsync start uses overflow bits 07h[7,2]",
                 {6'd0, crtc_dut.eff_v_sync_pos}, 16'h0334);
        expect16("CRTC split uses 09h[6], 07h[4], 18h plus one",
                 {5'd0, crtc_dut.line_compare_target}, 16'h03FF);

        begin_test("CRTC scanout address remap");
        expect_crtc_scanout("CRTC word mode using MA13",
                            16'h9234, 5'd0, 8'h00, 8'h83);
        expect_crtc_scanout("CRTC byte mode",
                            16'h9234, 5'd0, 8'h00, 8'hC3);
        expect_crtc_scanout("CRTC word mode using MA15",
                            16'h9234, 5'd0, 8'h00, 8'hA3);
        expect_crtc_scanout("CRTC dword mode",
                            16'h9234, 5'd0, 8'h40, 8'h83);
        expect_crtc_scanout("CRTC scanline substitutes MA13 and MA14",
                            16'h0234, 5'd3, 8'h00, 8'h80);

        begin_test("CRTC row advance and maximum scan line");
        crtc_write(1'b0, 8'h13);
        crtc_write(1'b1, 8'h14);
        crtc_write(1'b0, 8'h09);
        crtc_write(1'b1, 8'h07);
        expect16("CRTC row advance is offset << 1 in independent-plane RAM",
                 crtc_dut.ega_row_advance, 16'h0028);
        expect8("CRTC max scan line output uses low five bits",
                {3'b000, crtc_v_maxscan}, 8'h07);
        crtc_write(1'b0, 8'h09);
        crtc_write(1'b1, 8'h87);
        expect16("CRTC line-doubling row advance is offset << 2",
                 crtc_dut.ega_row_advance, 16'h0050);
        expect8("CRTC max scan line ignores line-double bit",
                {3'b000, crtc_v_maxscan}, 8'h07);

        begin_test("CRTC start address frame latch");
        crtc_write(1'b0, 8'h13);
        crtc_write(1'b1, 8'h00);
        crtc_dut.start_addr_frame = 16'h1234;
        crtc_dut.cursor_addr_frame = 14'h0123;
        crtc_dut.row_addr_r = 16'h0000;
        crtc_write(1'b0, 8'h0C);
        crtc_write(1'b1, 8'h56);
        crtc_write(1'b0, 8'h0D);
        crtc_write(1'b1, 8'h78);
        crtc_write(1'b0, 8'h0E);
        crtc_write(1'b1, 8'h04);
        crtc_write(1'b0, 8'h0F);
        crtc_write(1'b1, 8'h56);
        expect16("CRTC start address write updates pending latch",
                 crtc_dut.start_addr_latch, 16'h5678);
        expect16("CRTC cursor writes do not change current frame cursor",
                 {2'b00, crtc_dut.cursor_addr_frame}, 16'h0123);
        force crtc_dut.CRTC1_reload = 1'b1;
        force crtc_dut.frame_new = 1'b0;
        force crtc_dut.hcc_last = 1'b1;
        force crtc_dut.row_addr_save = 1'b0;
        @(posedge clk);
        #1 expect16("CRTC first-row reload keeps current frame start",
                    crtc_dut.row_addr_r, 16'h1234);
        crtc_dut.row_addr_r = 16'h0000;
        force crtc_dut.frame_new = 1'b1;
        @(posedge clk);
        #1 begin
            expect16("CRTC frame reload applies pending start address",
                     crtc_dut.row_addr_r, 16'h5678);
            expect16("CRTC visible frame start updates at frame boundary",
                     crtc_dut.start_addr_frame, 16'h5678);
            expect16("CRTC visible cursor address updates at frame boundary",
                     {2'b00, crtc_dut.cursor_addr_frame}, 16'h0456);
        end
        release crtc_dut.CRTC1_reload;
        release crtc_dut.frame_new;
        release crtc_dut.hcc_last;
        release crtc_dut.row_addr_save;

        begin_test("CRTC split resets address and scanline");
        crtc_write(1'b0, 8'h13);
        crtc_write(1'b1, 8'h14);
        crtc_dut.row_addr = 16'h5555;
        crtc_dut.row_addr_r = 16'hAAAA;
        crtc_dut.line = 5'd9;
        force crtc_dut.line_compare_match = 1'b1;
        force crtc_dut.hcc_last = 1'b0;
        @(posedge clk);
        #1 begin
            expect16("CRTC split resets saved row address",
                     crtc_dut.row_addr, 16'h0000);
            expect16("CRTC split resets current row address",
                     crtc_dut.row_addr_r, 16'h0000);
            expect8("CRTC split resets scanline",
                    {3'b000, crtc_dut.line}, 8'h00);
        end
        release crtc_dut.line_compare_match;
        release crtc_dut.hcc_last;

        begin_test("CRTC sampled address and blanking outputs");
        crtc_write(1'b0, 8'h14);
        crtc_write(1'b1, 8'h00);
        crtc_write(1'b0, 8'h17);
        crtc_write(1'b1, 8'hC3);
        crtc_dut.row_addr_r = 16'h002A;
        crtc_dut.line = 5'd4;
        crtc_dut.hcc = 8'd7;
        crtc_dut.row = 10'd9;
        crtc_dut.hde = 1'b1;
        crtc_dut.vde = 1'b1;
        crtc_dut.vde_r = 1'b1;
        crtc_dut.ega_vert_blank_active_r = 1'b0;
        #1 begin
            expect16("CRTC sampled byte-mode fetch address",
                     crtc_ma_full, expected_scanout_addr(16'h002A, 5'd4, 8'h00, 8'hC3));
            expect8("CRTC sampled row address output",
                    {3'b000, crtc_ra}, 8'h04);
            expect8("CRTC sampled horizontal counter",
                    crtc_hc, 8'h07);
            expect8("CRTC sampled vertical counter",
                    {1'b0, crtc_vc}, 8'h09);
            expect1("CRTC display enable asserted in visible area",
                    crtc_de, 1'b1);
            expect1("CRTC hblank clear in visible area",
                    crtc_hblank, 1'b0);
            expect1("CRTC vblank clear in visible area",
                    crtc_vblank, 1'b0);
        end
        crtc_dut.hde = 1'b0;
        #1 begin
            expect1("CRTC hblank follows horizontal display disable",
                    crtc_hblank, 1'b1);
            expect1("CRTC display enable clears during hblank",
                    crtc_de, 1'b0);
        end
        crtc_dut.hde = 1'b1;
        crtc_dut.ega_vert_blank_active_r = 1'b1;
        #1 begin
            expect1("CRTC vblank follows EGA vertical blank state",
                    crtc_vblank, 1'b1);
            expect1("CRTC not-displaying status follows EGA blanking",
                    crtc_status_not_displaying, 1'b1);
            expect1("CRTC vertical blank debug follows EGA blanking",
                    crtc_vert_blank_active, 1'b1);
        end

        begin_test("top-level misc output and color CRTC ports");
        top_io_read(16'h03CC, read_value);
        expect8("Misc Output reset", read_value, 8'h63);
        top_io_write(16'h03D4, 8'h12);
        top_io_write(16'h03D5, 8'h44);
        top_io_read(16'h03D5, read_value);
        expect8("color CRTC data readback", read_value, 8'h44);

        begin_test("top-level mono CRTC port selection");
        top_io_write(16'h03C2, 8'h62);
        top_io_write(16'h03B4, 8'h12);
        top_io_write(16'h03B5, 8'h55);
        top_io_read(16'h03B5, read_value);
        expect8("mono CRTC data readback", read_value, 8'h55);
        top_io_write(16'h03D4, 8'h12);
        top_io_write(16'h03D5, 8'h77);
        top_io_read(16'h03B5, read_value);
        expect8("color CRTC write ignored in mono mode", read_value, 8'h55);
        top_io_write(16'h03C2, 8'h63);
        top_io_read(16'h03D5, read_value);
        expect8("color CRTC sees shared EGA CRTC after reselect", read_value, 8'h55);

        begin_test("top-level selected status read side effects");
        top_io_read(16'h03DA, read_value);
        top_io_write(16'h03C0, 8'h24);
        top_io_write(16'h03C0, 8'h3C);
        top_select_and_read_attr(16'h03DA, 5'h04, read_value);
        expect8("color status resets ATTR flip-flop", read_value, 8'h3C);
        top_io_write(16'h03C2, 8'h62);
        top_io_read(16'h03BA, read_value);
        top_io_write(16'h03C0, 8'h25);
        top_io_read(16'h03DA, read_value);
        top_io_write(16'h03C0, 8'h5A);
        top_select_and_read_attr(16'h03BA, 5'h05, read_value);
        expect8("unselected color status does not reset ATTR flip-flop", read_value, 8'h5A);
        top_io_read(16'h03BA, status_a);
        top_io_read(16'h03BA, status_b);
        expect_true("selected status read toggles bits 5:4", ((status_a ^ status_b) & 8'h30) == 8'h30);
        force top_dut.ega_status_not_displaying_crtc = 1'b1;
        force top_dut.ega_status_vretrace_crtc = 1'b1;
        top_io_read(16'h03BA, status_a);
        expect8("selected status exposes blanking and retrace bits", status_a & 8'h09, 8'h09);
        force top_dut.ega_status_not_displaying_crtc = 1'b0;
        force top_dut.ega_status_vretrace_crtc = 1'b0;
        top_io_read(16'h03BA, status_a);
        expect8("selected status clears blanking and retrace bits", status_a & 8'h09, 8'h00);
        release top_dut.ega_status_not_displaying_crtc;
        release top_dut.ega_status_vretrace_crtc;

        if (failures == 0) begin
            $display("PASS: ega_registers_tb");
        end else begin
            $display("FAIL: ega_registers_tb failures=%0d", failures);
            $fatal(1);
        end
        $finish;
    end

endmodule
