//
// A real CGA or HGC card fed from SDRAM through its adapter and a vram_fetch
// engine, against an ideal video memory.
//
//   CARD = 0  cga + cga_vram_if      CARD = 1  hgc + hgc_vram_if
//   CARD = 0 with TANDY = 1: the CGA as a Tandy 1000 video: the
//            words are read from a 128 KiB block of system RAM that port A0h
//            chose, page by port 3DFh, and the golden card is the 128 KiB BRAM
//            the Tandy1000 core had, addressed as it did
//
// The card runs on its own clock (28.636 or 57.27 MHz) derived from the 114.545
// MHz clock of the arbiter by an integer divider, as in the core. A CPU model
// writes into the video region through the real arbiter CPU port, at random
// times and also at the very word the CRTC is about to read, and loads the
// arbiter with reads. The reference is an associative array that takes every
// write at the same clock the engine's snoop sees it, read at the same events
// (the sampling slots of the adapter). At every sampling event the byte the
// adapter hands to the card must equal the reference byte.
//
// Phases drive the card through the standard BIOS modes (text 80x25 and 40x25,
// graphics 320x200 and 640x200 for the CGA; text and Hercules graphics, both
// pages, for the HGC), one frame each plus a start-address change per frame.
// The last phase leaves the adapter's queue with words it will not pop (the
// CGA reset twice just after it asked for a word, as the core's reset can; the
// HGC set to text in mid-character), and it must be back in step with
// the CRTC.
// Reported: samples compared, data mismatches, address mismatches of the
// adapter (the head was not the word being addressed), late bytes, underruns.
//
`timescale 1ns / 1ps

module video_fetch_chain_tb #(
    parameter int CARD      = 0,
    parameter int WR_GAP    = 40,       // average clocks between CPU accesses
    parameter int TARGET    = 3,        // 1 in TARGET characters gets a write aimed at it
    parameter int FRAMES    = 1,        // frames per phase
    parameter int PHASES    = 99,       // number of phases to run (for quick runs)
    parameter int CMP       = 0,        // no CPU writes, and a card on a BRAM model beside it, compared pixel by pixel
    parameter int TANDY     = 0         // CARD 0 only: Tandy 1000 video memory
);
    import sdram_pkg::*;

    localparam real TCK  = 8.730;
    localparam real LEAD = 2.0;
    localparam real TCO  = 3.0;

    // Tandy: the video memory is the CPU image, block 5 of 128 KiB until a phase moves it
    localparam int          TBLK0 = 5;
    localparam logic [23:0] BASE = (CARD == 0) ? (TANDY ? 24'(TBLK0) << 16 : PHYS_CGA[24:1]) : PHYS_HGC[24:1];
    localparam int          NW   = (CARD == 0) ? (TANDY ? 65536 : 8192) : 32768;      // words of the region

    logic [2:0] t_block = 3'(TBLK0);    // A0h bits 3:1
    logic [5:0] t_page  = 6'd0;         // 3DFh

    // ------------------------------------------------------------------
    // Clocks: 114.545 (arbiter), 57.27 (HGC), 28.636 (CGA), all from one edge
    // ------------------------------------------------------------------
    logic clk = 1'b0, clk57 = 1'b0, clk28 = 1'b0, sdram_clk = 1'b0;
    // One family: the rising edges of the 57.27 and 28.636 MHz clocks coincide
    // with rising edges of clk, as the outputs of one PLL do (phase 0).
    int  clk_k = 0;
    always #(TCK / 2.0) begin
        clk   <= (clk_k % 2) == 0;
        clk57 <= (clk_k % 4) <  2;
        clk28 <= (clk_k % 8) <  4;
        clk_k <= clk_k + 1;
    end
    initial begin
        #(TCK - LEAD);
        forever #(TCK / 2.0) sdram_clk = ~sdram_clk;
    end
    logic reset = 1'b1;
    wire  cclk = (CARD == 0) ? clk28 : clk57;
    wire  vreset;     // the engine and its adapter wait for the chip, as in PCXT.sv

    // ------------------------------------------------------------------
    // SDRAM chain
    // ------------------------------------------------------------------
    logic        cpu_req = 0, cpu_we = 0;  logic [23:0] cpu_addr = 0;  logic [1:0] cpu_len = 0;
    logic [63:0] cpu_wdata = 0;  logic [7:0] cpu_wbe = 0;
    wire         cpu_ack, cpu_rvalid, cpu_rlast;
    wire         ldr_ack, ldr_rvalid, ldr_rlast, aux_ack, aux_rvalid, aux_rlast;
    wire [15:0]  rdata;
    logic        stop = 0;

    wire        vid_req, vid_ack, vid_rvalid, vid_rlast;
    wire [23:0] vid_addr;  wire [1:0] vid_len;  wire [15:0] vid_deadline;

    wire        op_valid, op_ref, op_we, op_issue, init_done;
    assign vreset = reset | ~init_done;
    wire [23:0] op_addr;  wire [1:0] op_len;  wire [63:0] op_wdata;  wire [7:0] op_wbe;
    wire [1:0]  op_tag;
    wire        rd_valid, rd_last;  wire [15:0] rd_data;  wire [1:0] rd_tag;
    wire [15:0] cpu_lat_max, vid_lat_max, vid_underruns;
    wire [3:0]  ref_debt;
    wire [3:0]  bank_idle;

    sdram_arbiter arb (
        .clk(clk), .reset(reset), .init_done(init_done),
        .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
        .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_len(cpu_len),
        .cpu_wdata(cpu_wdata), .cpu_wbe(cpu_wbe),
        .cpu_ack(cpu_ack), .cpu_rvalid(cpu_rvalid), .cpu_rlast(cpu_rlast),
        .ldr_req(1'b0), .ldr_we(1'b1), .ldr_addr(24'd0), .ldr_len(LEN_1),
        .ldr_wdata(64'd0), .ldr_wbe(8'h03), .ldr_high(1'b0),
        .ldr_ack(ldr_ack), .ldr_rvalid(ldr_rvalid), .ldr_rlast(ldr_rlast),
        .aux_req(1'b0), .aux_addr(24'd0), .aux_len(LEN_2),
        .aux_ack(aux_ack), .aux_rvalid(aux_rvalid), .aux_rlast(aux_rlast),
        .rdata(rdata),
        .op_valid(op_valid), .op_ref(op_ref), .op_we(op_we), .op_addr(op_addr),
        .op_len(op_len), .op_wdata(op_wdata), .op_wbe(op_wbe), .op_tag(op_tag),
        .op_issue(op_issue), .bank_idle(bank_idle), .rd_valid(rd_valid), .rd_data(rd_data),
        .rd_tag(rd_tag), .rd_last(rd_last),
        .cpu_lat_max(cpu_lat_max), .vid_lat_max(vid_lat_max),
        .vid_underruns(vid_underruns), .ref_debt(ref_debt)
    );

    wire        c_cke, c_cs_n, c_ras_n, c_cas_n, c_we_n, c_oe;
    wire [1:0]  c_ba, c_dqm;  wire [12:0] c_a;  wire [15:0] c_dq;
    logic       p_cke = 0, p_cs_n = 1, p_ras_n = 1, p_cas_n = 1, p_we_n = 1, p_oe = 0;
    logic [1:0] p_ba = 0, p_dqm = 3;  logic [12:0] p_a = 0;  logic [15:0] p_dq = 0;

    always @(posedge clk) begin
        #(TCO);
        {p_cke, p_cs_n, p_ras_n, p_cas_n, p_we_n, p_oe} = {c_cke, c_cs_n, c_ras_n, c_cas_n, c_we_n, c_oe};
        {p_ba, p_dqm, p_a, p_dq} = {c_ba, c_dqm, c_a, c_dq};
    end

    wire [15:0] chip_dq;  wire chip_drive, chip_valid;
    wire [15:0] dq_pin = p_oe ? p_dq : (chip_drive ? chip_dq : 16'hF10A);

    sdram_ctrl #(.INIT_US(20)) ctrl (
        .clk(clk), .reset(reset), .init_done(init_done),
        .op_valid(op_valid), .op_ref(op_ref), .op_we(op_we), .op_addr(op_addr),
        .op_len(op_len), .op_wdata(op_wdata), .op_wbe(op_wbe), .op_tag(op_tag),
        .op_issue(op_issue), .bank_idle(bank_idle), .rd_valid(rd_valid), .rd_data(rd_data),
        .rd_tag(rd_tag), .rd_last(rd_last),
        .sdram_cke(c_cke), .sdram_cs_n(c_cs_n), .sdram_ras_n(c_ras_n), .sdram_cas_n(c_cas_n),
        .sdram_we_n(c_we_n), .sdram_ba(c_ba), .sdram_a(c_a), .sdram_dqm(c_dqm),
        .sdram_dq_out(c_dq), .sdram_dq_oe(c_oe), .sdram_dq_in(dq_pin)
    );

    sdram_model #(.TCK(TCK), .CL(3)) chip (
        .clk(sdram_clk), .cke(p_cke), .cs_n(p_cs_n), .ras_n(p_ras_n), .cas_n(p_cas_n),
        .we_n(p_we_n), .ba(p_ba), .a(p_a), .dqm(p_dqm), .dq_in(p_dq), .dq_in_oe(p_oe),
        .dq_out(chip_dq), .dq_drive(chip_drive), .dq_valid(chip_valid)
    );

    // Snoop tap, as in PCXT.sv
    logic        sn_valid = 1'b0;
    logic [23:0] sn_addr = 0;  logic [1:0] sn_len = 0;
    logic [63:0] sn_wdata = 0; logic [7:0] sn_wbe = 0;
    always_ff @(posedge clk) begin
        sn_valid <= cpu_ack & cpu_we;
        sn_addr  <= cpu_addr;
        sn_len   <= cpu_len;
        sn_wdata <= cpu_wdata;
        sn_wbe   <= cpu_wbe;
    end

    // ------------------------------------------------------------------
    // Engine and adapter
    // ------------------------------------------------------------------
    wire        req_v, req_r, rsp_p, rsp_v, rsp_pop;
    wire [23:0] req_a, rsp_a;  wire [1:0] req_l;  wire [15:0] req_d;
    wire [63:0] rsp_d;
    wire [15:0] under, mism, late, dropped;
    wire [7:0]  vram_d;
    wire        ev_req, ev_chr, ev_att;
    wire [23:0] cur_addr, next_addr;

    vram_fetch #(.DEPTH(3), .MAX_WORDS(1)) eng (
        .clk(clk), .reset(vreset),
        .req_valid(req_v), .req_addr(req_a), .req_len(req_l), .req_deadline(req_d), .req_ready(req_r),
        .rsp_pending(rsp_p), .rsp_valid(rsp_v), .rsp_data(rsp_d), .rsp_addr(rsp_a), .rsp_len(),
        .rsp_pop(rsp_pop), .flush(1'b0),
        .snoop_valid(sn_valid), .snoop_addr(sn_addr), .snoop_len(sn_len),
        .snoop_wdata(sn_wdata), .snoop_wbe(sn_wbe),
        .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
        .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast), .vid_rdata(rdata),
        .underrun_count(under), .occupancy()
    );

    // ------------------------------------------------------------------
    // The card
    // ------------------------------------------------------------------
    logic [14:0] bus_a = 15'h0;
    logic        bus_ior_l = 1'b1, bus_iow_l = 1'b1;
    logic [7:0]  bus_d = 8'h00;
    logic        card_reset = 1'b1;

    wire [4:0]  c_phase;
    wire [13:0] c_cur_word, c_next_word;
    wire        c_hres, c_grph, c_page;
    wire [18:0] c_ram_a;
    wire        vsync_w;

    // pixel comparison against the BRAM card (CMP)
    longint pix_n = 0, pix_bad = 0;
    logic   pix_on = 1'b0;

    generate
        if (CARD == 0) begin : g_cga
            wire hsync, vsync, hblank, vblank;
            wire [3:0] video;
            cga card (
                .clk(clk28), .reset(card_reset), .clkdiv(c_phase),
                .bus_a(bus_a), .bus_ior_l(bus_ior_l), .bus_iow_l(bus_iow_l),
                .bus_memr_l(1'b1), .bus_memw_l(1'b1), .bus_d(bus_d), .bus_out(), .bus_dir(),
                .bus_aen(1'b0), .bus_rdy(),
                .ram_we_l(), .ram_a(c_ram_a), .ram_d(vram_d),
                .hsync(hsync), .hblank(hblank), .raw_hblank(), .dbl_hsync(), .vsync(vsync), .vblank(vblank),
                .vblank_border(), .raw_vblank(), .hsync_ref(), .vsync_ref(), .std_hsyncwidth(),
                .de_o(), .raw_de_o(), .video(video), .dbl_video(), .comp_video(),
                .splashscreen(1'b0), .composite(1'b0), .thin_font(1'b0), .tandy_video(TANDY != 0), .pcjr(1'b0), .pcjr_addr_mode(2'b00),
                .scandouble_en(1'b0), .grph_mode(c_grph), .hres_mode(c_hres), .bw_mode(), .mode_640(),
                .composite_hsync_width(), .composite_border_color(), .composite_phase(), .tandy_color_16(),
                .cga_hw(1'b1), .crt_h_offset(4'd0), .crt_v_offset(3'd0),
                .vsync_width_osd(3'd0), .hsync_width_osd(3'd0), .frame_stack_rebuild(1'b0),
                .fx_next_word(c_next_word)
            );
            // Golden card on the BRAM the core had before F2 (see the HGC)
            wire hsync_r, vsync_r, hblank_r, vblank_r;
            wire [3:0] video_r;
            wire [18:0] ram_a_r;
            wire        ram_we_r;
            wire [7:0]  ram_d_r;
            wire        grph_r, hres_r;
            // The address of the Tandy1000 core's BRAM port B (Peripherals.sv): with
            // the 32 KiB timing the card's bit 14 is an address bit and 3DFh[2:1]
            // pick the page, else bit 14 is dropped and 3DFh[2:0] pick it
            wire [16:0] ref_addrb = (TANDY == 0)  ? {3'b000, ram_a_r[13:0]} :
                                    (grph_r & hres_r) ? {t_page[2:1], ram_a_r[14:0]} :
                                                        {t_page[2:0], ram_a_r[13:0]};
            vram #(.AW(17)) ref_bram (
                .clka(clk28), .ena(1'b0), .wea(1'b0), .addra(17'd0), .dina(8'd0), .douta(),
                .clkb(clk28), .enb(ram_we_r), .web(1'b0), .addrb(ref_addrb), .dinb(8'd0), .doutb(ram_d_r)
            );
            cga card_ref (
                .clk(clk28), .reset(card_reset), .clkdiv(),
                .bus_a(bus_a), .bus_ior_l(bus_ior_l), .bus_iow_l(bus_iow_l),
                .bus_memr_l(1'b1), .bus_memw_l(1'b1), .bus_d(bus_d), .bus_out(), .bus_dir(),
                .bus_aen(1'b0), .bus_rdy(),
                .ram_we_l(ram_we_r), .ram_a(ram_a_r), .ram_d(ram_d_r),
                .hsync(hsync_r), .hblank(hblank_r), .raw_hblank(), .dbl_hsync(), .vsync(vsync_r), .vblank(vblank_r),
                .vblank_border(), .raw_vblank(), .hsync_ref(), .vsync_ref(), .std_hsyncwidth(),
                .de_o(), .raw_de_o(), .video(video_r), .dbl_video(), .comp_video(),
                .splashscreen(1'b0), .composite(1'b0), .thin_font(1'b0), .tandy_video(TANDY != 0), .pcjr(1'b0), .pcjr_addr_mode(2'b00),
                .scandouble_en(1'b0), .grph_mode(grph_r), .hres_mode(hres_r), .bw_mode(), .mode_640(),
                .composite_hsync_width(), .composite_border_color(), .composite_phase(), .tandy_color_16(),
                .cga_hw(1'b1), .crt_h_offset(4'd0), .crt_v_offset(3'd0),
                .vsync_width_osd(3'd0), .hsync_width_osd(3'd0), .frame_stack_rebuild(1'b0),
                .fx_next_word()
            );
            initial if (CMP)
                for (int i = 0; i < NW; i++) begin
                    ref_bram.vram[2*i]   = 8'(((i * 40503) ^ (i >> 3)) & 255);
                    ref_bram.vram[2*i+1] = 8'((((i * 40503) ^ (i >> 3)) >> 8) & 255);
                end
            always @(posedge clk28) if (CMP && pix_on) begin
                pix_n++;
                if ({hsync, vsync, hblank, vblank, video} !== {hsync_r, vsync_r, hblank_r, vblank_r, video_r}) begin
                    pix_bad++;
                    if (pix_bad <= 5) $display("%0.3f PIXEL differs: card %b%b%b%b %h, BRAM card %b%b%b%b %h",
                        $realtime, hsync, vsync, hblank, vblank, video, hsync_r, vsync_r, hblank_r, vblank_r, video_r);
                end
            end

            assign c_cur_word = c_ram_a[14:1];
            assign c_page     = 1'b0;
            assign vsync_w    = vsync;

            cga_vram_if #(.BASE(BASE)) vif (
                .clk(clk), .reset(vreset),
                .seq_phase(c_phase), .hres(c_hres), .cur_word(c_cur_word), .next_word(c_next_word),
                .tandy(TANDY != 0), .tandy_block(t_block), .tandy_crt_page(t_page[2:0]),
                .tandy_wide(c_grph & c_hres),
                .vram_d(vram_d),
                .req_valid(req_v), .req_addr(req_a), .req_len(req_l), .req_deadline(req_d), .req_ready(req_r),
                .rsp_pending(rsp_p), .rsp_valid(rsp_v), .rsp_data(rsp_d), .rsp_addr(rsp_a), .rsp_pop(rsp_pop),
                .mismatch_count(mism), .late_count(late), .dropped_count(dropped),
                .dbg_ev_req(ev_req), .dbg_ev_chr(ev_chr), .dbg_ev_att(ev_att),
                .dbg_cur_addr(cur_addr), .dbg_next_addr(next_addr)
            );
        end
        else begin : g_hgc
            wire hsync, vsync, hblank, vblank, de, video, intensity, std_hs, vb;
            wire grph_page;
            hgc card (
                .clk(clk57),
                .bus_a(bus_a), .bus_ior_l(bus_ior_l), .bus_iow_l(bus_iow_l),
                .bus_memr_l(1'b1), .bus_memw_l(1'b1), .bus_d(bus_d), .bus_out(), .bus_dir(),
                .bus_aen(1'b0), .bus_rdy(),
                .ram_we_l(), .ram_a(c_ram_a), .ram_d(vram_d),
                .hsync(hsync), .hblank(hblank), .vsync(vsync), .vblank(vblank),
                .de_o(de), .video(video), .intensity(intensity), .grph_mode(c_grph), .grph_page(grph_page),
                .std_hsyncwidth(std_hs), .vblank_border(vb), .hercules_hw(1'b1),
                .fx_next_word(c_next_word), .fx_phase(c_phase)
            );
            assign c_cur_word = c_ram_a[14:1];
            assign c_page     = grph_page;
            assign c_hres     = 1'b0;
            assign vsync_w    = vsync;

            // Golden card: the BRAM the core had before F2 (read-enabled by ram_we_l,
            // address registered at the card's clock), same bus, same clock
            wire hsync_r, vsync_r, hblank_r, vblank_r, de_r, video_r, intensity_r, std_hs_r, vb_r, grph_r, page_r;
            wire [18:0] ram_a_r;
            wire        ram_we_r;
            wire [7:0]  ram_d_r;
            vram #(.AW(16)) ref_bram (
                .clka(clk57), .ena(1'b0), .wea(1'b0), .addra(16'd0), .dina(8'd0), .douta(),
                .clkb(clk57), .enb(ram_we_r), .web(1'b0), .addrb({page_r, ram_a_r[14:0]}), .dinb(8'd0), .doutb(ram_d_r)
            );
            hgc card_ref (
                .clk(clk57),
                .bus_a(bus_a), .bus_ior_l(bus_ior_l), .bus_iow_l(bus_iow_l),
                .bus_memr_l(1'b1), .bus_memw_l(1'b1), .bus_d(bus_d), .bus_out(), .bus_dir(),
                .bus_aen(1'b0), .bus_rdy(),
                .ram_we_l(ram_we_r), .ram_a(ram_a_r), .ram_d(ram_d_r),
                .hsync(hsync_r), .hblank(hblank_r), .vsync(vsync_r), .vblank(vblank_r),
                .de_o(de_r), .video(video_r), .intensity(intensity_r), .grph_mode(grph_r), .grph_page(page_r),
                .std_hsyncwidth(std_hs_r), .vblank_border(vb_r), .hercules_hw(1'b1),
                .fx_next_word(), .fx_phase()
            );
            initial if (CMP)
                for (int i = 0; i < NW; i++) begin
                    ref_bram.vram[2*i]   = 8'(((i * 40503) ^ (i >> 3)) & 255);
                    ref_bram.vram[2*i+1] = 8'((((i * 40503) ^ (i >> 3)) >> 8) & 255);
                end
            always @(posedge clk57) if (CMP && pix_on) begin
                pix_n++;
                if ({hsync, vsync, hblank, vblank, de, video, intensity} !== {hsync_r, vsync_r, hblank_r, vblank_r, de_r, video_r, intensity_r}) begin
                    pix_bad++;
                    if (pix_bad <= 5) $display("%0.3f PIXEL differs: card %b%b%b%b%b%b%b, BRAM card %b%b%b%b%b%b%b",
                        $realtime, hsync, vsync, hblank, vblank, de, video, intensity,
                        hsync_r, vsync_r, hblank_r, vblank_r, de_r, video_r, intensity_r);
                end
            end

            hgc_vram_if #(.BASE(BASE)) vif (
                .clk(clk), .reset(vreset),
                .seq_phase(c_phase), .grph(c_grph), .page(c_page),
                .cur_word(c_cur_word), .next_word(c_next_word),
                .vram_d(vram_d),
                .req_valid(req_v), .req_addr(req_a), .req_len(req_l), .req_deadline(req_d), .req_ready(req_r),
                .rsp_pending(rsp_p), .rsp_valid(rsp_v), .rsp_data(rsp_d), .rsp_addr(rsp_a), .rsp_pop(rsp_pop),
                .mismatch_count(mism), .late_count(late), .dropped_count(dropped),
                .dbg_ev_req(ev_req), .dbg_ev_chr(ev_chr), .dbg_ev_att(ev_att),
                .dbg_cur_addr(cur_addr), .dbg_next_addr(next_addr)
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // Reference memory and checks
    // ------------------------------------------------------------------
    int errors = 0;
    task automatic err(input string m);
        errors++;
        if (errors <= 20) $display("%0.3f ERROR: %s", $realtime, m);
    endtask

    always @(p_oe or chip_drive) if (p_oe && chip_drive) err("DQ contention");

    // The reference is written one clock after the engine's snoop sees the write
    // (the snoop takes two clocks: it finds the words, then patches them).
    logic        rf_v = 1'b0;
    logic [23:0] rf_addr = 0;
    logic [1:0]  rf_len = 0;
    logic [63:0] rf_wdata = 0;
    logic [7:0]  rf_wbe = 0;

    logic [15:0] ref_mem [int unsigned];
    function automatic logic [15:0] rp(input int unsigned a);
        rp = ref_mem.exists(a) ? ref_mem[a] : 16'h0000;
    endfunction

    function automatic longint cyc();
        cyc = longint'($rtoi($realtime / TCK));
    endfunction

    logic [7:0] ref_d = 8'hFF;
    logic [15:0] rword;
    logic       chk_chr = 0, chk_att = 0;
    logic       measuring = 0;
    longint     n_cmp = 0, n_bad = 0;
    longint     n_cmp_ph = 0, n_bad_ph = 0;
    logic [15:0] mism_at_start, late_at_start, under_at_start, dropped_at_start;

    always @(posedge clk) begin
        // compare what the previous event produced
        if ((chk_chr || chk_att) && measuring) begin
            n_cmp++;
            if (vram_d !== ref_d) begin
                n_bad++;
                if (n_bad <= 8)
                    $display("%0.3f data differs: card sees %02h, ideal memory gives %02h (word %06h)",
                             $realtime, vram_d, ref_d, cur_addr);
            end
        end
        chk_chr <= ev_chr;
        chk_att <= ev_att;

        // ideal memory read at the same events, before this clock's write
        rword = rp(cur_addr);
        if (ev_chr) ref_d <= rword[7:0];
        if (ev_att) ref_d <= rword[15:8];

        // ideal memory write: one clock after the engine sees the snoop
        if (rf_v)
            for (int i = 0; i < len_words(rf_len); i++) begin
                int unsigned a = rf_addr + i;
                logic [15:0] o = rp(a);
                ref_mem[a] = {rf_wbe[2*i+1] ? rf_wdata[16*i+8 +: 8] : o[15:8],
                              rf_wbe[2*i]   ? rf_wdata[16*i   +: 8] : o[7:0]};
            end
        rf_v <= sn_valid;  rf_addr <= sn_addr;  rf_len <= sn_len;  rf_wdata <= sn_wdata;  rf_wbe <= sn_wbe;
    end

    // ------------------------------------------------------------------
    // CPU model: random writes, writes aimed at the next word, reads for load
    // ------------------------------------------------------------------
    typedef struct { logic [23:0] addr; longint when; } tw_t;
    tw_t tq [$];
    int  cpu_gap = 0;
    logic cpu_wait_data = 0;
    int  writes = 0, aimed = 0;

    always @(posedge clk) begin
        if (!reset && init_done && !stop) begin
            if (ev_req && ($urandom_range(0, TARGET - 1) == 0) && tq.size() < 4 && measuring) begin
                tw_t t;
                t.addr = next_addr;
                t.when = cyc() + $urandom_range(0, 70);
                tq.push_back(t);
            end
        end
        if (reset || !init_done) ;
        else if (cpu_req) begin
            if (cpu_ack) begin
                cpu_req <= 1'b0;
                if (cpu_we) writes++; else cpu_wait_data <= 1'b1;
            end
        end
        else if (cpu_wait_data) begin
            if (cpu_rlast) cpu_wait_data <= 1'b0;
        end
        else if (cpu_gap > 0)
            cpu_gap <= cpu_gap - 1;
        else if (!stop && measuring && !CMP) begin
            logic [23:0] a;
            logic we;
            we = 1'b1;
            if (tq.size() > 0 && tq[0].when <= cyc()) begin
                a = tq[0].addr;
                void'(tq.pop_front());
                aimed++;
            end
            else if ($urandom_range(0, 9) < 4) begin
                we = 1'b0;
                a  = {2'd0, 13'($urandom_range(64, 127)), 9'($urandom_range(0, 508))};
            end
            else
                a = BASE + 24'($urandom_range(0, NW - 1));
            cpu_req   <= 1'b1;
            cpu_we    <= we;
            cpu_len   <= LEN_1;
            cpu_addr  <= a;
            cpu_wdata <= {$urandom, $urandom};
            cpu_wbe   <= (($urandom_range(0, 9) < 4) ? 8'h03 : (($urandom_range(0, 1)) ? 8'h01 : 8'h02));
            cpu_gap   <= $urandom_range(0, 2 * WR_GAP);
        end
    end

    // ------------------------------------------------------------------
    // Programming the card (I/O writes on the card's clock)
    // ------------------------------------------------------------------
    localparam logic [14:0] IOB = (CARD == 0) ? 15'h3D0 : 15'h3B0;

    task automatic io_write(input logic [14:0] a, input logic [7:0] d);
        @(posedge cclk);
        bus_a <= a; bus_d <= d;
        @(posedge cclk);
        bus_iow_l <= 1'b0;
        repeat (6) @(posedge cclk);
        bus_iow_l <= 1'b1;
        repeat (4) @(posedge cclk);
    endtask

    task automatic crtc(input int r, input int v);
        io_write(IOB + 15'd4, 8'(r));
        io_write(IOB + 15'd5, 8'(v));
    endtask

    task automatic crtc_regs(input int t[10]);
        for (int i = 0; i < 10; i++) crtc(i, t[i]);
    endtask

    // Frame marker: vertical sync rising edge of the card
    event vs_rise;
    logic vs_q = 1'b0;
    always @(posedge cclk) begin
        vs_q <= vsync_w;
        if (vsync_w && !vs_q) -> vs_rise;
    end

    task automatic wait_frames(input int n);
        for (int i = 0; i < n; i++) @(vs_rise);
    endtask

    task automatic phase(input string name, input int frames);
        longint c0;
        // settle: one frame, nothing counted
        measuring = 0;
        wait_frames(1);
        repeat (2000) @(posedge clk);
        mism_at_start = mism; late_at_start = late; under_at_start = under; dropped_at_start = dropped;
        n_cmp_ph = n_cmp; n_bad_ph = n_bad;
        measuring = 1;
        pix_on = (CMP != 0);
        c0 = cyc();
        wait_frames(frames);
        measuring = 0;
        pix_on = 1'b0;
        $display("%-34s %7d samples, %0d data differences | adapter: %0d address mismatches, %0d late, %0d dropped | engine underruns %0d",
                 name, n_cmp - n_cmp_ph, n_bad - n_bad_ph,
                 mism - mism_at_start, late - late_at_start, dropped - dropped_at_start, under - under_at_start);
        if (n_bad != n_bad_ph) err($sformatf("%s: data differs from the ideal memory", name));
        if (mism != mism_at_start) err($sformatf("%s: address mismatches", name));
        if (late != late_at_start) err($sformatf("%s: late bytes", name));
        if (under != under_at_start) err($sformatf("%s: underruns", name));
    endtask

    // A write of a start address in mid-frame (the CRTC takes it at the next frame)
    task automatic new_start(input int sa);
        crtc(12, sa >> 8);
        crtc(13, sa & 255);
    endtask

    // A reset of the card (the core's reset) while the sequencer is at slot p:
    // the word asked for at that slot is never popped, so the queue of the
    // adapter is left with one word more than the CRTC is addressing
    task automatic reset_at_slot(input logic [4:0] p);
        @(posedge cclk iff c_phase == p - 5'd1);
        repeat (2) @(posedge clk);
        #1 card_reset = 1'b1;
        repeat (3) @(posedge cclk);
        card_reset = 1'b0;
        repeat (40) @(posedge cclk);
    endtask

    // HGC: text mode set at slot p of a graphics character. The text sequence
    // wraps at slot 17, so the pop at slot 18 of the word asked for at slot 2
    // never comes
    task automatic text_at_slot(input logic [4:0] p);
        @(posedge cclk iff c_phase == p);
        io_write(15'h3B8, 8'h28);
        repeat (40) @(posedge cclk);
    endtask

    // ------------------------------------------------------------------
    int bios80[10] = '{8'h71, 8'h50, 8'h5A, 8'h0A, 8'h1F, 8'h06, 8'h19, 8'h1C, 8'h02, 8'h07};
    int bios40[10] = '{8'h38, 8'h28, 8'h2D, 8'h0A, 8'h1F, 8'h06, 8'h19, 8'h1C, 8'h02, 8'h07};
    int gfx320[10] = '{8'h38, 8'h28, 8'h2D, 8'h0A, 8'h7F, 8'h06, 8'h64, 8'h70, 8'h02, 8'h01};
    int gfx640[10] = '{8'h38, 8'h28, 8'h2D, 8'h0A, 8'h7F, 8'h06, 8'h64, 8'h70, 8'h02, 8'h01};
    int hgcgfx[10] = '{8'h35, 8'h2D, 8'h2E, 8'h07, 8'h5B, 8'h02, 8'h57, 8'h57, 8'h02, 8'h03};
    int hgctxt[10] = '{8'h61, 8'h50, 8'h52, 8'h0F, 8'h19, 8'h06, 8'h19, 8'h19, 8'h02, 8'h0D};

    int ph = 0;

    initial begin
        // memory content, behind the controller's back
        for (int i = 0; i < NW; i++) begin
            chip.poke(BASE + 24'(i), 16'((i * 40503) ^ (i >> 3)));
            ref_mem[BASE + 24'(i)] = 16'((i * 40503) ^ (i >> 3));
        end
        repeat (10) @(posedge clk);
        reset = 1'b0;
        wait (init_done);
        repeat (50) @(posedge clk);
        card_reset = 1'b0;
        repeat (200) @(posedge cclk);

        if (CARD == 0) begin
            // 3D8 = 29h at power-up: 80x25 text, video on; the defaults of the CRTC are 80x25
            // With TANDY the CRT page (3DFh) changes with every phase: 16 KiB pages in
            // all but the last, which has the 32 KiB timing (3DFh[2:1] = 3, the top 32 KiB)
            io_write(15'h3D8, 8'h29);
            ph++; if (ph <= PHASES) begin crtc_regs(bios80); phase("CGA text 80x25 (mode 3)", FRAMES);
                  if (TANDY) t_page = 6'o03;
                  new_start(12'h140); phase("CGA text 80x25, new start address", FRAMES); end
            ph++; if (ph <= PHASES) begin if (TANDY) t_page = 6'o05;
                  io_write(15'h3D8, 8'h28); crtc_regs(bios40); new_start(0);
                  phase("CGA text 40x25 (mode 1)", FRAMES); end
            ph++; if (ph <= PHASES) begin if (TANDY) t_page = 6'o07;
                  io_write(15'h3D8, 8'h0A); crtc_regs(gfx320);
                  phase("CGA graphics 320x200 (mode 4)", FRAMES); end
            ph++; if (ph <= PHASES) begin if (TANDY) t_page = 6'o02;
                  io_write(15'h3D8, 8'h1E); crtc_regs(gfx640);
                  phase("CGA graphics 640x200 (mode 6)", FRAMES); end
            ph++; if (ph <= PHASES) begin if (TANDY) t_page = 6'o06;
                  io_write(15'h3D8, 8'h0B); crtc_regs(bios80); new_start(12'h080);
                  phase("CGA graphics, 80-column timing", FRAMES); end
            ph++; if (ph <= PHASES) begin if (TANDY) t_page = 6'o01;
                  reset_at_slot(5'd18); reset_at_slot(5'd2);
                  io_write(15'h3D8, 8'h29); crtc_regs(bios80); new_start(0);
                  phase("CGA text 80x25, resets in mid-character", FRAMES); end
        end
        else begin
            io_write(15'h3BF, 8'h03);                 // allow graphics and page 1
            io_write(15'h3B8, 8'h28);
            ph++; if (ph <= PHASES) begin crtc_regs(hgctxt); phase("HGC text 80x25", FRAMES); end
            ph++; if (ph <= PHASES) begin io_write(15'h3B8, 8'h0A); crtc_regs(hgcgfx);
                  phase("HGC graphics 720x348, page 0", FRAMES); end
            ph++; if (ph <= PHASES) begin io_write(15'h3B8, 8'h8A);
                  phase("HGC graphics 720x348, page 1", FRAMES); end
            ph++; if (ph <= PHASES) begin new_start(12'h200);
                  phase("HGC graphics, new start address", FRAMES); end
            ph++; if (ph <= PHASES) begin text_at_slot(5'd3); crtc_regs(hgctxt); new_start(0);
                  phase("HGC text, set in mid-character", FRAMES); end
        end

        stop = 1'b1;
        repeat (400) @(posedge clk);

        $display("%0d CPU writes (%0d aimed at the next word); arbiter: CPU latency max %0d, VID latency from urgency max %0d, VID underruns %0d",
                 writes, aimed, cpu_lat_max, vid_lat_max, vid_underruns);
        $display("%0d samples compared in total, %0d differences", n_cmp, n_bad);
        if (CMP != 0) begin
            $display("%0d pixels compared against the BRAM card, %0d differences", pix_n, pix_bad);
            if (pix_bad != 0) err("pixels differ from the BRAM card");
            if (pix_n < 1000) err("too few pixels compared");
        end
        if (n_cmp < 1000) err("too few samples compared");
        $display("RESULT: %s", (errors == 0 && chip.errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

endmodule
