
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KF8259_tm();

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
    logic           address;
    logic   [7:0]   data_bus_in;
    logic   [7:0]   data_bus_out;
    logic           data_bus_io;
    logic   [2:0]   cascade_in;
    logic   [2:0]   cascade_out;
    logic           cascade_io;
    logic           slave_program_n;
    logic           buffer_enable;
    logic           slave_program_or_enable_buffer;
    logic           interrupt_acknowledge_n;
    logic           interrupt_to_cpu;
    logic   [7:0]   interrupt_request;

    KF8259 u_KF8259 (.*);

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        chip_select_n           = 1'b1;
        read_enable_n           = 1'b1;
        write_enable_n          = 1'b1;
        address                 = 1'b0;
        data_bus_in             = 8'b00000000;
        cascade_in              = 3'b000;
        slave_program_n         = 1'b0;
        interrupt_acknowledge_n = 1'b1;
        interrupt_request       = 8'b00000000;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Task : Write data
    //
    task TASK_WRITE_DATA(input addr, input [7:0] data);
    begin
        #(`TB_CYCLE * 0);
        chip_select_n   = 1'b0;
        write_enable_n  = 1'b0;
        address         = addr;
        data_bus_in     = data;
        #(`TB_CYCLE * 1);
        chip_select_n   = 1'b1;
        write_enable_n  = 1'b1;
        address         = 1'b0;
        data_bus_in     = 8'b00000000;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : Read data
    //
    task TASK_READ_DATA(input addr);
    begin
        #(`TB_CYCLE * 0);
        chip_select_n   = 1'b0;
        read_enable_n   = 1'b0;
        address         = addr;
        #(`TB_CYCLE * 1);
        chip_select_n   = 1'b1;
        read_enable_n   = 1'b1;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : Send specific EOI
    //
    task TASK_INTERRUPT_REQUEST(input [7:0] request);
    begin
        #(`TB_CYCLE * 0);
        interrupt_request = request;
        #(`TB_CYCLE * 1);
        interrupt_request = 8'b00000000;
    end
    endtask;

    //
    // Task : Send specific EOI
    //
    task TASK_SEND_SPECIFIC_EOI(input [2:0] int_no);
    begin
        TASK_WRITE_DATA(1'b0, {8'b01100, int_no});
    end
    endtask;

    //
    // Task : Send non specific EOI
    //
    task TASK_SEND_NON_SPECIFIC_EOI();
    begin
        TASK_WRITE_DATA(1'b0, 8'b00100000);
    end
    endtask;

    //
    // Task : Send ack (MCS-80)
    //
    task TASK_SEND_ACK_TO_MCS80();
    begin
        #(`TB_CYCLE * 0);
        interrupt_acknowledge_n = 1'b1;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b0;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b1;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b0;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b1;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b0;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b1;
    end
    endtask;

    //
    // Task : Send ack (MCS-80)
    //
    task TASK_SEND_ACK_TO_MCS80_SLAVE(input [2:0] slave_id);
    begin
        #(`TB_CYCLE * 0);
        interrupt_acknowledge_n = 1'b1;
        cascade_in = 3'b000;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b0;
        #(`TB_CYCLE / 2);
        cascade_in = slave_id;
        #(`TB_CYCLE / 2);
        interrupt_acknowledge_n = 1'b1;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b0;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b1;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b0;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b1;
        cascade_in = 3'b000;
    end
    endtask;

    //
    // Task : Send ack (8086)
    //
    task TASK_SEND_ACK_TO_8086();
    begin
        #(`TB_CYCLE * 0);
        interrupt_acknowledge_n = 1'b1;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b0;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b1;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b0;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b1;
    end
    endtask;

    //
    // Task : Send ack (8086)
    //
    task TASK_SEND_ACK_TO_8086_SLAVE(input [2:0] slave_id);
    begin
        #(`TB_CYCLE * 0);
        interrupt_acknowledge_n = 1'b1;
        cascade_in = 3'b000;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b0;
        #(`TB_CYCLE / 2);
        cascade_in = slave_id;
        #(`TB_CYCLE / 2);
        interrupt_acknowledge_n = 1'b1;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b0;
        #(`TB_CYCLE * 1);
        interrupt_acknowledge_n = 1'b1;
        cascade_in = 3'b000;
    end
    endtask;



    //
    // TASK : MCS80 interrupt test
    //
    task TASK_MCS80_NORMAL_INTERRUPT_TEST();
    begin
        #(`TB_CYCLE * 0);
        $display("***** INTERVAL=4 A15-A5=0b'00000000_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        TASK_INTERRUPT_REQUEST(8'b00000010);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b001);

        TASK_INTERRUPT_REQUEST(8'b00000100);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b010);

        TASK_INTERRUPT_REQUEST(8'b00001000);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b011);

        TASK_INTERRUPT_REQUEST(8'b00010000);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b100);

        TASK_INTERRUPT_REQUEST(8'b00100000);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b101);

        TASK_INTERRUPT_REQUEST(8'b01000000);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b110);

        TASK_INTERRUPT_REQUEST(8'b10000000);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b111);

        $display("***** INTERVAL=4 A15-A5=0b'00000000_001 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00111111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=4 A15-A5=0b'00000000_010 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b01011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=4 A15-A5=0b'00000000_100 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b10011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=4 A15-A5=0b'00000001_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000001);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=4 A15-A5=0b'00000010_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000010);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=4 A15-A5=0b'00000100_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000100);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=4 A15-A5=0b'00001000_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00001000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=4 A15-A5=0b'00010000_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00010000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=4 A15-A5=0b'00100000_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00100000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=4 A15-A5=0b'01000000_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b01000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=4 A15-A5=0b'10000000_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b10000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=8 A15-A5=0b'00000000_000 ***** at %d", tb_cycle_counter);
        #(`TB_CYCLE * 0);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011011);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        TASK_INTERRUPT_REQUEST(8'b00000010);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b001);

        TASK_INTERRUPT_REQUEST(8'b00000100);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b010);

        TASK_INTERRUPT_REQUEST(8'b00001000);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b011);

        TASK_INTERRUPT_REQUEST(8'b00010000);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b100);

        TASK_INTERRUPT_REQUEST(8'b00100000);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b101);

        TASK_INTERRUPT_REQUEST(8'b01000000);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b110);

        TASK_INTERRUPT_REQUEST(8'b10000000);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b111);
        #(`TB_CYCLE * 1);

        $display("***** INTERVAL=8 A15-A5=0b'00000000_010 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b01011011);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=8 A15-A5=0b'00000000_100 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b10011011);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=8 A15-A5=0b'00000001_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011011);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000001);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=8 A15-A5=0b'00000010_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011011);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000010);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=8 A15-A5=0b'00000100_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011011);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000100);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=8 A15-A5=0b'00001000_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011011);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00001000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=8 A15-A5=0b'00010000_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011011);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00010000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=8 A15-A5=0b'00100000_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011011);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00100000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=8 A15-A5=0b'01000000_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011011);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b01000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** INTERVAL=8 A15-A5=0b'10000000_000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011011);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b10000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_SPECIFIC_EOI(3'b000);
        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : 8086 interrupt test
    //
    task TASK_8086_NORMAL_INTERRUPT_TEST();
    begin
        #(`TB_CYCLE * 0);
        $display("***** T7-T3=0b'00000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        TASK_INTERRUPT_REQUEST(8'b00000010);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b001);

        TASK_INTERRUPT_REQUEST(8'b00000100);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b010);

        TASK_INTERRUPT_REQUEST(8'b00001000);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b011);

        TASK_INTERRUPT_REQUEST(8'b00010000);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b100);

        TASK_INTERRUPT_REQUEST(8'b00100000);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b101);

        TASK_INTERRUPT_REQUEST(8'b01000000);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b110);

        TASK_INTERRUPT_REQUEST(8'b10000000);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b111);

        $display("***** T7-T3=0b'00001 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00001000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** T7-T3=0b'00010 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00010000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** T7-T3=0b'00100 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00100000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** T7-T3=0b'01000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b01000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        $display("***** T7-T3=0b'10000 ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b10000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b000);
        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : level torigger test
    //
    task TASK_LEVEL_TORIGGER_TEST();
    begin
        #(`TB_CYCLE * 0);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        interrupt_request = 8'b00000001;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b000);
        #(`TB_CYCLE * 1);
        interrupt_request = 8'b00000000;
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        interrupt_request = 8'b00000010;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b001);
        #(`TB_CYCLE * 1);
        interrupt_request = 8'b00000000;
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b001);

        interrupt_request = 8'b00000100;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b010);
        #(`TB_CYCLE * 1);
        interrupt_request = 8'b00000000;
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b010);

        interrupt_request = 8'b00001000;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b011);
        #(`TB_CYCLE * 1);
        interrupt_request = 8'b00000000;
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b011);

        interrupt_request = 8'b00010000;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b100);
        #(`TB_CYCLE * 1);
        interrupt_request = 8'b00000000;
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b100);

        interrupt_request = 8'b00100000;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b101);
        #(`TB_CYCLE * 1);
        interrupt_request = 8'b00000000;
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b101);

        interrupt_request = 8'b01000000;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b110);
        #(`TB_CYCLE * 1);
        interrupt_request = 8'b00000000;
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b110);

        interrupt_request = 8'b10000000;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b111);
        #(`TB_CYCLE * 1);
        interrupt_request = 8'b00000000;
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b111);
        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : edge torigger test
    //
    task TASK_EDGE_TORIGGER_TEST();
    begin
        #(`TB_CYCLE * 0);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00010111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        interrupt_request = 8'b00000001;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b000);
        #(`TB_CYCLE * 5);

        interrupt_request = 8'b00000010;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b001);
        #(`TB_CYCLE * 5);

        interrupt_request = 8'b00000100;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b010);
        #(`TB_CYCLE * 5);

        interrupt_request = 8'b00001000;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b011);
        #(`TB_CYCLE * 5);

        interrupt_request = 8'b00010000;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b100);
        #(`TB_CYCLE * 5);

        interrupt_request = 8'b00100000;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b101);
        #(`TB_CYCLE * 5);

        interrupt_request = 8'b01000000;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b110);
        #(`TB_CYCLE * 5);

        interrupt_request = 8'b10000000;
        #(`TB_CYCLE * 1);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b111);
        #(`TB_CYCLE * 5);

        interrupt_request = 8'b00000000;
        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : interrupt mask test
    //
    task TASK_INTERRUPT_MASK_TEST();
    begin
        #(`TB_CYCLE * 0);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b11111111);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Can't interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);
        #(`TB_CYCLE * 5);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b11111110);
        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b000);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b11111101);
        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b001);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b11111011);
        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b010);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b11110111);
        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b011);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b11101111);
        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b100);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b11011111);
        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b101);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b10111111);
        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b110);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b01111111);
        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b111);
        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : special task test
    //
    task TASK_SPECIAL_MASK_TEST();
    begin
        #(`TB_CYCLE * 0);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);

        // Interrupt (can't)
        TASK_INTERRUPT_REQUEST(8'b10000000);
        #(`TB_CYCLE * 5);

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b01101000);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000001);

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b111);

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b01001000);

        // Interrupt (can't)
        TASK_INTERRUPT_REQUEST(8'b10000000);
        #(`TB_CYCLE * 5);

        TASK_SEND_SPECIFIC_EOI(3'b000);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b111);

        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : auto-eoi test
    //
    task TASK_AUTO_EOI_TEST();
    begin
        #(`TB_CYCLE * 0);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001111);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);

        // ACK
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);

        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);

        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);

        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);

        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);

        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);

        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);

        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : non special fully nested
    //
    task TASK_NON_SPECTAL_FULLY_NESTED_TEST();
    begin
        #(`TB_CYCLE * 0);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00010000);    // 4
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);
        TASK_INTERRUPT_REQUEST(8'b00100000);    // 5
        TASK_INTERRUPT_REQUEST(8'b00010000);    // 4
        TASK_INTERRUPT_REQUEST(8'b00001000);    // 3
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b011);
        TASK_SEND_SPECIFIC_EOI(3'b100);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b100);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b101);
        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : special fully nested
    //
    task TASK_SPECTAL_FULLY_NESTED_TEST();
    begin
        #(`TB_CYCLE * 0);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00011101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00010000);    // 4
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);
        TASK_INTERRUPT_REQUEST(8'b00100000);    // 5
        TASK_INTERRUPT_REQUEST(8'b00010000);    // 4
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);

        TASK_INTERRUPT_REQUEST(8'b00001000);    // 3
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);

        TASK_SEND_SPECIFIC_EOI(3'b011);
        TASK_SEND_SPECIFIC_EOI(3'b100);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_SPECIFIC_EOI(3'b101);
        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : non specific test
    //
    task TASK_NON_SPECIFIC_EOI_TEST();
    begin
        #(`TB_CYCLE * 0);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();
        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : non specific test
    //
    task TASK_ROTATE_TEST();
    begin
        #(`TB_CYCLE * 0);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        $display("***** specific rotate ***** at %d", tb_cycle_counter);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b11000100);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        $display("***** rotate on non specific eoi ***** at %d", tb_cycle_counter);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b11000111);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00001000);
        TASK_SEND_ACK_TO_8086();
        TASK_WRITE_DATA(1'b0, 8'b10100000);
        TASK_INTERRUPT_REQUEST(8'b11111111);

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        $display("***** rotate in automatic eoi ***** at %d", tb_cycle_counter);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b11000111);
        TASK_WRITE_DATA(1'b0, 8'b10000000);

        // Interrupt
        TASK_INTERRUPT_REQUEST(8'b00000100);
        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_WRITE_DATA(1'b0, 8'b00000000);

        TASK_INTERRUPT_REQUEST(8'b11111111);

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b11000111);
        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : poll command test
    //
    task TASK_POLL_COMMAND_TEST();
    begin
        #(`TB_CYCLE * 0);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        TASK_INTERRUPT_REQUEST(8'b11111111);

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001100);
        TASK_READ_DATA(1'b0);
        TASK_SEND_NON_SPECIFIC_EOI();

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001100);
        TASK_READ_DATA(1'b0);
        TASK_SEND_NON_SPECIFIC_EOI();

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001100);
        TASK_READ_DATA(1'b0);
        TASK_SEND_NON_SPECIFIC_EOI();

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001100);
        TASK_READ_DATA(1'b0);
        TASK_SEND_NON_SPECIFIC_EOI();

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001100);
        TASK_READ_DATA(1'b0);
        TASK_SEND_NON_SPECIFIC_EOI();

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001100);
        TASK_READ_DATA(1'b0);
        TASK_SEND_NON_SPECIFIC_EOI();

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001100);
        TASK_READ_DATA(1'b0);
        TASK_SEND_NON_SPECIFIC_EOI();

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001100);
        TASK_READ_DATA(1'b0);
        TASK_SEND_NON_SPECIFIC_EOI();

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001100);
        TASK_READ_DATA(1'b0);
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_INTERRUPT_REQUEST(8'b10000000);

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001100);
        TASK_READ_DATA(1'b0);

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001100);
        TASK_READ_DATA(1'b0);

        TASK_INTERRUPT_REQUEST(8'b01000000);

        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001100);
        TASK_READ_DATA(1'b0);

        TASK_SEND_NON_SPECIFIC_EOI();
        TASK_SEND_NON_SPECIFIC_EOI();
        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : reading status test
    //
    task TASK_READING_STATUS_TEST();
    begin
        #(`TB_CYCLE * 0);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011111);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001101);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        $display("***** read irr ***** at %d", tb_cycle_counter);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001010);
        TASK_READ_DATA(1'b0);

        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);

        TASK_INTERRUPT_REQUEST(8'b00000001);
        TASK_READ_DATA(1'b0);

        TASK_INTERRUPT_REQUEST(8'b00000010);
        TASK_READ_DATA(1'b0);

        TASK_INTERRUPT_REQUEST(8'b00000100);
        TASK_READ_DATA(1'b0);

        TASK_INTERRUPT_REQUEST(8'b00001000);
        TASK_READ_DATA(1'b0);

        TASK_INTERRUPT_REQUEST(8'b00010000);
        TASK_READ_DATA(1'b0);

        TASK_INTERRUPT_REQUEST(8'b00100000);
        TASK_READ_DATA(1'b0);

        TASK_INTERRUPT_REQUEST(8'b01000000);
        TASK_READ_DATA(1'b0);

        TASK_INTERRUPT_REQUEST(8'b10000000);
        TASK_READ_DATA(1'b0);

        $display("***** read isr ***** at %d", tb_cycle_counter);
        TASK_WRITE_DATA(1'b0, 8'b00001011);

        TASK_READ_DATA(1'b0);

        TASK_SEND_NON_SPECIFIC_EOI();
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(1'b0);

        TASK_SEND_NON_SPECIFIC_EOI();
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(1'b0);

        TASK_SEND_NON_SPECIFIC_EOI();
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(1'b0);

        TASK_SEND_NON_SPECIFIC_EOI();
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(1'b0);

        TASK_SEND_NON_SPECIFIC_EOI();
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(1'b0);

        TASK_SEND_NON_SPECIFIC_EOI();
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(1'b0);

        TASK_SEND_NON_SPECIFIC_EOI();
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(1'b0);

        TASK_SEND_NON_SPECIFIC_EOI();
        TASK_SEND_ACK_TO_8086();
        #(`TB_CYCLE * 1);
        TASK_READ_DATA(1'b0);

        TASK_SEND_NON_SPECIFIC_EOI();
        TASK_READ_DATA(1'b0);

        $display("***** read imr ***** at %d", tb_cycle_counter);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        TASK_READ_DATA(1'b1);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000001);
        TASK_READ_DATA(1'b1);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000010);
        TASK_READ_DATA(1'b1);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000100);
        TASK_READ_DATA(1'b1);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00001000);
        TASK_READ_DATA(1'b1);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00010000);
        TASK_READ_DATA(1'b1);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00100000);
        TASK_READ_DATA(1'b1);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b01000000);
        TASK_READ_DATA(1'b1);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b10000000);
        TASK_READ_DATA(1'b1);

        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);

        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // TASK : cascade mode test
    //
    task TASK_CASCADE_MODE_TEST();
    begin
        #(`TB_CYCLE * 0);
        $display("***** mcs-80 cascade mode (master) ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011101);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW3
        TASK_WRITE_DATA(1'b1, 8'b11111111);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001100);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);

        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_MCS80();
        TASK_SEND_NON_SPECIFIC_EOI();

        $display("***** mcs-80 cascade mode (slave) ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011101);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW3
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001000);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // interrupt
        TASK_INTERRUPT_REQUEST(8'b10000000);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b001);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b010);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b011);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b100);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b101);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b110);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b111);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b000);
        TASK_SEND_NON_SPECIFIC_EOI();
        #(`TB_CYCLE * 1);

        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011101);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW3
        TASK_WRITE_DATA(1'b1, 8'b00000001);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001000);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // interrupt
        TASK_INTERRUPT_REQUEST(8'b01000000);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b000);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b010);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b011);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b100);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b101);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b110);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b111);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b001);
        TASK_SEND_NON_SPECIFIC_EOI();
        #(`TB_CYCLE * 1);

        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011101);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW3
        TASK_WRITE_DATA(1'b1, 8'b00000010);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001000);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // interrupt
        TASK_INTERRUPT_REQUEST(8'b00100000);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b000);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b001);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b011);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b100);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b101);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b110);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b111);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b010);
        TASK_SEND_NON_SPECIFIC_EOI();
        #(`TB_CYCLE * 1);

        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011101);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW3
        TASK_WRITE_DATA(1'b1, 8'b00000011);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001000);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // interrupt
        TASK_INTERRUPT_REQUEST(8'b00010000);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b000);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b001);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b010);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b100);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b101);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b110);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b111);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b011);
        TASK_SEND_NON_SPECIFIC_EOI();
        #(`TB_CYCLE * 1);

        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011101);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW3
        TASK_WRITE_DATA(1'b1, 8'b00000100);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001000);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // interrupt
        TASK_INTERRUPT_REQUEST(8'b00001000);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b000);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b001);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b010);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b011);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b101);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b110);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b111);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b100);
        TASK_SEND_NON_SPECIFIC_EOI();
        #(`TB_CYCLE * 1);

        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011101);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW3
        TASK_WRITE_DATA(1'b1, 8'b00000101);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001000);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // interrupt
        TASK_INTERRUPT_REQUEST(8'b00000100);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b000);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b001);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b010);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b011);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b100);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b110);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b111);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b101);
        TASK_SEND_NON_SPECIFIC_EOI();
        #(`TB_CYCLE * 1);

        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011101);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW3
        TASK_WRITE_DATA(1'b1, 8'b00000110);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001000);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // interrupt
        TASK_INTERRUPT_REQUEST(8'b00000010);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b000);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b001);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b010);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b011);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b100);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b101);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b111);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b110);
        TASK_SEND_NON_SPECIFIC_EOI();
        #(`TB_CYCLE * 1);

        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011101);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW3
        TASK_WRITE_DATA(1'b1, 8'b00000111);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00001000);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        // interrupt
        TASK_INTERRUPT_REQUEST(8'b00000001);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b000);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b001);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b010);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b011);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b100);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b101);
        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b110);

        TASK_SEND_ACK_TO_MCS80_SLAVE(3'b111);
        TASK_SEND_NON_SPECIFIC_EOI();

        #(`TB_CYCLE * 12);
    end
    endtask;

    task TASK_SLAVE_PROGRAM_TEST();
    begin
        #(`TB_CYCLE * 0);

        $display("***** 8086 cascade mode (master) ***** at %d", tb_cycle_counter);
        // ICW1
        TASK_WRITE_DATA(1'b0, 8'b00011101);
        // ICW2
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // ICW3
        TASK_WRITE_DATA(1'b1, 8'b00000111);
        // ICW4
        TASK_WRITE_DATA(1'b1, 8'b00000001);
        // OCW1
        TASK_WRITE_DATA(1'b1, 8'b00000000);
        // OCW3
        TASK_WRITE_DATA(1'b0, 8'b00001000);

        slave_program_n         = 1'b1;

        // interrupt
        TASK_INTERRUPT_REQUEST(8'b11111111);

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        TASK_SEND_ACK_TO_8086();
        TASK_SEND_NON_SPECIFIC_EOI();

        $display("***** 8086 cascade mode (slave) ***** at %d", tb_cycle_counter);

        slave_program_n         = 1'b0;

        // interrupt
        TASK_INTERRUPT_REQUEST(8'b10000000);

        TASK_SEND_ACK_TO_8086_SLAVE(3'b000);
        TASK_SEND_ACK_TO_8086_SLAVE(3'b001);
        TASK_SEND_ACK_TO_8086_SLAVE(3'b010);
        TASK_SEND_ACK_TO_8086_SLAVE(3'b011);
        TASK_SEND_ACK_TO_8086_SLAVE(3'b100);
        TASK_SEND_ACK_TO_8086_SLAVE(3'b101);
        TASK_SEND_ACK_TO_8086_SLAVE(3'b110);
        TASK_SEND_ACK_TO_8086_SLAVE(3'b111);

        TASK_SEND_NON_SPECIFIC_EOI();

        #(`TB_CYCLE * 12);
    end
    endtask;

    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        $display("******************************** ");
        $display("***** TEST MCS80 INTERRUPT ***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_MCS80_NORMAL_INTERRUPT_TEST();

        $display("******************************** ");
        $display("***** TEST 8086 INTERRUPT  ***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_8086_NORMAL_INTERRUPT_TEST();

        $display("******************************** ");
        $display("***** TEST LEVEL TORIGGER  ***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_LEVEL_TORIGGER_TEST();

        $display("******************************** ");
        $display("***** TEST EDGE TORIGGER  ***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_EDGE_TORIGGER_TEST();

        $display("******************************** ");
        $display("***** TEST INTERRUPT MASK ***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_INTERRUPT_MASK_TEST();

        $display("******************************** ");
        $display("***** TEST SPECIAL MASK    ***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_SPECIAL_MASK_TEST();

        $display("******************************** ");
        $display("***** TEST AUTO EOI        ***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_AUTO_EOI_TEST();

        $display("***************************************** ");
        $display("***** TEST NON SPECIAL FULLY NESTED ***** at %d", tb_cycle_counter);
        $display("***************************************** ");
        TASK_NON_SPECTAL_FULLY_NESTED_TEST();

        $display("************************************* ");
        $display("***** TEST SPECIAL FULLY NESTED ***** at %d", tb_cycle_counter);
        $display("************************************* ");
        TASK_SPECTAL_FULLY_NESTED_TEST();

        $display("******************************** ");
        $display("***** TEST NON SPECIFIC EOI***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_NON_SPECIFIC_EOI_TEST();

        $display("******************************** ");
        $display("***** TEST ROTATION       ***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_ROTATE_TEST();

        $display("******************************** ");
        $display("***** TEST POLL COMMAND    ***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_POLL_COMMAND_TEST();

        $display("******************************** ");
        $display("***** READING STATUS       ***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_READING_STATUS_TEST();

        $display("******************************** ");
        $display("***** CASCADE MODE         ***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_CASCADE_MODE_TEST();

        $display("******************************** ");
        $display("***** SLAVE PROGRAM        ***** at %d", tb_cycle_counter);
        $display("******************************** ");
        TASK_SLAVE_PROGRAM_TEST();

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

