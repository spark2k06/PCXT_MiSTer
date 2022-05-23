
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KF8259_Bus_Control_Logic_tm();

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
    logic           read_enable_n;
    logic           write_enable_n;
    logic           address;
    logic   [7:0]   data_bus_in;

    logic   [7:0]   internal_data_bus;
    logic           write_initial_command_word_1;
    logic           write_initial_command_word_2_4;
    logic           write_operation_control_word_1;
    logic           write_operation_control_word_2;
    logic           write_operation_control_word_3;
    logic           read;

    KF8259_Bus_Control_Logic u_KF8259_Bus_Control_Logic (.*);

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        chip_select_n   = 1'b1;
        read_enable_n   = 1'b1;
        write_enable_n  = 1'b1;
        address         = 1'b0;
        data_bus_in     = 8'b00000000;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Task : Write data
    //
    task TASK_WRITE_DATA(input [1:0] addr, input [7:0] data);
    begin
        #(`TB_CYCLE * 0);
        chip_select_n   = 1'b0;
        write_enable_n  = 1'b0;
        address         = addr;
        data_bus_in     = data;
        #(`TB_CYCLE * 1);
        write_enable_n  = 1'b1;
        chip_select_n   = 1'b1;
        #(`TB_CYCLE * 1);
    end
    endtask;


    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        TASK_WRITE_DATA(1'b0, 8'b00010000);
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        TASK_WRITE_DATA(1'b0, 8'b00000000);
        TASK_WRITE_DATA(1'b0, 8'b00001000);
        #(`TB_CYCLE * 1);
        read_enable_n   = 1'b0;
        chip_select_n   = 1'b0;
        #(`TB_CYCLE * 1);
        read_enable_n   = 1'b1;
        chip_select_n   = 1'b1;
        #(`TB_CYCLE * 1);
        read_enable_n   = 1'b0;
        chip_select_n   = 1'b0;
        #(`TB_CYCLE * 1);
        read_enable_n   = 1'b1;
        #(`TB_CYCLE * 1);
        chip_select_n   = 1'b1;
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

