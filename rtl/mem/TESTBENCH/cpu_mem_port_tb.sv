//
// cpu_mem_port through the whole new path (sdram_xbridge, sdram_arbiter,
// sdram_ctrl, chip model) with synthetic bus cycles, the cases the RAM.sv
// benches (ram_lookahead_tb, ram_refresh_collision_tb) covered and a few new
// ones:
//
//   - MEMW pulses of a single chipset clock at Max (the write must still land,
//     with its own byte and address, even when the next cycle has started);
//     below Max the strobe lasts the two CPU clocks of a real bus cycle, and
//     the CPU takes the data at the end of them (memory_access_ready stays
//     high until the last moment a wait state can still be requested)
//   - read strobes released before the data (DMA refresh cycles do that)
//   - byte and 8086 word accesses, both lanes, every speed setting
//   - write-protected writes (must not land, must not hang)
//   - lookahead hits after misses, updates by writes, ROM-loader flush
//   - video memory (F2): CGA and HGC windows through mem_map, byte-wide, no
//     RAM wait states; a CGA write is held until MEMW ends and is then written
//     (and, with HGC page 1, written twice); reads right after such writes
//     must see them; at the end the SDRAM content is compared with the
//     reference
//
// Every read is checked against a reference memory. The bus is played in the
// chipset domain (50 MHz); the SDRAM side runs at 114.545 MHz.
//
`timescale 1ns / 1ps

module cpu_mem_port_tb #(
    parameter int OPS = 40000
);
    import sdram_pkg::*;

    localparam real T_CHIP = 20.0;
    localparam real T_SD   = 8.730;

    logic clk = 0, sd_clk = 0, sd_pin = 0;
    always #(T_CHIP / 2.0) clk = ~clk;
    initial begin #1.37; forever #(T_SD / 2.0) sd_clk = ~sd_clk; end
    initial begin #(1.37 + T_SD - 2.0); forever #(T_SD / 2.0) sd_pin = ~sd_pin; end
    logic reset = 1, sd_reset = 1;

    // Bus
    logic        memr_n = 1, memw_n = 1, wrq = 0, wwq = 0, flush = 0, early = 0;
    logic [19:0] address = 0;
    logic [7:0]  dbus = 0;
    logic [15:0] dword = 0;
    logic [1:0]  clk_select = 0;

    // CPU clock edges as the chipset makes them: a strobe starts one chipset
    // clock after a rising edge and lasts two CPU clocks below Max.
    int ph = 0;
    wire [3:0] period = (clk_select == 2'd0) ? 4'd10 : (clk_select == 2'd1) ? 4'd7 : 4'd5;
    wire ce_p = (ph == 0);
    wire ce_n = (ph == int'(period) / 2);
    always @(posedge clk) ph <= (ph + 1 >= int'(period)) ? 0 : ph + 1;
    logic [1:0]  protect_flags = 2'b00;
    wire  [7:0]  dout;
    wire  [15:0] dout_word;
    wire         ready;
    wire         sel, prot;
    wire  [24:0] phys, phys2;
    wire  [1:0]  vclass;
    wire         phys2_valid;
    logic        hgc_page = 1'b0;
    logic [6:0]  ems [0:3];
    initial begin ems[0] = 0; ems[1] = 0; ems[2] = 0; ems[3] = 0; end

    mem_map map (
        .address(address), .map_ems(ems), .ems_b1(1'b0), .ems_b2(1'b0), .ems_b3(1'b0),
        .ems_b4(1'b0), .enable_a000h(1'b1), .bios_protect_flag(protect_flags), .ec00_loaded(1'b1),
        .en_cga(1'b1), .en_hgc(1'b1), .hgc_page(hgc_page),
        .select(sel), .phys(phys), .protect(prot),
        .vclass(vclass), .phys2(phys2), .phys2_valid(phys2_valid)
    );

    wire m_start, m_we, m_busy, m_done;  wire [23:0] m_addr;  wire [1:0] m_len;
    wire [63:0] m_wdata, m_rdata;  wire [7:0] m_wbe;
    wire snoop_valid;  wire [23:0] snoop_addr;  wire [15:0] snoop_data;  wire [1:0] snoop_be;

    cpu_mem_port dut (
        .clock(clk), .reset(reset),
        .internal_data_bus(dbus), .data_bus_out(dout),
        .word_read_request(wrq), .word_write_request(wwq),
        .data_bus_in_word(dword), .data_bus_out_word(dout_word),
        .memory_read_n(memr_n), .memory_write_n(memw_n), .memory_access_ready(ready),
        .map_select(sel), .map_phys(phys), .map_protect(prot),
        .map_vclass(vclass), .map_phys2(phys2), .map_phys2_valid(phys2_valid),
        .cpu_ce_posedge(ce_p), .wait_count_clk_en(ce_n), .ram_read_wait_cycle(2'd2), .ram_write_wait_cycle(2'd2),
        .clk_select(clk_select), .flush(flush), .early_read(early),
        .m_start(m_start), .m_we(m_we), .m_addr(m_addr), .m_len(m_len), .m_wdata(m_wdata),
        .m_wbe(m_wbe), .m_busy(m_busy), .m_done(m_done), .m_rdata(m_rdata),
        .snoop_valid(snoop_valid), .snoop_addr(snoop_addr), .snoop_data(snoop_data),
        .snoop_be(snoop_be)
    );

    wire s_req, s_we, s_ack, s_rvalid, s_rlast;  wire [23:0] s_addr;  wire [1:0] s_len;
    wire [63:0] s_wdata;  wire [7:0] s_wbe;  wire [15:0] rdata;

    sdram_xbridge #(.SYNC_STAGES(2)) bridge (
        .clk_a(clk), .reset_a(reset),
        .a_start(m_start), .a_we(m_we), .a_addr(m_addr), .a_len(m_len),
        .a_wdata(m_wdata), .a_wbe(m_wbe), .a_busy(m_busy), .a_done(m_done), .a_rdata(m_rdata),
        .clk_s(sd_clk), .reset_s(sd_reset),
        .s_req(s_req), .s_we(s_we), .s_addr(s_addr), .s_len(s_len), .s_wdata(s_wdata),
        .s_wbe(s_wbe), .s_ack(s_ack), .s_rvalid(s_rvalid), .s_rdata(rdata), .s_rlast(s_rlast)
    );

    wire        op_valid, op_ref, op_we, op_issue, init_done;
    wire [23:0] op_addr;  wire [1:0] op_len;  wire [63:0] op_wdata;  wire [7:0] op_wbe;
    wire [1:0]  op_tag;  wire [3:0] bank_idle;
    wire        rd_valid, rd_last;  wire [15:0] rd_data;  wire [1:0] rd_tag;

    sdram_arbiter arb (
        .clk(sd_clk), .reset(sd_reset), .init_done(init_done),
        .vid_req(1'b0), .vid_addr(24'd0), .vid_len(LEN_1), .vid_deadline(16'd0),
        .vid_ack(), .vid_rvalid(), .vid_rlast(),
        .cpu_req(s_req), .cpu_we(s_we), .cpu_addr(s_addr), .cpu_len(s_len),
        .cpu_wdata(s_wdata), .cpu_wbe(s_wbe), .cpu_ack(s_ack), .cpu_rvalid(s_rvalid),
        .cpu_rlast(s_rlast),
        .ldr_req(1'b0), .ldr_we(1'b0), .ldr_addr(24'd0), .ldr_len(LEN_1), .ldr_wdata(64'd0),
        .ldr_wbe(8'd0), .ldr_high(1'b0), .ldr_ack(), .ldr_rvalid(), .ldr_rlast(),
        .aux_req(1'b0), .aux_addr(24'd0), .aux_len(LEN_1), .aux_ack(), .aux_rvalid(), .aux_rlast(),
        .rdata(rdata),
        .op_valid(op_valid), .op_ref(op_ref), .op_we(op_we), .op_addr(op_addr), .op_len(op_len),
        .op_wdata(op_wdata), .op_wbe(op_wbe), .op_tag(op_tag), .op_issue(op_issue),
        .bank_idle(bank_idle), .rd_valid(rd_valid), .rd_data(rd_data), .rd_tag(rd_tag),
        .rd_last(rd_last), .cpu_lat_max(), .vid_lat_max(), .vid_underruns(), .ref_debt()
    );

    wire        c_cke, c_cs_n, c_ras_n, c_cas_n, c_we_n, c_oe;
    wire [1:0]  c_ba, c_dqm;  wire [12:0] c_a;  wire [15:0] c_dq;
    logic       p_cke = 0, p_cs_n = 1, p_ras_n = 1, p_cas_n = 1, p_we_n = 1, p_oe = 0;
    logic [1:0] p_ba = 0, p_dqm = 3;  logic [12:0] p_a = 0;  logic [15:0] p_dq = 0;
    always @(posedge sd_clk) begin
        #(3.0);
        {p_cke, p_cs_n, p_ras_n, p_cas_n, p_we_n, p_oe} = {c_cke, c_cs_n, c_ras_n, c_cas_n, c_we_n, c_oe};
        {p_ba, p_dqm, p_a, p_dq} = {c_ba, c_dqm, c_a, c_dq};
    end
    wire [15:0] chip_dq;  wire chip_drive, chip_valid;
    wire [15:0] dq_pin = p_oe ? p_dq : (chip_drive ? chip_dq : 16'hF10A);

    sdram_ctrl #(.INIT_US(20)) ctrl (
        .clk(sd_clk), .reset(sd_reset), .init_done(init_done),
        .op_valid(op_valid), .op_ref(op_ref), .op_we(op_we), .op_addr(op_addr), .op_len(op_len),
        .op_wdata(op_wdata), .op_wbe(op_wbe), .op_tag(op_tag), .op_issue(op_issue),
        .bank_idle(bank_idle), .rd_valid(rd_valid), .rd_data(rd_data), .rd_tag(rd_tag),
        .rd_last(rd_last),
        .sdram_cke(c_cke), .sdram_cs_n(c_cs_n), .sdram_ras_n(c_ras_n), .sdram_cas_n(c_cas_n),
        .sdram_we_n(c_we_n), .sdram_ba(c_ba), .sdram_a(c_a), .sdram_dqm(c_dqm),
        .sdram_dq_out(c_dq), .sdram_dq_oe(c_oe), .sdram_dq_in(dq_pin)
    );
    sdram_model #(.TCK(T_SD), .CL(3)) chip (
        .clk(sd_pin), .cke(p_cke), .cs_n(p_cs_n), .ras_n(p_ras_n), .cas_n(p_cas_n),
        .we_n(p_we_n), .ba(p_ba), .a(p_a), .dqm(p_dqm), .dq_in(p_dq), .dq_in_oe(p_oe),
        .dq_out(chip_dq), .dq_drive(chip_drive), .dq_valid(chip_valid)
    );

    // ------------------------------------------------------------------
    int errors = 0;
    task automatic err(input string m);
        errors++;
        if (errors <= 20) $display("%0.1f ERROR: %s", $realtime, m);
    endtask
    always @(p_oe or chip_drive) if (p_oe && chip_drive) err("DQ contention");

    // Reference, by physical byte address (no EMS in this bench).
    logic [7:0] ref_mem [int unsigned];
    function automatic logic [7:0] rb(input logic [24:0] a);
        rb = ref_mem.exists(a) ? ref_mem[a] : 8'h00;
    endfunction

    // A CGA write must not leave for the SDRAM before MEMW has ended, and a
    // video access never waits for the RAM wait states (wait counts are 2 here)
    int def_writes = 0, vid_reads = 0, vid_writes = 0, dual = 0;
    logic own_active = 1'b0;
    always @(posedge clk) begin
        if (dut.accept_defer) def_writes++;
        if (dut.accept_defer) own_active <= 1'b1;
        else if (memw_n)      own_active <= 1'b0;
        if (dut.post_dw && own_active && !memw_n) err("CGA write sent before MEMW ended");
        if (dut.dw_pending && dut.accept_write) err("write accepted during a deferred write");
    end

    int hits = 0, misses = 0, reads = 0, writes = 0, orphans = 0, short_writes = 0;
    always @(posedge clk) begin
        if (dut.accept_hit) hits++;
        if (dut.accept_read) misses++;
    end

    // What the READY logic and the CPU see: values captured on the edge.
    logic       ready_q;
    logic [7:0] dout_q;
    logic [15:0] dout_word_q;
    always @(posedge clk) begin
        ready_q     <= ready;
        dout_q      <= dout;
        dout_word_q <= dout_word;
    end

    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    // One bus cycle, played like the chipset: signals change just after an
    // edge, decisions use what was captured on it. strobe = chipset clocks
    // the strobe stays low at least; abandon = release a read before its data.
    task automatic cycle(input logic we, input logic word, input logic [19:0] a,
                         input int strobe, input logic abandon);
        logic [15:0] v;
        logic [24:0] pa, pa2;
        logic        p2;
        logic [1:0]  vc;
        int n;
        v = 16'($urandom);
        address = a;
        wrq = ~we & word;
        wwq = we & word;
        dbus = v[7:0];
        dword = v;
        tick();                                   // T1: address latched
        pa = phys; pa2 = phys2; p2 = phys2_valid; vc = vclass;
        early = ~we && ($urandom_range(0, 1) == 1);
        tick();
        early = 1'b0;
        if (clk_select != 2'd3) begin
            do tick(); while (ph != 1);           // one clock after a rising edge
            if (strobe < 2 * int'(period) - 1 && !abandon) strobe = 2 * int'(period) - 1;
        end
        if (we) memw_n = 1'b0; else memr_n = 1'b0;
        n = 0;
        if (we) begin
            // Held until READY was seen on an edge, and at least strobe clocks.
            do begin tick(); n++; end while ((n < strobe || !ready_q) && n < 1000);
            if (n >= 1000) err($sformatf("write at %05h never ready", a));
            memw_n = 1'b1;
            if (!prot) begin
                writes++;
                if (strobe == 1) short_writes++;
                if (word) begin
                    ref_mem[pa] = v[7:0];
                    ref_mem[pa + 1] = v[15:8];
                end
                else ref_mem[pa] = v[7:0];
                if (vc != VC_NONE) vid_writes++;
                if (p2) begin ref_mem[pa2] = v[7:0]; dual++; end
            end
        end
        else if (abandon) begin
            repeat (strobe) tick();
            memr_n = 1'b1;
            orphans++;
        end
        else begin
            do begin tick(); n++; end while ((n < strobe || !ready_q) && n < 1000);
            // The CPU takes the data half a clock after the edge that last
            // looked at READY
            if (clk_select != 2'd3) repeat (int'(period) / 2 + 1) tick();
            if (n >= 1000) err($sformatf("read at %05h never ready", a));
            reads++;
            if (vc != VC_NONE) vid_reads++;
            if (word) begin
                if (dout_word_q !== {rb(pa + 1), rb(pa)})
                    err($sformatf("word read %05h: %04h expected %04h", a, dout_word_q, {rb(pa + 1), rb(pa)}));
            end
            else if (dout_q !== rb(pa))
                err($sformatf("byte read %05h: %02h expected %02h (speed %0d, strobe %0d, n %0d, hit %0d, early %0d)", a, dout_q, rb(pa), clk_select, strobe, n, dut.hit, early));
            memr_n = 1'b1;
        end
        wrq = 0; wwq = 0;
        tick();
    endtask

    initial begin
        repeat (5) @(posedge clk);
        reset = 0;
        @(posedge sd_clk); sd_reset = 0;
        wait (init_done);
        repeat (10) @(posedge clk);

        for (int k = 0; k < OPS; k++) begin
            logic [19:0] a;
            logic we, word;
            int strobe;
            if (k % 5000 == 0) clk_select = 2'(k / 5000 % 4);
            // A small window so lines are re-read and re-written often.
            a = 20'h01000 + 20'($urandom_range(0, 255));
            if ($urandom_range(0, 9) == 0) a = 20'hF0000 + 20'($urandom_range(0, 63));
            we   = ($urandom_range(0, 2) == 0);
            word = ($urandom_range(0, 3) == 0);
            // Video memory: a small window in each, so that reads follow writes
            if ($urandom_range(0, 3) == 0) begin
                if ($urandom_range(0, 15) == 0) hgc_page = ~hgc_page;
                // with HGC page 1 only B8000 is memory (CGA, and HGC page 1 behind it)
                a = 20'hB0000 + ((hgc_page || $urandom_range(0, 1)) ? 20'h8000 : 20'h0000) + 20'($urandom_range(0, 127));
                word = 1'b0;
                we   = ($urandom_range(0, 1) == 0);
            end
            if (word) a[0] = 1'b0;
            strobe = $urandom_range(1, 6);
            protect_flags = ($urandom_range(0, 7) == 0) ? 2'b10 : 2'b00;
            if ($urandom_range(0, 199) == 0) begin
                flush = 1'b1; tick(); flush = 1'b0;
            end
            cycle(we, word, a, strobe, !we && ($urandom_range(0, 19) == 0));
        end
        repeat (100) @(posedge clk);
        // Read the window back once more.
        clk_select = 2'b00;
        for (int a = 20'h01000; a < 20'h01100; a++) cycle(1'b0, 1'b0, 20'(a), 3, 1'b0);

        // Whatever the CPU wrote must be in the chip, in every place it went
        begin
            int bad = 0, n = 0;
            foreach (ref_mem[k]) begin
                logic [15:0] w = chip.peek(k >> 1);
                logic [7:0]  b = k[0] ? w[15:8] : w[7:0];
                n++;
                if (b !== ref_mem[k]) begin
                    bad++;
                    if (bad <= 10) err($sformatf("chip byte %07h is %02h, expected %02h", k, b, ref_mem[k]));
                end
            end
            $display("chip content: %0d bytes checked, %0d wrong", n, bad);
        end

        $display("%0d reads (%0d lookahead hits, %0d SDRAM reads), %0d writes (%0d one-clock MEMW), %0d abandoned reads",
                 reads, hits, misses, writes, short_writes, orphans);
        $display("video: %0d reads, %0d writes (%0d held to the end of MEMW, %0d to two places)",
                 vid_reads, vid_writes, def_writes, dual);
        if (def_writes == 0 || dual == 0 || vid_reads == 0) err("video cases not covered");
        $display("chip: %0d protocol errors", chip.errors);
        $display("RESULT: %s", (errors == 0 && chip.errors == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
