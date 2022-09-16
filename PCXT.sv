//============================================================================
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

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE,

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
//assign {UART_RTS, UART_TXD, UART_DTR} = 0;
//assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
//assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign SDRAM_CLK = clk_chipset;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  


assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;

assign AUDIO_S = 1;
assign AUDIO_L = AUDIO_R;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

assign LED_USER = 0;
//led fdd_led(clk_cpu, |mgmt_req[7:6], LED_USER);

//////////////////////////////////////////////////////////////////

// Status Bit Map:
//              Upper                          Lower
// 0         1         2         3          4         5         6
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXX XXXXXXXXXXXXXXXXXXXXXXX


wire [1:0] ar = status[9:8];
assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"PCXT;;",
	"-;",
	"O3,Model,IBM PCXT,Tandy 1000;",
	"OHI,CPU Speed,4.77MHz,7.16MHz,14.318MHz;",
	"-;",
	"O7,Splash Screen,Yes,No;",
	"-;",
	"P1,FDD & HDD;",
	"P1-;",
	"P1S1,IMGIMA,FDD Image:;",
	"P1S0,IMG,HDD Image:;",
	"P1-;",
	"P1OJK,Write Protect,None,FDD,HDD,FDD & HDD;",
	"P1-;",
	"P1OLM,Speed,115200,230400,460800,921600;",
	"P1-;",
	"P2,Audio & Video;",
	"P2-;",
	"P2OA,Adlib,On,Invisible;",
	"P2-;",
	"P2O12,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"P2O89,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P2OT,Border,No,Yes;",
	"P2O4,Video Output,CGA/Tandy,MDA;",
	"P2OEG,Display,Full Color,Green,Amber,B&W,Red,Blue,Fuchsia,Purple;",	
	"P3,Hardware;",
	"P3-;",
	"P3OB,Lo-tech 2MB EMS,Enabled,Disabled;",
	"P3OCD,EMS Frame,A000,C000,D000;",
	"P3-;",
	"P3ONO,Joystick 1, Analog, Digital, Disabled;",
	"P3OPQ,Joystick 2, Analog, Digital, Disabled;",
	"P3OR,Sync Joy to CPU Speed,No,Yes;",
	"P3OS,Swap Joysticks,No,Yes;",
	"P3-;",
	"-;",
	"P4,BIOS;",
	"P4-;",
	"P4FC0,ROM,PCXT BIOS:;",
	"P4FC1,ROM,Tandy BIOS:;",
	"P4-;",
	"P4FC2,ROM,EC00 BIOS:;",
	"P4-;",
	"P4OUV,BIOS Writable,None,EC00,PCXT/Tandy,All;",
	"-;",
	"R0,Reset & apply model;",
	"J,Fire 1, Fire 2;",
	"V,v",`BUILD_DATE 
};

wire forced_scandoubler;
wire  [1:0] buttons;
wire [31:0] status;
//wire [10:0] ps2_key;

//VHD	
wire[ 0:0] usdRd = { vsdRd };
wire[ 0:0] usdWr = { vsdWr };
wire       usdAck;
wire[31:0] usdLba[1] = '{ vsdLba };
wire       usdBuffWr;
wire[ 8:0] usdBuffA;
wire[ 7:0] usdBuffD[1] = '{ vsdBuffD };
wire[ 7:0] usdBuffQ;
wire[63:0] usdImgSz;
wire[ 0:0] usdImgMtd;

//Keyboard Ps2
wire        ps2_kbd_clk_out;
wire        ps2_kbd_data_out;
wire        ps2_kbd_clk_in;
wire        ps2_kbd_data_in;

//Mouse PS2
wire        ps2_mouse_clk_out;
wire        ps2_mouse_data_out;
wire        ps2_mouse_clk_in;
wire        ps2_mouse_data_in;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;

wire        clk_uart;

wire [21:0] gamma_bus;
wire        adlibhide = status[10];

wire [31:0] joy0, joy1;
wire [15:0] joya0, joya1;
wire [4:0]  joy_opts = status[27:23];

hps_io #(.CONF_STR(CONF_STR), .PS2DIV(2000), .PS2WE(1)) hps_io
(
	.clk_sys(clk_chipset),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({status[5]}),
	
//VHD	
	.sd_rd         (usdRd),
	.sd_wr         (usdWr),
	.sd_ack        (usdAck),
	.sd_lba        (usdLba),
	.sd_buff_wr    (usdBuffWr),
	.sd_buff_addr  (usdBuffA),
	.sd_buff_din   (usdBuffD),
	.sd_buff_dout  (usdBuffQ),
	.img_mounted   (usdImgMtd),
	.img_size	   (usdImgSz),	
	
   .ps2_kbd_clk_in	(ps2_kbd_clk_out),
	.ps2_kbd_data_in	(ps2_kbd_data_out),
	.ps2_kbd_clk_out	(ps2_kbd_clk_in),
	.ps2_kbd_data_out	(ps2_kbd_data_in),
//  .ps2_mouse_clk_in	(ps2_mouse_clk_out),
//	.ps2_mouse_data_in	(ps2_mouse_data_out),
//	.ps2_mouse_clk_out	(ps2_mouse_clk_in),
//	.ps2_mouse_data_out	(ps2_mouse_data_in),

	//.ps2_key(ps2_key),
	.joystick_0(joy0),
	.joystick_1(joy1),
	.joystick_l_analog_0(joya0),
	.joystick_l_analog_1(joya1),

	//ioctl
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data)	
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
wire pll_locked;

wire clk_100;
wire clk_28_636;
wire clk_56_875;
wire clk_113_750;
reg clk_14_318 = 1'b0;
reg clk_7_16 = 1'b0;
wire clk_4_77;
wire clk_cpu;
wire pclk;
wire clk_opl2;
wire clk_chipset;
wire peripheral_clock;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_100),
	.outclk_1(clk_56_875),
	.outclk_2(clk_28_636),
	.outclk_3(clk_uart),
	.outclk_4(clk_opl2),
	.outclk_5(clk_chipset),
	.outclk_6(clk_113_750),
	.locked(pll_locked)
);

wire reset_wire = RESET | status[0] | buttons[1] | !pll_locked | (status[14] && usdImgMtd) | splashscreen;

//////////////////////////////////////////////////////////////////

wire HBlank;
wire HSync;
wire VBlank;
wire VSync;
wire ce_pixel_cga;
wire ce_pixel_mda;
//wire [7:0] video;

assign CLK_VIDEO = clk_56_875;

wire CLK_VIDEO_MDA;
wire CLK_VIDEO_CGA;
assign CLK_VIDEO_MDA = clk_113_750;
assign CLK_VIDEO_CGA = clk_56_875;
assign ce_pixel_mda = clk_28_636;

reg [14:0] HBlank_del;
wire tandy_16_gfx;
wire color = (screen_mode == 3'd0);
wire HBlank_VGA = mda_mode ? HBlank_del[color ? 12 : 13] : tandy_16_gfx ? HBlank_del[color ? 9 : 11] : HBlank_del[color ? 5 : 7];

always @(posedge clk_28_636) begin
	HBlank_del <= {HBlank_del[13], HBlank_del[12], HBlank_del[11], HBlank_del[10], HBlank_del[9],
						HBlank_del[8], HBlank_del[7], HBlank_del[6], HBlank_del[5], HBlank_del[4],
						HBlank_del[3], HBlank_del[2], HBlank_del[1], HBlank_del[0], HBlank};
	clk_14_318 <= ~clk_14_318; // 14.318Mhz
	ce_pixel_cga <= clk_14_318;	//if outside always block appears an overscan column in CGA mode
end

always @(posedge clk_14_318)
	clk_7_16 <= ~clk_7_16; // 7.16Mhz

clk_div3 clk_normal // 4.77MHz
(
	.clk(clk_14_318),
	.clk_out(clk_4_77)
);

always @(posedge clk_4_77)
	peripheral_clock <= ~peripheral_clock; // 2.385Mhz

logic  biu_done;
logic  turbo_mode;

always @(posedge clk_chipset) begin
    if (biu_done)
        turbo_mode  <= (status[18:17] == 2'b01 || status[18:17] == 2'b10);
    else
        turbo_mode  <= turbo_mode;
end

logic  clk_cpu_ff_1;
logic  clk_cpu_ff_2;

logic  pclk_ff_1;
logic  pclk_ff_2;

always @(posedge clk_chipset) begin
    clk_cpu_ff_1 <= (status[18:17] == 2'b10) ? clk_14_318 : (status[18:17] == 2'b01) ? clk_7_16 : clk_4_77;
    clk_cpu_ff_2 <= clk_cpu_ff_1;
    clk_cpu      <= clk_cpu_ff_2;
    pclk_ff_1    <= peripheral_clock;
    pclk_ff_2    <= pclk_ff_1;
    pclk         <= pclk_ff_2;
end

logic   clk_opl2_ff_1;
logic   clk_opl2_ff_2;
logic   clk_opl2_ff_3;
logic   cen_opl2;

always @(posedge clk_chipset) begin
    clk_opl2_ff_1 <= clk_opl2;
    clk_opl2_ff_2 <= clk_opl2_ff_1;
    clk_opl2_ff_3 <= clk_opl2_ff_2;
    cen_opl2 <= clk_opl2_ff_2 & ~clk_opl2_ff_3;
end


//////////////////////////////////////////////////////////////////

logic reset = 1'b1;
logic [15:0] reset_count = 16'h0000;

always @(posedge CLK_50M, posedge reset_wire) begin
	if (reset_wire) begin
		reset <= 1'b1;
		reset_count <= 16'h0000;
	end
	else if (reset) begin
		if (reset_count != 16'hffff) begin
			reset <= 1'b1;
			reset_count <= reset_count + 16'h0001;
		end
		else begin
			reset <= 1'b0;
			reset_count <= reset_count;
		end
	end 
	else begin
		reset <= 1'b0;
		reset_count <= reset_count;
	end
end

logic reset_cpu_ff = 1'b1;
logic reset_cpu = 1'b1;
logic [15:0] reset_cpu_count = 16'h0000;

always @(negedge clk_chipset, posedge reset) begin
	if (reset)
		reset_cpu_ff <= 1'b1;
	else
		reset_cpu_ff <= reset;
end

reg tandy_mode = 0;

always @(negedge clk_chipset, posedge reset) begin
	if (reset) begin
		tandy_mode <= status[3];		
		reset_cpu <= 1'b1;
		reset_cpu_count <= 16'h0000;
	end
	else if (reset_cpu) begin
		reset_cpu <= reset_cpu_ff;
		reset_cpu_count <= 16'h0000;
	end
	else begin
		if (reset_cpu_count != 16'h002A) begin
			reset_cpu <= reset_cpu_ff;
			reset_cpu_count <= reset_cpu_count + 16'h0001;
		end
		else begin
			reset_cpu <= 1'b0;
			reset_cpu_count <= reset_cpu_count;
		end
	end
end

//////////////////////////////////////////////////////////////////

	wire [5:0] r, g, b;	
	reg [7:0] raux_cga, gaux_cga, baux_cga;	
	reg [7:0] raux_mda, gaux_mda, baux_mda;	

	wire de_o;
	
	reg [24:0] splash_cnt = 0;
	reg [3:0] splash_cnt2 = 0;
	reg splashscreen = 1;
	
	always @ (posedge clk_14_318) begin
	
		if (splashscreen) begin
			if (status[7])
				splashscreen <= 0;
			else if(splash_cnt2 == 5) // 5 seconds delay
				splashscreen <= 0;
			else if (splash_cnt == 14318000) begin // 1 second at 14.318Mhz
					splash_cnt2 <= splash_cnt2 + 1;				
					splash_cnt <= 0;
				end
			else
				splash_cnt <= splash_cnt + 1;			
		end
	
	end
	
    //
    // Input F/F PS2_CLK
    //
    logic   device_clock_ff;
    logic   device_clock;

    always_ff @(negedge clk_chipset, posedge reset)
    begin
        if (reset) begin
            device_clock_ff <= 1'b0;
            device_clock    <= 1'b0;
        end
        else begin
            device_clock_ff <= ps2_kbd_clk_in;
            device_clock    <= device_clock_ff ;
        end
    end


    //
    // Input F/F PS2_DAT
    //
    logic   device_data_ff;
    logic   device_data;

    always_ff @(negedge clk_chipset, posedge reset)
    begin
        if (reset) begin
            device_data_ff <= 1'b0;
            device_data    <= 1'b0;
        end
        else begin
            device_data_ff <= ps2_kbd_data_in;
            device_data    <= device_data_ff;
        end
    end
	
    wire [7:0] data_bus;
    wire INTA_n;	
    wire [19:0] cpu_ad_out;
    reg  [19:0] cpu_address;
    wire [7:0] cpu_data_bus;    
    wire processor_ready;	
    wire interrupt_to_cpu;
    wire address_latch_enable;

    wire lock_n;
    wire [2:0]processor_status;
	 
	 logic   [7:0]   port_b_out;
    logic   [7:0]   port_c_in;	 
	 reg     [7:0]   sw;
	 
	wire [1:0] scale = status[2:1];	
	wire mda_mode = status[4];	 
	wire [2:0] screen_mode = status[16:14];
	 
	 
	 assign  sw = mda_mode ? 8'b00111101 : 8'b00101101; // PCXT DIP Switches (MDA or CGA 80)
	 assign  port_c_in[3:0] = port_b_out[3] ? sw[7:4] : sw[3:0];

   CHIPSET u_CHIPSET (
        .clock                              (clk_chipset),
        .cpu_clock                            (clk_cpu),
		  .clk_sys                            (clk_chipset),
		  .peripheral_clock                   (pclk),
		  .turbo_mode                         (status[18:17]),
        .reset                              (reset_cpu),
        .sdram_reset                        (reset),
        .cpu_address                        (cpu_address),
        .cpu_data_bus                       (cpu_data_bus),
        .processor_status                   (processor_status),
        .processor_lock_n                   (lock_n),
 //     .processor_transmit_or_receive_n    (processor_transmit_or_receive_n),
		  .processor_ready                    (processor_ready),
        .interrupt_to_cpu                   (interrupt_to_cpu),
        .splashscreen                       (splashscreen),
		  .video_output                       (mda_mode),
        .clk_vga_cga                        (clk_28_636),
        .enable_cga                         (1'b1),
        .clk_vga_mda                        (clk_56_875),
        .enable_mda                         (1'b1),
		.mda_rgb                            (2'b10), // always B&W - monochrome monitor tint handled down below
        //.de_o                               (VGA_DE),
        .VGA_R                              (r),
        .VGA_G                              (g),
        .VGA_B                              (b),
        .VGA_HSYNC                          (HSync),
        .VGA_VSYNC                          (VSync),
		.VGA_HBlank	  				        (HBlank),
		.VGA_VBlank							(VBlank),
//      .address                            (address),
        .address_ext                        (20'hFFFFF),
//      .address_direction                  (address_direction),
        .data_bus                           (data_bus),
        .data_bus_ext                       (8'hFF),
//      .data_bus_direction                 (data_bus_direction),
        .address_latch_enable               (address_latch_enable),
//      .io_channel_check                   (),
        .io_channel_ready                   (1'b1),
        .interrupt_request                  (0),    // use?	-> It does not seem to be necessary.
//      .io_read_n                          (io_read_n),
        .io_read_n_ext                      (1'b1),
//      .io_read_n_direction                (io_read_n_direction),
//      .io_write_n                         (io_write_n),
        .io_write_n_ext                     (1'b1),
//      .io_write_n_direction               (io_write_n_direction),
//      .memory_read_n                      (memory_read_n),
        .memory_read_n_ext                  (1'b1),
//      .memory_read_n_direction            (memory_read_n_direction),
//      .memory_write_n                     (memory_write_n),
        .memory_write_n_ext                 (1'b1),
//      .memory_write_n_direction           (memory_write_n_direction),
        .dma_request                        (0),    // use?	-> I don't know if it will ever be necessary, at least not during testing.
//      .dma_acknowledge_n                  (dma_acknowledge_n),
//      .address_enable_n                   (address_enable_n),
//      .terminal_count_n                   (terminal_count_n)
        .port_b_out                         (port_b_out),
		  .port_c_in                          (port_c_in),
	     .speaker_out                        (speaker_out),   
        .ps2_clock                          (device_clock),
	     .ps2_data                           (device_data),
	     .ps2_clock_out                      (ps2_kbd_clk_out),
	     .ps2_data_out                       (ps2_kbd_data_out),
		  .joy_opts                           (joy_opts),                          //Joy0-Disabled, Joy0-Type, Joy1-Disabled, Joy1-Type, turbo_sync
        .joy0                               (status[28] ? joy1 : joy0),
        .joy1                               (status[28] ? joy0 : joy1),
		  .joya0                              (status[28] ? joya1 : joya0),
		  .joya1                              (status[28] ? joya0 : joya1),
		  .clk_en_opl2                        (cen_opl2), // clk_en_opl2
		  .jtopl2_snd_e                       (jtopl2_snd_e),
		  .tandy_snd_e                        (tandy_snd_e),
		  .adlibhide                          (adlibhide),
		  .tandy_video                        (tandy_mode),
		  .tandy_16_gfx                       (tandy_16_gfx),
		  .ioctl_download                     (ioctl_download),
		  .ioctl_index                        (ioctl_index),
		  .ioctl_wr                           (ioctl_wr),
		  .ioctl_addr                         (ioctl_addr),
		  .ioctl_data                         (ioctl_data),		  
		  .clk_uart                          ((status[22:21] == 2'b00) ? clk_uart : clk_uart_en),
	     .uart_rx                           (uart_rx),
	     .uart_tx                           (uart_tx),
	     .uart_cts_n                        (uart_cts),
	     .uart_dcd_n                        (uart_dcd),
	     .uart_dsr_n                        (uart_dsr),
	     .uart_rts_n                        (uart_rts),
	     .uart_dtr_n                        (uart_dtr),
		  .enable_sdram                       (1'b1),
		  .sdram_clock                        (SDRAM_CLK),
		  .sdram_address                      (SDRAM_A),
        .sdram_cke                          (SDRAM_CKE),
        .sdram_cs                           (SDRAM_nCS),
        .sdram_ras                          (SDRAM_nRAS),
        .sdram_cas                          (SDRAM_nCAS),
        .sdram_we                           (SDRAM_nWE),
        .sdram_ba                           (SDRAM_BA),
        .sdram_dq_in                        (SDRAM_DQ_IN),
        .sdram_dq_out                       (SDRAM_DQ_OUT),
        .sdram_dq_io                        (SDRAM_DQ_IO),
        .sdram_ldqm                         (SDRAM_DQML),
        .sdram_udqm                         (SDRAM_DQMH),
		  .ems_enabled                        (~status[11]),
		  .ems_address                        (status[13:12]),
		  .bios_writable                      (status[31:30])
    );

	wire speaker_out;
	wire  [7:0]   tandy_snd_e;
	wire tandy_snd_rdy;

	wire [15:0] jtopl2_snd_e;	
	wire [16:0]sndmix = ({jtopl2_snd_e[15], jtopl2_snd_e}) + (speaker_out << 14) + ({tandy_snd_e, 9'd0}); // signed mixer
	 
	wire [15:0] SDRAM_DQ_IN;
	wire [15:0] SDRAM_DQ_OUT;
	wire        SDRAM_DQ_IO;
	
	assign SDRAM_DQ_IN = SDRAM_DQ;
	assign SDRAM_DQ = ~SDRAM_DQ_IO ? SDRAM_DQ_OUT : 16'hZZZZ;	

	assign AUDIO_R = sndmix >> 1;	

	wire s6_3_mux;
	wire [2:0] SEGMENT;

	i8088 B1(
	  .CORE_CLK(clk_100),
	  .CLK(clk_cpu),

	  .RESET(reset_cpu),
	  .READY(processor_ready),
	  .NMI(1'b0),
	  .INTR(interrupt_to_cpu),

	  .ad_out(cpu_ad_out),
	  .dout(cpu_data_bus),
	  .din(data_bus),
	  
	  .lock_n(lock_n),
	  .s6_3_mux(s6_3_mux),
	  .s2_s0_out(processor_status),
	  .SEGMENT(SEGMENT),

      .biu_done(biu_done),
      .turbo_mode(turbo_mode)
	);
	
	/// UART


	//assign USER_OUT = {1'b1, 1'b1, uart_dtr, 1'b1, uart_rts, uart_tx, 1'b1};
	
	//
	// Pin | USB Name |   |Signal
	// ----+----------+---+-------------
	// 0   | D+       | I |RX
	// 1   | D-       | O |TX
	// 2   | TX-      | O |RTS
	// 3   | GND_d    | I |CTS
	// 4   | RX+      | O |DTR
	// 5   | RX-      | I |DSR
	// 6   | TX+      | I |DCD
	//

	logic clk_uart_ff_1;
	logic clk_uart_ff_2;
	logic clk_uart_ff_3;
	logic clk_uart_en;

	always @(posedge clk_chipset) begin
		clk_uart_ff_1 <= clk_uart;
		clk_uart_ff_2 <= clk_uart_ff_1;
		clk_uart_ff_3 <= clk_uart_ff_2;
		clk_uart_en   <= ~clk_uart_ff_3 & clk_uart_ff_2;
    end

	wire uart_tx, uart_rts, uart_dtr;
	
	assign UART_TXD = uart_tx;
	assign UART_RTS = uart_rts;
	assign UART_DTR = uart_dtr;

	wire uart_rx  = UART_RXD;
	wire uart_cts = UART_CTS;
	wire uart_dsr = UART_DSR;
	wire uart_dcd = UART_DTR;

	always @(posedge clk_100) begin
		if (address_latch_enable)
			cpu_address <= cpu_ad_out;
		else
			cpu_address <= cpu_address;
	end	
	
	/// VIDEO

	/*
	wire [1:0] scale = status[8:7];
	assign VGA_SL = scale;
	wire freeze_sync;	
	video_mixer #(640, 1) mixer
	(
		.*,
        .hq2x(scale),
        .scandoubler (scale || forced_scandoubler),
        .R({raux, 2'b0}), 
        .G({gaux, 2'b0}), 
        .B({baux, 2'b0})
	);
	*/

	video_monochrome_converter video_mono_cga 
	(
		.clk_vid(CLK_VIDEO_CGA),
		.ce_pix(ce_pixel_cga),
		
		.R({r, 2'b00}),
		.G({g, 2'b00}),
		.B({b, 2'b00}),

		.gfx_mode(screen_mode),
		
		.R_OUT(raux_cga),
		.G_OUT(gaux_cga),
		.B_OUT(baux_cga)	
	);

	video_monochrome_converter video_mono_mda 
	(
		.clk_vid(CLK_VIDEO_MDA),
		.ce_pix(ce_pixel_mda),
		
		.R({r, 2'b00}),
		.G({g, 2'b00}),
		.B({b, 2'b00}),

		.gfx_mode(screen_mode),
		
		.R_OUT(raux_mda),
		.G_OUT(gaux_mda),
		.B_OUT(baux_mda)	
	);

	/*
	assign VGA_R = raux;
	assign VGA_G = gaux;
	assign VGA_B = baux;
	assign VGA_HS = HSync;
	assign VGA_VS = VSync;
	assign VGA_DE = ~(HBlank | VBlank);
	assign CE_PIXEL = ce_pixel;
	*/

	wire  [7:0] VGA_R_cga;
	wire  [7:0] VGA_G_cga;
	wire  [7:0] VGA_B_cga;
	wire        VGA_HS_cga;
	wire        VGA_VS_cga;
	wire        VGA_DE_cga;
	wire [21:0] gamma_bus_cga;
	wire        CE_PIXEL_cga;

	wire  [7:0] VGA_R_mda;
	wire  [7:0] VGA_G_mda;
	wire  [7:0] VGA_B_mda;
	wire        VGA_HS_mda;
	wire        VGA_VS_mda;
	wire        VGA_DE_mda;
	wire [21:0] gamma_bus_mda;
	wire        CE_PIXEL_mda;

	assign VGA_SL = {scale==3, scale==2};
	
	
    wire   scandoubler = (scale>0); //|| forced_scandoubler);
	 
	
	wire border = status[29];
	 
	reg [10:0] HBlank_counter = 0;
	reg HBlank_fixed = 1'b1;
	reg [1:0] HSync_del = 1'b11;

	always @ (posedge ce_pixel_cga) begin
		
		HSync_del <= {HSync_del[0], HSync};		
		
		if (HSync_del == 2'b01) begin
			HBlank_counter <= 0;
			HBlank_fixed <= 1'b1;
		end else begin			
			if (HBlank_counter == 143)
				HBlank_fixed <= 1'b0;
			else
				HBlank_counter <= HBlank_counter + 1;
		end
	end

	video_mixer #(.GAMMA(1)) video_mixer_cga
	(
		.*,
		
		.CLK_VIDEO(CLK_VIDEO_CGA),
		.CE_PIXEL(CE_PIXEL_cga),
		.ce_pix(ce_pixel_cga),

		.freeze_sync(),
		
		.R(raux_cga),
		.G(gaux_cga),
		.B(baux_cga),
		
		.HBlank(border ? HBlank_fixed : HBlank_VGA),
		.VBlank(border ? ~VSync : VBlank),
		.HSync(HSync),
		.VSync(VSync),
		
		.scandoubler(scandoubler),
		.hq2x(scale==1),
		.gamma_bus(gamma_bus_cga),

		.VGA_R(VGA_R_cga),
		.VGA_G(VGA_G_cga),
		.VGA_B(VGA_B_cga),
		.VGA_VS(VGA_VS_cga),
		.VGA_HS(VGA_HS_cga),
		.VGA_DE(VGA_DE_cga)

	);

	video_mixer #(.GAMMA(0)) video_mixer_mda
	(
		.*,
		
		.CLK_VIDEO(CLK_VIDEO_MDA),
		.CE_PIXEL(CE_PIXEL_mda),
		.ce_pix(ce_pixel_mda),

		.freeze_sync(),
		
		.R(raux_mda),
		.G(gaux_mda),
		.B(baux_mda),
		
		.HBlank(HBlank_VGA),
		.VBlank(VBlank),
		.HSync(HSync),
		.VSync(VSync),
		
		.scandoubler(scandoubler),
		.hq2x(scale==1),
		.gamma_bus(gamma_bus_mda),

		.VGA_R(VGA_R_mda),
		.VGA_G(VGA_G_mda),
		.VGA_B(VGA_B_mda),
		.VGA_VS(VGA_VS_mda),
		.VGA_HS(VGA_HS_mda),
		.VGA_DE(VGA_DE_mda)

	);


assign VGA_R  =  mda_mode ? VGA_R_mda  : VGA_R_cga;
assign VGA_G  =  mda_mode ? VGA_G_mda  : VGA_G_cga;
assign VGA_B  =  mda_mode ? VGA_B_mda  : VGA_B_cga;
assign VGA_HS =  mda_mode ? VGA_HS_mda : VGA_HS_cga;
assign VGA_VS =  mda_mode ? VGA_VS_mda : VGA_VS_cga;
assign VGA_DE =  mda_mode ? VGA_DE_mda : VGA_DE_cga;
assign gamma_bus =  mda_mode ? gamma_bus_mda : gamma_bus_cga;
assign CE_PIXEL  =  mda_mode ? CE_PIXEL_mda : CE_PIXEL_cga;


/*
// SRAM management
wire sramOe = ~sramWe;
wire sramWe;
wire [20:0] sramA;
wire [ 7:0] sramDQ;

Mister_sRam sRam
( // .*,
  //SDram interface
  .SDRAM_A		(SDRAM_A),
  .SDRAM_DQ		(SDRAM_DQ),
  .SDRAM_BA		(SDRAM_BA),
  .SDRAM_nWE	(SDRAM_nWE),
  .SDRAM_nCAS	(SDRAM_nCAS),
  .SDRAM_nCS	(SDRAM_nCS),
  .SDRAM_CKE	(SDRAM_CKE),
  //Sram interface
  .SRAM_A      (sramA),
  .SRAM_DQ     (sramDQ),
  .SRAM_nCE    (1'b0),
  .SRAM_nOE    (sramOe), 
  .SRAM_nWE    (sramWe) 
);
*/

reg vsd = 0;
always @(posedge CLK_50M) if(usdImgMtd[0]) vsd <= |usdImgSz;

wire       vsdRd;
wire       vsdWr;
wire       vsdAck = usdAck;
wire[31:0] vsdLba;
wire       vsdBuffWr = usdBuffWr;
wire[ 8:0] vsdBuffA = usdBuffA;
wire[ 7:0] vsdBuffD;
wire[ 7:0] vsdBuffQ = usdBuffQ;
wire[63:0] vsdImgSz = usdImgSz;
wire       vsdImgMtd = usdImgMtd[0];

wire vsdCs = usdCs | ~vsd;
wire vsdCk = usdCk;
wire vsdMosi = usdDo;
wire vsdMiso;

wire usdCs;
wire usdCk;
wire usdDo;
wire usdDi = vsd ? vsdMiso : SD_MISO;

assign SD_CS   = usdCs | vsd;
assign SD_SCK  = usdCk & ~vsd;
assign SD_MOSI = usdDo & ~vsd;

/*
sd_card sd_card
(
	.clk_sys     (CLK_50M  ),
	.reset       (reset    ),
	.sdhc        (status[4]),
	.sd_rd       (vsdRd    ),
	.sd_wr       (vsdWr    ),
	.sd_ack      (vsdAck   ),
	.sd_lba      (vsdLba   ),
	.sd_buff_wr  (vsdBuffWr),
	.sd_buff_addr(vsdBuffA ),
	.sd_buff_dout(vsdBuffQ ),
	.sd_buff_din (vsdBuffD ),
	.img_size    (vsdImgSz ),
	.img_mounted (vsdImgMtd),
	.clk_spi     (clk_25   ),
	.ss          (vsdCs    ),
	.sck         (vsdCk    ),
	.mosi        (vsdMosi  ),
	.miso        (vsdMiso  )
);
*/

endmodule

module led
(
	input      clk,
	input      in,
	output reg out
);

integer counter = 0;
always @(posedge clk) begin
	if(!counter) out <= 0;
	else begin
		counter <= counter - 1'b1;
		out <= 1;
	end
	
	if(in) counter <= 4500000;
end

endmodule
