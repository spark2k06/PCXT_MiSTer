//============================================================================
//
//  Port of PCXT MiSTer core to MiST platform
//  Target: poseidon_epc4cgx150 (Cyclone IV GX EP4CGX150)
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//============================================================================

`ifndef ENABLE_CGA
`define ENABLE_CGA 1
`endif
`ifndef ENABLE_HGC
`define ENABLE_HGC 1
`endif
`ifndef ENABLE_TANDY_VIDEO
`define ENABLE_TANDY_VIDEO 1
`endif

`include "build_id.v"

module PCXT_MiST
(
    // Clock inputs
    input         CLOCK_27,     // 27 MHz - not used (we use on-board 50 MHz via PLL)
    input         CLOCK_50,     // 50 MHz input clock

    // VGA output
    output  [5:0] VGA_R,
    output  [5:0] VGA_G,
    output  [5:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,

    // SDRAM
    inout  [15:0] SDRAM_DQ,
    output [12:0] SDRAM_A,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output  [1:0] SDRAM_BA,
    output        SDRAM_nCS,
    output        SDRAM_nWE,
    output        SDRAM_nRAS,
    output        SDRAM_nCAS,
    output        SDRAM_CLK,
    output        SDRAM_CKE,

    // Audio (sigma-delta)
    output        AUDIO_L,
    output        AUDIO_R,

    // SPI interface to IO controller
    output        SPI_DO,
    input         SPI_DI,
    input         SPI_SCK,
    input         SPI_SS2,   // data_io
    input         SPI_SS3,   // OSD
    input         SPI_SS4,   // data_io direct
    input         CONF_DATA0, // user_io

    // UART
    input         UART_RX,
    output        UART_TX,

    // LED
    output        LED
);

// ─── MiST Configuration String ────────────────────────────────────────────

localparam CONF_STR = {
    "PCXT;UART115200:115200;",
    "S0,IMGIMAVFD,Floppy A:;",
    "S1,IMGIMAVFD,Floppy B:;",
    "OAB,Write Protect,None,A:,B:,A: & B:;",
    "-;",
    "S2,VHD,IDE 0-0;",
    "S3,VHD,IDE 0-1;",
    "-;",
    "OCD,CPU Speed,4.77MHz,7.16MHz,9.54MHz,PC/AT 3.5MHz;",
    "-;",
    "O3,Model,IBM PCXT,Tandy 1000;",
    "O4,1st Video,CGA,Hercules;",
    "O7,Boot Splash,Yes,No;",
    "-;",
    "FC0,ROM,PCXT BIOS:;",
    "FC1,ROM,Tandy BIOS:;",
    "FC2,ROM,EC00 BIOS:;",
    "-;",
    "OEF,BIOS Writable,None,EC00,PCXT/Tandy,All;",
    "-;",
    "OA,C/MS Audio,Enabled,Disabled;",
    "O12,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
    "O89,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
    "OT,Border,No,Yes;",
    "O8C,Composite video,Off,On;",
    "-;",
    "OB,Lo-tech 2MB EMS,Enabled,Disabled;",
    "-;",
    "R0,Reset;",
    "J,Fire 1,Fire 2;",
    "V,v",`BUILD_DATE
};

localparam CONF_STR_LEN = $bits(CONF_STR) / 8;

// ─── Clocks ───────────────────────────────────────────────────────────────

wire clk_sys;      // 50 MHz system clock (chipset clock)
wire clk_100;      // 100 MHz (CPU core clock)
wire pll_locked;

wire clk_28_636;
wire clk_57_272;
wire clk_114_544;
wire clk_9_54;
wire clk_7_16;
wire pll_system_locked;

// Main PLL: 50 MHz → 100 MHz + 50 MHz
pll_mist pll_mist_inst (
    .inclk0  (CLOCK_50),
    .c0      (clk_100),
    .c1      (clk_sys),
    .locked  (pll_locked)
);

// System PLL: 50 MHz → video & CPU speed clocks
pll_system_mist pll_system_mist_inst (
    .inclk0  (CLOCK_50),
    .c0      (clk_28_636),
    .c1      (clk_57_272),
    .c2      (clk_114_544),
    .c3      (clk_9_54),
    .c4      (clk_7_16),
    .locked  (pll_system_locked)
);

// 4.772727 MHz derived from 9.545454 / 2
reg clk_4_77_r = 1'b0;
always @(posedge clk_9_54) clk_4_77_r <= ~clk_4_77_r;
wire clk_4_77 = clk_4_77_r;

// 25 MHz derived from 50 MHz / 2 (used for PC/AT 3.5 MHz CPU speed mode)
reg clk_25 = 1'b0;
always @(posedge clk_sys) clk_25 <= ~clk_25;

// 14.318 MHz derived from 28.636 / 2
reg clk_14_318 = 1'b0;
always @(posedge clk_28_636) clk_14_318 <= ~clk_14_318;

// Peripheral clock: 2.385 MHz derived from 4.77 / 2
reg peripheral_clock = 1'b0;
always @(posedge clk_4_77) peripheral_clock <= ~peripheral_clock;

// ─── Reset logic ─────────────────────────────────────────────────────────

wire reset_btn;
wire [63:0] status;

wire reset_wire = status[0] | reset_btn | !pll_locked | !pll_system_locked
                | splashscreen | splash_reset_hold | splash_pending;
wire reset_sdram_wire = !pll_locked;

logic reset = 1'b1;
logic [15:0] reset_count = 16'h0000;

always @(posedge clk_sys, posedge reset_wire)
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

logic reset_sdram = 1'b1;
logic [15:0] reset_sdram_count = 16'h0000;

always @(posedge clk_sys, posedge reset_sdram_wire)
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

logic reset_cpu_ff = 1'b1;
logic reset_cpu = 1'b1;
logic [15:0] reset_cpu_count = 16'h0000;

always @(negedge clk_sys, posedge reset)
begin
    if (reset)
        reset_cpu_ff <= 1'b1;
    else
        reset_cpu_ff <= reset;
end

reg tandy_mode = 0;
reg hgc_mode   = 0;

always @(negedge clk_sys, posedge reset)
begin
    if (reset)
    begin
        tandy_mode <= status[3];
        hgc_mode   <= status[4];
        reset_cpu  <= 1'b1;
        reset_cpu_count <= 16'h0000;
    end
    else if (reset_cpu)
    begin
        reset_cpu  <= reset_cpu_ff;
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

// ─── user_io / MiST IO ────────────────────────────────────────────────────

wire [31:0] joystick_0;
wire [31:0] joystick_1;
wire [31:0] joystick_analog_0;
wire [31:0] joystick_analog_1;
wire [1:0]  buttons;
wire [1:0]  switches;
wire        scandoubler_disable;
wire        ypbpr;
wire        no_csync;

// PS2 keyboard
wire ps2_kbd_clk_out, ps2_kbd_data_out;
wire ps2_kbd_clk_in,  ps2_kbd_data_in;

// PS2 mouse
wire ps2_mouse_clk_out, ps2_mouse_data_out;
wire ps2_mouse_clk_in,  ps2_mouse_data_in;

// SD card interface (for floppy images - images 0 and 1)
wire [31:0] sd_lba;
wire [3:0]  sd_rd;
wire [3:0]  sd_wr;
wire        sd_ack;
wire        sd_ack_conf;
wire [3:0]  sd_ack_x;
wire        sd_conf;
wire        sd_sdhc;
wire [7:0]  sd_dout;
wire        sd_dout_strobe;
wire [7:0]  sd_din;
wire        sd_din_strobe;
wire [8:0]  sd_buff_addr;
wire [3:0]  img_mounted;
wire [63:0] img_size;

// RTC
wire [63:0] rtc;

// Serial (UART to IO controller)
wire [7:0]  serial_data;
wire        serial_strobe;

user_io #(
    .STRLEN(CONF_STR_LEN),
    .PS2DIV(2000),
    .PS2BIDIR(1),
    .ROM_DIRECT_UPLOAD(1),
    .SD_IMAGES(4)
) user_io_inst (
    .conf_str      (CONF_STR),
    .clk_sys       (clk_sys),
    .clk_sd        (clk_sys),

    .SPI_CLK       (SPI_SCK),
    .SPI_SS_IO     (CONF_DATA0),
    .SPI_MISO      (SPI_DO),
    .SPI_MOSI      (SPI_DI),

    .joystick_0    (joystick_0),
    .joystick_1    (joystick_1),
    .joystick_analog_0(joystick_analog_0),
    .joystick_analog_1(joystick_analog_1),
    .buttons       (buttons),
    .switches      (switches),
    .scandoubler_disable(scandoubler_disable),
    .ypbpr         (ypbpr),
    .no_csync      (no_csync),
    .status        (status),

    .sd_lba        (sd_lba),
    .sd_rd         (sd_rd),
    .sd_wr         (sd_wr),
    .sd_ack        (sd_ack),
    .sd_ack_conf   (sd_ack_conf),
    .sd_ack_x      (sd_ack_x),
    .sd_conf       (sd_conf),
    .sd_sdhc       (sd_sdhc),
    .sd_dout       (sd_dout),
    .sd_dout_strobe(sd_dout_strobe),
    .sd_din        (sd_din),
    .sd_din_strobe (sd_din_strobe),
    .sd_buff_addr  (sd_buff_addr),
    .img_mounted   (img_mounted),
    .img_size      (img_size),

    .ps2_kbd_clk   (ps2_kbd_clk_in),
    .ps2_kbd_data  (ps2_kbd_data_in),
    .ps2_kbd_clk_i (ps2_kbd_clk_out),
    .ps2_kbd_data_i(ps2_kbd_data_out),

    .ps2_mouse_clk  (ps2_mouse_clk_in),
    .ps2_mouse_data (ps2_mouse_data_in),
    .ps2_mouse_clk_i(ps2_mouse_clk_out),
    .ps2_mouse_data_i(ps2_mouse_data_out),

    .rtc           (rtc),

    .serial_data   (serial_data),
    .serial_strobe (serial_strobe),

    .i2c_start     (),
    .i2c_read      (),
    .i2c_addr      (),
    .i2c_subaddr   (),
    .i2c_dout      (),
    .i2c_din       (8'h00),
    .i2c_ack       (1'b0),
    .i2c_end       (1'b0),

    .leds          (8'h00),
    .kbd_out_data  (8'h00),
    .kbd_out_strobe(1'b0),
    .key_pressed   (),
    .key_extended  (),
    .key_code      (),
    .key_strobe    (),
    .mouse_x       (),
    .mouse_y       (),
    .mouse_z       (),
    .mouse_flags   (),
    .mouse_strobe  (),
    .mouse_idx     ()
);

// ─── data_io ─────────────────────────────────────────────────────────────
// Handles BIOS ROM downloads and IDE disk access

wire        ioctl_download;
wire        ioctl_upload;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr_full;
wire [24:0] ioctl_addr = ioctl_addr_full[24:0];
wire [15:0] ioctl_data;
reg         ioctl_wait = 1'b0;
wire [23:0] ioctl_fileext;
wire [31:0] ioctl_filesize;

// IDE interface signals from data_io
wire        hdd_clk = clk_sys;
wire        hdd_cmd_req;
wire        hdd_cdda_req;
wire        hdd_dat_req;
wire        hdd_cdda_wr;
wire        hdd_status_wr;
wire  [2:0] hdd_addr;
wire        hdd_wr;
wire [15:0] hdd_data_out;
wire [15:0] hdd_data_in;
wire        hdd_data_rd;
wire        hdd_data_wr;
wire  [1:0] hdd0_ena;
wire  [1:0] hdd1_ena;

data_io #(
    .START_ADDR     (27'd0),
    .ROM_DIRECT_UPLOAD(1'b1),
    .ENABLE_IDE     (1'b1),
    .DOUT_16        (1'b1)
) data_io_inst (
    .clk_sys       (clk_sys),
    .SPI_SCK       (SPI_SCK),
    .SPI_SS2       (SPI_SS2),
    .SPI_SS4       (SPI_SS4),
    .SPI_DI        (SPI_DI),
    .SPI_DO        (SPI_DO),

    .QCSn          (1'b1),
    .QSCK          (1'b0),
    .QDAT          (4'h0),

    .clkref_n      (1'b0),

    .ioctl_download(ioctl_download),
    .ioctl_upload  (ioctl_upload),
    .ioctl_index   (ioctl_index),
    .ioctl_wr      (ioctl_wr),
    .ioctl_addr    (ioctl_addr_full),
    .ioctl_dout    (ioctl_data),
    .ioctl_din     (8'h00),
    .ioctl_fileext (ioctl_fileext),
    .ioctl_filesize(ioctl_filesize),

    .hdd_clk       (hdd_clk),
    .hdd_cmd_req   (hdd_cmd_req),
    .hdd_cdda_req  (hdd_cdda_req),
    .hdd_dat_req   (hdd_dat_req),
    .hdd_cdda_wr   (hdd_cdda_wr),
    .hdd_status_wr (hdd_status_wr),
    .hdd_addr      (hdd_addr),
    .hdd_wr        (hdd_wr),
    .hdd_data_out  (hdd_data_out),
    .hdd_data_in   (hdd_data_in),
    .hdd_data_rd   (hdd_data_rd),
    .hdd_data_wr   (hdd_data_wr),
    .hdd0_ena      (hdd0_ena),
    .hdd1_ena      (hdd1_ena)
);

// ─── Status / Options ─────────────────────────────────────────────────────
//
// Status bits mapping for MiST:
// [0]     = Reset
// [2:1]   = Scandoubler Fx (None/HQ2x/CRT25%/CRT50%)
// [3]     = Model (0=IBM PCXT, 1=Tandy)
// [4]     = 1st Video (0=CGA, 1=Hercules)
// [7]     = Boot Splash (0=Yes, 1=No)
// [8]     = Composite video (0=Off, 1=On)
// [9]     = Aspect ratio MSB
// [10]    = C/MS Audio (0=Enabled, 1=Disabled)
// [11]    = Lo-tech EMS (0=Enabled, 1=Disabled)
// [13:12] = EMS Frame (C000/D000/E000) -- not in simplified CONF_STR, reserved
// [15:14] = OPL2 mode
// [16]    = Tandy sound
// [19:18] = CPU Speed (from OCD bits)  was OHI in MiSTer
//   00=4.77MHz, 01=7.16MHz, 10=9.54MHz, 11=PC/AT 3.5MHz  (MiST status bits CD)
// [20:19] = Write protect (was OJK in MiSTer, now OAB)
// [21:22] = 2nd SD card (was OLM, not in simplified CONF_STR)
// [29]    = Border (0=No, 1=Yes)  was OT
// [30]    = BIOS Writable MSB
// [31]    = BIOS Writable LSB

// Remap status bits from simplified MiST CONF_STR positions
// The CONF_STR uses positions as per the 'O' option letters:
//   O12 -> status[2:1]  (Scandoubler Fx)
//   O3  -> status[3]    (Model)
//   O4  -> status[4]    (1st Video)
//   O7  -> status[7]    (Boot Splash)
//   O89 -> status[9:8]  (Aspect ratio)
//   OA  -> status[10]   (C/MS Audio)  [hex A = 10]
//   OAB -> status[11:10] (Write Protect) -- conflict! moved OA to separate bits
//   OB  -> status[11]   (EMS)
//   OCD -> status[13:12] (CPU Speed)
//   OEF -> status[15:14] (BIOS Writable)
//   OT  -> status[29]   (Border) [hex T = 29]
//   O8C -> status[... ] (Composite)

// Derived option wires (matching MiSTer bit positions as closely as possible)
wire        composite   = status[8];     // O8C simplified -> use bit 8 for composite
wire [1:0]  scale       = status[2:1];
wire        border      = status[29];
wire [1:0]  cpu_speed   = status[13:12]; // OCD
wire [1:0]  ems_address = 2'b00;        // not in simplified CONF_STR
wire [1:0]  floppy_wp   = status[11:10]; // OAB
wire [1:0]  bios_writable_sel = status[15:14]; // OEF
wire        a000h       = 1'b1;
wire        cms_en      = ~status[16];  // OA

assign reset_btn = buttons[1];

assign LED = ioctl_download | (sd_rd != 4'h0) | (sd_wr != 4'h0);

// ─── CPU Clock Selection ──────────────────────────────────────────────────

logic biu_done;
logic [7:0] clock_cycle_counter_division_ratio;
logic [7:0] clock_cycle_counter_decrement_value;
logic       shift_read_timing;
logic [1:0] ram_read_wait_cycle;
logic [1:0] ram_write_wait_cycle;
logic       cycle_accrate;
logic [1:0] clk_select;

always @(posedge clk_sys, posedge reset)
begin
    if (reset)
        clk_select <= 2'b00;
    else if (biu_done)
        clk_select <= cpu_speed;
    else
        clk_select <= clk_select;
end

logic clk_cpu_ff_1, clk_cpu_ff_2;
logic pclk_ff_1,    pclk_ff_2;
logic clk_cpu;
logic pclk;

always @(posedge clk_sys, posedge reset)
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
        clock_cycle_counter_division_ratio  <= 8'd0;
        clock_cycle_counter_decrement_value <= 8'd1;
        shift_read_timing                   <= 1'b0;
        ram_read_wait_cycle                 <= 2'd0;
        ram_write_wait_cycle                <= 2'd0;
    end
    else
    begin
        clk_cpu_ff_2 <= clk_cpu_ff_1;
        clk_cpu      <= clk_cpu_ff_2;
        pclk_ff_1    <= peripheral_clock;
        pclk_ff_2    <= pclk_ff_1;
        pclk         <= pclk_ff_2;
        casez (clk_select)
            2'b00: begin
                clk_cpu_ff_1                        <= clk_4_77;
                clock_cycle_counter_division_ratio  <= 8'd0;
                clock_cycle_counter_decrement_value <= 8'd1;
                shift_read_timing                   <= 1'b0;
                ram_read_wait_cycle                 <= 2'd0;
                ram_write_wait_cycle                <= 2'd0;
                cycle_accrate                       <= 1'b1;
            end
            2'b01: begin
                clk_cpu_ff_1                        <= clk_7_16;
                clock_cycle_counter_division_ratio  <= 8'd1;
                clock_cycle_counter_decrement_value <= 8'd3;
                shift_read_timing                   <= 1'b0;
                ram_read_wait_cycle                 <= 2'd0;
                ram_write_wait_cycle                <= 2'd0;
                cycle_accrate                       <= 1'b1;
            end
            2'b10: begin
                clk_cpu_ff_1                        <= clk_9_54;
                clock_cycle_counter_division_ratio  <= 8'd9;
                clock_cycle_counter_decrement_value <= 8'd21;
                shift_read_timing                   <= 1'b0;
                ram_read_wait_cycle                 <= 2'd0;
                ram_write_wait_cycle                <= 2'd0;
                cycle_accrate                       <= 1'b1;
            end
            2'b11: begin
                clk_cpu_ff_1                        <= clk_25;
                clock_cycle_counter_division_ratio  <= 8'd0;
                clock_cycle_counter_decrement_value <= 8'd5;
                shift_read_timing                   <= 1'b1;
                ram_read_wait_cycle                 <= 2'd1;
                ram_write_wait_cycle                <= 2'd0;
                cycle_accrate                       <= 1'b0;
            end
        endcase
    end
end

// ─── Splash Screen ────────────────────────────────────────────────────────

reg splash_off = 1'b1;
reg [24:0] splash_cnt = 0;
reg [3:0]  splash_cnt2 = 0;
reg        splashscreen = 1'b0;
reg        splash_pending = 1'b1;
reg [23:0] splash_boot_cnt = 24'd0;
reg        splashscreen_sync1 = 0;
reg        splashscreen_sync2 = 0;
reg        splashscreen_sync_prev = 0;
reg        status0_sync1 = 0;
reg        status0_sync2 = 0;
reg        status0_sync_prev = 0;
wire       status0_clear_pulse = status0_sync2 & ~status0_sync_prev;
reg        splash_reset_hold = 0;
reg [16:0] splash_reset_cnt = 17'd0;
localparam [16:0] SPLASH_RESET_HOLD = 17'd131072;
localparam [23:0] SPLASH_BOOT_WAIT  = 24'd14318000;

always @ (posedge clk_14_318)
begin
    splash_off <= status[7];

    if (splash_pending)
    begin
        if (~splash_off)
        begin
            splashscreen      <= 1'b1;
            splash_cnt        <= 0;
            splash_cnt2       <= 0;
            splash_pending    <= 1'b0;
            splash_boot_cnt   <= 24'd0;
        end
        else if (splash_boot_cnt == SPLASH_BOOT_WAIT)
            splash_pending <= 1'b0;
        else
            splash_boot_cnt <= splash_boot_cnt + 24'd1;
    end
    else if (splashscreen)
    begin
        if (splash_off)
            splashscreen <= 0;
        else if (splash_cnt2 == 5)
            splashscreen <= 0;
        else if (splash_cnt == 14318000)
        begin
            splash_cnt2 <= splash_cnt2 + 1;
            splash_cnt  <= 0;
        end
        else
            splash_cnt <= splash_cnt + 1;
    end
end

always @(posedge clk_sys)
begin
    splashscreen_sync1    <= splashscreen;
    splashscreen_sync2    <= splashscreen_sync1;
    splashscreen_sync_prev <= splashscreen_sync2;
    status0_sync1         <= status[0];
    status0_sync2         <= status0_sync1;
    status0_sync_prev     <= status0_sync2;

    if (splashscreen_sync_prev && ~splashscreen_sync2)
    begin
        splash_reset_hold <= 1'b1;
        splash_reset_cnt  <= 17'd0;
    end
    else if (splash_reset_hold)
    begin
        if (splash_reset_cnt == SPLASH_RESET_HOLD)
            splash_reset_hold <= 1'b0;
        else
            splash_reset_cnt <= splash_reset_cnt + 17'd1;
    end
end

// ─── PS2 keyboard FF ─────────────────────────────────────────────────────

logic device_clock_ff, device_clock;
logic device_data_ff,  device_data;

always_ff @(negedge clk_sys, posedge reset)
begin
    if (reset)
    begin
        device_clock_ff <= 1'b0;
        device_clock    <= 1'b0;
    end
    else
    begin
        device_clock_ff <= ps2_kbd_clk_in;
        device_clock    <= device_clock_ff;
    end
end

always_ff @(negedge clk_sys, posedge reset)
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

// ─── CPU and Chipset signals ──────────────────────────────────────────────

wire  [7:0] data_bus;
wire        INTA_n;
wire [19:0] cpu_ad_out;
reg  [19:0] cpu_address;
wire  [7:0] cpu_data_bus;
wire        processor_ready;
wire        interrupt_to_cpu;
wire        address_latch_enable;
wire        address_direction;
wire        lock_n;
wire  [2:0] processor_status;
wire  [3:0] dma_acknowledge_n;

logic [7:0] port_b_out;
logic [7:0] port_c_in;
wire  [1:0] fdd_present;
reg   [7:0] sw;

wire  [5:0] sw_base;
wire  [1:0] sw_floppy;

assign sw_base   = hgc_mode ? 6'b111101 : 6'b101101;
assign sw_floppy = fdd_present[1] ? 2'b01 : 2'b00;
assign sw        = {sw_floppy, sw_base};
assign port_c_in[3:0] = port_b_out[3] ? sw[7:4] : sw[3:0];

always @(posedge clk_sys)
begin
    if (address_latch_enable)
        cpu_address <= cpu_ad_out;
    else
        cpu_address <= cpu_address;
end

// ─── BIOS Loader ─────────────────────────────────────────────────────────

reg  [4:0]  bios_load_state = 4'h0;
reg  [1:0]  bios_protect_flag;
reg         bios_access_request;
reg [19:0]  bios_access_address;
reg [15:0]  bios_write_data;
reg         bios_write_n;
reg  [7:0]  bios_write_wait_cnt;
reg         bios_write_byte_cnt;
reg         tandy_bios_write;

wire select_pcxt  = (ioctl_index[5:0] == 0) && (ioctl_addr[24:16] == 9'b000000000);
wire select_tandy = (ioctl_index[5:0] == 1) && (ioctl_addr[24:16] == 9'b000000000);
wire select_xtide = ioctl_index == 2;

wire [19:0] bios_access_address_wire =
    select_pcxt  ? {4'b1111, ioctl_addr[15:0]} :
    select_tandy ? {4'b1111, ioctl_addr[15:0]} :
    select_xtide ? {6'b111011, ioctl_addr[13:0]} :
    20'hFFFFF;

wire bios_load_n = ~(ioctl_download & (select_pcxt | select_tandy | select_xtide));

wire tandy_bios_flag = bios_write_n ? tandy_mode : tandy_bios_write;

always @(posedge clk_sys, posedge reset_sdram)
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
            4'h00: begin
                bios_protect_flag   <= ~bios_writable;
                bios_access_address <= 20'hFFFFF;
                bios_write_data     <= 16'hFFFF;
                bios_write_n        <= 1'b1;
                bios_write_wait_cnt <= 'h0;
                bios_write_byte_cnt <= 1'h0;
                tandy_bios_write    <= 1'b0;
                if (~ioctl_download) begin
                    bios_access_request <= 1'b0;
                    ioctl_wait          <= 1'b0;
                end else begin
                    bios_access_request <= 1'b1;
                    ioctl_wait          <= 1'b1;
                end
                if ((ioctl_download) && (~processor_ready) && (address_direction))
                    bios_load_state <= 4'h01;
                else
                    bios_load_state <= 4'h00;
            end
            4'h01: begin
                bios_protect_flag   <= 2'b00;
                bios_access_request <= 1'b1;
                bios_write_byte_cnt <= 1'h0;
                tandy_bios_write    <= select_tandy;
                if (~ioctl_download) begin
                    bios_access_address <= 20'hFFFFF;
                    bios_write_data     <= 16'hFFFF;
                    bios_write_n        <= 1'b1;
                    bios_write_wait_cnt <= 'h0;
                    ioctl_wait          <= 1'b0;
                    bios_load_state     <= 4'h00;
                end else if ((~ioctl_wr) || (bios_load_n)) begin
                    bios_access_address <= 20'hFFFFF;
                    bios_write_data     <= 16'hFFFF;
                    bios_write_n        <= 1'b1;
                    bios_write_wait_cnt <= 'h0;
                    ioctl_wait          <= 1'b0;
                    bios_load_state     <= 4'h01;
                end else begin
                    bios_access_address <= bios_access_address_wire;
                    bios_write_data     <= ioctl_data;
                    bios_write_n        <= 1'b1;
                    bios_write_wait_cnt <= 'h0;
                    ioctl_wait          <= 1'b1;
                    bios_load_state     <= 4'h02;
                end
            end
            4'h02: begin
                bios_protect_flag   <= 2'b00;
                bios_access_request <= 1'b1;
                bios_access_address <= bios_access_address;
                bios_write_data     <= bios_write_data;
                bios_write_byte_cnt <= bios_write_byte_cnt;
                tandy_bios_write    <= select_tandy;
                ioctl_wait          <= 1'b1;
                bios_write_wait_cnt <= bios_write_wait_cnt + 'h1;
                if (bios_write_wait_cnt != 'd20) begin
                    bios_write_n    <= 1'b0;
                    bios_load_state <= 4'h02;
                end else begin
                    bios_write_n    <= 1'b1;
                    bios_load_state <= 4'h03;
                end
            end
            4'h03: begin
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
                    bios_load_state <= 4'h03;
                else
                    bios_load_state <= 4'h04;
            end
            4'h04: begin
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
                    bios_load_state <= 4'h02;
                else
                    bios_load_state <= 4'h01;
            end
            default: begin
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

// BIOS protect flag from option
wire [1:0] bios_writable = status[15:14]; // OEF -> bits [15:14]

// ─── Management (Floppy/IDE) bridge ──────────────────────────────────────
//
// In MiSTer, the ARM communicates with the PCXT chipset via hps_ext (EXT_BUS).
// In MiST, we implement a bridge using user_io SD card (for floppy) and
// data_io IDE interface (for IDE hard disk).

wire [15:0] mgmt_din;
wire [15:0] mgmt_dout;
wire [15:0] mgmt_addr;
wire        mgmt_rd;
wire        mgmt_wr;
wire  [7:0] mgmt_req;
assign mgmt_req[5:3] = 3'b000;

mist_io_bridge mist_io_bridge_inst (
    .clk_sys       (clk_sys),
    .reset         (reset),

    // From Chipset
    .mgmt_req      (mgmt_req),
    .mgmt_dout     (mgmt_dout),
    .mgmt_din      (mgmt_din),
    .mgmt_addr     (mgmt_addr),
    .mgmt_rd       (mgmt_rd),
    .mgmt_wr       (mgmt_wr),

    // user_io SD card (floppy images - drives 0 and 1)
    .sd_lba        (sd_lba),
    .sd_rd         (sd_rd[1:0]),
    .sd_wr         (sd_wr[1:0]),
    .sd_ack        (sd_ack),
    .sd_dout       (sd_dout),
    .sd_dout_strobe(sd_dout_strobe),
    .sd_din        (sd_din),
    .sd_din_strobe (sd_din_strobe),
    .sd_buff_addr  (sd_buff_addr),
    .img_mounted   (img_mounted[1:0]),
    .img_size      (img_size),
    .sd_conf       (sd_conf),
    .sd_sdhc       (sd_sdhc),

    // data_io IDE (hard disk images)
    .hdd_cmd_req   (hdd_cmd_req),
    .hdd_cdda_req  (hdd_cdda_req),
    .hdd_dat_req   (hdd_dat_req),
    .hdd_status_wr (hdd_status_wr),
    .hdd_addr      (hdd_addr),
    .hdd_wr        (hdd_wr),
    .hdd_data_out  (hdd_data_out),
    .hdd_data_in   (hdd_data_in),
    .hdd_data_rd   (hdd_data_rd),
    .hdd_data_wr   (hdd_data_wr),
    .hdd0_ena      (hdd0_ena),
    .hdd1_ena      (hdd1_ena),

    // FDD status
    .fdd_present   (fdd_present)
);

// ─── SDRAM ────────────────────────────────────────────────────────────────

wire [15:0] SDRAM_DQ_IN  = SDRAM_DQ;
wire [15:0] SDRAM_DQ_OUT;
wire        SDRAM_DQ_IO;
wire        initilized_sdram;

assign SDRAM_DQ  = ~SDRAM_DQ_IO ? SDRAM_DQ_OUT : 16'hZZZZ;
assign SDRAM_CLK = clk_sys;

// ─── Audio ────────────────────────────────────────────────────────────────

wire [15:0] cms_l_snd_e;
wire [16:0] cms_l_snd = {cms_l_snd_e[15], cms_l_snd_e};
wire [15:0] cms_r_snd_e;
wire [16:0] cms_r_snd = {cms_r_snd_e[15], cms_r_snd_e};

wire [15:0] jtopl2_snd_e;
wire [16:0] jtopl2_snd = {jtopl2_snd_e[15], jtopl2_snd_e};
wire [10:0] tandy_snd_e;
wire [16:0] tandy_snd   = {{6{tandy_snd_e[10]}}, tandy_snd_e, 2'b00};
wire        speaker_out;
wire [16:0] spk_vol     = {2'b00, {3'b000, ~speaker_out}, 11'd0};

reg [15:0] out_l;
reg [15:0] out_r;

always @(posedge clk_sys)
begin
    reg [16:0] tmp_l, tmp_r;
    tmp_l = jtopl2_snd + cms_l_snd + tandy_snd + spk_vol;
    tmp_r = jtopl2_snd + cms_r_snd + tandy_snd + spk_vol;
    out_l <= (^tmp_l[16:15]) ? {tmp_l[16], {15{tmp_l[15]}}} : tmp_l[15:0];
    out_r <= (^tmp_r[16:15]) ? {tmp_r[16], {15{tmp_r[15]}}} : tmp_r[15:0];
end

// Sigma-delta DAC for AUDIO_L / AUDIO_R
dac #(.C_bits(16)) dac_l (
    .clk_i  (clk_sys),
    .res_n_i(~reset),
    .dac_i  (out_l),
    .dac_o  (AUDIO_L)
);

dac #(.C_bits(16)) dac_r (
    .clk_i  (clk_sys),
    .res_n_i(~reset),
    .dac_i  (out_r),
    .dac_o  (AUDIO_R)
);

// ─── UART ─────────────────────────────────────────────────────────────────

wire uart_tx, uart_rts, uart_dtr;
wire uart_rx  = UART_RX;
wire uart_cts = 1'b0;
wire uart_dsr = 1'b0;
wire uart_dcd = 1'b0;

assign UART_TX = uart_tx;

// UART clock enable: 14.318 MHz / 8 = ~1.789 MHz
logic clk_uart_ff_1, clk_uart_ff_2, clk_uart_ff_3;
logic clk_uart_en;
logic clk_uart2_en;
logic [2:0] clk_uart2_counter;

always @(posedge clk_sys)
begin
    clk_uart_ff_1 <= clk_14_318;
    clk_uart_ff_2 <= clk_uart_ff_1;
    clk_uart_ff_3 <= clk_uart_ff_2;
    clk_uart_en   <= ~clk_uart_ff_3 & clk_uart_ff_2;
end

always @(posedge clk_sys)
begin
    if (clk_uart_en)
    begin
        if (3'd7 != clk_uart2_counter)
        begin
            clk_uart2_counter <= clk_uart2_counter + 3'd1;
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

// ─── Video ────────────────────────────────────────────────────────────────

wire        HBlank;
wire        HSync;
wire        VBlank;
wire        VSync;
reg         ce_pixel_cga;
wire  [5:0] r, g, b;
reg  [7:0]  raux_cga, gaux_cga, baux_cga;

// CGA pixel clock: 14.318 MHz (every other 28.636 MHz cycle)
always @(posedge clk_28_636) begin
    ce_pixel_cga <= ~ce_pixel_cga;
end

wire swap_video;
wire pause_core;
wire std_hsyncwidth;
wire VGA_VBlank_border;
wire tandy_16_gfx;
wire [7:0] tandy_color_16;

// HBlank delay chain for border
reg [14:0] HBlank_del;
always @(posedge clk_28_636) begin
    HBlank_del <= {HBlank_del[13:0], HBlank};
end

wire HBlank_VGA;
always_comb begin
    if (tandy_color_16)
        HBlank_VGA = HBlank_del[11];
    else if (tandy_16_gfx)
        HBlank_VGA = HBlank_del[9];
    else
        HBlank_VGA = HBlank_del[5];
end

wire LHBL = border ? HBlank_VGA : HBlank_VGA; // simplified: border handled by chipset
wire LVBL = VBlank;

// Monochrome converter
wire  [2:0] screen_mode = status[16:14]; // OEG position -- simplified
wire color = (screen_mode == 3'd0);

video_monochrome_converter video_mono_cga (
    .clk_vid  (clk_28_636),
    .ce_pix   (ce_pixel_cga),
    .R        ({r, 2'b00}),
    .G        ({g, 2'b00}),
    .B        ({b, 2'b00}),
    .gfx_mode (screen_mode),
    .R_OUT    (raux_cga),
    .G_OUT    (gaux_cga),
    .B_OUT    (baux_cga)
);

// mist_video: scandoubler + OSD + YPbPr
wire [5:0] video_r = raux_cga[7:2];
wire [5:0] video_g = gaux_cga[7:2];
wire [5:0] video_b = baux_cga[7:2];

mist_video #(
    .COLOR_DEPTH      (6),
    .OUT_COLOR_DEPTH  (6),
    .USE_BLANKS       (1'b1),
    .BIG_OSD          (1'b0),
    .SD_HCNT_WIDTH    (10)
) mist_video_inst (
    .clk_sys           (clk_28_636),
    .SPI_SCK           (SPI_SCK),
    .SPI_SS3           (SPI_SS3),
    .SPI_DI            (SPI_DI),
    .scandoubler_disable(scandoubler_disable),
    .no_csync          (no_csync),
    .ypbpr             (ypbpr),
    .rotate            (2'b00),
    .blend             (composite),
    .scanlines         (scale == 2'b01 ? 2'b00 :
                        scale == 2'b10 ? 2'b01 :
                        scale == 2'b11 ? 2'b10 : 2'b00),
    .ce_divider        (3'd1),
    .R                 (video_r),
    .G                 (video_g),
    .B                 (video_b),
    .HBlank            (LHBL),
    .VBlank            (LVBL),
    .HSync             (HSync),
    .VSync             (VSync),
    .osd_enable        (),
    .VGA_R             (VGA_R),
    .VGA_G             (VGA_G),
    .VGA_B             (VGA_B),
    .VGA_HS            (VGA_HS),
    .VGA_VS            (VGA_VS),
    .VGA_HB            (),
    .VGA_VB            (),
    .VGA_DE            ()
);

// ─── Chipset instantiation ────────────────────────────────────────────────

localparam [27:0] cur_rate = 28'd50000000;

wire hgc_mode_chipset = hgc_mode & ~tandy_mode;

CHIPSET #(.clk_rate(cur_rate)) u_CHIPSET (
    .clock                              (clk_sys),
    .cpu_clock                          (clk_cpu),
    .clk_sys                            (clk_sys),
    .peripheral_clock                   (pclk),
    .clk_select                         (clk_select),
    .reset                              (reset_cpu),
    .sdram_reset                        (reset_sdram),
    .cpu_address                        (cpu_address),
    .cpu_data_bus                       (cpu_data_bus),
    .processor_status                   (processor_status),
    .processor_lock_n                   (lock_n),
    .processor_ready                    (processor_ready),
    .interrupt_to_cpu                   (interrupt_to_cpu),
    .splashscreen                       (splashscreen),
    .status0_clear                      (status0_clear_pulse),
    .std_hsyncwidth                     (std_hsyncwidth),
    .composite                          (composite),
    .video_output                       (hgc_mode_chipset),
    .clk_vga_cga                        (clk_28_636),
    .enable_cga                         (1'b1),
    .clk_vga_hgc                        (clk_57_272),
    .enable_hgc                         (1'b1),
    .hgc_rgb                            (2'b10),
    .VGA_R                              (r),
    .VGA_G                              (g),
    .VGA_B                              (b),
    .VGA_HSYNC                          (HSync),
    .VGA_VSYNC                          (VSync),
    .VGA_HBlank                         (HBlank),
    .VGA_VBlank                         (VBlank),
    .VGA_VBlank_border                  (VGA_VBlank_border),
    .address_ext                        (bios_access_address),
    .ext_access_request                 (bios_access_request),
    .address_direction                  (address_direction),
    .data_bus                           (data_bus),
    .data_bus_ext                       (bios_write_data[7:0]),
    .address_latch_enable               (address_latch_enable),
    .io_channel_check                   (1'b0),
    .io_channel_ready                   (1'b1),
    .io_read_n_ext                      (1'b1),
    .io_write_n_ext                     (1'b1),
    .memory_read_n_ext                  (1'b1),
    .memory_write_n_ext                 (1'b1),
    .interrupt_request                  (0),
    .dma_request                        (0),
    .dma_acknowledge_n                  (dma_acknowledge_n),
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
    .joy_opts                           (5'b00000),
    .joy0                               (joystick_0[13:0]),
    .joy1                               (joystick_1[13:0]),
    .joya0                              (joystick_analog_0[15:0]),
    .joya1                              (joystick_analog_1[15:0]),
    .jtopl2_snd_e                       (jtopl2_snd_e),
    .tandy_snd_e                        (tandy_snd_e),
    .opl2_io                            (2'b00),
    .cms_en                             (cms_en),
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
    .sdram_clock                        (clk_sys),
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
    .ems_address                        (ems_address),
    .bios_protect_flag                  (bios_protect_flag),
    .use_mmc                            (2'b00),     // MMC disabled; SD access via user_io
    .spi_clk                            (),
    .spi_cs                             (),
    .spi_mosi                           (),
    .spi_miso                           (1'b1),
    .mgmt_readdata                      (mgmt_din),
    .mgmt_writedata                     (mgmt_dout),
    .mgmt_address                       (mgmt_addr),
    .mgmt_write                         (mgmt_wr),
    .mgmt_read                          (mgmt_rd),
    .floppy_wp                          (floppy_wp),
    .fdd_present                        (fdd_present),
    .fdd_request                        (mgmt_req[7:6]),
    .ide0_request                       (mgmt_req[2:0]),
    .xtctl                              (),          // output not used on MiST
    .enable_a000h                       (a000h),
    .wait_count_clk_en                  (~clk_cpu & clk_cpu_ff_2),
    .ram_read_wait_cycle                (ram_read_wait_cycle),
    .ram_write_wait_cycle               (ram_write_wait_cycle),
    .pause_core                         (pause_core),
    .cga_hw                             (1'b1),
    .hercules_hw                        (~tandy_mode),
    .swap_video                         (swap_video),
    .crt_h_offset                       (4'h0),
    .crt_v_offset                       (3'h0)
);

// ─── i8088 CPU ────────────────────────────────────────────────────────────

wire [2:0] SEGMENT;
wire       s6_3_mux;

i8088 B1 (
    .CORE_CLK  (clk_100),
    .CLK       (clk_cpu),
    .RESET     (reset_cpu),
    .READY     (processor_ready && ~pause_core),
    .NMI       (1'b0),
    .INTR      (interrupt_to_cpu),
    .ad_out    (cpu_ad_out),
    .dout      (cpu_data_bus),
    .din       (data_bus),
    .lock_n    (lock_n),
    .s6_3_mux  (s6_3_mux),
    .s2_s0_out (processor_status),
    .SEGMENT   (SEGMENT),
    .biu_done  (biu_done),
    .cycle_accrate (cycle_accrate),
    .clock_cycle_counter_division_ratio  (clock_cycle_counter_division_ratio),
    .clock_cycle_counter_decrement_value (clock_cycle_counter_decrement_value),
    .shift_read_timing                   (shift_read_timing)
);

endmodule
