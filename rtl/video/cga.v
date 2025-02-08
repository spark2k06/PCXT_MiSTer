// Graphics Gremlin
//
// Copyright (c) 2021 Eric Schlaepfer
// This work is licensed under the Creative Commons Attribution-ShareAlike 4.0
// International License. To view a copy of this license, visit
// http://creativecommons.org/licenses/by-sa/4.0/ or send a letter to Creative
// Commons, PO Box 1866, Mountain View, CA 94042, USA.
//
`default_nettype wire
module cga(
    // Clocks
    input clk,
    output [4:0] clkdiv,

    // ISA bus
    input[14:0] bus_a,
    input bus_ior_l,
    input bus_iow_l,
    input bus_memr_l,
    input bus_memw_l,
    input[7:0] bus_d,
    output[7:0] bus_out,
    output bus_dir,
    input bus_aen,
    output bus_rdy,

    // RAM
    output ram_we_l,
    output[18:0] ram_a,
    input[7:0] ram_d,

    // Video outputs
    output hsync,
    output hblank,
    output dbl_hsync,
    output vsync,
    output vblank,
    output vblank_border,
    output std_hsyncwidth,
    output de_o,
    output[3:0] video,
    output[3:0] dbl_video,
    output[6:0] comp_video,

    input splashscreen,
    input thin_font,
    input tandy_video,     
    output grph_mode,
    output hres_mode,
    output tandy_color_16,
    input cga_hw,
    input[3:0] crt_h_offset,
    input[2:0] crt_v_offset
    );

    parameter MDA_70HZ = 0;
    parameter BLINK_MAX = 0;
    // `define CGA_SNOW = 1; No snow

    parameter USE_BUS_WAIT = 0; // Should we add wait states on the ISA bus?
    parameter NO_DISPLAY_DISABLE = 0; // If 1, prevents flicker artifacts in DOS

    parameter IO_BASE_ADDR = 16'h3d0; // MDA is 3B0, CGA is 3D0
    // parameter FRAMEBUFFER_ADDR = 20'hB8000; // MDA is B0000, CGA is B8000

    wire crtc_cs;
    wire status_cs;
     wire tandy_newcolorsel_cs;
    wire colorsel_cs;
    wire control_cs;
    //wire bus_mem_cs;

    reg[7:0] bus_int_out;
    wire[7:0] bus_out_crtc;
    wire[7:0] bus_out_mem;
    wire[7:0] cga_status_reg;
    reg[7:0] cga_control_reg = 8'b0010_1001; // (TEXT 80x25)
    //reg[7:0] cga_control_reg = 8'b0010_1010; // (GFX 320 x 200)
    reg[7:0] cga_color_reg = 8'b0000_0000;
    reg[7:0] tandy_color_reg = 8'b0000_0000;
    reg[3:0] tandy_newcolor = 4'b0000;
    reg[3:0] tandy_bordercol = 4'b0000;
	 reg[4:0] tandy_modesel = 5'b00000;
    reg tandy_palette_set;

    wire bw_mode;
    wire mode_640;
    wire tandy_16_mode;
    wire video_enabled;
    wire blink_enabled;
	 
	 wire tandy_border_en;
	 wire tandy_color_4;

    wire hsync_int;
    wire vsync_l;
    wire cursor;
    wire display_enable;

    // Two different clocks from the sequencer
    wire hclk;
    wire lclk;

    wire[13:0] crtc_addr;
    wire[4:0] row_addr;
    wire line_reset;
    wire pixel_addr13;
    wire pixel_addr14;

    wire charrom_read;
    wire disp_pipeline;
    wire isa_op_enable;
    wire vram_read_char;
    wire vram_read_att;
    wire vram_read;
    wire vram_read_a0;
