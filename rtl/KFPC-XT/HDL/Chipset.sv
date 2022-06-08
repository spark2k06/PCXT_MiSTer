//
// KFPC-XT Chipset
// Written by kitune-san
//
module CHIPSET (
    input   logic           clock,
	 input   logic           clk_sys,
    input   logic           peripheral_clock,
    input   logic           reset,
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
    input   logic           clk_vga,	 
    input   logic           enable_cga,
    output  logic           de_o,
    output  logic   [5:0]   VGA_R,
    output  logic   [5:0]   VGA_G,
    output  logic   [5:0]   VGA_B,
    output  logic           VGA_HSYNC,
    output  logic           VGA_VSYNC,
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
    output  logic           ps2_busy,
	 // JTOPL	 
	 input   logic           clk_en_opl2,
	 output  logic   [15:0]  jtopl2_snd_e,
	 input   logic           adlibhide,
	 // TANDY SND
	 output  logic   [7:0]   tandy_snd_e,
	 // IOCTL
    input   logic           ioctl_download,
    input   logic   [7:0]   ioctl_index,
    input   logic           ioctl_wr,
    input   logic   [24:0]  ioctl_addr,
    input   logic   [7:0]   ioctl_data,
	 // UART
	 input   logic           clk_uart,
	 input   logic           uart_rx,
	 output  logic           uart_tx,
	 input   logic           uart_cts_n,
	 input   logic           uart_dcd_n,
	 input   logic           uart_dsr_n,
	 output  logic           uart_rts_n,
	 output  logic           uart_dtr_n,
    // SDRAM
    input   logic           enable_sdram,
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
    output  logic           sdram_udqm
);

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

    READY u_READY (
        .clock                              (clock),
        .reset                              (reset),
        .processor_ready                    (processor_ready),
        .dma_ready                          (dma_ready),
        .dma_wait_n                         (dma_wait_n),
        .io_channel_ready                   (io_channel_ready & memory_access_ready),
        .io_read_n                          (io_read_n),
        .io_write_n                         (io_write_n),
        .memory_read_n                      (memory_read_n),
        .dma0_acknowledge_n                 (dma_acknowledge_n[0]),
        .address_enable_n                   (address_enable_n)
    );

    BUS_ARBITER u_BUS_ARBITER (
        .clock                              (clock),
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
        .dma_request                        (dma_request),
        .dma_acknowledge_n                  (dma_acknowledge_n),
        .address_enable_n                   (address_enable_n),
        .terminal_count_n                   (terminal_count_n)
    );

    PERIPHERALS u_PERIPHERALS (
        .clock                              (clock),
		  .clk_sys                            (clk_sys),
		  .clk_uart                           (clk_uart),
        .peripheral_clock                   (peripheral_clock),
        .reset                              (reset),
        .interrupt_to_cpu                   (interrupt_to_cpu),
        .interrupt_acknowledge_n            (interrupt_acknowledge_n),
        .dma_chip_select_n                  (dma_chip_select_n),
        .dma_page_chip_select_n             (dma_page_chip_select_n),
        .splashscreen                       (splashscreen),
        .clk_vga                            (clk_vga),
        .enable_cga                         (enable_cga),
        .de_o                               (de_o),
        .VGA_R                              (VGA_R),
        .VGA_G                              (VGA_G),
        .VGA_B                              (VGA_B),
        .VGA_HSYNC                          (VGA_HSYNC),
        .VGA_VSYNC                          (VGA_VSYNC),
        .address                            (address),
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
	.ps2_busy                           (ps2_busy),
		  .clk_en_opl2                        (clk_en_opl2),
		  .jtopl2_snd_e                       (jtopl2_snd_e),
		  .adlibhide                          (adlibhide),
		  .tandy_snd_e                        (tandy_snd_e),
		  .ioctl_download                     (ioctl_download),
		  .ioctl_index                        (ioctl_index),
		  .ioctl_wr                           (ioctl_wr),
		  .ioctl_addr                         (ioctl_addr),
		  .ioctl_data                         (ioctl_data),
	     .uart_rx                           (uart_rx),
	     .uart_tx                           (uart_tx),
	     .uart_cts_n                        (uart_cts),
	     .uart_dcd_n                        (uart_dcd),
	     .uart_dsr_n                        (uart_dsr),
	     .uart_rts_n                        (uart_rts),
	     .uart_dtr_n                        (uart_dtr)
		  
    );

    RAM u_RAM (
        .clock                              (clock),
        .sdram_clock                        (sdram_clock),
        .reset                              (reset),
        .enable_sdram                       (enable_sdram),
        .address                            (address),
        .internal_data_bus                  (internal_data_bus),
        .data_bus_out                       (internal_data_bus_ram),
        .memory_read_n                      (memory_read_n),
        .memory_write_n                     (memory_write_n),
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
        .sdram_udqm                         (sdram_udqm)
    );

    assign  data_bus = internal_data_bus;

    always_comb begin
        if (data_bus_out_from_chipset) begin
            internal_data_bus_ext = internal_data_bus_chipset;
            data_bus_direction    = 1'b0;
        end
        else if ((~ram_address_select_n) && (~memory_read_n)) begin
            internal_data_bus_ext = internal_data_bus_ram;
            data_bus_direction    = 1'b0;
        end
        else begin
            if (internal_data_bus_direction == 1'b1) begin
                internal_data_bus_ext = data_bus_ext;
                data_bus_direction    = 1'b1;
            end
            else begin
                internal_data_bus_ext = 0;
                data_bus_direction    = 1'b0;
            end
        end
    end

endmodule

