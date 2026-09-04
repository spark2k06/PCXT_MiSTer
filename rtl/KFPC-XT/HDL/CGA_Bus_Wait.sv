//
// IBM CGA memory-bus wait-state generator.
//
// The video sequencer fetches from VRAM at phases 1..3 and 17..19 of
// every 32-dot cycle.  A CPU access can start after either fetch and must
// not be held for a complete sequencer turn: doing so makes write-heavy
// software much slower than a real CGA.  READY is therefore released at
// the beginning of the next free ISA window, phase 5 or phase 21.
//
// Besides bounding the wait, keeping the release tied to a real VRAM slot
// preserves the CPU/DMA/CGA phase relationship used by cycle-counted code
// such as the Kefrens part of 8088 MPH.
//
module CGA_BUS_WAIT (
    input   logic           clock,
    input   logic           reset,
    input   logic   [4:0]   sequencer_phase,
    input   logic           memory_select,
    input   logic           memory_read_n,
    input   logic           memory_write_n,
    output  logic           ready
);

    typedef enum logic [1:0] {WAIT_IDLE, WAIT_FETCH, WAIT_DONE} wait_state_t;
    wait_state_t wait_state = WAIT_IDLE;

    wire memory_cycle = memory_select & (~memory_read_n | ~memory_write_n);
    wire fetch_start = (sequencer_phase == 5'd1)
                    | (sequencer_phase == 5'd17);
    wire fetch_end = (sequencer_phase == 5'd4)
                  | (sequencer_phase == 5'd20);

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            wait_state <= WAIT_IDLE;
            ready      <= 1'b1;
        end
        else if (~memory_cycle) begin
            wait_state <= WAIT_IDLE;
            ready      <= 1'b1;
        end
        else begin
            case (wait_state)
                WAIT_IDLE: begin
                    if (fetch_start)
                        wait_state <= WAIT_FETCH;
                    ready <= 1'b0;
                end

                WAIT_FETCH: begin
                    if (fetch_end)
                        wait_state <= WAIT_DONE;
                    ready <= 1'b0;
                end

                WAIT_DONE: begin
                    wait_state <= WAIT_DONE;
                    ready      <= 1'b1;
                end

                default: begin
                    wait_state <= WAIT_IDLE;
                    ready      <= 1'b0;
                end
            endcase
        end
    end

endmodule
