//============================================================================
//
//  Credits overlay pause/restart regression.
//
//  The scroll position is re-seeded on the rising edge of enable, but the
//  re-seed only happens on a pixel enable. With pxl_cen one clk in four, the
//  phase of the enable transition must be tested rather than assumed.
//
//  The credits overlay stubs its own RAMs, so this bench can be compiled
//  against jtframe_credits.v alone.
//
//============================================================================

`timescale 1ns/1ps

// The overlay RAMs are stubbed empty. With no glyph data every character cell
// is background, which makes the enabled overlay's dimming unambiguous.
module jtframe_dual_ram #(
    parameter dw = 8, aw = 8, synfile = "", ascii_bin = 0
) (
    input wire clk0, clk1,
    input wire [dw-1:0] data0, data1,
    input wire [aw-1:0] addr0, addr1,
    input wire we0, we1,
    output wire [dw-1:0] q0,
    output wire [dw-2:0] q1
);
    assign q0 = {dw{1'b0}};
    assign q1 = {(dw-1){1'b0}};
endmodule

module jtframe_ram #(
    parameter dw = 8, aw = 8, synfile = ""
) (
    input wire clk, cen,
    input wire [dw-1:0] data,
    input wire [aw-1:0] addr,
    input wire we,
    output wire [dw-1:0] q
);
    assign q = {dw{1'b0}};
endmodule

module jtframe_credits_pause_tb;

    // Shrunk raster. Only the left edge of the overlay window matters here;
    // hoffset is 64, so 200 active pixels straddle it with room either side.
    localparam integer H_ACTIVE = 200;
    localparam integer H_TOTAL  = 224;
    localparam integer V_ACTIVE = 20;
    localparam integer V_TOTAL  = 24;

    localparam [23:0] RGB_IN  = 24'hFEDCBA;
    localparam [23:0] RGB_DIM = 24'h7F6E5D;   // each channel halved

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg enable = 1'b0;

    // One pixel in four, as on the video output clock.
    reg [1:0] cen_div = 2'd0;
    wire pxl_cen = (cen_div == 2'd0);
    always @(posedge clk) cen_div <= cen_div + 2'd1;

    integer hcnt = 0;
    integer vcnt = 0;
    integer frames = 0;

    always @(posedge clk) if (pxl_cen) begin
        if (hcnt == H_TOTAL-1) begin
            hcnt <= 0;
            if (vcnt == V_TOTAL-1) begin
                vcnt <= 0;
                frames <= frames + 1;
            end
            else vcnt <= vcnt + 1;
        end
        else hcnt <= hcnt + 1;
    end

    wire HB = (hcnt >= H_ACTIVE);
    wire VB = (vcnt >= V_ACTIVE);

    wire [23:0] rgb_out;

    jtframe_credits #(.PAGES(4), .COLW(8), .BLKPOL(1)) dut (
        .rst(rst), .clk(clk), .pxl_cen(pxl_cen),
        .HB(HB), .VB(VB), .rgb_in(RGB_IN),
        .vram_din(9'd0), .vram_addr(10'd0), .vram_we(1'b0),
        .vram_dout(), .enable(enable), .toggle(1'b0),
        .vram_ctrl(3'd0), .fast_scroll(1'b0), .rotate(2'd0),
        .border(1'b0), .HB_out(), .VB_out(),
        .rgb_out(rgb_out)
    );

    integer errors = 0;

    // Sampled well inside the active area so no blanking edge is in reach, and
    // split either side of hoffset. hn tracks hcnt within one pixel, so 100 is
    // safely past 64 and 30 is safely short of it.
    integer dim_inside = 0;
    integer pass_inside = 0;
    integer pass_outside = 0;
    integer dim_outside = 0;

    wire sampling = pxl_cen && (vcnt > 2) && (vcnt < V_ACTIVE-2);
    wire inside_window  = (hcnt > 100) && (hcnt < H_ACTIVE-5);
    wire outside_window = (hcnt > 5)   && (hcnt < 30);

    always @(posedge clk) if (sampling) begin
        if (inside_window) begin
            if (rgb_out === RGB_DIM) dim_inside = dim_inside + 1;
            if (rgb_out === RGB_IN)  pass_inside = pass_inside + 1;
        end
        if (outside_window) begin
            if (rgb_out === RGB_IN)  pass_outside = pass_outside + 1;
            if (rgb_out === RGB_DIM) dim_outside = dim_outside + 1;
        end
    end

    task automatic clear_counts;
        begin
            dim_inside = 0; pass_inside = 0;
            pass_outside = 0; dim_outside = 0;
        end
    endtask

    task automatic run_frames(input integer n);
        begin : body
            integer target;
            target = frames + n;
            wait (frames == target);
        end
    endtask

    task automatic fail(input string what);
        begin
            $display("FAIL: %s", what);
            errors = errors + 1;
        end
    endtask

    // Raise enable at a chosen offset from a pixel enable. The transition is
    // made in the middle of the active area, so no vertical blank can advance
    // the scroll between the edge and the check.
    task automatic enable_at_phase(input integer phase);
        begin
            wait (vcnt == 5);
            // Settle past the nonblocking region before reading the divider or
            // driving enable. The DUT sees the new value at the next edge.
            @(posedge clk); #1;
            while (cen_div != phase[1:0]) begin @(posedge clk); #1; end
            enable = 1'b1;
            repeat (32) @(posedge clk);
        end
    endtask

    integer phase;

    initial begin
        repeat (8) @(posedge clk);
        rst = 1'b0;

        // 1. Disabled: the picture must reach the output untouched.
        run_frames(2);
        clear_counts();
        run_frames(2);
        if (dim_inside != 0)    fail("picture dimmed while the overlay is off");
        if (pass_inside == 0)   fail("no pass-through samples inside the window");
        if (pass_outside == 0)  fail("no pass-through samples outside the window");

        // 2. Enabled: dimmed inside its window, untouched outside it.
        enable = 1'b1;
        run_frames(2);
        clear_counts();
        run_frames(2);
        if (dim_inside == 0)    fail("overlay does not draw when enabled");
        if (pass_inside != 0)   fail("overlay leaves gaps inside its window");
        if (dim_outside != 0)   fail("overlay reaches outside its window");
        if (pass_outside == 0)  fail("picture lost outside the overlay window");

        // 3. It scrolls.
        run_frames(10);
        if (dut.scrpos == 0)    fail("credits do not scroll while enabled");

        // 4. Every pause starts from the top, whichever clk the release and
        // the next press happen to land on.
        for (phase = 0; phase < 4; phase = phase + 1) begin
            enable = 1'b0;
            run_frames(2);
            enable_at_phase(phase);
            if (dut.scrpos != 0) begin
                $display("FAIL: scroll not re-seeded at phase %0d (scrpos=%0d)",
                         phase, dut.scrpos);
                errors = errors + 1;
            end
            run_frames(10);
            if (dut.scrpos == 0) fail("scroll stalled after re-enable");
        end

        // 5. Disabled again: back to pass-through.
        enable = 1'b0;
        run_frames(2);
        clear_counts();
        run_frames(2);
        if (dim_inside != 0)    fail("overlay still drawing after disable");
        if (pass_inside == 0)   fail("picture not restored after disable");

        if (errors == 0)
            $display("PASS: overlay follows enable and every pause starts from the top");
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #200000000;
        $display("RESULT: FAIL (timeout, %0d frames)", frames);
        $finish;
    end

endmodule
