
`define TB_CYCLE        200
`define TB_SDRAM_CYCLE  20
`define TB_FINISH_COUNT 200000

module CHIPSET_tm();

    timeunit        1ns;
    timeprecision   10ps;

    //
    // Generate wave file to check
    //
`ifdef IVERILOG
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
    end
`endif

    //
    // Generate clock
    //
    logic   clock;
    logic   video_clock;
    logic   sdram_clock;
    logic   cpu_ce_posedge;
    logic   cpu_ce_negedge;
    logic   clk_sys;
    logic   peripheral_ce;
    logic   [1:0] clk_select;
    initial clock = 1'b0;
    initial sdram_clock = 1'b0;
    always #(`TB_CYCLE / 2) clock = ~clock;

    assign video_clock = clock;
    assign cpu_ce_posedge = 1'b1;
    assign cpu_ce_negedge = 1'b1;
    assign clk_sys = clock;
    assign peripheral_ce = 1'b1;
    assign clk_select = 2'b00;
    assign clk_vga_cga = video_clock;
    assign clk_uart = clock;

    always #(`TB_SDRAM_CYCLE/ 2) sdram_clock = ~sdram_clock;

    //
    // Generate reset
    //
    logic reset;
    logic sdram_reset;
    initial begin
        reset = 1'b1;
            # (`TB_CYCLE * 10)
        reset = 1'b0;
    end
    logic status0_clear = 1'b0;
    logic splashscreen = 1'b0;
    logic cga_clear_busy;

    //
    // Cycle counter
    //
    logic   [31:0]  tb_cycle_counter;
    integer tb_failures = 0;
    always_ff @(negedge clock, posedge reset) begin
        if (reset)
            tb_cycle_counter <= 32'h0;
        else
            tb_cycle_counter <= tb_cycle_counter + 32'h1;
    end

    always_comb begin
        if (tb_cycle_counter == `TB_FINISH_COUNT) begin
            $display("***** SIMULATION TIMEOUT ***** at %d", tb_cycle_counter);
`ifdef IVERILOG
            $finish;
`elsif  MODELSIM
            $stop;
`else
            $finish;
`endif
        end
    end

    //
    // Module under test
    //
    // CPU
    logic   [19:0]  cpu_address;
    logic   [7:0]   cpu_data_bus;
    logic   [2:0]   processor_status;
    logic           processor_lock_n;
    logic           processor_transmit_or_receive_n;
    logic           processor_ready;
    logic           interrupt_to_cpu;
    // VGA
    logic           std_hsyncwidth;
    logic           composite;
    logic           clk_vga_cga;
    logic           de_o;
    logic   [5:0]   VGA_R;
    logic   [5:0]   VGA_G;
    logic   [5:0]   VGA_B;
    logic           VGA_HSYNC;
    logic           VGA_VSYNC;
    logic           VGA_HBlank;
    logic           VGA_VBlank;
    logic           VGA_VBlank_border;
    // I/O Ports
    logic   [19:0]  address;
    logic   [19:0]  address_ext;
    logic           address_direction;
    logic   [7:0]   data_bus;
    logic   [7:0]   data_bus_ext;
    logic           data_bus_direction;
    logic           address_latch_enable;
    logic           io_channel_check;
    logic           io_channel_ready;
    logic   [7:0]   interrupt_request;
    logic           io_read_n;
    logic           io_read_n_ext;
    logic           io_read_n_direction;
    logic           io_write_n;
    logic           io_write_n_ext;
    logic           io_write_n_direction;
    logic           memory_read_n;
    logic           memory_read_n_ext;
    logic           memory_read_n_direction;
    logic           memory_write_n;
    logic           memory_write_n_ext;
    logic           memory_write_n_direction;
    logic           ext_access_request;
    logic   [3:0]   dma_request;
    logic   [3:0]   dma_acknowledge_n;
    logic           address_enable_n;
    logic           terminal_count_n;
    // Peripherals
    logic   [2:0]   timer_counter_out;
    logic           speaker_out;
    logic   [7:0]   port_a_out;
    logic           port_a_io;
    logic   [7:0]   port_b_in;
    logic   [7:0]   port_b_out;
    logic           port_b_io;
    logic   [7:0]   port_c_in;
    logic   [7:0]   port_c_out;
    logic   [7:0]   port_c_io;
    logic           ps2_clock;
    logic           ps2_data;
    logic           ps2_clock_out;
    logic           ps2_data_out;
    logic           ps2_mouseclk_in;
    logic           ps2_mousedat_in;
    logic           ps2_mouseclk_out;
    logic           ps2_mousedat_out;
    logic   [4:0]   joy_opts;
    logic   [13:0]  joy0;
    logic   [13:0]  joy1;
    logic   [15:0]  joya0;
    logic   [15:0]  joya1;
    logic   [15:0]  jtopl2_snd_e;
    logic   [1:0]   opl2_io;
    logic           cms_en;
    logic   [15:0]  o_cms_l;
    logic   [15:0]  o_cms_r;
    logic           enable_tvga;
    logic           video_reset;
    logic           video_h_sync;
    logic           video_v_sync;
    logic   [3:0]   video_r;
    logic   [3:0]   video_g;
    logic   [3:0]   video_b;
    logic           enable_sdram;
    logic           initilized_sdram;
    logic           cga_scandouble_en;
    logic   [10:0]  tandy_snd_e;
    logic           tandy_16_gfx;
    logic           tandy_color_16;
    logic           clk_uart;
    logic           uart2_rx;
    logic           uart2_tx;
    logic           uart2_cts_n;
    logic           uart2_dcd_n;
    logic           uart2_dsr_n;
    logic           uart2_rts_n;
    logic           uart2_dtr_n;
    logic   [12:0]  sdram_address;
    logic           sdram_cke;
    logic           sdram_cs;
    logic           sdram_ras;
    logic           sdram_cas;
    logic           sdram_we;
    logic   [1:0]   sdram_ba;
    logic   [15:0]  sdram_dq_in;
    logic   [15:0]  sdram_dq_out;
    logic           sdram_dq_io;
    logic           sdram_ldqm;
    logic           sdram_udqm;
    logic           ems_enabled;
    logic   [1:0]   ems_address;
    logic   [2:0]   bios_protect_flag;
    logic   [1:0]   use_mmc;
    logic           spi_clk;
    logic           spi_cs;
    logic           spi_mosi;
    logic           spi_miso;
    logic   [15:0]  mgmt_address;
    logic           mgmt_read;
    logic   [15:0]  mgmt_readdata;
    logic           mgmt_write;
    logic   [15:0]  mgmt_writedata;
    logic   [1:0]   floppy_wp;
    logic   [1:0]   fdd_present;
    logic   [1:0]   fdd_request;
    logic   [2:0]   ide0_request;
    logic   [7:0]   xtctl;
    logic           enable_a000h;
    logic           wait_count_clk_en;
    logic   [1:0]   ram_read_wait_cycle;
    logic   [1:0]   ram_write_wait_cycle;
    logic           pause_core;
    logic   [3:0]   crt_h_offset;
    logic   [2:0]   crt_v_offset;
    logic   [2:0]   vsync_width_osd;
    logic   [2:0]   hsync_width_osd;

    CHIPSET u_CHIPSET (.*);

    defparam u_CHIPSET.u_RAM.u_KFSDRAM.sdram_init_wait = 16'd10;

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        cpu_address         = 20'h00000;
        #(`TB_CYCLE / 4);
        cpu_address         = 20'h00000;
        #(`TB_CYCLE * 0);
        //#(`TB_CYCLE / 2);
        sdram_reset         = 1'b0;
        cpu_address         = 20'h00000;
        cpu_data_bus        = 8'h00;
        processor_status    = 3'b111;
        processor_lock_n    = 1'b1;
        composite           = 1'b0;
        address_ext         = 20'hFFFFF;
        data_bus_ext        = 8'hFF;
        io_channel_check    = 1'b0;
        io_channel_ready    = 1'b1;
        interrupt_request   = 8'b00000000;
        io_read_n_ext       = 1'b1;
        io_write_n_ext      = 1'b1;
        memory_read_n_ext   = 1'b1;
        memory_write_n_ext  = 1'b1;
        ext_access_request  = 1'b0;
        dma_request         = 4'b0000;
        port_b_in           = 8'b00000000;
        port_c_in           = 8'b00000000;
        ps2_clock           = 1'b1;
        ps2_data            = 1'b1;
        ps2_mouseclk_in     = 1'b1;
        ps2_mousedat_in     = 1'b1;
        joy_opts            = 5'b00000;
        joy0                = 14'h0000;
        joy1                = 14'h0000;
        joya0               = 16'h0000;
        joya1               = 16'h0000;
        opl2_io             = 2'b00;
        cms_en              = 1'b0;
        enable_tvga         = 1'b1;
        video_reset         = 1'b1;
        enable_sdram        = 1'b1;
        cga_scandouble_en   = 1'b0;
        uart2_rx            = 1'b1;
        uart2_cts_n         = 1'b1;
        uart2_dcd_n         = 1'b1;
        uart2_dsr_n         = 1'b1;
        sdram_dq_in         = 16'hAAAA;
        ems_enabled         = 1'b0;
        ems_address         = 2'b00;
        bios_protect_flag   = 3'b000;
        use_mmc             = 2'b00;
        spi_miso            = 1'b1;
        mgmt_address        = 16'h0000;
        mgmt_read           = 1'b0;
        mgmt_write          = 1'b0;
        mgmt_writedata      = 16'h0000;
        floppy_wp           = 2'b00;
        enable_a000h        = 1'b0;
        wait_count_clk_en   = 1'b0;
        ram_read_wait_cycle = 2'b00;
        ram_write_wait_cycle = 2'b00;
        crt_h_offset        = 4'h0;
        crt_v_offset        = 3'h0;
        vsync_width_osd     = 3'h0;
        hsync_width_osd     = 3'h0;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Task : Interrupt Acknowledge
    //
    task TASK_INTERRUPT_ACKNOWLEDGE();
    begin
        #(`TB_CYCLE * 0);
        processor_status    = 3'b000;
        #(`TB_CYCLE * 4);
        processor_status    = 3'b111;
        #(`TB_CYCLE * 2);
        processor_status    = 3'b000;
        #(`TB_CYCLE * 4);
        processor_status    = 3'b111;
        #(`TB_CYCLE * 2);
    end
    endtask

    //
    // Task : Read I/O Port
    //
    task TASK_READ_IO_PORT(input [19:0] addr);
    begin
        #(`TB_CYCLE * 0);
        cpu_address         = addr;
        processor_status    = 3'b001;
        #(`TB_CYCLE * 4);
        processor_status    = 3'b111;
        #(`TB_CYCLE * 1);
        cpu_address         = 20'h00000;
        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Task : Write I/O Port
    //
    task TASK_WRITE_IO_PORT(input [19:0] addr, input [7:0] data);
    begin
        #(`TB_CYCLE * 0);
        cpu_address         = addr;
        cpu_data_bus        = data;
        processor_status    = 3'b010;
        #(`TB_CYCLE * 4);
       processor_status    = 3'b111;
        #(`TB_CYCLE * 1);
        cpu_address         = 20'h00000;
        cpu_data_bus        = 8'h00;
        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Task : Halt
    //
    task TASK_HALT();
    begin
        #(`TB_CYCLE * 0);
        processor_status    = 3'b011;
        #(`TB_CYCLE * 4);
        processor_status    = 3'b111;
        #(`TB_CYCLE * 2);
    end
    endtask

    //
    // Task : Code Access
    //
    task TASK_CODE_ACCESS(input [19:0] addr);
    begin
        #(`TB_CYCLE * 0);
        cpu_address         = addr;
        processor_status    = 3'b100;
        #(`TB_CYCLE * 4);
        processor_status    = 3'b111;
        #(`TB_CYCLE * 1);
        cpu_address         = 20'h00000;
        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Task : Read Memory
    //
    task TASK_READ_MEMORY(input [19:0] addr);
    begin
        #(`TB_CYCLE * 0);
        cpu_address         = addr;
        processor_status    = 3'b101;
        #(`TB_CYCLE * 4);
        processor_status    = 3'b111;
        #(`TB_CYCLE * 1);
        cpu_address         = 20'h00000;
        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Task : Write I/O Port
    //
    task TASK_WRITE_MEMORY(input [19:0] addr, input [7:0] data);
    begin
        #(`TB_CYCLE * 0);
        cpu_address         = addr;
        cpu_data_bus        = data;
        processor_status    = 3'b110;
        #(`TB_CYCLE * 4);
        processor_status    = 3'b111;
        #(`TB_CYCLE * 1);
        cpu_address         = 20'h00000;
        cpu_data_bus        = 8'h00;
        #(`TB_CYCLE * 1);
    end
    endtask

    task TASK_EXPECT_TRUE(input [8*80-1:0] label, input condition);
    begin
        if (!condition) begin
            $display("FAIL %0s at cycle %0d", label, tb_cycle_counter);
            tb_failures = tb_failures + 1;
        end
    end
    endtask

