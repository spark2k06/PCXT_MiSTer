//============================================================================
//
//  What the cursor actually looks like on screen.
//
//  ega_cursor_range_tb checks cursor_line inside the CRTC. That is not what a
//  user sees: the flag still has to cross into the text pipeline, which samples
//  it once per character cell, before it becomes pixels. A cursor reported as
//  two adjacent scanlines by the CRTC and drawn as two separated ones would
//  pass that bench and still be wrong.
//
//  So this one reads the vertical profile of the cursor cell straight off the
//  RGB output. The screen is filled with blank glyphs on a plain attribute, so
//  the only thing that can light a dot is the cursor itself.
//
//  Only the registers the cursor depends on carry real values - R9 for the cell
//  height, R10 and R11 for the shape. The rest of the geometry is deliberately
//  tiny: a frame of true mode 3 timing is ~473,000 clocks and a frame here is
//  about 7,000, and nothing about cursor rendering depends on how many
//  characters a line holds.
//
//  The pair measured on hardware after a mode 3 set is 0Ah=06, 0Bh=00, which
//  the BIOS programs on both this core and 86Box, so that case is covered
//  alongside the 06/07 the ROM's parameter table carries.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

// NEEDS: icarus (disable of a named block from outside it, which Verilator 5.020 rejects)
module ega_cursor_render_tb;

    reg clk = 1'b0;
    always #17.462 clk = ~clk;

    reg reset = 1'b1;
    reg [14:0] bus_a = 15'h0000;
    reg [7:0]  bus_d = 8'h00;
    reg        bus_ior_l = 1'b1;
    reg        bus_iow_l = 1'b1;
    reg        bus_aen = 1'b0;
    // ega_video_active only comes up after the CPU has written video memory,
    // so the display stays dark - and de_o low - without this.
    reg        cpu_mem_select = 1'b0;
    reg        cpu_mem_write = 1'b0;

    wire [15:0] fetch_addr;
    wire        fetch_en;
    wire [15:0] text_cell_addr, text_font_addr;
    wire        text_fetch_en;
    reg  [7:0]  plane0=0, plane1=0, plane2=0, plane3=0;
    reg         fetch_valid = 1'b0;
    reg  [7:0]  text_char=0, text_attr=0, text_glyph=0;
    reg         text_valid = 1'b0;
    reg [4:0]   tv_d = 5'd0;
    wire text_tag;  reg [4:0] tg_d = 5'd0;  reg text_tag_back = 1'b0;
    wire hsync, hblank, vsync, vblank, de_o;
    wire [5:0] red, green, blue;
    wire [7:0] bus_out;
    wire       bus_dir;

    // Blank glyphs on grey-on-black: the glyph never lights a dot, so every lit
    // pixel below belongs to the cursor, which swaps foreground and background
    // for the cell it covers.
    always @(posedge clk) begin
        fetch_valid <= fetch_en;
        tv_d <= {tv_d[3:0], text_fetch_en}; text_valid  <= tv_d[1];
        tg_d <= {tg_d[3:0], text_tag};  text_tag_back <= tg_d[1];
        text_char   <= 8'h20;
        text_attr   <= 8'h07;
        text_glyph  <= 8'h00;
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
        .cpu_mem_select(cpu_mem_select), .cpu_mem_write(cpu_mem_write),
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

    // A bench that waits on a signal that never moves should say so, not hang.
    initial begin
        #40_000_000;
        $display("[ega_cursor_render_tb] TIMEOUT: the bench blocked waiting for the display");
        $display("[ega_cursor_render_tb] RESULT: FAIL");
        $finish;
    end

    task io_write(input [14:0] a, input [7:0] d);
        begin
            @(posedge clk); bus_a<=a; bus_d<=d; bus_aen<=1'b0;
            repeat(4) @(posedge clk);
            bus_iow_l<=1'b0; repeat(8) @(posedge clk); bus_iow_l<=1'b1;
            repeat(6) @(posedge clk);
        end
    endtask
    task crtc_write(input [7:0] i, input [7:0] d); begin io_write(15'h03D4,i); io_write(15'h03D5,d); end endtask
    task seq_write (input [7:0] i, input [7:0] d); begin io_write(15'h03C4,i); io_write(15'h03C5,d); end endtask
    task gfx_write (input [7:0] i, input [7:0] d); begin io_write(15'h03CE,i); io_write(15'h03CF,d); end endtask

    task attr_reset_ff;
        begin
            @(posedge clk); bus_a<=15'h03DA; bus_aen<=1'b0;
            repeat(2) @(posedge clk);
            bus_ior_l<=1'b0; repeat(4) @(posedge clk); bus_ior_l<=1'b1;
            repeat(2) @(posedge clk);
        end
    endtask
    task attr_write(input [7:0] i, input [7:0] d);
        begin
            attr_reset_ff;
            io_write(15'h03C0, i);
            io_write(15'h03C0, d);
            io_write(15'h03C0, 8'h20);      // back to normal palette operation
        end
    endtask

    integer i;

    task program_text_mode;
        begin
            io_write(15'h03C2, 8'h23);      // colour, 14.318 MHz
            seq_write(8'h01, 8'h01);        // 8 dot characters, full dot clock
            seq_write(8'h02, 8'h03);
            seq_write(8'h03, 8'h00);
            seq_write(8'h04, 8'h03);

            // Horizontal is kept small - nothing about the cursor depends on
            // how many characters a line holds - but every vertical register
            // carries the option ROM's real 200 line value, because that is the
            // only mode where the stray scanline appears on hardware: 640x350
            // and 720x350 are clean.
            crtc_write(8'h00, 8'd13);       // horizontal total
            crtc_write(8'h01, 8'd8);        // horizontal displayed
            crtc_write(8'h02, 8'd9);
            crtc_write(8'h03, 8'd10);
            crtc_write(8'h04, 8'd10);
            crtc_write(8'h05, 8'h03);
            crtc_write(8'h06, 8'h04);       // vertical total, with R7 bit 0
            crtc_write(8'h07, 8'h11);       // overflow: v total bit 8
            crtc_write(8'h08, 8'h00);
            crtc_write(8'h09, 8'h07);       // 8 scanlines per row
            crtc_write(8'h0C, 8'h00);
            crtc_write(8'h0D, 8'h00);
            crtc_write(8'h0E, 8'h00);       // cursor at the first cell
            crtc_write(8'h0F, 8'h00);
            crtc_write(8'h10, 8'hE1);       // vertical retrace start, 225
            crtc_write(8'h11, 8'h24);
            crtc_write(8'h12, 8'hC7);       // vertical display end, 200 lines
            crtc_write(8'h13, 8'd4);
            crtc_write(8'h14, 8'h08);
            crtc_write(8'h15, 8'hE0);       // vertical blank start, 224
            crtc_write(8'h16, 8'hF0);       // vertical blank end, 240
            crtc_write(8'h17, 8'hA3);
            crtc_write(8'h18, 8'hFF);

            for (i = 0; i <= 15; i = i + 1) attr_write(i[7:0], i[7:0]);
            attr_write(8'h10, 8'h00);       // text mode, no blink
            attr_write(8'h11, 8'h00);       // black overscan
            attr_write(8'h12, 8'h0F);
            attr_write(8'h13, 8'h00);

            gfx_write(8'h05, 8'h10);
            gfx_write(8'h06, 8'h0E);
            gfx_write(8'h08, 8'hFF);
        end
    endtask

    task program_cursor(input [7:0] start, input [7:0] endv);
        begin
            crtc_write(8'h0A, start);
            crtc_write(8'h0B, endv);
        end
    endtask

    // Lit dots on one displayed scanline.
    task scanline_lit(output integer n);
        begin
            n = 0;
            @(posedge de_o);
            while (de_o === 1'b1) begin
                @(posedge clk);
                if (dut.ce_pix && ((red != 6'h00) || (green != 6'h00) || (blue != 6'h00)))
                    n = n + 1;
            end
        end
    endtask

    integer sl, dots;
    reg [7:0] profile;

    // The vertical profile of the first character row: one bit per scanline of
    // the cell, set when that scanline draws anything at all.
    task capture_profile(output [7:0] prof);
        begin
            @(negedge vblank);
            prof = 8'h00;
            for (sl = 0; sl < 8; sl = sl + 1) begin
                scanline_lit(dots);
                prof[sl] = (dots != 0);
            end
        end
    endtask

    // Every displayed scanline of the frame, not just the cursor's own cell.
    // A stray lit line landing in the row above would sit outside the 8 line
    // window above and never be seen, and the count per scanline separates a
    // real cursor line - 8 dots, the full width of the cell - from anything
    // else that happens to light up.
    integer counts [0:31];

    integer lit_lines;

    // Walk every displayed scanline of the frame and report the ones that draw
    // anything, as "scanline (row.line) = dots". Only the cursor can light a
    // dot here, so anything outside its own cell is the stray line.
    task dump_frame(input [255:0] label);
        begin
            @(negedge vblank);
            lit_lines = 0;
            sl = 0;
            $write("  %0s lit:", label);
            while (vblank === 1'b0 && sl < 256) begin
                scanline_lit(dots);
                if (dots != 0) begin
                    $write("  %0d (row %0d line %0d) = %0d dots", sl, sl / 8, sl % 8, dots);
                    lit_lines = lit_lines + 1;
                end
                sl = sl + 1;
            end
            if (lit_lines == 0) $write("  nothing");
            $write("   [%0d displayed scanlines]\n", sl);
        end
    endtask

    integer errors = 0;
    integer checks = 0;

    // A cursor is one solid band. Two lit scanlines with a gap between them is
    // the "one line at the top and one at the bottom" a wrapped cursor draws,
    // and it is what this bench exists to catch.
    function contiguous;
        input [7:0] p;
        integer k, runs;
        reg prev;
        begin
            runs = 0; prev = 1'b0;
            for (k = 0; k < 8; k = k + 1) begin
                if (p[k] && !prev) runs = runs + 1;
                prev = p[k];
            end
            contiguous = (runs <= 1);
        end
    endfunction

    task check_shape(input [255:0] label, input [7:0] start, input [7:0] endv,
                     input [7:0] expected);
        begin
            program_cursor(start, endv);
            capture_profile(profile);       // settling frame after the write
            capture_profile(profile);
            checks = checks + 1;
            if (!contiguous(profile)) begin
                errors = errors + 1;
                $display("FAIL %0s: cursor split across the cell, scanlines %08b", label, profile);
            end
            checks = checks + 1;
            if (profile !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: scanlines %08b, expected %08b", label, profile, expected);
            end else begin
                $display("  %0s: scanlines %08b", label, profile);
            end
        end
    endtask

    integer edges;

    initial begin
        repeat (20) @(posedge clk); reset <= 1'b0; repeat (20) @(posedge clk);
        // The cursor is drawn only while blink_state is high, and that is bit 4
        // of a once-per-frame counter. Hold the phase on rather than spend 16
        // frames per capture waiting for it.
        force dut.ega_blink_counter = 7'h1F;

        program_text_mode();

        // One CPU write to video memory, which is what arms ega_video_active.
        cpu_mem_select <= 1'b1; cpu_mem_write <= 1'b1;
        repeat (4) @(posedge clk);
        cpu_mem_select <= 1'b0; cpu_mem_write <= 1'b0;

        repeat (4) @(negedge vblank);

        // Prove the display is running before measuring anything, so a dead
        // configuration is reported rather than waited on.
        edges = 0;
        fork
            begin : counter
                forever begin @(posedge de_o); edges = edges + 1; end
            end
            begin
                #500_000;
                disable counter;
            end
        join
        if (edges < 8) begin
            $display("[ega_cursor_render_tb] only %0d displayed scanlines in 500 us - configuration is dead", edges);
            $display("[ega_cursor_render_tb] RESULT: FAIL");
            $finish;
        end

        // The whole displayed frame for the pair the BIOS really programs, so
        // a lit line outside the cursor's own cell shows up.
        program_cursor(8'h06, 8'h00);
        dump_frame("(6,0)");
        dump_frame("(6,0)");
        program_cursor(8'h06, 8'h07);
        dump_frame("(6,7)");

        // Bit 0 is the top scanline of the cell, bit 7 the bottom.
        check_shape("BIOS underline (6,7)", 8'h06, 8'h07, 8'b11000000);
        check_shape("as measured on hardware (6,0)", 8'h06, 8'h00, 8'b11000000);
        check_shape("full block (0,7)", 8'h00, 8'h07, 8'b11111111);

        $display("");
        $display("%0d checks, %0d failed", checks, errors);
        if (errors == 0) $display("[ega_cursor_render_tb] RESULT: PASS");
        else             $display("[ega_cursor_render_tb] RESULT: FAIL");
        $finish;
    end

endmodule
