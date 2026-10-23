//
// CGA side of the video-memory fetch (see crtc_vram_if.sv). The CGA sequencer
// (cga_sequencer.v) advances the CRTC at the end of slot 0 (and 16 in 80-column
// modes) and samples the character byte at the end of slot 2 and the attribute
// byte at the end of slot 3 (18 and 19). The BRAM it used to read captured the
// address of slot 1 (2) at the end of slot 1 (2), so the byte lanes are taken
// from the head of the queue at the start of slots 2 and 3 (18 and 19). The
// word of the next character is asked for at slot 2 (18), when the registered
// fx_next_word of the card has settled.
//
// All CGA signals are registered or settled in the 28.636 MHz domain, which is
// phase-locked to clk_sdram (114.545 MHz, 4:1), and are sampled here.
//
// Tandy 1000: the video memory is system RAM, in the
// 128 KiB block of the CPU image that port A0h chose, so the words are read
// from there instead of from the CGA region. Port 3DFh adds the CRT page: with
// the 640x200 / 320x200x16 timing (tandy_wide) the pages are 32 KiB (the card's
// bit 14 is a real address bit) and 3DFh bits 2:1 pick one, else they are
// 16 KiB and bits 2:0 pick one (the card's bit 14 is dropped).
//
module cga_vram_if #(
    parameter logic [23:0] BASE  = 24'h042_8000,    // word address of the CGA region
    parameter logic [23:0] TBASE = 24'h000_0000     // word address of the CPU image (Tandy)
) (
    input  logic        clk,                // clk_sdram
    input  logic        reset,

    input  logic [4:0]  seq_phase,          // cga_sequencer clkdiv
    input  logic        hres,               // 80-column timing (hres_mode)
    input  logic [13:0] cur_word,           // ram_a[14:1]: word being addressed
    input  logic [13:0] next_word,          // fx_next_word: word of the next character
    input  logic        tandy,              // Tandy 1000 video: read the shared RAM
    input  logic [2:0]  tandy_block,        // A0h bits 3:1
    input  logic [2:0]  tandy_crt_page,     // 3DFh bits 2:0
    input  logic        tandy_wide,         // 32 KiB pages (tandy_16_gfx; PCjr: 3DFh bits 7:6 = 11)
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
    logic        hres_s;
    logic [13:0] cur_s, nxt_s;
    logic        t_s;
    logic [2:0]  tb_s, tp_s;
    logic        tw_s;

    always_ff @(posedge clk) begin
        ph_s   <= seq_phase;
        ph_p   <= ph_s;
        hres_s <= hres;
        cur_s  <= cur_word;
        nxt_s  <= next_word;
        t_s    <= tandy;
        tb_s   <= tandy_block;
        tp_s   <= tandy_crt_page;
        tw_s   <= tandy_wide;
    end

    wire ph_ev = (ph_s != ph_p);

    // fx_next_word is registered in the CGA: it is settled from slot 2 (18)
    wire ev_req = ph_ev && ((ph_s == 5'd2)  || (hres_s && ph_s == 5'd18));
    wire ev_chr = ph_ev && ((ph_s == 5'd2)  || (hres_s && ph_s == 5'd18));
    wire ev_att = ph_ev && ((ph_s == 5'd3)  || (hres_s && ph_s == 5'd19));

    // From the request to the first sample of that word (4 clk_sdram per CGA
    // slot): 16 slots in 80-column modes, 32 in 40-column modes. The arbiter
    // takes it as urgent once it is within T_URGENT of this.
    wire [15:0] deadline = hres_s ? 16'd64 : 16'd128;

    // Word offset in the 128 KiB (64 Ki words) block
    function automatic logic [15:0] t_off(input logic [13:0] w);
        t_off = tw_s ? {tp_s[2:1], w} : {tp_s, w[12:0]};
    endfunction

    wire [23:0] cur_addr  = t_s ? TBASE + {5'd0, tb_s, t_off(cur_s)} : BASE + {10'd0, cur_s};
    wire [23:0] next_addr = t_s ? TBASE + {5'd0, tb_s, t_off(nxt_s)} : BASE + {10'd0, nxt_s};

    assign dbg_ev_req = ev_req;
    assign dbg_ev_chr = ev_chr;
    assign dbg_ev_att = ev_att;
    assign dbg_cur_addr  = cur_addr;
    assign dbg_next_addr = next_addr;

    crtc_vram_if u_if (
        .clk(clk), .reset(reset),
        .ev_req(ev_req), .ev_chr(ev_chr), .ev_att(ev_att), .ev_pop(ev_att),
        .cur_addr(cur_addr), .next_addr(next_addr),
        .deadline(deadline),
        .vram_d(vram_d),
        .req_valid(req_valid), .req_addr(req_addr), .req_len(req_len),
        .req_deadline(req_deadline), .req_ready(req_ready),
        .rsp_pending(rsp_pending), .rsp_valid(rsp_valid), .rsp_data(rsp_data),
        .rsp_addr(rsp_addr), .rsp_pop(rsp_pop),
        .mismatch_count(mismatch_count), .late_count(late_count), .dropped_count(dropped_count)
    );

endmodule
