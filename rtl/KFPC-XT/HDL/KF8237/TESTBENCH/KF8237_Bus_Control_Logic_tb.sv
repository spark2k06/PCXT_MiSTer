
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KF8237_Bus_Control_Logic_tm();

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
    //
    logic           chip_select_n;
    logic           io_read_n_in;
    logic           io_write_n_in;
    logic   [3:0]   address_in;
    logic   [7:0]   data_bus_in;

    logic           lock_bus_control;

    logic   [7:0]   internal_data_bus;
    logic           write_command_register;
    logic           write_mode_register;
    logic           write_request_register;
    logic           set_or_reset_mask_register;
    logic           write_mask_register;
    logic   [3:0]   write_base_and_current_address;
    logic   [3:0]   write_base_and_current_word_count;
    logic           clear_byte_pointer;
    logic           master_clear;
    logic           clear_mask_register;
    logic           read_temporary_register;
    logic           read_status_register;
    logic   [3:0]   read_current_address;
    logic   [3:0]   read_current_word_count;

    KF8237_Bus_Control_Logic u_KF8237_Bus_Control_Logic (.*);

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        chip_select_n   = 1'b1;
        io_read_n_in    = 1'b1;
        io_write_n_in   = 1'b1;
        address_in      = 4'b0000;
        data_bus_in     = 8'b00000000;
        lock_bus_control = 1'b0;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Task : Write data
    //
    task TASK_WRITE_DATA(input [3:0] addr, input [7:0] data);
    begin
        #(`TB_CYCLE * 0);
        chip_select_n   = 1'b0;
        io_write_n_in   = 1'b0;
        address_in      = addr;
        data_bus_in     = data;
        #(`TB_CYCLE * 1);
        io_write_n_in   = 1'b1;
        chip_select_n   = 1'b1;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : Read data
    //
    task TASK_READ_DATA(input [3:0] addr);
    begin
        #(`TB_CYCLE * 0);
        chip_select_n   = 1'b0;
        io_read_n_in    = 1'b0;
        address_in      = addr;
        #(`TB_CYCLE * 1);
        io_read_n_in    = 1'b1;
        chip_select_n   = 1'b1;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        TASK_WRITE_DATA(4'b1000, 8'b00000001);
        TASK_WRITE_DATA(4'b1011, 8'b00000011);
        TASK_WRITE_DATA(4'b1001, 8'b00000111);
        TASK_WRITE_DATA(4'b1010, 8'b00001111);
        TASK_WRITE_DATA(4'b1111, 8'b00011111);
        TASK_WRITE_DATA(4'b0000, 8'b00111111);
        TASK_WRITE_DATA(4'b0010, 8'b01111111);
        TASK_WRITE_DATA(4'b0100, 8'b11111111);
        TASK_WRITE_DATA(4'b0110, 8'b11111110);
        TASK_WRITE_DATA(4'b0001, 8'b11111100);
        TASK_WRITE_DATA(4'b0011, 8'b11111000);
        TASK_WRITE_DATA(4'b0101, 8'b11110000);
        TASK_WRITE_DATA(4'b0111, 8'b11100000);

        TASK_WRITE_DATA(4'b1100, 8'b11111111);
        TASK_WRITE_DATA(4'b1101, 8'b11111111);
        TASK_WRITE_DATA(4'b1110, 8'b11111111);

        TASK_READ_DATA(4'b1101);
        TASK_READ_DATA(4'b1000);
        TASK_READ_DATA(4'b0000);
        TASK_READ_DATA(4'b0010);
        TASK_READ_DATA(4'b0100);
        TASK_READ_DATA(4'b0110);
        TASK_READ_DATA(4'b0001);
        TASK_READ_DATA(4'b0011);
        TASK_READ_DATA(4'b0101);
        TASK_READ_DATA(4'b0111);

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

