`timescale 1ns/1ps

// End-to-end playback for the reduced Sound Blaster Pro.
//
// Drives the whole path a real program drives: reset the DSP through 226h,
// check the 0xAAh reset acknowledge at 22Ah, turn the speaker on, set a time
// constant, program the KF8237 for channel 1, issue command 14h (single-cycle
// 8-bit DMA output), and then assert that the bytes in memory come out of the
// DSP as samples, in order, correctly converted from unsigned to signed, with
// an interrupt at the end of the block.
//
// The bus is the real BUS_ARBITER with the real KF8237, so the DMA cycles here
// are the ones the hardware runs. Icarus cannot elaborate that controller;
// this runs under Verilator.
module sb_playback_tb;

    // 5 MHz, matching clk_rate below so the DSP's microsecond tick and its
    // sample clock are both self-consistent with simulated time.
    localparam TB_CYCLE  = 200;
    localparam CLK_RATE  = 28'd5_000_000;

    logic         clock = 1'b0;
    logic         reset = 1'b1;

    wire          cpu_ce_posedge = 1'b1;
    wire          cpu_ce_negedge = 1'b1;

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

    wire          sb_dma_request;
    assign dma_request = {2'b00, sb_dma_request, 1'b0};

    BUS_ARBITER u_arbiter (.*);

    // ---------------------------------------------------------------- memory
    function automatic [7:0] mem_byte(input [19:0] a);
        mem_byte = a[7:0] ^ 8'h5A;
    endfunction

    // The memory answers a DMA read; on a CPU read the peripheral drives the
    // bus instead, which for these ports means the Sound Blaster.
    always_comb begin
        if (~memory_read_n)                     data_bus_ext = mem_byte(address);
        else if (~io_read_n && sb_read_select)  data_bus_ext = sb_data_bus_out;
        else                                    data_bus_ext = 8'hFF;
    end

    // ---------------------------------------------------------- Sound Blaster
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
        .sample_l           (sample_l),
        .sample_r           (sample_r)
    );

    // ------------------------------------------------------------- CPU cycles
    task automatic io_write(input [19:0] addr, input [7:0] data);
        begin
            cpu_address      = addr;
            cpu_data_bus     = data;
            processor_status = 3'b010;
            #(TB_CYCLE * 4);
            processor_status = 3'b111;
            #(TB_CYCLE * 1);
            cpu_address      = 20'h00000;
            cpu_data_bus     = 8'h00;
            #(TB_CYCLE * 2);
        end
    endtask

    logic [7:0] last_read;

    task automatic io_read(input [19:0] addr);
        begin
            cpu_address      = addr;
            processor_status = 3'b001;
            #(TB_CYCLE * 4);
            last_read        = sb_data_bus_out;
            processor_status = 3'b111;
            #(TB_CYCLE * 1);
            cpu_address      = 20'h00000;
            #(TB_CYCLE * 2);
        end
    endtask

    task automatic dma_write(input [3:0] reg_addr, input [7:0] data);
        begin
            dma_chip_select_n = 1'b0;
            io_write({16'h0000, reg_addr}, data);
            dma_chip_select_n = 1'b1;
        end
    endtask

    // Writing the DSP command port. Real drivers poll 2xCh bit 7 first; the
    // bench does not need to, because io_write blocks for a whole bus cycle.
    task automatic dsp_write(input [7:0] data);
        begin
            io_write(20'h0022C, data);
        end
    endtask

    // ------------------------------------------------------------- capture
    localparam int XFER_COUNT = 16;
    localparam [15:0] XFER_ADDR = 16'h1234;
    localparam [3:0]  XFER_PAGE = 4'h5;

    // sample_value_l settles two clocks after the acknowledge: the DSP raises
    // sample_output the cycle after dma_valid, and updates the sample on that
    // edge. Three is a margin, and still well inside one sample period.
    logic [2:0]  ack_pipe = 3'b000;
    logic        prev_dack = 1'b0;
    logic [15:0] captured [0:63];
    int          captured_n = 0;

    // Captured at the DSP's own output rather than the module's, deliberately.
    // What this bench is asserting is that the DMA path delivers memory to the
    // converter intact; sample_l has been through the mixer's gain stage by
    // then, which is a separate concern with its own bench. Reading the mixed
    // output here would also be meaningless at the 1 MHz sample rate this
    // bench uses for speed, since the shared-multiplier gain stage needs more
    // clocks per sample than that leaves it.
    always @(posedge clock) begin
        prev_dack <= ~dma_acknowledge_n[1];
        ack_pipe  <= {ack_pipe[1:0], prev_dack & dma_acknowledge_n[1]};
        if (ack_pipe[2]) begin
            if (captured_n < 64) captured[captured_n] <= u_sb.dsp_l;
            captured_n <= captured_n + 1;
        end
    end

    logic irq_seen = 1'b0;
    always @(posedge clock) if (sb_irq) irq_seen <= 1'b1;


    int errors = 0;

    task automatic check(input cond, input string what);
        begin
            if (!cond) begin
                $display("FAIL: %s", what);
                errors++;
            end
        end
    endtask

    // How the DSP converts an unsigned 8-bit sample for output: the byte lands
    // in the top half and the sign bit is flipped.
    function automatic [15:0] expect_sample(input [7:0] b);
        expect_sample = {~b[7], b[6:0], 8'h00};
    endfunction

    initial begin
        repeat (10) @(posedge clock);
        reset = 1'b0;
        #(TB_CYCLE * 4);

        // -------------------------------------------------- DSP reset at 226h
        io_write(20'h00226, 8'h01);
        #(TB_CYCLE * 4);
        io_write(20'h00226, 8'h00);
        #(TB_CYCLE * 8);

        // A real driver detects the card by this byte. If it is wrong nothing
        // else in this bench is worth reading.
        io_read(20'h0022A);
        check(last_read == 8'hAA,
              $sformatf("reset acknowledge at 22Ah was %02h, expected AA", last_read));

        // -------------------------------------------------- DSP version, E1h
        dsp_write(8'hE1);
        io_read(20'h0022A);
        check(last_read == 8'h03,
              $sformatf("DSP major version was %02h, expected 03 (Sound Blaster Pro)",
                        last_read));

        // ------------------------------------------------ speaker on, then rate
        // With sbp set, the DSP mutes its output until the speaker is enabled,
        // so without this the samples below are all zero.
        dsp_write(8'hD1);

        // Time constant FFh: one sample per microsecond. Absurd for real
        // audio, but it keeps the simulation short and exercises the same path.
        dsp_write(8'h40);
        dsp_write(8'hFF);

        // ---------------------------------------------------- 8237 channel 1
        dma_page_chip_select_n = 1'b0;
        io_write(20'h00083, {4'h0, XFER_PAGE});
        dma_page_chip_select_n = 1'b1;

        dma_write(4'hD, 8'h00);                 // master clear
        #(TB_CYCLE * 2);
        dma_write(4'hB, 8'h49);                 // single, increment, mem->dev, ch1
        dma_write(4'hC, 8'h00);                 // clear byte pointer
        dma_write(4'h2, XFER_ADDR[7:0]);
        dma_write(4'h2, XFER_ADDR[15:8]);
        dma_write(4'h3, XFER_COUNT - 1);
        dma_write(4'h3, 8'h00);
        dma_write(4'hA, 8'h01);                 // unmask channel 1

        // ------------------------------------- command 14h, single-cycle out
        dsp_write(8'h14);
        dsp_write(XFER_COUNT - 1);              // length low  (length-1)
        dsp_write(8'h00);                       // length high

        // Let the block play out.
        #(TB_CYCLE * 1200);

        // ------------------------------------------------------------ checks
        check(captured_n == XFER_COUNT,
              $sformatf("DSP produced %0d samples, expected %0d", captured_n, XFER_COUNT));

        for (int i = 0; i < XFER_COUNT && i < captured_n; i++) begin
            automatic logic [19:0] a = {XFER_PAGE, XFER_ADDR} + i;
            check(captured[i] == expect_sample(mem_byte(a)),
                  $sformatf("sample %0d was %04h, expected %04h (byte %02h at %05h)",
                            i, captured[i], expect_sample(mem_byte(a)), mem_byte(a), a));
        end

        check(irq_seen, "no interrupt at the end of the block");

        // Reading 2xEh acknowledges the 8-bit interrupt on real hardware.
        io_read(20'h0022E);
        #(TB_CYCLE * 4);
        check(!sb_irq, "interrupt still asserted after reading 22Eh");

        if (errors == 0)
            $display("PASS: %0d samples played from memory, IRQ raised and acknowledged",
                     captured_n);
        else
            $display("RESULT: FAIL (%0d)", errors);
        $finish;
    end

    initial begin
        #(TB_CYCLE * 20000);
        $display("FAIL: TIMEOUT");
        $finish;
    end

endmodule
