
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module READY_TEST_tm();

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
    initial clock = 1'b0;
    always #(`TB_CYCLE / 2) clock = ~clock;

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
    logic           io_read_n;
    logic           io_write_n;
    logic           dma0_acknowledge_n;
    logic           memory_read_n;
    logic           address_enable_n;   // AENBRD
    logic           io_channel_ready;
    logic           dma_wait_n;
    logic           dma_ready;
    logic           processor_ready;

    READY u_READY(.*);

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        io_channel_ready    = 1'b1;
        dma_wait_n          = 1'b1;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Test pattern
    //
    initial begin
        TASK_INIT();
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b0;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b0;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b0;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;


        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b0;
        address_enable_n    = 1'b0;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b0;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b0;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b0;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b0;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b0;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b0;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;

        #(`TB_CYCLE * 12);
        io_channel_ready    = 1'b0;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b0;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 1);
        io_channel_ready    = 1'b1;
        #(`TB_CYCLE * 12);
        io_read_n           = 1'b0;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
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

