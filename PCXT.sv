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
// IBM PCjr: SYSTEM_VARIANT_PCJR names the core, ROM_VARIANT_PCJR / ROM_IS_PCJR
// say that the main BIOS is the PCjr one (slot 4), ENABLE_PCJR builds the PCjr
// machine (gate array, IR keyboard, IRQ5, NMI) into the video and chipset.
`ifndef SYSTEM_VARIANT_PCJR
`define SYSTEM_VARIANT_PCJR 0
`endif
`ifndef ROM_VARIANT_PCJR
`define ROM_VARIANT_PCJR `SYSTEM_VARIANT_PCJR
`endif
`ifndef ROM_IS_PCJR
`define ROM_IS_PCJR `ROM_VARIANT_PCJR
`endif
`ifndef ENABLE_PCJR
`define ENABLE_PCJR 0
`endif
`ifndef ENABLE_MIDI
`define ENABLE_MIDI 1
`endif
// Video cards built into this image. ENABLE_EGA adds the EGA/VGA 13h card next
// to the CGA/HGC pair; with ENABLE_CGA and ENABLE_HGC both 0 it is the only
// card. LAYOUT_EGA selects the status-bit layout of the menu (the EGA core's);
// without it the menu is the CGA core's, bit for bit.
`ifndef ENABLE_EGA
`define ENABLE_EGA 0
`endif
`ifndef ENABLE_VGA13
`define ENABLE_VGA13 1
`endif
`ifndef ENABLE_SB
`define ENABLE_SB 0
`endif
`ifndef ENABLE_UMB
`define ENABLE_UMB 0
`endif
// The name the core shows in the OSD, which also names its saved configuration.
// The profile sets it; without one it follows the machine. Every PCXT build is
// called "PCXT", whatever its video cards.
// Any padding of the shorter name sits in front of it, ahead of the string.
`ifndef CORE_NAME
`define CORE_NAME (`SYSTEM_VARIANT_PCJR ? "PCjr" : (`SYSTEM_VARIANT_TANDY ? "Tandy1000" : "PCXT"))
`endif
`ifndef CONF_STR_SYSTEM
`define CONF_STR_SYSTEM (`ENABLE_MIDI ? {`CORE_NAME, ";UART115200:115200,MIDI;"} : {`CORE_NAME, ";UART115200:115200;"})
`endif
// The machine is chosen in the OSD, PCXT or Tandy 1000, and applied at reset
// (LAYOUT_EGA menu only). It needs the Tandy video, keyboard and sound built in
// and a PCXT build otherwise (see scripts/config_check.tcl).
`ifndef ENABLE_MODEL_TANDY
`define ENABLE_MODEL_TANDY 0
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
    //
    // The menu has two layouts of the status vector, chosen at build time:
    //  * default: the CGA core's, except for the four options listed below;
    //  * LAYOUT_EGA: the options that exist only on the CGA/Hercules card are
    //    moved to bits 71..79:
    //      71 composite   72 border   73 border CRT offsets   74 frame stacking
    //      75 first video 76 CGA off  77 Hercules off         78 video card
    //      79 A000 UMB off
    //    The card itself is chosen with status[78] and is applied at reset.
    //    Both layouts save to the same PCXT.CFG, so no bit may mean one thing
    //    in one layout and another in the other (the EGA monitor switches
    //    would read the CGA/Hercules graphics bits), and no two options may
    //    share a bit within a layout. The options of the EGA layout that have
    //    no counterpart at the same bit in the CGA layout sit above 79:
    //      81:80 monitor  82 UMB off  83 VGA 13h+ TV 60 Hz  85:84 audio 220h
    //      86 swap joysticks  87 Tandy sound  88 MPU-401 off
    //      96 machine (PCXT / Tandy 1000), ENABLE_MODEL_TANDY builds
    //      91:89 VSync width  94:92 HSync width
    //    The CGA layout moved four options off the bits MT32-pi uses (3:4 ROM,
    //    13 off, 40 hanging-notes reset, 41 mode), where they sat on top of it:
    //      66 first video  68:67 EMS frame  69 A000 UMB off  95 composite
    // Every option that XTEGACTL can override goes through xtegactl_resolve
    // below, so the rest of the core only ever sees the eff_* values.

	`include "build_id.v"

`ifdef LAYOUT_EGA
    localparam bit L_EGA = 1'b1;
`else
    localparam bit L_EGA = 1'b0;
`endif
    localparam bit HAS_EGA     = (`ENABLE_EGA != 0);
    localparam bit HAS_CGA_HGC = ((`ENABLE_CGA != 0) || (`ENABLE_HGC != 0));
    // The card is selectable at run time only when both families are built
    localparam bit CARD_SELECTABLE = HAS_EGA && HAS_CGA_HGC;
    // The machine (PCXT, Tandy 1000 or, if built, IBM PCjr) is chosen in the OSD
    localparam bit HAS_MODEL = (`ENABLE_MODEL_TANDY != 0);
    localparam bit HAS_PCJR_MODEL = HAS_MODEL && (`ENABLE_PCJR != 0);
    localparam bit HAS_PCJR = (`ENABLE_PCJR != 0);

    // With the machine selectable, the entries that belong to one of the two are
    // shown only for it: hA PCXT, hB Tandy 1000, hE PCjr (see status_menumask).
    localparam CONF_STR_ROM = HAS_MODEL
        ? (HAS_PCJR_MODEL ? "hAP1FC0,ROM,PCXT BIOS:;hBP1FC1,ROM,Tandy BIOS:;hEP1FC4,ROM,PCjr BIOS:;"
                          : "hAP1FC0,ROM,PCXT BIOS:;hBP1FC1,ROM,Tandy BIOS:;")
        : (`ROM_IS_PCJR ? "P1FC4,ROM,PCjr BIOS:;P1-;" : (`ROM_IS_TANDY ? "P1FC1,ROM,Tandy BIOS:;P1-;" : "P1FC0,ROM,PCXT BIOS:;"));
    // The PCjr has no EC00 ROM card: its two cartridge slots take that place
    // (h2 is "the machine is not a PCjr" in a build that chooses it)
    localparam CONF_STR_EC00 = HAS_PCJR_MODEL ? "h2P1FC2,ROM,EC00 BIOS:;hEP1FC5,JRC,PCjr Cartridge 1:;hEP1FC6,JRC,PCjr Cartridge 2:;"
                             : (HAS_PCJR ? "P1FC5,JRC,PCjr Cartridge 1:;P1FC6,JRC,PCjr Cartridge 2:;" : "P1FC2,ROM,EC00 BIOS:;");
    // PCjr RAM (applied at reset) and the tape sound
    localparam CONF_STR_PCJR_RAM = HAS_PCJR_MODEL ? "hEP1O[101:98],PCjr RAM,128K,192K,256K,320K,384K,448K,512K,576K,640K;"
                                 : (HAS_PCJR ? "P1O[101:98],PCjr RAM,128K,192K,256K,320K,384K,448K,512K,576K,640K;" : "");
    localparam CONF_STR_PCJR_TAPE = HAS_PCJR_MODEL ? "hEP2O[102],Tape sound,Disabled,Enabled;"
                                  : (HAS_PCJR ? "P2O[102],Tape sound,Disabled,Enabled;" : "");
    localparam CONF_STR_OPL2 = (`ENABLE_OPL2 ? "P2oAB,OPL2,Adlib 388h,SB FM 388h/228h, Disabled;" : "");
    localparam CONF_STR_EMS_EGA = (`ENABLE_EMS ? "P3O5,2MB EMS D000-DFFF,Enabled,Disabled;P3-;" : "");
    localparam CONF_STR_UMB = ((L_EGA && `ENABLE_UMB) ? "P3O[82],UMB C400-CFFF,Enabled,Disabled;P3-;" : "");

`ifdef LAYOUT_EGA
    // CGA/Hercules only items are hidden (h7) while the EGA card is selected
    // A Tandy 1000 has only the CGA with its Tandy modes: no card choice, no
    // Hercules (hA hides them, hD is "CGA/HGC card selected on a PCXT").
    localparam CONF_STR_MACHINE = HAS_PCJR_MODEL ? "P1O[97:96],Machine,IBM PCXT,Tandy 1000,IBM PCjr;P1-;"
                                : (HAS_MODEL ? "P1O[96],Machine,IBM PCXT,Tandy 1000;P1-;" : "");
    localparam CONF_STR_CARD = CARD_SELECTABLE
        ? (HAS_MODEL ? "hAP1O[78],PCXT Video,CGA/HGC,EGA/VGA;hAP1-;" : "P1O[78],PCXT Video,CGA/HGC,EGA/VGA;P1-;")
        : "";
    localparam CONF_STR_HGC = (`ENABLE_HGC && `ENABLE_CGA)
        ? (HAS_MODEL ? "hDP1O[76],PCXT CGA Graphics,Yes,No;hDP1O[77],PCXT Hercules Graphics,Yes,No;hDP1O[75],PCXT 1st Video,CGA,Hercules;hDP1-;"
                     : "h7P1O[76],PCXT CGA Graphics,Yes,No;h7P1O[77],PCXT Hercules Graphics,Yes,No;h7P1O[75],PCXT 1st Video,CGA,Hercules;h7P1-;")
        : "";
    // The EGA BIOS only matters when the EGA card is the one selected
    localparam CONF_STR_EGABIOS = (HAS_EGA ? "h8P1FC3,ROM,EGA BIOS:;" : "");
    // The Sound Blaster and the C/MS both live at 220h and collide on
    // 226h/227h, so when both are built it is one three-way choice.
    localparam CONF_STR_A220 =
        (`ENABLE_CMS && `ENABLE_SB) ? "P2O[85:84],Audio 220h,C/MS,Sound Blaster,Disabled;" :
        (`ENABLE_SB)                ? "P2O[85],Sound Blaster,Enabled,Disabled;"            :
        (`ENABLE_CMS)               ? "P2O[85],C/MS Audio,Enabled,Disabled;"               : "";
    // A Tandy 1000 always has its sound chip
    localparam CONF_STR_TANDY_AUDIO = `ENABLE_TANDY_AUDIO
        ? (HAS_MODEL ? "hAP2O[87],Tandy Sound,Disabled,Enabled;" : "P2O[87],Tandy Sound,Disabled,Enabled;")
        : "";
    localparam CONF_STR_VIDEO_CGA = (HAS_CGA_HGC ? "h7P2O[72],Border,No,Yes;h9P2O[73],Border CRT offsets,No,Yes;h7P2O[74],CRTC Frame Stacking,Native,Rebuilt;h7P2O[71],Composite video,Off,On;" : "");
    localparam CONF_STR_VIDEO_EGA = (HAS_EGA ? "h8P2O[83],VGA 13h+ CRT,Native 70Hz,TV 60Hz;" : "");
    localparam CONF_STR_MONITOR = (HAS_EGA ? "h8P3O[81:80],Monitor,5154/ECD,5153/CGA,5151/MDA;P3-;" : "");
    localparam CONF_STR_A000 = ((`ENABLE_A000_UMB && HAS_CGA_HGC) ? "h7P3O[79],A000 UMB,Enabled,Disabled;P3-;" : "");
    localparam CONF_STR_JOY_SWAP = "P3O[86],Swap Joysticks,No,Yes;";
    localparam CONF_STR_SB_IRQ = (`ENABLE_SB ? "P3O[70],Sound Blaster IRQ,5,7;" : "");
    localparam CONF_STR_MIDI = (`ENABLE_MIDI ? "P3O[88],MPU-401,Enabled,Disabled;P3-;P3O6,USER I/O,MIDI,COM2;P3-;h3P4,MT32-pi;h3P4-;h3P4OD,Use MT32-pi,Yes,No;h3P4-;h3P4o9,MT32-pi Mode,MT-32,General MIDI;h3P4O34,MT32-pi ROM,MT-32 v1,MT-32 v2,CM-32L,Reserved;h3P4oSU,MT32-pi SoundFont,#0,#1,#2,#3,#4,#5,#6,#7;h3P4-;h3P4r8,Reset Hanging Notes;h3P4-;" : "");
    localparam CONF_STR_VSYNC = "P2O[91:89],VSync Width,Auto,1,2,3,4,5,6,7;P2O[94:92],HSync Width,Auto,1,2,3,4,5,6,7;";
    localparam CONF_STR_CRT = "P2o23,350-line CRT,Native,480i 15 kHz,240p 15 kHz;";
    localparam CONF_STR_HALT_BIOS = (`ROM_IS_PCJR ? "h4-,HALTED: no PCjr BIOS selected;" : (`ROM_IS_TANDY ? "h4-,HALTED: no Tandy BIOS selected;" : "h4-,HALTED: no PCXT BIOS selected;"));
    localparam CONF_STR_INFO_BIOS = (`ROM_IS_PCJR ? "No PCjr BIOS selected\n" : (`ROM_IS_TANDY ? "No Tandy BIOS selected\n" : "No PCXT BIOS selected\n"));
    localparam CONF_STR_HALT = {
        CONF_STR_HALT_BIOS,
        (HAS_EGA ? "h5-,HALTED: no EGA BIOS selected;" : ""),
        (HAS_MODEL ? "hC-,HALTED: no Tandy BIOS selected;" : ""),
        (HAS_PCJR_MODEL ? "hF-,HALTED: no PCjr BIOS selected;" : "")
    };
    // The box is 32 columns wide; commas separate the messages, so none of
    // them may contain one.
    localparam CONF_STR_INFO = {
        "I,",
        CONF_STR_INFO_BIOS,
        "Machine halted\n",
        "OSD: System & BIOS,",
        (HAS_EGA ? "No EGA BIOS selected\nMachine halted\nOSD: System & BIOS," : ""),
        (HAS_MODEL ? "No Tandy BIOS selected\nMachine halted\nOSD: System & BIOS," : ""),
        (HAS_PCJR_MODEL ? "No PCjr BIOS selected\nMachine halted\nOSD: System & BIOS," : ""),
        "That setting is applied\n",
        "when the machine resets;"
    };
    // Number of the Tandy BIOS notice and of the "That setting is applied"
    // message in the "I," section
    localparam [7:0] TANDY_INFO_INDEX   = HAS_EGA ? 8'd3 : 8'd2;
    localparam [7:0] PCJR_INFO_INDEX    = TANDY_INFO_INDEX + 8'd1;
    localparam [7:0] PENDING_INFO_INDEX = TANDY_INFO_INDEX + (HAS_MODEL ? 8'd1 : 8'd0) + (HAS_PCJR_MODEL ? 8'd1 : 8'd0);
