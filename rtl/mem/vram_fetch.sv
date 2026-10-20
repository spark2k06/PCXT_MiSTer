//
// Video fetch engine.
//
// One per video adapter. It is an in-order queue of read requests of 1, 2 or 4
// SDRAM words. The adapter asks for the data some time before it needs it, the
// engine gets it through the VID port of the arbiter, and the adapter takes it
// from the head of the queue at the moment it would have read the memory.
//
// Coherence: every write that the arbiter captures from the CPU or
// loader port is seen here (snoop) and applied to the entries that cover its
// words, so an entry always shows the last written value up to the moment it
// is consumed. The snoop takes two clocks: the first finds which words of which
// entries the write covers, the second patches them. A write that arrives before the data of an entry does is kept in
// an overlay (data + byte mask) and merged when the data comes in; the overlay
// wins because it is, by construction, the newest write seen by the engine
// since the request existed. A write that was already in the SDRAM when the
// read was captured shows up again as an identical patch (idempotent).
//
// Bookkeeping, per entry: v (allocated), sent (accepted by the arbiter), done
// (all words in), drop (nobody wants it any more), taken (consumed), skip
// (dropped before being sent: it never goes to the arbiter). An entry is freed
// from the tail when it is taken, or dropped and done.
//
module vram_fetch #(
    parameter int DEPTH     = 4,    // entries, 2..8
    parameter int MAX_WORDS = 1     // 1, 2 or 4 words per entry
) (
    input  logic        clk,
    input  logic        reset,

    // request
    input  logic        req_valid,
    input  logic [23:0] req_addr,
    input  logic [1:0]  req_len,
    input  logic [15:0] req_deadline,
    output logic        req_ready,

    // response, in request order
    output logic        rsp_pending,
    output logic        rsp_valid,
    output logic [63:0] rsp_data,
    output logic [23:0] rsp_addr,
    output logic [1:0]  rsp_len,
    input  logic        rsp_pop,
    input  logic        flush,

    // snoop: writes captured by the arbiter
    input  logic        snoop_valid,
    input  logic [23:0] snoop_addr,
    input  logic [1:0]  snoop_len,
    input  logic [63:0] snoop_wdata,
    input  logic [7:0]  snoop_wbe,

    // VID port of the arbiter
    output logic        vid_req,
    output logic [23:0] vid_addr,
    output logic [1:0]  vid_len,
    output logic [15:0] vid_deadline,
    input  logic        vid_ack,
    input  logic        vid_rvalid,
    input  logic        vid_rlast,
    input  logic [15:0] vid_rdata,

    // debug
    output logic [15:0] underrun_count,
    output logic [3:0]  occupancy
);
    import sdram_pkg::*;

    localparam int IW           = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    localparam int DW           = 16 * MAX_WORDS;
    localparam int MW           = 2 * MAX_WORDS;
    localparam int MAX_INFLIGHT = 4;

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    logic            e_v     [DEPTH];
    logic            e_sent  [DEPTH];
    logic            e_done  [DEPTH];
    logic            e_drop  [DEPTH];
    logic            e_taken [DEPTH];
    logic            e_skip  [DEPTH];
    logic [23:0]     e_addr  [DEPTH];
    logic [1:0]      e_len   [DEPTH];
    logic [15:0]     e_dl    [DEPTH];
    logic [DW-1:0]   e_data  [DEPTH];
    logic [DW-1:0]   e_ov    [DEPTH];
    logic [MW-1:0]   e_ovm   [DEPTH];

    logic            n_v     [DEPTH];
    logic            n_sent  [DEPTH];
    logic            n_done  [DEPTH];
    logic            n_drop  [DEPTH];
    logic            n_taken [DEPTH];
    logic            n_skip  [DEPTH];
    logic [23:0]     n_addr  [DEPTH];
    logic [1:0]      n_len   [DEPTH];
    logic [15:0]     n_dl    [DEPTH];
    logic [DW-1:0]   n_data  [DEPTH];
    logic [DW-1:0]   n_ov    [DEPTH];
    logic [MW-1:0]   n_ovm   [DEPTH];

    logic [IW-1:0]   wr_ptr, tail_ptr, snd_ptr, cons_ptr;
    logic [IW-1:0]   n_wr_ptr, n_tail_ptr, n_snd_ptr, n_cons_ptr;
    logic [3:0]      occ, snd_cnt, cons_cnt;
    logic [3:0]      n_occ, n_snd_cnt, n_cons_cnt;

    // Accepted reads whose words are still to come, in order.
    logic [IW-1:0]   if_q [MAX_INFLIGHT];
    logic [1:0]      if_rd, if_wr;
    logic [2:0]      if_cnt;
    logic [1:0]      n_if_rd, n_if_wr;
    logic [2:0]      n_if_cnt;
    logic [1:0]      beat, n_beat;

    logic [15:0]     n_underrun;

    // Snoop pipeline: stage 1 (registered) holds the write and, for every entry
    // and write word, whether it hits and which word of the entry it is.
    logic            h_valid;
    logic [63:0]     h_wdata;
    logic [7:0]      h_wbe;
    logic            h_hit  [DEPTH][4];
    logic [1:0]      h_wsel [DEPTH][4];
    logic            s1_hit  [DEPTH][4];
    logic [1:0]      s1_wsel [DEPTH][4];
    logic [2:0]      s1_nw;
    logic [23:0]     s1_off;

    function automatic logic [IW-1:0] inc(input logic [IW-1:0] p);
        inc = (p == IW'(DEPTH - 1)) ? '0 : p + 1'b1;
    endfunction

    function automatic logic [IW-1:0] addp(input logic [IW-1:0] p, input int k);
        int t;
        t = int'(p) + k;
        addp = IW'((t >= DEPTH) ? t - DEPTH : t);
    endfunction

    function automatic logic [15:0] byte_merge(input logic [15:0] old, input logic [15:0] d,
                                               input logic [1:0] be);
        byte_merge = {be[1] ? d[15:8] : old[15:8], be[0] ? d[7:0] : old[7:0]};
    endfunction

    // ------------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------------
    // The head is the oldest entry that is still wanted. It is found by looking
    // for the first live entry from the consumer pointer on, so a run of dropped
    // entries (after a flush or a late pop) never delays it. Every live entry is
    // inside the consumer window (an entry is allocated into it and only leaves
    // it by being taken or dropped), so the window length is not looked at.
    logic          head_found;
    logic [IW-1:0] head_idx;
    logic [3:0]    head_k;
    always_comb begin
        head_found = 1'b0;
        head_idx   = cons_ptr;
        head_k     = 4'd0;
        for (int k = 0; k < DEPTH; k++) begin
            if (!head_found
                && e_v[addp(cons_ptr, k)] && !e_taken[addp(cons_ptr, k)] && !e_drop[addp(cons_ptr, k)]) begin
                head_found = 1'b1;
                head_idx   = addp(cons_ptr, k);
                head_k     = 4'(k);
            end
        end
    end

    wire head_live = head_found;
    wire head_done = head_found && e_done[head_idx];

    assign rsp_pending = head_live;
    assign rsp_valid   = head_done;
    // e_data keeps what the SDRAM returned; the bytes a snooped CPU write has
    // overwritten since are taken from the overlay here, so a returning word never
    // has to wait for the snoop patch of the same clock.
    logic [DW-1:0] rsp_merged;
    always_comb begin
        for (int w = 0; w < MAX_WORDS; w++)
            for (int k = 0; k < 2; k++)
                rsp_merged[16*w + 8*k +: 8] = e_ovm[head_idx][2*w + k]
                                            ? e_ov[head_idx][16*w + 8*k +: 8]
                                            : e_data[head_idx][16*w + 8*k +: 8];
    end
    assign rsp_data    = 64'(rsp_merged);
    assign rsp_addr    = e_addr[head_idx];
    assign rsp_len     = e_len[head_idx];
    assign occupancy   = occ;

    assign req_ready = !e_v[wr_ptr] && !flush;

    wire snd_here = (snd_cnt != 4'd0) && e_v[snd_ptr] && !e_sent[snd_ptr] && !e_skip[snd_ptr];
    assign vid_req      = snd_here && (if_cnt < 3'(MAX_INFLIGHT));
    assign vid_addr     = e_addr[snd_ptr];
    assign vid_len      = e_len[snd_ptr];
    assign vid_deadline = e_dl[snd_ptr];

    // ------------------------------------------------------------------
    // Snoop, stage 1: which entries does the write cover, and where
    // ------------------------------------------------------------------
    always_comb begin
        s1_nw  = len_words(snoop_len);
        s1_off = 24'd0;
        for (int i = 0; i < DEPTH; i++) begin
            for (int j = 0; j < 4; j++) begin
                s1_off = snoop_addr + 24'(j) - e_addr[i];
                s1_wsel[i][j] = s1_off[1:0];
                s1_hit[i][j]  = snoop_valid && e_v[i] && !e_skip[i] && (3'(j) < s1_nw)
                              && (s1_off < 24'(len_words(e_len[i]))) && ({1'b0, s1_off[1:0]} < 3'(MAX_WORDS));
            end
        end
    end

    // ------------------------------------------------------------------
    // Next state
    // ------------------------------------------------------------------
    logic            tail_free;
    logic            do_alloc;
    logic            do_ack;
    logic [IW-1:0]   bi;
    logic [1:0]      wsel;
    logic [1:0]      sbe;
    logic [15:0]     sd;

    always_comb begin
        for (int i = 0; i < DEPTH; i++) begin
            n_v[i]     = e_v[i];
            n_sent[i]  = e_sent[i];
            n_done[i]  = e_done[i];
            n_drop[i]  = e_drop[i];
            n_taken[i] = e_taken[i];
            n_skip[i]  = e_skip[i];
            n_addr[i]  = e_addr[i];
            n_len[i]   = e_len[i];
            n_dl[i]    = (e_dl[i] != 16'd0) ? e_dl[i] - 16'd1 : 16'd0;
            n_data[i]  = e_data[i];
            n_ov[i]    = e_ov[i];
            n_ovm[i]   = e_ovm[i];
        end
        n_wr_ptr   = wr_ptr;
        n_tail_ptr = tail_ptr;
        n_snd_ptr  = snd_ptr;
        n_cons_ptr = cons_ptr;
        n_occ      = occ;
        n_snd_cnt  = snd_cnt;
        n_cons_cnt = cons_cnt;
        n_if_rd    = if_rd;
        n_if_wr    = if_wr;
        n_if_cnt   = if_cnt;
        n_beat     = beat;
        n_underrun = underrun_count;
        bi         = '0;
        wsel       = 2'd0;
        sbe        = 2'd0;
        sd         = 16'd0;

        // --- free from the tail ---
        tail_free = (occ != 4'd0) && e_v[tail_ptr]
                  && (e_taken[tail_ptr] || (e_drop[tail_ptr] && e_done[tail_ptr]));
        if (tail_free) begin
            n_v[tail_ptr] = 1'b0;
            n_tail_ptr    = inc(tail_ptr);
            n_occ         = n_occ - 4'd1;
        end

        // --- allocate ---
        do_alloc = req_valid && req_ready;
        if (do_alloc) begin
            n_v[wr_ptr]     = 1'b1;
            n_sent[wr_ptr]  = 1'b0;
            n_done[wr_ptr]  = 1'b0;
            n_drop[wr_ptr]  = 1'b0;
            n_taken[wr_ptr] = 1'b0;
            n_skip[wr_ptr]  = 1'b0;
            n_addr[wr_ptr]  = req_addr;
            n_len[wr_ptr]   = req_len;
            n_dl[wr_ptr]    = req_deadline;
            n_data[wr_ptr]  = '0;
            n_ov[wr_ptr]    = '0;
            n_ovm[wr_ptr]   = '0;
            n_wr_ptr        = inc(wr_ptr);
            n_occ           = n_occ + 4'd1;
            n_snd_cnt       = n_snd_cnt + 4'd1;
            n_cons_cnt      = n_cons_cnt + 4'd1;
        end

        // --- snoop, stage 2: patch the overlay of every word found one clock ago ---
        if (h_valid) begin
            for (int i = 0; i < DEPTH; i++) begin
                if (e_v[i] && !e_skip[i]) begin
                    for (int j = 0; j < 4; j++) begin
                        if (h_hit[i][j]) begin
                            wsel = h_wsel[i][j];
                            sbe  = h_wbe[2*j +: 2];
                            sd   = h_wdata[16*j +: 16];
                            n_ov[i][16*wsel +: 16]   = byte_merge(n_ov[i][16*wsel +: 16], sd, sbe);
                            n_ovm[i][2*wsel +: 2]    = n_ovm[i][2*wsel +: 2] | sbe;
                        end
                    end
                end
            end
        end

        // --- request accepted by the arbiter ---
        do_ack = vid_req && vid_ack;
        if (do_ack) begin
            n_sent[snd_ptr] = 1'b1;
            n_snd_ptr       = inc(snd_ptr);
            n_snd_cnt       = n_snd_cnt - 4'd1;
            n_if_wr         = if_wr + 2'd1;
            n_if_cnt        = n_if_cnt + 3'd1;
        end
        else if ((snd_cnt != 4'd0) && (!e_v[snd_ptr] || e_skip[snd_ptr])) begin
            n_snd_ptr = inc(snd_ptr);
            n_snd_cnt = n_snd_cnt - 4'd1;
        end

        // --- words coming back ---
        if (vid_rvalid && (if_cnt != 3'd0)) begin
            bi = if_q[if_rd];
            if ({1'b0, beat} < 3'(MAX_WORDS)) begin
                n_data[bi][16*beat +: 16] = vid_rdata;
            end
            if (vid_rlast) begin
                n_done[bi] = 1'b1;
                n_if_rd    = if_rd + 2'd1;
                n_if_cnt   = n_if_cnt - 3'd1;
                n_beat     = 2'd0;
            end
            else
                n_beat = beat + 2'd1;
        end

        // --- the adapter consumes the head ---
        if (head_found) begin
            // entries in front of the head are not wanted: pass them
            n_cons_ptr = addp(cons_ptr, int'(head_k));
            n_cons_cnt = n_cons_cnt - head_k;
            if (rsp_pop) begin
                if (e_done[head_idx]) n_taken[head_idx] = 1'b1;
                else begin
                    n_drop[head_idx] = 1'b1;
                    if (underrun_count != 16'hFFFF) n_underrun = underrun_count + 16'd1;
                end
                n_cons_ptr = addp(cons_ptr, int'(head_k) + 1);
                n_cons_cnt = n_cons_cnt - head_k - 4'd1;
            end
        end
        else begin
            // nothing wanted in the queue: pass everything
            n_cons_ptr = addp(cons_ptr, int'(cons_cnt));
            n_cons_cnt = n_cons_cnt - cons_cnt;
            if (rsp_pop && underrun_count != 16'hFFFF) n_underrun = underrun_count + 16'd1;
        end

        // --- flush: nothing in the queue is wanted any more ---
        if (flush) begin
            for (int i = 0; i < DEPTH; i++) begin
                if (e_v[i]) begin
                    n_drop[i] = 1'b1;
                    if (!e_sent[i] && !(do_ack && (snd_ptr == IW'(i)))) begin
                        n_skip[i] = 1'b1;
                        n_done[i] = 1'b1;
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < DEPTH; i++) begin
                e_v[i]     <= 1'b0;
                e_sent[i]  <= 1'b0;
                e_done[i]  <= 1'b0;
                e_drop[i]  <= 1'b0;
                e_taken[i] <= 1'b0;
                e_skip[i]  <= 1'b0;
                e_addr[i]  <= 24'd0;
                e_len[i]   <= LEN_1;
                e_dl[i]    <= 16'd0;
                e_data[i]  <= '0;
                e_ov[i]    <= '0;
                e_ovm[i]   <= '0;
            end
            wr_ptr   <= '0;
            tail_ptr <= '0;
            snd_ptr  <= '0;
            cons_ptr <= '0;
            occ      <= 4'd0;
            snd_cnt  <= 4'd0;
            cons_cnt <= 4'd0;
            if_rd    <= 2'd0;
            if_wr    <= 2'd0;
            if_cnt   <= 3'd0;
            beat     <= 2'd0;
            underrun_count <= 16'd0;
            h_valid  <= 1'b0;
            h_wdata  <= '0;
            h_wbe    <= '0;
            for (int i = 0; i < DEPTH; i++)
                for (int j = 0; j < 4; j++) begin
                    h_hit[i][j]  <= 1'b0;
                    h_wsel[i][j] <= 2'd0;
                end
        end
        else begin
            for (int i = 0; i < DEPTH; i++) begin
                e_v[i]     <= n_v[i];
                e_sent[i]  <= n_sent[i];
                e_done[i]  <= n_done[i];
                e_drop[i]  <= n_drop[i];
                e_taken[i] <= n_taken[i];
                e_skip[i]  <= n_skip[i];
                e_addr[i]  <= n_addr[i];
                e_len[i]   <= n_len[i];
                e_dl[i]    <= n_dl[i];
                e_data[i]  <= n_data[i];
                e_ov[i]    <= n_ov[i];
                e_ovm[i]   <= n_ovm[i];
            end
            wr_ptr   <= n_wr_ptr;
            tail_ptr <= n_tail_ptr;
            snd_ptr  <= n_snd_ptr;
            cons_ptr <= n_cons_ptr;
            occ      <= n_occ;
            snd_cnt  <= n_snd_cnt;
            cons_cnt <= n_cons_cnt;
            if_rd    <= n_if_rd;
            if_wr    <= n_if_wr;
            if_cnt   <= n_if_cnt;
            beat     <= n_beat;
            underrun_count <= n_underrun;
            h_valid  <= snoop_valid;
            h_wdata  <= snoop_wdata;
            h_wbe    <= snoop_wbe;
            for (int i = 0; i < DEPTH; i++)
                for (int j = 0; j < 4; j++) begin
                    h_hit[i][j]  <= s1_hit[i][j];
                    h_wsel[i][j] <= s1_wsel[i][j];
                end
            if (do_ack) if_q[if_wr] <= snd_ptr;
        end
    end

endmodule
