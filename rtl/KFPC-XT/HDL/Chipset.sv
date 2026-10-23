//
// MiSTer PCXT Chipset
// Ported by @spark2k06
//
// Based on KFPC-XT written by @kitune-san
//
module CHIPSET #(
        parameter clk_rate = 28'd50000000,
        parameter bit ROM_TANDY = 1'b0,       // F000 maps the Tandy BIOS slot
        parameter bit ENABLE_EGA = 1'b0)      // the EGA/VGA card and its memory map are built
        (
        input   logic           clock,
        input   logic           cpu_ce_posedge,
        input   logic           cpu_ce_negedge,
        input   logic           clk_sys,
        input   logic           peripheral_ce,
        input   logic   [1:0]   clk_select,
        input   logic           reset,
        input   logic           sdram_reset,
        // CPU
        input   logic   [19:0]  cpu_address,
        input   logic   [7:0]   cpu_data_bus,
        input   logic   [2:0]   processor_status,
        input   logic           processor_lock_n,
        output  logic           processor_transmit_or_receive_n,
        output  logic           processor_ready,
        output  logic           interrupt_to_cpu,
        // SplashScreen
        input   logic           splashscreen,
        // Video card chosen at reset: 1 = EGA/VGA, 0 = CGA/Hercules
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
        // EGA/VGA card outputs (clk_vga_cga domain)
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
        output  logic           ega_dot_toggle,
        output  logic           ega_dot_clock_sel,
        output  logic           ega_scandouble_active_out,
        output  logic           ega_vmode_toggle_out,
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
        output  logic   [19:0]  address,
        input   logic   [19:0]  address_ext,
        output  logic           address_direction,
        output  logic   [7:0]   data_bus,
        // The private 16-bit SDRAM path, for an 8086 bus cycle. Steps 2 and 5 of
        // docs/8086-adaptation.md. It runs beside the 8-bit bus rather than
        // widening it: everything on the expansion side - video memory, the
        // BIOS ROM, every peripheral - stays eight bits wide, which is what an
        // XT-class expansion bus was and what an 8086 XT-clone's steering
        // logic presented to software anyway.
        //
        // Only SDRAM answers it. word_read_possible (the historical signal
        // name, now used for either direction) says so for the address
        // currently latched, and it is about the memory map alone - the CPU
        // side still has to check that the access is a word at an even
        // address, which is the half of the question it is the one that knows.
        input   logic           word_read_request,
        input   logic           word_write_request,
        input   logic   [15:0]  data_bus_word_in,
        output  logic   [15:0]  data_bus_word,
        output  logic           word_read_possible,
        input   logic   [7:0]   data_bus_ext,
        output  logic           data_bus_direction,
        output  logic           address_latch_enable,
        input   logic           io_channel_check,
        input   logic           io_channel_ready,
        input   logic   [7:0]   interrupt_request,
        output  logic           io_read_n,
        input   logic           io_read_n_ext,
        output  logic           io_read_n_direction,
        output  logic           io_write_n,
        input   logic           io_write_n_ext,
        output  logic           io_write_n_direction,
        output  logic           memory_read_n,
        input   logic           memory_read_n_ext,
        output  logic           memory_read_n_direction,
        output  logic           memory_write_n,
        input   logic           memory_write_n_ext,
        output  logic           memory_write_n_direction,
        input   logic           ext_access_request,
        input   logic   [3:0]   dma_request,
        output  logic   [3:0]   dma_acknowledge_n,
        output  logic           address_enable_n,
        output  logic           terminal_count_n,
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
        // C/MS Audio
        input   logic           cms_en,
        output  logic   [15:0]  o_cms_l,
        output  logic   [15:0]  o_cms_r,
        // TANDY
        input   logic           tandy_video,
        output  logic   [10:0]  tandy_snd_e,
        input   logic           tandy_en,
        output  logic           tandy_16_gfx,
        output  logic           tandy_color_16,
        // IBM PCjr (implies tandy_video)
        input   logic           pcjr,
        output  logic           pcjr_vram_32k,
        input   logic   [3:0]   pcjr_ram_size,   // 0 = 128 KiB ... 8 = 640 KiB
        input   logic   [7:0]   cart1_seg,       // cartridges: where they are mapped and how long they are
        input   logic   [16:0]  cart1_len,
        input   logic   [7:0]   cart2_seg,
        input   logic   [16:0]  cart2_len,
        output  logic           nmi_to_cpu,
        output  logic           cassette_out,
        output  logic           cassette_motor,
        // UART
        input   logic           clk_uart,
        input   logic           clk_uart_com2,
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
        // System memory. Each access is a transaction to the SDRAM arbiter
        // (through sdram_xbridge); the controller is in the platform layer.
        output  logic           mem_start,
        output  logic           mem_we,
        output  logic   [23:0]  mem_addr,
        output  logic   [1:0]   mem_len,
        output  logic   [63:0]  mem_wdata,
        output  logic   [7:0]   mem_wbe,
        input   logic           mem_busy,
        input   logic           mem_done,
        input   logic   [63:0]  mem_rdata,
        input   logic           mem_flush,      // the ROM loader is writing
        input   logic           ec00_loaded,    // an EC00 ROM has been loaded; if not, EC000-EFFFF is open bus
        // Video memory of the EGA card: the frontend's client end of the
        // arbiter's video port and the writes the arbiter captured (sdram clock)
        input   logic           sdram_clk,
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
        // Committed writes, for the video fetch engines (F2)
        output  logic           mem_snoop_valid,
        output  logic   [23:0]  mem_snoop_addr,
        output  logic   [15:0]  mem_snoop_data,
        output  logic   [1:0]   mem_snoop_be,
        // EMS
        input   logic           ems_enabled,
        input   logic   [1:0]   ems_address,
        // UMB (EGA memory map)
        input   logic           umb_enabled,
        // BIOS: [2] C000 (EGA only), [1] F000 (main), [0] EC00
        input  logic    [2:0]   bios_protect_flag,
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
        // XTCTL DATA: legacy 8888h register (CGA family only)
        output  logic   [7:0]   xtctl,
        // XTEGACTL register file
        output  logic   [7:0]   xtegactl_cpu,
        output  logic   [7:0]   xtegactl_exp,
        output  logic   [7:0]   xtegactl_vid,
        output  logic   [7:0]   xtegactl_inp,
        output  logic   [7:0]   xtegactl_midi,
        output  logic   [7:0]   xtegactl_exp2,
        output  logic   [7:0]   xtegactl_crt,
        output  logic   [7:0]   xtegactl_sync,
        // Read-only effective XTEGACTL status, supplied by the top level
        // where the OSD values are available.
        input   logic   [39:0]  xtegactl_status_effective,
        input   logic   [17:0]  xtegactl_status_osd_match,
        // Identification block (8990h..8997h)
        input   logic   [1:0]   id_video_card,
        input   logic           id_vga13_active,
        // Optional flags
        input   logic           enable_a000h,
        // RAM wait mode
        input   logic           wait_count_clk_en,
        input   logic   [1:0]   ram_read_wait_cycle,
        input   logic   [1:0]   ram_write_wait_cycle,
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
        // Video memory fetch (F2): what the adapters need to ask for the
        // next character and the bytes they get back, see Peripherals.sv
        input   logic   [7:0]   fx_cga_vram_d,
        output  logic   [4:0]   fx_cga_phase,
        output  logic           fx_cga_hres,
        output  logic   [13:0]  fx_cga_cur_word,
        output  logic   [13:0]  fx_cga_next_word,
        output  logic           tandy_vram_en,
        output  logic   [2:0]   tandy_vram_block,
        output  logic   [5:0]   tandy_vram_page,
        input   logic   [7:0]   fx_hgc_vram_d,
        output  logic   [4:0]   fx_hgc_phase,
        output  logic           fx_hgc_grph,
        output  logic           fx_hgc_page,
        output  logic   [13:0]  fx_hgc_cur_word,
        output  logic   [13:0]  fx_hgc_next_word
    );

	 logic   [19:0]  latch_address;
	 
    logic           dma_ready;
    logic           dma_wait_n;
    logic           interrupt_acknowledge_n;
    logic           dma_chip_select_n;
    logic           dma_page_chip_select_n;
    logic           memory_access_ready;
    logic           cga_memory_ready;
    logic           cga_memory_write_wait;
    logic           map_select;
    logic   [24:0]  map_phys;
    logic           map_protect;
    logic   [1:0]   map_vclass;
    logic   [24:0]  map_phys2;
    logic           map_phys2_valid;
    logic           hgc_page_sys;
    logic   [7:0]   internal_data_bus;
    logic   [7:0]   internal_data_bus_ext;
    logic   [7:0]   internal_data_bus_chipset;
    logic   [7:0]   internal_data_bus_ram;
    logic   [15:0]  internal_data_bus_ram_word;
    logic           pcjr_cold_override;
    logic           data_bus_out_from_chipset;
    logic           internal_data_bus_direction;
    logic           no_command_state;

    logic           prev_timer_count_1;
    logic           DRQ0;

    logic   [6:0]   map_ems[0:3];
    logic           ena_ems[0:3];
    logic           ems_b1;
    logic           ems_b2;
    logic           ems_b3;
    logic           ems_b4;
    logic           tandy_snd_rdy;
    logic           fdd_dma_req;
    logic           sb_dma_req;

    // CPU memory port <-> EGA frontend (sdram_txn_mux) and the EGA map
    logic           video_memory_access_ready;
    logic           video_io_access_ready;
    logic           vga13_packed_cpu;
    logic           vram_m_start;
    logic           vram_m_we;
    logic   [23:0]  vram_m_addr;
    logic   [1:0]   vram_m_len;
    logic   [63:0]  vram_m_wdata;
    logic   [7:0]   vram_m_wbe;
    logic           vram_m_done;
    logic           cpu_m_start;
    logic           cpu_m_we;
    logic   [23:0]  cpu_m_addr;
    logic   [1:0]   cpu_m_len;
    logic   [63:0]  cpu_m_wdata;
    logic   [7:0]   cpu_m_wbe;
    logic           cpu_m_done;
    logic           map_select_cga;
    logic   [24:0]  map_phys_cga;
    logic           map_protect_cga;
    logic   [1:0]   map_vclass_cga;
    logic   [24:0]  map_phys2_cga;
    logic           map_phys2_valid_cga;
    logic           map_select_ega;
    logic   [24:0]  map_phys_ega;
    logic           map_protect_ega;

    // IBM-compatible BIOSes announce a warm reboot by writing 1234h to the
    // BIOS Data Area at 0040:0072.  Detect that bus transaction here, where
    // both the ordinary 8088 byte bus and the 8086 private word path are
    // visible, before handing the event to the peripheral register file.
    logic           warm_boot_marker_event;

    //
    // I/O settle guard (EGA card only)
    //
    // The EGA vehicle added a small, CPU-speed dependent floor of extra wait
    // at the start of every I/O cycle: the I/O device response pipelines are a
    // fixed number of chipset clocks long, sized against the roomy cycle at the
    // slower CPU speeds, while at the fastest setting that cycle shrinks to a
    // couple of clocks -- the same role the 5160's one I/O wait state plays on
    // real hardware. The CGA family never had it, and adding it there would
    // change every I/O cycle of a validated core, so it applies to the EGA
    // card only.
    logic   [2:0]   io_settle_count;
    logic           prev_io_active;
    wire            io_active = ~io_read_n | ~io_write_n;

    function automatic logic [2:0] io_settle_ticks(input logic [1:0] sel);
        case (sel)
            2'b11:   io_settle_ticks = 3'd4;
            default: io_settle_ticks = 3'd0;
        endcase
    endfunction

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            prev_io_active  <= 1'b0;
            io_settle_count <= 3'd0;
        end
        else begin
            prev_io_active <= io_active;
            if (io_active && ~prev_io_active)
                io_settle_count <= io_settle_ticks(clk_select);
            else if (io_settle_count != 3'd0)
                io_settle_count <= io_settle_count - 3'd1;
        end
    end

    wire    io_settle_ready = ~ega_active | (io_settle_count == 3'd0);

    //
    // Longest CPU stall, for the debug register at XTCTL 8997h. Counts chipset
    // clocks the CPU spends held by the READY logic outside a DMA cycle, and
    // keeps the largest run seen since reset, saturating at 255.
    //
    logic   [7:0]   cpu_stall_run;
    logic   [7:0]   id_cpu_latency_max;
    wire            cpu_stalled = ~processor_ready & dma_acknowledge_n[0] & ~reset;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            cpu_stall_run      <= 8'd0;
            id_cpu_latency_max <= 8'd0;
        end
        else if (cpu_stalled) begin
            if (cpu_stall_run != 8'hFF)
                cpu_stall_run <= cpu_stall_run + 8'd1;
            if (cpu_stall_run >= id_cpu_latency_max && id_cpu_latency_max != 8'hFF)
                id_cpu_latency_max <= cpu_stall_run + 8'd1;
        end
        else
            cpu_stall_run <= 8'd0;
    end


    always_ff @(posedge clock)
    begin
        if (reset)
            prev_timer_count_1 <= 1'b1;
        else
            prev_timer_count_1 <= timer_counter_out[1];
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            DRQ0 <= 1'b0;
        else if (~dma_acknowledge_n[0])
            DRQ0 <= 1'b0;
        else if (~prev_timer_count_1 & timer_counter_out[1])
            DRQ0 <= 1'b1;
        else
            DRQ0 <= DRQ0;
    end

    READY u_READY 
    (
        .clock                              (clock),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .reset                              (reset),
        .processor_ready                    (processor_ready),
        .dma_ready                          (dma_ready),
        .dma_wait_n                         (dma_wait_n),
        .io_channel_ready                   (io_channel_ready & memory_access_ready & video_memory_access_ready & io_settle_ready & video_io_access_ready & tandy_snd_rdy & cga_memory_ready),
        .io_read_n                          (io_read_n),
        .io_write_n                         (io_write_n),
        .memory_read_n                      (memory_read_n),
        .memory_write_n                     (memory_write_n),
        .cga_memory_write_wait              (cga_memory_write_wait),
        .dma0_acknowledge_n                 (dma_acknowledge_n[0]),
        .address_enable_n                   (address_enable_n),
        .clk_select                         (clk_select)
    );

    BUS_ARBITER u_BUS_ARBITER 
    (
        .clock                              (clock),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .reset                              (reset),
        .cpu_address                        (cpu_address),
        .cpu_data_bus                       (cpu_data_bus),
        .processor_status                   (processor_status),
        .processor_lock_n                   (processor_lock_n),
        .processor_transmit_or_receive_n    (processor_transmit_or_receive_n),
        .dma_ready                          (dma_ready),
        .dma_wait_n                         (dma_wait_n),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .dma_chip_select_n                  (dma_chip_select_n),
        .dma_page_chip_select_n             (dma_page_chip_select_n),
        .address                            (address),
        .address_ext                        (address_ext),
        .address_direction                  (address_direction),
        .data_bus_ext                       (internal_data_bus_ext),
        .internal_data_bus                  (internal_data_bus),
        .data_bus_direction                 (internal_data_bus_direction),
        .address_latch_enable               (address_latch_enable),
        .io_read_n                          (io_read_n),
        .io_read_n_ext                      (io_read_n_ext),
        .io_read_n_direction                (io_read_n_direction),
        .io_write_n                         (io_write_n),
        .io_write_n_ext                     (io_write_n_ext),
        .io_write_n_direction               (io_write_n_direction),
        .memory_read_n                      (memory_read_n),
        .memory_read_n_ext                  (memory_read_n_ext),
        .memory_read_n_direction            (memory_read_n_direction),
        .memory_write_n                     (memory_write_n),
        .memory_write_n_ext                 (memory_write_n_ext),
        .memory_write_n_direction           (memory_write_n_direction),
        .no_command_state                   (no_command_state),
        .ext_access_request                 (ext_access_request),
        .dma_request                        ({dma_request[3], fdd_dma_req, dma_request[1] | sb_dma_req, DRQ0}),
        .dma_acknowledge_n                  (dma_acknowledge_n),
        .address_enable_n                   (address_enable_n),
        .terminal_count_n                   (terminal_count_n)
    );

    warm_boot_marker_detector u_warm_boot_marker_detector (
        .clock              (clock),
        .reset              (reset),
        .address            (address),
        .address_enable_n   (address_enable_n),
        .memory_write_n     (memory_write_n),
        .byte_data          (internal_data_bus),
        .word_write_request (word_write_request),
        .word_data          (data_bus_word_in),
        .warm_boot_event    (warm_boot_marker_event)
    );

    PERIPHERALS #(.clk_rate(clk_rate)) u_PERIPHERALS
    (
        .clock                              (clock),
        .clk_sys                            (clk_sys),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .cpu_ce_negedge                     (cpu_ce_negedge),
        .clk_uart                           (clk_uart),
        .clk_uart_com2                      (clk_uart_com2),
        .peripheral_ce                      (peripheral_ce),
        .clk_select                         (clk_select),
        .reset                              (reset),
        .interrupt_to_cpu                   (interrupt_to_cpu),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .dma_chip_select_n                  (dma_chip_select_n),
        .dma_page_chip_select_n             (dma_page_chip_select_n),
        .splashscreen                       (splashscreen),
        .ega_active                         (ega_active),
        .std_hsyncwidth                     (std_hsyncwidth),
        .composite                          (composite),
        .video_reset                        (video_reset),
        .video_output                       (video_output),
        .clk_vga_cga                        (clk_vga_cga),
        .enable_cga                         (enable_cga),
        .clk_vga_hgc                        (clk_vga_hgc),
        .enable_hgc                         (enable_hgc),
        .de_o                               (de_o),
        .hgc_rgb                            (hgc_rgb),
        .VGA_R                              (VGA_R),
        .VGA_G                              (VGA_G),
        .VGA_B                              (VGA_B),
        .VGA_HSYNC                          (VGA_HSYNC),
        .VGA_VSYNC                          (VGA_VSYNC),
        .VGA_HBlank                         (VGA_HBlank),
        .VGA_VBlank                         (VGA_VBlank),
        .VGA_VBlank_border                  (VGA_VBlank_border),
        .VGA_HSYNC_REF                      (VGA_HSYNC_REF),
        .VGA_VSYNC_REF                      (VGA_VSYNC_REF),
        .cga_memory_ready                   (cga_memory_ready),
        .cga_memory_write_wait              (cga_memory_write_wait),
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
        .ega_scandouble_active_out          (ega_scandouble_active_out),
        .ega_vmode_toggle_out               (ega_vmode_toggle_out),
        .ega_mode350                        (ega_mode350),
        .ega_active_dots                    (ega_active_dots),
        .ega_active_lines                   (ega_active_lines),
        .vga_mode13_osd                     (vga_mode13_osd),
        .vga_mode13_native                  (vga_mode13_native),
        .ega_monitor_profile                (ega_monitor_profile),
        .vga_mode13_active_out              (vga_mode13_active_out),
        .vga_mode13_wide_clock_out          (vga_mode13_wide_clock_out),
        .vga_mode13_pixel_toggle_out        (vga_mode13_pixel_toggle_out),
        .warm_boot_marker_event             (warm_boot_marker_event),
        .video_memory_access_ready          (video_memory_access_ready),
        .video_io_access_ready              (video_io_access_ready),
        .vram_m_start                       (vram_m_start),
        .vram_m_we                          (vram_m_we),
        .vram_m_addr                        (vram_m_addr),
        .vram_m_len                         (vram_m_len),
        .vram_m_wdata                       (vram_m_wdata),
        .vram_m_wbe                         (vram_m_wbe),
        .vram_m_busy                        (mem_busy),
        .vram_m_done                        (vram_m_done),
        .vram_m_rdata                       (mem_rdata),
        .sdram_clk                          (sdram_clk),
        .sdram_reset                        (sdram_reset),
        .vid_req                            (vid_req),
        .vid_addr                           (vid_addr),
        .vid_len                            (vid_len),
        .vid_deadline                       (vid_deadline),
        .vid_ack                            (vid_ack),
        .vid_rvalid                         (vid_rvalid),
        .vid_rlast                          (vid_rlast),
        .vid_rdata                          (vid_rdata),
        .snoop_valid                        (snoop_valid),
        .snoop_addr                         (snoop_addr),
        .snoop_len                          (snoop_len),
        .snoop_wdata                        (snoop_wdata),
        .snoop_wbe                          (snoop_wbe),
        .vga13_packed_cpu                   (vga13_packed_cpu),
        .address                            (address),
	    .latch_address                      (latch_address),
        .internal_data_bus                  (internal_data_bus),
        .data_bus_out                       (internal_data_bus_chipset),
        .data_bus_out_from_chipset          (data_bus_out_from_chipset),
        .interrupt_request                  (interrupt_request),
        .io_read_n                          (io_read_n),
        .io_write_n                         (io_write_n),
        .memory_read_n                      (memory_read_n),
        .memory_write_n                     (memory_write_n),
        .address_enable_n                   (address_enable_n),
        .timer_counter_out                  (timer_counter_out),
        .speaker_out                        (speaker_out),
        .port_a_out                         (port_a_out),
        .port_a_io                          (port_a_io),
        .port_b_in                          (port_b_in),
        .port_b_out                         (port_b_out),
        .port_b_io                          (port_b_io),
        .port_c_in                          (port_c_in),
        .port_c_out                         (port_c_out),
        .port_c_io                          (port_c_io),
        .ps2_clock                          (ps2_clock),
        .ps2_data                           (ps2_data),
        .ps2_mouseclk_in                    (ps2_mouseclk_in),
        .ps2_mousedat_in                    (ps2_mousedat_in),
        .ps2_mouseclk_out                   (ps2_mouseclk_out),
        .ps2_mousedat_out                   (ps2_mousedat_out),
        .joy_opts                           (joy_opts),
        .joy0                               (joy0),
        .joy1                               (joy1),
        .joya0                              (joya0),
        .joya1                              (joya1),
        .ps2_clock_out                      (ps2_clock_out),
        .ps2_data_out                       (ps2_data_out),
        .jtopl2_snd_e                       (jtopl2_snd_e),
        .opl2_io                            (opl2_io),
        .sb_en                              (sb_en),
        .sb_irq7                            (sb_irq7),
        .sb_snd_l                           (sb_snd_l),
        .sb_snd_r                           (sb_snd_r),
        .sb_dma_req                         (sb_dma_req),
        .sb_dma_ack                         (~dma_acknowledge_n[1]),
        .tandy_en                           (tandy_en),
        .cms_en                             (cms_en),
        .o_cms_l                            (o_cms_l),
        .o_cms_r                            (o_cms_r),
        .tandy_video                        (tandy_video),
        .tandy_snd_e                        (tandy_snd_e),
        .tandy_snd_rdy                      (tandy_snd_rdy),
        .tandy_16_gfx                       (tandy_16_gfx),
		.tandy_color_16                     (tandy_color_16),
        .pcjr                               (pcjr),
        .pcjr_vram_32k                      (pcjr_vram_32k),
        .nmi_to_cpu                         (nmi_to_cpu),
        .cassette_out                       (cassette_out),
        .cassette_motor                     (cassette_motor),
        .uart2_rx                           (uart2_rx),
        .uart2_tx                           (uart2_tx),
        .uart2_cts_n                        (uart2_cts_n),
        .uart2_dcd_n                        (uart2_dcd_n),
        .uart2_dsr_n                        (uart2_dsr_n),
        .uart2_rts_n                        (uart2_rts_n),
        .uart2_dtr_n                        (uart2_dtr_n),
        .clk_midi                          (clk_midi),
        .midi_rx                           (midi_rx),
        .midi_tx                           (midi_tx),
        .mpu401_enabled                    (mpu401_enabled),
        .ems_enabled                       (ems_enabled),
        .ems_address                       (ems_address),
        .map_ems                           (map_ems),
        .ena_ems                           (ena_ems),
        .ems_b1                            (ems_b1),
        .ems_b2                            (ems_b2),
        .ems_b3                            (ems_b3),
        .ems_b4                            (ems_b4),
        .use_mmc                            (use_mmc),
        .spi_clk                            (spi_clk),
        .spi_cs                             (spi_cs),
        .spi_mosi                           (spi_mosi),
        .spi_miso                           (spi_miso),
        .mgmt_address                       (mgmt_address),
        .mgmt_read                          (mgmt_read),
        .mgmt_readdata                      (mgmt_readdata),
        .mgmt_write                         (mgmt_write),
        .mgmt_writedata                     (mgmt_writedata),
        .floppy_wp                          (floppy_wp),
        .fdd_present                        (fdd_present),
        .fdd_request                        (fdd_request),
        .ide0_request                       (ide0_request),
        .fdd_dma_req                        (fdd_dma_req),
        .fdd_dma_ack                        (~dma_acknowledge_n[2]),
        .terminal_count                     (terminal_count_n),
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
        .id_cpu_latency_max                 (id_cpu_latency_max),
        .pause_core                         (pause_core),
        .cga_hw                             (cga_hw),
        .cga_scandouble_en                  (cga_scandouble_en),
        .hercules_hw                        (hercules_hw),
        .swap_video                         (swap_video),
        .crt_h_offset                       (crt_h_offset),
        .crt_v_offset                       (crt_v_offset),
        .vsync_width_osd                    (vsync_width_osd),
        .hsync_width_osd                    (hsync_width_osd),
        .cga_frame_stack_rebuild            (cga_frame_stack_rebuild),
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
        .fx_hgc_next_word                   (fx_hgc_next_word),
        .hgc_page_sys                       (hgc_page_sys)
    );

    //
    // System memory
    //
    mem_map #(.ROM_TANDY(ROM_TANDY)) u_mem_map
    (
        .address                            (latch_address),
        .map_ems                            (map_ems),
        .ems_b1                             (ems_b1),
        .ems_b2                             (ems_b2),
        .ems_b3                             (ems_b3),
        .ems_b4                             (ems_b4),
        .enable_a000h                       (enable_a000h),
        .bios_protect_flag                  (bios_protect_flag[1:0]),
        .ec00_loaded                        (ec00_loaded),
        .en_cga                             (enable_cga),
        .en_hgc                             (enable_hgc),
        .hgc_page                           (hgc_page_sys),
        .tandy_video                        (tandy_vram_en),
        .tandy_block                        (tandy_vram_block),
        .tandy_cpu_page                     (tandy_vram_page[5:3]),
        .pcjr                               (pcjr),
        .pcjr_32k                           (pcjr_vram_32k),
        .pcjr_ram_size                      (pcjr_ram_size),
        .cart1_seg                          (cart1_seg),
        .cart1_len                          (cart1_len),
        .cart2_seg                          (cart2_seg),
        .cart2_len                          (cart2_len),
        .select                             (map_select_cga),
        .phys                               (map_phys_cga),
        .protect                            (map_protect_cga),
        .vclass                             (map_vclass_cga),
        .phys2                              (map_phys2_cga),
        .phys2_valid                        (map_phys2_valid_cga)
    );

    // The EGA map replaces the CGA one when that card is chosen. It has no
    // CGA/HGC video memory: the EGA aperture has its own frontend, and the
    // 13h image is ordinary memory to the CPU port.
    generate
    if (ENABLE_EGA) begin : EGA_MAP
        mem_map_ega u_mem_map_ega
        (
            .address                        (latch_address),
            .map_ems                        (map_ems),
            .ems_b1                         (ems_b1),
            .ems_b2                         (ems_b2),
            .ems_b3                         (ems_b3),
            .ems_b4                         (ems_b4),
            .umb_enabled                    (umb_enabled),
            .vga13_packed                   (vga13_packed_cpu),
            .bios_protect_flag              (bios_protect_flag),
            .ec00_loaded                    (ec00_loaded),
            .select                         (map_select_ega),
            .phys                           (map_phys_ega),
            .protect                        (map_protect_ega)
        );
    end
    else begin : NO_EGA_MAP
        assign map_select_ega  = 1'b0;
        assign map_phys_ega    = 25'd0;
        assign map_protect_ega = 1'b0;
    end
    endgenerate

    wire            use_ega_map = ENABLE_EGA & ega_active;
    assign  map_select       = use_ega_map ? map_select_ega  : map_select_cga;
    assign  map_phys         = use_ega_map ? map_phys_ega    : map_phys_cga;
    assign  map_protect      = use_ega_map ? map_protect_ega : map_protect_cga;
    assign  map_vclass       = use_ega_map ? 2'd0            : map_vclass_cga;
    assign  map_phys2        = use_ega_map ? 25'd0           : map_phys2_cga;
    assign  map_phys2_valid  = use_ega_map ? 1'b0            : map_phys2_valid_cga;

    // A CPU memory read or code fetch can start in SDRAM before MEMR: the
    // clock after ALE rises, cpu_address (latched at the top level) already
    // holds the T1 address. See cpu_mem_port.
    logic   ale_q;
    logic   ale_qq;
    always_ff @(posedge clock) begin
        ale_q  <= address_latch_enable;
        ale_qq <= ale_q;
    end
    wire    early_read = ale_q & ~ale_qq
                       & ((processor_status == 3'b100) | (processor_status == 3'b101));

    // PCjr: the BIOS finds no warm-start flag after a reset of the machine
    pcjr_cold_boot u_pcjr_cold_boot
    (
        .clock                              (clock),
        .reset                              (reset),
        .pcjr                               (pcjr),
        .address                            (latch_address),
        .select                             (map_select),
        .memory_write_n                     (memory_write_n),
        .override                           (pcjr_cold_override)
    );

    cpu_mem_port u_cpu_mem_port
    (
        .clock                              (clock),
        .reset                              (sdram_reset),
        .internal_data_bus                  (internal_data_bus),
        .data_bus_out                       (internal_data_bus_ram),
        .word_read_request                  (word_read_request),
        .word_write_request                 (word_write_request),
        .data_bus_in_word                   (data_bus_word_in),
        .data_bus_out_word                  (internal_data_bus_ram_word),
        .memory_read_n                      (memory_read_n),
        .memory_write_n                     (memory_write_n),
        .memory_access_ready                (memory_access_ready),
        .map_select                         (map_select),
        .map_phys                           (map_phys),
        .map_protect                        (map_protect),
        .map_vclass                         (map_vclass),
        .map_phys2                          (map_phys2),
        .map_phys2_valid                    (map_phys2_valid),
        .cpu_ce_posedge                     (cpu_ce_posedge),
        .wait_count_clk_en                  (wait_count_clk_en),
        .ram_read_wait_cycle                (ram_read_wait_cycle),
        .ram_write_wait_cycle               (ram_write_wait_cycle),
        .clk_select                         (clk_select),
        .flush                              (mem_flush),
        .early_read                         (early_read),
        .m_start                            (cpu_m_start),
        .m_we                               (cpu_m_we),
        .m_addr                             (cpu_m_addr),
        .m_len                              (cpu_m_len),
        .m_wdata                            (cpu_m_wdata),
        .m_wbe                              (cpu_m_wbe),
        .m_busy                             (mem_busy),
        .m_done                             (cpu_m_done),
        .m_rdata                            (mem_rdata),
        .snoop_valid                        (mem_snoop_valid),
        .snoop_addr                         (mem_snoop_addr),
        .snoop_data                         (mem_snoop_data),
        .snoop_be                           (mem_snoop_be)
    );

    // The EGA frontend is the other master of the CPU port: its window
    // (A0000-BFFFF) is not memory to cpu_mem_port. Without the EGA card the
    // port goes straight through.
    generate
    if (ENABLE_EGA) begin : TXN_MUX
        sdram_txn_mux u_txn_mux
        (
            .clock                          (clock),
            .reset                          (sdram_reset),
            .a0_start                       (cpu_m_start),
            .a0_we                          (cpu_m_we),
            .a0_addr                        (cpu_m_addr),
            .a0_len                         (cpu_m_len),
            .a0_wdata                       (cpu_m_wdata),
            .a0_wbe                         (cpu_m_wbe),
            .a0_done                        (cpu_m_done),
            .a1_start                       (vram_m_start),
            .a1_we                          (vram_m_we),
            .a1_addr                        (vram_m_addr),
            .a1_len                         (vram_m_len),
            .a1_wdata                       (vram_m_wdata),
            .a1_wbe                         (vram_m_wbe),
            .a1_done                        (vram_m_done),
            .m_start                        (mem_start),
            .m_we                           (mem_we),
            .m_addr                         (mem_addr),
            .m_len                          (mem_len),
            .m_wdata                        (mem_wdata),
            .m_wbe                          (mem_wbe),
            .m_busy                         (mem_busy),
            .m_done                         (mem_done)
        );
    end
    else begin : NO_TXN_MUX
        assign mem_start    = cpu_m_start;
        assign mem_we       = cpu_m_we;
        assign mem_addr     = cpu_m_addr;
        assign mem_len      = cpu_m_len;
        assign mem_wdata    = cpu_m_wdata;
        assign mem_wbe      = cpu_m_wbe;
        assign cpu_m_done   = mem_done;
        assign vram_m_done  = 1'b0;
    end
    endgenerate

    assign  data_bus = internal_data_bus;

    // The word never joins the byte multiplexer below. It has one source and
    // one destination, it is only meaningful for the cycle the CPU asked a
    // word for, and putting it through the same arbitration would mean giving
    // every other device a 16-bit port it has nothing to put on.
    assign  data_bus_word = pcjr_cold_override ? 16'h0000 : internal_data_bus_ram_word;

    // map_select is combinational on the latched address, so this settles as
    // soon as the address does and is available to the CPU well before it has
    // to commit to a wide cycle. It covers the decode holes - video memory,
    // the UMB window when it is off - because those are the places a wide
    // read would come back with whatever the memory port happened to hold.
    // Video memory is eight bits wide, as on the card, so it is excluded.
    assign  word_read_possible = map_select & (map_vclass == 2'd0);

    always_comb
    begin
        if (data_bus_out_from_chipset)
        begin
            internal_data_bus_ext = internal_data_bus_chipset;
            data_bus_direction    = 1'b0;
        end
        else if ((map_select) && (~memory_read_n))
        begin
            internal_data_bus_ext = pcjr_cold_override ? 8'h00 : internal_data_bus_ram;
            data_bus_direction    = 1'b0;
        end
        else
        begin
            if (internal_data_bus_direction == 1'b1)
            begin
                internal_data_bus_ext = data_bus_ext;
                data_bus_direction    = 1'b1;
            end
            else
            begin
                internal_data_bus_ext = 0;
                data_bus_direction    = 1'b0;
            end
        end
    end

endmodule
