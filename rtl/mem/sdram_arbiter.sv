//
// SDRAM arbiter.
//
// Four clients speak the sdram_port protocol (see sdram_pkg.sv): VID (video
// fetch, reads with a deadline), CPU (chipset bus: CPU, DMA), LDR (ROM loader)
// and AUX (reserved). One of them, or a refresh, is captured into the holding
// register that sdram_ctrl executes from. Capturing is the client's ack, so a
// request is never taken back and nothing captured later can overtake it.
//
// Order of preference when the holding register is free:
//
//   1. refresh, when the debt has reached 8
//   2. VID, when its deadline is within T_URGENT clocks
//   2b. LDR or AUX, once they have waited T_STARVE clocks (no starvation
//       even under a CPU that never lets go; the real CPU port always does)
//   3. CPU
//   4. LDR, while the machine is held for a ROM download (ldr_high)
//   5. VID
//   6. LDR
//   7. AUX
//   8. refresh, when there is any debt and nothing else to do
//
// Refresh debt: one AUTO REFRESH is owed every tREFI (7.8 us); up to eight
// are postponed while the memory is busy. The CPU can therefore only ever
// find one refresh in front of it, never a burst of them.
//
// The low-priority choices (5. to 7.) are only taken when their bank is
// idle, so they go out at once and never sit in the holding register in
// front of a CPU request that arrives a clock later. The CPU then finds, at
// worst, one operation that has already started, never one that is still
// waiting for its bank.
//
// An optional refresh (8.) may still be waiting in the holding register for
// the banks to close when the CPU or an urgent VID read turns up. It has not
// started, so it gives its place up and goes back to the debt; otherwise the
// CPU would wait for the bank of the previous operation AND for tRFC. A
// forced refresh (1.) never gives way.
//
// Statistics: worst CPU latency in clocks, from the
// request to the first read word (or to the ack, for a write); worst VID
// latency from the moment a request became urgent to its first word (a VID
// request that is not urgent waits behind the CPU by design, so its latency
// from the request says nothing about the display); and the number of VID
// reads whose last word came after their deadline.
//
module sdram_arbiter #(
    parameter int T_URGENT = 56,       // one EGA character at 16.257 MHz
    parameter int T_STARVE = 255
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        init_done,

    // VID
    input  logic        vid_req,
    input  logic [23:0] vid_addr,
    input  logic [1:0]  vid_len,
    input  logic [15:0] vid_deadline,     // clocks until the data is needed
    output logic        vid_ack,
    output logic        vid_rvalid,
    output logic        vid_rlast,

    // CPU
    input  logic        cpu_req,
    input  logic        cpu_we,
    input  logic [23:0] cpu_addr,
    input  logic [1:0]  cpu_len,
    input  logic [63:0] cpu_wdata,
    input  logic [7:0]  cpu_wbe,
    output logic        cpu_ack,
    output logic        cpu_rvalid,
    output logic        cpu_rlast,

    // LDR
    input  logic        ldr_req,
    input  logic        ldr_we,
    input  logic [23:0] ldr_addr,
    input  logic [1:0]  ldr_len,
    input  logic [63:0] ldr_wdata,
    input  logic [7:0]  ldr_wbe,
    input  logic        ldr_high,
    output logic        ldr_ack,
    output logic        ldr_rvalid,
    output logic        ldr_rlast,

    // AUX
    input  logic        aux_req,
    input  logic [23:0] aux_addr,
    input  logic [1:0]  aux_len,
    output logic        aux_ack,
    output logic        aux_rvalid,
    output logic        aux_rlast,

    // Read data, shared by all clients (qualified by their rvalid)
    output logic [15:0] rdata,

    // sdram_ctrl
    output logic        op_valid,
    output logic        op_ref,
    output logic        op_we,
    output logic [23:0] op_addr,
    output logic [1:0]  op_len,
    output logic [63:0] op_wdata,
    output logic [7:0]  op_wbe,
    output logic [1:0]  op_tag,
    input  logic        op_issue,
    input  logic [3:0]  bank_idle,
    input  logic        rd_valid,
    input  logic [15:0] rd_data,
    input  logic [1:0]  rd_tag,
    input  logic        rd_last,

    // Statistics
    output logic [15:0] cpu_lat_max,
    output logic [15:0] vid_lat_max,
    output logic [15:0] vid_underruns,
    output logic [3:0]  ref_debt
);
    import sdram_pkg::*;

    localparam int T_REFI = 894;   // 7.8 us

    // ------------------------------------------------------------------
    // Refresh debt
    // ------------------------------------------------------------------
    // The debt counts refreshes owed and not yet captured, so a refresh
    // waiting in the holding register is not chosen a second time.
    logic [9:0] refi_cnt;
    wire        refi_tick = (refi_cnt == 10'(T_REFI - 1));
    logic       ref_taken;
    logic       ref_refund;
    wire        ref_forced = (ref_debt >= 4'd8);

    always_ff @(posedge clk) begin
        if (reset || !init_done) begin
            refi_cnt <= 10'd0;
            ref_debt <= 4'd0;
        end
        else begin
            refi_cnt <= refi_tick ? 10'd0 : refi_cnt + 10'd1;
            // Ticks are never dropped: at 8 the refresh is forced and goes out
            // within a few clocks, long before the next tick.
            ref_debt <= ref_debt + 4'(refi_tick) + 4'(ref_refund) - 4'(ref_taken);
        end
    end

    // ------------------------------------------------------------------
    // Choice
    // ------------------------------------------------------------------
    typedef enum logic [2:0] {S_NONE, S_REF, S_VID, S_CPU, S_LDR, S_AUX} sel_t;
    sel_t sel;

    wire vid_urgent = vid_req & (vid_deadline <= 16'(T_URGENT));
    // A bank is free for a low-priority operation if it is idle now and the
    // holding register is not about to take it: no refresh there (it closes
    // every bank) and no access to that same bank.
    function automatic logic bank_free(input logic [1:0] b);
        bank_free = bank_idle[b] & ~(op_valid & (op_ref | (op_addr[23:22] == b)));
    endfunction

    wire vid_ready  = vid_req & bank_free(vid_addr[23:22]);
    wire ldr_ready  = ldr_req & bank_free(ldr_addr[23:22]);
    wire aux_ready  = aux_req & bank_free(aux_addr[23:22]);

    // Waiting time of the two low-priority clients.
    logic [7:0] ldr_age, aux_age;
    wire        ldr_old = ldr_req & (ldr_age == 8'(T_STARVE));
    wire        aux_old = aux_req & (aux_age == 8'(T_STARVE));

    always_ff @(posedge clk) begin
        if (reset || !ldr_req || ldr_ack) ldr_age <= 8'd0;
        else if (!ldr_old)                ldr_age <= ldr_age + 8'd1;
        if (reset || !aux_req || aux_ack) aux_age <= 8'd0;
        else if (!aux_old)                aux_age <= aux_age + 8'd1;
    end

    always_comb begin
        if (ref_forced)              sel = S_REF;
        else if (vid_urgent)         sel = S_VID;
        else if (ldr_old)            sel = S_LDR;
        else if (aux_old)            sel = S_AUX;
        else if (cpu_req)            sel = S_CPU;
        else if (ldr_req & ldr_high) sel = S_LDR;
        else if (vid_ready)          sel = S_VID;
        else if (ldr_ready)          sel = S_LDR;
        else if (aux_ready)          sel = S_AUX;
        else if (ref_debt != 4'd0 && !vid_req && !ldr_req && !aux_req)
                                     sel = S_REF;
        else                         sel = S_NONE;
    end

    // The holding register's refresh was optional and has not gone out yet.
    logic op_ref_optional;
    wire  swap = op_valid & op_ref & op_ref_optional & ~op_issue & ~ref_forced
               & (vid_urgent | cpu_req);

    wire free = ~op_valid | op_issue | swap;
    wire load = init_done & free & (sel != S_NONE);
    assign ref_taken  = load & (sel == S_REF);
    assign ref_refund = swap;

    assign vid_ack = load & (sel == S_VID);
    assign cpu_ack = load & (sel == S_CPU);
    assign ldr_ack = load & (sel == S_LDR);
    assign aux_ack = load & (sel == S_AUX);

    always_ff @(posedge clk) begin
        if (reset) begin
            op_valid <= 1'b0;
            op_ref   <= 1'b0;
            op_we    <= 1'b0;
            op_addr  <= 24'd0;
            op_len   <= LEN_1;
            op_wdata <= 64'd0;
            op_wbe   <= 8'd0;
            op_tag   <= TAG_CPU;
            op_ref_optional <= 1'b0;
        end
        else if (free) begin
            op_valid <= load;
            op_ref   <= (sel == S_REF);
            op_ref_optional <= ~ref_forced;
            case (sel)
                S_VID: begin
                    op_we <= 1'b0;   op_addr <= vid_addr;  op_len <= vid_len;
                    op_wdata <= 64'd0; op_wbe <= 8'd0;     op_tag <= TAG_VID;
                end
                S_CPU: begin
                    op_we <= cpu_we; op_addr <= cpu_addr;  op_len <= cpu_len;
                    op_wdata <= cpu_wdata; op_wbe <= cpu_wbe; op_tag <= TAG_CPU;
                end
                S_LDR: begin
                    op_we <= ldr_we; op_addr <= ldr_addr;  op_len <= ldr_len;
                    op_wdata <= ldr_wdata; op_wbe <= ldr_wbe; op_tag <= TAG_LDR;
                end
                S_AUX: begin
                    op_we <= 1'b0;   op_addr <= aux_addr;  op_len <= aux_len;
                    op_wdata <= 64'd0; op_wbe <= 8'd0;     op_tag <= TAG_AUX;
                end
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Read words back to their client
    // ------------------------------------------------------------------
    assign rdata      = rd_data;
    assign vid_rvalid = rd_valid & (rd_tag == TAG_VID);
    assign cpu_rvalid = rd_valid & (rd_tag == TAG_CPU);
    assign ldr_rvalid = rd_valid & (rd_tag == TAG_LDR);
    assign aux_rvalid = rd_valid & (rd_tag == TAG_AUX);
    assign vid_rlast  = vid_rvalid & rd_last;
    assign cpu_rlast  = cpu_rvalid & rd_last;
    assign ldr_rlast  = ldr_rvalid & rd_last;
    assign aux_rlast  = aux_rvalid & rd_last;

    // ------------------------------------------------------------------
    // Statistics
    // ------------------------------------------------------------------
    logic [15:0] now;
    always_ff @(posedge clk)
        now <= reset ? 16'd0 : now + 16'd1;

    // CPU: one request at a time.
    logic        cpu_waiting;   // request up, not acked yet
    logic        cpu_rd_wait;   // read acked, first word not back yet
    logic [15:0] cpu_t0;
    logic [15:0] cpu_rd_t0;
    wire  [15:0] cpu_start = cpu_waiting ? cpu_t0 : now;

    always_ff @(posedge clk) begin
        if (reset) begin
            cpu_waiting <= 1'b0;
            cpu_rd_wait <= 1'b0;
            cpu_t0      <= 16'd0;
            cpu_rd_t0   <= 16'd0;
            cpu_lat_max <= 16'd0;
        end
        else begin
            if (cpu_ack) begin
                cpu_waiting <= 1'b0;
                if (cpu_we) begin
                    if (now - cpu_start > cpu_lat_max)
                        cpu_lat_max <= now - cpu_start;
                end
                else begin
                    cpu_rd_wait <= 1'b1;
                    cpu_rd_t0   <= cpu_start;
                end
            end
            else if (cpu_req && !cpu_waiting) begin
                cpu_waiting <= 1'b1;
                cpu_t0      <= now;
            end

            if (cpu_rd_wait && cpu_rvalid) begin
                cpu_rd_wait <= 1'b0;
                if (now - cpu_rd_t0 > cpu_lat_max)
                    cpu_lat_max <= now - cpu_rd_t0;
            end
        end
    end

    // VID: several reads may be in flight; their words come back in order.
    logic [15:0] vq_t0  [4];     // when the read became urgent
    logic        vq_u   [4];     // ...if it ever did
    logic [15:0] vq_dl  [4];
    logic [1:0]  vq_wr, vq_rd;
    logic        vid_first;      // the next VID word is the first of its read
    logic        vid_waiting;    // the current request has become urgent
    logic [15:0] vid_t0;

    always_ff @(posedge clk) begin
        if (reset) begin
            vq_wr         <= 2'd0;
            vq_rd         <= 2'd0;
            vid_first     <= 1'b1;
            vid_waiting   <= 1'b0;
            vid_t0        <= 16'd0;
            vid_lat_max   <= 16'd0;
            vid_underruns <= 16'd0;
        end
        else begin
            if (vid_ack) begin
                vq_t0[vq_wr] <= vid_waiting ? vid_t0 : now;
                vq_u[vq_wr]  <= vid_waiting | vid_urgent;
                vq_dl[vq_wr] <= now + vid_deadline;
                vq_wr        <= vq_wr + 2'd1;
                vid_waiting  <= 1'b0;
            end
            else if (vid_urgent && !vid_waiting) begin
                vid_waiting <= 1'b1;
                vid_t0      <= now;
            end

            if (vid_rvalid) begin
                vid_first <= rd_last;
                if (vid_first && vq_u[vq_rd] && (now - vq_t0[vq_rd] > vid_lat_max))
                    vid_lat_max <= now - vq_t0[vq_rd];
                if (rd_last) begin
                    if ($signed(now - vq_dl[vq_rd]) > 0)
                        vid_underruns <= vid_underruns + 16'd1;
                    vq_rd <= vq_rd + 2'd1;
                end
            end
        end
    end

endmodule
