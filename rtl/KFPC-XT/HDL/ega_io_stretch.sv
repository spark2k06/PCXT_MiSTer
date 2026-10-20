//
// KFPC-XT video I/O posted-write stretcher
//
// The video card lives in its own clock domain (28.636 MHz) and receives the
// I/O bus through per-bit two-stage synchronisers plus a two-identical-samples
// qualifier in ega_top. That crossing has no handshake: a write lands only if
// the IOW pulse stays low, with stable address and data, long enough for the
// far side to sample it twice - about 6 to 7 video clocks, 210-245 ns, in the
// worst case phase.
//
// At the PC/AT 3.5MHz speed setting the virtual 8088 runs at 25 MHz and an I/O
// write pulse is about 3 T-states plus the io_settle floor: near 200 ns. That
// sits exactly on the requirement, so whether any given write survives depends
// on the momentary phase between two free-running clocks - and on placement,
// which is why unrelated builds moved it. The writes software issues most are
// CRTC index/data pairs (cursor updates, one per character printed); a lost
// index desynchronises the pair and the data byte lands in whatever register
// the index last named. That is the slow on-screen corruption at this speed.
//
// This module makes the crossing correct by construction. A write is captured
// in the chipset domain, where the cycle is synchronous, and presented to the
// video domain as a pulse of guaranteed minimum width followed by a guaranteed
// minimum gap. While the CPU's own assertion persists the capture follows the
// live bus, so at the slower speeds - where the real pulse already exceeds the
// minimum - the presented cycle is the real one and nothing changes.
//
// Three details protect the corners:
//
//  * The captured cycle is presented with its address enable held active for
//    the whole synthetic pulse. The real cycle was a CPU cycle; if DMA takes
//    the bus while the tail of the pulse is still draining, the live AEN would
//    otherwise gate the decode off mid-write in ega_top.
//
//  * Reads are masked while a stretch is in flight. The presented address
//    still belongs to the captured write, and several video ports have read
//    side effects (3DAh resets the attribute flip-flop, 3C9h advances the DAC
//    read state), so a read strobe must not be seen against that address.
//
//  * access_ready backpressures any NEW I/O cycle that begins while a stretch
//    is draining, using the arm-at-cycle-start pattern the ready path already
//    relies on: the stall level is low before the new cycle's first clock, so
//    its wait states are armed in time. The cycle that produced the stretch is
//    never stalled by it.
//
module ega_io_stretch
    #(
        // 14 chipset clocks = 280 ns = 8 video clocks presented low;
        // 8 chipset clocks = 160 ns = 4.6 video clocks presented high.
        // Both clear the far side's worst case with margin.
        parameter int MIN_LOW_TICKS  = 14,
        parameter int MIN_HIGH_TICKS = 8,
        // Setup: how long address and data are presented, strobe still high,
        // before the write strobe is asserted. This was one chipset clock,
        // 20 ns, because the capture and the state change happened on the
        // same edge and only the registered output added a clock. 20 ns is
        // less than one 34.9 ns video clock, so on the far side the strobe
        // could land in the same sample as the data - or ahead of some of
        // it, since every bit crosses through its own synchroniser. The
        // two-identical-samples qualifier in ega_top then accepted a value
        // that was still half the previous write, and the card took one
        // write, exactly once, with the wrong byte in it.
        //
        // 6 chipset clocks = 120 ns covers two video clock samples plus a
        // full period of phase uncertainty, which is what the qualifier
        // needs to have settled on the real value before it sees the strobe.
        parameter int MIN_SETUP_TICKS = 6,
        // Read return: how long the CPU is held after a read has been
        // presented to the video domain, so the answer is on internal_data_bus
        // before the cycle ends.
        //
        // Reads had no completion signal at all. access_ready held the CPU
        // while a posted write drained, then went high the instant the bus was
        // free - which is not the same thing as the card having answered. The
        // round trip is two synchroniser stages out at 28.636 MHz, the
        // two-identical-samples qualifier in ega_top, the decode, and two
        // stages back at 50 MHz: measured at five to six chipset clocks from
        // the presented strobe. All the CPU ever got was io_settle_ticks, a
        // fixed four-clock floor in Chipset.sv that starts counting from the
        // CPU's own strobe rather than from when the read reached the card, so
        // a read issued behind a draining write lost even that.
        //
        // 12 chipset clocks = 240 ns covers the measured trip with margin, and
        // the counter starts when the read is actually presented, so a read
        // chasing a write waits from the right moment.
        parameter int READ_RETURN_TICKS = 12
    )
    (
        input   logic           clock,
        input   logic           reset,

        input   logic           io_write_n,
        input   logic           io_read_n,
        input   logic           address_enable_n,
        input   logic   [14:0]  address,
        input   logic   [7:0]   write_data,

        output  logic   [14:0]  video_address,
        output  logic   [7:0]   video_data,
        output  logic           video_io_write_n,
        output  logic           video_io_read_n,
        output  logic           video_address_enable_n,
        output  logic           access_ready
    );

    typedef enum logic [1:0] {
        IDLE,
        STRETCH_SETUP,
        STRETCH_LOW,
        STRETCH_HIGH
    } state_t;

    state_t         state;
    logic   [4:0]   ticks;
    // The current io_write_n assertion has been captured; cleared when the
    // strobe returns high. One assertion is captured exactly once.
    logic           strobe_seen;

    // Only accesses aimed at the video card need any of this. The crossing
    // this module protects - two synchroniser stages out at 28.636 MHz, the
    // two-identical-samples qualifier in ega_top, and two stages back at
    // 50 MHz - exists for the EGA/VGA register file and for nothing else. The
    // 8253, 8255, 8259, 8237, FDC, IDE, UART, RTC and OPL2 all answer inside
    // the 50 MHz chipset domain through short fixed pipelines, so holding them
    // for the video round trip buys nothing and costs a great deal: 12 clocks
    // on every read, and 28 on any write issued behind another one. Those
    // devices keep the io_settle_ticks floor in Chipset.sv, which is what they
    // were sized against.
    //
    // ega_top decodes 3B4/3B5/3BA, 3C0-3CF, 3D4/3D5/3DA and the 2Cx aliases.
    // 2Bx and 2Dx are folded in as margin: a port wrongly left on the slow
    // path only loses speed, while one wrongly taken off it loses the RC8
    // read-completion protection, so the bias belongs on the generous side.
    wire    [9:0] io_page   = address[13:4];
    wire    video_port      = (io_page == 10'h03B) | (io_page == 10'h03C)
                            | (io_page == 10'h03D) | (io_page == 10'h02B)
                            | (io_page == 10'h02C) | (io_page == 10'h02D);

    // The forwarded address and data still follow every I/O cycle, exactly as
    // they did before. Only the stalling is gated. Were video_address to stop
    // tracking non-video cycles it would go stale while video_io_read_n still
    // carried the raw strobe, and ega_top would answer a read that was never
    // addressed to it.
    wire    bus_write       = ~io_write_n & ~address_enable_n;
    wire    bus_read        = ~io_read_n  & ~address_enable_n;
    wire    cpu_write       = bus_write & video_port;
    wire    cpu_read        = bus_read  & video_port;
    wire    original_active = strobe_seen & ~io_write_n;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            state            <= IDLE;
            ticks            <= 5'd0;
            strobe_seen      <= 1'b0;
            video_address    <= 15'd0;
            video_data       <= 8'd0;
        end
        else begin
            if (io_write_n)
                strobe_seen <= 1'b0;

            case (state)
                IDLE: begin
                    // Same behaviour the live path had: the address holds
                    // under either strobe so reads keep theirs, the data
                    // follows only under the write strobe.
                    if (bus_write | bus_read)
                        video_address <= address;
                    if (bus_write)
                        video_data <= write_data;
                    if (cpu_write & ~strobe_seen) begin
                        strobe_seen <= 1'b1;
                        ticks       <= MIN_SETUP_TICKS[4:0];
                        state       <= STRETCH_SETUP;
                    end
                end

                STRETCH_SETUP: begin
                    // Address and data are presented and the strobe is still
                    // high. Keep tracking the live bus while the CPU is still
                    // driving its own assertion, exactly as STRETCH_LOW does,
                    // so nothing changes at the speeds where the real cycle is
                    // longer than everything here.
                    if (original_active) begin
                        video_address <= address;
                        video_data    <= write_data;
                    end
                    if (ticks != 5'd0)
                        ticks <= ticks - 5'd1;
                    else begin
                        ticks <= MIN_LOW_TICKS[4:0];
                        state <= STRETCH_LOW;
                    end
                end

                STRETCH_LOW: begin
                    // Track the live bus while the CPU still drives the
                    // original assertion, exactly as the live path did; the
                    // values freeze when the CPU moves on.
                    if (original_active) begin
                        video_address <= address;
                        video_data    <= write_data;
                    end
                    if (ticks != 5'd0)
                        ticks <= ticks - 5'd1;
                    else if (~original_active) begin
                        ticks <= MIN_HIGH_TICKS[4:0];
                        state <= STRETCH_HIGH;
                    end
                end

                STRETCH_HIGH: begin
                    if (ticks != 5'd0)
                        ticks <= ticks - 5'd1;
                    else
                        state <= IDLE;
                end

                default:
                    state <= IDLE;
            endcase
        end
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            video_io_write_n       <= 1'b1;
            video_io_read_n        <= 1'b1;
            video_address_enable_n <= 1'b1;
        end
        else begin
            video_io_write_n       <= ~(state == STRETCH_LOW);
            video_io_read_n        <= (state == IDLE) ? io_read_n : 1'b1;
            video_address_enable_n <= (state == IDLE) ? address_enable_n : 1'b0;
        end
    end

    // A new write is one whose assertion has not been captured yet. The
    // original write never stalls on its own stretch.
    wire    new_write_pending = cpu_write & ~strobe_seen;

    // Read completion. The counter is armed the moment the read is actually
    // presented to the video domain - which is when state reaches IDLE, since
    // video_io_read_n is masked until then - and not when the CPU raised its
    // strobe. That distinction is the whole point: a read issued behind a
    // draining write is presented late, and it has to be given the return trip
    // measured from there.
    logic           read_presented;
    logic   [4:0]   read_ticks;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            read_presented <= 1'b0;
            read_ticks     <= 5'd0;
        end
        else if (io_read_n) begin
            read_presented <= 1'b0;
            read_ticks     <= READ_RETURN_TICKS[4:0];
        end
        else if (~read_presented) begin
            if (state == IDLE) begin
                read_presented <= 1'b1;
                read_ticks     <= READ_RETURN_TICKS[4:0];
            end
        end
        else if (read_ticks != 5'd0)
            read_ticks <= read_ticks - 5'd1;
    end

    wire    read_incomplete = cpu_read & (~read_presented | (read_ticks != 5'd0));

    assign  access_ready = ((state == IDLE) | ~(new_write_pending | cpu_read))
                         & ~read_incomplete;

endmodule
