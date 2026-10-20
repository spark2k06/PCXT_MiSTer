//
// Joins the VID ports of several vram_fetch engines into the single VID port of
// the arbiter.
//
//  * Among the engines that are asking, the one with the earliest deadline is
//    presented (ties: lowest index). The comparison is registered, so it uses
//    the deadlines of the clock before (they all count down together, which
//    does not change the order); if the registered choice is not asking, the
//    first asking engine is presented. A request that is being presented keeps
//    its place until the arbiter takes it, so the fields stay stable.
//  * The engine of every accepted request is queued, and the words that come
//    back are handed to the engines in that order.
//  * At most four reads are in flight in total (the arbiter keeps four).
//
module vid_mux #(
    parameter int N = 2             // 2..4 engines
) (
    input  logic            clk,
    input  logic            reset,

    input  logic [N-1:0]    c_req,
    input  logic [24*N-1:0] c_addr,
    input  logic [2*N-1:0]  c_len,
    input  logic [16*N-1:0] c_deadline,
    output logic [N-1:0]    c_ack,
    output logic [N-1:0]    c_rvalid,
    output logic [N-1:0]    c_rlast,

    output logic            vid_req,
    output logic [23:0]     vid_addr,
    output logic [1:0]      vid_len,
    output logic [15:0]     vid_deadline,
    input  logic            vid_ack,
    input  logic            vid_rvalid,
    input  logic            vid_rlast
);
    localparam int MAX_INFLIGHT = 4;
    localparam int SW = (N > 1) ? $clog2(N) : 1;

    // Choice among the asking engines
    logic [SW-1:0] best;
    logic          any;
    always_comb begin
        best = '0;
        any  = 1'b0;
        for (int i = 0; i < N; i++) begin
            if (c_req[i] && (!any || c_deadline[16*i +: 16] < c_deadline[16*best +: 16])) begin
                best = SW'(i);
                any  = 1'b1;
            end
        end
    end

    logic [SW-1:0] best_q;
    logic          any_q;

    // First asking engine, for when the registered choice is not asking
    logic [SW-1:0] first;
    always_comb begin
        first = '0;
        for (int i = N - 1; i >= 0; i--)
            if (c_req[i]) first = SW'(i);
    end

    // The request on show is kept until it is taken (or withdrawn)
    logic          locked;
    logic [SW-1:0] sel_q;
    wire           use_q = locked && c_req[sel_q];
    wire           use_b = any_q && c_req[best_q];
    wire  [SW-1:0] sel   = use_q ? sel_q : (use_b ? best_q : first);

    logic [2:0]    if_cnt;
    wire           room = (if_cnt < 3'(MAX_INFLIGHT));

    assign vid_req      = (use_q | (|c_req)) & room;
    assign vid_addr     = c_addr[24*sel +: 24];
    assign vid_len      = c_len[2*sel +: 2];
    assign vid_deadline = c_deadline[16*sel +: 16];

    wire take = vid_req & vid_ack;

    always_comb
        for (int i = 0; i < N; i++)
            c_ack[i] = take && (sel == SW'(i));

    // Who the words belong to
    logic [SW-1:0] own_q [MAX_INFLIGHT];
    logic [1:0]    own_rd, own_wr;

    always_ff @(posedge clk) begin
        if (reset) begin
            locked <= 1'b0;
            sel_q  <= '0;
            best_q <= '0;
            any_q  <= 1'b0;
            own_rd <= 2'd0;
            own_wr <= 2'd0;
            if_cnt <= 3'd0;
        end
        else begin
            best_q <= best;
            any_q  <= any;

            if (vid_req && !vid_ack) begin
                locked <= 1'b1;
                sel_q  <= sel;
            end
            else
                locked <= 1'b0;

            if (take) begin
                own_q[own_wr] <= sel;
                own_wr        <= own_wr + 2'd1;
            end
            if (vid_rvalid && vid_rlast)
                own_rd <= own_rd + 2'd1;

            if_cnt <= if_cnt + 3'(take) - 3'(vid_rvalid && vid_rlast);
        end
    end

    wire [SW-1:0] owner = own_q[own_rd];
    always_comb
        for (int i = 0; i < N; i++) begin
            c_rvalid[i] = vid_rvalid && (owner == SW'(i));
            c_rlast[i]  = vid_rvalid && vid_rlast && (owner == SW'(i));
        end

endmodule
