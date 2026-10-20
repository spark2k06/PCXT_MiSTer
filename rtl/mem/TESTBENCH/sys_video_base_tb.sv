//
// The same machine and the same program as sys_video_tb, built from the F1
// sources (video memory in BRAM, no video fetch engines). It exists to compare
// CPU time: the program runs the same instructions on both, so any difference
// in the time it needs is the time the video memory path costs or saves.
//
// Not part of run_tests.sh: it compiles against a checkout of the F1 commit.
//
`timescale 1ns / 1ps

module sys_video_base_tb #(
    parameter int SPEED  = 0,
    parameter int LIMIT_US = 150000
);
    import sdram_pkg::*;

    localparam real TCK  = 8.730;
    localparam real LEAD = 2.0;
    localparam real TCO  = 3.0;

    logic clk_chip = 1'b0, clk100 = 1'b0;
    always #10.0 clk_chip = ~clk_chip;
    always #5.0  clk100   = ~clk100;

    logic clk = 1'b0, clk57 = 1'b0, clk28 = 1'b0, sdram_clk = 1'b0;
    int   clk_k = 0;
    initial begin
        #3.3;
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

    logic reset_sdram = 1'b1, sd_reset = 1'b1;
    wire  sd_init_done;
    logic [1:0] init_sync = 2'b00;
    logic [7:0] cpu_rst_cnt = 8'd0;
    logic reset_cpu = 1'b1;
    always @(posedge clk_chip) begin
        init_sync   <= {init_sync[0], sd_init_done};
        reset_sdram <= !(init_sync[1]);
        if (!init_sync[1]) begin reset_cpu <= 1'b1; cpu_rst_cnt <= 8'd0; end
        else if (cpu_rst_cnt != 8'd60) cpu_rst_cnt <= cpu_rst_cnt + 8'd1;
        else reset_cpu <= 1'b0;
    end
    logic [3:0] sdr_cnt = 4'd0;
    always @(posedge clk) begin
        if (sdr_cnt != 4'd10) sdr_cnt <= sdr_cnt + 4'd1;
        else sd_reset <= 1'b0;
    end

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

    wire        mem_start, mem_we, mem_busy, mem_done;
    wire [23:0] mem_addr;  wire [1:0] mem_len;  wire [63:0] mem_wdata, mem_rdata;  wire [7:0] mem_wbe;

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
        .clk_uart(1'b0), .uart2_rx(1'b1), .uart2_cts_n(1'b1), .uart2_dcd_n(1'b1), .uart2_dsr_n(1'b1),
        .clk_midi(1'b0), .midi_rx(1'b1),
        .mem_start(mem_start), .mem_we(mem_we), .mem_addr(mem_addr), .mem_len(mem_len),
        .mem_wdata(mem_wdata), .mem_wbe(mem_wbe), .mem_busy(mem_busy), .mem_done(mem_done),
        .mem_rdata(mem_rdata), .mem_flush(1'b0), .ec00_loaded(1'b1),
        .ems_enabled(1'b0), .ems_address(2'b00), .bios_protect_flag(2'b11),
        .use_mmc(2'b00), .spi_miso(1'b0),
        .mgmt_address(16'd0), .mgmt_read(1'b0), .mgmt_write(1'b0), .mgmt_writedata(16'd0),
        .floppy_wp(2'b00), .enable_a000h(1'b1),
        .wait_count_clk_en(cpu_ce_negedge),
        .ram_read_wait_cycle(ram_read_wait_cycle), .ram_write_wait_cycle(ram_write_wait_cycle),
        .cga_hw(1'b1), .cga_scandouble_en(1'b0), .hercules_hw(1'b1),
        .crt_h_offset(4'd0), .crt_v_offset(3'd0), .vsync_width_osd(3'd0), .hsync_width_osd(3'd0),
        .cga_frame_stack_rebuild(1'b0)
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
        .is8086(1'b0), .fake286_flags(1'b0),
        .word_read_request(word_read_request), .word_write_request(word_write_request),
        .data_bus_word_out(cpu_data_bus_word), .data_bus_word(data_bus_word),
        .word_access_possible(word_read_possible)
    );

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

    wire        op_valid, op_ref, op_we, op_issue;
    wire [23:0] op_addr;  wire [1:0] op_len;  wire [63:0] op_wdata;  wire [7:0] op_wbe;
    wire [1:0]  op_tag;
    wire        rd_valid, rd_last;  wire [15:0] rd_data;  wire [1:0] rd_tag;
    wire [3:0]  bank_idle;

    sdram_arbiter arb (
        .clk(clk), .reset(sd_reset), .init_done(sd_init_done),
        .vid_req(1'b0), .vid_addr(24'd0), .vid_len(LEN_1), .vid_deadline(16'd0),
        .vid_ack(), .vid_rvalid(), .vid_rlast(),
        .cpu_req(sd_cpu_req), .cpu_we(sd_cpu_we), .cpu_addr(sd_cpu_addr), .cpu_len(sd_cpu_len),
        .cpu_wdata(sd_cpu_wdata), .cpu_wbe(sd_cpu_wbe),
        .cpu_ack(sd_cpu_ack), .cpu_rvalid(sd_cpu_rvalid), .cpu_rlast(sd_cpu_rlast),
        .ldr_req(1'b0), .ldr_we(1'b1), .ldr_addr(24'd0), .ldr_len(LEN_1),
        .ldr_wdata(64'd0), .ldr_wbe(8'h03), .ldr_high(1'b0),
        .ldr_ack(), .ldr_rvalid(), .ldr_rlast(),
        .aux_req(1'b0), .aux_addr(24'd0), .aux_len(LEN_2),
        .aux_ack(), .aux_rvalid(), .aux_rlast(),
        .rdata(sd_rdata),
        .op_valid(op_valid), .op_ref(op_ref), .op_we(op_we), .op_addr(op_addr),
        .op_len(op_len), .op_wdata(op_wdata), .op_wbe(op_wbe), .op_tag(op_tag),
        .op_issue(op_issue), .bank_idle(bank_idle), .rd_valid(rd_valid), .rd_data(rd_data),
        .rd_tag(rd_tag), .rd_last(rd_last),
        .cpu_lat_max(), .vid_lat_max(), .vid_underruns(), .ref_debt()
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

    logic [15:0] rom_img [0:32767];
    initial begin
        logic [15:0] w;
        longint t0;
        for (int i = 0; i < 32768; i++) rom_img[i] = 16'bx;
        $readmemh("sys_video_prog.hex", rom_img);
        for (int i = 0; i < 32768; i++)
            if (rom_img[i] !== 16'bx) chip.poke((PHYS_ROM_BANK >> 1) + i, rom_img[i]);
        wait (sd_init_done);
        wait (!reset_cpu);
        t0 = $time;
        begin
            int waited = 0;
            while (waited < LIMIT_US) begin
                #1000;
                waited++;
                if (waited % 5 == 0 && chip.peek(32'h0000_0301) == 16'hBEEF) break;
            end
        end
        w = chip.peek(32'h0000_0301);
        if (w != 16'hBEEF) $display("the program did not finish");
        else $display("program finished after %0d us of CPU time", ($time - t0) / 1000);
        w = chip.peek(32'h0000_0300);
        $display("read-back errors reported by the program: %0d", w);
        $display("RESULT: %s", (w == 0 && chip.errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
