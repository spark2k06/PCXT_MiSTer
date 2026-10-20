//============================================================================
//
//  The progressive raster and, above all, which source line each of its output
//  lines shows.
//
//  350 source lines into 224 output lines is 25 into 16 exactly, so the
//  readout is built here with LINES_240 = 16 against a 25 line picture. The
//  accumulator does the identical sequence of one and two line steps it does
//  at full size, in a frame short enough to simulate.
//
//  The expected answer is written out longhand as (k * HEIGHT) / LINES rather
//  than by running a second accumulator, so a mistake in the design's
//  arithmetic cannot be reproduced by the check on the other side.
//
//  Positions are taken from the emitted sync, not from inside the module, so
//  what is tested is what a television would see.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_fb_240p_tb;

    localparam integer WIDTH  = 16;    // source dots per line
    localparam integer HEIGHT = 25;    // source active lines
    localparam integer HBLANK = 8;
    localparam integer VBLANK = 2;
    localparam integer LINES  = 16;    // output lines the picture becomes

    localparam integer V_TOTAL = 262;

    localparam [28:0] BASE  = 29'h100;
    localparam [28:0] BUFSZ = 29'h100;

    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg reset  = 1'b1;
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
        .frame_seq(), .frame_valid(frame_valid), .overrun(overrun)
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
        .BASE_ADDR(BASE), .BUFFER_SIZE(BUFSZ), .BURST(8),
        .LINES_240(LINES[8:0])
    ) rdo (
        .clk(clk), .reset(reset), .enable(1'b1),
        .progressive(1'b1),
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
    // DDRAM model. Busy in runs and reads come back after a latency, both of
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
    // Source driver. Every dot carries where it came from: red the frame,
    // green the source line, blue the dot within it.
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
    // Output observer
    //------------------------------------------------------------------------
    integer errors = 0;

    reg     p_hs = 1'b0, p_vs = 1'b0, p_de = 1'b0;
    integer dots_since_hs = 0;
    integer lines_since_vs = 0;
    integer vs_dot = -1;           // where in its line vertical sync begins
    integer disp_line = 0;
    integer disp_dot = 0;
    integer frame_id = -1;
    integer frame_count = 0;
    integer lines_this = 0;
    integer lines_last = -1;
    integer total_last = -1;
    reg     checking = 1'b0;

    task check_map;
        integer want;
        begin
            want = (disp_line * HEIGHT) / LINES;
            if (out_g !== want[7:0]) begin
                $display("FAIL output line %0d shows source line %0d, expected %0d",
                         disp_line, out_g, want);
                errors = errors + 1;
            end
        end
    endtask

    always @(posedge clk) if (out_ce) begin
        p_hs <= out_hs; p_vs <= out_vs; p_de <= out_de;

        if (out_hs && !p_hs) begin
            dots_since_hs  <= 0;
            lines_since_vs <= lines_since_vs + 1;
        end else begin
            dots_since_hs <= dots_since_hs + 1;
        end

        if (out_vs && !p_vs) begin
            vs_dot         <= (out_hs && !p_hs) ? 0 : dots_since_hs + 1;
            total_last     <= lines_since_vs;
            lines_last     <= lines_this;
            lines_since_vs <= 0;
            lines_this     <= 0;
            disp_line      <= 0;
            frame_id       <= -1;
            frame_count    <= frame_count + 1;
        end

        // There is one field and it is field 0. A television told otherwise
        // would displace every other frame by half a line and shake.
        if (checking && out_field !== 1'b0) begin
            $display("FAIL field is %0d on a progressive raster", out_field);
            errors = errors + 1;
        end

        if (out_de && !p_de) begin
            disp_dot <= 0;
            if (checking) begin
                check_map;
                if (frame_id < 0) frame_id <= out_r;
                else if (out_r !== frame_id[7:0]) begin
                    $display("FAIL output line %0d came from captured frame %0d, the rest from %0d",
                             disp_line, out_r, frame_id);
                    errors = errors + 1;
                end
            end
        end else if (out_de) begin
            disp_dot <= disp_dot + 1;
            if (checking && out_b !== disp_dot[7:0] + 8'd1) begin
                $display("FAIL output line %0d dot %0d holds source dot %0d",
                         disp_line, disp_dot + 1, out_b);
                errors = errors + 1;
            end
        end

        if (!out_de && p_de) begin
            disp_line  <= disp_line + 1;
            lines_this <= lines_this + 1;
        end
    end

    //------------------------------------------------------------------------
    initial begin
        #500_000_000;
        $display("FAIL timed out");
        $display("[ega_fb_240p_tb] RESULT: FAIL");
        $finish;
    end

    initial begin
        repeat (20) @(posedge clk);
        reset = 1'b0;
        repeat (20) @(posedge clk);
        enable = 1'b1;

        // Let a frame be captured and adopted before anything is judged.
        while (frame_count < 3) @(posedge clk);
        checking = 1'b1;

        while (frame_count < 6) @(posedge clk);
        checking = 1'b0;
        @(posedge clk);

        $display("");
        $display("  output frame: %0d lines total, %0d of them showing picture",
                 total_last, lines_last);
        $display("  vertical sync begins at dot %0d of its line", vs_dot);
        $display("");

        if (total_last !== V_TOTAL) begin
            $display("FAIL a progressive frame must be %0d lines, not %0d",
                     V_TOTAL, total_last);
            errors = errors + 1;
        end

        if (lines_last !== LINES) begin
            $display("FAIL the picture must occupy %0d output lines, not %0d",
                     LINES, lines_last);
            errors = errors + 1;
        end

        if (overrun) begin
            $display("FAIL the capture overran");
            errors = errors + 1;
        end

        if (errors == 0) $display("[ega_fb_240p_tb] RESULT: PASS");
        else             $display("[ega_fb_240p_tb] RESULT: FAIL");
        $finish;
    end

endmodule
