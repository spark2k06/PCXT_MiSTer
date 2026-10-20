//
// vram_fetch (F2 engine, clk_sdram domain) seen from a video clock.
//
// The engine lives in the arbiter's clock domain; the video adapters of the EGA
// run on the 28.636 MHz clock of the same PLL, an exact quarter of it with
// aligned edges. This shim is the crossing between the two, as the F2 document
// leaves to the adapter:
//
//   request  video side registers the fields and flips a toggle; the sdram side
//            sees the toggle, presents the request to the engine and keeps it
//            up until the engine takes it, so a request is delayed, never lost,
//            when the engine is full
//   pop      a toggle too, one pulse in the sdram domain
//   flush    a toggle too; it also cancels a request of the same video clock
//   head     the engine's head (complete flag and data) is copied into
//            registers every sdram clock and read straight from the video side
//
// Why the head is mirrored instead of taken at the pop: the engine's head is a
// combinational search over its entries, and a path from there into a register
// of the slower clock has one sdram period to settle. As a register of the
// engine's own clock, read by a video register, it is an ordinary short path.
// The cost is that the mirror is one sdram clock behind the engine, and that
// the pop reaches the engine one or two clocks after the video side captured
// the head. Two pops of one engine are many sdram clocks apart (at least one
// character), so the mirror has long caught up with the pop by the next one.
//
// Timing: both crossings are direct register-to-register paths of 8.7 ns
// (SYNC_STAGES = 1 adds a sampling register in the destination); the fields are
// stable for at least four sdram clocks around their toggle.
//
module vram_fetch_x #(
    parameter int DEPTH       = 4,
    parameter int MAX_WORDS   = 1,
    parameter int SYNC_STAGES = 1
) (
    // video domain
    input  logic        clk_v,
    input  logic        reset_v,
    input  logic        rq_valid,          // pulse; at most one per clk_v
    input  logic [23:0] rq_addr,
    input  logic [1:0]  rq_len,
    input  logic [15:0] rq_deadline,       // sdram clocks until the pop
    input  logic        pop,               // pulse
    input  logic        flush,             // pulse
    output logic        hd_valid,
    output logic [63:0] hd_data,

    // sdram domain
    input  logic        clk_s,
    input  logic        reset_s,
    input  logic        snoop_valid,
    input  logic [23:0] snoop_addr,
    input  logic [1:0]  snoop_len,
    input  logic [63:0] snoop_wdata,
    input  logic [7:0]  snoop_wbe,

    output logic        vid_req,
    output logic [23:0] vid_addr,
    output logic [1:0]  vid_len,
    output logic [15:0] vid_deadline,
    input  logic        vid_ack,
    input  logic        vid_rvalid,
    input  logic        vid_rlast,
    input  logic [15:0] vid_rdata,

    output logic [15:0] underrun_count,
    output logic [3:0]  occupancy
);
    // ---------------- video domain
    logic        rq_t, pop_t, fl_t;
    logic [23:0] rq_addr_r;
    logic [1:0]  rq_len_r;
    logic [15:0] rq_dl_r;

    always_ff @(posedge clk_v) begin
        if (reset_v) begin
            rq_t <= 1'b0;
            pop_t <= 1'b0;
            fl_t <= 1'b0;
        end
        else begin
            if (rq_valid & ~flush) begin
                rq_addr_r <= rq_addr;
                rq_len_r  <= rq_len;
                rq_dl_r   <= rq_deadline;
                rq_t      <= ~rq_t;
            end
            if (pop)   pop_t <= ~pop_t;
            if (flush) fl_t  <= ~fl_t;
        end
    end

    // ---------------- sdram domain
    logic rq_t_s, pop_t_s, fl_t_s;
    generate
        if (SYNC_STAGES == 0) begin : g_direct
            assign rq_t_s = rq_t;  assign pop_t_s = pop_t;  assign fl_t_s = fl_t;
        end
        else begin : g_sampled
            logic rq_q, pop_q, fl_q;
            always_ff @(posedge clk_s) begin
                rq_q <= rq_t;  pop_q <= pop_t;  fl_q <= fl_t;
            end
            assign rq_t_s = rq_q;  assign pop_t_s = pop_q;  assign fl_t_s = fl_q;
        end
    endgenerate

    logic rq_seen, pop_seen, fl_seen;
    wire  eng_ready;
    wire  rq_pending = (rq_t_s != rq_seen);
    wire  pop_pulse  = (pop_t_s != pop_seen);
    wire  fl_pulse   = (fl_t_s != fl_seen);

    always_ff @(posedge clk_s) begin
        if (reset_s) begin
            rq_seen  <= rq_t_s;
            pop_seen <= pop_t_s;
            fl_seen  <= fl_t_s;
        end
        else begin
            if (rq_pending & eng_ready & ~fl_pulse) rq_seen <= rq_t_s;
            if (fl_pulse)  begin fl_seen <= fl_t_s; rq_seen <= rq_t_s; end   // a flush drops a pending request
            if (pop_pulse) pop_seen <= pop_t_s;
        end
    end

    wire         eng_valid;
    wire [63:0]  eng_data;
    wire         eng_pending;
    wire [23:0]  eng_raddr;
    wire [1:0]   eng_rlen;

    vram_fetch #(.DEPTH(DEPTH), .MAX_WORDS(MAX_WORDS)) u_engine (
        .clk(clk_s), .reset(reset_s),
        .req_valid(rq_pending & ~fl_pulse), .req_addr(rq_addr_r), .req_len(rq_len_r),
        .req_deadline(rq_dl_r), .req_ready(eng_ready),
        .rsp_pending(eng_pending), .rsp_valid(eng_valid), .rsp_data(eng_data),
        .rsp_addr(eng_raddr), .rsp_len(eng_rlen),
        .rsp_pop(pop_pulse), .flush(fl_pulse),
        .snoop_valid(snoop_valid), .snoop_addr(snoop_addr), .snoop_len(snoop_len),
        .snoop_wdata(snoop_wdata), .snoop_wbe(snoop_wbe),
        .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
        .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast), .vid_rdata(vid_rdata),
        .underrun_count(underrun_count), .occupancy(occupancy)
    );

    // Head mirror: registers of the sdram clock, read from the video side
    always_ff @(posedge clk_s) begin
        hd_valid <= eng_valid;
        hd_data  <= eng_data;
    end
endmodule
