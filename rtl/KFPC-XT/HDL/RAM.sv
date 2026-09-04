//
// MiSTer PCXT RAM
// Ported by @spark2k06
//
// Based on KFPC-XT written by @kitune-san
//
`ifndef SYSTEM_VARIANT_TANDY
`define SYSTEM_VARIANT_TANDY 0
`endif
`ifndef ROM_VARIANT_TANDY
`define ROM_VARIANT_TANDY `SYSTEM_VARIANT_TANDY
`endif
`ifndef ROM_IS_TANDY
`define ROM_IS_TANDY `ROM_VARIANT_TANDY
`endif

module RAM (
    input   logic           clock,
    input   logic           reset,
    input   logic           enable_sdram,
    output  logic           initilized_sdram,
    // I/O Ports
    input   logic   [19:0]  address,
    input   logic   [7:0]   internal_data_bus,
    output  logic   [7:0]   data_bus_out,
    // Private 16-bit path for an 8086 bus cycle (steps 1 and 5 of
    // docs/8086-adaptation.md). It transfers two consecutive low-lane bytes
    // in one SDRAM burst while the chipset's public bus remains eight bits.
    //
    // Contract: either word request may only be asserted for an EVEN address.
    // That is not a restriction in practice - an 8086 splits a word access at
    // an odd offset into two byte cycles anyway, and offset parity equals
    // linear parity because a segment base is always a multiple of 16 - and it
    // is what makes the burst safe without a single extra gate. The SDRAM
    // column adder wraps inside its row, so a burst of two is only correct
    // when the first column is not 511; an even address has an even column,
    // which is at most 510. The same evenness rules out straddling an EMS,
    // UMB or video decode boundary, since every one of those is 16KB-aligned.
    input   logic           word_read_request,
    input   logic           word_write_request,
    input   logic   [15:0]  data_bus_in_word,
    output  logic   [15:0]  data_bus_out_word,
    input   logic           memory_read_n,
    input   logic           memory_write_n,
    input   logic           no_command_state,
    output  logic           memory_access_ready,
    output  logic           ram_address_select_n,
    // SDRAM
    output  logic   [12:0]  sdram_address,
    output  logic           sdram_cke,
    output  logic           sdram_cs,
    output  logic           sdram_ras,
    output  logic           sdram_cas,
    output  logic           sdram_we,
    output  logic   [1:0]   sdram_ba,
    input   logic   [15:0]  sdram_dq_in,
    output  logic   [15:0]  sdram_dq_out,
    output  logic           sdram_dq_io,
    output  logic           sdram_ldqm,
    output  logic           sdram_udqm,
     // EMS
     input   logic   [6:0]   map_ems[0:3],
     input   logic           ems_b1,
     input   logic           ems_b2,
     input   logic           ems_b3,
     input   logic           ems_b4,
     // BIOS
     input  logic    [1:0]  bios_protect_flag,
     input  logic           tandy_bios_flag,
    // Optional flags
    input  logic           enable_a000h,
    // Wait mode
    input   logic           wait_count_clk_en,
    input   logic   [1:0]   ram_read_wait_cycle,
    input   logic   [1:0]   ram_write_wait_cycle,
    // CPU speed setting (0 - 4.77MHz, 1 - 7.16MHz, 2 - 9.54MHz, 3 - max)
    input   logic   [1:0]   clk_select
);

    typedef enum {IDLE, RAM_WRITE_1, RAM_WRITE_2, RAM_READ_1, RAM_READ_2, COMPLETE_RAM_RW, WAIT} state_t;

    state_t         state;
    state_t         next_state;
    logic   [21:0]  decoded_address;
    logic   [21:0]  latch_address;
    logic   [7:0]   latch_data;
    logic   [15:0]  latch_data_word;
    logic           write_command;
    logic           read_command;
    logic           prev_no_command_state;
    logic           enable_refresh;
    logic           write_protect;
    logic           tandy_bios_select;

    logic   [1:0]   read_wait_count;
    logic   [1:0]   write_wait_count;
    logic           access_ready;

    //
    // Sequential read lookahead
    //
    // Every access here is one byte and every byte costs a full SDRAM
    // transaction: ACTIVE, one column command, PRECHARGE. With trp = 0 and
    // CL = 2 that is 7 chipset clocks per byte, and on an 8-bit bus with a
    // four-byte prefetch queue roughly half of all bus traffic is sequential
    // instruction fetch, which asks for byte N and then byte N+1.
    //
    // Reading two words in one burst costs one extra clock in KFSDRAM's READ
    // state and saves the whole ACTIVE and PRECHARGE of the second access:
    // 8 clocks for two bytes instead of 14. The second byte is parked here with
    // the address it belongs to, and the next access is answered from the latch
    // without touching the SDRAM at all.
    //
    // Correctness rests on three things:
    //
    //  * Every write reaches this module. The chipset has one memory bus and
    //    the arbiter drives it for the CPU, for DMA and for the HPS BIOS
    //    loader alike, so there is no master that can change SDRAM behind the
    //    latch's back. Invalidation is by address, not wholesale, so a write
    //    stream to one buffer does not keep flushing a read stream from
    //    another - which is exactly what rep movsb does.
    //
    //  * The addresses compared are the decoded ones, after the EMS window has
    //    been resolved. Two different logical addresses that map to the same
    //    physical word are the same entry, and remapping a bank does not make
    //    the parked byte wrong, because the byte belongs to the physical
    //    address.
    //
    //  * KFSDRAM's burst counter is the column adder, `address[8:0] +
    //    access_counter`, so a burst that starts at column 511 wraps to column
    //    0 of the SAME row rather than advancing to the next one. That second
    //    word is not address+1, so the lookahead is suppressed there.
    //
    // A write-protected region is deliberately not invalidated: write_command
    // already excludes it, the write never reaches the memory, and the parked
    // byte is still what is there.
    //
    // Two entries, because one is not enough to survive real code.
    //
    // Every read that is allowed to park overwrites the entry, and an
    // instruction fetch is a memory read like any other. With a single entry,
    // the byte parked by a data read is gone before the next data read asks for
    // it, because the BIU refilled its queue in between. That leaves the latch
    // working only where the bus does one thing at a time - inside a REP string
    // operation, or a straight run of fetch - and doing nothing at all in code
    // that interleaves the two, which is most code.
    //
    // Two entries with round-robin replacement need no help from the BIU to
    // tell code from data. The two streams alternate on the bus by themselves,
    // so they land in different entries and stay there:
    //
    //   fetch A   miss, park A+1 -> entry 0
    //   data  D   miss, park D+1 -> entry 1
    //   fetch A+1 HIT entry 0
    //   data  D+1 HIT entry 1
    //
    // Nothing about correctness rests on the replacement policy. A hit still
    // requires an exact address match against a valid entry, and a write still
    // clears any entry it lands on, so the worst a bad victim choice can do is
    // cost a transaction.
    logic   [21:0]  lookahead_address_0;    // Byte address entry 0 can answer
    logic   [21:0]  lookahead_address_1;
    logic   [7:0]   lookahead_data_0;
    logic   [7:0]   lookahead_data_1;
    logic   [1:0]   lookahead_valid;
    logic           lookahead_victim;       // Which entry the next park replaces
    logic           read_beat;              // 0 = first word of the burst, 1 = second
    logic           prefetch_armed;         // This transaction was issued as a burst of two
    logic           word_armed;             // ...and the second word is being delivered, not parked
    logic           write_word_armed;       // Two emulated bytes are being written in one SDRAM burst
    logic           write_beat;             // 0 = low byte, 1 = high byte
    logic   [7:0]   data_bus_out_hi;

    // Only the two fastest settings take the burst. The two slowest ones are
    // the cycle-accurate settings, and there the bus already has slack: at
    // 4.77MHz the profiler measures no change at all, and at 7.16MHz the burst
    // is a net loss of about 1.6 chipset clocks per byte. A CPU cycle there is
    // 6.98 chipset clocks, so the one extra clock the burst spends inside
    // KFSDRAM's READ state can cross the point where READY is sampled and cost
    // a whole T-state on every miss - more than the hits give back. At 9.54MHz
    // and above the cycle is short enough that the extra clock stays inside it,
    // and the burst gains 1.5 and 3.0 clocks per byte respectively.
    //
    // clk_select is registered on this same clock at the top level, so this is
    // not a clock crossing, and it only changes on biu_done, between bus
    // cycles. Both the issue side and the answer side are gated, so with the
    // burst off this module behaves exactly as it did before it existed.
    wire            lookahead_enable   = clk_select[1];

    // The column adder wraps within the row, so the word after column 511 is
    // not the next byte. Ask for one word there.
    wire            lookahead_possible = lookahead_enable & (decoded_address[8:0] != 9'h1FF);

    wire            lookahead_hit_0    = lookahead_enable & lookahead_valid[0]
                                       & (decoded_address == lookahead_address_0);
    wire            lookahead_hit_1    = lookahead_enable & lookahead_valid[1]
                                       & (decoded_address == lookahead_address_1);
    wire            word_request       = read_command & word_read_request;
    wire            write_word_request = write_command & word_write_request;

    // A word access needs both halves, and the latch can only ever hold one of
    // them, so a hit on the low byte would leave the high one unfetched. Take
    // the SDRAM read instead - one burst answers the whole word.
    wire            lookahead_hit      = ~word_request
                                       & (lookahead_hit_0 | lookahead_hit_1);

    // Entry 0 is checked first; the two addresses can never both match, since
    // an address is only parked into one entry and a park into the other would
    // have to match it to collide.
    wire    [7:0]   lookahead_answer   = lookahead_hit_0 ? lookahead_data_0
                                                         : lookahead_data_1;

    // What a read leaving IDLE will do. Registered into prefetch_armed on the
    // same edge, so access_num is stable for the whole transaction.
    //
    // A word bursts unconditionally: it is not speculation, both halves were
    // asked for. In particular it does not consult lookahead_enable, because
    // an 8086 has a 16-bit bus at every speed setting - the gate exists to
    // keep a throughput guess out of the cycle-accurate settings, and this is
    // not a guess.
    wire            start_prefetch     = read_command & ~word_request
                                       & lookahead_possible & ~lookahead_hit;
    wire            start_word         = word_request;
    wire            start_word_write   = write_word_request;

    //
    // RAM Address Select (0x00000-0xAFFFF and 0xC0000-0xFFFFF)
    //
    assign ram_address_select_n = ~(enable_sdram && ~(address[19:16] == 4'b1011) &&  // B0000h reserved for VRAM
	                               ~(~enable_a000h && address[19:16] == 4'b1010));    // A0000h is optional
	 

    assign tandy_bios_select    = `ROM_IS_TANDY ? (tandy_bios_flag & (address[19:16] == 4'b1111)) : 1'b0;


    //
    // Write protect
    //
    assign write_protect = bios_protect_flag[1] & (address[19:16] == 4'b1111)
                         | bios_protect_flag[0] & (address[19:14] == 6'b111011);


    //
    // I/O Ports
    //
    // Address
    always_comb begin
        if (ems_b1)
            decoded_address = {1'b1, map_ems[0], address[13:0]};
        else if (ems_b2)
            decoded_address = {1'b1, map_ems[1], address[13:0]};
        else if (ems_b3)
            decoded_address = {1'b1, map_ems[2], address[13:0]};
        else if (ems_b4)
            decoded_address = {1'b1, map_ems[3], address[13:0]};
        else
            decoded_address = {1'b0, tandy_bios_select, address};
    end

    // Keep the address after the bus cycle has released MEMW. KFSDRAM needs
    // the live decoded value for ACTIVE on the acceptance edge (while this
    // register still contains the previous access), then uses this copy for
    // the column command and the rest of the transaction.
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            latch_address <= 22'd0;
        else if (state == IDLE)
            latch_address <= decoded_address;
    end

    // Data
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            latch_data      <= 0;
        else
            latch_data      <= internal_data_bus;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            latch_data_word <= 16'h0000;
        else if (state == IDLE)
            latch_data_word <= data_bus_in_word;
    end

    // Write Command
    assign write_command = ~ram_address_select_n & ~memory_write_n & ~write_protect;

    // Read Command
    assign read_command  = ~ram_address_select_n & ~memory_read_n;

    // Generate refresh timing
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            prev_no_command_state   <= 1'b0;
        end
        else begin
            prev_no_command_state   <= no_command_state;
        end
    end

    assign  enable_refresh  = no_command_state & ~prev_no_command_state;


    //
    // SDRAM Controller
    //
    logic   [23:0]  access_address;
    logic   [8:0]   access_num;
    logic   [15:0]  access_data_in;
    logic   [15:0]  access_data_out;
    logic           write_request;
    logic           read_request;
    logic           write_flag;
    logic           read_flag;
    logic           idle;
    logic           refresh_mode;

    KFSDRAM u_KFSDRAM (
        .sdram_clock        (clock),
        .sdram_reset        (reset),
        .address            (access_address),
        .access_num         (access_num),
        .data_in            (access_data_in),
        .data_out           (access_data_out),
        .write_request      (write_request),
        .read_request       (read_request),
        .enable_refresh     (enable_refresh),
        .write_flag         (write_flag),
        .read_flag          (read_flag),
        .idle               (idle),
        .refresh_mode       (refresh_mode),
        .sdram_address      (sdram_address),
        .sdram_cke          (sdram_cke),
        .sdram_cs           (sdram_cs),
        .sdram_ras          (sdram_ras),
        .sdram_cas          (sdram_cas),
        .sdram_we           (sdram_we),
        .sdram_ba           (sdram_ba),
        .sdram_dq_in        (sdram_dq_in),
        .sdram_dq_out       (sdram_dq_out),
        .sdram_dq_io        (sdram_dq_io)
    );


    //
    // State machine
    //
    always_comb begin
        next_state = state;
        casez (state)
            IDLE: begin
                if (write_command)
                    next_state = RAM_WRITE_1;
                else if (read_command) begin
                    // A hit never reaches the SDRAM. COMPLETE_RAM_RW is where
                    // access_ready is raised and where it waits for the CPU to
                    // release the strobe, which is exactly what is wanted.
                    //
                    // Spelled out rather than written as a ternary: Icarus
                    // rejects a conditional whose arms are enum values with
                    // "this assignment requires an explicit cast", which is
                    // what keeps the KF8237 benches from elaborating.
                    if (lookahead_hit)
                        next_state = COMPLETE_RAM_RW;
                    else
                        next_state = RAM_READ_1;
                end
            end
            // Once accepted, a write owns its address and byte and must reach
            // SDRAM even if the short 25 MHz MEMW pulse has already ended.
            // Reads still abort below because their result has no recipient
            // after MEMR is released.
            RAM_WRITE_1: begin
                if (write_flag)
                    next_state = RAM_WRITE_2;
            end
            RAM_WRITE_2: begin
                if (~write_flag)
                    next_state = COMPLETE_RAM_RW;
            end
            RAM_READ_1: begin
                if (~read_command)
                    next_state = WAIT;
                if (read_flag)
                    next_state = RAM_READ_2;
            end
            RAM_READ_2: begin
                if (~read_command)
                    next_state = WAIT;
                if (~read_flag)
                    next_state = COMPLETE_RAM_RW;
            end
            COMPLETE_RAM_RW: begin
                if ((~write_command) && (~read_command))
                    next_state = IDLE;
            end
            WAIT: begin
                if (idle)
                    next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            initilized_sdram <= 1'b0;
        else if (idle)
            initilized_sdram <= 1'b1;
        else
            initilized_sdram <= initilized_sdram;
    end


    //
    // Output SDRAM Control Signals
    //
    always_comb begin
        casez (state)
            IDLE: begin
                // KFSDRAM captures row/bank on the same edge that RAM latches
                // this access. The registered address is therefore still one
                // cycle old here; use the live decode for ACTIVE only.
                access_address  = {2'b00, decoded_address};
                access_num      = (start_prefetch | start_word | start_word_write) ? 9'h002 : 9'h001;
                access_data_in  = write_word_request
                                ? {8'h00, data_bus_in_word[7:0]}
                                : {8'h00, latch_data};
                write_request   = write_command ? 1'b1 : 1'b0;
                read_request    = (read_command & ~lookahead_hit) ? 1'b1 : 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_WRITE_1: begin
                access_address  = {2'b00, latch_address};
                access_num      = write_word_armed ? 9'h002 : 9'h001;
                access_data_in  = write_word_armed
                                ? {8'h00, write_beat ? latch_data_word[15:8]
                                                     : latch_data_word[7:0]}
                                : {8'h00, latch_data};
                write_request   = 1'b1;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_WRITE_2: begin
                access_address  = {2'b00, latch_address};
                access_num      = write_word_armed ? 9'h002 : 9'h001;
                access_data_in  = write_word_armed
                                ? {8'h00, write_beat ? latch_data_word[15:8]
                                                     : latch_data_word[7:0]}
                                : {8'h00, latch_data};
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_READ_1: begin
                access_address  = {2'b00, latch_address};
                access_num      = (prefetch_armed | word_armed) ? 9'h002 : 9'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b1;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_READ_2: begin
                access_address  = {2'b00, latch_address};
                access_num      = (prefetch_armed | word_armed) ? 9'h002 : 9'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            COMPLETE_RAM_RW: begin
                access_address  = 24'h000000;
                access_num      = 9'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            WAIT: begin
                access_address  = 24'h000000;
                access_num      = 9'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b1;
                sdram_udqm      = 1'b1;
            end
        endcase
    end


    //
    // Databus Out
    //
    logic   [7:0]   data_bus_out_reg;

    // Which word of the burst is on access_data_out. KFSDRAM raises read_flag
    // once per word, so in a burst of two the first pulse is the byte the CPU
    // asked for and the second is the one being parked.
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            read_beat <= 1'b0;
        else if (state == IDLE)
            read_beat <= 1'b0;
        else if (read_flag)
            read_beat <= 1'b1;
    end

    // Whether the transaction in flight asked for two words. Sampled where the
    // decision is made so access_num cannot change under KFSDRAM mid-burst,
    // which would move the column count and the completion test with it.
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prefetch_armed <= 1'b0;
        else if (state == IDLE)
            prefetch_armed <= start_prefetch;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            word_armed <= 1'b0;
        else if (state == IDLE)
            word_armed <= start_word;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            write_word_armed <= 1'b0;
        else if (state == IDLE)
            write_word_armed <= start_word_write;
    end

    // KFSDRAM presents write_flag for each beat. Its first WRITE edge samples
    // the low byte; advancing this local selector on that edge presents the
    // high byte for the second beat without changing KFSDRAM's interface.
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            write_beat <= 1'b0;
        else if (state == IDLE)
            write_beat <= 1'b0;
        else if (write_flag)
            write_beat <= 1'b1;
    end

    // The high half. The low half is data_bus_out_reg, which the byte path
    // already registers on the first beat; this is the same store one beat
    // later. Both are settled before COMPLETE_RAM_RW raises access_ready, so
    // the word needs none of the combinational bypass the byte path has.
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            data_bus_out_hi <= 8'h00;
        else if (read_flag && read_beat && word_armed)
            data_bus_out_hi <= access_data_out[7:0];
    end

    assign  data_bus_out_word = {data_bus_out_hi, data_bus_out_reg};

    // synthesis translate_off
    // The evenness contract, checked where it is cheap to check. A word read
    // at an odd address would still return the right two bytes everywhere
    // except column 511, where the burst wraps to the start of the same row -
    // which is exactly the kind of once-per-512 corruption that is worth
    // catching in simulation rather than on hardware.
    always_ff @(posedge clock) begin
        if (!reset && (state == IDLE) && word_request && decoded_address[0])
            $display("%0t RAM: WORD READ AT ODD ADDRESS %05h - contract violated",
                     $time, decoded_address);
        if (!reset && (state == IDLE) && write_word_request && decoded_address[0])
            $display("%0t RAM: WORD WRITE AT ODD ADDRESS %05h - contract violated",
                     $time, decoded_address);
    end
    // synthesis translate_on

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            data_bus_out_reg    <= 8'h00;
        else if ((state == IDLE) && read_command && lookahead_hit)
            data_bus_out_reg    <= lookahead_answer;
        else if (read_flag && ~read_beat)
            data_bus_out_reg    <= access_data_out[7:0];
        else
            data_bus_out_reg    <= data_bus_out_reg;
    end

    // The same combinational bypass the live path always had, but only for the
    // word the CPU asked for: on the lookahead word access_data_out belongs to
    // the NEXT address and must not reach the bus.
    assign  data_bus_out = ~read_command            ? 8'h00
                         : (read_flag & ~read_beat) ? access_data_out[7:0]
                         :                            data_bus_out_reg;


    //
    // The lookahead latch
    //
    // A hit does not consume the entry. Re-reading the same byte is still a
    // hit, and the only thing that can make the parked byte wrong is a write
    // landing on it.
    //
    // Invalidation is done where the write is accepted rather than for as long
    // as the strobe is asserted: in IDLE decoded_address is the address being
    // captured into latch_address on this very edge, so it is the address the
    // write will actually reach. Later in the write it tracks the live bus and
    // no longer means that.
    //
    // Invalidation looks at both entries and the park writes one of them. The
    // two cannot collide: a park happens on read_flag, which cannot be asserted
    // while this module is in IDLE accepting a write.
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            lookahead_valid     <= 2'b00;
            lookahead_victim    <= 1'b0;
            lookahead_address_0 <= 22'd0;
            lookahead_address_1 <= 22'd0;
            lookahead_data_0    <= 8'h00;
            lookahead_data_1    <= 8'h00;
        end
        else begin
            if ((state == IDLE) && write_command) begin
                if (lookahead_valid[0] && (decoded_address == lookahead_address_0))
                    lookahead_valid[0] <= 1'b0;
                if (lookahead_valid[1] && (decoded_address == lookahead_address_1))
                    lookahead_valid[1] <= 1'b0;
                if (write_word_request) begin
                    if (lookahead_valid[0] && ((decoded_address + 22'd1) == lookahead_address_0))
                        lookahead_valid[0] <= 1'b0;
                    if (lookahead_valid[1] && ((decoded_address + 22'd1) == lookahead_address_1))
                        lookahead_valid[1] <= 1'b0;
                end
            end

            // prefetch_armed and word_armed are mutually exclusive by
            // construction, so a word transaction parks nothing. The byte it
            // fetched second is on its way to the CPU, and spending an entry
            // on a byte the CPU already holds would evict something useful.
            if (read_flag && read_beat && prefetch_armed) begin
                if (lookahead_victim == 1'b0) begin
                    lookahead_address_0 <= latch_address + 22'd1;
                    lookahead_data_0    <= access_data_out[7:0];
                    lookahead_valid[0]  <= 1'b1;
                end
                else begin
                    lookahead_address_1 <= latch_address + 22'd1;
                    lookahead_data_1    <= access_data_out[7:0];
                    lookahead_valid[1]  <= 1'b1;
                end
                lookahead_victim <= ~lookahead_victim;
            end
        end
    end


    //
    // Ready/Wait Signal
    //
    // Two policies, chosen by CPU speed.
    //
    // Open loop (the original): readiness stays high through the whole access
    // unless a refresh was already in progress when the command was decoded.
    // It bets that the bus cycle always outlasts the SDRAM transaction and
    // never makes the CPU wait for the answer. Below the fastest setting that
    // bet is safe with room to spare - at 4.77MHz the cycle is 44 chipset
    // clocks against 7 for the transaction - and refresh_mode covers the one
    // case where it is not.
    //
    // Closed loop: not ready as soon as a command is decoded in IDLE, ready
    // again only at COMPLETE_RAM_RW, i.e. after the SDRAM side has actually
    // finished. At the fastest setting the write command pulse is about two
    // CPU clocks and can close before the controller has issued the write,
    // silently dropping it, so there the bet does not hold and the handshake
    // has to be real.
    //
    // Charging the closed loop to every setting adds an unnecessary wait state
    // to every memory cycle at 4.77MHz while leaving I/O cycles unchanged.
    wire    strict_ready = (clk_select == 2'b11);

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            access_ready <= 1'b0;
        else if (state == COMPLETE_RAM_RW)
            access_ready <= 1'b1;
        else if (state == IDLE)
            access_ready <= idle & ~(strict_ready & (write_command | read_command));
        else if (strict_ready)
            access_ready <= 1'b0;
        else if ((write_command | read_command) & refresh_mode)
            access_ready <= 1'b0;
        else
            access_ready <= access_ready;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            read_wait_count     <= 0;
        else if (~read_command)
            read_wait_count     <= ram_read_wait_cycle;
        else if ((wait_count_clk_en) && (read_wait_count != 0))
            read_wait_count     <= read_wait_count - 1;
        else
            read_wait_count     <= read_wait_count;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            write_wait_count    <= 0;
        else if (~write_command)
            write_wait_count    <= ram_write_wait_cycle;
        else if ((wait_count_clk_en) && (write_wait_count != 0))
            write_wait_count    <= write_wait_count - 1;
        else
            write_wait_count    <= write_wait_count;
    end

    assign  memory_access_ready = ((~ram_address_select_n) && ((~memory_read_n) || (~memory_write_n)))
                                        ? (access_ready & ((read_wait_count==0) || (~read_command)) & ((write_wait_count==0) || (~write_command))) : 1'b1;

endmodule
