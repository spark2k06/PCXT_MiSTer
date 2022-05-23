
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KF8237_tm();

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
    logic           ready;
    logic           hold_acknowledge;
    logic   [3:0]   dma_request;
    logic   [7:0]   data_bus_in;
    logic   [7:0]   data_bus_out;
    logic           io_read_n_in;
    logic           io_read_n_out;
    logic           io_read_n_io;
    logic           io_write_n_in;
    logic           io_write_n_out;
    logic           io_write_n_io;
    logic           end_of_process_n_in;
    logic           end_of_process_n_out;
    logic   [3:0]   address_in;
    logic   [15:0]  address_out;
    logic           output_highst_address;
    logic           hold_request;
    logic   [3:0]   dma_acknowledge;
    logic           address_enable;
    logic           address_strobe;
    logic           memory_read_n;
    logic           memory_write_n;

    KF8237 u_KF8237 (.*);

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        chip_select_n       = 1'b1;
        ready               = 1'b1;
        hold_acknowledge    = 1'b0;
        dma_request         = 4'b0000;
        data_bus_in         = 8'h00;
        io_read_n_in        = 1'b1;
        io_write_n_in       = 1'b1;
        end_of_process_n_in = 1'b1;
        address_in          = 4'b0000;
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
        chip_select_n   = 1'b1;
        io_write_n_in   = 1'b1;
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
        chip_select_n   = 1'b1;
        io_read_n_in    = 1'b1;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : Write Command Register
    //
    task TASK_WRITE_COMMAND_REGISTER(input [7:0] data);
    begin
        TASK_WRITE_DATA(4'b1000, data);
    end
    endtask;

    //
    // Task : Write Mode Register
    //
    task TASK_WRITE_MODE_REGISTER(input [7:0] data);
    begin
        TASK_WRITE_DATA(4'b1011, data);
    end
    endtask;

    //
    // Task : Write Request Register
    //
    task TASK_WRITE_REQUEST_REGISTER(input [7:0] data);
    begin
        TASK_WRITE_DATA(4'b1001, data);
    end
    endtask;

    //
    // Task : Write Mask Register
    //
    task TASK_WRITE_MASK_REGISTER(input [7:0] data);
    begin
        TASK_WRITE_DATA(4'b1111, data);
    end
    endtask;

    //
    // Task : Set/Reset Mask Register
    //
    task TASK_SET_RESET_MASK_REGISTER(input [7:0] data);
    begin
        TASK_WRITE_DATA(4'b1010, data);
    end
    endtask;

    //
    // Task : Clear Byte Pointer Flip/Flop
    //
    task TASK_CLEAR_BYTE_POINTER_FF();
    begin
        TASK_WRITE_DATA(4'b1100, 8'h00);
    end
    endtask;

    //
    // Task : Master Clear
    //
    task TASK_MASTER_CLEAR();
    begin
        TASK_WRITE_DATA(4'b1101, 8'h00);
    end
    endtask;

    //
    // Task : Clear Mask Register
    //
    task TASK_CLEAR_MASK_REGISTER();
    begin
        TASK_WRITE_DATA(4'b1110, 8'h00);
    end
    endtask;

    //
    // Task : Write Base And Current Address
    //
    task TASK_WRITE_BASE_AND_CURRENT_ADDRESS(input [1:0] ch, input [7:0] data);
    begin
        casez (ch)
            2'b00:      TASK_WRITE_DATA(4'b0000, data);
            2'b01:      TASK_WRITE_DATA(4'b0010, data);
            2'b10:      TASK_WRITE_DATA(4'b0100, data);
            2'b11:      TASK_WRITE_DATA(4'b0110, data);
            default:    TASK_WRITE_DATA(4'b0000, data);
        endcase
    end
    endtask;

    //
    // Task : Write Base And Current Word
    //
    task TASK_WRITE_BASE_AND_CURRENT_WORD(input [1:0] ch, input [7:0] data);
    begin
        casez (ch)
            2'b00:      TASK_WRITE_DATA(4'b0001, data);
            2'b01:      TASK_WRITE_DATA(4'b0011, data);
            2'b10:      TASK_WRITE_DATA(4'b0101, data);
            2'b11:      TASK_WRITE_DATA(4'b0111, data);
            default:    TASK_WRITE_DATA(4'b0001, data);
        endcase
    end
    endtask;

    //
    // Task : Read Temporary Register
    //
    task TASK_READ_TEMPORARY_REGISTER();
    begin
        TASK_READ_DATA(4'b1101);
    end
    endtask;

    //
    // Task : Read Status Register
    //
    task TASK_READ_STATUS_REGISTER();
    begin
        TASK_READ_DATA(4'b1000);
    end
    endtask;

    //
    // Task : Read Current Address
    //
    task TASK_READ_CURRENT_ADDRESS(input [1:0] ch);
    begin
        casez (ch)
            2'b00:      TASK_READ_DATA(4'b0000);
            2'b01:      TASK_READ_DATA(4'b0010);
            2'b10:      TASK_READ_DATA(4'b0100);
            2'b11:      TASK_READ_DATA(4'b0110);
            default:    TASK_READ_DATA(4'b0000);
        endcase
    end
    endtask;

    //
    // Task : Write Base And Current Word
    //
    task TASK_READ_CURRENT_WORD(input [1:0] ch);
    begin
        casez (ch)
            2'b00:      TASK_READ_DATA(4'b0001);
            2'b01:      TASK_READ_DATA(4'b0011);
            2'b10:      TASK_READ_DATA(4'b0101);
            2'b11:      TASK_READ_DATA(4'b0111);
            default:    TASK_READ_DATA(4'b0001);
        endcase
    end
    endtask;

    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        $display("***** CH0/SINGLE/WRITE/READY TEST ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00000000);
        TASK_WRITE_MODE_REGISTER(8'b01000100);
        TASK_SET_RESET_MASK_REGISTER(8'b00000000);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h10);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h00);
        dma_request         = 4'b0001;
        #(`TB_CYCLE * 3);
        hold_acknowledge    = 1'b1;
        ready               = 1'b0;
        #(`TB_CYCLE * 6);
        ready               = 1'b1;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CH1/SINGLE/DECREMENT/READ TEST ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00000000);
        TASK_WRITE_MODE_REGISTER(8'b01101001);
        TASK_SET_RESET_MASK_REGISTER(8'b00000001);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd1, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd1, 8'h20);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd1, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd1, 8'h00);
        dma_request         = 4'b0010;
        #(`TB_CYCLE * 1);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd1);
        TASK_READ_CURRENT_ADDRESS(2'd1);
        TASK_READ_CURRENT_WORD(2'd1);
        TASK_READ_CURRENT_WORD(2'd1);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CH2/SINGLE/VERIFY TEST ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00000000);
        TASK_WRITE_MODE_REGISTER(8'b01000010);
        TASK_SET_RESET_MASK_REGISTER(8'b00000010);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd2, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd2, 8'h30);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd2, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd2, 8'h0F);
        dma_request         = 4'b0100;
        #(`TB_CYCLE * 1);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd2);
        TASK_READ_CURRENT_ADDRESS(2'd2);
        TASK_READ_CURRENT_WORD(2'd2);
        TASK_READ_CURRENT_WORD(2'd2);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CH3/SINGLE/AUTOINITIALIZE/WRITE TEST ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00000000);
        TASK_WRITE_MODE_REGISTER(8'b01010111);
        TASK_SET_RESET_MASK_REGISTER(8'b00000011);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd3, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd3, 8'h40);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd3, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd3, 8'h00);
        dma_request         = 4'b1000;
        #(`TB_CYCLE * 1);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd3);
        TASK_READ_CURRENT_ADDRESS(2'd3);
        TASK_READ_CURRENT_WORD(2'd3);
        TASK_READ_CURRENT_WORD(2'd3);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CH0/BLOCK/READ TEST ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00000000);
        TASK_WRITE_MODE_REGISTER(8'b10000100);
        TASK_SET_RESET_MASK_REGISTER(8'b00000000);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'hF5);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h10);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h00);
        dma_request         = 4'b0001;
        #(`TB_CYCLE * 3);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 4 * 17);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CH1/BLOCK/DECREMENT/READ/EX_EOP TEST ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00000000);
        TASK_WRITE_MODE_REGISTER(8'b10101001);
        TASK_SET_RESET_MASK_REGISTER(8'b00000001);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd1, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd1, 8'h20);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd1, 8'hFF);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd1, 8'h01);
        dma_request         = 4'b0010;
        #(`TB_CYCLE * 1);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 4 * 8);
        #(`TB_CYCLE * 1);
        end_of_process_n_in = 1'b0;
        #(`TB_CYCLE * 4);
        end_of_process_n_in = 1'b1;
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 4);
        TASK_READ_CURRENT_ADDRESS(2'd1);
        TASK_READ_CURRENT_ADDRESS(2'd1);
        TASK_READ_CURRENT_WORD(2'd1);
        TASK_READ_CURRENT_WORD(2'd1);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CH0/DEMAND/AUTOINITIALIZE/WRITE TEST ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00000000);
        TASK_WRITE_MODE_REGISTER(8'b00010100);
        TASK_SET_RESET_MASK_REGISTER(8'b00000000);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h10);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h02);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h00);
        dma_request         = 4'b0001;
        #(`TB_CYCLE * 3);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 4 * 17);
        dma_request         = 4'b0000;
        #(`TB_CYCLE * 4);
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CH0/CASCADE TEST ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00000000);
        TASK_WRITE_MODE_REGISTER(8'b11000000);
        TASK_SET_RESET_MASK_REGISTER(8'b00000000);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h10);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h02);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h00);
        dma_request         = 4'b0001;
        #(`TB_CYCLE * 3);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 10);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CH0/EXTEND_WRITE/SINGLE/WRITE ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00100000);
        TASK_WRITE_MODE_REGISTER(8'b01000100);
        TASK_SET_RESET_MASK_REGISTER(8'b00000000);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h10);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h00);
        dma_request         = 4'b0001;
        #(`TB_CYCLE * 3);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CH1/EXTEND_WRITE/SINGLE/READ ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00100000);
        TASK_WRITE_MODE_REGISTER(8'b01101001);
        TASK_SET_RESET_MASK_REGISTER(8'b00000001);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd1, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd1, 8'h20);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd1, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd1, 8'h00);
        dma_request         = 4'b0010;
        #(`TB_CYCLE * 1);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd1);
        TASK_READ_CURRENT_ADDRESS(2'd1);
        TASK_READ_CURRENT_WORD(2'd1);
        TASK_READ_CURRENT_WORD(2'd1);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CH0/COMPRESSED/SINGLE/WRITE ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00001000);
        TASK_WRITE_MODE_REGISTER(8'b01000100);
        TASK_SET_RESET_MASK_REGISTER(8'b00000000);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h10);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h00);
        dma_request         = 4'b0001;
        #(`TB_CYCLE * 3);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CH1/COMPRESSED/SINGLE/READ ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00001000);
        TASK_WRITE_MODE_REGISTER(8'b01101001);
        TASK_SET_RESET_MASK_REGISTER(8'b00000001);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd1, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd1, 8'h20);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd1, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd1, 8'h00);
        dma_request         = 4'b0010;
        #(`TB_CYCLE * 1);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd1);
        TASK_READ_CURRENT_ADDRESS(2'd1);
        TASK_READ_CURRENT_WORD(2'd1);
        TASK_READ_CURRENT_WORD(2'd1);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CH0/ADDRESS_HOLD/SINGLE/WRITE ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00000010);
        TASK_WRITE_MODE_REGISTER(8'b01000100);
        TASK_SET_RESET_MASK_REGISTER(8'b00000000);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h10);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h00);
        dma_request         = 4'b0001;
        #(`TB_CYCLE * 3);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** FIXED PRIORITY TEST ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00000000);
        TASK_WRITE_MODE_REGISTER(8'b01000100);
        TASK_WRITE_MODE_REGISTER(8'b01000101);
        TASK_WRITE_MODE_REGISTER(8'b01000110);
        TASK_WRITE_MODE_REGISTER(8'b01000111);
        TASK_WRITE_MASK_REGISTER(8'b00000000);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h10);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd1, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd1, 8'h20);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd2, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd2, 8'h30);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd3, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd3, 8'h40);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd1, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd1, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd2, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd3, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd3, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd3, 8'h00);
        dma_request         = 4'b1111;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b1110;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b1100;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b1000;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** ROTETE PRIORITY TEST ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00010000);
        TASK_WRITE_MODE_REGISTER(8'b01000100);
        TASK_WRITE_MODE_REGISTER(8'b01000101);
        TASK_WRITE_MODE_REGISTER(8'b01000110);
        TASK_WRITE_MODE_REGISTER(8'b01000111);
        TASK_WRITE_MASK_REGISTER(8'b00000000);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h10);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd1, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd1, 8'h20);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd2, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd2, 8'h30);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd3, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd3, 8'h40);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd1, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd1, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd2, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd3, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd3, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd3, 8'h00);
        dma_request         = 4'b1111;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b1111;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b1111;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b1111;
        #(`TB_CYCLE * 1);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** DREQ SENSE ACTIVE HIGH TEST ***** at %d", tb_cycle_counter);
        dma_request         = 4'b1111;
        TASK_WRITE_COMMAND_REGISTER(8'b01000000);
        TASK_WRITE_MODE_REGISTER(8'b01000100);
        TASK_SET_RESET_MASK_REGISTER(8'b00000000);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h10);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h00);
        dma_request         = 4'b1110;
        #(`TB_CYCLE * 3);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        dma_request         = 4'b1111;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();
        dma_request         = 4'b0000;
        #(`TB_CYCLE * 1);

        $display("***** DACK SENSE ACTIVE HIGH TEST ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b10000000);
        TASK_WRITE_MODE_REGISTER(8'b01000100);
        TASK_SET_RESET_MASK_REGISTER(8'b00000000);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h10);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h00);
        dma_request         = 4'b0001;
        #(`TB_CYCLE * 3);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

        $display("***** CONTROLLER DISABLE TEST ***** at %d", tb_cycle_counter);
        TASK_WRITE_COMMAND_REGISTER(8'b00000100);
        TASK_WRITE_MODE_REGISTER(8'b01000100);
        TASK_SET_RESET_MASK_REGISTER(8'b00000000);
        TASK_CLEAR_BYTE_POINTER_FF();
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h00);
        TASK_WRITE_BASE_AND_CURRENT_ADDRESS(2'd0, 8'h10);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h0F);
        TASK_WRITE_BASE_AND_CURRENT_WORD(2'd0, 8'h00);
        dma_request         = 4'b0001;
        #(`TB_CYCLE * 6);
        dma_request         = 4'b0000;
        #(`TB_CYCLE * 1);
        TASK_WRITE_COMMAND_REGISTER(8'b00000000);
        dma_request         = 4'b0001;
        #(`TB_CYCLE * 3);
        hold_acknowledge    = 1'b1;
        #(`TB_CYCLE * 6);
        dma_request         = 4'b0000;
        hold_acknowledge    = 1'b0;
        #(`TB_CYCLE * 1);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_ADDRESS(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        TASK_READ_CURRENT_WORD(2'd0);
        #(`TB_CYCLE * 12);
        TASK_MASTER_CLEAR();

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

