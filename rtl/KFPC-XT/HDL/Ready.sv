//
// KFPC-XT Ready_Signal
// Written by kitune-san
//
module READY (
    input   logic           clock,
    input   logic           cpu_clock,
    input   logic           reset,
    // CPU
    output  logic           processor_ready,
    // Bus Arbiter
    output  logic           dma_ready,
    input   logic           dma_wait_n,
    // I/O
    input   logic           io_channel_ready,
    input   logic           io_read_n,
    input   logic           io_write_n,
    input   logic           memory_read_n,
    input   logic           dma0_acknowledge_n,
    input   logic           address_enable_n
);

    //
    // CPU clock edge
    //
    logic   prev_cpu_clock;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_cpu_clock <= 1'b0;
        else
            prev_cpu_clock <= cpu_clock;
    end

    wire    cpu_clock_posedge = ~prev_cpu_clock & cpu_clock;
    wire    cpu_clock_negedge = prev_cpu_clock & ~cpu_clock;


    //
    // Ready/Wait Signal
    //
    logic   prev_bus_state;
    logic   ready_n_or_wait;
    logic   ready_n_or_wait_Qn;
    logic   prev_ready_n_or_wait;

    wire    bus_state = ~io_read_n | ~io_write_n | (dma0_acknowledge_n & ~memory_read_n & address_enable_n);

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_bus_state <= 1'b1;
        else
            prev_bus_state <= bus_state;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            ready_n_or_wait     <= 1'b1;
            ready_n_or_wait_Qn  <= 1'b0;
        end
        else if (~io_channel_ready & prev_ready_n_or_wait) begin
            ready_n_or_wait     <= 1'b1;
            ready_n_or_wait_Qn  <= 1'b1;
        end
        else if (~io_channel_ready & ~prev_ready_n_or_wait) begin
            ready_n_or_wait     <= 1'b1;
            ready_n_or_wait_Qn  <= 1'b0;
        end
        else if (io_channel_ready & prev_ready_n_or_wait) begin
            ready_n_or_wait     <= 1'b0;
            ready_n_or_wait_Qn  <= 1'b1;
        end
        else if (~prev_bus_state & bus_state) begin
            ready_n_or_wait     <= 1'b1;
            ready_n_or_wait_Qn  <= 1'b0;
        end
        else begin
            ready_n_or_wait     <= ready_n_or_wait;
            ready_n_or_wait_Qn  <= ready_n_or_wait_Qn;
        end
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_ready_n_or_wait    <= 1'b0;
        else if (cpu_clock_posedge)
            prev_ready_n_or_wait    <= ready_n_or_wait;
        else
            prev_ready_n_or_wait    <= prev_ready_n_or_wait;
    end


    //
    // Ready to DMA
    //
    assign  dma_ready = ~prev_ready_n_or_wait & ready_n_or_wait_Qn;


    //
    // Ready Signal (Instead of 8284)
    //
    logic   processor_ready_ff_1;
    logic   processor_ready_ff_2;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            processor_ready_ff_1    <= 1'b0;
        else if (cpu_clock_posedge)
            processor_ready_ff_1    <= dma_wait_n & ~ready_n_or_wait;
        else
            processor_ready_ff_1    <= processor_ready_ff_1;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            processor_ready_ff_2    <= 1'b0;
        else if (cpu_clock_negedge)
            processor_ready_ff_2    <= processor_ready_ff_1 & dma_wait_n & ~ready_n_or_wait;
        else
            processor_ready_ff_2    <= processor_ready_ff_2;
    end

    assign  processor_ready = processor_ready_ff_2;

endmodule

