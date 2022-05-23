
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KF8253_tm();

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
    logic           chip_select_n;
    logic           read_enable_n;
    logic           write_enable_n;
    logic   [1:0]   address;
    logic   [7:0]   data_bus_in;
    logic   [7:0]   data_bus_out;

    logic           counter_0_clock;
    logic           counter_0_gate;
    logic           counter_0_out;

    logic           counter_1_clock;
    logic           counter_1_gate;
    logic           counter_1_out;

    logic           counter_2_clock;
    logic           counter_2_gate;
    logic           counter_2_out;

    KF8253 u_KF8253 (.*);

    //
    // Generate counters clock
    //
    initial begin
        counter_0_clock = 1'b0;
        # (`TB_CYCLE);

        forever begin
            counter_0_clock = ~counter_0_clock;
            # (`TB_CYCLE * 1);
        end
    end

    initial begin
        counter_1_clock = 1'b0;
        # (`TB_CYCLE);

        forever begin
            counter_1_clock = ~counter_1_clock;
            # (`TB_CYCLE * 2);
        end
    end

    initial begin
        counter_2_clock = 1'b0;
        # (`TB_CYCLE);

        forever begin
            counter_2_clock = ~counter_2_clock;
            # (`TB_CYCLE * 3);
        end
    end

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
        chip_select_n   = 1'b1;
        write_enable_n  = 1'b1;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : Read data
    //
    task TASK_READ_DATA(input [1:0] addr);
    begin
        #(`TB_CYCLE * 0);
        chip_select_n   = 1'b0;
        read_enable_n   = 1'b0;
        address         = addr;
        #(`TB_CYCLE * 1);
        chip_select_n   = 1'b1;
        read_enable_n   = 1'b1;
    end
    endtask;

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        chip_select_n   = 1'b1;
        read_enable_n   = 1'b1;
        write_enable_n  = 1'b1;
        address         = 2'b00;
        data_bus_in     = 8'b00000000;
        counter_0_gate  = 1'b1;
        counter_1_gate  = 1'b1;
        counter_2_gate  = 1'b1;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Task : Mode 0
    //
    task TASK_TEST_MODE_0();
    begin
        #(`TB_CYCLE * 0);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 1);
        // SC=0, RL1,RL0=LSB, M=MODE0, BCD=binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b01, 3'b000, 1'b0});
        // Counter=16
        TASK_WRITE_DATA(2'b00, 8'h0f);
        #(`TB_CYCLE * 2 * 5);
        counter_0_gate = 1'b0;
        #(`TB_CYCLE * 2 * 1);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 2 * 1);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 2 * 6);
         // Counter=16
        TASK_WRITE_DATA(2'b00, 8'h0f);
        #(`TB_CYCLE * 2 * 16);

        #(`TB_CYCLE * 5);
    end
    endtask

    //
    // Task : Mode 1
    //
    task TASK_TEST_MODE_1();
    begin
        #(`TB_CYCLE * 0);
        counter_0_gate = 1'b0;
        #(`TB_CYCLE * 1);
        // SC=0, RL1,RL0=LSB, M=MODE1, BCD=binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b01, 3'b001, 1'b0});
        // Counter=16
        TASK_WRITE_DATA(2'b00, 8'h10);
        #(`TB_CYCLE * 2 * 2);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 2 * 2);
        counter_0_gate = 1'b0;
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 2 * 2);
        counter_0_gate = 1'b1;
        TASK_WRITE_DATA(2'b00, 8'h07);
        #(`TB_CYCLE * 2 * 4);
        #(`TB_CYCLE * 2 * 5);
        counter_0_gate = 1'b0;
        #(`TB_CYCLE * 2 * 2);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 2 * 7);

        #(`TB_CYCLE * 5);
    end
    endtask

    //
    // Task : Mode 2
    //
    task TASK_TEST_MODE_2();
    begin
        #(`TB_CYCLE * 0);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 1);
        // SC=0, RL1,RL0=LSB, M=MODE2, BCD=binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b01, 3'b010, 1'b0});
        // Counter=5
        TASK_WRITE_DATA(2'b00, 8'h05);
        #(`TB_CYCLE * 2 * 10);
        #(`TB_CYCLE * 2 * 3);
        counter_0_gate = 1'b0;
        #(`TB_CYCLE * 2 * 2);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 2 * 3);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 2 * 4);
        #(`TB_CYCLE * 1);
        counter_0_gate = 1'b0;
        #(`TB_CYCLE * 1);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 2 * 3);
        // Counter=3
        TASK_WRITE_DATA(2'b00, 8'h03);
        #(`TB_CYCLE * 2 * 3);
        counter_0_gate = 1'b0;
        #(`TB_CYCLE * 1);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 2 * 3);
        #(`TB_CYCLE * 2 * 3);

        #(`TB_CYCLE * 5);
    end
    endtask

    //
    // Task : Mode 3
    //
    task TASK_TEST_MODE_3();
    begin
        #(`TB_CYCLE * 0);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 1);
        // SC=0, RL1,RL0=LSB, M=MODE3, BCD=binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b01, 3'b011, 1'b0});
        // Counter=5
        TASK_WRITE_DATA(2'b00, 8'h05);
        #(`TB_CYCLE * 2 * 10);
        #(`TB_CYCLE * 2 * 2);
        // Counter=4
        TASK_WRITE_DATA(2'b00, 8'h04);
        #(`TB_CYCLE * 2 * 3);
        counter_0_gate = 1'b0;
        TASK_READ_DATA(2'b00);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 2 * 2);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 2 * 2);

        #(`TB_CYCLE * 5);
    end
    endtask

    //
    // Task : Mode 4
    //
    task TASK_TEST_MODE_4();
    begin
        #(`TB_CYCLE * 0);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 1);
        // SC=0, RL1,RL0=LSB, M=MODE4, BCD=binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b01, 3'b100, 1'b0});
        // Counter=4
        TASK_WRITE_DATA(2'b00, 8'h04);
        #(`TB_CYCLE * 2 * 1);
        counter_0_gate = 1'b0;
        #(`TB_CYCLE * 2 * 1);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 2 * 1);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 2 * 4);
        TASK_WRITE_DATA(2'b00, 8'h05);
        #(`TB_CYCLE * 2 * 2);
        TASK_WRITE_DATA(2'b00, 8'h05);
        #(`TB_CYCLE * 2 * 5);

        #(`TB_CYCLE * 5);
    end
    endtask

    //
    // Task : Mode 5
    //
    task TASK_TEST_MODE_5();
    begin
        #(`TB_CYCLE * 0);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 1);
        // SC=0, RL1,RL0=LSB, M=MODE5, BCD=binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b01, 3'b101, 1'b0});
        // Counter=4
        TASK_WRITE_DATA(2'b00, 8'h04);
        #(`TB_CYCLE * 2 * 1);
        counter_0_gate = 1'b0;
        #(`TB_CYCLE * 1);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 1);
        #(`TB_CYCLE * 2 * 4);
        // Counter=6
        TASK_WRITE_DATA(2'b00, 8'h06);
        counter_0_gate = 1'b0;
        #(`TB_CYCLE * 1);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 1);
        #(`TB_CYCLE * 2 * 4);
        counter_0_gate = 1'b0;
        #(`TB_CYCLE * 1);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 1);
        #(`TB_CYCLE * 2 * 3);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 2 * 3);
        counter_0_gate = 1'b0;
        #(`TB_CYCLE * 1);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 2 * 6);

        #(`TB_CYCLE * 5);
    end
    endtask

    //
    // Task : RL
    //
    task TASK_TEST_RL();
    begin
        #(`TB_CYCLE * 0);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 1);
        // SC=0, RL1,RL0=LSB, M=MODE0, BCD=Binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b01, 3'b000, 1'b0});
        // Counter=0x55(LSB)
        TASK_WRITE_DATA(2'b00, 8'h55);
        // SC=0, RL1,RL0=MSB, M=MODE0, BCD=Binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b10, 3'b000, 1'b0});
        // Counter=0xAA(MSB)
        TASK_WRITE_DATA(2'b00, 8'hAA);
        #(`TB_CYCLE * 2 * 5);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 2 * 5);
        // SC=0, RL1,RL0=LSB, M=MODE0, BCD=Binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b01, 3'b000, 1'b0});
        #(`TB_CYCLE * 2 * 5);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 2 * 5);
        // SC=0, RL1,RL0=LATCH, M=MODE0, BCD=Binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b00, 3'b000, 1'b0});
        #(`TB_CYCLE * 2 * 5);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 1);
        // Counter=0x05(LSB)
        TASK_WRITE_DATA(2'b00, 8'h05);
        #(`TB_CYCLE * 1);
        // SC=0, RL1,RL0=MSB, M=MODE0, BCD=Binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b10, 3'b000, 1'b0});
        #(`TB_CYCLE * 1);
        // Counter=0x02(MSB)
        TASK_WRITE_DATA(2'b00, 8'h02);
        #(`TB_CYCLE * 1);
        // SC=0, RL1,RL0=LATCH, M=MODE0, BCD=Binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b00, 3'b000, 1'b0});
        #(`TB_CYCLE * 2 * 10);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 1);

        // SC=0, RL1,RL0=LSB/MSB, M=MODE0, BCD=Binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b11, 3'b000, 1'b0});
        #(`TB_CYCLE * 1);
        // Counter=0x55(LSB)
        TASK_WRITE_DATA(2'b00, 8'h55);
        #(`TB_CYCLE * 1);
        // Counter=0xAA(MSB)
        TASK_WRITE_DATA(2'b00, 8'hAA);
        #(`TB_CYCLE * 1);
        #(`TB_CYCLE * 2 * 5);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 2 * 5);
        // Counter=0x55(LSB)
        TASK_WRITE_DATA(2'b00, 8'h05);
        #(`TB_CYCLE * 1);
        // Counter=0xAA(MSB)
        TASK_WRITE_DATA(2'b00, 8'hAA);
        #(`TB_CYCLE * 1);
        // SC=0, RL1,RL0=LATCH, M=MODE0, BCD=Binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b00, 3'b000, 1'b0});
        #(`TB_CYCLE * 2 * 6);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);

        // SC=0, RL1,RL0=LSB/MSB, M=MODE4, BCD=binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b11, 3'b100, 1'b0});
        // Counter=0x55(LSB)
        TASK_WRITE_DATA(2'b00, 8'h55);
        #(`TB_CYCLE * 1);
        // Counter=0xAA(MSB)
        TASK_WRITE_DATA(2'b00, 8'hAA);
        #(`TB_CYCLE * 2 * 10);
        // Counter=0x55(LSB)
        TASK_WRITE_DATA(2'b00, 8'h55);
        #(`TB_CYCLE * 1);
        // Counter=0xAA(MSB)
        TASK_WRITE_DATA(2'b00, 8'hAA);
        #(`TB_CYCLE * 2 * 10);

        #(`TB_CYCLE * 5);
    end
    endtask

    //
    // Task : BCD
    //
    task TASK_TEST_BCD();
    begin
        #(`TB_CYCLE * 0);
        counter_0_gate = 1'b1;
        #(`TB_CYCLE * 1);
        // SC=0, RL1,RL0=LSB/MSB, M=MODE0, BCD=BCD
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b11, 3'b000, 1'b1});
        // Counter=10000
        TASK_WRITE_DATA(2'b00, 8'h00);
        TASK_WRITE_DATA(2'b00, 8'h00);
        #(`TB_CYCLE * 2 * 5);
        // Counter=1000
        TASK_WRITE_DATA(2'b00, 8'h00);
        TASK_WRITE_DATA(2'b00, 8'h10);
        #(`TB_CYCLE * 2 * 5);
        // Counter=100
        TASK_WRITE_DATA(2'b00, 8'h00);
        TASK_WRITE_DATA(2'b00, 8'h01);
        #(`TB_CYCLE * 2 * 5);
        // Counter=10
        TASK_WRITE_DATA(2'b00, 8'h10);
        TASK_WRITE_DATA(2'b00, 8'h00);
        #(`TB_CYCLE * 2 * 10);
        // SC=0, RL1,RL0=LSB/MSB, M=MODE0, BCD=BCD
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b11, 3'b111, 1'b1});
        // Couter=5
        TASK_WRITE_DATA(2'b00, 8'h05);
        TASK_WRITE_DATA(2'b00, 8'h00);
        #(`TB_CYCLE * 2 * 10);
        // Couter=5
        TASK_WRITE_DATA(2'b00, 8'h04);
        TASK_WRITE_DATA(2'b00, 8'h00);
        #(`TB_CYCLE * 2 * 10);

        #(`TB_CYCLE * 5);
    end
    endtask

    //
    // Task : OTHER COUNTER
    //
    task TASK_TEST_OTHER_COUNTER();
    begin
        #(`TB_CYCLE * 0);
        #(`TB_CYCLE * 0);
        counter_0_gate = 1'b1;
        counter_1_gate = 1'b1;
        counter_2_gate = 1'b1;
        #(`TB_CYCLE * 1);
        // SC=0, RL1,RL0=LSB, M=MODE0, BCD=Binary
        TASK_WRITE_DATA(2'b11, {2'b00, 2'b01, 3'b000, 1'b0});
        // SC=1, RL1,RL0=LSB, M=MODE0, BCD=Binary
        TASK_WRITE_DATA(2'b11, {2'b01, 2'b01, 3'b000, 1'b0});
        // SC=2, RL1,RL0=LSB, M=MODE0, BCD=Binary
        TASK_WRITE_DATA(2'b11, {2'b10, 2'b01, 3'b000, 1'b0});
        // Counter #0 = 5
        TASK_WRITE_DATA(2'b00, 8'h05);
        // Counter #1 = 5
        TASK_WRITE_DATA(2'b01, 8'h05);
        // Counter #2 = 5
        TASK_WRITE_DATA(2'b10, 8'h05);
        #(`TB_CYCLE * 2 * 30);

        #(`TB_CYCLE * 5);
    end
    endtask

    //
    // Test pattern
    //
    initial begin
        TASK_INIT();
        $display("***** TEST MODE0 ***** at %d", tb_cycle_counter);
        TASK_TEST_MODE_0();
        $display("***** TEST MODE1 ***** at %d", tb_cycle_counter);
        TASK_TEST_MODE_1();
        $display("***** TEST MODE2 ***** at %d", tb_cycle_counter);
        TASK_TEST_MODE_2();
        $display("***** TEST MODE3 ***** at %d", tb_cycle_counter);
        TASK_TEST_MODE_3();
        $display("***** TEST MODE4 ***** at %d", tb_cycle_counter);
        TASK_TEST_MODE_4();
        $display("***** TEST MODE5 ***** at %d", tb_cycle_counter);
        TASK_TEST_MODE_5();
        $display("***** TEST RL    ***** at %d", tb_cycle_counter);
        TASK_TEST_RL();
        $display("***** TEST BCD   ***** at %d", tb_cycle_counter);
        TASK_TEST_BCD();
        $display("***** TEST OTHER ***** at %d", tb_cycle_counter);
        TASK_TEST_OTHER_COUNTER();

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