`ifdef EGA_CHIPSET_SMOKE
    task TASK_WAIT_EGA_DISPLAY(input integer max_cycles);
        integer i;
        reg found_display;
        reg found_fetch;
        reg found_rgb;
    begin
        found_display = 1'b0;
        found_fetch = 1'b0;
        found_rgb = 1'b0;

        for (i = 0; i < max_cycles; i = i + 1) begin
            #(`TB_CYCLE * 1);
            found_display = found_display | u_CHIPSET.u_PERIPHERALS.ega_display_sel_cga;
            found_fetch = found_fetch | u_CHIPSET.u_PERIPHERALS.EGA_FETCH_EN;
            found_rgb = found_rgb | (|{VGA_R, VGA_G, VGA_B});
        end

        TASK_EXPECT_TRUE("EGA display path became active", found_display);
        TASK_EXPECT_TRUE("EGA generated at least one fetch", found_fetch);
        TASK_EXPECT_TRUE("EGA drove non-zero RGB", found_rgb);
    end
    endtask

    task TASK_EGA_CHIPSET_SMOKE();
    begin
        $display("***** INTEGRATED EGA SMOKE ***** at %d", tb_cycle_counter);
        #(`TB_CYCLE * 8);

        // Minimal graphics setup: map all planes, select graphics mode, and
        // use the A0000h aperture before writing a visible planar pattern.
        TASK_WRITE_IO_PORT(20'h003C4, 8'h02);
        TASK_WRITE_IO_PORT(20'h003C5, 8'h0F);
        TASK_WRITE_IO_PORT(20'h003CE, 8'h05);
        TASK_WRITE_IO_PORT(20'h003CF, 8'h00);
        TASK_WRITE_IO_PORT(20'h003CE, 8'h06);
        TASK_WRITE_IO_PORT(20'h003CF, 8'h05);
        TASK_WRITE_IO_PORT(20'h003DA, 8'h00);
        TASK_WRITE_IO_PORT(20'h003C0, 8'h20);

        TASK_WRITE_MEMORY(20'hA0000, 8'hFF);
        TASK_WRITE_MEMORY(20'hA0001, 8'h81);
        TASK_WRITE_MEMORY(20'hA0002, 8'h42);
        TASK_READ_MEMORY(20'hA0000);

        TASK_WAIT_EGA_DISPLAY(4096);
        TASK_EXPECT_TRUE(
            "EGA memory cycles do not hold processor_ready low",
            processor_ready
        );
    end
    endtask
`endif

    //
    // Task : Send keybord Serial
    //
    task TASK_SEND_KEYBORD_SERIAL(input [10:0] data);
    begin
        #(`TB_CYCLE * 0);
        ps2_clock  = 1'b1;
        ps2_data   = 1'b1;
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b1;
        ps2_data   = data[10];
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b1;
        ps2_data   = data[9];
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b1;
        ps2_data   = data[8];
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b1;
        ps2_data   = data[7];
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b1;
        ps2_data   = data[6];
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b1;
        ps2_data   = data[5];
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b1;
        ps2_data   = data[4];
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b1;
        ps2_data   = data[3];
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b1;
        ps2_data   = data[2];
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b1;
        ps2_data   = data[1];
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b1;
        ps2_data   = data[0];
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        ps2_clock  = 1'b1;
        ps2_data   = 1'b1;
        #(`TB_CYCLE * 1);
    end
    endtask


    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        $display("***** BUS CONTROL(8288) TEST ***** at %d", tb_cycle_counter);
        TASK_READ_IO_PORT(20'h12345);
        TASK_WRITE_IO_PORT(20'h6789A, 8'hBC);
        TASK_HALT();
        TASK_CODE_ACCESS(20'hDEF01);
        TASK_READ_MEMORY(20'h23456);
        TASK_WRITE_MEMORY(20'h789AB, 8'hCD);

        $display("***** ACCESS TO PPI CHIP(8255) ***** at %d", tb_cycle_counter);
        // 060-063
        TASK_WRITE_IO_PORT(20'h00063, 8'b10011001);
        TASK_WRITE_IO_PORT(20'h00061, 8'b01010101);
        port_c_in   = 8'b11001100;
        TASK_READ_IO_PORT(20'h00062);

        $display("***** ACCESS TO TIMER CHIP(8253) ***** at %d", tb_cycle_counter);
        // 040-043
        // SC=1, RL1,RL0=LSB, M=MODE3, BCD=binary
        TASK_WRITE_IO_PORT(20'h00043, {2'b01, 2'b01, 3'b011, 1'b0});
        // Counter=2
        TASK_WRITE_IO_PORT(20'h00041, 8'h05);
        #(`TB_CYCLE * 3);
        TASK_READ_IO_PORT(20'h00041);


        $display("***** ACCESS TO INTERRUPT CHIP(8259) ***** at %d", tb_cycle_counter);
        // 020-021
        // ICW1
        TASK_WRITE_IO_PORT(20'h00020, 8'b00010111);
        // ICW2
        TASK_WRITE_IO_PORT(20'h00021, 8'b01100000);
        // ICW4
        TASK_WRITE_IO_PORT(20'h00021, 8'b00001111);
        // OCW1
        TASK_WRITE_IO_PORT(20'h00021, 8'b00000000);
        // OCW3
        TASK_WRITE_IO_PORT(20'h00020, 8'b00001000);
        interrupt_request   = 8'b00000100;
        #(`TB_CYCLE * 1);
        interrupt_request   = 8'b00000000;
        #(`TB_CYCLE * 1);
        TASK_INTERRUPT_ACKNOWLEDGE();
        interrupt_request   = 8'b00001000;
        #(`TB_CYCLE * 2);
        interrupt_request   = 8'b00000000;
        #(`TB_CYCLE * 1);
        TASK_INTERRUPT_ACKNOWLEDGE();


        $display("***** ACCESS TO DMA CHIP(8237) ***** at %d", tb_cycle_counter);
        // 080-083 (Page)
        TASK_WRITE_IO_PORT(20'h00083, 8'h01);   // DMA1
        TASK_WRITE_IO_PORT(20'h00081, 8'h02);   // DMA2
        TASK_WRITE_IO_PORT(20'h00082, 8'h03);   // DMA3
        // 000-00F
        // Command
        TASK_WRITE_IO_PORT(20'h00008, 8'b00000000);
        // Mode
        TASK_WRITE_IO_PORT(20'h0000B, 8'b01000101); // DMA1 Write Single
        TASK_WRITE_IO_PORT(20'h0000B, 8'b01001010); // DMA2 Read  Single
        TASK_WRITE_IO_PORT(20'h0000B, 8'b01000011); // DMA3 Verify Single
        // Address
        TASK_WRITE_IO_PORT(20'h0000C, 8'h00);
        TASK_WRITE_IO_PORT(20'h00002, 8'h00); // DMA1 L
        TASK_WRITE_IO_PORT(20'h00002, 8'h10); // DMA1 H
        TASK_WRITE_IO_PORT(20'h00004, 8'h01); // DMA2 L
        TASK_WRITE_IO_PORT(20'h00004, 8'h20); // DMA2 H
        TASK_WRITE_IO_PORT(20'h00006, 8'h02); // DMA3 L
        TASK_WRITE_IO_PORT(20'h00006, 8'h30); // DMA3 H
        // Count
        TASK_WRITE_IO_PORT(20'h00003, 8'h01); // DMA1 L
        TASK_WRITE_IO_PORT(20'h00003, 8'h10); // DMA1 H
        TASK_WRITE_IO_PORT(20'h00005, 8'h01); // DMA2 L
        TASK_WRITE_IO_PORT(20'h00005, 8'h20); // DMA2 H
        TASK_WRITE_IO_PORT(20'h00007, 8'h00); // DMA3 L
        TASK_WRITE_IO_PORT(20'h00007, 8'h00); // DMA3 H
        // Mask
        TASK_WRITE_IO_PORT(20'h0000F, 8'b00000001);

        dma_request         = 4'b0010;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b0000;
        #(`TB_CYCLE * 12);

        dma_request         = 4'b0100;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b0000;
        #(`TB_CYCLE * 12);

        dma_request         = 4'b1000;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b0000;
        #(`TB_CYCLE * 12);

        // Read Address
        TASK_READ_IO_PORT(20'h0000C);
        TASK_READ_IO_PORT(20'h00002); // DMA1 L
        TASK_READ_IO_PORT(20'h00002); // DMA1 H
        TASK_READ_IO_PORT(20'h00004); // DMA2 L
        TASK_READ_IO_PORT(20'h00004); // DMA2 H
        TASK_READ_IO_PORT(20'h00006); // DMA3 L
        TASK_READ_IO_PORT(20'h00006); // DMA3 H

        // Read Count
        TASK_READ_IO_PORT(20'h00003); // DMA1 L
        TASK_READ_IO_PORT(20'h00003); // DMA1 H
        TASK_READ_IO_PORT(20'h00005); // DMA2 L
        TASK_READ_IO_PORT(20'h00005); // DMA2 H
        TASK_READ_IO_PORT(20'h00007); // DMA3 L
        TASK_READ_IO_PORT(20'h00007); // DMA3 H

        $display("***** ACCESS TO TVGA CHIP(8237) ***** at %d", tb_cycle_counter);
        // B8000-BBFFF (Memory Address)
        TASK_WRITE_MEMORY(20'hB8000, 8'h01);
        TASK_WRITE_MEMORY(20'hB8001, 8'h02);
        TASK_READ_MEMORY(20'hB8000);
        TASK_READ_MEMORY(20'hB8001);

`ifdef EGA_CHIPSET_SMOKE
        TASK_EGA_CHIPSET_SMOKE();
`endif

        $display("***** KEYBORD INPUT TEST ***** at %d", tb_cycle_counter);
        TASK_SEND_KEYBORD_SERIAL(11'b0_1010_1010_1_1);
        TASK_INTERRUPT_ACKNOWLEDGE();
        TASK_WRITE_IO_PORT(20'h00061, 8'b10000000);
        TASK_WRITE_IO_PORT(20'h00061, 8'b00000000);

        #(`TB_CYCLE * 12);

        if (tb_failures != 0) begin
            $display("***** CHIPSET TB FAILED: %0d failures *****", tb_failures);
            $fatal(1);
        end else begin
            $display("***** CHIPSET TB PASSED *****");
        end

        // End of simulation
`ifdef IVERILOG
        $finish;
`elsif  MODELSIM
        $stop;
`else
        $finish;
`endif
    end
endmodule

