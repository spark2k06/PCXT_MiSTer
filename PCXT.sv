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
	inout  [47:0] HPS_BUS,

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
//assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
//assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
//assign SDRAM_CLK = CLK_50M;
//assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign HDMI_FREEZE = 0;

assign AUDIO_S = 1;
assign AUDIO_L = AUDIO_R;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;


//led fdd_led(clk_cpu, |mgmt_req[7:6], LED_USER);

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[9:8];
assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"PCXT;;",
	"-;",
	"O3,Splash Screen,Yes,No;",
	//"O4,CPU Speed,4.77Mhz,7.16Mhz;",	
	"-;",
	"OA,Adlib,On,Invisible;",
	"-;",
	"O12,Video,Color,Green,Amber,B/W;",	
	"O89,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",	
	//"O78,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",	
	"-;",
	"F1,ROM,Load ROM;",	
	"-;",
	"T0,Reset;",
	"R0,Reset and close OSD;",
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
//wire        ps2_kbd_clk_out;
//wire        ps2_kbd_data_out;
wire        ps2_kbd_clk_in;
wire        ps2_kbd_data_in;
wire        ps2_kbd_busy;

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

hps_io #(.CONF_STR(CONF_STR), .PS2DIV(2000), .PS2WE(1)) hps_io
(
	.clk_sys(CLK_50M),
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
	
   .ps2_kbd_clk_in	(~ps2_kbd_busy),
	.ps2_kbd_data_in	(1'b1),
	.ps2_kbd_clk_out	(ps2_kbd_clk_in),
	.ps2_kbd_data_out	(ps2_kbd_data_in),
//  .ps2_mouse_clk_in	(ps2_mouse_clk_out),
//	.ps2_mouse_data_in	(ps2_mouse_data_out),
//	.ps2_mouse_clk_out	(ps2_mouse_clk_in),
//	.ps2_mouse_data_out	(ps2_mouse_data_in),

	//.ps2_key(ps2_key),

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
wire clk_25;
reg clk_14_318 = 1'b0;
//reg clk_7_16 = 1'b0;
wire clk_4_77;
wire clk_cpu;
wire peripheral_clock;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_100),
	.outclk_1(clk_28_636),	
	.outclk_2(clk_uart),
	.outclk_3(cen_opl2),
	.locked(pll_locked)
);

wire reset = RESET | status[0] | buttons[1] | !pll_locked | (status[14] && usdImgMtd) | (ioctl_download && ioctl_index == 0);

//////////////////////////////////////////////////////////////////

wire HBlank;
wire HSync;
wire VBlank;
wire VSync;
wire ce_pix;
//wire [7:0] video;

assign CLK_VIDEO = clk_28_636;
assign CE_PIXEL = 1'b1;

//assign clk_cpu = status[4] ? clk_7_16 : clk_4_77;
assign clk_cpu = clk_4_77;

always @(posedge clk_28_636)
	clk_14_318 <= ~clk_14_318; // 14.318Mhz
	

//always @(posedge clk_14_318)
//	clk_7_16 <= ~clk_7_16; // 7.16Mhz
	
	
clk_div3 clk_normal // 4.77MHz
(
	.clk(clk_14_318),
	.clk_out(clk_4_77)
);

always @(posedge clk_4_77)
	peripheral_clock <= ~peripheral_clock; // 2.385Mhz


