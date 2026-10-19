//
// CPU memory port: the chipset side of system memory. It keeps
// the contract RAM.sv had with the chipset bus - memory_access_ready, the
// private 16-bit path of an 8086 bus cycle, and writes that are owned once
// accepted even if MEMW ends first - and turns each access into an
// sdram_port transaction through sdram_xbridge.
//
// What changed from RAM.sv:
//
//  * Storage is packed: two bytes per 16-bit SDRAM word, the even one
//    in the low lane. A byte write is a one-word write with one byte enable;
//    an 8086 word (always at an even address, see below) is one word.
//
//  * The physical address comes from mem_map; this module knows no machine.
//
//  * Reads are closed loop at every speed: memory_access_ready is low from
//    the strobe until the data is here. With KFSDRAM on the chipset clock the
//    answer was known to come back in time and the readiness could be left
//    high; with the controller on its own clock it cannot be assumed. The
//    READY logic only turns a late answer into a wait state if it is later
//    than the point where the bus cycle samples it, which is what
//    cpu_sdram_e2e_tb measures for every speed.
//
//  * Writes are posted: accepted at once (ready stays high), carried out in
//    the background. A following access waits only if the bridge is still
//    busy with it.
//
//  * The lookahead keeps two lines of up to four words each (eight bytes)
//    instead of two single bytes. A read that misses fetches the requested
//    word and, at the two fastest settings, the words after it: 2 at 9.54 MHz
//    and 4 at Max (clipped at the end of the 512-word row). At 4.77 and
//    7.16 MHz only the word itself is read, but its second byte is still
//    kept. Writes update a line they fall in instead of invalidating it, and
//    a ROM-loader write (flush) clears both lines.
//
//  * Committed writes are published on the snoop port for vram_fetch (F2).
//
//  * A CPU read may start before its strobe (early_read): the chipset raises
//    it once the address of a memory read or code fetch has been latched in
//    T1, about one CPU clock before MEMR. The line goes into the lookahead,
//    and the strobe then finds it there or waits for it. It is only a read
//    of memory that has no side effects, so a wrong guess costs nothing but
//    the transaction. With the controller on its own clock this is what
//    keeps 7.16 MHz free of extra wait states (see cpu_sdram_e2e_tb).
//
// The 8086 word contract is unchanged: a word request only ever comes for an
// even address, so it is always exactly one SDRAM word.
//
module cpu_mem_port (
    input  logic        clock,
    input  logic        reset,

    // Chipset bus
    input  logic [7:0]  internal_data_bus,
    output logic [7:0]  data_bus_out,
    input  logic        word_read_request,
    input  logic        word_write_request,
    input  logic [15:0] data_bus_in_word,
    output logic [15:0] data_bus_out_word,
    input  logic        memory_read_n,
    input  logic        memory_write_n,
    output logic        memory_access_ready,

    // From mem_map
    input  logic        map_select,
    input  logic [24:0] map_phys,
    input  logic        map_protect,

    // Wait profile and speed (0 4.77, 1 7.16, 2 9.54, 3 Max)
    input  logic        wait_count_clk_en,
    input  logic [1:0]  ram_read_wait_cycle,
    input  logic [1:0]  ram_write_wait_cycle,
    input  logic [1:0]  clk_select,

    input  logic        flush,
    input  logic        early_read,     // CPU read/fetch address latched (T1)

    // Transaction to sdram_xbridge
    output logic        m_start,
    output logic        m_we,
    output logic [23:0] m_addr,
    output logic [1:0]  m_len,
    output logic [63:0] m_wdata,
    output logic [7:0]  m_wbe,
    input  logic        m_busy,
    input  logic        m_done,
    input  logic [63:0] m_rdata,

    // Committed writes
    output logic        snoop_valid,
    output logic [23:0] snoop_addr,
    output logic [15:0] snoop_data,
    output logic [1:0]  snoop_be
);
    import sdram_pkg::*;

    wire        read_command  = map_select & ~memory_read_n;
    wire        write_command = map_select & ~memory_write_n & ~map_protect;
    wire        cmd_active    = read_command | write_command;

    wire [23:0] w    = map_phys[24:1];
    wire        lane = map_phys[0];

    // ------------------------------------------------------------------
    // Lookahead lines
    // ------------------------------------------------------------------
    logic        la_valid [2];
    logic [23:0] la_base  [2];
    logic [2:0]  la_cnt   [2];
    logic [63:0] la_data  [2];
    logic        la_victim;

    logic [23:0] la_off  [2];
    logic        la_in   [2];

    always_comb
        for (int e = 0; e < 2; e++) begin
            la_off[e] = w - la_base[e];
            la_in[e]  = la_valid[e] & (la_off[e] < 24'(la_cnt[e]));
        end

    wire        hit      = la_in[0] | la_in[1];
    wire [63:0] hit_line = la_in[0] ? la_data[0] : la_data[1];
    wire [1:0]  hit_off  = la_in[0] ? la_off[0][1:0] : la_off[1][1:0];
    wire [15:0] hit_word = hit_line[16*hit_off +: 16];

    // Burst length of a read miss.
    logic [1:0] rd_len;
    always_comb begin
        case (clk_select)
            2'b11:   rd_len = (w[8:0] <= 9'd508) ? LEN_4 : ((w[8:0] <= 9'd510) ? LEN_2 : LEN_1);
            2'b10:   rd_len = (w[8:0] <= 9'd510) ? LEN_2 : LEN_1;
            default: rd_len = LEN_1;
        endcase
    end

    // ------------------------------------------------------------------
    // Accepting a strobe
    // ------------------------------------------------------------------
    logic        owned;         // the active strobe has been accepted
    logic        rd_valid;      // data_reg answers the active read
    logic        rd_owner;      // the transaction in flight answers it
    logic        xfer_read;     // the transaction in flight is a read
    logic [23:0] xfer_w;
    logic [1:0]  xfer_len;
    logic        xfer_lane;
    logic [15:0] data_reg;

    wire bridge_free = ~m_busy & ~m_done;

    wire accept_hit   = cmd_active & ~owned & read_command & hit & ~flush;
    wire accept_read  = cmd_active & ~owned & read_command & ~accept_hit & bridge_free;
    wire accept_write = cmd_active & ~owned & ~read_command & write_command & bridge_free;
    wire accept_early = early_read & ~cmd_active & map_select & ~hit & ~flush & bridge_free;

    // A read strobe waiting for the line an early read is bringing: answer
    // it from the line on its way into the lookahead.
    wire [23:0] xfer_off   = w - xfer_w;
    wire        xfer_cover = xfer_off < 24'(len_words(xfer_len));

    // Byte or word written.
    wire        wr_word  = word_write_request;
    wire [15:0] wr_data  = wr_word ? data_bus_in_word : {internal_data_bus, internal_data_bus};
    wire [1:0]  wr_be    = wr_word ? 2'b11 : (lane ? 2'b10 : 2'b01);

    assign m_start = accept_read | accept_write | accept_early;
    assign m_we    = accept_write;
    assign m_addr  = w;
    assign m_len   = accept_write ? LEN_1 : rd_len;
    assign m_wdata = {48'd0, wr_data};
    assign m_wbe   = accept_write ? {6'd0, wr_be} : 8'd0;

    assign snoop_valid = accept_write;
    assign snoop_addr  = w;
    assign snoop_data  = wr_data;
    assign snoop_be    = wr_be;

    function automatic logic [15:0] merge(input logic [15:0] old, input logic [15:0] d,
                                          input logic [1:0] be);
        merge = {be[1] ? d[15:8] : old[15:8], be[0] ? d[7:0] : old[7:0]};
    endfunction

    always_ff @(posedge clock) begin
        if (reset) begin
            owned     <= 1'b0;
            rd_valid  <= 1'b0;
            rd_owner  <= 1'b0;
            xfer_read <= 1'b0;
            xfer_w    <= 24'd0;
            xfer_len  <= LEN_1;
            xfer_lane <= 1'b0;
            data_reg  <= 16'h0000;
            la_victim <= 1'b0;
            for (int e = 0; e < 2; e++) begin
                la_valid[e] <= 1'b0;
                la_base[e]  <= 24'd0;
                la_cnt[e]   <= 3'd0;
                la_data[e]  <= 64'd0;
            end
        end
        else begin
            // The strobe has gone: the next one is a new access.
            if (!cmd_active) begin
                owned    <= 1'b0;
                rd_valid <= 1'b0;
                rd_owner <= 1'b0;
            end

            if (accept_hit) begin
                owned    <= 1'b1;
                rd_valid <= 1'b1;
                data_reg <= (word_read_request || !lane) ? hit_word : {8'h00, hit_word[15:8]};
            end

            if (accept_read) begin
                owned     <= 1'b1;
                rd_owner  <= 1'b1;
                xfer_read <= 1'b1;
                xfer_w    <= w;
                xfer_len  <= rd_len;
                xfer_lane <= lane & ~word_read_request;
            end

            if (accept_early) begin
                xfer_read <= 1'b1;
                xfer_w    <= w;
                xfer_len  <= rd_len;
            end

            if (accept_write) begin
                owned     <= 1'b1;
                xfer_read <= 1'b0;
                for (int e = 0; e < 2; e++)
                    if (la_in[e])
                        la_data[e][16*la_off[e][1:0] +: 16] <=
                            merge(la_data[e][16*la_off[e][1:0] +: 16], wr_data, wr_be);
            end

            if (m_done && xfer_read) begin
                xfer_read <= 1'b0;
                if (rd_owner && cmd_active) begin
                    rd_owner <= 1'b0;
                    rd_valid <= 1'b1;
                    data_reg <= xfer_lane ? {8'h00, m_rdata[15:8]} : m_rdata[15:0];
                end
                else if (read_command && !owned && xfer_cover && !flush) begin
                    owned    <= 1'b1;
                    rd_valid <= 1'b1;
                    data_reg <= (word_read_request || !lane)
                              ? m_rdata[16*xfer_off[1:0] +: 16]
                              : {8'h00, m_rdata[16*xfer_off[1:0] + 8 +: 8]};
                end
                if (!flush) begin
                    la_valid[la_victim] <= 1'b1;
                    la_base[la_victim]  <= xfer_w;
                    la_cnt[la_victim]   <= len_words(xfer_len);
                    la_data[la_victim]  <= m_rdata;
                    la_victim           <= ~la_victim;
                end
            end

            if (flush) begin
                la_valid[0] <= 1'b0;
                la_valid[1] <= 1'b0;
            end
        end
    end

    assign data_bus_out      = read_command ? data_reg[7:0] : 8'h00;
    assign data_bus_out_word = data_reg;

    // synthesis translate_off
    always_ff @(posedge clock) begin
        if (!reset && (accept_read || accept_hit) && word_read_request && map_phys[0])
            $display("%0t cpu_mem_port: WORD READ AT ODD ADDRESS %07h - contract violated", $time, map_phys);
        if (!reset && accept_write && word_write_request && map_phys[0])
            $display("%0t cpu_mem_port: WORD WRITE AT ODD ADDRESS %07h - contract violated", $time, map_phys);
    end
    // synthesis translate_on

    // ------------------------------------------------------------------
    // Ready / wait (wait counters as in RAM.sv)
    // ------------------------------------------------------------------
    logic [1:0] read_wait_count;
    logic [1:0] write_wait_count;

    always_ff @(posedge clock) begin
        if (reset)
            read_wait_count <= 2'd0;
        else if (~read_command)
            read_wait_count <= ram_read_wait_cycle;
        else if (wait_count_clk_en && (read_wait_count != 2'd0))
            read_wait_count <= read_wait_count - 2'd1;
    end

    always_ff @(posedge clock) begin
        if (reset)
            write_wait_count <= 2'd0;
        else if (~write_command)
            write_wait_count <= ram_write_wait_cycle;
        else if (wait_count_clk_en && (write_wait_count != 2'd0))
            write_wait_count <= write_wait_count - 2'd1;
    end

    // A write is ready in the very clock it is accepted: the READY logic
    // turns even one clock of "not ready" into a whole wait state, and
    // RAM.sv never showed one for a write below Max.
    wire access_ready = read_command  ? (owned & rd_valid)
                      : write_command ? (owned | accept_write)
                      :                 1'b1;

    assign memory_access_ready = (map_select & (~memory_read_n | ~memory_write_n))
                               ? (access_ready
                                  & ((read_wait_count == 2'd0) | ~read_command)
                                  & ((write_wait_count == 2'd0) | ~write_command))
                               : 1'b1;

endmodule
