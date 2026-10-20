`timescale 1ns/1ps

// The discriminator for sb_dma_glue.
//
// sb_dma_cycle_tb proved a single channel-1 cycle reaches the bus correctly.
// That is not enough to know playback works: the failure modes that matter for
// audio are dropped and duplicated samples, and both look fine for one
// transfer. This bench streams a whole block through the real BUS_ARBITER and
// KF8237 and asserts the device received every byte, in order, exactly once.
//
// The device stub requests continuously rather than at a sample rate, which is
// the hardest case for the glue - back-to-back DMA cycles with no idle gap
// between them. The real DSP paces itself far slower.
//
// Runs under Verilator; Icarus cannot elaborate the KF8237.
module sb_dma_stream_tb;

    localparam TB_CYCLE = 200;

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

    // Channel 1 comes from the glue; the rest are idle.
    wire          sb_dma_request;
    logic [3:0]   dma_request_drive;
    assign dma_request = {2'b00, sb_dma_request, 1'b0};

    BUS_ARBITER dut (.*);

    // ---------------------------------------------------------------- memory
    function automatic [7:0] mem_byte(input [19:0] a);
        mem_byte = a[7:0] ^ 8'h5A;
    endfunction

    always_comb begin
        if (~memory_read_n) data_bus_ext = mem_byte(address);
        else                data_bus_ext = 8'hFF;
    end

    // ------------------------------------------------------------------- glue
    wire       device_dma_ack;
    wire [7:0] device_dma_readdata;

    sb_dma_glue u_glue (
        .clock                  (clock),
        .reset                  (reset),
        .cpu_ce_negedge         (cpu_ce_negedge),
        .dma_acknowledge        (~dma_acknowledge_n[1]),
        .io_write_n             (io_write_n),
        .internal_data_bus      (internal_data_bus),
        .dma_request            (sb_dma_request),
        .device_dma_req         (device_wants_data),
        .device_dma_ack         (device_dma_ack),
        .device_dma_readdata    (device_dma_readdata)
    );

    // ----------------------------------------------------------- device stub
    localparam int XFER_COUNT = 16;

    // The stub stops asking once it has its block, exactly as sound_dsp does -
    // the DSP runs its own len_left counter and drops the request when it hits
    // zero. That self-limiting matters here, because this core's KF8237 does
    // NOT mask a channel at terminal count the way a real 8237 does: its
    // mask_register is only ever written by software. A device that kept
    // requesting past TC would keep being served. See the note by the
    // terminal-count check below.
    logic        streaming = 1'b0;
    logic [7:0]  received [0:63];
    int          received_n = 0;

    wire         device_wants_data = streaming && (received_n < XFER_COUNT);

    always @(posedge clock) begin
        if (device_dma_ack) begin
            if (received_n < 64) received[received_n] <= device_dma_readdata;
            received_n <= received_n + 1;
        end
    end

    // Terminal count as the peripheral side sees it. The naming in
    // Bus_Arbiter is inverted twice over - the KF8237 emits an active-low EOP
    // into a wire called terminal_count, which is then inverted into
    // terminal_count_n - so what arrives here, and what Peripherals.sv passes
    // to the floppy as `terminal_count`, is active HIGH.
    logic        tc_at_last_byte  = 1'b0;
    logic        tc_at_first_byte = 1'b0;

    always @(posedge clock) begin
        if (~dma_acknowledge_n[1] && terminal_count_n) begin
            if (received_n == XFER_COUNT - 1) tc_at_last_byte  <= 1'b1;
            if (received_n == 0)              tc_at_first_byte <= 1'b1;
        end
    end

    // Diagnostics: how many DMA cycles the controller actually ran, versus how
    // many acknowledges the glue produced. If these disagree the glue is
    // over-acknowledging; if they agree and both exceed the count, the
    // controller never stopped.
    int          memr_cycles = 0;
    logic        prev_memr_active = 1'b0;
    wire         memr_active = ~dma_acknowledge_n[1] & ~memory_read_n;

    always @(posedge clock) begin
        prev_memr_active <= memr_active;
        if (memr_active & ~prev_memr_active) memr_cycles <= memr_cycles + 1;
    end

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
            #(TB_CYCLE * 1);
        end
    endtask

    task automatic dma_write(input [3:0] reg_addr, input [7:0] data);
        begin
            dma_chip_select_n = 1'b0;
            io_write({16'h0000, reg_addr}, data);
            dma_chip_select_n = 1'b1;
        end
    endtask

    int errors = 0;

    task automatic check(input cond, input string what);
        begin
            if (!cond) begin
                $display("FAIL: %s", what);
                errors++;
            end
        end
    endtask

    localparam [15:0] XFER_ADDR = 16'h1234;
    localparam [3:0]  XFER_PAGE = 4'h5;

    initial begin
        repeat (10) @(posedge clock);
        reset = 1'b0;
        #(TB_CYCLE * 4);

        dma_page_chip_select_n = 1'b0;
        io_write(20'h00083, {4'h0, XFER_PAGE});
        dma_page_chip_select_n = 1'b1;

        dma_write(4'hD, 8'h00);                     // master clear
        #(TB_CYCLE * 2);

        dma_write(4'hB, 8'h49);                     // single, increment, mem->dev, ch1
        dma_write(4'hC, 8'h00);                     // clear byte pointer
        dma_write(4'h2, XFER_ADDR[7:0]);
        dma_write(4'h2, XFER_ADDR[15:8]);
        dma_write(4'h3, XFER_COUNT - 1);            // count is transfers-1
        dma_write(4'h3, 8'h00);
        dma_write(4'hA, 8'h01);                     // unmask channel 1

        #(TB_CYCLE * 4);

        // Stream the whole block at maximum rate.
        streaming = 1'b1;
        #(TB_CYCLE * 600);
        streaming = 1'b0;
        #(TB_CYCLE * 10);

        // The glue must produce exactly one acknowledge per controller cycle.
        // These diverging is the failure that matters: an extra acknowledge
        // duplicates a sample, a missing one drops it, and both are audible
        // while a single-transfer test still passes.
        check(memr_cycles == received_n,
              $sformatf("controller ran %0d cycles but glue produced %0d acks",
                        memr_cycles, received_n));

        check(received_n == XFER_COUNT,
              $sformatf("device received %0d bytes, expected %0d", received_n, XFER_COUNT));

        check(tc_at_last_byte, "terminal count was not asserted on the final transfer");

        // Negative control for the check above: if terminal_count_n were
        // simply stuck high, tc_at_last_byte would pass while meaning nothing.
        check(!tc_at_first_byte, "terminal count was already asserted on the first transfer");

        for (int i = 0; i < XFER_COUNT && i < received_n; i++) begin
            automatic logic [19:0] a = {XFER_PAGE, XFER_ADDR} + i;
            check(received[i] == mem_byte(a),
                  $sformatf("byte %0d was %02h, expected %02h (from %05h)",
                            i, received[i], mem_byte(a), a));
        end

        if (errors == 0)
            $display("PASS: %0d bytes streamed in order, none dropped or repeated", received_n);
        else
            $display("RESULT: FAIL (%0d)", errors);
        $finish;
    end

    initial begin
        #(TB_CYCLE * 4000);
        $display("FAIL: TIMEOUT");
        $finish;
    end

endmodule