`else
    localparam CONF_STR_HGC = ((`ENABLE_HGC && `ENABLE_CGA) ? "P1oC,PCXT CGA Graphics,Yes,No;P1oD,PCXT Hercules Graphics,Yes,No;P1O[66],PCXT 1st Video,CGA,Hercules;P1-;" : "");
    localparam CONF_STR_A220 = (`ENABLE_CMS ? "P2OA,C/MS Audio,Enabled,Disabled;" : "");
    localparam CONF_STR_TANDY_AUDIO = (`ENABLE_TANDY_AUDIO ? "P2o23,Tandy Volume,1,2,3,4;" : "");
    localparam CONF_STR_VIDEO_CGA = "P2OT,Border,No,Yes;h5P2O[65],Border CRT offsets,No,Yes;P2O[64],CRTC Frame Stacking,Native,Rebuilt;P2O[95],Composite video,Off,On;";
    localparam CONF_STR_A000 = (`ENABLE_A000_UMB ? "P3O[69],A000 UMB,Enabled,Disabled;P3-;" : "");
    localparam CONF_STR_JOY_SWAP = "P3OS,Swap Joysticks,No,Yes;";
    localparam CONF_STR_MIDI = (`ENABLE_MIDI ? "P3O6,USER I/O,MIDI,COM2;P3-;h3P4,MT32-pi;h3P4-;h3P4OD,Use MT32-pi,Yes,No;h3P4-;h3P4o9,MT32-pi Mode,MT-32,General MIDI;h3P4O34,MT32-pi ROM,MT-32 v1,MT-32 v2,CM-32L,Reserved;h3P4oSU,MT32-pi SoundFont,#0,#1,#2,#3,#4,#5,#6,#7;h3P4-;h3P4r8,Reset Hanging Notes;h3P4-;" : "");
    localparam CONF_STR_VSYNC = "P2oMO,VSync Width,Auto,1,2,3,4,5,6,7;P2oPR,HSync Width,Auto,1,2,3,4,5,6,7;";
    // P2o23 occupies status[35:34].  It is shared with Tandy Volume in the
    // optional Tandy-audio build, so keep the CRT converter out of that
    // mutually exclusive configuration rather than aliasing two controls.
    localparam CONF_STR_CRT = (`ENABLE_TANDY_AUDIO ? "" : "P2o23,350-line CRT,Native,480i 15 kHz,240p 15 kHz;");
    // This line is shown at the top of the menu while the required PCXT BIOS
    // is absent, so the splash hold has an actionable explanation.
    localparam CONF_STR_HALT = (`ROM_IS_PCJR ? "h4-,HALTED: no PCjr BIOS selected;" : (`ROM_IS_TANDY ? "h4-,HALTED: no Tandy BIOS selected;" : "h4-,HALTED: no PCXT BIOS selected;"));
    localparam CONF_STR_INFO_BIOS = (`ROM_IS_PCJR ? "No PCjr BIOS selected\n" : (`ROM_IS_TANDY ? "No Tandy BIOS selected\n" : "No PCXT BIOS selected\n"));
    localparam CONF_STR_INFO = {
        "I,",
        CONF_STR_INFO_BIOS,
        "Machine halted\n",
        "OSD: System & BIOS;"
    };
    localparam [7:0] PENDING_INFO_INDEX = 8'd2;
    // The CGA layout cannot choose the machine; the index is never used
    localparam [7:0] TANDY_INFO_INDEX   = 8'd3;
    localparam [7:0] PCJR_INFO_INDEX    = 8'd4;
`endif

    localparam CONF_STR_EMS_CGA = (`ENABLE_EMS ? "P3OB,Lo-tech 2MB EMS,Enabled,Disabled;P3O[68:67],EMS Frame,C000,D000,E000;P3-;" : "");
    localparam CONF_STR_EMS = L_EGA ? CONF_STR_EMS_EGA : CONF_STR_EMS_CGA;

    // Quartus 17 mis-sizes a concatenation that contains a bare "" localparam:
    // $size and the bits disagree, so hps_io's STRLEN no longer matches the
    // string, the menu is read out of step and the core never starts (no
    // BIOS is requested). The EGA-layout-only items are therefore left out of
    // the CGA layout with the preprocessor instead of being defined as "".
    // Empty arms of ?: are fine: they are padded to the width of the other arm.
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
`ifdef LAYOUT_EGA
        CONF_STR_MACHINE,
        CONF_STR_CARD,
`endif
        CONF_STR_HGC,
        "P1O7,Boot Splash Screen,Yes,No;",
        "P1oV,CPU Type,8088,8086;",
        "P1oL,Fake 286 FLAGS,Off,On;",
        "P1-;",
        CONF_STR_ROM,
        CONF_STR_EC00,
        CONF_STR_PCJR_RAM,
`ifdef LAYOUT_EGA
        CONF_STR_EGABIOS,
`endif
        "P1-;",
        "P1OUV,BIOS Writable,None,EC00,Main,All;",
        "P1-;",
        "P2,Audio & Video;",
        "P2-;",
        CONF_STR_A220,
        CONF_STR_OPL2,
        CONF_STR_TANDY_AUDIO,
        CONF_STR_PCJR_TAPE,
        "P2o01,Speaker Volume,1,2,3,4;",
        "P2o45,Audio Boost,No,2x,4x;",
        "P2o67,Stereo Mix,none,25%,50%,100%;",
        "P2-;",
        "d6P2oEH,CRT H offset,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15;",
        "d6P2oIK,CRT V offset,0,1,2,3,4,5,6,7;",
        CONF_STR_VSYNC,
        "P2-;",
        "P2O12,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
        "P2O89,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
        CONF_STR_VIDEO_CGA,
        "P2OEG,Display,Full Color,Green,Amber,B&W,Red,Blue,Fuchsia,Purple;",
`ifdef LAYOUT_EGA
        CONF_STR_VIDEO_EGA,
`endif
        CONF_STR_CRT,
        "P2-;",
        "P3,Hardware;",
        "P3-;",
`ifdef LAYOUT_EGA
        CONF_STR_MONITOR,
`endif
        CONF_STR_EMS,
        CONF_STR_UMB,
        CONF_STR_A000,
        "P3ONO,Joystick 1, Analog, Digital, Disabled;",
        "P3OPQ,Joystick 2, Analog, Digital, Disabled;",
        "P3OR,Sync Joy to CPU Speed,No,Yes;",
        CONF_STR_JOY_SWAP,
