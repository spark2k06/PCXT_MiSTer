//============================================================================
//
//  ega_top I/O qualifier regression
//
//  Covers the transient-address filter and, crucially, the read path that the
//  filter broke. The original verification of that filter drove bus_d as an
//  independent stimulus, so it could not reproduce the failure at all: in the
//  real design bus_d is not independent during a read. Peripherals.sv latches
//  video_io_data from internal_data_bus while either strobe is low, and on a
//  read internal_data_bus carries what the EGA is driving back, so the card's
//  own read data returns on its bus_d input a few clocks later.
//
//  This bench models the Peripherals.sv path the EGA actually sits behind:
//
//    stage 1  video_io_address / video_io_data  (conditional latch, `clock`)
//             video_io_write_n / read_n / aen   (plain register, `clock`)
//    stage 2  *_sync1                           (clk_video)
//    stage 3  *_sync2                           (clk_video)  -> ega_top
//
//  Address, data and strobes all take the same three stages, which is what
//  makes a write land with its own data rather than the previous one. Getting
//  that wrong in a bench produces failures that look like RTL bugs.
//
//  With loop_enable = 1 the read return path is modelled, so a read qualified
//  on bus_d == bus_d_q gates itself on its own result: the strobe drops,
//  vga_dac_io drives 8'h00 (its io_data_out is combinational on those
//  strobes), that 00h comes round again, and the byte oscillates while
//  data_read_evt re-fires and walks read_component off its R/G/B phase. That
//  is what broke DAC readback - palette fades, and the write-index probe a
//  VGA-aware game uses to decide whether a DAC is there at all.
//  loop_enable = 0 models Peripherals.sv with the return path removed.
//
//  Transients are injected on the synchronised address feeding ega_top, not on
//  the CPU-side bus, because that is where the hazard arises: per-bit skew in
//  the synchronisers makes the decoders see an address that was never driven.
//
//  Limitation, stated because it matters: the real path crosses clk_video to
//  clock and back. This bench runs one clock with the same stage count, so it
//  reproduces the failure deterministically rather than probabilistically, and
//  it does not model bit-level skew on the return path itself.
//
//  Run (from the repo root):
//    iverilog -g2012 -o tb rtl/video/TESTBENCH/ega_io_qualifier_tb.v \
//      rtl/video/ega_top.v <the rest of video.qip>
//    vvp tb
//
//============================================================================

`timescale 1ns / 1ps
`default_nettype wire

