// Graphics Gremlin
//
// Copyright (c) 2021 Eric Schlaepfer
// This work is licensed under the Creative Commons Attribution-ShareAlike 4.0
// International License. To view a copy of this license, visit
// http://creativecommons.org/licenses/by-sa/4.0/ or send a letter to Creative
// Commons, PO Box 1866, Mountain View, CA 94042, USA.
//
`ifndef ENABLE_TANDY_VIDEO
`define ENABLE_TANDY_VIDEO 0
`endif
`ifndef ENABLE_PCJR
`define ENABLE_PCJR 0
`endif

`default_nettype wire
module cga(
    // Clocks
    input clk,
    input reset,
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
    output raw_hblank,
    output dbl_hsync,
    output vsync,
    output vblank,
    output vblank_border,
    output raw_vblank,
    output hsync_ref,               // syncs at MC6845 positions, for the border window
    output vsync_ref,
    output std_hsyncwidth,
    output de_o,
    output raw_de_o,
    output[3:0] video,
    output[3:0] dbl_video,
    output[6:0] comp_video,

    input splashscreen,
    output[14:0] splash_rom_addr,   // port A of splash_rom, outside the card
    input[7:0] splash_rom_q,
    input composite,
    input thin_font,
    input tandy_video,     
    // IBM PCjr: the gate array takes the place of the Tandy
    // registers. It implies tandy_video (video memory shared with the system)
    input pcjr,
    input [1:0] pcjr_addr_mode,     // 3DFh bits 7:6: address interleave
    input scandouble_en,
    // The cadence of the CRTC and of the memory fetch: the 80 column timing
    // (equal to hres_mode, except that the PCjr gate array sets it on its own)
    output crtc_2x,
    output tandy_16_gfx_o,          // the card's own tandy_16_gfx (blanking tap of the chipset)
    output grph_mode,
    output hres_mode,
    output bw_mode,
    output mode_640,
    output [3:0] composite_hsync_width,
    output [3:0] composite_border_color,
    output composite_phase,
    output tandy_color_16,
    input cga_hw,
    input[3:0] crt_h_offset,
    input[2:0] crt_v_offset,
    input[2:0] vsync_width_osd,
    input[2:0] hsync_width_osd,
    input frame_stack_rebuild,
    // Word of video memory (16 bits: character, attribute) that the CRTC will
    // address at its next character clock, for the memory fetch engine.
    // Registered, so it is settled one slot after the CRTC has advanced.
    output reg [13:0] fx_next_word
);

    // Keep the carrier/CRTC relationship independent of the boot-time clock
    // phase, while synchronizing reset release to the CGA clock domain.
    reg [1:0] video_reset_sync = 2'b11;
    always @(posedge clk or posedge reset) begin
        if (reset)
            video_reset_sync <= 2'b11;
        else
            video_reset_sync <= {video_reset_sync[0], 1'b0};
    end
    wire video_reset_local = video_reset_sync[1];

    // OSD bit from the chipset clock domain.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] frame_stack_sync = 2'b00;
    always @(posedge clk)
        frame_stack_sync <= {frame_stack_sync[0], frame_stack_rebuild};

    parameter MDA_70HZ = 0;
    parameter BLINK_MAX = 0;
    // `define CGA_SNOW = 1; No snow

    parameter USE_BUS_WAIT = 0; // Should we add wait states on the ISA bus?
    parameter NO_DISPLAY_DISABLE = 0; // If 1, prevents flicker artifacts in DOS
    localparam STD_HSYNCWIDTH = 4'd10;

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
    reg tandy_palette_set = 1'b0;

    wire tandy_16_mode = `ENABLE_TANDY_VIDEO ? tandy_video : 1'b0;
    wire video_enabled;
    wire blink_enabled;

    // IBM PCjr gate array: 16 mode/colour registers behind 3DAh (index, then
    // data, the flip-flop is cleared by reading 3DAh), 16 palette entries
    wire pcjr_video = `ENABLE_PCJR ? (tandy_video & pcjr) : 1'b0;
    reg [4:0] pcjr_array_index = 5'd0;
    reg       pcjr_array_ff = 1'b0;
    reg       pcjr_status_toggle = 1'b0;
    reg [7:0] pcjr_array [0:31];
    reg       pcjr_palette_write = 1'b0;
    reg [3:0] pcjr_palette_index = 4'd0;
    reg [3:0] pcjr_palette_value = 4'd0;
    integer   pcjr_i;
    initial begin
        for (pcjr_i = 0; pcjr_i < 32; pcjr_i = pcjr_i + 1)
            pcjr_array[pcjr_i] = 8'd0;
        pcjr_array[0] = 8'h09;
        pcjr_array[1] = 8'h0F;
        pcjr_array[2] = 8'h00;
        pcjr_array[3] = 8'h02;
    end
    // The mode: register 3 bit 3 and the mode bits of register 0
    wire [8:0] pcjr_mode_sel = {pcjr_array[3][3], (pcjr_array[0] & 8'h13)};
    wire pcjr_mode_text      = (pcjr_mode_sel == 9'h00) || (pcjr_mode_sel == 9'h01);
    wire pcjr_mode_16        = (pcjr_mode_sel == 9'h13) || (pcjr_mode_sel == 9'h12);
    wire pcjr_mode_640x200x2 = (pcjr_mode_sel == 9'h102);
    wire pcjr_mode_640       = (pcjr_mode_sel == 9'h03) || pcjr_mode_640x200x2;
    // 640x200x4 uses mode 03h; 320x200x4 (02h) packs like the CGA
    wire pcjr_color_4        = (pcjr_mode_sel == 9'h03);
    wire pcjr_grph_mode      = ~pcjr_mode_text;
    wire pcjr_bw_mode        = pcjr_array[0][2];
    // High resolution timing: register 0 bit 0, forced by 640x200x2
    wire pcjr_hres_mode      = pcjr_mode_640x200x2 ? 1'b1 : pcjr_array[0][0];
    wire pcjr_video_enabled  = pcjr_array[0][3];
    wire pcjr_blink_enabled  = pcjr_array[3][2];
    wire [3:0] pcjr_palette_mask = pcjr_array[1][3:0];
    wire [3:0] pcjr_border_color = pcjr_array[2][3:0];
    wire [7:0] pcjr_status_reg;

    // The Tandy video logic is built (ENABLE_TANDY_VIDEO) but only a Tandy 1000
    // uses it (tandy_video): in a PCXT it must neither answer 3DEh nor change
    // the address of a graphics mode.
    wire tandy_border_en = `ENABLE_TANDY_VIDEO ? (tandy_video & tandy_modesel[2]) : 1'b0;
    wire tandy_color_4 = `ENABLE_TANDY_VIDEO ? (pcjr_video ? pcjr_color_4 : (tandy_video & tandy_modesel[3])) : 1'b0;
    wire [3:0] border_color = pcjr_video ? pcjr_border_color : tandy_bordercol;

    wire hsync_int;
    wire hblank_crtc;
    wire vblank_crtc;
    wire vsync_l;
    wire vsync_sd_l;
    wire vblank_sd;
    wire cursor;
    wire display_enable;
    wire display_enable_sd;
    wire [3:0] hsync_width_crtc;
    wire composite_phase_crtc;

    // Two different clocks from the sequencer
    wire hclk;
    wire lclk;

    wire[13:0] crtc_addr;
    wire[4:0] row_addr;
    wire[13:0] crtc_addr_next;
    wire[4:0] row_addr_next;
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
    reg bus_ior_prev_l = 1'b1;
    reg bus_iow_prev_l = 1'b1;

    //wire cpu_memsel;
    //reg[1:0] wait_state = 2'd0;
    //reg bus_rdy_latch; 

    assign de_o = scandouble_en ? display_enable_sd : display_enable;
    assign hblank = scandouble_en ? ~display_enable_sd : hblank_crtc;
    // Keep the unmodified CRTC timing available to consumers that must
    // decode the native 14.318 MHz CGA stream before scan doubling.
    assign raw_hblank = hblank_crtc;
    assign raw_vblank = vblank_crtc;
    assign raw_de_o = display_enable;
    
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
        bus_ior_prev_l   <= bus_ior_synced_l;
        bus_iow_prev_l   <= bus_iow_synced_l;
    end
    // One-clock strobes: the gate array registers count accesses
    wire bus_ior_pulse = ~bus_ior_synced_l & bus_ior_prev_l;
    wire bus_iow_pulse = ~bus_iow_synced_l & bus_iow_prev_l;

    // Some modules need a non-inverted vsync trigger.
    // In scandoubled mode use VSYNC synthesized by the scandoubler.
    // Vertical picture window. A CRTC line with display off inside the picture
    // is part of the picture: a demo that ends the frame early to split the
    // screen (TETRA3D) shows the border colour there on a real CGA, not black.
    // The window is the first and last displayed line of the previous frame,
    // counted from VSYNC, so only the overscan outside the picture is blanked.
    reg        hblank_q = 1'b1, hsync_q = 1'b0, vsync_q = 1'b1;
    reg [9:0]  line_no = 10'd0;
    reg        disp_any = 1'b0;
    reg [9:0]  disp_first = 10'h3FF, disp_last = 10'h000;
    reg [9:0]  win_first = 10'h3FF, win_last = 10'h000;
    wire       frame_start = vsync_l & ~vsync_q;          // VSYNC has ended
    wire       line_start  = ~hblank_crtc & hblank_q;     // first character of a line
    wire       line_sync   = hsync_int & ~hsync_q;        // HSYNC of this line
    // The line index moves one clock after the blanking edge; use the index of
    // the line that is starting so its first pixel is judged in the same line.
    wire [9:0] line_now    = line_start ? line_no + 10'd1 : line_no;
    wire       in_window   = (line_now >= win_first) && (line_now <= win_last);
    wire       vblank_win  = vblank_crtc & (~in_window | vsync_l);

    always @(posedge clk) begin
        vsync_q  <= vsync_l;
        hblank_q <= hblank_crtc;
        hsync_q  <= hsync_int;
        if (frame_start) begin
            win_first  <= disp_any ? disp_first : 10'h3FF;
            win_last   <= disp_last;
            disp_any   <= 1'b0;
            disp_first <= 10'h3FF;
            disp_last  <= 10'h000;
            line_no    <= 10'd0;
        end else begin
            if (line_start) line_no <= line_no + 10'd1;
            if (line_sync && !vblank_crtc) begin
                disp_any <= 1'b1;
                if (line_no < disp_first) disp_first <= line_no;
                if (line_no > disp_last)  disp_last  <= line_no;
            end
        end
    end

    assign vsync = scandouble_en ? ~vsync_sd_l : ~vsync_l;
    assign vblank = scandouble_en ? vblank_sd : vblank_win;

    // Mapped IO
    assign crtc_cs = (bus_a[14:3] == IO_BASE_ADDR[14:3]) & ~bus_aen & cga_hw; // 3D4/3D5
    assign status_cs = (bus_a == IO_BASE_ADDR + 20'hA) & ~bus_aen & cga_hw;
    assign tandy_newcolorsel_cs = `ENABLE_TANDY_VIDEO ? ((bus_a == IO_BASE_ADDR + 20'hE) & ~bus_aen & cga_hw & tandy_video) : 1'b0;
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
            bus_int_out <= pcjr_video ? pcjr_status_reg : cga_status_reg;
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

    // VRAM lives outside this module in the MiSTer port, so its READY timing
    // is generated at the chipset boundary by CGA_BUS_WAIT. Keep this legacy
    // pin benign; it is not connected by the MiSTer integration.
    assign bus_rdy = 1'b1;

    // status register (read only at 3BA)
    // FIXME: vsync_l should be delayed/synced to HCLK.
    assign cga_status_reg = {4'b1111, vsync_l, 2'b10, ~display_enable};
    // PCjr: bit 3 vertical retrace, bit 0 display enable (active display high)
    assign pcjr_status_reg = {3'b000, pcjr_status_toggle, vsync_l, 2'b00, display_enable};

    // mode control register (write only)
    //
    assign hres_mode = pcjr_video ? pcjr_hres_mode : cga_control_reg[0]; // 1=80x25,0=40x25
    // What advances the CRTC and the fetch: the clock of the PCjr gate array
    assign crtc_2x   = pcjr_video ? pcjr_array[0][0] : cga_control_reg[0];
    assign grph_mode = pcjr_video ? pcjr_grph_mode : cga_control_reg[1]; // 1=graphics, 0=text
    assign bw_mode = pcjr_video ? pcjr_bw_mode : cga_control_reg[2]; // 1=b&w, 0=color
    assign composite_hsync_width = hsync_width_crtc;
    assign composite_border_color = cga_color_reg[3:0];
    assign composite_phase = composite_phase_crtc;

    assign video_enabled = pcjr_video ? pcjr_video_enabled :
        (NO_DISPLAY_DISABLE ? 1'b1 : cga_control_reg[3]);

    assign mode_640 = pcjr_video ? pcjr_mode_640 : cga_control_reg[4]; // 1=640x200 mode, 0=others
    assign blink_enabled = pcjr_video ? pcjr_blink_enabled : cga_control_reg[5];

    assign tandy_color_16 = `ENABLE_TANDY_VIDEO ? (pcjr_video ? pcjr_mode_16 : (tandy_video & tandy_modesel[4])) : 1'b0;
    assign std_hsyncwidth = (hsync_width_crtc == STD_HSYNCWIDTH);
    assign vblank_border = vblank;

    assign hsync = hsync_int;

    // Update control or color register
    always @ (posedge clk)
    begin
        tandy_palette_set <= 1'b0;
        pcjr_palette_write <= 1'b0;
        if (pcjr_video) begin
            // Gate array: reading 3DAh resets the index/data flip-flop
            if (status_cs && bus_ior_pulse) begin
                pcjr_array_ff <= 1'b0;
                pcjr_status_toggle <= ~pcjr_status_toggle;
            end
            if (status_cs && bus_iow_pulse) begin
                if (!pcjr_array_ff)
                    pcjr_array_index <= bus_d[4:0];
                else begin
                    pcjr_array[pcjr_array_index] <= pcjr_array_index[4] ? {4'b0000, bus_d[3:0]} : bus_d;
                    if (pcjr_array_index[4]) begin
                        pcjr_palette_write <= 1'b1;
                        pcjr_palette_index <= pcjr_array_index[3:0];
                        pcjr_palette_value <= bus_d[3:0];
                    end
                end
                pcjr_array_ff <= ~pcjr_array_ff;
            end
            if (~bus_iow_synced_l) begin
                if (control_cs)
                    cga_control_reg <= bus_d;
                else if (colorsel_cs)
                    cga_color_reg <= bus_d;
            end
        end else if (~bus_iow_synced_l) begin
            if (control_cs) begin
                cga_control_reg <= bus_d;
            end else if (colorsel_cs) begin
                cga_color_reg <= bus_d;
            end else if (`ENABLE_TANDY_VIDEO && tandy_video && status_cs) begin
                tandy_color_reg <= bus_d;
            end else if (`ENABLE_TANDY_VIDEO && tandy_newcolorsel_cs && tandy_color_reg[7:4] == 4'b0001) begin // Palette Mask Register
                tandy_newcolor <= bus_d[3:0];
                     tandy_palette_set <= 1'b1;
                end else if (`ENABLE_TANDY_VIDEO && tandy_newcolorsel_cs && tandy_color_reg[3:0] == 4'b0010) begin // Border Color
                tandy_bordercol <= bus_d[3:0];
            end else if (`ENABLE_TANDY_VIDEO && tandy_newcolorsel_cs && tandy_color_reg[3:0] == 4'b0011) begin // Mode Select
                tandy_modesel <= bus_d[4:0];
            end

        end
    end 
	 
	
    UM6845R_cga crtc (
        .CLOCK(clk),
		  .CLKEN(crtc_clk), 
		  // .nCLKEN(),
        .nRESET(~video_reset_local),
		  .CRTC_TYPE(1'b1),
		  
		  .ENABLE(1'b1),
		  .nCS(~crtc_cs),
		  .R_nW(bus_iow_synced_l),
		  .RS(bus_a[0]),
		  .DI(bus_d),
		  .DO(bus_out_crtc),
		  
		  .hblank(hblank_crtc),
		  .vblank(vblank_crtc),
		  .line_reset(),
		  
		  .VSYNC(vsync_l),
		  .HSYNC(hsync_int),
		  .HSYNC_REF(hsync_ref),
		  .VSYNC_REF(vsync_ref),
		  .DE(display_enable),
		  // .FIELD(),
		  .CURSOR(cursor),
		  
		  .MA(crtc_addr),
		  .RA(row_addr),
		  .MA_NEXT(crtc_addr_next),
		  .RA_NEXT(row_addr_next),
		  .hsync_width(hsync_width_crtc),
		  .composite_phase(composite_phase_crtc),
		  
		  .crt_h_offset(crt_h_offset),
		  .crt_v_offset(crt_v_offset),
		  .vsync_width_osd(vsync_width_osd),
		  .hsync_width_osd(hsync_width_osd),
			  .hres_mode(crtc_2x),
			  .frame_stack_rebuild(frame_stack_sync[1])
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
    // PCjr: 3DFh bits 7:6 choose the interleave of the graphics modes (none,
    // 2 banks, 4 banks), text is always linear
    wire pcjr_addr_use = (pcjr_addr_mode != 2'b00);
    wire pcjr_addr_hi  = (pcjr_addr_mode == 2'b11);
    assign pixel_addr13 = pcjr_video ? (grph_mode ? (pcjr_addr_use ? row_addr[0] : crtc_addr[12]) : crtc_addr[12])
                                     : (grph_mode ? row_addr[0] : crtc_addr[12]);

    // Address bit 14 is only used for Tandy modes (32K RAM)
    assign pixel_addr14 = pcjr_video ? (grph_mode && pcjr_addr_hi ? row_addr[1] : 1'b0)
                        : (`ENABLE_TANDY_VIDEO && tandy_video) ? (grph_mode ? row_addr[1] : 1'b0) : 1'b0;

    // The same address mapping as ram_a, for the character after this one
    wire fx_pixel_addr13 = pcjr_video ? (grph_mode ? (pcjr_addr_use ? row_addr_next[0] : crtc_addr_next[12]) : crtc_addr_next[12])
                                      : (grph_mode ? row_addr_next[0] : crtc_addr_next[12]);
    wire fx_pixel_addr14 = pcjr_video ? (grph_mode && pcjr_addr_hi ? row_addr_next[1] : 1'b0)
                         : (`ENABLE_TANDY_VIDEO && tandy_video) ? (grph_mode ? row_addr_next[1] : 1'b0) : 1'b0;
    always @(posedge clk)
        fx_next_word <= {fx_pixel_addr14, fx_pixel_addr13, crtc_addr_next[11:0]};

    wire tandy_16_gfx = `ENABLE_TANDY_VIDEO ? (pcjr_video ? (grph_mode & hres_mode & (tandy_color_16 | tandy_color_4))
                                                          : (tandy_16_mode & grph_mode & hres_mode)) : 1'b0;
    assign tandy_16_gfx_o = tandy_16_gfx;

    // Sequencer state machine
    cga_sequencer sequencer (
        .clk(clk),
        .reset(video_reset_local),
        .clk_seq(clkdiv),
        .vram_read(vram_read),
        .vram_read_a0(vram_read_a0),
        .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att),
        .hres_mode(crtc_2x),
        .crtc_clk(crtc_clk),
        .charrom_read(charrom_read),
        .disp_pipeline(disp_pipeline),
        .isa_op_enable(isa_op_enable),
        .hclk(hclk),
        .lclk(lclk),
        .tandy_16_gfx(tandy_16_gfx),
		  .tandy_color_16(tandy_color_16)
    );

    wire [3:0] video_core;
    wire [3:0] splash_video;

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
        .tandy_palette_color(pcjr_video ? pcjr_palette_index : tandy_color_reg[3:0]),
        .tandy_newcolor(pcjr_video ? pcjr_palette_value : tandy_newcolor),
        .tandy_palette_set(pcjr_video ? pcjr_palette_write : tandy_palette_set),
        .tandy_bordercol(border_color),
        .tandy_color_4(tandy_color_4),
        .tandy_color_16(tandy_color_16),
        .pcjr_video(pcjr_video),
        .pcjr_mode_640x200x2(pcjr_video & pcjr_mode_640x200x2),
        .pcjr_palette_mask(pcjr_palette_mask),
        .video(video_core)
    );

    // The graphical boot splash replaces only the native RGBI stream.  The
    // existing scandoubler and cga_vgaport remain downstream, so both RGB
    // and composite output use the same timing and analogue model as normal
    // CGA video.
    cga_splash_renderer splash_renderer (
        .clk(clk),
        .reset(video_reset_local),
        .enable(splashscreen),
        .clkdiv(clkdiv),
        .display_enable(display_enable),
        .vblank(vblank_crtc),
        .rom_addr(splash_rom_addr),
        .rom_q(splash_rom_q),
        .pixel_index(splash_video)
    );

    assign video = splashscreen ? splash_video : video_core;

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

    video_scandoubler_cga #(
        .PIXEL_WIDTH(4),
        .H_TOTAL_MAX(912)
    ) scandoubler (
        .clk(clk),
        .ce_pix(clkdiv[0]),
        .ce_2x(1'b1),
        .scandouble_en(scandouble_en),
        .pixel_in(video),
        .hsync_in(hsync_int),
        .vsync_in(vsync_l),
        .vblank_in(vblank_win),
        .display_enable_in(display_enable),
        .pixel_out(dbl_video),
        .hsync_out(dbl_hsync),
        .vsync_out(vsync_sd_l),
        .vblank_out(vblank_sd),
        .display_enable_out(display_enable_sd)
    );

endmodule
