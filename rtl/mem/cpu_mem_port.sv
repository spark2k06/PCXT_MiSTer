//
// CPU memory port: the chipset side of system memory. It keeps
// the contract RAM.sv had with the chipset bus - memory_access_ready, the
// private 16-bit path of an 8086 bus cycle, and writes that are owned once
// accepted even if MEMW ends first - and turns each access into an
// sdram_port transaction through sdram_xbridge.
//
// What changed from RAM.sv:
//
//  * Storage is packed: two bytes per 16-bit SDRAM word, the even one
//    in the low lane. A byte write is a one-word write with one byte enable;
//    an 8086 word (always at an even address, see below) is one word.
//
//  * The physical address comes from mem_map; this module knows no machine.
//
//  * Readiness is closed loop, but late. READY.sv turns any dip of
//    memory_access_ready, however short and wherever in the bus cycle, into a
//    whole wait state, so a dip at the strobe (when the data is not yet in
//    data_reg, even a clock before it arrives) costs the CPU a clock on every
//    read. Below Max the readiness therefore stays high until the last chipset
//    clock in which a wait state can still be requested (the one before the
//    CPU clock falling edge at which READY decides, see dip_ok) and only dips
//    then if the access has still not been accepted (write) or answered
//    (read). RAM.sv gave no wait states there either; at Max it is closed loop
//    from the strobe, as RAM.sv was. This is what keeps 4.77 and 7.16 MHz
//    exactly as they were (cpu_sdram_e2e_tb, with the READY of the real
//    chipset: AEN low for CPU cycles).
//
//  * Writes are posted: accepted at once (ready stays high), carried out in
//    the background. A following access waits only if the bridge is still
//    busy with it.
//
//  * The lookahead keeps two lines of up to four words each (eight bytes)
//    instead of two single bytes. A read that misses fetches the requested
//    word and, at the two fastest settings, the words after it: 2 at 9.54 MHz
//    and 4 at Max (clipped at the end of the 512-word row). At 4.77 and
//    7.16 MHz only the word itself is read, but its second byte is still
//    kept. Writes update a line they fall in instead of invalidating it, and
//    a ROM-loader write (flush) clears both lines.
//
//  * Committed writes are published on the snoop port (chipset clock domain).
//    The video fetch engines do not use it: they take the writes as the
//    arbiter captures them, which is the order that matters (F2).
//
//  * Video memory (F2). mem_map says when an address is CGA or HGC memory. Such
//    accesses are byte-wide and have no RAM wait states (the CGA has its own,
//    CGA_BUS_WAIT, outside this module). A CGA write is accepted at once but only
//    sent to the SDRAM when MEMW ends, because that is the moment the CGA
//    BRAM used to take it and the video side sees the write from the moment
//    the arbiter captures it: raster-timed code depends on that instant. An HGC
//    write is sent as soon as it is accepted, as RAM writes are. An address
//    that is both CGA and HGC memory (HGC graphics page 1 at B8000) is written
//    in both places, one after the other.
//
//  * A CPU read may start before its strobe (early_read): the chipset raises
//    it once the address of a memory read or code fetch has been latched in
//    T1, about one CPU clock before MEMR. The line goes into the lookahead,
//    and the strobe then finds it there or waits for it. It is only a read
//    of memory that has no side effects, so a wrong guess costs nothing but
//    the transaction. With the controller on its own clock this is what
//    keeps 7.16 MHz free of extra wait states (see cpu_sdram_e2e_tb).
//
// The 8086 word contract is unchanged: a word request only ever comes for an
// even address, so it is always exactly one SDRAM word.
//
module cpu_mem_port (
    input  logic        clock,
    input  logic        reset,

    // Chipset bus
    input  logic [7:0]  internal_data_bus,
    output logic [7:0]  data_bus_out,
    input  logic        word_read_request,
    input  logic        word_write_request,
    input  logic [15:0] data_bus_in_word,
    output logic [15:0] data_bus_out_word,
    input  logic        memory_read_n,
    input  logic        memory_write_n,
    output logic        memory_access_ready,

    // From mem_map
    input  logic        map_select,
    input  logic [24:0] map_phys,
    input  logic        map_protect,
    input  logic [1:0]  map_vclass,
    input  logic [24:0] map_phys2,
    input  logic        map_phys2_valid,

    // Wait profile and speed (0 4.77, 1 7.16, 2 9.54, 3 Max)
    input  logic        cpu_ce_posedge,
    input  logic        cpu_ce_negedge_next,  // cpu_ce_negedge in the next clock
    input  logic        wait_count_clk_en,    // cpu_ce_negedge
    input  logic [1:0]  ram_read_wait_cycle,
    input  logic [1:0]  ram_write_wait_cycle,
    input  logic [1:0]  clk_select,

    input  logic        flush,
    input  logic        early_read,     // CPU read/fetch address latched (T1)

    // Transaction to sdram_xbridge
    output logic        m_start,
    output logic        m_we,
    output logic [23:0] m_addr,
    output logic [1:0]  m_len,
    output logic [63:0] m_wdata,
    output logic [7:0]  m_wbe,
    input  logic        m_busy,
    input  logic        m_done,
    input  logic [63:0] m_rdata,

    // Committed writes
    output logic        snoop_valid,
    output logic [23:0] snoop_addr,
    output logic [15:0] snoop_data,
    output logic [1:0]  snoop_be
);
    import sdram_pkg::*;

    wire        read_command  = map_select & ~memory_read_n;
    wire        write_command = map_select & ~memory_write_n & ~map_protect;
    wire        cmd_active    = read_command | write_command;

    wire [23:0] w    = map_phys[24:1];
    wire        lane = map_phys[0];

    wire        video = (map_vclass != VC_NONE);
    wire        defer = (map_vclass == VC_CGA);

    // ------------------------------------------------------------------
    // Lookahead lines
    // ------------------------------------------------------------------
    logic        la_valid [2];
    logic [23:0] la_base  [2];
    logic [2:0]  la_cnt   [2];
    logic [63:0] la_data  [2];
    logic        la_victim;

    logic [23:0] la_off  [2];
    logic        la_in   [2];

    always_comb
        for (int e = 0; e < 2; e++) begin
            la_off[e] = w - la_base[e];
            la_in[e]  = la_valid[e] & (la_off[e] < 24'(la_cnt[e]));
        end

    wire        hit      = la_in[0] | la_in[1];
    wire [63:0] hit_line = la_in[0] ? la_data[0] : la_data[1];
    wire [1:0]  hit_off  = la_in[0] ? la_off[0][1:0] : la_off[1][1:0];
    wire [15:0] hit_word = hit_line[16*hit_off +: 16];

    // Burst length of a read miss. Video memory is read a word at a time: it is
    // what the video fetch engines share a bank with.
    logic [1:0] rd_len;
    always_comb begin
        case (video ? 2'b00 : clk_select)
            2'b11:   rd_len = (w[8:0] <= 9'd508) ? LEN_4 : ((w[8:0] <= 9'd510) ? LEN_2 : LEN_1);
            2'b10:   rd_len = (w[8:0] <= 9'd510) ? LEN_2 : LEN_1;
            default: rd_len = LEN_1;
        endcase
    end

    // ------------------------------------------------------------------
    // Accepting a strobe
    // ------------------------------------------------------------------
    logic        owned;         // the active strobe has been accepted
    logic        rd_valid;      // data_reg answers the active read
    logic        rd_owner;      // the transaction in flight answers it
    logic        xfer_read;     // the transaction in flight is a read
    logic [23:0] xfer_w;
    logic [1:0]  xfer_len;
    logic        xfer_lane;
    logic [15:0] data_reg;

    wire bridge_free = ~m_busy & ~m_done;

    // A CGA write waiting for the end of its bus cycle (and then for the bridge)
    logic        dw_pending;
    logic        dw_ended;      // the strobe it was taken in has ended
    logic        dw_stage;      // 0: first target, 1: second target
    logic        dw_two;
    logic [23:0] dw_w, dw_w2;
    logic [15:0] dw_data;
    logic [1:0]  dw_be;

    wire accept_hit   = cmd_active & ~owned & read_command & hit & ~flush & ~dw_pending;
    wire accept_read  = cmd_active & ~owned & read_command & ~accept_hit & bridge_free & ~dw_pending;
    wire accept_write = cmd_active & ~owned & ~read_command & write_command & ~defer & bridge_free & ~dw_pending;
    wire accept_defer = cmd_active & ~owned & ~read_command & write_command &  defer & ~dw_pending;
    wire accept_early = early_read & ~cmd_active & map_select & ~hit & ~flush & bridge_free & ~dw_pending;

    wire post_dw  = dw_pending & (dw_ended | ~write_command) & bridge_free;
    wire post_now = accept_write | post_dw;

    // A read strobe waiting for the line an early read is bringing: answer
    // it from the line on its way into the lookahead.
    wire [23:0] xfer_off   = w - xfer_w;
    wire        xfer_cover = xfer_off < 24'(len_words(xfer_len));

    // Byte or word written.
    wire        wr_word  = word_write_request;
    wire [15:0] wr_data  = wr_word ? data_bus_in_word : {internal_data_bus, internal_data_bus};
    wire [1:0]  wr_be    = wr_word ? 2'b11 : (lane ? 2'b10 : 2'b01);

    wire [23:0] post_w    = accept_write ? w : (dw_stage ? dw_w2 : dw_w);
    wire [15:0] post_data = accept_write ? wr_data : dw_data;
    wire [1:0]  post_be   = accept_write ? wr_be   : dw_be;

    assign m_start = accept_read | post_now | accept_early;
    assign m_we    = post_now;
    assign m_addr  = post_now ? post_w : w;
    assign m_len   = post_now ? LEN_1 : rd_len;
    assign m_wdata = {48'd0, post_data};
    assign m_wbe   = post_now ? {6'd0, post_be} : 8'd0;

    assign snoop_valid = post_now;
    assign snoop_addr  = post_w;
    assign snoop_data  = post_data;
    assign snoop_be    = post_be;

    // Lookahead lines a posted write falls in
    logic [23:0] la_poff [2];
    logic        la_pin  [2];
    always_comb
        for (int e = 0; e < 2; e++) begin
            la_poff[e] = post_w - la_base[e];
            la_pin[e]  = la_valid[e] & (la_poff[e] < 24'(la_cnt[e]));
        end

    function automatic logic [15:0] merge(input logic [15:0] old, input logic [15:0] d,
                                          input logic [1:0] be);
        merge = {be[1] ? d[15:8] : old[15:8], be[0] ? d[7:0] : old[7:0]};
    endfunction

    always_ff @(posedge clock) begin
        if (reset) begin
            owned     <= 1'b0;
            rd_valid  <= 1'b0;
            rd_owner  <= 1'b0;
            xfer_read <= 1'b0;
            xfer_w    <= 24'd0;
            xfer_len  <= LEN_1;
            xfer_lane <= 1'b0;
            data_reg  <= 16'h0000;
            la_victim <= 1'b0;
            dw_pending <= 1'b0;
            dw_ended   <= 1'b0;
            dw_stage   <= 1'b0;
            dw_two     <= 1'b0;
            dw_w       <= 24'd0;
            dw_w2      <= 24'd0;
            dw_data    <= 16'd0;
            dw_be      <= 2'd0;
            for (int e = 0; e < 2; e++) begin
                la_valid[e] <= 1'b0;
                la_base[e]  <= 24'd0;
                la_cnt[e]   <= 3'd0;
                la_data[e]  <= 64'd0;
            end
        end
        else begin
            // The strobe has gone: the next one is a new access.
            if (!cmd_active) begin
                owned    <= 1'b0;
                rd_valid <= 1'b0;
                rd_owner <= 1'b0;
            end

            if (accept_hit) begin
                owned    <= 1'b1;
                rd_valid <= 1'b1;
                data_reg <= (word_read_request || !lane) ? hit_word : {8'h00, hit_word[15:8]};
            end

            if (accept_read) begin
                owned     <= 1'b1;
                rd_owner  <= 1'b1;
                xfer_read <= 1'b1;
                xfer_w    <= w;
                xfer_len  <= rd_len;
                xfer_lane <= lane & ~word_read_request;
            end

            if (accept_early) begin
                xfer_read <= 1'b1;
                xfer_w    <= w;
                xfer_len  <= rd_len;
            end

            if (accept_write)
                owned <= 1'b1;

            if (post_now) begin
                xfer_read <= 1'b0;
                for (int e = 0; e < 2; e++)
                    if (la_pin[e])
                        la_data[e][16*la_poff[e][1:0] +: 16] <=
                            merge(la_data[e][16*la_poff[e][1:0] +: 16], post_data, post_be);
            end

            // CGA: take the write now, send it when MEMW is over
            if (accept_defer) begin
                owned      <= 1'b1;
                dw_pending <= 1'b1;
                dw_ended   <= 1'b0;
                dw_stage   <= 1'b0;
                dw_two     <= map_phys2_valid;
                dw_w       <= w;
                dw_w2      <= map_phys2[24:1];
                dw_data    <= wr_data;
                dw_be      <= wr_be;
            end
            else if (dw_pending) begin
                if (write_command && !dw_ended)
                    dw_data <= wr_data;         // the last value on the bus wins
                if (!write_command)
                    dw_ended <= 1'b1;
                if (post_dw) begin
                    if (dw_two && !dw_stage)
                        dw_stage <= 1'b1;
                    else begin
                        dw_pending <= 1'b0;
                        dw_stage   <= 1'b0;
                    end
                end
            end

            if (m_done && xfer_read) begin
                xfer_read <= 1'b0;
                if (rd_owner && cmd_active) begin
                    rd_owner <= 1'b0;
                    rd_valid <= 1'b1;
                    data_reg <= xfer_lane ? {8'h00, m_rdata[15:8]} : m_rdata[15:0];
                end
                else if (read_command && !owned && xfer_cover && !flush) begin
                    owned    <= 1'b1;
                    rd_valid <= 1'b1;
                    data_reg <= (word_read_request || !lane)
                              ? m_rdata[16*xfer_off[1:0] +: 16]
                              : {8'h00, m_rdata[16*xfer_off[1:0] + 8 +: 8]};
                end
                if (!flush) begin
                    la_valid[la_victim] <= 1'b1;
                    la_base[la_victim]  <= xfer_w;
                    la_cnt[la_victim]   <= len_words(xfer_len);
                    la_data[la_victim]  <= m_rdata;
                    la_victim           <= ~la_victim;
                end
            end

            if (flush) begin
                la_valid[0] <= 1'b0;
                la_valid[1] <= 1'b0;
            end
        end
    end

    assign data_bus_out      = read_command ? data_reg[7:0] : 8'h00;
    assign data_bus_out_word = data_reg;

    // synthesis translate_off
    always_ff @(posedge clock) begin
        if (!reset && (accept_read || accept_hit) && word_read_request && map_phys[0])
            $display("%0t cpu_mem_port: WORD READ AT ODD ADDRESS %07h - contract violated", $time, map_phys);
        if (!reset && accept_write && word_write_request && map_phys[0])
            $display("%0t cpu_mem_port: WORD WRITE AT ODD ADDRESS %07h - contract violated", $time, map_phys);
    end
    // synthesis translate_on

    // ------------------------------------------------------------------
    // Ready / wait (wait counters as in RAM.sv)
    // ------------------------------------------------------------------
    logic [1:0] read_wait_count;
    logic [1:0] write_wait_count;

    always_ff @(posedge clock) begin
        if (reset)
            read_wait_count <= 2'd0;
        else if (~read_command)
            read_wait_count <= ram_read_wait_cycle;
        else if (wait_count_clk_en && (read_wait_count != 2'd0))
            read_wait_count <= read_wait_count - 2'd1;
    end

    always_ff @(posedge clock) begin
        if (reset)
            write_wait_count <= 2'd0;
        else if (~write_command)
            write_wait_count <= ram_write_wait_cycle;
        else if (wait_count_clk_en && (write_wait_count != 2'd0))
            write_wait_count <= write_wait_count - 2'd1;
    end

    // Where a wait state can still be requested. The strobe starts one chipset
    // clock after the CPU clock falling edge in T2. READY decides at the next
    // falling edge (T3), from its ready_n_or_wait register, which takes the
    // readiness one clock earlier: a dip has to be there in the clock before
    // that edge, the one with cpu_ce_negedge_next after the rising edge of T3.
    // A dip any later comes after the decision. There is no wait state then:
    // a read gives the CPU data_reg as it was (the previous answer), a write
    // not yet taken is lost when its strobe ends, and READY puts the wait
    // state into the next bus cycle instead. sys_video_tb at 7.16 and 9.54 MHz
    // had code fetches answered a clock late, behind the two posts of a
    // CGA + HGC page 1 write: the CPU ran the previous byte as an opcode.
    logic pos_seen, dip_ok;
    always_ff @(posedge clock) begin
        if (reset || !cmd_active) begin
            pos_seen <= 1'b0;
            dip_ok   <= 1'b0;
        end
        else begin
            if (cpu_ce_posedge)
                pos_seen <= 1'b1;
            if (cpu_ce_negedge_next && pos_seen)
                dip_ok <= 1'b1;
        end
    end
    wire dip_now = dip_ok | (pos_seen & cpu_ce_negedge_next);

    // The READY logic turns even one clock of "not ready" into a whole wait
    // state, so below Max readiness only dips when the answer is really late
    // (see the header). At Max it dips from the strobe, as RAM.sv did.
    wire strict  = (clk_select == 2'b11);
    wire may_dip = strict | dip_now;
    wire access_ready = read_command  ? ((accept_hit & ~strict) | (owned & rd_valid) | ~may_dip)
                      : write_command ? (owned | accept_write | accept_defer | ~may_dip)
                      :                 1'b1;

    // Video memory has no RAM wait states
    assign memory_access_ready = (map_select & (~memory_read_n | ~memory_write_n))
                               ? (access_ready
                                  & ((read_wait_count == 2'd0) | ~read_command | video)
                                  & ((write_wait_count == 2'd0) | ~write_command | video))
                               : 1'b1;

endmodule
