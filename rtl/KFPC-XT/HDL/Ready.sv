//
// KFPC-XT Ready_Signal
// Written by kitune-san
//
module READY (
    input   logic           clock,
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
    // Ready/Wait Signal
    //
    logic   ready_n_or_wait;
    logic   prev_bus_state;

    wire    bus_state = ~io_read_n | ~io_write_n | (dma0_acknowledge_n & ~memory_read_n & address_enable_n);

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_bus_state <= 1'b1;
        else
            prev_bus_state <= bus_state;
    end

    wire timing_to_check_ready = (~prev_bus_state) & (bus_state);

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            ready_n_or_wait <= 1'b1;
        else if (io_channel_ready)
            if ((ready_n_or_wait == 1'b0) && (timing_to_check_ready))
                ready_n_or_wait <= 1'b1;
            else
                ready_n_or_wait <= 1'b0;
        else
            ready_n_or_wait <= 1'b1;
    end

    //
    // Ready to DMA
    //
    assign  dma_ready = ~ready_n_or_wait;

    //
    // Ready Signal (Instead of 8284)
    //
    always_ff @(negedge clock, posedge reset) begin
        if (reset)
            processor_ready <= 1'b0;
        else
            processor_ready <= dma_wait_n & ~ready_n_or_wait;
    end

endmodule