module ega_io_qualifier_tb;

    // ~28.6 MHz, the ~35 ns video clock the qualifier comments refer to.
    localparam integer CLK_HALF = 17;
    // A real I/O cycle holds the bus for the best part of a microsecond.
    localparam integer CYCLE_CLKS = 20;
    // Stages between a strobe going low and ega_top seeing a settled bus.
    localparam integer PIPE_CLKS = 6;

    reg clk = 1'b0;
    reg reset = 1'b1;

    // CPU-side bus
    reg [14:0] cpu_a = 15'h0000;
    reg [7:0]  cpu_d = 8'h00;
    reg        cpu_iow_l = 1'b1;
    reg        cpu_ior_l = 1'b1;
    reg        cpu_aen = 1'b0;

    // Set to 0 to model Peripherals.sv after the capture-condition fix, i.e.
    // with the read return path removed at source.
    reg        loop_enable = 1'b1;

    // One-clock transient injected on the synchronised bus
    reg        tr_active = 1'b0;
    reg [14:0] tr_a = 15'h0000;
    reg [7:0]  tr_d = 8'h00;

    wire [7:0] bus_out;
    wire       bus_dir;
    wire       vga_mode13_active_out;
    wire       vga_planar_memory_active_out;
    wire       video_de;
    wire [5:0] video_red;
    wire [5:0] video_green;
    wire [5:0] video_blue;
    reg        vga_enabled = 1'b1;

    reg [7:0] planar_plane0 = 8'h00;
    reg [7:0] planar_plane1 = 8'h00;
    reg [7:0] planar_plane2 = 8'h00;
    reg [7:0] planar_plane3 = 8'h00;
    reg       planar_data_valid = 1'b0;

    integer pass_count = 0;
    integer fail_count = 0;

    always #CLK_HALF clk = ~clk;

    //------------------------------------------------------------------
    // Return path: ega_top -> EGA_IO_DOUT -> 2 sync -> data_bus_out
    //------------------------------------------------------------------
    reg [7:0] dout_s1 = 8'h00;
    reg [7:0] dout_s2 = 8'h00;
    reg [7:0] data_bus_out = 8'h00;

    // On a read the chipset muxes the card's own output back onto
    // internal_data_bus; on a write it carries the CPU's data.
    wire [7:0] internal_data_bus = (~cpu_ior_l & bus_dir) ? data_bus_out : cpu_d;

    //------------------------------------------------------------------
    // Peripherals.sv stage 1 (`clock` domain)
    //------------------------------------------------------------------
    reg [14:0] p_a = 15'h0000;
    reg [7:0]  p_d = 8'h00;
    reg        p_iow_l = 1'b1;
    reg        p_ior_l = 1'b1;
    reg        p_aen = 1'b0;

    //------------------------------------------------------------------
    // Peripherals.sv stages 2 and 3 (clk_video domain)
    //------------------------------------------------------------------
    reg [14:0] s1_a = 15'h0000, s2_a = 15'h0000;
    reg [7:0]  s1_d = 8'h00,    s2_d = 8'h00;
    reg        s1_iow_l = 1'b1, s2_iow_l = 1'b1;
    reg        s1_ior_l = 1'b1, s2_ior_l = 1'b1;
    reg        s1_aen = 1'b0,   s2_aen = 1'b0;

    always @(posedge clk) begin
        dout_s1      <= bus_out;
        dout_s2      <= dout_s1;
        data_bus_out <= dout_s2;

        if (~cpu_iow_l | ~cpu_ior_l)
            p_a <= cpu_a;

        if (loop_enable) begin
            // Pre-fix: latches on either strobe, so read data comes back.
            if (~cpu_iow_l | ~cpu_ior_l)
                p_d <= internal_data_bus;
        end else begin
            // Post-fix: write data only.
            if (~cpu_iow_l)
                p_d <= cpu_d;
        end

        p_iow_l <= cpu_iow_l;
        p_ior_l <= cpu_ior_l;
        p_aen   <= cpu_aen;

        s1_a <= p_a;      s2_a <= s1_a;
        s1_d <= p_d;      s2_d <= s1_d;
        s1_iow_l <= p_iow_l; s2_iow_l <= s1_iow_l;
        s1_ior_l <= p_ior_l; s2_ior_l <= s1_ior_l;
        s1_aen <= p_aen;     s2_aen <= s1_aen;
    end

    wire [14:0] dut_a = tr_active ? tr_a : s2_a;
    wire [7:0]  dut_d = tr_active ? tr_d : s2_d;

    ega_top dut (
        .clk                       (clk),
        .reset                     (reset),
        .bus_a                     (dut_a),
        .bus_ior_l                 (s2_ior_l),
        .bus_iow_l                 (s2_iow_l),
        .bus_d                     (dut_d),
        .bus_out                   (bus_out),
        .bus_dir                   (bus_dir),
        .bus_aen                   (s2_aen),
        .ega_plane0_data           (planar_plane0),
        .ega_plane1_data           (planar_plane1),
        .ega_plane2_data           (planar_plane2),
        .ega_plane3_data           (planar_plane3),
        .ega_fetch_data_valid      (planar_data_valid),
        .ega_text_char             (8'h00),
        .ega_text_attr             (8'h00),
        .ega_text_glyph            (8'h00),
        .ega_text_data_valid       (1'b0), .ega_text_tag_in(1'b0),
        .vga_framebuffer_pixel     (8'h00),
        .vga_framebuffer_data_valid(1'b0),
        .cpu_mem_select            (1'b0),
        .cpu_mem_write             (1'b0),
        .splashscreen              (1'b0), .ext_splash_pixel_index(4'd0), .ext_splash_pixel_valid(1'b0), .prebios_video(1'b0),
        .thin_font                 (1'b0),
        .scandouble_en             (1'b0),
        .ega_enabled               (1'b1),
        .ega_monitor_profile       (2'b00),
        .vga_enabled               (vga_enabled),
        .vga_mode13_native         (1'b0),
        .vga_mode13_set            (1'b0),
        .vga_mode13_clear          (1'b0),
        .vga_mode13_active_out     (vga_mode13_active_out),
        .vga_planar_memory_active_out(vga_planar_memory_active_out),
        .de_o                      (video_de),
        .ega_red                  (video_red),
        .ega_green                (video_green),
        .ega_blue                 (video_blue),
        .crt_h_offset              (4'd0),
        .crt_v_offset              (3'd0),
        .vsync_width_osd           (3'd0),
        .hsync_width_osd           (3'd0)
    );

    //------------------------------------------------------------------
    // Bus cycle helpers
    //------------------------------------------------------------------
    task automatic clks(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    // Clocks the strobe stays high between one cycle and the next. The DAC
    // edge-detects, so it needs to see the strobe deassert to count a second
    // access; a gap too short to survive the synchronisers merges two cycles
    // into one. Back-to-back `in al, dx` in the TSR's read_one_dac is about as
    // tight as this gets on real code.
    integer gap_clks = PIPE_CLKS + 2;

    // Clocks the strobe is held low, CPU side. Kept as a variable rather than
    // the fixed PIPE_CLKS + CYCLE_CLKS it defaults to, because
    // run_write_burst_sweep narrows it to find how tight a palette-block write
    // burst can get.
    integer strobe_clks = PIPE_CLKS + CYCLE_CLKS;

    task automatic io_write(input [14:0] addr, input [7:0] data);
        begin
            cpu_a = addr;
            cpu_d = data;
            cpu_iow_l = 1'b0;
            clks(strobe_clks);
            cpu_iow_l = 1'b1;
            clks(gap_clks);
        end
    endtask

    // Samples where the CPU does: at the end of the cycle, off the byte the
    // chipset has already registered.
    task automatic io_read(input [14:0] addr, output [7:0] data);
        begin
            cpu_a = addr;
            cpu_ior_l = 1'b0;
            clks(strobe_clks);
            data = data_bus_out;
            cpu_ior_l = 1'b1;
            clks(gap_clks);
        end
    endtask

    // A write during which the synchronised bus shows, for exactly one video
    // clock, an address and data that were never driven together.
    task automatic io_write_with_transient(input [14:0] addr,
                                           input [7:0]  data,
                                           input [14:0] t_addr,
                                           input [7:0]  t_data);
        begin
            cpu_a = addr;
            cpu_d = data;
            clks(2);
            cpu_iow_l = 1'b0;
            clks(PIPE_CLKS + 4);
            tr_a = t_addr;
            tr_d = t_data;
            tr_active = 1'b1;
            clks(1);
            tr_active = 1'b0;
            clks(CYCLE_CLKS);
            cpu_iow_l = 1'b1;
            clks(PIPE_CLKS);
        end
    endtask

    task automatic check8(input string name,
                          input [7:0] got, input [7:0] expected);
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("  PASS  %s (got %02h)", name, got);
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL  %s: got %02h, expected %02h",
                         name, got, expected);
            end
        end
    endtask

    task automatic check1(input string name,
                          input got, input expected);
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("  PASS  %s (got %0d)", name, got);
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL  %s: got %0d, expected %0d",
                         name, got, expected);
            end
        end
    endtask

    //------------------------------------------------------------------
    // Scenarios
    //------------------------------------------------------------------
    task automatic dac_write_entry(input [7:0] idx,
                                   input [7:0] r,
                                   input [7:0] g,
                                   input [7:0] b);
        begin
            io_write(15'h03C8, idx);
            io_write(15'h03C9, r);
            io_write(15'h03C9, g);
            io_write(15'h03C9, b);
        end
    endtask

    task automatic run_dac_tests(input string tag);
        reg [7:0] r, g, b, probe;
        begin
            // The VGA-presence probe a DAC-aware program does: write the write
            // index, read it back, believe the DAC only if it matches.
            io_write(15'h03C8, 8'h5A);
            io_read(15'h03C8, probe);
            check8({tag, "3C8 write-index readback (VGA probe)"}, probe, 8'h5A);

            // Load one entry, then read it back the way a fade does.
            dac_write_entry(8'h20, 8'h2A, 8'h15, 8'h3F);
            io_write(15'h03C7, 8'h20);
            io_read(15'h03C9, r);
            io_read(15'h03C9, g);
            io_read(15'h03C9, b);
            check8({tag, "3C9 readback red"},   r, 8'h2A);
            check8({tag, "3C9 readback green"}, g, 8'h15);
            check8({tag, "3C9 readback blue"},  b, 8'h3F);

            // The index must auto-advance exactly once per RGB triple, not
            // once per glitch on the read strobe.
            dac_write_entry(8'h21, 8'h01, 8'h02, 8'h03);
            io_write(15'h03C7, 8'h20);
            io_read(15'h03C9, r);
            io_read(15'h03C9, g);
            io_read(15'h03C9, b);
            io_read(15'h03C9, r);
            io_read(15'h03C9, g);
            io_read(15'h03C9, b);
            check8({tag, "3C9 next entry red after auto-advance"},   r, 8'h01);
            check8({tag, "3C9 next entry green after auto-advance"}, g, 8'h02);
            check8({tag, "3C9 next entry blue after auto-advance"},  b, 8'h03);

            // 3CD readback: how the TSR decides whether to claim VGA.
            io_read(15'h03CD, probe);
            check8({tag, "3CD mode13 availability readback"}, probe, 8'h13);
        end
    endtask

    // Little Game Engine's first LOADING/CARGANDO box exposes an important
    // distinction between storing a palette in system RAM and actually
    // programming the VGA DAC. Its mode-X startup clears the hardware DAC,
    // LT_Load_Font only fills LT_tileset_palette[252..255] in RAM, and the
    // first DAC upload does not happen until LT_Fade_in, after the logo has
    // finished loading and the display page has changed. Keep the core side
    // of that sequence explicit: a cleared high palette entry must stay black
    // until software writes it, and the later write must land normally.
    task automatic run_ltdemo_loading_palette_test;
        reg [7:0] r, g, b, status_probe;
        integer timeout;
        begin
            io_write(15'h03CD, 8'h13);

            // Representative of VGA_ClearPalette for the font's first DAC
            // entry. The real routine repeats this for all 256 entries.
            dac_write_entry(8'hFC, 8'h00, 8'h00, 8'h00);

            // LT_Load_Font performs no OUT to 3C8h/3C9h. Reading the entry at
            // the point where the loading box is drawn must therefore still
            // return black.
            io_write(15'h03C7, 8'hFC);
            io_read(15'h03C9, r);
            io_read(15'h03C9, g);
            io_read(15'h03C9, b);
            check8("LT demo font entry red before first fade",   r, 8'h00);
            check8("LT demo font entry green before first fade", g, 8'h00);
            check8("LT demo font entry blue before first fade",  b, 8'h00);

            // LT_Fade_in eventually uploads LT_tileset_palette. Confirm that
            // the same entry becomes visible once software really writes it.
            dac_write_entry(8'hFC, 8'h3F, 8'h2A, 8'h15);
            io_write(15'h03C7, 8'hFC);
            io_read(15'h03C9, r);
            io_read(15'h03C9, g);
            io_read(15'h03C9, b);
            check8("LT demo font entry red after first fade",   r, 8'h3F);
            check8("LT demo font entry green after first fade", g, 8'h2A);
            check8("LT demo font entry blue after first fade",  b, 8'h15);

            // Entering planar 0Dh invalidates the mode-13h DAC defaults. That
            // path consequently falls back to the normal EGA palette and is
            // not affected by the high-index mode-X font-palette problem.
            io_write(15'h03CD, 8'h0D);
            check1("LT demo mode0D invalidates DAC entry FC",
                   dut.vga_dac_io_inst.dac.entry_valid[8'hFC], 1'b0);

            // The EGA BIOS terminates a mode set by restoring Palette Address
            // Source. Reproduce that final write; an earlier transient test
            // deliberately left PAS cleared.
            io_read(15'h03DA, status_probe);
            io_write(15'h03C0, 8'h20);

            // Unlike mode X, the 16-colour route uses the ordinary attribute
            // palette. Feed a white planar pixel and prove that the private
            // 0Dh raster can display it immediately, before any VGA DAC fade.
            planar_plane0 = 8'hFF;
            planar_plane1 = 8'hFF;
            planar_plane2 = 8'hFF;
            planar_plane3 = 8'hFF;
            planar_data_valid = 1'b1;
            timeout = 0;
            while ((video_de !== 1'b1) && timeout < 1000000) begin
                clks(1);
                timeout = timeout + 1;
            end
            check1("LT demo mode0D reaches active video before a DAC fade",
                   video_de, 1'b1);
            if (video_de) begin
                // Attribute lookup and RGB conversion trail the renderer's
                // first DE edge by a couple of video clocks.
                clks(4);
                check8("LT demo mode0D initial white red",
                       {2'b00, video_red}, 8'h3F);
                check8("LT demo mode0D initial white green",
                       {2'b00, video_green}, 8'h3F);
                check8("LT demo mode0D initial white blue",
                       {2'b00, video_blue}, 8'h3F);
            end
            planar_data_valid = 1'b0;
            io_write(15'h03CD, 8'h00);
        end
    endtask

    task automatic run_transient_tests;
        reg [7:0] misc_before;
        reg [7:0] probe;
        begin
            // Misc Output must survive a one-clock 0x3C2 landing during a
            // write to the attribute controller: bit 2 is the dot clock and
            // bit 7 the palette rule, so a stray write retimes the display.
            io_write(15'h03C2, 8'h63);
            misc_before = dut.ega_misc_output_reg;
            check8("Misc Output took its setup write", misc_before, 8'h63);
            io_write_with_transient(15'h03C0, 8'h00, 15'h03C2, 8'hA5);
            check8("Misc Output ignores one-clock 3C2 transient",
                   dut.ega_misc_output_reg, misc_before);

            // A genuine write still lands.
            io_write(15'h03C2, 8'h67);
            check8("Misc Output takes a genuine write",
                   dut.ega_misc_output_reg, 8'h67);
            io_write(15'h03C2, 8'h63);

            // A transient 0x3CD carrying 0x13 must not enter mode 13h.
            check1("mode13 inactive before transient", vga_mode13_active_out, 1'b0);
            io_write_with_transient(15'h03C5, 8'h13, 15'h03CD, 8'h13);
            check1("mode13 ignores one-clock 3CD transient",
                   vga_mode13_active_out, 1'b0);

            // A genuine write to 3CD still enters, and still leaves.
            io_write(15'h03CD, 8'h13);
            check1("mode13 enters on a genuine 3CD write",
                   vga_mode13_active_out, 1'b1);
            check1("packed mode13 uses packed framebuffer memory",
                   vga_planar_memory_active_out, 1'b0);

            // Ctrl+Alt+Del clears XTEGACTL's VGA enable. The private raster
            // must then release the connector even though software did not
            // write the usual 3CD exit value.
            vga_enabled = 1'b0;
            clks(2);
            check1("disabling VGA13 releases the private raster",
                   vga_mode13_active_out, 1'b0);
            io_read(15'h03CD, probe);
            // Reconciliation PCXT-EGA / PCAT-286: with the VGA
            // extension off the port is not decoded and the bus floats high,
            // as on a real EGA, where PCXT-EGA used to answer 00h. Either
            // value is "not 13h", which is all the DOS tools test.
            check8("disabled VGA13 reports unavailable", probe, 8'hFF);
            vga_enabled = 1'b1;
            clks(2);
            io_write(15'h03CD, 8'h13);

            io_write(15'h03CD, 8'h0D);
            check1("VGA planar mode0D owns the private raster",
                   vga_mode13_active_out, 1'b1);
            check1("VGA planar mode0D keeps planar VRAM active",
                   vga_planar_memory_active_out, 1'b1);
            io_write(15'h03CD, 8'h00);
            check1("private VGA raster leaves on a genuine 3CD clear",
                   vga_mode13_active_out, 1'b0);
        end
    endtask

    // How tight can consecutive DAC accesses get before the core stops
    // counting them separately? The TSR reads a palette entry as three
    // back-to-back `in al, dx`, so this is the shape of a fade, and at the
    // fastest CPU setting the virtual 8088 runs at 25 MHz against a 35 ns
    // video clock. Informational rather than pass/fail: the answer is a
    // property of the synchronisers, and what matters is whether it leaves
    // margin over what real code produces.
    task automatic run_burst_sweep;
        reg [7:0] r, g, b;
        integer gap;
        integer narrowest_ok;
        begin
            narrowest_ok = -1;
            for (gap = 12; gap >= 1; gap = gap - 1) begin
                gap_clks = PIPE_CLKS + 2;
                dac_write_entry(8'h30, 8'h11, 8'h22, 8'h33);
                io_write(15'h03C7, 8'h30);
                gap_clks = gap;
                io_read(15'h03C9, r);
                io_read(15'h03C9, g);
                io_read(15'h03C9, b);
                gap_clks = PIPE_CLKS + 2;
                if (r === 8'h11 && g === 8'h22 && b === 8'h33) begin
                    $display("  gap %2d clk: ok    (%02h %02h %02h)", gap, r, g, b);
                    narrowest_ok = gap;
                end else begin
                    $display("  gap %2d clk: BAD   (%02h %02h %02h)", gap, r, g, b);
                end
            end
            $display("  narrowest inter-cycle gap that still reads back: %0d clk",
                     narrowest_ok);
        end
    endtask

    // Titus the Fox never reads the DAC - no AX=1015h, no AX=1017h, no 3C7h
    // anywhere in MTF.COM. It loads its palette with AX=1012h, which lands in
    // the TSR's set_dac_block: one OUT to 3C8h then a tight loop of three OUTs
    // to 3C9h per entry, up to 768 of them back to back with only a mov and an
    // inc between. So the fade is a write burst, and this sweep is the one that
    // matters for it. Writes carry the full qualifier including bus_d ==
    // bus_d_q, and consecutive entries change the data every cycle, so each
    // write spends a clock or two settling out of a budget that is only about
    // five video clocks wide at the PC/AT 3.5MHz setting.
    //
    // Readback afterwards is done at wide timing, so a failure here means the
    // write was genuinely dropped, not that the read could not keep up.
    task automatic run_write_burst_sweep;
        reg [7:0] r, g, b;
        integer w;
        integer min_ok;
        integer bad;
        begin
            min_ok = -1;
            $display("   width  palette block write, read back wide");
            for (w = 30; w >= 3; w = w - 1) begin
                // Load four consecutive entries the way set_dac_block does.
                strobe_clks = w;
                gap_clks = 3;
                io_write(15'h03C8, 8'h50);
                io_write(15'h03C9, 8'h01); io_write(15'h03C9, 8'h02); io_write(15'h03C9, 8'h03);
                io_write(15'h03C9, 8'h04); io_write(15'h03C9, 8'h05); io_write(15'h03C9, 8'h06);
                io_write(15'h03C9, 8'h07); io_write(15'h03C9, 8'h08); io_write(15'h03C9, 8'h09);
                io_write(15'h03C9, 8'h0A); io_write(15'h03C9, 8'h0B); io_write(15'h03C9, 8'h0C);

                strobe_clks = PIPE_CLKS + CYCLE_CLKS;
                gap_clks = PIPE_CLKS + 2;
                bad = 0;
                io_write(15'h03C7, 8'h50);
                io_read(15'h03C9, r); io_read(15'h03C9, g); io_read(15'h03C9, b);
                if (r !== 8'h01 || g !== 8'h02 || b !== 8'h03) bad = bad + 1;
                io_read(15'h03C9, r); io_read(15'h03C9, g); io_read(15'h03C9, b);
                if (r !== 8'h04 || g !== 8'h05 || b !== 8'h06) bad = bad + 1;
                io_read(15'h03C9, r); io_read(15'h03C9, g); io_read(15'h03C9, b);
                if (r !== 8'h07 || g !== 8'h08 || b !== 8'h09) bad = bad + 1;
                io_read(15'h03C9, r); io_read(15'h03C9, g); io_read(15'h03C9, b);
                if (r !== 8'h0A || g !== 8'h0B || b !== 8'h0C) bad = bad + 1;

                if (bad == 0) begin
                    $display("   %2d clk  ok    all 4 entries landed", w);
                    min_ok = w;
                end else begin
                    $display("   %2d clk  BAD   %0d of 4 entries wrong", w, bad);
                end
            end
            $display("   narrowest cycle that loads a palette block: %0d clk", min_ok);
        end
    endtask

    initial begin
        $display("");
        $display("ega_top I/O qualifier regression");
        $display("");

        reset = 1'b1;
        clks(8);
        reset = 1'b0;
        clks(8);

        $display("-- read path, Peripherals.sv return path modelled --");
        loop_enable = 1'b1;
        run_dac_tests("loop: ");

        $display("");
        $display("-- transient-address rejection must still hold --");
        run_transient_tests();

        $display("");
        $display("-- read path, return path removed at source --");
        loop_enable = 1'b0;
        clks(8);
        run_dac_tests("noloop: ");

        $display("");
        $display("-- how tight can back-to-back DAC reads get --");
        loop_enable = 1'b1;
        clks(8);
        run_burst_sweep();

        $display("");
        $display("-- palette block write burst, the shape of a Titus fade --");
        run_write_burst_sweep();

        $display("");
        $display("-- Little Game Engine initial loading palette sequence --");
        strobe_clks = PIPE_CLKS + CYCLE_CLKS;
        gap_clks = PIPE_CLKS + 2;
        loop_enable = 1'b0;
        run_ltdemo_loading_palette_test();

        $display("");
        $display("%0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $display("");
        $finish;
    end

endmodule
