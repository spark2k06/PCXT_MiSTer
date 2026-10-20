//
// A whole machine around the video memory: the 8088 (MCL86) and the real CHIPSET
// (bus, READY, CGA bus wait, mem_map, cpu_mem_port, the CGA and the HGC) on the
// 50 MHz clock, the SDRAM path (bridge, arbiter, ram_clear, vram_fetch engines
// and adapters) on 114.545 MHz, with the SDRAM model as the chip.
//
// sys_video_prog.asm runs from the BIOS slot and writes and reads back CGA and
// HGC memory (text fill, the 16 KiB mirror, HGC page 1 dual write, writes
// followed at once by reads) while both cards scan it. Checked:
//   - the program finishes and reports no read-back errors;
//   - the video bytes it wrote are in the chip, in every place they go;
//   - every write the CPU made is in the chip, as in the reference;
//   - at every sampling event of each card, the byte the adapter gives the card
//     is the byte an ideal memory would give.
//
// SPEED is clk_select: 0 4.77, 1 7.16, 2 9.54, 3 Max.
//
`timescale 1ns / 1ps

module sys_video_tb #(
    parameter int SPEED  = 0,
    parameter int IS8086 = 0,
    parameter int LIMIT_US = 150000
);
    import sdram_pkg::*;

    localparam real TCK  = 8.730;
    localparam real LEAD = 2.0;
    localparam real TCO  = 3.0;

    // ------------------------------------------------------------------
    // Clocks: 50/100 MHz (chipset), 114.545 / 57.27 / 28.636 MHz (one family)
    // ------------------------------------------------------------------
    logic clk_chip = 1'b0, clk100 = 1'b0;
    always #10.0 clk_chip = ~clk_chip;
    always #5.0  clk100   = ~clk100;

    logic clk = 1'b0, clk57 = 1'b0, clk28 = 1'b0, sdram_clk = 1'b0;
    int   clk_k = 0;
    initial begin
        #3.3;                                   // not aligned with the chipset clock
        // one PLL family: the rising edges of clk57 and clk28 coincide with
        // rising edges of clk
        fork
            forever begin
                #(TCK / 2.0);
                clk   <= (clk_k % 2) == 0;
                clk57 <= (clk_k % 4) <  2;
                clk28 <= (clk_k % 8) <  4;
                clk_k <= clk_k + 1;
            end
        join_none
    end
    initial begin
        #(3.3 + TCK - LEAD);
        forever #(TCK / 2.0) sdram_clk = ~sdram_clk;
    end

    // ------------------------------------------------------------------
    // Resets
    // ------------------------------------------------------------------
    logic reset_sdram = 1'b1;               // chipset side, held at the start
    logic sd_reset_f = 1'b1;
    wire  sd_reset = sd_reset_f;
    wire  sd_init_done;
    logic [1:0] init_sync = 2'b00;
    always @(posedge clk_chip) init_sync <= {init_sync[0], sd_init_done};
    wire clr_busy;
    logic [1:0] clr_busy_s = 2'b11, clr_seen_s = 2'b00;
    logic       clr_seen = 1'b0;
    logic [7:0] cpu_rst_cnt = 8'd0;
    logic reset_cpu = 1'b1;
    always @(posedge clk_chip) begin
        reset_sdram <= !(init_sync[1]);
        // the CPU waits for the chip and for the video memory to be cleared
        if (!init_sync[1] || clr_busy_s[1] || !clr_seen_s[1]) begin
            reset_cpu   <= 1'b1;
            cpu_rst_cnt <= 8'd0;
        end
        else if (cpu_rst_cnt != 8'd60) begin
            cpu_rst_cnt <= cpu_rst_cnt + 8'd1;
        end
        else reset_cpu <= 1'b0;
    end
    always @(posedge clk) if (clr_busy) clr_seen <= 1'b1;
    always @(posedge clk_chip) begin
        clr_busy_s <= {clr_busy_s[0], clr_busy};
        clr_seen_s <= {clr_seen_s[0], clr_seen};
    end

    logic [3:0] sdr_cnt = 4'd0;
    always @(posedge clk) begin
        if (sdr_cnt != 4'd10) sdr_cnt <= sdr_cnt + 4'd1;
        else sd_reset_f <= 1'b0;
    end

    // ------------------------------------------------------------------
    // CPU and chipset
    // ------------------------------------------------------------------
    wire        cpu_ce_posedge, cpu_ce_negedge, peripheral_ce, clk_cpu;
    wire        cycle_accrate, shift_read_timing, biu_done;
    wire [7:0]  clock_cycle_counter_division_ratio, clock_cycle_counter_decrement_value;
    wire [1:0]  ram_read_wait_cycle, ram_write_wait_cycle;
    logic [1:0] clk_select = 2'b00;
    wire  [1:0] clk_select_next = 2'(SPEED);

    always @(posedge clk_chip, posedge reset_cpu)
        if (reset_cpu) clk_select <= 2'b00;
        else if (biu_done) clk_select <= clk_select_next;

    XT_CE_Generator u_ce (
        .clock(clk_chip), .reset(reset_cpu),
        .clk_select_load(biu_done), .clk_select(clk_select_next),
        .cpu_clk_pin(clk_cpu), .cpu_ce_posedge(cpu_ce_posedge), .cpu_ce_negedge(cpu_ce_negedge),
        .peripheral_ce(peripheral_ce), .cycle_accrate(cycle_accrate),
        .clock_cycle_counter_division_ratio(clock_cycle_counter_division_ratio),
        .clock_cycle_counter_decrement_value(clock_cycle_counter_decrement_value),
        .shift_read_timing(shift_read_timing),
        .ram_read_wait_cycle(ram_read_wait_cycle), .ram_write_wait_cycle(ram_write_wait_cycle)
    );

    wire [19:0] cpu_ad_out;
    logic [19:0] cpu_address = 20'd0;
    wire [7:0]  cpu_data_bus, data_bus;
    wire [15:0] data_bus_word, cpu_data_bus_word;
    wire        word_read_possible, word_read_request, word_write_request;
    wire        processor_ready, interrupt_to_cpu, address_latch_enable, address_direction, lock_n;
    wire [2:0]  processor_status;
    wire [3:0]  dma_acknowledge_n;
    wire [2:0]  SEGMENT;
    wire        s6_3_mux;

    always @(posedge clk_chip) if (address_latch_enable) cpu_address <= cpu_ad_out;

    // memory port <-> bridge
    wire        mem_start, mem_we, mem_busy, mem_done;
    wire [23:0] mem_addr;  wire [1:0] mem_len;  wire [63:0] mem_wdata, mem_rdata;  wire [7:0] mem_wbe;

    // video fetch
    wire [4:0]  fx_cga_phase, fx_hgc_phase;
    wire        fx_cga_hres, fx_hgc_grph, fx_hgc_page;
    wire [13:0] fx_cga_cur_word, fx_cga_next_word, fx_hgc_cur_word, fx_hgc_next_word;
    wire [7:0]  fx_cga_vram_d, fx_hgc_vram_d;

    CHIPSET #(.clk_rate(28'd50000000), .ROM_TANDY(1'b0)) u_chipset (
        .clock(clk_chip), .cpu_ce_posedge(cpu_ce_posedge), .cpu_ce_negedge(cpu_ce_negedge),
        .clk_sys(clk_chip), .peripheral_ce(peripheral_ce), .clk_select(clk_select),
        .reset(reset_cpu), .sdram_reset(reset_sdram),
        .cpu_address(cpu_address), .cpu_data_bus(cpu_data_bus), .processor_status(processor_status),
        .processor_lock_n(lock_n), .processor_ready(processor_ready), .interrupt_to_cpu(interrupt_to_cpu),
        .splashscreen(1'b0), .composite(1'b0), .video_reset(1'b0), .video_output(1'b0),
        .clk_vga_cga(clk28), .enable_cga(1'b1), .clk_vga_hgc(clk57), .enable_hgc(1'b1), .hgc_rgb(2'b10),
        .address_ext(20'hFFFFF), .ext_access_request(1'b0),
        .address_direction(address_direction), .data_bus(data_bus),
        .word_read_request(word_read_request), .word_write_request(word_write_request),
        .data_bus_word_in(cpu_data_bus_word), .data_bus_word(data_bus_word),
        .word_read_possible(word_read_possible), .data_bus_ext(8'hFF),
        .address_latch_enable(address_latch_enable),
        .io_channel_check(1'b0), .io_channel_ready(1'b1), .interrupt_request(8'd0),
        .io_read_n_ext(1'b1), .io_write_n_ext(1'b1), .memory_read_n_ext(1'b1), .memory_write_n_ext(1'b1),
        .dma_request(4'd0), .dma_acknowledge_n(dma_acknowledge_n),
        .port_b_in(8'd0), .port_c_in(8'h00),
        .ps2_clock(1'b1), .ps2_data(1'b1), .ps2_mouseclk_in(1'b1), .ps2_mousedat_in(1'b1),
        .joy_opts(5'd0), .joy0(14'd0), .joy1(14'd0), .joya0(16'd0), .joya1(16'd0),
        .opl2_io(2'b11), .cms_en(1'b0), .tandy_video(1'b0),
        // The CGA family only: no EGA card, no Sound Blaster, Tandy sound and MPU-401 as before
        .ega_active(1'b0), .sb_en(1'b0), .sb_irq7(1'b0), .tandy_en(1'b1), .mpu401_enabled(1'b1),
        .umb_enabled(1'b0), .vga_mode13_osd(1'b0), .vga_mode13_native(1'b0), .ega_monitor_profile(2'b00),
        .sdram_clk(1'b0), .vid_ack(1'b0), .vid_rvalid(1'b0), .vid_rlast(1'b0), .vid_rdata(16'd0),
        .snoop_valid(1'b0), .snoop_addr(24'd0), .snoop_len(2'd0), .snoop_wdata(64'd0), .snoop_wbe(8'd0),
        .xtegactl_status_effective(40'd0), .xtegactl_status_osd_match(18'd0),
        .id_video_card(2'd1), .id_vga13_active(1'b0),
        .clk_uart(1'b0), .uart2_rx(1'b1), .uart2_cts_n(1'b1), .uart2_dcd_n(1'b1), .uart2_dsr_n(1'b1),
        .clk_midi(1'b0), .midi_rx(1'b1),
        .mem_start(mem_start), .mem_we(mem_we), .mem_addr(mem_addr), .mem_len(mem_len),
        .mem_wdata(mem_wdata), .mem_wbe(mem_wbe), .mem_busy(mem_busy), .mem_done(mem_done),
        .mem_rdata(mem_rdata), .mem_flush(1'b0), .ec00_loaded(1'b1),
        .ems_enabled(1'b0), .ems_address(2'b00), .bios_protect_flag(3'b011),
        .use_mmc(2'b00), .spi_miso(1'b0),
        .mgmt_address(16'd0), .mgmt_read(1'b0), .mgmt_write(1'b0), .mgmt_writedata(16'd0),
        .floppy_wp(2'b00), .enable_a000h(1'b1),
        .wait_count_clk_en(cpu_ce_negedge),
        .ram_read_wait_cycle(ram_read_wait_cycle), .ram_write_wait_cycle(ram_write_wait_cycle),
        .cga_hw(1'b1), .cga_scandouble_en(1'b0), .hercules_hw(1'b1),
        .crt_h_offset(4'd0), .crt_v_offset(3'd0), .vsync_width_osd(3'd0), .hsync_width_osd(3'd0),
        .cga_frame_stack_rebuild(1'b0),
        .fx_cga_vram_d(fx_cga_vram_d), .fx_cga_phase(fx_cga_phase), .fx_cga_hres(fx_cga_hres),
        .fx_cga_cur_word(fx_cga_cur_word), .fx_cga_next_word(fx_cga_next_word),
        .fx_hgc_vram_d(fx_hgc_vram_d), .fx_hgc_phase(fx_hgc_phase), .fx_hgc_grph(fx_hgc_grph),
        .fx_hgc_page(fx_hgc_page), .fx_hgc_cur_word(fx_hgc_cur_word), .fx_hgc_next_word(fx_hgc_next_word)
    );

    i8088 cpu (
        .CORE_CLK(clk100), .CLK(clk_cpu), .RESET(reset_cpu), .READY(processor_ready),
        .NMI(1'b0), .INTR(interrupt_to_cpu),
        .ad_out(cpu_ad_out), .dout(cpu_data_bus), .din(data_bus),
        .lock_n(lock_n), .s6_3_mux(s6_3_mux), .s2_s0_out(processor_status), .SEGMENT(SEGMENT),
        .biu_done(biu_done), .cycle_accrate(cycle_accrate),
        .clock_cycle_counter_division_ratio(clock_cycle_counter_division_ratio),
        .clock_cycle_counter_decrement_value(clock_cycle_counter_decrement_value),
        .shift_read_timing(shift_read_timing),
        .is8086(IS8086 != 0), .fake286_flags(1'b0),
        .word_read_request(word_read_request), .word_write_request(word_write_request),
        .data_bus_word_out(cpu_data_bus_word), .data_bus_word(data_bus_word),
        .word_access_possible(word_read_possible)
    );

    // ------------------------------------------------------------------
    // SDRAM path (as in PCXT.sv)
    // ------------------------------------------------------------------
    wire        sd_cpu_req, sd_cpu_we, sd_cpu_ack, sd_cpu_rvalid, sd_cpu_rlast;
    wire [23:0] sd_cpu_addr;  wire [1:0] sd_cpu_len;  wire [63:0] sd_cpu_wdata;  wire [7:0] sd_cpu_wbe;
    wire [15:0] sd_rdata;

    sdram_xbridge #(.SYNC_STAGES(2)) u_cpu_bridge (
        .clk_a(clk_chip), .reset_a(reset_sdram),
        .a_start(mem_start), .a_we(mem_we), .a_addr(mem_addr), .a_len(mem_len),
        .a_wdata(mem_wdata), .a_wbe(mem_wbe), .a_busy(mem_busy), .a_done(mem_done), .a_rdata(mem_rdata),
        .clk_s(clk), .reset_s(sd_reset),
        .s_req(sd_cpu_req), .s_we(sd_cpu_we), .s_addr(sd_cpu_addr), .s_len(sd_cpu_len),
        .s_wdata(sd_cpu_wdata), .s_wbe(sd_cpu_wbe), .s_ack(sd_cpu_ack),
        .s_rvalid(sd_cpu_rvalid), .s_rdata(sd_rdata), .s_rlast(sd_cpu_rlast)
    );

    localparam logic [23:0] CGA_WORD_BASE = PHYS_CGA[24:1];
    localparam logic [23:0] HGC_WORD_BASE = PHYS_HGC[24:1];

    wire        clr_req, clr_ack, arb_ldr_ack;
    wire [23:0] clr_addr;  wire [1:0] clr_len;  wire [63:0] clr_wdata;  wire [7:0] clr_wbe;

    ram_clear #(
        .NREG(2),
        .BASES({HGC_WORD_BASE, CGA_WORD_BASE}),
        .WORDS({24'd32768, 24'd16384})
    ) u_ram_clear (
        .clk(clk), .reset(sd_reset), .init_done(sd_init_done), .clear(1'b0),
        .busy(clr_busy), .req(clr_req), .addr(clr_addr), .len(clr_len), .wdata(clr_wdata), .wbe(clr_wbe),
        .ack(clr_ack)
    );
    assign clr_ack = arb_ldr_ack;

    logic        sn_valid = 1'b0;
    logic [23:0] sn_addr = 0;  logic [1:0] sn_len = 0;
    logic [63:0] sn_wdata = 0; logic [7:0] sn_wbe = 0;
    always_ff @(posedge clk) begin
        sn_valid <= (sd_cpu_ack & sd_cpu_we) | arb_ldr_ack;
        sn_addr  <= arb_ldr_ack ? clr_addr  : sd_cpu_addr;
        sn_len   <= arb_ldr_ack ? clr_len   : sd_cpu_len;
        sn_wdata <= arb_ldr_ack ? clr_wdata : sd_cpu_wdata;
        sn_wbe   <= arb_ldr_ack ? clr_wbe   : sd_cpu_wbe;
    end

    wire vid_reset = sd_reset | ~sd_init_done;

    wire        cga_req_v, cga_req_r, cga_rsp_p, cga_rsp_v, cga_rsp_pop;
    wire [23:0] cga_req_a, cga_rsp_a;  wire [1:0] cga_req_l;  wire [15:0] cga_req_d;  wire [63:0] cga_rsp_d;
    wire        cga_vreq, cga_vack, cga_vrv, cga_vrl;
    wire [23:0] cga_vaddr;  wire [1:0] cga_vlen;  wire [15:0] cga_vdl;
    wire [15:0] cga_underrun, cga_mismatch, cga_late, cga_dropped;
    wire        cga_ev_req, cga_ev_chr, cga_ev_att;  wire [23:0] cga_cur_addr, cga_next_addr;

    wire        hgc_req_v, hgc_req_r, hgc_rsp_p, hgc_rsp_v, hgc_rsp_pop;
    wire [23:0] hgc_req_a, hgc_rsp_a;  wire [1:0] hgc_req_l;  wire [15:0] hgc_req_d;  wire [63:0] hgc_rsp_d;
    wire        hgc_vreq, hgc_vack, hgc_vrv, hgc_vrl;
    wire [23:0] hgc_vaddr;  wire [1:0] hgc_vlen;  wire [15:0] hgc_vdl;
    wire [15:0] hgc_underrun, hgc_mismatch, hgc_late, hgc_dropped;
    wire        hgc_ev_req, hgc_ev_chr, hgc_ev_att;  wire [23:0] hgc_cur_addr, hgc_next_addr;

    wire        vid_req, vid_ack, vid_rvalid, vid_rlast;
    wire [23:0] vid_addr;  wire [1:0] vid_len;  wire [15:0] vid_deadline;

    vram_fetch #(.DEPTH(3), .MAX_WORDS(1)) u_cga_fetch (
        .clk(clk), .reset(vid_reset),
        .req_valid(cga_req_v), .req_addr(cga_req_a), .req_len(cga_req_l), .req_deadline(cga_req_d), .req_ready(cga_req_r),
        .rsp_pending(cga_rsp_p), .rsp_valid(cga_rsp_v), .rsp_data(cga_rsp_d), .rsp_addr(cga_rsp_a), .rsp_len(),
        .rsp_pop(cga_rsp_pop), .flush(1'b0),
        .snoop_valid(sn_valid), .snoop_addr(sn_addr), .snoop_len(sn_len), .snoop_wdata(sn_wdata), .snoop_wbe(sn_wbe),
        .vid_req(cga_vreq), .vid_addr(cga_vaddr), .vid_len(cga_vlen), .vid_deadline(cga_vdl),
        .vid_ack(cga_vack), .vid_rvalid(cga_vrv), .vid_rlast(cga_vrl), .vid_rdata(sd_rdata),
        .underrun_count(cga_underrun), .occupancy()
    );
    cga_vram_if #(.BASE(CGA_WORD_BASE)) u_cga_vif (
        .clk(clk), .reset(vid_reset),
        .seq_phase(fx_cga_phase), .hres(fx_cga_hres), .cur_word(fx_cga_cur_word), .next_word(fx_cga_next_word),
        .vram_d(fx_cga_vram_d),
        .req_valid(cga_req_v), .req_addr(cga_req_a), .req_len(cga_req_l), .req_deadline(cga_req_d), .req_ready(cga_req_r),
        .rsp_pending(cga_rsp_p), .rsp_valid(cga_rsp_v), .rsp_data(cga_rsp_d), .rsp_addr(cga_rsp_a), .rsp_pop(cga_rsp_pop),
        .mismatch_count(cga_mismatch), .late_count(cga_late), .dropped_count(cga_dropped),
        .dbg_ev_req(cga_ev_req), .dbg_ev_chr(cga_ev_chr), .dbg_ev_att(cga_ev_att),
        .dbg_cur_addr(cga_cur_addr), .dbg_next_addr(cga_next_addr)
    );

    vram_fetch #(.DEPTH(3), .MAX_WORDS(1)) u_hgc_fetch (
        .clk(clk), .reset(vid_reset),
        .req_valid(hgc_req_v), .req_addr(hgc_req_a), .req_len(hgc_req_l), .req_deadline(hgc_req_d), .req_ready(hgc_req_r),
        .rsp_pending(hgc_rsp_p), .rsp_valid(hgc_rsp_v), .rsp_data(hgc_rsp_d), .rsp_addr(hgc_rsp_a), .rsp_len(),
        .rsp_pop(hgc_rsp_pop), .flush(1'b0),
        .snoop_valid(sn_valid), .snoop_addr(sn_addr), .snoop_len(sn_len), .snoop_wdata(sn_wdata), .snoop_wbe(sn_wbe),
        .vid_req(hgc_vreq), .vid_addr(hgc_vaddr), .vid_len(hgc_vlen), .vid_deadline(hgc_vdl),
        .vid_ack(hgc_vack), .vid_rvalid(hgc_vrv), .vid_rlast(hgc_vrl), .vid_rdata(sd_rdata),
        .underrun_count(hgc_underrun), .occupancy()
    );
    hgc_vram_if #(.BASE(HGC_WORD_BASE)) u_hgc_vif (
        .clk(clk), .reset(vid_reset),
        .seq_phase(fx_hgc_phase), .grph(fx_hgc_grph), .page(fx_hgc_page),
        .cur_word(fx_hgc_cur_word), .next_word(fx_hgc_next_word),
        .vram_d(fx_hgc_vram_d),
        .req_valid(hgc_req_v), .req_addr(hgc_req_a), .req_len(hgc_req_l), .req_deadline(hgc_req_d), .req_ready(hgc_req_r),
        .rsp_pending(hgc_rsp_p), .rsp_valid(hgc_rsp_v), .rsp_data(hgc_rsp_d), .rsp_addr(hgc_rsp_a), .rsp_pop(hgc_rsp_pop),
        .mismatch_count(hgc_mismatch), .late_count(hgc_late), .dropped_count(hgc_dropped),
        .dbg_ev_req(hgc_ev_req), .dbg_ev_chr(hgc_ev_chr), .dbg_ev_att(hgc_ev_att),
        .dbg_cur_addr(hgc_cur_addr), .dbg_next_addr(hgc_next_addr)
    );

    vid_mux #(.N(2)) u_vid_mux (
        .clk(clk), .reset(vid_reset),
        .c_req({hgc_vreq, cga_vreq}), .c_addr({hgc_vaddr, cga_vaddr}),
        .c_len({hgc_vlen, cga_vlen}), .c_deadline({hgc_vdl, cga_vdl}),
        .c_ack({hgc_vack, cga_vack}), .c_rvalid({hgc_vrv, cga_vrv}), .c_rlast({hgc_vrl, cga_vrl}),
        .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
        .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast)
    );

    wire        op_valid, op_ref, op_we, op_issue;
    wire [23:0] op_addr;  wire [1:0] op_len;  wire [63:0] op_wdata;  wire [7:0] op_wbe;
    wire [1:0]  op_tag;
    wire        rd_valid, rd_last;  wire [15:0] rd_data;  wire [1:0] rd_tag;
    wire [15:0] cpu_lat_max, vid_lat_max, vid_underruns;
    wire [3:0]  ref_debt, bank_idle;
    wire        ldr_rvalid, ldr_rlast, aux_ack, aux_rvalid, aux_rlast;

    sdram_arbiter arb (
        .clk(clk), .reset(sd_reset), .init_done(sd_init_done),
        .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
        .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast),
        .cpu_req(sd_cpu_req), .cpu_we(sd_cpu_we), .cpu_addr(sd_cpu_addr), .cpu_len(sd_cpu_len),
        .cpu_wdata(sd_cpu_wdata), .cpu_wbe(sd_cpu_wbe),
        .cpu_ack(sd_cpu_ack), .cpu_rvalid(sd_cpu_rvalid), .cpu_rlast(sd_cpu_rlast),
        .ldr_req(clr_req), .ldr_we(1'b1), .ldr_addr(clr_addr), .ldr_len(clr_len),
        .ldr_wdata(clr_wdata), .ldr_wbe(clr_wbe), .ldr_high(1'b0),
        .ldr_ack(arb_ldr_ack), .ldr_rvalid(ldr_rvalid), .ldr_rlast(ldr_rlast),
        .aux_req(1'b0), .aux_addr(24'd0), .aux_len(LEN_2),
        .aux_ack(aux_ack), .aux_rvalid(aux_rvalid), .aux_rlast(aux_rlast),
        .rdata(sd_rdata),
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
        .clk(clk), .reset(sd_reset), .init_done(sd_init_done),
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

    // ------------------------------------------------------------------
    // Checks
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

    logic [7:0]  cga_ref_d = 8'hFF, hgc_ref_d = 8'hFF;
    logic [15:0] rw_c, rw_h;
    logic        cga_chk = 0, hgc_chk = 0;
    longint      n_cmp = 0, n_bad_cga = 0, n_bad_hgc = 0;
    logic        measuring = 1'b0;
    // The Hercules page is a base address that the adapter applies when it asks
    // for a character, one character ahead: a change of page is seen by the
    // card at once and by the adapter one character later (documented in the
    // F2 report). The first samples after a change are not compared.
    int          hgc_skip = 0;
    logic        hgc_page_q = 1'b0;
    int          page_changes = 0;
    always @(posedge clk) begin
        hgc_page_q <= fx_hgc_page;
        if (fx_hgc_page != hgc_page_q) begin hgc_skip <= 200; page_changes++; end
        else if (hgc_skip > 0) hgc_skip <= hgc_skip - 1;
    end

    always @(posedge clk) begin
        if (cga_chk && measuring) begin
            n_cmp++;
            if (fx_cga_vram_d !== cga_ref_d) begin
                n_bad_cga++;
                if (n_bad_cga <= 5) $display("%0.3f CGA data differs: %02h, ideal %02h (word %06h)", $realtime, fx_cga_vram_d, cga_ref_d, cga_cur_addr);
            end
        end
        if (hgc_chk && measuring && hgc_skip == 0) begin
            n_cmp++;
            if (fx_hgc_vram_d !== hgc_ref_d) begin
                n_bad_hgc++;
                if (n_bad_hgc <= 5) $display("%0.3f HGC data differs: %02h, ideal %02h (word %06h)", $realtime, fx_hgc_vram_d, hgc_ref_d, hgc_cur_addr);
            end
        end
        cga_chk <= cga_ev_chr | cga_ev_att;
        hgc_chk <= hgc_ev_chr | hgc_ev_att;
        rw_c = rp(cga_cur_addr);
        rw_h = rp(hgc_cur_addr);
        if (cga_ev_chr) cga_ref_d <= rw_c[7:0];
        if (cga_ev_att) cga_ref_d <= rw_c[15:8];
        if (hgc_ev_chr) hgc_ref_d <= rw_h[7:0];
        if (hgc_ev_att) hgc_ref_d <= rw_h[15:8];

        if (rf_v)
            for (int i = 0; i < len_words(rf_len); i++) begin
                int unsigned a = rf_addr + i;
                logic [15:0] o = rp(a);
                ref_mem[a] = {rf_wbe[2*i+1] ? rf_wdata[16*i+8 +: 8] : o[15:8],
                              rf_wbe[2*i]   ? rf_wdata[16*i   +: 8] : o[7:0]};
            end
        rf_v <= sn_valid;  rf_addr <= sn_addr;  rf_len <= sn_len;  rf_wdata <= sn_wdata;  rf_wbe <= sn_wbe;
    end

    // CPU activity on the video windows (the bus as the chipset sees it)
    int vid_wr = 0, vid_rd = 0, wait_cga = 0;
    always @(posedge clk_chip) begin
        if (u_chipset.map_vclass != 2'd0 && u_chipset.map_select) begin
            if (!u_chipset.memory_write_n && u_chipset.memory_access_ready && !reset_cpu) vid_wr++;
            if (!u_chipset.memory_read_n  && u_chipset.memory_access_ready && !reset_cpu) vid_rd++;
        end
    end

    // When does a CPU write become visible to the video side? CGA: from the end
    // of MEMW (the old BRAM took it one chipset clock after, written at the next
    // edge: about 40 ns); HGC: from the start of MEMW (the old BRAM wrote while
    // MEMW was low, the first write landing about 40 ns after it fell). Measured
    // here to the clock in which the engines see the snoop.
    real t_cga_rise = 0.0, t_hgc_fall = 0.0;
    logic memw_q = 1'b1;
    real cga_min = 1e9, cga_max = 0.0, cga_sum = 0.0;  int cga_n = 0;
    real hgc_min = 1e9, hgc_max = 0.0, hgc_sum = 0.0;  int hgc_n = 0;
    logic cga_pend = 1'b0, hgc_pend = 1'b0;
    always @(posedge clk_chip) begin
        memw_q <= u_chipset.memory_write_n;
        if (!reset_cpu && u_chipset.map_select) begin
            if (memw_q && !u_chipset.memory_write_n && u_chipset.map_vclass == VC_HGC) begin
                t_hgc_fall = $realtime; hgc_pend = 1'b1;
            end
            if (!memw_q && u_chipset.memory_write_n && u_chipset.map_vclass == VC_CGA) begin
                t_cga_rise = $realtime; cga_pend = 1'b1;
            end
        end
    end
    always @(posedge clk) if (sn_valid && measuring) begin
        real d;
        if (sn_addr >= CGA_WORD_BASE && sn_addr < CGA_WORD_BASE + 24'h4000 && cga_pend) begin
            d = $realtime - t_cga_rise; cga_pend = 1'b0;
            if (d < cga_min) cga_min = d;  if (d > cga_max) cga_max = d;  cga_sum += d;  cga_n++;
        end
        else if (sn_addr >= HGC_WORD_BASE && sn_addr < HGC_WORD_BASE + 24'h8000 && hgc_pend) begin
            d = $realtime - t_hgc_fall; hgc_pend = 1'b0;
            if (d < hgc_min) hgc_min = d;  if (d > hgc_max) hgc_max = d;  hgc_sum += d;  hgc_n++;
        end
    end

    // +trace: every chipset clock for 70 clocks after the first bus cycle at F000:00BB
    int trace_left = 0;
    logic trace_seen = 0;
    always @(posedge clk_chip) if (!reset_cpu && $test$plusargs("trace")) begin
        if (!trace_seen && address_latch_enable && cpu_ad_out == 20'hf00bb) begin trace_seen = 1; trace_left = 70; end
        if (trace_left != 0) begin
            trace_left--;
            $display("TR ce=%b%b st=%0d ale=%b rd_n=%b rdy=%b mar=%b ioc=%b cgar=%b tnd=%b busst=%b pbs=%b aen_n=%b dack0=%b rnw=%b prnw=%b",
                     cpu_ce_posedge, cpu_ce_negedge, processor_status, address_latch_enable, u_chipset.memory_read_n,
                     processor_ready, u_chipset.memory_access_ready, u_chipset.io_channel_ready,
                     u_chipset.cga_memory_ready, u_chipset.tandy_snd_rdy,
                     u_chipset.u_READY.bus_state, u_chipset.u_READY.prev_bus_state,
                     u_chipset.address_enable_n, u_chipset.dma_acknowledge_n[0],
                     u_chipset.u_READY.ready_n_or_wait, u_chipset.u_READY.prev_ready_n_or_wait);
        end
    end

    // Length of every memory strobe in CPU clocks, for the whole run
    int  strobe_len = 0;
    int  strobe_hist [16];
    initial for (int i = 0; i < 16; i++) strobe_hist[i] = 0;
    always @(posedge clk_chip) if (cpu_ce_posedge && !reset_cpu) begin
        if (!u_chipset.memory_read_n || !u_chipset.memory_write_n) strobe_len++;
        else if (strobe_len != 0) begin strobe_hist[strobe_len > 15 ? 15 : strobe_len]++; strobe_len = 0; end
    end

    // Progress, for long runs
    always @(posedge clk_chip) begin
        if (!reset_cpu && ($time % 20000000) < 20) // every 20 ms
            $display("%0.0f us: CPU at %05h, video bus cycles so far: %0d writes, %0d reads",
                     $realtime / 1000.0, cpu_address, vid_wr, vid_rd);
    end

    // ------------------------------------------------------------------
    logic [15:0] rom_img [0:32767];

    // A word of the system RAM. With IDEAL_MEM the memory is the array of
    // cpu_mem_port_ideal.sv instead of the chip.
    function automatic logic [15:0] peek_ram(input int unsigned w);
`ifdef IDEAL_MEM
        peek_ram = {u_chipset.u_cpu_mem_port.rd(25'(2 * w + 1)), u_chipset.u_cpu_mem_port.rd(25'(2 * w))};
