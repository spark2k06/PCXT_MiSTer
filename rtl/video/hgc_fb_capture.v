//============================================================================
//
//  Captures a 350-line HGC/MDA picture into DDRAM, one frame per buffer.
//
//  A 15 kHz television cannot scan 350 lines progressively, and 480i can only
//  carry them a whole frame at a time: each field holds half of them, so the
//  second half is wanted a field after the source finished delivering it.
//  That is what the framebuffer is for. No line buffer of any depth helps -
//  the source hands over 350 lines in 16 ms and the output wants them spread
//  over 33.
//
//  Written as it comes off the palette, two pixels to a 64 bit beat, eight
//  bits a channel. Addressing is linear: every active line writes the same
//  number of beats, so the DDRAM side counts words and is never handed an
//  address.
//
//  Only whole frames are published. A buffer becomes visible when its last
//  line has been accepted and not before, and a frame whose lines did not come
//  out the length the geometry promised is discarded rather than shown, so a
//  mode change landing mid-picture cannot put half of one picture and half of
//  another on the screen.
//
//============================================================================

`default_nettype wire

module hgc_fb_capture #(
    // 64 bit word address of the first buffer. The framework's own
    // framebuffer sits at byte 0x24000000 and is not enabled in this core;
    // this is clear of it, at byte 0x30000000.
    parameter [28:0] BASE_ADDR   = 29'h6000000,
    // Words per buffer. 720x350 at two pixels a word is 126000 words; rounded
    // up to a power of two so picking a buffer is a bit, not a multiply.
    parameter [28:0] BUFFER_SIZE = 29'h40000,
    // Beats per DDRAM write burst.
    parameter integer BURST      = 32,
    // Beats the FIFO holds. Two dots a word at 16.257 MHz makes 512 words
    // about 63 us of tolerance for the memory being busy elsewhere - a line.
    parameter integer FIFO_DEPTH = 512
) (
    input  wire        clk,
    input  wire        reset,

    // High while the CRTC is programmed for a picture that needs converting.
    // Read at the frame boundary only, so it cannot change mid-capture.
    input  wire        enable,

    // Video, in this clock domain.
    input  wire        ce_pix,
    input  wire [7:0]  r,
    input  wire [7:0]  g,
    input  wire [7:0]  b,
    input  wire        de,
    input  wire        vblank,

    // Geometry of the picture, itself held still for the frame.
    input  wire [11:0] active_dots,
    input  wire [9:0]  active_lines,

    // Which buffer the raster is showing. Two buffers are not enough: the
    // reader holds one for a whole 480i frame, 33 ms, and the source produces
    // one every 17, so with two the writer comes back round to the buffer on
    // screen every single time. With three it can always be told to go
    // somewhere else.
    input  wire [1:0]  reading_buffer,

    // DDRAM write port.
    input  wire        ddram_busy,
    output reg  [7:0]  ddram_burstcnt,
    output reg  [28:0] ddram_addr,
    output wire [63:0] ddram_din,
    output wire [7:0]  ddram_be,
    output reg         ddram_we,

    // The last frame written in full. Stable until the next one is published,
    // and frame_seq moves only when it is.
    output reg  [1:0]  frame_buffer,
    output reg [11:0]  frame_width,
    output reg [9:0]   frame_height,
    output reg [13:0]  frame_stride,   // 64 bit words per line
    output reg [7:0]   frame_seq,
    output reg         frame_valid,

    // Set for the rest of a frame whose FIFO ran full, and that frame is not
    // published. Says the memory could not keep up, which is a bandwidth
    // problem rather than anything the picture did.
    output reg         overrun
);

    localparam integer FIFO_AW = $clog2(FIFO_DEPTH);

    //------------------------------------------------------------------------
    // Frame and line structure, taken from the picture rather than from sync.
    //
    // Display enable is the one thing that means the same on both dot clocks.
    // The 350 line modes run off the 16.257 MHz accumulator, where dots are
    // one or two clocks apart, so counting clocks would give a different width
    // from one line to the next.
    //------------------------------------------------------------------------
    reg de_q     = 1'b0;
    reg vblank_q = 1'b1;

    wire de_rise     = ce_pix &&  de     && !de_q;
    wire de_fall     = ce_pix && !de     &&  de_q;
    wire vblank_rise = ce_pix &&  vblank && !vblank_q;
    wire vblank_fall = ce_pix && !vblank &&  vblank_q;

    // Words a line occupies: half the active dots, rounded up so an odd width
    // still ends on a whole beat.
    wire [13:0] stride_now = {2'b00, active_dots[11:1]} + {13'd0, active_dots[0]};

    reg         capturing = 1'b0;      // enable, latched for the whole frame
    reg         lines_full = 1'b1;     // no line has come up short this frame
    reg         kept_up = 1'b1;        // the FIFO has not dropped a word
    wire        frame_ok = lines_full & kept_up;
    reg [1:0]   wr_buffer = 2'd0;
    reg [9:0]   line_count = 10'd0;
    reg [13:0]  word_count = 14'd0;    // words pushed for the current line
    reg         phase = 1'b0;          // which half of the beat being built
    reg [31:0]  pixel_hold = 32'd0;

    reg [11:0]  frame_dots = 12'd0;
    reg [9:0]   frame_lines = 10'd0;
    reg [13:0]  frame_words = 14'd0;

    reg [FIFO_AW:0] fifo_wr = 0;
    reg [FIFO_AW:0] fifo_rd = 0;
    wire [FIFO_AW:0] fifo_level = fifo_wr - fifo_rd;
    wire fifo_full  = fifo_level >= FIFO_DEPTH;
    wire fifo_empty = fifo_level == 0;

    reg        push = 1'b0;
    reg [63:0] push_data = 64'd0;

    wire [31:0] pixel_now = {8'h00, r, g, b};

    // The lowest numbered buffer that is neither being shown nor the one
    // already published. With three there is always one.
    wire [1:0] free_buffer =
        ((2'd0 != frame_buffer) && (2'd0 != reading_buffer)) ? 2'd0 :
        ((2'd1 != frame_buffer) && (2'd1 != reading_buffer)) ? 2'd1 : 2'd2;

    // Display enable rising and the first dot of the line are the same clock,
    // so the line counters have to read as already reset on it. Taking them at
    // face value there uses the previous line's finished values and throws the
    // first dot of every line away.
    wire [13:0] word_count_eff = de_rise ? 14'd0 : word_count;
    wire [9:0]  line_count_eff = (de_fall && capturing) ? (line_count + 10'd1)
                                                       : line_count;
    wire        phase_eff      = de_rise ? 1'b0  : phase;

    //------------------------------------------------------------------------
    // Video side: pack pixels into beats and account for the frame.
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        push <= 1'b0;

        if (reset) begin
            de_q         <= 1'b0;
            vblank_q     <= 1'b1;
            capturing    <= 1'b0;
            lines_full   <= 1'b1;
            kept_up      <= 1'b1;
            wr_buffer    <= 2'd0;
            line_count   <= 10'd0;
            word_count   <= 14'd0;
            phase        <= 1'b0;
            overrun      <= 1'b0;
            frame_valid  <= 1'b0;
            frame_seq    <= 8'd0;
            frame_buffer <= 2'd0;
            frame_width  <= 12'd0;
            frame_height <= 10'd0;
            frame_stride <= 14'd0;
            frame_dots   <= 12'd0;
            frame_lines  <= 10'd0;
            frame_words  <= 14'd0;
        end else begin
            if (ce_pix) begin
                de_q     <= de;
                vblank_q <= vblank;
            end

            // Start of the visible field. Everything about the frame is fixed
            // here and does not move again until the next one, the buffer it
            // goes into included: whichever of the three is neither on screen
            // nor the one already published.
            if (vblank_fall) begin
                wr_buffer   <= free_buffer;
                capturing   <= enable;
                lines_full  <= 1'b1;
                kept_up     <= 1'b1;
                line_count  <= 10'd0;
                word_count  <= 14'd0;
                phase       <= 1'b0;
                overrun     <= 1'b0;
                frame_dots  <= active_dots;
                frame_lines <= active_lines;
                frame_words <= stride_now;
            end

            if (de_rise) begin
                word_count <= 14'd0;
                phase      <= 1'b0;
            end

            // Two pixels make a beat, earlier pixel in the low half, so a
            // reader walking the buffer forwards walks the line left to right.
            // Never more than the line was promised to hold: a line longer
            // than the geometry says would otherwise push the rest of the
            // frame along by however many words it overran.
            if (capturing && de && ce_pix && (word_count_eff < frame_words)) begin
                phase <= ~phase;
                if (!phase_eff) begin
                    pixel_hold <= pixel_now;
                end else begin
                    push       <= 1'b1;
                    push_data  <= {pixel_now, pixel_hold};
                    word_count <= word_count_eff + 14'd1;
                end
            end

            if (de_fall && capturing) begin
                // An odd width leaves half a beat at the end of the line.
                // Finish it with black rather than letting the next line run
                // into it and shift the picture by a pixel.
                if (phase && (word_count < frame_words)) begin
                    push       <= 1'b1;
                    push_data  <= {32'h00000000, pixel_hold};
                    word_count <= word_count + 14'd1;
                end
                else if (word_count != frame_words) begin
                    // Short line. The buffer is already out of step with the
                    // stride from here on, so this frame is not publishable.
                    lines_full <= 1'b0;
                end

                line_count <= line_count + 10'd1;
            end

            // A dropped word does not tear one line, it shifts everything
            // after it, so an overrun frame is no more publishable than a
            // short one. Persistent overrun freezes the picture on the last
            // good frame, which is at least a symptom someone can name.
            if (push && fifo_full) begin
                overrun <= 1'b1;
                kept_up <= 1'b0;
            end

            // End of the picture. If the last line's display enable falls on
            // the same clock as vertical blanking starts, that line still
            // belongs to this frame - reading the counter before its own
            // increment would lose it and reject every frame.
            if (vblank_rise) begin
                if (capturing && frame_ok && (line_count_eff == frame_lines)) begin
                    frame_buffer <= wr_buffer;
                    frame_width  <= frame_dots;
                    frame_height <= frame_lines;
                    frame_stride <= frame_words;
                    frame_seq    <= frame_seq + 8'd1;
                    frame_valid  <= 1'b1;
                end
                if (!enable)
                    frame_valid <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------------
    // Beat FIFO. One clock at both ends, so a plain ring: video pushes, DDRAM
    // pops in bursts. Read through a register, because an M10K cannot be read
    // combinationally and 32 Kib of it in logic would be an expensive way to
    // save a clock.
    //------------------------------------------------------------------------
    (* ramstyle = "M10K, no_rw_check" *) reg [63:0] fifo [0:FIFO_DEPTH-1];
    reg [63:0] fifo_q = 64'd0;

    // The address is chosen from this clock's decision, not a registered copy
    // of it, so the word landing in fifo_q is the one wanted on the clock the
    // pointer moves to it.
    wire pop;
    wire [FIFO_AW-1:0] fifo_rd_next = pop ? (fifo_rd[FIFO_AW-1:0] + 1'b1)
                                          : fifo_rd[FIFO_AW-1:0];

    always @(posedge clk) begin
        if (push && !fifo_full)
            fifo[fifo_wr[FIFO_AW-1:0]] <= push_data;
        fifo_q <= fifo[fifo_rd_next];
    end

    always @(posedge clk) begin
        if (reset || vblank_fall)
            fifo_wr <= 0;                   // anything left over is last frame's
        else if (push && !fifo_full)
            fifo_wr <= fifo_wr + 1'b1;
    end

    //------------------------------------------------------------------------
    // DDRAM side. Words leave the FIFO in the order they arrived and land in
    // consecutive addresses, so the only state is where the frame started and
    // how far into it we are.
    //------------------------------------------------------------------------
    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_PREP  = 2'd1;
    localparam [1:0] ST_BURST = 2'd2;

    reg [1:0]  state = ST_IDLE;
    reg [28:0] wr_addr = BASE_ADDR;
    reg [7:0]  beats_left = 8'd0;

    // Recomputed at the start of each visible field, from the buffer the video
    // side is about to fill. No burst can be in flight then: vertical blanking
    // is far longer than one.
    // wr_buffer takes its new value on the same clock this is used, so the
    // address has to be built from what it is about to be.
    wire [1:0]  wr_buffer_now = vblank_fall ? free_buffer : wr_buffer;
    // A burst may not cross a 4 KB boundary. The HPS bridge is AXI behind an
    // Avalon front and AXI forbids it, and a straddling burst is not split
    // for us. 512 words of 64 bits is 4 KB.
    wire [9:0] wr_to_edge = 10'd512 - {1'b0, wr_addr[8:0]};
    wire [7:0] wr_burst   = (wr_to_edge >= BURST) ? BURST[7:0] : wr_to_edge[7:0];

    wire [28:0] buffer_base = BASE_ADDR + (wr_buffer_now == 2'd0 ? 29'd0 :
                                           wr_buffer_now == 2'd1 ? BUFFER_SIZE
                                                                 : (BUFFER_SIZE + BUFFER_SIZE));

    // Vertical blanking is meant to arrive with this side idle: the picture
    // stopped a line ago and the FIFO drains in a fraction of the blanking.
    // If a burst is somehow still in flight - the reader had priority for a
    // long stretch, the memory was slow - the buffer switch waits for it.
    // Walking away mid-burst does not stop the memory counting beats; it just
    // means the rest of them carry whatever the FIFO happens to hold, written
    // over the frame that was about to be published.
    reg restart_pending = 1'b0;
    wire ddr_restart = (vblank_fall | restart_pending) && (state == ST_IDLE);

    assign ddram_din = fifo_q;
    assign ddram_be  = 8'hFF;
    assign pop       = (state == ST_BURST) && !ddram_busy;

    always @(posedge clk) begin
        if (reset) begin
            state          <= ST_IDLE;
            ddram_we       <= 1'b0;
            ddram_burstcnt <= 8'd0;
            ddram_addr     <= BASE_ADDR;
            wr_addr        <= BASE_ADDR;
            fifo_rd        <= 0;
            beats_left     <= 8'd0;
        end else begin
            // Noting the request must not cost the burst a beat, so this sits
            // alongside the state machine rather than in front of it.
            if (vblank_fall && (state != ST_IDLE))
                restart_pending <= 1'b1;

            if (ddr_restart) begin
                // Start of a field. Drop whatever the last frame left behind
                // and aim at the buffer this one is going into.
                state           <= ST_IDLE;
                ddram_we        <= 1'b0;
                wr_addr         <= buffer_base;
                fifo_rd         <= 0;
                beats_left      <= 8'd0;
                restart_pending <= 1'b0;
            end else case (state)
                ST_IDLE: begin
                    ddram_we <= 1'b0;
                    if (fifo_level >= {2'd0, wr_burst}) begin
                        ddram_addr     <= wr_addr;
                        ddram_burstcnt <= wr_burst;
                        beats_left     <= wr_burst;
                        state          <= ST_PREP;
                    end
                    else if (!fifo_empty && vblank) begin
                        // The picture has finished and no more is coming, so
                        // the tail goes out a beat at a time.
                        ddram_addr     <= wr_addr;
                        ddram_burstcnt <= 8'd1;
                        beats_left     <= 8'd1;
                        state          <= ST_PREP;
                    end
                end

                // One clock with the read pointer settled, so the FIFO's
                // output register is holding the first beat before the memory
                // is allowed to take it.
                ST_PREP: begin
                    ddram_we <= 1'b1;
                    state    <= ST_BURST;
                end

                ST_BURST: begin
                    // A beat is taken every clock the memory is not busy, and
                    // ddram_din already holds the next word.
                    if (!ddram_busy) begin
                        fifo_rd    <= fifo_rd + 1'b1;
                        wr_addr    <= wr_addr + 29'd1;
                        beats_left <= beats_left - 8'd1;
                        if (beats_left == 8'd1) begin
                            ddram_we <= 1'b0;
                            state    <= ST_IDLE;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule


