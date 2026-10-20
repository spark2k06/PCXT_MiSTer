//============================================================================
//
//  What ega_fb_capture must put in DDRAM, and what it must refuse to publish.
//
//  A synthetic raster stands in for the EGA here, small enough to simulate a
//  dozen frames in seconds but with the same shape as the real thing: a
//  blanking interval, a fixed number of active lines, a fixed active width,
//  and a pixel value that encodes where it came from so a misplaced byte is
//  identifiable rather than merely wrong.
//
//  The DDRAM model is deliberately awkward. It holds the bus busy in bursts of
//  its own choosing, which is what the real memory does when the HPS is using
//  it, and it records every beat it accepts along with the address, so the
//  bench can check the frame that landed rather than the requests that were
//  made.
//
//  Checked here:
//    * a captured frame reads back pixel for pixel, in the right place,
//    * the buffer moves on every frame and a published one is never the one
//      being written,
//    * frame_seq advances once per frame and only for whole frames,
//    * a mode change part way through a picture is discarded, not published,
//    * nothing is written at all while the converter is disabled,
//    * the memory being busy for long stretches does not corrupt anything.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_fb_capture_tb;

    localparam integer WIDTH  = 32;    // active dots per line
    localparam integer HEIGHT = 12;    // active lines per frame
    localparam integer HBLANK = 16;    // dots of horizontal blanking
    localparam integer VBLANK = 4;     // lines of vertical blanking

    localparam [28:0] BASE  = 29'h100;
    localparam [28:0] BUFSZ = 29'h200;

    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg reset = 1'b1;
    reg enable = 1'b0;
    reg ce_pix = 1'b0;
    reg [7:0] r = 8'd0, g = 8'd0, b = 8'd0;
    reg de = 1'b0;
    reg vblank = 1'b1;
    reg [11:0] active_dots = WIDTH[11:0];
    reg [9:0]  active_lines = HEIGHT[9:0];

    wire [7:0]  ddram_burstcnt;
    wire [28:0] ddram_addr;
    wire [63:0] ddram_din;
    wire [7:0]  ddram_be;
    wire        ddram_we;
    reg         ddram_busy = 1'b0;

    wire [1:0]  frame_buffer;
    wire [11:0] frame_width;
    wire [9:0]  frame_height;
    wire [13:0] frame_stride;
    wire [7:0]  frame_seq;
    wire        frame_valid;
    wire        overrun;

    ega_fb_capture #(
        .BASE_ADDR(BASE),
        .BUFFER_SIZE(BUFSZ),
        .BURST(8),
        .FIFO_DEPTH(32)
    ) dut (
        .clk(clk), .reset(reset), .enable(enable),
        .ce_pix(ce_pix), .r(r), .g(g), .b(b), .de(de), .vblank(vblank),
        .active_dots(active_dots), .active_lines(active_lines),
        .reading_buffer(2'd0),
        .ddram_busy(ddram_busy), .ddram_burstcnt(ddram_burstcnt),
        .ddram_addr(ddram_addr), .ddram_din(ddram_din), .ddram_be(ddram_be),
        .ddram_we(ddram_we),
        .frame_buffer(frame_buffer), .frame_width(frame_width),
        .frame_height(frame_height), .frame_stride(frame_stride),
        .frame_seq(frame_seq), .frame_valid(frame_valid), .overrun(overrun)
    );

    integer errors = 0;

    initial begin
        #4_000_000;
        $display("[ega_fb_capture_tb] TIMEOUT");
        $display("[ega_fb_capture_tb] RESULT: FAIL");
        $finish;
    end

    //------------------------------------------------------------------------
    // DDRAM model: a sparse memory, a burst counter, and a busy signal that
    // gets in the way on purpose.
    //------------------------------------------------------------------------
    reg [63:0] mem [0:1023];
    reg        mem_written [0:1023];
    reg [28:0] burst_addr = 29'd0;
    reg [8:0]  burst_left = 9'd0;
    integer    beats_taken = 0;
    integer    k;

    // Pseudo-random busy, biased so the memory is available most of the time
    // but stalls for a run of clocks now and then, which is what a burst of
    // HPS traffic looks like from here.
    reg [15:0] lfsr = 16'hACE1;
    reg [3:0]  busy_run = 4'd0;
    reg        stall_memory = 1'b0;

    always @(posedge clk) begin
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        if (stall_memory) begin
            ddram_busy <= 1'b1;
        end else if (busy_run != 0) begin
            busy_run   <= busy_run - 4'd1;
            ddram_busy <= 1'b1;
        end else if (lfsr[3:0] == 4'h0) begin
            busy_run   <= lfsr[7:4];
            ddram_busy <= 1'b1;
        end else begin
            ddram_busy <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (ddram_we && !ddram_busy) begin
            if (burst_left == 0) begin
                burst_addr <= ddram_addr + 29'd1;
                burst_left <= {1'b0, ddram_burstcnt} - 9'd1;
                mem[ddram_addr[9:0]] <= ddram_din;
                mem_written[ddram_addr[9:0]] <= 1'b1;
            end else begin
                burst_addr <= burst_addr + 29'd1;
                burst_left <= burst_left - 9'd1;
                mem[burst_addr[9:0]] <= ddram_din;
                mem_written[burst_addr[9:0]] <= 1'b1;
            end
            beats_taken <= beats_taken + 1;
        end
    end

    //------------------------------------------------------------------------
    // Synthetic raster. One ce_pix every four clocks, so the FIFO is not fed
    // faster than the memory could ever drain it by construction.
    //------------------------------------------------------------------------
    integer div = 0;
    always @(posedge clk) begin
        div <= div + 1;
        ce_pix <= (div[1:0] == 2'b00);
    end

    integer frame_no = 0;
    integer line_no, dot_no;
    integer stop_after = 0;      // frames to emit; the driver counts down

    // One dot: present it, then wait for the clock edge the capture samples it
    // on. Driving on the pixel enable's own edge instead would hand the DUT
    // the following dot, because the enable is registered and the value it
    // sees is the one that was there before the edge.
    task drive_dot(input dd, input [7:0] rr, input [7:0] gg, input [7:0] bb);
        begin
            @(negedge clk);
            de <= dd; r <= rr; g <= gg; b <= bb;
            @(posedge clk);
            while (ce_pix !== 1'b1) @(posedge clk);
        end
    endtask

    task drive_blank(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) drive_dot(1'b0, 8'd0, 8'd0, 8'd0);
        end
    endtask

    // Every pixel says which frame, line and dot it is: red is the frame, green
    // the line, blue the dot. A byte in the wrong place is then identifiable.
    task emit_frame(input integer fno, input integer lines, input integer dots);
        begin
            // Vertical blanking first, so the capture sees a clean field start.
            @(negedge clk);
            vblank <= 1'b1;
            drive_blank(VBLANK * (dots + HBLANK));

            @(negedge clk);
            vblank <= 1'b0;
            // Back porch. Every CRTC raster leaves blanking between the end of
            // vertical blanking and the first displayed dot, and the capture
            // uses that gap to arm itself for the frame.
            drive_blank(HBLANK);
            for (line_no = 0; line_no < lines; line_no = line_no + 1) begin
                for (dot_no = 0; dot_no < dots; dot_no = dot_no + 1)
                    drive_dot(1'b1, fno[7:0], line_no[7:0], dot_no[7:0]);
                drive_blank(HBLANK);
            end

            @(negedge clk);
            vblank <= 1'b1;
            // A couple of blanked lines so the tail of the frame drains.
            drive_blank(2 * (dots + HBLANK));
        end
    endtask

    //------------------------------------------------------------------------
    // Checks
    //------------------------------------------------------------------------
    task check_frame(input integer fno, input integer buf_sel,
                     input integer lines, input integer dots);
        integer li, di, widx, half;
        reg [28:0] base;
        reg [31:0] pix;
        begin
            base = BASE + buf_sel * BUFSZ;
            for (li = 0; li < lines; li = li + 1) begin
                for (di = 0; di < dots; di = di + 1) begin
                    widx = base + li*(dots/2) + (di/2);
                    half = di % 2;
                    pix  = half ? mem[widx[9:0]][63:32] : mem[widx[9:0]][31:0];
                    if (pix !== {8'h00, fno[7:0], li[7:0], di[7:0]}) begin
                        $display("FAIL frame %0d line %0d dot %0d: word %0h holds %08h, expected %08h",
                                 fno, li, di, widx, pix,
                                 {8'h00, fno[7:0], li[7:0], di[7:0]});
                        errors = errors + 1;
                        if (errors > 8) begin
                            $display("[ega_fb_capture_tb] RESULT: FAIL");
                            $finish;
                        end
                    end
                end
            end
        end
    endtask

    integer seq_before;
    integer buf_before;
    integer beats_before;

    initial begin
        for (k = 0; k < 1024; k = k + 1) begin
            mem[k] = 64'd0;
            mem_written[k] = 1'b0;
        end

        repeat (8) @(posedge clk);
        reset <= 1'b0;
        repeat (8) @(posedge clk);

        //--------------------------------------------------------------------
        // Disabled: the memory must not be touched at all.
        //--------------------------------------------------------------------
        enable <= 1'b0;
        emit_frame(1, HEIGHT, WIDTH);
        if (beats_taken != 0) begin
            $display("FAIL %0d beats were written with the converter disabled", beats_taken);
            errors = errors + 1;
        end
        if (frame_valid !== 1'b0) begin
            $display("FAIL a frame was published with the converter disabled");
            errors = errors + 1;
        end

        //--------------------------------------------------------------------
        // Three frames in a row. Each has to land whole, in the buffer that is
        // not the one just published, with the sequence advancing by one.
        //--------------------------------------------------------------------
        enable <= 1'b1;
        for (frame_no = 2; frame_no <= 4; frame_no = frame_no + 1) begin
            seq_before = frame_seq;
            emit_frame(frame_no, HEIGHT, WIDTH);

            if (frame_valid !== 1'b1) begin
                $display("FAIL frame %0d was not published", frame_no);
                errors = errors + 1;
            end
            if (frame_seq != ((seq_before + 1) % 256)) begin
                $display("FAIL frame %0d moved the sequence from %0d to %0d",
                         frame_no, seq_before, frame_seq);
                errors = errors + 1;
            end
            if (frame_width != WIDTH || frame_height != HEIGHT) begin
                $display("FAIL frame %0d published as %0dx%0d",
                         frame_no, frame_width, frame_height);
                errors = errors + 1;
            end
            if (frame_stride != WIDTH/2) begin
                $display("FAIL frame %0d published a stride of %0d words, expected %0d",
                         frame_no, frame_stride, WIDTH/2);
                errors = errors + 1;
            end
            if (overrun !== 1'b0) begin
                $display("FAIL frame %0d overran the FIFO", frame_no);
                errors = errors + 1;
            end

            check_frame(frame_no, frame_buffer, HEIGHT, WIDTH);
        end

        //--------------------------------------------------------------------
        // The buffers have to alternate, or the reader would be handed the one
        // being overwritten.
        //--------------------------------------------------------------------
        buf_before = frame_buffer;
        seq_before = frame_seq;
        emit_frame(5, HEIGHT, WIDTH);
        if (frame_buffer == buf_before) begin
            $display("FAIL two frames in a row were published from buffer %0d", buf_before);
            errors = errors + 1;
        end
        check_frame(5, frame_buffer, HEIGHT, WIDTH);

        //--------------------------------------------------------------------
        // A picture that stops short of the geometry it declared. This is what
        // a mode change lands as, and half of one picture on top of half of
        // another is worse than showing the previous frame again, so it must
        // not be published.
        //--------------------------------------------------------------------
        seq_before = frame_seq;
        buf_before = frame_buffer;
        emit_frame(6, HEIGHT - 3, WIDTH);
        if (frame_seq != seq_before) begin
            $display("FAIL a %0d line picture was published as a %0d line frame",
                     HEIGHT - 3, HEIGHT);
            errors = errors + 1;
        end
        if (frame_buffer != buf_before) begin
            $display("FAIL the buffer moved on for a frame that was never published");
            errors = errors + 1;
        end
        // ... and the last good frame is still intact behind it.
        check_frame(5, buf_before, HEIGHT, WIDTH);

        //--------------------------------------------------------------------
        // A line shorter than declared, the other way a mode change lands.
        //--------------------------------------------------------------------
        seq_before = frame_seq;
        emit_frame(7, HEIGHT, WIDTH - 4);
        if (frame_seq != seq_before) begin
            $display("FAIL a %0d dot picture was published as a %0d dot frame",
                     WIDTH - 4, WIDTH);
            errors = errors + 1;
        end

        //--------------------------------------------------------------------
        // Memory that never frees up. Words are dropped, and a dropped word
        // does not tear one line - it shifts every line after it - so the
        // frame must be refused, not shown sheared.
        //--------------------------------------------------------------------
        seq_before = frame_seq;
        stall_memory <= 1'b1;
        emit_frame(9, HEIGHT, WIDTH);
        stall_memory <= 1'b0;
        if (overrun !== 1'b1) begin
            $display("FAIL the FIFO did not report an overrun with the memory held busy");
            errors = errors + 1;
        end
        if (frame_seq != seq_before) begin
            $display("FAIL a frame that lost words to an overrun was published");
            errors = errors + 1;
        end

        //--------------------------------------------------------------------
        // And back to normal afterwards: a rejected frame must not leave the
        // capture stuck.
        //--------------------------------------------------------------------
        seq_before = frame_seq;
        emit_frame(8, HEIGHT, WIDTH);
        if (frame_seq != ((seq_before + 1) % 256)) begin
            $display("FAIL capture did not recover after a discarded frame");
            errors = errors + 1;
        end
        check_frame(8, frame_buffer, HEIGHT, WIDTH);

        $display("");
        $display("  %0d beats accepted by the memory model over the run", beats_taken);
        $display("");

        if (errors == 0) $display("[ega_fb_capture_tb] RESULT: PASS");
        else             $display("[ega_fb_capture_tb] RESULT: FAIL");
        $finish;
    end

endmodule
