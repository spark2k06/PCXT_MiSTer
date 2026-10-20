//
// Sound Blaster DMA glue
//
// Bridges the ao486-style synchronous DMA handshake that sound_dsp expects to
// the ISA-style DACK/IOW cycle the KF8237 actually runs in this core.
//
// The two do not match. ao486's DMA controller hands the peripheral its byte
// over a dedicated bus; the KF8237 does not - it drives MEMR and IOW and
// expects whoever owns DACK to take the byte off the bus itself. The floppy in
// this core is an ao486 module that was already adapted this way, and this
// module is the same bridge made reusable. Its shape is copied from
// Peripherals.sv rather than invented:
//
//   - the byte is captured while IOW is low, which is the only window in which
//     the memory drives it
//   - the acknowledge handed to the device is a single-cycle pulse on the
//     FALLING edge of DACK, not DACK itself, because the consumer expects one
//     pulse per transfer and the byte is settled by then
//   - the request is registered, dropped the moment DACK arrives so the
//     controller runs exactly one transfer per request, and only sampled on
//     cpu_ce_negedge
//
// sb_dma_cycle_tb establishes, against the real BUS_ARBITER and KF8237, that a
// channel-1 cycle really does present the programmed address with MEMR and IOW
// both low, which is what the capture below relies on.
//
// Unlike the floppy, the capture here is qualified by DACK. The floppy latches
// the bus on any IOW at all and gets away with it because the CPU is held off
// during a DMA cycle, so the last write it saw was the DMA one. Qualifying
// costs nothing and removes the need for that argument.
//
// Terminal count is deliberately not forwarded: sound_dsp has no dma_tc input,
// it counts its own block length. The 8237's count and the DSP's are two
// independent counters that the host is expected to program consistently.
//
module sb_dma_glue (
    input   logic           clock,
    input   logic           reset,
    input   logic           cpu_ce_negedge,

    // ISA side
    input   logic           dma_acknowledge,    // DACK for our channel, active high
    input   logic           io_write_n,
    input   logic   [7:0]   internal_data_bus,
    output  logic           dma_request,        // DREQ to the KF8237, active high

    // Device side (ao486 handshake)
    input   logic           device_dma_req,
    output  logic           device_dma_ack,
    output  logic   [7:0]   device_dma_readdata
);

    // Capture the memory byte during the DMA cycle's IOW window.
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            device_dma_readdata <= 8'h00;
        else if (dma_acknowledge && ~io_write_n)
            device_dma_readdata <= internal_data_bus;
    end

    // One-cycle acknowledge on the trailing edge of DACK.
    logic prev_dma_acknowledge;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_dma_acknowledge <= 1'b0;
        else
            prev_dma_acknowledge <= dma_acknowledge;
    end

    assign device_dma_ack = prev_dma_acknowledge & ~dma_acknowledge;

    // Request, dropped on acknowledge so one request buys one transfer.
    //
    // The ~device_dma_ack term is what stops a block overrunning by one
    // transfer, and it is not in the floppy's copy of this logic. The device
    // lowers its request in the same clock edge that the acknowledge pulse
    // appears, so on that edge device_dma_req still reads high. Reloading from
    // it there re-raises DREQ for a byte the device never asked for, and the
    // controller serves it - this core's KF8237 does not mask a channel at
    // terminal count, so nothing else stops the extra cycle. One sample too
    // many per block is audible, and sb_dma_stream_tb fails without this term.
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            dma_request <= 1'b0;
        else if (dma_acknowledge)
            dma_request <= 1'b0;
        else if (cpu_ce_negedge && ~device_dma_ack)
            dma_request <= device_dma_req;
    end

endmodule
