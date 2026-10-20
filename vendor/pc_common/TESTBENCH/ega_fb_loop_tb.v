//============================================================================
//
//  Capture and readout together: a picture goes into DDRAM as a progressive
//  frame and has to come back out of it as two interlaced fields.
//
//  This is the test the two halves cannot do separately. Each on its own can
//  be self-consistently wrong - the capture writing a layout the readout does
//  not read, the readout inventing an interlace the capture never fed. Wiring
//  them through one arbiter and one memory model, with the source pixels
//  carrying their own coordinates, makes the whole path answer for itself.
//
//  What has to hold:
//
//    * field 0 shows the even source lines and field 1 the odd ones, so
//      between them every line of the picture is shown exactly once,
//    * both fields of an output frame come from the same captured frame, even
//      though several more were captured while it was on screen,
//    * every dot is the dot it should be, left to right,
//    * field 1's vertical sync is exactly half a line after field 0's, which
//      is the whole of interlacing - without it a television draws the two
//      fields on top of each other and half the picture is never seen,
//    * the capture never writes the buffer the readout is reading.
//
//  The source raster here runs far faster than the output, which is not what
//  the EGA does but is a harder case for the buffer rotation: several frames
//  are captured and published during each frame that is displayed.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_fb_loop_tb;

    localparam integer WIDTH  = 16;    // source dots per line
    localparam integer HEIGHT = 8;     // source active lines
    localparam integer HBLANK = 8;
    localparam integer VBLANK = 2;

    localparam [28:0] BASE  = 29'h100;
    localparam [28:0] BUFSZ = 29'h100;

    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg reset = 1'b1;
    reg enable = 1'b0;

    //------------------------------------------------------------------------
    // Source raster
    //------------------------------------------------------------------------
    reg        src_ce = 1'b0;
    reg [7:0]  src_r = 8'd0, src_g = 8'd0, src_b = 8'd0;
    reg        src_de = 1'b0;
    reg        src_vblank = 1'b1;

    integer div = 0;
    always @(posedge clk) begin
        div <= div + 1;
        src_ce <= (div[1:0] == 2'b00);
    end

    //------------------------------------------------------------------------
    // Capture, arbiter, readout
    //------------------------------------------------------------------------
    wire [7:0]  cap_burstcnt;
    wire [28:0] cap_addr;
    wire [63:0] cap_din;
    wire        cap_we;
    wire        cap_busy;

    wire [1:0]  frame_buffer;
    wire [11:0] frame_width;
    wire [9:0]  frame_height;
    wire [13:0] frame_stride;
    wire [7:0]  frame_seq;
    wire        frame_valid;
    wire        overrun;
    wire [1:0]  reading_buffer;

    ega_fb_capture #(
        .BASE_ADDR(BASE), .BUFFER_SIZE(BUFSZ), .BURST(8), .FIFO_DEPTH(32)
    ) cap (
        .clk(clk), .reset(reset), .enable(enable),
        .ce_pix(src_ce), .r(src_r), .g(src_g), .b(src_b),
        .de(src_de), .vblank(src_vblank),
        .active_dots(WIDTH[11:0]), .active_lines(HEIGHT[9:0]),
        .reading_buffer(reading_buffer),
        .ddram_busy(cap_busy), .ddram_burstcnt(cap_burstcnt),
        .ddram_addr(cap_addr), .ddram_din(cap_din), .ddram_be(),
        .ddram_we(cap_we),
        .frame_buffer(frame_buffer), .frame_width(frame_width),
        .frame_height(frame_height), .frame_stride(frame_stride),
        .frame_seq(frame_seq), .frame_valid(frame_valid), .overrun(overrun)
    );

    wire        rd_req;
    wire [28:0] rd_addr;
    wire [7:0]  rd_burstcnt;
    wire        rd_grant;
    wire [63:0] rd_data;
    wire        rd_data_valid;

    wire [7:0]  out_r, out_g, out_b;
    wire        out_hs, out_vs, out_hb, out_vb, out_de, out_field, out_ce;

    ega_fb_readout #(
        .BASE_ADDR(BASE), .BUFFER_SIZE(BUFSZ), .BURST(8)
    ) rdo (
        .clk(clk), .reset(reset), .enable(1'b1),
        .progressive(1'b0),
        .crt_h_offset(4'd6), .crt_v_offset(3'd4),
        .frame_buffer(frame_buffer), .frame_width(frame_width),
        .frame_height(frame_height), .frame_stride(frame_stride),
        .frame_valid(frame_valid),
        .rd_req(rd_req), .rd_addr(rd_addr), .rd_burstcnt(rd_burstcnt),
        .rd_grant(rd_grant), .rd_data(rd_data), .rd_data_valid(rd_data_valid),
        .r(out_r), .g(out_g), .b(out_b),
        .hsync(out_hs), .vsync(out_vs), .hblank(out_hb), .vblank(out_vb),
        .de(out_de), .field(out_field), .ce_pix(out_ce),
        .reading_buffer(reading_buffer)
    );

    wire [7:0]  ddram_burstcnt;
    wire [28:0] ddram_addr;
    wire [63:0] ddram_din;
    wire        ddram_we, ddram_rd;
    reg  [63:0] ddram_dout = 64'd0;
    reg         ddram_dout_ready = 1'b0;
    reg         ddram_busy = 1'b0;

    ega_ddr_arbiter arb (
        .clk(clk), .reset(reset),
        .ddram_busy(ddram_busy), .ddram_burstcnt(ddram_burstcnt),
        .ddram_addr(ddram_addr), .ddram_din(ddram_din), .ddram_be(),
        .ddram_we(ddram_we), .ddram_rd(ddram_rd),
        .ddram_dout(ddram_dout), .ddram_dout_ready(ddram_dout_ready),
        .rd_req(rd_req), .rd_addr(rd_addr), .rd_burstcnt(rd_burstcnt),
        .rd_grant(rd_grant), .rd_data(rd_data), .rd_data_valid(rd_data_valid),
        .wr_req(cap_we), .wr_addr(cap_addr), .wr_burstcnt(cap_burstcnt),
        .wr_din(cap_din), .wr_busy_out(cap_busy), .wr_grant(),
        // No AT RAM client in this bench.
        .at_req(1'b0), .at_write(1'b0), .at_addr(29'd0), .at_be(8'd0),
        .at_din(64'd0), .at_burstcnt(8'd0), .at_done(), .at_rvalid(), .at_rdata()
    );

    //------------------------------------------------------------------------
    // DDRAM model. Busy in runs, and reads come back after a latency, both of
    // which the real memory does and neither of which the design may assume
    // away.
    //------------------------------------------------------------------------
    reg [63:0] mem [0:4095];
    reg [15:0] lfsr = 16'hBEEF;
    reg [3:0]  busy_run = 4'd0;

    always @(posedge clk) begin
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        if (busy_run != 0) begin
            busy_run   <= busy_run - 4'd1;
            ddram_busy <= 1'b1;
        end else if (lfsr[3:0] == 4'h0) begin
            busy_run   <= lfsr[6:3];
            ddram_busy <= 1'b1;
        end else begin
            ddram_busy <= 1'b0;
        end
    end

    reg [28:0] wr_a = 29'd0;
    reg [8:0]  wr_n = 9'd0;
    reg [28:0] rd_a = 29'd0;
    reg [8:0]  rd_n = 9'd0;
    reg [3:0]  rd_lat = 4'd0;

    always @(posedge clk) begin
        if (ddram_we && !ddram_busy) begin
            if (wr_n == 0) begin
                mem[ddram_addr[11:0]] <= ddram_din;
                wr_a <= ddram_addr + 29'd1;
                wr_n <= {1'b0, ddram_burstcnt} - 9'd1;
            end else begin
                mem[wr_a[11:0]] <= ddram_din;
                wr_a <= wr_a + 29'd1;
                wr_n <= wr_n - 9'd1;
            end
        end
    end

    always @(posedge clk) begin
        ddram_dout_ready <= 1'b0;
        if (ddram_rd && !ddram_busy && rd_n == 0) begin
            rd_a   <= ddram_addr;
            rd_n   <= {1'b0, ddram_burstcnt};
            rd_lat <= 4'd6;
        end else if (rd_n != 0) begin
            if (rd_lat != 0) begin
                rd_lat <= rd_lat - 4'd1;
            end else begin
                ddram_dout       <= mem[rd_a[11:0]];
                ddram_dout_ready <= 1'b1;
                rd_a             <= rd_a + 29'd1;
                rd_n             <= rd_n - 9'd1;
            end
        end
    end

    //------------------------------------------------------------------------
    // Source driver
    //------------------------------------------------------------------------
    integer src_frame = 1;
    integer sl, sd;

    task src_dot(input dd, input [7:0] rr, input [7:0] gg, input [7:0] bb);
        begin
            @(negedge clk);
            src_de <= dd; src_r <= rr; src_g <= gg; src_b <= bb;
            @(posedge clk);
            while (src_ce !== 1'b1) @(posedge clk);
        end
    endtask

    task src_blank(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) src_dot(1'b0, 8'd0, 8'd0, 8'd0);
        end
    endtask

    initial begin
        forever begin
            @(negedge clk);
            src_vblank <= 1'b1;
            src_blank(VBLANK * (WIDTH + HBLANK));
            @(negedge clk);
            src_vblank <= 1'b0;
            src_blank(HBLANK);
            for (sl = 0; sl < HEIGHT; sl = sl + 1) begin
                for (sd = 0; sd < WIDTH; sd = sd + 1)
                    src_dot(1'b1, src_frame[7:0], sl[7:0], sd[7:0]);
                src_blank(HBLANK);
            end
            @(negedge clk);
            src_vblank <= 1'b1;
            src_blank(WIDTH + HBLANK);
            src_frame = (src_frame % 200) + 1;
        end
    end

    //------------------------------------------------------------------------
    // Output observer. Positions are taken from the emitted sync, not from
    // inside the module, so what is checked is what a television would see.
    //------------------------------------------------------------------------
    integer errors = 0;

    reg        p_hs = 1'b0, p_vs = 1'b0, p_de = 1'b0;
    integer    dots_since_hs = 0;
    integer    lines_since_vs = 0;
    integer    vs_phase [0:1];
    integer    disp_line = 0;      // which displayed line of this field
    integer    disp_dot = 0;
    integer    field_now = 0;
    integer    frame_id = -1;      // source frame this output frame is showing
    integer    lines_seen [0:1];
    integer    frame_count = 0;
    reg        checking = 1'b0;
    integer    seen_line [0:63];   // source lines shown in the current frame
    integer    seen_snap [0:63];
    integer    lines_snap [0:1];
    integer    i;

    always @(posedge clk) if (out_ce) begin
        p_hs <= out_hs; p_vs <= out_vs; p_de <= out_de;

        if (out_hs && !p_hs) begin
            dots_since_hs  <= 0;
            lines_since_vs <= lines_since_vs + 1;
        end else begin
            dots_since_hs <= dots_since_hs + 1;
        end

        if (out_vs && !p_vs) begin
            vs_phase[out_field] <= (out_hs && !p_hs) ? 0 : dots_since_hs + 1;
            lines_since_vs <= 0;
            disp_line      <= 0;
            field_now      <= out_field;
            lines_seen[out_field] <= 0;

            // A new output frame starts at field 0. Everything shown until the
            // next one has to come from a single captured frame.
            // Snapshot before clearing: the counters are cleared here, so
            // reading them here instead would always find them empty.
            if (out_field == 0) begin
                frame_id    <= -1;
                frame_count <= frame_count + 1;
                lines_snap[0] <= lines_seen[0];
                lines_snap[1] <= lines_seen[1];
                for (i = 0; i < 64; i = i + 1) begin
                    seen_snap[i] <= seen_line[i];
                    seen_line[i] <= 0;
                end
            end
        end

        // Start of a displayed line.
        if (out_de && !p_de) begin
            disp_dot <= 1;
            if (checking) checkline;
        end else if (out_de) begin
            disp_dot <= disp_dot + 1;
        end

        if (out_de && checking) checkdot;

        if (!out_de && p_de) begin
            if (checking && (disp_dot != WIDTH)) begin
                $display("FAIL field %0d line %0d came out %0d dots wide, expected %0d",
                         field_now, disp_line, disp_dot, WIDTH);
                errors = errors + 1;
            end
            disp_line  <= disp_line + 1;
            lines_seen[field_now] <= lines_seen[field_now] + 1;
        end
    end

    // The dot index of the sample being looked at right now. disp_dot is what
    // the next one will be, so on the first dot of a line it is not it yet.
    wire [31:0] cur_dot = (out_de && !p_de) ? 32'd0 : disp_dot[31:0];

    // The source line this displayed line must be showing, and the frame it
    // must have come from.
    task checkline;
        integer want_src;
        begin
            want_src = 2*disp_line + field_now;
            if (out_g !== want_src[7:0]) begin
                $display("FAIL field %0d line %0d shows source line %0d, expected %0d",
                         field_now, disp_line, out_g, want_src);
                errors = errors + 1;
            end
            if (want_src < 64) seen_line[want_src] = seen_line[want_src] + 1;

            if (frame_id < 0) begin
                frame_id <= out_r;
            end else if (out_r !== frame_id[7:0]) begin
                $display("FAIL field %0d line %0d came from captured frame %0d, the rest of the output frame from %0d",
                         field_now, disp_line, out_r, frame_id);
                errors = errors + 1;
            end
        end
    endtask

    task checkdot;
        begin
            if (out_b !== cur_dot[7:0]) begin
                $display("FAIL field %0d line %0d dot %0d holds dot %0d",
                         field_now, disp_line, cur_dot, out_b);
                errors = errors + 1;
            end
        end
    endtask

    // The capture must never be writing the buffer on screen.
    always @(posedge clk)
        if (!reset && cap_we && (cap.wr_buffer == reading_buffer) && frame_valid) begin
            $display("FAIL the capture wrote buffer %0d while the readout was reading it",
                     reading_buffer);
            errors = errors + 1;
        end

    integer n_wr = 0, n_rdreq = 0, n_rdbeat = 0;
    always @(posedge clk) begin
        if (ddram_we && !ddram_busy) n_wr <= n_wr + 1;
        if (rd_grant) n_rdreq <= n_rdreq + 1;
        if (rd_data_valid) n_rdbeat <= n_rdbeat + 1;
    end

    initial begin
        #250_000_000;
        $display("[ega_fb_loop_tb] TIMEOUT");
        $display("[ega_fb_loop_tb] RESULT: FAIL");
        $finish;
    end

    initial begin
        vs_phase[0] = -1;
        vs_phase[1] = -1;
        lines_seen[0] = 0;
        lines_seen[1] = 0;
        for (i = 0; i < 64; i = i + 1) begin seen_line[i] = 0; seen_snap[i] = 0; end
        lines_snap[0] = 0; lines_snap[1] = 0;

        repeat (8) @(posedge clk);
        reset <= 1'b0;
        repeat (8) @(posedge clk);
        enable <= 1'b1;

        // Let a couple of output frames go by before checking anything: the
        // first has nothing captured to show yet.
        wait (frame_count == 2);
        checking <= 1'b1;

        wait (frame_count == 4);
        checking <= 1'b0;

        $display("");
        $display("  DDRAM: %0d beats written, %0d read bursts granted, %0d beats returned",
                 n_wr, n_rdreq, n_rdbeat);
        $display("  capture: seq %0d, buffer %0d, valid %b, %0dx%0d stride %0d",
                 frame_seq, frame_buffer, frame_valid, frame_width, frame_height,
                 frame_stride);
        $display("  readout: reading buffer %0d, cur_valid %b",
                 reading_buffer, rdo.cur_valid);
        $display("  memory at 0x200: %h %h %h %h", mem[12'h200], mem[12'h201],
                 mem[12'h202], mem[12'h203]);
        $display("  memory at 0x300: %h %h %h %h", mem[12'h300], mem[12'h301],
                 mem[12'h302], mem[12'h303]);
        $display("");
        $display("  lines shown: %0d in field 0, %0d in field 1, of %0d in the picture",
                 lines_snap[0], lines_snap[1], HEIGHT);

        if (lines_snap[0] != HEIGHT/2 || lines_snap[1] != HEIGHT/2) begin
            $display("FAIL each field must show %0d lines", HEIGHT/2);
            errors = errors + 1;
        end

        // Every source line exactly once across the two fields of a frame.
        for (i = 0; i < HEIGHT; i = i + 1)
            if (seen_snap[i] != 1) begin
                $display("FAIL source line %0d was shown %0d times in one output frame",
                         i, seen_snap[i]);
                errors = errors + 1;
            end

        $display("  vertical sync of field 0 at dot %0d of its line, field 1 at %0d",
                 vs_phase[0], vs_phase[1]);

        if ((vs_phase[1] - vs_phase[0]) != 455) begin
            $display("FAIL the two fields' vertical sync are %0d dots apart, expected 455",
                     vs_phase[1] - vs_phase[0]);
            $display("     without half a line between them a television draws both fields on the same lines");
            errors = errors + 1;
        end

        if (overrun !== 1'b0) begin
            $display("FAIL the capture overran");
            errors = errors + 1;
        end

        $display("");
        if (errors == 0) $display("[ega_fb_loop_tb] RESULT: PASS");
        else             $display("[ega_fb_loop_tb] RESULT: FAIL");
        $finish;
    end

endmodule
