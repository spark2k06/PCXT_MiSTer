// Full-core 8086 speed matrix: EU + BIU + READY + RAM + SDRAM model.
`timescale 1ns / 1ps

module cpu_8086_speed_tb;
    localparam logic [2:0] ST_FETCH = 3'b100;
    localparam logic [2:0] ST_MEMR  = 3'b101;
    localparam logic [2:0] ST_MEMW  = 3'b110;

    logic core_clock = 0, ram_clock = 0;
    logic cpu_reset = 1, ram_reset = 1;
    logic [1:0] requested_clk = 0;
    logic [1:0] selected_clk = 0;
    integer core_phase_ns;
    initial begin
        if (!$value$plusargs("CORE_PHASE_NS=%d", core_phase_ns))
            core_phase_ns = 0;
        #(core_phase_ns);
        forever #5 core_clock = ~core_clock;
    end
    always #10 ram_clock = ~ram_clock;

    wire cpu_clock, cpu_ce_posedge, cpu_ce_negedge;
    wire cycle_accurate, shift_read_timing;
    wire [7:0] counter_division, counter_decrement;
    wire [1:0] ram_read_wait_cycle, ram_write_wait_cycle;
    XT_CE_Generator clock_generator (
        .clock(ram_clock), .reset(ram_reset), .clk_select_load(biu_done),
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
    wire [7:0] cpu_data_out, ram_data_out;
    wire [2:0] status;
    wire s6_3_mux, processor_ready, biu_done;
    wire word_read_request, word_write_request;
    wire [15:0] data_bus_word_out, data_bus_word;
    wire ram_address_select_n;
    i8088 cpu (
        .CORE_CLK(core_clock), .CLK(cpu_clock), .RESET(cpu_reset),
        .READY(processor_ready), .INTR(1'b0), .NMI(1'b0),
        .ad_out(ad_out), .dout(cpu_data_out), .din(ram_data_out),
        .lock_n(), .s6_3_mux(s6_3_mux), .s2_s0_out(status), .SEGMENT(),
        .biu_done(biu_done), .cycle_accrate(cycle_accurate),
        .clock_cycle_counter_division_ratio(counter_division),
        .clock_cycle_counter_decrement_value(counter_decrement),
        .shift_read_timing(shift_read_timing), .is8086(1'b1),
        .word_read_request(word_read_request),
        .word_write_request(word_write_request),
        .data_bus_word_out(data_bus_word_out), .data_bus_word(data_bus_word),
        .word_access_possible(~ram_address_select_n)
    );

    // Top-level speed handover: the chipset-visible profile and the clock
    // generator both change only when the BIU reports a completed operation.
    // A reset always begins at 4.77 MHz, then applies the pending OSD setting.
    always @(posedge ram_clock, posedge ram_reset) begin
        if (ram_reset)
            selected_clk <= 2'b00;
        else if (biu_done)
            selected_clk <= requested_clk;
    end

    // Real 8288 command timing and ALE-derived address latch, as used by the
    // top level.  Directly decoding S2:S0 makes short/fractional profiles look
    // unlike the board and can manufacture false byte-read failures.
    logic [19:0] bus_address = 0;
    wire address_latch_enable;
    wire memory_read_n, memory_write_n;
    KF8288 bus_controller (
        .clock(ram_clock), .cpu_ce_posedge(cpu_ce_posedge),
        .cpu_ce_negedge(cpu_ce_negedge), .reset(ram_reset),
        .address_enable_n(1'b0), .command_enable(1'b1),
        .io_bus_mode(1'b0), .processor_status(status),
        .enable_io_command(), .advanced_io_write_command_n(),
        .io_write_command_n(), .io_read_command_n(),
        .interrupt_acknowledge_n(), .enable_memory_command(),
        .advanced_memory_write_command_n(memory_write_n),
        .memory_write_command_n(), .memory_read_command_n(memory_read_n),
        .direction_transmit_or_receive_n(), .data_enable(),
        .master_cascade_enable(), .peripheral_data_enable_n(),
        .address_latch_enable(address_latch_enable)
    );
    always @(posedge ram_clock)
        if (address_latch_enable) bus_address <= ad_out;
    wire no_command_state = memory_read_n & memory_write_n;

    wire initialized_sdram, memory_access_ready;
    wire [15:0] ram_data_out_word;
    wire [12:0] sdram_address;
    wire sdram_cke, sdram_cs, sdram_ras, sdram_cas, sdram_we;
    wire [1:0] sdram_ba;
    wire [15:0] sdram_dq_in, sdram_dq_out;
    wire sdram_dq_io, sdram_ldqm, sdram_udqm;
    logic [6:0] map_ems [0:3];
    RAM ram (
        .clock(ram_clock), .reset(ram_reset), .enable_sdram(1'b1),
        .initilized_sdram(initialized_sdram), .address(bus_address),
        .internal_data_bus(cpu_data_out), .data_bus_out(ram_data_out),
        .word_read_request(word_read_request),
        .data_bus_out_word(ram_data_out_word),
        .word_write_request(word_write_request),
        .data_bus_in_word(data_bus_word_out),
        .memory_read_n(memory_read_n), .memory_write_n(memory_write_n),
        .no_command_state(no_command_state),
        .memory_access_ready(memory_access_ready),
        .ram_address_select_n(ram_address_select_n),
        .sdram_address(sdram_address), .sdram_cke(sdram_cke),
        .sdram_cs(sdram_cs), .sdram_ras(sdram_ras), .sdram_cas(sdram_cas),
        .sdram_we(sdram_we), .sdram_ba(sdram_ba), .sdram_dq_in(sdram_dq_in),
        .sdram_dq_out(sdram_dq_out), .sdram_dq_io(sdram_dq_io),
        .sdram_ldqm(sdram_ldqm), .sdram_udqm(sdram_udqm),
        .map_ems(map_ems), .ems_b1(1'b0), .ems_b2(1'b0),
        .ems_b3(1'b0), .ems_b4(1'b0), .tandy_bios_flag(1'b0),
        .enable_a000h(1'b1), .bios_protect_flag(2'b00),
        .wait_count_clk_en(cpu_ce_negedge),
        .ram_read_wait_cycle(ram_read_wait_cycle),
        .ram_write_wait_cycle(ram_write_wait_cycle),
        .clk_select(selected_clk)
    );
    READY ready (
        .clock(ram_clock), .cpu_ce_posedge(cpu_ce_posedge),
        .cpu_ce_negedge(cpu_ce_negedge), .reset(ram_reset),
        .processor_ready(processor_ready), .dma_ready(), .dma_wait_n(1'b1),
        .io_channel_ready(memory_access_ready), .io_read_n(1'b1),
        .io_write_n(1'b1), .memory_read_n(memory_read_n),
        .memory_write_n(memory_write_n), .cga_memory_write_wait(1'b0),
        .dma0_acknowledge_n(1'b1),
        .address_enable_n(1'b1), .clk_select(selected_clk)
    );
    assign data_bus_word = ram_data_out_word;

    // Each low byte is one PC byte address. Wide accesses use two SDRAM beats.
    localparam integer MEM_BYTES = 8192;
    logic [15:0] memory [0:MEM_BYTES-1];
    logic [12:0] active_row = 0;
    logic [1:0] active_bank = 0;
    logic [15:0] read_d1 = 0, read_d2 = 0;
    wire cmd_active = ~sdram_cs & ~sdram_ras &  sdram_cas &  sdram_we;
    wire cmd_read   = ~sdram_cs &  sdram_ras & ~sdram_cas &  sdram_we;
    wire cmd_write  = ~sdram_cs &  sdram_ras & ~sdram_cas & ~sdram_we;
    wire [23:0] cmd_address = {active_bank, active_row, sdram_address[8:0]};
    always @(posedge ram_clock) begin
        if (cmd_active) begin
            active_row <= sdram_address;
            active_bank <= sdram_ba;
        end
        if (cmd_read) read_d1 <= memory[cmd_address[12:0]];
        if (cmd_write && !sdram_ldqm)
            memory[cmd_address[12:0]][7:0] <= sdram_dq_out[7:0];
        read_d2 <= read_d1;
    end
    assign sdram_dq_in = read_d2;

    integer fetch_cycles = 0, wide_reads = 0, wide_writes = 0;
    logic [2:0] previous_status = 3'b111;
    always @(posedge core_clock) begin
        if (cpu_reset) previous_status <= 3'b111;
        else begin
`ifdef TRACE
            if (cpu.u_eu_core.new_instruction)
                $display("TRACE opcode IP=%04h byte=%02h AX=%04h BX=%04h CX=%04h",
                         cpu.t_pfq_addr_out, cpu.t_pfq_top_byte,
                         cpu.u_eu_core.eu_register_ax,
                         cpu.u_eu_core.eu_register_bx,
                         cpu.u_eu_core.eu_register_cx);
