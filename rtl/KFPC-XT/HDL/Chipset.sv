//
// KFPC-XT Chipset
// Written by kitune-san
//
module CHIPSET (
        input   logic           clock,
        input   logic           cpu_clock,
        input   logic           clk_sys,
        input   logic           peripheral_clock,
        input   logic   [1:0]   turbo_mode,
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
        // VGA
        input   logic           composite,
        input   logic           video_output,
        input   logic           clk_vga_cga,
        input   logic           enable_cga,
        input   logic           clk_vga_mda,
        input   logic           enable_mda,
        input   logic   [1:0]   mda_rgb,
        output  logic           de_o,
        output  logic   [5:0]   VGA_R,
        output  logic   [5:0]   VGA_G,
        output  logic   [5:0]   VGA_B,
        output  logic           VGA_HSYNC,
        output  logic           VGA_VSYNC,
        output  logic           VGA_HBlank,
        output  logic           VGA_VBlank,
        // I/O Ports
        output  logic   [19:0]  address,
        input   logic   [19:0]  address_ext,
        output  logic           address_direction,
        output  logic   [7:0]   data_bus,
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
        input   logic   [31:0]  joy0,
        input   logic   [31:0]  joy1,
        input   logic   [15:0]  joya0,
        input   logic   [15:0]  joya1,
        // JTOPL
        input   logic           clk_en_opl2,
        output  logic   [15:0]  jtopl2_snd_e,
        input   logic           adlibhide,
        // TANDY
        input   logic           tandy_video,
        input   logic           tandy_bios_flag,
        output  logic   [10:0]  tandy_snd_e,
        output  logic           tandy_16_gfx,
        // UART
        input   logic           clk_uart,
        input   logic           uart2_rx,
        output  logic           uart2_tx,
        input   logic           uart2_cts_n,
        input   logic           uart2_dcd_n,
        input   logic           uart2_dsr_n,
        output  logic           uart2_rts_n,
        output  logic           uart2_dtr_n,
        // SDRAM
        input   logic           enable_sdram,
        output  logic           initilized_sdram,
        input   logic           sdram_clock,    // 50MHz
        output  logic   [12:0]  sdram_address,
        output  logic           sdram_cke,
        output  logic           sdram_cs,
        output  logic           sdram_ras,
        output  logic           sdram_cas,
        output  logic           sdram_we,
        output  logic   [1:0]   sdram_ba,
        input   logic   [15:0]  sdram_dq_in,
        output  logic   [15:0]  sdram_dq_out,
        output  logic           sdram_dq_io,
        output  logic           sdram_ldqm,
        output  logic           sdram_udqm,
        // EMS
        input   logic           ems_enabled,
        input   logic   [1:0]   ems_address,
        // BIOS
        input  logic    [1:0]   bios_protect_flag,
        // FDD
        input   logic   [15:0]  mgmt_address,
        input   logic           mgmt_read,
        output  logic   [15:0]  mgmt_readdata,
        input   logic           mgmt_write,
        input   logic   [15:0]  mgmt_writedata,
        input   logic   [27:0]  clock_rate,
        input   logic   [1:0]   floppy_wp,
        output  logic   [1:0]   fdd_request,
        output  logic   [2:0]   ide0_request,
        // XTCTL DATA
        output  logic   [7:0]   xtctl,
        // Optional flags
        input   logic           enable_a000h,
        // RAM wait mode
        input   logic           wait_count_clk_en,
        input   logic   [1:0]   ram_read_wait_cycle,
        input   logic   [1:0]   ram_write_wait_cycle
    );

	 logic   [19:0]  latch_address;
	 
    logic           dma_ready;
    logic           dma_wait_n;
    logic           interrupt_acknowledge_n;
    logic           dma_chip_select_n;
    logic           dma_page_chip_select_n;
    logic           memory_access_ready;
    logic           ram_address_select_n;
    logic   [7:0]   internal_data_bus;
    logic   [7:0]   internal_data_bus_ext;
    logic   [7:0]   internal_data_bus_chipset;
    logic   [7:0]   internal_data_bus_ram;
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
        .cpu_clock                          (cpu_clock),
        .reset                              (reset),
        .processor_ready                    (processor_ready),
        .dma_ready                          (dma_ready),
        .dma_wait_n                         (dma_wait_n),
        .io_channel_ready                   (io_channel_ready & memory_access_ready & tandy_snd_rdy),
        .io_read_n                          (io_read_n),
        .io_write_n                         (io_write_n),
        .memory_read_n                      (memory_read_n),
        .dma0_acknowledge_n                 (dma_acknowledge_n[0]),
        .address_enable_n                   (address_enable_n)
    );

    BUS_ARBITER u_BUS_ARBITER 
    (
        .clock                              (clock),
        .cpu_clock                          (cpu_clock),
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
        .dma_request                        ({dma_request[3], fdd_dma_req, dma_request[1], DRQ0}),
        .dma_acknowledge_n                  (dma_acknowledge_n),
        .address_enable_n                   (address_enable_n),
        .terminal_count_n                   (terminal_count_n)
    );

    PERIPHERALS u_PERIPHERALS 
    (
        .clock                              (clock),
        .clk_sys                            (clk_sys),
        .cpu_clock                          (cpu_clock),
        .clk_uart                           (clk_uart),
        .peripheral_clock                   (peripheral_clock),
        .turbo_mode                         (turbo_mode),
        .reset                              (reset),
        .interrupt_to_cpu                   (interrupt_to_cpu),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .dma_chip_select_n                  (dma_chip_select_n),
        .dma_page_chip_select_n             (dma_page_chip_select_n),
        .splashscreen                       (splashscreen),
        .composite                          (composite),
        .video_output                       (video_output),
        .clk_vga_cga                        (clk_vga_cga),
        .enable_cga                         (enable_cga),
        .clk_vga_mda                        (clk_vga_mda),
        .enable_mda                         (enable_mda),
        .de_o                               (de_o),
        .mda_rgb                            (mda_rgb),
        .VGA_R                              (VGA_R),
        .VGA_G                              (VGA_G),
        .VGA_B                              (VGA_B),
        .VGA_HSYNC                          (VGA_HSYNC),
        .VGA_VSYNC                          (VGA_VSYNC),
        .VGA_HBlank                         (VGA_HBlank),
        .VGA_VBlank                         (VGA_VBlank),
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
        .clk_en_opl2                        (clk_en_opl2),
        .jtopl2_snd_e                       (jtopl2_snd_e),
        .adlibhide                          (adlibhide),
        .tandy_video                        (tandy_video),
        .tandy_snd_e                        (tandy_snd_e),
        .tandy_snd_rdy                      (tandy_snd_rdy),
        .tandy_16_gfx                       (tandy_16_gfx),
        .uart2_rx                           (uart2_rx),
        .uart2_tx                           (uart2_tx),
        .uart2_cts_n                        (uart2_cts_n),
        .uart2_dcd_n                        (uart2_dcd_n),
        .uart2_dsr_n                        (uart2_dsr_n),
        .uart2_rts_n                        (uart2_rts_n),
        .uart2_dtr_n                        (uart2_dtr_n),
        .ems_enabled                       (ems_enabled),
        .ems_address                       (ems_address),
        .map_ems                           (map_ems),
        .ena_ems                           (ena_ems),
        .ems_b1                            (ems_b1),
        .ems_b2                            (ems_b2),
        .ems_b3                            (ems_b3),
        .ems_b4                            (ems_b4),
        .mgmt_address                       (mgmt_address),
        .mgmt_read                          (mgmt_read),
        .mgmt_readdata                      (mgmt_readdata),
        .mgmt_write                         (mgmt_write),
        .mgmt_writedata                     (mgmt_writedata),
        .clock_rate                         (clock_rate),
        .floppy_wp                          (floppy_wp),
        .fdd_request                        (fdd_request),
        .ide0_request                       (ide0_request),
        .fdd_dma_req                        (fdd_dma_req),
        .fdd_dma_ack                        (~dma_acknowledge_n[2]),
        .terminal_count                     (terminal_count_n),
        .xtctl                              (xtctl)
    );

    RAM u_RAM 
    (
        .clock                              (sdram_clock),
        .reset                              (sdram_reset),
        .enable_sdram                       (enable_sdram),
        .initilized_sdram                   (initilized_sdram),
        .address                            (latch_address),
        .internal_data_bus                  (internal_data_bus),
        .data_bus_out                       (internal_data_bus_ram),
        .memory_read_n                      (memory_read_n),
        .memory_write_n                     (memory_write_n),
        .no_command_state                   (no_command_state),
        .memory_access_ready                (memory_access_ready),
        .ram_address_select_n               (ram_address_select_n),
        .sdram_address                      (sdram_address),
        .sdram_cke                          (sdram_cke),
        .sdram_cs                           (sdram_cs),
        .sdram_ras                          (sdram_ras),
        .sdram_cas                          (sdram_cas),
        .sdram_we                           (sdram_we),
        .sdram_ba                           (sdram_ba),
        .sdram_dq_in                        (sdram_dq_in),
        .sdram_dq_out                       (sdram_dq_out),
        .sdram_dq_io                        (sdram_dq_io),
        .sdram_ldqm                         (sdram_ldqm),
        .sdram_udqm                         (sdram_udqm),
        .map_ems                            (map_ems),
        .ems_b1                             (ems_b1),
        .ems_b2                             (ems_b2),
        .ems_b3                             (ems_b3),
        .ems_b4                             (ems_b4),
        .tandy_bios_flag                    (tandy_bios_flag),
        .bios_protect_flag                  (bios_protect_flag),
        .enable_a000h                       (enable_a000h),
        .wait_count_clk_en                  (wait_count_clk_en),
        .ram_read_wait_cycle                (ram_read_wait_cycle),
        .ram_write_wait_cycle               (ram_write_wait_cycle)
    );

    assign  data_bus = internal_data_bus;

    always_comb
    begin
        if (data_bus_out_from_chipset)
        begin
            internal_data_bus_ext = internal_data_bus_chipset;
            data_bus_direction    = 1'b0;
        end
        else if ((~ram_address_select_n) && (~memory_read_n))
        begin
            internal_data_bus_ext = internal_data_bus_ram;
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

