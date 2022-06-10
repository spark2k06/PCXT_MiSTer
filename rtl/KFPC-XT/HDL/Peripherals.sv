//
// KFPC-XT Peripherals
// Written by kitune-san
//
module PERIPHERALS #(
    parameter ps2_over_time = 16'd1000
) (
    input   logic           clock,
	 input   logic           clk_sys,
    input   logic           peripheral_clock,
    input   logic           reset,
    // CPU
    output  logic           interrupt_to_cpu,
    // Bus Arbiter
    input   logic           interrupt_acknowledge_n,
    output  logic           dma_chip_select_n,
    output  logic           dma_page_chip_select_n,
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
    input   logic   [19:0]  address,
    input   logic   [7:0]   internal_data_bus,
    output  logic   [7:0]   data_bus_out,
    output  logic           data_bus_out_from_chipset,
    input   logic   [7:0]   interrupt_request,
    input   logic           io_read_n,
    input   logic           io_write_n,
    input   logic           memory_read_n,
    input   logic           memory_write_n,
    input   logic           address_enable_n,
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
	 output  logic           uart_dtr_n

	 
);
    //
    // chip select
    //
    logic   [7:0]   chip_select_n;

    always_comb begin
        if (~address_enable_n & ~address[9] & ~address[8]) begin
            casez (address[7:5])
                3'b000:  chip_select_n = 8'b11111110;
                3'b001:  chip_select_n = 8'b11111101;
                3'b010:  chip_select_n = 8'b11111011;
                3'b011:  chip_select_n = 8'b11110111;
                3'b100:  chip_select_n = 8'b11101111;
                3'b101:  chip_select_n = 8'b11011111;
                3'b110:  chip_select_n = 8'b10111111;
                3'b111:  chip_select_n = 8'b01111111;
                default: chip_select_n = 8'b11111111;
            endcase
        end
        else begin
            chip_select_n = 8'b11111111;
        end
    end

    assign  dma_chip_select_n       = chip_select_n[0];
    wire    interrupt_chip_select_n = chip_select_n[1];
    wire    timer_chip_select_n     = chip_select_n[2];
    wire    ppi_chip_select_n       = chip_select_n[3];
    assign  dma_page_chip_select_n  = chip_select_n[4];
	 
	 wire    tandy_chip_select_n    = ~(address[15:3] == (16'h00c0 >> 3)); // 0xc0 - 0xc7
	 wire    opl_chip_select_n      = ~(address[15:1] == (16'h0388 >> 1)); // 0x388 .. 0x389
    wire    cga_chip_select_n      = ~(enable_cga & (address[19:14] == 6'b1011_10)); // B8000 - BFFFF (32 KB)
	 wire    mda_chip_select_n      = ~(enable_cga & (address[19:14] == 6'b1011_00)); // B0000 - B7FFF (32 KB)
	 wire    rom_select_n           = ~(address[19:16] == 4'b1111); // F0000 - FFFFF (64 KB)
	 wire    ram_select_n           = ~(address[19:18] == 2'b00); // 00000 - 3FFFF (256 KB)
	 wire    uart_cs                = ({address[15:3], 3'd0} == 16'h03F8);
	 

    //
    // 8259
    //
    logic           timer_interrupt;
    logic           keybord_interrupt;
	 logic           uart_interrupt;
    logic   [7:0]   interrupt_data_bus_out;

    KF8259 u_KF8259 (
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
        .interrupt_to_cpu           (interrupt_to_cpu),
        .interrupt_request          ({interrupt_request[7:5], uart_interrupt, interrupt_request[3:2],
                                        keybord_interrupt, timer_interrupt})
    );

    //
    // 8253
    //
    // Clock domain crossing
    logic   timer_clock_ff_1;
    always_ff @(negedge peripheral_clock, posedge reset) begin
        if (reset)
            timer_clock_ff_1 <= 1'b0;
        else
            timer_clock_ff_1 <= ~timer_clock_ff_1;
    end

    logic   timer_clock_ff_2;
    logic   timer_clock;
    always_ff @(negedge clock, posedge reset) begin
        if (reset) begin
            timer_clock_ff_2    <= 1'b0;
            timer_clock         <= 1'b0;
        end
        else begin
            timer_clock_ff_2    <= timer_clock_ff_1;
            timer_clock         <= timer_clock_ff_2;
        end
    end

    logic   [7:0]   timer_data_bus_out;

    wire    tim2gatespk = port_b_out[0] & ~port_b_io;
    wire    spkdata     = port_b_out[1] & ~port_b_io;

    KF8253 u_KF8253 (
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

    KF8255 u_KF8255 (
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

    // Clock domain crossing
    logic   clear_keycode_ff;
    logic   clear_keycode;
    always_ff @(negedge peripheral_clock, posedge reset) begin
        if (reset) begin
            clear_keycode_ff    <= 1'b0;
            clear_keycode       <= 1'b0;
        end
        else begin
            clear_keycode_ff    <= port_b_out[7];
            clear_keycode       <= clear_keycode_ff;
        end
    end

    logic           keybord_irq;
    logic   [7:0]   keycode;

    KFPS2KB u_KFPS2KB (
        // Bus
        .clock                      (peripheral_clock),
        .reset                      (reset),

        // PS/2 I/O
        .device_clock               (ps2_clock),
        .device_data                (ps2_data),

        // I/O
        .irq                        (keybord_irq),
        .keycode                    (keycode),
        .clear_keycode              (clear_keycode)
    );
    assign ps2_busy = keybord_irq | (~port_b_io & ~port_b_out[6]);

   wire [7:0] jtopl2_dout;
	wire [7:0]opl32_data;	
   assign opl32_data = adlibhide ? 8'hFF : jtopl2_dout;
	 
	jtopl2 jtopl2_inst
	(
		.rst(reset),
		.clk(clock),
		.cen(clk_en_opl2),
		.din(internal_data_bus),
		.dout(jtopl2_dout),
		.addr(address[0]),
		.cs_n(opl_chip_select_n),
		.wr_n(io_write_n),
		.irq_n(),
		.snd(jtopl2_snd_e),
		.sample()
	);	
	
	wire TANDY_SND_RDY;
	
	// Tandy sound
	sn76489_top sn76489
	(
		.clock_i(clock),
		.clock_en_i(clk_en_opl2), // 3.579MHz
		.res_n_i(reset),
		.ce_n_i(tandy_chip_select_n),
		.we_n_i(io_write_n),
		.ready_o(TANDY_SND_RDY),
		.d_i(internal_data_bus),
		.aout_o(tandy_snd_e)
	);	
	
	    logic   keybord_interrupt_ff;
    always_ff @(negedge clock, posedge reset) begin
        if (reset) begin
            keybord_interrupt_ff    <= 1'b0;
            keybord_interrupt       <= 1'b0;
        end
        else begin
            keybord_interrupt_ff    <= keybord_irq;
            keybord_interrupt       <= keybord_interrupt_ff;
        end
	end
	
	logic	prev_io_read_n;
	logic	prev_io_write_n;
	logic	[7:0]	write_to_uart;
	logic [7:0] uart_readdata_1;
	logic [7:0] uart_readdata_2;
	logic [7:0] uart_readdata;

	always_ff @(negedge clock) begin
		prev_io_read_n <= io_read_n;
		prev_io_write_n <= io_write_n;
	end

    logic   [7:0]   keycode_ff;
    always_ff @(negedge clock, posedge reset) begin
        if (reset) begin
            keycode_ff  <= 8'h00;
            port_a_in   <= 8'h00;
        end
        else begin
            keycode_ff  <= keycode;
            port_a_in   <= keycode_ff;
        end
    end
	always_ff @(negedge clock) begin
		if (~io_write_n)
			write_to_uart <= internal_data_bus;
		else
			write_to_uart <= write_to_uart;
	end

	uart uart1
	(
		.clk               (clock),
		.br_clk            (clk_uart),
		.reset             (reset),

		.address           (address[2:0]),
		.writedata         (write_to_uart),
		.read              (~io_read_n & prev_io_read_n),
		.write             (io_write_n & ~prev_io_write_n),
		.readdata          (uart_readdata_1),
		.cs                (uart_cs),

		.rx                (uart_rx),
		.tx                (uart_tx),
		.cts_n             (uart_cts_n),
		.dcd_n             (uart_dcd_n),
		.dsr_n             (uart_dsr_n),
		.rts_n             (uart_rts_n),
		.dtr_n             (uart_dtr_n),
		.ri_n              (1),

		.irq               (uart_interrupt)
	);

	// Timing of the readings may need to be reviewed.
	always_ff @(negedge clock) begin
		if (~io_read_n & prev_io_read_n)
			uart_readdata <= uart_readdata_1;
		else
			uart_readdata <= uart_readdata;
	end
	 
	 
	 wire VRAM_ENABLE;
	 wire [18:0] VRAM_ADDR;
	 wire [7:0] VRAM_DOUT;
	 wire CRTC_OE;
	 wire [7:0] CRTC_DOUT;	 
	
    // Sets up the card to generate a video signal
    // that will work with a standard VGA monitor
    // connected to the VGA port.
    parameter MDA_70HZ = 0;

    wire[3:0] vga_video;
	 wire[3:0] video;

    // wire composite_on;
    wire thin_font;

	// Composite mode switch
    //assign composite_on = switch3; (TODO: Test in next version, from the original Graphics Gremlin sources)

    // Thin font switch (TODO: switchable with Keyboard shortcut)
	 assign thin_font = 1'b0; // Default: No thin font

    // CGA digital to analog converter
    cga_vgaport vga (
        .clk(clk_vga),
//      .video(vga_video),		  
        .video(video),		  //Mister Test without Scandouble
        .red(VGA_R),
        .green(VGA_G),
        .blue(VGA_B)
    );   

	 cga cga1 (
	     .clk                        (clk_vga),
		  .bus_a                      (address[15:0]),
		  .bus_ior_l                  (io_read_n),
		  .bus_iow_l                  (io_write_n),
        .bus_memr_l                 (1'd0),
        .bus_memw_l                 (1'd0),  
		  .bus_d                      (internal_data_bus),
		  .bus_out                    (CRTC_DOUT),
		  .bus_dir                    (CRTC_OE),
		  .bus_aen                    (address_enable_n),
        .ram_we_l                   (VRAM_ENABLE),
        .ram_a                      (VRAM_ADDR),
        .ram_d                      (VRAM_DOUT),
//      .dbl_hsync                  (VGA_HSYNC), 
		  .hsync                      (VGA_HSYNC), //Mister Test without Scandouble
        .vsync                      (VGA_VSYNC),
		  .de_o                       (de_o),
        .video                      (video),
//      .dbl_video                  (vga_video),
//      .comp_video                 (comp_video),
		  .splashscreen               (splashscreen),
        .thin_font                  (thin_font)
    );
	 
    defparam cga1.BLINK_MAX = 24'd4772727;
	 wire [7:0] ram_cpu_dout;
	 wire [7:0] bios_cpu_dout;
	 wire [7:0] vram_cpu_dout;

    vram vram
	 (
        .clka                       (clock),
        .ena                        (~address_enable_n && (~mda_chip_select_n || ~cga_chip_select_n)),
        .wea                        (~memory_write_n),
        .addra                      (address[14:0]),
        .dina                       (internal_data_bus),
        .douta                      (vram_cpu_dout),
        .clkb                       (clk_vga),
        .web                        (1'b0),
        .enb                        (VRAM_ENABLE),
        .addrb                      (VRAM_ADDR[14:0]),
        .dinb                       (8'h0),
        .doutb                      (VRAM_DOUT)
	);

	
	ram #(.AW(18)) mram
	(
	  .clka(clock),
	  .ena(~address_enable_n && ~ram_select_n),
	  .wea(~memory_write_n),
	  .addra(address[17:0]),
	  .dina(internal_data_bus),
	  .douta(ram_cpu_dout)
	);
	
	
	bios bios
	(
        .clka(ioctl_download ? clk_sys : clock),
        .ena((~address_enable_n && ~rom_select_n) || ioctl_download),
        .wea(ioctl_download && ioctl_wr),
        .addra(ioctl_download ? ioctl_addr[15:0] : address[15:0]),
        .dina(ioctl_data),
        .douta(bios_cpu_dout)
	);
	
	 
    //
    // KFTVGA
    //
    /*
	 logic   [7:0]   tvga_data_bus_out;

    KFTVGA u_KFTVGA (
        // Bus
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (tvga_chip_select_n),
        .read_enable_n              (memory_read_n),
        .write_enable_n             (memory_write_n),
        .address                    (address[13:0]),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (tvga_data_bus_out),

        // I/O
        .video_clock                (video_clock),
        .video_reset                (video_reset),
        .video_h_sync               (video_h_sync),
        .video_v_sync               (video_v_sync),
        .video_r                    (video_r),
        .video_g                    (video_g),
        .video_b                    (video_b)
    );
	 */

    //
    // data_bus_out
    //
    always_comb begin
        if (~interrupt_acknowledge_n) begin
            data_bus_out_from_chipset = 1'b1;
            data_bus_out = interrupt_data_bus_out;
        end
        else if ((~interrupt_chip_select_n) && (~io_read_n)) begin
            data_bus_out_from_chipset = 1'b1;
            data_bus_out = interrupt_data_bus_out;
        end
        else if ((~timer_chip_select_n) && (~io_read_n)) begin
            data_bus_out_from_chipset = 1'b1;
            data_bus_out = timer_data_bus_out;
        end
        else if ((~ppi_chip_select_n) && (~io_read_n)) begin
            data_bus_out_from_chipset = 1'b1;
            data_bus_out = ppi_data_bus_out;
        end
        else if ((~cga_chip_select_n || ~mda_chip_select_n) && (~memory_read_n)) begin
            data_bus_out_from_chipset = 1'b1;
            data_bus_out = vram_cpu_dout;
        end
		  else if ((~rom_select_n) && (~memory_read_n)) begin
            data_bus_out_from_chipset = 1'b1;
            data_bus_out = bios_cpu_dout;
        end
		  else if ((~ram_select_n) && (~memory_read_n)) begin
            data_bus_out_from_chipset = 1'b1;
            data_bus_out = ram_cpu_dout;			
        end
		  else if (CRTC_OE) begin
            data_bus_out_from_chipset = 1'b1;
            data_bus_out = CRTC_DOUT;			
        end
		  else if ((~opl_chip_select_n) && (~io_read_n)) begin
            data_bus_out_from_chipset = 1'b1;
            data_bus_out = opl32_data;			
        end
		  else if ((uart_cs) && (~io_read_n)) begin
            data_bus_out_from_chipset = 1'b1;
            data_bus_out = uart_readdata;			
        end
        else begin
            data_bus_out_from_chipset = 1'b0;
            data_bus_out = 8'b00000000;
        end
    end

endmodule

