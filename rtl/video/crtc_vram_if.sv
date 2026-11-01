//
// Video-memory interface of a CRTC adapter (CGA, HGC): replaces the video side
// of a dual-port BRAM with a vram_fetch engine.
//
// The adapter reads two bytes of video memory per CRTC character, the character
// and the attribute (the even and the odd byte of one 16-bit word), at fixed
// slots of its sequencer. The word is asked for one character ahead: when the
// CRTC has just moved to character n it already knows the address of n+1, so
// the request goes out at slot 1 and is used at the next character's slots 2/3.
// The word is taken from the head of the queue at the very slot where the BRAM
// used to be sampled, so a CPU write that the engine has seen by then is
// displayed and a later one is not, as with the BRAM.
//
// This module is clocked by clk_sdram and works on events: one-clock pulses,
// derived by the wrapper from the sequencer phase of the adapter, at
//   ev_req  the CRTC has just advanced; next_addr is the word it will read next
//   ev_chr  the character byte is sampled now (vram_d <= low byte)
//   ev_att  the attribute byte is sampled now (vram_d <= high byte)
//   ev_pop  the word is not needed any more (always together with an ev_att)
//
// If the queue is empty at ev_req (start-up, or after a mismatch the engine
// lost track of) the word of the current character cannot be there: the turn
// is skipped ("prime") and the next one is in step.
//
// In step the queue holds exactly one word at ev_req, the current character's.
// More means it still holds words of characters already gone: a reset of the
// card, or a change of the 40/80-column timing, between the request of a word
// and its pop. The display would then stay that many characters to the right,
// across resets too, since the engine and this module are only reset with the
// SDRAM. The oldest word is dropped right after ev_req, one per character,
// until the queue is back in step.
//
module crtc_vram_if (
    input  logic        clk,
    input  logic        reset,

    input  logic        ev_req,
    input  logic        ev_chr,
    input  logic        ev_att,
    input  logic        ev_pop,
    input  logic [23:0] cur_addr,       // word the CRTC is addressing now
    input  logic [23:0] next_addr,      // word it will address at the next character
    input  logic [15:0] deadline,       // clk_sdram cycles from ev_req to ev_pop of that word

    output logic [7:0]  vram_d,         // the byte the adapter sees as RAM data

    output logic        req_valid,
    output logic [23:0] req_addr,
    output logic [1:0]  req_len,
    output logic [15:0] req_deadline,
    input  logic        req_ready,
    input  logic        rsp_pending,
    input  logic        rsp_valid,
    input  logic [63:0] rsp_data,
    input  logic [23:0] rsp_addr,
    output logic        rsp_pop,

    output logic [15:0] mismatch_count, // the head was not the word being addressed
    output logic [15:0] late_count,     // a byte was due and its word had not arrived
    output logic [15:0] dropped_count   // a request that could not be queued
);
    logic        prime;
    logic        req_pend;
    logic [23:0] req_addr_r;
    logic [15:0] req_dl_r;
    logic [3:0]  queued;        // words accepted by the engine and not popped
    logic        trim;          // drop the head: a word of a character already gone

    assign req_len      = 2'd0;
    assign req_valid    = req_pend;
    assign req_addr     = req_addr_r;
    assign req_deadline = req_dl_r;

    wire have_head = rsp_pending && !prime;

    assign rsp_pop = (ev_pop && have_head) || (trim && rsp_pending);

    always_ff @(posedge clk) begin
        if (reset) begin
            prime          <= 1'b1;
            req_pend       <= 1'b0;
            req_addr_r     <= 24'd0;
            req_dl_r       <= 16'd0;
            queued         <= 4'd0;
            trim           <= 1'b0;
            vram_d         <= 8'hFF;
            mismatch_count <= 16'd0;
            late_count     <= 16'd0;
            dropped_count  <= 16'd0;
        end
        else begin
            if (req_pend && req_ready)
                req_pend <= 1'b0;

            queued <= queued + {3'd0, req_pend && req_ready} - {3'd0, rsp_pop};
            trim   <= ev_req && (queued > 4'd1);

            if (ev_req) begin
                prime <= !rsp_pending;
                if (req_pend && !req_ready && dropped_count != 16'hFFFF)
                    dropped_count <= dropped_count + 16'd1;
                req_pend   <= 1'b1;
                req_addr_r <= next_addr;
                req_dl_r   <= deadline;
            end

            if (ev_chr && have_head) begin
                if (rsp_addr != cur_addr && mismatch_count != 16'hFFFF)
                    mismatch_count <= mismatch_count + 16'd1;
                if (rsp_valid) vram_d <= rsp_data[7:0];
                else if (late_count != 16'hFFFF) late_count <= late_count + 16'd1;
            end

            if (ev_att && have_head) begin
                if (rsp_valid) vram_d <= rsp_data[15:8];
                else if (late_count != 16'hFFFF) late_count <= late_count + 16'd1;
            end

            if (ev_pop)
                prime <= 1'b0;
        end
    end

endmodule
