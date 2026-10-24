//============================================================================
//
//  Text cursor: the block must never outlive its own character row.
//
//  UM6845R's cursor_line latches on at CRTC index 0Ah (cursor start) and
//  clears at index 0Bh (cursor end). If R11 is programmed past the last real
//  scanline of the current font, "line" never reaches it and the latch never
//  clears - it stays on from R10 onward for the rest of the frame, showing a
//  cursor across the whole cell (and, since the check runs every row, into
//  rows below it too) instead of the intended block.
//
//  This is not hypothetical: the real IBM EGA BIOS's INT 10h AH=01h (set
//  cursor shape) adds 5 to both start and end whenever the display switches
//  read as an Enhanced Color Display - a documented CGA-cursor-emulation
//  rescale from an 8-line CGA cell to a 14-line EGA one - and 0x06/0x0D
//  becomes 11/19, past the last scanline (13) of an 8x14 font. This core
//  reports that same switch pattern, so any program going through the BIOS
//  cursor-shape service with an EGA-native (>4) shape hits this.
//
//  86Box guards against exactly this in vid_ega.c's per-scanline cursor
//  update:
//
//      if ((ega->scanline == (ega->crtc[11] & 31)) ||
//          (ega->scanline == ega->rowcount))
//          ega->cursorvisible = 0;
//
//  clearing at the last scanline of the row regardless of what R11 says.
//  UM6845R.v now carries the same OR.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_cursor_range_tb;

    reg clk = 1'b0;
    always #17.462 clk = ~clk;

    reg reset = 1'b1;
    reg [14:0] bus_a = 15'h0000;
    reg [7:0]  bus_d = 8'h00;
    reg        bus_ior_l = 1'b1;
    reg        bus_iow_l = 1'b1;
    reg        bus_aen = 1'b0;

    wire [15:0] fetch_addr;
    wire        fetch_en;
    wire [15:0] text_cell_addr, text_font_addr;
    wire        text_fetch_en;
    reg  [7:0]  plane0=0, plane1=0, plane2=0, plane3=0;
    reg         fetch_valid = 1'b0;
    reg  [7:0]  text_char=0, text_attr=8'h0F, text_glyph=8'hFF;
    reg         text_valid = 1'b0;
    reg [4:0]   tv_d = 5'd0;
    wire text_tag;  reg [4:0] tg_d = 5'd0;  reg text_tag_back = 1'b0;
    wire hsync, hblank, vsync, vblank, de_o;
    wire [5:0] red, green, blue;
    wire [7:0] bus_out;
    wire       bus_dir;

    reg [15:0] fetch_addr_q; reg fetch_en_q; reg text_fetch_en_q;
    always @(posedge clk) begin
        fetch_en_q<=fetch_en; fetch_addr_q<=fetch_addr; fetch_valid<=fetch_en_q;
        plane0<=8'hAA; plane1<=8'h00; plane2<=8'h00; plane3<=8'h00;
        tv_d <= {tv_d[3:0], text_fetch_en}; text_valid <= tv_d[3];
        tg_d <= {tg_d[3:0], text_tag};  text_tag_back <= tg_d[3];
    end

    always @(posedge clk) begin
        text_char <= 8'h41;
        text_attr <= 8'h0F;
        text_glyph <= 8'hFF;
    end

    ega_top dut (
        .clk(clk), .reset(reset),
        .bus_a(bus_a), .bus_ior_l(bus_ior_l), .bus_iow_l(bus_iow_l), .bus_d(bus_d),
        .bus_out(bus_out), .bus_dir(bus_dir), .bus_aen(bus_aen),
        .ega_fetch_addr(fetch_addr), .ega_fetch_en(fetch_en),
        .ega_plane0_data(plane0), .ega_plane1_data(plane1),
        .ega_plane2_data(plane2), .ega_plane3_data(plane3),
        .ega_fetch_data_valid(fetch_valid),
        .ega_text_cell_addr(text_cell_addr), .ega_text_scanline(), .ega_text_tag(text_tag),
        .ega_text_fetch_en(text_fetch_en),
        .ega_text_char(text_char), .ega_text_attr(text_attr), .ega_text_glyph(text_glyph),
        .ega_text_data_valid(text_valid), .ega_text_tag_in(text_tag_back),
        .cpu_mem_select(1'b0), .cpu_mem_write(1'b0),
        .ega_cfg_toggle(), .ega_plane_write_mask_out(), .ega_odd_even_mode_out(),
        .ega_cpu_access_slot_out(), .ega_chain2_write_out(), .ega_chain2_read_out(),
        .ega_extended_memory_out(), .ega_mem_map_sel_out(), .ega_page_select_out(),
        .ega_write_mode_out(), .ega_read_mode_out(), .ega_read_plane_sel_out(),
        .ega_color_compare_out(), .ega_color_dont_care_out(), .ega_bit_mask_out(),
        .ega_set_reset_out(), .ega_enable_set_reset_out(), .ega_rop_select_out(),
        .ega_rotate_count_out(), .ega_blink_counter_out(), .ega_blink_state_out(),
        .hsync(hsync), .hblank(hblank), .dbl_hsync(), .vsync(vsync), .vblank(vblank),
        .vblank_border(), .std_hsyncwidth(), .de_o(de_o),
        .ega_red(red), .ega_green(green), .ega_blue(blue),
        .ega_display_sel_out(), .ega_dot_toggle_out(), .ega_dot_clock_sel_out(),
        .ega_scandouble_active_out(),
        .prebios_video(1'b0), .splashscreen(1'b0), .ext_splash_pixel_index(4'd0), .ext_splash_pixel_valid(1'b0), .thin_font(1'b0), .scandouble_en(1'b0),
        .ega_enabled(1'b1), .ega_monitor_profile(2'b00),
        .crt_h_offset(4'd0), .crt_v_offset(3'd0),
        .vsync_width_osd(3'd0), .hsync_width_osd(3'd0)
    );

    task io_write(input [14:0] a, input [7:0] d);
        begin
            @(posedge clk); bus_a<=a; bus_d<=d; bus_aen<=1'b0;
            repeat(4) @(posedge clk);
            bus_iow_l<=1'b0; repeat(8) @(posedge clk); bus_iow_l<=1'b1;
            repeat(6) @(posedge clk);
        end
    endtask
    task crtc_write(input [7:0] i, input [7:0] d); begin io_write(15'h03D4,i); io_write(15'h03D5,d); end endtask
    task seq_write(input [7:0] i, input [7:0] d); begin io_write(15'h03C4,i); io_write(15'h03C5,d); end endtask
    task gfx_write(input [7:0] i, input [7:0] d); begin io_write(15'h03CE,i); io_write(15'h03CF,d); end endtask

    task program_cursor(input [7:0] start, input [7:0] endv);
        begin
            crtc_write(8'h0A, start);
            crtc_write(8'h0B, endv);
        end
    endtask

    integer errors = 0;
    integer checks = 0;
    integer r, s;
    reg [13:0] cursor_seen;

    // A bench that waits on a signal that never moves should say so, not hang.
    initial begin
        #40_000_000;
        $display("TIMEOUT: the bench blocked waiting for the display");
        $display("RESULT: FAIL");
        $finish;
    end

    task capture_row(output [13:0] pattern);
        begin
            pattern = 14'd0;
            for (s = 0; s <= 13; s = s + 1) begin
                @(posedge dut.ega_crtc.line_new);
                pattern[dut.ega_crtc.line] = dut.ega_crtc.cursor_line;
            end
        end
    endtask

    // The reported symptom, directly: cursor_line must be clear at the very
    // top of the row (scanlines 0-3, well below any of the start values used
    // below) in every row, not just the one it was programmed on. A latch
    // that never clears shows up here as scanline 0 still being set, carried
    // over from wherever it last turned on.
    task check_bounded(input [255:0] label, input [7:0] start, input [7:0] endv);
        begin
            program_cursor(start, endv);
            repeat (3) @(negedge vblank);
            capture_row(cursor_seen);   // settling row, register change mid-cycle
            capture_row(cursor_seen);
            checks = checks + 1;
            if (cursor_seen[3:0] !== 4'b0000) begin
                errors = errors + 1;
                $display("FAIL %0s: cursor_line already set at the top of the row (scanlines 0-3 = %04b), start=%0d end=%0d",
                         label, cursor_seen[3:0], start, endv);
            end
            capture_row(cursor_seen);   // a further row, well past any settling
            checks = checks + 1;
            if (cursor_seen[3:0] !== 4'b0000) begin
                errors = errors + 1;
                $display("FAIL %0s: cursor_line spilled into a later row's top (scanlines 0-3 = %04b), start=%0d end=%0d",
                         label, cursor_seen[3:0], start, endv);
            end
            // A start scanline inside 0..13 must turn the cursor on; a start
            // past 13 can never match "line" at all (5 bit register, but line
            // itself never counts past line_max), so the correct outcome
            // there is simply "never visible", not "stuck" - check whichever
            // applies instead of assuming the value is reachable.
            checks = checks + 1;
            if (start <= 8'd13) begin
                if (cursor_seen[start[4:0]] !== 1'b1) begin
                    errors = errors + 1;
                    $display("FAIL %0s: cursor_line never turned on at its own start scanline (%0d)",
                             label, start);
                end
            end else if (cursor_seen !== 14'd0) begin
                errors = errors + 1;
                $display("FAIL %0s: start scanline %0d is unreachable, expected the cursor fully invisible, got %014b",
                         label, start, cursor_seen);
            end
        end
    endtask

    // The exact set of scanlines the cursor covers.
    task check_span(input [255:0] label, input [7:0] start, input [7:0] endv,
                    input [13:0] expected);
        begin
            program_cursor(start, endv);
            repeat (3) @(negedge vblank);
            capture_row(cursor_seen);       // settling row after the write
            capture_row(cursor_seen);
            checks = checks + 1;
            if (cursor_seen !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: covers %014b, expected %014b",
                         label, cursor_seen, expected);
            end
        end
    endtask

    initial begin
        repeat (20) @(posedge clk); reset <= 1'b0; repeat (20) @(posedge clk);

        io_write(15'h03C2, 8'h23);
        seq_write(8'h01, 8'h00);
        seq_write(8'h04, 8'h02);
        gfx_write(8'h06, 8'h0E);
        // Only R9 carries a real value here - the 14 scanline cell this bench
        // walks. Everything else is deliberately tiny: cursor_line depends on
        // the cell height and on R10/R11, never on how many characters a line
        // holds or how many rows a frame has, and the original geometry (113
        // characters, 357 scanlines once the R7 overflow bits are counted) made
        // this the slowest bench in the tree by an order of magnitude.
        crtc_write(8'h00, 8'd13);  crtc_write(8'h01, 8'd8);  crtc_write(8'h02, 8'd9);
        crtc_write(8'h03, 8'd10);  crtc_write(8'h04, 8'd10); crtc_write(8'h05, 8'h03);
        crtc_write(8'h06, 8'd41);  crtc_write(8'h07, 8'h00); crtc_write(8'h09, 8'h0D);
        crtc_write(8'h0C, 8'h00); crtc_write(8'h0D, 8'h00);
        crtc_write(8'h0E, 8'h00); crtc_write(8'h0F, 8'h00);
        crtc_write(8'h10, 8'd32); crtc_write(8'h12, 8'd27); crtc_write(8'h13, 8'd4);
        crtc_write(8'h17, 8'hE3); crtc_write(8'h15, 8'd28); crtc_write(8'h16, 8'd41);
        crtc_write(8'h18, 8'hFF);

        // Well-formed shapes (both registers inside 0..13): must still work,
        // this fix must not change ordinary cursor behaviour. Only the start
        // scanline is asserted here - the exact scanline the block closes on
        // is a separate, pre-existing +/-1 characteristic of this design,
        // unrelated to the out-of-range latch-up this bench targets.
        program_cursor(8'h0B, 8'h0C);   // 11,12: normal underline, in range
        repeat (3) @(negedge vblank);
        capture_row(cursor_seen);
        capture_row(cursor_seen);
        checks = checks + 1;
        if (cursor_seen[11] !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL in-range underline (11,12): scanline 11 = %0b, expected 1", cursor_seen[11]);
        end
        checks = checks + 1;
        if (cursor_seen[3:0] !== 4'b0000) begin
            errors = errors + 1;
            $display("FAIL in-range underline (11,12): cursor_line set at the top of the row (scanlines 0-3 = %04b)", cursor_seen[3:0]);
        end

        // The BIOS-adjusted out-of-range shapes that would otherwise latch on
        // for the rest of the frame.
        check_bounded("half-block BIOS-adjusted (11,19)", 8'h0B, 8'h13);
        check_bounded("underline BIOS-adjusted (16,17)",  8'h10, 8'h11);
        check_bounded("start in range, end far out (8,31)", 8'h08, 8'h1F);

        // The exact set of scanlines the cursor covers, against 86Box. It sets
        // cursorvisible using the already incremented scanline and clears it
        // at the end of the line matching crtc[11], so R10 to R11 are drawn
        // inclusive; with start past end it runs on to rowcount instead of
        // wrapping to the top of the cell.
        crtc_write(8'h09, 8'h07);           // 8 line cell, the 200 line modes
        repeat (3) @(negedge vblank);
        check_span("8 line cell, BIOS underline (6,7)", 8'h06, 8'h07, 14'b00000011000000);
        check_span("8 line cell, end before start (6,0)", 8'h06, 8'h00, 14'b00000011000000);
        check_span("8 line cell, full block (0,7)", 8'h00, 8'h07, 14'b00000011111111);

        crtc_write(8'h09, 8'h0D);           // 14 line cell, the 350 line modes
        repeat (3) @(negedge vblank);
        check_span("14 line cell, BIOS underline (11,12)", 8'h0B, 8'h0C, 14'b01100000000000);

        $display("");
        $display("%0d checks, %0d failed", checks, errors);
        $display("RESULT: %0s", (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #1_500_000_000; $display("RESULT: FAIL (timeout)"); $finish; end

endmodule
