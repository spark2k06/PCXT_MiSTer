
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KF8259_In_Service_tm();

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

    logic   [7:0]   interrupt;
    logic           start_in_service;
    logic   [7:0]   end_of_interrupt;

    logic   [7:0]   in_service_register;
    logic   [7:0]   highest_level_in_service;

    KF8259_In_Service u_KF8259_In_Service (.*);

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        priority_rotate  = 3'b111;
        interrupt        = 8'b00000000;
        start_in_service = 1'b0;
        end_of_interrupt = 8'b00000000;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Task : Interrupt
    //
    task TASK_INTERRUPT(input [7:0] in);
    begin
        #(`TB_CYCLE * 0);
        interrupt        = in;
        start_in_service = 1'b0;
        #(`TB_CYCLE * 1);
        start_in_service = 1'b1;
        #(`TB_CYCLE * 1);
        interrupt        = 8'b00000000;
        start_in_service = 1'b0;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : End of interrupt
    //
    task TASK_END_OF_INTERRUPT(input [7:0] in);
    begin
        #(`TB_CYCLE * 0);
        end_of_interrupt = in;
        #(`TB_CYCLE * 1);
        end_of_interrupt = 8'b00000000;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : Scan 1nterrupt
    //
    task TASK_SCAN_INTERRUPT();
    begin
        #(`TB_CYCLE * 0);
        TASK_INTERRUPT(8'b10000000);
        TASK_INTERRUPT(8'b01000000);
        TASK_INTERRUPT(8'b00100000);
        TASK_INTERRUPT(8'b00010000);
        TASK_INTERRUPT(8'b00001000);
        TASK_INTERRUPT(8'b00000100);
        TASK_INTERRUPT(8'b00000010);
        TASK_INTERRUPT(8'b00000001);
        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Task : Scan end of 1nterrupt
    //
    task TASK_SCAN_END_OF_INTERRUPT();
    begin
        #(`TB_CYCLE * 0);
        TASK_END_OF_INTERRUPT(8'b00000001);
        TASK_END_OF_INTERRUPT(8'b00000010);
        TASK_END_OF_INTERRUPT(8'b00000100);
        TASK_END_OF_INTERRUPT(8'b00001000);
        TASK_END_OF_INTERRUPT(8'b00010000);
        TASK_END_OF_INTERRUPT(8'b00100000);
        TASK_END_OF_INTERRUPT(8'b01000000);
        TASK_END_OF_INTERRUPT(8'b10000000);
        #(`TB_CYCLE * 1);
    end
    endtask

    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        $display("***** TEST ROTATE 7 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b111;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT();
        TASK_SCAN_END_OF_INTERRUPT();

        $display("***** TEST ROTATE 6 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b110;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT();
        TASK_SCAN_END_OF_INTERRUPT();

        $display("***** TEST ROTATE 5 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b101;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT();
        TASK_SCAN_END_OF_INTERRUPT();

        $display("***** TEST ROTATE 4 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b100;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT();
        TASK_SCAN_END_OF_INTERRUPT();

        $display("***** TEST ROTATE 3 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b011;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT();
        TASK_SCAN_END_OF_INTERRUPT();

        $display("***** TEST ROTATE 2 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b010;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT();
        TASK_SCAN_END_OF_INTERRUPT();

        $display("***** TEST ROTATE 1 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b001;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT();
        TASK_SCAN_END_OF_INTERRUPT();

        $display("***** TEST ROTATE 0 ***** at %d", tb_cycle_counter);
        priority_rotate = 3'b000;
        #(`TB_CYCLE * 1);
        TASK_SCAN_INTERRUPT();
        TASK_SCAN_END_OF_INTERRUPT();

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

