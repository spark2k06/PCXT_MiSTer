`timescale 1ns / 1ps

module mcga_mode13_bios_ctrl_tb;

    reg         clk = 1'b0;
    reg         reset = 1'b1;
    reg [14:0]  bus_a = 15'h0000;
    reg         bus_ior_l = 1'b1;
    reg         bus_iow_l = 1'b1;
    reg         bus_memr_l = 1'b1;
    reg         bus_memw_l = 1'b1;
    reg [7:0]   bus_d = 8'h00;
    reg         mcga_enabled = 1'b1;
    wire [4:0]  clkdiv;
    wire [7:0]  bus_out;
    wire        bus_dir;
    wire        bus_rdy;
    wire        ram_we_l;
    wire [18:0] ram_a;
    wire [15:0] ega_fetch_addr;
    wire        ega_fetch_en;
    wire [15:0] ega_text_cell_addr;
    wire [15:0] ega_text_font_addr;
    wire        ega_text_fetch_en;
    wire [15:0] mcga_framebuffer_addr;
    wire        mcga_framebuffer_read_en;
    wire        mcga_mode13_active;

    integer failures = 0;

    ega_top dut (
        .clk(clk),
        .reset(reset),
        .clkdiv(clkdiv),
        .bus_a(bus_a),
        .bus_ior_l(bus_ior_l),
        .bus_iow_l(bus_iow_l),
        .bus_memr_l(bus_memr_l),
        .bus_memw_l(bus_memw_l),
        .bus_d(bus_d),
        .bus_out(bus_out),
        .bus_dir(bus_dir),
        .bus_aen(1'b0),
        .bus_rdy(bus_rdy),
        .ram_we_l(ram_we_l),
        .ram_a(ram_a),
        .ram_d(8'h00),
        .ram_data_valid(1'b1),
        .ega_fetch_addr(ega_fetch_addr),
        .ega_fetch_en(ega_fetch_en),
        .ega_plane0_data(8'h00),
        .ega_plane1_data(8'h00),
        .ega_plane2_data(8'h00),
        .ega_plane3_data(8'h00),
        .ega_fetch_data_valid(1'b0),
        .ega_text_cell_addr(ega_text_cell_addr),
        .ega_text_font_addr(ega_text_font_addr),
        .ega_text_fetch_en(ega_text_fetch_en),
        .ega_text_char(8'h00),
        .ega_text_attr(8'h00),
        .ega_text_glyph(8'h00),
        .ega_text_data_valid(1'b0),
        .mcga_framebuffer_addr(mcga_framebuffer_addr),
        .mcga_framebuffer_read_en(mcga_framebuffer_read_en),
        .mcga_framebuffer_pixel(8'h00),
        .mcga_framebuffer_data_valid(1'b0),
        .cpu_mem_select(1'b0),
        .cpu_mem_write(1'b0),
        .ega_cfg_toggle(),
        .ega_plane_write_mask_out(),
        .ega_odd_even_mode_out(),
        .ega_cpu_access_slot_out(),
        .ega_chain2_write_out(),
        .ega_chain2_read_out(),
        .ega_extended_memory_out(),
        .ega_mem_map_sel_out(),
        .ega_page_select_out(),
        .ega_write_mode_out(),
        .ega_read_mode_out(),
        .ega_read_plane_sel_out(),
        .ega_color_compare_out(),
        .ega_color_dont_care_out(),
        .ega_bit_mask_out(),
        .ega_set_reset_out(),
        .ega_enable_set_reset_out(),
        .ega_rop_select_out(),
        .ega_rotate_count_out(),
        .ega_blink_counter_out(),
        .ega_blink_state_out(),
        .hsync(),
        .hblank(),
        .dbl_hsync(),
        .vsync(),
        .vblank(),
        .vblank_border(),
        .std_hsyncwidth(),
        .de_o(),
        .video(),
        .dbl_video(),
        .comp_video(),
        .ega_red(),
        .ega_green(),
        .ega_blue(),
        .ega_rgb_active(),
        .ega_display_sel_out(),
        .splashscreen(1'b0),
        .thin_font(1'b0),
        .scandouble_en(1'b0),
        .ega_enabled(1'b1),
        .mcga_enabled(mcga_enabled),
        .mcga_mode13_set(1'b0),
        .mcga_mode13_clear(1'b0),
        .mcga_mode13_active_out(mcga_mode13_active),
        .grph_mode(),
        .hres_mode(),
        .crt_h_offset(4'h0),
        .crt_v_offset(3'h0),
        .vsync_width_osd(3'h0),
        .hsync_width_osd(3'h0)
    );

    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*80-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL %0s", message);
                failures = failures + 1;
            end
        end
    endtask

    task write_port_03cd;
        input [7:0] value;
        begin
            bus_a = 15'h03CD;
            bus_d = value;
            bus_iow_l = 1'b0;
            @(posedge clk);
            #1;
            bus_iow_l = 1'b1;
            bus_a = 15'h0000;
            bus_d = 8'h00;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        #1;

        mcga_enabled = 1'b0;
        write_port_03cd(8'h13);
        check(!mcga_mode13_active, "MCGA gate blocks development mode13 port");

        mcga_enabled = 1'b1;
        write_port_03cd(8'h13);
        check(mcga_mode13_active, "03CDh write 13h enters mode13");
        check(mcga_framebuffer_read_en, "mode13 renderer starts framebuffer fetches");

        write_port_03cd(8'h03);
        check(!mcga_mode13_active, "03CDh non-13h write exits mode13");
        check(!mcga_framebuffer_read_en, "mode13 renderer stops after exit");

        if (failures == 0) begin
            $display("PASS mcga_mode13_bios_ctrl_tb");
            $finish;
        end

        $display("FAIL mcga_mode13_bios_ctrl_tb failures=%0d", failures);
        $finish;
    end

endmodule
