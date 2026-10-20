//
// Behavioural stand-in for the SDRAM arbiter and chip, for the benches of the
// video frontends: it speaks the two ports the frontend uses and nothing else.
//
//   CPU port   the transaction interface of sdram_xbridge, in the chipset clock
//              domain (m_start / m_busy / m_done), one transaction at a time
//   VID port   the client end of the arbiter's video port, in the sdram clock
//              domain (vid_req held until vid_ack; words back in order)
//
// One memory of 16-bit words serves both. Latencies are random within the given
// limits, drawn per transaction. A write is applied to the memory at the moment
// the model "captures" it and is announced on the snoop port one sdram clock
// later, as the arbiter does at its capture. Reads read the memory when their
// first word goes out.
//
// Word addresses are relative to MEM_BASE (the first word of the array).
//
`timescale 1ns / 1ps

module pc_port_model #(
    parameter [23:0] MEM_BASE   = 24'h400000,
    parameter int    MEM_WORDS  = 262144,
    parameter int    CPU_LAT_MIN = 6,      // chipset clocks, capture of a CPU transaction
    parameter int    CPU_LAT_MAX = 22,
    parameter int    VID_ACK_MAX = 6,      // sdram clocks before the ack
    parameter int    VID_LAT_MIN = 4,      // sdram clocks from ack to the first word
    parameter int    VID_LAT_MAX = 22,
    parameter int    VID_QUEUE   = 3       // reads accepted and not finished
) (
    input  logic         reset,         // unused here, present for ega_real_stack's port list

    // CPU port
    input  logic         clock,
    input  logic         m_start,
    input  logic         m_we,
    input  logic [23:0]  m_addr,
    input  logic [1:0]   m_len,
    input  logic [63:0]  m_wdata,
    input  logic [7:0]   m_wbe,
    output logic         m_busy,
    output logic         m_done,
    output logic [63:0]  m_rdata,

    // VID port
    input  logic         sclk,
    input  logic         vid_req,
    input  logic [23:0]  vid_addr,
    input  logic [1:0]   vid_len,
    input  logic [15:0]  vid_deadline,
    output logic         vid_ack,
    output logic         vid_rvalid,
    output logic         vid_rlast,
    output logic [15:0]  vid_rdata,

    // Snoop of the captured writes (sclk domain)
    output logic         snoop_valid,
    output logic [23:0]  snoop_addr,
    output logic [1:0]   snoop_len,
    output logic [63:0]  snoop_wdata,
    output logic [7:0]   snoop_wbe,

    output int           vid_max_lat,    // longest request-to-last-word seen, sclk cycles
    output int           chip_errors,    // 0: no chip here
    output int           vid_underruns_out
);
    assign chip_errors       = 0;
    assign vid_underruns_out = 0;

    logic [15:0] mem [0:MEM_WORDS-1];

    // Backdoor into the memory: word addresses relative to MEM_BASE
    task automatic poke(input int rel, input logic [15:0] v);
        mem[rel] = v;
    endtask

    function automatic int words_of(input logic [1:0] l);
        words_of = (l == 2'd0) ? 1 : ((l == 2'd1) ? 2 : 4);
    endfunction

    // ------------------------------------------------------------------
    // CPU port
    // ------------------------------------------------------------------
    int          c_wait;
    logic        c_active;
    logic        c_we_q;
    logic [23:0] c_addr_q;
    logic [1:0]  c_len_q;
    logic [63:0] c_wdata_q;
    logic [7:0]  c_wbe_q;

    // write announcement towards sclk
    logic        sn_req_t;               // toggles in `clock`
    logic        sn_seen_t;
    logic [23:0] sn_a;  logic [1:0] sn_l;  logic [63:0] sn_d;  logic [7:0] sn_b;

    initial begin
        m_busy = 1'b0; m_done = 1'b0; m_rdata = 64'd0; c_active = 1'b0; c_wait = 0;
        sn_req_t = 1'b0; sn_seen_t = 1'b0; snoop_valid = 1'b0;
        vid_max_lat = 0;
    end

    always @(posedge clock) begin
        m_done <= 1'b0;
        if (m_start && !m_busy) begin
            c_we_q <= m_we;  c_addr_q <= m_addr;  c_len_q <= m_len;
            c_wdata_q <= m_wdata;  c_wbe_q <= m_wbe;
            c_active <= 1'b1;
            m_busy   <= 1'b1;
            c_wait   <= $urandom_range(CPU_LAT_MAX, CPU_LAT_MIN);
        end
        else if (c_active) begin
            if (c_wait > 0) c_wait <= c_wait - 1;
            else begin
                logic [23:0] a;
                a = c_addr_q - MEM_BASE;
                if (c_we_q) begin
                    for (int w = 0; w < words_of(c_len_q); w++)
                        for (int l = 0; l < 2; l++)
                            if (c_wbe_q[2*w + l])
                                mem[a + w][8*l +: 8] = c_wdata_q[16*w + 8*l +: 8];
                    sn_a <= c_addr_q;  sn_l <= c_len_q;  sn_d <= c_wdata_q;  sn_b <= c_wbe_q;
                    sn_req_t <= ~sn_req_t;
                end
                else begin
                    logic [63:0] d;
                    d = 64'd0;
                    for (int w = 0; w < words_of(c_len_q); w++) d[16*w +: 16] = mem[a + w];
                    m_rdata <= d;
                end
                c_active <= 1'b0;
                m_busy   <= 1'b0;
                m_done   <= 1'b1;
            end
        end
    end

    always @(posedge sclk) begin
        snoop_valid <= 1'b0;
        if (sn_req_t != sn_seen_t) begin
            sn_seen_t   <= sn_req_t;
            snoop_valid <= 1'b1;
            snoop_addr  <= sn_a;  snoop_len <= sn_l;  snoop_wdata <= sn_d;  snoop_wbe <= sn_b;
        end
    end

    // ------------------------------------------------------------------
    // VID port
    // ------------------------------------------------------------------
    logic [23:0] rq_addr  [4];
    logic [1:0]  rq_len   [4];
    int          rq_start [4];
    int          rq_t0    [4];
    int          rq_wr, rq_rd, scyc, ack_wait, beat, prev_end;

    initial begin rq_wr = 0; rq_rd = 0; scyc = 0; ack_wait = -1; beat = 0; prev_end = 0; end

    always @(posedge sclk) begin
        scyc <= scyc + 1;
        vid_ack    <= 1'b0;
        vid_rvalid <= 1'b0;
        vid_rlast  <= 1'b0;

        if (vid_req && !vid_ack && (rq_wr - rq_rd) < VID_QUEUE) begin
            if (ack_wait < 0) ack_wait = $urandom_range(VID_ACK_MAX, 0);
            if (ack_wait == 0) begin
                int lat;
                lat = $urandom_range(VID_LAT_MAX, VID_LAT_MIN);
                vid_ack <= 1'b1;
                rq_addr[rq_wr % 4]  = vid_addr;
                rq_len[rq_wr % 4]   = vid_len;
                rq_t0[rq_wr % 4]    = scyc;
                rq_start[rq_wr % 4] = (scyc + lat > prev_end) ? scyc + lat : prev_end;
                prev_end = rq_start[rq_wr % 4] + words_of(vid_len);
                rq_wr = rq_wr + 1;
                ack_wait = -1;
            end
            else ack_wait = ack_wait - 1;
        end

        if (rq_rd < rq_wr && scyc >= rq_start[rq_rd % 4]) begin
            int q;  logic [23:0] a;
            q = rq_rd % 4;
            a = rq_addr[q] - MEM_BASE;
            vid_rvalid <= 1'b1;
            vid_rdata  <= mem[a + beat];
            vid_rlast  <= (beat == words_of(rq_len[q]) - 1);
            if (beat == words_of(rq_len[q]) - 1) begin
                if (scyc - rq_t0[q] > vid_max_lat) vid_max_lat = scyc - rq_t0[q];
                beat = 0;
                rq_rd = rq_rd + 1;
            end
            else beat = beat + 1;
        end
    end
endmodule
