
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KF8237_Priority_Encoder_tm();

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
    logic           write_command_register;
    logic           write_request_register;
    logic           set_or_reset_mask_register;
    logic           write_mask_register;
    logic           master_clear;
    logic           clear_mask_register;
    logic   [1:0]   dma_rotate;
    logic   [3:0]   edge_request;
    logic   [3:0]   encoded_dma;
    logic           end_of_process;
    logic   [3:0]   dma_acknowledge_internal;
    logic   [3:0]   dma_request;

    KF8237_Priority_Encoder u_Priority_Encoder (.*);

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        internal_data_bus           = 1'b0;
        write_command_register      = 1'b0;
        write_request_register      = 1'b0;
        set_or_reset_mask_register  = 1'b0;
        write_mask_register         = 1'b0;
        master_clear                = 1'b0;
        clear_mask_register         = 1'b0;
        dma_rotate                  = 2'b11;
        edge_request                = 4'b0000;
        end_of_process              = 1'b0;
        dma_acknowledge_internal    = 4'b0000;
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        dma_request                 = 4'b1111;

        $display("***** CLEAR MASK BIT TEST ***** at %d", tb_cycle_counter);
        internal_data_bus           = 8'b00000011;
        set_or_reset_mask_register  = 1'b1;
        #(`TB_CYCLE * 1);
        set_or_reset_mask_register  = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000010;
        set_or_reset_mask_register  = 1'b1;
        #(`TB_CYCLE * 1);
        set_or_reset_mask_register  = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000001;
        set_or_reset_mask_register  = 1'b1;
        #(`TB_CYCLE * 1);
        set_or_reset_mask_register  = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000000;
        set_or_reset_mask_register  = 1'b1;
        #(`TB_CYCLE * 1);
        set_or_reset_mask_register  = 1'b0;
        #(`TB_CYCLE * 12);

        $display("***** WRITE MASK REGISTER TEST ***** at %d", tb_cycle_counter);
        internal_data_bus           = 8'b00000001;
        write_mask_register         = 1'b1;
        #(`TB_CYCLE * 1);
        write_mask_register         = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000011;
        write_mask_register         = 1'b1;
        #(`TB_CYCLE * 1);
        write_mask_register         = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000111;
        write_mask_register         = 1'b1;
        #(`TB_CYCLE * 1);
        write_mask_register         = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00001111;
        write_mask_register         = 1'b1;
        #(`TB_CYCLE * 1);
        write_mask_register         = 1'b0;
        #(`TB_CYCLE * 1);

        internal_data_bus           = 8'b00000000;
        write_mask_register         = 1'b1;
        #(`TB_CYCLE * 1);
        write_mask_register         = 1'b0;
        #(`TB_CYCLE * 12);

        $display("***** DMA PRIORITY TEST ***** at %d", tb_cycle_counter);
        dma_request                 = 4'b1111;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b1110;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b1100;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b1000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 12);

        $display("***** DMA PRIORITY ROTATE TEST ***** at %d", tb_cycle_counter);
        dma_request                 = 4'b1111;
        dma_rotate                  = 2'b11;
        internal_data_bus           = 8'b00010000;
        write_command_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_command_register      = 1'b0;
        #(`TB_CYCLE * 1);
        dma_rotate                  = 2'b00;
        #(`TB_CYCLE * 1);
        dma_rotate                  = 2'b01;
        #(`TB_CYCLE * 1);
        dma_rotate                  = 2'b10;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000000;
        write_command_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_command_register      = 1'b0;
        #(`TB_CYCLE * 12);


        $display("***** DMA ACTIVE LOW TEST ***** at %d", tb_cycle_counter);
        dma_request                 = 4'b1111;
        internal_data_bus           = 8'b01000000;
        write_command_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_command_register      = 1'b0;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0111;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0011;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0001;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b1111;
        internal_data_bus           = 8'b00000000;
        write_command_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_command_register      = 1'b0;
        #(`TB_CYCLE * 12);

        $display("***** CONTROLLER DISABLE TEST ***** at %d", tb_cycle_counter);
        internal_data_bus           = 8'b00000100;
        write_command_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_command_register      = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000000;
        write_command_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_command_register      = 1'b0;
        #(`TB_CYCLE * 12);

        $display("***** WRITE REQUEST REGISTER TEST ***** at %d", tb_cycle_counter);
        dma_request                 = 4'b0000;
        internal_data_bus           = 8'b00000111;
        write_request_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_request_register      = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000110;
        write_request_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_request_register      = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000101;
        write_request_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_request_register      = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000100;
        write_request_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_request_register      = 1'b0;
        #(`TB_CYCLE * 12);

        internal_data_bus           = 8'b00000000;
        write_request_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_request_register      = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000001;
        write_request_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_request_register      = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000010;
        write_request_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_request_register      = 1'b0;
        #(`TB_CYCLE * 1);
        internal_data_bus           = 8'b00000011;
        write_request_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_request_register      = 1'b0;
        #(`TB_CYCLE * 12);

        $display("***** AUTO CLRAR REQUEST REGISTER TEST ***** at %d", tb_cycle_counter);
        internal_data_bus           = 8'b00000111;
        write_request_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_request_register      = 1'b0;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b1000;
        end_of_process              = 1'b1;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0000;
        end_of_process              = 1'b0;
        #(`TB_CYCLE * 1);

       internal_data_bus           = 8'b00000110;
        write_request_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_request_register      = 1'b0;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0100;
        end_of_process              = 1'b1;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0000;
        end_of_process              = 1'b0;
        #(`TB_CYCLE * 1);

       internal_data_bus           = 8'b00000101;
        write_request_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_request_register      = 1'b0;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0010;
        end_of_process              = 1'b1;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0000;
        end_of_process              = 1'b0;
        #(`TB_CYCLE * 1);

       internal_data_bus           = 8'b00000100;
        write_request_register      = 1'b1;
        #(`TB_CYCLE * 1);
        write_request_register      = 1'b0;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0001;
        end_of_process              = 1'b1;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0000;
        end_of_process              = 1'b0;
        #(`TB_CYCLE * 12);

        $display("***** EDGE TEST ***** at %d", tb_cycle_counter);
        edge_request                = 4'b0000;
        dma_request                 = 4'b0001;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0001;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0001;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        edge_request                = 4'b0001;
        dma_request                 = 4'b0001;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0001;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0001;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);

        edge_request                = 4'b0000;
        dma_request                 = 4'b0010;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0010;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0010;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        edge_request                = 4'b0010;
        dma_request                 = 4'b0010;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0010;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0010;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);

        edge_request                = 4'b0000;
        dma_request                 = 4'b0100;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0100;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0100;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        edge_request                = 4'b0100;
        dma_request                 = 4'b0100;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0100;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0100;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);

        edge_request                = 4'b0000;
        dma_request                 = 4'b1000;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b1000;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b1000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        edge_request                = 4'b1000;
        dma_request                 = 4'b1000;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b1000;
        #(`TB_CYCLE * 1);
        dma_acknowledge_internal    = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b1000;
        #(`TB_CYCLE * 1);
        dma_request                 = 4'b0000;
        #(`TB_CYCLE * 1);

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

