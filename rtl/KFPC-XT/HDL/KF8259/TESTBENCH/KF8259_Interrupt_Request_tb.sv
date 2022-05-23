
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module KF8259_Interrupt_Request_tm();

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
    logic           level_toriggered_config;
    logic           freeze;
    logic   [7:0]   clear_interrupt_request;
    logic   [7:0]   interrupt_request_pin;
    logic   [7:0]   interrupt_request_register;

    KF8259_Interrupt_Request u_KF8259_Interrupt_Request (.*);

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        level_toriggered_config = 1'b0;
        freeze                  = 1'b0;
        interrupt_request_pin   = 8'b00000000;
        clear_interrupt_request = 8'b00000000;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Task : Level trigger interrupt
    //
    task TASK_LEVEL_TRIGGER_INTERRUPT(input [7:0] data);
    begin
        #(`TB_CYCLE * 0);
        level_toriggered_config = 1'b1;
        #(`TB_CYCLE * 1);
        interrupt_request_pin   = data;
        #(`TB_CYCLE * 1);
        clear_interrupt_request = data;
        #(`TB_CYCLE * 1);
        clear_interrupt_request = 8'b00000000;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : Edge trigger interrupt
    //
    task TASK_EDGE_TRIGGER_INTERRUPT(input [7:0] data);
    begin
        #(`TB_CYCLE * 0);
        level_toriggered_config = 1'b0;
        #(`TB_CYCLE * 1);
        interrupt_request_pin   = 8'b00000000;
        #(`TB_CYCLE * 1);
        interrupt_request_pin   = data;
        #(`TB_CYCLE * 1);
        clear_interrupt_request = data;
        #(`TB_CYCLE * 1);
        clear_interrupt_request = 8'b00000000;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : Clear interrupt request
    //
    task TASK_CLEAR_INTERRUPT_REQUEST(input [7:0] data);
    begin
        #(`TB_CYCLE * 0);
        clear_interrupt_request = data;
        #(`TB_CYCLE * 1);
    end
    endtask;

    //
    // Task : Interrupt test
    //
    task TASK_INTERRUPT_TEST();
    begin
        #(`TB_CYCLE * 0);
        TASK_LEVEL_TRIGGER_INTERRUPT(8'b00000001);
        TASK_LEVEL_TRIGGER_INTERRUPT(8'b00000010);
        TASK_LEVEL_TRIGGER_INTERRUPT(8'b00000100);
        TASK_LEVEL_TRIGGER_INTERRUPT(8'b00001000);
        TASK_LEVEL_TRIGGER_INTERRUPT(8'b00010000);
        TASK_LEVEL_TRIGGER_INTERRUPT(8'b00100000);
        TASK_LEVEL_TRIGGER_INTERRUPT(8'b01000000);
        TASK_LEVEL_TRIGGER_INTERRUPT(8'b10000000);
        TASK_LEVEL_TRIGGER_INTERRUPT(8'b00000000);

        TASK_CLEAR_INTERRUPT_REQUEST(8'b11111111);
        TASK_CLEAR_INTERRUPT_REQUEST(8'b00000000);

        TASK_EDGE_TRIGGER_INTERRUPT(8'b10000000);
        TASK_EDGE_TRIGGER_INTERRUPT(8'b01000000);
        TASK_EDGE_TRIGGER_INTERRUPT(8'b00100000);
        TASK_EDGE_TRIGGER_INTERRUPT(8'b00010000);
        TASK_EDGE_TRIGGER_INTERRUPT(8'b00001000);
        TASK_EDGE_TRIGGER_INTERRUPT(8'b00000100);
        TASK_EDGE_TRIGGER_INTERRUPT(8'b00000010);
        TASK_EDGE_TRIGGER_INTERRUPT(8'b00000001);

        TASK_CLEAR_INTERRUPT_REQUEST(8'b11111111);
        TASK_CLEAR_INTERRUPT_REQUEST(8'b00000000);

        #(`TB_CYCLE * 1);
    end
    endtask;


    //
    // Test pattern
    //
    initial begin
        TASK_INIT();

        TASK_INTERRUPT_TEST();

        freeze = 1'b1;

        TASK_INTERRUPT_TEST();

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

