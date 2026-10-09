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
// Clock domains
//
// The sequencer runs on the CGA clock and the bus cycle and READY live on
// the chipset clock. The two come from different PLLs, and although they
// share a reference their edges can fall arbitrarily close together, so
// nothing may cross between them unsynchronized. Only one level crosses
// here: whether a sequencer fetch window is open. It is registered in the
// CGA domain and goes through a two-flop synchronizer; the state machine and
// READY itself run entirely on the chipset clock.
//
// An earlier version ran the state machine on the CGA clock and sampled the
// bus cycle directly. Synthesis encodes it one-hot without illegal-state
// recovery, and a bus cycle starting on a fetch-start edge could be seen by
// one state flop and not another. That left the machine in no state with
// READY low for as long as the access lasted, which is forever: the CPU
// hung on the CGA access.
//
// The window is registered one sequencer phase early (phases 0..3 and
// 16..19) so the synchronizer latency is absorbed and READY still returns
// in the phase-5/21 slot as seen from the chipset.
//
module CGA_BUS_WAIT (
    input   logic           clock,
    input   logic           video_clock,
    input   logic           reset,
    input   logic   [4:0]   sequencer_phase,    // video_clock domain
    input   logic           memory_select,
    input   logic           memory_read_n,
    input   logic           memory_write_n,
    output  logic           ready
);

    //
    // CGA clock domain: fetch window level
    //
    logic fetch_window = 1'b0;

    always_ff @(posedge video_clock)
        fetch_window <= (sequencer_phase[3:0] <= 4'd3);

    //
    // Chipset clock domain
    //
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [1:0] fetch_window_sync = 2'b00;
    logic       fetch_window_prev = 1'b0;

    always_ff @(posedge clock)
        fetch_window_sync <= {fetch_window_sync[0], fetch_window};

    wire fetch_open  = fetch_window_sync[1];
    wire fetch_start = fetch_open & ~fetch_window_prev;

    typedef enum logic [1:0] {WAIT_IDLE, WAIT_FETCH, WAIT_DONE} wait_state_t;
    wait_state_t wait_state = WAIT_IDLE;

    wire memory_cycle = memory_select & (~memory_read_n | ~memory_write_n);

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            wait_state        <= WAIT_IDLE;
            fetch_window_prev <= 1'b0;
        end
        else begin
            fetch_window_prev <= fetch_open;

            if (~memory_cycle)
                wait_state <= WAIT_IDLE;
            else begin
                case (wait_state)
                    WAIT_IDLE:  if (fetch_start) wait_state <= WAIT_FETCH;
                    WAIT_FETCH: if (~fetch_open) wait_state <= WAIT_DONE;
                    WAIT_DONE:  wait_state <= WAIT_DONE;
                    default:    wait_state <= WAIT_IDLE;
                endcase
            end
        end
    end

    // READY drops in the same chipset cycle that a CGA access starts, and is
    // returned as soon as the synchronized fetch window has closed.
    assign ready = ~memory_cycle
                 | (wait_state == WAIT_DONE)
                 | ((wait_state == WAIT_FETCH) & ~fetch_open);

endmodule
