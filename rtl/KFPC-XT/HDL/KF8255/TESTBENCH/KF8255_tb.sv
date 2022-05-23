
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KF8255_tm();

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

    logic   [7:0]   port_a_in;
    logic   [7:0]   port_a_out;
    logic           port_a_io;

    logic   [7:0]   port_b_in;
    logic   [7:0]   port_b_out;
    logic           port_b_io;

    logic   [7:0]   port_c_in;
    logic   [7:0]   port_c_out;
    logic   [7:0]   port_c_io;

    KF8255 u_KF8255 (.*);

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
        port_a_in       = 8'b00000000;
        port_b_in       = 8'b00000000;
        port_c_in       = 8'b00000000;
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
    // Task : Test mode0 output
    //
    task TASK_MODE_0_OUTPUT();
    begin
        #(`TB_CYCLE * 0);
        // MODE0 OUTPUT
        TASK_WRITE_DATA(2'b11, 8'b10000000);  // Output All
        // Port A
        TASK_WRITE_DATA(2'b00, 8'b00000001);
        TASK_WRITE_DATA(2'b00, 8'b00000011);
        TASK_WRITE_DATA(2'b00, 8'b00000111);
        TASK_WRITE_DATA(2'b00, 8'b00001111);
        TASK_WRITE_DATA(2'b00, 8'b00011111);
        TASK_WRITE_DATA(2'b00, 8'b00111111);
        TASK_WRITE_DATA(2'b00, 8'b01111111);
        TASK_WRITE_DATA(2'b00, 8'b11111111);
        // Port B
        TASK_WRITE_DATA(2'b01, 8'b00000001);
        TASK_WRITE_DATA(2'b01, 8'b00000011);
        TASK_WRITE_DATA(2'b01, 8'b00000111);
        TASK_WRITE_DATA(2'b01, 8'b00001111);
        TASK_WRITE_DATA(2'b01, 8'b00011111);
        TASK_WRITE_DATA(2'b01, 8'b00111111);
        TASK_WRITE_DATA(2'b01, 8'b01111111);
        TASK_WRITE_DATA(2'b01, 8'b11111111);
        // Port C
        TASK_WRITE_DATA(2'b10, 8'b00000001);
        TASK_WRITE_DATA(2'b10, 8'b00000011);
        TASK_WRITE_DATA(2'b10, 8'b00000111);
        TASK_WRITE_DATA(2'b10, 8'b00001111);
        TASK_WRITE_DATA(2'b10, 8'b00011111);
        TASK_WRITE_DATA(2'b10, 8'b00111111);
        TASK_WRITE_DATA(2'b10, 8'b01111111);
        TASK_WRITE_DATA(2'b10, 8'b11111111);
        // Port C (bit reset)
        TASK_WRITE_DATA(2'b11, 8'b00000000);
        TASK_WRITE_DATA(2'b11, 8'b00000010);
        TASK_WRITE_DATA(2'b11, 8'b00000100);
        TASK_WRITE_DATA(2'b11, 8'b00000110);
        TASK_WRITE_DATA(2'b11, 8'b00001000);
        TASK_WRITE_DATA(2'b11, 8'b00001010);
        TASK_WRITE_DATA(2'b11, 8'b00001100);
        TASK_WRITE_DATA(2'b11, 8'b00001110);
        // Port C (bit set)
        TASK_WRITE_DATA(2'b11, 8'b00000001);
        TASK_WRITE_DATA(2'b11, 8'b00000011);
        TASK_WRITE_DATA(2'b11, 8'b00000101);
        TASK_WRITE_DATA(2'b11, 8'b00000111);
        TASK_WRITE_DATA(2'b11, 8'b00001001);
        TASK_WRITE_DATA(2'b11, 8'b00001011);
        TASK_WRITE_DATA(2'b11, 8'b00001101);
        TASK_WRITE_DATA(2'b11, 8'b00001111);

        #(`TB_CYCLE * 5);
    end
    endtask;

    //
    // Task : Test mode 0 input
    //
    task TASK_MODE_0_INPUT();
    begin
        #(`TB_CYCLE * 0);
        // MODE0 INPUT
        // Port A
        TASK_WRITE_DATA(2'b11, 8'b10010000);

        port_a_in = 8'b00000000;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);

        port_a_in = 8'b00000001;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);

        port_a_in = 8'b00000011;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);

        port_a_in = 8'b00000111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);

        port_a_in = 8'b00001111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);

        port_a_in = 8'b00011111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);

        port_a_in = 8'b00111111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);

        port_a_in = 8'b01111111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);

        port_a_in = 8'b11111111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);

        // Port B
        TASK_WRITE_DATA(2'b11, 8'b10010010);

        port_b_in = 8'b00000000;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b01);

        port_b_in = 8'b00000001;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b01);

        port_b_in = 8'b00000011;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b01);

        port_b_in = 8'b00000111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b01);

        port_b_in = 8'b00001111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b01);

        port_b_in = 8'b00011111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b01);

        port_b_in = 8'b00111111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b01);

        port_b_in = 8'b01111111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b01);

        port_b_in = 8'b11111111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b01);

        // Port C(upper)
        TASK_WRITE_DATA(2'b11, 8'b10011010);
        port_c_in = 8'b00010001;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b10);

        port_c_in = 8'b00110011;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b10);

        port_c_in = 8'b01110111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b10);

        port_c_in = 8'b11111111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b10);

        // Port C(lower)
        port_c_in = 8'b00000000;
        TASK_WRITE_DATA(2'b11, 8'b10010011);
        port_c_in = 8'b00010001;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b10);

        port_c_in = 8'b00110011;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b10);

        port_c_in = 8'b01110111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b10);

        port_c_in = 8'b11111111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b10);

        #(`TB_CYCLE * 5);
    end
    endtask;

    //
    // Task : Test mode 1 input
    //
    task TASK_MODE_1_INPUT();
    begin
        #(`TB_CYCLE * 0);
        port_a_in = 8'b00000000;
        port_b_in = 8'b00000000;
        port_c_in = 8'b00000000;
        port_c_in[4] = 1'b1;    // /STBA
        port_c_in[2] = 1'b1;    // /STBB
        #(`TB_CYCLE * 1);

        // MODE 1 INPUT
        // Group A
        TASK_WRITE_DATA(2'b11, 8'b10110000);
        // Disable INTAE
        #(`TB_CYCLE * 1);
        port_a_in = 8'b10101010;
        port_c_in[4] = 1'b0;    // /STB
        #(`TB_CYCLE * 1);
        port_c_in[4] = 1'b1;    // /STB
        port_a_in = 8'b11111111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);

        // Enable INTEA
        TASK_WRITE_DATA(2'b11, 8'b00001001);
        port_a_in = 8'b01010101;
        port_c_in[4] = 1'b0;    // /STB
        #(`TB_CYCLE * 1);
        port_c_in[4] = 1'b1;    // /STB
        port_a_in = 8'b11111111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);

        // Group B
        TASK_WRITE_DATA(2'b11, 8'b10110110);
        #(`TB_CYCLE * 1);
        port_b_in = 8'b10101010;
        port_c_in[2] = 1'b0;    // /STB
        #(`TB_CYCLE * 1);
        port_c_in[2] = 1'b1;    // /STB
        port_b_in = 8'b11111111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b01);

        // Enable INTEB
        TASK_WRITE_DATA(2'b11, 8'b00000101);
        #(`TB_CYCLE * 1);
        port_b_in = 8'b01010101;
        port_c_in[2] = 1'b0;    // /STB
        #(`TB_CYCLE * 1);
        port_c_in[2] = 1'b1;    // /STB
        port_b_in = 8'b11111111;
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b01);

        #(`TB_CYCLE * 5);
    end
    endtask;

    //
    // Task : Test mode 1 output
    //
    task TASK_MODE_1_OUTPUT();
    begin
        #(`TB_CYCLE * 0);
        port_a_in = 8'b00000000;
        port_b_in = 8'b00000000;
        port_c_in = 8'b00000000;
        port_c_in[6] = 1'b1;    // /ACKA
        port_c_in[2] = 1'b1;    // /ACKB
        #(`TB_CYCLE * 1);

        // MODE 1 OUTPUT
        // Group A
        TASK_WRITE_DATA(2'b11, 8'b10100110);
        #(`TB_CYCLE * 1);
        TASK_WRITE_DATA(2'b00, 8'b01010101);
        #(`TB_CYCLE * 1);
        port_c_in[6] = 1'b0;    // /ACK
        #(`TB_CYCLE * 1);
        port_c_in[6] = 1'b1;    // /ACK
        #(`TB_CYCLE * 1);

        // Enable INTEA
        TASK_WRITE_DATA(2'b11, 8'b00001101);
        TASK_WRITE_DATA(2'b00, 8'b10101010);
        #(`TB_CYCLE * 1);
        port_c_in[6] = 1'b0;    // /ACK
        #(`TB_CYCLE * 1);
        port_c_in[6] = 1'b1;    // /ACK
        #(`TB_CYCLE * 1);

        // Group B
        TASK_WRITE_DATA(2'b11, 8'b10100100);
        #(`TB_CYCLE * 1);
        TASK_WRITE_DATA(2'b01, 8'b01010101);
        #(`TB_CYCLE * 1);
        port_c_in[2] = 1'b0;    // /ACK
        #(`TB_CYCLE * 1);
        port_c_in[2] = 1'b1;    // /ACK
        #(`TB_CYCLE * 1);

        // Enable INTEB
        TASK_WRITE_DATA(2'b11, 8'b00000101);
        TASK_WRITE_DATA(2'b01, 8'b10101010);
        #(`TB_CYCLE * 1);
        port_c_in[2] = 1'b0;    // /ACK
        #(`TB_CYCLE * 1);
        port_c_in[2] = 1'b1;    // /ACK
        #(`TB_CYCLE * 1);

        #(`TB_CYCLE * 5);
    end
    endtask;

    //
    // Task : Test mode 2
    //
    task TASK_MODE_2();
    begin
        #(`TB_CYCLE * 0);
        port_a_in = 8'b00000000;
        port_b_in = 8'b00000000;
        port_c_in = 8'b00000000;
        port_c_in[4] = 1'b1;    // /STBA
        port_c_in[6] = 1'b1;    // /ACKA
        #(`TB_CYCLE * 1);

        // MODE 2
        TASK_WRITE_DATA(2'b11, 8'b11000100);
        TASK_WRITE_DATA(2'b00, 8'b01010101);
        #(`TB_CYCLE * 1);
        port_a_in = 8'b10101010;
        port_c_in[4] = 1'b0;    // /STBA
        #(`TB_CYCLE * 1);
        port_a_in = 8'b00000000;
        port_c_in[4] = 1'b1;    // /STBA
        #(`TB_CYCLE * 1);
        port_c_in[6] = 1'b0;    // /ACKA
        #(`TB_CYCLE * 1);
        port_c_in[6] = 1'b1;    // /ACKA
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 1);

        // Enable INTE1
        TASK_WRITE_DATA(2'b11, 8'b00001101);

        TASK_WRITE_DATA(2'b00, 8'b10101010);
        #(`TB_CYCLE * 1);
        port_a_in = 8'b01010101;
        port_c_in[4] = 1'b0;    // /STBA
        #(`TB_CYCLE * 1);
        port_a_in = 8'b00000000;
        port_c_in[4] = 1'b1;    // /STBA
        #(`TB_CYCLE * 1);
        port_c_in[6] = 1'b0;    // /ACKA
        #(`TB_CYCLE * 1);
        port_c_in[6] = 1'b1;    // /ACKA
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 1);

        // Disable INTE1
        TASK_WRITE_DATA(2'b11, 8'b00001100);
        // Enable  INTE2
        TASK_WRITE_DATA(2'b11, 8'b00001001);

        TASK_WRITE_DATA(2'b00, 8'b11001100);
        #(`TB_CYCLE * 1);
        port_a_in = 8'b01010101;
        port_c_in[4] = 1'b0;    // /STBA
        #(`TB_CYCLE * 1);
        port_a_in = 8'b00000000;
        port_c_in[4] = 1'b1;    // /STBA
        #(`TB_CYCLE * 1);
        port_c_in[6] = 1'b0;    // /ACKA
        #(`TB_CYCLE * 1);
        port_c_in[6] = 1'b1;    // /ACKA
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 1);

        // Enable INTE1
        TASK_WRITE_DATA(2'b11, 8'b00001101);

        TASK_WRITE_DATA(2'b00, 8'b00110011);
        #(`TB_CYCLE * 1);
        port_a_in = 8'b01010101;
        port_c_in[4] = 1'b0;    // /STBA
        #(`TB_CYCLE * 1);
        port_a_in = 8'b00000000;
        port_c_in[4] = 1'b1;    // /STBA
        #(`TB_CYCLE * 1);
        port_c_in[6] = 1'b0;    // /ACKA
        #(`TB_CYCLE * 1);
        port_c_in[6] = 1'b1;    // /ACKA
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(2'b00);
        #(`TB_CYCLE * 1);

        #(`TB_CYCLE * 5);
    end
    endtask;

    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        TASK_MODE_0_OUTPUT();
        TASK_MODE_0_INPUT();
        TASK_MODE_1_INPUT();
        TASK_MODE_1_OUTPUT();
        TASK_MODE_2();

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

