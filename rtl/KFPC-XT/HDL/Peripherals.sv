//
// MiSTer PCXT Peripherals
// Ported by @spark2k06
//
// Based on KFPC-XT written by @kitune-san
//
`ifndef ENABLE_OPL2
`define ENABLE_OPL2 0
`endif
`ifndef ENABLE_CMS
`define ENABLE_CMS 0
`endif
`ifndef ENABLE_EMS
`define ENABLE_EMS 0
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
        input   logic           video_reset,
        // CPU
        output  logic           interrupt_to_cpu,
        // Bus Arbiter
        input   logic           interrupt_acknowledge_n,
        output  logic           dma_chip_select_n,
        output  logic           dma_page_chip_select_n,
        // SplashScreen
        input   logic           splashscreen,
        // VGA
        output  logic           std_hsyncwidth,
        input   logic           clk_video,
        output  logic           de_o,
        output  logic   [5:0]   VGA_R,
        output  logic   [5:0]   VGA_G,
        output  logic   [5:0]   VGA_B,
        output  logic           VGA_HSYNC,
        output  logic           VGA_VSYNC,
        output  logic           VGA_HBlank,
        output  logic           VGA_VBlank,
        output  logic           VGA_VBlank_border,
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
        output  logic           video_memory_access_ready,
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
        // C/MS Audio
        input   logic           cms_en,
        output  reg     [15:0]  o_cms_l,
        output  reg     [15:0]  o_cms_r,
        // UART
        input   logic           clk_uart,
        input   logic           uart2_rx,
        output  logic           uart2_tx,
        input   logic           uart2_cts_n,
        input   logic           uart2_dcd_n,
        input   logic           uart2_dsr_n,
        output  logic           uart2_rts_n,
        output  logic           uart2_dtr_n,
        // EMS
        input   logic           ems_enabled,
        input   logic   [1:0]   ems_address,
        output  reg     [6:0]   map_ems[0:3], // Segment D000, D400, D800, DC00
        output  reg             ena_ems[0:3], // Enable Segment Map D000, D400, D800, DC00
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
        // XTCTL DATA
        output  logic   [7:0]   xtctl = 8'h00,
        // Others
        output  logic           pause_core,
        input   logic           video_scandoubler_en,
        // EGA dot clock status, clk_video domain
        output  logic           ega_dot_toggle,
        output  logic           ega_dot_clock_sel,
        output  logic           ega_scandouble_active_out,
        input   logic           vga_mode13_osd,
        output  logic           vga_mode13_active_out,
        input   logic   [3:0]   crt_h_offset,
        input   logic   [2:0]   crt_v_offset,
        input   logic   [2:0]   vsync_width_osd,
        input   logic   [2:0]   hsync_width_osd
        
    );

    wire vga_mode13_active_video;
    logic vga_mode13_active_sync1;
    logic vga_mode13_active_sync2;
    wire vga_mode13_active_sys = vga_mode13_active_sync2;
    assign vga_mode13_active_out = vga_mode13_active_video;

    // Assert reset immediately, but release it in the clock domain that
    // consumes it.  video_reset originates outside both of these domains.
    (* ASYNC_REG = "TRUE" *) logic [1:0] video_reset_clock_sync = 2'b11;
    (* ASYNC_REG = "TRUE" *) logic [1:0] video_reset_video_sync = 2'b11;
    wire video_reset_clock = video_reset_clock_sync[1];
    wire video_reset_video = video_reset_video_sync[1];

    always_ff @(posedge clock or posedge video_reset) begin
        if (video_reset)
            video_reset_clock_sync <= 2'b11;
        else
            video_reset_clock_sync <= {video_reset_clock_sync[0], 1'b0};
    end

    always_ff @(posedge clk_video or posedge video_reset) begin
        if (video_reset)
            video_reset_video_sync <= 2'b11;
        else
            video_reset_video_sync <= {video_reset_video_sync[0], 1'b0};
    end

    wire [1:0] ega_mem_map_sel_cfg;

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
        if (iorq & ~address_enable_n & ~address[9] & ~address[8])
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
    wire    joystick_select         = (iorq && ~address_enable_n && address[15:3] == (16'h0200 >> 3)); // 0x200 .. 0x207
    wire    opl_388_chip_select     = `ENABLE_OPL2 ? (iorq && ~address_enable_n && ~opl2_io[1] && address[15:1] == (16'h0388 >> 1)) : 1'b0; // 0x388 .. 0x389 (Adlib)
    wire    opl_228_chip_select     = `ENABLE_OPL2 ? (iorq && ~address_enable_n && (opl2_io == 2'b01) && address[15:1] == (16'h0228 >> 1)) : 1'b0; // 0x228 .. 0x229 (Sound Blaster FM)
    wire    cms_220_chip_select     = `ENABLE_CMS ? (iorq && ~address_enable_n && address[15:4] == (16'h0220 >> 4)) : 1'b0; // 0x220 .. 0x22F (C/MS Audio)
    wire    vga_a000_select;
    wire    ega_mem_select_raw      = ~iorq && ~address_enable_n && ega_memory_window_select(address, ega_mem_map_sel_cfg);
    wire    ega_mem_select          = ega_mem_select_raw && !vga_a000_select;
    wire    uart_chip_select        = (~address_enable_n && {address[15:3], 3'd0} == 16'h03F8);
    wire    uart2_chip_select       = (~address_enable_n && {address[15:3], 3'd0} == 16'h02F8);
    wire    lpt_chip_select         = (iorq && ~address_enable_n && address[15:1] == (16'h0378 >> 1)); // 0x378 ... 0x379
	 wire    lpt_ctrl_select         = (iorq && ~address_enable_n && address[15:0] == 16'h037A); // 0x37A
    wire    xtctl_chip_select       = (iorq && ~address_enable_n && address[15:0] == 16'h8888);
    wire    rtc_chip_select         = (iorq && ~address_enable_n && address[15:1] == (16'h02C0 >> 1)); // 0x2C0 .. 0x2C1

    wire    [3:0] ems_page_address  = (ems_address == 2'b00) ? 4'b1100 : (ems_address == 2'b01) ? 4'b1101 : 4'b1110;
    wire    ems_chip_select         = `ENABLE_EMS ? (iorq && ~address_enable_n && ems_enabled && ({address[15:2], 2'd0} == 16'h0260)) : 1'b0;          // 260h..263h
    assign  ems_b1                  = `ENABLE_EMS ? (ems_enabled && ~iorq && ena_ems[0] && (address[19:14] == {ems_page_address, 2'b00})) : 1'b0;
    assign  ems_b2                  = `ENABLE_EMS ? (ems_enabled && ~iorq && ena_ems[1] && (address[19:14] == {ems_page_address, 2'b01})) : 1'b0;
    assign  ems_b3                  = `ENABLE_EMS ? (ems_enabled && ~iorq && ena_ems[2] && (address[19:14] == {ems_page_address, 2'b10})) : 1'b0;
    assign  ems_b4                  = `ENABLE_EMS ? (ems_enabled && ~iorq && ena_ems[3] && (address[19:14] == {ems_page_address, 2'b11})) : 1'b0;
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
    assign latch_address = address;

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
        if (reset)
        begin
            map_ems = '{7'h00, 7'h00, 7'h00, 7'h00};
            ena_ems = '{1'b0, 1'b0, 1'b0, 1'b0};
        end
        else if (!`ENABLE_EMS || !ems_enabled)
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
        .interrupt_request          ({interrupt_request[7],
                                        fdd_interrupt,
                                        interrupt_request[5],
                                        uart_interrupt,
                                        uart2_interrupt,
                                        interrupt_request[2],
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
    logic   [7:0]   keycode_buf;
    logic   [7:0]   keycode;
    logic           prev_ps2_reset;
    logic           prev_ps2_reset_n;
    logic           lock_recv_clock;
    localparam [15:0] OPL_WARM_RESET_HOLD = 16'd5000;
    logic           prev_keybord_irq;
    logic           ctrl_down;
    logic           alt_down;
    logic   [15:0]  opl_reset_cnt;
    wire            opl_warm_reset = `ENABLE_OPL2 ? (opl_reset_cnt != 16'd0) : 1'b0;

    wire    clear_keycode = port_b_out[7];
    wire    ps2_reset_n   = port_b_out[6];

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
        .pause_core                 (pause_core)
    );

    assign  keycode = ps2_reset_n ? keycode_buf : 8'h80;

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            prev_keybord_irq <= 1'b0;
            ctrl_down        <= 1'b0;
            alt_down         <= 1'b0;
            opl_reset_cnt    <= 16'd0;
        end
        else if (`ENABLE_OPL2)
        begin
            prev_keybord_irq <= keybord_irq;
            if (opl_reset_cnt != 16'd0)
                opl_reset_cnt <= opl_reset_cnt - 16'd1;

            if (keybord_irq && ~prev_keybord_irq)
            begin
                case (keycode)
                    8'h1D: ctrl_down <= 1'b1;
                    8'h9D: ctrl_down <= 1'b0;
                    8'h38: alt_down  <= 1'b1;
                    8'hB8: alt_down  <= 1'b0;
                    default: ;
                endcase

                if (keycode == 8'h53 && ctrl_down && alt_down)
                    opl_reset_cnt <= OPL_WARM_RESET_HOLD;
            end
        end
        else
        begin
            prev_keybord_irq <= 1'b0;
            ctrl_down        <= 1'b0;
            alt_down         <= 1'b0;
            opl_reset_cnt    <= 16'd0;
        end
    end

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

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            ps2_clock_out = 1'b1;
        else
            ps2_clock_out = ~(keybord_irq | ~ps2_send_clock | ~ps2_reset_n);
    end

    wire [7:0] jtopl2_dout_int;
    wire [15:0] jtopl2_snd_e_int;
    wire [7:0] jtopl2_dout = `ENABLE_OPL2 ? jtopl2_dout_int : 8'hFF;
    assign jtopl2_snd_e = `ENABLE_OPL2 ? jtopl2_snd_e_int : 16'd0;

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
        .rst(reset | opl_warm_reset),
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
        end
        else
        begin
            keybord_interrupt_ff    <= keybord_irq;
            keybord_interrupt       <= keybord_interrupt_ff;
            uart_interrupt_ff       <= uart_irq;
            uart_interrupt          <= uart_interrupt_ff;
            uart2_interrupt_ff      <= uart2_irq;
            uart2_interrupt         <= uart2_interrupt_ff;
        end
    end

    logic prev_io_read_n;
    logic prev_io_write_n;
    logic [7:0] write_to_uart;
    logic [7:0] write_to_uart2;
    logic [7:0] uart_readdata_1;
    logic [7:0] uart_readdata;
    logic [7:0] uart2_readdata_1;
    logic [7:0] uart2_readdata;

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
            keycode_ff  <= keycode;
            port_a_in   <= keycode_ff;
        end
    end

    reg [7:0] lpt_reg = 8'hFF;
	 reg [7:0] lpt_ctrl = 8'h00;
	 reg [7:0] lpt_enable_irq = 8'h00;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)        
        begin
            xtctl <= 8'b00;
        end
        else begin
            if (~io_write_n)
            begin
                write_to_uart <= internal_data_bus;
                write_to_uart2 <= internal_data_bus;
            end
            else
            begin
                write_to_uart <= write_to_uart;
                write_to_uart2 <= write_to_uart2;
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
	 

    uart uart2
    (
        .clk               (clock),
        .br_clk            (clk_uart),
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
        end
        else
        begin
            uart_readdata <= uart_readdata;
            uart2_readdata <= uart2_readdata;
        end
    end


    logic  [16:0]  video_ram_address;
    logic  [7:0]   video_ram_data;
    logic          video_memory_write_n;
    logic  [14:0]  video_io_address;
    logic  [7:0]   video_io_data;
    logic          video_io_write_n;
    logic          video_io_read_n;
    logic          video_address_enable_n;
    logic  [14:0]  video_io_address_sync1;
    logic  [14:0]  video_io_address_sync2;
    logic  [7:0]   video_io_data_sync1;
    logic  [7:0]   video_io_data_sync2;
    logic          video_io_write_n_sync1;
    logic          video_io_write_n_sync2;
    logic          video_io_read_n_sync1;
    logic          video_io_read_n_sync2;
    logic          video_address_enable_n_sync1;
    logic          video_address_enable_n_sync2;
    logic          ega_mem_select_sys;
    logic          ega_mem_write_sys;
    logic          ega_mem_select_1;
    logic          ega_mem_select_2;
    logic          ega_mem_write_1;
    logic          ega_mem_write_2;
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
        ega_mem_select_sys      <= ega_mem_select;
        ega_mem_write_sys       <= ega_mem_select & ~memory_write_n;

        video_io_write_n        <= io_write_n;
        video_io_read_n         <= io_read_n;
        video_address_enable_n  <= address_enable_n;
    end

    always_ff @(posedge clock or posedge reset)
    begin
        if (reset) begin
            vga_mode13_active_sync1 <= 1'b0;
            vga_mode13_active_sync2 <= 1'b0;
        end else begin
            vga_mode13_active_sync1 <= vga_mode13_active_video;
            vga_mode13_active_sync2 <= vga_mode13_active_sync1;
        end
    end

    always_ff @(posedge clk_video, posedge reset)
    begin
        if (reset)
        begin
            video_io_address_sync1        <= 15'd0;
            video_io_address_sync2        <= 15'd0;
            video_io_data_sync1           <= 8'd0;
            video_io_data_sync2           <= 8'd0;
            video_io_write_n_sync1        <= 1'b1;
            video_io_write_n_sync2        <= 1'b1;
            video_io_read_n_sync1         <= 1'b1;
            video_io_read_n_sync2         <= 1'b1;
            video_address_enable_n_sync1  <= 1'b1;
            video_address_enable_n_sync2  <= 1'b1;
            ega_mem_select_1        <= 1'b0;
            ega_mem_select_2        <= 1'b0;
            ega_mem_write_1         <= 1'b0;
            ega_mem_write_2         <= 1'b0;
        end
        else
        begin
            video_io_address_sync1        <= video_io_address;
            video_io_address_sync2        <= video_io_address_sync1;
            video_io_data_sync1           <= video_io_data;
            video_io_data_sync2           <= video_io_data_sync1;
            video_io_write_n_sync1        <= video_io_write_n;
            video_io_write_n_sync2        <= video_io_write_n_sync1;
            video_io_read_n_sync1         <= video_io_read_n;
            video_io_read_n_sync2         <= video_io_read_n_sync1;
            video_address_enable_n_sync1  <= video_address_enable_n;
            video_address_enable_n_sync2  <= video_address_enable_n_sync1;
            ega_mem_select_1        <= ega_mem_select_sys;
            ega_mem_select_2        <= ega_mem_select_1;
            ega_mem_write_1         <= ega_mem_write_sys;
            ega_mem_write_2         <= ega_mem_write_1;
        end
    end


    wire [5:0] R_EGA;
    wire [5:0] G_EGA;
    wire [5:0] B_EGA;
    wire [15:0] VGA_FRAMEBUFFER_ADDR;
    wire        VGA_FRAMEBUFFER_READ_EN;
    wire [7:0]  VGA_FRAMEBUFFER_PIXEL;
    wire        VGA_FRAMEBUFFER_DATA_VALID;
    wire       HSYNC_EGA;
    wire       VSYNC_EGA;
    wire       HBLANK_EGA;
    wire       VBLANK_EGA;
    wire       de_o_ega;
    wire       hsync_ega_raw;
    wire       hsync_ega_sd;
    wire       video_display_active;
    wire       ega_scandouble_active;

    assign VGA_R = R_EGA;
    assign VGA_G = G_EGA;
    assign VGA_B = B_EGA;
    assign VGA_HSYNC = HSYNC_EGA;
    assign VGA_VSYNC = VSYNC_EGA;

    assign VGA_HBlank = HBLANK_EGA;
    assign VGA_VBlank = VBLANK_EGA;

    assign de_o = de_o_ega;
    assign HSYNC_EGA = ega_scandouble_active ? hsync_ega_sd : hsync_ega_raw;
    assign ega_scandouble_active_out = ega_scandouble_active;

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
    wire [15:0] EGA_TEXT_FONT_ADDR;
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
    wire        VGA_VBlank_border_raw;
    wire        std_hsyncwidth_raw;

    // Sets up the card to generate a video signal
    // that will work with a standard VGA monitor
    // connected to the VGA port.


    wire thin_font;

    // Thin font switch (TODO: switchable with Keyboard shortcut)
    assign thin_font = 1'b0; // Default: No thin font

    assign VGA_VBlank_border = VGA_VBlank_border_raw;
    assign std_hsyncwidth = std_hsyncwidth_raw;

    ega_top ega1 
    (
        .clk                        (clk_video),
        .reset                      (video_reset_video),
        .bus_a                      (video_io_address_sync2),
        .bus_ior_l                  (video_io_read_n_sync2),
        .bus_iow_l                  (video_io_write_n_sync2),
        .bus_d                      (video_io_data_sync2),
        .bus_out                    (EGA_IO_DOUT),
        .bus_dir                    (EGA_IO_OE),
        .bus_aen                    (video_address_enable_n_sync2),
        .ega_fetch_addr             (EGA_FETCH_ADDR),
        .ega_fetch_en               (EGA_FETCH_EN),
        .ega_plane0_data            (EGA_PLANE0_DOUT),
        .ega_plane1_data            (EGA_PLANE1_DOUT),
        .ega_plane2_data            (EGA_PLANE2_DOUT),
        .ega_plane3_data            (EGA_PLANE3_DOUT),
        .ega_fetch_data_valid       (EGA_FETCH_DATA_VALID),
        .ega_text_cell_addr         (EGA_TEXT_CELL_ADDR),
        .ega_text_font_addr         (EGA_TEXT_FONT_ADDR),
        .ega_text_fetch_en          (EGA_TEXT_FETCH_EN),
        .ega_text_char              (EGA_TEXT_CHAR),
        .ega_text_attr              (EGA_TEXT_ATTR),
        .ega_text_glyph             (EGA_TEXT_GLYPH),
        .ega_text_data_valid        (EGA_TEXT_DATA_VALID),
        .vga_framebuffer_addr      (VGA_FRAMEBUFFER_ADDR),
        .vga_framebuffer_read_en   (VGA_FRAMEBUFFER_READ_EN),
        .vga_framebuffer_pixel     (VGA_FRAMEBUFFER_PIXEL),
        .vga_framebuffer_data_valid(VGA_FRAMEBUFFER_DATA_VALID),
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
        .hblank                     (HBLANK_EGA),
        .vsync                      (VSYNC_EGA),
        .vblank                     (VBLANK_EGA),
        .vblank_border              (VGA_VBlank_border_raw),
        .std_hsyncwidth             (std_hsyncwidth_raw),
        .de_o                       (de_o_ega),
        .ega_red                    (R_EGA),
        .ega_green                  (G_EGA),
        .ega_blue                   (B_EGA),
        .ega_display_sel_out        (video_display_active),
        .ega_dot_toggle_out         (ega_dot_toggle),
        .ega_dot_clock_sel_out      (ega_dot_clock_sel),
        .ega_scandouble_active_out  (ega_scandouble_active),
        .splashscreen               (splashscreen),
        .thin_font                  (thin_font),
        .scandouble_en              (video_scandoubler_en),
        .ega_enabled                (1'b1),
        .vga_enabled               (vga_mode13_osd),
        .vga_mode13_set            (1'b0),
        .vga_mode13_clear          (1'b0),
        .vga_mode13_active_out     (vga_mode13_active_video),
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


    defparam ega1.BLINK_MAX = 24'd4772727;
    wire [7:0] ega_vram_cpu_dout;
    wire [7:0] vga_vram_cpu_dout;
    wire [15:0] ega_vram_cpu_addr = address[15:0];
    wire        ega_vram_cpu_a16 = address[16];
    wire [7:0]  ega_vram_cpu_din = internal_data_bus;
    wire        ega_vram_cpu_read_req = ega_mem_select && ~memory_read_n;
    wire        ega_vram_cpu_write_req = ega_mem_select && ~memory_write_n;
    wire        ega_vram_cpu_cycle = ega_vram_cpu_read_req | ega_vram_cpu_write_req;
    wire        ega_vram_cpu_ready;
    wire        vga_vram_cpu_cycle;
    wire        vga_vram_cpu_ready;
    ega_vram_bram_frontend ega_vram_frontend
    (
        .clock                      (clock),
        .reset_cpu                  (video_reset_clock),
        .reset_video                (video_reset_video),
        .clk_video                  (clk_video),
        .cpu_addr                   (ega_vram_cpu_addr),
        .cpu_a16                    (ega_vram_cpu_a16),
        .cpu_din                    (ega_vram_cpu_din),
        .cpu_read                   (ega_vram_cpu_read_req),
        .cpu_write                  (ega_vram_cpu_write_req),
        .cpu_dout                   (ega_vram_cpu_dout),
        .cpu_ready                  (ega_vram_cpu_ready),
        .video_addr                 (EGA_FETCH_ADDR),
        .video_read_en              (EGA_FETCH_EN),
        .video_plane0               (EGA_PLANE0_DOUT),
        .video_plane1               (EGA_PLANE1_DOUT),
        .video_plane2               (EGA_PLANE2_DOUT),
        .video_plane3               (EGA_PLANE3_DOUT),
        .video_data_valid           (EGA_FETCH_DATA_VALID),
        .text_cell_addr             (EGA_TEXT_CELL_ADDR),
        .text_font_addr             (EGA_TEXT_FONT_ADDR),
        .text_fetch_en              (EGA_TEXT_FETCH_EN & video_display_active),
        .text_char                  (EGA_TEXT_CHAR),
        .text_attr                  (EGA_TEXT_ATTR),
        .text_glyph                 (EGA_TEXT_GLYPH),
        .text_data_valid            (EGA_TEXT_DATA_VALID),
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
        .rotate_count               (ega_rotate_count_cfg)
    );

    vga_a000_cpu_frontend vga_a000_cpu_frontend_inst
    (
        .clock                      (clock),
        .reset                      (reset),
        .clk_video                  (clk_video),
        .active                     (vga_mode13_active_sys),
        .address                    (address),
        .cpu_din                    (internal_data_bus),
        .iorq                       (iorq),
        .address_enable_n           (address_enable_n),
        .memory_read_n              (memory_read_n),
        .memory_write_n             (memory_write_n),
        .a000_select                (vga_a000_select),
        .cpu_cycle                  (vga_vram_cpu_cycle),
        .cpu_dout                   (vga_vram_cpu_dout),
        .cpu_ready                  (vga_vram_cpu_ready),
        .video_addr                 (VGA_FRAMEBUFFER_ADDR),
        .video_read_en              (VGA_FRAMEBUFFER_READ_EN),
        .video_pixel                (VGA_FRAMEBUFFER_PIXEL),
        .video_data_valid           (VGA_FRAMEBUFFER_DATA_VALID)
    );

    assign video_memory_access_ready = vga_vram_cpu_cycle ? vga_vram_cpu_ready :
                                     ega_vram_cpu_cycle ? ega_vram_cpu_ready :
                                     1'b1;
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
        else if (ega_mem_select && (~memory_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= ega_vram_cpu_dout;
        end
        else if (vga_a000_select && (~memory_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= vga_vram_cpu_dout;
        end
        else if (EGA_IO_OE_SYNC2)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= EGA_IO_DOUT_SYNC2;
        end
        else if (`ENABLE_OPL2 && (opl_228_chip_select || opl_388_chip_select) && ~io_read_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= jtopl2_dout;
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
