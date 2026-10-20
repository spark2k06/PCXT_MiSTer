//
// EGA/VGA video memory in SDRAM: the replacement for
// ega_vram_bram_frontend. The ports towards the CPU, the register copy and the
// video-side fetch ports keep their meaning; what is new is that the planes
// and the packed 13h framebuffer are not in this module but in the SDRAM:
//
//   plane p, address a (16 bits)   word  PLANE_BASE + 2a + (p >> 1),
//                                  byte lane p & 1
//   packed 13h byte b (16 bits)    word  VGA13_BASE + (b >> 1), lane b & 1
//
// CPU side (clock domain `clock`, the chipset clock)
//   A read is one burst of two words that loads the four latches and answers
//   with the byte the read mode asks for. A write computes the four bytes from
//   the latches (no read-modify-write of the memory: the latches are what the
//   last read left, as on a real EGA) and goes out as one burst of two with the
//   byte enables of the map mask. It is posted: the CPU is released once the
//   transaction has been handed to the bridge. The write is seen by the video
//   engines when the arbiter captures it (snoop, sdram clock; see vram_fetch).
//
// Video side (clock domain `clk_video`)
//   Nothing here can wait for the memory, so every read is asked for ahead of
//   time and answered at a fixed latency (see vram_fetch). The consumer sees the
//   same shape of interface as the BRAM version, later by a known number of
//   steps:
//     classic EGA graphics   video_read_en / video_addr  -> video_plane*,
//                            video_data_valid, LEAD_GFX dots later
//     classic EGA text       text_fetch_en / text_cell_addr -> text_char/attr/
//                            glyph, text_data_valid, LEAD_CELL + LEAD_GLYPH dots
//                            later. The glyph address depends on the character,
//                            so the frontend chains the second read itself.
//     private VGA routes     the same video_* ports, but timed in clocks
//     (Mode X, 0Dh, 12h)     (EXTRA_PRIV more than the BRAM version) because
//                            their raster is not driven by the CRTC and asks for
//                            data on every clock
//     packed 13h             fb_read_en / fb_addr -> fb_pixel, fb_data_valid,
//                            EXTRA_FB clocks more than the BRAM version
//   The consumers (ega_top and its renderers) are built with the matching
//   delays, and the display side of ega_top is retimed by the same amount so
//   the picture only moves as a whole.
//
// Request sequencing. Within one engine the answers come back in request order
// and are taken in the same order. Text needs two engines because the glyph
// reads are due later than the next cell read; with one stream a glyph could
// stand in front of a cell that is due earlier. Each is a vram_fetch (F2)
// behind a vram_fetch_x clock crossing; both
// reach the arbiter's single VID port through vid_mux.
//
module ega_vram_sdram_frontend #(
    parameter logic [23:0] PLANE_BASE = 24'h400000,  // word address of plane byte 0 (byte 0x080_0000)
    parameter logic [23:0] VGA13_BASE = 24'h420000,  // word address of packed byte 0 (byte 0x084_0000)
    parameter int LEAD_GFX    = 16,    // dots, graphics request -> answer
    parameter int LEAD_CELL   = 9,     // dots, text cell request -> answer
    parameter int LEAD_GLYPH  = 10,    // dots, glyph request -> answer
    parameter int EXTRA_PRIV  = 16,    // clocks added to the BRAM latency of the private routes
    parameter int EXTRA_FB    = 16,    // clocks added to the BRAM latency of packed 13h
    parameter int DOT_SDRAM   = 7,     // sdram clocks in the shortest dot, for deadlines
    parameter int MAIN_DEPTH  = 4,     // entries of the main engine (>= requests in flight + 1)
    parameter int SYNC        = 2
) (
    // ---------------- CPU side
    input  logic         clock,
    input  logic         reset_cpu,

    input  logic [15:0]  cpu_addr,
    input  logic         cpu_a16,
    input  logic [7:0]   cpu_din,
    input  logic         cpu_read,
    input  logic         cpu_write,
    output logic [7:0]   cpu_dout,
    output logic         cpu_ready,

    // Transaction to sdram_xbridge (clock domain), through the shared CPU port
    output logic         m_start,
    output logic         m_we,
    output logic [23:0]  m_addr,
    output logic [1:0]   m_len,
    output logic [63:0]  m_wdata,
    output logic [7:0]   m_wbe,
    input  logic         m_busy,
    input  logic         m_done,
    input  logic [63:0]  m_rdata,


    // ---------------- Video side
    input  logic         clk_video,
    input  logic         reset_video,
    input  logic         dot_tick,          // ega_top ce_pix
    input  logic         priv_route,        // a private VGA route owns the fetch port

    input  logic [15:0]  video_addr,
    input  logic         video_read_en,
    output logic [7:0]   video_plane0,
    output logic [7:0]   video_plane1,
    output logic [7:0]   video_plane2,
    output logic [7:0]   video_plane3,
    output logic         video_data_valid,

    input  logic [15:0]  text_cell_addr,
    input  logic [4:0]   text_scanline,
    input  logic         text_tag,          // travels with the cell (cursor)
    input  logic         text_fetch_en,
    input  logic [1:0]   char_map_a,
    input  logic [1:0]   char_map_b,
    output logic [7:0]   text_char,
    output logic [7:0]   text_attr,
    output logic [7:0]   text_glyph,
    output logic         text_tag_out,
    output logic         text_data_valid,

    input  logic [15:0]  fb_addr,
    input  logic         fb_read_en,
    output logic [7:0]   fb_pixel,
    output logic         fb_data_valid,

    // ---------------- Register copy, as in the BRAM frontend
    input  logic         cfg_toggle,
    input  logic [3:0]   plane_write_mask,
    input  logic         odd_even_mode,
    input  logic         cpu_access_en,     // unused, kept for the same port list
    input  logic         chain2_write,
    input  logic         chain2_read,
    input  logic         extended_memory,
    input  logic [1:0]   mem_map_sel,
    input  logic         page_select,
    input  logic [1:0]   write_mode,
    input  logic [1:0]   read_mode,
    input  logic [1:0]   read_plane_sel,
    input  logic [7:0]   color_compare,
    input  logic [7:0]   color_dont_care,
    input  logic [7:0]   bit_mask,
    input  logic [7:0]   set_reset,
    input  logic [3:0]   enable_set_reset,
    input  logic [1:0]   rop_select,
    input  logic [2:0]   rotate_count,

    // ---------------- Arbiter VID port (sdram_clk domain)
    input  logic         sdram_clk,
    input  logic         sdram_reset,
    output logic         vid_req,
    output logic [23:0]  vid_addr,
    output logic [1:0]   vid_len,
    output logic [15:0]  vid_deadline,
    input  logic         vid_ack,
    input  logic         vid_rvalid,
    input  logic         vid_rlast,
    input  logic [15:0]  vid_rdata,

    // Writes captured by the arbiter (CPU or LDR port), in the sdram_clk domain
    input  logic         snoop_valid,
    input  logic [23:0]  snoop_addr,
    input  logic [1:0]   snoop_len,
    input  logic [63:0]  snoop_wdata,
    input  logic [7:0]   snoop_wbe,

    // ---------------- Debug
    output logic [15:0]  underrun_count
);
    import ega_vram_fns_pkg::*;

    localparam logic [1:0] LEN_1 = 2'd0, LEN_2 = 2'd1, LEN_4 = 2'd2;

    // =====================================================================
    // CPU side
    // =====================================================================
    typedef enum logic [2:0] {
        CPU_IDLE, CPU_ISSUE_RD, CPU_WAIT_RD, CPU_ISSUE_WR, CPU_DONE
    } cpu_state_t;
    cpu_state_t cpu_state;

    logic [15:0] cpu_addr_l;
    logic        cpu_a16_l;
    logic [7:0]  cpu_din_l;
    logic        cpu_is_write;

    logic        cfg_toggle_sync1, cfg_toggle_sync2, cfg_toggle_prev;
    logic [3:0]  plane_write_mask_sync1, plane_write_mask_sync2, cfg_plane_write_mask;
    logic        odd_even_mode_sync1, odd_even_mode_sync2, cfg_odd_even_mode;
    logic        chain2_write_sync1, chain2_write_sync2, cfg_chain2_write;
    logic        chain2_read_sync1, chain2_read_sync2, cfg_chain2_read;
    logic        extended_memory_sync1, extended_memory_sync2, cfg_extended_memory;
    logic [1:0]  mem_map_sel_sync1, mem_map_sel_sync2, cfg_mem_map_sel;
    logic        page_select_sync1, page_select_sync2, cfg_page_select;
    logic [1:0]  write_mode_sync1, write_mode_sync2, cfg_write_mode;
    logic [1:0]  read_mode_sync1, read_mode_sync2, cfg_read_mode;
    logic [1:0]  read_plane_sel_sync1, read_plane_sel_sync2, cfg_read_plane_sel;
    logic [7:0]  color_compare_sync1, color_compare_sync2, cfg_color_compare;
    logic [7:0]  color_dont_care_sync1, color_dont_care_sync2, cfg_color_dont_care;
    logic [7:0]  bit_mask_sync1, bit_mask_sync2, cfg_bit_mask;
    logic [7:0]  set_reset_sync1, set_reset_sync2, cfg_set_reset;
    logic [3:0]  enable_set_reset_sync1, enable_set_reset_sync2, cfg_enable_set_reset;
    logic [1:0]  rop_select_sync1, rop_select_sync2, cfg_rop_select;
    logic [2:0]  rotate_count_sync1, rotate_count_sync2, cfg_rotate_count;

    logic [7:0] latch0, latch1, latch2, latch3;      // the four EGA latches

    wire [15:0] cpu_a_remap = remap_cpu_addr(cpu_addr_l, cpu_a16_l, cfg_odd_even_mode,
                                             cfg_extended_memory, cfg_mem_map_sel,
                                             cfg_page_select, 1'b0);
    wire [1:0]  eff_read_plane = cfg_chain2_read ? {cfg_read_plane_sel[1], cpu_addr_l[0]}
                                                 : cfg_read_plane_sel;
    wire [3:0]  eff_write_mask = cfg_chain2_write
                               ? (cfg_plane_write_mask & (4'b0101 << cpu_addr_l[0]))
                               : cfg_plane_write_mask;

    wire        wmode1 = (cfg_write_mode == 2'b01);
    wire [7:0]  new0 = wmode1 ? latch0 : compute_write_byte(latch0, cpu_din_l, cfg_set_reset[0],
                           cfg_enable_set_reset[0], cpu_din_l[0], cfg_bit_mask, cfg_rop_select,
                           cfg_write_mode, cfg_rotate_count);
    wire [7:0]  new1 = wmode1 ? latch1 : compute_write_byte(latch1, cpu_din_l, cfg_set_reset[1],
                           cfg_enable_set_reset[1], cpu_din_l[1], cfg_bit_mask, cfg_rop_select,
                           cfg_write_mode, cfg_rotate_count);
    wire [7:0]  new2 = wmode1 ? latch2 : compute_write_byte(latch2, cpu_din_l, cfg_set_reset[2],
                           cfg_enable_set_reset[2], cpu_din_l[2], cfg_bit_mask, cfg_rop_select,
                           cfg_write_mode, cfg_rotate_count);
    wire [7:0]  new3 = wmode1 ? latch3 : compute_write_byte(latch3, cpu_din_l, cfg_set_reset[3],
                           cfg_enable_set_reset[3], cpu_din_l[3], cfg_bit_mask, cfg_rop_select,
                           cfg_write_mode, cfg_rotate_count);

    // The two words of the burst at plane address a
    wire [23:0] cpu_word0 = PLANE_BASE + {7'd0, cpu_a_remap, 1'b0};

    assign m_start = ((cpu_state == CPU_ISSUE_RD) || (cpu_state == CPU_ISSUE_WR)) & ~m_busy;
    assign m_we    = (cpu_state == CPU_ISSUE_WR);
    assign m_addr  = cpu_word0;
    assign m_len   = LEN_2;
    assign m_wdata = {32'd0, new3, new2, new1, new0};
    assign m_wbe   = {4'd0, eff_write_mask[3], eff_write_mask[2], eff_write_mask[1], eff_write_mask[0]};
    assign cpu_ready = (cpu_state == CPU_DONE);

    always_ff @(posedge clock or posedge reset_cpu) begin
        if (reset_cpu) begin
            cpu_state <= CPU_IDLE;
            cpu_addr_l <= 16'h0000;
            cpu_a16_l <= 1'b0;
            cpu_din_l <= 8'h00;
            cpu_is_write <= 1'b0;
            cpu_dout <= 8'h00;
            latch0 <= 8'h00; latch1 <= 8'h00; latch2 <= 8'h00; latch3 <= 8'h00;

            cfg_toggle_sync1 <= 1'b0;
            cfg_toggle_sync2 <= 1'b0;
            cfg_toggle_prev <= 1'b0;
            plane_write_mask_sync1 <= 4'h0;
            plane_write_mask_sync2 <= 4'h0;
            cfg_plane_write_mask <= 4'h0;
            odd_even_mode_sync1 <= 1'b0;
            odd_even_mode_sync2 <= 1'b0;
            cfg_odd_even_mode <= 1'b0;
            chain2_write_sync1 <= 1'b0;
            chain2_write_sync2 <= 1'b0;
            cfg_chain2_write <= 1'b0;
            chain2_read_sync1 <= 1'b0;
            chain2_read_sync2 <= 1'b0;
            cfg_chain2_read <= 1'b0;
            extended_memory_sync1 <= 1'b0;
            extended_memory_sync2 <= 1'b0;
            cfg_extended_memory <= 1'b0;
            mem_map_sel_sync1 <= 2'b00;
            mem_map_sel_sync2 <= 2'b00;
            cfg_mem_map_sel <= 2'b00;
            page_select_sync1 <= 1'b0;
            page_select_sync2 <= 1'b0;
            cfg_page_select <= 1'b0;
            write_mode_sync1 <= 2'b00;
            write_mode_sync2 <= 2'b00;
            cfg_write_mode <= 2'b00;
            read_mode_sync1 <= 2'b00;
            read_mode_sync2 <= 2'b00;
            cfg_read_mode <= 2'b00;
            read_plane_sel_sync1 <= 2'b00;
            read_plane_sel_sync2 <= 2'b00;
            cfg_read_plane_sel <= 2'b00;
            color_compare_sync1 <= 8'h00;
            color_compare_sync2 <= 8'h00;
            cfg_color_compare <= 8'h00;
            color_dont_care_sync1 <= 8'h0F;
            color_dont_care_sync2 <= 8'h0F;
            cfg_color_dont_care <= 8'h0F;
            bit_mask_sync1 <= 8'hFF;
            bit_mask_sync2 <= 8'hFF;
            cfg_bit_mask <= 8'hFF;
            set_reset_sync1 <= 8'h00;
            set_reset_sync2 <= 8'h00;
            cfg_set_reset <= 8'h00;
            enable_set_reset_sync1 <= 4'h0;
            enable_set_reset_sync2 <= 4'h0;
            cfg_enable_set_reset <= 4'h0;
            rop_select_sync1 <= 2'b00;
            rop_select_sync2 <= 2'b00;
            cfg_rop_select <= 2'b00;
            rotate_count_sync1 <= 3'b000;
            rotate_count_sync2 <= 3'b000;
            cfg_rotate_count <= 3'b000;
        end else begin
            cfg_toggle_sync1 <= cfg_toggle;
            cfg_toggle_sync2 <= cfg_toggle_sync1;
            plane_write_mask_sync1 <= plane_write_mask;
            plane_write_mask_sync2 <= plane_write_mask_sync1;
            odd_even_mode_sync1 <= odd_even_mode;
            odd_even_mode_sync2 <= odd_even_mode_sync1;
            chain2_write_sync1 <= chain2_write;
            chain2_write_sync2 <= chain2_write_sync1;
            chain2_read_sync1 <= chain2_read;
            chain2_read_sync2 <= chain2_read_sync1;
            extended_memory_sync1 <= extended_memory;
            extended_memory_sync2 <= extended_memory_sync1;
            mem_map_sel_sync1 <= mem_map_sel;
            mem_map_sel_sync2 <= mem_map_sel_sync1;
            page_select_sync1 <= page_select;
            page_select_sync2 <= page_select_sync1;
            write_mode_sync1 <= write_mode;
            write_mode_sync2 <= write_mode_sync1;
            read_mode_sync1 <= read_mode;
            read_mode_sync2 <= read_mode_sync1;
            read_plane_sel_sync1 <= read_plane_sel;
            read_plane_sel_sync2 <= read_plane_sel_sync1;
            color_compare_sync1 <= color_compare;
            color_compare_sync2 <= color_compare_sync1;
            color_dont_care_sync1 <= color_dont_care;
            color_dont_care_sync2 <= color_dont_care_sync1;
            bit_mask_sync1 <= bit_mask;
            bit_mask_sync2 <= bit_mask_sync1;
            set_reset_sync1 <= set_reset;
            set_reset_sync2 <= set_reset_sync1;
            enable_set_reset_sync1 <= enable_set_reset;
            enable_set_reset_sync2 <= enable_set_reset_sync1;
            rop_select_sync1 <= rop_select;
            rop_select_sync2 <= rop_select_sync1;
            rotate_count_sync1 <= rotate_count;
            rotate_count_sync2 <= rotate_count_sync1;

            if (cfg_toggle_sync2 != cfg_toggle_prev) begin
                cfg_toggle_prev <= cfg_toggle_sync2;
                cfg_plane_write_mask <= plane_write_mask_sync2;
                cfg_odd_even_mode <= odd_even_mode_sync2;
                cfg_chain2_write <= chain2_write_sync2;
                cfg_chain2_read <= chain2_read_sync2;
                cfg_extended_memory <= extended_memory_sync2;
                cfg_mem_map_sel <= mem_map_sel_sync2;
                cfg_page_select <= page_select_sync2;
                cfg_write_mode <= write_mode_sync2;
                cfg_read_mode <= read_mode_sync2;
                cfg_read_plane_sel <= read_plane_sel_sync2;
                cfg_color_compare <= color_compare_sync2;
                cfg_color_dont_care <= color_dont_care_sync2;
                cfg_bit_mask <= bit_mask_sync2;
                cfg_set_reset <= set_reset_sync2;
                cfg_enable_set_reset <= enable_set_reset_sync2;
                cfg_rop_select <= rop_select_sync2;
                cfg_rotate_count <= rotate_count_sync2;
            end

            case (cpu_state)
                CPU_IDLE: begin
                    if (cpu_read || cpu_write) begin
                        cpu_addr_l   <= cpu_addr;
                        cpu_a16_l    <= cpu_a16;
                        cpu_din_l    <= cpu_din;
                        cpu_is_write <= cpu_write;
                        cpu_state    <= cpu_write ? CPU_ISSUE_WR : CPU_ISSUE_RD;
                    end
                end

                CPU_ISSUE_RD: if (!m_busy) cpu_state <= CPU_WAIT_RD;

                CPU_WAIT_RD: begin
                    if (m_done) begin
                        // The latches take the whole burst; the answer is the
                        // byte read mode 0 or 1 asks for.
                        latch0 <= m_rdata[7:0];
                        latch1 <= m_rdata[15:8];
                        latch2 <= m_rdata[23:16];
                        latch3 <= m_rdata[31:24];
                        if (cfg_read_mode == 2'b01)
                            cpu_dout <= read_mode1_byte(m_rdata[7:0], m_rdata[15:8], m_rdata[23:16],
                                                        m_rdata[31:24], cfg_color_compare,
                                                        cfg_color_dont_care);
                        else
                            case (eff_read_plane)
                                2'b00:   cpu_dout <= m_rdata[7:0];
                                2'b01:   cpu_dout <= m_rdata[15:8];
                                2'b10:   cpu_dout <= m_rdata[23:16];
                                default: cpu_dout <= m_rdata[31:24];
                            endcase
                        cpu_state <= CPU_DONE;
                    end
                end

                CPU_ISSUE_WR: if (!m_busy) cpu_state <= CPU_DONE;

                CPU_DONE: begin
                    if (~cpu_read && ~cpu_write) cpu_state <= CPU_IDLE;
                end

                default: cpu_state <= CPU_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Video side: two engines and the arbiter port
    // =====================================================================
    logic        mf_rq_valid, gf_rq_valid;
    logic [23:0] mf_rq_addr, gf_rq_addr;
    logic [1:0]  mf_rq_len;
    logic [15:0] mf_rq_dl, gf_rq_dl;
    logic        mf_pop, gf_pop;
    logic        mode_flush;

    wire         mf_hd_valid, gf_hd_valid;
    wire  [63:0] mf_hd_data, gf_hd_data;
    wire         mf_c_req, gf_c_req;
    wire  [23:0] mf_c_addr, gf_c_addr;
    wire  [1:0]  mf_c_len, gf_c_len;
    wire  [15:0] mf_c_dl, gf_c_dl;
    wire         mf_c_ack, gf_c_ack, mf_c_rv, gf_c_rv, mf_c_rl, gf_c_rl;
    wire  [15:0] mf_ur, gf_ur;
    wire  [3:0]  mf_occ, gf_occ;

    // Cells, graphics, private routes and 13h: one request in flight per
    // character or block, at most one per video clock.
    vram_fetch_x #(.DEPTH(MAIN_DEPTH), .MAX_WORDS(2), .SYNC_STAGES(SYNC)) u_fetch_main (
        .clk_v(clk_video), .reset_v(reset_video),
        .rq_valid(mf_rq_valid), .rq_addr(mf_rq_addr), .rq_len(mf_rq_len), .rq_deadline(mf_rq_dl),
        .pop(mf_pop), .flush(mode_flush), .hd_valid(mf_hd_valid), .hd_data(mf_hd_data),
        .clk_s(sdram_clk), .reset_s(sdram_reset),
        .snoop_valid(snoop_valid), .snoop_addr(snoop_addr), .snoop_len(snoop_len),
        .snoop_wdata(snoop_wdata), .snoop_wbe(snoop_wbe),
        .vid_req(mf_c_req), .vid_addr(mf_c_addr), .vid_len(mf_c_len), .vid_deadline(mf_c_dl),
        .vid_ack(mf_c_ack), .vid_rvalid(mf_c_rv), .vid_rlast(mf_c_rl), .vid_rdata(vid_rdata),
        .underrun_count(mf_ur), .occupancy(mf_occ)
    );

    // Glyph rows of text
    vram_fetch_x #(.DEPTH(4), .MAX_WORDS(1), .SYNC_STAGES(SYNC)) u_fetch_glyph (
        .clk_v(clk_video), .reset_v(reset_video),
        .rq_valid(gf_rq_valid), .rq_addr(gf_rq_addr), .rq_len(LEN_1), .rq_deadline(gf_rq_dl),
        .pop(gf_pop), .flush(mode_flush), .hd_valid(gf_hd_valid), .hd_data(gf_hd_data),
        .clk_s(sdram_clk), .reset_s(sdram_reset),
        .snoop_valid(snoop_valid), .snoop_addr(snoop_addr), .snoop_len(snoop_len),
        .snoop_wdata(snoop_wdata), .snoop_wbe(snoop_wbe),
        .vid_req(gf_c_req), .vid_addr(gf_c_addr), .vid_len(gf_c_len), .vid_deadline(gf_c_dl),
        .vid_ack(gf_c_ack), .vid_rvalid(gf_c_rv), .vid_rlast(gf_c_rl), .vid_rdata(vid_rdata),
        .underrun_count(gf_ur), .occupancy(gf_occ)
    );

    vid_mux #(.N(2)) u_vid_mux (
        .clk(sdram_clk), .reset(sdram_reset),
        .c_req({gf_c_req, mf_c_req}),
        .c_addr({gf_c_addr, mf_c_addr}),
        .c_len({gf_c_len, mf_c_len}),
        .c_deadline({gf_c_dl, mf_c_dl}),
        .c_ack({gf_c_ack, mf_c_ack}),
        .c_rvalid({gf_c_rv, mf_c_rv}),
        .c_rlast({gf_c_rl, mf_c_rl}),
        .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
        .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast)
    );

    // Underruns as the display side sees them: a pop with no complete answer in
    // the mirror. (The engines count too, in the sdram clock domain, but a late
    // answer can slip in between the video side's look and the pop reaching the
    // engine, which would not be counted there.)
    logic [15:0] ur_main_v, ur_glyph_v;
    assign underrun_count = ur_main_v + ur_glyph_v;
    always_ff @(posedge clk_video) begin
        if (reset_video) begin
            ur_main_v  <= 16'd0;
            ur_glyph_v <= 16'd0;
        end
        else begin
            if (mf_pop & ~mf_hd_valid & (ur_main_v  != 16'hFFFF)) ur_main_v  <= ur_main_v  + 16'd1;
            if (gf_pop & ~gf_hd_valid & (ur_glyph_v != 16'hFFFF)) ur_glyph_v <= ur_glyph_v + 16'd1;
        end
    end

    // ---------------------------------------------------------------------
    // What kind of fetch is going on; a change flushes everything in flight
    // ---------------------------------------------------------------------
    typedef enum logic [2:0] {K_NONE, K_GFX, K_TEXT, K_PRIV, K_FB} kind_t;
    kind_t kind;
    wire   want_gfx  = video_read_en & ~priv_route;
    wire   want_priv = video_read_en &  priv_route;
    wire   want_text = text_fetch_en;
    wire   want_fb   = fb_read_en;
    kind_t want_kind;
    always_comb begin
        want_kind = K_NONE;
        if      (want_fb)   want_kind = K_FB;
        else if (want_priv) want_kind = K_PRIV;
        else if (want_text) want_kind = K_TEXT;
        else if (want_gfx)  want_kind = K_GFX;
    end
    assign mode_flush = (want_kind != K_NONE) && (kind != K_NONE) && (want_kind != kind);
    always_ff @(posedge clk_video) begin
        if (reset_video) kind <= K_NONE;
        else if (want_kind != K_NONE) kind <= want_kind;
    end

    // ---------------------------------------------------------------------
    // Request to the main engine
    // ---------------------------------------------------------------------
    logic [15:0] priv_last_addr;
    logic        priv_last_valid;
    logic [13:0] fb_last_blk;
    logic        fb_last_valid;

    wire priv_new   = want_priv & (~priv_last_valid | (video_addr != priv_last_addr));
    wire fb_blk_new = want_fb & (~fb_last_valid | (fb_addr[15:2] != fb_last_blk));

    always_comb begin
        mf_rq_valid = 1'b0;
        mf_rq_addr  = 24'd0;
        mf_rq_len   = LEN_2;
        mf_rq_dl    = 16'd0;
        if (want_fb) begin
            mf_rq_valid = fb_blk_new;
            mf_rq_addr  = VGA13_BASE + {9'd0, fb_addr[15:2], 1'b0};
            mf_rq_len   = LEN_2;
            mf_rq_dl    = 16'(EXTRA_FB * 4);
        end
        else if (want_priv) begin
            mf_rq_valid = priv_new;
            mf_rq_addr  = PLANE_BASE + {7'd0, video_addr, 1'b0};
            mf_rq_len   = LEN_2;
            mf_rq_dl    = 16'(EXTRA_PRIV * 4);
        end
        else if (want_text) begin
            mf_rq_valid = 1'b1;
            mf_rq_addr  = PLANE_BASE + {7'd0, text_cell_addr, 1'b0};
            mf_rq_len   = LEN_1;
            mf_rq_dl    = 16'(LEAD_CELL * DOT_SDRAM);
        end
        else if (want_gfx) begin
            mf_rq_valid = 1'b1;
            mf_rq_addr  = PLANE_BASE + {7'd0, video_addr, 1'b0};
            mf_rq_len   = LEN_2;
            mf_rq_dl    = 16'(LEAD_GFX * DOT_SDRAM);
        end
    end

    always_ff @(posedge clk_video) begin
        if (reset_video) begin
            priv_last_valid <= 1'b0;
            fb_last_valid   <= 1'b0;
        end
        else begin
            if (want_priv) begin priv_last_addr <= video_addr; priv_last_valid <= 1'b1; end
            else if (~video_read_en) priv_last_valid <= 1'b0;
            if (want_fb) begin fb_last_blk <= fb_addr[15:2]; fb_last_valid <= 1'b1; end
            else if (~fb_read_en) fb_last_valid <= 1'b0;
        end
    end

    // ---------------------------------------------------------------------
    // Token lines. Payloads:
    //   gfx   none
    //   cell  {scanline(5), tag}
    //   glyph {tag, attr(8), char(8)}
    //   priv  {ren, new}
    //   fb    {ren, new, 0, byte offset(2)}   (one token per read, not per block)
    // ---------------------------------------------------------------------
    logic gfx_exit;
    pc_token_delay #(.N(LEAD_GFX), .PW(1), .ANCHOR(0)) u_tok_gfx (
        .clk(clk_video), .reset(reset_video), .clear(mode_flush), .adv(dot_tick),
        .tok_in(want_kind == K_GFX), .pay_in(1'b0),
        .exit_now(gfx_exit), .exit_pay());

    logic        cell_exit;
    logic [5:0]  cell_pay;
    pc_token_delay #(.N(LEAD_CELL), .PW(6), .ANCHOR(1)) u_tok_cell (
        .clk(clk_video), .reset(reset_video), .clear(mode_flush), .adv(dot_tick),
        .tok_in(want_kind == K_TEXT), .pay_in({text_scanline, text_tag}),
        .exit_now(cell_exit), .exit_pay(cell_pay));

    // The cell answer gives character and attribute; the glyph read follows
    wire [7:0]  cell_char = mf_hd_data[7:0];
    wire [7:0]  cell_attr = mf_hd_data[15:8];
    wire [1:0]  font_bank = cell_attr[3] ? char_map_b : char_map_a;
    wire [15:0] font_addr = {font_bank, 14'b0} + {3'b000, cell_char, 5'b00000} + {11'd0, cell_pay[5:1]};
    wire        glyph_go  = cell_exit;

    always_comb begin
        gf_rq_valid = glyph_go;
        gf_rq_addr  = PLANE_BASE + {7'd0, font_addr, 1'b1};     // plane 2 is in word 1
        gf_rq_dl    = 16'(LEAD_GLYPH * DOT_SDRAM);
    end

    logic        glyph_exit;
    logic [16:0] glyph_pay;
    pc_token_delay #(.N(LEAD_GLYPH), .PW(17), .ANCHOR(2)) u_tok_glyph (
        .clk(clk_video), .reset(reset_video), .clear(mode_flush), .adv(dot_tick),
        .tok_in(glyph_go), .pay_in({cell_pay[0], cell_attr, cell_char}),
        .exit_now(glyph_exit), .exit_pay(glyph_pay));

    logic        priv_exit;
    logic [1:0]  priv_pay;
    pc_token_delay #(.N(EXTRA_PRIV), .PW(2), .ANCHOR(2)) u_tok_priv (
        .clk(clk_video), .reset(reset_video), .clear(mode_flush), .adv(1'b1),
        .tok_in(want_priv), .pay_in({1'b1, priv_new}),
        .exit_now(priv_exit), .exit_pay(priv_pay));

    logic        fb_exit;
    logic [4:0]  fb_pay;
    pc_token_delay #(.N(EXTRA_FB), .PW(5), .ANCHOR(2)) u_tok_fb (
        .clk(clk_video), .reset(reset_video), .clear(mode_flush), .adv(1'b1),
        .tok_in(want_fb), .pay_in({1'b1, fb_blk_new, 1'b0, fb_addr[1:0]}),
        .exit_now(fb_exit), .exit_pay(fb_pay));

    // ---------------------------------------------------------------------
    // Pops and outputs
    // ---------------------------------------------------------------------
    wire gfx_pop   = gfx_exit;
    wire cell_pop  = cell_exit;
    wire priv_pop  = priv_exit & priv_pay[0];
    wire fb_pop    = fb_exit & fb_pay[3];
    assign mf_pop = gfx_pop | cell_pop | priv_pop | fb_pop;
    assign gf_pop = glyph_exit;

    logic [31:0] gfx_planes;
    logic        gfx_valid_q;
    logic [31:0] priv_planes;
    logic        priv_valid_q, priv_valid_q2;
    logic [31:0] fb_blk;
    logic        fb_valid_q;
    logic [7:0]  fb_byte;

    always_ff @(posedge clk_video) begin
        if (reset_video) begin
            gfx_valid_q   <= 1'b0;
            priv_valid_q  <= 1'b0;
            priv_valid_q2 <= 1'b0;
            fb_valid_q    <= 1'b0;
            gfx_planes    <= 32'd0;
            priv_planes   <= 32'd0;
            fb_blk        <= 32'd0;
            fb_byte       <= 8'd0;
        end
        else begin
            // An underrun leaves the previous data in place; the engine counts it.
            gfx_valid_q <= gfx_exit;
            if (gfx_pop & mf_hd_valid) gfx_planes <= mf_hd_data[31:0];

            if (priv_pop & mf_hd_valid) priv_planes <= mf_hd_data[31:0];
            priv_valid_q  <= priv_exit & priv_pay[1];
            priv_valid_q2 <= priv_valid_q;

            if (fb_pop & mf_hd_valid) fb_blk <= mf_hd_data[31:0];
            fb_valid_q <= fb_exit & fb_pay[4];
            if (fb_exit & fb_pay[4]) begin
                fb_byte <= ((fb_pay[3] & mf_hd_valid) ? mf_hd_data[31:0] : fb_blk) >> (8 * fb_pay[1:0]);
            end
        end
    end

    assign video_plane0 = priv_route ? priv_planes[7:0]   : gfx_planes[7:0];
    assign video_plane1 = priv_route ? priv_planes[15:8]  : gfx_planes[15:8];
    assign video_plane2 = priv_route ? priv_planes[23:16] : gfx_planes[23:16];
    assign video_plane3 = priv_route ? priv_planes[31:24] : gfx_planes[31:24];
    assign video_data_valid = priv_route ? priv_valid_q2 : gfx_valid_q;
    assign fb_pixel      = fb_byte;
    assign fb_data_valid = fb_valid_q;

    // Text: coincident with the step, like the cell/glyph pair of the BRAM version
    assign text_data_valid = glyph_exit;
    assign text_char       = glyph_pay[7:0];
    assign text_attr       = glyph_pay[15:8];
    assign text_tag_out    = glyph_pay[16];
    assign text_glyph      = gf_hd_data[7:0];     // plane 2: the low byte of word 1

endmodule
