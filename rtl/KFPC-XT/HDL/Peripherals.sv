//
// MiSTer PCXT Peripherals
// Ported by @spark2k06
//
// Based on KFPC-XT written by @kitune-san
//
`ifndef ENABLE_TANDY_VIDEO
`define ENABLE_TANDY_VIDEO 0
`endif
`ifndef ENABLE_TANDY_AUDIO
`define ENABLE_TANDY_AUDIO 0
`endif
`ifndef ENABLE_TANDY_KBD
`define ENABLE_TANDY_KBD 0
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
`ifndef ENABLE_MIDI
`define ENABLE_MIDI 1
`endif
`ifndef ENABLE_SB
`define ENABLE_SB 0
`endif
// The EGA/VGA card is built into the RBF, and with it the VGA 13h+ extension
//. Without ENABLE_EGA nothing of the EGA is instantiated.
`ifndef ENABLE_EGA
`define ENABLE_EGA 0
`endif
`ifndef ENABLE_VGA13
`define ENABLE_VGA13 1
`endif

module PERIPHERALS #(
        parameter ps2_over_time = 16'd1000,
		parameter clk_rate = 28'd50000000
    ) (
        input   logic           clock,
        input   logic           clk_sys,
        input   logic           cpu_ce_posedge,
        input   logic           cpu_ce_negedge,
        input   logic           peripheral_ce,
        input   logic   [1:0]   clk_select,
        input   logic           reset,
        // CPU
        output  logic           interrupt_to_cpu,
        // Bus Arbiter
        input   logic           interrupt_acknowledge_n,
        output  logic           dma_chip_select_n,
        output  logic           dma_page_chip_select_n,
        // SplashScreen
        input   logic           splashscreen,
        // Video card chosen at reset: 1 = EGA/VGA, 0 = CGA/Hercules. Static for
        // as long as the machine runs; the card that is not chosen is held in
        // reset and kept off the bus.
        input   logic           ega_active,
        // VGA
        output  logic           std_hsyncwidth,
        input   logic           composite,
        input   logic           video_reset,
        input   logic           video_output,
        input   logic           clk_vga_cga,
        input   logic           enable_cga,
        input   logic           clk_vga_hgc,
        input   logic           enable_hgc,
        input   logic   [1:0]   hgc_rgb,
        output  logic           de_o,
        output  logic   [5:0]   VGA_R,
        output  logic   [5:0]   VGA_G,
        output  logic   [5:0]   VGA_B,
        output  logic           VGA_HSYNC,
        output  logic           VGA_VSYNC,
        output  logic           VGA_HBlank,
        output  logic           VGA_VBlank,
        output  logic           VGA_VBlank_border,
        output  logic           VGA_HSYNC_REF,
        output  logic           VGA_VSYNC_REF,
        output  logic           cga_memory_ready,
        output  logic           cga_memory_write_wait,
        // EGA/VGA card outputs (clk_vga_cga domain), zero without ENABLE_EGA
        output  logic   [5:0]   EGA_R,
        output  logic   [5:0]   EGA_G,
        output  logic   [5:0]   EGA_B,
        output  logic           EGA_HSYNC,
        output  logic           EGA_VSYNC,
        output  logic           EGA_HBlank,
        output  logic           EGA_VBlank,
        output  logic           EGA_VBlank_border,
        output  logic           EGA_std_hsyncwidth,
        output  logic           EGA_de_o,
        // EGA dot clock and mode status, clk_vga_cga domain
        output  logic           ega_dot_toggle,
        output  logic           ega_dot_clock_sel,
        output  logic           ega_scandouble_active_out,
        output  logic           ega_vmode_toggle_out,
        // Geometry of the picture the CRTC is currently asked for, latched
        // once a frame. What the 480i converter switches on.
        output  logic           ega_mode350,
        output  logic   [11:0]  ega_active_dots,
        output  logic   [9:0]   ega_active_lines,
        input   logic           vga_mode13_osd,
        input   logic           vga_mode13_native,
        input   logic   [1:0]   ega_monitor_profile,
        output  logic           vga_mode13_active_out,
        output  logic           vga_mode13_wide_clock_out,
        output  logic           vga_mode13_pixel_toggle_out,
        // I/O Ports
        input   logic   [19:0]  address,
        output  logic   [19:0]  latch_address,
        input   logic   [7:0]   internal_data_bus,
        output  logic   [7:0]   data_bus_out,
        output  logic           data_bus_out_from_chipset,
        input   logic   [7:0]   interrupt_request,
        input   logic           io_read_n,
        input   logic           io_write_n,
        input   logic           memory_read_n,
        input   logic           memory_write_n,
        input   logic           address_enable_n,
        input   logic           warm_boot_marker_event,
        // EGA video memory in SDRAM (F3). The frontend's side of the CPU memory
        // port (chipset clock), its client end of the arbiter's video port and
        // the captured writes it snoops (sdram clock), and whether the packed
        // 13h framebuffer is the CPU's A0000 window (served by cpu_mem_port).
        output  logic           video_memory_access_ready,
        output  logic           video_io_access_ready,
        output  logic           vram_m_start,
        output  logic           vram_m_we,
        output  logic   [23:0]  vram_m_addr,
        output  logic   [1:0]   vram_m_len,
        output  logic   [63:0]  vram_m_wdata,
        output  logic   [7:0]   vram_m_wbe,
        input   logic           vram_m_busy,
        input   logic           vram_m_done,
        input   logic   [63:0]  vram_m_rdata,
        input   logic           sdram_clk,
        input   logic           sdram_reset,
        output  logic           vid_req,
        output  logic   [23:0]  vid_addr,
        output  logic   [1:0]   vid_len,
        output  logic   [15:0]  vid_deadline,
        input   logic           vid_ack,
        input   logic           vid_rvalid,
        input   logic           vid_rlast,
        input   logic   [15:0]  vid_rdata,
        input   logic           snoop_valid,
        input   logic   [23:0]  snoop_addr,
        input   logic   [1:0]   snoop_len,
        input   logic   [63:0]  snoop_wdata,
        input   logic   [7:0]   snoop_wbe,
        output  logic           vga13_packed_cpu,
        // Peripherals
        output  logic   [2:0]   timer_counter_out,
        output  logic           speaker_out,
        output  logic   [7:0]   port_a_out,
        output  logic           port_a_io,
        input   logic   [7:0]   port_b_in,
        output  logic   [7:0]   port_b_out,
        output  logic           port_b_io,
        input   logic   [7:0]   port_c_in,
        output  logic   [7:0]   port_c_out,
        output  logic   [7:0]   port_c_io,
        input   logic           ps2_clock,
        input   logic           ps2_data,
        output  logic           ps2_clock_out,
        output  logic           ps2_data_out,
        input   logic           ps2_mouseclk_in,
        input   logic           ps2_mousedat_in,
        output  logic           ps2_mouseclk_out,
        output  logic           ps2_mousedat_out,
        input   logic   [4:0]   joy_opts,
        input   logic   [13:0]  joy0,
        input   logic   [13:0]  joy1,
        input   logic   [15:0]  joya0,
        input   logic   [15:0]  joya1,
        // JTOPL
        output  logic   [15:0]  jtopl2_snd_e,
        input   logic   [1:0]   opl2_io,
        // Sound Blaster Pro
        input   logic           sb_en,
        input   logic           sb_irq7,
        output  logic   [15:0]  sb_snd_l,
        output  logic   [15:0]  sb_snd_r,
        output  logic           sb_dma_req,
        input   logic           sb_dma_ack,
        // Tandy 1000 sound switch (XTEGACTL): 0 takes the SN76489 off the bus
        input   logic           tandy_en,
        // C/MS Audio
        input   logic           cms_en,
        output  reg     [15:0]  o_cms_l,
        output  reg     [15:0]  o_cms_r,
        // TANDY
        input   logic           tandy_video,
        output  logic   [10:0]  tandy_snd_e,
        output  logic           tandy_snd_rdy,
        output  logic           tandy_16_gfx,
        output  logic           tandy_color_16,
        // UART
        input   logic           clk_uart,
        input   logic           clk_uart_com2,      // 1.8432 MHz reference for COM2 only
        input   logic           uart2_rx,
        output  logic           uart2_tx,
        input   logic           uart2_cts_n,
        input   logic           uart2_dcd_n,
        input   logic           uart2_dsr_n,
        output  logic           uart2_rts_n,
        output  logic           uart2_dtr_n,
        // MPU-401 (MIDI / MT32-pi)
        input   logic           clk_midi,
        input   logic           midi_rx,
        output  logic           midi_tx,
        input   logic           mpu401_enabled,
        // EMS
        input   logic           ems_enabled,
        input   logic   [1:0]   ems_address,
        output  reg     [6:0]   map_ems[0:3], // Segment hx000, hx400, hx800, hxC00
        output  reg             ena_ems[0:3], // Enable Segment Map hx000, hx400, hx800, hxC00
        output  logic           ems_b1,
        output  logic           ems_b2,
        output  logic           ems_b3,
        output  logic           ems_b4,
        // MMC interface
        input   logic   [1:0]   use_mmc,
        output  logic           spi_clk,
        output  logic           spi_cs,
        output  logic           spi_mosi,
        input   logic           spi_miso,
        // FDD
        input   logic   [15:0]  mgmt_address,
        input   logic           mgmt_read,
        output  logic   [15:0]  mgmt_readdata,
        input   logic           mgmt_write,
        input   logic   [15:0]  mgmt_writedata,
        input   logic   [1:0]   floppy_wp,
        output  logic   [1:0]   fdd_present,
        output  logic   [1:0]   fdd_request,
        output  logic   [2:0]   ide0_request,
        output  logic           fdd_dma_req,
        input   logic           fdd_dma_ack,
        input   logic           terminal_count,
        // XTCTL DATA: legacy 8888h register (CGA family only)
        output  logic   [7:0]   xtctl = 8'h00,
        // XTEGACTL register file (8980h..898Fh), interpreted by xtegactl_resolve
        // up top. Common to every video card.
        output  logic   [7:0]   xtegactl_cpu,
        output  logic   [7:0]   xtegactl_exp,
        output  logic   [7:0]   xtegactl_vid,
        output  logic   [7:0]   xtegactl_inp,
        output  logic   [7:0]   xtegactl_midi,
        output  logic   [7:0]   xtegactl_exp2,
        output  logic   [7:0]   xtegactl_crt,
        output  logic   [7:0]   xtegactl_sync,
        // Read-only effective XTEGACTL status, supplied by the top level where
        // the OSD values are available.
        input   logic   [39:0]  xtegactl_status_effective,
        input   logic   [17:0]  xtegactl_status_osd_match,
        // Identification block (8990h..8997h)
        input   logic   [1:0]   id_video_card,
        input   logic           id_vga13_active,
        input   logic   [7:0]   id_cpu_latency_max,
        // Others
        output  logic           pause_core,
        input   logic           cga_hw,
        input   logic           cga_scandouble_en,
        input   logic           hercules_hw,
        output  logic           swap_video,
        input   logic   [3:0]   crt_h_offset,
        input   logic   [2:0]   crt_v_offset,
        input   logic   [2:0]   vsync_width_osd,
        input   logic   [2:0]   hsync_width_osd,
        input   logic           cga_frame_stack_rebuild,
        // Video memory is in SDRAM (F2). The CPU reaches it through the memory
        // port; the adapters read it through the video fetch engines, which are
        // in the clk_sdram domain at the top level. These are the adapters'
        // views of the CRTC and the bytes they get back.
        input   logic   [7:0]   fx_cga_vram_d,
        output  logic   [4:0]   fx_cga_phase,
        output  logic           fx_cga_hres,
        output  logic   [13:0]  fx_cga_cur_word,
        output  logic   [13:0]  fx_cga_next_word,
        input   logic   [7:0]   fx_hgc_vram_d,
        output  logic   [4:0]   fx_hgc_phase,
        output  logic           fx_hgc_grph,
        output  logic           fx_hgc_page,
        output  logic   [13:0]  fx_hgc_cur_word,
        output  logic   [13:0]  fx_hgc_next_word,
        // Hercules graphics page, in the chipset clock domain, for the memory map
        output  logic           hgc_page_sys
    );

    wire [4:0] clkdiv;
    wire grph_mode;
    wire hres_mode;
    wire bw_mode;
    wire mode_640;
    wire [3:0] composite_hsync_width;
    wire [3:0] composite_border_color;
    wire composite_phase;

    // video_reset is generated outside the CGA/HGC clock domains. Assert it
    // immediately, but release it only on the clock that consumes it so the
    // video state machines cannot leave reset close to an active edge.
    (* ASYNC_REG = "TRUE" *) logic [1:0] video_reset_cga_sync = 2'b11;
    (* ASYNC_REG = "TRUE" *) logic [1:0] video_reset_hgc_sync = 2'b11;
    wire video_reset_cga = video_reset_cga_sync[1];
    wire video_reset_hgc = video_reset_hgc_sync[1];

    // The chosen card is static once the machine is out of reset, so one
    // synchroniser per clock domain is all the crossing needs.
    (* ASYNC_REG = "TRUE" *) logic [1:0] ega_active_cga_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) logic [1:0] ega_active_hgc_sync = 2'b00;
    wire ega_active_cga = `ENABLE_EGA ? ega_active_cga_sync[1] : 1'b0;
    wire ega_active_hgc = `ENABLE_EGA ? ega_active_hgc_sync[1] : 1'b0;

    always_ff @(posedge clk_vga_cga)
        ega_active_cga_sync <= {ega_active_cga_sync[0], ega_active};

    always_ff @(posedge clk_vga_hgc)
        ega_active_hgc_sync <= {ega_active_hgc_sync[0], ega_active};

    always_ff @(posedge clk_vga_cga or posedge video_reset) begin
        if (video_reset)
            video_reset_cga_sync <= 2'b11;
        else
            video_reset_cga_sync <= {video_reset_cga_sync[0], 1'b0};
    end

    always_ff @(posedge clk_vga_hgc or posedge video_reset) begin
        if (video_reset)
            video_reset_hgc_sync <= 2'b11;
        else
            video_reset_hgc_sync <= {video_reset_hgc_sync[0], 1'b0};
    end

    wire tandy_video_en = `ENABLE_TANDY_VIDEO ? tandy_video : 1'b0;
    wire tandy_audio_en = `ENABLE_TANDY_AUDIO ? tandy_en : 1'b0;
    wire tandy_kbd_en = `ENABLE_TANDY_KBD ? 1'b1 : 1'b0;

    wire tandy_io_en = tandy_video_en | tandy_audio_en;

    wire hgc_enable = `ENABLE_HGC ? (enable_hgc & ~ega_active) : 1'b0;
    wire hgc_grph_mode;
    wire hgc_grph_page;

    assign tandy_16_gfx = `ENABLE_CGA ? (tandy_video_en & grph_mode & hres_mode) : 1'b0;

    // Handed between the shared decoders below and the EGA block at the end
    // of the video section.
    wire        ega_mem_select_raw;
    wire        ega_mem_select;
    wire  [1:0] ega_mem_map_sel_cfg;
    wire        vga13_packed_cpu_w;
    wire        ega_io_oe_sys;
    wire  [7:0] ega_io_dout_sys;
    wire        ega_switch_sense_oe;
    wire  [7:0] ega_switch_sense_data;
    wire  [7:0] ega_vram_cpu_dout;
    wire [15:0] id_video_underruns;

    function automatic logic ega_memory_window_select(
        input logic [19:0] addr,
        input logic [1:0]  mem_map_sel
    );
        begin
            case (mem_map_sel)
                2'b00:  ega_memory_window_select = (addr[19:17] == 3'b101);   // A0000 - BFFFF
                2'b01:  ega_memory_window_select = (addr[19:16] == 4'hA);     // A0000 - AFFFF
                2'b10:  ega_memory_window_select = (addr[19:15] == 5'b10110); // B0000 - B7FFF
                2'b11:  ega_memory_window_select = (addr[19:15] == 5'b10111); // B8000 - BFFFF
                default: ega_memory_window_select = 1'b0;
            endcase
        end
    endfunction



    //
    // chip select
    //
    logic   [7:0]   chip_select_n;

    always_comb
    begin
        if (iorq & ~address_enable_n & ~address[9] & ~address[8] & (tandy_video_en ? ~address[4] : 1'b1))
        begin
            casez (address[7:5])
                3'b000:
                    chip_select_n = 8'b11111110;
                3'b001:
                    chip_select_n = 8'b11111101;
                3'b010:
                    chip_select_n = 8'b11111011;
                3'b011:
                    chip_select_n = 8'b11110111;
                3'b100:
                    chip_select_n = 8'b11101111;
                3'b101:
                    chip_select_n = 8'b11011111;
                3'b110:
                    chip_select_n = 8'b10111111;
                3'b111:
                    chip_select_n = 8'b01111111;
                default:
                    chip_select_n = 8'b11111111;
            endcase
        end
        else
        begin
            chip_select_n = 8'b11111111;
        end
    end

    wire    iorq = ~io_read_n | ~io_write_n;

    assign  dma_chip_select_n       = chip_select_n[0]; // 0x00 .. 0x1F
    wire    interrupt_chip_select_n = chip_select_n[1]; // 0x20 .. 0x3F
    wire    timer_chip_select_n     = chip_select_n[2]; // 0x40 .. 0x5F
    wire    ppi_chip_select_n       = chip_select_n[3]; // 0x60 .. 0x7F
    assign  dma_page_chip_select_n  = chip_select_n[4]; // 0x80 .. 0x8F
    wire    nmi_chip_select_n       = chip_select_n[5]; // 0xA0 .. 0xBF
    wire    joystick_select         = (iorq && ~address_enable_n && address[15:3] == (16'h0200 >> 3)); // 0x200 .. 0x207
    // Tandy 1000 video claims the whole 0xC0..0xDF block and narrows every
    // on-board decode with address[4]. The SN76489 alone only answers 0xC0..0xCF
    // and leaves the shared decoder alone: tightening the DMA controller, PIC,
    // PIT and PPI decode is more faithful but silently changes how they decode.
    wire    tandy_chip_select_n     = tandy_video_en ? chip_select_n[6]
                                    : (tandy_audio_en ? (chip_select_n[6] | address[4]) : 1'b1);
    wire    nmi_mask_register       = (tandy_video_en && ~nmi_chip_select_n);

    wire    opl_388_chip_select     = `ENABLE_OPL2 ? (iorq && ~address_enable_n && ~opl2_io[1] && address[15:1] == (16'h0388 >> 1)) : 1'b0; // 0x388 .. 0x389 (Adlib)
    wire    opl_228_chip_select     = `ENABLE_OPL2 ? (iorq && ~address_enable_n && (opl2_io == 2'b01) && address[15:1] == (16'h0228 >> 1)) : 1'b0; // 0x228 .. 0x229 (Sound Blaster FM)
    wire    cms_220_chip_select     = `ENABLE_CMS ? (iorq && ~address_enable_n && address[15:4] == (16'h0220 >> 4)) : 1'b0; // 0x220 .. 0x22F (C/MS Audio)
    wire    video_mem_select        = `ENABLE_TANDY_VIDEO ? (tandy_video_en && ~iorq && ~address_enable_n & (address[19:17] == nmi_mask_register_data[3:1])) : 1'b0; // 128KB
    wire    cga_mem_select          = `ENABLE_CGA ? (~iorq && ~address_enable_n && enable_cga & ~ega_active & (address[19:15] == 5'b10111)) : 1'b0; // B8000 - BFFFF (16 KB / 32 KB)
    wire    hgc_mem_select          = `ENABLE_HGC ? (~iorq && ~address_enable_n && hgc_enable & (address[19:15] == {5'b1011, hgc_grph_page})) : 1'b0; // B0000 - BFFFF (32KB / 64 KB)
    wire    uart_chip_select        = (~address_enable_n && {address[15:3], 3'd0} == 16'h03F8);
    wire    uart2_chip_select       = (~address_enable_n && {address[15:3], 3'd0} == 16'h02F8);
    // NOTE: deliberately no `iorq` term here, matching uart_chip_select above.
    // This select is qualified by iorq_uart, which pulses on the *trailing* edge
    // of io_write_n - by then iorq has already dropped, so including it would
    // gate away every write.
    wire    mpu401_chip_select      = (`ENABLE_MIDI && mpu401_enabled) ? (~address_enable_n && address[15:1] == (16'h0330 >> 1)) : 1'b0; // 0x330 .. 0x331 (MPU-401 UART mode)
    wire    lpt_chip_select         = (iorq && ~address_enable_n && address[15:1] == (16'h0378 >> 1)); // 0x378 ... 0x379
	 wire    lpt_ctrl_select         = (iorq && ~address_enable_n && address[15:0] == 16'h037A); // 0x37A
    wire    tandy_page_chip_select  = `ENABLE_TANDY_VIDEO ? (tandy_video_en && iorq && ~address_enable_n && address[15:0] == 16'h03DF) : 1'b0;
    // The old XTCTL port at 8888h exists in the CGA family only: with
    // the EGA card the whole 8980h block is the interface. It stays aliased
    // onto DMA page index 0 by the on-board decoder either way (see xtegactl).
    wire    xtctl_chip_select       = (~ega_active && iorq && ~address_enable_n && address[15:0] == 16'h8888);

    // 0x2C0 .. 0x2CF is claimed by the EGA card as an undocumented mirror of
    // 0x3C0 .. 0x3CF (attribute/sequencer/graphics controller index-data
    // pairs), so with the EGA the RTC/CMOS device (used for the x86_launcher
    // AppId, among other things) can't live there without every index write
    // also toggling Palette Address Source and blanking the display. It moves
    // to 0x340 .. 0x341, one of the standard base addresses of a real MM58167
    // RTC card. Every other card keeps it at 0x2C0.
    wire [15:0] rtc_port            = ega_active ? 16'h0340 : 16'h02C0;
    wire    rtc_chip_select         = (iorq && ~address_enable_n && address[15:1] == rtc_port[15:1]); // 0x2C0 or 0x340, two ports

    // The packed 13h framebuffer is ordinary memory in SDRAM now (mem_map_ega,
    // cpu_mem_port); all that is left here is keeping the EGA aperture out of
    // its way while it owns A0000-AFFFF.
    wire    vga_a000_select         = vga13_packed_cpu_w && ~iorq && ~address_enable_n && (address[19:16] == 4'hA);
    assign  ega_mem_select          = ega_mem_select_raw && !vga_a000_select;

    // Every CGA byte write carries the Tw marked "+WS" in cycle-counted
    // software.  CGA_BUS_WAIT also ties completion to the next of the two
    // free VRAM windows.  Using both windows is important: selecting only one
    // can hold a polygon write for nearly a complete 32-dot turn and starve
    // its PC-speaker updates, while an unphased fixed Tw breaks Kefrens.
    assign cga_memory_write_wait = `ENABLE_CGA ? cga_mem_select : 1'b0;

    generate
        if (`ENABLE_CGA) begin : CGA_MEMORY_WAIT
            CGA_BUS_WAIT u_CGA_BUS_WAIT (
                .clock              (clock),
                .video_clock        (clk_vga_cga),
                .reset              (reset),
                .sequencer_phase    (clkdiv),
                .memory_select      (cga_mem_select),
                .memory_read_n      (memory_read_n),
                .memory_write_n     (memory_write_n),
                .ready              (cga_memory_ready)
            );
        end
        else begin : NO_CGA_MEMORY_WAIT
            assign cga_memory_ready = 1'b1;
        end
    endgenerate

    wire    [3:0] ems_page_address  = (ems_address == 2'b00) ? 4'b1100 : (ems_address == 2'b01) ? 4'b1101 : 4'b1110;
    wire    ems_chip_select         = `ENABLE_EMS ? (iorq && ~address_enable_n && ems_enabled && ({address[15:2], 2'd0} == 16'h0260)) : 1'b0;          // 260h..263h
    assign  ems_b1                  = `ENABLE_EMS ? (ems_enabled && ~iorq && ena_ems[0] && (address[19:14] == {ems_page_address, 2'b00})) : 1'b0; // C0000h - D0000h - E0000h
    assign  ems_b2                  = `ENABLE_EMS ? (ems_enabled && ~iorq && ena_ems[1] && (address[19:14] == {ems_page_address, 2'b01})) : 1'b0; // C4000h - D4000h - E4000h
    assign  ems_b3                  = `ENABLE_EMS ? (ems_enabled && ~iorq && ena_ems[2] && (address[19:14] == {ems_page_address, 2'b10})) : 1'b0; // C8000h - D8000h - E0000h
    assign  ems_b4                  = `ENABLE_EMS ? (ems_enabled && ~iorq && ena_ems[3] && (address[19:14] == {ems_page_address, 2'b11})) : 1'b0; // CC000h - DC000h - EC000h
    wire    ide0_chip_select_n      = ~(iorq && ~address_enable_n && ({address[15:4], 4'd0} == 16'h0300));
    wire    floppy0_chip_select_n   = ~(~address_enable_n && (({address[15:2], 2'd0} == 16'h03F0) || ({address[15:1], 1'd0} == 16'h03F4) || ({address[15:0]} == 16'h03F7)));

    logic   [1:0]   ems_access_address;
    logic           ems_write_enable;
    logic   [7:0]   write_map_ems_data;
    logic           write_map_ena_data;
	 
    //
    // I/O Ports
    //
    // Address
    always_comb begin
        if (`ENABLE_TANDY_VIDEO && cga_mem_select && ~memory_write_n && tandy_video_en)
            latch_address   = {nmi_mask_register_data[3:1], tandy_page_data[3] ? {tandy_page_data[5:3], video_ram_address[13:0]} : {tandy_page_data[5:4], video_ram_address[14:0]}};
        else
            latch_address   = address;
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            ems_access_address  <= 2'b11;
            ems_write_enable    <= 1'b0;
            write_map_ems_data  <= 8'd0;
            write_map_ena_data  <= 1'b0;
        end
        else if (`ENABLE_EMS)
        begin
            ems_access_address  <= address[1:0];
            ems_write_enable    <= ems_chip_select && ~io_write_n;
            write_map_ems_data  <= (internal_data_bus == 8'hFF) ? 8'hFF : (internal_data_bus < 8'h80) ? internal_data_bus[6:0] : map_ems[address[1:0]];
            write_map_ena_data  <= (internal_data_bus == 8'hFF) ? 1'b0  : (internal_data_bus < 8'h80) ? 1'b1 : ena_ems[address[1:0]];
        end
        else
        begin
            ems_access_address  <= 2'b11;
            ems_write_enable    <= 1'b0;
            write_map_ems_data  <= 8'd0;
            write_map_ena_data  <= 1'b0;
        end
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset || !`ENABLE_EMS)
        begin
            map_ems = '{7'h00, 7'h00, 7'h00, 7'h00};
            ena_ems = '{1'b0, 1'b0, 1'b0, 1'b0};
        end
        // ems_enabled is a level, not an edge of this block: it clears the map synchronously
        else if (!ems_enabled)
        begin
            map_ems = '{7'h00, 7'h00, 7'h00, 7'h00};
            ena_ems = '{1'b0, 1'b0, 1'b0, 1'b0};
        end
        else if (ems_write_enable)
        begin
            map_ems[ems_access_address] <= write_map_ems_data;
            ena_ems[ems_access_address] <= write_map_ena_data;
        end
    end


    //
    // 8259
    //
    logic           timer_interrupt;
    logic           keybord_interrupt;
    logic           uart_interrupt;
    logic           fdd_interrupt;
    logic           uart2_interrupt;
    logic           mpu_interrupt;
    logic   [7:0]   interrupt_data_bus_out;
    logic           interrupt_to_cpu_buf;

    KF8259 u_KF8259 
    (
        // Bus
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (interrupt_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (address[0]),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (interrupt_data_bus_out),

        // I/O
        .cascade_in                 (3'b000),
        //.cascade_out                (),
        //.cascade_io                 (),
        .slave_program_n            (1'b1),
        //.buffer_enable              (),
        //.slave_program_or_enable_buffer     (),
        .interrupt_acknowledge_n    (interrupt_acknowledge_n),
        .interrupt_to_cpu           (interrupt_to_cpu_buf),
        .interrupt_request          ({interrupt_request[7] | (sb_interrupt & sb_irq7),
                                        fdd_interrupt,
                                        interrupt_request[5] | (sb_interrupt & ~sb_irq7),
                                        uart_interrupt,
                                        uart2_interrupt,
                                        mpu_interrupt,
                                        keybord_interrupt,
                                        timer_interrupt})
    );

    always_ff @(posedge clock, posedge reset)
        if (reset)
            interrupt_to_cpu    <= 1'b0;
        else if (cpu_ce_negedge)
            interrupt_to_cpu    <= interrupt_to_cpu_buf;
        else
            interrupt_to_cpu    <= interrupt_to_cpu;


    //
    // 8253
    //
    logic   timer_clock;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            timer_clock         <= 1'b0;
        else if (peripheral_ce)
            timer_clock         <= ~timer_clock;
        else
            timer_clock         <= timer_clock;
    end

    logic   [7:0]   timer_data_bus_out;

    wire    tim2gatespk = port_b_out[0] & ~port_b_io;
    wire    spkdata     = port_b_out[1] & ~port_b_io;

    KF8253 u_KF8253 
    (
        // Bus
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (timer_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (address[1:0]),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (timer_data_bus_out),

        // I/O
        .counter_0_clock            (timer_clock),
        .counter_0_gate             (1'b1),
        .counter_0_out              (timer_counter_out[0]),
        .counter_1_clock            (timer_clock),
        .counter_1_gate             (1'b1),
        .counter_1_out              (timer_counter_out[1]),
        .counter_2_clock            (timer_clock),
        .counter_2_gate             (tim2gatespk),
        .counter_2_out              (timer_counter_out[2])
    );

    assign  timer_interrupt = timer_counter_out[0];
    assign  speaker_out     = timer_counter_out[2] & spkdata;

    //
    // 8255
    //
    logic   [7:0]   ppi_data_bus_out;
    logic   [7:0]   port_a_in;

    KF8255 u_KF8255 
    (
        // Bus
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (ppi_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (address[1:0]),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (ppi_data_bus_out),

        // I/O
        .port_a_in                  (port_a_in),
        .port_a_out                 (port_a_out),
        .port_a_io                  (port_a_io),
        .port_b_in                  (port_b_in),
        .port_b_out                 (port_b_out),
        .port_b_io                  (port_b_io),
        .port_c_in                  (port_c_in),
        .port_c_out                 (port_c_out),
        .port_c_io                  (port_c_io)
    );

    //
    // KFPS2KB
    //
    logic           ps2_send_clock;
    logic           keybord_irq;
    logic           uart_irq;
    logic           uart2_irq;
    logic           mpu_irq;
    logic   [7:0]   keycode_buf;
    logic   [7:0]   keycode;
    logic   [7:0]   tandy_keycode_conv;
    logic           prev_ps2_reset;
    logic           prev_ps2_reset_n;
    logic           lock_recv_clock;
    logic           swap_video_buffer_1;
    logic           swap_video_buffer_2;
    localparam [15:0] KEYBOARD_WARM_RESET_HOLD = 16'd5000;
    wire            keyboard_warm_reset_active;

    wire    clear_keycode = port_b_out[7];
    wire    ps2_reset_n   = ~tandy_video ? port_b_out[6] : 1'b1;

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            prev_ps2_reset_n <= 1'b0;
        else
            prev_ps2_reset_n <= ps2_reset_n;
    end

    KFPS2KB u_KFPS2KB 
    (
        // Bus
        .clock                      (clock),
        .peripheral_ce              (peripheral_ce),
        .reset                      (reset),

        // PS/2 I/O
        .device_clock               (ps2_clock | lock_recv_clock),
        .device_data                (ps2_data),

        // I/O
        .irq                        (keybord_irq),
        .keycode                    (keycode_buf),
        .clear_keycode              (clear_keycode),
        .pause_core                 (pause_core),
        .swap_video                 (swap_video_buffer_1),
        .video_output               (video_output),
        .tandy_video                (tandy_video_en)
    );

    assign  keycode = ps2_reset_n ? keycode_buf : 8'h80;

    keyboard_warm_reset #(
        .HOLD_CYCLES(KEYBOARD_WARM_RESET_HOLD)
    ) keyboard_warm_reset_detect (
        .clock             (clock),
        .reset             (reset),
        .keycode_irq       (keybord_irq),
        .keycode           (keycode),
        .warm_reset_active (keyboard_warm_reset_active)
    );

    // Keyboard reset
    KFPS2KB_Send_Data u_KFPS2KB_Send_Data 
    (
        // Bus
        .clock                      (clock),
        .peripheral_ce              (peripheral_ce),
        .reset                      (reset),

        // PS/2 I/O
        .device_clock               (ps2_clock),
        .device_clock_out           (ps2_send_clock),
        .device_data_out            (ps2_data_out),
        .sending_data_flag          (lock_recv_clock),

        // I/O
        .send_request               (~prev_ps2_reset_n & ps2_reset_n),
        .send_data                  (8'hFF)
    );

    // Convert Tandy scancode
    Tandy_Scancode_Converter u_Tandy_Scancode_Converter 
    (
        .clock                      (clock),
        .reset                      (reset),
        .scancode                   (keycode),
        .keybord_irq                (keybord_irq),
        .convert_data               (tandy_keycode_conv)
    );
    wire [7:0] tandy_keycode = `ENABLE_TANDY_KBD ? tandy_keycode_conv : keycode;

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            ps2_clock_out = 1'b1;
        else
            ps2_clock_out = ~(keybord_irq | ~ps2_send_clock | ~ps2_reset_n);
    end

    always_ff @(posedge clk_vga_hgc or posedge video_reset_hgc)
    begin
        if (video_reset_hgc) begin
            swap_video_buffer_2 <= 1'b0;
            swap_video          <= 1'b0;
        end
        else begin
            swap_video_buffer_2 <= swap_video_buffer_1;
            swap_video          <= swap_video_buffer_2;
        end
    end


    wire [7:0] jtopl2_dout_int;
    wire [15:0] jtopl2_snd_e_int;
    wire [7:0] jtopl2_dout = `ENABLE_OPL2 ? jtopl2_dout_int : 8'hFF;
    // The OPL2 goes out through the Sound Blaster when there is one, so that
    // the card's mixer can set its level like a real one does. The direct
    // path is silenced in that case - otherwise the top level would sum the
    // same FM twice. With no card built this is exactly as it was.
    assign jtopl2_snd_e = (`ENABLE_OPL2 && !`ENABLE_SB) ? jtopl2_snd_e_int : 16'd0;

    reg clk_en_opl2;
    always @(posedge clock) begin
        reg [27:0] sum = 0;

        clk_en_opl2 <= 0;
        sum = sum + 28'd3579545;
        if(sum >= clk_rate) begin
            sum = sum - clk_rate;
            clk_en_opl2 <= 1;
        end
    end

    jtopl2 jtopl2_inst
    (
        .rst(reset | (`ENABLE_OPL2 && keyboard_warm_reset_active)),
        .clk(clock),
        .cen(clk_en_opl2),
        .din(internal_data_bus),
        .dout(jtopl2_dout_int),
        .addr(address[0]),
        .cs_n(~(opl_228_chip_select || opl_388_chip_select)),
        .wr_n(io_write_n),
        .irq_n(),
        .snd(jtopl2_snd_e_int),
        .sample()
    );


    //
    // Sound Blaster Pro
    //
    // 220h and DMA channel 1 are fixed. IRQ 5 or 7 is selected by the OSD or
    // XTEGACTL, matching the two standard Sound Blaster jumper positions.
    // The DSP, mixer and DMA bridge all live inside soundblaster.sv; what is
    // left out here is only the wiring.
    //
    // sb_en arrives already exclusive with cms_en: xtegactl_resolve drops
    // the C/MS whenever this is set, because the two collide on 226h/227h.
    logic           sb_read_select;
    logic   [7:0]   sb_readdata;
    logic           sb_interrupt;

    generate
    if (`ENABLE_SB) begin : SOUND_BLASTER
        soundblaster u_soundblaster (
            .clock              (clock),
            .reset              (reset),
            .cpu_ce_negedge     (cpu_ce_negedge),
            .clk_rate           (clk_rate),
            .address            (address[15:0]),
            .internal_data_bus  (internal_data_bus),
            .io_read_n          (io_read_n),
            .io_write_n         (io_write_n),
            .address_enable_n   (address_enable_n),
            .enable             (sb_en),
            .read_select        (sb_read_select),
            .data_bus_out       (sb_readdata),
            .dma_acknowledge    (sb_dma_ack),
            .dma_request        (sb_dma_req),
            .irq                (sb_interrupt),
            .fm_l               (jtopl2_snd_e_int),
            .fm_r               (jtopl2_snd_e_int),
            .sample_l           (sb_snd_l),
            .sample_r           (sb_snd_r)
        );
    end
    else begin : NO_SOUND_BLASTER
        assign sb_read_select = 1'b0;
        assign sb_readdata    = 8'hFF;
        assign sb_interrupt   = 1'b0;
        assign sb_dma_req     = 1'b0;
        assign sb_snd_l       = 16'd0;
        assign sb_snd_r       = 16'd0;
    end
    endgenerate

    wire [10:0] tandy_snd_e_int;
    wire        tandy_snd_rdy_int;
    assign tandy_snd_e = (`ENABLE_TANDY_AUDIO && tandy_en) ? tandy_snd_e_int : 11'd0;
    assign tandy_snd_rdy = `ENABLE_TANDY_AUDIO ? tandy_snd_rdy_int : 1'b1;

    // Tandy sound
		 jt89 sn76489
    (
        .rst(reset),
		  .clk(clock),
		  .clk_en(clk_en_opl2), // 3.579MHz
		  .wr_n(io_write_n),
		  .cs_n(tandy_chip_select_n),
		  .din(internal_data_bus),
		  .sound(tandy_snd_e_int),
		  .ready(tandy_snd_rdy_int)
    );
	 
//------------------------------------------------------------------------------

reg ce_1us;
always @(posedge clock) begin
	reg [27:0] sum = 0;

	ce_1us <= 0;
	sum = sum + 28'd1000000;
	if(sum >= clk_rate) begin
		sum = sum - clk_rate;
		ce_1us <= 1;
	end
end	 
	 
//------------------------------------------------------------------------------ c/ms

    reg [7:0] cms_det;
    wire cms_rd = `ENABLE_CMS ? ((address[3:0] == 4'h4 || address[3:0] == 4'hB) && cms_220_chip_select && cms_en) : 1'b0;
    wire [7:0] data_from_cms = `ENABLE_CMS ? (address[3] ? cms_det : 8'h7F) : 8'hFF;

    wire cms_wr = `ENABLE_CMS ? (~address[3] & cms_220_chip_select & cms_en) : 1'b0;
    always @(posedge clock)
        if (`ENABLE_CMS && ~io_write_n && cms_wr && &address[2:1])
            cms_det <= internal_data_bus;
        else if (!`ENABLE_CMS)
            cms_det <= 8'h00;

    reg ce_saa;
    always @(posedge clock) begin
	    reg [27:0] sum = 0;

	    if (`ENABLE_CMS)
        begin
	        ce_saa <= 0;
	        sum = sum + 28'd7159090;
	        if(sum >= clk_rate) begin
		        sum = sum - clk_rate;
		        ce_saa <= 1;
	        end
        end
        else
            ce_saa <= 1'b0;
    end

    wire [7:0] saa1_l,saa1_r;
    saa1099 ssa1
    (
	    .clk_sys(clock),
	    .ce(ce_saa),
	    .rst_n(~reset & cms_en),
	    .cs_n(~(cms_wr && (address[2:1] == 0))),
	    .a0(address[0]),
	    .wr_n(io_write_n),
	    .din(internal_data_bus),
	    .out_l(saa1_l),
	    .out_r(saa1_r)
    );

    wire [7:0] saa2_l,saa2_r;
    saa1099 ssa2
    (
	    .clk_sys(clock),
	    .ce(ce_saa),
	    .rst_n(~reset & cms_en),
	    .cs_n(~(cms_wr && (address[2:1] == 1))),
	    .a0(address[0]),
	    .wr_n(io_write_n),
	    .din(internal_data_bus),
	    .out_l(saa2_l),
	    .out_r(saa2_r)
    );

    wire [8:0] cms_l = {1'b0, saa1_l} + {1'b0, saa2_l};
    wire [8:0] cms_r = {1'b0, saa1_r} + {1'b0, saa2_r};
	 
    reg [15:0] sample_pre_l, sample_pre_r;
    always @(posedge clock) begin
        if (`ENABLE_CMS)
        begin
	        sample_pre_l <= {2'b0, cms_l, cms_l[8:4]};
	        sample_pre_r <= {2'b0, cms_r, cms_r[8:4]};
        end
        else
        begin
            sample_pre_l <= 16'd0;
            sample_pre_r <= 16'd0;
        end
    end

    always @(posedge clock) begin
        if (`ENABLE_CMS)
        begin
	        o_cms_l <= $signed(sample_pre_l) >>> ~{3'd7};
	        o_cms_r <= $signed(sample_pre_r) >>> ~{3'd7};
        end
        else
        begin
            o_cms_l <= 16'd0;
            o_cms_r <= 16'd0;
        end
    end
	 
//

    logic   keybord_interrupt_ff;
    logic   uart_interrupt_ff;
    logic   uart2_interrupt_ff;
    logic   mpu_interrupt_ff;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            keybord_interrupt_ff    <= 1'b0;
            keybord_interrupt       <= 1'b0;
            uart_interrupt_ff       <= 1'b0;
            uart_interrupt          <= 1'b0;
            uart2_interrupt_ff      <= 1'b0;
            uart2_interrupt         <= 1'b0;
            mpu_interrupt_ff        <= 1'b0;
            mpu_interrupt           <= 1'b0;
        end
        else
        begin
            keybord_interrupt_ff    <= keybord_irq;
            keybord_interrupt       <= keybord_interrupt_ff;
            uart_interrupt_ff       <= uart_irq;
            uart_interrupt          <= uart_interrupt_ff;
            // mpu401_inst's rx_ready tracks the underlying UART core, which
            // keeps receiving on midi_rx regardless of the chip select above,
            // so gate the interrupt here too - otherwise a byte arriving from
            // a still-connected mt32-pi/USB MIDI link could raise IRQ9 for a
            // card that is supposed to look unplugged.
            mpu_interrupt_ff        <= mpu_irq & mpu401_enabled;
            mpu_interrupt           <= mpu_interrupt_ff;
            uart2_interrupt_ff      <= uart2_irq;
            uart2_interrupt         <= uart2_interrupt_ff;
        end
    end

    logic prev_io_read_n;
    logic prev_io_write_n;
    logic [7:0] write_to_uart;
    logic [7:0] write_to_uart2;
    logic [7:0] write_to_mpu401;
    logic [7:0] uart_readdata_1;
    logic [7:0] uart_readdata;
    logic [7:0] uart2_readdata_1;
    logic [7:0] uart2_readdata;
    logic [7:0] mpu401_readdata_1;
    logic [7:0] mpu401_readdata;

    always_ff @(posedge clock)
    begin
        prev_io_read_n <= io_read_n;
        prev_io_write_n <= io_write_n;
    end

    logic   [7:0]   keycode_ff;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            keycode_ff  <= 8'h00;
            port_a_in   <= 8'h00;
        end
        else
        begin
            keycode_ff  <= tandy_kbd_en ? tandy_keycode : keycode;
            port_a_in   <= keycode_ff;
        end
    end

    reg [7:0] lpt_reg = 8'hFF;
	 reg [7:0] lpt_ctrl = 8'h00;
	 reg [7:0] lpt_enable_irq = 8'h00;
    reg [7:0] tandy_page_data = 8'h00;
    reg [7:0] nmi_mask_register_data = 8'hFF;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)        
        begin
            xtctl <= 8'b00;
            tandy_page_data <= 8'h00;
            nmi_mask_register_data <= 8'hFF;
        end
        else begin
            if (~io_write_n)
            begin
                write_to_uart <= internal_data_bus;
                write_to_uart2 <= internal_data_bus;
                write_to_mpu401 <= internal_data_bus;
            end
            else
            begin
                write_to_uart <= write_to_uart;
                write_to_uart2 <= write_to_uart2;
                write_to_mpu401 <= write_to_mpu401;
            end

            if ((lpt_chip_select) && (~io_write_n) && ~address[0])
                lpt_reg <= internal_data_bus;

            if ((lpt_ctrl_select) && (~io_write_n))
            begin
                lpt_ctrl <= internal_data_bus;
                lpt_enable_irq <= internal_data_bus & 8'h10;
            end

            if ((xtctl_chip_select) && (~io_write_n))
                xtctl <= internal_data_bus;

            if (`ENABLE_TANDY_VIDEO && (tandy_page_chip_select) && (~io_write_n))
                tandy_page_data <= internal_data_bus;

            if (`ENABLE_TANDY_VIDEO && nmi_mask_register && (~io_write_n))
                nmi_mask_register_data <= internal_data_bus;
        end

    end

    wire iorq_uart = (io_write_n & ~prev_io_write_n) || (~io_read_n  & prev_io_read_n);
    wire uart_tx;
    wire rts_n;
	 
    uart uart1
    (
        .clk               (clock),
        .br_clk            (clk_uart),
        .reset             (reset),

        .address           (address[2:0]),
        .writedata         (write_to_uart),
        .read              (~io_read_n  & prev_io_read_n),
        .write             (io_write_n & ~prev_io_write_n),
        .readdata          (uart_readdata_1),
        .cs                (uart_chip_select & iorq_uart),
        .rx                (uart_tx),
        .cts_n             (0),
        .dcd_n             (0),
        .dsr_n             (0),
        .ri_n              (1),
        .rts_n             (rts_n),
        .irq               (uart_irq)
    );
	 

    uart #(.RX_MIDSTOP(1)) uart2
    (
        .clk               (clock),
        .br_clk            (clk_uart_com2),
        .reset             (reset),

        .address           (address[2:0]),
        .writedata         (write_to_uart2),
        .read              (~io_read_n  & prev_io_read_n),
        .write             (io_write_n & ~prev_io_write_n),
        .readdata          (uart2_readdata_1),
        .cs                (uart2_chip_select & iorq_uart),

        .rx                (uart2_rx),
        .tx                (uart2_tx),
        .cts_n             (uart2_cts_n),
        .dcd_n             (uart2_dcd_n),
        .dsr_n             (uart2_dsr_n),
        .rts_n             (uart2_rts_n),
        .dtr_n             (uart2_dtr_n),
        .ri_n              (1),

        .irq               (uart2_irq)
    );

    mpu401 mpu401_inst
    (
        .clk               (clock),
        .reset             (reset),

        .baudce            (clk_midi),

        .address           (address[0]),
        .writedata         (write_to_mpu401),
        .read              (~io_read_n  & prev_io_read_n),
        .write             (io_write_n & ~prev_io_write_n),
        .readdata          (mpu401_readdata_1),
        .cs                (mpu401_chip_select & iorq_uart),

        .midi_tx           (midi_tx),
        .midi_rx           (midi_rx),

        .irq               (mpu_irq)
    );


    MSMouseWrapper MSMouseWrapper_inst
    (
        .clk(clock),
        .ps2dta_in(ps2_mousedat_in),
        .ps2clk_in(ps2_mouseclk_in),
        .ps2dta_out(ps2_mousedat_out),
        .ps2clk_out(ps2_mouseclk_out),
        .rts(~rts_n),
        .rd(uart_tx)
    );

    // Timing of the readings may need to be reviewed.
    always_ff @(posedge clock)
    begin
        if (~io_read_n)
        begin
            uart_readdata <= uart_readdata_1;
            uart2_readdata <= uart2_readdata_1;
            mpu401_readdata <= mpu401_readdata_1;
        end
        else
        begin
            uart_readdata <= uart_readdata;
            uart2_readdata <= uart2_readdata;
            mpu401_readdata <= mpu401_readdata;
        end
    end


    // Per-program hardware control, 8980h..898Fh. Only the register file lives
    // here; what the fields mean is xtegactl_resolve, up where the OSD is.
    wire [7:0] xtegactl_data;
    wire       xtegactl_oe;

    xtegactl xtegactl_ports (
        .clock            (clock),
        .reset            (reset),
        .clear_vga13      (warm_boot_marker_event),
        .address          (address[15:0]),
        .address_enable_n (address_enable_n),
        .io_read_n        (io_read_n),
        .io_write_n       (io_write_n),
        .data_in          (internal_data_bus),
        .data_out         (xtegactl_data),
        .output_enable    (xtegactl_oe),
        .reg_cpu          (xtegactl_cpu),
        .reg_exp          (xtegactl_exp),
        .reg_vid          (xtegactl_vid),
        .reg_inp          (xtegactl_inp),
        .reg_midi         (xtegactl_midi),
        .reg_exp2         (xtegactl_exp2),
        .reg_crt          (xtegactl_crt),
        .reg_sync         (xtegactl_sync),
        .status_effective (xtegactl_status_effective),
        .status_osd_match (xtegactl_status_osd_match)
    );

    // Identification and debug, 8990h..8997h
    localparam [7:0] XTCTL_CAPABILITIES = {
        `ENABLE_TANDY_AUDIO ? 1'b1 : 1'b0,
        `ENABLE_CMS         ? 1'b1 : 1'b0,
        `ENABLE_OPL2        ? 1'b1 : 1'b0,
        `ENABLE_SB          ? 1'b1 : 1'b0,
        `ENABLE_HGC         ? 1'b1 : 1'b0,
        `ENABLE_CGA         ? 1'b1 : 1'b0,
        (`ENABLE_EGA && `ENABLE_VGA13) ? 1'b1 : 1'b0,
        `ENABLE_EGA         ? 1'b1 : 1'b0
    };
    wire [7:0] xtctl_id_data;
    wire       xtctl_id_oe;

    xtctl_id #(
        .CAPABILITIES (XTCTL_CAPABILITIES)
    ) xtctl_id_ports (
        .clock            (clock),
        .reset            (reset),
        .address          (address[15:0]),
        .address_enable_n (address_enable_n),
        .io_read_n        (io_read_n),
        .data_out         (xtctl_id_data),
        .output_enable    (xtctl_id_oe),
        .video_card       (id_video_card),
        .vga13_active     (id_vga13_active),
        .rtc_port         (rtc_port),
        .video_underruns  (id_video_underruns),
        .cpu_latency_max  (id_cpu_latency_max)
    );

    logic  [16:0]  video_ram_address;
    logic  [7:0]   video_ram_data;
    logic          video_memory_write_n;
    logic          hgc_mem_select_1;
    logic          cga_mem_select_1;
    logic          video_mem_select_1;
    logic  [14:0]  video_io_address;
    logic  [7:0]   video_io_data;
    logic          video_io_write_n;
    logic          video_io_read_n;
    logic          video_address_enable_n;
    logic  [14:0]  hgc_io_address_1;
    logic  [14:0]  hgc_io_address_2;
    logic  [7:0]   hgc_io_data_1;
    logic  [7:0]   hgc_io_data_2;
    logic          hgc_io_write_n_1;
    logic          hgc_io_write_n_2;
    logic          hgc_io_write_n_3;
    logic          hgc_io_read_n_1;
    logic          hgc_io_read_n_2;
    logic          hgc_io_read_n_3;
    logic          hgc_address_enable_n_1;
    logic          hgc_address_enable_n_2;
    logic  [14:0]  cga_io_address_1;
    logic  [14:0]  cga_io_address_2;
    logic  [7:0]   cga_io_data_1;
    logic  [7:0]   cga_io_data_2;
    logic          cga_io_write_n_1;
    logic          cga_io_write_n_2;
    logic          cga_io_read_n_1;
    logic          cga_io_read_n_2;
    logic          cga_address_enable_n_1;
    logic          cga_address_enable_n_2;
    always_ff @(posedge clock)
    begin
        if (~io_write_n | ~io_read_n)
        begin
            video_io_address    <= address[13:0];
            video_io_data       <= internal_data_bus;
        end
        else
        begin
            video_io_address    <= video_io_address;
            video_io_data       <= video_io_data;
        end
    end

    always_ff @(posedge clock)
    begin
        video_ram_address       <= address[16:0];
        video_ram_data          <= internal_data_bus;
        video_memory_write_n    <= memory_write_n;
        hgc_mem_select_1        <= hgc_mem_select;
        cga_mem_select_1        <= cga_mem_select;
        video_mem_select_1      <= video_mem_select;

        video_io_write_n        <= io_write_n;
        video_io_read_n         <= io_read_n;
        video_address_enable_n  <= address_enable_n;
    end

    always_ff @(posedge clk_vga_hgc or posedge video_reset_hgc)
    begin
        if (video_reset_hgc)
        begin
            hgc_io_address_1        <= 15'd0;
            hgc_io_address_2        <= 15'd0;
            hgc_io_data_1           <= 8'd0;
            hgc_io_data_2           <= 8'd0;
            hgc_io_write_n_1        <= 1'b1;
            hgc_io_write_n_2        <= 1'b1;
            hgc_io_write_n_3        <= 1'b1;
            hgc_io_read_n_1         <= 1'b1;
            hgc_io_read_n_2         <= 1'b1;
            hgc_io_read_n_3         <= 1'b1;
            hgc_address_enable_n_1  <= 1'b1;
            hgc_address_enable_n_2  <= 1'b1;
        end
        else if (`ENABLE_HGC && !ega_active_hgc)
        begin
            hgc_io_address_1        <= video_io_address;
            hgc_io_address_2        <= hgc_io_address_1;
            hgc_io_data_1           <= video_io_data;
            hgc_io_data_2           <= hgc_io_data_1;
            hgc_io_write_n_1        <= video_io_write_n;
            hgc_io_write_n_2        <= hgc_io_write_n_1;
            hgc_io_write_n_3        <= hgc_io_write_n_2;
            hgc_io_read_n_1         <= video_io_read_n;
            hgc_io_read_n_2         <= hgc_io_read_n_1;
            hgc_io_read_n_3         <= hgc_io_read_n_2;
            hgc_address_enable_n_1  <= video_address_enable_n;
            hgc_address_enable_n_2  <= hgc_address_enable_n_1;
        end
        else
        begin
            hgc_io_address_1        <= 15'd0;
            hgc_io_address_2        <= 15'd0;
            hgc_io_data_1           <= 8'd0;
            hgc_io_data_2           <= 8'd0;
            hgc_io_write_n_1        <= 1'b1;
            hgc_io_write_n_2        <= 1'b1;
            hgc_io_write_n_3        <= 1'b1;
            hgc_io_read_n_1         <= 1'b1;
            hgc_io_read_n_2         <= 1'b1;
            hgc_io_read_n_3         <= 1'b1;
            hgc_address_enable_n_1  <= 1'b1;
            hgc_address_enable_n_2  <= 1'b1;
        end
    end

    always_ff @(posedge clk_vga_cga)
    begin
        if (`ENABLE_CGA && !ega_active_cga)
        begin
            cga_io_address_1        <= video_io_address;
            cga_io_address_2        <= cga_io_address_1;
            cga_io_data_1           <= video_io_data;
            cga_io_data_2           <= cga_io_data_1;
            cga_io_write_n_1        <= video_io_write_n;
            cga_io_write_n_2        <= cga_io_write_n_1;
            cga_io_read_n_1         <= video_io_read_n;
            cga_io_read_n_2         <= cga_io_read_n_1;
            cga_address_enable_n_1  <= video_address_enable_n;
            cga_address_enable_n_2  <= cga_address_enable_n_1;
        end
        else
        begin
            cga_io_address_1        <= 15'd0;
            cga_io_address_2        <= 15'd0;
            cga_io_data_1           <= 8'd0;
            cga_io_data_2           <= 8'd0;
            cga_io_write_n_1        <= 1'b1;
            cga_io_write_n_2        <= 1'b1;
            cga_io_read_n_1         <= 1'b1;
            cga_io_read_n_2         <= 1'b1;
            cga_address_enable_n_1  <= 1'b1;
            cga_address_enable_n_2  <= 1'b1;
        end
    end


    wire  [5:0]   R_CGA;
    wire  [5:0]   G_CGA;
    wire  [5:0]   B_CGA;
    wire          HSYNC_CGA;
    wire          VSYNC_CGA;
    wire          HBLANK_CGA;
    wire          VBLANK_CGA;
    wire          de_o_cga;

    wire       hsync_cga_raw;
    wire       hsync_cga_rgbi_sd;
    wire       vsync_cga_raw;
    wire       vblank_cga_raw;
    wire       hblank_cga_raw;
    wire       vblank_cga_crtc;
    wire       de_o_cga_raw;
    wire       hsync_cga_sd;
    wire       vsync_cga_sd;
    wire       hblank_cga_sd;
    wire       vblank_cga_sd;
    wire       de_o_cga_sd;
    wire [3:0] video_cga_raw;
    wire [3:0] video_cga_sd;
    wire [5:0] R_CGA_native;
    wire [5:0] G_CGA_native;
    wire [5:0] B_CGA_native;
    wire [17:0] cga_rgb_sd;
    reg   [5:0]   R_HGC;
    reg   [5:0]   G_HGC;
    reg   [5:0]   B_HGC;
    reg           HSYNC_HGC;
    reg           VSYNC_HGC;
    reg           HBLANK_HGC;
    reg           VBLANK_HGC;
    reg           de_o_hgc;
    wire          video_hgc;

    // The boot artwork is generated by the CGA raster path.  Do not let the
    // normal HGC/MDA source select the shared stream while that raster is on
    // screen; HGC/MDA resumes as soon as the splash is dismissed.
    wire swap_video_sel = splashscreen ? 1'b0 :
                          (`ENABLE_HGC ? (`ENABLE_CGA ? (swap_video & ~tandy_video_en) : ~tandy_video_en) : 1'b0);

    assign VGA_R = swap_video_sel ? R_HGC : (`ENABLE_CGA ? R_CGA : 6'd0);
    assign VGA_G = swap_video_sel ? G_HGC : (`ENABLE_CGA ? G_CGA : 6'd0);
    assign VGA_B = swap_video_sel ? B_HGC : (`ENABLE_CGA ? B_CGA : 6'd0);
    assign VGA_HSYNC = swap_video_sel ? HSYNC_HGC : (`ENABLE_CGA ? HSYNC_CGA : 1'b0);
    assign VGA_VSYNC = swap_video_sel ? VSYNC_HGC : (`ENABLE_CGA ? VSYNC_CGA : 1'b0);

    assign VGA_HBlank = swap_video_sel ? HBLANK_HGC : (`ENABLE_CGA ? HBLANK_CGA : 1'b0);
    assign VGA_VBlank = swap_video_sel ? VBLANK_HGC : (`ENABLE_CGA ? VBLANK_CGA : 1'b0);

    assign de_o = swap_video_sel ? de_o_hgc : (`ENABLE_CGA ? de_o_cga : 1'b0);
    assign HSYNC_CGA = cga_scandouble_en ? hsync_cga_sd : hsync_cga_raw;
    assign VSYNC_CGA = cga_scandouble_en ? vsync_cga_sd : vsync_cga_raw;
    assign HBLANK_CGA = cga_scandouble_en ? hblank_cga_sd : hblank_cga_raw;
    assign VBLANK_CGA = cga_scandouble_en ? vblank_cga_sd : vblank_cga_raw;
    assign de_o_cga = cga_scandouble_en ? de_o_cga_sd : de_o_cga_raw;

    assign R_CGA = cga_scandouble_en ? cga_rgb_sd[5:0]   : R_CGA_native;
    assign G_CGA = cga_scandouble_en ? cga_rgb_sd[11:6]  : G_CGA_native;
    assign B_CGA = cga_scandouble_en ? cga_rgb_sd[17:12] : B_CGA_native;

    wire HGC_VRAM_ENABLE;
    wire [18:0] HGC_VRAM_ADDR;
    wire [7:0] HGC_VRAM_DOUT;
    wire HGC_CRTC_OE;
    reg  HGC_CRTC_OE_1;
    reg  HGC_CRTC_OE_2;
    wire [7:0] HGC_CRTC_DOUT;
    reg  [7:0] HGC_CRTC_DOUT_1;
    reg  [7:0] HGC_CRTC_DOUT_2;

    wire intensity;


    hgc_vgaport vga_hgc 
    (
        .clk(clk_vga_hgc),
        .video(video_hgc),
        .intensity(intensity),
        .red(R_HGC),
        .green(G_HGC),
        .blue(B_HGC),
        .hgc_rgb(hgc_rgb)
    );

    hgc hgc1
    (
        .clk                        (clk_vga_hgc),
        .bus_a                      (hgc_io_address_2),
        .bus_ior_l                  (hgc_io_read_n_3),
        .bus_iow_l                  (hgc_io_write_n_3),
        .bus_memr_l                 (1'd0),
        .bus_memw_l                 (1'd0),
        .bus_d                      (hgc_io_data_2),
        .bus_out                    (HGC_CRTC_DOUT),
        .bus_dir                    (HGC_CRTC_OE),
        .bus_aen                    (hgc_address_enable_n_2),
        .ram_we_l                   (HGC_VRAM_ENABLE),
        .ram_a                      (HGC_VRAM_ADDR),
        .ram_d                      (HGC_VRAM_DOUT),
        .hsync                      (HSYNC_HGC),
        .hblank                     (HBLANK_HGC),
        .vsync                      (VSYNC_HGC),
        .vblank                     (VBLANK_HGC),
        .intensity                  (intensity),
        .video                      (video_hgc),
        .de_o                       (de_o_hgc),
        .grph_mode                  (hgc_grph_mode),
        .grph_page                  (hgc_grph_page),
        .std_hsyncwidth             (std_hsyncwidth_hgc),
        .vblank_border              (vblank_border_hgc),
        .hercules_hw                (hercules_hw),
        .fx_next_word               (fx_hgc_next_word),
        .fx_phase                   (fx_hgc_phase)

    );

    always_ff @(posedge clock)
    begin
        if (`ENABLE_HGC)
        begin
            HGC_CRTC_DOUT_1 <= HGC_CRTC_DOUT;
            HGC_CRTC_DOUT_2 <= HGC_CRTC_DOUT_1;
            HGC_CRTC_OE_1   <= HGC_CRTC_OE;
            HGC_CRTC_OE_2   <= HGC_CRTC_OE_1;
        end
        else
        begin
            HGC_CRTC_DOUT_1 <= 8'h00;
            HGC_CRTC_DOUT_2 <= 8'h00;
            HGC_CRTC_OE_1   <= 1'b0;
            HGC_CRTC_OE_2   <= 1'b0;
        end
    end


    wire CGA_VRAM_ENABLE;
    wire [18:0] CGA_VRAM_ADDR;
    wire [7:0] CGA_VRAM_DOUT;
    wire        CGA_CRTC_OE;
    logic       CGA_CRTC_OE_1;
    logic       CGA_CRTC_OE_2;
    wire [7:0]  CGA_CRTC_DOUT;
    logic [7:0] CGA_CRTC_DOUT_1;
    logic [7:0] CGA_CRTC_DOUT_2;
    wire        VGA_VBlank_border_raw;
    wire        hsync_ref_cga, vsync_ref_cga;
    wire        std_hsyncwidth_raw;
    wire        tandy_color_16_raw;
    wire        std_hsyncwidth_hgc;
    wire        vblank_border_hgc;

    // Sets up the card to generate a video signal
    // that will work with a standard VGA monitor
    // connected to the VGA port.
    localparam HGC_70HZ = 0;

    // wire composite_on;
    wire thin_font;

    // Composite mode switch
    //assign composite_on = switch3; (TODO: Test in next version, from the original Graphics Gremlin sources)

    // Thin font switch (TODO: switchable with Keyboard shortcut)
    assign thin_font = 1'b0; // Default: No thin font

    wire composite_cga = tandy_video_en ? (swap_video ? ~composite : composite) : composite;

    // The boot artwork is a native 320x200x4 CGA signal.  Keep the CRTC
    // timing unchanged, but make the analogue decoder use the graphics-mode
    // colour/burst convention while the splash is active.
    wire cga_video_bw_mode   = splashscreen ? 1'b0 : bw_mode;
    wire cga_video_hres_mode = splashscreen ? 1'b0 : hres_mode;
    wire cga_video_grph_mode = splashscreen ? 1'b1 : grph_mode;
    wire [3:0] cga_video_border_color = splashscreen ? 4'h0 : composite_border_color;

    // The CGA outputs the border colour on every line outside the picture, as it
    // does during horizontal blanking. The pixel stream carries no defined data
    // there, so give the converter the border colour rather than whatever the
    // stream holds (it showed as stray coloured lines when the overscan is visible).
    // The stream is black during HSYNC; the border window starts inside the
    // 160-pixel HSYNC of the 40-column modes, so that is border colour too (the
    // composite decoder keeps the real signal). Outside the window it is never
    // shown: the scaler and the analogue output blank it.
    wire [3:0] video_cga_port = (vblank_cga_crtc | (hsync_cga_raw & ~composite_cga)) ?
                                cga_video_border_color : video_cga_raw;

    assign VGA_VBlank_border = `ENABLE_CGA ? VGA_VBlank_border_raw : (`ENABLE_HGC ? vblank_border_hgc : 1'b0);
    assign VGA_HSYNC_REF = `ENABLE_CGA ? hsync_ref_cga : 1'b0;
    assign VGA_VSYNC_REF = `ENABLE_CGA ? vsync_ref_cga : 1'b0;
    assign std_hsyncwidth = `ENABLE_CGA ? std_hsyncwidth_raw : (`ENABLE_HGC ? std_hsyncwidth_hgc : 1'b0);
    assign tandy_color_16 = `ENABLE_CGA ? tandy_color_16_raw : 1'b0;


    // CGA digital to analog converter
    cga_vgaport vga_cga 
    (
        .clk(clk_vga_cga),
        .clkdiv(clkdiv),
        // Composite decoding must see the native CGA dot stream.  The
        // scan-doubled RGBI stream has a different time base and loses the
        // phase relationship used by 8088 MPH colour effects.
        .video(video_cga_port),
        .hblank(hblank_cga_raw),
        .composite(composite_cga),
        .bw_mode(cga_video_bw_mode),
        .hres_mode(cga_video_hres_mode),
        .grph_mode(cga_video_grph_mode),
        .hsync_width(composite_hsync_width),
        .border_color(cga_video_border_color),
        .phase(composite_phase),
        .scandouble(1'b0),
        .red(R_CGA_native),
        .green(G_CGA_native),
        .blue(B_CGA_native)
    );

    // The decoded RGB leaves the decoder 5 clocks after the CRTC blanking
    // edge (later with the composite filter or a Tandy 16-colour mode).  The
    // scandoubler takes its line window from the samples it stores, so give
    // it the horizontal enable at the RGB's own time.  These are the native
    // path's taps in PCXT.sv minus 2: there the monochrome converter's extra
    // colour register sits after the blanking tap, here after the doubler.
    reg  [21:0] hblank_cga_raw_del = 22'h3FFFFF;
    always_ff @(posedge clk_vga_cga)
        hblank_cga_raw_del <= {hblank_cga_raw_del[20:0], hblank_cga_raw};

    wire cga_sd_hblank_in = composite_cga  ? (hblank_cga_raw_del[20] | hblank_cga_raw_del[0]) :
                            tandy_color_16 ? hblank_cga_raw_del[9] :
                            tandy_16_gfx   ? hblank_cga_raw_del[7] :
                                             hblank_cga_raw_del[4];

    // The converter registers colour once more than blanking; one doubled
    // pixel is one clock here.
    reg hblank_cga_sd_r = 1'b1;
    always_ff @(posedge clk_vga_cga)
        hblank_cga_sd_r <= ~de_o_cga_sd;
    assign hblank_cga_sd = hblank_cga_sd_r;

    // The decoder above runs at the native CGA rate.  Only the decoded RGB
    // stream is doubled for the digital output, preserving the original line
    // sample sequence and its carrier phase.
    video_scandoubler_cga #(
        .PIXEL_WIDTH(18),
        .H_TOTAL_MAX(912)
    ) cga_rgb_scandoubler (
        .clk(clk_vga_cga),
        .ce_pix(clkdiv[0]),
        .ce_2x(1'b1),
        .scandouble_en(cga_scandouble_en),
        .pixel_in({B_CGA_native, G_CGA_native, R_CGA_native}),
        .hsync_in(hsync_cga_raw),
        .vsync_in(vsync_cga_raw),
        .vblank_in(vblank_cga_raw),
        .display_enable_in(~cga_sd_hblank_in),
        .pixel_out(cga_rgb_sd),
        .hsync_out(hsync_cga_sd),
        .vsync_out(vsync_cga_sd),
        .vblank_out(vblank_cga_sd),
        .display_enable_out(de_o_cga_sd)
    );

    cga cga1 
    (
        .clk                        (clk_vga_cga),
        .reset                      (video_reset_cga | ega_active_cga),
        .clkdiv                     (clkdiv),
        .bus_a                      (cga_io_address_2),
        .bus_ior_l                  (cga_io_read_n_2),
        .bus_iow_l                  (cga_io_write_n_2),
        .bus_memr_l                 (1'd0),
        .bus_memw_l                 (1'd0),
        .bus_d                      (cga_io_data_2),
        .bus_out                    (CGA_CRTC_DOUT),
        .bus_dir                    (CGA_CRTC_OE),
        .bus_aen                    (cga_address_enable_n_2),
        .ram_we_l                   (CGA_VRAM_ENABLE),
        .ram_a                      (CGA_VRAM_ADDR),
        .ram_d                      (CGA_VRAM_DOUT),
        .hsync                      (hsync_cga_raw),
        .dbl_hsync                  (hsync_cga_rgbi_sd),
        .hblank                     (),
        .raw_hblank                 (hblank_cga_raw),
        .raw_vblank                 (vblank_cga_crtc),
        .vsync                      (vsync_cga_raw),
        .vblank                     (vblank_cga_raw),
        .vblank_border              (VGA_VBlank_border_raw),
        .hsync_ref                  (hsync_ref_cga),
        .vsync_ref                  (vsync_ref_cga),
        .std_hsyncwidth             (std_hsyncwidth_raw),
        .de_o                       (),
        .raw_de_o                   (de_o_cga_raw),
        .video                      (video_cga_raw),
        .dbl_video                  (video_cga_sd),
        .splashscreen               (splashscreen),
        .composite                  (composite_cga),
        .thin_font                  (thin_font),
        .tandy_video                (tandy_video_en),
        .scandouble_en              (cga_scandouble_en),
        .grph_mode                  (grph_mode),
        .hres_mode                  (hres_mode),
        .bw_mode                    (bw_mode),
        .mode_640                   (mode_640),
        .composite_hsync_width       (composite_hsync_width),
        .composite_border_color      (composite_border_color),
        .composite_phase             (composite_phase),
        .tandy_color_16             (tandy_color_16_raw),
        .cga_hw                     (cga_hw),
        .crt_h_offset               (crt_h_offset),
        .crt_v_offset               (crt_v_offset),
        .vsync_width_osd            (vsync_width_osd),
        .hsync_width_osd            (hsync_width_osd),
        .frame_stack_rebuild        (cga_frame_stack_rebuild),
        .fx_next_word               (fx_cga_next_word)
    );

    always_ff @(posedge clock)
    begin
        if (`ENABLE_CGA)
        begin
            CGA_CRTC_OE_1   <= CGA_CRTC_OE;
            CGA_CRTC_OE_2   <= CGA_CRTC_OE_1;
            CGA_CRTC_DOUT_1 <= CGA_CRTC_DOUT;
            CGA_CRTC_DOUT_2 <= CGA_CRTC_DOUT_1;
        end
        else
        begin
            CGA_CRTC_OE_1   <= 1'b0;
            CGA_CRTC_OE_2   <= 1'b0;
            CGA_CRTC_DOUT_1 <= 8'h00;
            CGA_CRTC_DOUT_2 <= 8'h00;
        end
    end


    defparam cga1.BLINK_MAX = 24'd4772727;
    defparam hgc1.BLINK_MAX = 24'd9100000;
    // Video memory lives in SDRAM. The CPU's reads and writes go through the
    // memory map and the memory port (mem_map, cpu_mem_port); what the two cards
    // read comes from the video fetch engines at the top level, through the
    // adapters (crtc_vram_if), which need the sequencer phase, the word being
    // addressed and the word of the next character.
    assign CGA_VRAM_DOUT = fx_cga_vram_d;
    assign HGC_VRAM_DOUT = fx_hgc_vram_d;

    assign fx_cga_phase     = clkdiv;
    assign fx_cga_hres      = hres_mode;
    assign fx_cga_cur_word  = CGA_VRAM_ADDR[14:1];
    assign fx_hgc_grph      = hgc_grph_mode;
    assign fx_hgc_page      = hgc_grph_page;
    assign fx_hgc_cur_word  = HGC_VRAM_ADDR[14:1];

    // The Hercules page crosses from the HGC clock to the chipset clock
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] hgc_page_meta = 2'b00;
    always_ff @(posedge clock)
        hgc_page_meta <= {hgc_page_meta[0], hgc_grph_page};
    assign hgc_page_sys = hgc_page_meta[1];

    //
    // EGA / VGA 13h+ card
    //
    // Built only when ENABLE_EGA is set, and then only the machine that came
    // out of reset with ega_active drives anything: the card is held in reset
    // otherwise, its bus strobes never reach it, and its memory window and its
    // data bus tap stay off. The CGA and Hercules cards above get the same
    // treatment in the other direction, so exactly one family answers.
    generate
    if (`ENABLE_EGA) begin : EGA_CARD

        // Release reset on the clock that consumes it. The frontend's CPU side
        // runs on the chipset clock, the card itself on the 28.636 MHz clock.
        (* ASYNC_REG = "TRUE" *) logic [1:0] video_reset_clock_sync = 2'b11;
        wire video_reset_clock = video_reset_clock_sync[1];
        wire video_reset_video = video_reset_cga | ~ega_active_cga;

        always_ff @(posedge clock or posedge video_reset) begin
            if (video_reset)
                video_reset_clock_sync <= 2'b11;
            else
                video_reset_clock_sync <= {video_reset_clock_sync[0], 1'b0};
        end

        // The OSD status originates in the chipset clock domain. Treat the
        // monitor choice like a physical switch and synchronise its static
        // level before exposing it to the card's input-status register.
        (* ASYNC_REG = "TRUE" *) logic [1:0] ega_monitor_profile_meta = 2'b00;
        (* ASYNC_REG = "TRUE" *) logic [1:0] ega_monitor_profile_sync = 2'b00;

        always_ff @(posedge clk_vga_cga) begin
            if (video_reset_video) begin
                ega_monitor_profile_meta <= 2'b00;
                ega_monitor_profile_sync <= 2'b00;
            end
            else begin
                ega_monitor_profile_meta <= ega_monitor_profile;
                ega_monitor_profile_sync <= ega_monitor_profile_meta;
            end
        end

        // The packed 13h framebuffer is the CPU's A0000 window while VGA 13h
        // is packed (not Mode X or 0Dh, whose planes the frontend serves).
        wire vga_mode13_active_video;
        wire vga_planar_memory_active_video;
        logic vga_mode13_active_sync1;
        logic vga_mode13_active_sync2;
        logic vga_planar_memory_active_sync1;
        logic vga_planar_memory_active_sync2;

        always_ff @(posedge clock or posedge reset) begin
            if (reset) begin
                vga_mode13_active_sync1        <= 1'b0;
                vga_mode13_active_sync2        <= 1'b0;
                vga_planar_memory_active_sync1 <= 1'b0;
                vga_planar_memory_active_sync2 <= 1'b0;
            end else begin
                vga_mode13_active_sync1        <= vga_mode13_active_video;
                vga_mode13_active_sync2        <= vga_mode13_active_sync1;
                vga_planar_memory_active_sync1 <= vga_planar_memory_active_video;
                vga_planar_memory_active_sync2 <= vga_planar_memory_active_sync1;
            end
        end

        assign vga_mode13_active_out = vga_mode13_active_video;
        assign vga13_packed_cpu_w    = vga_mode13_active_sync2 & ~vga_planar_memory_active_sync2;
        assign vga13_packed_cpu      = vga13_packed_cpu_w;

        assign ega_mem_select_raw = ~iorq && ~address_enable_n && ega_active
                                  && ega_memory_window_select(address, ega_mem_map_sel_cfg);

        // The I/O cycle towards the video clock domain used to be a live
        // registered copy of the bus, which left every write racing the far
        // side's two-sample qualifier; at the PC/AT 3.5MHz setting the pulse is
        // barely as long as the qualifier needs and writes were lost by clock
        // phase. The stretcher posts each write with a guaranteed minimum width
        // instead. Address latching for reads and the write-only data latch are
        // preserved inside it: on a read internal_data_bus carries the card's
        // own reply, so data must never latch under the read strobe.
        logic  [14:0]  ega_io_address_s;
        logic  [7:0]   ega_io_data_s;
        logic          ega_io_write_n_s;
        logic          ega_io_read_n_s;
        logic          ega_address_enable_n_s;
        logic          ega_stretch_ready;

        ega_io_stretch u_ega_io_stretch (
            .clock                  (clock),
            .reset                  (reset),
            .io_write_n             (io_write_n),
            .io_read_n              (io_read_n),
            .address_enable_n       (address_enable_n),
            .address                ({1'b0, address[13:0]}),
            .write_data             (internal_data_bus),
            .video_address          (ega_io_address_s),
            .video_data             (ega_io_data_s),
            .video_io_write_n       (ega_io_write_n_s),
            .video_io_read_n        (ega_io_read_n_s),
            .video_address_enable_n (ega_address_enable_n_s),
            .access_ready           (ega_stretch_ready)
        );

        // CGA and Hercules cycle-count against the unstretched bus, so the
        // stretcher's backpressure only exists while the EGA is the card.
        assign video_io_access_ready = ega_active ? ega_stretch_ready : 1'b1;

        // Input Status 0 switch sense is physically selected by the same ISA OUT
        // that programs Miscellaneous Output, and it is answered entirely here:
        // ega_top does not decode 3C2h reads, so this is the only source of the
        // byte. Both the selector and the readback therefore live on the live
        // 8088 bus, with no clock crossing and no posted-write queue in between.
        //
        // That matters because the ROM issues OUT 3C2h,01h, then two
        // instructions later OUT 3C2h,0Dh followed at once by IN 3C2h. Anything
        // that delays the second selector past the read - the video clock
        // domain, or the posted write still queued behind the first OUT in
        // ega_io_stretch - answers that first probe with the previous selector
        // and turns the CGA 80-column pattern 0111b into 0110b, which is the
        // CGA 40-column setting.
        ega_switch_sense_host ega_switch_sense_isa (
            .clock            (clock),
            .reset            (reset),
            .monitor_profile  (ega_monitor_profile),
            .io_address       ({1'b0, address[13:0]}),
            .io_data          (internal_data_bus),
            .io_write_n       (io_write_n),
            .io_read_n        (io_read_n),
            .address_enable_n (address_enable_n | ~ega_active),
            .data_out         (ega_switch_sense_data),
            .output_enable    (ega_switch_sense_oe)
        );

        logic  [14:0]  ega_io_address_sync1;
        logic  [14:0]  ega_io_address_sync2;
        logic  [7:0]   ega_io_data_sync1;
        logic  [7:0]   ega_io_data_sync2;
        logic          ega_io_write_n_sync1;
        logic          ega_io_write_n_sync2;
        logic          ega_io_read_n_sync1;
        logic          ega_io_read_n_sync2;
        logic          ega_address_enable_n_sync1;
        logic          ega_address_enable_n_sync2;
        logic          ega_mem_select_sys;
        logic          ega_mem_write_sys;
        logic          ega_mem_select_1;
        logic          ega_mem_select_2;
        logic          ega_mem_write_1;
        logic          ega_mem_write_2;

        always_ff @(posedge clock)
        begin
            ega_mem_select_sys <= ega_mem_select;
            ega_mem_write_sys  <= ega_mem_select & ~memory_write_n;
        end

        always_ff @(posedge clk_vga_cga, posedge video_reset_video)
        begin
            if (video_reset_video)
            begin
                ega_io_address_sync1        <= 15'd0;
                ega_io_address_sync2        <= 15'd0;
                ega_io_data_sync1           <= 8'd0;
                ega_io_data_sync2           <= 8'd0;
                ega_io_write_n_sync1        <= 1'b1;
                ega_io_write_n_sync2        <= 1'b1;
                ega_io_read_n_sync1         <= 1'b1;
                ega_io_read_n_sync2         <= 1'b1;
                ega_address_enable_n_sync1  <= 1'b1;
                ega_address_enable_n_sync2  <= 1'b1;
                ega_mem_select_1            <= 1'b0;
                ega_mem_select_2            <= 1'b0;
                ega_mem_write_1             <= 1'b0;
                ega_mem_write_2             <= 1'b0;
            end
            else
            begin
                ega_io_address_sync1        <= ega_io_address_s;
                ega_io_address_sync2        <= ega_io_address_sync1;
                ega_io_data_sync1           <= ega_io_data_s;
                ega_io_data_sync2           <= ega_io_data_sync1;
                ega_io_write_n_sync1        <= ega_io_write_n_s;
                ega_io_write_n_sync2        <= ega_io_write_n_sync1;
                ega_io_read_n_sync1         <= ega_io_read_n_s;
                ega_io_read_n_sync2         <= ega_io_read_n_sync1;
                ega_address_enable_n_sync1  <= ega_address_enable_n_s;
                ega_address_enable_n_sync2  <= ega_address_enable_n_sync1;
                ega_mem_select_1            <= ega_mem_select_sys;
                ega_mem_select_2            <= ega_mem_select_1;
                ega_mem_write_1             <= ega_mem_write_sys;
                ega_mem_write_2             <= ega_mem_write_1;
            end
        end

        wire [15:0] VGA_FRAMEBUFFER_ADDR;
        wire        VGA_FRAMEBUFFER_READ_EN;
        wire [7:0]  VGA_FRAMEBUFFER_PIXEL;
        wire        VGA_FRAMEBUFFER_DATA_VALID;
        wire        hsync_ega_raw;
        wire        hsync_ega_sd;
        wire        video_display_active;
        wire        ega_scandouble_active;
        wire        ega_hsync_sel = ega_scandouble_active ? hsync_ega_sd : hsync_ega_raw;

        wire        EGA_IO_OE;
        logic       EGA_IO_OE_SYNC1;
        logic       EGA_IO_OE_SYNC2;
        wire [7:0]  EGA_IO_DOUT;
        logic [7:0] EGA_IO_DOUT_SYNC1;
        logic [7:0] EGA_IO_DOUT_SYNC2;
        wire [15:0] EGA_FETCH_ADDR;
        wire        EGA_FETCH_EN;
        wire [7:0]  EGA_PLANE0_DOUT;
        wire [7:0]  EGA_PLANE1_DOUT;
        wire [7:0]  EGA_PLANE2_DOUT;
        wire [7:0]  EGA_PLANE3_DOUT;
        wire        EGA_FETCH_DATA_VALID;
        wire [15:0] EGA_TEXT_CELL_ADDR;
        wire [4:0]  EGA_TEXT_SCANLINE;
        wire        EGA_TEXT_TAG;
        wire        EGA_TEXT_TAG_IN;
        wire [1:0]  EGA_CHAR_MAP_A;
        wire [1:0]  EGA_CHAR_MAP_B;
        wire        EGA_CE_PIX;
        wire        EGA_PRIV_ROUTE;
        wire        EGA_SPLASH_CE;
        wire        EGA_SPLASH_DE;
        wire [9:0]  EGA_SPLASH_SCAN;
        wire [3:0]  EGA_SPLASH_PIX;
        wire        EGA_SPLASH_PIX_VALID;
        wire        EGA_TEXT_FETCH_EN;
        wire [7:0]  EGA_TEXT_CHAR;
        wire [7:0]  EGA_TEXT_ATTR;
        wire [7:0]  EGA_TEXT_GLYPH;
        wire        EGA_TEXT_DATA_VALID;
        wire        ega_cfg_toggle;
        wire [3:0]  ega_plane_write_mask_cfg;
        wire        ega_odd_even_mode_cfg;
        wire        ega_cpu_access_slot_cfg;
        wire        ega_chain2_write_cfg;
        wire        ega_chain2_read_cfg;
        wire        ega_extended_memory_cfg;
        wire        ega_page_select_cfg;
        wire [1:0]  ega_write_mode_cfg;
        wire [1:0]  ega_read_mode_cfg;
        wire [1:0]  ega_read_plane_sel_cfg;
        wire [7:0]  ega_color_compare_cfg;
        wire [7:0]  ega_color_dont_care_cfg;
        wire [7:0]  ega_bit_mask_cfg;
        wire [7:0]  ega_set_reset_cfg;
        wire [3:0]  ega_enable_set_reset_cfg;
        wire [1:0]  ega_rop_select_cfg;
        wire [2:0]  ega_rotate_count_cfg;
        wire [6:0]  ega_blink_counter;
        wire        ega_blink_state;
        wire        ega_vblank_border_raw;
        wire        ega_std_hsyncwidth_raw;
        wire        thin_font = 1'b0;     // Default: No thin font

        assign ega_scandouble_active_out = ega_scandouble_active;
        assign EGA_HSYNC                 = ega_hsync_sel;
        assign EGA_VBlank_border         = ega_vblank_border_raw;
        assign EGA_std_hsyncwidth        = ega_std_hsyncwidth_raw;

        ega_top ega1
        (
            .clk                        (clk_vga_cga),
            .reset                      (video_reset_video),
            .bus_a                      (ega_io_address_sync2),
            .bus_ior_l                  (ega_io_read_n_sync2),
            .bus_iow_l                  (ega_io_write_n_sync2),
            .bus_d                      (ega_io_data_sync2),
            .bus_out                    (EGA_IO_DOUT),
            .bus_dir                    (EGA_IO_OE),
            .bus_aen                    (ega_address_enable_n_sync2),
            .ega_fetch_addr             (EGA_FETCH_ADDR),
            .ega_fetch_en               (EGA_FETCH_EN),
            .ega_plane0_data            (EGA_PLANE0_DOUT),
            .ega_plane1_data            (EGA_PLANE1_DOUT),
            .ega_plane2_data            (EGA_PLANE2_DOUT),
            .ega_plane3_data            (EGA_PLANE3_DOUT),
            .ega_fetch_data_valid       (EGA_FETCH_DATA_VALID),
            .ega_text_cell_addr         (EGA_TEXT_CELL_ADDR),
            .ega_text_scanline          (EGA_TEXT_SCANLINE),
            .ega_text_tag               (EGA_TEXT_TAG),
            .ega_text_fetch_en          (EGA_TEXT_FETCH_EN),
            .ega_text_char              (EGA_TEXT_CHAR),
            .ega_text_attr              (EGA_TEXT_ATTR),
            .ega_text_glyph             (EGA_TEXT_GLYPH),
            .ega_text_tag_in            (EGA_TEXT_TAG_IN),
            .ega_text_data_valid        (EGA_TEXT_DATA_VALID),
            .ega_char_map_a_out         (EGA_CHAR_MAP_A),
            .ega_char_map_b_out         (EGA_CHAR_MAP_B),
            .ega_ce_pix_out             (EGA_CE_PIX),
            .ega_priv_route_out         (EGA_PRIV_ROUTE),
            .vga_framebuffer_addr       (VGA_FRAMEBUFFER_ADDR),
            .vga_framebuffer_read_en    (VGA_FRAMEBUFFER_READ_EN),
            .vga_framebuffer_pixel      (VGA_FRAMEBUFFER_PIXEL),
            .vga_framebuffer_data_valid (VGA_FRAMEBUFFER_DATA_VALID),
            .cpu_mem_select             (ega_mem_select_2),
            .cpu_mem_write              (ega_mem_write_2),
            .ega_cfg_toggle             (ega_cfg_toggle),
            .ega_plane_write_mask_out   (ega_plane_write_mask_cfg),
            .ega_odd_even_mode_out      (ega_odd_even_mode_cfg),
            .ega_cpu_access_slot_out    (ega_cpu_access_slot_cfg),
            .ega_chain2_write_out       (ega_chain2_write_cfg),
            .ega_chain2_read_out        (ega_chain2_read_cfg),
            .ega_extended_memory_out    (ega_extended_memory_cfg),
            .ega_mem_map_sel_out        (ega_mem_map_sel_cfg),
            .ega_page_select_out        (ega_page_select_cfg),
            .ega_write_mode_out         (ega_write_mode_cfg),
            .ega_read_mode_out          (ega_read_mode_cfg),
            .ega_read_plane_sel_out     (ega_read_plane_sel_cfg),
            .ega_color_compare_out      (ega_color_compare_cfg),
            .ega_color_dont_care_out    (ega_color_dont_care_cfg),
            .ega_bit_mask_out           (ega_bit_mask_cfg),
            .ega_set_reset_out          (ega_set_reset_cfg),
            .ega_enable_set_reset_out   (ega_enable_set_reset_cfg),
            .ega_rop_select_out         (ega_rop_select_cfg),
            .ega_rotate_count_out       (ega_rotate_count_cfg),
            .ega_blink_counter_out      (ega_blink_counter),
            .ega_blink_state_out        (ega_blink_state),
            .hsync                      (hsync_ega_raw),
            .dbl_hsync                  (hsync_ega_sd),
            .hblank                     (EGA_HBlank),
            .vsync                      (EGA_VSYNC),
            .vblank                     (EGA_VBlank),
            .vblank_border              (ega_vblank_border_raw),
            .std_hsyncwidth             (ega_std_hsyncwidth_raw),
            .de_o                       (EGA_de_o),
            .ega_red                    (EGA_R),
            .ega_green                  (EGA_G),
            .ega_blue                   (EGA_B),
            .ega_display_sel_out        (video_display_active),
            .ega_dot_toggle_out         (ega_dot_toggle),
            .ega_dot_clock_sel_out      (ega_dot_clock_sel),
            .ega_scandouble_active_out  (ega_scandouble_active),
            .ega_vmode_toggle_out       (ega_vmode_toggle_out),
            .ega_mode350_out            (ega_mode350),
            .ega_active_dots_out        (ega_active_dots),
            .ega_active_lines_out       (ega_active_lines),
            .splashscreen               (splashscreen),
            .ext_splash_pixel_index     (EGA_SPLASH_PIX),
            .ext_splash_pixel_valid     (EGA_SPLASH_PIX_VALID),
            .ext_splash_ce_pix          (EGA_SPLASH_CE),
            .ext_splash_display_enable  (EGA_SPLASH_DE),
            .ext_splash_scanline        (EGA_SPLASH_SCAN),
            .prebios_video              (1'b0),
            .thin_font                  (thin_font),
            .scandouble_en              (cga_scandouble_en),
            .ega_enabled                (1'b1),
            .ega_monitor_profile        (ega_monitor_profile_sync),
            .vga_enabled                (`ENABLE_VGA13 ? vga_mode13_osd : 1'b0),
            .vga_mode13_native          (vga_mode13_native),
            .vga_mode13_set             (1'b0),
            .vga_mode13_clear           (1'b0),
            .vga_mode13_active_out      (vga_mode13_active_video),
            .vga_unchained256_active_out(),
            .vga_mode13_wide_clock_out  (vga_mode13_wide_clock_out),
            .vga_planar_memory_active_out(vga_planar_memory_active_video),
            .vga_mode13_pixel_toggle_out(vga_mode13_pixel_toggle_out),
            .crt_h_offset               (crt_h_offset),
            .crt_v_offset               (crt_v_offset),
            .vsync_width_osd            (vsync_width_osd),
            .hsync_width_osd            (hsync_width_osd)
        );

        always_ff @(posedge clock)
        begin
            EGA_IO_OE_SYNC1   <= EGA_IO_OE;
            EGA_IO_OE_SYNC2   <= EGA_IO_OE_SYNC1;
            EGA_IO_DOUT_SYNC1 <= EGA_IO_DOUT;
            EGA_IO_DOUT_SYNC2 <= EGA_IO_DOUT_SYNC1;
        end

        assign ega_io_oe_sys   = EGA_IO_OE_SYNC2;
        assign ega_io_dout_sys = EGA_IO_DOUT_SYNC2;

        defparam ega1.BLINK_MAX = 24'd4772727;
        // The video memory is read ahead of the display (vram_fetch): the
        // display side is retimed to match; the same numbers are given to the
        // frontend below.
        defparam ega1.SDRAM_LEAD_DOTS  = 16;
        defparam ega1.SDRAM_PRIV_EXTRA = 16;

        // The boot picture of the EGA card is the core's own
        ega_splash_renderer ega_splash_renderer_inst (
            .clk            (clk_vga_cga),
            .reset          (video_reset_video),
            .ce_pix         (EGA_SPLASH_CE),
            .enable         (splashscreen),
            .display_enable (EGA_SPLASH_DE),
            .scanline       (EGA_SPLASH_SCAN),
            .pixel_index    (EGA_SPLASH_PIX),
            .pixel_valid    (EGA_SPLASH_PIX_VALID)
        );

        wire [15:0] ega_vram_cpu_addr = address[15:0];
        wire        ega_vram_cpu_a16 = address[16];
        wire [7:0]  ega_vram_cpu_din = internal_data_bus;
        wire        ega_vram_cpu_read_req = ega_mem_select && ~memory_read_n;
        wire        ega_vram_cpu_write_req = ega_mem_select && ~memory_write_n;
        wire        ega_vram_cpu_cycle = ega_vram_cpu_read_req | ega_vram_cpu_write_req;
        wire        ega_vram_cpu_ready;
        wire [15:0] ega_vram_underruns;

        ega_vram_sdram_frontend
        #(
            .LEAD_GFX                   (16),
            .LEAD_CELL                  (9),
            .LEAD_GLYPH                 (10),
            .EXTRA_PRIV                 (16),
            .EXTRA_FB                   (16)
        )
        ega_vram_frontend
        (
            .clock                      (clock),
            .reset_cpu                  (video_reset_clock | ~ega_active),
            .cpu_addr                   (ega_vram_cpu_addr),
            .cpu_a16                    (ega_vram_cpu_a16),
            .cpu_din                    (ega_vram_cpu_din),
            .cpu_read                   (ega_vram_cpu_read_req),
            .cpu_write                  (ega_vram_cpu_write_req),
            .cpu_dout                   (ega_vram_cpu_dout),
            .cpu_ready                  (ega_vram_cpu_ready),
            .m_start                    (vram_m_start),
            .m_we                       (vram_m_we),
            .m_addr                     (vram_m_addr),
            .m_len                      (vram_m_len),
            .m_wdata                    (vram_m_wdata),
            .m_wbe                      (vram_m_wbe),
            .m_busy                     (vram_m_busy),
            .m_done                     (vram_m_done),
            .m_rdata                    (vram_m_rdata),
            .clk_video                  (clk_vga_cga),
            .reset_video                (video_reset_video),
            .dot_tick                   (EGA_CE_PIX),
            .priv_route                 (EGA_PRIV_ROUTE),
            .video_addr                 (EGA_FETCH_ADDR),
            .video_read_en              (EGA_FETCH_EN),
            .video_plane0               (EGA_PLANE0_DOUT),
            .video_plane1               (EGA_PLANE1_DOUT),
            .video_plane2               (EGA_PLANE2_DOUT),
            .video_plane3               (EGA_PLANE3_DOUT),
            .video_data_valid           (EGA_FETCH_DATA_VALID),
            .text_cell_addr             (EGA_TEXT_CELL_ADDR),
            .text_scanline              (EGA_TEXT_SCANLINE),
            .text_tag                   (EGA_TEXT_TAG),
            .text_fetch_en              (EGA_TEXT_FETCH_EN & video_display_active),
            .char_map_a                 (EGA_CHAR_MAP_A),
            .char_map_b                 (EGA_CHAR_MAP_B),
            .text_char                  (EGA_TEXT_CHAR),
            .text_attr                  (EGA_TEXT_ATTR),
            .text_glyph                 (EGA_TEXT_GLYPH),
            .text_tag_out               (EGA_TEXT_TAG_IN),
            .text_data_valid            (EGA_TEXT_DATA_VALID),
            .fb_addr                    (VGA_FRAMEBUFFER_ADDR),
            .fb_read_en                 (VGA_FRAMEBUFFER_READ_EN),
            .fb_pixel                   (VGA_FRAMEBUFFER_PIXEL),
            .fb_data_valid              (VGA_FRAMEBUFFER_DATA_VALID),
            .cfg_toggle                 (ega_cfg_toggle),
            .plane_write_mask           (ega_plane_write_mask_cfg),
            .odd_even_mode              (ega_odd_even_mode_cfg),
            .cpu_access_en              (ega_cpu_access_slot_cfg),
            .chain2_write               (ega_chain2_write_cfg),
            .chain2_read                (ega_chain2_read_cfg),
            .extended_memory            (ega_extended_memory_cfg),
            .mem_map_sel                (ega_mem_map_sel_cfg),
            .page_select                (ega_page_select_cfg),
            .write_mode                 (ega_write_mode_cfg),
            .read_mode                  (ega_read_mode_cfg),
            .read_plane_sel             (ega_read_plane_sel_cfg),
            .color_compare              (ega_color_compare_cfg),
            .color_dont_care            (ega_color_dont_care_cfg),
            .bit_mask                   (ega_bit_mask_cfg),
            .set_reset                  (ega_set_reset_cfg),
            .enable_set_reset           (ega_enable_set_reset_cfg),
            .rop_select                 (ega_rop_select_cfg),
            .rotate_count               (ega_rotate_count_cfg),
            .sdram_clk                  (sdram_clk),
            .sdram_reset                (sdram_reset),
            .vid_req                    (vid_req),
            .vid_addr                   (vid_addr),
            .vid_len                    (vid_len),
            .vid_deadline               (vid_deadline),
            .vid_ack                    (vid_ack),
            .vid_rvalid                 (vid_rvalid),
            .vid_rlast                  (vid_rlast),
            .vid_rdata                  (vid_rdata),
            .snoop_valid                (snoop_valid),
            .snoop_addr                 (snoop_addr),
            .snoop_len                  (snoop_len),
            .snoop_wdata                (snoop_wdata),
            .snoop_wbe                  (snoop_wbe),
            .underrun_count             (ega_vram_underruns)
        );

        assign video_memory_access_ready = ega_vram_cpu_cycle ? ega_vram_cpu_ready : 1'b1;
        assign id_video_underruns        = ega_vram_underruns;
    end
    else begin : NO_EGA_CARD
        assign video_io_access_ready     = 1'b1;
        assign video_memory_access_ready = 1'b1;
        assign id_video_underruns        = 16'd0;
        assign vga13_packed_cpu          = 1'b0;
        assign vga13_packed_cpu_w        = 1'b0;
        assign vga_mode13_active_out     = 1'b0;
        assign vga_mode13_wide_clock_out = 1'b0;
        assign vga_mode13_pixel_toggle_out = 1'b0;
        assign ega_mem_select_raw        = 1'b0;
        assign ega_mem_map_sel_cfg       = 2'b00;
        assign ega_io_oe_sys             = 1'b0;
        assign ega_io_dout_sys           = 8'h00;
        assign ega_switch_sense_oe       = 1'b0;
        assign ega_switch_sense_data     = 8'h00;
        assign ega_vram_cpu_dout         = 8'h00;
        assign ega_dot_toggle            = 1'b0;
        assign ega_dot_clock_sel         = 1'b0;
        assign ega_scandouble_active_out = 1'b0;
        assign ega_vmode_toggle_out      = 1'b0;
        assign ega_mode350               = 1'b0;
        assign ega_active_dots           = 12'd0;
        assign ega_active_lines          = 10'd0;
        assign EGA_R                     = 6'd0;
        assign EGA_G                     = 6'd0;
        assign EGA_B                     = 6'd0;
        assign EGA_HSYNC                 = 1'b0;
        assign EGA_VSYNC                 = 1'b0;
        assign EGA_HBlank                = 1'b0;
        assign EGA_VBlank                = 1'b0;
        assign EGA_VBlank_border         = 1'b0;
        assign EGA_std_hsyncwidth        = 1'b0;
        assign EGA_de_o                  = 1'b0;
        assign vram_m_start              = 1'b0;
        assign vram_m_we                 = 1'b0;
        assign vram_m_addr               = 24'd0;
        assign vram_m_len                = 2'd0;
        assign vram_m_wdata              = 64'd0;
        assign vram_m_wbe                = 8'd0;
        assign vid_req                   = 1'b0;
        assign vid_addr                  = 24'd0;
        assign vid_len                   = 2'd0;
        assign vid_deadline              = 16'd0;
    end
    endgenerate

    //
    // XT2IDE
    //
    logic   [7:0]   xt2ide0_data_bus_out;
    logic           ide0_cs1fx;
    logic           ide0_cs3fx;
    logic           ide0_io_read_n;
    logic           ide0_io_write_n;
    logic   [2:0]   ide0_address;
    logic   [15:0]  ide0_data_bus_in;
    logic   [15:0]  ide0_data_bus_out;

    XT2IDE xt2ide0 (
        .clock              (clock),
        .reset              (reset),

        .high_speed         (0),

        .chip_select_n      (ide0_chip_select_n),
        .io_read_n          (io_read_n),
        .io_write_n         (io_write_n),

        .address            (address[3:0]),
        .data_bus_in        (internal_data_bus),
        .data_bus_out       (xt2ide0_data_bus_out),

        .ide_cs1fx          (ide0_cs1fx),
        .ide_cs3fx          (ide0_cs3fx),
        .ide_io_read_n      (ide0_io_read_n),
        .ide_io_write_n     (ide0_io_write_n),

        .ide_address        (ide0_address),
        .ide_data_bus_in    (ide0_data_bus_in),
        .ide_data_bus_out   (ide0_data_bus_out)
    );


    //
    // IDE
    //
    logic           mgmt_ide0_cs;
    logic [15:0]    mgmt_ide0_readdata;
    logic           ide0_command_cs;
    logic           ide0_control_cs;
    logic           ide0_comd_ctrl_select;
    logic           ide0_io_read;
    logic           ide0_io_read_1;
    logic           ide0_io_write;
    logic           prev_ide0_io_read;
    logic           prev_ide0_io_write;
    logic [3:0]     ide0_address_1;
    logic [15:0]    ide0_writedata;
    logic [15:0]    ide_readdata;
    logic           ide_ignore;

    assign mgmt_ide0_cs     = (mgmt_address[15:8] == 8'hF0);

    assign ide0_command_cs  = ~ide0_cs1fx;
    assign ide0_control_cs  = ~ide0_cs3fx & &ide0_address[2:1];
    assign ide0_io_read     = ~ide0_io_read_n  & (ide0_command_cs | ide0_control_cs);
    assign ide0_io_write    = ~ide0_io_write_n & (ide0_command_cs | ide0_control_cs);

    always_ff @(posedge clock)
    begin
        ide0_io_read_1          <= ide0_io_read;
        prev_ide0_io_read       <= ide0_io_read_1;
        prev_ide0_io_write      <= ide0_io_write;
        ide0_address_1          <= ~ide0_control_cs ? {1'b0, ide0_address} : {1'b1, ide0_address};
        ide0_writedata          <= ide0_data_bus_out;
    end

    ide ide
    (
        .clk            (clock),
        .rst_n          (~reset),

//        .irq            (),
//        .drq            (),

        .use_fast       (0),
//        .no_data        (),

//        .drive_en       (),

        .io_address     (ide0_address_1),
        .io_read        (ide0_io_read   & ~prev_ide0_io_read),
        .io_readdata    (ide_readdata),
        .io_write       (~ide0_io_write & prev_ide0_io_write),
        .io_writedata   (ide0_writedata),
        .io_32          (0),

//        .io_wait        (),

        .request                    (ide0_request),
        .mgmt_address               (mgmt_address[3:0]),
        .mgmt_writedata             (mgmt_writedata),
        .mgmt_readdata              (mgmt_ide0_readdata),
        .mgmt_write                 (mgmt_write & mgmt_ide0_cs),
        .mgmt_read                  (mgmt_read & mgmt_ide0_cs),

        .primary_only               (use_mmc == 2'b10),
        .secondary_only             (use_mmc == 2'b01),
        .ignore_access              (ide_ignore)
    );


    //
    // XTIDE-MMC
    //
    logic [15:0]    mmcide_readdata;
    wire    enable_mmc_n    = ~((use_mmc == 2'b01) | (use_mmc == 2'b10));

    KFMMC_DRIVE_IDE #(
        .init_spi_clock_cycle               (8'd150),
        .normal_spi_clock_cycle             (8'd002)
    ) u_KFMMC_DRIVE_IDE (
        .clock              (clock),
        .reset              (reset),

        .ide_cs1fx_n        (ide0_cs1fx),
        .ide_cs3fx_n        (ide0_cs3fx),
        .ide_io_read_n      (ide0_io_read_n  | enable_mmc_n),
        .ide_io_write_n     (ide0_io_write_n | enable_mmc_n),

        .ide_address        (ide0_address),
        .ide_data_bus_in    (ide0_data_bus_out),
        .ide_data_bus_out   (mmcide_readdata),

        .device_master      (use_mmc == 2'b01),

        .spi_clk            (spi_clk),
        .spi_cs             (spi_cs),
        .spi_mosi           (spi_mosi),
        .spi_miso           (spi_miso)

    );

    assign ide0_data_bus_in = ~ide_ignore ? ide_readdata : mmcide_readdata;


    //
    // FDC
    //
    logic           mgmt_fdd_cs;
    logic   [15:0]  mgmt_fdd_readdata;
    logic   [7:0]   write_to_fdd;
    logic   [2:0]   fdd_io_address;
    logic           fdd_io_read;
    logic           fdd_io_read_1;
    logic           fdd_io_write;
    logic   [7:0]   fdd_readdata_wire;
    logic   [7:0]   fdd_dma_readdata;
    logic   [7:0]   fdd_readdata;
    logic           fdd_dma_req_wire;
    logic           fdd_dma_read;
    logic           prev_fdd_dma_ack;
    logic           fdd_dma_rw_ack;
    logic           fdd_dma_tc;

    assign  mgmt_fdd_cs = (mgmt_address[15:8] == 8'hF2);

    always_ff @(posedge clock)
    begin
        if (mgmt_write & mgmt_fdd_cs & (mgmt_address[3:0] == 4'd0))
            fdd_present[mgmt_address[7]] <= mgmt_writedata[0];
    end

    always_ff @(posedge clock)
    begin
        if (~io_write_n)
            write_to_fdd  <= internal_data_bus;
        else
            write_to_fdd  <= write_to_fdd;
    end

    always_ff @(posedge clock)
    begin
        fdd_io_address     <= address[2:0];
        fdd_io_read        <= ~io_read_n & prev_io_read_n   & ~floppy0_chip_select_n;
        fdd_io_read_1      <= fdd_io_read;
        fdd_io_write       <= io_write_n & ~prev_io_write_n & ~floppy0_chip_select_n;
    end

    assign  fdd_dma_read    = fdd_dma_ack & ~io_read_n;

    always_ff @(posedge clock)
    begin
        prev_fdd_dma_ack   <= fdd_dma_ack;
    end

    assign  fdd_dma_rw_ack  = prev_fdd_dma_ack & ~fdd_dma_ack;

    always_ff @(posedge clock)
    begin
        if (fdd_dma_ack)
            if (fdd_dma_tc == 1'b0)
                fdd_dma_tc <= terminal_count;
            else
                fdd_dma_tc <= fdd_dma_tc;
        else
            fdd_dma_tc <= 1'b0;
    end

    floppy floppy 
    (
        .clk                        (clock),
        .rst_n                      (~reset),

        //dma
        .dma_req                    (fdd_dma_req_wire),
        .dma_ack                    (fdd_dma_rw_ack),
        .dma_tc                     (fdd_dma_tc & fdd_dma_rw_ack),
        .dma_readdata               (write_to_fdd),
        .dma_writedata              (fdd_dma_readdata),

        //irq
        .irq                        (fdd_interrupt),

        //io buf
        .io_address                 (fdd_io_address),
        .io_read                    (fdd_io_read),
        .io_readdata                (fdd_readdata_wire),
        .io_write                   (fdd_io_write),
        .io_writedata               (write_to_fdd),

        //        .fdd0_inserted              (),

        .mgmt_address               (mgmt_address[3:0]),
        .mgmt_fddn                  (mgmt_address[7]),
        .mgmt_write                 (mgmt_write & mgmt_fdd_cs),
        .mgmt_writedata             (mgmt_writedata),
        .mgmt_read                  (mgmt_read  & mgmt_fdd_cs),
        .mgmt_readdata              (mgmt_fdd_readdata),

        .wp                         (floppy_wp),

        .clock_rate                 (clk_select[1] == 1'b0 ? clk_rate :
                                     clk_select[0] == 1'b0 ? {1'b0, clk_rate[27:1]} : {2'b00, clk_rate[27:2]}),

        .request                    (fdd_request)
    );

    always_ff @(posedge clock)
    begin
        if (fdd_dma_ack)
            fdd_dma_req <= 1'b0;
        else if (cpu_ce_negedge)
            fdd_dma_req <= fdd_dma_req_wire;
        else
            fdd_dma_req <= fdd_dma_req;
    end

    always_ff @(posedge clock)
    begin
        if ((fdd_io_read_1) && (~address_enable_n))
            fdd_readdata <= fdd_readdata_wire;
        else if (fdd_dma_read)
            fdd_readdata <= fdd_dma_readdata;
        else
            fdd_readdata <= fdd_readdata;
    end


    //
    // mgmt_readdata
    //
    assign mgmt_readdata = mgmt_ide0_cs ? mgmt_ide0_readdata : mgmt_fdd_readdata;


    //
    // KFTVGA
    //
    
    // logic   [7:0]   tvga_data_bus_out;

    // KFTVGA u_KFTVGA (
    //     // Bus
    //     .clock                      (clock),
    //     .reset                      (reset),
    //     .chip_select_n              (tvga_chip_select_n),
    //     .read_enable_n              (memory_read_n),
    //     .write_enable_n             (memory_write_n),
    //     .address                    (address[13:0]),
    //     .data_bus_in                (internal_data_bus),
    //     .data_bus_out               (tvga_data_bus_out),

    //     // I/O
    //     .video_clock                (video_clock),
    //     .video_reset                (video_reset),
    //     .video_h_sync               (video_h_sync),
    //     .video_v_sync               (video_v_sync),
    //     .video_r                    (video_r),
    //     .video_g                    (video_g),
    //     .video_b                    (video_b)
    // );

	 
    // RTC
	 
    logic           mgmt_rtc_cs;
    logic   [7:0]   rtc_readdata;
	 
    assign mgmt_rtc_cs   = (mgmt_address[15:8] == 8'hF4);

    rtc rtc
    (
       .clk               (clock),
       .rst_n             (~reset),

       .clock_rate        (clk_rate),

       .io_address        (address[0]),
       .io_writedata      (internal_data_bus),
       .io_read           (~io_read_n & rtc_chip_select),
       .io_write          (~io_write_n & rtc_chip_select),
       .io_readdata       (rtc_readdata),

       .mgmt_address      (mgmt_address),
       .mgmt_write        (mgmt_write & mgmt_rtc_cs),
       .mgmt_writedata    (mgmt_writedata[7:0]),

       .memcfg            (1'b0),
       .bootcfg           (5'd0)
    );
    

    //
    // Joysticks
    //

    logic [7:0] joy_data;

    tandy_pcjr_joy joysticks
    (
        .clk                       (clock),
        .reset                     (reset),
        .en                        (joystick_select && ~io_write_n),
        .clk_select                (clk_select),
        .joy_opts                  (joy_opts),
        .joy0                      (joy0),
        .joy1                      (joy1),
        .joya0                     (joya0),
        .joya1                     (joya1),
        .d_out                     (joy_data)
    );


    //
    // data_bus_out
    //
    
    always_ff @(posedge clock)
    begin
        if (~interrupt_acknowledge_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= interrupt_data_bus_out;
        end
        else if ((~interrupt_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= interrupt_data_bus_out;
        end
        else if ((~timer_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= timer_data_bus_out;
        end
        else if ((~ppi_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= ppi_data_bus_out;
        end
        else if (`ENABLE_CGA && CGA_CRTC_OE_2)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= CGA_CRTC_DOUT_2;
        end
        else if (`ENABLE_HGC && HGC_CRTC_OE_2)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= HGC_CRTC_DOUT_2;
        end
        else if (ega_mem_select && (~memory_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= ega_vram_cpu_dout;
        end
        else if (ega_switch_sense_oe)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= ega_switch_sense_data;
        end
        else if (ega_io_oe_sys)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= ega_io_dout_sys;
        end
        else if (`ENABLE_OPL2 && (opl_228_chip_select || opl_388_chip_select) && ~io_read_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= jtopl2_dout;
        end
        else if (`ENABLE_SB && sb_read_select && ~io_read_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= sb_readdata;
        end
        else if (cms_rd && ~io_read_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= data_from_cms;
        end
        else if ((uart_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= uart_readdata;
        end
        else if ((uart2_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= uart2_readdata;
        end
        else if ((mpu401_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= mpu401_readdata;
        end
        else if (`ENABLE_EMS && (ems_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= ena_ems[address[1:0]] ? map_ems[address[1:0]] : 8'hFF;
        end
        else if ((lpt_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= address[0] ? 8'hDF : lpt_reg;
        end
        else if ((lpt_ctrl_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= 8'hE0 | lpt_ctrl | lpt_enable_irq;
        end
        else if ((xtctl_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= xtctl;
        end
        else if (xtegactl_oe)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= xtegactl_data;
        end
        else if (xtctl_id_oe)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= xtctl_id_data;
        end
        else if (`ENABLE_TANDY_VIDEO && nmi_mask_register && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= nmi_mask_register_data;
        end
        else if (joystick_select && ~io_read_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= joy_data;
        end
        else if ((~ide0_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= xt2ide0_data_bus_out;
        end
        else if ((~floppy0_chip_select_n || fdd_dma_read) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= fdd_readdata;
        end
        else if (rtc_chip_select && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= rtc_readdata;
        end
        else
        begin
            data_bus_out_from_chipset <= 1'b0;
            data_bus_out <= 8'b00000000;
        end
    end

endmodule
