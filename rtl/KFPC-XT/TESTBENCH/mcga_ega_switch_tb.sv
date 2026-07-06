`timescale 1ns / 1ps

module mcga_ega_switch_tb;

    reg         clk = 1'b0;
    reg         reset = 1'b1;
    reg [14:0]  bus_a = 15'h0000;
    reg         bus_ior_l = 1'b1;
    reg         bus_iow_l = 1'b1;
    reg         bus_memr_l = 1'b1;
    reg         bus_memw_l = 1'b1;
    reg [7:0]   bus_d = 8'h00;
    wire [7:0]  bus_out;
    wire        bus_dir;
    wire [4:0]  clkdiv;
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
    reg  [7:0]  mcga_framebuffer_pixel = 8'h0F;
    reg         mcga_framebuffer_data_valid = 1'b0;
    wire        hsync;
    wire        hblank;
    wire        dbl_hsync;
    wire        vsync;
    wire        vblank;
    wire        vblank_border;
    wire        std_hsyncwidth;
    wire        de_o;
    wire [3:0]  video;
    wire [3:0]  dbl_video;
    wire [6:0]  comp_video;
    wire [5:0]  ega_red;
    wire [5:0]  ega_green;
    wire [5:0]  ega_blue;
    wire        ega_rgb_active;
    wire        ega_display_sel_out;
    reg         mcga_mode13_set = 1'b0;
    reg         mcga_mode13_clear = 1'b0;
    wire        mcga_mode13_active;
    wire        grph_mode;
    wire        hres_mode;

    integer failures = 0;
    integer i;
    integer saw_mcga_pixel = 0;

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
        .mcga_framebuffer_pixel(mcga_framebuffer_pixel),
        .mcga_framebuffer_data_valid(mcga_framebuffer_data_valid),
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
        .hsync(hsync),
        .hblank(hblank),
        .dbl_hsync(dbl_hsync),
        .vsync(vsync),
        .vblank(vblank),
        .vblank_border(vblank_border),
        .std_hsyncwidth(std_hsyncwidth),
        .de_o(de_o),
        .video(video),
        .dbl_video(dbl_video),
        .comp_video(comp_video),
        .ega_red(ega_red),
        .ega_green(ega_green),
        .ega_blue(ega_blue),
        .ega_rgb_active(ega_rgb_active),
        .ega_display_sel_out(ega_display_sel_out),
        .splashscreen(1'b0),
        .thin_font(1'b0),
        .scandouble_en(1'b0),
        .ega_enabled(1'b1),
        .mcga_mode13_set(mcga_mode13_set),
        .mcga_mode13_clear(mcga_mode13_clear),
        .mcga_mode13_active_out(mcga_mode13_active),
        .grph_mode(grph_mode),
        .hres_mode(hres_mode),
        .crt_h_offset(4'h0),
        .crt_v_offset(3'h0),
        .vsync_width_osd(3'h0),
        .hsync_width_osd(3'h0)
    );

    always #5 clk = ~clk;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mcga_framebuffer_data_valid <= 1'b0;
        end else begin
            mcga_framebuffer_data_valid <= mcga_framebuffer_read_en;
        end
    end

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

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        check(!mcga_mode13_active, "mode13 inactive after reset");
        check(!mcga_framebuffer_read_en, "MCGA framebuffer idle before mode13");

        mcga_mode13_set = 1'b1;
        @(posedge clk);
        #1;
        mcga_mode13_set = 1'b0;
        check(mcga_mode13_active, "mode13 set activates MCGA path");

        for (i = 0; i < 32 && !saw_mcga_pixel; i = i + 1) begin
            @(posedge clk);
            #1;
            if (de_o) begin
                check(ega_rgb_active, "MCGA visible pixel marks RGB active");
                check(ega_display_sel_out, "MCGA visible pixel owns display select");
                check(ega_red == 6'h3F && ega_green == 6'h3F && ega_blue == 6'h3F,
                      "MCGA default DAC index 0F renders white");
                check(video == 4'h0 && dbl_video == 4'h0 && comp_video == 7'h00,
                      "MCGA output suppresses legacy indexed video buses");
                saw_mcga_pixel = 1;
            end
        end

        check(saw_mcga_pixel, "MCGA mode produces visible output");
        check(mcga_framebuffer_addr < 16'hFA00, "MCGA visible fetch stays inside visible range");
        check(!ega_fetch_en && !ega_text_fetch_en, "EGA fetches are blocked while MCGA owns output");

        mcga_mode13_clear = 1'b1;
        @(posedge clk);
        #1;
        mcga_mode13_clear = 1'b0;
        repeat (4) @(posedge clk);
        #1;

        check(!mcga_mode13_active, "mode13 clear exits MCGA path");
        check(!mcga_framebuffer_read_en, "MCGA framebuffer fetch stops after clear");
        check(!de_o, "unarmed EGA path has no MCGA visible output after clear");
        check(!ega_rgb_active, "RGB active returns to non-MCGA state after clear");

        if (failures == 0) begin
            $display("PASS mcga_ega_switch_tb");
            $finish;
        end

        $display("FAIL mcga_ega_switch_tb failures=%0d", failures);
        $finish;
    end

endmodule
