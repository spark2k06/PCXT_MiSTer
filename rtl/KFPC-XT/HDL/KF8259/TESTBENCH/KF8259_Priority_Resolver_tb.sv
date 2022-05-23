
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KF8259_Priority_Resolver_tm();

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
    logic   [2:0]   priority_rotate;
    logic   [7:0]   interrupt_mask;
    logic   [7:0]   interrupt_special_mask;
    logic           special_fully_nest_config;
    logic   [7:0]   highest_level_in_service;

    logic   [7:0]   interrupt_request_register;
    logic   [7:0]   in_service_register;

    logic   [7:0]   interrupt;

    KF8259_Priority_Resolver u_KF8259_Priority_Resolver(.*);

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        priority_rotate            = 3'b111;
        interrupt_mask             = 8'b11111111;
        interrupt_special_mask     = 8'b00000000;
        special_fully_nest_config  = 1'b0;
        highest_level_in_service   = 8'b00000000;
        interrupt_request_register = 8'b00000000;
        in_service_register        = 8'b00000000;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Task : Scan
    //
    task TASK_SCAN_INTERRUPT_REQUEST();
    begin
        #(`TB_CYCLE * 0);
        interrupt_request_register = 8'b10000000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b11000000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b11100000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b11110000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b11111000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b11111100;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b11111110;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b11111111;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00000000;
        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Task : INTERRUPT MASK TEST
    //
    task TASK_INTERRUPT_MASK_TEST();
    begin
        $display("***** TEST ALL MASK ***** at %d", tb_cycle_counter);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST ALL NON-MASK ***** at %d", tb_cycle_counter);
        interrupt_mask = 8'b00000000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST MASK BIT0 ***** at %d", tb_cycle_counter);
        interrupt_mask = 8'b00000001;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST MASK BIT1 ***** at %d", tb_cycle_counter);
        interrupt_mask = 8'b00000010;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST MASK BIT2 ***** at %d", tb_cycle_counter);
        interrupt_mask = 8'b00000100;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST MASK BIT3 ***** at %d", tb_cycle_counter);
        interrupt_mask = 8'b00001000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST MASK BIT4 ***** at %d", tb_cycle_counter);
        interrupt_mask = 8'b00010000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST MASK BIT5 ***** at %d", tb_cycle_counter);
        interrupt_mask = 8'b00100000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST MASK BIT6 ***** at %d", tb_cycle_counter);
        interrupt_mask = 8'b01000000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST MASK BIT7 ***** at %d", tb_cycle_counter);
        interrupt_mask = 8'b10000000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Task : IN-SERVICE INTERRUPT TEST
    //
    task TASK_IN_SERVICE_INTERRUPT_TEST();
    begin
        interrupt_mask = 8'b00000000;
        #(`TB_CYCLE * 1);

        $display("***** TEST IN-SERVICE BIT0 ***** at %d", tb_cycle_counter);
        in_service_register = 8'b00000001;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST IN-SERVICE BIT1 ***** at %d", tb_cycle_counter);
        in_service_register = 8'b00000010;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST IN-SERVICE BIT2 ***** at %d", tb_cycle_counter);
        in_service_register = 8'b00000100;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST IN-SERVICE BIT3 ***** at %d", tb_cycle_counter);
        in_service_register = 8'b00001000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST IN-SERVICE BIT4 ***** at %d", tb_cycle_counter);
        in_service_register = 8'b00010000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST IN-SERVICE BIT5 ***** at %d", tb_cycle_counter);
        in_service_register = 8'b00100000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST IN-SERVICE BIT6 ***** at %d", tb_cycle_counter);
        in_service_register = 8'b01000000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST IN-SERVICE BIT7 ***** at %d", tb_cycle_counter);
        in_service_register = 8'b10000000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        in_service_register = 8'b00000000;
        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Task : SPECIAL MASK MODE TEST
    //
    task TASK_SPECIAL_MASK_MODE_TEST();
    begin
        interrupt_mask = 8'b00000000;
        #(`TB_CYCLE * 1);

        $display("***** TEST SPECIAL MASK BIT0 ***** at %d", tb_cycle_counter);
        in_service_register    = 8'b00000011;
        interrupt_special_mask = 8'b00000001;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST SPECIAL MASK BIT1 ***** at %d", tb_cycle_counter);
        in_service_register    = 8'b00000110;
        interrupt_special_mask = 8'b00000010;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST SPECIAL MASK BIT2 ***** at %d", tb_cycle_counter);
        in_service_register    = 8'b00001100;
        interrupt_special_mask = 8'b00000100;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST SPECIAL MASK BIT3 ***** at %d", tb_cycle_counter);
        in_service_register    = 8'b00011000;
        interrupt_special_mask = 8'b00001000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST SPECIAL MASK BIT4 ***** at %d", tb_cycle_counter);
        in_service_register    = 8'b00110000;
        interrupt_special_mask = 8'b00010000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST SPECIAL MASK BIT5 ***** at %d", tb_cycle_counter);
        in_service_register    = 8'b01100000;
        interrupt_special_mask = 8'b00100000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST SPECIAL MASK BIT6 ***** at %d", tb_cycle_counter);
        in_service_register    = 8'b11000000;
        interrupt_special_mask = 8'b01000000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST SPECIAL MASK BIT7 ***** at %d", tb_cycle_counter);
        in_service_register    = 8'b10000000;
        interrupt_special_mask = 8'b10000000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        in_service_register    = 8'b00000000;
        interrupt_special_mask = 8'b00000000;
        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Task : SPECIAL FULLY NEST MODE TEST
    //
    task TASK_SPECIAL_FULLY_NEST_MODE_TEST();
    begin
        special_fully_nest_config = 1'b1;
        #(`TB_CYCLE * 1);

        $display("***** TEST FULLY NEST BIT0 ***** at %d", tb_cycle_counter);
        in_service_register      = 8'b00000001;
        highest_level_in_service = 8'b00000001;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST FULLY NEST BIT1 ***** at %d", tb_cycle_counter);
        in_service_register      = 8'b00000010;
        highest_level_in_service = 8'b00000010;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST FULLY NEST BIT2 ***** at %d", tb_cycle_counter);
        in_service_register      = 8'b00000100;
        highest_level_in_service = 8'b00000100;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST FULLY NEST BIT3 ***** at %d", tb_cycle_counter);
        in_service_register      = 8'b00001000;
        highest_level_in_service = 8'b00001000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST FULLY NEST BIT4 ***** at %d", tb_cycle_counter);
        in_service_register      = 8'b00010000;
        highest_level_in_service = 8'b00010000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST FULLY NEST BIT5 ***** at %d", tb_cycle_counter);
        in_service_register      = 8'b00100000;
        highest_level_in_service = 8'b00100000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST FULLY NEST BIT6 ***** at %d", tb_cycle_counter);
        in_service_register      = 8'b01000000;
        highest_level_in_service = 8'b01000000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        $display("***** TEST FULLY NEST BIT7 ***** at %d", tb_cycle_counter);
        in_service_register      = 8'b10000000;
        highest_level_in_service = 8'b10000000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();

        in_service_register      = 8'b00000000;
        highest_level_in_service = 8'b00000000;

        special_fully_nest_config = 1'b0;
        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Task : ROTATION TEST
    //
    task TASK_ROTATION_TEST();
    begin
        $display("***** TEST ROTATE 0 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();
        interrupt_request_register = 8'b00000001;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00000000;

        $display("***** TEST ROTATE 1 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b001;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();
        interrupt_request_register = 8'b00000010;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00000011;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00000000;

        $display("***** TEST ROTATE 2 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b010;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();
        interrupt_request_register = 8'b00000100;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00000110;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00000111;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00000000;

        $display("***** TEST ROTATE 3 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b011;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();
        interrupt_request_register = 8'b00001000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00001100;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00001110;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00001111;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00000000;

        $display("***** TEST ROTATE 4 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b100;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();
        interrupt_request_register = 8'b00010000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00011000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00011100;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00011110;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00011111;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00000000;

        $display("***** TEST ROTATE 5 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b101;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();
        interrupt_request_register = 8'b00100000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00110000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00111000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00111100;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00111110;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00111111;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00000000;

        $display("***** TEST ROTATE 6 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b110;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();
        interrupt_request_register = 8'b01000000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b01100000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b01110000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b01111000;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b01111100;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b01111110;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b01111111;
        #(`TB_CYCLE * 1);
        interrupt_request_register = 8'b00000000;

        $display("***** TEST ROTATE 7 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b111;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT_REQUEST();
        interrupt_request_register = 8'b00000000;
        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        $display("***** TEST INTERRUPT NASK ***** at %d", tb_cycle_counter);
        TASK_INTERRUPT_MASK_TEST();

        $display("***** TEST IN-SERVICE INTERRUPT ***** at %d", tb_cycle_counter);
        TASK_IN_SERVICE_INTERRUPT_TEST();

        $display("***** TEST SPECIAL MASK MODE ***** at %d", tb_cycle_counter);
        TASK_SPECIAL_MASK_MODE_TEST();

        $display("***** TEST SPECIAL FULLY NEST MODE ***** at %d", tb_cycle_counter);
        TASK_SPECIAL_FULLY_NEST_MODE_TEST();

        $display("***** TEST ROTATION ***** at %d", tb_cycle_counter);
        TASK_ROTATION_TEST();

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

