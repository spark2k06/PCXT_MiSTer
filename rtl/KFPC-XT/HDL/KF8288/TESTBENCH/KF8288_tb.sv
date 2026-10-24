
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KF8288_tb();

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
    initial clock = 1'b1;
    always #(`TB_CYCLE / 2) clock = ~clock;

    // The module runs on a system clock twice as fast as the processor clock
    // `clock`, with enables on the processor clock's edges (as the chipset
    // drives it)
    logic   sysclk;
    initial sysclk = 1'b0;
    always #(`TB_CYCLE / 4) sysclk = ~sysclk;

    logic   cpu_clock_prev;
    logic   cpu_ce_posedge;
    logic   cpu_ce_negedge;
    always_ff @(posedge sysclk) begin
        cpu_clock_prev <= clock;
        cpu_ce_posedge <=  clock & ~cpu_clock_prev;
        cpu_ce_negedge <= ~clock &  cpu_clock_prev;
    end

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
    // Control input
    logic           address_enable_n;
    logic           command_enable;
    logic           io_bus_mode;
    // Processor status
    logic   [2:0]   processor_status;
    // Command bus
    // I/O
    logic           enable_io_command;
    logic           advanced_io_write_command_n;
    logic           io_write_command_n;
    logic           io_read_command_n;
    logic           interrupt_acknowledge_n;
    // Memory
    logic           enable_memory_command;
    logic           advanced_memory_write_command_n;
    logic           memory_write_command_n;
    logic           memory_read_command_n;
    // Control output
    logic           direction_transmit_or_receive_n;
    logic           data_enable;
    logic           master_cascade_enable;
    logic           peripheral_data_enable_n;
    logic           address_latch_enable;

    KF8288 u_KF8288 (.*, .clock(sysclk));


    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        address_enable_n = 1'b0;
        command_enable   = 1'b1;
        io_bus_mode      = 1'b0;
        processor_status = 3'b111;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Task : Machine cycle
    //
    task MACHINE_CYCLE(input [2:0] command);
    begin
        #(`TB_CYCLE * 0);
        command_enable   = 1'b1;
        processor_status = 3'b111;
        #(`TB_CYCLE / 4 * 1);
        processor_status = command;
        #(`TB_CYCLE / 4 * 3);
        #(`TB_CYCLE * 2);
        processor_status = 3'b111;
        #(`TB_CYCLE * 1);
        #(`TB_CYCLE / 4 * 3);
        processor_status = command;
        #(`TB_CYCLE / 4 * 1);
        #(`TB_CYCLE * 2);
        command_enable   = 1'b0;
        #(`TB_CYCLE * 1);
        command_enable   = 1'b1;
        #(`TB_CYCLE * 1);
        processor_status = 3'b111;
        #(`TB_CYCLE * 0);
    end
    endtask

    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        $display("***** TEST /INTA ***** at %d", tb_cycle_counter);
        MACHINE_CYCLE(3'b000);
        #(`TB_CYCLE * 12);

        $display("***** TEST /IORC ***** at %d", tb_cycle_counter);
        MACHINE_CYCLE(3'b001);
        #(`TB_CYCLE * 12);

        $display("***** TEST /IOWC /AIOWC ***** at %d", tb_cycle_counter);
        MACHINE_CYCLE(3'b010);
        #(`TB_CYCLE * 12);

        $display("***** TEST HALT ***** at %d", tb_cycle_counter);
        MACHINE_CYCLE(3'b011);
        #(`TB_CYCLE * 12);

        $display("***** TEST /MRDC ***** at %d", tb_cycle_counter);
        MACHINE_CYCLE(3'b100);
        #(`TB_CYCLE * 12);
        MACHINE_CYCLE(3'b101);
        #(`TB_CYCLE * 12);

        $display("***** TEST /MWTC /AMWC ***** at %d", tb_cycle_counter);
        MACHINE_CYCLE(3'b110);
        #(`TB_CYCLE * 12);

        $display("***** TEST IOB /AEN ***** at %d", tb_cycle_counter);
        #(`TB_CYCLE * 1);
        address_enable_n = 1'b1;
        io_bus_mode      = 1'b0;
        #(`TB_CYCLE * 1);
        address_enable_n = 1'b1;
        io_bus_mode      = 1'b1;

        #(`TB_CYCLE * 1);
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

