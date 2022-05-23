
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
    initial clock = 1'b0;
    initial sdram_clock = 1'b0;
    always #(`TB_CYCLE / 2) clock = ~clock;

    assign video_clock = clock;

    always #(`TB_SDRAM_CYCLE/ 2) sdram_clock = ~sdram_clock;

    //
    // Generate reset
    //
    logic reset;
    initial begin
        reset = 1'b1;
            # (`TB_CYCLE * 10)
        reset = 1'b0;
    end

    //
    // Cycle counter
    //
    logic   [31:0]  tb_cycle_counter;
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
    logic           enable_tvga;
    logic           video_reset;
    logic           video_h_sync;
    logic           video_v_sync;
    logic   [3:0]   video_r;
    logic   [3:0]   video_g;
    logic   [3:0]   video_b;
    logic           enable_sdram;
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
        cpu_address         = 20'h00000;
        cpu_data_bus        = 8'h00;
        processor_status    = 3'b111;
        processor_lock_n    = 1'b1;
        address_ext         = 20'hFFFFF;
        data_bus_ext        = 8'hFF;
        io_channel_check    = 1'b0;
        io_channel_ready    = 1'b1;
        interrupt_request   = 8'b00000000;
        io_read_n_ext       = 1'b1;
        io_write_n_ext      = 1'b1;
        memory_read_n_ext   = 1'b1;
        memory_write_n_ext  = 1'b1;
        dma_request         = 4'b0000;
        port_b_in           = 8'b00000000;
        port_c_in           = 8'b00000000;
        ps2_clock           = 1'b1;
        ps2_data            = 1'b1;
        enable_tvga         = 1'b1;
        video_reset         = 1'b1;
        enable_sdram        = 1'b1;
        sdram_dq_in         = 16'hAAAA;
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
    endtask;

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
    endtask;

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
    endtask;

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
    endtask;

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
    endtask;

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
    endtask;

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
    endtask;

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

        $display("***** KEYBORD INPUT TEST ***** at %d", tb_cycle_counter);
        TASK_SEND_KEYBORD_SERIAL(11'b0_1010_1010_1_1);
        TASK_INTERRUPT_ACKNOWLEDGE();
        TASK_WRITE_IO_PORT(20'h00061, 8'b10000000);
        TASK_WRITE_IO_PORT(20'h00061, 8'b00000000);

        #(`TB_CYCLE * 12);

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