//    wire[4:0] clkdiv;
    wire crtc_clk;
    wire[7:0] ram_1_d;

    reg[23:0] blink_counter = 24'd0;
    reg blink = 0;     

    reg bus_memw_synced_l;
    reg bus_memr_synced_l;
    reg bus_ior_synced_l;
    reg bus_iow_synced_l;

    //wire cpu_memsel;
    //reg[1:0] wait_state = 2'd0;
    //reg bus_rdy_latch; 

    assign de_o = display_enable;
    
    assign ram_a = {4'h0, pixel_addr14, pixel_addr13, crtc_addr[11:0],
                    vram_read_a0};

    assign ram_1_d = ram_d;
    //assign ram_1_d = 8'hFF;
    assign ram_we_l = vram_read;
    

    // Synchronize ISA bus control lines to our clock
    always @ (posedge clk)
    begin
        //bus_memw_synced_l <= bus_memw_l;
        //bus_memr_synced_l <= bus_memr_l;
        bus_ior_synced_l <= bus_ior_l;
        bus_iow_synced_l <= bus_iow_l;
    end

    // Some modules need a non-inverted vsync trigger
    assign vsync = ~vsync_l;

    // Mapped IO
    assign crtc_cs = (bus_a[14:3] == IO_BASE_ADDR[14:3]) & ~bus_aen & cga_hw; // 3D4/3D5
    assign status_cs = (bus_a == IO_BASE_ADDR + 20'hA) & ~bus_aen & cga_hw;
    assign tandy_newcolorsel_cs = (bus_a == IO_BASE_ADDR + 20'hE) & ~bus_aen & cga_hw;
    assign control_cs = (bus_a == IO_BASE_ADDR + 16'h8) & ~bus_aen & cga_hw;
    assign colorsel_cs = (bus_a == IO_BASE_ADDR + 20'h9) & ~bus_aen & cga_hw;
    // Memory-mapped from B0000 to B7FFF
    //assign bus_mem_cs = (bus_a[19:15] == FRAMEBUFFER_ADDR[19:15]);
    //assign bus_mem_cs = 1'b1;


    // Mux ISA bus data from every possible internal source.
    always @ (*)
    begin
//        if (bus_mem_cs & ~bus_memr_l) begin
//            bus_int_out <= bus_out_mem;
        if (status_cs & ~bus_ior_l) begin
            bus_int_out <= cga_status_reg;
        end else if (crtc_cs & ~bus_ior_l & (bus_a[0] == 1)) begin
            bus_int_out <= bus_out_crtc;
        end else begin
            bus_int_out <= 8'h00;
        end
    end

    // Only for read operations does bus_dir go high.
    assign bus_dir = (crtc_cs | status_cs) & ~bus_ior_l;
    //                | (bus_mem_cs & ~bus_memr_l);
    //assign bus_dir = (crtc_cs | status_cs);
    assign bus_out = bus_int_out;

    // Wait state generator
    // Optional for operation but required to run timing-sensitive demos
    // e.g. 8088MPH.
    /*
    if (USE_BUS_WAIT == 0) begin
        assign bus_rdy = 1;
    end else begin
        assign bus_rdy = bus_rdy_latch;
    end
    */

/*
    assign cpu_memsel = bus_mem_cs & (~bus_memr_l | ~bus_memw_l);

    always @ (posedge clk)
    begin
        if (cpu_memsel) begin
            case (wait_state)
                2'b00: begin
                    if (clkdiv == 5'd17) wait_state <= 2'b01;
                    bus_rdy_latch <= 0;
                end
                2'b01: begin
                    if (clkdiv == 5'd20) wait_state <= 2'b10;
                    bus_rdy_latch <= 0;
                end
                2'b10: begin
                    wait_state <= 2'b10;
                    bus_rdy_latch <= 1;
                end
                default: begin
                    wait_state <= 2'b00;
                    bus_rdy_latch <= 0;
                end
            endcase
        end else begin
            wait_state <= 2'b00;
            bus_rdy_latch <= 1;
        end
    end
*/

    // status register (read only at 3BA)
    // FIXME: vsync_l should be delayed/synced to HCLK.
    assign cga_status_reg = {4'b1111, vsync_l, 2'b10, ~display_enable};

    // mode control register (write only)
    //
    assign hres_mode = cga_control_reg[0]; // 1=80x25,0=40x25
    assign grph_mode = cga_control_reg[1]; // 1=graphics, 0=text
    assign bw_mode = cga_control_reg[2]; // 1=b&w, 0=color

    assign video_enabled = NO_DISPLAY_DISABLE ? 1'b1 : cga_control_reg[3];
     
    assign mode_640 = cga_control_reg[4]; // 1=640x200 mode, 0=others
    assign blink_enabled = cga_control_reg[5];
	 
	 assign tandy_border_en = tandy_modesel[2];
	 assign tandy_color_4 = tandy_modesel[3];
	 assign tandy_color_16 = tandy_modesel[4];

    assign tandy_16_mode = tandy_video;

    assign hsync = hsync_int;

    // Update control or color register
    always @ (posedge clk)
    begin
        tandy_palette_set <= 1'b0;
        if (~bus_iow_synced_l) begin
            if (control_cs) begin
                cga_control_reg <= bus_d;
            end else if (colorsel_cs) begin
                cga_color_reg <= bus_d;
            end else if (status_cs) begin
                tandy_color_reg <= bus_d;
            end else if (tandy_newcolorsel_cs && tandy_color_reg[7:4] == 4'b0001) begin // Palette Mask Register
                tandy_newcolor <= bus_d[3:0];
                     tandy_palette_set <= 1'b1;
                end else if (tandy_newcolorsel_cs && tandy_color_reg[3:0] == 4'b0010) begin // Border Color
                tandy_bordercol <= bus_d[3:0];
            end else if (tandy_newcolorsel_cs && tandy_color_reg[3:0] == 4'b0011) begin // Mode Select
                tandy_modesel <= bus_d[4:0];
            end

        end
    end 
	 
	
    UM6845R crtc (
        .CLOCK(clk),
		  .CLKEN(crtc_clk), 
		  // .nCLKEN(),
		  .nRESET(1'b1),
		  .CRTC_TYPE(1'b1),
		  
		  .ENABLE(1'b1),
		  .nCS(~crtc_cs),
		  .R_nW(bus_iow_synced_l),
		  .RS(bus_a[0]),
		  .DI(bus_d),
		  .DO(bus_out_crtc),
		  
		  .hblank(hblank),
		  .vblank(vblank),
		  .line_reset(line_reset),
		  
		  .VSYNC(vsync_l),
		  .HSYNC(hsync_int),
		  .DE(display_enable),
		  // .FIELD(),
		  .CURSOR(cursor),
		  
		  .MA(crtc_addr),
		  .RA(row_addr),
		  
                  .crt_h_offset(crt_h_offset),
                  .crt_v_offset(crt_v_offset)

	 );

    // CGA 80 column timings
    defparam crtc.H_TOTAL = 8'd113; // 113 // 56
    defparam crtc.H_DISP = 8'd80;   // 80 // 40
    defparam crtc.H_SYNCPOS = 8'd90;    // 90 // 45
    defparam crtc.H_SYNCWIDTH = 4'd10;
    defparam crtc.V_TOTAL = 7'd31;
    defparam crtc.V_TOTALADJ = 5'd6;
    defparam crtc.V_DISP = 7'd25;
    defparam crtc.V_SYNCPOS = 7'd28;
    defparam crtc.V_MAXSCAN = 5'd7;
    defparam crtc.C_START = 7'd6;
    defparam crtc.C_END = 5'd7;
     

    // In graphics mode, memory address MSB comes from CRTC row
    // which produces the weird CGA "interlaced" memory map
    assign pixel_addr13 = grph_mode ? row_addr[0] : crtc_addr[12];

    // Address bit 14 is only used for Tandy modes (32K RAM)
    assign pixel_addr14 = grph_mode ? row_addr[1] : 1'b0;

    // Sequencer state machine
    cga_sequencer sequencer (
        .clk(clk),
        .clk_seq(clkdiv),
        .vram_read(vram_read),
        .vram_read_a0(vram_read_a0),
        .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att),
        .hres_mode(hres_mode),
        .crtc_clk(crtc_clk),
        .charrom_read(charrom_read),
        .disp_pipeline(disp_pipeline),
        .isa_op_enable(isa_op_enable),
        .hclk(hclk),
        .lclk(lclk),
        .tandy_16_gfx(tandy_16_mode & grph_mode & hres_mode),
		  .tandy_color_16(tandy_color_16)
    );

    // Pixel pusher
    cga_pixel pixel (
        .clk(clk),
        .clk_seq(clkdiv),
        .hres_mode(hres_mode),
        .grph_mode(grph_mode),
        .bw_mode(bw_mode),
        .mode_640(mode_640),
        .tandy_16_mode(tandy_16_mode),
        .thin_font(thin_font),
        .vram_data(ram_1_d),
        .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att),
        .disp_pipeline(disp_pipeline),
        .charrom_read(charrom_read),
        .display_enable(display_enable),
        .cursor(cursor),
        .row_addr(row_addr),
        .blink_enabled(blink_enabled),
        .blink(blink),
        .hsync(hsync_int),
        .vsync(vsync_l),
        .video_enabled(video_enabled),
        .cga_color_reg(cga_color_reg),
        .tandy_palette_color(tandy_color_reg[3:0]),
        .tandy_newcolor(tandy_newcolor),
        .tandy_palette_set(tandy_palette_set),
        .tandy_bordercol(tandy_bordercol),
        .tandy_color_4(tandy_color_4),
        .tandy_color_16(tandy_color_16),
        .video(video)
    );

    // Generate blink signal for cursor and character
    always @ (posedge clk)
    begin
        if (~splashscreen) begin
        if (blink_counter == BLINK_MAX) begin
            blink_counter <= 0;
            blink <= ~blink;
        end else begin
            blink_counter <= blink_counter + 1'b1;
        end
        end
    end

    /*
    cga_scandoubler scandoubler (
        .clk(clk),
        .line_reset(line_reset),
        .video(video),          
        .dbl_hsync(dbl_hsync),
        .dbl_video(dbl_video)
    );
    */

endmodule
