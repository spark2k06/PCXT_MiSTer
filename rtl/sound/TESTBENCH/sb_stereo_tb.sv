`timescale 1ns/1ps

// Interleaved stereo, which is the reason the mixer exists at all.
//
// A Sound Blaster Pro has one 8-bit converter. Stereo is not two channels of
// data, it is one stream that the card deals alternately to left and right,
// armed by mixer register 0Eh bit 1. So the same DMA block that plays as mono
// must, with that bit set, split into two half-rate channels.
//
// The first sample goes to the RIGHT channel, not the left. That is not a
// convention someone chose: the Pro's board swaps left and right, and the DSP
// starts its interleave flip-flop set to compensate. Software written against
// real hardware depends on the resulting channel order, so a clone that starts
// on the left plays every stereo sample in the wrong ear.
//
// Runs under Verilator; Icarus cannot elaborate the KF8237.
module sb_stereo_tb;

    localparam TB_CYCLE = 200;
    localparam CLK_RATE = 28'd5_000_000;

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

    task automatic dma_write(input [3:0] reg_addr, input [7:0] data);
        begin
            dma_chip_select_n = 1'b0;
            io_write({16'h0000, reg_addr}, data);
            dma_chip_select_n = 1'b1;
        end
    endtask

    task automatic dsp_write(input [7:0] data);
        begin io_write(20'h0022C, data); end
    endtask

    task automatic mixer_write(input [7:0] index, input [7:0] data);
        begin
            io_write(20'h00224, index);
            io_write(20'h00225, data);
        end
    endtask

    localparam int XFER_COUNT = 8;
    localparam [15:0] XFER_ADDR = 16'h1234;
    localparam [3:0]  XFER_PAGE = 4'h5;

    // Captured straight from the DSP, before the gain stage - this bench is
    // about which channel a sample lands in, not what it is scaled by.
    logic [2:0]  ack_pipe = 3'b000;
    logic        prev_dack = 1'b0;
    logic [15:0] cap_l [0:15];
    logic [15:0] cap_r [0:15];
    int          cap_n = 0;

    always @(posedge clock) begin
        prev_dack <= ~dma_acknowledge_n[1];
        ack_pipe  <= {ack_pipe[1:0], prev_dack & dma_acknowledge_n[1]};
        if (ack_pipe[2]) begin
            if (cap_n < 16) begin
                cap_l[cap_n] <= u_sb.dsp_l;
                cap_r[cap_n] <= u_sb.dsp_r;
            end
            cap_n <= cap_n + 1;
        end
    end

    int errors = 0;

    task automatic check(input cond, input string what);
        begin
            if (!cond) begin
                $display("FAIL: %s", what);
                errors++;
            end
        end
    endtask

    function automatic [15:0] expect_sample(input [7:0] b);
        expect_sample = {~b[7], b[6:0], 8'h00};
    endfunction

    initial begin
        repeat (10) @(posedge clock);
        reset = 1'b0;
        #(TB_CYCLE * 4);

        // DSP reset
        io_write(20'h00226, 8'h01);
        #(TB_CYCLE * 4);
        io_write(20'h00226, 8'h00);
        #(TB_CYCLE * 8);

        dsp_write(8'hD1);                       // speaker on

        // Arm interleaved stereo. Writing 0Eh also re-arms the flip-flop that
        // decides which channel the next sample belongs to.
        mixer_write(8'h0E, 8'h02);

        dsp_write(8'h40);                       // time constant
        dsp_write(8'hFF);

        dma_page_chip_select_n = 1'b0;
        io_write(20'h00083, {4'h0, XFER_PAGE});
        dma_page_chip_select_n = 1'b1;

        dma_write(4'hD, 8'h00);
        #(TB_CYCLE * 2);
        dma_write(4'hB, 8'h49);
        dma_write(4'hC, 8'h00);
        dma_write(4'h2, XFER_ADDR[7:0]);
        dma_write(4'h2, XFER_ADDR[15:8]);
        dma_write(4'h3, XFER_COUNT - 1);
        dma_write(4'h3, 8'h00);
        dma_write(4'hA, 8'h01);

        dsp_write(8'h14);
        dsp_write(XFER_COUNT - 1);
        dsp_write(8'h00);

        #(TB_CYCLE * 900);

        check(cap_n == XFER_COUNT,
              $sformatf("DSP produced %0d samples, expected %0d", cap_n, XFER_COUNT));

        // Sample 0 to the right, sample 1 to the left, alternating. Each
        // channel holds its value until its next turn, so between updates the
        // other channel must still read the sample before it.
        for (int i = 0; i < XFER_COUNT && i < cap_n; i++) begin
            automatic logic [19:0] a = {XFER_PAGE, XFER_ADDR} + i;
            automatic logic [15:0] want = expect_sample(mem_byte(a));

            if (i[0] == 0)
                check(cap_r[i] == want,
                      $sformatf("sample %0d should be on the right, got r=%04h want %04h",
                                i, cap_r[i], want));
            else
                check(cap_l[i] == want,
                      $sformatf("sample %0d should be on the left, got l=%04h want %04h",
                                i, cap_l[i], want));
        end

        // The discriminator against a mono card, and it is doing real work:
        // run this bench with stereo left off and every per-sample check above
        // still passes, because a mono DSP writes each sample to BOTH channels
        // and so satisfies "sample i is on the right" and "sample i is on the
        // left" alike. Only the fact that the two channels then never differ
        // gives it away.
        begin
            automatic int differing = 0;
            for (int i = 1; i < XFER_COUNT && i < cap_n; i++)
                if (cap_l[i] != cap_r[i]) differing++;
            check(differing > 0,
                  "left and right carried identical samples - interleave never happened");
        end

        if (errors == 0)
            $display("PASS: %0d samples interleaved right-first across both channels", cap_n);
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
