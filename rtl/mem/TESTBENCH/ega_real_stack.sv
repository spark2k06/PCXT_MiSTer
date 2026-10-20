//
// The real memory stack behind the EGA frontend, for ega_sdram_equiv_tb
// (-DPORT_MODEL=ega_real_stack): the same ports as pc_port_model, but
//
//   frontend m_* -> sdram_txn_mux -> sdram_xbridge -> sdram_arbiter -> sdram_ctrl -> chip model
//   frontend vid_* ----------------------------------^
//
// and a second master on the CPU port, standing in for cpu_mem_port: random
// reads and writes of 1, 2 and 4 words in bank 0, close to back to back (the
// bus of an 8088 at Max). The writes the arbiter captures are announced on the
// snoop port as in PCXT.sv. Verilator only (the chip model).
//
// Reports at the end: worst CPU and VID latency of the arbiter, video
// underruns, protocol errors of the chip model. Errors of the chip
// model fail the bench through chip_errors.
//
`timescale 1ns / 1ps

module ega_real_stack #(
    parameter [23:0] MEM_BASE    = 24'h400000,
    parameter int    MEM_WORDS   = 262144,
    parameter int    CPU_GAP_MIN = 3,           // chipset clocks between two CPU transactions
    parameter int    CPU_GAP_MAX = 9,
    parameter int    CPU_LAT_MIN = 0,           // unused: kept for the pc_port_model parameter list
    parameter int    CPU_LAT_MAX = 0,
    parameter int    VID_ACK_MAX = 0,
    parameter int    VID_LAT_MIN = 0,
    parameter int    VID_LAT_MAX = 0,
    parameter int    VID_QUEUE   = 0
) (
    input  logic         reset,

    // CPU port of the EGA frontend (chipset clock)
    input  logic         clock,
    input  logic         m_start,
    input  logic         m_we,
    input  logic [23:0]  m_addr,
    input  logic [1:0]   m_len,
    input  logic [63:0]  m_wdata,
    input  logic [7:0]   m_wbe,
    output logic         m_busy,
    output logic         m_done,
    output logic [63:0]  m_rdata,

    // VID port (sdram clock)
    input  logic         sclk,
    input  logic         vid_req,
    input  logic [23:0]  vid_addr,
    input  logic [1:0]   vid_len,
    input  logic [15:0]  vid_deadline,
    output logic         vid_ack,
    output logic         vid_rvalid,
    output logic         vid_rlast,
    output logic [15:0]  vid_rdata,

    output logic         snoop_valid,
    output logic [23:0]  snoop_addr,
    output logic [1:0]   snoop_len,
    output logic [63:0]  snoop_wdata,
    output logic [7:0]   snoop_wbe,

    output int           vid_max_lat,
    output int           chip_errors,
    output int           vid_underruns_out
);
    import sdram_pkg::*;

    localparam real TCK  = 8.730;
    localparam real LEAD = 2.0;
    localparam real TCO  = 3.0;

    // ------------------------------------------------------------------
    // Resets as PCXT.sv makes them
    // ------------------------------------------------------------------
    logic sd_reset_q = 1'b1;
    always_ff @(posedge sclk or posedge reset)
        if (reset) sd_reset_q <= 1'b1;
        else       sd_reset_q <= 1'b0;
    wire sd_reset = sd_reset_q;

    logic reset_c = 1'b1;
    always_ff @(posedge clock or posedge reset)
        if (reset) reset_c <= 1'b1;
        else       reset_c <= 1'b0;

    // ------------------------------------------------------------------
    // A master standing in for cpu_mem_port, and the mux
    // ------------------------------------------------------------------
    logic        g_start = 1'b0, g_we = 1'b0;
    logic [23:0] g_addr = 24'd0;
    logic [1:0]  g_len = 2'd0;
    logic [63:0] g_wdata = 64'd0;
    logic [7:0]  g_wbe = 8'd0;
    wire         g_done, f_done;
    wire         b_start, b_we, b_busy, b_done;
    wire [23:0]  b_addr;  wire [1:0] b_len;  wire [63:0] b_wdata, b_rdata;  wire [7:0] b_wbe;
    int          g_gap = 0;
    logic        g_wait = 1'b0;
    int          g_ops = 0;
    logic        init_s2 = 1'b0;      // init_done of the controller, in the chipset clock domain

    always @(posedge clock) begin
        if (reset_c || !init_s2) begin      // idle until the chip is initialised, so the
            g_start <= 1'b0; g_wait <= 1'b0; g_gap <= 20;      // latencies are not the init wait
        end
        else if (g_start) begin
            if (b_start && !b_busy && !m_start) begin g_start <= 1'b0; g_wait <= 1'b1; end
        end
        else if (g_wait) begin
            if (g_done) begin g_wait <= 1'b0; g_gap <= $urandom_range(CPU_GAP_MAX, CPU_GAP_MIN); g_ops++; end
        end
        else if (g_gap > 0) g_gap <= g_gap - 1;
        else if (!m_start && !m_busy_f) begin
            logic we;
            we = ($urandom_range(0, 9) < 3);
            g_start <= 1'b1;
            g_we    <= we;
            g_len   <= we ? 2'd0 : (($urandom_range(0, 9) < 5) ? 2'd0 : ($urandom_range(0, 1) ? 2'd1 : 2'd2));
            g_addr  <= {2'd0, 13'($urandom_range(64, 127)), 9'($urandom_range(0, 508))};
            g_wdata <= {$urandom, $urandom};
            g_wbe   <= 8'($urandom_range(1, 3));
        end
    end
    wire m_busy_f = b_busy;

    sdram_txn_mux u_mux (
        .clock(clock), .reset(reset_c),
        .a0_start(g_start), .a0_we(g_we), .a0_addr(g_addr), .a0_len(g_len),
        .a0_wdata(g_wdata), .a0_wbe(g_wbe), .a0_done(g_done),
        .a1_start(m_start), .a1_we(m_we), .a1_addr(m_addr), .a1_len(m_len),
        .a1_wdata(m_wdata), .a1_wbe(m_wbe), .a1_done(f_done),
        .m_start(b_start), .m_we(b_we), .m_addr(b_addr), .m_len(b_len),
        .m_wdata(b_wdata), .m_wbe(b_wbe), .m_busy(b_busy), .m_done(b_done)
    );

    assign m_busy  = b_busy;
    assign m_done  = f_done;
    assign m_rdata = b_rdata;

    // ------------------------------------------------------------------
    // Bridge, arbiter, controller, chip
    // ------------------------------------------------------------------
    wire        sd_cpu_req, sd_cpu_we, sd_cpu_ack, sd_cpu_rvalid, sd_cpu_rlast;
    wire [23:0] sd_cpu_addr;  wire [1:0] sd_cpu_len;  wire [63:0] sd_cpu_wdata;  wire [7:0] sd_cpu_wbe;
    wire [15:0] sd_rdata;

    sdram_xbridge #(.SYNC_STAGES(2)) u_bridge (
        .clk_a(clock), .reset_a(reset_c),
        .a_start(b_start), .a_we(b_we), .a_addr(b_addr), .a_len(b_len), .a_wdata(b_wdata), .a_wbe(b_wbe),
        .a_busy(b_busy), .a_done(b_done), .a_rdata(b_rdata),
        .clk_s(sclk), .reset_s(sd_reset),
        .s_req(sd_cpu_req), .s_we(sd_cpu_we), .s_addr(sd_cpu_addr), .s_len(sd_cpu_len),
        .s_wdata(sd_cpu_wdata), .s_wbe(sd_cpu_wbe), .s_ack(sd_cpu_ack),
        .s_rvalid(sd_cpu_rvalid), .s_rdata(sd_rdata), .s_rlast(sd_cpu_rlast)
    );

    wire        op_valid, op_ref, op_we, op_issue, init_done;
    wire [23:0] op_addr;  wire [1:0] op_len;  wire [63:0] op_wdata;  wire [7:0] op_wbe;  wire [1:0] op_tag;
    wire [3:0]  bank_idle;
    logic       init_s1 = 1'b0;
    always @(posedge clock) begin init_s1 <= init_done; init_s2 <= init_s1; end
    wire        rd_valid, rd_last;  wire [15:0] rd_data;  wire [1:0] rd_tag;
    wire [15:0] cpu_lat_max, vid_lat_stat, vid_underruns;
    wire [3:0]  ref_debt;

    sdram_arbiter arb (
        .clk(sclk), .reset(sd_reset), .init_done(init_done),
        .vid_req(vid_req), .vid_addr(vid_addr), .vid_len(vid_len), .vid_deadline(vid_deadline),
        .vid_ack(vid_ack), .vid_rvalid(vid_rvalid), .vid_rlast(vid_rlast),
        .cpu_req(sd_cpu_req), .cpu_we(sd_cpu_we), .cpu_addr(sd_cpu_addr), .cpu_len(sd_cpu_len),
        .cpu_wdata(sd_cpu_wdata), .cpu_wbe(sd_cpu_wbe),
        .cpu_ack(sd_cpu_ack), .cpu_rvalid(sd_cpu_rvalid), .cpu_rlast(sd_cpu_rlast),
        .ldr_req(1'b0), .ldr_we(1'b1), .ldr_addr(24'd0), .ldr_len(2'd0), .ldr_wdata(64'd0),
        .ldr_wbe(8'd0), .ldr_high(1'b0), .ldr_ack(), .ldr_rvalid(), .ldr_rlast(),
        .aux_req(1'b0), .aux_addr(24'd0), .aux_len(2'd0), .aux_ack(), .aux_rvalid(), .aux_rlast(),
        .rdata(sd_rdata),
        .op_valid(op_valid), .op_ref(op_ref), .op_we(op_we), .op_addr(op_addr),
        .op_len(op_len), .op_wdata(op_wdata), .op_wbe(op_wbe), .op_tag(op_tag),
        .op_issue(op_issue), .bank_idle(bank_idle), .rd_valid(rd_valid), .rd_data(rd_data),
        .rd_tag(rd_tag), .rd_last(rd_last),
        .cpu_lat_max(cpu_lat_max), .vid_lat_max(vid_lat_stat),
        .vid_underruns(vid_underruns), .ref_debt(ref_debt)
    );

    assign vid_rdata = sd_rdata;

    // What the arbiter captured of the CPU's writes, for the video engines
    // The fields are registered, as in PCXT.sv: the engines see the write one
    // sdram clock after the capture.
    always_ff @(posedge sclk) begin
        snoop_valid <= sd_cpu_ack & sd_cpu_we & ~sd_reset;
        snoop_addr  <= sd_cpu_addr;
        snoop_len   <= sd_cpu_len;
        snoop_wdata <= sd_cpu_wdata;
        snoop_wbe   <= sd_cpu_wbe;
    end

    wire        c_cke, c_cs_n, c_ras_n, c_cas_n, c_we_n, c_oe;
    wire [1:0]  c_ba, c_dqm;  wire [12:0] c_a;  wire [15:0] c_dq;
    logic       p_cke = 0, p_cs_n = 1, p_ras_n = 1, p_cas_n = 1, p_we_n = 1, p_oe = 0;
    logic [1:0] p_ba = 0, p_dqm = 3;  logic [12:0] p_a = 0;  logic [15:0] p_dq = 0;

    always @(posedge sclk) begin
        #(TCO);
        {p_cke, p_cs_n, p_ras_n, p_cas_n, p_we_n, p_oe} = {c_cke, c_cs_n, c_ras_n, c_cas_n, c_we_n, c_oe};
        {p_ba, p_dqm, p_a, p_dq} = {c_ba, c_dqm, c_a, c_dq};
    end

    // the chip's clock leaves the FPGA about half a period after the controller's
    logic chip_clk = 1'b0;
    always @(sclk) chip_clk <= #(TCK - LEAD) sclk;

    wire [15:0] chip_dq;  wire chip_drive, chip_valid;
    wire [15:0] dq_pin = p_oe ? p_dq : (chip_drive ? chip_dq : 16'hF10A);

    sdram_ctrl #(.INIT_US(20)) ctrl (
        .clk(sclk), .reset(sd_reset), .init_done(init_done),
        .op_valid(op_valid), .op_ref(op_ref), .op_we(op_we), .op_addr(op_addr),
        .op_len(op_len), .op_wdata(op_wdata), .op_wbe(op_wbe), .op_tag(op_tag),
        .op_issue(op_issue), .bank_idle(bank_idle), .rd_valid(rd_valid), .rd_data(rd_data),
        .rd_tag(rd_tag), .rd_last(rd_last),
        .sdram_cke(c_cke), .sdram_cs_n(c_cs_n), .sdram_ras_n(c_ras_n), .sdram_cas_n(c_cas_n),
        .sdram_we_n(c_we_n), .sdram_ba(c_ba), .sdram_a(c_a), .sdram_dqm(c_dqm),
        .sdram_dq_out(c_dq), .sdram_dq_oe(c_oe), .sdram_dq_in(dq_pin)
    );

    sdram_model #(.TCK(TCK), .CL(3)) chip (
        .clk(chip_clk), .cke(p_cke), .cs_n(p_cs_n), .ras_n(p_ras_n), .cas_n(p_cas_n),
        .we_n(p_we_n), .ba(p_ba), .a(p_a), .dqm(p_dqm), .dq_in(p_dq), .dq_in_oe(p_oe),
        .dq_out(chip_dq), .dq_drive(chip_drive), .dq_valid(chip_valid)
    );

    always @(p_oe or chip_drive)
        if (p_oe && chip_drive) begin
            $display("%0t ERROR: DQ contention", $time);
            contention++;
        end
    int contention = 0;

    assign vid_max_lat       = int'(vid_lat_stat);
    assign chip_errors       = chip.errors + contention;
    assign vid_underruns_out = int'(vid_underruns);

    // Backdoor into the memory: word addresses relative to MEM_BASE
    task automatic poke(input int rel, input logic [15:0] v);
        chip.poke(MEM_BASE + 24'(rel), v);
    endtask

    int vid_req_clks = 0, vid_acks = 0, vid_words = 0, init_clks = -1, clks = 0;
    always @(posedge sclk) begin
        clks++;
        if (vid_req) vid_req_clks++;
        if (vid_ack) vid_acks++;
        if (vid_rvalid) vid_words++;
        if (init_done && init_clks < 0) init_clks = clks;
    end

    final begin
        $display("real stack: worst CPU latency %0d, worst VID latency %0d (from becoming urgent), %0d video underruns, chip errors %0d, %0d background CPU transactions",
                 cpu_lat_max, vid_lat_stat, vid_underruns, chip.errors, g_ops);
        $display("real stack: init_done after %0d sdram clocks, VID port: %0d request clocks, %0d acks, %0d words", init_clks, vid_req_clks, vid_acks, vid_words);
    end
endmodule
