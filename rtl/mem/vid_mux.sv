//
// Joins the VID ports of several vram_fetch engines into the single VID port of
// the arbiter.
//
//  * Among the engines that are asking, the one with the earliest deadline is
//    chosen (ties: lowest index). The comparison is registered, so it uses the
//    deadlines of the clock before (they all count down together, which does
//    not change the order); if the registered choice is not asking, the first
//    asking engine is chosen.
//  * The chosen request is acknowledged to its engine and parked in a register
//    stage, which is what the arbiter sees. The stage holds the fields stable
//    until the arbiter takes it, and its deadline keeps counting down, so the
//    arbiter reads the value the engine would have shown on that clock. The
//    engines never see the arbiter's answer: the loop engine -> arbiter ->
//    engine that this stage cuts was the longest path of the core with three
//    engines (about 10 logic levels).
//  * The stage takes a new request the clock after it has emptied, so the port
//    carries at most one request every two clocks.
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

    wire use_b = any_q && c_req[best_q];
    wire [SW-1:0] sel = use_b ? best_q : first;

    logic [2:0]    if_cnt;
    wire           room = (if_cnt < 3'(MAX_INFLIGHT));

    // The register stage that the arbiter sees
    logic          stage_v;
    logic [SW-1:0] stage_own;
    logic [23:0]   stage_addr;
    logic [1:0]    stage_len;
    logic [15:0]   stage_dl;

    assign vid_req      = stage_v;
    assign vid_addr     = stage_addr;
    assign vid_len      = stage_len;
    assign vid_deadline = stage_dl;

    wire take = stage_v & vid_ack;
    wire fill = !stage_v & (|c_req) & room;

    always_comb
        for (int i = 0; i < N; i++)
            c_ack[i] = fill && (sel == SW'(i));

    // Who the words belong to
    logic [SW-1:0] own_q [MAX_INFLIGHT];
    logic [1:0]    own_rd, own_wr;

    wire [15:0] fill_dl = c_deadline[16*sel +: 16];

    always_ff @(posedge clk) begin
        if (reset) begin
            stage_v <= 1'b0;
            best_q  <= '0;
            any_q   <= 1'b0;
            own_rd  <= 2'd0;
            own_wr  <= 2'd0;
            if_cnt  <= 3'd0;
        end
        else begin
            best_q <= best;
            any_q  <= any;

            if (fill) begin
                stage_v    <= 1'b1;
                stage_own  <= sel;
                stage_addr <= c_addr[24*sel +: 24];
                stage_len  <= c_len[2*sel +: 2];
                stage_dl   <= (fill_dl != 16'd0) ? fill_dl - 16'd1 : 16'd0;
            end
            else begin
                if (take) stage_v <= 1'b0;
                if (stage_dl != 16'd0) stage_dl <= stage_dl - 16'd1;
            end

            if (take) begin
                own_q[own_wr] <= stage_own;
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
