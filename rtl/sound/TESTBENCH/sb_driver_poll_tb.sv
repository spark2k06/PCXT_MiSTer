`timescale 1ns/1ps

// Playback the way a driver actually does it, rather than the way a testbench
// finds convenient. Two things here are deliberately closer to the machine
// than sb_playback_tb is, and both are places a hang could hide:
//
//   The CPU clock enables pulse once every ten chipset clocks, roughly what
//   4.77 MHz inside 50 MHz looks like. sb_playback_tb asserts both on every
//   clock, which is simple and hides anything that depends on the gap between
//   them - the DMA glue only re-arms its request on cpu_ce_negedge.
//
//   Every DSP command is preceded by polling the write-status port at 2xCh
//   until bit 7 says the DSP is ready, which is what CT-VOICE.DRV does and
//   what no bench here has ever exercised. If that bit sticks high the driver
//   spins forever - and a driver spinning forever is not a sound bug, it is
//   the machine hanging, which is the symptom this bench exists to catch.
//
// The polls are bounded. A real driver would wait forever; this one fails.
module sb_driver_poll_tb;

    localparam TB_CYCLE = 20;      // 50 MHz chipset clock
    localparam CE_DIV   = 10;      // -> 5 MHz CPU, near enough to 4.77
    localparam CLK_RATE = 28'd50_000_000;

    logic         clock = 1'b0;
    logic         reset = 1'b1;

    logic         cpu_ce_posedge = 1'b0;
    logic         cpu_ce_negedge = 1'b0;

    logic [19:0]  cpu_address = '0;
    logic [7:0]   cpu_data_bus = '0;
    logic [2:0]   processor_status = 3'b111;
    logic         processor_lock_n = 1'b1;
    logic         dma_ready = 1'b1;
    logic         dma_chip_select_n = 1'b1;
    logic         dma_page_chip_select_n = 1'b1;
    logic [19:0]  address_ext = '0;
    logic [7:0]   data_bus_ext;
    logic         io_read_n_ext = 1'b1;
    logic         io_write_n_ext = 1'b1;
    logic         memory_read_n_ext = 1'b1;
    logic         memory_write_n_ext = 1'b1;
    logic         ext_access_request = 1'b0;
    wire  [3:0]   dma_request;

    wire          processor_transmit_or_receive_n;
    wire          dma_wait_n;
    wire          interrupt_acknowledge_n;
    wire [19:0]   address;
    wire          address_direction;
    wire [7:0]    internal_data_bus;
    wire          data_bus_direction;
    wire          address_latch_enable;
    wire          io_read_n;
    wire          io_read_n_direction;
    wire          io_write_n;
    wire          io_write_n_direction;
    wire          memory_read_n;
    wire          memory_read_n_direction;
    wire          memory_write_n;
    wire          memory_write_n_direction;
    wire          no_command_state;
    wire [3:0]    dma_acknowledge_n;
    wire          address_enable_n;
    wire          terminal_count_n;

    always #(TB_CYCLE / 2) clock = ~clock;

    // The two CPU phases, half a CPU period apart.
    int ce_count = 0;
    always @(posedge clock) begin
        ce_count       <= (ce_count == CE_DIV - 1) ? 0 : ce_count + 1;
        cpu_ce_posedge <= (ce_count == 0);
        cpu_ce_negedge <= (ce_count == CE_DIV / 2);
    end

    wire          sb_dma_request;
    assign dma_request = {2'b00, sb_dma_request, 1'b0};

    BUS_ARBITER u_arbiter (.*);

    function automatic [7:0] mem_byte(input [19:0] a);
        mem_byte = a[7:0] ^ 8'h5A;
    endfunction

    always_comb begin
        if (~memory_read_n)                     data_bus_ext = mem_byte(address);
        else if (~io_read_n && sb_read_select)  data_bus_ext = sb_data_bus_out;
        else                                    data_bus_ext = 8'hFF;
    end

    wire          sb_read_select;
    wire  [7:0]   sb_data_bus_out;
    wire          sb_irq;
    wire  [15:0]  sample_l, sample_r;

    soundblaster u_sb (
        .clock              (clock),
        .reset              (reset),
        .cpu_ce_negedge     (cpu_ce_negedge),
        .clk_rate           (CLK_RATE),
        .address            (address[15:0]),
        .internal_data_bus  (internal_data_bus),
        .io_read_n          (io_read_n),
        .io_write_n         (io_write_n),
        .address_enable_n   (address_enable_n),
        .enable             (1'b1),
        .read_select        (sb_read_select),
        .data_bus_out       (sb_data_bus_out),
        .dma_acknowledge    (~dma_acknowledge_n[1]),
        .dma_request        (sb_dma_request),
        .irq                (sb_irq),
        .fm_l               (16'sd0),
        .fm_r               (16'sd0),
        .sample_l           (sample_l),
        .sample_r           (sample_r)
    );

    int errors = 0;

    task automatic fail(input string what);
        begin
            $display("FAIL: %s", what);
            errors++;
        end
    endtask

    // A bus cycle paced by the CPU clock enables rather than by raw time.
    task automatic cpu_cycle(input [2:0] status, input [19:0] addr, input [7:0] data);
        begin
            @(posedge clock);
            cpu_address      = addr;
            cpu_data_bus     = data;
            processor_status = status;
            repeat (CE_DIV * 4) @(posedge clock);
            processor_status = 3'b111;
            repeat (CE_DIV * 2) @(posedge clock);
            cpu_address      = 20'h00000;
            cpu_data_bus     = 8'h00;
            repeat (CE_DIV) @(posedge clock);
        end
    endtask

    logic [7:0] last_read;

    task automatic io_write(input [19:0] addr, input [7:0] data);
        begin cpu_cycle(3'b010, addr, data); end
    endtask

    task automatic io_read(input [19:0] addr);
        begin
            @(posedge clock);
            cpu_address      = addr;
            processor_status = 3'b001;
            repeat (CE_DIV * 4) @(posedge clock);
            last_read        = sb_data_bus_out;
            processor_status = 3'b111;
            repeat (CE_DIV * 2) @(posedge clock);
            cpu_address      = 20'h00000;
            repeat (CE_DIV) @(posedge clock);
        end
    endtask

    task automatic dma_write(input [3:0] reg_addr, input [7:0] data);
        begin
            dma_chip_select_n = 1'b0;
            io_write({16'h0000, reg_addr}, data);
            dma_chip_select_n = 1'b1;
        end
    endtask

    // What CT-VOICE.DRV does before every command it writes: read 2xCh and
    // wait for bit 7 to clear. Bounded here so a stuck flag is a failure
    // rather than a hung simulation.
    int  worst_poll = 0;

    task automatic dsp_write(input [7:0] data, input string what);
        begin
            automatic int tries = 0;
            forever begin
                io_read(20'h0022C);
                if (!last_read[7]) break;
                tries++;
                if (tries > 200) begin
                    fail($sformatf("DSP busy flag never cleared before %s - a driver polling 2xCh would hang here",
                                   what));
                    return;
                end
            end
            if (tries > worst_poll) worst_poll = tries;
            io_write(20'h0022C, data);
        end
    endtask

    localparam int XFER_COUNT = 32;
    localparam [15:0] XFER_ADDR = 16'h1234;
    localparam [3:0]  XFER_PAGE = 4'h5;

    int  dack_count = 0;
    logic prev_dack = 1'b0;
    always @(posedge clock) begin
        prev_dack <= ~dma_acknowledge_n[1];
        if (~dma_acknowledge_n[1] && !prev_dack) dack_count++;
    end

    logic irq_seen = 1'b0;
    always @(posedge clock) if (sb_irq) irq_seen <= 1'b1;

    initial begin
        repeat (20) @(posedge clock);
        reset = 1'b0;
        repeat (20) @(posedge clock);

        // ------------------------------------------------------- DSP reset
        io_write(20'h00226, 8'h01);
        repeat (CE_DIV * 4) @(posedge clock);
        io_write(20'h00226, 8'h00);
        repeat (CE_DIV * 8) @(posedge clock);

        io_read(20'h0022A);
        if (last_read !== 8'hAA)
            fail($sformatf("reset acknowledge was %02h, expected AA", last_read));

        // The busy flag must be clear before a driver would send anything.
        io_read(20'h0022C);
        if (last_read[7])
            fail("DSP reported busy immediately after reset");

        // -------------------------------------------- set up as a driver does
        dsp_write(8'hD1, "speaker on");
        dsp_write(8'h40, "time constant command");
        dsp_write(8'hA6, "time constant value");   // ~11 kHz

        dma_page_chip_select_n = 1'b0;
        io_write(20'h00083, {4'h0, XFER_PAGE});
        dma_page_chip_select_n = 1'b1;

        dma_write(4'hA, 8'h05);                    // mask channel 1
        dma_write(4'hC, 8'h00);                    // clear byte pointer
        dma_write(4'hB, 8'h49);                    // single, increment, mem->dev
        dma_write(4'h2, XFER_ADDR[7:0]);
        dma_write(4'h2, XFER_ADDR[15:8]);
        dma_write(4'h3, XFER_COUNT - 1);
        dma_write(4'h3, 8'h00);
        dma_write(4'hA, 8'h01);                    // unmask channel 1

        dsp_write(8'h14, "single-cycle DMA output");
        dsp_write(XFER_COUNT - 1, "length low");
        dsp_write(8'h00, "length high");

        // ------------------------------------------------- let it play out
        // At ~11 kHz a 32-byte block takes about 2.9 ms.
        #(4_000_000);

        if (dack_count == 0)
            fail("no DMA cycle ever ran - the transfer never started");
        else if (dack_count != XFER_COUNT)
            fail($sformatf("%0d DMA cycles ran, expected %0d", dack_count, XFER_COUNT));

        if (!irq_seen)
            fail("no interrupt at the end of the block");

        // And the driver has to be able to talk to the DSP again afterwards,
        // which means the busy flag has to have come back down.
        dsp_write(8'hD3, "speaker off after the block");

        io_read(20'h0022E);                        // acknowledge the interrupt
        repeat (CE_DIV * 4) @(posedge clock);
        if (sb_irq) fail("interrupt still asserted after reading 22Eh");

        // ------------------------------------------- auto-init playback
        // What a game sound effect actually uses. The DSP restarts the
        // block itself and the 8237 reloads its own address and count, so
        // neither side is reprogrammed between blocks - the driver only
        // acknowledges each interrupt and refills the half of the buffer
        // that just played. If the second block never starts, or the
        // interrupt cannot be re-armed, a driver waits forever.
        dack_count = 0;
        irq_seen   = 1'b0;

        dma_write(4'hA, 8'h05);                    // mask channel 1
        dma_write(4'hC, 8'h00);
        dma_write(4'hB, 8'h59);                    // as before, plus autoinit
        dma_write(4'h2, XFER_ADDR[7:0]);
        dma_write(4'h2, XFER_ADDR[15:8]);
        dma_write(4'h3, XFER_COUNT - 1);
        dma_write(4'h3, 8'h00);
        dma_write(4'hA, 8'h01);                    // unmask

        dsp_write(8'h48, "set block size");
        dsp_write(XFER_COUNT - 1, "block size low");
        dsp_write(8'h00, "block size high");
        dsp_write(8'h1C, "auto-init DMA output");

        // Two blocks' worth, acknowledging each interrupt the way an ISR
        // would. A block is about 2.9 ms at this rate.
        begin
            automatic int acks = 0;
            automatic int guard = 0;
            while (acks < 2 && guard < 40) begin
                if (sb_irq) begin
                    io_read(20'h0022E);
                    acks++;
                end
                #(200_000);
                guard++;
            end
            if (acks < 2)
                fail($sformatf("auto-init produced %0d interrupts in two block times, expected 2",
                               acks));
        end

        if (dack_count < XFER_COUNT * 2)
            fail($sformatf("auto-init ran %0d DMA cycles across two blocks, expected at least %0d",
                           dack_count, XFER_COUNT * 2));

        // Leaving auto-init has to actually stop it. A DSP that kept
        // requesting after the driver said stop would hold DREQ up and
        // steal bus cycles from the CPU for as long as it ran.
        //
        // DAh does not stop the transfer where it stands, though: it
        // clears the auto-init flag, and the block already in flight plays
        // to its end before the DSP goes idle. So allow a whole block to
        // drain first, and only then require silence - asserting silence
        // immediately just fails against correct hardware.
        dsp_write(8'hDA, "exit auto-init");
        #(6_000_000);                              // one block is ~2.9 ms
        begin
            automatic int dack_before = dack_count;
            #(6_000_000);
            if (dack_count != dack_before)
                fail($sformatf("%0d more DMA cycles a block after leaving auto-init - it never stopped",
                               dack_count - dack_before));
        end

        // ---------------------------------------- high-speed playback
        // The mode CT-VOICE.DRV actually uses: the driver in this game's
        // directory issues 48h then 91h, single-cycle high-speed output.
        //
        // High-speed is where a hang would live. The DSP accepts no
        // commands while it is in it, and says so by holding the busy flag
        // at 2xCh high for the whole block - that part is correct hardware
        // behaviour, not a fault. What matters is that the block ends: the
        // end-of-block is the only thing that clears high-speed mode, so if
        // it never arrives the flag stays high forever and the next command
        // the driver tries to send never goes out.
        dack_count = 0;
        irq_seen   = 1'b0;

        dsp_write(8'h40, "time constant command");
        dsp_write(8'hA6, "time constant value");
        dsp_write(8'h48, "set block size");
        dsp_write(XFER_COUNT - 1, "block size low");
        dsp_write(8'h00, "block size high");

        dma_write(4'hA, 8'h05);
        dma_write(4'hC, 8'h00);
        dma_write(4'hB, 8'h49);
        dma_write(4'h2, XFER_ADDR[7:0]);
        dma_write(4'h2, XFER_ADDR[15:8]);
        dma_write(4'h3, XFER_COUNT - 1);
        dma_write(4'h3, 8'h00);
        dma_write(4'hA, 8'h01);

        dsp_write(8'h91, "high-speed single-cycle output");

        // The busy flag is expected to be high from here until the block
        // ends, so wait on the block rather than on the flag.
        #(8_000_000);

        if (dack_count == 0)
            fail("high-speed mode ran no DMA cycles at all");
        else if (dack_count != XFER_COUNT)
            fail($sformatf("high-speed ran %0d DMA cycles, expected %0d",
                           dack_count, XFER_COUNT));

        if (!irq_seen)
            fail("no interrupt at the end of the high-speed block");

        io_read(20'h0022E);
        repeat (CE_DIV * 4) @(posedge clock);

        // The flag has to come back down, or the driver's next command
        // never goes out and the machine stops here.
        io_read(20'h0022C);
        if (last_read[7])
            fail("DSP still busy after the high-speed block ended - high-speed mode never cleared");

        dsp_write(8'hD3, "speaker off after high-speed");

        // And the whole thing has to be repeatable, the way a game firing
        // the same effect twice would.
        dack_count = 0;
        dma_write(4'hA, 8'h05);
        dma_write(4'hC, 8'h00);
        dma_write(4'hB, 8'h49);
        dma_write(4'h2, XFER_ADDR[7:0]);
        dma_write(4'h2, XFER_ADDR[15:8]);
        dma_write(4'h3, XFER_COUNT - 1);
        dma_write(4'h3, 8'h00);
        dma_write(4'hA, 8'h01);
        dsp_write(8'h91, "second high-speed block");
        #(8_000_000);
        if (dack_count != XFER_COUNT)
            fail($sformatf("second high-speed block ran %0d DMA cycles, expected %0d",
                           dack_count, XFER_COUNT));
        io_read(20'h0022E);
        repeat (CE_DIV * 4) @(posedge clock);

        // And the DSP must still take commands afterwards.
        dsp_write(8'hD3, "speaker off after auto-init");

        // ------------------------------- aborting a high-speed block
        // A game does not always let an effect finish. It cuts one short
        // to start the next, and the only way out of high-speed mode is a
        // DSP reset - write 1 to 2x6h, then 0, and wait for the AAh that
        // says the DSP came back. A driver that never sees that AAh waits
        // for it for ever.
        //
        // Nothing above this covers it: every block so far was allowed to
        // play to its end, and so is every step of the hardware probe.
        dack_count = 0;
        irq_seen   = 1'b0;

        dsp_write(8'h48, "block size for the aborted block");
        dsp_write(8'hFF, "block size low");
        dsp_write(8'h07, "block size high");   // long enough to still be running

        dma_write(4'hA, 8'h05);
        dma_write(4'hC, 8'h00);
        dma_write(4'hB, 8'h49);
        dma_write(4'h2, XFER_ADDR[7:0]);
        dma_write(4'h2, XFER_ADDR[15:8]);
        dma_write(4'h3, 8'hFF);
        dma_write(4'h3, 8'h07);
        dma_write(4'hA, 8'h01);

        io_write(20'h0022C, 8'h91);            // straight in; the flag is
                                                // high from here by design
        #(2_000_000);                           // let it get going
        if (dack_count == 0)
            fail("the block to be aborted never started");

        // The standard reset sequence, mid-block.
        io_write(20'h00226, 8'h01);
        repeat (CE_DIV * 8) @(posedge clock);
        io_write(20'h00226, 8'h00);
        repeat (CE_DIV * 8) @(posedge clock);

        begin
            automatic int tries = 0;
            automatic logic got = 1'b0;
            while (tries < 100 && !got) begin
                io_read(20'h0022E);
                if (last_read[7]) got = 1'b1;
                tries++;
            end
            if (!got)
                fail("no reply after resetting out of high speed - a driver waits for AAh for ever here");
            else begin
                io_read(20'h0022A);
                if (last_read !== 8'hAA)
                    fail($sformatf("reset out of high speed answered %02h, expected AA",
                                   last_read));
            end
        end

        // And the transfer has to have stopped.
        begin
            automatic int dack_before = dack_count;
            #(4_000_000);
            if (dack_count != dack_before)
                fail($sformatf("%0d more DMA cycles after the abort - it kept playing",
                               dack_count - dack_before));
        end

        // ------------------------------- a one-byte block, length zero
        // CT-VOICE.DRV verifies the card by playing a single byte: command
        // 14h with a length of zero, then waiting for the end-of-block
        // interrupt in a bounded loop. If that interrupt never comes the
        // driver calls the card unusable, which would leave a game silent
        // while everything else about the card still worked.
        //
        // Every block above was hundreds of bytes. Zero is its own case:
        // the length counter starts already exhausted, so the first
        // transfer has to be both the first and the last.
        dack_count = 0;
        irq_seen   = 1'b0;
        dma_write(4'hA, 8'h05);
        dma_write(4'hC, 8'h00);
        dma_write(4'hB, 8'h49);
        dma_write(4'h2, XFER_ADDR[7:0]);
        dma_write(4'h2, XFER_ADDR[15:8]);
        dma_write(4'h3, 8'h00);
        dma_write(4'h3, 8'h00);
        dma_write(4'hA, 8'h01);
        dsp_write(8'h40, "time constant command");
        dsp_write(8'h64, "time constant 64h, as the driver uses");
        dsp_write(8'h14, "single-cycle output");
        dsp_write(8'h00, "length low = 0");
        dsp_write(8'h00, "length high = 0");
        #(3_000_000);
        if (dack_count != 1)
            fail($sformatf("one-byte block ran %0d DMA cycles, expected 1", dack_count));
        if (!irq_seen)
            fail("no interrupt after a one-byte block - the driver would call the card unusable");
        io_read(20'h0022E);
        repeat (CE_DIV * 4) @(posedge clock);


        if (errors == 0)
            $display("PASS: single-cycle and auto-init both played, IRQs cleared, busy never stuck (worst poll %0d)",
                     worst_poll);
        else
            $display("RESULT: FAIL (%0d)", errors);
        $finish;
    end

    initial begin
        #(120_000_000);
        $display("FAIL: TIMEOUT");
        $finish;
    end

endmodule