`else
        peek_ram = chip.peek(w);
`endif
    endfunction
    string       hexfile = "sys_video_prog.hex";

    initial begin
        logic [15:0] w;
        longint t0;
        // BIOS image into the ROM bank behind the controller's back
        for (int i = 0; i < 32768; i++) rom_img[i] = 16'bx;
        void'($value$plusargs("hex=%s", hexfile));
        $readmemh(hexfile, rom_img);
        for (int i = 0; i < 32768; i++)
            if (rom_img[i] !== 16'bx) chip.poke((PHYS_ROM_BANK >> 1) + i, rom_img[i]);

        wait (sd_init_done);
        wait (!reset_cpu);
        t0 = $time;
        repeat (3000) @(posedge clk_chip);
        measuring = 1'b1;

        // wait for the marker or give up
        begin
            int waited = 0;
            while (waited < LIMIT_US) begin
                #1000;                      // 1 us
                waited++;
                if (waited % 5 == 0) begin
                    w = peek_ram(32'h0000_0301);
                    if (w == 16'hBEEF) break;
                end
            end
            w = peek_ram(32'h0000_0301);
            if (w != 16'hBEEF) err("the program did not finish");
            else $display("program finished after %0d us of CPU time", ($time - t0) / 1000);
        end
        repeat (4000) @(posedge clk_chip);
        measuring = 1'b0;

        if (hexfile != "sys_video_prog.hex") begin
            // sys_mph_prog: the 8088 MPH start-up sequence, timed without and with the refresh DMA
            logic [15:0] t_off = peek_ram(32'h0000_0304), t_on = peek_ram(32'h0000_0305);
            $display("MPH sequence: %0d ticks with the refresh masked, %0d with it running (%0d CPU clocks, %0d with refresh)",
                     t_off, t_on, 4 * t_off, 4 * t_on);
            $write("memory strobe lengths in CPU clocks:");
            for (int i = 1; i < 16; i++) if (strobe_hist[i] != 0) $write(" %0d:%0d", i, strobe_hist[i]);
            $display("");
            $display("RESULT: %s", (errors == 0 && chip.errors == 0) ? "PASS" : "FAIL");
            $finish;
        end
        w = peek_ram(32'h0000_0300);
        $display("read-back errors reported by the program: %0d", w);
        if (w != 16'd0) err("the program found read-back errors");

        // The bytes the program wrote in the video memory
        w = chip.peek(CGA_WORD_BASE + 24'h80);        if (w !== 16'h3CC3) err($sformatf("CGA 0100: %04h", w));
        w = chip.peek(HGC_WORD_BASE + 24'h4080);      if (w !== 16'h3CC3) err($sformatf("HGC page 1 8100: %04h", w));
        w = chip.peek(CGA_WORD_BASE + 24'h8);         if (w[7:0] !== 8'h5A) err($sformatf("CGA mirror 0010: %04h", w));

        // Everything the CPU wrote is in the chip
        begin
            int bad = 0, n = 0;
            foreach (ref_mem[k]) begin
                logic [15:0] c = chip.peek(k);
                n++;
                if (c !== ref_mem[k]) begin
                    bad++;
                    if (bad <= 10) err($sformatf("chip word %06h is %04h, expected %04h", k, c, ref_mem[k]));
                end
            end
            $display("chip content: %0d words checked, %0d wrong", n, bad);
        end

        $display("video bus cycles: %0d writes, %0d reads", vid_wr, vid_rd);
        if (cga_n > 0) $display("CGA write visible to the engines %0.0f..%0.0f ns (mean %0.0f) after MEMW rises (%0d writes)", cga_min, cga_max, cga_sum / cga_n, cga_n);
        if (hgc_n > 0) $display("HGC write visible to the engines %0.0f..%0.0f ns (mean %0.0f) after MEMW falls (%0d writes)", hgc_min, hgc_max, hgc_sum / hgc_n, hgc_n);
        $display("cards vs ideal memory: %0d samples, %0d differences on the CGA, %0d on the HGC (%0d page changes)",
                 n_cmp, n_bad_cga, n_bad_hgc, page_changes);
        $display("adapters: CGA %0d address mismatches, %0d late, %0d dropped, %0d engine underruns; HGC %0d, %0d, %0d, %0d",
                 cga_mismatch, cga_late, cga_dropped, cga_underrun, hgc_mismatch, hgc_late, hgc_dropped, hgc_underrun);
        $display("arbiter: CPU latency max %0d, VID latency from urgency max %0d, VID underruns %0d",
                 cpu_lat_max, vid_lat_max, vid_underruns);
        if (n_bad_cga != 0 || n_bad_hgc != 0) err("video data differs from the ideal memory");
        if (n_cmp < 1000) err("too few samples");
        $display("RESULT: %s", (errors == 0 && chip.errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

endmodule
