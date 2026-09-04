//============================================================================
//
//  What the BIU does on the bus, pinned down before anything changes it.
//
//  Steps 3, 4 and 5 of docs/8086-adaptation.md all rewrite parts of
//  mcl86_biu_max: the prefetch queue grows from four bytes to six, the fetch
//  becomes word-aligned, and the word split is suppressed at even addresses.
//  Until this bench existed the only check available was "the BIOS still
//  boots", which takes a twenty-minute synthesis to run, says nothing about
//  which of a dozen behaviours moved, and has already cost this project two
//  builds spent on hypotheses.
//
//  So this is a characterisation bench first and a regression bench second. It
//  is written against the CURRENT four-byte queue and must pass unmodified on
//  it. Every number that the 8086 work is expected to change is named by a
//  parameter or called out in its case, so that when a case starts failing the
//  question is always "is this the change I meant to make".
//
//  What it drives: the BIU is the whole DUT. This bench plays the EU on one
//  side - EU_BIU_COMMAND, EU_REGISTER_R3, the opcode-fetch strobe - and the
//  motherboard on the other, latching the address off the multiplexed bus
//  during the address phase and presenting memory on AD_IN. Bus cycles are
//  observed exactly the way an 8288 sees them, off S2_S0_OUT, rather than by
//  reaching into the state machine: the internal state numbering is precisely
//  what steps 4 and 5 are going to disturb.
//
//  Memory is a function rather than an array, so any address in the 20-bit
//  space answers and the expected value is computable in the check.
//
//============================================================================

`timescale 1ns / 1ps

module biu_prefetch_tb;

    // The queue is four bytes on an 8088 and six on an 8086, selected by the
    // BIU's IS8086 input. Both are exercised: the depth is the one number the
    // rework was for, and 8088 mode has to come out of it bit for bit.
    localparam integer PFQ_DEPTH_8088 = 4;
    localparam integer PFQ_DEPTH_8086 = 6;

    //------------------------------------------------------------------------
    // Clocks. CORE_CLK_INT runs the state machine; CLK is the 8088 pin clock
    // and is an input to be edge-detected, which is what gives the fast FSM
    // real bus timing. Eight core clocks per pin clock keeps every edge
    // unambiguous without making the run long.
    //------------------------------------------------------------------------
    logic CORE_CLK_INT = 1'b0;
    logic CLK          = 1'b0;
    always #5  CORE_CLK_INT = ~CORE_CLK_INT;    // 100 MHz
    always #40 CLK          = ~CLK;             // 12.5 MHz

    logic        RESET_INT = 1'b1;
    logic        READY_IN  = 1'b1;
    logic [15:0] EU_BIU_COMMAND  = 16'h0000;
    logic [15:0] EU_BIU_DATAOUT  = 16'h0000;
    logic [15:0] EU_REGISTER_R3  = 16'h0000;
    logic        IS8086          = 1'b0;

    wire         LOCK_n, AD_OE, S6_3_MUX;
    wire [19:0]  AD_OUT;
    wire [2:0]   S2_S0_OUT;
    wire         BIU_DONE, BIU_CLK_COUNTER_ZERO;
    wire [1:0]   BIU_SEGMENT;
    wire         BIU_NMI_CAUGHT, BIU_INTR;
    wire [7:0]   PFQ_TOP_BYTE;
    wire         PFQ_EMPTY;
    wire [15:0]  PFQ_ADDR_OUT;
    wire [15:0]  BIU_REGISTER_ES, BIU_REGISTER_SS, BIU_REGISTER_CS;
    wire [15:0]  BIU_REGISTER_DS, BIU_REGISTER_RM, BIU_REGISTER_REG;
    wire [15:0]  BIU_RETURN_DATA;

    wire  [7:0]  AD_IN;
    wire         WORD_READ_REQUEST;
    wire         WORD_WRITE_REQUEST;
    wire [15:0]  DATA_BUS_WORD_OUT;
    wire [15:0]  DATA_BUS_WORD;

    mcl86_biu_max dut (
        .CORE_CLK_INT   (CORE_CLK_INT),
        .RESET_INT      (RESET_INT),
        .CLK            (CLK),
        .READY_IN       (READY_IN),
        .NMI            (1'b0),
        .INTR           (1'b0),
        .LOCK_n         (LOCK_n),
        .AD_OE          (AD_OE),
        .AD_OUT         (AD_OUT),
        .AD_IN          (AD_IN),
        .S6_3_MUX       (S6_3_MUX),
        .S2_S0_OUT      (S2_S0_OUT),
        .EU_BIU_COMMAND (EU_BIU_COMMAND),
        .EU_BIU_DATAOUT (EU_BIU_DATAOUT),
        .EU_REGISTER_R3 (EU_REGISTER_R3),
        .EU_PREFIX_LOCK (1'b0),
        .BIU_DONE       (BIU_DONE),
        .BIU_CLK_COUNTER_ZERO (BIU_CLK_COUNTER_ZERO),
        .BIU_SEGMENT    (BIU_SEGMENT),
        .BIU_NMI_CAUGHT (BIU_NMI_CAUGHT),
        .BIU_NMI_DEBOUNCE (1'b0),
        .BIU_INTR       (BIU_INTR),
        .PFQ_TOP_BYTE   (PFQ_TOP_BYTE),
        .PFQ_EMPTY      (PFQ_EMPTY),
        .PFQ_ADDR_OUT   (PFQ_ADDR_OUT),
        .BIU_REGISTER_ES  (BIU_REGISTER_ES),
        .BIU_REGISTER_SS  (BIU_REGISTER_SS),
        .BIU_REGISTER_CS  (BIU_REGISTER_CS),
        .BIU_REGISTER_DS  (BIU_REGISTER_DS),
        .BIU_REGISTER_RM  (BIU_REGISTER_RM),
        .BIU_REGISTER_REG (BIU_REGISTER_REG),
        .BIU_RETURN_DATA  (BIU_RETURN_DATA),
        .clock_cycle_counter_division_ratio  (8'd0),
        .clock_cycle_counter_decrement_value (8'd1),
        .shift_read_timing (1'b0),
        .IS8086         (IS8086),
        .WORD_READ_REQUEST (WORD_READ_REQUEST),
        .WORD_WRITE_REQUEST(WORD_WRITE_REQUEST),
        .DATA_BUS_WORD_OUT (DATA_BUS_WORD_OUT),
        .DATA_BUS_WORD     (DATA_BUS_WORD),
        .WORD_ACCESS_POSSIBLE(WORD_ACCESS_POSSIBLE)
    );

    //------------------------------------------------------------------------
    // The motherboard side
    //------------------------------------------------------------------------
    // Memory as a function, so every address in the space answers and the
    // expected value can be computed inside a check instead of being carried
    // around in an array the test has to keep in step.
    function automatic [7:0] mem_byte(input [19:0] a);
        mem_byte = a[7:0] ^ a[15:8] ^ {4'h0, a[19:16]} ^ 8'hA5;
    endfunction

    // The address phase is the window where AD carries the address and the
    // upper bits are still address rather than status. Latching there is what
    // a 74LS373 on a real board does, and it is why this bench never has to
    // look at biu_state - which is exactly what steps 4 and 5 will renumber.
    logic [19:0] bus_addr = 20'h00000;
    always @(posedge CORE_CLK_INT)
        if (AD_OE && !S6_3_MUX)
            bus_addr <= AD_OUT;

    assign AD_IN = mem_byte(bus_addr);

    // The word path never goes through the byte multiplexer - see
    // docs/8086-adaptation.md, step 2 - so the bench mirrors that: a second,
    // independent function of the same latched address, not a byte pair
    // assembled from AD_IN.
    assign DATA_BUS_WORD = {mem_byte(bus_addr + 20'd1), mem_byte(bus_addr)};
    // Mirrors Chipset's SDRAM decode with UMB enabled and no EMS bank mapped.
    // It is deliberately based on the address latched from T1, which is when
    // the real word_read_possible signal becomes valid.
    wire WORD_ACCESS_POSSIBLE = (bus_addr < 20'hA0000)
                              | (bus_addr >= 20'hC0000);

    //------------------------------------------------------------------------
    // Bus cycle observation, off S2_S0_OUT exactly as the 8288 sees it
    //------------------------------------------------------------------------
    localparam logic [2:0] ST_PASSIVE = 3'b111;
    localparam logic [2:0] ST_FETCH   = 3'b100;
    localparam logic [2:0] ST_IOR     = 3'b001;
    localparam logic [2:0] ST_IOW     = 3'b010;
    localparam logic [2:0] ST_MEMR    = 3'b101;
    localparam logic [2:0] ST_MEMW    = 3'b110;

    logic [2:0]  prev_status = ST_PASSIVE;
    integer      cycles_seen  = 0;
    integer      fetches_seen = 0;

    // The last few cycles, so a check can say what actually happened.
    localparam integer LOG_DEPTH = 64;
    logic [2:0]  log_status [0:LOG_DEPTH-1];
    logic [19:0] log_addr   [0:LOG_DEPTH-1];
    logic [7:0]  log_data   [0:LOG_DEPTH-1];
    integer      log_len    [0:LOG_DEPTH-1];   // Core clocks the status was active
    logic        log_wide   [0:LOG_DEPTH-1];   // WORD_READ_REQUEST, captured with the rest
    logic        log_wide_write [0:LOG_DEPTH-1];
    logic [15:0] log_word_out [0:LOG_DEPTH-1];
    integer      log_count = 0;
    integer      cycle_len = 0;

    always @(posedge CORE_CLK_INT) begin
        if (!RESET_INT) begin
            prev_status <= S2_S0_OUT;
            if ((prev_status == ST_PASSIVE) && (S2_S0_OUT != ST_PASSIVE)) begin
                cycles_seen <= cycles_seen + 1;
                cycle_len   <= 1;
                if (S2_S0_OUT == ST_FETCH)
                    fetches_seen <= fetches_seen + 1;
            end
            else if (S2_S0_OUT != ST_PASSIVE) begin
                cycle_len <= cycle_len + 1;
            end
            // The address is settled and, on a write, so is the data by the
            // time the status returns to passive.
            if ((prev_status != ST_PASSIVE) && (S2_S0_OUT == ST_PASSIVE)) begin
                if (log_count < LOG_DEPTH) begin
                    log_status[log_count] <= prev_status;
                    log_addr  [log_count] <= bus_addr;
                    log_data  [log_count] <= AD_OUT[7:0];
                    log_len   [log_count] <= cycle_len;
                    log_wide  [log_count] <= WORD_READ_REQUEST;
                    log_wide_write[log_count] <= WORD_WRITE_REQUEST;
                    log_word_out[log_count] <= DATA_BUS_WORD_OUT;
                    log_count <= log_count + 1;
                end
            end
        end
    end

    task automatic log_clear;
        begin
            log_count = 0;
        end
    endtask

    //------------------------------------------------------------------------
    // Scoreboard
    //------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    task automatic fail_msg(input string message);
        begin
            fail_count = fail_count + 1;
            $display("  FAIL  %s", message);
        end
    endtask

    task automatic pass_msg(input string message);
        begin
            pass_count = pass_count + 1;
            $display("  PASS  %s", message);
        end
    endtask

    //------------------------------------------------------------------------
    // Playing the EU
    //------------------------------------------------------------------------
    // EU_BIU_COMMAND is packed: [14] segment-override present, [13:12] strobe,
    // [11:10] default segment, [9] request, [8:4] request code, [3:2] queue
    // status, [1:0] the override's segment.
    function automatic [15:0] cmd_request(input [4:0] code, input [1:0] seg);
        cmd_request = {2'b00, 2'b00, seg, 1'b1, code, 2'b00, 2'b00};
    endfunction

    localparam logic [15:0] CMD_FETCH_STROBE = {2'b00, 2'b01, 2'b00, 1'b0,
                                                5'h00, 2'b00, 2'b00};

    // A request is held until the BIU reports it done - eu_biu_req is caught on
    // its rising edge and released on completion, so dropping it early would
    // race the BIU rather than cancel anything.
    // Loads CS directly, via the same strobe path a MOV-to-segreg uses
    // (eu_biu_strobe==2'b11, register code 2 - see the case in
    // mcl86_biu_max.sv). Needed only to reach addresses a 16-bit jump offset
    // from CS=FFFF cannot: that reachable range is [0,0FFEFh] union
    // [FFFF0h,FFFFFh], nowhere near the 0A0000h/0F0000h boundary this file
    // tests below.
    localparam logic [2:0] SEG_CS = 3'h2;
    localparam logic [2:0] SEG_DS = 3'h3;
    localparam logic [2:0] SEG_SS = 3'h1;

    task automatic load_cs(input [15:0] value);
        begin
            @(negedge CORE_CLK_INT);
            EU_BIU_DATAOUT = value;
            EU_BIU_COMMAND = {2'b00, 2'b11, 2'b00, 1'b0, 2'b00, SEG_CS, 2'b00, 2'b00};
            @(negedge CORE_CLK_INT);
            EU_BIU_COMMAND = 16'h0000;
            @(negedge CORE_CLK_INT);
        end
    endtask

    task automatic load_ds(input [15:0] value);
        begin
            @(negedge CORE_CLK_INT);
            EU_BIU_DATAOUT = value;
            EU_BIU_COMMAND = {2'b00, 2'b11, 2'b00, 1'b0, 2'b00, SEG_DS, 2'b00, 2'b00};
            @(negedge CORE_CLK_INT);
            EU_BIU_COMMAND = 16'h0000;
            @(negedge CORE_CLK_INT);
        end
    endtask

    task automatic load_ss(input [15:0] value);
        begin
            @(negedge CORE_CLK_INT);
            EU_BIU_DATAOUT = value;
            EU_BIU_COMMAND = {2'b00, 2'b11, 2'b00, 1'b0, 2'b00, SEG_SS, 2'b00, 2'b00};
            @(negedge CORE_CLK_INT);
            EU_BIU_COMMAND = 16'h0000;
            @(negedge CORE_CLK_INT);
        end
    endtask

    task automatic eu_request(input [4:0] code, input [1:0] seg,
                              input [15:0] r3, input string label);
        integer guard;
        begin
            @(negedge CORE_CLK_INT);
            EU_REGISTER_R3 = r3;
            EU_BIU_COMMAND = cmd_request(code, seg);

            guard = 0;
            while (!BIU_DONE && (guard < 20000)) begin
                @(posedge CORE_CLK_INT); #1; guard = guard + 1;
            end
            if (!BIU_DONE)
                fail_msg($sformatf("%s: BIU never reported done", label));

            @(negedge CORE_CLK_INT);
            EU_BIU_COMMAND = 16'h0000;
            @(negedge CORE_CLK_INT);
        end
    endtask

    // Take the top byte and advance IP, which is what the EU's opcode fetch
    // strobe does. PFQ_TOP_BYTE is pipelined a clock behind the queue, so the
    // byte is read before the strobe rather than after it.
    task automatic pfq_take(output logic [7:0] b);
        integer guard;
        begin
            guard = 0;
            while (PFQ_EMPTY && (guard < 20000)) begin
                @(posedge CORE_CLK_INT); #1; guard = guard + 1;
            end
            repeat (3) @(posedge CORE_CLK_INT);
            b = PFQ_TOP_BYTE;
            @(negedge CORE_CLK_INT);
            EU_BIU_COMMAND = CMD_FETCH_STROBE;
            @(negedge CORE_CLK_INT);
            EU_BIU_COMMAND = 16'h0000;
            @(negedge CORE_CLK_INT);
        end
    endtask

    // Wait until the bus has been passive for long enough that nothing more is
    // coming. A prefetch that is going to happen starts within a bus cycle.
    //
    // Bounded, and it says so when it gives up. A queue that never reports full
    // prefetches for ever, and an unbounded wait would turn that into a bare
    // simulation timeout - which names no property and points at no line.
    task automatic wait_bus_quiet;
        integer quiet;
        integer budget;
        begin
            quiet  = 0;
            budget = 0;
            while ((quiet < 400) && (budget < 100000)) begin
                @(posedge CORE_CLK_INT); #1;
                budget = budget + 1;
                if (S2_S0_OUT != ST_PASSIVE) quiet = 0;
                else                         quiet = quiet + 1;
            end
            if (quiet < 400)
                fail_msg("the bus never went quiet - something is driving cycles for ever");
        end
    endtask

    //------------------------------------------------------------------------
    // The queue's whole contract, at whatever depth is currently selected.
    //------------------------------------------------------------------------
    // With the EU consuming nothing, prefetch must run until the queue is full
    // and then leave the bus alone: a queue that never reports full fetches for
    // ever, and one that reports full early starves the EU. Then every byte has
    // to come back, in order, from where it was fetched.
    //
    // The depth is the one number the eight-entry rework was for, so it is
    // checked at both - four as an 8088 and six as an 8086 - from the same code.
    // If this fails with a number that is neither, the full/empty scheme is
    // wrong rather than the depth.
    task automatic check_queue_depth(input logic [15:0] cs_val,
                                     input logic [15:0] target,
                                     input integer      depth,
                                     input string       who);
        integer k, m, fails_before;
        logic [19:0] want;
        logic [7:0]  b;
        begin
            fails_before = fail_count;

            load_cs(cs_val);
            wait_bus_quiet;
            eu_request(5'h19, 2'b10, target, $sformatf("%s: jump", who));
            log_clear;
            wait_bus_quiet;

            // Wide fetches bring back two bytes per cycle, so counting FETCH
            // bus cycles only equals byte count while every cycle here is
            // narrow - true for the 8088 cases and for the 8086 depth check,
            // which runs before any wide fetch in this file has had a chance
            // to fire. check_word_fetch, below, is the version of this
            // property for a wide cycle.
            m = 0;
            for (k = 0; k < log_count; k = k + 1)
                if (log_status[k] === ST_FETCH) m = m + 1;

            if (m != depth)
                fail_msg($sformatf("%s: queue took %0d fetches before going quiet, expected %0d",
                                   who, m, depth));
            else
                pass_msg($sformatf("%s: prefetch fills %0d bytes and then stops", who, depth));

            m = 0;
            for (k = 0; k < log_count; k = k + 1) begin
                if (log_status[k] === ST_FETCH) begin
                    want = {cs_val, 4'h0} + {4'h0, target} + m[19:0];
                    if (log_addr[k] !== want)
                        fail_msg($sformatf("%s: fetch %0d from %05h, expected %05h",
                                           who, m, log_addr[k], want));
                    m = m + 1;
                end
            end
            if (fail_count == fails_before)
                pass_msg($sformatf("%s: prefetch runs consecutively from the jump target", who));

            fails_before = fail_count;
            for (k = 0; k < depth; k = k + 1) begin
                want = {cs_val, 4'h0} + {4'h0, target} + k[19:0];
                pfq_take(b);
                if (b !== mem_byte(want))
                    fail_msg($sformatf("%s: queue byte %0d was %02h, memory at %05h holds %02h",
                                       who, k, b, want, mem_byte(want)));
            end
            if (fail_count == fails_before)
                pass_msg($sformatf("%s: the EU reads the queue back in program order", who));

            repeat (5) @(posedge CORE_CLK_INT);
            if (PFQ_ADDR_OUT !== target + depth[15:0])
                fail_msg($sformatf("%s: IP is %04h after %0d bytes, expected %04h",
                                   who, PFQ_ADDR_OUT, depth, target + depth[15:0]));
            else
                pass_msg($sformatf("%s: IP advanced one byte per opcode fetch strobe", who));
        end
    endtask

    // One wide - or deliberately narrow - prefetch cycle, checked at the
    // address and shape (log_wide) the case names. Used both for the ordinary
    // case (an even, in-range target: one cycle, both bytes) and for the
    // static-range boundary (docs/8086-adaptation.md, step 4: word_fetch_ok is
    // a fixed range rather than a live memory-map decode, and this is where
    // that boundary is pinned).
    task automatic check_word_fetch(input logic [15:0] target,
                                    input bit           expect_wide,
                                    input string        label);
        logic [19:0] want_addr;
        begin
            wait_bus_quiet;
            eu_request(5'h19, 2'b10, target, $sformatf("%s: jump", label));
            log_clear;
            wait_bus_quiet;

            want_addr = 20'hFFFF0 + {4'h0, target};

            if (log_count < 1)
                fail_msg($sformatf("%s: no fetch at all", label));
            else if (log_status[0] !== ST_FETCH)
                fail_msg($sformatf("%s: first cycle is not a fetch", label));
            else if (log_addr[0] !== want_addr)
                fail_msg($sformatf("%s: fetch from %05h, expected %05h",
                                   label, log_addr[0], want_addr));
            else if (log_wide[0] !== expect_wide)
                fail_msg($sformatf("%s: fetch at %05h was %s, expected %s",
                                   label, log_addr[0],
                                   log_wide[0] ? "wide" : "narrow",
                                   expect_wide  ? "wide" : "narrow"));
            else
                pass_msg($sformatf("%s: %s cycle at %05h", label,
                                   expect_wide ? "one wide" : "a narrow", log_addr[0]));
        end
    endtask

    // Same property as check_word_fetch, at an explicit CS - for the two
    // boundary cases (0A0000h, 0F0000h) that CS=FFFF's 16-bit reachable range
    // cannot reach at all.
    task automatic check_word_fetch_at(input logic [15:0] cs_val,
                                       input logic [15:0] target,
                                       input bit           expect_wide,
                                       input string        label);
        logic [19:0] want_addr;
        begin
            load_cs(cs_val);
            wait_bus_quiet;
            eu_request(5'h19, 2'b10, target, $sformatf("%s: jump", label));
            log_clear;
            wait_bus_quiet;

            want_addr = {cs_val, 4'h0} + {4'h0, target};

            if (log_count < 1)
                fail_msg($sformatf("%s: no fetch at all", label));
            else if (log_status[0] !== ST_FETCH)
                fail_msg($sformatf("%s: first cycle is not a fetch", label));
            else if (log_addr[0] !== want_addr)
                fail_msg($sformatf("%s: fetch from %05h, expected %05h",
                                   label, log_addr[0], want_addr));
            else if (log_wide[0] !== expect_wide)
                fail_msg($sformatf("%s: fetch at %05h was %s, expected %s",
                                   label, log_addr[0],
                                   log_wide[0] ? "wide" : "narrow",
                                   expect_wide  ? "wide" : "narrow"));
            else
                pass_msg($sformatf("%s: %s cycle at %05h", label,
                                   expect_wide ? "one wide" : "a narrow", log_addr[0]));
        end
    endtask

    // Step 5 data-path checks. The caller establishes DS; linear is kept
    // independent of the DUT so an address-generation bug cannot make both
    // the request and its expected answer agree by accident.
    task automatic check_data_word_read(input logic [4:0]  code,
                                        input logic [15:0] offset,
                                        input logic [19:0] linear,
                                        input integer      expected_cycles,
                                        input bit          expected_request,
                                        input string       label);
        integer k, first, failures_before;
        logic [15:0] expected_word;
        begin
            failures_before = fail_count;
            expected_word = {mem_byte(linear + 20'd1), mem_byte(linear)};
            wait_bus_quiet;
            log_clear;
            eu_request(code, 2'b11, offset, label);
            wait_bus_quiet;

            k = 0;
            first = -1;
            for (integer j = 0; j < log_count; j = j + 1) begin
                if (log_status[j] === ST_MEMR) begin
                    if (first == -1) first = j;
                    if (log_addr[j] !== (linear + k[19:0]))
                        fail_msg($sformatf("%s: cycle %0d addressed %05h, expected %05h",
                                           label, k, log_addr[j], linear + k[19:0]));
                    k = k + 1;
                end
            end
            if (k != expected_cycles)
                fail_msg($sformatf("%s: used %0d memory cycles, expected %0d",
                                   label, k, expected_cycles));
            else if ((first == -1) || (log_wide[first] !== expected_request))
                fail_msg($sformatf("%s: wide request was %b, expected %b",
                                   label, (first == -1) ? 1'bx : log_wide[first], expected_request));
            if (BIU_RETURN_DATA !== expected_word)
                fail_msg($sformatf("%s: returned %04h, memory holds %04h",
                                   label, BIU_RETURN_DATA, expected_word));
            if (fail_count == failures_before)
                pass_msg($sformatf("%s: %0d cycle(s), data %04h", label,
                                   expected_cycles, expected_word));
        end
    endtask

    task automatic check_data_word_write(input logic [4:0]  code,
                                         input logic [15:0] offset,
                                         input logic [19:0] linear,
                                         input logic [15:0] value,
                                         input integer      expected_cycles,
                                         input bit          expected_request,
                                         input string       label);
        integer k, first, failures_before;
        begin
            failures_before = fail_count;
            wait_bus_quiet;
            log_clear;
            EU_BIU_DATAOUT = value;
            eu_request(code, 2'b11, offset, label);
            wait_bus_quiet;

            k = 0;
            first = -1;
            for (integer j = 0; j < log_count; j = j + 1) begin
                if (log_status[j] === ST_MEMW) begin
                    if (first == -1) first = j;
                    if (log_addr[j] !== (linear + k[19:0]))
                        fail_msg($sformatf("%s: cycle %0d addressed %05h, expected %05h",
                                           label, k, log_addr[j], linear + k[19:0]));
                    if ((expected_cycles == 2)
                        && (log_data[j] !== ((k == 0) ? value[7:0] : value[15:8])))
                        fail_msg($sformatf("%s: cycle %0d drove %02h", label, k, log_data[j]));
                    k = k + 1;
                end
            end
            if (k != expected_cycles)
                fail_msg($sformatf("%s: used %0d memory cycles, expected %0d",
                                   label, k, expected_cycles));
            else if ((first == -1) || (log_wide_write[first] !== expected_request))
                fail_msg($sformatf("%s: wide write request was %b, expected %b",
                                   label, (first == -1) ? 1'bx : log_wide_write[first], expected_request));
            else if (expected_request) begin
                if (log_word_out[first] !== value)
                    fail_msg($sformatf("%s: private word bus drove %04h, expected %04h",
                                       label, log_word_out[first], value));
            end
            if (fail_count == failures_before)
                pass_msg($sformatf("%s: %0d cycle(s), data %04h", label,
                                   expected_cycles, value));
        end
    endtask

    //------------------------------------------------------------------------
    integer i;
    integer n;
    logic [7:0]  got;
    logic [19:0] want_addr;
    integer      seen;
    integer      plain_read_len = 0;

    initial begin
        $display("");
        $display("=== what the BIU does on the bus ===");
        $display("");

        repeat (10) @(posedge CORE_CLK_INT);
        @(negedge CORE_CLK_INT);
        RESET_INT = 1'b0;

        //--------------------------------------------------------------------
        // 1. Reset state, and the first thing it does
        //--------------------------------------------------------------------
        // CS resets to FFFF and IP to 0000, so the first code fetch is from
        // FFFF0 - the reset vector, and the one address in the map that has to
        // be right or nothing else in this file matters.
        wait_bus_quiet;
        if (BIU_REGISTER_CS !== 16'hFFFF)
            fail_msg($sformatf("CS resets to %04h, expected FFFF", BIU_REGISTER_CS));
        else
            pass_msg("CS resets to FFFF");

        if (log_count == 0)
            fail_msg("no bus cycle at all after reset");
        else if (log_status[0] !== ST_FETCH)
            fail_msg($sformatf("first cycle status %03b, expected a code fetch",
                               log_status[0]));
        else if (log_addr[0] !== 20'hFFFF0)
            fail_msg($sformatf("first fetch from %05h, expected FFFF0", log_addr[0]));
        else
            pass_msg("first bus cycle is a code fetch from FFFF0");

        //--------------------------------------------------------------------
        // 2 and 3. The queue fills, stops, and comes back in order
        //--------------------------------------------------------------------
        check_queue_depth(16'hFFFF, 16'h0100, PFQ_DEPTH_8088, "8088");

        //--------------------------------------------------------------------
        // 4. A jump flushes the queue
        //--------------------------------------------------------------------
        // Both pointers are reloaded, so the queue is empty and the next fetch
        // comes from the new address. A flush that only moved the read pointer
        // would hand the EU bytes from the old path, which is the failure that
        // does not announce itself.
        wait_bus_quiet;
        eu_request(5'h19, 2'b10, 16'h0500, "jump to 0500");
        log_clear;
        @(posedge CORE_CLK_INT); #1;
        if (!PFQ_EMPTY)
            fail_msg("queue not empty immediately after a jump");
        else
            pass_msg("a jump empties the queue at once");

        wait_bus_quiet;
        if (log_count == 0)
            fail_msg("no prefetch after the jump");
        else if (log_addr[0] !== 20'hFFFF0 + 20'h0500)
            fail_msg($sformatf("first fetch after the jump from %05h, expected %05h",
                               log_addr[0], 20'hFFFF0 + 20'h0500));
        else
            pass_msg("the first fetch after a jump is from the new address");

        //--------------------------------------------------------------------
        // 5. Taking one byte lets exactly one more in
        //--------------------------------------------------------------------
        log_clear;
        pfq_take(got);
        wait_bus_quiet;
        n = 0;
        for (i = 0; i < log_count; i = i + 1)
            if (log_status[i] === ST_FETCH) n = n + 1;
        if (n != 1)
            fail_msg($sformatf("one byte consumed caused %0d fetches, expected 1", n));
        else
            pass_msg("the queue refills one byte for each one taken");

        //--------------------------------------------------------------------
        // 6. A memory byte read
        //--------------------------------------------------------------------
        wait_bus_quiet;
        log_clear;
        eu_request(5'h0C, 2'b11, 16'h1234, "byte read DS:1234");
        wait_bus_quiet;

        n = -1;
        for (i = 0; i < log_count; i = i + 1)
            if ((log_status[i] === ST_MEMR) && (n == -1)) n = i;

        if (n == -1)
            fail_msg("byte read issued no memory read cycle");
        else if (log_addr[n] !== 20'h01234)
            fail_msg($sformatf("byte read addressed %05h, expected 01234 (DS=0)",
                               log_addr[n]));
        else if (BIU_RETURN_DATA[7:0] !== mem_byte(20'h01234))
            fail_msg($sformatf("byte read returned %02h, memory holds %02h",
                               BIU_RETURN_DATA[7:0], mem_byte(20'h01234)));
        else begin
            plain_read_len = log_len[n];
            pass_msg($sformatf("a byte read is one memory cycle at the right address (%0d core clocks)",
                               plain_read_len));
        end

        //--------------------------------------------------------------------
        // 7. A word read is two byte cycles, and this is what step 5 changes
        //--------------------------------------------------------------------
        // On an 8088 every word access is split, whatever the alignment. The
        // count here is the thing the 16-bit path is for: after step 5 an even
        // address must produce ONE cycle and an odd one must still produce two.
        wait_bus_quiet;
        log_clear;
        eu_request(5'h10, 2'b11, 16'h2000, "word read DS:2000, even");
        wait_bus_quiet;

        n = 0;
        for (i = 0; i < log_count; i = i + 1)
            if (log_status[i] === ST_MEMR) n = n + 1;

        if (n != 2)
            fail_msg($sformatf("even word read took %0d memory cycles, expected 2", n));
        else
            pass_msg("an even word read is two byte cycles on an 8088");

        if (BIU_RETURN_DATA !== {mem_byte(20'h02001), mem_byte(20'h02000)})
            fail_msg($sformatf("word read returned %04h, memory holds %04h",
                               BIU_RETURN_DATA,
                               {mem_byte(20'h02001), mem_byte(20'h02000)}));
        else
            pass_msg("the word is assembled low byte first");

        //--------------------------------------------------------------------
        // 8. The second half wraps inside the segment
        //--------------------------------------------------------------------
        // A word at offset FFFF takes its high byte from offset 0000 of the
        // same segment, not from the next paragraph. Already true here because
        // the offset register is 16 bits and simply increments, but it is worth
        // a case: it is the one piece of address arithmetic that steps 4 and 5
        // could quietly widen.
        wait_bus_quiet;
        log_clear;
        eu_request(5'h10, 2'b11, 16'hFFFF, "word read DS:FFFF");
        wait_bus_quiet;

        n = 0;
        for (i = 0; i < log_count; i = i + 1) begin
            if (log_status[i] === ST_MEMR) begin
                want_addr = (n == 0) ? 20'h0FFFF : 20'h00000;
                if (log_addr[i] !== want_addr)
                    fail_msg($sformatf("wrapping word, cycle %0d addressed %05h, expected %05h",
                                       n, log_addr[i], want_addr));
                n = n + 1;
            end
        end
        if (n != 2)
            fail_msg($sformatf("wrapping word read took %0d cycles, expected 2", n));
        else
            pass_msg("a word at offset FFFF wraps inside the segment");

        //--------------------------------------------------------------------
        // 9. Wait states
        //--------------------------------------------------------------------
        // READY low holds the cycle open. The data must still be right, and the
        // cycle must be longer - a BIU that ignored READY would pass the first
        // half of this and fail the second.
        wait_bus_quiet;
        log_clear;
        fork
            begin
                eu_request(5'h0C, 2'b11, 16'h3456, "byte read with wait states");
            end
            begin
                // Hold READY low across the middle of the cycle.
                @(negedge CORE_CLK_INT);
                while (S2_S0_OUT == ST_PASSIVE) @(negedge CORE_CLK_INT);
                READY_IN = 1'b0;
                repeat (60) @(negedge CORE_CLK_INT);
                READY_IN = 1'b1;
            end
        join
        wait_bus_quiet;

        // Correct data alone would pass on a BIU that ignored READY entirely,
        // because the memory model here answers whether it was asked to wait or
        // not. The length is the half of this that tests READY.
        n = -1;
        for (i = 0; i < log_count; i = i + 1)
            if ((log_status[i] === ST_MEMR) && (n == -1)) n = i;

        if (BIU_RETURN_DATA[7:0] !== mem_byte(20'h03456))
            fail_msg($sformatf("read with wait states returned %02h, memory holds %02h",
                               BIU_RETURN_DATA[7:0], mem_byte(20'h03456)));
        else if (n == -1)
            fail_msg("read with wait states issued no memory cycle");
        else if (log_len[n] <= plain_read_len)
            fail_msg($sformatf("READY held low for 60 clocks but the cycle took %0d, same as the %0d it takes unobstructed - READY is being ignored",
                               log_len[n], plain_read_len));
        else
            pass_msg($sformatf("wait states hold the cycle open (%0d core clocks against %0d) without corrupting it",
                               log_len[n], plain_read_len));

        //--------------------------------------------------------------------
        // 10. A memory byte write puts the right byte at the right address
        //--------------------------------------------------------------------
        wait_bus_quiet;
        log_clear;
        EU_BIU_DATAOUT = 16'h9C5E;
        eu_request(5'h0E, 2'b11, 16'h4321, "byte write DS:4321");
        wait_bus_quiet;

        n = -1;
        for (i = 0; i < log_count; i = i + 1)
            if ((log_status[i] === ST_MEMW) && (n == -1)) n = i;

        if (n == -1)
            fail_msg("byte write issued no memory write cycle");
        else if (log_addr[n] !== 20'h04321)
            fail_msg($sformatf("byte write addressed %05h, expected 04321", log_addr[n]));
        else if (log_data[n] !== 8'h5E)
            fail_msg($sformatf("byte write put %02h on the bus, expected 5E", log_data[n]));
        else
            pass_msg("a byte write drives the low byte at the right address");

        //--------------------------------------------------------------------
        // 11. A data cycle takes the bus from prefetch
        //--------------------------------------------------------------------
        // The EU's request is dispatched from the idle state ahead of the
        // prefetch, so a starved queue can never lock the EU out. Consume the
        // queue empty, then ask for data and check the data cycle happens.
        wait_bus_quiet;
        eu_request(5'h19, 2'b10, 16'h0800, "jump to 0800");
        wait_bus_quiet;
        log_clear;
        eu_request(5'h0C, 2'b11, 16'h5678, "data read while prefetching");

        n = -1;
        for (i = 0; i < log_count; i = i + 1)
            if ((log_status[i] === ST_MEMR) && (n == -1)) n = i;
        if (n == -1)
            fail_msg("the data read never reached the bus");
        else if (log_addr[n] !== 20'h05678)
            fail_msg($sformatf("data read addressed %05h, expected 05678", log_addr[n]));
        else
            pass_msg("an EU request is served ahead of prefetch");

        //--------------------------------------------------------------------
        // 12. The same queue as an 8086
        //--------------------------------------------------------------------
        // Six bytes rather than four, from the same pointers and the same
        // eight entries. This is the whole of step 3: nothing else about the
        // BIU changes with IS8086 yet, so every case above must hold here too -
        // which is why it runs last, after they have all been checked at four.
        wait_bus_quiet;
        IS8086 = 1'b1;
        // 0xB0C00 is inside 0A0000-0EFFF: word_fetch_ok is false there, so
        // this stays a narrow, one-byte-per-cycle fetch and the depth/index
        // scheme is what is being checked, not step 4's wide path.
        check_queue_depth(16'hB000, 16'h0C00, PFQ_DEPTH_8086, "8086");
        load_cs(16'hFFFF);   // check_word_fetch below assumes CS=FFFF, as the earlier cases do
        wait_bus_quiet;

        //--------------------------------------------------------------------
        // 13. Word-aligned prefetch (step 4)
        //--------------------------------------------------------------------
        check_word_fetch(16'h0D00, 1'b1, "even target, in range");

        // check_word_fetch only checks the bus - address and shape. The
        // content still has to be right in both halves, in order: pfq_take
        // the two bytes a wide fetch just brought back and compare them
        // against memory directly, the same way check_queue_depth does for
        // the narrow path.
        n = fail_count;
        pfq_take(got);
        if (got !== mem_byte(20'hFFFF0 + 20'h0D00))
            fail_msg($sformatf("wide fetch content: low byte was %02h, memory at %05h holds %02h",
                               got, 20'hFFFF0 + 20'h0D00, mem_byte(20'hFFFF0 + 20'h0D00)));
        pfq_take(got);
        if (got !== mem_byte(20'hFFFF0 + 20'h0D01))
            fail_msg($sformatf("wide fetch content: high byte was %02h, memory at %05h holds %02h",
                               got, 20'hFFFF0 + 20'h0D01, mem_byte(20'hFFFF0 + 20'h0D01)));
        if (fail_count == n)
            pass_msg("wide fetch: both bytes land in the queue in order");

        // A jump to an odd target cannot start wide - the pointer is odd - so
        // the first fetch is a single byte, which is what realigns it. The
        // second is even and must be wide again. This is the vx0_biu.c
        // mechanic docs/8086-adaptation.md section 2.3 says to carry across.
        wait_bus_quiet;
        eu_request(5'h19, 2'b10, 16'h0D01, "jump to odd target");
        log_clear;
        wait_bus_quiet;

        if (log_count < 2)
            fail_msg("odd target: fewer than two fetches seen");
        else if (log_status[0] !== ST_FETCH)
            fail_msg("odd target: first cycle is not a fetch");
        else if (log_wide[0])
            fail_msg($sformatf("odd target: first fetch from %05h was wide, expected a realigning byte",
                               log_addr[0]));
        else if (log_addr[0] !== (20'hFFFF0 + 20'h0D01))
            fail_msg($sformatf("odd target: first fetch from %05h, expected %05h",
                               log_addr[0], 20'hFFFF0 + 20'h0D01));
        else if (log_status[1] !== ST_FETCH)
            fail_msg("odd target: second cycle is not a fetch");
        else if (log_addr[1] !== (20'hFFFF0 + 20'h0D02))
            fail_msg($sformatf("odd target: second fetch from %05h, expected %05h",
                               log_addr[1], 20'hFFFF0 + 20'h0D02));
        else if (!log_wide[1])
            fail_msg("odd target: second fetch was narrow, expected wide once realigned");
        else
            pass_msg("odd target: one realigning byte, then wide from the next even address");

        // The static range itself, pinned at both edges. word_fetch_ok is
        // deliberately NOT a live memory-map decode (see the comment beside it
        // in mcl86_biu_max.sv), so this is checking a fixed boundary, not
        // Chipset's runtime state.
        //
        // A jump offset from CS=FFFF cannot reach here at all - the reachable
        // range is [0,0FFEFh] union [FFFF0h,FFFFFh] - so these load CS
        // directly instead, and restore it to FFFF afterwards since every
        // check from here on assumes it.
        check_word_fetch_at(16'h9FFE, 16'h0000, 1'b1, "09FFE0: just below the excluded range");
        check_word_fetch_at(16'hA000, 16'h0000, 1'b0, "0A0000: start of the excluded range");
        check_word_fetch_at(16'hEFFE, 16'h0000, 1'b0, "0EFFE0: still inside the excluded range");
        check_word_fetch_at(16'hF000, 16'h0000, 1'b1, "0F0000: BIOS region, wide again");
        load_cs(16'hFFFF);
        wait_bus_quiet;

        // Room for only one more byte forces a narrow fetch even at an even,
        // in-range target - the room-for-two check in mcl86_biu_max.sv, and
        // the one place a depth-vs-index off-by-one would show up as silently
        // corrupted queue contents rather than a clean failure.
        wait_bus_quiet;
        eu_request(5'h19, 2'b10, 16'h0E00, "jump to 0E00 (fills wide, 6 bytes)");
        wait_bus_quiet;
        pfq_take(got);   // take one byte: 5 held, 1 free - room for one, not two
        log_clear;
        wait_bus_quiet;
        if (log_count < 1)
            fail_msg("one free slot: no fetch at all");
        else if (log_status[0] !== ST_FETCH)
            fail_msg("one free slot: first cycle is not a fetch");
        else if (log_wide[0])
            fail_msg($sformatf("one free slot: fetch from %05h was wide with room for only one byte",
                               log_addr[0]));
        else
            pass_msg("one free slot forces a narrow fetch, even in range and even-aligned");

        //--------------------------------------------------------------------
        // 14. Even 8086 data words use one private SDRAM cycle (step 5)
        //--------------------------------------------------------------------
        load_ds(16'h0000);
        check_data_word_read (5'h10, 16'h2200, 20'h02200, 1, 1'b1, "8086 even word read");
        check_data_word_read (5'h10, 16'h2201, 20'h02201, 2, 1'b0, "8086 odd word read");
        check_data_word_write(5'h13, 16'h2400, 20'h02400, 16'h9C5E, 1, 1'b1, "8086 even word write");
        check_data_word_write(5'h13, 16'h2401, 20'h02401, 16'hA73D, 2, 1'b0, "8086 odd word write");

        // The odd fallback still wraps its second offset inside the segment.
        wait_bus_quiet;
        log_clear;
        EU_BIU_DATAOUT = 16'h6E2A;
        eu_request(5'h13, 2'b11, 16'hFFFF, "8086 wrapping word write");
        wait_bus_quiet;
        n = 0;
        for (i = 0; i < log_count; i = i + 1) begin
            if (log_status[i] === ST_MEMW) begin
                want_addr = (n == 0) ? 20'h0FFFF : 20'h00000;
                if (log_addr[i] !== want_addr)
                    fail_msg($sformatf("wrapping write cycle %0d addressed %05h, expected %05h",
                                       n, log_addr[i], want_addr));
                if (log_wide_write[i])
                    fail_msg("odd wrapping write asserted the private word request");
                if (log_data[i] !== ((n == 0) ? 8'h2A : 8'h6E))
                    fail_msg($sformatf("wrapping write cycle %0d drove %02h", n, log_data[i]));
                n = n + 1;
            end
        end
        if (n != 2)
            fail_msg($sformatf("wrapping word write used %0d cycles, expected 2", n));
        else
            pass_msg("8086 odd word write wraps inside the segment");

        // Every memory-word command variant has its own BIU dispatch arm.
        // Exercise the SS-forced and interrupt-vector forms so a candidate
        // added to only the common DS forms cannot pass unnoticed.
        load_ss(16'h0100);
        check_data_word_read (5'h11, 16'h0200, 20'h01200, 1, 1'b1, "8086 SS word read");
        check_data_word_write(5'h14, 16'h0400, 20'h01400, 16'h5AC7, 1, 1'b1, "8086 SS word write");
        check_data_word_read (5'h12, 16'h0180, 20'h00180, 1, 1'b1, "8086 vector word read");
        load_ss(16'h0000);

        // An even offset is necessary, not sufficient. Video memory is still
        // on the byte bus, so the address decode rejects the candidate and
        // the BIU executes the original two cycles.
        load_ds(16'hA000);
        check_data_word_read (5'h10, 16'h0100, 20'hA0100, 2, 1'b1, "8086 even video word read");
        check_data_word_write(5'h13, 16'h0200, 20'hA0200, 16'hB649, 2, 1'b1, "8086 even video word write");
        load_ds(16'h0000);

        // I/O deliberately remains an XT-class 8-bit bus even in 8086 mode.
        wait_bus_quiet;
        log_clear;
        eu_request(5'h1A, 2'b11, 16'h0300, "8086 I/O word read");
        wait_bus_quiet;
        n = 0;
        for (i = 0; i < log_count; i = i + 1) begin
            if (log_status[i] === ST_IOR) begin
                if (log_wide[i])
                    fail_msg("8086 I/O word read asserted the private RAM word request");
                n = n + 1;
            end
        end
        if (n != 2)
            fail_msg($sformatf("8086 I/O word read used %0d cycles, expected 2", n));
        else
            pass_msg("8086 I/O word read remains two byte cycles");

        wait_bus_quiet;
        log_clear;
        EU_BIU_DATAOUT = 16'h8D34;
        eu_request(5'h1C, 2'b11, 16'h0300, "8086 I/O word write");
        wait_bus_quiet;
        n = 0;
        for (i = 0; i < log_count; i = i + 1) begin
            if (log_status[i] === ST_IOW) begin
                if (log_wide_write[i])
                    fail_msg("8086 I/O word write asserted the private RAM word request");
                if (log_data[i] !== ((n == 0) ? 8'h34 : 8'h8D))
                    fail_msg($sformatf("8086 I/O write cycle %0d drove %02h", n, log_data[i]));
                n = n + 1;
            end
        end
        if (n != 2)
            fail_msg($sformatf("8086 I/O word write used %0d cycles, expected 2", n));
        else
            pass_msg("8086 I/O word write remains two byte cycles");

        IS8086 = 1'b0;

        // Switching back must restore the old data-bus shape as well as the
        // queue depth. These are even addresses which were wide immediately
        // above, so two cycles here specifically prove IS8086 is still live.
        check_data_word_read (5'h10, 16'h2600, 20'h02600, 2, 1'b0, "8088 even word read");
        check_data_word_write(5'h13, 16'h2800, 20'h02800, 16'hD21B, 2, 1'b0, "8088 even word write");

        // And back again, because the depth is a runtime input rather than a
        // parameter: an 8086 that leaves the queue six deep after switching
        // back would be an 8088 that runs ahead of itself.
        wait_bus_quiet;
        check_queue_depth(16'hFFFF, 16'h0E00, PFQ_DEPTH_8088, "8088 again");

        //--------------------------------------------------------------------
        $display("");
        $display("%0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0) $display("RESULT: PASS");
        else                 $display("RESULT: FAIL");
        $display("");
        $finish;
    end

    initial begin
        #20_000_000;
        $display("  FAIL  timeout");
        $display("RESULT: FAIL");
        $finish;
    end

endmodule
