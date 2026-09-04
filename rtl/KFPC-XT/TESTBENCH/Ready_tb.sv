
`define TB_CYCLE        20
`define TB_FINISH_COUNT 20000

module READY_TEST_tm();

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
    initial clock = 1'b0;
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
    // READY runs on the chipset clock and receives the virtual CPU edges as
    // enables. Holding both asserted gives this legacy bench one CPU edge per
    // chipset clock.
    logic           cpu_ce_posedge;
    logic           cpu_ce_negedge;
    logic           io_read_n;
    logic           io_write_n;
    logic           dma0_acknowledge_n;
    logic           memory_read_n;
    logic           memory_write_n;
    logic           address_enable_n;   // AENBRD
    logic           io_channel_ready;
    logic           dma_wait_n;
    logic           dma_ready;
    logic           processor_ready;
    logic   [1:0]   clk_select;

    READY u_READY(.*);

    //
    // Scoreboard
    //
    // This bench used to drive stimulus and dump a waveform, with nothing that
    // could ever say FAIL. It now checks the one property the speed gate turns
    // on and off, so a regression in it is caught rather than eyeballed.
    //
    integer pass_count = 0;
    integer fail_count = 0;

    task automatic check(input string label, input logic got, input logic want);
    begin
        if (got !== want) begin
            fail_count = fail_count + 1;
            $display("FAIL  %s: processor_ready = %b, expected %b", label, got, want);
        end
        else begin
            pass_count = pass_count + 1;
            $display("PASS  %s", label);
        end
    end
    endtask

    // Run one bus cycle and report whether it ever made the CPU wait. Both
    // kinds are sampled the same way, so the I/O control is a real control.
    task automatic cycle_waits(input bit is_io, output logic waited);
    begin
        waited = 1'b0;
        address_enable_n = 1'b1;
        if (is_io) io_write_n     = 1'b0;
        else       memory_write_n = 1'b0;
        repeat (6) begin
            #(`TB_CYCLE);
            if (~processor_ready) waited = 1'b1;
        end
        io_write_n     = 1'b1;
        memory_write_n = 1'b1;
        #(`TB_CYCLE * 6);
    end
    endtask

    //
    // Task : Initialization
    //
    task TASK_INIT();
    begin
        #(`TB_CYCLE * 0);
        cpu_ce_posedge      = 1'b1;
        cpu_ce_negedge      = 1'b1;
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        memory_write_n      = 1'b1;
        address_enable_n    = 1'b1;
        io_channel_ready    = 1'b1;
        dma_wait_n          = 1'b1;
        clk_select          = 2'b11;
        #(`TB_CYCLE * 12);
    end
    endtask

    //
    // Test pattern
    //
    logic write_waited;

    initial begin
        TASK_INIT();
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b0;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b0;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b0;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;


        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b0;
        address_enable_n    = 1'b0;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b0;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b0;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b0;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b0;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b0;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b0;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;

        #(`TB_CYCLE * 12);
        io_channel_ready    = 1'b0;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b0;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 1);
        io_channel_ready    = 1'b1;
        #(`TB_CYCLE * 12);
        io_read_n           = 1'b0;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        io_read_n           = 1'b1;
        io_write_n          = 1'b1;
        dma0_acknowledge_n  = 1'b1;
        memory_read_n       = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 12);

        // Memory write.  This fork added the write term to bus_state so a
        // write arms the wait/ready flip-flop at the start of its cycle like
        // everything else; see docs/max-speed-stability.md, RC2.  Nothing
        // here drove memory_write_n before, so that term went unexercised.
        memory_write_n      = 1'b0;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 3);
        memory_write_n      = 1'b1;
        #(`TB_CYCLE * 3);
        memory_write_n      = 1'b0;
        address_enable_n    = 1'b0;
        #(`TB_CYCLE * 3);
        memory_write_n      = 1'b1;
        address_enable_n    = 1'b1;
        #(`TB_CYCLE * 12);

        // The write term is only armed at the fastest CPU speed setting. Below
        // it the command pulse outlasts the SDRAM transaction by three to five
        // times and the wait state is pure cost, so the same stimulus must
        // produce a wait at 2'b11 and none at the other three settings.
        clk_select = 2'b11;
        #(`TB_CYCLE * 4);
        cycle_waits(1'b0, write_waited);
        check("max speed: a memory write makes the CPU wait", write_waited, 1'b1);

        for (int unsigned sel = 0; sel < 3; sel++) begin
            clk_select = sel[1:0];
            #(`TB_CYCLE * 4);
            cycle_waits(1'b0, write_waited);
            check($sformatf("clk_select %0d: a memory write does not wait", sel),
                  write_waited, 1'b0);
        end

        // I/O must arm the flip-flop at every setting - the gate is on the
        // memory-write term alone, and gating the wrong one would still let
        // the checks above pass.
        clk_select = 2'b00;
        #(`TB_CYCLE * 4);
        cycle_waits(1'b1, write_waited);
        check("slow speed: an I/O write still waits", write_waited, 1'b1);

        $display("");
        $display("%0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0) $display("RESULT: PASS");
        else                 $display("RESULT: FAIL");

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

