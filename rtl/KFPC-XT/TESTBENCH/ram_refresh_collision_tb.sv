// Regression for writes that overlap an SDRAM refresh.
//
// At the PC/AT 3.5 MHz setting MEMW is shorter than the READY feedback path.
// A write must therefore remain owned by RAM after MEMW is released.  This
// bench verifies the byte and the complete row/column address presented to the
// SDRAM pins, including tight consecutive accesses where a registered-only
// address would still belong to the previous cycle.

`timescale 1ns / 1ps

module ram_refresh_collision_tb;

    logic clock = 1'b0;
    logic reset = 1'b1;
    always #10 clock = ~clock; // 50 MHz, matching clk_chipset

    logic [1:0]  clk_select = 2'b11;
    logic [19:0] address = 20'h00000;
    logic [7:0]  data_in = 8'h00;
    logic        memory_read_n = 1'b1;
    logic        memory_write_n = 1'b1;
    logic        no_command_state = 1'b1;

    wire [7:0]  data_out;
    wire        memory_access_ready;
    wire        ram_address_select_n;
    wire        initilized_sdram;
    wire [12:0] sdram_address;
    wire        sdram_cke;
    wire        sdram_cs;
    wire        sdram_ras;
    wire        sdram_cas;
    wire        sdram_we;
    wire [1:0]  sdram_ba;
    wire [15:0] sdram_dq_out;
    wire        sdram_dq_io;
    wire        sdram_ldqm;
    wire        sdram_udqm;

    logic [6:0] map_ems [0:3];

    RAM dut (
        .clock                 (clock),
        .reset                 (reset),
        .enable_sdram          (1'b1),
        .initilized_sdram      (initilized_sdram),
        .address               (address),
        .internal_data_bus     (data_in),
        .data_bus_out          (data_out),
        .word_read_request     (1'b0),
        .word_write_request    (1'b0),
        .data_bus_in_word      (16'h0000),
        .data_bus_out_word     (),
        .memory_read_n         (memory_read_n),
        .memory_write_n        (memory_write_n),
        .no_command_state      (no_command_state),
        .memory_access_ready   (memory_access_ready),
        .ram_address_select_n  (ram_address_select_n),
        .sdram_address         (sdram_address),
        .sdram_cke             (sdram_cke),
        .sdram_cs              (sdram_cs),
        .sdram_ras             (sdram_ras),
        .sdram_cas             (sdram_cas),
        .sdram_we              (sdram_we),
        .sdram_ba              (sdram_ba),
        .sdram_dq_in           (16'h0000),
        .sdram_dq_out          (sdram_dq_out),
        .sdram_dq_io           (sdram_dq_io),
        .sdram_ldqm            (sdram_ldqm),
        .sdram_udqm            (sdram_udqm),
        .map_ems               (map_ems),
        .ems_b1                (1'b0),
        .ems_b2                (1'b0),
        .ems_b3                (1'b0),
        .ems_b4                (1'b0),
        .tandy_bios_flag       (1'b0),
        .enable_a000h          (1'b1),
        .bios_protect_flag     (2'b00),
        .wait_count_clk_en     (1'b1),
        .clk_select            (clk_select),
        .ram_read_wait_cycle   (2'd0),
        .ram_write_wait_cycle  (2'd0)
    );

    integer pass_count = 0;
    integer fail_count = 0;
    integer write_count = 0;
    logic [12:0] active_row = 13'h0000;
    logic [1:0]  active_bank = 2'b00;
    logic [23:0] last_write_address = 24'h000000;
    logic [7:0]  last_write_data = 8'h00;

    // KFSDRAM issues ACTIVE first and WRITE one clock later.  Reassemble both
    // halves so the test catches a row from one access combined with the
    // column of the next one.  Ignore masked commands: they do not write RAM.
    always @(posedge clock) begin
        if (!sdram_cs && !sdram_ras && sdram_cas && sdram_we) begin
            active_row  <= sdram_address;
            active_bank <= sdram_ba;
        end

        if (!sdram_cs && sdram_ras && !sdram_cas && !sdram_we &&
            !sdram_ldqm) begin
            last_write_address <= {active_bank, active_row,
                                   sdram_address[8:0]};
            last_write_data <= sdram_dq_out[7:0];
            write_count <= write_count + 1;
        end
    end

    task automatic fail(input string message);
        begin
            fail_count = fail_count + 1;
            $display("FAIL: %s", message);
        end
    endtask

    task automatic check_latest_write(
        input logic [19:0] expected_address,
        input logic [7:0] expected_data,
        input string label_text
    );
        begin
            if (last_write_address[19:0] !== expected_address) begin
                fail_count = fail_count + 1;
                $display("FAIL: %s address=%05h expected=%05h", label_text,
                         last_write_address[19:0], expected_address);
            end
            else if (last_write_data !== expected_data) begin
                fail_count = fail_count + 1;
                $display("FAIL: %s data=%02h expected=%02h", label_text,
                         last_write_data, expected_data);
            end
            else begin
                pass_count = pass_count + 1;
                $display("PASS: %s address=%05h data=%02h", label_text,
                         last_write_address[19:0], last_write_data);
            end
        end
    endtask

    task automatic wait_for_new_write(
        input integer previous_count,
        input string label_text
    );
        integer guard;
        begin
            guard = 0;
            while ((write_count == previous_count) && (guard < 1000)) begin
                @(posedge clock);
                #1;
                guard = guard + 1;
            end
            if (write_count == previous_count)
                fail({label_text, ": no unmasked SDRAM WRITE command"});
        end
    endtask

    task automatic wait_until_idle(input string label_text);
        integer guard;
        begin
            guard = 0;
            while (((dut.state !== 3'd0) || !dut.idle) && (guard < 1000)) begin
                @(posedge clock);
                #1;
                guard = guard + 1;
            end
            if ((dut.state !== 3'd0) || !dut.idle)
                fail({label_text, ": RAM/SDRAM did not return idle"});
        end
    endtask

    // Hold a normal write until RAM reports completion.  Successive calls
    // leave only the single IDLE edge needed to begin the next bus cycle.
    task automatic write_held(
        input logic [19:0] write_address,
        input logic [7:0] write_data
    );
        integer guard;
        begin
            @(negedge clock);
            address = write_address;
            data_in = write_data;
            no_command_state = 1'b0;
            memory_write_n = 1'b0;

            guard = 0;
            while (memory_access_ready && (guard < 1000)) begin
                @(posedge clock);
                #1;
                guard = guard + 1;
            end
            guard = 0;
            while (!memory_access_ready && (guard < 1000)) begin
                @(posedge clock);
                #1;
                guard = guard + 1;
            end

            @(negedge clock);
            memory_write_n = 1'b1;
            no_command_state = 1'b1;
        end
    endtask

    // Start in a selected clock of REFRESH_PALL/REFRESH and release MEMW after
    // one chipset clock.  Six offsets cover every clock for the default SDRAM
    // timing parameters.  The RAM frontend must retain the request afterward.
    task automatic write_during_refresh(
        input integer refresh_offset,
        input logic [19:0] write_address,
        input logic [7:0] write_data
    );
        integer i;
        integer previous_count;
        string label_text;
        begin
            $sformat(label_text, "refresh phase %0d", refresh_offset);

            while (dut.refresh_mode) begin
                @(posedge clock);
                #1;
            end
            while (!dut.refresh_mode) begin
                @(posedge clock);
                #1;
            end

            for (i = 0; i < refresh_offset; i = i + 1)
                @(posedge clock);
            #1;
            if (!dut.refresh_mode)
                fail({label_text, ": selected offset is outside refresh"});

            previous_count = write_count;
            @(negedge clock);
            address = write_address;
            data_in = write_data;
            no_command_state = 1'b0;
            memory_write_n = 1'b0;
            @(posedge clock);
            @(negedge clock);
            memory_write_n = 1'b1;
            no_command_state = 1'b1;

            wait_for_new_write(previous_count, label_text);
            if (write_count != previous_count)
                check_latest_write(write_address, write_data, label_text);
            wait_until_idle(label_text);
        end
    endtask

    integer i;
    integer speed;
    integer previous_count;
    logic [19:0] collision_address;
    logic [7:0] collision_data;

    initial begin
        map_ems[0] = 7'd0;
        map_ems[1] = 7'd0;
        map_ems[2] = 7'd0;
        map_ems[3] = 7'd0;

        repeat (5) @(posedge clock);
        reset = 1'b0;

        // KFSDRAM's power-up wait is 10,000 clocks.
        repeat (10100) @(posedge clock);
        wait_until_idle("initialization");

        // Addresses deliberately cross columns and rows, including the address
        // shown in the report; the bug is not tied to 30000h. 0046Bh is the
        // IBM BIOS data-area interrupt flag written by the POST IRQ0 handler.
        //
        // Swept at both readiness policies. RAM.sv runs the closed-loop
        // handshake only at 2'b11 and the original open-loop one below it, so
        // retaining the write after MEMW releases has to hold either way; the
        // policy decides when the CPU is told to wait, not who owns the write.
        // Ready_tb covers the CPU-side half.
        for (speed = 0; speed < 2; speed = speed + 1) begin
            clk_select = (speed == 0) ? 2'b11 : 2'b00;
            wait_until_idle("policy change");
            for (i = 0; i < 6; i = i + 1) begin
                case (i)
                    0: collision_address = 20'h0046B;
                    1: collision_address = 20'h12345;
                    2: collision_address = 20'h30000;
                    3: collision_address = 20'h57A5C;
                    4: collision_address = 20'h81234;
                    default: collision_address = 20'h9FFEF;
                endcase
                collision_data = 8'hA0 + i[7:0] + speed[7:0];
                write_during_refresh(i, collision_address, collision_data);
            end
        end

        // The tight-write cases below drive MEMW off the ready handshake, which
        // only closes under the strict policy.
        clk_select = 2'b11;
        wait_until_idle("policy change");

        // Tight consecutive writes prove that ACTIVE uses the current live
        // address while WRITE uses the copy latched for that same access.
        previous_count = write_count;
        write_held(20'h01234, 8'h77);
        wait_for_new_write(previous_count, "tight write 1");
        if (write_count != previous_count)
            check_latest_write(20'h01234, 8'h77, "tight write 1");

        previous_count = write_count;
        write_held(20'h6B678, 8'h88);
        wait_for_new_write(previous_count, "tight write 2");
        if (write_count != previous_count)
            check_latest_write(20'h6B678, 8'h88, "tight write 2");

        previous_count = write_count;
        write_held(20'h9ABCD, 8'h99);
        wait_for_new_write(previous_count, "tight write 3");
        if (write_count != previous_count)
            check_latest_write(20'h9ABCD, 8'h99, "tight write 3");

        $display("RESULT: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count != 0)
            $fatal(1, "ram_refresh_collision_tb failed");
        $finish;
    end

endmodule
