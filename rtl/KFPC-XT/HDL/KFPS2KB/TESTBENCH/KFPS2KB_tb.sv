
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KFPS2KB_tm();

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
    logic           device_clock;
    logic           device_data;

    logic           irq;
    logic   [7:0]   keycode;
    logic           clear_keycode;

    KFPS2KB #(.over_time (16'd6)
    ) u_KFPS2KB (.*);


    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        device_clock  = 1'b1;
        device_data   = 1'b1;
        clear_keycode = 1'b0;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Task : Send Serial
    //
    task TASK_SEND_SERIAL(input [10:0] data);
    begin
        #(`TB_CYCLE * 0);
        device_clock  = 1'b1;
        device_data   = 1'b1;
        clear_keycode = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[10];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[9];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[8];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[7];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[6];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[5];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[4];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[3];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[2];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[1];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[0];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = 1'b1;
        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Task : TEST TIMEOUUT
    //
    task TASK_TEST_TIMEOUT(input [10:0] data);
    begin
        #(`TB_CYCLE * 0);
        device_clock  = 1'b1;
        device_data   = 1'b1;
        clear_keycode = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[10];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[9];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[8];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[7];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        device_data   = data[6];
        #(`TB_CYCLE * 3);
        device_clock  = 1'b0;
        #(`TB_CYCLE * 3);
        device_clock  = 1'b1;
        #(`TB_CYCLE * 6);
    end
    endtask


    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        // Make code
        TASK_SEND_SERIAL(11'b0_1010_1010_1_1);
        #(`TB_CYCLE * 10);

        clear_keycode = 1'b1;
        #(`TB_CYCLE * 1);
        clear_keycode = 1'b0;

        // Break code
        TASK_SEND_SERIAL(11'b0_0000_1111_1_1);
        #(`TB_CYCLE * 1);
        TASK_SEND_SERIAL(11'b0_0000_1000_0_1);
        #(`TB_CYCLE * 10);

        clear_keycode = 1'b1;
        #(`TB_CYCLE * 1);
        clear_keycode = 1'b0;

        // Parity error
        TASK_SEND_SERIAL(11'b0_0101_0101_0_1);
        #(`TB_CYCLE * 10);

        clear_keycode = 1'b1;
        #(`TB_CYCLE * 1);
        clear_keycode = 1'b0;

        // Buffer overrun
        TASK_SEND_SERIAL(11'b0_1111_0000_1_1);
        TASK_SEND_SERIAL(11'b0_0000_1111_1_1);

        clear_keycode = 1'b1;
        #(`TB_CYCLE * 1);
        clear_keycode = 1'b0;

        // Test timeout
        TASK_TEST_TIMEOUT(11'b0_0101_0101_0_1);

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

