//============================================================================
//
//  Horizontal Pel Panning (attribute controller index 13h) against 86Box.
//
//  86Box turns the register into a shift in dots in vid_ega.c:
//
//      scrollcache = (attrregs[0x13] & 0x0F);
//      if (scrollcache >= 8) scrollcache = 0; else scrollcache++;
//      if (seqregs[1] & 8)   scrollcache <<= 1;
//      x_add = (overscan_x >> 1) - scrollcache;
//
//  and gives one dot width back at the top of both renderers in the 8 dot
//  character modes ("compensate for 8dot scroll"). Net of the two:
//
//      8 dot, full dot clock    pan 0-7  -> 0..7 dots left, 8-15 -> 1 right
//      8 dot, halved dot clock  pan 0-7  -> 0..14 even,     8-15 -> 2 right
//      9 dot                    pan 0-7  -> 1..8 dots left, 8-15 -> aligned
//
//  The bench puts a single lit dot a known distance into every row, sweeps the
//  register and checks where that dot lands relative to the start of the
//  displayed window. It also checks that a solid row still fills the window at
//  every panning value, which only holds if the extra character a panned line
//  needs is actually fetched, and that the window itself does not move against
//  HSYNC - panning must shift the picture, not the raster.
//
//  The second half covers Line Compare and split screen, the other register
//  that decides where a scanline is fetched from. 86Box builds the compare in
//  ega_recalctimings and acts on it in ega_poll:
//
//      split = crtc[0x18] | overflow bit 8 | max scan line bit 9; split++;
//      if (vc == split) { memaddr = memaddr_backup = 0; scanline = 0; }
//
//  so the scanline the register names is the last one drawn from the start
//  address. Two regions with different patterns make it possible to read off,
//  scanline by scanline, which one is on screen and which row of it.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_pan_split_tb;

    reg clk = 1'b0;
    always #17.462 clk = ~clk;   // 28.636363 MHz video clock

    reg reset = 1'b1;

    reg [14:0] bus_a = 15'h0000;
    reg [7:0]  bus_d = 8'h00;
    reg        bus_ior_l = 1'b1;
    reg        bus_iow_l = 1'b1;
    reg        bus_aen = 1'b0;
    reg        cpu_mem_select = 1'b0;
    reg        cpu_mem_write = 1'b0;

    wire [15:0] fetch_addr;
    wire        fetch_en;
    wire [15:0] text_cell_addr;
    wire [15:0] text_font_addr;
    wire        text_fetch_en;

    reg [7:0] plane0 = 8'h00, plane1 = 8'h00, plane2 = 8'h00, plane3 = 8'h00;
    reg       fetch_valid = 1'b0;
    reg [7:0] text_char = 8'h00, text_attr = 8'h00, text_glyph = 8'h00;
    reg       text_valid = 1'b0;
    reg [4:0] tv_d = 5'd0;
    wire text_tag;  reg [4:0] tg_d = 5'd0;  reg text_tag_back = 1'b0;
    reg       text_solid = 1'b0;

    wire hsync, hblank, vsync, vblank;
    wire de_o;
    wire [5:0] red, green, blue;

    integer errors = 0;
    integer checks = 0;

    // --- VRAM model, same two clock latency as ega_vram_bram_frontend --------
    reg [7:0]  vram_p0 [0:65535];
    reg [15:0] fetch_addr_q;
    reg        fetch_en_q;
    reg        text_fetch_en_q;

    integer i;

    always @(posedge clk) begin
        fetch_en_q   <= fetch_en;
        fetch_addr_q <= fetch_addr;
        fetch_valid  <= fetch_en_q;
        plane0       <= vram_p0[fetch_addr_q];
        plane1       <= 8'h00;
        plane2       <= 8'h00;
        plane3       <= 8'h00;
    end

    always @(posedge clk) begin
        tv_d <= {tv_d[3:0], text_fetch_en};
        text_valid      <= tv_d[3];
        tg_d <= {tg_d[3:0], text_tag};  text_tag_back <= tg_d[3];
        text_char       <= 8'h00;
        text_attr       <= 8'h0F;
        // only the third cell of a row carries a lit dot, in its leftmost column
        text_glyph      <= text_solid ? 8'hFF :
                           ((text_cell_addr[2:0] == 3'd2) ? 8'h80 : 8'h00);
    end

    ega_top dut (
        .clk(clk),
        .reset(reset),
        .bus_a(bus_a),
        .bus_ior_l(bus_ior_l),
        .bus_iow_l(bus_iow_l),
        .bus_d(bus_d),
        .bus_out(),
        .bus_dir(),
        .bus_aen(bus_aen),
        .ega_fetch_addr(fetch_addr),
        .ega_fetch_en(fetch_en),
        .ega_plane0_data(plane0),
        .ega_plane1_data(plane1),
        .ega_plane2_data(plane2),
        .ega_plane3_data(plane3),
        .ega_fetch_data_valid(fetch_valid),
        .ega_text_cell_addr(text_cell_addr),
        .ega_text_scanline(), .ega_text_tag(text_tag),
        .ega_text_fetch_en(text_fetch_en),
        .ega_text_char(text_char),
        .ega_text_attr(text_attr),
        .ega_text_glyph(text_glyph),
        .ega_text_data_valid(text_valid), .ega_text_tag_in(text_tag_back),
        .vga_framebuffer_addr(),
        .vga_framebuffer_read_en(),
        .vga_framebuffer_pixel(8'h00),
        .vga_framebuffer_data_valid(1'b0),
        .cpu_mem_select(cpu_mem_select),
        .cpu_mem_write(cpu_mem_write),
        .ega_cfg_toggle(),
        .ega_plane_write_mask_out(),
        .ega_odd_even_mode_out(),
        .ega_cpu_access_slot_out(),
        .ega_chain2_write_out(),
        .ega_chain2_read_out(),
        .ega_extended_memory_out(),
        .ega_mem_map_sel_out(),
        .ega_page_select_out(),
        .ega_write_mode_out(),
        .ega_read_mode_out(),
        .ega_read_plane_sel_out(),
        .ega_color_compare_out(),
        .ega_color_dont_care_out(),
        .ega_bit_mask_out(),
        .ega_set_reset_out(),
        .ega_enable_set_reset_out(),
        .ega_rop_select_out(),
        .ega_rotate_count_out(),
        .ega_blink_counter_out(),
        .ega_blink_state_out(),
        .hsync(hsync),
        .hblank(hblank),
        .dbl_hsync(),
        .vsync(vsync),
        .vblank(vblank),
        .vblank_border(),
        .std_hsyncwidth(),
        .de_o(de_o),
        .ega_red(red),
        .ega_green(green),
        .ega_blue(blue),
        .ega_display_sel_out(),
        .ega_dot_toggle_out(),
        .ega_dot_clock_sel_out(),
        .ega_scandouble_active_out(),
        .prebios_video(1'b0),
        .splashscreen(1'b0), .ext_splash_pixel_index(4'd0), .ext_splash_pixel_valid(1'b0),
        .thin_font(1'b0),
        .scandouble_en(1'b0),
        .ega_enabled(1'b1),
        .ega_monitor_profile(2'b00),
        .vga_enabled(1'b0),
        .vga_mode13_set(1'b0),
        .vga_mode13_clear(1'b0),
        .vga_mode13_active_out(),
        .crt_h_offset(4'd0),
        .crt_v_offset(3'd0),
        .vsync_width_osd(3'd0),
        .hsync_width_osd(3'd0)
    );

    // ---------------------------------------------------------------- I/O ---
    task io_write(input [14:0] a, input [7:0] d);
        begin
            @(posedge clk);
            bus_a <= a; bus_d <= d; bus_aen <= 1'b0;
            repeat (4) @(posedge clk);
            bus_iow_l <= 1'b0;
            repeat (8) @(posedge clk);
            bus_iow_l <= 1'b1;
            repeat (6) @(posedge clk);
        end
    endtask

    task crtc_write(input [7:0] idx, input [7:0] d);
        begin io_write(15'h03D4, idx); io_write(15'h03D5, d); end
    endtask

    task seq_write(input [7:0] idx, input [7:0] d);
        begin io_write(15'h03C4, idx); io_write(15'h03C5, d); end
    endtask

    task gfx_write(input [7:0] idx, input [7:0] d);
        begin io_write(15'h03CE, idx); io_write(15'h03CF, d); end
    endtask

    task attr_reset_ff;
        begin
            // reading Input Status 1 resets the address/data flip flop
            @(posedge clk);
            bus_a <= 15'h03DA; bus_ior_l <= 1'b0;
            repeat (8) @(posedge clk);
            bus_ior_l <= 1'b1;
            repeat (6) @(posedge clk);
        end
    endtask

    task attr_write(input [7:0] idx, input [7:0] d);
        begin
            attr_reset_ff;
            io_write(15'h03C0, idx);
            io_write(15'h03C0, d);
            io_write(15'h03C0, 8'h20);   // back to normal palette operation
        end
    endtask

    // What EGA software actually does: index at 3C0h, value at 3C1h. The card
    // does not decode A0 for this register, so the write has to land.
    task attr_write_via_3c1(input [7:0] idx, input [7:0] d);
        begin
            attr_reset_ff;
            io_write(15'h03C0, idx | 8'h20);
            io_write(15'h03C1, d);
        end
    endtask

    // ------------------------------------------------------- line inspection -
    integer dot_count = 0;
    integer first_lit = -1;
    integer lit_count = 0;
    integer de_start = 0;
    integer de_dots = 0;
    reg     prev_de = 1'b0;
    reg     prev_hsync = 1'b0;

    wire ce_pix = dut.ce_pix;
    wire lit = (red != 6'h00) || (green != 6'h00) || (blue != 6'h00);

    always @(posedge clk) begin
        if (ce_pix) begin
            if (hsync && !prev_hsync) dot_count <= 0;
            else                      dot_count <= dot_count + 1;
            prev_hsync <= hsync;

            if (de_o && !prev_de) de_start <= dot_count;
            prev_de <= de_o;

            if (de_o) de_dots <= de_dots + 1;

            if (de_o && lit) begin
                if (first_lit < 0) first_lit <= dot_count;
                lit_count <= lit_count + 1;
            end
        end
    end

    // Sample the second displayed line of a frame, so the measurement never
    // lands on the first line of a freshly reprogrammed mode.
    task measure(output integer lit_at, output integer lit_dots, output integer win);
        begin
            @(negedge vblank);
            wait (de_o == 1'b1);
            wait (de_o == 1'b0);
            first_lit = -1; lit_count = 0;
            wait (de_o == 1'b1);
            wait (de_o == 1'b0);
            lit_at   = first_lit;
            lit_dots = lit_count;
            win      = de_start;
        end
    endtask

    integer lit_at, lit_dots, win;
    integer pan;
    integer probe_dot;
    integer probe_ref;
    integer got_shift;

    // Everything is measured against where the probe sits at pan 0, so the test
    // states what panning does and stays silent about the fixed pipeline
    // alignment of each mode, which is tuned elsewhere and is not its business.
    // Also pins the pipeline alignment. probe_dot is where the lit dot sits in
    // the row; probe_ref is where it lands in the displayed window. They differ
    // by however many dots of the row fall off the left edge, which must be
    // zero - the delay from the CRTC's display enable to the first dot reaching
    // the attribute controller is a fixed property of each mode's fetch path,
    // and if the window is tapped later than that, the leftmost pixels of every
    // row are simply cut. The one legitimate exception is a 9 dot cell with the
    // panning register at 0, where the EGA table itself asks for one dot of
    // shift and the BIOS writes 08h to cancel it.
    task capture_reference(input [255:0] label, input integer expected_lost);
        begin
            attr_write(8'h13, 8'h00);
            measure(lit_at, lit_dots, win);
            probe_ref  = lit_at - win;
            window_ref = win;
            checks = checks + 1;
            if ((probe_dot - probe_ref) !== expected_lost) begin
                errors = errors + 1;
                $display("FAIL %0s alignment: %0d dots of the row fall off the left edge, expected %0d",
                         label, probe_dot - probe_ref, expected_lost);
            end
        end
    endtask

    task check_shift(input [255:0] label, input integer pan_value,
                     input integer expected);
        begin
            attr_write(8'h13, pan_value[7:0]);
            measure(lit_at, lit_dots, win);
            got_shift = probe_ref - (lit_at - win);
            checks = checks + 1;
            if (got_shift !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s pan=%0d: shifted %0d dots from pan 0, expected %0d",
                         label, pan_value, got_shift, expected);
            end
        end
    endtask

    task check_filled(input [255:0] label, input integer pan_value,
                      input integer expected_dots);
        begin
            attr_write(8'h13, pan_value[7:0]);
            measure(lit_at, lit_dots, win);
            checks = checks + 1;
            if (lit_dots !== expected_dots) begin
                errors = errors + 1;
                $display("FAIL %0s pan=%0d: %0d lit dots in the window, expected %0d",
                         label, pan_value, lit_dots, expected_dots);
            end
        end
    endtask

    integer window_ref;

    task check_window_fixed(input [255:0] label);
        begin
            checks = checks + 1;
            if (win !== window_ref) begin
                errors = errors + 1;
                $display("FAIL %0s: display window moved to dot %0d, was %0d",
                         label, win, window_ref);
            end
        end
    endtask

    // ------------------------------------------------------- split screen ---
    // Two regions that are told apart by where the lit dot sits in the line:
    // the top one is fetched from the start address and lights dot 16, the
    // bottom one from address 0 and lights dot 48.
    localparam integer SPLIT_START_ADDR = 16'h0040;
    localparam integer SPLIT_TOP_DOT    = 16;
    localparam integer SPLIT_BOTTOM_DOT = 48;

    task split_pattern;
        begin
            for (i = 0; i < 256; i = i + 1) vram_p0[i] = 8'h00;
            // bottom region: rows based at address 0, dot in the fourth cell
            for (i = 0; i < 8; i = i + 1) vram_p0[(i * 8) + 3] = 8'h80;
            // top region: rows based at the start address, dot in the second
            for (i = 0; i < 8; i = i + 1) vram_p0[SPLIT_START_ADDR + (i * 8) + 1] = 8'h80;
        end
    endtask

    integer scan_lit [0:15];
    integer scan_lines;

    // Walk one frame and record, for every displayed scanline, where its first
    // lit dot sits relative to the start of the window.
    task split_profile;
        begin
            @(negedge vblank);
            scan_lines = 0;
            while (vblank == 1'b0 && scan_lines < 16) begin
                first_lit = -1; lit_count = 0;
                @(posedge clk);
                wait ((de_o == 1'b1) || (vblank == 1'b1));
                if (vblank == 1'b0) begin
                    wait ((de_o == 1'b0) || (vblank == 1'b1));
                    scan_lit[scan_lines] = (first_lit < 0) ? -1 : (first_lit - de_start);
                    scan_lines = scan_lines + 1;
                end
            end
        end
    endtask

    integer sl;
    integer exp_lit [0:15];

    // Bottom region with a dot that moves one cell right per character row, so
    // the profile shows not just which region is on screen but which row of it.
    task split_pattern_rows;
        begin
            for (i = 0; i < 256; i = i + 1) vram_p0[i] = 8'h00;
            for (i = 0; i < 8; i = i + 1) vram_p0[(i * 8) + 3 + i] = 8'h80;
            for (i = 0; i < 8; i = i + 1) vram_p0[SPLIT_START_ADDR + (i * 8) + 1] = 8'h80;
        end
    endtask

    task check_split_profile(input [255:0] label, input integer line_compare);
        begin
            crtc_write(8'h18, line_compare[7:0]);
            repeat (3) @(negedge vblank);
            split_profile;
            for (sl = 0; sl < scan_lines; sl = sl + 1) begin
                checks = checks + 1;
                if (scan_lit[sl] !== exp_lit[sl]) begin
                    errors = errors + 1;
                    $display("FAIL %0s scanline %0d: dot %0d, expected %0d",
                             label, sl, scan_lit[sl], exp_lit[sl]);
                end
            end
        end
    endtask

    task check_split(input integer line_compare, input integer first_bottom_line);
        begin
            crtc_write(8'h18, line_compare[7:0]);
            repeat (3) @(negedge vblank);
            split_profile;
            for (sl = 0; sl < scan_lines; sl = sl + 1) begin
                checks = checks + 1;
                if (scan_lit[sl] !== ((sl < first_bottom_line) ? SPLIT_TOP_DOT
                                                               : SPLIT_BOTTOM_DOT)) begin
                    errors = errors + 1;
                    $display("FAIL split lc=%0d scanline %0d: dot %0d, expected %0d",
                             line_compare, sl, scan_lit[sl],
                             (sl < first_bottom_line) ? SPLIT_TOP_DOT : SPLIT_BOTTOM_DOT);
                end
            end
        end
    endtask

    // ------------------------------------------------------ smooth scroll ---
    // A byte granular start address plus a panning value is how EGA software
    // scrolls one pixel at a time, and the two have to reach the screen on the
    // same frame or the picture stutters at every character boundary while
    // moving smoothly in between. Filling memory with a pattern that repeats
    // every four characters makes one lit dot per 64 dots, so the position of
    // the first one reads the combined scroll modulo 64: one step of the
    // software loop must move it exactly one visible pixel.
    localparam integer SCROLL_BASE   = 256;
    localparam integer SCROLL_PERIOD = 64;

    task scroll_pattern;
        begin
            for (i = 0; i < 1024; i = i + 1)
                vram_p0[i] = ((i % 4) == 0) ? 8'h80 : 8'h00;
        end
    endtask

    // Passive monitor: the stimulus below must run at exactly the pace the
    // software sets, so nothing may wait on the display to take a measurement.
    reg        scroll_watch = 1'b0;
    integer    frame_pos [0:63];
    integer    frame_count = 0;
    integer    mon_state = 0;
    integer    mon_dot = 0;
    integer    mon_first = -1;
    reg        mon_vblank_q = 1'b0;
    reg        mon_de_q = 1'b0;

    always @(posedge clk) begin
        if (ce_pix) begin
            mon_vblank_q <= vblank;
            mon_de_q <= de_o;

            if (mon_state == 0) begin
                if (mon_vblank_q && !vblank) mon_state <= 1;
            end else if (mon_state == 1) begin
                if (de_o && !mon_de_q) begin
                    mon_dot   <= 1;
                    mon_first <= lit ? 0 : -1;
                    mon_state <= 2;
                end
            end else begin
                if (de_o) begin
                    mon_dot <= mon_dot + 1;
                    if (lit && (mon_first < 0)) mon_first <= mon_dot;
                end
                if (!de_o && mon_de_q) begin
                    if (scroll_watch && (frame_count < 64)) begin
                        frame_pos[frame_count] <= mon_first;
                        frame_count <= frame_count + 1;
                    end
                    mon_state <= 0;
                end
            end
        end
    end

    // Poll Input Status 1 bit 3 the way wait_vsync() does. The DUT signal is
    // read directly rather than through hundreds of I/O cycles: what this is
    // reproducing is where the writes land inside the frame, and that is not
    // changed by finding the edge a microsecond sooner.
    task wait_vretrace_rise;
        begin
            @(posedge clk);
            wait (dut.ega_status_reg[3] == 1'b0);
            wait (dut.ega_status_reg[3] == 1'b1);
        end
    endtask

    integer xi;
    integer off;

    // The loop from the EGA test program: start address for this step, wait for
    // vertical retrace, then the panning value for the same step.
    task software_scroll_loop(input integer steps);
        begin
            for (xi = 0; xi < steps; xi = xi + 1) begin
                off = SCROLL_BASE + (xi / 8);
                crtc_write(8'h0C, (off >> 8) & 8'hFF);
                crtc_write(8'h0D, off & 8'hFF);
                wait_vretrace_rise;
                attr_write_via_3c1(8'h13, (xi % 8));
            end
        end
    endtask

    integer fp;
    integer delta;
    integer settle;

    task check_smooth_scroll;
        begin
            // The first frames carry the start of the sequence; judge the run
            // once both halves are being updated every frame.
            settle = 4;
            for (fp = settle; fp < frame_count - 1; fp = fp + 1) begin
                delta = frame_pos[fp + 1] - frame_pos[fp];
                if (delta > 0) delta = delta - SCROLL_PERIOD;   // wrapped
                checks = checks + 1;
                if ((frame_pos[fp] < 0) || (frame_pos[fp + 1] < 0)) begin
                    errors = errors + 1;
                    $display("FAIL smooth scroll: frame %0d has no lit dot", fp);
                end else if (delta !== -2) begin
                    errors = errors + 1;
                    $display("FAIL smooth scroll: frame %0d -> %0d moved %0d dots, expected -2  (%0d -> %0d)",
                             fp, fp + 1, delta, frame_pos[fp], frame_pos[fp + 1]);
                end
            end
        end
    endtask

    // ------------------------------------------ Palette Address Source ------
    // Clearing bit 5 of an attribute controller index write takes the beam
    // dark. It must not take the raster with it: the CRTC keeps scanning and
    // the line is still drawn, in black, which is what 86Box does by swapping
    // in ega_render_blank. A 64 colour raster bar effect clears and sets this
    // bit twice per scanline, so if the display window disappears with it the
    // scaler has nothing stable to lock to.
    //
    // Sampled over a whole field rather than by waiting on display enable
    // edges, because the failure being guarded against is display enable never
    // asserting at all.
    integer pas_de, pas_lit;

    task sample_field(output integer de_out, output integer lit_out);
        begin
            @(negedge vblank);
            de_dots = 0;
            lit_count = 0;
            @(posedge vblank);
            de_out = de_dots;
            lit_out = lit_count;
        end
    endtask

    task check_pas;
        begin
            solid_pattern;
            repeat (2) @(negedge vblank);
            sample_field(pas_de, pas_lit);
            checks = checks + 1;
            if (pas_de <= 0) begin
                errors = errors + 1;
                $display("FAIL PAS baseline: no display enable at all");
            end

            // Palette Address Source cleared: index write with bit 5 low.
            attr_reset_ff;
            io_write(15'h03C0, 8'h01);
            repeat (2) @(negedge vblank);
            sample_field(pas_de, pas_lit);
            checks = checks + 1;
            if (pas_de <= 0) begin
                errors = errors + 1;
                $display("FAIL PAS=0: the display window vanished, the raster must survive");
            end
            checks = checks + 1;
            if (pas_lit !== 0) begin
                errors = errors + 1;
                $display("FAIL PAS=0: %0d lit dots, the beam should be dark", pas_lit);
            end

            // and back on
            attr_reset_ff;
            io_write(15'h03C0, 8'h20);
            repeat (2) @(negedge vblank);
            sample_field(pas_de, pas_lit);
            checks = checks + 1;
            if (pas_lit <= 0) begin
                errors = errors + 1;
                $display("FAIL PAS=1: the picture did not come back");
            end
            probe_pattern;
        end
    endtask

    // --------------------------------------------------------------- probe --
    task probe_pattern;
        begin
            for (i = 0; i < 256; i = i + 1) vram_p0[i] = 8'h00;
            // third character of every row (rows are 8 characters apart here)
            for (i = 2; i < 256; i = i + 8) vram_p0[i] = 8'h80;
        end
    endtask

    task solid_pattern;
        begin
            for (i = 0; i < 256; i = i + 1) vram_p0[i] = 8'hFF;
        end
    endtask

    // ---------------------------------------------------------------- main --
    initial begin
        for (i = 0; i < 65536; i = i + 1) vram_p0[i] = 8'h00;
        probe_pattern;

        repeat (20) @(posedge clk);
        reset <= 1'b0;
        repeat (20) @(posedge clk);

        io_write(15'h03C2, 8'h63);     // Miscellaneous Output: colour, 14.318 MHz

        seq_write(8'h01, 8'h09);       // 8 dot characters, halved dot clock
        seq_write(8'h04, 8'h06);

        gfx_write(8'h05, 8'h00);
        gfx_write(8'h06, 8'h05);       // graphics mode, A000 map

        crtc_write(8'h00, 8'd13);      // horizontal total
        crtc_write(8'h01, 8'd8);       // horizontal displayed
        crtc_write(8'h02, 8'd9);
        crtc_write(8'h03, 8'd10);
        // Horizontal retrace: 04h is the character it starts on, 05h is matched
        // against the low five bits of the character counter to end it. On a 14
        // character line only the values below 14 are ever reached, and the CRTC
        // advances both compares by 3 or 4 characters depending on the dot
        // clock, so both the start and the end have to be left inside the line
        // for every mode here. Get it wrong and HSYNC latches high rather than
        // failing outright.
        //
        // This bench stays on the retrace registers: its line is far too short
        // to hold the fixed 256 dot lead the output stage uses on a real mode,
        // so tv_geometry declines it and the fallback path is what runs.
        crtc_write(8'h04, 8'd11);
        crtc_write(8'h05, 8'd15);
        crtc_write(8'h06, 8'd10);      // vertical total
        crtc_write(8'h07, 8'h00);
        crtc_write(8'h08, 8'h00);
        crtc_write(8'h09, 8'h00);
        crtc_write(8'h0C, 8'h00);
        crtc_write(8'h0D, 8'h00);
        crtc_write(8'h10, 8'd7);
        crtc_write(8'h12, 8'd5);       // vertical display end
        crtc_write(8'h13, 8'd4);       // offset: 8 addresses per row
        crtc_write(8'h17, 8'hE3);
        crtc_write(8'h15, 8'd6);
        crtc_write(8'h16, 8'd9);

        attr_write(8'h00, 8'h00);      // palette 0 black, 1 bright white
        attr_write(8'h01, 8'h3F);
        attr_write(8'h10, 8'h01);      // graphics mode
        attr_write(8'h11, 8'h00);      // black overscan, so only pixels light up
        attr_write(8'h12, 8'h0F);
        attr_write(8'h13, 8'h00);

        cpu_mem_select <= 1'b1; cpu_mem_write <= 1'b1;
        repeat (4) @(posedge clk);
        cpu_mem_select <= 1'b0; cpu_mem_write <= 1'b0;

        repeat (8) @(negedge vblank);

        // --- graphics, 8 dot characters, halved dot clock (mode 0Dh) --------
        probe_dot = 32;
        // Each step is one 320 wide pixel, which is what makes a program that
        // scrolls a byte at a time plus a panning value scroll smoothly.
        capture_reference("gfx 320", 0);
        for (pan = 0; pan < 16; pan = pan + 1)
            check_shift("gfx 320", pan, (pan < 8) ? (2 * pan) : -2);
        check_window_fixed("gfx 320");

        // A panned line has to fetch one character more than it displays, or
        // the dots the shift uncovers on the right come out blank.
        solid_pattern;
        for (pan = 0; pan < 16; pan = pan + 1)
            check_filled("gfx 320 solid", pan, (pan < 8) ? 144 : 142);
        probe_pattern;

        // --- graphics, 8 dot characters, full dot clock (mode 10h) ----------
        seq_write(8'h01, 8'h01);
        repeat (4) @(negedge vblank);
        probe_dot = 16;
        capture_reference("gfx 640", 0);
        for (pan = 0; pan < 16; pan = pan + 1)
            check_shift("gfx 640", pan, (pan < 8) ? pan : -1);
        check_window_fixed("gfx 640");

        // --- text, 9 dot characters (mode 03h/07h) --------------------------
        // No "compensate for 8dot scroll" here, so the aligned position is pan
        // 8 - the value the BIOS writes for mode 7 - and pan 0 is one dot left.
        seq_write(8'h01, 8'h00);
        gfx_write(8'h06, 8'h04);
        attr_write(8'h10, 8'h00);
        repeat (4) @(negedge vblank);
        probe_dot = 18;
        capture_reference("text 9 dot", 1);
        for (pan = 0; pan < 16; pan = pan + 1)
            check_shift("text 9 dot", pan, (pan < 8) ? pan : -1);
        check_window_fixed("text 9 dot");

        // --- text, 8 dot characters (mode 02h/03h with 8-dot clocking) ------
        // This is the cell geometry used by the 640-wide MS-DOS Editor screen.
        seq_write(8'h01, 8'h01);
        repeat (4) @(negedge vblank);
        probe_dot = 16;
        capture_reference("text 8 dot", 0);
        text_solid = 1'b1;
        check_filled("text 8 dot solid", 0, 72);
        text_solid = 1'b0;

        // --- text, 8 dot characters, halved dot clock (mode 00h/01h) --------
        // 40 column text: the same cell, but every dot is emitted twice, so the
        // fetch-to-window delay is a different constant from the 80 column one
        // and nothing above exercised it.
        seq_write(8'h01, 8'h09);
        repeat (4) @(negedge vblank);
        probe_dot = 32;
        capture_reference("text 8 dot 320", 0);
        for (pan = 0; pan < 16; pan = pan + 1)
            check_shift("text 8 dot 320", pan, (pan < 8) ? (2 * pan) : -2);
        check_window_fixed("text 8 dot 320");

        // The same cell on the 16.257 MHz oscillator, which is what a 350 line
        // 40 column screen runs on. Dots are one or two clocks apart there, so
        // the delay taps have to hold on both oscillators, not just the exact
        // divide by two.
        io_write(15'h03C2, 8'h67);
        repeat (4) @(negedge vblank);
        capture_reference("text 8 dot 320, 16.257 MHz", 0);
        io_write(15'h03C2, 8'h63);
        repeat (4) @(negedge vblank);

        seq_write(8'h01, 8'h01);
        repeat (4) @(negedge vblank);
        probe_dot = 16;
        capture_reference("text 8 dot", 0);

        // --- the same sweep, but programmed the way software does it --------
        seq_write(8'h01, 8'h09);
        gfx_write(8'h06, 8'h05);
        attr_write(8'h10, 8'h01);
        repeat (4) @(negedge vblank);
        probe_dot = 32;
        capture_reference("gfx 320", 0);
        for (pan = 0; pan < 16; pan = pan + 1) begin
            attr_write_via_3c1(8'h13, pan[7:0]);
            measure(lit_at, lit_dots, win);
            got_shift = probe_ref - (lit_at - win);
            checks = checks + 1;
            if (got_shift !== ((pan < 8) ? (2 * pan) : -2)) begin
                errors = errors + 1;
                $display("FAIL 3C1h write pan=%0d: shifted %0d dots, expected %0d",
                         pan, got_shift, (pan < 8) ? (2 * pan) : -2);
            end
        end

        // --- Line Compare / split screen ------------------------------------
        // The scanline the register names is the last one drawn from the start
        // address; the next one restarts at address 0. 0FFh, what the BIOS
        // writes in every ordinary mode, must never split.
        attr_write(8'h13, 8'h00);
        split_pattern;
        crtc_write(8'h0C, SPLIT_START_ADDR >> 8);
        crtc_write(8'h0D, SPLIT_START_ADDR & 8'hFF);
        crtc_write(8'h07, 8'h00);       // overflow: line compare bit 8 clear
        repeat (4) @(negedge vblank);

        check_split(8'hFF, 99);         // no split anywhere in the frame
        check_split(0, 1);              // only the first scanline is the top
        check_split(2, 3);
        check_split(4, 5);

        // Bit 8 lives in the overflow register, so a compare past 255 must not
        // fold back into the visible frame.
        crtc_write(8'h07, 8'h10);
        check_split(0, 99);
        crtc_write(8'h07, 8'h00);

        // Two scanlines per character row, which is the case that shows whether
        // the split restarted the character row as well as the address: rows 0
        // and 1 of the lower screen must each get their two scanlines. Without
        // the reset the lower screen inherits the scan line it landed on and
        // steps to the next row half a cell early.
        split_pattern_rows;
        crtc_write(8'h09, 8'h01);
        repeat (4) @(negedge vblank);
        exp_lit[0] = 16; exp_lit[1] = 16; exp_lit[2] = 16;
        exp_lit[3] = 48; exp_lit[4] = 48; exp_lit[5] = 64;
        check_split_profile("split, 2 scanline cells", 2);
        crtc_write(8'h09, 8'h00);
        split_pattern;

        // --- smooth scrolling, start address and panning together -----------
        crtc_write(8'h18, 8'hFF);       // no split
        attr_write(8'h13, 8'h00);
        scroll_pattern;
        crtc_write(8'h0C, SCROLL_BASE >> 8);
        crtc_write(8'h0D, SCROLL_BASE & 8'hFF);
        repeat (4) @(negedge vblank);
        frame_count = 0;
        scroll_watch = 1'b1;
        software_scroll_loop(24);
        scroll_watch = 1'b0;
        $display("scroll positions:");
        for (fp = 0; fp < frame_count; fp = fp + 1)
            $write(" %0d", frame_pos[fp]);
        $display("");
        check_smooth_scroll;

        // --- Palette Address Source ------------------------------------------
        seq_write(8'h01, 8'h09);
        gfx_write(8'h06, 8'h05);
        attr_write(8'h10, 8'h01);
        attr_write(8'h13, 8'h00);
        repeat (4) @(negedge vblank);
        check_pas;

        $display("");
        $display("%0d checks, %0d failed", checks, errors);
        $display("RESULT: %0s", (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #60_000_000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

endmodule