`ifdef LAYOUT_EGA
        CONF_STR_SB_IRQ,
`endif
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

    // Video card chosen at reset. card_sel_ega is what the menu asks for (it
    // is pending until the next reset); ega_active is the card that is in use.
    // A Tandy 1000 has only the CGA.
    // status[97:96]: 0 PCXT, 1 Tandy 1000, 2 PCjr. Both Tandy and PCjr are of the
    // Tandy video family (tandy_sel_osd / tandy_applied); the PCjr is the one with
    // pcjr_sel_osd / pcjr_applied.
    wire        pcjr_sel_osd  = HAS_PCJR_MODEL ? status[97] : 1'b0;
    wire        tandy_sel_osd = HAS_MODEL ? (status[96] | pcjr_sel_osd) : 1'b0;
    reg         tandy_applied_r = 1'b0;     // the machine in use, latched at reset
    reg         pcjr_applied_r  = 1'b0;
    wire        tandy_applied = HAS_MODEL ? tandy_applied_r : 1'b0;
    wire        pcjr_applied  = HAS_PCJR_MODEL ? pcjr_applied_r : 1'b0;
    // Whether the machine is a Tandy 1000: fixed by the build or chosen at reset.
    // It drives the Tandy video, keyboard and BIOS slot wherever they are built.
    wire        tandy_video_mode = (`ENABLE_TANDY_VIDEO != 0) ? (HAS_MODEL ? tandy_applied : 1'b1) : 1'b0;
    // Whether the machine is a PCjr (a member of the Tandy video family)
    wire        pcjr_video_mode = (`ENABLE_PCJR != 0) ? (HAS_MODEL ? pcjr_applied : (`ROM_IS_PCJR != 0)) : 1'b0;
    // PCjr RAM: 128 KiB plus 64 KiB per step, taken at reset (the menu has nine
    // sizes; a larger value is the largest)
    reg   [3:0] pcjr_ram_size_r = 4'd8;
    wire  [3:0] pcjr_ram_size = HAS_PCJR ? pcjr_ram_size_r : 4'd8;
    wire        card_sel_ega = HAS_EGA ? (CARD_SELECTABLE ? (status[78] & ~tandy_sel_osd) : 1'b1) : 1'b0;
    wire        ega_active;
    wire        ega_active_vid;
    wire [5:0]  EGA_R, EGA_G, EGA_B;
    wire        EGA_HSYNC, EGA_VSYNC, EGA_HBlank, EGA_VBlank, EGA_VBlank_border;
    wire        EGA_std_hsyncwidth, EGA_de_o;
    wire        ega_dot_toggle;
    wire        ega_dot_clock_sel;
    wire        ega_scandouble_active;
    wire        ega_vmode_toggle;
    wire        ega_mode350;
    wire [11:0] ega_active_dots;
    wire [9:0]  ega_active_lines;
    wire        vga_mode13_active_video;
    wire        vga_mode13_pixel_toggle;
    wire        vga_mode13_wide_clock;

    // Pending options. Everything that depends on the layout is gathered here.
    wire        composite_osd   = L_EGA ? status[71] : status[95];
    wire        border_osd      = L_EGA ? status[72] : status[29];
    wire        border_crt_osd  = L_EGA ? status[73] : status[65];
    wire        frame_stack_osd = L_EGA ? status[74] : status[64];
    wire        hgc_first_osd   = L_EGA ? status[75] : status[66];
    wire        cga_absent_osd  = L_EGA ? status[76] : status[44];
    wire        hgc_absent_osd  = L_EGA ? status[77] : status[45];
    wire        a000_off_osd    = L_EGA ? status[79] : status[69];
    // The EGA card has no use for Native/TV 60 Hz outside Mode 13h and no
    // physical-monitor switches in the CGA layout, where they stay at zero.
    wire        vga_mode13_native_osd = L_EGA ? ~status[83] : 1'b1;
    // Status bits 81:80 are the pending physical-monitor switch selection.
    // ega_monitor_profile_applied is only updated while the machine is held
    // in reset, just as a real EGA card samples its switches during POST.
    wire  [1:0] ega_monitor_profile_osd = L_EGA ? status[81:80] : 2'b00;
    wire  [1:0] ega_monitor_profile_applied;

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
    wire [1:0]  id_video_card;
    wire        id_vga13_active;

    // XTEGACTL. The register file is decoded down in the chipset; what the
    // fields mean is resolved here, where the menu status lives. Every field
    // reads zero as "leave it to the OSD", so with nothing written the machine
    // behaves exactly as the menu says.
    wire [7:0]  xtegactl_cpu, xtegactl_exp, xtegactl_vid, xtegactl_inp, xtegactl_midi, xtegactl_exp2;
    wire [7:0]  xtegactl_crt, xtegactl_sync;
    wire [39:0] xtegactl_status_effective;
    wire [17:0] xtegactl_status_osd_match;
    wire [1:0]  eff_speed;
    wire        eff_fake286;
    wire [1:0]  eff_opl2;
    wire        eff_cms, eff_ems, eff_umb, eff_vga13;
    wire        eff_sb;
    wire  [2:0] eff_sb_irq;
    wire [3:0]  eff_crt_h;
    wire [2:0]  eff_crt_v;
    wire [2:0]  eff_vsync_w, eff_hsync_w;
    wire        eff_joy1_digital, eff_joy1_disable;
    wire        eff_joy2_digital, eff_joy2_disable;
    wire        eff_joy_sync, eff_joy_swap, eff_mt32_gm, eff_tandy, eff_mpu401;

    // Audio at 220h in the EGA layout. With both cards built this is one
    // three-way field in status[85:84]: 0 = C/MS, 1 = Sound Blaster, 2 =
    // neither. With only one built, bit 85 stays the plain Enabled/Disabled
    // and bit 84 is free. They are never both high, which 226h/227h requires.
    wire       a220_three_way = (`ENABLE_CMS && `ENABLE_SB) ? 1'b1 : 1'b0;
    wire [1:0] a220_sel       = status[85:84];
    wire       a220_cms       = `ENABLE_CMS
                             ? (a220_three_way ? (a220_sel == 2'd0) : ~status[85])
                             : 1'b0;
    wire       a220_sb        = `ENABLE_SB
                             ? (a220_three_way ? (a220_sel == 2'd1) : ~status[85])
                             : 1'b0;
    wire [2:0] sb_irq_osd     = status[70] ? 3'd7 : 3'd5;
    wire       sb_irq7        = (eff_sb_irq == 3'd7);

    xtegactl_resolve xtegactl_apply (
        .reg_cpu          (xtegactl_cpu),
        .reg_exp          (xtegactl_exp),
        .reg_vid          (xtegactl_vid),
        .reg_inp          (xtegactl_inp),
        .reg_midi         (xtegactl_midi),
        .reg_exp2         (xtegactl_exp2),
        .osd_speed        (status[18:17]),
        .osd_fake286      (fake_286_flags_osd),
        .osd_opl2         (status[43:42]),
        .osd_cms          (L_EGA ? a220_cms : ~status[10]),
        .osd_sb           (L_EGA ? a220_sb : 1'b0),
        .osd_sb_irq       (L_EGA ? sb_irq_osd : 3'd5),
        .build_sb         (`ENABLE_SB ? 1'b1 : 1'b0),
        .reg_crt          (xtegactl_crt),
        .reg_sync         (xtegactl_sync),
        .osd_crt_h        (status[49:46]),
        .osd_crt_v        (status[52:50]),
        .osd_vsync_w      (L_EGA ? status[91:89] : status[56:54]),
        .osd_hsync_w      (L_EGA ? status[94:92] : status[59:57]),
        .osd_ems          (L_EGA ? ~status[5] : ~status[11]),
        .osd_umb          (L_EGA ? ~status[82] : 1'b0),
        .osd_joy1_digital (status[23]),
        .osd_joy1_disable (status[24]),
        .osd_joy2_digital (status[25]),
        .osd_joy2_disable (status[26]),
        .osd_joy_sync     (status[27]),
        .osd_joy_swap     (L_EGA ? status[86] : status[28]),
        .osd_mt32_gm      (status[41]),
        .osd_tandy        (L_EGA ? (status[87] | tandy_video_mode) : 1'b1),
        .osd_mpu401       (L_EGA ? ~status[88] : 1'b1),
        .build_tandy      (`ENABLE_TANDY_AUDIO ? 1'b1 : 1'b0),
        .eff_speed        (eff_speed),
        .eff_fake286      (eff_fake286),
        .eff_opl2         (eff_opl2),
        .eff_cms          (eff_cms),
        .eff_sb           (eff_sb),
        .eff_sb_irq       (eff_sb_irq),
        .eff_ems          (eff_ems),
        .eff_umb          (eff_umb),
        .eff_vga13        (eff_vga13),
        .eff_joy1_digital (eff_joy1_digital),
        .eff_joy1_disable (eff_joy1_disable),
        .eff_joy2_digital (eff_joy2_digital),
        .eff_joy2_disable (eff_joy2_disable),
        .eff_joy_sync     (eff_joy_sync),
        .eff_joy_swap     (eff_joy_swap),
        .eff_mt32_gm      (eff_mt32_gm),
        .eff_tandy        (eff_tandy),
        .eff_mpu401       (eff_mpu401),
        .eff_crt_h        (eff_crt_h),
        .eff_crt_v        (eff_crt_v),
        .eff_vsync_w      (eff_vsync_w),
        .eff_hsync_w      (eff_hsync_w),
        .status_effective (xtegactl_status_effective),
        .status_osd_match (xtegactl_status_osd_match)
    );

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
    // Bit order set by tandy_pcjr_joy: P1 type, P1 disable, P2 type, P2
    // disable, turbo sync.
    wire [4:0]  joy_opts = {eff_joy_sync, eff_joy2_disable, eff_joy2_digital,
                            eff_joy1_disable, eff_joy1_digital};

    // Border only exists on the CGA card. border_menu follows the pending
    // card, so the menu already shows the right entries before the reset;
    // border follows the card in use.
    wire border_menu = (border_osd | xtctl[1]) & ~card_sel_ega;
    wire composite = composite_osd | xtctl[0];
    wire [1:0] scale = status[2:1];
    wire [2:0] screen_mode = status[16:14];
    wire [1:0] ar = status[9:8];
    wire border = (border_osd | xtctl[1]) & ~ega_active;
    wire a000h = `ENABLE_A000_UMB ? (~a000_off_osd & ~xtctl[6]) : 1'b0;
    // A zero XTEGACTL field defers to the OSD; a non-zero value is a
    // per-program override.
    wire [2:0] vsync_width_osd = eff_vsync_w;    // 0=Auto (use register), 1-7=override
    wire [2:0] hsync_width_osd = eff_hsync_w;    // 0=Auto, 1-7=fixed width (Nx16 pixel clocks)
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
    // CGA layout: bit0=status[5]; bit3 exposes the MT32-pi options; bit4
    // exposes the halted/missing-PCXT-BIOS status line at the top of the menu;
    // bit5 is set while Border is on (it shows Border CRT offsets); bit6 is
    // set while the OSD CRT H/V offsets act on the picture: always, except
    // with Border on and Border CRT offsets off, where the window ignores them.
    //
    // EGA layout: bits 2:0 have no h0/h1/h2 entries; bit3 exposes MT32-pi,
    // gated on the MPU-401 being enabled as well; bits 5:4 reveal the two
    // "halted, no BIOS" lines; bit 6 as above; bit 7 is set while the CGA/HGC
    // card is selected and bit 8 while the EGA card is; bit 9 is set when the
    // CGA card is selected with Border on.
    wire        crt_offsets_act = ~(L_EGA ? border_menu : border) | border_crt_osd;
    //   machine selectable (ENABLE_MODEL_TANDY): bit 10 PCXT chosen, 11 Tandy 1000
    //   chosen, 12 the Tandy BIOS is absent, 13 PCXT chosen with the CGA/HGC card.
    //   with the PCjr built in as well: bit 11 is the Tandy 1000 only, 14 the PCjr
    //   chosen, 15 the PCjr BIOS is absent, 2 the machine is not a PCjr.
    wire [15:0] status_menumask = L_EGA
        ? {bios_missing_pcjr, pcjr_sel_osd, ~card_sel_ega & ~tandy_sel_osd, bios_missing_tandy,
           tandy_sel_osd & ~pcjr_sel_osd, ~tandy_sel_osd,
           border_menu, card_sel_ega, ~card_sel_ega, crt_offsets_act,
           bios_missing_ega, bios_missing_pcxt,
           ((`ENABLE_MIDI != 0) && mt32_available && eff_mpu401), ~pcjr_sel_osd, 2'b11}
        : {9'd0, crt_offsets_act, border, bios_missing_pcxt,
           ((`ENABLE_MIDI != 0) && mt32_available),
           2'b00, status[5]};

    wire VGA_VBlank_border;
    wire VGA_HSYNC_REF, VGA_VSYNC_REF;
    wire std_hsyncwidth;
    wire pause_core;
    wire swap_video;
    wire swap_video_requested = ega_active ? 1'b0 :
                                (`ENABLE_HGC ? (`ENABLE_CGA ? (swap_video & ~tandy_video_mode) : (`ENABLE_TANDY_VIDEO ? 1'b0 : 1'b1)) : 1'b0);

    always @(posedge clk_57_272)
    begin
        scale_video_meta        <= scale;
        scale_video_ff          <= scale_video_meta;
        screen_mode_video_meta  <= screen_mode;
        screen_mode_video_ff    <= screen_mode_video_meta;
        border_video_meta       <= border;
        border_video_ff         <= border_video_meta;
        cga_hw                  <= `ENABLE_CGA ? (~cga_absent_osd | tandy_video_mode) : 1'b0;
        hercules_hw             <= `ENABLE_HGC ? (`ENABLE_CGA ? (~hgc_absent_osd & ~tandy_video_mode) : 1'b1) : 1'b0;
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
		.new_vmode(ega_vmode_toggle),

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

    // PCjr: a cartridge is seen by the BIOS at power on only, so the machine
    // restarts when one has been loaded (about 2 ms of reset)
    wire        cart_download = pcjr_video_mode && ioctl_download && ((ioctl_index[5:0] == 6'd5) || (ioctl_index[5:0] == 6'd6));
    logic       cart_download_d = 1'b0;
    logic [17:0] cart_reset_count = 18'd0;
    always @(posedge clk_chipset) begin
        cart_download_d <= cart_download;
        if (cart_download_d && !cart_download)
            cart_reset_count <= 18'h3FFFF;
        else if (cart_reset_count != 18'd0)
            cart_reset_count <= cart_reset_count - 18'd1;
    end
    wire cart_reset_hold = (cart_reset_count != 18'd0);

    wire reset_wire = RESET | status[0] | buttons[1] | !pll_locked | !pll_system_locked  | splashscreen | splash_reset_hold | splash_pending | cart_reset_hold;
    wire video_retime_reset = RESET | status[0] | buttons[1] | !pll_locked | !pll_system_locked | splash_pending;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] video_retime_reset_sync = 2'b11;
    wire video_retime_reset_local = video_retime_reset_sync[1];

    // The shared 350-line framebuffer (EGA card and HGC) runs on the 57.272 MHz
    // clock; same idea, release only on its own clock.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] video_retime_57_sync = 2'b11;
    wire video_retime_reset_57 = video_retime_57_sync[1];

    // The output retime registers assert reset immediately, but release it
    // only on their own phase-shifted video clock.
    always_ff @(posedge clk_video_out_ps or posedge video_retime_reset) begin
        if (video_retime_reset)
            video_retime_reset_sync <= 2'b11;
        else
            video_retime_reset_sync <= {video_retime_reset_sync[0], 1'b0};
    end

    always_ff @(posedge clk_57_272 or posedge video_retime_reset) begin
        if (video_retime_reset)
            video_retime_57_sync <= 2'b11;
        else
            video_retime_57_sync <= {video_retime_57_sync[0], 1'b0};
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
    wire   [1:0] clk_select_next = ((xtctl[3:2] == 2'b00) && ~xtctl[7]) ? eff_speed :
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

    // Track the OSD selection throughout the stretched reset interval so the
    // final stable value is ready before the CPU starts executing the BIOS.
    // Changes made while the machine is running remain pending until reset.
    ega_monitor_profile_latch monitor_profile_latch (
        .clock        (clk_chipset),
        .reset_active (reset),
        .selected     (ega_monitor_profile_osd),
        .applied      (ega_monitor_profile_applied)
    );

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
        fake_286_flags_meta <= {fake_286_flags_meta[0], eff_fake286};

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

    reg hgc_mode = 0;

    // hgc_mode is sampled while reset is active. Keeping the data-dependent
    // load synchronous avoids synthesis turning reset into a latch clock.
    always @(negedge clk_chipset)
        if (reset)
            hgc_mode <= `ENABLE_HGC ? (`ENABLE_CGA ? (hgc_first_osd & ~tandy_sel_osd) : 1'b1) : 1'b0;

    // The machine is chosen the same way (and the video card follows from it)
    always @(negedge clk_chipset)
        if (reset) begin
            tandy_applied_r <= tandy_sel_osd;
            pcjr_applied_r  <= pcjr_sel_osd;
            pcjr_ram_size_r <= (status[101:98] > 4'd8) ? 4'd8 : status[101:98];
        end

    // The video card is chosen the same way: the menu entry is sampled while
    // reset is active and what it says then stays in force until the next
    // reset. With a single card built there is nothing to choose.
    reg ega_active_r = 1'b0;
    always @(negedge clk_chipset)
        if (reset)
            ega_active_r <= card_sel_ega;
    assign ega_active = HAS_EGA ? (HAS_CGA_HGC ? ega_active_r : 1'b1) : 1'b0;

    // The same, seen from the 57.272 MHz video clock. It only changes while
    // the machine is in reset and the video path is held in reset too.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] ega_active_vid_sync = 2'b00;
    always @(posedge clk_57_272)
        ega_active_vid_sync <= {ega_active_vid_sync[0], ega_active};
    assign ega_active_vid = HAS_EGA ? (HAS_CGA_HGC ? ega_active_vid_sync[1] : 1'b1) : 1'b0;

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

    // BIOS Writable: [2] C000 (EGA option ROM, the EGA card only), [1] F000
    // (main), [0] EC00.
    wire ega_bios_write_protect;
    wire ega_bios_write_complete;
    reg [2:0] bios_protect_flag = 3'b111;
    always @(posedge clk_chipset)
        bios_protect_flag <= {HAS_EGA ? ega_bios_write_protect : 1'b1, ~status[31:30]};

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
    wire        tandy_bios_write_complete;
    wire        pcjr_bios_write_complete;
    wire        ec00_loaded;
    wire [7:0]  cart1_seg, cart2_seg;
    wire [16:0] cart1_len, cart2_len;

    // The PCXT BIOS slot is offered unless the build is only a Tandy; the Tandy
    // one when the build is a Tandy or chooses the machine
    rom_loader #(.ROM_PCXT(!`ROM_IS_TANDY && !`ROM_IS_PCJR), .ROM_TANDY(`ROM_IS_TANDY || HAS_MODEL), .ROM_EGA(`ENABLE_EGA),
                 .ROM_PCJR((`ROM_IS_PCJR != 0) || HAS_PCJR_MODEL), .ROM_PCJR_CART(HAS_PCJR)) u_rom_loader
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
        .write_tandy        (tandy_bios_write_complete),
        .write_ega          (ega_bios_write_complete),
        .write_pcjr         (pcjr_bios_write_complete),
        .cart1_seg          (cart1_seg),
        .cart1_len          (cart1_len),
        .cart2_seg          (cart2_seg),
        .cart2_len          (cart2_len),
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
    // engines; the EGA/VGA card reads its planes
    // and the packed Mode 13h region through the frontend of the pc_common
    // library, which has its own engines and is the third client of vid_mux.
    // Everything here is in clk_sdram; the CGA (28.636 MHz) and HGC (57.27 MHz)
    // sequencers come from the same PLL and are sampled by the adapters.
    //
    //   LDR port: rom_loader (through its bridge) or ram_clear, which writes zeros
    //             over the video regions once the chip is initialised
    //   VID port: the CGA and HGC fetch engines and the EGA frontend, through
    //             vid_mux (only the ones that are built)
    //   snoop:    every write the arbiter captures (CPU or LDR), registered once
    //
    localparam logic [23:0] CGA_WORD_BASE = sdram_pkg::PHYS_CGA[24:1];
    localparam logic [23:0] HGC_WORD_BASE = sdram_pkg::PHYS_HGC[24:1];
    // The EGA planes (256 KiB) and the packed 13h region (64 KiB) are one
    // contiguous 320 KiB that ends where the CGA window starts.
    localparam logic [23:0] EGA_WORD_BASE  = 24'h400000;
    localparam logic [23:0] EGA_WORD_COUNT = 24'd163840;

    localparam bit E_CGA = (`ENABLE_CGA != 0);
    localparam bit E_HGC = (`ENABLE_HGC != 0);
    localparam bit E_EGA = HAS_EGA;

    wire        clr_busy, clr_req, clr_ack;
    wire [23:0] clr_addr;
    wire [1:0]  clr_len;
    wire [63:0] clr_wdata;
    wire [7:0]  clr_wbe;

    // The card is not known yet when the chip comes up, so with the EGA card
    // built its regions are cleared as well.
    localparam int CLR_NREG = E_EGA ? 3 : 2;
    localparam logic [71:0] CLR_BASES_ALL = {EGA_WORD_BASE, HGC_WORD_BASE, CGA_WORD_BASE};
    localparam logic [71:0] CLR_WORDS_ALL = {EGA_WORD_COUNT, 24'd32768, 24'd16384};   // 64 KiB, 32 KiB, 320 KiB

    ram_clear #(
        .NREG   (CLR_NREG),
        .BASES  (CLR_BASES_ALL[24*CLR_NREG-1:0]),
        .WORDS  (CLR_WORDS_ALL[24*CLR_NREG-1:0])
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

    // Tandy 1000 video memory: the CGA reads the block of system RAM
    // that port A0h chose, page by port 3DFh
    wire        tandy_vram_en;
    wire [2:0]  tandy_vram_block;
    wire [5:0]  tandy_vram_page;
    wire        tandy_16_gfx;
    wire        tandy_color_16;
    wire        pcjr_vram_32k;
    wire        nmi_to_cpu;
    wire        cassette_out, cassette_motor;

    // Engines
    wire        cga_vreq, cga_vack, cga_vrv, cga_vrl;
    wire [23:0] cga_vaddr;
    wire [1:0]  cga_vlen;
    wire [15:0] cga_vdl;

    wire        hgc_vreq, hgc_vack, hgc_vrv, hgc_vrl;
    wire [23:0] hgc_vaddr;
    wire [1:0]  hgc_vlen;
    wire [15:0] hgc_vdl;

    // The EGA frontend, as the chipset presents it
    wire        egaf_req, egaf_ack, egaf_rvalid, egaf_rlast;
    wire [23:0] egaf_addr;
    wire [1:0]  egaf_len;
    wire [15:0] egaf_deadline;

    wire        vid_req, vid_ack, vid_rvalid, vid_rlast;
    wire [23:0] vid_addr;
    wire [1:0]  vid_len;
    wire [15:0] vid_deadline;

    generate
    if (E_CGA) begin : g_cga_fetch
        wire        cga_req_v, cga_req_r, cga_rsp_p, cga_rsp_v, cga_rsp_pop;
        wire [23:0] cga_req_a, cga_rsp_a;
        wire [1:0]  cga_req_l;
        wire [15:0] cga_req_d;
        wire [63:0] cga_rsp_d;
        wire [15:0] cga_underrun, cga_mismatch, cga_late, cga_dropped;

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
            .tandy(tandy_vram_en), .tandy_block(tandy_vram_block),
            .tandy_crt_page(tandy_vram_page[2:0]), .tandy_wide(pcjr_video_mode ? pcjr_vram_32k : tandy_16_gfx),
            .vram_d(fx_cga_vram_d),
            .req_valid(cga_req_v), .req_addr(cga_req_a), .req_len(cga_req_l),
            .req_deadline(cga_req_d), .req_ready(cga_req_r),
            .rsp_pending(cga_rsp_p), .rsp_valid(cga_rsp_v), .rsp_data(cga_rsp_d),
            .rsp_addr(cga_rsp_a), .rsp_pop(cga_rsp_pop),
            .mismatch_count(cga_mismatch), .late_count(cga_late), .dropped_count(cga_dropped)
        );
    end
    else begin : g_no_cga_fetch
        assign cga_vreq    = 1'b0;
        assign cga_vaddr   = 24'd0;
        assign cga_vlen    = 2'd0;
        assign cga_vdl     = 16'd0;
        assign fx_cga_vram_d = 8'd0;
    end
    endgenerate

    generate
    if (E_HGC) begin : g_hgc_fetch
        wire        hgc_req_v, hgc_req_r, hgc_rsp_p, hgc_rsp_v, hgc_rsp_pop;
        wire [23:0] hgc_req_a, hgc_rsp_a;
        wire [1:0]  hgc_req_l;
        wire [15:0] hgc_req_d;
        wire [63:0] hgc_rsp_d;
        wire [15:0] hgc_underrun, hgc_mismatch, hgc_late, hgc_dropped;

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
    end
    else begin : g_no_hgc_fetch
        assign hgc_vreq    = 1'b0;
        assign hgc_vaddr   = 24'd0;
        assign hgc_vlen    = 2'd0;
        assign hgc_vdl     = 16'd0;
        assign fx_hgc_vram_d = 8'd0;
    end
    endgenerate

    // The clients of the video port, in the order CGA, HGC, EGA frontend,
    // whichever of them are built. One client goes straight through; two or
    // three share vid_mux. The acknowledge and the words that come back are
    // handed to the clients in the same positions.
    localparam int N_VID = (E_CGA ? 1 : 0) + (E_HGC ? 1 : 0) + (E_EGA ? 1 : 0);

    generate
    if (N_VID == 3) begin : g_vid_mux3
        wire [2:0] mx_ack, mx_rvalid, mx_rlast;
        vid_mux #(.N(3)) u_vid_mux
        (
            .clk(clk_sdram), .reset(vid_reset),
            .c_req({egaf_req, hgc_vreq, cga_vreq}), .c_addr({egaf_addr, hgc_vaddr, cga_vaddr}),
            .c_len({egaf_len, hgc_vlen, cga_vlen}), .c_deadline({egaf_deadline, hgc_vdl, cga_vdl}),
            .c_ack(mx_ack), .c_rvalid(mx_rvalid), .c_rlast(mx_rlast),
            .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
            .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast)
        );
        assign {egaf_ack, hgc_vack, cga_vack}       = mx_ack;
        assign {egaf_rvalid, hgc_vrv, cga_vrv}      = mx_rvalid;
        assign {egaf_rlast, hgc_vrl, cga_vrl}       = mx_rlast;
    end
    else if (N_VID == 2) begin : g_vid_mux2
        // CGA+HGC, CGA+EGA or HGC+EGA: the EGA frontend, when built, is second
        wire [1:0] mx_ack, mx_rvalid, mx_rlast;
        wire       first_req  = E_CGA ? cga_vreq : hgc_vreq;
        wire       second_req = E_EGA ? egaf_req : hgc_vreq;
        vid_mux #(.N(2)) u_vid_mux
        (
            .clk(clk_sdram), .reset(vid_reset),
            .c_req({second_req, first_req}),
            .c_addr({E_EGA ? egaf_addr : hgc_vaddr, E_CGA ? cga_vaddr : hgc_vaddr}),
            .c_len({E_EGA ? egaf_len : hgc_vlen, E_CGA ? cga_vlen : hgc_vlen}),
            .c_deadline({E_EGA ? egaf_deadline : hgc_vdl, E_CGA ? cga_vdl : hgc_vdl}),
            .c_ack(mx_ack), .c_rvalid(mx_rvalid), .c_rlast(mx_rlast),
            .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
            .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast)
        );
        assign cga_vack    = E_CGA ? mx_ack[0]    : 1'b0;
        assign cga_vrv     = E_CGA ? mx_rvalid[0] : 1'b0;
        assign cga_vrl     = E_CGA ? mx_rlast[0]  : 1'b0;
        assign hgc_vack    = E_HGC ? (E_CGA ? mx_ack[1]    : mx_ack[0])    : 1'b0;
        assign hgc_vrv     = E_HGC ? (E_CGA ? mx_rvalid[1] : mx_rvalid[0]) : 1'b0;
        assign hgc_vrl     = E_HGC ? (E_CGA ? mx_rlast[1]  : mx_rlast[0])  : 1'b0;
        assign egaf_ack    = E_EGA ? mx_ack[1]    : 1'b0;
        assign egaf_rvalid = E_EGA ? mx_rvalid[1] : 1'b0;
        assign egaf_rlast  = E_EGA ? mx_rlast[1]  : 1'b0;
    end
    else begin : g_vid_one
        assign vid_req      = E_CGA ? cga_vreq     : (E_HGC ? hgc_vreq     : egaf_req);
        assign vid_addr     = E_CGA ? cga_vaddr    : (E_HGC ? hgc_vaddr    : egaf_addr);
        assign vid_len      = E_CGA ? cga_vlen     : (E_HGC ? hgc_vlen     : egaf_len);
        assign vid_deadline = E_CGA ? cga_vdl      : (E_HGC ? hgc_vdl      : egaf_deadline);
        assign cga_vack     = vid_ack;
        assign cga_vrv      = vid_rvalid;
        assign cga_vrl      = vid_rlast;
        assign hgc_vack     = vid_ack;
        assign hgc_vrv      = vid_rvalid;
        assign hgc_vrl      = vid_rlast;
        assign egaf_ack     = vid_ack;
        assign egaf_rvalid  = vid_rvalid;
        assign egaf_rlast   = vid_rlast;
    end
    endgenerate

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
    // Each BIOS slot has its own flag: slot 0 PCXT, slot 1 Tandy 1000.
    wire pcxt_slot_download  = ioctl_download && (ioctl_index[5:0] == 6'd0);
    wire tandy_slot_download = ioctl_download && (ioctl_index[5:0] == 6'd1);
    wire pcjr_slot_download  = ioctl_download && (ioctl_index[5:0] == 6'd4);
    wire pcxt_slot_loaded, tandy_slot_loaded, pcjr_slot_loaded;

    rom_presence_latch pcxt_bios_presence (
        .clock              (clk_chipset),
        .reset              (reset_sdram),
        .sdram_initialized  (initilized_sdram),
        .download_active    (pcxt_slot_download),
        .write_complete     (pcxt_bios_write_complete),
        .loaded             (pcxt_slot_loaded)
    );

    rom_presence_latch pcjr_bios_presence (
        .clock              (clk_chipset),
        .reset              (reset_sdram),
        .sdram_initialized  (initilized_sdram),
        .download_active    (pcjr_slot_download),
        .write_complete     (pcjr_bios_write_complete),
        .loaded             (pcjr_slot_loaded)
    );

    rom_presence_latch tandy_bios_presence (
        .clock              (clk_chipset),
        .reset              (reset_sdram),
        .sdram_initialized  (initilized_sdram),
        .download_active    (tandy_slot_download),
        .write_complete     (tandy_bios_write_complete),
        .loaded             (tandy_slot_loaded)
    );

    // The main BIOS is the one of the machine: the Tandy one in a Tandy build,
    // the PCXT one in a PCXT build, and the chosen one when the build chooses.
    wire pcxt_bios_loaded = HAS_MODEL ? (pcjr_applied ? pcjr_slot_loaded : tandy_applied ? tandy_slot_loaded : pcxt_slot_loaded)
                                      : (`ROM_IS_PCJR ? pcjr_slot_loaded :
                                         `ROM_IS_TANDY ? tandy_slot_loaded : pcxt_slot_loaded);

    // The EGA option ROM (slot 3) is tracked the same way. Present, it is
    // write-protected and advertised to the XT BIOS as an adapter with its own
    // firmware; absent, the BIOS falls back to the CGA switch setting.
    wire       ega_bios_loaded;
    wire [1:0] ega_video_switches;
    wire       ega_bios_download_active = ioctl_download && (ioctl_index[5:0] == 6'd3);

    generate
    if (HAS_EGA) begin : g_ega_bios_presence
        ega_bios_loaded_latch ega_bios_presence (
            .clock              (clk_chipset),
            .reset              (reset_sdram),
            .sdram_initialized  (initilized_sdram),
            .download_active    (ega_bios_download_active),
            .write_complete     (ega_bios_write_complete),
            .loaded             (ega_bios_loaded),
            .write_protect      (ega_bios_write_protect),
            .video_switches     (ega_video_switches)
        );
    end
    else begin : g_no_ega_bios_presence
        assign ega_bios_loaded    = 1'b1;
        assign ega_bios_write_protect = 1'b1;
        assign ega_video_switches = 2'b10;
    end
    endgenerate

    // Reported one at a time, main BIOS first. The EGA ROM is only required
    // while the EGA card is the one that is selected.
    wire bios_missing_pcxt  = ~pcxt_bios_loaded & ~tandy_applied;
    // The Tandy notice and menu line exist only when the machine is chosen; a
    // build that is only a Tandy reports its BIOS as the main one (above)
    wire bios_missing_tandy = HAS_MODEL & tandy_applied & ~pcjr_applied & ~tandy_slot_loaded;
    wire bios_missing_pcjr  = HAS_PCJR_MODEL & pcjr_applied & ~pcjr_slot_loaded;
    wire bios_missing_ega  = HAS_EGA & ega_active & pcxt_bios_loaded & ~ega_bios_loaded;


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
    wire       bios_hold;
    wire [7:0] bios_info;
    wire       bios_info_req;
    // Driven by reset_pending_notice, instantiated with the MMC block below
    // (EGA menu layout only)
    wire [7:0] pending_info;
    wire       pending_info_req;

    bios_hold_notice #(.TANDY_INFO_INDEX(TANDY_INFO_INDEX), .PCJR_INFO_INDEX(PCJR_INFO_INDEX)) bios_notice (
        .clock             (clk_14_318),
        .splash_boot_phase (splash_pending | splash_timed),
        .bios_missing_pcxt (bios_missing_pcxt),
        .bios_missing_ega  (bios_missing_ega),
        .bios_missing_tandy(bios_missing_tandy),
        .bios_missing_pcjr (bios_missing_pcjr),
        .hold              (bios_hold),
        .info              (bios_info),
        .info_req          (bios_info_req)
    );

    // The missing-BIOS notice wins; reset_pending_notice is held off by the
    // same signal, so in practice the two are never asked at once.
    assign info     = L_EGA ? (bios_info_req ? bios_info : pending_info) : bios_info;
    assign info_req = L_EGA ? (bios_info_req | pending_info_req) : bios_info_req;

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

    // sw_base[5:4] is the motherboard video switch pair the BIOS copies into
    // the equipment word: 00 = EGA (its option ROM is present), 10 = CGA 80
    // columns, 11 = monochrome.
    wire [5:0] sw_base_cga = `ENABLE_HGC ? (hgc_mode ? 6'b111101 : 6'b101101) : 6'b101101;
    assign  sw_base = ega_active ? {ega_video_switches, 4'b1101} : sw_base_cga;
    assign  sw_floppy = fdd_present[1] ? 2'b01 : 2'b00;
    assign  sw = {sw_floppy, sw_base}; // DIP switches (CGA and floppy count)
    assign  port_c_in[3:0] = port_b_out[3] ? sw[7:4] : sw[3:0];


    wire video_output_sel = `ENABLE_HGC ? hgc_mode_video_ff : 1'b0;
    wire enable_hgc_sel = `ENABLE_HGC ? 1'b1 : 1'b0;
    wire [1:0] hgc_rgb_sel = `ENABLE_HGC ? 2'b10 : 2'b00;
    wire hercules_hw_sel = `ENABLE_HGC ? hercules_hw : 1'b0;
    wire ems_enabled_sel = `ENABLE_EMS ? eff_ems : 1'b0;
    // The EGA layout fixes the frame at D000, which avoids the EGA and XT-IDE
    // ROM conflicts; the CGA layout lets the menu choose C000/D000/E000.
    wire [1:0] ems_address_sel = `ENABLE_EMS ? (L_EGA ? 2'b01 : status[68:67]) : 2'b00;
    wire umb_enabled_sel = `ENABLE_UMB ? eff_umb : 1'b0;
    wire mpu401_enabled_sel = `ENABLE_MIDI ? eff_mpu401 : 1'b0;

    always @(posedge clk_chipset)
    begin
        if (address_latch_enable)
            cpu_address <= cpu_ad_out;
        else
            cpu_address <= cpu_address;
    end

    CHIPSET #(.clk_rate(cur_rate), .ROM_TANDY(`ROM_IS_TANDY), .ENABLE_EGA(`ENABLE_EGA)) u_CHIPSET
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
		.ega_active                         (ega_active),
		.EGA_R                              (EGA_R),
		.EGA_G                              (EGA_G),
		.EGA_B                              (EGA_B),
		.EGA_HSYNC                          (EGA_HSYNC),
		.EGA_VSYNC                          (EGA_VSYNC),
		.EGA_HBlank                         (EGA_HBlank),
		.EGA_VBlank                         (EGA_VBlank),
		.EGA_VBlank_border                  (EGA_VBlank_border),
		.EGA_std_hsyncwidth                 (EGA_std_hsyncwidth),
		.EGA_de_o                           (EGA_de_o),
		.ega_dot_toggle                     (ega_dot_toggle),
		.ega_dot_clock_sel                  (ega_dot_clock_sel),
		.ega_scandouble_active_out          (ega_scandouble_active),
		.ega_vmode_toggle_out               (ega_vmode_toggle),
		.ega_mode350                        (ega_mode350),
		.ega_active_dots                    (ega_active_dots),
		.ega_active_lines                   (ega_active_lines),
		.vga_mode13_osd                     (eff_vga13),
		.vga_mode13_native                  (vga_mode13_native_osd),
		.ega_monitor_profile                (ega_monitor_profile_applied),
		.vga_mode13_active_out              (vga_mode13_active_video),
		.vga_mode13_wide_clock_out          (vga_mode13_wide_clock),
		.vga_mode13_pixel_toggle_out        (vga_mode13_pixel_toggle),
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
		.joy0                               (eff_joy_swap ? joy1 : joy0),
		.joy1                               (eff_joy_swap ? joy0 : joy1),
		.joya0                              (eff_joy_swap ? joya1 : joya0),
		.joya1                              (eff_joy_swap ? joya0 : joya1),
		.jtopl2_snd_e                       (jtopl2_snd_e),
		.tandy_snd_e                        (tandy_snd_e),
		.tandy_en                           (eff_tandy),
		.opl2_io                            (xtctl[4] ? 2'b10 : eff_opl2),
		.sb_en                              (eff_sb),
		.sb_irq7                            (sb_irq7),
		.sb_snd_l                           (sb_snd_l),
		.sb_snd_r                           (sb_snd_r),
		.cms_en                             (eff_cms),
		.o_cms_l                            (cms_l_snd_e),
		.o_cms_r                            (cms_r_snd_e),
		.tandy_video                        (tandy_video_mode),
		.tandy_16_gfx                       (tandy_16_gfx),
		.tandy_color_16                     (tandy_color_16),
		.pcjr                               (pcjr_video_mode),
		.pcjr_vram_32k                      (pcjr_vram_32k),
		.pcjr_ram_size                      (pcjr_ram_size),
		.cart1_seg                          (cart1_seg),
		.cart1_len                          (cart1_len),
		.cart2_seg                          (cart2_seg),
		.cart2_len                          (cart2_len),
		.nmi_to_cpu                         (nmi_to_cpu),
		.cassette_out                       (cassette_out),
		.cassette_motor                     (cassette_motor),
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
		.mpu401_enabled                     (mpu401_enabled_sel),
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
		.sdram_clk                          (clk_sdram),
		.vid_req                            (egaf_req),
		.vid_addr                           (egaf_addr),
		.vid_len                            (egaf_len),
		.vid_deadline                       (egaf_deadline),
		.vid_ack                            (egaf_ack),
		.vid_rvalid                         (egaf_rvalid),
		.vid_rlast                          (egaf_rlast),
		.vid_rdata                          (sd_rdata),
		.snoop_valid                        (sn_valid),
		.snoop_addr                         (sn_addr),
		.snoop_len                          (sn_len),
		.snoop_wdata                        (sn_wdata),
		.snoop_wbe                          (sn_wbe),
		.mem_snoop_valid                    (),
		.mem_snoop_addr                     (),
		.mem_snoop_data                     (),
		.mem_snoop_be                       (),
		.ems_enabled                        (ems_enabled_sel),
		.ems_address                        (ems_address_sel),
		.umb_enabled                        (umb_enabled_sel),
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
		.xtegactl_cpu                       (xtegactl_cpu),
		.xtegactl_exp                       (xtegactl_exp),
		.xtegactl_vid                       (xtegactl_vid),
		.xtegactl_inp                       (xtegactl_inp),
		.xtegactl_midi                      (xtegactl_midi),
		.xtegactl_exp2                      (xtegactl_exp2),
		.xtegactl_crt                       (xtegactl_crt),
		.xtegactl_sync                      (xtegactl_sync),
		.xtegactl_status_effective          (xtegactl_status_effective),
		.xtegactl_status_osd_match          (xtegactl_status_osd_match),
		.id_video_card                      (id_video_card),
		.id_vga13_active                    (id_vga13_active),
		.enable_a000h                       (a000h),
		.wait_count_clk_en                  (cpu_ce_negedge),
		.ram_read_wait_cycle                (ram_read_wait_cycle),
		.ram_write_wait_cycle               (ram_write_wait_cycle),
		.pause_core                         (pause_core),
		.cga_hw                             (cga_hw),
		.cga_scandouble_en                  (cga_scandouble_en),
		.hercules_hw                        (hercules_hw_sel),
		.swap_video                         (swap_video),
		.crt_h_offset                       (eff_crt_h),
		.crt_v_offset                       (eff_crt_v),
		.vsync_width_osd                    (vsync_width_osd),
		.hsync_width_osd                    (hsync_width_osd),
		.cga_frame_stack_rebuild            (frame_stack_osd),
		.fx_cga_vram_d                      (fx_cga_vram_d),
		.fx_cga_phase                       (fx_cga_phase),
		.fx_cga_hres                        (fx_cga_hres),
		.fx_cga_cur_word                    (fx_cga_cur_word),
		.fx_cga_next_word                   (fx_cga_next_word),
		.tandy_vram_en                      (tandy_vram_en),
		.tandy_vram_block                   (tandy_vram_block),
		.tandy_vram_page                    (tandy_vram_page),
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
		.NMI(nmi_to_cpu),
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
    // The CGA layout has a "Tandy Volume" option (status[35:34]). The EGA layout
    // has no status bit left to spend on one, so it rides the Speaker Volume
    // setting: both are internal beeper-class sources.
    wire [16:0] tandy_snd = `ENABLE_TANDY_AUDIO ?
                            (L_EGA ? {{{2{tandy_snd_e[10]}}, {4{tandy_snd_e[10]}}, tandy_snd_e} << status[33:32], 2'b00}
                                   : (tandy_snd_base << ({1'b0, status[35:34]} + 3'd2))) : 17'd0;
    wire [16:0] spk_vol =  {2'b00, {3'b000,~speaker_out} << status[33:32], 11'd0};

    // PCjr: what the BASIC SAVE puts on the cassette line is heard as long as the
    // motor is on and the line keeps changing (about 2.5 ms without an edge is
    // silence), at the speaker volume
    localparam [17:0] CASS_OUT_ACTIVE_AGE = 18'd150000;
    logic        cassette_out_d = 1'b0;
    logic [17:0] cassette_out_age = {18{1'b1}};
    always @(posedge clk_chipset) begin
        cassette_out_d <= cassette_out;
        if (cassette_out_d != cassette_out)
            cassette_out_age <= 18'd0;
        else if (cassette_out_age != {18{1'b1}})
            cassette_out_age <= cassette_out_age + 18'd1;
    end
    wire        tape_audio = pcjr_video_mode && status[102] && cassette_motor && (cassette_out_age < CASS_OUT_ACTIVE_AGE);
    wire [16:0] tape_snd = tape_audio ? {2'b00, {3'b000,cassette_out} << status[33:32], 11'd0} : 17'd0;
    wire [15:0] sb_snd_l, sb_snd_r;
    wire [16:0] sb_l_snd = `ENABLE_SB ? {sb_snd_l[15], sb_snd_l} : 17'd0;
    wire [16:0] sb_r_snd = `ENABLE_SB ? {sb_snd_r[15], sb_snd_r} : 17'd0;
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

        tmp_l <= jtopl2_snd + cms_l_snd + tandy_snd + spk_vol + tape_snd + mt32_l_snd + sb_l_snd;

        // clamp the output
        out_l <= (^tmp_l[16:15]) ? {tmp_l[16], {15{tmp_l[15]}}} : tmp_l[15:0];

        cmp_l <= compr(out_l);
    end
	 
    reg [15:0] cmp_r;
    reg [15:0] out_r;
    always @(posedge clk_chipset)
    begin
        reg [16:0] tmp_r;

        tmp_r <= jtopl2_snd + cms_r_snd + tandy_snd + spk_vol + tape_snd + mt32_r_snd + sb_r_snd;

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
    wire        mt32_mode_req = eff_mt32_gm;
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
    // With the EGA layout MT32-pi gets some headroom before it is summed with
    // the core audio (a resource-free -6 dB shift of the signed samples).
    wire signed [16:0] mt32_i2s_l_attenuated = {mt32_i2s_l_ext[16], mt32_i2s_l_ext[16:1]};
    wire signed [16:0] mt32_i2s_r_attenuated = {mt32_i2s_r_ext[16], mt32_i2s_r_ext[16:1]};
    wire [16:0] mt32_l_snd = mt32_use ? (L_EGA ? mt32_i2s_l_attenuated : mt32_i2s_l_ext) : 17'd0;
    wire [16:0] mt32_r_snd = mt32_use ? (L_EGA ? mt32_i2s_r_attenuated : mt32_i2s_r_ext) : 17'd0;

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

    // Options that the machine samples only while it is in reset: say so when
    // one of them has been changed and is still waiting for the next reset.
    wire reset_pending = (cpu_type_8086_osd       != is8086_applied)
                       | (HAS_EGA && (ega_monitor_profile_osd != ega_monitor_profile_applied))
                       | (status[22:21]           != use_mmc)
                       | (CARD_SELECTABLE && (card_sel_ega != ega_active))
                       | (HAS_MODEL && (tandy_sel_osd != tandy_applied))
                       | (HAS_PCJR_MODEL && (pcjr_sel_osd != pcjr_applied))
                       | (HAS_PCJR && (((status[101:98] > 4'd8) ? 4'd8 : status[101:98]) != pcjr_ram_size_r));

    generate
    if (L_EGA) begin : g_pending_notice
        reset_pending_notice #(.INFO_INDEX(PENDING_INFO_INDEX)) reset_notice (
            .clock      (clk_14_318),
            .pending    (reset_pending),
            .osd_status (OSD_STATUS),
            .suppress   (bios_hold),
            .info       (pending_info),
            .info_req   (pending_info_req)
        );
    end
    else begin : g_no_pending_notice
        assign pending_info     = 8'd0;
        assign pending_info_req = 1'b0;
    end
    endgenerate

    // Identification block (XTCTL 8990h..8997h): which card is in use
    assign id_video_card    = ega_active ? 2'd3 : ((`ENABLE_HGC && hgc_mode) ? 2'd2 : 2'd1);
    assign id_vga13_active  = HAS_EGA & vga_mode13_active_video;

    //
    ///////////////////////   VIDEO   ///////////////////////
    //
    // The CGA/HGC card and the EGA card each keep their own front end
    // (converter, scandoubler, border window).  Past that point the machine has
    // one video path: whichever card is in use (ega_active_vid, fixed while the
    // machine is out of reset) feeds a single 350-line framebuffer, a single
    // source switch and a single main video mixer on the 57.272 MHz clock.  The
    // HGC keeps its own 114.5 MHz mixer for the native (non-framebuffer)
    // raster, which is merged with the main path in the output clock domain.
    // With one card built the selections below are constants and fold away.

    wire HBlank;
    wire HSync;
    wire VBlank;
    wire VSync;
    reg  ce_pixel_cga = 1'b0;
    wire ce_pixel_hgc_raw;
    wire [5:0] r, g, b;
    wire [7:0] raux_cga, gaux_cga, baux_cga;
    wire [7:0] raux_hgc, gaux_hgc, baux_hgc;
    wire [7:0] raux_ega, gaux_ega, baux_ega;
    wire [7:0] VGA_R_AUX, VGA_G_AUX, VGA_B_AUX;
    wire CLK_VIDEO_HGC;
    wire CLK_VIDEO_MAIN;
    wire CE_PIXEL_CREDITS;

    wire  [7:0] VGA_R_main;
    wire  [7:0] VGA_G_main;
    wire  [7:0] VGA_B_main;
    wire        VGA_HS_main;
    wire        VGA_VS_main;
    wire        VGA_DE_main;
    wire [21:0] gamma_bus_main;
    wire        CE_PIXEL_main;
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
    reg  [5:0]  hgc_r_meta, hgc_g_meta, hgc_b_meta;
    reg  [5:0]  hgc_r_sync, hgc_g_sync, hgc_b_sync;
    reg         hgc_hs_meta, hgc_vs_meta;
    reg         hgc_hs_sync, hgc_vs_sync;
    reg         hgc_hb_meta, hgc_vb_meta;
    reg         hgc_hb_sync, hgc_vb_sync;

    reg  [7:0]  VGA_R_main_src = 8'd0;
    reg  [7:0]  VGA_G_main_src = 8'd0;
    reg  [7:0]  VGA_B_main_src = 8'd0;
    reg         VGA_HS_main_src = 1'b0;
    reg         VGA_VS_main_src = 1'b0;
    reg         VGA_DE_main_src = 1'b0;
    reg         LHBL_main_src = 1'b1;
    reg         LVBL_main_src = 1'b1;
    reg         CE_PIXEL_main_src = 1'b0;
    reg  [7:0]  VGA_R_main_ps = 8'd0;
    reg  [7:0]  VGA_G_main_ps = 8'd0;
    reg  [7:0]  VGA_B_main_ps = 8'd0;
    reg         VGA_HS_main_ps = 1'b0;
    reg         VGA_VS_main_ps = 1'b0;
    reg         VGA_DE_main_ps = 1'b0;
    reg         LHBL_main_ps = 1'b1;
    reg         LVBL_main_ps = 1'b1;
    reg         CE_PIXEL_main_ps = 1'b0;
    reg         CE_PIXEL_main_ps_d = 1'b0;
    reg  [7:0]  VGA_R_main_hdmi, VGA_G_main_hdmi, VGA_B_main_hdmi;
    reg         VGA_HS_main_hdmi, VGA_VS_main_hdmi, VGA_DE_main_hdmi;
    reg         LHBL_main_hdmi, LVBL_main_hdmi;
    reg         CE_PIXEL_main_hdmi = 1'b0;

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

    assign CLK_VIDEO = clk_video_out_ps;
    assign CLK_VIDEO_HGC = clk_114_544;
    assign CLK_VIDEO_MAIN = clk_57_272;
    assign ce_pixel_hgc_raw = ce_pixel_hgc_div[1];

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
        .v_early   (border_crt_osd ? eff_crt_v : 3'd0),
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
    wire [3:0] crt_h_off = border_crt_osd ? eff_crt_h : 4'd0;
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
    wire haux_ega, vaux_ega, hbaux_ega, vbaux_ega;

    video_monochrome_converter_cga video_mono_cga
	(
		.clk_vid(CLK_VIDEO_MAIN),
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

    ///////////////////////////  EGA CARD FRONT END  ///////////////////////////
    //
    // The EGA dot rate is not a fixed 14.318 MHz: in the 16.257 MHz modes
    // consecutive dots can land on adjacent clk_28_636 edges, which in this
    // domain would be a single wide level with only one rising edge.  The EGA
    // exports a toggle instead, one flip per dot.  Exactly one synchroniser
    // stage before the XOR: both clocks come from pll_system with a 2:1 ratio
    // and no phase shift, and a second stage would push the enable past the
    // end of the short dots of the 16.257 MHz pattern.
    reg         ega_dot_toggle_d = 1'b0;
    reg         ega_dot_toggle_dd = 1'b0;
    // vga_mode13_active_video drives either the Native VGA or 15 kHz CRT-TV
    // raster (rtl/video/vga_mode13_timing.v), whose real pixel rate is one
    // flip per displayed pixel, not per video-clock cycle.
    reg         vga_mode13_pixel_toggle_d = 1'b0;
    reg         vga_mode13_pixel_toggle_dd = 1'b0;

    always @(posedge clk_57_272)
    begin
        ega_dot_toggle_d           <= ega_dot_toggle;
        ega_dot_toggle_dd          <= ega_dot_toggle_d;
        vga_mode13_pixel_toggle_d  <= vga_mode13_pixel_toggle;
        vga_mode13_pixel_toggle_dd <= vga_mode13_pixel_toggle_d;
    end

    wire        ce_pixel_dot    = ega_dot_toggle_d ^ ega_dot_toggle_dd;
    wire        ce_pixel_mode13 = vga_mode13_pixel_toggle_d ^ vga_mode13_pixel_toggle_dd;
    wire        vga_video_direct = vga_mode13_active_video;
    wire        ce_pixel_ega = ega_scandouble_active ? ce_pixel_cga_2x
                             : vga_video_direct      ? ce_pixel_mode13
                             : ce_pixel_dot;

    wire LHBL_ega = (ega_scandouble_active || vga_video_direct) ? EGA_HBlank : ~EGA_de_o;
    wire LVBL_ega = EGA_VBlank;

    // Sync and blanking go through the converter with the colour so they come
    // out of it with the same delay.  Mode 13h only takes the undelayed pair
    // below in Full Color: once a monochrome Display option is picked it has
    // to run through the converter like every other mode, both for the tint
    // and to stay time-aligned with it, or the picture is full colour again.
    video_monochrome_converter video_mono_ega
	(
		.clk_vid(CLK_VIDEO_MAIN),
		.ce_pix(ce_pixel_ega),

		.R({EGA_R, 2'b00}),
		.G({EGA_G, 2'b00}),
		.B({EGA_B, 2'b00}),

		.HSync(EGA_HSYNC),
		.VSync(EGA_VSYNC),
		.HBlank(LHBL_ega),
		.VBlank(LVBL_ega),

		.gfx_mode(screen_mode_video_ff),

		.R_OUT(raux_ega),
		.G_OUT(gaux_ega),
		.B_OUT(baux_ega),

		.HSync_OUT(haux_ega),
		.VSync_OUT(vaux_ega),
		.HBlank_OUT(hbaux_ega),
		.VBlank_OUT(vbaux_ega)
	);

    wire vga_video_direct_color = vga_video_direct && color;
    wire [7:0] bypass_r = vga_video_direct_color ? {EGA_R, EGA_R[5:4]} : raux_ega;
    wire [7:0] bypass_g = vga_video_direct_color ? {EGA_G, EGA_G[5:4]} : gaux_ega;
    wire [7:0] bypass_b = vga_video_direct_color ? {EGA_B, EGA_B[5:4]} : baux_ega;
    wire bypass_hs = vga_video_direct_color ? EGA_HSYNC : haux_ega;
    wire bypass_vs = vga_video_direct_color ? EGA_VSYNC : vaux_ega;
    wire bypass_hb = vga_video_direct_color ? LHBL_ega  : hbaux_ega;
    wire bypass_vb = vga_video_direct_color ? LVBL_ega  : vbaux_ega;

    // The detector runs in the 28.636 MHz video domain and these change once a
    // frame. Two stages across to the 57.272 MHz clock, which is the same PLL at
    // twice the rate.
    reg        mode350_s1, mode350_s2;
    reg [11:0] adots_s1, adots_s2;
    reg [9:0]  alines_s1, alines_s2;

    always @(posedge clk_57_272) begin
        mode350_s1 <= ega_mode350;      mode350_s2 <= mode350_s1;
        adots_s1   <= ega_active_dots;  adots_s2   <= adots_s1;
        alines_s1  <= ega_active_lines; alines_s2  <= alines_s1;
    end

    ///////////////////  350-LINE CRT OUTPUT, 720x480i / 240p  ///////////////////
    //
    // EGA and MDA/HGC modes with more than 240 active lines scan at 18-22 kHz
    // and no television locks to that.  They are captured into DDRAM a frame
    // at a time and read back out on a 15.734 kHz interlaced (or progressive)
    // raster.  CGA never enters this block: its calibrated native 15 kHz path
    // stays completely bypassed.  The capture taps the picture after the
    // monochrome converter, so the Display option is already applied.
    //
    // One capture/readout/DDRAM arbiter serves both cards, on the 57.272 MHz
    // clock.  The HGC front end runs at 114.5 MHz and exposes its pixels as a
    // two-clock level; the rising edge of that level, sampled here, gives one
    // event per converted 28.636 MHz pixel with the colour already settled.
    reg  hgc_raw_57 = 1'b0, hgc_raw_57_d = 1'b0;
    always @(posedge clk_57_272) begin
        hgc_raw_57   <= ce_pixel_hgc_raw;
        hgc_raw_57_d <= hgc_raw_57;
    end
    wire ce_pixel_hgc_fb = hgc_raw_57 & ~hgc_raw_57_d;

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
    always @(posedge clk_57_272) begin
        if (video_retime_reset_57) begin
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

    wire fb_enable = ega_active_vid ? (mode350_s2 & crt480i_osd)
                                    : (swap_video_eff & crt480i_osd);

    wire        cap_ce      = ega_active_vid ? ce_pixel_ega : ce_pixel_hgc_fb;
    wire [7:0]  cap_r       = ega_active_vid ? bypass_r : raux_hgc;
    wire [7:0]  cap_g       = ega_active_vid ? bypass_g : gaux_hgc;
    wire [7:0]  cap_b       = ega_active_vid ? bypass_b : baux_hgc;
    wire        cap_de      = ega_active_vid ? (~bypass_hb & ~bypass_vb) : hgc_fb_de;
    wire        cap_vblank  = ega_active_vid ? bypass_vb : vbaux_hgc;
    wire [11:0] cap_dots    = ega_active_vid ? adots_s2  : HGC_FB_DOTS;
    wire [9:0]  cap_lines   = ega_active_vid ? alines_s2 : hgc_fb_active_lines;

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

    ega_fb_capture fb_capture (
        .clk(CLK_VIDEO_MAIN),
        .reset(video_retime_reset_57),
        .enable(fb_enable),
        .ce_pix(cap_ce),
        .r(cap_r), .g(cap_g), .b(cap_b),
        .de(cap_de),
        .vblank(cap_vblank),
        .active_dots(cap_dots),
        .active_lines(cap_lines),
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

    ega_fb_readout fb_readout (
        .clk(CLK_VIDEO_MAIN),
        .reset(video_retime_reset_57),
        .enable(fb_enable),
        .progressive(crt480i_prog),
        .crt_h_offset(eff_crt_h),
        .crt_v_offset(eff_crt_v),
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

    // The memory runs on the video pipeline clock, so the capture, the
    // raster that reads it back and DDRAM itself are all one domain and
    // nothing has to cross between them.
    assign DDRAM_CLK = CLK_VIDEO_MAIN;

    ega_ddr_arbiter fb_arbiter (
        .clk(CLK_VIDEO_MAIN),
        .reset(video_retime_reset_57),
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

    // Change over in the destination raster's own vertical blank. Requiring
    // both rasters to be blank at once can stall when two roughly 60 Hz modes
    // keep nearly the same phase, leaving the output on the old (already
    // black) path while the new one is ready underneath it.
    wire crt480i_active;

    video_source_switch crt480i_source_switch (
        .clock(CLK_VIDEO_MAIN),
        .reset(video_retime_reset_57),
        .select_alt(fb_enable & fb_frame_valid),
        .primary_hsync(ega_active_vid ? bypass_hs : haux_hgc),
        .primary_vblank(ega_active_vid ? bypass_vb : vbaux_hgc),
        .alt_hsync(fb_hs),
        .alt_vblank(fb_vb),
        .alt_active(crt480i_active)
    );

    // The main mixer carries the EGA picture, the CGA picture and, when the
    // captured 15 kHz raster is on the wire, the HGC picture too.
    wire [7:0] main_r  = crt480i_active ? fb_r  : (ega_active_vid ? bypass_r  : raux_cga);
    wire [7:0] main_g  = crt480i_active ? fb_g  : (ega_active_vid ? bypass_g  : gaux_cga);
    wire [7:0] main_b  = crt480i_active ? fb_b  : (ega_active_vid ? bypass_b  : baux_cga);
    wire       main_hs = crt480i_active ? fb_hs : (ega_active_vid ? bypass_hs : haux_cga);
    wire       main_vs = crt480i_active ? fb_vs : (ega_active_vid ? bypass_vs : vaux_cga);
    wire       main_hb = crt480i_active ? fb_hb : (ega_active_vid ? bypass_hb : hbaux_cga);
    wire       main_vb = crt480i_active ? fb_vb : (ega_active_vid ? bypass_vb : vbaux_cga);
    wire       ce_pixel_main = crt480i_active ? fb_ce_pix
                             : (ega_active_vid ? ce_pixel_ega : ce_pixel_cga_vid);

    // The credits overlay and the framework's active-window measurement follow
    // whichever raster is actually being emitted.
    wire LHBL_main = crt480i_active ? fb_hb : (ega_active_vid ? LHBL_ega : LHBL);
    wire LVBL_main = crt480i_active ? fb_vb : (ega_active_vid ? LVBL_ega : LVBL);

    // Which field is on the wire. It moves once per field, far slower than
    // anything else here, so two flops across to the output clock are enough.
    reg vga_f1_ps1 = 1'b0, vga_f1_ps2 = 1'b0;

    always @(posedge clk_video_out_ps) begin
        vga_f1_ps1 <= crt480i_active & fb_field;
        vga_f1_ps2 <= vga_f1_ps1;
    end

    assign VGA_F1 = vga_f1_ps2;

    wire       pre2x_LHBL, pre2x_LVBL;

	video_mixer #(.GAMMA(1)) video_mixer_main
	(
		.*,

		.CLK_VIDEO(CLK_VIDEO_MAIN),
		.CE_PIXEL(CE_PIXEL_main),
		.ce_pix(ce_pixel_main),

		.freeze_sync(),

		.R(main_r),
		.G(main_g),
		.B(main_b),

		.HBlank(main_hb),
		.VBlank(main_vb),
		.HSync(main_hs),
		.VSync(main_vs),

		.scandoubler(1'b0),
		.hq2x((ega_active_vid || swap_video_eff) ? (scale_video_ff==1) : (scale_cga_ff==1)),
		.gamma_bus(gamma_bus_main),

		.VGA_R(VGA_R_main),
		.VGA_G(VGA_G_main),
		.VGA_B(VGA_B_main),
		.VGA_VS(VGA_VS_main),
		.VGA_HS(VGA_HS_main),
		.VGA_DE(VGA_DE_main)

	);

    always @(posedge clk_57_272)
    begin
        VGA_R_main_src <= VGA_R_main;
        VGA_G_main_src <= VGA_G_main;
        VGA_B_main_src <= VGA_B_main;
        VGA_HS_main_src <= VGA_HS_main;
        VGA_VS_main_src <= VGA_VS_main;
        VGA_DE_main_src <= VGA_DE_main;
        LHBL_main_src <= LHBL_main;
        LVBL_main_src <= LVBL_main;
        CE_PIXEL_main_src <= CE_PIXEL_main;
    end

    // Retimes the exact-frequency main output onto a phase-shifted sibling clock.
    always @(posedge clk_video_out_ps or posedge video_retime_reset_local)
    begin
        if (video_retime_reset_local)
        begin
            VGA_R_main_ps <= 8'd0;
            VGA_G_main_ps <= 8'd0;
            VGA_B_main_ps <= 8'd0;
            VGA_HS_main_ps <= 1'b0;
            VGA_VS_main_ps <= 1'b0;
            VGA_DE_main_ps <= 1'b0;
            LHBL_main_ps <= 1'b1;
            LVBL_main_ps <= 1'b1;
            CE_PIXEL_main_ps <= 1'b0;
            CE_PIXEL_main_ps_d <= 1'b0;
            VGA_R_main_hdmi <= 8'd0;
            VGA_G_main_hdmi <= 8'd0;
            VGA_B_main_hdmi <= 8'd0;
            VGA_HS_main_hdmi <= 1'b0;
            VGA_VS_main_hdmi <= 1'b0;
            VGA_DE_main_hdmi <= 1'b0;
            LHBL_main_hdmi <= 1'b1;
            LVBL_main_hdmi <= 1'b1;
            CE_PIXEL_main_hdmi <= 1'b0;
        end
        else
        begin
            CE_PIXEL_main_hdmi <= CE_PIXEL_main_ps & ~CE_PIXEL_main_ps_d;
            if (CE_PIXEL_main_ps & ~CE_PIXEL_main_ps_d)
            begin
                VGA_R_main_hdmi <= VGA_R_main_ps;
                VGA_G_main_hdmi <= VGA_G_main_ps;
                VGA_B_main_hdmi <= VGA_B_main_ps;
                VGA_HS_main_hdmi <= VGA_HS_main_ps;
                VGA_VS_main_hdmi <= VGA_VS_main_ps;
                VGA_DE_main_hdmi <= VGA_DE_main_ps;
                LHBL_main_hdmi <= LHBL_main_ps;
                LVBL_main_hdmi <= LVBL_main_ps;
            end

            CE_PIXEL_main_ps_d <= CE_PIXEL_main_ps;
            CE_PIXEL_main_ps <= CE_PIXEL_main_src;
            VGA_R_main_ps <= VGA_R_main_src;
            VGA_G_main_ps <= VGA_G_main_src;
            VGA_B_main_ps <= VGA_B_main_src;
            VGA_HS_main_ps <= VGA_HS_main_src;
            VGA_VS_main_ps <= VGA_VS_main_src;
            VGA_DE_main_ps <= VGA_DE_main_src;
            LHBL_main_ps <= LHBL_main_src;
            LVBL_main_ps <= LVBL_main_src;
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
		.ce_pix(ce_pixel_hgc_raw),

		.freeze_sync(),

		.R(raux_hgc),
		.G(gaux_hgc),
		.B(baux_hgc),

		.HBlank(hbaux_hgc),
		.VBlank(vbaux_hgc),
		.HSync(haux_hgc),
		.VSync(vaux_hgc),

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
            LHBL_hgc_src <= hgc_hb_sync;
            credits_vb_hgc_src <= hgc_vb_sync;
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
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg crt480i_out_meta = 1'b0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg crt480i_out_ff = 1'b0;
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
        crt480i_out_meta      <= crt480i_active;
        crt480i_out_ff        <= crt480i_out_meta;
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

    // The HGC's own mixer is on the wire only for its native raster; once the
    // captured 15 kHz raster is up it travels through the main mixer instead.
    wire hgc_native_out = swap_video_out_ff & ~crt480i_out_ff;

    assign VGA_R_AUX  =  hgc_native_out ? VGA_R_hgc_56   : VGA_R_main_hdmi;
    assign VGA_G_AUX  =  hgc_native_out ? VGA_G_hgc_56   : VGA_G_main_hdmi;
    assign VGA_B_AUX  =  hgc_native_out ? VGA_B_hgc_56   : VGA_B_main_hdmi;
    assign VGA_HS =  hgc_native_out ? VGA_HS_hgc_56 : VGA_HS_main_hdmi;
    assign VGA_VS =  hgc_native_out ? VGA_VS_hgc_56 : VGA_VS_main_hdmi;
    assign gamma_bus =  (swap_video_eff && !crt480i_active) ? gamma_bus_hgc : gamma_bus_main;
    assign CE_PIXEL  =  hgc_native_out ? CE_PIXEL_hgc_hdmi : CE_PIXEL_main_hdmi;
    assign CE_PIXEL_CREDITS = hgc_native_out ? CE_PIXEL_hgc_hdmi : CE_PIXEL_main_hdmi;
    wire credits_hb = hgc_native_out ? LHBL_hgc_56 : LHBL_main_hdmi;
    wire credits_vb = hgc_native_out ? credits_vb_hgc_56 : LVBL_main_hdmi;
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
    // the selected DE directly opens the active window one pixel before the
    // corresponding RGB output sample and clips the last pixel instead.
    reg VGA_DE_credits = 1'b0;
    wire VGA_DE_selected = hgc_native_out ? VGA_DE_hgc_56 : VGA_DE_main_hdmi;
    always @(posedge clk_video_out_ps or posedge video_retime_reset_local) begin
        if (video_retime_reset_local)
            VGA_DE_credits <= 1'b0;
        else if (CE_PIXEL_CREDITS)
            VGA_DE_credits <= VGA_DE_selected;
    end

    assign VGA_DE = VGA_DE_credits;

endmodule
