//
// SDR SDRAM controller for the MiSTer SDRAM module (32 MiB, x16, 4 banks,
// 8192 rows x 512 columns).
//
// It executes one operation at a time from the arbiter's holding
// register, but operations on different banks overlap: the ACTIVE of the next
// one can go out while the previous one is still in its tRCD or CAS latency.
//
// Every operation is ACTIVE + 1, 2 or 4 single-word column commands on
// consecutive clocks, the last one with auto-precharge. The mode register
// programs a burst length of one, so a burst is simply a run of column
// commands and its length is exact for reads and writes alike.
//
// Scheduling
//
// Issuing an operation fixes the clock of every command it will need: the
// ACTIVE on the next edge, column i RCD+i edges after it, and, for a read, the
// edge at which word i is sitting in the input register. These are written
// into small tables indexed by "edges from now" that shift down by one each
// clock:
//
//   col_*      the column command to send on that edge
//   wr_drv     the FPGA drives DQ after that edge (write data)
//   rd_busy    a write may not be sent on that edge, because the chip is
//              driving DQ for an earlier read around then, or because a
//              masked write's DQM would also mask that read's data (DQM read
//              latency is two clocks)
//   rd_*       which client the word in the input register belongs to
//
// An operation can be issued only when every slot it needs is still free,
// its bank has finished the previous auto-precharge (bank_wait) and tRRD has
// passed since the last ACTIVE. Nothing is ever cancelled, so a free slot
// stays free and the check is all there is to it.
//
// Clocking
//
// clk is the controller clock; SDRAM_CLK is the same frequency from its own
// PLL output, half a period later, forwarded through a DDIO register so that
// it leaves the FPGA like the commands do. A command registered on edge e is
// sampled by the chip around the middle of that cycle, and the data of a
// READ registered on edge e is in the input register after edge e+CL+1
// (RD_DELAY).
//
module sdram_ctrl #(
    parameter int RD_DELAY = 0,       // 0: CL+1
    parameter int INIT_US  = 200      // power-up wait
) (
    input  logic        clk,
    input  logic        reset,
    output logic        init_done,

    // Operation from the arbiter. Held, unchanged, until op_issue.
    input  logic        op_valid,
    input  logic        op_ref,       // AUTO REFRESH instead of an access
    input  logic        op_we,
    input  logic [23:0] op_addr,      // {bank, row, col}, 16-bit words
    input  logic [1:0]  op_len,       // sdram_pkg::LEN_*
    input  logic [63:0] op_wdata,
    input  logic [7:0]  op_wbe,
    input  logic [1:0]  op_tag,
    output logic        op_issue,     // taken on this edge
    output logic [3:0]  bank_idle,    // an ACTIVE to that bank would be allowed

    // Read words, in the order the reads were issued.
    output logic        rd_valid,
    output logic [15:0] rd_data,
    output logic [1:0]  rd_tag,
    output logic        rd_last,

    // Chip
    output logic        sdram_cke,
    output logic        sdram_cs_n,
    output logic        sdram_ras_n,
    output logic        sdram_cas_n,
    output logic        sdram_we_n,
    output logic [1:0]  sdram_ba,
    output logic [12:0] sdram_a,
    output logic [1:0]  sdram_dqm,    // {DQMH, DQML}
    output logic [15:0] sdram_dq_out,
    output logic        sdram_dq_oe,
    input  logic [15:0] sdram_dq_in
);

    // ------------------------------------------------------------------
    // Timing in clocks
    // ------------------------------------------------------------------
    localparam int CL    = 3;
    localparam int T_RCD = 3;     // 18 ns
    localparam int T_RP  = 3;     // 18 ns
    localparam int T_RAS = 5;     // 42 ns
    localparam int T_RC  = 7;     // 60 ns
    localparam int T_WR  = 2;               // 2 clocks / 14 ns
    localparam int T_RRD = 2;     // 12 ns
    localparam int T_RFC = 8;     // 60-70 ns, see the report
    localparam int T_MRD = 2;
    localparam int INIT_CYCLES = INIT_US * 115;
    localparam int RDD   = (RD_DELAY == 0) ? CL + 1 : RD_DELAY;

    // Table depths, in edges from now.
    localparam int COLS  = T_RCD + 4;              // last column index + 1
    localparam int MASK  = T_RCD + 3 + CL + 2;     // last read window index + 1
    localparam int RDQ   = T_RCD + 3 + RDD + 1;    // last capture index + 1

    // Bank ready time after the ACTIVE edge, per operation (see the report):
    // the auto-precharge starts after the last column (reads) or tWR after the
    // last write word, never before tRAS, and the next ACTIVE needs tRP after
    // that and tRC after this one.
    function automatic int max2(input int a, input int b);
        max2 = (a > b) ? a : b;
    endfunction

    function automatic int bank_busy(input bit we, input int n);
        int pre;
        pre = we ? max2(T_RCD + n - 1 + T_WR, T_RAS) : max2(T_RCD + n, T_RAS);
        bank_busy = max2(pre + T_RP, T_RC);
    endfunction

    // Loaded into bank_wait on the ACTIVE edge, so one less than the time.
    localparam logic [3:0] BUSY_R1 = 4'(bank_busy(0, 1) - 1);
    localparam logic [3:0] BUSY_R2 = 4'(bank_busy(0, 2) - 1);
    localparam logic [3:0] BUSY_R4 = 4'(bank_busy(0, 4) - 1);
    localparam logic [3:0] BUSY_W1 = 4'(bank_busy(1, 1) - 1);
    localparam logic [3:0] BUSY_W2 = 4'(bank_busy(1, 2) - 1);
    localparam logic [3:0] BUSY_W4 = 4'(bank_busy(1, 4) - 1);

    // ------------------------------------------------------------------
    // Commands {cs_n, ras_n, cas_n, we_n}
    // ------------------------------------------------------------------
    localparam logic [3:0] CMD_NOP   = 4'b0111;
    localparam logic [3:0] CMD_ACT   = 4'b0011;
    localparam logic [3:0] CMD_READ  = 4'b0101;
    localparam logic [3:0] CMD_WRITE = 4'b0100;
    localparam logic [3:0] CMD_PRE   = 4'b0010;
    localparam logic [3:0] CMD_REF   = 4'b0001;
    localparam logic [3:0] CMD_MRS   = 4'b0000;

    // BL = 1, sequential, CL, burst write = programmed length.
    localparam logic [12:0] MODE = {3'b000, 1'b0, 2'b00, 3'(CL), 1'b0, 3'b000};

    // ------------------------------------------------------------------
    // Power-up
    // ------------------------------------------------------------------
    typedef enum logic [2:0] {I_WAIT, I_PALL, I_REF, I_MRS, I_DONE} init_t;

    init_t       init_state;
    logic [15:0] init_cnt;
    logic [3:0]  init_refs;

    // ------------------------------------------------------------------
    // Schedule
    // ------------------------------------------------------------------
    logic             col_v   [COLS];
    logic             col_we  [COLS];
    logic             col_ap  [COLS];
    logic [1:0]       col_ba  [COLS];
    logic [8:0]       col_col [COLS];
    logic [15:0]      col_d   [COLS];
    logic [1:0]       col_dqm [COLS];

    logic [MASK-1:0]  wr_drv;
    logic [MASK-1:0]  rd_busy;

    logic             rdq_v    [RDQ];
    logic [1:0]       rdq_tag  [RDQ];
    logic             rdq_last [RDQ];

    logic [3:0]       bank_wait [4];
    logic [1:0]       act_wait;
    // The same as "== 0", registered: they gate op_issue, which feeds the
    // command outputs, so the compare is kept out of that path.
    logic [3:0]       bank_rdy;
    logic             act_rdy;

    // ------------------------------------------------------------------
    // Can the held operation go now?
    // ------------------------------------------------------------------
    wire [1:0]  op_bank = op_addr[23:22];
    wire [12:0] op_row  = op_addr[21:9];
    wire [8:0]  op_col  = op_addr[8:0];
    wire [2:0]  op_n    = sdram_pkg::len_words(op_len);

    logic slots_free;

    always_comb begin
        slots_free = 1'b1;
        // An ACTIVE with row bits 12:11 set drives the chip's DQM pins in its
        // own clock (XS/XSDS boards), which masks the read data two clocks
        // later: it may not go where a read's data would be. rd_busy covers
        // that clock for every word in flight.
        if ((op_row[12:11] != 2'b00) && rd_busy[0])
            slots_free = 1'b0;
        for (int i = 0; i < 4; i++) begin
            if (i < op_n) begin
                if (col_v[T_RCD + i])
                    slots_free = 1'b0;
                if (op_we) begin
                    if (rd_busy[T_RCD + i])
                        slots_free = 1'b0;
                end
                else begin
                    for (int k = CL - 2; k <= CL + 1; k++)
                        if (wr_drv[T_RCD + i + k])
                            slots_free = 1'b0;
                end
            end
        end
    end

    logic [3:0] op_busy;

    always_comb
        case ({op_we, op_len})
            {1'b0, sdram_pkg::LEN_1}: op_busy = BUSY_R1;
            {1'b0, sdram_pkg::LEN_2}: op_busy = BUSY_R2;
            {1'b1, sdram_pkg::LEN_1}: op_busy = BUSY_W1;
            {1'b1, sdram_pkg::LEN_2}: op_busy = BUSY_W2;
            default:                  op_busy = op_we ? BUSY_W4 : BUSY_R4;
        endcase

    wire can_access  = slots_free & bank_rdy[op_bank] & act_rdy;
    wire can_refresh = &bank_rdy;

    assign bank_idle = bank_rdy;

    assign op_issue = (init_state == I_DONE) & op_valid & ~col_v[0]
                    & (op_ref ? can_refresh : can_access);

    wire issue_act = op_issue & ~op_ref;
    wire issue_ref = op_issue &  op_ref;

    // ------------------------------------------------------------------
    // Next-edge command
    // ------------------------------------------------------------------
    logic [3:0]  cmd_n;
    logic [1:0]  ba_n;
    logic [12:0] a_n;
    logic [1:0]  dqm_n;
    logic [15:0] dq_n;
    logic        oe_n;

    always_comb begin
        cmd_n = CMD_NOP;
        ba_n  = 2'b00;
        a_n   = 13'd0;
        dqm_n = 2'b00;
        dq_n  = 16'h0000;
        oe_n  = 1'b0;

        if (init_state != I_DONE)
            dqm_n = 2'b11;

        case (init_state)
            I_PALL: if (init_cnt == 16'd0) begin
                cmd_n = CMD_PRE;
                a_n   = 13'h0400;                       // A10: all banks
            end
            I_REF:  if (init_cnt == 16'd0)
                cmd_n = CMD_REF;
            I_MRS:  if (init_cnt == 16'd0) begin
                cmd_n = CMD_MRS;
                a_n   = MODE;
            end
            I_DONE: begin
                // Only the command depends on op_issue. A column command and
                // an ACTIVE never share an edge, and the address and bank of
                // a REFRESH or a NOP do not matter, so the address, bank and
                // data are chosen by col_v[0] alone: the column if one is due,
                // otherwise the held operation's row.
                //
                // The byte masks also leave on A[12:11] (A12 = DQMH, A11 =
                // DQML), because on the MiSTer SDRAM XS/XSDS boards those two
                // nets, not the dedicated DQML/DQMH pins, are what the chip's
                // DQM pins are wired to. That makes A[12:11] a mask in every
                // cycle: it must be 0 in all but a masked write and an ACTIVE
                // (whose row bits it carries, so a high row has to keep clear
                // of the clocks where a read's data could be masked, see
                // slots_free). The two bits therefore do depend on op_issue.
                if (col_v[0]) begin
                    cmd_n = col_we[0] ? CMD_WRITE : CMD_READ;
                    ba_n  = col_ba[0];
                    a_n   = {col_dqm[0], col_ap[0], 1'b0, col_col[0]};
                    dqm_n = col_dqm[0];
                    oe_n  = col_we[0];
                end
                else begin
                    ba_n  = op_bank;
                    a_n   = {issue_act ? op_row[12:11] : 2'b00, op_row[10:0]};
                    if (issue_act)
                        cmd_n = CMD_ACT;
                    else if (issue_ref)
                        cmd_n = CMD_REF;
                end
                dq_n = col_d[0];
            end
            default: ;
        endcase
    end

    // Registered outputs; with FAST_OUTPUT_REGISTER these are the I/O cells.
    always_ff @(posedge clk) begin
        if (reset) begin
            sdram_cke   <= 1'b0;
            {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= CMD_NOP;
            sdram_ba    <= 2'b00;
            sdram_a     <= 13'd0;
            sdram_dqm   <= 2'b11;
            sdram_dq_out <= 16'h0000;
            sdram_dq_oe <= 1'b0;
        end
        else begin
            sdram_cke   <= 1'b1;
            {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} <= cmd_n;
            sdram_ba    <= ba_n;
            sdram_a     <= a_n;
            sdram_dqm   <= dqm_n;
            sdram_dq_out <= dq_n;
            sdram_dq_oe <= oe_n;
        end
    end

    // ------------------------------------------------------------------
    // Power-up sequence: wait, PRECHARGE ALL, 8 x AUTO REFRESH, MODE
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            init_state <= I_WAIT;
            init_cnt   <= 16'(INIT_CYCLES);
            init_refs  <= 4'd0;
        end
        else begin
            case (init_state)
                I_WAIT:
                    if (init_cnt != 16'd0)
                        init_cnt <= init_cnt - 16'd1;
                    else
                        init_state <= I_PALL;
                I_PALL:
                    if (init_cnt == 16'd0)
                        init_cnt <= 16'(T_RP);
                    else if (init_cnt == 16'd1) begin
                        init_cnt   <= 16'd0;
                        init_state <= I_REF;
                    end
                    else
                        init_cnt <= init_cnt - 16'd1;
                I_REF:
                    if (init_cnt == 16'd0) begin
                        init_cnt  <= 16'(T_RFC);
                        init_refs <= init_refs + 4'd1;
                    end
                    else if (init_cnt == 16'd1) begin
                        init_cnt <= 16'd0;
                        if (init_refs == 4'd8)
                            init_state <= I_MRS;
                    end
                    else
                        init_cnt <= init_cnt - 16'd1;
                I_MRS:
                    if (init_cnt == 16'd0)
                        init_cnt <= 16'(T_MRD);
                    else if (init_cnt == 16'd1) begin
                        init_cnt   <= 16'd0;
                        init_state <= I_DONE;
                    end
                    else
                        init_cnt <= init_cnt - 16'd1;
                default: ;
            endcase
        end
    end

    assign init_done = (init_state == I_DONE);

    // ------------------------------------------------------------------
    // Schedule tables
    // ------------------------------------------------------------------
    // Insert the new operation at its pre-shift indices, then shift by one.
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int k = 0; k < COLS; k++) begin
                col_v[k]   <= 1'b0;
                col_we[k]  <= 1'b0;
                col_ap[k]  <= 1'b0;
                col_ba[k]  <= 2'b00;
                col_col[k] <= 9'd0;
                col_d[k]   <= 16'h0000;
                col_dqm[k] <= 2'b00;
            end
            wr_drv  <= '0;
            rd_busy <= '0;
            for (int k = 0; k < RDQ; k++) begin
                rdq_v[k]    <= 1'b0;
                rdq_tag[k]  <= 2'b00;
                rdq_last[k] <= 1'b0;
            end
        end
        else begin : schedule
            logic             v   [COLS + 1];
            logic             we  [COLS + 1];
            logic             ap  [COLS + 1];
            logic [1:0]       ba  [COLS + 1];
            logic [8:0]       cc  [COLS + 1];
            logic [15:0]      d   [COLS + 1];
            logic [1:0]       m   [COLS + 1];
            logic [MASK:0]    wd;
            logic [MASK:0]    rb;
            logic             qv  [RDQ + 1];
            logic [1:0]       qt  [RDQ + 1];
            logic             ql  [RDQ + 1];

            for (int k = 0; k < COLS; k++) begin
                v[k] = col_v[k];  we[k] = col_we[k];  ap[k] = col_ap[k];
                ba[k] = col_ba[k]; cc[k] = col_col[k]; d[k] = col_d[k]; m[k] = col_dqm[k];
            end
            v[COLS] = 1'b0;  we[COLS] = 1'b0;  ap[COLS] = 1'b0;
            ba[COLS] = 2'b00; cc[COLS] = 9'd0; d[COLS] = 16'h0000; m[COLS] = 2'b00;

            wd = {1'b0, wr_drv};
            rb = {1'b0, rd_busy};

            for (int k = 0; k < RDQ; k++) begin
                qv[k] = rdq_v[k];  qt[k] = rdq_tag[k];  ql[k] = rdq_last[k];
            end
            qv[RDQ] = 1'b0;  qt[RDQ] = 2'b00;  ql[RDQ] = 1'b0;

            if (issue_act) begin
                for (int i = 0; i < 4; i++) begin
                    if (i < op_n) begin
                        v[T_RCD + i]  = 1'b1;
                        we[T_RCD + i] = op_we;
                        ap[T_RCD + i] = (3'(i) == op_n - 3'd1);
                        ba[T_RCD + i] = op_bank;
                        cc[T_RCD + i] = op_col + 9'(i);
                        d[T_RCD + i]  = op_wdata[16*i +: 16];
                        m[T_RCD + i]  = op_we ? ~op_wbe[2*i +: 2] : 2'b00;
                        if (op_we)
                            wd[T_RCD + i] = 1'b1;
                        else begin
                            for (int k = CL - 2; k <= CL + 1; k++)
                                rb[T_RCD + i + k] = 1'b1;
                            qv[T_RCD + i + RDD] = 1'b1;
                            qt[T_RCD + i + RDD] = op_tag;
                            ql[T_RCD + i + RDD] = (3'(i) == op_n - 3'd1);
                        end
                    end
                end
            end

            for (int k = 0; k < COLS; k++) begin
                col_v[k]   <= v[k + 1];
                col_we[k]  <= we[k + 1];
                col_ap[k]  <= ap[k + 1];
                col_ba[k]  <= ba[k + 1];
                col_col[k] <= cc[k + 1];
                col_d[k]   <= d[k + 1];
                col_dqm[k] <= m[k + 1];
            end
            wr_drv  <= wd[MASK:1];
            rd_busy <= rb[MASK:1];
            for (int k = 0; k < RDQ; k++) begin
                rdq_v[k]    <= qv[k + 1];
                rdq_tag[k]  <= qt[k + 1];
                rdq_last[k] <= ql[k + 1];
            end
        end
    end

    // ------------------------------------------------------------------
    // Bank and ACTIVE spacing
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int b = 0; b < 4; b++)
                bank_wait[b] <= 4'd0;
            act_wait <= 2'd0;
            bank_rdy <= 4'b1111;
            act_rdy  <= 1'b1;
        end
        else begin : timers
            logic [3:0] bw;
            logic [1:0] aw;
            for (int b = 0; b < 4; b++) begin
                if (issue_ref)
                    bw = 4'(T_RFC - 1);
                else if (issue_act && (op_bank == 2'(b)))
                    bw = op_busy;
                else if (bank_wait[b] != 4'd0)
                    bw = bank_wait[b] - 4'd1;
                else
                    bw = 4'd0;
                bank_wait[b] <= bw;
                bank_rdy[b]  <= (bw == 4'd0);
            end

            if (issue_act)
                aw = 2'(T_RRD - 1);
            else if (act_wait != 2'd0)
                aw = act_wait - 2'd1;
            else
                aw = 2'd0;
            act_wait <= aw;
            act_rdy  <= (aw == 2'd0);
        end
    end

    // ------------------------------------------------------------------
    // Read capture
    // ------------------------------------------------------------------
    // sdram_dq_in is sampled by the input register on every edge; rdq says
    // whose word it is.
    logic [15:0] dq_in_q;

    always_ff @(posedge clk) begin
        dq_in_q <= sdram_dq_in;
        if (reset) begin
            rd_valid <= 1'b0;
            rd_tag   <= 2'b00;
            rd_last  <= 1'b0;
        end
        else begin
            rd_valid <= rdq_v[0];
            rd_tag   <= rdq_tag[0];
            rd_last  <= rdq_last[0];
        end
    end

    assign rd_data = dq_in_q;

endmodule
