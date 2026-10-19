//
// One-transaction bridge from a client clock domain to an sdram_port of the
// arbiter ("request/ack handshake with double flip-flop").
//
// Client side (clk_a): a_start for one clock with the fields, when a_busy is
// low; a_done for one clock when the transaction is over, with a_rdata for a
// read (word i in bits [16*i +: 16]). A write is over when the arbiter has
// captured it; nothing issued later can overtake it.
//
// SDRAM side (clk_s): the client end of an arbiter port.
//
// The request and the answer each cross as a toggle through SYNC_STAGES
// flip-flops. The fields and the read buffer are not synchronised: they are
// written before their toggle and held until the other side has seen it, so
// they are stable for at least one destination clock when they are used.
//
// SYNC_STAGES = 0 is for option A, where clk_s is 2 x clk_a from the same PLL
// and both edges line up: the toggles are then compared directly and every
// path is an ordinary timed one.
//
module sdram_xbridge #(
    parameter int SYNC_STAGES = 2
) (
    // Client domain
    input  logic        clk_a,
    input  logic        reset_a,
    input  logic        a_start,
    input  logic        a_we,
    input  logic [23:0] a_addr,
    input  logic [1:0]  a_len,
    input  logic [63:0] a_wdata,
    input  logic [7:0]  a_wbe,
    output logic        a_busy,
    output logic        a_done,
    output logic [63:0] a_rdata,

    // Arbiter domain
    input  logic        clk_s,
    input  logic        reset_s,
    output logic        s_req,
    output logic        s_we,
    output logic [23:0] s_addr,
    output logic [1:0]  s_len,
    output logic [63:0] s_wdata,
    output logic [7:0]  s_wbe,
    input  logic        s_ack,
    input  logic        s_rvalid,
    input  logic [15:0] s_rdata,
    input  logic        s_rlast
);

    // ------------------------------------------------------------------
    // Client domain
    // ------------------------------------------------------------------
    logic req_t;        // toggles once per transaction
    logic rsp_seen;     // last answer toggle consumed
    logic rsp_a;        // answer toggle, synchronised

    always_ff @(posedge clk_a) begin
        if (reset_a) begin
            req_t    <= 1'b0;
            rsp_seen <= 1'b0;
            a_busy   <= 1'b0;
            a_done   <= 1'b0;
            s_we     <= 1'b0;
            s_addr   <= 24'd0;
            s_len    <= 2'd0;
            s_wdata  <= 64'd0;
            s_wbe    <= 8'd0;
        end
        else begin
            a_done <= 1'b0;
            if (a_start && !a_busy) begin
                s_we    <= a_we;
                s_addr  <= a_addr;
                s_len   <= a_len;
                s_wdata <= a_wdata;
                s_wbe   <= a_wbe;
                req_t   <= ~req_t;
                a_busy  <= 1'b1;
            end
            else if (a_busy && (rsp_a != rsp_seen)) begin
                rsp_seen <= rsp_a;
                a_busy   <= 1'b0;
                a_done   <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Arbiter domain
    // ------------------------------------------------------------------
    logic req_s;        // request toggle, synchronised
    logic req_seen;
    logic rsp_t;
    logic rd_wait;
    logic [1:0]  beat;
    logic [63:0] rbuf;

    assign s_req   = (req_s != req_seen) & ~rd_wait;
    assign a_rdata = rbuf;

    always_ff @(posedge clk_s) begin
        if (reset_s) begin
            req_seen <= 1'b0;
            rsp_t    <= 1'b0;
            rd_wait  <= 1'b0;
            beat     <= 2'd0;
            rbuf     <= 64'd0;
        end
        else begin
            if (s_req && s_ack) begin
                req_seen <= req_s;
                if (s_we)
                    rsp_t <= ~rsp_t;
                else begin
                    rd_wait <= 1'b1;
                    beat    <= 2'd0;
                end
            end
            if (rd_wait && s_rvalid) begin
                rbuf[16*beat +: 16] <= s_rdata;
                beat <= beat + 2'd1;
                if (s_rlast) begin
                    rd_wait <= 1'b0;
                    rsp_t   <= ~rsp_t;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Toggle crossings
    // ------------------------------------------------------------------
    generate
        if (SYNC_STAGES == 0) begin : g_sync
            assign req_s = req_t;
            assign rsp_a = rsp_t;
        end
        else begin : g_async
            (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
            logic [SYNC_STAGES-1:0] req_sync;
            (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
            logic [SYNC_STAGES-1:0] rsp_sync;

            always_ff @(posedge clk_s)
                if (reset_s) req_sync <= '0;
                else         req_sync <= {req_sync[SYNC_STAGES-2:0], req_t};

            always_ff @(posedge clk_a)
                if (reset_a) rsp_sync <= '0;
                else         rsp_sync <= {rsp_sync[SYNC_STAGES-2:0], rsp_t};

            assign req_s = req_sync[SYNC_STAGES-1];
            assign rsp_a = rsp_sync[SYNC_STAGES-1];
        end
    endgenerate

endmodule
