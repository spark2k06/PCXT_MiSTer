//============================================================================
//
//  A video I/O read must hold the CPU until the answer can be back.
//
//  ega_io_stretch closed the write side of the crossing: a write is posted in
//  the chipset domain and presented to the video side with a guaranteed width.
//  Reads had no completion signal at all. access_ready meant "the bus is free",
//  not "the card has answered", so the CPU was released the instant a draining
//  write let go - or, for an isolated read, never held at all - and it latched
//  internal_data_bus while the answer was still crossing.
//
//  On hardware that showed up as a palette that read back wrong roughly once
//  in every 1600 bytes at the PC/AT 3.5MHz setting, and nowhere else. The write
//  side was never involved: the DAC's own write index came back exact on every
//  burst, and pacing the reads apart - same data, same comparison, only slower
//  - made the errors vanish.
//
//  The return trip is two synchroniser stages out at 28.636 MHz, the
//  two-identical-samples qualifier in ega_top, the decode, and two stages back
//  at 50 MHz. This bench does not model any of that, and does not model the
//  CPU either. It asks ega_io_stretch one question that needs neither: once a
//  read has been presented to the video domain, does access_ready stay low
//  long enough for the answer to make the journey.
//
//  The distinction the bench exists to protect is where the counter starts. A
//  read issued behind a draining write reaches the card late, so it has to be
//  given the return trip measured from when it was presented, not from when
//  the CPU raised its strobe - which is what io_settle_ticks in Chipset.sv
//  does, and why that floor alone never covered this case.
//
//  The second distinction is which ports pay it. The module originally decoded
//  no address, so every I/O read in the machine was charged the video round
//  trip: 12 chipset clocks on the 8253, the 8255, the FDC, the UART, the RTC
//  and everything else that answers inside the chipset domain and never
//  crosses to 28.636 MHz at all. Those keep the io_settle_ticks floor, which
//  is what they were sized against. The reads below therefore use real video
//  ports, and the last case pins the exemption so it cannot silently grow back
//  to cover the whole machine - or silently shrink and take 3DAh with it.
//
//============================================================================

`timescale 1ns/1ps

module ega_io_read_ready_tb;

    reg clk50 = 1'b0;
    always #10 clk50 = ~clk50;
    reg reset = 1'b1;

    // 3DAh: the input status register, and the retrace poll a fade loop issues
    // between palette writes - the exact read RC8 was found on.
    reg  [14:0] addr  = 15'h03DA;
    reg  [7:0]  data  = 8'h00;
    reg         iow_n = 1'b1;
    reg         ior_n = 1'b1;

    wire [14:0] v_addr;
    wire [7:0]  v_data;
    wire        v_iow_n, v_ior_n, v_aen_n, access_ready;

    ega_io_stretch dut (
        .clock                  (clk50),
        .reset                  (reset),
        .io_write_n             (iow_n),
        .io_read_n              (ior_n),
        .address_enable_n       (1'b0),
        .address                (addr),
        .write_data             (data),
        .video_address          (v_addr),
        .video_data             (v_data),
        .video_io_write_n       (v_iow_n),
        .video_io_read_n        (v_ior_n),
        .video_address_enable_n (v_aen_n),
        .access_ready           (access_ready)
    );

    // The far side needs the strobe to survive its two synchroniser stages and
    // then two identical samples of the qualifier before it will decode, and
    // the answer needs two more stages coming back. At 28.636 MHz against a
    // 50 MHz chipset clock that is six chipset clocks even before any phase
    // penalty, so anything below this is not a margin, it is a coincidence.
    localparam integer MIN_HOLD_AFTER_PRESENT = 8;

    integer pass_count = 0;
    integer fail_count = 0;

    integer presented_at;
    integer released_at;
    integer k;

    // Drive a read and record, in chipset clocks from the strobe, when it
    // reached the video domain and when the CPU was let go.
    task automatic do_read;
        begin
            presented_at = -1;
            released_at  = -1;
            @(posedge clk50);
            ior_n <= 1'b0;
            for (k = 0; k < 80; k = k + 1) begin
                @(posedge clk50);
                if ((presented_at < 0) && !v_ior_n)
                    presented_at = k;
                if ((presented_at >= 0) && (released_at < 0) && access_ready)
                    released_at = k;
            end
            ior_n <= 1'b1;
            @(posedge clk50);
        end
    endtask

    task automatic check(input [255:0] label);
        integer held;
        begin
            if (presented_at < 0) begin
                fail_count = fail_count + 1;
                $display("  FAIL  %0s: the read never reached the video domain", label);
            end
            else begin
                held = (released_at < 0) ? 80 - presented_at
                                         : released_at - presented_at;
                if (held >= MIN_HOLD_AFTER_PRESENT) begin
                    pass_count = pass_count + 1;
                    $display("  PASS  %0s: presented at clock %0d, CPU held %0d clocks after it (%0d ns)",
                             label, presented_at, held, held * 20);
                end
                else begin
                    fail_count = fail_count + 1;
                    $display("  FAIL  %0s: presented at clock %0d, CPU released %0d clocks after it (%0d ns), needs %0d",
                             label, presented_at, held, held * 20,
                             MIN_HOLD_AFTER_PRESENT);
                end
            end
        end
    endtask

    // The mirror of `check`: a port the video card never decodes must not be
    // charged the round trip it does not make.
    task automatic check_not_held(input [255:0] label);
        integer held;
        begin
            if (presented_at < 0) begin
                fail_count = fail_count + 1;
                $display("  FAIL  %0s: the read never reached the video domain", label);
            end
            else begin
                held = (released_at < 0) ? 80 - presented_at
                                         : released_at - presented_at;
                if (held < MIN_HOLD_AFTER_PRESENT) begin
                    pass_count = pass_count + 1;
                    $display("  PASS  %0s: presented at clock %0d, CPU held %0d clocks (%0d ns) - not charged the video round trip",
                             label, presented_at, held, held * 20);
                end
                else begin
                    fail_count = fail_count + 1;
                    $display("  FAIL  %0s: held %0d clocks (%0d ns) for a port the video card does not decode",
                             label, held, held * 20);
                end
            end
        end
    endtask

    initial begin
        $display("");
        $display("=== a video read must hold the CPU until the answer can be back ===");
        $display("");

        repeat (10) @(posedge clk50);
        reset = 1'b0;
        repeat (10) @(posedge clk50);

        // Nothing else on the bus: the read is presented immediately, and the
        // hold has to come from the read itself.
        do_read;
        check("isolated read");

        repeat (30) @(posedge clk50);

        // Straight behind a posted write, which is where a fade loop's retrace
        // poll lands. The read is presented late; the hold has to start there.
        @(posedge clk50);
        addr <= 15'h03C8; data <= 8'h5A; iow_n <= 1'b0;
        repeat (4) @(posedge clk50);
        iow_n <= 1'b1;
        @(posedge clk50);
        do_read;
        check("read chasing a posted write");

        repeat (30) @(posedge clk50);

        // A port the video card never decodes. 40h is 8253 counter 0, which
        // answers in the chipset domain in a couple of clocks; charging it the
        // 28.636 MHz round trip is pure loss, and at the PC/AT 3.5MHz setting
        // it was 12 clocks against a 160 ns bus cycle.
        @(posedge clk50);
        addr <= 15'h0040;
        @(posedge clk50);
        do_read;
        check_not_held("read from a non-video port");

        $display("");
        $display("%0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0) $display("RESULT: PASS");
        else                 $display("RESULT: FAIL");
        $display("");
        $finish;
    end

endmodule