`endif
            if ((previous_status != 3'b111) && (status == 3'b111)) begin
                if (previous_status == ST_FETCH) fetch_cycles <= fetch_cycles + 1;
                if (word_read_request) wide_reads <= wide_reads + 1;
                if (word_write_request) wide_writes <= wide_writes + 1;
`ifdef TRACE
                if ((previous_status == ST_FETCH) && (fetch_cycles < 40))
                    $display("TRACE fetch %05h byte=%02h word=%04h wide=%b",
                             bus_address, ram_data_out, ram_data_out_word,
                             word_read_request);
                if ((previous_status == ST_MEMW) && (wide_writes < 40))
                    $display("TRACE write %05h data=%04h wide=%b",
                             bus_address, data_bus_word_out, word_write_request);
`endif
            end
            previous_status <= status;
        end
    end

    integer pass_count = 0, fail_count = 0;
    task automatic fail_msg(input string message);
        begin fail_count = fail_count + 1; $display("  FAIL  %s", message); end
    endtask
    task automatic pass_msg(input string message);
        begin pass_count = pass_count + 1; $display("  PASS  %s", message); end
    endtask
    task automatic put_byte(input logic [19:0] address, input logic [7:0] value);
        begin memory[address[12:0]][7:0] = value; end
    endtask

    task automatic load_program;
        integer k;
        begin
            for (k = 0; k < MEM_BYTES; k = k + 1) memory[k] = 16'h0090;
            // FFFF:0000 -> F000:0100.
            put_byte(20'hFFFF0,8'hEA); put_byte(20'hFFFF1,8'h00);
            put_byte(20'hFFFF2,8'h01); put_byte(20'hFFFF3,8'h00);
            put_byte(20'hFFFF4,8'hF0);
            // cli; xor ax,ax; mov ds,ax; mov bx,0200; mov cx,0020.
            put_byte(20'hF0100,8'hFA);
            put_byte(20'hF0101,8'h31); put_byte(20'hF0102,8'hC0);
            put_byte(20'hF0103,8'h8E); put_byte(20'hF0104,8'hD8);
            put_byte(20'hF0105,8'hBB); put_byte(20'hF0106,8'h00); put_byte(20'hF0107,8'h02);
            put_byte(20'hF0108,8'hB9); put_byte(20'hF0109,8'h20); put_byte(20'hF010A,8'h00);
            // mov [bx],ax; mov dx,[bx]; cmp dx,ax; jne fail; inc ax;
            // add bx,2; loop; mov [0400],ax; hlt.
            put_byte(20'hF010B,8'h89); put_byte(20'hF010C,8'h07);
            put_byte(20'hF010D,8'h8B); put_byte(20'hF010E,8'h17);
            put_byte(20'hF010F,8'h39); put_byte(20'hF0110,8'hC2);
            put_byte(20'hF0111,8'h75); put_byte(20'hF0112,8'h0A);
            put_byte(20'hF0113,8'h40);
            put_byte(20'hF0114,8'h83); put_byte(20'hF0115,8'hC3); put_byte(20'hF0116,8'h02);
            put_byte(20'hF0117,8'hE2); put_byte(20'hF0118,8'hF2);
            put_byte(20'hF0119,8'hA3); put_byte(20'hF011A,8'h00); put_byte(20'hF011B,8'h04);
            put_byte(20'hF011C,8'hF4);
            // Failure signature DEAD.
            put_byte(20'hF011D,8'hB8); put_byte(20'hF011E,8'hAD); put_byte(20'hF011F,8'hDE);
            put_byte(20'hF0120,8'hA3); put_byte(20'hF0121,8'h00); put_byte(20'hF0122,8'h04);
            put_byte(20'hF0123,8'hF4);
            memory[13'h400][7:0] = 8'hA5;
            memory[13'h401][7:0] = 8'h5A;
        end
    endtask

    task automatic run_profile(input logic [1:0] profile, input string name);
        integer guard, k, failures_before;
        begin
            failures_before = fail_count;
            $display(""); $display("full 8086 core at %s (clk_select=%02b)", name, profile);
            requested_clk = profile; cpu_reset = 1; ram_reset = 1;
            fetch_cycles = 0; wide_reads = 0; wide_writes = 0;
            load_program;
            repeat (5) @(posedge ram_clock);
            ram_reset = 0;
            while (!initialized_sdram) @(posedge ram_clock);
            repeat (5) @(posedge core_clock); cpu_reset = 0;
            guard = 0;
            while ((memory[13'h400][7:0] == 8'hA5) && (guard < 100_000)) begin
                @(posedge core_clock); #1; guard = guard + 1;
            end
            if (guard != 100_000)
                repeat (200) @(posedge core_clock);
            if (guard == 100_000)
                fail_msg($sformatf("%s: no signature (status=%03b address=%05h fetches=%0d AX=%04h BX=%04h CX=%04h DX=%04h mem0=%02h mem200=%02h)",
                                   name, status, bus_address, fetch_cycles,
                                   cpu.u_eu_core.eu_register_ax,
                                   cpu.u_eu_core.eu_register_bx,
                                   cpu.u_eu_core.eu_register_cx,
                                   cpu.u_eu_core.eu_register_dx,
                                   memory[13'h000][7:0], memory[13'h200][7:0]));
            else if ({memory[13'h401][7:0],memory[13'h400][7:0]} !== 16'h0020)
                fail_msg($sformatf("%s: failure signature %02h%02h", name,
                                   memory[13'h401][7:0],memory[13'h400][7:0]));
            else begin
                for (k = 0; k < 32; k = k + 1)
                    if ((memory[13'h200+(k*2)][7:0] !== k[7:0]) ||
                        (memory[13'h201+(k*2)][7:0] !== 8'h00))
                        fail_msg($sformatf("%s: bad loop word %0d", name, k));
                if ((wide_reads < 32) || (wide_writes < 33))
                    fail_msg($sformatf("%s: only %0d wide reads and %0d writes",
                                       name, wide_reads, wide_writes));
                if (fail_count == failures_before)
                    pass_msg($sformatf("%s: %0d fetches, %0d wide reads, %0d wide writes",
                                       name, fetch_cycles, wide_reads, wide_writes));
            end
        end
    endtask

    task automatic run_live_transition(input logic [1:0] from_profile,
                                       input string from_name);
        integer guard;
        begin
            $display("");
            $display("live 8086 speed transition %s -> 9.54 MHz", from_name);
            requested_clk = from_profile; cpu_reset = 1; ram_reset = 1;
            fetch_cycles = 0; wide_reads = 0; wide_writes = 0;
            load_program;
            repeat (5) @(posedge ram_clock);
            ram_reset = 0;
            while (!initialized_sdram) @(posedge ram_clock);
            repeat (5) @(posedge core_clock); cpu_reset = 0;

            // Change the pending OSD value after eight verified loop words.
            // The design must defer application to BIU_DONE, just as it does
            // in PCXT.sv, and continue without resetting the CPU or queue.
            guard = 0;
            while (!((selected_clk == from_profile) &&
                     (cpu.u_eu_core.eu_register_cx == 16'h0018)) &&
                   (guard < 100_000)) begin
                @(posedge core_clock); #1; guard = guard + 1;
            end
            if (guard == 100_000)
                fail_msg($sformatf("%s -> 9.54 MHz: switch point not reached", from_name));
            else begin
                requested_clk = 2'b10;
                guard = 0;
                while ((memory[13'h400][7:0] == 8'hA5) &&
                       (guard < 100_000)) begin
                    @(posedge core_clock); #1; guard = guard + 1;
                end
                if (guard != 100_000)
                    repeat (200) @(posedge core_clock);
                if (guard == 100_000)
                    fail_msg($sformatf("%s -> 9.54 MHz: no completion signature", from_name));
                else if (selected_clk != 2'b10)
                    fail_msg($sformatf("%s -> 9.54 MHz: requested speed was never applied", from_name));
                else if ({memory[13'h401][7:0],memory[13'h400][7:0]} !== 16'h0020)
                    fail_msg($sformatf("%s -> 9.54 MHz: signature was %02h%02h", from_name,
                                       memory[13'h401][7:0],memory[13'h400][7:0]));
                else
                    pass_msg($sformatf("%s -> 9.54 MHz: execution continued across live handover", from_name));
            end
        end
    endtask

    integer profile_arg;
    initial begin
        map_ems[0]=0; map_ems[1]=0; map_ems[2]=0; map_ems[3]=0;
        if ($value$plusargs("PROFILE=%d", profile_arg)) begin
            case (profile_arg)
                0: run_profile(2'b00,"4.77 MHz");
                1: run_profile(2'b01,"7.16 MHz");
                2: run_profile(2'b10,"9.54 MHz");
                3: run_profile(2'b11,"maximum");
                default: fail_msg("PROFILE must be 0..3");
            endcase
        end
        else begin
            run_profile(2'b00,"4.77 MHz"); run_profile(2'b01,"7.16 MHz");
            run_profile(2'b10,"9.54 MHz"); run_profile(2'b11,"maximum");
            run_live_transition(2'b00,"4.77 MHz");
            run_live_transition(2'b01,"7.16 MHz");
            run_live_transition(2'b11,"maximum");
        end
        $display(""); $display("%0d passed, %0d failed",pass_count,fail_count);
        if (fail_count == 0) $display("RESULT: PASS");
        else $display("RESULT: FAIL");
        $finish;
    end
    initial begin
        #10_000_000; $display("  FAIL  global timeout");
        $display("RESULT: FAIL"); $finish;
    end
endmodule
