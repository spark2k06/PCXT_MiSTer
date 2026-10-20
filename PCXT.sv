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

`ifndef SYSTEM_VARIANT_TANDY
`define SYSTEM_VARIANT_TANDY 0
`endif
`ifndef ROM_VARIANT_TANDY
`define ROM_VARIANT_TANDY `SYSTEM_VARIANT_TANDY
`endif
`ifndef ROM_IS_TANDY
`define ROM_IS_TANDY `ROM_VARIANT_TANDY
`endif
`ifndef ENABLE_MIDI
`define ENABLE_MIDI 1
`endif
`ifndef CONF_STR_SYSTEM
`define CONF_STR_SYSTEM (`SYSTEM_VARIANT_TANDY ? (`ENABLE_MIDI ? "Tandy1000;UART115200:115200,MIDI;" : "Tandy1000;UART115200:115200;") : (`ENABLE_MIDI ? "PCXT;UART115200:115200,MIDI;" : "PCXT;UART115200:115200;"))
`endif
`ifndef ENABLE_TANDY_VIDEO
`define ENABLE_TANDY_VIDEO 0
`endif
`ifndef ENABLE_TANDY_AUDIO
`define ENABLE_TANDY_AUDIO 0
`endif
`ifndef ENABLE_TANDY_KBD
`define ENABLE_TANDY_KBD 0
`endif
`ifndef ENABLE_A000_UMB
`define ENABLE_A000_UMB 0
`endif
`ifndef ENABLE_CGA
`define ENABLE_CGA 1
`endif
`ifndef ENABLE_HGC
`define ENABLE_HGC 0
`endif
`ifndef ENABLE_OPL2
`define ENABLE_OPL2 0
`endif
`ifndef ENABLE_CMS
`define ENABLE_CMS 0
`endif
`ifndef ENABLE_EMS
`define ENABLE_EMS 0
`endif

module emu
    (
`include "sys/emu_ports.vh"
    );

    ///////// Default values for ports not used in this core /////////

    assign ADC_BUS  = 'Z;
    //assign USER_OUT = '1;
    //assign {UART_RTS, UART_TXD, UART_DTR} = 0;
    assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
    //assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
    assign VGA_SCALER = 0;
    assign VGA_DISABLE = 0;
    assign HDMI_FREEZE = 0;
    assign HDMI_BLACKOUT = 0;
    assign HDMI_BOB_DEINT = 0;

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
    // status[64]: CRTC Frame Stacking (Native / Rebuilt)

	`include "build_id.v"

    localparam CONF_STR_HGC = ((`ENABLE_HGC && `ENABLE_CGA) ? "P1oC,PCXT CGA Graphics,Yes,No;P1oD,PCXT Hercules Graphics,Yes,No;P1O4,PCXT 1st Video,CGA,Hercules;P1-;" : "");
    localparam CONF_STR_ROM = (`ROM_IS_TANDY ? "P1FC1,ROM,Tandy BIOS:;P1-;" : "P1FC0,ROM,PCXT BIOS:;");
    localparam CONF_STR_CMS = (`ENABLE_CMS ? "P2OA,C/MS Audio,Enabled,Disabled;" : "");
    localparam CONF_STR_OPL2 = (`ENABLE_OPL2 ? "P2oAB,OPL2,Adlib 388h,SB FM 388h/228h, Disabled;" : "");
    localparam CONF_STR_TANDY_AUDIO = (`ENABLE_TANDY_AUDIO ? "P2o23,Tandy Volume,1,2,3,4;" : "");
    // P2o23 occupies status[35:34].  It is shared with Tandy Volume in the
    // optional Tandy-audio build, so keep the CRT converter out of that
    // mutually exclusive configuration rather than aliasing two controls.
    localparam CONF_STR_CRT = (`ENABLE_TANDY_AUDIO ? "" : "P2o23,350-line CRT,Native,480i 15 kHz,240p 15 kHz;");
    localparam CONF_STR_EMS = (`ENABLE_EMS ? "P3OB,Lo-tech 2MB EMS,Enabled,Disabled;P3OCD,EMS Frame,C000,D000,E000;P3-;" : "");
    localparam CONF_STR_A000 = (`ENABLE_A000_UMB ? "P3o9,A000 UMB,Enabled,Disabled;P3-;" : "");
    localparam CONF_STR_MIDI = (`ENABLE_MIDI ? "P3O6,USER I/O,MIDI,COM2;P3-;h3P4,MT32-pi;h3P4-;h3P4OD,Use MT32-pi,Yes,No;h3P4-;h3P4o9,MT32-pi Mode,MT-32,General MIDI;h3P4O34,MT32-pi ROM,MT-32 v1,MT-32 v2,CM-32L,Reserved;h3P4oSU,MT32-pi SoundFont,#0,#1,#2,#3,#4,#5,#6,#7;h3P4-;h3P4r8,Reset Hanging Notes;h3P4-;" : "");
    // This line is shown at the top of the menu while the required PCXT BIOS
    // is absent, so the splash hold has an actionable explanation.
    localparam CONF_STR_HALT = "h4-,HALTED: no PCXT BIOS selected;";
    localparam CONF_STR_INFO = {
        "I,",
        "No PCXT BIOS selected\n",
        "Machine halted\n",
        "OSD: System & BIOS;"
    };

	localparam CONF_STR = {
		`CONF_STR_SYSTEM,
		CONF_STR_HALT,
		"S0,IMGIMAVFD,Floppy A:;",
		"S1,IMGIMAVFD,Floppy B:;",
		"OJK,Write Protect,None,A:,B:,A: & B:;",
		"-;",
		"S2,VHD,IDE 0-0;",
		"S3,VHD,IDE 0-1;",
		"OLM,2nd SD card,Disable,IDE 0-0,IDE 0-1;",
		"-;",
		"OHI,CPU Speed,4.77MHz,7.16MHz,9.54MHz,Max;",
		"-;",
		"P1,System & BIOS;",
		"P1-;",
		CONF_STR_HGC,
		"P1O7,Boot Splash Screen,Yes,No;",
		"P1oV,CPU Type,8088,8086;",
		"P1oL,Fake 286 FLAGS,Off,On;",
		"P1-;",
		CONF_STR_ROM,
		"P1FC2,ROM,EC00 BIOS:;",
		"P1-;",
		"P1OUV,BIOS Writable,None,EC00,Main,All;",
		"P1-;",	
		"P2,Audio & Video;",
		"P2-;",
		CONF_STR_CMS,
		CONF_STR_OPL2,
		"P2o01,Speaker Volume,1,2,3,4;",
		CONF_STR_TANDY_AUDIO,
		"P2o45,Audio Boost,No,2x,4x;",
		"P2o67,Stereo Mix,none,25%,50%,100%;",
		"P2-;",
		"d6P2oEH,CRT H offset,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15;",
		"d6P2oIK,CRT V offset,0,1,2,3,4,5,6,7;",        
		"P2oMO,VSync Width,Auto,1,2,3,4,5,6,7;",
		"P2oPR,HSync Width,Auto,1,2,3,4,5,6,7;",
        "P2-;",
		"P2O12,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
		"P2O89,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
		"P2OT,Border,No,Yes;",
		"h5P2O[65],Border CRT offsets,No,Yes;",
		"P2O[64],CRTC Frame Stacking,Native,Rebuilt;",
		"P2o8,Composite video,Off,On;",
		"P2OEG,Display,Full Color,Green,Amber,B&W,Red,Blue,Fuchsia,Purple;",
		CONF_STR_CRT,
		"P2-;",
		"P3,Hardware;",
		"P3-;",
		CONF_STR_EMS,
		CONF_STR_A000,
		"P3ONO,Joystick 1, Analog, Digital, Disabled;",
		"P3OPQ,Joystick 2, Analog, Digital, Disabled;",
		"P3OR,Sync Joy to CPU Speed,No,Yes;",
		"P3OS,Swap Joysticks,No,Yes;",
		"P3-;",
		CONF_STR_MIDI,
		"-;",
		"R0,Reset & apply settings;",
		"J,Fire 1,Fire 2;",
		CONF_STR_INFO,
		"V,v",`BUILD_DATE
	};

    wire forced_scandoubler;
    wire [1:0] buttons;
    wire [127:0] status;
    // Status bit 63 is the pending CPU selection. The value presented to the
    // BIU is latched only during reset; changing the menu alone cannot change
    // queue depth or bus width while an instruction is in flight.
    wire        cpu_type_8086_osd = status[63];
    // Status bit 53 makes PUSHF report zero in reserved FLAGS bits 12:15,
    // matching a real-mode 80286 for legacy CPU probes.  Unlike the CPU type
    // this is applied live: it only gates a mux on the PUSHF operand path, so
    // the worst a mid-run change can do is decide the PUSHF of that instant.
    wire        fake_286_flags_osd = status[53];
    wire        is8086_applied;
    wire [7:0]  xtctl;
    wire [7:0]  uart_mode;

    //Keyboard Ps2
    wire        ps2_kbd_clk_out;
    wire        ps2_kbd_data_out;
    wire        ps2_kbd_clk_in;
    wire        ps2_kbd_data_in;
    // Decoded key stream, used to catch F12 while the machine is in reset.
    wire [10:0] ps2_key;
    wire [7:0]  info;
    wire        info_req;

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
    wire        ioctl_wait;

    wire [21:0] gamma_bus;

    wire [13:0] joy0, joy1;
    wire [15:0] joya0, joya1;
    wire [4:0]  joy_opts = status[27:23];

    wire composite = status[40] | xtctl[0];
    wire [1:0] scale = status[2:1];
    wire [2:0] screen_mode = status[16:14];
    wire [1:0] ar = status[9:8];
    wire border = status[29] | xtctl[1];
    wire a000h = `ENABLE_A000_UMB ? (~status[41] & ~xtctl[6]) : 1'b0;
    wire [2:0] vsync_width_osd = status[56:54];  // 0=Auto (use register), 1-7=override
    wire [2:0] hsync_width_osd = status[59:57];  // 0=Auto, 1-7=fixed width (Nx16 pixel clocks)
    wire [1:0] crt480i_mode = status[35:34];     // 0=native, 1=480i, 2=240p
    wire       crt480i_osd  = |crt480i_mode;
    wire       crt480i_prog = crt480i_mode[1];

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] scale_video_meta = 2'b00;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] scale_video_ff = 2'b00;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] screen_mode_video_meta = 3'b000;
    reg         hgc_mode_video_ff;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] screen_mode_video_ff = 3'b000;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg border_video_meta = 1'b0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg border_video_ff = 1'b0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] scale_cga_meta = 2'b00;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] scale_cga_ff = 2'b00;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] screen_mode_cga_meta = 3'b000;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [2:0] screen_mode_cga_ff = 3'b000;
    reg         cga_hw;
    wire        video_scandoubler_en = (scale_video_ff > 0) || forced_scandoubler;
    wire        cga_scandouble_en = (scale_cga_ff > 0) || forced_scandoubler;
    reg         hercules_hw;
    // bit0=status[5]; bit3 exposes the MT32-pi options; bit4 exposes the
    // halted/missing-PCXT-BIOS status line at the top of the menu; bit5 is set
    // while Border is on (it shows Border CRT offsets); bit6 is set while the OSD
    // CRT H/V offsets act on the picture: always, except with Border on and
    // Border CRT offsets off, where the window ignores them.
    wire        crt_offsets_act = ~border | status[65];
    wire [15:0] status_menumask = {9'd0, crt_offsets_act, border, bios_missing_pcxt,
                                   ((`ENABLE_MIDI != 0) && mt32_available),
                                   2'b00, status[5]};

    wire VGA_VBlank_border;
    wire VGA_HSYNC_REF, VGA_VSYNC_REF;
    wire std_hsyncwidth;
    wire pause_core;
    wire swap_video;
    wire swap_video_requested = `ENABLE_HGC ? (`ENABLE_CGA ? swap_video : (`ENABLE_TANDY_VIDEO ? 1'b0 : 1'b1)) : 1'b0;

    always @(posedge clk_57_272)
    begin
        scale_video_meta        <= scale;
        scale_video_ff          <= scale_video_meta;
        screen_mode_video_meta  <= screen_mode;
        screen_mode_video_ff    <= screen_mode_video_meta;
        border_video_meta       <= border;
        border_video_ff         <= border_video_meta;
        cga_hw                  <= `ENABLE_CGA ? (~status[44] | tandy_video_mode) : 1'b0;
        hercules_hw             <= `ENABLE_HGC ? (`ENABLE_CGA ? ~status[45] : 1'b1) : 1'b0;
    end

    // Keep static CGA configuration local to the exact CGA clock domain.
    always @(posedge clk_28_636)
    begin
        scale_cga_meta          <= scale;
        scale_cga_ff            <= scale_cga_meta;
        screen_mode_cga_meta    <= screen_mode;
        screen_mode_cga_ff      <= screen_mode_cga_meta;
    end

    always @(posedge clk_chipset)
        hgc_mode_video_ff       <= `ENABLE_HGC ? hgc_mode : 1'b0;

    hps_io #(.CONF_STR(CONF_STR), .PS2DIV(2000), .PS2WE(1), .WIDE(1), .F12KEYMOD(1)) hps_io
	(
		.clk_sys(clk_chipset),
		.HPS_BUS(HPS_BUS),
		.EXT_BUS(EXT_BUS),
		.gamma_bus(gamma_bus),

		.forced_scandoubler(forced_scandoubler),

		.buttons(buttons),
		.status(status),
		.status_menumask(status_menumask),
		.info_req(info_req),
		.info(info),

		.uart_mode(uart_mode),

		.ps2_key(ps2_key),
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
    wire clk_57_272;
    wire clk_114_544;
    wire clk_video_out_ps;
    wire clk_sdram_pin;
    reg clk_14_318 = 1'b0;
    wire clk_cpu;
    logic cpu_ce_posedge;
    logic cpu_ce_negedge;
    logic peripheral_ce;
    wire clk_chipset;

    localparam [27:0] cur_rate = 28'd50000000;

    pll pll 
	(
		.refclk(CLK_50M),
		.rst(0),
		.outclk_0(clk_100),
        .outclk_1(clk_chipset),
		.locked(pll_locked)
	);

    wire pll_system_locked;

    // Keep the CGA/video PLL phase-related to the chipset clock.  The XT
    // CPU/PIT and the real CGA card share the 14.31818 MHz source; using the
    // board oscillator independently here leaves the two PLL lock phases
    // unrelated and makes cycle-locked effects such as 8088 MPH depend on
    // power-up phase.  The video frequencies themselves are unchanged.
    pll_system pll_system_inst (
        .refclk(clk_chipset),
        .rst(0),
        .outclk_0(clk_28_636),
        .outclk_1(clk_57_272),
        .outclk_2(clk_114_544),
        .outclk_3(clk_video_out_ps),
        .outclk_4(clk_sdram_pin),
        .locked(pll_system_locked)
    );

    wire reset_wire = RESET | status[0] | buttons[1] | !pll_locked | !pll_system_locked  | splashscreen | splash_reset_hold | splash_pending;
    wire video_retime_reset = RESET | status[0] | buttons[1] | !pll_locked | !pll_system_locked | splash_pending;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] video_retime_reset_sync = 2'b11;
    wire video_retime_reset_local = video_retime_reset_sync[1];

    // The 350-line HGC framebuffer has its own video clock domain.  Keep the
    // reset assertion immediate, but release it synchronously there so the
    // framebuffer state machines do not time the global reset as data.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] video_retime_hgc_sync = 2'b11;
    wire video_retime_reset_hgc = video_retime_hgc_sync[1];

    // The output retime registers assert reset immediately, but release it
    // only on their own phase-shifted video clock.
    always_ff @(posedge clk_video_out_ps or posedge video_retime_reset) begin
        if (video_retime_reset)
            video_retime_reset_sync <= 2'b11;
        else
            video_retime_reset_sync <= {video_retime_reset_sync[0], 1'b0};
    end

    always_ff @(posedge CLK_VIDEO_HGC or posedge video_retime_reset) begin
        if (video_retime_reset)
            video_retime_hgc_sync <= 2'b11;
        else
            video_retime_hgc_sync <= {video_retime_hgc_sync[0], 1'b0};
    end
    wire reset_sdram_wire = RESET | !pll_locked | !pll_system_locked;

    //////////////////////////////////////////////////////////////////

    // TODO: messy, use a single clock domain at least
    always @(posedge clk_28_636)
    begin
        HBlank_del <= {HBlank_del[23], HBlank_del[22], HBlank_del[21], HBlank_del[20], HBlank_del[19],
                       HBlank_del[18], HBlank_del[17], HBlank_del[16], HBlank_del[15], HBlank_del[14],
                       HBlank_del[13], HBlank_del[12], HBlank_del[11], HBlank_del[10], HBlank_del[9],
                       HBlank_del[8], HBlank_del[7], HBlank_del[6], HBlank_del[5], HBlank_del[4],
                       HBlank_del[3], HBlank_del[2], HBlank_del[1], HBlank_del[0], HBlank};
        clk_14_318 <= ~clk_14_318;  // 14.318Mhz
        ce_pixel_cga <= clk_14_318;	//if outside always block appears an overscan column in CGA mode
    end

    //////////////////////////////////////////////////////////////////

    logic  biu_done;
    logic  [7:0] clock_cycle_counter_division_ratio;
    logic  [7:0] clock_cycle_counter_decrement_value;
    logic        shift_read_timing;
    logic  [1:0] ram_read_wait_cycle;
    logic  [1:0] ram_write_wait_cycle;
    logic        cycle_accrate;
    logic  [1:0] clk_select;
    wire   [1:0] clk_select_next = ((xtctl[3:2] == 2'b00) && ~xtctl[7]) ? status[18:17] :
                                   (xtctl[7] ? 2'b11 : xtctl[3:2] - 2'b01);

    always @(posedge clk_chipset, posedge reset)
    begin
        if (reset)
            clk_select <= 2'b00;
        else if (biu_done)
            clk_select <= clk_select_next;
    end

    XT_CE_Generator u_XT_CE_Generator
    (
        .clock                              (clk_chipset),
        .reset                              (reset),
        .clk_select_load                    (biu_done),
        .clk_select                         (clk_select_next),
        .cpu_clk_pin                        (clk_cpu),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .peripheral_ce                      (peripheral_ce),
        .cycle_accrate                      (cycle_accrate),
        .clock_cycle_counter_division_ratio (clock_cycle_counter_division_ratio),
        .clock_cycle_counter_decrement_value(clock_cycle_counter_decrement_value),
        .shift_read_timing                  (shift_read_timing),
        .ram_read_wait_cycle                (ram_read_wait_cycle),
        .ram_write_wait_cycle               (ram_write_wait_cycle)
    );
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

    cpu_type_latch cpu_type_apply_latch (
        .clock                 (clk_chipset),
        .reset_active          (reset),
        .selected_8086         (cpu_type_8086_osd),
        .is8086                (is8086_applied)
    );

    // Fake 286 FLAGS is live, so it now crosses from the chipset domain that
    // hps_io drives into the core clock the EU mux is evaluated on. While it
    // was reset-latched the value only ever moved with the CPU held in reset
    // and no synchronizer was needed; a running change needs one.
    (* ASYNC_REG = "TRUE" *) logic [1:0] fake_286_flags_meta = 2'b00;
    wire fake_286_flags_applied = fake_286_flags_meta[1];

    always_ff @(posedge clk_100)
        fake_286_flags_meta <= {fake_286_flags_meta[0], fake_286_flags_osd};

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

    localparam tandy_video_mode = `ENABLE_TANDY_VIDEO;
    reg hgc_mode = 0;

    // hgc_mode is sampled while reset is active. Keeping the data-dependent
    // load synchronous avoids synthesis turning reset into a latch clock.
    always @(negedge clk_chipset)
        if (reset)
            hgc_mode <= `ENABLE_HGC ? (`ENABLE_CGA ? status[4] : 1'b1) : 1'b0;

    always @(negedge clk_chipset, posedge reset)
    begin
        if (reset)
        begin
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
    ///////////////////////   MEMORY   ////////////////////////////////
    //
    // System memory and the ROMs live in SDRAM behind one arbiter.
    // The chipset's memory port and the ROM loader are its clients;
    // the controller drives the chip. In F1 the controller runs on its own
    // clock: the chipset stays at 50 MHz and each
    // client crosses with an sdram_xbridge.
    //
    //   CHIPSET (cpu_mem_port) -> sdram_xbridge -+-> sdram_arbiter -> sdram_ctrl -> SDRAM
    //   rom_loader              -> sdram_xbridge -+

    wire clk_sdram = clk_114_544;

    // The chip's clock is forwarded through a DDIO output register, so that it
    // leaves the FPGA on the same kind of path as the commands and data and
    // its delay tracks theirs across process, voltage and temperature. A
    // global clock taken straight to the pin arrives ~5 ns late in the slow
    // corner and ~2.6 ns less in the fast one, which leaves no read window.
    // It is its own PLL output (calibrable phase, half a period after the
    // controller clock).
    wire sdram_clk_src = clk_sdram_pin;

    altddio_out
    #(
        .extend_oe_disable  ("OFF"),
        .intended_device_family("Cyclone V"),
        .invert_output      ("OFF"),
        .lpm_hint           ("UNUSED"),
        .lpm_type           ("altddio_out"),
        .oe_reg             ("UNREGISTERED"),
        .power_up_high      ("OFF"),
        .width              (1)
    )
    sdram_clk_ddr
    (
        .datain_h           (1'b1),
        .datain_l           (1'b0),
        .outclock           (sdram_clk_src),
        .dataout            (SDRAM_CLK),
        .aclr               (1'b0),
        .aset               (1'b0),
        .oe                 (1'b1),
        .outclocken         (1'b1),
        .sclr               (1'b0),
        .sset               (1'b0)
    );

    // Controller-side reset: asserted with reset_sdram, released on clk_sdram.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] sd_reset_sync = 2'b11;
    always_ff @(posedge clk_sdram or posedge reset_sdram) begin
        if (reset_sdram)
            sd_reset_sync <= 2'b11;
        else
            sd_reset_sync <= {sd_reset_sync[0], 1'b0};
    end
    wire sd_reset = sd_reset_sync[1];

    // The chip has finished its power-up sequence, seen from the chipset.
    wire sd_init_done;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] sd_init_sync = 2'b00;
    always_ff @(posedge clk_chipset)
        sd_init_sync <= {sd_init_sync[0], sd_init_done};
    wire initilized_sdram = sd_init_sync[1];

    // BIOS Writable: [1] F000 (main), [0] EC00.
    reg [1:0] bios_protect_flag = 2'b11;
    always @(posedge clk_chipset)
        bios_protect_flag <= ~status[31:30];

    //
    // ROM loader: HPS downloads straight into the SDRAM ROM bank
    //
    wire        ldr_start;
    wire        ldr_busy;
    wire        ldr_done;
    wire        ldr_flush;
    wire        ldr_hold_request;
    wire [23:0] ldr_addr;
    wire [15:0] ldr_wdata;
    wire        pcxt_bios_write_complete;
    wire        ec00_loaded;

    rom_loader #(.ROM_TANDY(`ROM_IS_TANDY)) u_rom_loader
    (
        .clock              (clk_chipset),
        .reset              (reset_sdram),
        .sdram_ready        (initilized_sdram),
        .ioctl_download     (ioctl_download),
        .ioctl_index        (ioctl_index),
        .ioctl_wr           (ioctl_wr),
        .ioctl_addr         (ioctl_addr),
        .ioctl_data         (ioctl_data),
        .ioctl_wait         (ioctl_wait),
        .hold_request       (ldr_hold_request),
        .hold_granted       ((~processor_ready) & address_direction),
        .l_start            (ldr_start),
        .l_addr             (ldr_addr),
        .l_wdata            (ldr_wdata),
        .l_busy             (ldr_busy),
        .l_done             (ldr_done),
        .write_any          (ldr_flush),
        .write_main         (pcxt_bios_write_complete),
        .ec00_loaded        (ec00_loaded)
    );

    //
    // Clock-domain bridges
    //
    wire        mem_start;
    wire        mem_we;
    wire [23:0] mem_addr;
    wire [1:0]  mem_len;
    wire [63:0] mem_wdata;
    wire [7:0]  mem_wbe;
    wire        mem_busy;
    wire        mem_done;
    wire [63:0] mem_rdata;

    wire        sd_cpu_req, sd_cpu_we, sd_cpu_ack, sd_cpu_rvalid, sd_cpu_rlast;
    wire [23:0] sd_cpu_addr;
    wire [1:0]  sd_cpu_len;
    wire [63:0] sd_cpu_wdata;
    wire [7:0]  sd_cpu_wbe;
    wire        sd_ldr_req, sd_ldr_we, sd_ldr_ack, sd_ldr_rvalid, sd_ldr_rlast;
    wire [23:0] sd_ldr_addr;
    wire [1:0]  sd_ldr_len;
    wire [63:0] sd_ldr_wdata;
    wire [7:0]  sd_ldr_wbe;
    wire [15:0] sd_rdata;

    sdram_xbridge #(.SYNC_STAGES(2)) u_cpu_bridge
    (
        .clk_a      (clk_chipset),
        .reset_a    (reset_sdram),
        .a_start    (mem_start),
        .a_we       (mem_we),
        .a_addr     (mem_addr),
        .a_len      (mem_len),
        .a_wdata    (mem_wdata),
        .a_wbe      (mem_wbe),
        .a_busy     (mem_busy),
        .a_done     (mem_done),
        .a_rdata    (mem_rdata),
        .clk_s      (clk_sdram),
        .reset_s    (sd_reset),
        .s_req      (sd_cpu_req),
        .s_we       (sd_cpu_we),
        .s_addr     (sd_cpu_addr),
        .s_len      (sd_cpu_len),
        .s_wdata    (sd_cpu_wdata),
        .s_wbe      (sd_cpu_wbe),
        .s_ack      (sd_cpu_ack),
        .s_rvalid   (sd_cpu_rvalid),
        .s_rdata    (sd_rdata),
        .s_rlast    (sd_cpu_rlast)
    );

    sdram_xbridge #(.SYNC_STAGES(2)) u_ldr_bridge
    (
        .clk_a      (clk_chipset),
        .reset_a    (reset_sdram),
        .a_start    (ldr_start),
        .a_we       (1'b1),
        .a_addr     (ldr_addr),
        .a_len      (2'd0),
        .a_wdata    ({48'd0, ldr_wdata}),
        .a_wbe      (8'h03),
        .a_busy     (ldr_busy),
        .a_done     (ldr_done),
        .a_rdata    (),
        .clk_s      (clk_sdram),
        .reset_s    (sd_reset),
        .s_req      (sd_ldr_req),
        .s_we       (sd_ldr_we),
        .s_addr     (sd_ldr_addr),
        .s_len      (sd_ldr_len),
        .s_wdata    (sd_ldr_wdata),
        .s_wbe      (sd_ldr_wbe),
        .s_ack      (sd_ldr_ack),
        .s_rvalid   (sd_ldr_rvalid),
        .s_rdata    (sd_rdata),
        .s_rlast    (sd_ldr_rlast)
    );

    //
    // Video memory (F2): CGA and HGC read their VRAM from SDRAM through vram_fetch
    // engines. Everything here is in clk_sdram;
    // the CGA (28.636 MHz) and HGC (57.27 MHz) sequencers come from the same PLL
    // and are sampled by the adapters.
    //
    //   LDR port: rom_loader (through its bridge) or ram_clear, which writes zeros
    //             over the video regions once the chip is initialised
    //   VID port: u_cga_fetch and u_hgc_fetch through vid_mux
    //   snoop:    every write the arbiter captures (CPU or LDR), registered once
    //
    localparam logic [23:0] CGA_WORD_BASE = sdram_pkg::PHYS_CGA[24:1];
    localparam logic [23:0] HGC_WORD_BASE = sdram_pkg::PHYS_HGC[24:1];

    wire        clr_busy, clr_req, clr_ack;
    wire [23:0] clr_addr;
    wire [1:0]  clr_len;
    wire [63:0] clr_wdata;
    wire [7:0]  clr_wbe;

    ram_clear #(
        .NREG   (2),
        .BASES  ({HGC_WORD_BASE, CGA_WORD_BASE}),
        .WORDS  ({24'd32768, 24'd16384})            // 64 KiB and 32 KiB
    ) u_ram_clear
    (
        .clk        (clk_sdram),
        .reset      (sd_reset),
        .init_done  (sd_init_done),
        .clear      (1'b0),
        .busy       (clr_busy),
        .req        (clr_req),
        .addr       (clr_addr),
        .len        (clr_len),
        .wdata      (clr_wdata),
        .wbe        (clr_wbe),
        .ack        (clr_ack)
    );

    wire        arb_ldr_req   = clr_busy ? clr_req   : sd_ldr_req;
    wire        arb_ldr_we    = clr_busy ? 1'b1      : sd_ldr_we;
    wire [23:0] arb_ldr_addr  = clr_busy ? clr_addr  : sd_ldr_addr;
    wire [1:0]  arb_ldr_len   = clr_busy ? clr_len   : sd_ldr_len;
    wire [63:0] arb_ldr_wdata = clr_busy ? clr_wdata : sd_ldr_wdata;
    wire [7:0]  arb_ldr_wbe   = clr_busy ? clr_wbe   : sd_ldr_wbe;
    wire        arb_ldr_ack;
    assign sd_ldr_ack = arb_ldr_ack & ~clr_busy;
    assign clr_ack    = arb_ldr_ack &  clr_busy;

    // Snoop: writes as the arbiter captures them. The fields of both ports are
    // registered as they are (only the two acknowledges are logic), so that the
    // path from the arbiter's grant logic does not run through the engines; the
    // choice between the two ports is made after the registers.
    logic        sn_c_v, sn_l_v;
    logic [23:0] sn_c_addr, sn_l_addr;
    logic [1:0]  sn_c_len,  sn_l_len;
    logic [63:0] sn_c_wdata, sn_l_wdata;
    logic [7:0]  sn_c_wbe,  sn_l_wbe;
    always_ff @(posedge clk_sdram) begin
        sn_c_v     <= sd_cpu_ack & sd_cpu_we;
        sn_l_v     <= arb_ldr_ack;
        sn_c_addr  <= sd_cpu_addr;
        sn_c_len   <= sd_cpu_len;
        sn_c_wdata <= sd_cpu_wdata;
        sn_c_wbe   <= sd_cpu_wbe;
        sn_l_addr  <= arb_ldr_addr;
        sn_l_len   <= arb_ldr_len;
        sn_l_wdata <= arb_ldr_wdata;
        sn_l_wbe   <= arb_ldr_wbe;
    end
    wire        sn_valid = sn_c_v | sn_l_v;
    wire [23:0] sn_addr  = sn_l_v ? sn_l_addr  : sn_c_addr;
    wire [1:0]  sn_len   = sn_l_v ? sn_l_len   : sn_c_len;
    wire [63:0] sn_wdata = sn_l_v ? sn_l_wdata : sn_c_wdata;
    wire [7:0]  sn_wbe   = sn_l_v ? sn_l_wbe   : sn_c_wbe;

    // The engines wait for the chip: until it is initialised nothing can be read
    wire vid_reset = sd_reset | ~sd_init_done;

    // CRTC views and bytes (to and from the chipset)
    wire [4:0]  fx_cga_phase, fx_hgc_phase;
    wire        fx_cga_hres, fx_hgc_grph, fx_hgc_page;
    wire [13:0] fx_cga_cur_word, fx_cga_next_word, fx_hgc_cur_word, fx_hgc_next_word;
    wire [7:0]  fx_cga_vram_d, fx_hgc_vram_d;

    // Engines
    wire        cga_req_v, cga_req_r, cga_rsp_p, cga_rsp_v, cga_rsp_pop;
    wire [23:0] cga_req_a, cga_rsp_a;
    wire [1:0]  cga_req_l;
    wire [15:0] cga_req_d;
    wire [63:0] cga_rsp_d;
    wire        cga_vreq, cga_vack, cga_vrv, cga_vrl;
    wire [23:0] cga_vaddr;
    wire [1:0]  cga_vlen;
    wire [15:0] cga_vdl;
    wire [15:0] cga_underrun, cga_mismatch, cga_late, cga_dropped;

    wire        hgc_req_v, hgc_req_r, hgc_rsp_p, hgc_rsp_v, hgc_rsp_pop;
    wire [23:0] hgc_req_a, hgc_rsp_a;
    wire [1:0]  hgc_req_l;
    wire [15:0] hgc_req_d;
    wire [63:0] hgc_rsp_d;
    wire        hgc_vreq, hgc_vack, hgc_vrv, hgc_vrl;
    wire [23:0] hgc_vaddr;
    wire [1:0]  hgc_vlen;
    wire [15:0] hgc_vdl;
    wire [15:0] hgc_underrun, hgc_mismatch, hgc_late, hgc_dropped;

    wire        vid_req, vid_ack, vid_rvalid, vid_rlast;
    wire [23:0] vid_addr;
    wire [1:0]  vid_len;
    wire [15:0] vid_deadline;

    vram_fetch #(.DEPTH(3), .MAX_WORDS(1)) u_cga_fetch
    (
        .clk(clk_sdram), .reset(vid_reset),
        .req_valid(cga_req_v), .req_addr(cga_req_a), .req_len(cga_req_l),
        .req_deadline(cga_req_d), .req_ready(cga_req_r),
        .rsp_pending(cga_rsp_p), .rsp_valid(cga_rsp_v), .rsp_data(cga_rsp_d),
        .rsp_addr(cga_rsp_a), .rsp_len(),
        .rsp_pop(cga_rsp_pop), .flush(1'b0),
        .snoop_valid(sn_valid), .snoop_addr(sn_addr), .snoop_len(sn_len),
        .snoop_wdata(sn_wdata), .snoop_wbe(sn_wbe),
        .vid_req(cga_vreq), .vid_addr(cga_vaddr), .vid_len(cga_vlen), .vid_deadline(cga_vdl),
        .vid_ack(cga_vack), .vid_rvalid(cga_vrv), .vid_rlast(cga_vrl), .vid_rdata(sd_rdata),
        .underrun_count(cga_underrun), .occupancy()
    );

    cga_vram_if #(.BASE(CGA_WORD_BASE)) u_cga_vif
    (
        .clk(clk_sdram), .reset(vid_reset),
        .seq_phase(fx_cga_phase), .hres(fx_cga_hres),
        .cur_word(fx_cga_cur_word), .next_word(fx_cga_next_word),
        .vram_d(fx_cga_vram_d),
        .req_valid(cga_req_v), .req_addr(cga_req_a), .req_len(cga_req_l),
        .req_deadline(cga_req_d), .req_ready(cga_req_r),
        .rsp_pending(cga_rsp_p), .rsp_valid(cga_rsp_v), .rsp_data(cga_rsp_d),
        .rsp_addr(cga_rsp_a), .rsp_pop(cga_rsp_pop),
        .mismatch_count(cga_mismatch), .late_count(cga_late), .dropped_count(cga_dropped)
    );

    vram_fetch #(.DEPTH(3), .MAX_WORDS(1)) u_hgc_fetch
    (
        .clk(clk_sdram), .reset(vid_reset),
        .req_valid(hgc_req_v), .req_addr(hgc_req_a), .req_len(hgc_req_l),
        .req_deadline(hgc_req_d), .req_ready(hgc_req_r),
        .rsp_pending(hgc_rsp_p), .rsp_valid(hgc_rsp_v), .rsp_data(hgc_rsp_d),
        .rsp_addr(hgc_rsp_a), .rsp_len(),
        .rsp_pop(hgc_rsp_pop), .flush(1'b0),
        .snoop_valid(sn_valid), .snoop_addr(sn_addr), .snoop_len(sn_len),
        .snoop_wdata(sn_wdata), .snoop_wbe(sn_wbe),
        .vid_req(hgc_vreq), .vid_addr(hgc_vaddr), .vid_len(hgc_vlen), .vid_deadline(hgc_vdl),
        .vid_ack(hgc_vack), .vid_rvalid(hgc_vrv), .vid_rlast(hgc_vrl), .vid_rdata(sd_rdata),
        .underrun_count(hgc_underrun), .occupancy()
    );

    hgc_vram_if #(.BASE(HGC_WORD_BASE)) u_hgc_vif
    (
        .clk(clk_sdram), .reset(vid_reset),
        .seq_phase(fx_hgc_phase), .grph(fx_hgc_grph), .page(fx_hgc_page),
        .cur_word(fx_hgc_cur_word), .next_word(fx_hgc_next_word),
        .vram_d(fx_hgc_vram_d),
        .req_valid(hgc_req_v), .req_addr(hgc_req_a), .req_len(hgc_req_l),
        .req_deadline(hgc_req_d), .req_ready(hgc_req_r),
        .rsp_pending(hgc_rsp_p), .rsp_valid(hgc_rsp_v), .rsp_data(hgc_rsp_d),
        .rsp_addr(hgc_rsp_a), .rsp_pop(hgc_rsp_pop),
        .mismatch_count(hgc_mismatch), .late_count(hgc_late), .dropped_count(hgc_dropped)
    );

    vid_mux #(.N(2)) u_vid_mux
    (
        .clk(clk_sdram), .reset(vid_reset),
        .c_req({hgc_vreq, cga_vreq}), .c_addr({hgc_vaddr, cga_vaddr}),
        .c_len({hgc_vlen, cga_vlen}), .c_deadline({hgc_vdl, cga_vdl}),
        .c_ack({hgc_vack, cga_vack}), .c_rvalid({hgc_vrv, cga_vrv}), .c_rlast({hgc_vrl, cga_vrl}),
        .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
        .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast)
    );

    //
    // Arbiter and controller
    //
    wire        op_valid, op_ref, op_we, op_issue;
    wire [23:0] op_addr;
    wire [1:0]  op_len;
    wire [63:0] op_wdata;
    wire [7:0]  op_wbe;
    wire [1:0]  op_tag;
    wire [3:0]  sd_bank_idle;
    wire        sd_rd_valid, sd_rd_last;
    wire [15:0] sd_rd_data;
    wire [1:0]  sd_rd_tag;

    sdram_arbiter u_sdram_arbiter
    (
        .clk            (clk_sdram),
        .reset          (sd_reset),
        .init_done      (sd_init_done),
        // VID: the video fetch engines, joined by vid_mux
        .vid_req        (vid_req),
        .vid_addr       (vid_addr),
        .vid_len        (vid_len),
        .vid_deadline   (vid_deadline),
        .vid_ack        (vid_ack),
        .vid_rvalid     (vid_rvalid),
        .vid_rlast      (vid_rlast),
        .cpu_req        (sd_cpu_req),
        .cpu_we         (sd_cpu_we),
        .cpu_addr       (sd_cpu_addr),
        .cpu_len        (sd_cpu_len),
        .cpu_wdata      (sd_cpu_wdata),
        .cpu_wbe        (sd_cpu_wbe),
        .cpu_ack        (sd_cpu_ack),
        .cpu_rvalid     (sd_cpu_rvalid),
        .cpu_rlast      (sd_cpu_rlast),
        .ldr_req        (arb_ldr_req),
        .ldr_we         (arb_ldr_we),
        .ldr_addr       (arb_ldr_addr),
        .ldr_len        (arb_ldr_len),
        .ldr_wdata      (arb_ldr_wdata),
        .ldr_wbe        (arb_ldr_wbe),
        .ldr_high       (1'b0),
        .ldr_ack        (arb_ldr_ack),
        .ldr_rvalid     (sd_ldr_rvalid),
        .ldr_rlast      (sd_ldr_rlast),
        // AUX: reserved.
        .aux_req        (1'b0),
        .aux_addr       (24'd0),
        .aux_len        (2'd0),
        .aux_ack        (),
        .aux_rvalid     (),
        .aux_rlast      (),
        .rdata          (sd_rdata),
        .op_valid       (op_valid),
        .op_ref         (op_ref),
        .op_we          (op_we),
        .op_addr        (op_addr),
        .op_len         (op_len),
        .op_wdata       (op_wdata),
        .op_wbe         (op_wbe),
        .op_tag         (op_tag),
        .op_issue       (op_issue),
        .bank_idle      (sd_bank_idle),
        .rd_valid       (sd_rd_valid),
        .rd_data        (sd_rd_data),
        .rd_tag         (sd_rd_tag),
        .rd_last        (sd_rd_last),
        // Debug counters (XTCTL 8990h+, a later phase).
        .cpu_lat_max    (),
        .vid_lat_max    (),
        .vid_underruns  (),
        .ref_debt       ()
    );

    wire [15:0] sdram_dq_out;
    wire        sdram_dq_oe;
    wire [1:0]  sdram_dqm;

    sdram_ctrl u_sdram_ctrl
    (
        .clk            (clk_sdram),
        .reset          (sd_reset),
        .init_done      (sd_init_done),
        .op_valid       (op_valid),
        .op_ref         (op_ref),
        .op_we          (op_we),
        .op_addr        (op_addr),
        .op_len         (op_len),
        .op_wdata       (op_wdata),
        .op_wbe         (op_wbe),
        .op_tag         (op_tag),
        .op_issue       (op_issue),
        .bank_idle      (sd_bank_idle),
        .rd_valid       (sd_rd_valid),
        .rd_data        (sd_rd_data),
        .rd_tag         (sd_rd_tag),
        .rd_last        (sd_rd_last),
        .sdram_cke      (SDRAM_CKE),
        .sdram_cs_n     (SDRAM_nCS),
        .sdram_ras_n    (SDRAM_nRAS),
        .sdram_cas_n    (SDRAM_nCAS),
        .sdram_we_n     (SDRAM_nWE),
        .sdram_ba       (SDRAM_BA),
        .sdram_a        (SDRAM_A),
        .sdram_dqm      (sdram_dqm),
        .sdram_dq_out   (sdram_dq_out),
        .sdram_dq_oe    (sdram_dq_oe),
        .sdram_dq_in    (SDRAM_DQ)
    );

    assign SDRAM_DQ   = sdram_dq_oe ? sdram_dq_out : 16'hZZZZ;
    assign SDRAM_DQML = sdram_dqm[0];
    assign SDRAM_DQMH = sdram_dqm[1];

    // The ROM loader writes the selected image one word at a time. A slot is
    // recorded as present once a word of the download has reached the SDRAM;
    // starting a new download clears it, which re-arms the hold.
    wire pcxt_bios_download_active = ioctl_download && (ioctl_index[5:0] == 6'd0);
    wire pcxt_bios_loaded;

    rom_presence_latch pcxt_bios_presence (
        .clock              (clk_chipset),
        .reset              (reset_sdram),
        .sdram_initialized  (initilized_sdram),
        .download_active    (pcxt_bios_download_active),
        .write_complete     (pcxt_bios_write_complete),
        .loaded             (pcxt_bios_loaded)
    );

    wire bios_missing_pcxt = ~pcxt_bios_loaded;


    //////////////////////////////////////////////////////////////////

    //
    // Splash screen
    //
    reg splash_off = 1'b1;
    reg [24:0] splash_cnt = 0;
    reg [3:0] splash_cnt2 = 0;
    reg splash_timed = 1'b0;
    reg splash_pending = 1'b1;
    reg [23:0] splash_boot_cnt = 24'd0;
    reg splashscreen_sync1 = 0;
    reg splashscreen_sync2 = 0;
    reg splashscreen_sync_prev = 0;
    reg splash_reset_hold = 0;
    reg [17:0] splash_reset_cnt = 18'd0;
    localparam [17:0] SPLASH_RESET_HOLD = 18'd131072;
    reg phys_reset_hold = 0;
    reg [23:0] phys_reset_cnt = 24'd0;
    localparam [23:0] PHYS_RESET_HOLD = 24'd2863600;
    localparam [23:0] SPLASH_BOOT_WAIT = 24'd14318000;

    always @ (posedge clk_14_318)
    begin
        splash_off <= status[7];
        if (RESET || buttons[1])
        begin
            phys_reset_hold <= 1'b1;
            phys_reset_cnt <= 24'd0;
        end
        else if (phys_reset_hold)
        begin
            if (phys_reset_cnt == PHYS_RESET_HOLD)
                phys_reset_hold <= 1'b0;
            else
                phys_reset_cnt <= phys_reset_cnt + 24'd1;
        end

        if (splash_pending)
        begin
            if (~splash_off)
            begin
                splash_timed <= 1'b1;
                splash_cnt <= 0;
                splash_cnt2 <= 0;
                splash_pending <= 1'b0;
                splash_boot_cnt <= 24'd0;
            end
            else if (splash_boot_cnt == SPLASH_BOOT_WAIT)
            begin
                splash_pending <= 1'b0;
            end
            else
            begin
                splash_boot_cnt <= splash_boot_cnt + 24'd1;
            end
        end
        else if (splash_timed)
        begin
            if (splash_off)
            begin
                splash_timed <= 0;
            end
            else if (splash_paused)
            begin
                // F12 holds the picture and the machine reset until pressed
                // again. Turning the splash off in the OSD still dismisses it.
                splash_cnt <= splash_cnt;
            end
            else if(splash_cnt2 == 5) // 5 seconds delay
            begin
                splash_timed <= 0;
            end
            else if (splash_cnt == 14318000)
            begin // 1 second at 14.318Mhz
                splash_cnt2 <= splash_cnt2 + 1;
                splash_cnt <= 0;
            end
            else
                splash_cnt <= splash_cnt + 1;
        end

    end

    // The keyboard controller that normally decodes F12 is inside the
    // machine, and is held in reset while the splash is shown. Catch the key
    // in the framework stream instead.
    wire splash_paused;

    splash_f12_pause splash_pause (
        .clock         (clk_14_318),
        .splash_active (splash_timed),
        .ps2_key       (ps2_key),
        .paused        (splash_paused)
    );

    // Keep the power-on raster until the required BIOS exists. Reusing the
    // splash signal means the CPU reset, splash renderer and video timing all
    // agree on the held state.
    wire bios_hold;

    bios_hold_notice bios_notice (
        .clock             (clk_14_318),
        .splash_boot_phase (splash_pending | splash_timed),
        .bios_missing_pcxt (bios_missing_pcxt),
        .hold              (bios_hold),
        .info              (info),
        .info_req          (info_req)
    );

    wire splashscreen = splash_timed | bios_hold;
    // The splash is always a native CGA raster.  Keep the shared video path on
    // CGA until it has finished; the selected HGC/MDA path is restored after
    // the normal two-flop output-domain synchronization below.
    wire swap_video_eff = splashscreen ? 1'b0 : swap_video_requested;

    always @(posedge clk_chipset)
    begin
        splashscreen_sync1 <= splashscreen;
        splashscreen_sync2 <= splashscreen_sync1;
        splashscreen_sync_prev <= splashscreen_sync2;
        if (splashscreen_sync_prev && ~splashscreen_sync2)
        begin
            splash_reset_hold <= 1'b1;
            splash_reset_cnt  <= 18'd0;
        end
        else if (splash_reset_hold)
        begin
            if (splash_reset_cnt == SPLASH_RESET_HOLD)
                splash_reset_hold <= 1'b0;
            else
                splash_reset_cnt <= splash_reset_cnt + 18'd1;
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
    wire [15:0] data_bus_word;          // 8086 wide read
    wire [15:0] cpu_data_bus_word;       // 8086 wide write
    wire        word_read_possible;      // SDRAM can serve the latched address wide
    wire        word_read_request;
    wire        word_write_request;
    wire processor_ready;
    wire interrupt_to_cpu;
    wire address_latch_enable;
    wire address_direction;

    wire lock_n;
    wire [2:0]processor_status;

    wire [3:0]   dma_acknowledge_n;

    logic   [7:0]   port_b_out;
    logic   [7:0]   port_c_in;
    wire    [1:0]   fdd_present;
    reg     [7:0]   sw;

    wire    [5:0]   sw_base;
    wire    [1:0]   sw_floppy;

    assign  sw_base = `ENABLE_HGC ? (hgc_mode ? 6'b111101 : 6'b101101) : 6'b101101;
    assign  sw_floppy = fdd_present[1] ? 2'b01 : 2'b00;
    assign  sw = {sw_floppy, sw_base}; // DIP switches (CGA and floppy count)
    assign  port_c_in[3:0] = port_b_out[3] ? sw[7:4] : sw[3:0];


    wire video_output_sel = `ENABLE_HGC ? hgc_mode_video_ff : 1'b0;
    wire enable_hgc_sel = `ENABLE_HGC ? 1'b1 : 1'b0;
    wire [1:0] hgc_rgb_sel = `ENABLE_HGC ? 2'b10 : 2'b00;
    wire hercules_hw_sel = `ENABLE_HGC ? hercules_hw : 1'b0;
    wire ems_enabled_sel = `ENABLE_EMS ? ~status[11] : 1'b0;
    wire [1:0] ems_address_sel = `ENABLE_EMS ? status[13:12] : 2'b00;

    always @(posedge clk_chipset)
    begin
        if (address_latch_enable)
            cpu_address <= cpu_ad_out;
        else
            cpu_address <= cpu_address;
    end

    CHIPSET #(.clk_rate(cur_rate), .ROM_TANDY(`ROM_IS_TANDY)) u_CHIPSET
	(
		.clock                              (clk_chipset),
		.cpu_ce_posedge                     (cpu_ce_posedge),
		.cpu_ce_negedge                     (cpu_ce_negedge),
		.clk_sys                            (clk_chipset),
		.peripheral_ce                      (peripheral_ce),
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
		.video_reset                        (video_retime_reset),
		.video_output                       (video_output_sel),
		.clk_vga_cga                        (clk_28_636),
		.enable_cga                         (`ENABLE_CGA),
		.clk_vga_hgc                        (clk_57_272),
		.enable_hgc                         (enable_hgc_sel),
		.hgc_rgb                            (hgc_rgb_sel),
	//	.de_o                               (VGA_DE),
		.VGA_R                              (r),
		.VGA_G                              (g),
		.VGA_B                              (b),
		.VGA_HSYNC                          (HSync),
		.VGA_VSYNC                          (VSync),
		.VGA_HBlank                         (HBlank),
		.VGA_VBlank                         (VBlank),
		.VGA_VBlank_border                  (VGA_VBlank_border),
		.VGA_HSYNC_REF                      (VGA_HSYNC_REF),
		.VGA_VSYNC_REF                      (VGA_VSYNC_REF),
	//	.address                            (address),
		.address_ext                        (20'hFFFFF),
		.ext_access_request                 (ldr_hold_request),     // CPU off the bus during a ROM download
		.address_direction                  (address_direction),
		.data_bus                           (data_bus),
		// Private 16-bit SDRAM path, beside the public 8-bit chipset bus.
		.word_read_request                  (word_read_request),
		.word_write_request                 (word_write_request),
		.data_bus_word_in                   (cpu_data_bus_word),
		.data_bus_word                      (data_bus_word),
		.word_read_possible                 (word_read_possible),
		.data_bus_ext                       (8'hFF),
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
		.memory_write_n_ext                 (1'b1),
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
		.tandy_video                        (tandy_video_mode),
		.tandy_16_gfx                       (tandy_16_gfx),
		.tandy_color_16                     (tandy_color_16),
		.clk_uart                           (clk_uart2_en),
		.clk_uart_com2                      (clk_com2_en),
		.uart2_rx                           (uart_rx),
		.uart2_tx                           (uart_tx),
		.uart2_cts_n                        (uart_cts),
		.uart2_dcd_n                        (uart_dcd),
		.uart2_dsr_n                        (uart_dsr),
		.uart2_rts_n                        (uart_rts),
		.uart2_dtr_n                        (uart_dtr),
		.clk_midi                           (clk_midi_en),
		.midi_rx                            (midi_rx),
		.midi_tx                            (midi_tx),
		.mem_start                          (mem_start),
		.mem_we                             (mem_we),
		.mem_addr                           (mem_addr),
		.mem_len                            (mem_len),
		.mem_wdata                          (mem_wdata),
		.mem_wbe                            (mem_wbe),
		.mem_busy                           (mem_busy),
		.mem_done                           (mem_done),
		.mem_rdata                          (mem_rdata),
		.mem_flush                          (ldr_flush),
		.ec00_loaded                        (ec00_loaded),
		.mem_snoop_valid                    (),
		.mem_snoop_addr                     (),
		.mem_snoop_data                     (),
		.mem_snoop_be                       (),
		.ems_enabled                        (ems_enabled_sel),
		.ems_address                        (ems_address_sel),
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
		.fdd_present                        (fdd_present),
		.fdd_request                        (mgmt_req[7:6]),
		.ide0_request                       (mgmt_req[2:0]),
		.xtctl                              (xtctl),
		.enable_a000h                       (a000h),
		.wait_count_clk_en                  (cpu_ce_negedge),
		.ram_read_wait_cycle                (ram_read_wait_cycle),
		.ram_write_wait_cycle               (ram_write_wait_cycle),
		.pause_core                         (pause_core),
		.cga_hw                             (cga_hw),
		.cga_scandouble_en                  (cga_scandouble_en),
		.hercules_hw                        (hercules_hw_sel),
		.swap_video                         (swap_video),
		.crt_h_offset                       (status[49:46]),
		.crt_v_offset                       (status[52:50]),
		.vsync_width_osd                    (vsync_width_osd),
		.hsync_width_osd                    (hsync_width_osd),
		.cga_frame_stack_rebuild            (status[64]),
		.fx_cga_vram_d                      (fx_cga_vram_d),
		.fx_cga_phase                       (fx_cga_phase),
		.fx_cga_hres                        (fx_cga_hres),
		.fx_cga_cur_word                    (fx_cga_cur_word),
		.fx_cga_next_word                   (fx_cga_next_word),
		.fx_hgc_vram_d                      (fx_hgc_vram_d),
		.fx_hgc_phase                       (fx_hgc_phase),
		.fx_hgc_grph                        (fx_hgc_grph),
		.fx_hgc_page                        (fx_hgc_page),
		.fx_hgc_cur_word                    (fx_hgc_cur_word),
		.fx_hgc_next_word                   (fx_hgc_next_word)
	);

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
		.shift_read_timing(shift_read_timing),

		// The CPU type is frozen outside reset so queue depth and bus width
		// cannot change in the middle of an instruction or bus cycle. Fake 286
		// FLAGS carries no such state and tracks the menu as it is changed.
		.is8086(is8086_applied),
		.fake286_flags(fake_286_flags_applied),
		.word_read_request(word_read_request),
		.word_write_request(word_write_request),
		.data_bus_word_out(cpu_data_bus_word),
		.data_bus_word(data_bus_word),
		.word_access_possible(word_read_possible)
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
    wire [16:0] tandy_snd_base = {{6{tandy_snd_e[10]}}, tandy_snd_e};
    wire [16:0] tandy_snd = `ENABLE_TANDY_AUDIO ?
                            (tandy_snd_base << ({1'b0, status[35:34]} + 3'd2)) : 17'd0;
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

        tmp_l <= jtopl2_snd + cms_l_snd + tandy_snd + spk_vol + mt32_l_snd;

        // clamp the output
        out_l <= (^tmp_l[16:15]) ? {tmp_l[16], {15{tmp_l[15]}}} : tmp_l[15:0];

        cmp_l <= compr(out_l);
    end
	 
    reg [15:0] cmp_r;
    reg [15:0] out_r;
    always @(posedge clk_chipset)
    begin
        reg [16:0] tmp_r;

        tmp_r <= jtopl2_snd + cms_r_snd + tandy_snd + spk_vol + mt32_r_snd;

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

    // MIDI baud reference for the MPU-401. Derived straight from the 50MHz
    // clk_chipset rather than the 14.318MHz UART reference, because 50MHz
    // divides exactly: 50e6 / (4 * 16 * 25) = 31250 baud, zero error.
    // (The 14.318MHz path can only reach 30858 baud, -1.25%.) ao486 likewise
    // feeds its MPU a dedicated exact-rate clock instead of the COM reference.
    logic [1:0] clk_midi_counter = 2'd0;
    logic       clk_midi_en = 1'b0;

    always @(posedge clk_chipset)
    begin
        if (clk_midi_counter == 2'd3)
        begin
            clk_midi_counter <= 2'd0;
            clk_midi_en      <= 1'b1;
        end
        else
        begin
            clk_midi_counter <= clk_midi_counter + 2'd1;
            clk_midi_en      <= 1'b0;
        end
    end

    always @(posedge clk_chipset)
    begin
        clk_uart_ff_1 <= clk_14_318;
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

    // COM2 baud reference: a real 8250/16550 card runs from a 1.8432 MHz
    // crystal and DOS divisors assume it. 14.318/8 = 1.7898 MHz made every
    // COM2 rate 2.9% slow, enough to garble data coming from the HPS (modem,
    // PPP). 1.8432/50 = 576/15625, so this fractional accumulator gives an
    // exact 1.8432 MHz average from the 50 MHz clk_chipset (pulses every 27 or
    // 28 cycles, 20 ns jitter). COM1 (internal mouse) keeps clk_uart2_en.
    logic [13:0] clk_com2_acc = 14'd0;
    logic        clk_com2_en  = 1'b0;

    always @(posedge clk_chipset)
    begin
        if (clk_com2_acc >= 14'd15049)      // 15625 - 576
        begin
            clk_com2_acc <= clk_com2_acc - 14'd15049;
            clk_com2_en  <= 1'b1;
        end
        else
        begin
            clk_com2_acc <= clk_com2_acc + 14'd576;
            clk_com2_en  <= 1'b0;
        end
    end

    wire uart_tx, uart_rts, uart_dtr;

    // Selecting MIDI in the MiSTer UART menu hands these pins to the HPS, which
    // bridges them to a USB MIDI device. That gives the MPU-401 a second possible
    // destination besides the mt32-pi on the user port, and is the only way to
    // reach a USB MIDI interface - the user port cannot see one. ao486 gates the
    // same way on uart_mode >= 3.
    //
    // COM2, not COM1, is what normally owns these pins here (COM1 is the internal
    // serial mouse), so COM2 is the port that has to let go of them.
    wire hps_midi = `ENABLE_MIDI && (uart_mode >= 8'd3);

    assign UART_TXD = hps_midi ? midi_tx : uart_tx;
    assign UART_RTS = ~hps_midi & uart_rts;
    assign UART_DTR = ~hps_midi & uart_dtr;

    // Idle high, never low: a UART input held at 0 is a break condition, the same
    // trap the USER_OUT default fell into. Holding DCD deasserted also keeps the
    // handover from looking like a carrier transition to a guest with COM2 open.
    wire uart_rx  = hps_midi | UART_RXD;
    wire uart_cts = hps_midi | UART_CTS;
    wire uart_dsr = hps_midi | UART_DSR;
    // DCD comes from the HPS side as well, like ao486: sys_top crosses the
    // lines null-modem style, so UART_DSR is the Linux UART's DTR, raised by
    // the soft modem / pppd / getty. It used to be UART_DTR, the core's own
    // DTR output, so the guest saw "carrier" whenever it raised DTR itself and
    // never saw a hang-up.
    wire uart_dcd = hps_midi | UART_DSR;


    /// UART2

    // USER_IO is time-shared between the COM2 passthrough (default) and the
    // MT32-pi bridge below - only one can be connected at a time.
    // Default (0) is MT32-pi, matching ao486: at core load, before the saved
    // config arrives, we must already be in the safe non-driving state.
    wire user_io_mt32 = `ENABLE_MIDI && ~status[6];

    // The COM2-over-USER_IO path is dead code in this core: uart2_tx/rts/dtr have
    // no driver, so they synthesise to constant 0 and would actively pull pins
    // 1, 2 and 4 low. Pins 2 and 4 are *outputs* of an attached mt32-pi (I2S), so
    // that is a direct output-vs-output contention, and pin 1 low is a permanent
    // MIDI break. COM2 is also the power-on default before the saved config is
    // applied, so this happened on every core load. Release the pins instead;
    // ao486 never hits this because its COM2 signals are real and idle high.
    assign USER_OUT = user_io_mt32 ? mt32_user_out : 7'h7F;

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

    wire uart2_rx  = user_io_mt32 | USER_IN[0];
    wire uart2_cts = user_io_mt32 | USER_IN[3];
    wire uart2_dsr = user_io_mt32 | USER_IN[5];
    wire uart2_dcd = user_io_mt32 | USER_IN[6];

    //
    ////////////////////////////  MT32-pi  //////////////////////////////////
    //
    // Bridges the MPU-401 UART-mode MIDI interface (rtl/uart/mpu401.sv, wired
    // through the chipset above) to an external mt32-pi device connected on
    // USER_IO. See sys/mt32pi.sv for the wire protocol (MIDI serial + I2S
    // audio in + I2C status/LCD mirror).
    //

    wire        mt32_disable  = status[13];
    // Deliberately NOT reset_wire: that one stays asserted for the whole boot
    // splash (~5s), which would hold the I2C slave silent long enough for the
    // mt32-pi's I2C master to give up. Mirror ao486 and use only the genuine
    // system/user resets.
    wire        mt32_reset    = status[40] | RESET | status[0] | buttons[1];
    wire        mt32_mode_req = status[41];
    wire  [1:0] mt32_rom_req  = status[4:3];
    wire  [7:0] mt32_sf_req   = {5'd0, status[62:60]};

    wire [15:0] mt32_i2s_r, mt32_i2s_l;
    wire  [7:0] mt32_mode, mt32_rom, mt32_sf;
    wire        mt32_lcd_en, mt32_lcd_pix, mt32_lcd_update;
    wire        mt32_newmode;
    wire        mt32_available;
    // Gate on the user's explicit USER_IO selection, NOT on mt32_available.
    // The I2C handshake is only an auto-detect convenience for the OSD; tying
    // the audio path to it means a perfectly working mt32-pi stays silent
    // whenever that handshake does not happen - which is exactly what we hit.
    wire        mt32_use  = user_io_mt32 & ~mt32_disable;
    wire        mt32_mute = user_io_mt32 &  mt32_disable;

    wire  [6:0] mt32_user_out;
    wire        midi_tx;              // driven by the CHIPSET's mpu401 instance
    wire        mt32_pi_midi_rx;
    // Three sources in priority order: the HPS bridge when the UART menu is set
    // to MIDI, the mt32-pi on the user port otherwise, and idle-high when neither
    // is connected. The transmit side needs no such priority - it simply reaches
    // both destinations at once, which is what a MIDI thru does anyway.
    wire        midi_rx = hps_midi    ? UART_RXD        :
                          user_io_mt32 ? mt32_pi_midi_rx : 1'b1;

    mt32pi mt32pi
    (
        .CLK_AUDIO       (CLK_AUDIO),

        .CLK_VIDEO       (CLK_VIDEO),
        .CE_PIXEL        (CE_PIXEL),
        .VGA_VS          (VGA_VS),
        .VGA_DE          (VGA_DE),

        .USER_IN         (USER_IN),
        .USER_OUT        (mt32_user_out),

        .reset           (mt32_reset),
        .midi_tx         (midi_tx | mt32_mute),
        .midi_rx         (mt32_pi_midi_rx),

        .mt32_i2s_r      (mt32_i2s_r),
        .mt32_i2s_l      (mt32_i2s_l),

        .mt32_available  (mt32_available),

        .mt32_mode_req   (mt32_mode_req),
        .mt32_rom_req    (mt32_rom_req),
        .mt32_sf_req     (mt32_sf_req),

        .mt32_mode       (mt32_mode),
        .mt32_rom        (mt32_rom),
        .mt32_sf         (mt32_sf),
        .mt32_newmode    (mt32_newmode),

        .mt32_lcd_en     (mt32_lcd_en),
        .mt32_lcd_pix    (mt32_lcd_pix),
        .mt32_lcd_update (mt32_lcd_update)
    );

    wire signed [16:0] mt32_i2s_l_ext = {mt32_i2s_l[15], mt32_i2s_l};
    wire signed [16:0] mt32_i2s_r_ext = {mt32_i2s_r[15], mt32_i2s_r};
    wire [16:0] mt32_l_snd = mt32_use ? mt32_i2s_l_ext : 17'd0;
    wire [16:0] mt32_r_snd = mt32_use ? mt32_i2s_r_ext : 17'd0;

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
    reg  ce_pixel_cga = 1'b0;
    wire ce_pixel_hgc_raw;
    wire de_o;
    wire [5:0] r, g, b;
    reg [7:0] raux_cga, gaux_cga, baux_cga;
    reg [7:0] raux_hgc, gaux_hgc, baux_hgc;
	 wire [7:0] VGA_R_AUX, VGA_G_AUX, VGA_B_AUX;
    wire CLK_VIDEO_HGC;
    wire CLK_VIDEO_CGA;
    wire CE_PIXEL_CREDITS;

    wire  [7:0] VGA_R_cga;
    wire  [7:0] VGA_G_cga;
    wire  [7:0] VGA_B_cga;
    wire        VGA_HS_cga;
    wire        VGA_VS_cga;
    wire        VGA_DE_cga;
    wire [21:0] gamma_bus_cga;
    wire        CE_PIXEL_cga;
    reg         ce_pixel_cga_2x = 1'b0;
    wire        ce_pixel_cga_vid = cga_scandouble_en ? ce_pixel_cga_2x : ce_pixel_cga;

    wire  [7:0] VGA_R_hgc;
    wire  [7:0] VGA_G_hgc;
    wire  [7:0] VGA_B_hgc;
    wire        VGA_HS_hgc;
    wire        VGA_VS_hgc;
    wire        VGA_DE_hgc;
    wire [21:0] gamma_bus_hgc;
    wire        CE_PIXEL_hgc;
    reg  [1:0]  ce_pixel_hgc_div = 2'b0;
    reg         ce_pixel_hgc_raw_d = 1'b0;
    reg  [5:0]  hgc_r_meta, hgc_g_meta, hgc_b_meta;
    reg  [5:0]  hgc_r_sync, hgc_g_sync, hgc_b_sync;
    reg         hgc_hs_meta, hgc_vs_meta;
    reg         hgc_hs_sync, hgc_vs_sync;
    reg         hgc_hb_meta, hgc_vb_meta;
    reg         hgc_hb_sync, hgc_vb_sync;

    reg  [7:0]  VGA_R_cga_src = 8'd0;
    reg  [7:0]  VGA_G_cga_src = 8'd0;
    reg  [7:0]  VGA_B_cga_src = 8'd0;
    reg         VGA_HS_cga_src = 1'b0;
    reg         VGA_VS_cga_src = 1'b0;
    reg         VGA_DE_cga_src = 1'b0;
    reg         LHBL_cga_src = 1'b1;
    reg         LVBL_cga_src = 1'b1;
    reg         CE_PIXEL_cga_src = 1'b0;
    reg  [7:0]  VGA_R_cga_ps = 8'd0;
    reg  [7:0]  VGA_G_cga_ps = 8'd0;
    reg  [7:0]  VGA_B_cga_ps = 8'd0;
    reg         VGA_HS_cga_ps = 1'b0;
    reg         VGA_VS_cga_ps = 1'b0;
    reg         VGA_DE_cga_ps = 1'b0;
    reg         LHBL_cga_ps = 1'b1;
    reg         LVBL_cga_ps = 1'b1;
    reg         CE_PIXEL_cga_ps = 1'b0;
    reg         CE_PIXEL_cga_ps_d = 1'b0;
    reg  [7:0]  VGA_R_cga_hdmi, VGA_G_cga_hdmi, VGA_B_cga_hdmi;
    reg         VGA_HS_cga_hdmi, VGA_VS_cga_hdmi, VGA_DE_cga_hdmi;
    reg         LHBL_cga_hdmi, LVBL_cga_hdmi;
    reg         CE_PIXEL_cga_hdmi = 1'b0;

    reg  [7:0]  VGA_R_hgc_src = 8'd0;
    reg  [7:0]  VGA_G_hgc_src = 8'd0;
    reg  [7:0]  VGA_B_hgc_src = 8'd0;
    reg         VGA_HS_hgc_src = 1'b0;
    reg         VGA_VS_hgc_src = 1'b0;
    reg         VGA_DE_hgc_src = 1'b0;
    reg         LHBL_hgc_src = 1'b1;
    reg         credits_vb_hgc_src = 1'b1;
    reg         CE_PIXEL_hgc_src = 1'b0;
    reg  [7:0]  VGA_R_hgc_ps = 8'd0;
    reg  [7:0]  VGA_G_hgc_ps = 8'd0;
    reg  [7:0]  VGA_B_hgc_ps = 8'd0;
    reg         VGA_HS_hgc_ps = 1'b0;
    reg         VGA_VS_hgc_ps = 1'b0;
    reg         VGA_DE_hgc_ps = 1'b0;
    reg         LHBL_hgc_ps = 1'b1;
    reg         credits_vb_hgc_ps = 1'b1;
    reg         CE_PIXEL_hgc_ps = 1'b0;
    reg         ce_pixel_hgc_prev = 1'b0;
    reg         ce_pixel_hgc_tog = 1'b0;
    reg         ce_pixel_hgc_tog_1 = 1'b0;
    reg         ce_pixel_hgc_tog_2 = 1'b0;
    wire        CE_PIXEL_hgc_sync;
    reg  [7:0]  VGA_R_hgc_56 = 8'd0, VGA_G_hgc_56 = 8'd0, VGA_B_hgc_56 = 8'd0;
    reg         VGA_HS_hgc_56 = 1'b0, VGA_VS_hgc_56 = 1'b0, VGA_DE_hgc_56 = 1'b0;
    reg         LHBL_hgc_56 = 1'b1, credits_vb_hgc_56 = 1'b1;
    reg         CE_PIXEL_hgc_hdmi = 1'b0;
    reg         vga_f1_hgc_ps1 = 1'b0, vga_f1_hgc_ps2 = 1'b0;

    assign CLK_VIDEO = clk_video_out_ps;
    assign CLK_VIDEO_HGC = clk_114_544;
    assign CLK_VIDEO_CGA = clk_57_272;
    assign ce_pixel_hgc_raw = ce_pixel_hgc_div[1];
    // ce_pixel_hgc_raw is deliberately a two-clock level for the existing
    // HGC mixer.  The framebuffer needs one event per converted pixel, after
    // the converter has registered the new colour, so sample the second half
    // of that level as a single-cycle enable.
    wire ce_pixel_hgc_fb = ce_pixel_hgc_raw & ce_pixel_hgc_raw_d;

    always @(posedge clk_114_544)
        ce_pixel_hgc_raw_d <= ce_pixel_hgc_raw;

    always @(posedge clk_114_544)
        if (`ENABLE_HGC)
            ce_pixel_hgc_div <= ce_pixel_hgc_div + 2'd1;
        else
            ce_pixel_hgc_div <= 2'd0;

    always @(posedge clk_57_272)
        ce_pixel_cga_2x <= ~ce_pixel_cga_2x;

    wire   scandoubler = video_scandoubler_en;

    reg [24:0] HBlank_del;
    reg [24:0] HBlank_del_hgc;
    wire tandy_16_gfx;
    wire tandy_color_16;
    wire color = (screen_mode_video_ff == 3'd0);
    
	 wire HBlank_VGA;

    reg [10:0] HBlank_counter_hgc = 0;
    reg HBlank_fixed_hgc = 1'b1;
    reg [1:0] HSync_del_hgc = 2'b11;
    localparam integer MDA_VSYNC_DELAY = 19;
    reg [MDA_VSYNC_DELAY:0] VSync_line;
    // Credits are useful during the splash pause as well as during a normal
    // pause. Audio and CPU control continue to use pause_core alone.
    reg        video_credits_show_buf;
    reg        video_credits_show;

    always_comb
    begin
        if (swap_video_eff)
            HBlank_VGA = HBlank_del_hgc[24];
        else if (composite && !cga_scandouble_en)
            // The composite decoder has a multi-sample filter/pixel latency.
            // Keep its electrical input on raw CRTC blanking, while keeping
            // the active aperture at the shortest delay that preserves the
            // first source column.  The decoder clamps the transition
            // residue internally; delaying this edge to [24] crops real
            // 80/40-column content.
            HBlank_VGA = HBlank_del[22] | HBlank_del[2];
        else if (tandy_color_16)
            HBlank_VGA = HBlank_del[11];
        else if (tandy_16_gfx)
            HBlank_VGA = HBlank_del[9];
        else
            // RGBI reaches the converter 5 clocks after the CRTC blanking
            // edge, and the converter registers colour once more than
            // blanking (one 14 MHz pixel = 2 clocks).  [6] puts the blanking
            // edge on that colour edge exactly.  [5] was half a pixel early,
            // so with half of the power-up phases of ce_pixel_cga against
            // the CGA clkdiv the window opened on one border pixel and
            // dropped the last pixel of the line.
            HBlank_VGA = HBlank_del[6];
    end

    // With Border the CGA output is a fixed raster placed after the sync pulses,
    // as a monitor shows it, whatever timing the CRTC is given: the scaler gets
    // frames of the same size, with the picture where the timing puts it.
    wire HBlank_win, VBlank_win, HSync_win, VSync_win;
    cga_border_window cga_border_win
    (
        .clk       (clk_28_636),
        .ce        (clk_14_318),
        .hsync     (VGA_HSYNC_REF),
        .vsync     (VGA_VSYNC_REF),
        .v_early   (status[65] ? status[52:50] : 3'd0),
        .hblank    (HBlank_win),
        .vblank    (VBlank_win),
        .hsync_out (HSync_win),
        .vsync_out (VSync_win)
    );

    always @(posedge clk_57_272)
    begin
        if (swap_video_eff)
        begin
            HBlank_del_hgc <= {HBlank_del_hgc[23:0], HBlank};
            HSync_del_hgc <= {HSync_del_hgc[0], HSync};
            if (HSync_del_hgc == 2'b01)
            begin
                VSync_line <= {VSync_line[MDA_VSYNC_DELAY-1:0], VSync};
                HBlank_counter_hgc <= 0;
                HBlank_fixed_hgc <= 1'b1;
            end
            else
            begin
                if (HBlank_counter_hgc == (std_hsyncwidth ? 120 : 143))
                    HBlank_fixed_hgc <= 1'b0;
                else
                    HBlank_counter_hgc <= HBlank_counter_hgc + 1;
            end
        end
    end

    always @ (posedge clk_video_out_ps) begin
        video_credits_show_buf  <= pause_core | splash_paused;
        video_credits_show      <= video_credits_show_buf;
    end

    wire cga_border_win_en = border_video_ff & ~swap_video_eff & ~cga_scandouble_en;
    wire LHBL = cga_scandouble_en ? HBlank :
                (border_video_ff ? (swap_video_eff ? HBlank_fixed_hgc : HBlank_win) : HBlank_VGA);
    wire LVBL = cga_scandouble_en ? VBlank :
                (border_video_ff ? (swap_video_eff ? VGA_VBlank_border : VBlank_win) : VBlank);
    wire LHS  = cga_border_win_en ? HSync_win : HSync;
    wire LVS  = cga_border_win_en ? VSync_win : VSync;

    // The window's sync pulses do not follow the OSD CRT H offset, so with Border
    // and "Border CRT offsets" the picture is moved inside the window instead.
    // The window is the same in every mode, so this is too. The CGA's own HSYNC
    // is 6 pixels later than the reference one in 80 columns and every step of
    // the offset brings it 2 pixels earlier: the picture goes where the same
    // offset puts it in 80 columns with Border off.
    wire [3:0] crt_h_off = status[65] ? status[49:46] : 4'd0;
    wire [6:0] crt_h_pix = (crt_h_off > 4'd3) ? {2'b00, crt_h_off, 1'b0} - 7'd6 : 7'd0;
    wire [17:0] cga_pix_dly;
    cga_pixel_delay #(.W(18)) cga_border_pix_delay
    (
        .clk  (clk_28_636),
        .en   (clk_14_318),
        .n    (cga_border_win_en ? crt_h_pix : 7'd0),
        .din  ({r, g, b}),
        .dout (cga_pix_dly)
    );
    wire VSync_hgc = VSync_line[MDA_VSYNC_DELAY];

    wire haux_cga, vaux_cga, hbaux_cga, vbaux_cga;
    wire haux_hgc, vaux_hgc, hbaux_hgc, vbaux_hgc;

    video_monochrome_converter_cga video_mono_cga 
	(
		.clk_vid(CLK_VIDEO_CGA),
		.ce_pix(ce_pixel_cga_vid),

		.R({cga_pix_dly[17:12], 2'b00}),
		.G({cga_pix_dly[11:6], 2'b00}),
		.B({cga_pix_dly[5:0], 2'b00}),

		.HSync(LHS),
		.VSync(LVS),
		.HBlank(LHBL),
		.VBlank(LVBL),

		.gfx_mode(screen_mode_cga_ff),

		.R_OUT(raux_cga),
		.G_OUT(gaux_cga),
		.B_OUT(baux_cga),

		.HSync_OUT(haux_cga),
		.VSync_OUT(vaux_cga),
		.HBlank_OUT(hbaux_cga),
		.VBlank_OUT(vbaux_cga)
	);

    video_monochrome_converter_cga video_mono_hgc
	(
		.clk_vid(CLK_VIDEO_HGC),
		.ce_pix(ce_pixel_hgc_raw),

		.R({hgc_r_sync, 2'b00}),
		.G({hgc_g_sync, 2'b00}),
		.B({hgc_b_sync, 2'b00}),

		.HSync(hgc_hs_sync),
		.VSync(hgc_vs_sync),
		.HBlank(hgc_hb_sync),
		.VBlank(hgc_vb_sync),

		.gfx_mode(screen_mode_video_ff),

		.R_OUT(raux_hgc),
		.G_OUT(gaux_hgc),
		.B_OUT(baux_hgc),

		.HSync_OUT(haux_hgc),
		.VSync_OUT(vaux_hgc),
		.HBlank_OUT(hbaux_hgc),
		.VBlank_OUT(vbaux_hgc)
	);

    ///////////////////  HGC/MDA 350-LINE CRT OUTPUT  ///////////////////
    //
    // HGC/MDA's native 350-line raster is above the progressive limit of a
    // 15 kHz television.  Capture only this path into DDRAM and read it back
    // as either 480i or 240p.  CGA never enters this block: its calibrated
    // native 15 kHz path remains completely bypassed.
    //
    // The HGC pipeline runs at 114.544 MHz while its native pixels are exposed
    // by ce_pixel_hgc_raw as a two-clock level.  The capture samples the second
    // half of that level, giving one event per converted 28.636 MHz pixel.
    localparam [11:0] HGC_FB_DOTS  = 12'd720;
    localparam [9:0]  HGC_FB_LINES = 10'd350;

    // HGC text and graphics do not always expose the same active vertical
    // aperture after the CRTC/sequencer pipeline.  In particular, HGC
    // graphics can arrive a few lines shorter than the nominal 350-line
    // timing.  The framebuffer must be told the aperture that is actually
    // present or its whole-frame guard will reject every graphics frame.
    wire hgc_fb_de = ~hbaux_hgc & ~vbaux_hgc;
    reg  hgc_fb_de_q = 1'b0;
    reg  hgc_fb_vblank_q = 1'b1;
    reg  [9:0] hgc_fb_line_count = 10'd0;
    reg  [9:0] hgc_fb_active_lines = HGC_FB_LINES;
    wire hgc_fb_de_fall = ce_pixel_hgc_fb && !hgc_fb_de && hgc_fb_de_q;
    wire hgc_fb_vblank_fall = ce_pixel_hgc_fb && !vbaux_hgc && hgc_fb_vblank_q;
    wire hgc_fb_vblank_rise = ce_pixel_hgc_fb && vbaux_hgc && !hgc_fb_vblank_q;
    wire [9:0] hgc_fb_line_count_eff = hgc_fb_de_fall ?
                                       (hgc_fb_line_count + 10'd1) :
                                       hgc_fb_line_count;

    // Measure the source aperture once per frame.  The result is held still
    // while the next frame is captured, so register writes during a mode set
    // cannot change the DDRAM stride or make a mixed frame appear valid.
    always @(posedge CLK_VIDEO_HGC) begin
        if (video_retime_reset_hgc) begin
            hgc_fb_de_q          <= 1'b0;
            hgc_fb_vblank_q      <= 1'b1;
            hgc_fb_line_count   <= 10'd0;
            hgc_fb_active_lines <= HGC_FB_LINES;
        end else begin
            if (ce_pixel_hgc_fb) begin
                hgc_fb_de_q     <= hgc_fb_de;
                hgc_fb_vblank_q <= vbaux_hgc;
            end

            if (hgc_fb_vblank_fall)
                hgc_fb_line_count <= 10'd0;
            else if (hgc_fb_de_fall)
                hgc_fb_line_count <= hgc_fb_line_count + 10'd1;

            if (hgc_fb_vblank_rise && (hgc_fb_line_count_eff != 10'd0))
                hgc_fb_active_lines <= hgc_fb_line_count_eff;
        end
    end

    wire fb_enable = swap_video_eff & crt480i_osd;
    wire [7:0]  cap_burstcnt;
    wire [28:0] cap_addr;
    wire [63:0] cap_din;
    wire        cap_we;
    wire        cap_busy;
    wire [1:0]  fb_frame_buffer;
    wire [11:0] fb_frame_width;
    wire [9:0]  fb_frame_height;
    wire [13:0] fb_frame_stride;
    wire        fb_frame_valid;
    wire [1:0]  fb_reading_buffer;

    hgc_fb_capture fb_capture_hgc (
        .clk(CLK_VIDEO_HGC),
        .reset(video_retime_reset_hgc),
        .enable(fb_enable),
        .ce_pix(ce_pixel_hgc_fb),
        .r(raux_hgc), .g(gaux_hgc), .b(baux_hgc),
        .de(hgc_fb_de),
        .vblank(vbaux_hgc),
        .active_dots(HGC_FB_DOTS),
        .active_lines(hgc_fb_active_lines),
        .reading_buffer(fb_reading_buffer),
        .ddram_busy(cap_busy),
        .ddram_burstcnt(cap_burstcnt),
        .ddram_addr(cap_addr),
        .ddram_din(cap_din),
        .ddram_be(),
        .ddram_we(cap_we),
        .frame_buffer(fb_frame_buffer),
        .frame_width(fb_frame_width),
        .frame_height(fb_frame_height),
        .frame_stride(fb_frame_stride),
        .frame_seq(),
        .frame_valid(fb_frame_valid),
        .overrun()
    );

    wire        fb_rd_req;
    wire [28:0] fb_rd_addr;
    wire [7:0]  fb_rd_burstcnt;
    wire        fb_rd_grant;
    wire [63:0] fb_rd_data;
    wire        fb_rd_data_valid;
    wire [7:0]  fb_r, fb_g, fb_b;
    wire        fb_hs, fb_vs, fb_hb, fb_vb, fb_de, fb_field, fb_ce_pix;

    hgc_fb_readout #(.CLK_DIV(8)) fb_readout_hgc (
        .clk(CLK_VIDEO_HGC),
        .reset(video_retime_reset_hgc),
        .enable(fb_enable),
        .progressive(crt480i_prog),
        .crt_h_offset(status[49:46]),
        .crt_v_offset(status[52:50]),
        .frame_buffer(fb_frame_buffer),
        .frame_width(fb_frame_width),
        .frame_height(fb_frame_height),
        .frame_stride(fb_frame_stride),
        .frame_valid(fb_frame_valid),
        .rd_req(fb_rd_req),
        .rd_addr(fb_rd_addr),
        .rd_burstcnt(fb_rd_burstcnt),
        .rd_grant(fb_rd_grant),
        .rd_data(fb_rd_data),
        .rd_data_valid(fb_rd_data_valid),
        .r(fb_r), .g(fb_g), .b(fb_b),
        .hsync(fb_hs), .vsync(fb_vs), .hblank(fb_hb), .vblank(fb_vb),
        .de(fb_de), .field(fb_field), .ce_pix(fb_ce_pix),
        .reading_buffer(fb_reading_buffer)
    );

    assign DDRAM_CLK = CLK_VIDEO_HGC;

    hgc_ddr_arbiter fb_arbiter_hgc (
        .clk(CLK_VIDEO_HGC),
        .reset(video_retime_reset_hgc),
        .ddram_busy(DDRAM_BUSY),
        .ddram_burstcnt(DDRAM_BURSTCNT),
        .ddram_addr(DDRAM_ADDR),
        .ddram_din(DDRAM_DIN),
        .ddram_be(DDRAM_BE),
        .ddram_we(DDRAM_WE),
        .ddram_rd(DDRAM_RD),
        .ddram_dout(DDRAM_DOUT),
        .ddram_dout_ready(DDRAM_DOUT_READY),
        .rd_req(fb_rd_req),
        .rd_addr(fb_rd_addr),
        .rd_burstcnt(fb_rd_burstcnt),
        .rd_grant(fb_rd_grant),
        .rd_data(fb_rd_data),
        .rd_data_valid(fb_rd_data_valid),
        .wr_req(cap_we),
        .wr_addr(cap_addr),
        .wr_burstcnt(cap_burstcnt),
        .wr_din(cap_din),
        .wr_busy_out(cap_busy),
        .wr_grant()
    );

    // Switch on an HGC blanking edge once a complete frame is available. It
    // avoids exposing a half-filled DDRAM frame during a mode transition.
    wire crt480i_active;
    video_source_switch crt480i_source_switch_hgc (
        .clock(CLK_VIDEO_HGC),
        .reset(video_retime_reset_hgc),
        .select_alt(fb_enable & fb_frame_valid),
        .primary_hsync(haux_hgc),
        .primary_vblank(vbaux_hgc),
        .alt_hsync(fb_hs),
        .alt_vblank(fb_vb),
        .alt_active(crt480i_active)
    );

    wire [7:0] hgc_mixer_r = crt480i_active ? fb_r : raux_hgc;
    wire [7:0] hgc_mixer_g = crt480i_active ? fb_g : gaux_hgc;
    wire [7:0] hgc_mixer_b = crt480i_active ? fb_b : baux_hgc;
    wire       hgc_mixer_hs = crt480i_active ? fb_hs : haux_hgc;
    wire       hgc_mixer_vs = crt480i_active ? fb_vs : vaux_hgc;
    wire       hgc_mixer_hb = crt480i_active ? fb_hb : hbaux_hgc;
    wire       hgc_mixer_vb = crt480i_active ? fb_vb : vbaux_hgc;
    wire       ce_pixel_hgc_mixer = crt480i_active ? fb_ce_pix : ce_pixel_hgc_raw;

    always @(posedge clk_video_out_ps or posedge video_retime_reset_local)
    begin
        if (video_retime_reset_local) begin
            vga_f1_hgc_ps1 <= 1'b0;
            vga_f1_hgc_ps2 <= 1'b0;
        end else begin
            vga_f1_hgc_ps1 <= crt480i_active & fb_field;
            vga_f1_hgc_ps2 <= vga_f1_hgc_ps1;
        end
    end

    assign VGA_F1 = vga_f1_hgc_ps2;

    /*
    assign VGA_R = raux;
    assign VGA_G = gaux;
    assign VGA_B = baux;
    assign VGA_HS = HSync;
    assign VGA_VS = VSync;
    assign VGA_DE = ~(HBlank | VBlank);
    assign CE_PIXEL = ce_pixel;
    */

    wire       pre2x_LHBL, pre2x_LVBL;
    wire [7:0] pre2x_r, pre2x_g, pre2x_b;
	 

	video_mixer #(.GAMMA(1)) video_mixer_cga
	(
		.*,

		.CLK_VIDEO(CLK_VIDEO_CGA),
		.CE_PIXEL(CE_PIXEL_cga),
		.ce_pix(ce_pixel_cga_vid),

		.freeze_sync(),

		.R(raux_cga),
		.G(gaux_cga),
		.B(baux_cga),

		.HBlank(hbaux_cga),
		.VBlank(vbaux_cga),
		.HSync(haux_cga),
		.VSync(vaux_cga),

		.scandoubler(1'b0),
		.hq2x(scale_cga_ff==1),
		.gamma_bus(gamma_bus_cga),

		.VGA_R(VGA_R_cga),
		.VGA_G(VGA_G_cga),
		.VGA_B(VGA_B_cga),
		.VGA_VS(VGA_VS_cga),
		.VGA_HS(VGA_HS_cga),
		.VGA_DE(VGA_DE_cga)

	);

    always @(posedge clk_57_272)
    begin
        VGA_R_cga_src <= VGA_R_cga;
        VGA_G_cga_src <= VGA_G_cga;
        VGA_B_cga_src <= VGA_B_cga;
        VGA_HS_cga_src <= VGA_HS_cga;
        VGA_VS_cga_src <= VGA_VS_cga;
        VGA_DE_cga_src <= VGA_DE_cga;
        LHBL_cga_src <= LHBL;
        LVBL_cga_src <= LVBL;
        CE_PIXEL_cga_src <= CE_PIXEL_cga;
    end

    // Retimes the exact-frequency CGA output onto a phase-shifted sibling clock.
    always @(posedge clk_video_out_ps or posedge video_retime_reset_local)
    begin
        if (video_retime_reset_local)
        begin
            VGA_R_cga_ps <= 8'd0;
            VGA_G_cga_ps <= 8'd0;
            VGA_B_cga_ps <= 8'd0;
            VGA_HS_cga_ps <= 1'b0;
            VGA_VS_cga_ps <= 1'b0;
            VGA_DE_cga_ps <= 1'b0;
            LHBL_cga_ps <= 1'b1;
            LVBL_cga_ps <= 1'b1;
            CE_PIXEL_cga_ps <= 1'b0;
            CE_PIXEL_cga_ps_d <= 1'b0;
            VGA_R_cga_hdmi <= 8'd0;
            VGA_G_cga_hdmi <= 8'd0;
            VGA_B_cga_hdmi <= 8'd0;
            VGA_HS_cga_hdmi <= 1'b0;
            VGA_VS_cga_hdmi <= 1'b0;
            VGA_DE_cga_hdmi <= 1'b0;
            LHBL_cga_hdmi <= 1'b1;
            LVBL_cga_hdmi <= 1'b1;
            CE_PIXEL_cga_hdmi <= 1'b0;
        end
        else
        begin
            CE_PIXEL_cga_hdmi <= CE_PIXEL_cga_ps & ~CE_PIXEL_cga_ps_d;
            if (CE_PIXEL_cga_ps & ~CE_PIXEL_cga_ps_d)
            begin
                VGA_R_cga_hdmi <= VGA_R_cga_ps;
                VGA_G_cga_hdmi <= VGA_G_cga_ps;
                VGA_B_cga_hdmi <= VGA_B_cga_ps;
                VGA_HS_cga_hdmi <= VGA_HS_cga_ps;
                VGA_VS_cga_hdmi <= VGA_VS_cga_ps;
                VGA_DE_cga_hdmi <= VGA_DE_cga_ps;
                LHBL_cga_hdmi <= LHBL_cga_ps;
                LVBL_cga_hdmi <= LVBL_cga_ps;
            end

            CE_PIXEL_cga_ps_d <= CE_PIXEL_cga_ps;
            CE_PIXEL_cga_ps <= CE_PIXEL_cga_src;
            VGA_R_cga_ps <= VGA_R_cga_src;
            VGA_G_cga_ps <= VGA_G_cga_src;
            VGA_B_cga_ps <= VGA_B_cga_src;
            VGA_HS_cga_ps <= VGA_HS_cga_src;
            VGA_VS_cga_ps <= VGA_VS_cga_src;
            VGA_DE_cga_ps <= VGA_DE_cga_src;
            LHBL_cga_ps <= LHBL_cga_src;
            LVBL_cga_ps <= LVBL_cga_src;
        end
    end

    always @(posedge clk_114_544)
    begin
        if (ce_pixel_hgc_raw)
        begin
            hgc_r_meta  <= r;
            hgc_g_meta  <= g;
            hgc_b_meta  <= b;
            hgc_hs_meta <= HSync;
            hgc_vs_meta <= VSync_hgc;
            hgc_hb_meta <= HBlank;
            hgc_vb_meta <= VBlank;

            hgc_r_sync  <= hgc_r_meta;
            hgc_g_sync  <= hgc_g_meta;
            hgc_b_sync  <= hgc_b_meta;
            hgc_hs_sync <= hgc_hs_meta;
            hgc_vs_sync <= hgc_vs_meta;
            hgc_hb_sync <= hgc_hb_meta;
            hgc_vb_sync <= hgc_vb_meta;
        end
    end

	video_mixer #(.GAMMA(0)) video_mixer_hgc
	(
		.*,

		.CLK_VIDEO(CLK_VIDEO_HGC),
		.CE_PIXEL(CE_PIXEL_hgc),
		.ce_pix(ce_pixel_hgc_mixer),

		.freeze_sync(),

		.R(hgc_mixer_r),
		.G(hgc_mixer_g),
		.B(hgc_mixer_b),

		.HBlank(hgc_mixer_hb),
		.VBlank(hgc_mixer_vb),
		.HSync(hgc_mixer_hs),
		.VSync(hgc_mixer_vs),

		// The framebuffer already emits a 15 kHz raster. Applying the normal
		// HGC scandoubler to it would turn 480i/240p back into a high-rate mode.
		.scandoubler(scandoubler && !crt480i_active),
		.hq2x(scale_video_ff==1),
		.gamma_bus(gamma_bus_hgc),

		.VGA_R(VGA_R_hgc),
		.VGA_G(VGA_G_hgc),
		.VGA_B(VGA_B_hgc),
		.VGA_VS(VGA_VS_hgc),
		.VGA_HS(VGA_HS_hgc),
		.VGA_DE(VGA_DE_hgc)

	);

    always @(posedge clk_114_544)
    begin
        ce_pixel_hgc_prev <= CE_PIXEL_hgc;
        if (CE_PIXEL_hgc && ~ce_pixel_hgc_prev)
            ce_pixel_hgc_tog <= ~ce_pixel_hgc_tog;
    end

    always @(posedge clk_57_272)
    begin
        ce_pixel_hgc_tog_1 <= ce_pixel_hgc_tog;
        ce_pixel_hgc_tog_2 <= ce_pixel_hgc_tog_1;
        CE_PIXEL_hgc_src <= CE_PIXEL_hgc_sync;

        if (CE_PIXEL_hgc_sync)
        begin
            VGA_R_hgc_src <= VGA_R_hgc;
            VGA_G_hgc_src <= VGA_G_hgc;
            VGA_B_hgc_src <= VGA_B_hgc;
            VGA_HS_hgc_src <= VGA_HS_hgc;
            VGA_VS_hgc_src <= VGA_VS_hgc;
            VGA_DE_hgc_src <= VGA_DE_hgc;
            LHBL_hgc_src <= crt480i_active ? fb_hb : hgc_hb_sync;
            credits_vb_hgc_src <= crt480i_active ? fb_vb : hgc_vb_sync;
        end
    end

    assign CE_PIXEL_hgc_sync = ce_pixel_hgc_tog_1 ^ ce_pixel_hgc_tog_2;

    // Retimes the HGC mixer output by exploiting the exact 2:1 relation between
    // clk_114_544 and the phase-shifted clk_video_out_ps.
    //
    // The *_ps stage captures on the falling edge of clk_video_out_ps. The
    // *_src registers change every 17.46 ns on clk_57_272, so that edge (13.1 ns
    // after launch) still takes the same value the rising edge 4.4 ns after
    // launch did, and the rising-edge *_56 stage still loads it on the same
    // edge as before. Only the timing window grows; the cycle alignment of
    // every HGC signal, CE included, is unchanged.
    always @(negedge clk_video_out_ps or posedge video_retime_reset_local)
    begin
        if (video_retime_reset_local)
        begin
            VGA_R_hgc_ps <= 8'd0;
            VGA_G_hgc_ps <= 8'd0;
            VGA_B_hgc_ps <= 8'd0;
            VGA_HS_hgc_ps <= 1'b0;
            VGA_VS_hgc_ps <= 1'b0;
            VGA_DE_hgc_ps <= 1'b0;
            LHBL_hgc_ps <= 1'b1;
            credits_vb_hgc_ps <= 1'b1;
            CE_PIXEL_hgc_ps <= 1'b0;
        end
        else
        begin
            CE_PIXEL_hgc_ps <= CE_PIXEL_hgc_src;
            VGA_R_hgc_ps <= VGA_R_hgc_src;
            VGA_G_hgc_ps <= VGA_G_hgc_src;
            VGA_B_hgc_ps <= VGA_B_hgc_src;
            VGA_HS_hgc_ps <= VGA_HS_hgc_src;
            VGA_VS_hgc_ps <= VGA_VS_hgc_src;
            VGA_DE_hgc_ps <= VGA_DE_hgc_src;
            LHBL_hgc_ps <= LHBL_hgc_src;
            credits_vb_hgc_ps <= credits_vb_hgc_src;
        end
    end

    always @(posedge clk_video_out_ps or posedge video_retime_reset_local)
    begin
        if (video_retime_reset_local)
        begin
            VGA_R_hgc_56 <= 8'd0;
            VGA_G_hgc_56 <= 8'd0;
            VGA_B_hgc_56 <= 8'd0;
            VGA_HS_hgc_56 <= 1'b0;
            VGA_VS_hgc_56 <= 1'b0;
            VGA_DE_hgc_56 <= 1'b0;
            LHBL_hgc_56 <= 1'b1;
            credits_vb_hgc_56 <= 1'b1;
            CE_PIXEL_hgc_hdmi <= 1'b0;
        end
        else
        begin
            CE_PIXEL_hgc_hdmi <= CE_PIXEL_hgc_ps;
            if (CE_PIXEL_hgc_ps)
            begin
                VGA_R_hgc_56 <= VGA_R_hgc_ps;
                VGA_G_hgc_56 <= VGA_G_hgc_ps;
                VGA_B_hgc_56 <= VGA_B_hgc_ps;
                VGA_HS_hgc_56 <= VGA_HS_hgc_ps;
                VGA_VS_hgc_56 <= VGA_VS_hgc_ps;
                VGA_DE_hgc_56 <= VGA_DE_hgc_ps;
                LHBL_hgc_56 <= LHBL_hgc_ps;
                credits_vb_hgc_56 <= credits_vb_hgc_ps;
            end
        end
    end

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] ar_video_out_meta = 2'b00;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] ar_video_out_ff = 2'b00;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg swap_video_out_meta = 1'b0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg swap_video_out_ff = 1'b0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg border_video_out_meta = 1'b0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg border_video_out_ff = 1'b0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] scale_video_out_meta = 2'b00;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] scale_video_out_ff = 2'b00;

    // Aspect ratio and adapter selection are static controls. Synchronize them
    // into the final video domain instead of timing them against PLL phase.
    always @(posedge clk_video_out_ps)
    begin
        ar_video_out_meta     <= ar;
        ar_video_out_ff       <= ar_video_out_meta;
        swap_video_out_meta   <= swap_video_eff;
        swap_video_out_ff     <= swap_video_out_meta;
        border_video_out_meta <= border_video_ff;
        border_video_out_ff   <= border_video_out_meta;
        scale_video_out_meta  <= scale_video_ff;
        scale_video_out_ff    <= scale_video_out_meta;
        VIDEO_ARX             <= (!ar_video_out_ff) ? 13'd4 : {11'd0, ar_video_out_ff - 1'd1};
        VIDEO_ARY             <= (!ar_video_out_ff) ? 13'd3 : 13'd0;
    end

    // The scanline selection drives the scanlines block, which runs on the
    // final video clock, so take it from the synchronized copy.
    assign VGA_SL = {scale_video_out_ff==3, scale_video_out_ff==2};

    assign VGA_R_AUX  =  swap_video_out_ff ? VGA_R_hgc_56   : VGA_R_cga_hdmi;
    assign VGA_G_AUX  =  swap_video_out_ff ? VGA_G_hgc_56   : VGA_G_cga_hdmi;
    assign VGA_B_AUX  =  swap_video_out_ff ? VGA_B_hgc_56   : VGA_B_cga_hdmi;
    assign VGA_HS =  swap_video_out_ff ? VGA_HS_hgc_56 : VGA_HS_cga_hdmi;
    assign VGA_VS =  swap_video_out_ff ? VGA_VS_hgc_56 : VGA_VS_cga_hdmi;
    assign gamma_bus =  swap_video_eff ? gamma_bus_hgc : gamma_bus_cga;
    assign CE_PIXEL  =  swap_video_out_ff ? CE_PIXEL_hgc_hdmi : CE_PIXEL_cga_hdmi;
    assign CE_PIXEL_CREDITS = swap_video_out_ff ? CE_PIXEL_hgc_hdmi : CE_PIXEL_cga_hdmi;
    wire credits_hb = swap_video_out_ff ? LHBL_hgc_56 : LHBL_cga_hdmi;
    wire credits_vb = swap_video_out_ff ? credits_vb_hgc_56 : LVBL_cga_hdmi;
    wire credits_border = swap_video_out_ff ? 1'b0 : border_video_out_ff;
    jtframe_credits #(
        .PAGES  (4),
        .COLW   (8),
        .BLKPOL (1),
        .BORDER_X (64)      // left margin of the CGA border window
    ) u_credits(
        .rst        ( video_retime_reset_local ),
        .clk        ( clk_video_out_ps ),
        .pxl_cen    ( CE_PIXEL_CREDITS ),

        // input image
        .HB         ( credits_hb  ),
        .VB         ( credits_vb ),
        .rgb_in     ( { VGA_R_AUX, VGA_G_AUX, VGA_B_AUX } ),
        .rotate     ( 2'd0  ),
        .toggle     ( 1'b0  ),
        .fast_scroll( 1'b0  ),
        .border     ( credits_border ),

        .vram_din   ( 8'h0  ),
        .vram_dout  (       ),
        .vram_addr  ( 8'h0  ),
        .vram_we    ( 1'b0  ),
        .vram_ctrl  ( 3'b0  ),
        .enable     ( video_credits_show ),

        // output image
        .HB_out     ( pre2x_LHBL      ),
        .VB_out     ( pre2x_LVBL      ),
        .rgb_out    ( {VGA_R, VGA_G, VGA_B } )
    );

    // The credits block registers RGB once on CE_PIXEL, even while its overlay
    // is disabled. Register the already-processed DE on that same event; using
    // the selected CGA/HGC DE directly opens the active window one pixel before
    // the corresponding RGB output sample and clips the last pixel instead.
    reg VGA_DE_credits = 1'b0;
    wire VGA_DE_selected = swap_video_out_ff ? VGA_DE_hgc_56 : VGA_DE_cga_hdmi;
    always @(posedge clk_video_out_ps or posedge video_retime_reset_local) begin
        if (video_retime_reset_local)
            VGA_DE_credits <= 1'b0;
        else if (CE_PIXEL_CREDITS)
            VGA_DE_credits <= VGA_DE_selected;
    end

    assign VGA_DE = VGA_DE_credits;

endmodule
