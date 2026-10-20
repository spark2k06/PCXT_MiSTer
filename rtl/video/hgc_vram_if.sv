//
// HGC side of the video-memory fetch (see crtc_vram_if.sv). hgc_sequencer.v
// advances the CRTC at the end of slot 0 and the card samples the character
// and the attribute bytes at the end of the slots where vram_read_char and
// vram_read_att are high:
//
//   graphics  characters of 32 slots; the word is sampled twice, at the end of
//             slots 2/3 (character/attribute) and again at 18/19; the word is
//             released after the second sample
//   text      characters of 18 slots; character at the end of slot 3 and
//             attribute at the end of slot 4
//
// The BRAM the card used to read changed its output at the end of the slot
// before the one the card samples, so the bytes are taken from the head of the
// queue one slot earlier than they are sampled: the events below fire when the
// sequencer enters the slot before. A slot is two clk_sdram cycles (clk_vga_hgc
// is 57.27 MHz, clk_sdram 114.545, both rising edges coincide) and the adapter
// sees the phase one cycle late, so vram_d changes at the very edge that ends
// that slot and the card has a whole slot of margin. Taking the bytes at the
// start of the sampled slot, as the CGA does, would change vram_d at the edge
// where the card samples it: the card would read the previous byte.
//
// The 32 KiB page selected by the Hercules control register is the top bit of
// the word address.
//
module hgc_vram_if #(
    parameter logic [23:0] BASE = 24'h043_0000      // word address of the HGC region (64 KiB)
) (
    input  logic        clk,                // clk_sdram
    input  logic        reset,

    input  logic [4:0]  seq_phase,          // hgc_sequencer clkdiv
    input  logic        grph,               // graphics mode
    input  logic        page,               // graphics page (hercules control bit 7)
    input  logic [13:0] cur_word,           // ram_a[14:1]
    input  logic [13:0] next_word,          // fx_next_word
    output logic [7:0]  vram_d,

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

    output logic [15:0] mismatch_count,
    output logic [15:0] late_count,
    output logic [15:0] dropped_count,

    // events and addresses, for the testbenches
    output logic        dbg_ev_req,
    output logic        dbg_ev_chr,
    output logic        dbg_ev_att,
    output logic [23:0] dbg_cur_addr,
    output logic [23:0] dbg_next_addr
);
    logic [4:0]  ph_s, ph_p;
    logic        grph_s, page_s;
    logic [13:0] cur_s, nxt_s;

    always_ff @(posedge clk) begin
        ph_s   <= seq_phase;
        ph_p   <= ph_s;
        grph_s <= grph;
        page_s <= page;
        cur_s  <= cur_word;
        nxt_s  <= next_word;
    end

    wire ph_ev = (ph_s != ph_p);

    // fx_next_word is registered in the HGC: it is settled from slot 2
    wire ev_req = ph_ev && (ph_s == 5'd2);
    wire ev_chr = ph_ev && (grph_s ? ((ph_s == 5'd1) || (ph_s == 5'd17)) : (ph_s == 5'd2));
    wire ev_att = ph_ev && (grph_s ? ((ph_s == 5'd2) || (ph_s == 5'd18)) : (ph_s == 5'd3));
    wire ev_pop = ph_ev && (grph_s ? (ph_s == 5'd18) : (ph_s == 5'd3));

    // From the request to the first byte of that word, in clk_sdram cycles (two
    // per slot): graphics from slot 2 to slot 1 of the next character, 31
    // slots; text 18 slots.
    wire [15:0] deadline = grph_s ? 16'd62 : 16'd36;

    wire [23:0] cur_addr  = BASE + {9'd0, page_s, cur_s};
    wire [23:0] next_addr = BASE + {9'd0, page_s, nxt_s};

    assign dbg_ev_req = ev_req;
    assign dbg_ev_chr = ev_chr;
    assign dbg_ev_att = ev_att;
    assign dbg_cur_addr  = cur_addr;
    assign dbg_next_addr = next_addr;

    crtc_vram_if u_if (
        .clk(clk), .reset(reset),
        .ev_req(ev_req), .ev_chr(ev_chr), .ev_att(ev_att), .ev_pop(ev_pop),
        .cur_addr(cur_addr), .next_addr(next_addr), .deadline(deadline),
        .vram_d(vram_d),
        .req_valid(req_valid), .req_addr(req_addr), .req_len(req_len),
        .req_deadline(req_deadline), .req_ready(req_ready),
        .rsp_pending(rsp_pending), .rsp_valid(rsp_valid), .rsp_data(rsp_data),
        .rsp_addr(rsp_addr), .rsp_pop(rsp_pop),
        .mismatch_count(mismatch_count), .late_count(late_count), .dropped_count(dropped_count)
    );

endmodule
