`timescale 1ns/1ps

// Checks that cga_border_window gives the scaler frames of the same size
// (V_LINES lines of H_WIDTH pixels, one run per line) placed after the sync
// pulses, with regular timing and with the irregular timing of demos: long
// HSYNC, short and long frames, an early VSYNC, no VSYNC, a short line.
// V_EARLY is the OSD CRT V offset; the window comes V_START lines after the held-back VSYNC,
// so every step of the offset brings it one line earlier. The default pair (8, 0) puts it
// where it was with V_START 15 and no hold-back.
//   iverilog -g2012 -o bw.vvp TESTBENCH/cga_border_window_tb.sv cga_border_window.sv && vvp bw.vvp
//   (also -P cga_border_window_tb.V_START=15 -P cga_border_window_tb.V_EARLY=7, and V_EARLY=4)
module cga_border_window_tb;
    parameter integer V_START = 8;
    parameter integer V_EARLY = 0;
    reg clk = 0, ce = 0;
    always #5 clk = ~clk;
    always @(posedge clk) ce <= ~ce;

    reg  hsync = 0, vsync = 0;
    wire hblank, vblank, hs_out, vs_out;
    cga_border_window #(.V_START(V_START)) dut (.clk(clk), .ce(ce), .hsync(hsync), .vsync(vsync), .v_early(V_EARLY[2:0]),
        .hblank(hblank), .vblank(vblank), .hsync_out(hs_out), .vsync_out(vs_out));

    localparam integer W = 768, H = 246;
    localparam integer X0 = 129;            // window start after the HSYNC edge (as sampled here)
    localparam integer Y0 = V_START + 1 + 7 - V_EARLY;  // first window line: 16th HSYNC after VSYNC at offset 0

    integer errors = 0, tick = 0;
    integer hs_tick = 0, hs_count = 0, vs_hs = 0;
    integer run = 0, lines = 0, frames = 0, bad_frames = 0, bad_runs = 0, bad_x = 0, bad_y = 0;
    integer hs_len = 0, hs_max = 0;
    reg     win_q = 0, hs_q = 0, vs_q = 0, vso_q = 0, hso_q = 0, first = 1;
    wire    win = !hblank && !vblank;

    always @(posedge ce) begin
        tick <= tick + 1;
        hs_q <= hsync; vs_q <= vsync; win_q <= win; vso_q <= vs_out; hso_q <= hs_out;
        if (hsync && !hs_q) begin hs_tick <= tick; hs_count <= hs_count + 1; end
        if (vsync && !vs_q) vs_hs <= hs_count;
        // HSYNC sent on
        if (hs_out) hs_len <= hs_len + 1;
        if (!hs_out && hso_q) begin if (hs_len > hs_max) hs_max = hs_len; hs_len <= 0; end
        if (win && hs_out) bad_runs = bad_runs + 1;
        // what the scaler counts
        if (win && !win_q) begin
            run <= 1;
            lines <= lines + 1;
            if (tick - hs_tick != X0) bad_x = bad_x + 1;
            if (first && hs_count - vs_hs != Y0) bad_y = bad_y + 1;
            first <= 0;
        end else if (win) run <= run + 1;
        if (!win && win_q && run != W) bad_runs = bad_runs + 1;
        if (vs_out && !vso_q) begin
            if (lines != 0) begin
                frames = frames + 1;
                if (lines != H) bad_frames = bad_frames + 1;
            end
            lines <= 0;
            first <= 1;
        end
    end

    // one line of p pixels with an HSYNC of hw pixels at 720; vs: VSYNC on it
    task line(input integer p, input integer hw, input integer vs);
        integer t;
        begin
            for (t = 0; t < p; t = t + 1) begin
                @(posedge ce);
                hsync <= (t >= 720 && t < 720 + hw);
                if (t == 0) vsync <= vs;
            end
        end
    endtask

    // n frames of l lines, VSYNC 16 lines long (vs = 0: no VSYNC)
    task frames_of(input integer n, input integer l, input integer hw, input integer vs);
        integer f, k;
        begin
            for (f = 0; f < n; f = f + 1)
                for (k = 0; k < l; k = k + 1) line(912, hw, vs && k < 16);
        end
    endtask

    task reset_counts;
        begin frames = 0; bad_frames = 0; bad_runs = 0; bad_x = 0; bad_y = 0; hs_max = 0; end
    endtask

    // nf frames expected; xy: also check the place of the window
    task report(input [255:0] name, input integer nf, input integer xy, input integer hsmax);
        begin
            $display("%0s: frames %0d, wrong size %0d, wrong runs %0d, x off %0d, y off %0d, HSYNC out %0d",
                     name, frames, bad_frames, bad_runs, bad_x, bad_y, hs_max);
            if (frames < nf || bad_frames || bad_runs || (xy && (bad_x || bad_y)) || hs_max != hsmax) begin
                errors = errors + 1;
                $display("  FAIL");
            end
        end
    endtask

    initial begin
        #100;
        frames_of(3, 262, 80, 1);                    // lock
        reset_counts; frames_of(4, 262, 80, 1);   report("80 col BIOS        ", 4, 1, 80);
        reset_counts; frames_of(4, 262, 160, 1);  report("40 col BIOS hsync  ", 4, 1, 80);
        frames_of(1, 262, 80, 1);                    // back to an 80-pixel HSYNC
        reset_counts; frames_of(5, 255, 80, 1);   report("255-line frames    ", 5, 1, 80);
        reset_counts; frames_of(4, 300, 80, 1);   report("300-line frames    ", 4, 1, 80);
        // an early VSYNC cuts one frame, then the window is back in place
        frames_of(1, 150, 80, 1); frames_of(2, 262, 80, 1);
        reset_counts; frames_of(3, 262, 80, 1);   report("after early VSYNC  ", 3, 1, 80);
        reset_counts; frames_of(4, 262, 80, 0);   report("no VSYNC           ", 2, 0, 80);
        frames_of(2, 262, 80, 1);
        // one short line: the window waits for its own end
        reset_counts;
        frames_of(1, 100, 80, 1); line(800, 80, 0); frames_of(1, 162, 80, 0); frames_of(2, 262, 80, 1);
        report("short line         ", 2, 0, 80);
        if (errors == 0) $display("PASS"); else $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
