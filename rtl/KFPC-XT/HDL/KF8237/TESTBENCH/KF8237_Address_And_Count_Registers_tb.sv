
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KF8237_Address_And_Count_Registers_tm();

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
    logic   [7:0]   internal_data_bus;
    logic   [7:0]   read_address_or_count;
    logic   [3:0]   write_base_and_current_address;
    logic   [3:0]   write_base_and_current_word_count;
    logic           clear_byte_pointer;
    logic           master_clear;
    logic   [3:0]   read_current_address;
    logic   [3:0]   read_current_word_count;
    logic   [3:0]   transfer_register_select;
    logic           initialize_current_register;
    logic           address_hold_config;
    logic           decrement_address_config;
    logic           next_word;
    logic           underflow;
    logic           update_high_address;
    logic   [15:0]  transfer_address;


    KF8237_Address_And_Count_Registers u_KF8237_Address_And_Count_Registers (.*);

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        internal_data_bus                   = 8'h00;
        write_base_and_current_address      = 4'b0000;
        write_base_and_current_word_count   = 4'b0000;
        clear_byte_pointer                  = 1'b0;
        master_clear                        = 1'b0;
        read_current_address                = 4'b0000;
        read_current_word_count             = 4'b0000;
        transfer_register_select            = 4'b0000;
        initialize_current_register         = 1'b0;
        address_hold_config                 = 1'b0;
        decrement_address_config            = 1'b0;
        next_word                           = 1'b0;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Task : Write BASE AND CURRENT ADDRESS
    //
    task TASK_WRITE_BASE_AND_CURRENT_ADDRESS(input [3:0] addr, input [7:0] data);
    begin
        #(`TB_CYCLE * 0);
        write_base_and_current_address  = 4'b0000;
        internal_data_bus               = 8'h00;
        #(`TB_CYCLE * 1);
        write_base_and_current_address  = addr;
        internal_data_bus               = data;
        #(`TB_CYCLE * 1);
        write_base_and_current_address  = 4'b0000;
        internal_data_bus               = 8'h00;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : Write BASE AND CURRENT WORD COUNT
    //
    task TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(input [3:0] addr, input [7:0] data);
    begin
        #(`TB_CYCLE * 0);
        write_base_and_current_word_count   = 4'b0000;
        internal_data_bus                   = 8'h00;
        #(`TB_CYCLE * 1);
        write_base_and_current_word_count   = addr;
        internal_data_bus                   = data;
        #(`TB_CYCLE * 1);
        write_base_and_current_word_count   = 4'b0000;
        internal_data_bus                   = 8'h00;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : READ CURRENT ADDRESS
    //
    task TASK_READ_CURRENT_ADDRESS(input [3:0] addr);
    begin
        #(`TB_CYCLE * 0);
        read_current_address                = 4'b0000;
        #(`TB_CYCLE * 1);
        read_current_address                = addr;
        #(`TB_CYCLE * 1);
        read_current_address                = 4'b0000;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : READ CURRENT WORD COUNT
    //
    task TASK_READ_CURRENT_WORD_COUNT(input [3:0] addr);
    begin
        #(`TB_CYCLE * 0);
        read_current_word_count             = 4'b0000;
        #(`TB_CYCLE * 1);
        read_current_word_count             = addr;
        #(`TB_CYCLE * 1);
        read_current_word_count             = 4'b0000;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : INCREMENT ADDRESS
    //
    task TASK_INCREMENT_ADDRESS(input [3:0] addr, input [15:0] tr_address, input [15:0] tr_count);
    begin
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(addr, tr_address[7:0]);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(addr, tr_address[15:8]);
        TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(addr, tr_count[7:0]);
        TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(addr, tr_count[15:8]);
        transfer_register_select = addr;
        decrement_address_config = 1'b0;
        #(`TB_CYCLE * 1);
        next_word                = 1'b1;
        #(`TB_CYCLE * 1);
        next_word                = 1'b0;
        #(`TB_CYCLE * 1);
        next_word                = 1'b1;
        #(`TB_CYCLE * 1);
        next_word                = 1'b0;
        #(`TB_CYCLE * 1);
        transfer_register_select = 4'b0000;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : DECREMENT ADDRESS
    //
    task TASK_DECREMENT_ADDRESS(input [3:0] addr, input [15:0] tr_address, input [15:0] tr_count);
    begin
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(addr, tr_address[7:0]);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(addr, tr_address[15:8]);
        TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(addr, tr_count[7:0]);
        TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(addr, tr_count[15:8]);
        transfer_register_select = addr;
        decrement_address_config = 1'b1;
        #(`TB_CYCLE * 1);
        next_word                = 1'b1;
        #(`TB_CYCLE * 1);
        next_word                = 1'b0;
        #(`TB_CYCLE * 1);
        next_word                = 1'b1;
        #(`TB_CYCLE * 1);
        next_word                = 1'b0;
        #(`TB_CYCLE * 1);
        transfer_register_select = 4'b0000;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : INITIALIZE CURRENT ADDRESS & COUNT
    //
    task TASK_INITIALIZE_CURRENT_ADDRESS_AND_COUNT(input [3:0] addr);
    begin
        TASK_READ_CURRENT_ADDRESS(addr);
        TASK_READ_CURRENT_ADDRESS(addr);
        TASK_READ_CURRENT_WORD_COUNT(addr);
        TASK_READ_CURRENT_WORD_COUNT(addr);
        #(`TB_CYCLE * 1);
        transfer_register_select    = addr;
        initialize_current_register = 1'b1;
        #(`TB_CYCLE * 1);
        transfer_register_select    = 4'b0000;
        initialize_current_register = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(addr);
        TASK_READ_CURRENT_ADDRESS(addr);
        TASK_READ_CURRENT_WORD_COUNT(addr);
        TASK_READ_CURRENT_WORD_COUNT(addr);
    end
    endtask;

    //
    // Task : CKEAR BYTE TEST
    //
    task TASK_CLEAR_BYTE(input [3:0] addr);
    begin
        #(`TB_CYCLE * 0);
        write_base_and_current_address  = 4'b0000;
        internal_data_bus               = 8'h00;
        clear_byte_pointer              = 1'b0;
        #(`TB_CYCLE * 1);
        write_base_and_current_address  = addr;
        internal_data_bus               = 8'hAB;
        #(`TB_CYCLE * 1);
        write_base_and_current_address  = 4'b0000;
        internal_data_bus               = 8'h00;
        #(`TB_CYCLE * 1);
        clear_byte_pointer              = 1'b1;
        #(`TB_CYCLE * 1);
        clear_byte_pointer              = 1'b0;
        #(`TB_CYCLE * 1);
        write_base_and_current_address  = addr;
        internal_data_bus               = 8'hCD;
        #(`TB_CYCLE * 1);
        write_base_and_current_address  = 4'b0000;
        internal_data_bus               = 8'h00;
        #(`TB_CYCLE * 1);
        clear_byte_pointer              = 1'b1;
        #(`TB_CYCLE * 1);
        clear_byte_pointer              = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(addr);
        TASK_READ_CURRENT_ADDRESS(addr);
    end
    endtask;

    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        $display("***** WRITE BASE AND CURRENT ADDRESS ***** at %d", tb_cycle_counter);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(4'b0001, 8'h12);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(4'b0001, 8'h34);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(4'b0010, 8'h56);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(4'b0010, 8'h78);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(4'b0100, 8'h9A);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(4'b0100, 8'hBC);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(4'b1000, 8'hDE);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(4'b1000, 8'hF0);
        #(`TB_CYCLE * 12);

        $display("***** READ CURRENT ADDRESS ***** at %d", tb_cycle_counter);
        TASK_READ_CURRENT_ADDRESS(4'b0001);
        TASK_READ_CURRENT_ADDRESS(4'b0001);
        TASK_READ_CURRENT_ADDRESS(4'b0010);
        TASK_READ_CURRENT_ADDRESS(4'b0010);
        TASK_READ_CURRENT_ADDRESS(4'b0100);
        TASK_READ_CURRENT_ADDRESS(4'b0100);
        TASK_READ_CURRENT_ADDRESS(4'b1000);
        TASK_READ_CURRENT_ADDRESS(4'b1000);
        #(`TB_CYCLE * 12);

        $display("***** WRITE BASE AND CURRENT WORD COUNT ***** at %d", tb_cycle_counter);
        TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(4'b0001, 8'h01);
        TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(4'b0001, 8'h23);
        TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(4'b0010, 8'h45);
        TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(4'b0010, 8'h67);
        TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(4'b0100, 8'h89);
        TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(4'b0100, 8'hAB);
        TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(4'b1000, 8'hCD);
        TASK_WRITE_BASE_AND_CURRENT_WORD_COUNT(4'b1000, 8'hEF);
        #(`TB_CYCLE * 12);

        $display("***** READ CURRENT WORD COUNT ***** at %d", tb_cycle_counter);
        TASK_READ_CURRENT_WORD_COUNT(4'b0001);
        TASK_READ_CURRENT_WORD_COUNT(4'b0001);
        TASK_READ_CURRENT_WORD_COUNT(4'b0010);
        TASK_READ_CURRENT_WORD_COUNT(4'b0010);
        TASK_READ_CURRENT_WORD_COUNT(4'b0100);
        TASK_READ_CURRENT_WORD_COUNT(4'b0100);
        TASK_READ_CURRENT_WORD_COUNT(4'b1000);
        TASK_READ_CURRENT_WORD_COUNT(4'b1000);
        #(`TB_CYCLE * 12);

        $display("***** INCREMENT ADDRESS ***** at %d", tb_cycle_counter);
        TASK_INCREMENT_ADDRESS(4'b0001, 16'h10FF, 16'h0100);
        TASK_INCREMENT_ADDRESS(4'b0010, 16'h20FF, 16'h0200);
        TASK_INCREMENT_ADDRESS(4'b0100, 16'h30FF, 16'h0300);
        TASK_INCREMENT_ADDRESS(4'b1000, 16'h40FF, 16'h0400);
        TASK_READ_CURRENT_ADDRESS(4'b0001);
        TASK_READ_CURRENT_ADDRESS(4'b0001);
        TASK_READ_CURRENT_WORD_COUNT(4'b0001);
        TASK_READ_CURRENT_WORD_COUNT(4'b0001);
        TASK_READ_CURRENT_ADDRESS(4'b0010);
        TASK_READ_CURRENT_ADDRESS(4'b0010);
        TASK_READ_CURRENT_WORD_COUNT(4'b0010);
        TASK_READ_CURRENT_WORD_COUNT(4'b0010);
        TASK_READ_CURRENT_ADDRESS(4'b0100);
        TASK_READ_CURRENT_ADDRESS(4'b0100);
        TASK_READ_CURRENT_WORD_COUNT(4'b0100);
        TASK_READ_CURRENT_WORD_COUNT(4'b0100);
        TASK_READ_CURRENT_ADDRESS(4'b1000);
        TASK_READ_CURRENT_ADDRESS(4'b1000);
        TASK_READ_CURRENT_WORD_COUNT(4'b1000);
        TASK_READ_CURRENT_WORD_COUNT(4'b1000);
        #(`TB_CYCLE * 12);

        $display("***** DECREMENT ADDRESS ***** at %d", tb_cycle_counter);
        TASK_DECREMENT_ADDRESS(4'b0001, 16'h1100, 16'h0100);
        TASK_DECREMENT_ADDRESS(4'b0010, 16'h2200, 16'h0200);
        TASK_DECREMENT_ADDRESS(4'b0100, 16'h3300, 16'h0300);
        TASK_DECREMENT_ADDRESS(4'b1000, 16'h4400, 16'h0400);
        TASK_READ_CURRENT_ADDRESS(4'b0001);
        TASK_READ_CURRENT_ADDRESS(4'b0001);
        TASK_READ_CURRENT_WORD_COUNT(4'b0001);
        TASK_READ_CURRENT_WORD_COUNT(4'b0001);
        TASK_READ_CURRENT_ADDRESS(4'b0010);
        TASK_READ_CURRENT_ADDRESS(4'b0010);
        TASK_READ_CURRENT_WORD_COUNT(4'b0010);
        TASK_READ_CURRENT_WORD_COUNT(4'b0010);
        TASK_READ_CURRENT_ADDRESS(4'b0100);
        TASK_READ_CURRENT_ADDRESS(4'b0100);
        TASK_READ_CURRENT_WORD_COUNT(4'b0100);
        TASK_READ_CURRENT_WORD_COUNT(4'b0100);
        TASK_READ_CURRENT_ADDRESS(4'b1000);
        TASK_READ_CURRENT_ADDRESS(4'b1000);
        TASK_READ_CURRENT_WORD_COUNT(4'b1000);
        TASK_READ_CURRENT_WORD_COUNT(4'b1000);
        #(`TB_CYCLE * 12);

        $display("***** INITIALIZE ADDRESS & COUNT ***** at %d", tb_cycle_counter);
        TASK_INITIALIZE_CURRENT_ADDRESS_AND_COUNT(4'b0001);
        TASK_INITIALIZE_CURRENT_ADDRESS_AND_COUNT(4'b0010);
        TASK_INITIALIZE_CURRENT_ADDRESS_AND_COUNT(4'b0100);
        TASK_INITIALIZE_CURRENT_ADDRESS_AND_COUNT(4'b1000);
        #(`TB_CYCLE * 12);

        $display("***** UNDERFLOW ***** at %d", tb_cycle_counter);
        TASK_INCREMENT_ADDRESS(4'b0001, 16'h1100, 16'h0001);
        TASK_INCREMENT_ADDRESS(4'b0010, 16'h2100, 16'h0001);
        TASK_INCREMENT_ADDRESS(4'b0100, 16'h3100, 16'h0001);
        TASK_INCREMENT_ADDRESS(4'b1000, 16'h4100, 16'h0001);
        #(`TB_CYCLE * 12);

        $display("***** MASTER CLEAR ***** at %d", tb_cycle_counter);
        master_clear = 1'b1;
        #(`TB_CYCLE * 1);
        master_clear = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(4'b0001);
        TASK_READ_CURRENT_ADDRESS(4'b0001);
        TASK_READ_CURRENT_WORD_COUNT(4'b0001);
        TASK_READ_CURRENT_WORD_COUNT(4'b0001);
        TASK_READ_CURRENT_ADDRESS(4'b0010);
        TASK_READ_CURRENT_ADDRESS(4'b0010);
        TASK_READ_CURRENT_WORD_COUNT(4'b0010);
        TASK_READ_CURRENT_WORD_COUNT(4'b0010);
        TASK_READ_CURRENT_ADDRESS(4'b0100);
        TASK_READ_CURRENT_ADDRESS(4'b0100);
        TASK_READ_CURRENT_WORD_COUNT(4'b0100);
        TASK_READ_CURRENT_WORD_COUNT(4'b0100);
        TASK_READ_CURRENT_ADDRESS(4'b1000);
        TASK_READ_CURRENT_ADDRESS(4'b1000);
        TASK_READ_CURRENT_WORD_COUNT(4'b1000);
        TASK_READ_CURRENT_WORD_COUNT(4'b1000);
        #(`TB_CYCLE * 12);

        $display("***** CLEAR BYTE POINTER ***** at %d", tb_cycle_counter);
        TASK_CLEAR_BYTE(4'b0001);
        TASK_CLEAR_BYTE(4'b0010);
        TASK_CLEAR_BYTE(4'b0100);
        TASK_CLEAR_BYTE(4'b1000);
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

