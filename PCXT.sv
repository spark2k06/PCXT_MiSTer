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
    //assign USER_OUT = '1;
    //assign {UART_RTS, UART_TXD, UART_DTR} = 0;
    assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
    //assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
    assign SDRAM_CLK = clk_chipset;
    assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

    assign VGA_F1 = 0;
    assign VGA_SCALER = 0;
    assign VGA_DISABLE = 0;
    assign HDMI_FREEZE = 0;

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
    // XXXXX XXXXXXXXXXXXXXXXXXXXXXXXXX XXXXXXXX

	`include "build_id.v"

    localparam CONF_STR = {
		"PCXT;UART115200:115200;",
		"S0,IMGIMAVFD,Floppy A:;",
		"S1,IMGIMAVFD,Floppy B:;",
		"OJK,Write Protect,None,A:,B:,A: & B:;",
		"-;",
		"S2,VHD,IDE 0-0;",
		"S3,VHD,IDE 0-1;",
		"OLM,2nd SD card,Disable,IDE 0-0,IDE 0-1;",
		"-;",
		"OHI,CPU Speed,4.77MHz,7.16MHz,9.54MHz,PC/AT 3.5MHz;",
		"-;",
		"P1,System & BIOS;",
		"P1-;",
		"P1O3,Model,IBM PCXT,Tandy 1000;",
		"P1-;",
		"P1oC,PCXT CGA Graphics,Yes,No;",
		"P1oD,PCXT Hercules Graphics,Yes,No;",
		"P1O4,PCXT 1st Video,CGA,Hercules;",
		"P1-;",
		"P1O7,Boot Splash Screen,Yes,No;",
		"P1-;",
		"P1FC0,ROM,PCXT BIOS:;",
		"P1FC1,ROM,Tandy BIOS:;",
		"P1-;",
		"P1FC2,ROM,EC00 BIOS:;",
		"P1-;",
		"P1OUV,BIOS Writable,None,EC00,PCXT/Tandy,All;",
		"P1-;",	
		"P2,Audio & Video;",
		"P2-;",
		"P2OA,C/MS Audio,Enabled,Disabled;",
		"P2oAB,OPL2,Adlib 388h,SB FM 388h/228h, Disabled;",
		"P2o01,Speaker Volume,1,2,3,4;",
		"P2o23,Tandy Volume,1,2,3,4;",
		"P2o45,Audio Boost,No,2x,4x;",
		"P2o67,Stereo Mix,none,25%,50%,100%;",
		"P2-;",
		"P2O12,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
		"P2O89,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
		"P2OT,Border,No,Yes;",
		"P2o8,Composite video,Off,On;",
		"P2OEG,Display,Full Color,Green,Amber,B&W,Red,Blue,Fuchsia,Purple;",
		"P2-;",
		"P3,Hardware;",
		"P3-;",
		"P3OB,Lo-tech 2MB EMS,Enabled,Disabled;",
		"P3OCD,EMS Frame,C000,D000,E000;",
		"P3-;",
		"P3o9,A000 UMB,Enabled,Disabled;",
		"P3-;",
		"P3ONO,Joystick 1, Analog, Digital, Disabled;",
		"P3OPQ,Joystick 2, Analog, Digital, Disabled;",
		"P3OR,Sync Joy to CPU Speed,No,Yes;",
		"P3OS,Swap Joysticks,No,Yes;",
		"P3-;",	
		"-;",
		"R0,Reset & apply settings;",
		"J,Fire 1,Fire 2;",
		"V,v",`BUILD_DATE
	};

    wire forced_scandoubler;
    wire [1:0] buttons;
    wire [63:0] status;
    wire [7:0]  xtctl;

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
    wire [15:0] ioctl_data;
    reg         ioctl_wait;

    wire [21:0] gamma_bus;

    wire [13:0] joy0, joy1;
    wire [15:0] joya0, joya1;
    wire [4:0]  joy_opts = status[27:23];

    wire composite = status[40] | xtctl[0];
    wire [1:0] scale = status[2:1];
    wire [2:0] screen_mode = status[16:14];
    wire [1:0] ar = status[9:8];
    wire border = status[29] | xtctl[1];
	wire a000h = ~status[41] & ~xtctl[6];

    reg [1:0]   scale_video_ff;
    reg         hgc_mode_video_ff;
    reg [2:0]   screen_mode_video_ff;
    reg         border_video_ff;
    reg         cga_hw;
    reg         hercules_hw;

    wire VGA_VBlank_border;
    wire std_hsyncwidth;
    wire pause_core;
    wire swap_video;

    always @(posedge CLK_VIDEO)
    begin
        scale_video_ff          <= scale;
        screen_mode_video_ff    <= screen_mode;
        border_video_ff         <= border;
        cga_hw                  <= ~status[44] | tandy_mode;
        hercules_hw             <= ~status[45] & ~tandy_mode;
        VIDEO_ARX               <= (!ar) ? 12'd4 : (ar - 1'd1);
        VIDEO_ARY               <= (!ar) ? 12'd3 : 12'd0;
    end

    always @(posedge clk_chipset)
        hgc_mode_video_ff       <= hgc_mode & ~tandy_mode;

    hps_io #(.CONF_STR(CONF_STR), .PS2DIV(2000), .PS2WE(1), .WIDE(1)) hps_io 
	(
		.clk_sys(clk_chipset),
		.HPS_BUS(HPS_BUS),
		.EXT_BUS(EXT_BUS),
		.gamma_bus(gamma_bus),

		.forced_scandoubler(forced_scandoubler),

		.buttons(buttons),
		.status(status),
		.status_menumask({status[5]}),

		.ps2_kbd_clk_in		(ps2_kbd_clk_out),
		.ps2_kbd_data_in	(ps2_kbd_data_out),
		.ps2_kbd_clk_out	(ps2_kbd_clk_in),
		.ps2_kbd_data_out	(ps2_kbd_data_in),

		.ps2_mouse_clk_out    (ps2_mouse_clk_out),
		.ps2_mouse_data_out   (ps2_mouse_data_out),
		.ps2_mouse_clk_in     (ps2_mouse_clk_in),
		.ps2_mouse_data_in    (ps2_mouse_data_in),

		.joystick_0(joy0),
		.joystick_1(joy1),
		.joystick_l_analog_0(joya0),
		.joystick_l_analog_1(joya1),

		//ioctl
		.ioctl_download(ioctl_download),
		.ioctl_index(ioctl_index),
		.ioctl_wr(ioctl_wr),
		.ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_data),
		.ioctl_wait(ioctl_wait)
	);


    wire [15:0] mgmt_din;
    wire [15:0] mgmt_dout;
    wire [15:0] mgmt_addr;
    wire        mgmt_rd;
    wire        mgmt_wr;
    wire  [7:0] mgmt_req;
    assign mgmt_req[5:3] = 3'b000;

    wire [35:0] EXT_BUS;
    hps_ext hps_ext  
	(
		.clk_sys(clk_chipset),
		.EXT_BUS(EXT_BUS),

		.ext_din(mgmt_din),
		.ext_dout(mgmt_dout),
		.ext_addr(mgmt_addr),
		.ext_rd(mgmt_rd),
		.ext_wr(mgmt_wr),

		.ext_req(mgmt_req),
		.ext_hotswap(2'b00)
	);

    //
    ///////////////////////   CLOCKS   /////////////////////////////
    //

    wire clk_sys;
    wire pll_locked;

    wire clk_100;
    wire clk_28_636;
    wire clk_56_875;
    wire clk_113_750;
    reg clk_25 = 1'b0;
    reg clk_14_318 = 1'b0;
    reg clk_9_54 = 1'b0;
    reg clk_7_16 = 1'b0;
    wire clk_4_77;
    wire clk_cpu;
    wire pclk;
    wire clk_chipset;
    wire peripheral_clock;
    wire clk_uart;

    localparam [27:0] cur_rate = 28'd50000000;

    pll pll 
	(
		.refclk(CLK_50M),
		.rst(0),
		.outclk_0(clk_100),
		.outclk_1(clk_56_875),
		.outclk_2(clk_28_636),
		.outclk_3(clk_uart),
		//.outclk_4(clk_opl2),
		.outclk_5(clk_chipset),
		.outclk_6(clk_113_750),
		.locked(pll_locked)
	);

    wire reset_wire = RESET | status[0] | buttons[1] | !pll_locked | splashscreen;
    wire reset_sdram_wire = RESET | !pll_locked;

    //////////////////////////////////////////////////////////////////

    // TODO: messy, use a single clock domain at least
    always @(posedge clk_28_636)
    begin
        HBlank_del <= {HBlank_del[13], HBlank_del[12], HBlank_del[11], HBlank_del[10], HBlank_del[9],
                       HBlank_del[8], HBlank_del[7], HBlank_del[6], HBlank_del[5], HBlank_del[4],
                       HBlank_del[3], HBlank_del[2], HBlank_del[1], HBlank_del[0], HBlank};
        clk_14_318 <= ~clk_14_318;  // 14.318Mhz
        ce_pixel_cga <= clk_14_318;	//if outside always block appears an overscan column in CGA mode
    end

    reg [4:0] clk_9_54_cnt = 1'b0;
    always @(posedge clk_chipset)
        if (4'd0 == clk_9_54_cnt) begin
            if (clk_9_54)
                clk_9_54_cnt  <= 4'd3 - 4'd1;
            else
                clk_9_54_cnt  <= 4'd2 - 4'd1;
            clk_9_54      <= ~clk_9_54;
        end
        else begin
            clk_9_54_cnt  <= clk_9_54_cnt - 4'd1;
            clk_9_54      <= clk_9_54;
        end

    always @(posedge clk_chipset)
        clk_25 <= ~clk_25;

    always @(posedge clk_14_318)
        clk_7_16 <= ~clk_7_16;      // 7.16Mhz

    clk_div3 clk_normal             // 4.77MHz
    (
        .clk(clk_14_318),
        .clk_out(clk_4_77)
    );

    always @(posedge clk_4_77)
        peripheral_clock <= ~peripheral_clock; // 2.385Mhz

    //////////////////////////////////////////////////////////////////

    logic  biu_done;
    logic  [7:0] clock_cycle_counter_division_ratio;
    logic  [7:0] clock_cycle_counter_decrement_value;
    logic        shift_read_timing;
    logic  [1:0] ram_read_wait_cycle;
    logic  [1:0] ram_write_wait_cycle;
    logic        cycle_accrate;
    logic  [1:0] clk_select;


    always @(posedge clk_chipset, posedge reset)
    begin
        if (reset)
            clk_select  <= 2'b00;

        else if (biu_done)
            clk_select  <= (xtctl[3:2] == 2'b00 & ~xtctl[7]) ? status[18:17] : xtctl[7] ? 2'b11 : xtctl[3:2] - 2'b01;

        else
            clk_select  <= clk_select;

    end

    logic  clk_cpu_ff_1;
    logic  clk_cpu_ff_2;

    logic  pclk_ff_1;
    logic  pclk_ff_2;

    always @(posedge clk_chipset, posedge reset)
    begin
        if (reset)
        begin
            clk_cpu_ff_1    <= 1'b0;
            clk_cpu_ff_2    <= 1'b0;
            clk_cpu         <= 1'b0;
            pclk_ff_1       <= 1'b0;
            pclk_ff_2       <= 1'b0;
            pclk            <= 1'b0;
            cycle_accrate   <= 1'b1;
            clock_cycle_counter_division_ratio  <= 8'd1 - 8'd1;
            clock_cycle_counter_decrement_value <= 8'd1;
            shift_read_timing                   <= 1'b0;
            ram_read_wait_cycle                 <= 2'd0;
            ram_write_wait_cycle                <= 2'd0;
        end
        else
        begin
            clk_cpu_ff_2    <= clk_cpu_ff_1;
            clk_cpu         <= clk_cpu_ff_2;
            pclk_ff_1       <= peripheral_clock;
            pclk_ff_2       <= pclk_ff_1;
            pclk            <= pclk_ff_2;
            casez (clk_select)
                2'b00: begin
                    clk_cpu_ff_1    <= clk_4_77;
                    clock_cycle_counter_division_ratio  <= 8'd1 - 8'd1;
                    clock_cycle_counter_decrement_value <= 8'd1;
                    shift_read_timing                   <= 1'b0;
                    ram_read_wait_cycle                 <= 2'd0;
                    ram_write_wait_cycle                <= 2'd0;
                    cycle_accrate                       <= 1'b1;
                end
                2'b01: begin
                    clk_cpu_ff_1    <= clk_7_16;
                    clock_cycle_counter_division_ratio  <= 8'd2 - 8'd1;
                    clock_cycle_counter_decrement_value <= 8'd3;
                    shift_read_timing                   <= 1'b0;
                    ram_read_wait_cycle                 <= 2'd0;
                    ram_write_wait_cycle                <= 2'd0;
                    cycle_accrate                       <= 1'b1;
                end
                2'b10: begin
                    clk_cpu_ff_1    <= clk_9_54;
                    clock_cycle_counter_division_ratio  <= 8'd10 - 8'd1;
                    clock_cycle_counter_decrement_value <= 8'd21;
                    shift_read_timing                   <= 1'b0;
                    ram_read_wait_cycle                 <= 2'd0;
                    ram_write_wait_cycle                <= 2'd0;
                    cycle_accrate                       <= 1'b1;

                end
                2'b11: begin
                    clk_cpu_ff_1    <= clk_25;
                    clock_cycle_counter_division_ratio  <= 8'd1 - 8'd1;
                    clock_cycle_counter_decrement_value <= 8'd5;
                    shift_read_timing                   <= 1'b1;
                    ram_read_wait_cycle                 <= 2'd1;
                    ram_write_wait_cycle                <= 2'd0;
                    cycle_accrate                       <= 1'b0;
                end
            endcase
        end
    end

    //////////////////////////////////////////////////////////////////

    logic reset = 1'b1;
    logic [15:0] reset_count = 16'h0000;
    logic reset_sdram = 1'b1;
    logic [15:0] reset_sdram_count = 16'h0000;

    always @(posedge clk_chipset, posedge reset_wire)
    begin
        if (reset_wire)
        begin
            reset <= 1'b1;
            reset_count <= 16'h0000;
        end
        else if (reset)
        begin
            if (reset_count != 16'hffff)
            begin
                reset <= 1'b1;
                reset_count <= reset_count + 16'h0001;
            end
            else
            begin
                reset <= 1'b0;
                reset_count <= reset_count;
            end
        end
        else
        begin
            reset <= 1'b0;
            reset_count <= reset_count;
        end
    end

    logic reset_cpu_ff = 1'b1;
    logic reset_cpu = 1'b1;
    logic [15:0] reset_cpu_count = 16'h0000;

    always @(negedge clk_chipset, posedge reset)
    begin
        if (reset)
            reset_cpu_ff <= 1'b1;
        else
            reset_cpu_ff <= reset;
    end

    reg tandy_mode = 0;
    reg hgc_mode = 0;

    always @(negedge clk_chipset, posedge reset)
    begin
        if (reset)
        begin
            tandy_mode <= status[3];
            hgc_mode <= status[4];
            reset_cpu <= 1'b1;
            reset_cpu_count <= 16'h0000;
        end
        else if (reset_cpu)
        begin
            reset_cpu <= reset_cpu_ff;
            reset_cpu_count <= 16'h0000;
        end
        else
        begin
            if (reset_cpu_count != 16'h002A)
            begin
                reset_cpu <= reset_cpu_ff;
                reset_cpu_count <= reset_cpu_count + 16'h0001;
            end
            else
            begin
                reset_cpu <= 1'b0;
                reset_cpu_count <= reset_cpu_count;
            end
        end
    end

    always @(posedge clk_chipset, posedge reset_sdram_wire)
    begin
        if (reset_sdram_wire)
        begin
            reset_sdram <= 1'b1;
            reset_sdram_count <= 16'h0000;
        end
        else if (reset_sdram)
        begin
            if (reset_sdram_count != 16'hffff)
            begin
                reset_sdram <= 1'b1;
                reset_sdram_count <= reset_sdram_count + 16'h0001;
            end
            else
            begin
                reset_sdram <= 1'b0;
                reset_sdram_count <= reset_sdram_count;
            end
        end
        else
        begin
            reset_sdram <= 1'b0;
            reset_sdram_count <= reset_sdram_count;
        end
    end

    //
    ///////////////////////   BIOS LOADER   ////////////////////////////
    //

    reg [4:0]  bios_load_state = 4'h0;
    reg [1:0]  bios_protect_flag;
    reg        bios_access_request;
    reg [19:0] bios_access_address;
    reg [15:0] bios_write_data;
    reg        bios_write_n;
    reg [7:0]  bios_write_wait_cnt;
    reg        bios_write_byte_cnt;
    reg        tandy_bios_write;

    wire select_pcxt  = (ioctl_index[5:0] == 0) && (ioctl_addr[24:16] == 9'b000000000);
    wire select_tandy = (ioctl_index[5:0] == 1) && (ioctl_addr[24:16] == 9'b000000000);
    wire select_xtide = ioctl_index == 2;

    wire [19:0] bios_access_address_wire = select_pcxt  ? { 4'b1111, ioctl_addr[15:0]} :
         select_tandy ? { 4'b1111, ioctl_addr[15:0]} :
         select_xtide ? { 6'b111011, ioctl_addr[13:0]} :
         20'hFFFFF;

    wire bios_load_n = ~(ioctl_download & (select_pcxt | select_tandy | select_xtide));

    always @(posedge clk_chipset, posedge reset_sdram)
    begin
        if (reset_sdram)
        begin
            bios_protect_flag   <= 2'b11;
            bios_access_request <= 1'b0;
            bios_access_address <= 20'hFFFFF;
            bios_write_data     <= 16'hFFFF;
            bios_write_n        <= 1'b1;
            bios_write_wait_cnt <= 'h0;
            bios_write_byte_cnt <= 1'h0;
            tandy_bios_write    <= 1'b0;
            ioctl_wait          <= 1'b1;
            bios_load_state     <= 4'h00;
        end
        else if (~initilized_sdram)
        begin
            bios_protect_flag   <= 2'b11;
            bios_access_request <= 1'b0;
            bios_access_address <= 20'hFFFFF;
            bios_write_data     <= 16'hFFFF;
            bios_write_n        <= 1'b1;
            bios_write_wait_cnt <= 'h0;
            bios_write_byte_cnt <= 1'h0;
            ioctl_wait          <= 1'b1;
            bios_load_state     <= 4'h00;
        end
        else
        begin
            casez (bios_load_state)
                4'h00:
                begin
                    bios_protect_flag   <= ~status[31:30];  // bios_writable
                    bios_access_address <= 20'hFFFFF;
                    bios_write_data     <= 16'hFFFF;
                    bios_write_n        <= 1'b1;
                    bios_write_wait_cnt <= 'h0;
                    bios_write_byte_cnt <= 1'h0;
                    tandy_bios_write    <= 1'b0;

                    if (~ioctl_download)
                    begin
                        bios_access_request <= 1'b0;
                        ioctl_wait          <= 1'b0;
                    end
                    else
                    begin
                        bios_access_request <= 1'b1;
                        ioctl_wait          <= 1'b1;
                    end

                    if ((ioctl_download) && (~processor_ready) && (address_direction))
                        bios_load_state <= 4'h01;
                    else
                        bios_load_state <= 4'h00;
                end
                4'h01:
                begin
                    bios_protect_flag   <= 2'b00;
                    bios_access_request <= 1'b1;
                    bios_write_byte_cnt <= 1'h0;
                    tandy_bios_write    <= select_tandy;

                    if (~ioctl_download)
                    begin
                        bios_access_address <= 20'hFFFFF;
                        bios_write_data     <= 16'hFFFF;
                        bios_write_n        <= 1'b1;
                        bios_write_wait_cnt <= 'h0;
                        ioctl_wait          <= 1'b0;
                        bios_load_state     <= 4'h00;
                    end
                    else if ((~ioctl_wr) || (bios_load_n))
                    begin
                        bios_access_address <= 20'hFFFFF;
                        bios_write_data     <= 16'hFFFF;
                        bios_write_n        <= 1'b1;
                        bios_write_wait_cnt <= 'h0;
                        ioctl_wait          <= 1'b0;
                        bios_load_state     <= 4'h01;
                    end
                    else
                    begin
                        bios_access_address <= bios_access_address_wire;
                        bios_write_data     <= ioctl_data;
                        bios_write_n        <= 1'b1;
                        bios_write_wait_cnt <= 'h0;
                        ioctl_wait          <= 1'b1;
                        bios_load_state     <= 4'h02;
                    end
                end
                4'h02:
                begin
                    bios_protect_flag   <= 2'b00;
                    bios_access_request <= 1'b1;
                    bios_access_address <= bios_access_address;
                    bios_write_data     <= bios_write_data;
                    bios_write_byte_cnt <= bios_write_byte_cnt;
                    tandy_bios_write    <= select_tandy;
                    ioctl_wait          <= 1'b1;
                    bios_write_wait_cnt <= bios_write_wait_cnt + 'h1;

                    if (bios_write_wait_cnt != 'd20)
                    begin
                        bios_write_n        <= 1'b0;
                        bios_load_state     <= 4'h02;
                    end
                    else
                    begin
                        bios_write_n        <= 1'b1;
                        bios_load_state     <= 4'h03;
                    end
                end
                4'h03:
                begin
                    bios_protect_flag   <= 2'b00;
                    bios_access_request <= 1'b1;
                    bios_access_address <= bios_access_address;
                    bios_write_data     <= bios_write_data;
                    bios_write_n        <= 1'b1;
                    bios_write_byte_cnt <= bios_write_byte_cnt;
                    tandy_bios_write    <= 1'b0;
                    ioctl_wait          <= 1'b1;
                    bios_write_wait_cnt <= bios_write_wait_cnt + 'h1;

                    if (bios_write_wait_cnt != 'h40)
                        bios_load_state     <= 4'h03;
                    else
                        bios_load_state     <= 4'h04;
                end
                4'h04:
                begin
                    bios_protect_flag   <= 2'b00;
                    bios_access_request <= 1'b1;
                    bios_access_address <= bios_access_address + 'h1;
                    bios_write_data     <= {8'hFF, bios_write_data[15:8]};
                    bios_write_n        <= 1'b1;
                    bios_write_wait_cnt <= 'h0;
                    bios_write_byte_cnt <= ~bios_write_byte_cnt;
                    tandy_bios_write    <= 1'b0;
                    ioctl_wait          <= 1'b1;
                    if (bios_write_byte_cnt == 1'b0)
                        bios_load_state     <= 4'h02;
                    else
                        bios_load_state     <= 4'h01;
                end
                default:
                begin
                    bios_protect_flag   <= 2'b11;
                    bios_access_request <= 1'b0;
                    bios_access_address <= 20'hFFFFF;
                    bios_write_data     <= 16'hFFFF;
                    bios_write_n        <= 1'b1;
                    bios_write_wait_cnt <= 'h0;
                    bios_write_byte_cnt <= 1'h0;
                    tandy_bios_write    <= 1'b0;
                    ioctl_wait          <= 1'b0;
                    bios_load_state     <= 4'h00;
                end
            endcase
        end
    end


    //////////////////////////////////////////////////////////////////

    //
    // Splash screen
    //
    reg splash_off;
    reg [24:0] splash_cnt = 0;
    reg [3:0] splash_cnt2 = 0;
    reg splashscreen = 1;

    always @ (posedge clk_14_318)
    begin
        splash_off <= status[7];

        if (splashscreen)
        begin
            if (splash_off)
                splashscreen <= 0;
            else if(splash_cnt2 == 5) // 5 seconds delay
                splashscreen <= 0;
            else if (splash_cnt == 14318000)
            begin // 1 second at 14.318Mhz
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
        if (reset)
        begin
            device_clock_ff <= 1'b0;
            device_clock    <= 1'b0;
        end
        else
        begin
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
        if (reset)
        begin
            device_data_ff <= 1'b0;
            device_data    <= 1'b0;
        end
        else
        begin
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
    wire address_direction;

    wire lock_n;
    wire [2:0]processor_status;

    wire [3:0]   dma_acknowledge_n;

    logic   [7:0]   port_b_out;
    logic   [7:0]   port_c_in;
    reg     [7:0]   sw;

    assign  sw = hgc_mode ? 8'b00111101 : 8'b00101101; // PCXT DIP Switches (HGC or CGA 80)
    assign  port_c_in[3:0] = port_b_out[3] ? sw[7:4] : sw[3:0];

    wire tandy_bios_flag = bios_write_n ? tandy_mode : tandy_bios_write;

    always @(posedge clk_chipset)
    begin
        if (address_latch_enable)
            cpu_address <= cpu_ad_out;
        else
            cpu_address <= cpu_address;
    end

    CHIPSET #(.clk_rate(cur_rate)) u_CHIPSET
	(
		.clock                              (clk_chipset),
		.cpu_clock                          (clk_cpu),
		.clk_sys                            (clk_chipset),
		.peripheral_clock                   (pclk),
		.clk_select                         (clk_select),
		.reset                              (reset_cpu),
		.sdram_reset                        (reset_sdram),
		.cpu_address                        (cpu_address),
		.cpu_data_bus                       (cpu_data_bus),
		.processor_status                   (processor_status),
		.processor_lock_n                   (lock_n),
	//	.processor_transmit_or_receive_n    (processor_transmit_or_receive_n),
		.processor_ready                    (processor_ready),
		.interrupt_to_cpu                   (interrupt_to_cpu),
		.splashscreen                       (splashscreen),
		.std_hsyncwidth                     (std_hsyncwidth),
		.composite                          (composite),
		.video_output                       (hgc_mode_video_ff),
		.clk_vga_cga                        (clk_28_636),
		.enable_cga                         (1'b1),
		.clk_vga_hgc                        (clk_56_875),
		.enable_hgc                         (1'b1),
		.hgc_rgb                            (2'b10), // always B&W - monochrome monitor tint handled down below
	//	.de_o                               (VGA_DE),
		.VGA_R                              (r),
		.VGA_G                              (g),
		.VGA_B                              (b),
		.VGA_HSYNC                          (HSync),
		.VGA_VSYNC                          (VSync),
		.VGA_HBlank                         (HBlank),
		.VGA_VBlank                         (VBlank),
		.VGA_VBlank_border                  (VGA_VBlank_border),
	//	.address                            (address),
		.address_ext                        (bios_access_address),
		.ext_access_request                 (bios_access_request),
		.address_direction                  (address_direction),
		.data_bus                           (data_bus),
		.data_bus_ext                       (bios_write_data[7:0]),
	//	.data_bus_direction                 (data_bus_direction),
		.address_latch_enable               (address_latch_enable),
	//  .io_channel_check                   (),
		.io_channel_ready                   (1'b1),
		.interrupt_request                  (0),    // use?	-> It does not seem to be necessary.
	//  .io_read_n                          (io_read_n),
		.io_read_n_ext                      (1'b1),
	//  .io_read_n_direction                (io_read_n_direction),
	//  .io_write_n                         (io_write_n),
		.io_write_n_ext                     (1'b1),
	//  .io_write_n_direction               (io_write_n_direction),
	//  .memory_read_n                      (memory_read_n),
		.memory_read_n_ext                  (1'b1),
	//  .memory_read_n_direction            (memory_read_n_direction),
	//  .memory_write_n                     (memory_write_n),
		.memory_write_n_ext                 (bios_write_n),
	//  .memory_write_n_direction           (memory_write_n_direction),
		.dma_request                        (0),    // use?	-> I don't know if it will ever be necessary, at least not during testing.
		.dma_acknowledge_n                  (dma_acknowledge_n),
	//  .address_enable_n                   (address_enable_n),
	//  .terminal_count_n                   (terminal_count_n)
		.port_b_out                         (port_b_out),
		.port_c_in                          (port_c_in),
		.port_b_in                          (port_b_out),
		.speaker_out                        (speaker_out),
		.ps2_clock                          (device_clock),
		.ps2_data                           (device_data),
		.ps2_clock_out                      (ps2_kbd_clk_out),
		.ps2_data_out                       (ps2_kbd_data_out),
		.ps2_mouseclk_in                    (ps2_mouse_clk_out),
		.ps2_mousedat_in                    (ps2_mouse_data_out),
		.ps2_mouseclk_out                   (ps2_mouse_clk_in),
		.ps2_mousedat_out                   (ps2_mouse_data_in),
		.joy_opts                           (joy_opts),           //Joy0-Disabled, Joy0-Type, Joy1-Disabled, Joy1-Type, turbo_sync
		.joy0                               (status[28] ? joy1 : joy0),
		.joy1                               (status[28] ? joy0 : joy1),
		.joya0                              (status[28] ? joya1 : joya0),
		.joya1                              (status[28] ? joya0 : joya1),
		.jtopl2_snd_e                       (jtopl2_snd_e),
		.tandy_snd_e                        (tandy_snd_e),
		.opl2_io                            (xtctl[4] ? 2'b10 : status[43:42]),
		.cms_en                             (~status[10]),
		.o_cms_l                            (cms_l_snd_e),
		.o_cms_r                            (cms_r_snd_e),
		.tandy_video                        (tandy_mode),
		.tandy_bios_flag                    (tandy_bios_flag),
		.tandy_16_gfx                       (tandy_16_gfx),
		.tandy_color_16                     (tandy_color_16),
		.clk_uart                           (clk_uart2_en),
		.uart2_rx                           (uart_rx),
		.uart2_tx                           (uart_tx),
		.uart2_cts_n                        (uart_cts),
		.uart2_dcd_n                        (uart_dcd),
		.uart2_dsr_n                        (uart_dsr),
		.uart2_rts_n                        (uart_rts),
		.uart2_dtr_n                        (uart_dtr),
		.enable_sdram                       (1'b1),
		.initilized_sdram                   (initilized_sdram),
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
		.bios_protect_flag                  (bios_protect_flag),
		.use_mmc                            (use_mmc),
		.spi_clk                            (spi_clk),
		.spi_cs                             (spi_cs),
		.spi_mosi                           (spi_mosi),
		.spi_miso                           (spi_miso),
		.mgmt_readdata                      (mgmt_din),
		.mgmt_writedata                     (mgmt_dout),
		.mgmt_address                       (mgmt_addr),
		.mgmt_write                         (mgmt_wr),
		.mgmt_read                          (mgmt_rd),
		.floppy_wp                          (status[20:19]),
		.fdd_request                        (mgmt_req[7:6]),
		.ide0_request                       (mgmt_req[2:0]),
		.xtctl                              (xtctl),
		.enable_a000h                       (a000h),
		.wait_count_clk_en                  (~clk_cpu & clk_cpu_ff_2),
		.ram_read_wait_cycle                (ram_read_wait_cycle),
		.ram_write_wait_cycle               (ram_write_wait_cycle),
		.pause_core                         (pause_core),
		.cga_hw                             (cga_hw),
		.hercules_hw                        (hercules_hw),
		.swap_video                         (swap_video)
	);

    wire [15:0] SDRAM_DQ_IN;
    wire [15:0] SDRAM_DQ_OUT;
    wire        SDRAM_DQ_IO;
    wire        initilized_sdram;

    assign SDRAM_DQ_IN = SDRAM_DQ;
    assign SDRAM_DQ = ~SDRAM_DQ_IO ? SDRAM_DQ_OUT : 16'hZZZZ;

    wire s6_3_mux;
    wire [2:0] SEGMENT;

    i8088 B1 	
	(
		.CORE_CLK(clk_100),
		.CLK(clk_cpu),

		.RESET(reset_cpu),
		.READY(processor_ready && ~pause_core),
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
		.cycle_accrate(cycle_accrate),
		.clock_cycle_counter_division_ratio(clock_cycle_counter_division_ratio),
		.clock_cycle_counter_decrement_value(clock_cycle_counter_decrement_value),
		.shift_read_timing(shift_read_timing)
	);

    //
    ////////////////////////////  AUDIO  ///////////////////////////////////
    //

    wire [15:0] cms_l_snd_e;
    wire [16:0] cms_l_snd = {cms_l_snd_e[15],cms_l_snd_e};
    wire [15:0] cms_r_snd_e;
    wire [16:0] cms_r_snd = {cms_r_snd_e[15],cms_r_snd_e};
	 
    wire [15:0] jtopl2_snd_e;
    wire [16:0] jtopl2_snd = {jtopl2_snd_e[15], jtopl2_snd_e};
    wire [10:0] tandy_snd_e;
    wire [16:0] tandy_snd = {{{2{tandy_snd_e[10]}}, {4{tandy_snd_e[10]}}, tandy_snd_e} << status[35:34], 2'b00};
    wire [16:0] spk_vol =  {2'b00, {3'b000,~speaker_out} << status[33:32], 11'd0};
    wire        speaker_out;

    localparam [3:0] comp_f1 = 4;
    localparam [3:0] comp_a1 = 2;
    localparam       comp_x1 = ((32767 * (comp_f1 - 1)) / ((comp_f1 * comp_a1) - 1)) + 1; // +1 to make sure it won't overflow
    localparam       comp_b1 = comp_x1 * comp_a1;

    localparam [3:0] comp_f2 = 8;
    localparam [3:0] comp_a2 = 4;
    localparam       comp_x2 = ((32767 * (comp_f2 - 1)) / ((comp_f2 * comp_a2) - 1)) + 1; // +1 to make sure it won't overflow
    localparam       comp_b2 = comp_x2 * comp_a2;

    function [15:0] compr;
        input [15:0] inp;
        reg [15:0] v, v1, v2;
        begin
            v  = inp[15] ? (~inp) + 1'd1 : inp;
            v1 = (v < comp_x1[15:0]) ? (v * comp_a1) : (((v - comp_x1[15:0])/comp_f1) + comp_b1[15:0]);
            v2 = (v < comp_x2[15:0]) ? (v * comp_a2) : (((v - comp_x2[15:0])/comp_f2) + comp_b2[15:0]);
            v  = status[37] ? v2 : v1;
            compr = inp[15] ? ~(v-1'd1) : v;
        end
    endfunction

    reg [15:0] cmp_l;
    reg [15:0] out_l;
    always @(posedge clk_chipset)
    begin
        reg [16:0] tmp_l;

        tmp_l <= jtopl2_snd + cms_l_snd + tandy_snd + spk_vol;

        // clamp the output
        out_l <= (^tmp_l[16:15]) ? {tmp_l[16], {15{tmp_l[15]}}} : tmp_l[15:0];

        cmp_l <= compr(out_l);
    end
	 
    reg [15:0] cmp_r;
    reg [15:0] out_r;
    always @(posedge clk_chipset)
    begin
        reg [16:0] tmp_r;

        tmp_r <= jtopl2_snd + cms_r_snd + tandy_snd + spk_vol;

        // clamp the output
        out_r <= (^tmp_r[16:15]) ? {tmp_r[16], {15{tmp_r[15]}}} : tmp_r[15:0];

        cmp_r <= compr(out_r);
    end

    assign AUDIO_L   = pause_core ? 1'b0 : status[37:36] ? cmp_l : out_l;
    assign AUDIO_R   = pause_core ? 1'b0 : status[37:36] ? cmp_r : out_r;
    assign AUDIO_S   = 1;
    assign AUDIO_MIX = status[39:38];

    //
    ////////////////////////////  UART  ///////////////////////////////////
    //

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
    logic clk_uart2_en;
    logic [2:0] clk_uart2_counter;

    always @(posedge clk_chipset)
    begin
        clk_uart_ff_1 <= clk_uart;
        clk_uart_ff_2 <= clk_uart_ff_1;
        clk_uart_ff_3 <= clk_uart_ff_2;
        clk_uart_en   <= ~clk_uart_ff_3 & clk_uart_ff_2;
    end

    always @(posedge clk_chipset)
    begin
        if (clk_uart_en)
        begin
            if (3'd7 != clk_uart2_counter)
            begin
                clk_uart2_counter <= clk_uart2_counter +3'd1;
                clk_uart2_en <= 1'b0;
            end
            else
            begin
                clk_uart2_counter <= 3'd0;
                clk_uart2_en <= 1'b1;
            end
        end
        else
        begin
            clk_uart2_counter <= clk_uart2_counter;
            clk_uart2_en <= 1'b0;
        end
    end

    wire uart_tx, uart_rts, uart_dtr;

    assign UART_TXD = uart_tx;
    assign UART_RTS = uart_rts;
    assign UART_DTR = uart_dtr;

    wire uart_rx  = UART_RXD;
    wire uart_cts = UART_CTS;
    wire uart_dsr = UART_DSR;
    wire uart_dcd = UART_DTR;


    /// UART2

    assign USER_OUT = {1'b1, 1'b1, uart2_dtr, 1'b1, uart2_rts, uart2_tx, 1'b1};

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

    wire uart2_tx, uart2_rts, uart2_dtr;

    wire uart2_rx  = USER_IN[0];
    wire uart2_cts = USER_IN[3];
    wire uart2_dsr = USER_IN[5];
    wire uart2_dcd = USER_IN[6];

    //
    ///////////////////////   MMC     ///////////////////////
    //
    logic [1:0]  use_mmc;
    logic spi_clk;
    logic spi_cs;
    logic spi_mosi;
    logic spi_miso;

    always @(posedge clk_chipset)
        if (reset)
            use_mmc <= status[22:21];
        else
            use_mmc <= use_mmc;

    assign  SD_SCK      = spi_clk;
    assign  SD_MOSI     = spi_mosi;
    assign  spi_miso    = SD_MISO;
    assign  SD_CS       = spi_cs;

    //
    ///////////////////////   VIDEO   ///////////////////////
    //

    wire HBlank;
    wire HSync;
    wire VBlank;
    wire VSync;
    wire ce_pixel_cga;
    wire ce_pixel_hgc;
    wire de_o;
    wire [5:0] r, g, b;
    reg [7:0] raux_cga, gaux_cga, baux_cga;
    reg [7:0] raux_hgc, gaux_hgc, baux_hgc;
	 wire [7:0] VGA_R_AUX, VGA_G_AUX, VGA_B_AUX;
    wire CLK_VIDEO_HGC;
    wire CLK_VIDEO_CGA;

    wire  [7:0] VGA_R_cga;
    wire  [7:0] VGA_G_cga;
    wire  [7:0] VGA_B_cga;
    wire        VGA_HS_cga;
    wire        VGA_VS_cga;
    wire        VGA_DE_cga;
    wire [21:0] gamma_bus_cga;
    wire        CE_PIXEL_cga;

    wire  [7:0] VGA_R_hgc;
    wire  [7:0] VGA_G_hgc;
    wire  [7:0] VGA_B_hgc;
    wire        VGA_HS_hgc;
    wire        VGA_VS_hgc;
    wire        VGA_DE_hgc;
    wire [21:0] gamma_bus_hgc;
    wire        CE_PIXEL_hgc;

    assign CLK_VIDEO = clk_56_875;
    assign CLK_VIDEO_HGC = clk_113_750;
    assign CLK_VIDEO_CGA = clk_56_875;
    assign ce_pixel_hgc = clk_28_636;

    assign VGA_SL = {scale_video_ff==3, scale_video_ff==2};

    wire   scandoubler = (scale_video_ff>0); //|| forced_scandoubler);

    reg [14:0] HBlank_del;
    wire tandy_16_gfx;
    wire color = (screen_mode_video_ff == 3'd0);
    
	 wire HBlank_VGA;

    reg [10:0] HBlank_counter = 0;
    reg HBlank_fixed = 1'b1;
    reg [1:0] HSync_del = 1'b11;

    reg        video_pause_core_buf;
    reg        video_pause_core;

    always_comb
    begin
        if (swap_video & ~tandy_mode)

        HBlank_VGA = HBlank_del[color ? 12 : 13];

        else if (tandy_color_16)
            HBlank_VGA = HBlank_del[color ? 11 : 13];

        else if (tandy_16_gfx)
            HBlank_VGA = HBlank_del[color ? 9 : 11];

        else HBlank_VGA = HBlank_del[color ? 5 : 7];
    end

    always @ (posedge ce_pixel_cga)
    begin

        HSync_del <= {HSync_del[0], HSync};

        if (HSync_del == 2'b01)
        begin
            HBlank_counter <= 0;
            HBlank_fixed <= 1'b1;
        end
        else
        begin
            if (HBlank_counter == (std_hsyncwidth ? 120 : 143))
                HBlank_fixed <= 1'b0;
            else
                HBlank_counter <= HBlank_counter + 1;
        end
    end

    always @ (posedge clk_56_875) begin
        video_pause_core_buf    <= pause_core;
        video_pause_core        <= video_pause_core_buf;
    end

    video_monochrome_converter video_mono_cga 
	(
		.clk_vid(CLK_VIDEO_CGA),
		.ce_pix(ce_pixel_cga),

		.R({r, 2'b00}),
		.G({g, 2'b00}),
		.B({b, 2'b00}),

		.gfx_mode(screen_mode_video_ff),

		.R_OUT(raux_cga),
		.G_OUT(gaux_cga),
		.B_OUT(baux_cga)
	);

    video_monochrome_converter video_mono_hgc
	(
		.clk_vid(CLK_VIDEO_HGC),
		.ce_pix(ce_pixel_hgc),

		.R({r, 2'b00}),
		.G({g, 2'b00}),
		.B({b, 2'b00}),

		.gfx_mode(screen_mode_video_ff),

		.R_OUT(raux_hgc),
		.G_OUT(gaux_hgc),
		.B_OUT(baux_hgc)
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

    wire LHBL = (~swap_video && border_video_ff) ? HBlank_fixed : HBlank_VGA;
    wire LVBL = (~swap_video && border_video_ff) ? std_hsyncwidth ? VGA_VBlank_border : ~VSync : VBlank;

    wire       pre2x_LHBL, pre2x_LVBL;
    wire [7:0] pre2x_r, pre2x_g, pre2x_b;
	 

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

		.HBlank(pre2x_LHBL),
		.VBlank(pre2x_LVBL),
		.HSync(HSync),
		.VSync(VSync),

		.scandoubler(scandoubler),
		.hq2x(scale_video_ff==1),
		.gamma_bus(gamma_bus_cga),

		.VGA_R(VGA_R_cga),
		.VGA_G(VGA_G_cga),
		.VGA_B(VGA_B_cga),
		.VGA_VS(VGA_VS_cga),
		.VGA_HS(VGA_HS_cga),
		.VGA_DE(VGA_DE_cga)

	);

    video_mixer #(.GAMMA(0)) video_mixer_hgc
	(
		.*,

		.CLK_VIDEO(CLK_VIDEO_HGC),
		.CE_PIXEL(CE_PIXEL_hgc),
		.ce_pix(ce_pixel_hgc),

		.freeze_sync(),

		.R(raux_hgc),
		.G(gaux_hgc),
		.B(baux_hgc),

		.HBlank(pre2x_LHBL),
		.VBlank(pre2x_LVBL),
		.HSync(HSync),
		.VSync(VSync),

		.scandoubler(scandoubler),
		.hq2x(scale_video_ff==1),
		.gamma_bus(gamma_bus_hgc),

		.VGA_R(VGA_R_hgc),
		.VGA_G(VGA_G_hgc),
		.VGA_B(VGA_B_hgc),
		.VGA_VS(VGA_VS_hgc),
		.VGA_HS(VGA_HS_hgc),
		.VGA_DE(VGA_DE_hgc)

	);


    assign VGA_R_AUX  =  swap_video & ~tandy_mode ? VGA_R_hgc  : VGA_R_cga;
    assign VGA_G_AUX  =  swap_video & ~tandy_mode ? VGA_G_hgc  : VGA_G_cga;
    assign VGA_B_AUX  =  swap_video & ~tandy_mode ? VGA_B_hgc  : VGA_B_cga;
    assign VGA_HS =  swap_video & ~tandy_mode ? VGA_HS_hgc : VGA_HS_cga;
    assign VGA_VS =  swap_video & ~tandy_mode ? VGA_VS_hgc : VGA_VS_cga;
    assign VGA_DE =  swap_video & ~tandy_mode ? VGA_DE_hgc : VGA_DE_cga;
    assign gamma_bus =  swap_video & ~tandy_mode ? gamma_bus_hgc : gamma_bus_cga;
    assign CE_PIXEL  =  swap_video & ~tandy_mode ? CE_PIXEL_hgc : CE_PIXEL_cga;



    jtframe_credits #(
        .PAGES  (4),
        .COLW   (8),
        .BLKPOL (1)
    ) u_credits(
        .rst        ( reset      ),
        .clk        ( clk_56_875 ),
        .pxl_cen    ( CE_PIXEL   ),

        // input image
        .HB         ( LHBL  ),
        .VB         ( LVBL  ),
        .rgb_in     ( { VGA_R_AUX, VGA_G_AUX, VGA_B_AUX } ),
        .rotate     ( 2'd0  ),
        .toggle     ( 1'b0  ),
        .fast_scroll( 1'b0  ),
        .border     ( swap_video & ~tandy_mode ? 1'b0 : border_video_ff ),

        .vram_din   ( 8'h0  ),
        .vram_dout  (       ),
        .vram_addr  ( 8'h0  ),
        .vram_we    ( 1'b0  ),
        .vram_ctrl  ( 3'b0  ),
        .enable     ( video_pause_core ),

        // output image
        .HB_out     ( pre2x_LHBL      ),
        .VB_out     ( pre2x_LVBL      ),
        .rgb_out    ( {VGA_R, VGA_G, VGA_B } )
    );


endmodule
