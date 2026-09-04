//============================================================================
//
//  Reads a captured 350-line HGC/MDA frame back out on a 15 kHz raster.
//
//  The horizontal geometry is the one the 200 line modes already use and the
//  television is already calibrated for: 910 dots at 14.318 MHz, 15.734 kHz,
//  a 64 dot sync at the head of the line and the picture a fixed distance
//  behind it. The CRT H offset moves that distance in the same four dot steps
//  and about the same place, so one setting still centres everything.
//
//  Vertically it is a 525 line interlaced frame: 263 lines in one field, 262
//  in the other, and the odd field's VSYNC displaced half a line. That
//  displacement is the whole of interlacing. Without it a television draws
//  both fields on the same lines and half the picture is never seen.
//
//  350 source lines occupy 350 of the 525, centred, so each field carries 175
//  of them: field 0 the even ones, field 1 the odd. Both fields of an output
//  frame come from the same captured frame, so a still picture is exactly the
//  captured one and nothing combs. The cost is that motion updates at the
//  frame rate, 29.97 Hz, rather than the field rate - which is inherent to
//  showing all 350 lines on a 480i display, not a choice made here.
//
//============================================================================

`default_nettype wire

module hgc_fb_readout #(
    parameter [28:0] BASE_ADDR   = 29'h6000000,
    parameter [28:0] BUFFER_SIZE = 29'h40000,
    parameter integer BURST      = 32,
    // Video-clock cycles per output pixel. The HGC/MDA path runs this block at
    // 57.272 MHz; PCXT's HGC pipeline is 114.544 MHz, so it uses 8.
    parameter integer CLK_DIV    = 4,
    // Active lines the progressive raster emits. A parameter so a testbench
    // can shrink the picture without changing the arithmetic under test:
    // 350 into 224 is 25 into 16, the same sequence of one and two line steps.
    parameter [8:0]   LINES_240    = 9'd224
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Show the picture progressively, on a 262 line 240p raster, instead of
    // interlaced. All 350 source lines do not fit: 240p has half the lines of
    // 480i in the same height of screen, so a little over a third of them are
    // dropped. What it buys is that nothing flickers, which on high contrast
    // text is worth more to some eyes than the lines it costs.
    input  wire        progressive,

    input  wire [3:0]  crt_h_offset,
    input  wire [2:0]  crt_v_offset,

    // The frame published by the capture. Sampled at the start of an output
    // frame, so a new one cannot arrive between the two fields of the one
    // being shown and put half of each on the screen.
    input  wire [1:0]  frame_buffer,
    input  wire [11:0] frame_width,
    input  wire [9:0]  frame_height,
    input  wire [13:0] frame_stride,
    input  wire        frame_valid,

    // DDRAM read client.
    output reg         rd_req,
    output reg  [28:0] rd_addr,
    output reg  [7:0]  rd_burstcnt,
    input  wire        rd_grant,
    input  wire [63:0] rd_data,
    input  wire        rd_data_valid,

    output reg  [7:0]  r,
    output reg  [7:0]  g,
    output reg  [7:0]  b,
    output reg         hsync,
    output reg         vsync,
    output reg         hblank,
    output reg         vblank,
    output reg         de,
    output reg         field,
    output reg         ce_pix,

    // Which buffer is on screen, so the capture can be told to write anywhere
    // but there.
    output wire [1:0]  reading_buffer
);

    localparam [11:0] H_TOTAL     = 12'd910;   // 63.56 us at 14.318 MHz
    localparam [11:0] H_SYNC      = 12'd64;    // 4.47 us
    localparam [11:0] H_HALF      = 12'd455;
    localparam [11:0] H_MIN_FRONT = 12'd8;
    // Sync start to the first active dot at CRT H 0, picked so that the H
    // setting which centres the 200 line modes centres this raster too and one
    // calibration serves both. The native path leaves 171 + 4H dots between the
    // two; a 350 line picture wants a few more than that on a set.
    localparam [11:0] H_GAP_BASE  = 12'd179;

    localparam [8:0]  V_FIELD0    = 9'd263;
    localparam [8:0]  V_FIELD1    = 9'd262;
    localparam [11:0] V_SYNC_DOTS = 12'd2730;  // three lines
    // Field lines from the top of the field to the picture at CRT V 0, which is
    // where centring 175 lines in a 263 line field puts it, biased so the V
    // setting the other modes take has travel left on both sides of it.
    localparam [8:0]  V_GAP_BASE  = 9'd44;

    // 240p: one 262 line frame, no half line, no alternating field. 224 active
    // lines is what a console emits and what a television reliably shows -
    // taking all 240 would leave three lines of front porch and risk the
    // bottom of the picture falling off the tube.
    localparam [8:0]  V_TOTAL_240 = 9'd262;
    // Centring 224 lines in 262 puts them here, which leaves the V setting the
    // 480i path is centred at in the same place on the tube - the two fields
    // are the same length.
    localparam [8:0]  V_GAP_240   = 9'd19;

    //------------------------------------------------------------------------
    // Dot rate: the caller's video clock divided by CLK_DIV.
    //------------------------------------------------------------------------
    localparam integer PHASE_W = (CLK_DIV <= 1) ? 1 : $clog2(CLK_DIV);
    reg [PHASE_W-1:0] phase = {PHASE_W{1'b0}};

    always @(posedge clk) begin
        if (reset) begin
            phase  <= {PHASE_W{1'b0}};
            ce_pix <= 1'b0;
        end else begin
            phase  <= (phase == CLK_DIV - 1) ? {PHASE_W{1'b0}} : phase + 1'b1;
            ce_pix <= (phase == CLK_DIV - 1);
        end
    end

    //------------------------------------------------------------------------
    // Raster counters.
    //------------------------------------------------------------------------
    reg [11:0] hcnt = 12'd0;
    reg [8:0]  vcnt = 9'd0;
    reg [11:0] vs_dots = 12'd0;

    wire [8:0]  lines_this_field = progressive ? V_TOTAL_240
                                  : field       ? V_FIELD1 : V_FIELD0;
    wire        line_end  = (hcnt == H_TOTAL - 12'd1);
    wire        field_end = line_end && (vcnt == lines_this_field - 9'd1);

    // The frame's geometry is taken once per output frame, at the start of
    // field 0, and everything below reads these rather than the live inputs.
    reg [1:0]  cur_buffer = 2'd0;
    reg [11:0] cur_width  = 12'd640;
    reg [9:0]  cur_height = 10'd350;
    reg [13:0] cur_stride = 14'd320;
    reg        cur_valid  = 1'b0;

    wire [11:0] h_gap_want = H_GAP_BASE + {6'd0, crt_h_offset, 2'b00};
    wire [11:0] h_gap_max  = H_TOTAL - H_MIN_FRONT - cur_width;
    wire [11:0] h_start    = (h_gap_want > h_gap_max) ? h_gap_max : h_gap_want;

    wire [8:0]  v_start    = (progressive ? V_GAP_240 : V_GAP_BASE)
                             + {6'd0, crt_v_offset};
    // Interlaced, a field carries half the source lines. Progressive, it
    // carries a fixed 224 of them whatever the source height, and the stepper
    // below decides which.
    wire [8:0]  v_lines    = progressive ? LINES_240 : cur_height[9:1];

    assign reading_buffer = cur_buffer;




    always @(posedge clk) begin
        if (reset) begin
            hcnt       <= 12'd0;
            vcnt       <= 9'd0;
            field      <= 1'b0;
            vs_dots    <= 12'd0;
            cur_buffer <= 2'd0;
            cur_width  <= 12'd640;
            cur_height <= 10'd350;
            cur_stride <= 14'd320;
            cur_valid  <= 1'b0;
        end else if (ce_pix) begin
            hcnt <= line_end ? 12'd0 : (hcnt + 12'd1);

            if (line_end) begin
                if (field_end) begin
                    vcnt  <= 9'd0;
                    // Progressive has one field and it is always field 0, so
                    // vertical sync never moves half a line and VGA_F1 upstream
                    // stays low without being told.
                    field <= progressive ? 1'b0 : ~field;
                    // A new capture is taken up only between output frames -
                    // which for progressive is every frame.
                    if (progressive || field) begin
                        cur_buffer <= frame_buffer;
                        cur_width  <= frame_width;
                        cur_height <= frame_height;
                        cur_stride <= frame_stride;
                        cur_valid  <= frame_valid && enable;
                    end
                end else begin
                    vcnt <= vcnt + 9'd1;
                end
            end

            // Field 0's vertical sync starts on a line boundary and field 1's
            // half a line later. That half line is what interlaces the two.
            if ((vcnt == 9'd0) && (hcnt == (field ? H_HALF : 12'd0)))
                vs_dots <= V_SYNC_DOTS;
            else if (vs_dots != 12'd0)
                vs_dots <= vs_dots - 12'd1;
        end
    end

    //------------------------------------------------------------------------
    // Line buffers. Two banks: one being shown, one being filled from DDRAM.
    //------------------------------------------------------------------------
    (* ramstyle = "M10K, no_rw_check" *) reg [63:0] lb0 [0:511];
    (* ramstyle = "M10K, no_rw_check" *) reg [63:0] lb1 [0:511];
    reg [63:0] lb_q0 = 64'd0;
    reg [63:0] lb_q1 = 64'd0;

    reg        disp_bank = 1'b0;
    reg        fill_bank = 1'b1;

    // Addressed from the dot that will be current on the next pixel enable, so
    // the registered output is already there when the dot arrives.
    wire [11:0] hcnt_next = line_end ? 12'd0 : (hcnt + 12'd1);
    wire [11:0] px_next   = hcnt_next - h_start;
    wire [8:0]  lb_raddr  = px_next[9:1];

    reg  [8:0]  fill_waddr = 9'd0;
    // The data is registered on its way into the buffer, so it arrives a clock
    // after the beat that carried it, by which time fill_waddr has already
    // moved on. This is the address that belongs to the word being written.
    reg  [8:0]  fill_waddr_q = 9'd0;
    reg  [63:0] fill_data = 64'd0;
    reg         fill_we = 1'b0;

    always @(posedge clk) begin
        if (fill_we && !fill_bank) lb0[fill_waddr_q] <= fill_data;
        if (fill_we &&  fill_bank) lb1[fill_waddr_q] <= fill_data;
        lb_q0 <= lb0[lb_raddr];
        lb_q1 <= lb1[lb_raddr];
    end

    // The output registers are written on the pixel enable and appear a dot
    // later, so everything they are built from is the dot after the counters'
    // current one. Mixing the two - blanking from this dot, colour from the
    // next - shifts the picture against its own display enable.
    wire [63:0] lb_word = disp_bank ? lb_q1 : lb_q0;
    wire [31:0] px_data = px_next[0] ? lb_word[63:32] : lb_word[31:0];

    //------------------------------------------------------------------------
    // Fetching. Lines are consumed two source lines apart within a field, so
    // the address walks by two strides and never needs a multiplier.
    //------------------------------------------------------------------------
    localparam [1:0] F_IDLE = 2'd0;
    localparam [1:0] F_REQ  = 2'd1;
    localparam [1:0] F_DATA = 2'd2;

    reg [1:0]  fstate = F_IDLE;
    reg [28:0] line_addr = 29'd0;      // where the next active line starts
    reg [28:0] fetch_addr = 29'd0;
    reg [13:0] words_left = 14'd0;
    reg [8:0]  beats_left = 9'd0;

    // Which source line each progressive output line comes from. Interlaced,
    // the answer is fixed - two on from the last - and the address walks by
    // two strides. Progressive, cur_height source lines have to land on
    // V_LINES_240 output lines, a ratio that is not a whole number and is not
    // the same for a 350 line mode as for a 400 line one.
    //
    // So it is counted rather than multiplied: each output line adds the source
    // height to an accumulator, and every time that reaches the output height
    // one stride comes off it and the address moves on a source line. 350 into
    // 224 gives one stride then two, over and over, averaging the 1.5625 the
    // ratio asks for, and never needs a multiplier or a divider.
    reg [13:0] vacc = 14'd0;

    wire [8:0] vcnt_next = line_end ? (field_end ? 9'd0 : (vcnt + 9'd1)) : vcnt;
    wire       line_tick = ce_pix && line_end;

    // Which line the fetch started here is for. At a line tick vcnt still holds
    // the line that is ending, the line starting is the one after it, and the
    // bank swap in the same tick has just put the line fetched last time on
    // screen. So the fetch beginning now is for the line after the one about to
    // be displayed - two on from vcnt, not one.
    wire [8:0] vcnt_fetch  = field_end ? 9'd1 : (vcnt + 9'd2);
    wire       next_active = (vcnt_fetch >= v_start) && (vcnt_fetch < (v_start + v_lines));

    wire h_active_out = (hcnt_next >= h_start) && (hcnt_next < (h_start + cur_width));
    wire v_active_out = (vcnt_next >= v_start) && (vcnt_next < (v_start + v_lines));

    // A burst may not cross a 4 KB boundary. The HPS bridge is AXI behind an
    // Avalon front, and AXI forbids it; an unaligned burst that straddles one
    // is not split for us, it is answered with fewer beats than were asked
    // for - and a read that comes up short holds the port for good.
    // 512 words of 64 bits is 4 KB.
    wire [9:0] rd_to_edge  = 10'd512 - {1'b0, fetch_addr[8:0]};
    wire [7:0] burst_cap   = (rd_to_edge >= BURST) ? BURST[7:0] : rd_to_edge[7:0];
    wire [7:0] this_burst  = (words_left >= {6'd0, burst_cap}) ? burst_cap
                                                              : words_left[7:0];

    // At the start of field 0 the geometry registers are taking on the newly
    // published frame in the same clock, so the first line address has to be
    // built from what they are about to become, not from what they hold.
    // The same condition the geometry registers are taken on. Left as
    // field_end && field it is never true progressively, and the first line
    // address is built from the buffer being left rather than the one being
    // taken up - so the raster reads the buffer the capture has just been
    // told it may overwrite.
    wire        adopt     = field_end && (progressive || field);
    wire [1:0]  nx_buffer = adopt ? frame_buffer : cur_buffer;
    wire [13:0] nx_stride = adopt ? frame_stride : cur_stride;
    wire [28:0] nx_base   = BASE_ADDR + (nx_buffer == 2'd0 ? 29'd0 :
                                        nx_buffer == 2'd1 ? BUFFER_SIZE
                                                             : (BUFFER_SIZE + BUFFER_SIZE));

    always @(posedge clk) begin
        fill_we <= 1'b0;

        if (reset) begin
            fstate     <= F_IDLE;
            rd_req     <= 1'b0;
            disp_bank  <= 1'b0;
            fill_bank  <= 1'b1;
            line_addr  <= 29'd0;
            words_left <= 14'd0;
            beats_left <= 9'd0;
            fill_waddr <= 9'd0;
            vacc       <= 14'd0;
        end else begin
            if (line_tick) begin
                // The bank just filled becomes the one on screen, and the one
                // coming off screen is where the next line goes.
                disp_bank <= ~disp_bank;
                fill_bank <= disp_bank;

                if (field_end) begin
                    // Aim at the new field's first source line: field 0 takes
                    // the even ones, field 1 the odd, so the odd field starts
                    // a stride in. Progressive starts at the top every time.
                    // Nothing is fetched on this tick - the picture is dozens
                    // of lines away yet.
                    line_addr <= nx_base + ((progressive || field) ? 29'd0
                                                          : {15'd0, nx_stride});
                    vacc      <= 14'd0;
                    fstate    <= F_IDLE;
                end else if (next_active && cur_valid) begin
                    fetch_addr <= line_addr;
                    // Interlaced the step is always two strides. Progressive it
                    // is one or two, and the accumulator below works out which
                    // over the following clocks - there is a whole line to do
                    // it in, and fetch_addr is already taken.
                    if (progressive) vacc      <= vacc + {4'd0, cur_height};
                    else             line_addr <= line_addr +
                                                  {14'd0, cur_stride, 1'b0};
                    words_left <= cur_stride;
                    fill_waddr <= 9'd0;
                    fstate     <= F_REQ;
                end else begin
                    fstate <= F_IDLE;
                end
            end else begin
                // One source line per pass, as many passes as the accumulator
                // has earned. Never on a line tick, which is the one clock that
                // writes line_addr and vacc itself.
                if (progressive && (vacc >= {5'd0, LINES_240})) begin
                    vacc      <= vacc - {5'd0, LINES_240};
                    line_addr <= line_addr + {15'd0, cur_stride};
                end

                case (fstate)
                    F_IDLE: rd_req <= 1'b0;

                    F_REQ: begin
                        rd_req      <= 1'b1;
                        rd_addr     <= fetch_addr;
                        rd_burstcnt <= this_burst;
                        if (rd_grant) begin
                            rd_req     <= 1'b0;
                            beats_left <= {1'b0, this_burst};
                            fstate     <= F_DATA;
                        end
                    end

                    F_DATA: begin
                        if (rd_data_valid) begin
                            fill_we      <= 1'b1;
                            fill_data    <= rd_data;
                            fill_waddr_q <= fill_waddr;
                            fill_waddr   <= fill_waddr + 9'd1;
                            fetch_addr <= fetch_addr + 29'd1;
                            words_left <= words_left - 14'd1;
                            beats_left <= beats_left - 9'd1;
                            if (beats_left == 9'd1)
                                fstate <= (words_left == 14'd1) ? F_IDLE : F_REQ;
                        end
                    end

                    default: fstate <= F_IDLE;
                endcase
            end
        end
    end

    //------------------------------------------------------------------------
    // Output.
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            r      <= 8'd0;
            g      <= 8'd0;
            b      <= 8'd0;
            hsync  <= 1'b0;
            vsync  <= 1'b0;
            hblank <= 1'b1;
            vblank <= 1'b1;
            de     <= 1'b0;
        end else if (ce_pix) begin
            hsync  <= (hcnt_next < H_SYNC);
            vsync  <= (vs_dots != 12'd0);
            hblank <= ~h_active_out;
            vblank <= ~v_active_out;
            de     <= h_active_out && v_active_out && cur_valid;
            if (h_active_out && v_active_out && cur_valid) begin
                r <= px_data[23:16];
                g <= px_data[15:8];
                b <= px_data[7:0];
            end else begin
                r <= 8'd0;
                g <= 8'd0;
                b <= 8'd0;
            end
        end
    end

endmodule


