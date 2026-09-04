//============================================================================
//
//  Step 4 integration: BIU -> RAM.sv -> SDRAM model -> BIU.
//
//  biu_prefetch_tb proves the BIU asks for and queues a word.  ram_lookahead_tb
//  proves RAM.sv returns one.  This bench proves that the two independently
//  tested halves still agree when connected as they are at the top level.
//  In particular it catches a disconnected WORD_READ_REQUEST, swapped word
//  lanes, or a word path accidentally gated by the byte-lookahead speed gate.
//
//============================================================================

`timescale 1ns / 1ps

module biu_ram_prefetch_tb;

    localparam logic [2:0] ST_PASSIVE = 3'b111;
    localparam logic [2:0] ST_FETCH   = 3'b100;
    localparam logic [2:0] ST_MEMR    = 3'b101;
    localparam logic [2:0] ST_MEMW    = 3'b110;

    logic core_clock = 1'b0;
    logic ram_clock  = 1'b0;
    logic biu_reset  = 1'b1;
    logic ram_reset  = 1'b1;
    always #5  core_clock = ~core_clock;
    always #10 ram_clock  = ~ram_clock;

    wire cpu_clock;
    wire cpu_ce_posedge, cpu_ce_negedge;
    wire cycle_accurate, shift_read_timing;
    wire [7:0] counter_division, counter_decrement;
    wire [1:0] ram_read_wait_cycle, ram_write_wait_cycle;
    logic [1:0] selected_clk = 2'b11;

    // Use the design's own clock generator for every selectable speed. Besides
    // making the CPU pin clock realistic, this supplies the exact fractional
    // CE pulses, delayed read-sampling selection and RAM wait count used on
    // hardware.  In particular, 9.54 MHz must not be approximated by a simple
    // periodic testbench clock: its 21/55 edge cadence is the property under
    // test here.
    XT_CE_Generator clock_generator (
        .clock(ram_clock), .reset(ram_reset), .clk_select_load(1'b1),
        .clk_select(selected_clk), .cpu_clk_pin(cpu_clock),
        .cpu_ce_posedge(cpu_ce_posedge), .cpu_ce_negedge(cpu_ce_negedge),
        .peripheral_ce(), .cycle_accrate(cycle_accurate),
        .clock_cycle_counter_division_ratio(counter_division),
        .clock_cycle_counter_decrement_value(counter_decrement),
        .shift_read_timing(shift_read_timing),
        .ram_read_wait_cycle(ram_read_wait_cycle),
        .ram_write_wait_cycle(ram_write_wait_cycle)
    );

    logic [15:0] eu_command = 16'h0000;
    logic [15:0] eu_dataout = 16'h0000;
    logic [15:0] eu_r3      = 16'h0000;

    wire        lock_n, ad_oe, s6_3_mux;
    wire [19:0] ad_out;
    wire [7:0]  ad_in;
    wire [2:0]  status;
    wire        biu_done;
    wire [7:0]  pfq_top_byte;
    wire        pfq_empty;
    wire [15:0] pfq_addr_out;
    wire [15:0] biu_cs;
    wire [15:0] biu_return_data;
    wire        word_read_request;
    wire        word_write_request;
    wire [15:0] data_bus_word_out;
    wire [15:0] data_bus_word;

    // The CPU side is deliberately a BIU-only harness: the integration being
    // checked is the new private 16-bit read path, not EU microcode.
    mcl86_biu_max biu (
        .CORE_CLK_INT(core_clock), .RESET_INT(biu_reset), .CLK(cpu_clock),
        .READY_IN(processor_ready), .NMI(1'b0), .INTR(1'b0),
        .LOCK_n(lock_n), .AD_OE(ad_oe), .AD_OUT(ad_out), .AD_IN(ad_in),
        .S6_3_MUX(s6_3_mux), .S2_S0_OUT(status),
        .EU_BIU_COMMAND(eu_command), .EU_BIU_DATAOUT(eu_dataout),
        .EU_REGISTER_R3(eu_r3), .EU_PREFIX_LOCK(1'b0), .BIU_DONE(biu_done),
        .BIU_CLK_COUNTER_ZERO(), .BIU_SEGMENT(), .BIU_NMI_CAUGHT(),
        .BIU_NMI_DEBOUNCE(1'b0), .BIU_INTR(), .PFQ_TOP_BYTE(pfq_top_byte),
        .PFQ_EMPTY(pfq_empty), .PFQ_ADDR_OUT(pfq_addr_out),
        .BIU_REGISTER_ES(), .BIU_REGISTER_SS(), .BIU_REGISTER_CS(biu_cs),
        .BIU_REGISTER_DS(), .BIU_REGISTER_RM(), .BIU_REGISTER_REG(),
        .BIU_RETURN_DATA(biu_return_data),
        .clock_cycle_counter_division_ratio(counter_division),
        .clock_cycle_counter_decrement_value(counter_decrement),
        .shift_read_timing(shift_read_timing),
        .IS8086(1'b1), .WORD_READ_REQUEST(word_read_request),
        .WORD_WRITE_REQUEST(word_write_request),
        .DATA_BUS_WORD_OUT(data_bus_word_out), .DATA_BUS_WORD(data_bus_word),
        .WORD_ACCESS_POSSIBLE(~ram_address_select_n)
    );

    // The chipset latches the multiplexed address in T1.  RAM.sv therefore
    // sees an ordinary stable address during the later read part of the cycle.
    logic [19:0] bus_address = 20'h00000;
    always @(posedge core_clock)
        if (ad_oe && !s6_3_mux)
            bus_address <= ad_out;

    wire memory_read_n  = ~((status == ST_FETCH) || (status == ST_MEMR));
    wire memory_write_n = ~(status == ST_MEMW);
    wire no_command_state = memory_read_n & memory_write_n;
    wire processor_ready;

    wire        initialized_sdram;
    wire        memory_access_ready;
    wire        ram_address_select_n;
    wire [7:0]  ram_data_out;
    wire [15:0] ram_data_out_word;
    wire [12:0] sdram_address;
    wire        sdram_cke, sdram_cs, sdram_ras, sdram_cas, sdram_we;
    wire [1:0]  sdram_ba;
    wire [15:0] sdram_dq_in, sdram_dq_out;
    wire        sdram_dq_io, sdram_ldqm, sdram_udqm;
    logic [6:0] map_ems [0:3];

    RAM ram (
        .clock(ram_clock), .reset(ram_reset), .enable_sdram(1'b1),
        .initilized_sdram(initialized_sdram), .address(bus_address),
        .internal_data_bus(ad_out[7:0]), .data_bus_out(ram_data_out),
        .word_read_request(word_read_request), .data_bus_out_word(ram_data_out_word),
        .word_write_request(word_write_request), .data_bus_in_word(data_bus_word_out),
        .memory_read_n(memory_read_n), .memory_write_n(memory_write_n),
        .no_command_state(no_command_state), .memory_access_ready(memory_access_ready),
        .ram_address_select_n(ram_address_select_n), .sdram_address(sdram_address),
        .sdram_cke(sdram_cke), .sdram_cs(sdram_cs), .sdram_ras(sdram_ras),
        .sdram_cas(sdram_cas), .sdram_we(sdram_we), .sdram_ba(sdram_ba),
        .sdram_dq_in(sdram_dq_in), .sdram_dq_out(sdram_dq_out),
        .sdram_dq_io(sdram_dq_io), .sdram_ldqm(sdram_ldqm), .sdram_udqm(sdram_udqm),
        .map_ems(map_ems), .ems_b1(1'b0), .ems_b2(1'b0), .ems_b3(1'b0), .ems_b4(1'b0),
        .tandy_bios_flag(1'b0), .enable_a000h(1'b1),
        .bios_protect_flag(2'b00),
        .wait_count_clk_en(cpu_ce_negedge),
        .ram_read_wait_cycle(ram_read_wait_cycle),
        .ram_write_wait_cycle(ram_write_wait_cycle),
        .clk_select(selected_clk)
    );

    // This is the same READY conditioning stage that sits between RAM and the
    // CPU at the top level.  Wiring RAM's raw ready straight to the BIU makes
    // the byte realignment cycle sample one chipset clock too early; using the
    // real synchroniser is therefore part of the integration property.
    READY ready (
        .clock(ram_clock), .cpu_ce_posedge(cpu_ce_posedge),
        .cpu_ce_negedge(cpu_ce_negedge),
        .reset(ram_reset), .processor_ready(processor_ready), .dma_ready(),
        .dma_wait_n(1'b1), .io_channel_ready(memory_access_ready),
        .io_read_n(1'b1), .io_write_n(1'b1), .memory_read_n(memory_read_n),
        .memory_write_n(memory_write_n), .cga_memory_write_wait(1'b0),
        .dma0_acknowledge_n(1'b1),
        .address_enable_n(1'b1), .clk_select(selected_clk)
    );

    assign ad_in         = ram_data_out;
    assign data_bus_word = ram_data_out_word;

    // A small behavioural SDRAM, lifted in shape from ram_lookahead_tb.  It
    // observes RAM's real pins and has the controller's CAS latency of two.
    localparam integer MEM_WORDS = 8192;
    logic [15:0] memory [0:MEM_WORDS-1];
    logic [12:0] active_row = 13'd0;
    logic [1:0]  active_bank = 2'd0;
    logic [15:0] read_d1 = 16'h0000, read_d2 = 16'h0000;
    integer sdram_activates = 0;
    integer sdram_writes = 0;
    wire cmd_active = ~sdram_cs & ~sdram_ras &  sdram_cas &  sdram_we;
    wire cmd_read   = ~sdram_cs &  sdram_ras & ~sdram_cas &  sdram_we;
    wire cmd_write  = ~sdram_cs &  sdram_ras & ~sdram_cas & ~sdram_we;
    wire [23:0] cmd_address = {active_bank, active_row, sdram_address[8:0]};

    always @(posedge ram_clock) begin
        if (cmd_active) begin
            active_row <= sdram_address;
            active_bank <= sdram_ba;
            sdram_activates <= sdram_activates + 1;
        end
        if (cmd_read)
            read_d1 <= memory[cmd_address[12:0]];
        if (cmd_write && !sdram_ldqm) begin
            memory[cmd_address[12:0]][7:0] <= sdram_dq_out[7:0];
            sdram_writes <= sdram_writes + 1;
        end
        read_d2 <= read_d1;
    end
    assign sdram_dq_in = read_d2;

    function automatic [7:0] expected_byte(input [19:0] address);
        expected_byte = address[7:0] ^ {3'b000, address[12:8]} ^ 8'h5A;
    endfunction

    integer pass_count = 0;
    integer fail_count = 0;
    task automatic fail_msg(input string message);
        begin fail_count = fail_count + 1; $display("  FAIL  %s", message); end
    endtask
    task automatic pass_msg(input string message);
        begin pass_count = pass_count + 1; $display("  PASS  %s", message); end
    endtask

    localparam logic [15:0] CMD_FETCH_STROBE = {2'b00, 2'b01, 2'b00, 1'b0,
                                                  5'h00, 2'b00, 2'b00};
    function automatic [15:0] command_request(input [4:0] code);
        command_request = {2'b00, 2'b00, 2'b10, 1'b1, code, 2'b00, 2'b00};
    endfunction
    function automatic [15:0] data_command_request(input [4:0] code);
        data_command_request = {2'b00, 2'b00, 2'b11, 1'b1, code, 2'b00, 2'b00};
    endfunction

    task automatic wait_bus_quiet;
        integer quiet, guard;
        begin
            quiet = 0; guard = 0;
            while ((quiet < 400) && (guard < 100000)) begin
                @(posedge core_clock); #1; guard = guard + 1;
                if (status == ST_PASSIVE) quiet = quiet + 1;
                else                      quiet = 0;
            end
            if (quiet < 400) fail_msg("bus did not become quiet");
        end
    endtask

    task automatic data_request(input [4:0] code, input [15:0] offset,
                                input string label);
        integer guard;
        begin
            @(negedge core_clock);
            eu_r3 = offset;
            eu_command = data_command_request(code);
            guard = 0;
            while (!biu_done && (guard < 20000)) begin
                @(posedge core_clock); #1; guard = guard + 1;
            end
            if (!biu_done) fail_msg($sformatf("%s: request never completed", label));
            @(negedge core_clock); eu_command = 16'h0000;
            @(negedge core_clock);
        end
    endtask

    task automatic jump_to(input [15:0] target, input string label);
        integer guard;
        begin
            @(negedge core_clock);
            eu_r3 = target;
            eu_command = command_request(5'h19);
            guard = 0;
            while (!biu_done && (guard < 20000)) begin
                @(posedge core_clock); #1; guard = guard + 1;
            end
            if (!biu_done) fail_msg($sformatf("%s: jump never completed", label));
            @(negedge core_clock); eu_command = 16'h0000;
            @(negedge core_clock);
        end
    endtask

    task automatic take_byte(output logic [7:0] value);
        integer guard;
        begin
            guard = 0;
            while (pfq_empty && (guard < 20000)) begin
                @(posedge core_clock); #1; guard = guard + 1;
            end
            if (pfq_empty) fail_msg("queue never supplied a byte");
            repeat (3) @(posedge core_clock);
            value = pfq_top_byte;
            @(negedge core_clock); eu_command = CMD_FETCH_STROBE;
            @(negedge core_clock); eu_command = 16'h0000;
            @(negedge core_clock);
        end
    endtask

    localparam integer LOG_DEPTH = 16;
    logic [2:0]  log_status [0:LOG_DEPTH-1];
    logic [19:0] log_address [0:LOG_DEPTH-1];
    logic        log_wide [0:LOG_DEPTH-1];
    logic        log_wide_write [0:LOG_DEPTH-1];
    integer log_count = 0;
    logic [2:0] previous_status = ST_PASSIVE;
    always @(posedge core_clock) begin
        if (!biu_reset) begin
            // Log at the end of the cycle.  At that point bus_address has
            // passed through its T1 latch, and WORD_READ_REQUEST is still the
            // request which shaped the cycle just completed.
            if ((previous_status != ST_PASSIVE) && (status == ST_PASSIVE)) begin
                if (log_count < LOG_DEPTH) begin
                    log_status[log_count] <= previous_status;
                    log_address[log_count] <= bus_address;
                    log_wide[log_count] <= word_read_request;
                    log_wide_write[log_count] <= word_write_request;
                    log_count <= log_count + 1;
                end
            end
            previous_status <= status;
        end
    end
    task automatic clear_log;
        begin log_count = 0; end
    endtask

    task automatic check_queue_bytes(input [19:0] first, input string label);
        integer i, failures_before;
        logic [7:0] got;
        begin
            failures_before = fail_count;
            for (i = 0; i < 6; i = i + 1) begin
                take_byte(got);
                if (got !== expected_byte(first + i))
                    fail_msg($sformatf("%s: byte %0d was %02h, expected %02h",
                                       label, i, got, expected_byte(first + i)));
            end
            if (fail_count == failures_before)
                pass_msg($sformatf("%s: RAM word path delivers six queue bytes in order", label));
        end
    endtask

    integer i, activations_before, writes_before;

    task automatic run_speed_profile(input logic [1:0] profile,
                                     input string profile_name);
        integer failures_before;
        begin
            failures_before = fail_count;
            $display("");
            $display("8086 speed profile %s (clk_select=%02b)", profile_name, profile);

            // A menu speed change is reset-applied in the real core.  Repeat
            // that boundary here so each profile starts from the BIOS reset
            // vector with empty BIU/RAM/READY state.
            selected_clk = profile;
            biu_reset = 1'b1;
            ram_reset = 1'b1;
            eu_command = 16'h0000;
            eu_dataout = 16'h0000;
            eu_r3 = 16'h0000;
            previous_status = ST_PASSIVE;
            clear_log;

            repeat (5) @(posedge ram_clock);
            ram_reset = 1'b0;
            while (!initialized_sdram) @(posedge ram_clock);

            // This is a hardware-derived requirement, not something a
            // zero-delay memory model can discover by corrupting data. RAM
            // lookahead is active at 9.54 MHz, so that profile must use the
            // same late BIU read sample as maximum speed.
            if (shift_read_timing !== ((profile == 2'b10) || (profile == 2'b11)))
                fail_msg($sformatf("%s: shift_read_timing was %b", profile_name,
                                   shift_read_timing));
            else
                pass_msg($sformatf("%s: read sampling profile is hardware-safe",
                                   profile_name));

            // No prefetch is permitted until the RAM controller is ready.
            repeat (5) @(posedge core_clock);
            activations_before = sdram_activates;
            biu_reset = 1'b0;
            wait_bus_quiet;

            if (biu_cs !== 16'hFFFF)
                fail_msg($sformatf("reset CS was %04h, expected FFFF", biu_cs));
            else if (log_count != 3)
                fail_msg($sformatf("reset filled 6-byte queue with %0d cycles, expected 3", log_count));
            else if (!log_wide[0] || !log_wide[1] || !log_wide[2])
                fail_msg("reset prefetch did not keep WORD_READ_REQUEST high for all three cycles");
            else if ((sdram_activates - activations_before) != 3)
                fail_msg($sformatf("reset prefetch caused %0d SDRAM transactions, expected 3 wide reads",
                                   sdram_activates - activations_before));
            else
                pass_msg("reset vector fills six-byte 8086 queue through RAM in three word transactions");
            check_queue_bytes(20'hFFFF0, "reset vector");

            // Reset uses the BIOS mapping.  Repeat from a conventional-memory
            // address reached through a real BIU jump so the test also covers
            // a queue flush and a newly latched address.
            wait_bus_quiet;
            clear_log;
            activations_before = sdram_activates;
            jump_to(16'h0D00, "even jump");
            wait_bus_quiet;
            if (log_count != 3)
                fail_msg($sformatf("even jump filled queue with %0d cycles, expected 3", log_count));
            else if (!log_wide[0] || !log_wide[1] || !log_wide[2])
                fail_msg("even jump did not make all three RAM fetches wide");
            else if (log_address[0] !== 20'hFFFF0 + 20'h0D00)
                fail_msg($sformatf("even jump first fetch was %05h", log_address[0]));
            else if ((sdram_activates - activations_before) != 3)
                fail_msg($sformatf("even jump caused %0d SDRAM transactions, expected 3",
                                   sdram_activates - activations_before));
            else
                pass_msg("even jump crosses BIU and RAM word paths in three transactions");
            check_queue_bytes(20'hFFFF0 + 20'h0D00, "even jump");

            // Step 5, end to end: write a word through the private CPU->RAM
            // path, then read it back.  The watchdog in data_request turns a
            // READY/CE deadlock into a bounded, profile-labelled failure.
            wait_bus_quiet;
            clear_log;
            activations_before = sdram_activates;
            writes_before = sdram_writes;
            eu_dataout = 16'hD46B;
            data_request(5'h13, 16'h3000, "wide data write");
            wait_bus_quiet;
            if (log_count < 1 || log_status[0] !== ST_MEMW || !log_wide_write[0])
                fail_msg("wide data write did not appear as one private word cycle");
            else if ((sdram_activates - activations_before) != 1)
                fail_msg($sformatf("wide data write used %0d SDRAM transactions",
                                   sdram_activates - activations_before));
            else if ((sdram_writes - writes_before) != 2)
                fail_msg($sformatf("wide data write issued %0d SDRAM beats",
                                   sdram_writes - writes_before));
            else
                pass_msg("wide data write crosses BIU and RAM in one two-beat transaction");

            wait_bus_quiet;
            clear_log;
            activations_before = sdram_activates;
            data_request(5'h10, 16'h3000, "wide data read");
            wait_bus_quiet;
            if (log_count < 1 || log_status[0] !== ST_MEMR || !log_wide[0])
                fail_msg("wide data read did not appear as one private word cycle");
            else if ((sdram_activates - activations_before) != 1)
                fail_msg($sformatf("wide data read used %0d SDRAM transactions",
                                   sdram_activates - activations_before));
            else if (biu_return_data !== 16'hD46B)
                fail_msg($sformatf("wide data read returned %04h, expected D46B", biu_return_data));
            else
                pass_msg("wide data read returns both bytes written by the wide data write");

            if (fail_count == failures_before)
                $display("PROFILE RESULT: PASS (%s)", profile_name);
            else
                $display("PROFILE RESULT: FAIL (%s)", profile_name);
        end
    endtask

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1)
            memory[i] = {~expected_byte(i[19:0]), expected_byte(i[19:0])};
        map_ems[0] = 0; map_ems[1] = 0; map_ems[2] = 0; map_ems[3] = 0;

        run_speed_profile(2'b00, "4.77 MHz");
        run_speed_profile(2'b01, "7.16 MHz");
        run_speed_profile(2'b10, "9.54 MHz");
        run_speed_profile(2'b11, "maximum");

        $display("");
        $display("%0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0) $display("RESULT: PASS");
        else                 $display("RESULT: FAIL");
        $finish;
    end

    initial begin
        #30_000_000;
        $display("  FAIL  timeout");
        $display("RESULT: FAIL");
        $finish;
    end
endmodule
