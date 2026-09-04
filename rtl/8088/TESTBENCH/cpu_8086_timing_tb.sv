// Step-7 full-core 8088/8086 timing and bus-accounting regression.
`timescale 1ns / 1ps

module cpu_8086_timing_tb;
    localparam logic [2:0] ST_INTA  = 3'b000;
    localparam logic [2:0] ST_IOR   = 3'b001;
    localparam logic [2:0] ST_IOW   = 3'b010;
    localparam logic [2:0] ST_FETCH = 3'b100;
    localparam logic [2:0] ST_MEMR  = 3'b101;
    localparam logic [2:0] ST_MEMW  = 3'b110;
    localparam logic [2:0] ST_IDLE  = 3'b111;
    localparam integer LAST_MARKER = 11;
    localparam integer MEM_BYTES = 1 << 16;

    logic core_clock = 0, board_clock = 0;
    logic reset = 1, is8086_mode = 0, intr = 0;
    logic [1:0] requested_clk = 0;
    always #5 core_clock = ~core_clock;
    always #10 board_clock = ~board_clock;

    wire cpu_clock, cpu_ce_posedge, cpu_ce_negedge;
    wire cycle_accurate, shift_read_timing;
    wire [7:0] counter_division, counter_decrement;
    wire [1:0] ram_read_wait_cycle, ram_write_wait_cycle;
    wire biu_done;
    XT_CE_Generator clock_generator (
        .clock(board_clock), .reset(reset), .clk_select_load(biu_done),
        .clk_select(requested_clk), .cpu_clk_pin(cpu_clock),
        .cpu_ce_posedge(cpu_ce_posedge), .cpu_ce_negedge(cpu_ce_negedge),
        .peripheral_ce(), .cycle_accrate(cycle_accurate),
        .clock_cycle_counter_division_ratio(counter_division),
        .clock_cycle_counter_decrement_value(counter_decrement),
        .shift_read_timing(shift_read_timing),
        .ram_read_wait_cycle(ram_read_wait_cycle),
        .ram_write_wait_cycle(ram_write_wait_cycle)
    );

    wire [19:0] ad_out;
    wire [7:0] cpu_data_out;
    logic [7:0] cpu_data_in;
    wire [2:0] status;
    wire word_read_request, word_write_request;
    wire [15:0] data_bus_word_out;
    logic [15:0] data_bus_word;
    wire lock_n;
    logic [7:0] memory [0:MEM_BYTES-1];
    logic [19:0] bus_address = 0;

    // Low conventional memory is the only 16-bit target in this model. The
    // reset vector remains byte-wide, then jumps to 0000:0500 in SDRAM.
    wire word_access_possible = bus_address < 20'ha0000;

    i8088 cpu (
        .CORE_CLK(core_clock), .CLK(cpu_clock), .RESET(reset), .READY(1'b1),
        .INTR(intr), .NMI(1'b0), .ad_out(ad_out), .dout(cpu_data_out),
        .din(cpu_data_in), .lock_n(lock_n), .s6_3_mux(),
        .s2_s0_out(status), .SEGMENT(), .biu_done(biu_done),
        .cycle_accrate(cycle_accurate),
        .clock_cycle_counter_division_ratio(counter_division),
        .clock_cycle_counter_decrement_value(counter_decrement),
        .shift_read_timing(shift_read_timing), .is8086(is8086_mode),
        .word_read_request(word_read_request),
        .word_write_request(word_write_request),
        .data_bus_word_out(data_bus_word_out),
        .data_bus_word(data_bus_word),
        .word_access_possible(word_access_possible)
    );

    wire address_latch_enable;
    wire io_read_n, io_write_n, memory_read_n, memory_write_n;
    KF8288 bus_controller (
        .clock(board_clock), .cpu_ce_posedge(cpu_ce_posedge),
        .cpu_ce_negedge(cpu_ce_negedge), .reset(reset),
        .address_enable_n(1'b0), .command_enable(1'b1),
        .io_bus_mode(1'b0), .processor_status(status),
        .enable_io_command(), .advanced_io_write_command_n(),
        .io_write_command_n(io_write_n), .io_read_command_n(io_read_n),
        .interrupt_acknowledge_n(), .enable_memory_command(),
        .advanced_memory_write_command_n(memory_write_n),
        .memory_write_command_n(), .memory_read_command_n(memory_read_n),
        .direction_transmit_or_receive_n(), .data_enable(),
        .master_cascade_enable(), .peripheral_data_enable_n(),
        .address_latch_enable(address_latch_enable)
    );

    always @(posedge board_clock)
        if (address_latch_enable) bus_address <= ad_out;

    // Deliberately exclude the complete memory array from the sensitivity
    // list. Icarus otherwise wakes this block for every byte initialised.
    always @(bus_address or status or lock_n or cpu.u_biu_core.s_bits or
             cpu.u_biu_core.biu_state) begin
        data_bus_word = {memory[bus_address[15:0] + 16'd1],
                         memory[bus_address[15:0]]};
        if ((cpu.u_biu_core.s_bits == ST_INTA) &&
            (cpu.u_biu_core.biu_state != 8'h00))
            cpu_data_in = 8'h60;
        else if (status == ST_IOR)
            cpu_data_in = bus_address[0] ? 8'h12 : 8'h34;
        else
            cpu_data_in = memory[bus_address[15:0]];
    end

    integer cpu_ticks, fetch_cycles, mem_reads, mem_writes;
    integer io_reads, io_writes, inta_cycles, wide_reads, wide_writes;
    integer mark_ticks [0:LAST_MARKER];
    integer mark_fetch [0:LAST_MARKER];
    integer mark_memr  [0:LAST_MARKER];
    integer mark_memw  [0:LAST_MARKER];
    integer mark_ior   [0:LAST_MARKER];
    integer mark_iow   [0:LAST_MARKER];
    integer mark_inta  [0:LAST_MARKER];
    integer mark_wider [0:LAST_MARKER];
    integer mark_widew [0:LAST_MARKER];
    logic marker_seen [0:LAST_MARKER];
    logic [2:0] previous_status = ST_IDLE;
    logic [7:0] previous_biu_state = 0;

    integer saved_ticks [0:LAST_MARKER];
    integer saved_fetch [0:LAST_MARKER];
    integer saved_memr  [0:LAST_MARKER];
    integer saved_memw  [0:LAST_MARKER];
    integer saved_ior   [0:LAST_MARKER];
    integer saved_iow   [0:LAST_MARKER];
    integer saved_inta  [0:LAST_MARKER];
    integer saved_wider [0:LAST_MARKER];
    integer saved_widew [0:LAST_MARKER];
    logic [7:0] saved_signature [0:3];

    always @(posedge cpu_clock) begin
        if (reset) cpu_ticks = 0;
        else cpu_ticks = cpu_ticks + 1;
    end

    // Account completed external cycles. Data writes are committed here so
    // the model observes exactly the byte/word decision made by the real BIU.
    always @(posedge core_clock) begin
        if (reset) begin
            previous_status <= ST_IDLE;
            previous_biu_state <= 0;
            intr <= 1'b0;
        end
        else begin
            // INTA has no useful address phase and its two cycles can be
            // adjacent. Count each entry into the BIU's T1 state directly.
            if ((previous_biu_state != 8'h01) &&
                (cpu.u_biu_core.biu_state == 8'h01) &&
                (cpu.u_biu_core.s_bits == ST_INTA)) begin
                inta_cycles = inta_cycles + 1;
                intr <= 1'b0;
            end
            if ((previous_status != ST_IDLE) && (status == ST_IDLE)) begin
                case (previous_status)
                    ST_FETCH: fetch_cycles = fetch_cycles + 1;
                    ST_MEMR: begin
                        mem_reads = mem_reads + 1;
                        if (word_read_request) wide_reads = wide_reads + 1;
                    end
                    ST_MEMW: begin
                        mem_writes = mem_writes + 1;
                        if (word_write_request) begin
                            wide_writes = wide_writes + 1;
                            memory[bus_address[15:0]] = data_bus_word_out[7:0];
                            memory[bus_address[15:0] + 16'd1] =
                                data_bus_word_out[15:8];
                        end
                        else memory[bus_address[15:0]] = cpu_data_out;
                    end
                    ST_IOR: io_reads = io_reads + 1;
                    ST_IOW: begin
                        io_writes = io_writes + 1;
                        if ((bus_address[15:0] == 16'h00e0) &&
                            (cpu_data_out <= LAST_MARKER)) begin
                            marker_seen[cpu_data_out] = 1'b1;
                            mark_ticks[cpu_data_out] = cpu_ticks;
                            mark_fetch[cpu_data_out] = fetch_cycles;
                            mark_memr[cpu_data_out] = mem_reads;
                            mark_memw[cpu_data_out] = mem_writes;
                            mark_ior[cpu_data_out] = io_reads;
                            mark_iow[cpu_data_out] = io_writes;
                            mark_inta[cpu_data_out] = inta_cycles;
                            mark_wider[cpu_data_out] = wide_reads;
                            mark_widew[cpu_data_out] = wide_writes;
                            if (cpu_data_out == 8'd10) intr <= 1'b1;
                        end
                    end
                    ST_INTA: intr <= 1'b0;
                    default: ;
                endcase
            end
            previous_status <= status;
            previous_biu_state <= cpu.u_biu_core.biu_state;
        end
    end

    integer pass_count = 0, fail_count = 0;
    task automatic fail_msg(input string message);
        begin fail_count = fail_count + 1; $display("  FAIL  %s", message); end
    endtask
    task automatic pass_msg(input string message);
        begin pass_count = pass_count + 1; $display("  PASS  %s", message); end
    endtask
    task automatic expect_less(input integer actual, input integer reference,
                               input string message);
        begin
            if (!(actual < reference))
                fail_msg($sformatf("%s: 8086=%0d, 8088=%0d", message,
                                   actual, reference));
        end
    endtask
    task automatic expect_equal(input integer actual, input integer reference,
                                input string message);
        begin
            if (actual != reference)
                fail_msg($sformatf("%s: 8086=%0d, 8088=%0d", message,
                                   actual, reference));
        end
    endtask

    task automatic clear_and_load_program;
        integer k, fd, value, address;
        begin
            for (k = 0; k < 20'h9000; k = k + 1) memory[k] = 8'h00;
            for (k = 0; k < 16; k = k + 1) memory[16'hfff0+k] = 8'h90;

            fd = $fopen("cpu_8086_timing.bin", "rb");
            if (fd == 0) begin
                fail_msg("cannot open cpu_8086_timing.bin");
            end
            else begin
                address = 0;
                while (!$feof(fd)) begin
                    value = $fgetc(fd);
                    if (value >= 0) begin
                        memory[address] = value[7:0];
                        address = address + 1;
                    end
                end
                $fclose(fd);
            end

            // Reset vector: far jump to the low-RAM workload at 0000:0500.
            memory[16'hfff0] = 8'hea;
            memory[16'hfff1] = 8'h00;
            memory[16'hfff2] = 8'h05;
            memory[16'hfff3] = 8'h00;
            memory[16'hfff4] = 8'h00;

            for (k = 0; k < 64; k = k + 1) begin
                memory[16'h1000 + (k*2)] = (k + 1) & 8'hff;
                memory[16'h1001 + (k*2)] = 8'h00;
                memory[16'h1101 + (k*2)] = (8'h80 + k) & 8'hff;
                memory[16'h1102 + (k*2)] = 8'h01;
            end
            for (k = 0; k < 32; k = k + 1) begin
                memory[16'h1400 + (k*2)] = (8'h20 + k) & 8'hff;
                memory[16'h1401 + (k*2)] = 8'ha5;
                memory[16'h1501 + (k*2)] = (8'h60 + k) & 8'hff;
                memory[16'h1502 + (k*2)] = 8'h5a;
            end
            memory[16'h1200] = 8'h00; memory[16'h1201] = 8'h20;
            memory[16'h1301] = 8'h00; memory[16'h1302] = 8'h30;
            memory[16'h1bfe] = 8'h00; memory[16'h1bff] = 8'h00;
        end
    endtask

    task automatic reset_counters;
        integer k;
        begin
            cpu_ticks = 0; fetch_cycles = 0; mem_reads = 0; mem_writes = 0;
            io_reads = 0; io_writes = 0; inta_cycles = 0;
            wide_reads = 0; wide_writes = 0;
            for (k = 0; k <= LAST_MARKER; k = k + 1) begin
                marker_seen[k] = 1'b0;
                mark_ticks[k] = 0; mark_fetch[k] = 0;
                mark_memr[k] = 0; mark_memw[k] = 0;
                mark_ior[k] = 0; mark_iow[k] = 0; mark_inta[k] = 0;
                mark_wider[k] = 0; mark_widew[k] = 0;
            end
        end
    endtask

    task automatic verify_functional(input string mode_name);
        integer k;
        begin
            if ({memory[16'h1201], memory[16'h1200]} !== 16'h2020)
                fail_msg($sformatf("%s aligned RMW result", mode_name));
            if ({memory[16'h1302], memory[16'h1301]} !== 16'h3020)
                fail_msg($sformatf("%s odd RMW result", mode_name));
            if ({memory[16'h1a01], memory[16'h1a00]} !== 16'h0001)
                fail_msg($sformatf("%s interrupt handler count", mode_name));
            for (k = 0; k < 64; k = k + 1) begin
                if (memory[16'h1600+k] !== memory[16'h1400+k])
                    fail_msg($sformatf("%s aligned MOVSW byte %0d", mode_name,k));
                if (memory[16'h1701+k] !== memory[16'h1501+k])
                    fail_msg($sformatf("%s odd MOVSW byte %0d", mode_name,k));
            end
        end
    endtask

    task automatic run_mode(input logic [1:0] profile, input logic mode,
                            input string profile_name);
        integer guard, k, failures_before;
        string mode_name;
        begin
            failures_before = fail_count;
            mode_name = mode ? "8086" : "8088";
            $display("");
            $display("%s timing workload at %s", mode_name, profile_name);
            reset = 1'b1; requested_clk = profile; is8086_mode = mode;
            reset_counters();
            clear_and_load_program();
            repeat (8) @(posedge board_clock);
            repeat (5) @(posedge core_clock);
            reset = 1'b0;

            guard = 0;
            while (!((memory[16'h1bfe] == 8'hef) &&
                     (memory[16'h1bff] == 8'hbe)) && (guard < 500_000)) begin
                @(posedge core_clock); #1; guard = guard + 1;
            end
            if (guard == 500_000)
                fail_msg($sformatf("%s/%s timeout IP=%04h status=%03b addr=%05h IVT=%02h%02h:%02h%02h",
                                   mode_name, profile_name, cpu.t_pfq_addr_out,
                                   status, bus_address,
                                   memory[16'h0183],memory[16'h0182],
                                   memory[16'h0181],memory[16'h0180]));
            else repeat (50) @(posedge core_clock);

            for (k = 0; k <= LAST_MARKER; k = k + 1)
                if (!marker_seen[k])
                    fail_msg($sformatf("%s/%s missing marker %0d",
                                       mode_name, profile_name, k));
            verify_functional($sformatf("%s/%s",mode_name,profile_name));

            if (!mode) begin
                for (k = 0; k <= LAST_MARKER; k = k + 1) begin
                    saved_ticks[k] = mark_ticks[k];
                    saved_fetch[k] = mark_fetch[k];
                    saved_memr[k] = mark_memr[k];
                    saved_memw[k] = mark_memw[k];
                    saved_ior[k] = mark_ior[k]; saved_iow[k] = mark_iow[k];
                    saved_inta[k] = mark_inta[k];
                    saved_wider[k] = mark_wider[k];
                    saved_widew[k] = mark_widew[k];
                end
                for (k = 0; k < 4; k = k + 1)
                    saved_signature[k] = memory[16'h1b00+k];
            end
            else begin
                for (k = 0; k < 4; k = k + 1)
                    if (memory[16'h1b00+k] !== saved_signature[k])
                        fail_msg($sformatf("%s functional signature %0d differs",
                                           profile_name,k));
            end

            if (fail_count == failures_before)
                pass_msg($sformatf("%s/%s completed all 12 markers",
                                   mode_name, profile_name));
        end
    endtask

    task automatic compare_profile(input string profile_name);
        integer s, ticks88, ticks86;
        begin
            $display("");
            $display("stage CPU clocks at %s (8088 -> 8086)", profile_name);
            for (s = 1; s <= LAST_MARKER; s = s + 1) begin
                ticks88 = saved_ticks[s] - saved_ticks[s-1];
                ticks86 = mark_ticks[s] - mark_ticks[s-1];
                $display("  stage %0d: %0d -> %0d", s, ticks88, ticks86);
            end

            // Register-only code may benefit from the wider prefetch queue,
            // but it must not gain or lose data-bus cycles.
            expect_equal(mark_memr[1]-mark_memr[0],
                         saved_memr[1]-saved_memr[0], "register MEMR cycles");
            expect_equal(mark_memw[1]-mark_memw[0],
                         saved_memw[1]-saved_memw[0], "register MEMW cycles");

            expect_less(mark_memr[2]-mark_memr[1],
                        saved_memr[2]-saved_memr[1], "aligned word reads");
            expect_equal(mark_memr[3]-mark_memr[2],
                         saved_memr[3]-saved_memr[2], "odd word reads");
            expect_less(mark_memr[4]-mark_memr[3],
                        saved_memr[4]-saved_memr[3], "aligned RMW reads");
            expect_less(mark_memw[4]-mark_memw[3],
                        saved_memw[4]-saved_memw[3], "aligned RMW writes");
            expect_equal(mark_memr[5]-mark_memr[4],
                         saved_memr[5]-saved_memr[4], "odd RMW reads");
            expect_equal(mark_memw[5]-mark_memw[4],
                         saved_memw[5]-saved_memw[4], "odd RMW writes");
            expect_less(mark_memr[6]-mark_memr[5],
                        saved_memr[6]-saved_memr[5], "stack/CALL/RET reads");
            expect_less(mark_memw[6]-mark_memw[5],
                        saved_memw[6]-saved_memw[5], "stack/CALL/RET writes");
            expect_less(mark_memr[7]-mark_memr[6],
                        saved_memr[7]-saved_memr[6], "aligned MOVSW reads");
            expect_less(mark_memw[7]-mark_memw[6],
                        saved_memw[7]-saved_memw[6], "aligned MOVSW writes");
            expect_equal(mark_memr[8]-mark_memr[7],
                         saved_memr[8]-saved_memr[7], "odd MOVSW reads");
            expect_equal(mark_memw[8]-mark_memw[7],
                         saved_memw[8]-saved_memw[7], "odd MOVSW writes");

            expect_equal(mark_ior[10]-mark_ior[9],
                         saved_ior[10]-saved_ior[9], "word I/O reads");
            expect_equal(mark_iow[10]-mark_iow[9],
                         saved_iow[10]-saved_iow[9], "word I/O writes");
            expect_equal(mark_inta[11]-mark_inta[10],
                         saved_inta[11]-saved_inta[10], "interrupt acknowledge");
            if ((mark_inta[11]-mark_inta[10]) != 2)
                fail_msg($sformatf("%s interrupt used %0d INTA cycles, expected 2",
                                   profile_name,
                                   mark_inta[11]-mark_inta[10]));
            expect_less(mark_memr[11]-mark_memr[10],
                        saved_memr[11]-saved_memr[10], "interrupt/IRET reads");
            expect_less(mark_memw[11]-mark_memw[10],
                        saved_memw[11]-saved_memw[10], "interrupt stack writes");

            if ((mark_wider[2]-mark_wider[1]) < 64)
                fail_msg($sformatf("%s only %0d aligned wide reads",
                                   profile_name,
                                   mark_wider[2]-mark_wider[1]));
            if ((mark_wider[3]-mark_wider[2]) != 0)
                fail_msg($sformatf("%s odd reads widened",profile_name));
            if ((mark_wider[8]-mark_wider[7]) != 0 ||
                (mark_widew[8]-mark_widew[7]) != 0)
                fail_msg($sformatf("%s odd MOVSW widened",profile_name));
            if ((saved_wider[LAST_MARKER] != 0) ||
                (saved_widew[LAST_MARKER] != 0))
                fail_msg($sformatf("%s 8088 issued a wide data cycle",
                                   profile_name));

            pass_msg($sformatf("%s bus-width matrix compared",profile_name));
        end
    endtask

    task automatic run_profile_pair(input logic [1:0] profile,
                                    input string profile_name);
        begin
            run_mode(profile, 1'b0, profile_name);
            run_mode(profile, 1'b1, profile_name);
            compare_profile(profile_name);
        end
    endtask

    integer profile_arg;
    initial begin
        if ($value$plusargs("PROFILE=%d", profile_arg)) begin
            case (profile_arg)
                0: run_profile_pair(2'b00, "4.77 MHz");
                1: run_profile_pair(2'b01, "7.16 MHz");
                2: run_profile_pair(2'b10, "9.54 MHz");
                3: run_profile_pair(2'b11, "maximum");
                default: fail_msg("PROFILE must be 0..3");
            endcase
        end
        else begin
            run_profile_pair(2'b00, "4.77 MHz");
            run_profile_pair(2'b01, "7.16 MHz");
            run_profile_pair(2'b10, "9.54 MHz");
            run_profile_pair(2'b11, "maximum");
        end
        $display("");
        $display("%0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0) $display("RESULT: PASS");
        else $display("RESULT: FAIL");
        $finish;
    end

    initial begin
        #80_000_000;
        $display("  FAIL  global timeout");
        $display("RESULT: FAIL");
        $finish;
    end
endmodule