//////////////////////////////////////////////////////////////////

	wire [5:0] r, g, b;	
	reg [5:0] raux, gaux, baux;	
		
	reg [5:0]red_weight[0:63] = '{ // 0.2126*R
	6'h00, 6'h01, 6'h01, 6'h01, 6'h01, 6'h02, 6'h02, 6'h02, 6'h02, 6'h02, 6'h03, 6'h03, 6'h03, 6'h03, 6'h03, 6'h04,
	6'h04, 6'h04, 6'h04, 6'h05, 6'h05, 6'h05, 6'h05, 6'h05, 6'h06, 6'h06, 6'h06, 6'h06, 6'h06, 6'h07, 6'h07, 6'h07,
	6'h07, 6'h08, 6'h08, 6'h08, 6'h08, 6'h08, 6'h09, 6'h09, 6'h09, 6'h09, 6'h09, 6'h0a, 6'h0a, 6'h0a, 6'h0a, 6'h0a,
	6'h0b, 6'h0b, 6'h0b, 6'h0b, 6'h0c, 6'h0c, 6'h0c, 6'h0c, 6'h0c, 6'h0d, 6'h0d, 6'h0d, 6'h0d, 6'h0d, 6'h0e, 6'h0e
	};
	
	reg [5:0]green_weight[0:63] = '{ // 0.7152*G
	6'h00, 6'h01, 6'h02, 6'h03, 6'h03, 6'h04, 6'h05, 6'h06, 6'h06, 6'h07, 6'h08, 6'h08, 6'h09, 6'h0a, 6'h0b, 6'h0b,
	6'h0c, 6'h0d, 6'h0d, 6'h0e, 6'h0f, 6'h10, 6'h10, 6'h11, 6'h12, 6'h12, 6'h13, 6'h14, 6'h15, 6'h15, 6'h16, 6'h17,
	6'h17, 6'h18, 6'h19, 6'h1a, 6'h1a, 6'h1b, 6'h1c, 6'h1c, 6'h1d, 6'h1e, 6'h1f, 6'h1f, 6'h20, 6'h21, 6'h21, 6'h22,
	6'h23, 6'h24, 6'h24, 6'h25, 6'h26, 6'h26, 6'h27, 6'h28, 6'h29, 6'h29, 6'h2a, 6'h2a, 6'h2a, 6'h2b, 6'h2b, 6'h2b
	};
	
	reg [5:0]blue_weight[0:63] = '{ // 0.0722*B
	6'h00, 6'h01, 6'h01, 6'h01, 6'h01, 6'h01, 6'h01, 6'h01, 6'h01, 6'h01, 6'h01, 6'h01, 6'h01, 6'h01, 6'h02, 6'h02,
	6'h02, 6'h02, 6'h02, 6'h02, 6'h02, 6'h02, 6'h02, 6'h02, 6'h02, 6'h02, 6'h02, 6'h02, 6'h03, 6'h03, 6'h03, 6'h03,
	6'h03, 6'h03, 6'h03, 6'h03, 6'h03, 6'h03, 6'h03, 6'h03, 6'h03, 6'h03, 6'h04, 6'h04, 6'h04, 6'h04, 6'h04, 6'h04,
	6'h04, 6'h04, 6'h04, 6'h04, 6'h04, 6'h04, 6'h04, 6'h04, 6'h05, 6'h05, 6'h05, 6'h05, 6'h05, 6'h05, 6'h05, 6'h05
	};

	wire de_o;
	

	reg [24:0] splash_cnt = 0;
	reg [3:0] splash_cnt2 = 0;
	reg splashscreen = 1;
	
	always @ (posedge clk_14_318) begin
	
		if (splashscreen) begin
			if (status[3])
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

    always_ff @(negedge clk_cpu, posedge reset)
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

    always_ff @(negedge clk_cpu, posedge reset)
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

   CHIPSET u_CHIPSET (
        .clock                              (clk_cpu),
		  .clk_sys                            (CLK_50M),
		  .peripheral_clock                   (peripheral_clock),
		  
        .reset                              (reset || splashscreen),
        .cpu_address                        (cpu_address),
        .cpu_data_bus                       (cpu_data_bus),
        .processor_status                   (processor_status),
        .processor_lock_n                   (lock_n),
 //     .processor_transmit_or_receive_n    (processor_transmit_or_receive_n),
		  .processor_ready                    (processor_ready),
        .interrupt_to_cpu                   (interrupt_to_cpu),
        .splashscreen                       (splashscreen),
        .clk_vga                            (clk_28_636),
        .enable_cga                         (1'b1),
        .de_o                               (VGA_DE),
        .VGA_R                              (r),
        .VGA_G                              (g),
        .VGA_B                              (b),
        .VGA_HSYNC                          (VGA_HS),
        .VGA_VSYNC                          (VGA_VS),
//      .address                            (address),
        .address_ext                        (0),
//      .address_direction                  (address_direction),
        .data_bus                           (data_bus),
//      .data_bus_ext                       (data_bus_ext),
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
	     .speaker_out                        (speaker_out),   
        .ps2_clock                          (ps2_kbd_clk_in),
	     .ps2_data                           (ps2_kbd_data_in),
	     .ps2_busy                           (ps2_kbd_busy),
	     .enable_sdram                       (0),	   // -> During the first tests, it shall not be used.		  
		  .clk_en_opl2                        (cen_opl2), // clk_en_opl2
		  .jtopl2_snd_e                       (jtopl2_snd_e),
		  .adlibhide                          (adlibhide),
		  .tandy_snd_e                        (tandy_snd_e),
		  .ioctl_download                     (ioctl_download),
		  .ioctl_index                        (ioctl_index),
		  .ioctl_wr                           (ioctl_wr),
		  .ioctl_addr                         (ioctl_addr),
		  .ioctl_data                         (ioctl_data),
		  
		  .clk_uart                          (clk_uart),
	     .uart_rx                           (uart_rx),
	     .uart_tx                           (uart_tx),
	     .uart_cts_n                        (uart_cts),
	     .uart_dcd_n                        (uart_dcd),
	     .uart_dsr_n                        (uart_dsr),
	     .uart_rts_n                        (uart_rts),
	     .uart_dtr_n                        (uart_dtr)
    );
	 
	wire [15:0] jtopl2_snd_e;	
	wire [16:0]sndmix = (({jtopl2_snd_e[15], jtopl2_snd_e}) << 2) + (speaker_out << 15) + (tandy_snd_e << 8); // signed mixer
		
	assign AUDIO_R = sndmix >> 1;
		 
	i8088 B1(
	  .CORE_CLK(clk_100),
	  .CLK(clk_cpu),

	  .RESET(reset || splashscreen),
	  .READY(processor_ready),	  
	  .NMI(1'b0),
	  .INTR(interrupt_to_cpu),

	  .ad_out(cpu_ad_out),
	  .dout(cpu_data_bus),
	  .din(data_bus),
	  
	  .lock_n(lock_n),
	  .s6_3_mux(s6_3_mux),
	  .s2_s0_out(processor_status),
	  .SEGMENT(SEGMENT)
	);
	
	/// UART


	assign USER_OUT = {1'b1, 1'b1, uart_dtr, 1'b1, uart_rts, uart_tx, 1'b1};

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

	wire uart_tx, uart_rts, uart_dtr;

	wire uart_rx  = USER_IN[0];
	wire uart_cts = USER_IN[3];
	wire uart_dsr = USER_IN[5];
	wire uart_dcd = USER_IN[6];

	always @(posedge clk_cpu) begin
		if (address_latch_enable)
			cpu_address <= cpu_ad_out;
		else
			cpu_address <= cpu_address;
	end	
	
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

	always @ (status[2:1], r, g, b) begin
		case(status[2:1])
			// Verde
			2'b01	: begin
				raux = 6'b0;
				gaux = red_weight[r] + green_weight[g] + blue_weight[b];				
				baux = 6'b0;
			end
			// Ambar
			2'b10	: begin
				raux = red_weight[r] + green_weight[g] + blue_weight[b];
				gaux = (red_weight[r] + green_weight[g] + blue_weight[b]) >> 1;
				baux = 6'b0;
			end
			// Blanco y negro
			2'b11	: begin
				raux = red_weight[r] + green_weight[g] + blue_weight[b];
				gaux = red_weight[r] + green_weight[g] + blue_weight[b];
				baux = red_weight[r] + green_weight[g] + blue_weight[b];
			end
			// Color
			default: begin
				raux = r;
				gaux = g;
				baux = b;
			end
		endcase
	end

	assign VGA_R = {raux, 2'b0};
	assign VGA_G = {gaux, 2'b0};
	assign VGA_B = {baux, 2'b0};

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
