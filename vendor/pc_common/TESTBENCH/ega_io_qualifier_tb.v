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
//  on bus_d == bus_d_q gates itself on its own result: the strobe drops, the
//  card drives a different byte (its read data is combinational on those
//  strobes), that byte comes round again, and the value oscillates. The CRTC
//  data port (3D5h, registers 0Ch-11h) is the readback the EGA has to keep
//  right through it; it is what the cursor and start-address probes of DOS
//  programs read.
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
//    iverilog -g2012 -o tb TESTBENCH/ega_io_qualifier_tb.v \
//      rtl/ega/ega_top.v <the rest of pc_common.qip>
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
    wire       video_de;
    wire [5:0] video_red;
    wire [5:0] video_green;
    wire [5:0] video_blue;

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
        .cpu_mem_select            (1'b0),
        .cpu_mem_write             (1'b0),
        .splashscreen              (1'b0), .ext_splash_pixel_index(4'd0), .ext_splash_pixel_valid(1'b0), .prebios_video(1'b0),
        .thin_font                 (1'b0),
        .scandouble_en             (1'b0),
        .ega_enabled               (1'b1),
        .ega_monitor_profile       (2'b00),
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

    // Clocks the strobe stays high between one cycle and the next. A gap too
    // short to survive the synchronisers merges two cycles into one.
    integer gap_clks = PIPE_CLKS + 2;

    // Clocks the strobe is held low, CPU side.
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
    // CRTC registers 0Ch-11h read back through 3D5h. Written with the index
    // at 3D4h, read back the way a program reads the cursor position or the
    // start address.
    task automatic run_crtc_readback_tests(input string tag);
        reg [7:0] v;
        begin
            io_write(15'h03D4, 8'h0E);
            io_write(15'h03D5, 8'h5A);
            io_write(15'h03D4, 8'h0F);
            io_write(15'h03D5, 8'hC3);

            io_write(15'h03D4, 8'h0E);
            io_read(15'h03D5, v);
            // R14 is six bits wide: bits 7:6 read back as zero
            check8({tag, "3D5 cursor location high readback"}, v, 8'h1A);
            io_write(15'h03D4, 8'h0F);
            io_read(15'h03D5, v);
            check8({tag, "3D5 cursor location low readback"}, v, 8'hC3);

            io_write(15'h03D4, 8'h0C);
            io_write(15'h03D5, 8'h12);
            io_write(15'h03D4, 8'h0D);
            io_write(15'h03D5, 8'h34);
            io_write(15'h03D4, 8'h0C);
            io_read(15'h03D5, v);
            check8({tag, "3D5 start address high readback"}, v, 8'h12);
            io_write(15'h03D4, 8'h0D);
            io_read(15'h03D5, v);
            check8({tag, "3D5 start address low readback"}, v, 8'h34);

            // Registers 00h-0Bh are write-only on the EGA: nothing drives the
            // bus, which floats high.
            io_write(15'h03D4, 8'h00);
            io_read(15'h03D5, v);
            check8({tag, "3D5 write-only register floats high"}, v, 8'hFF);
        end
    endtask

    task automatic run_transient_tests;
        reg [7:0] misc_before;
        reg [7:0] v;
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

            // A transient 3D5h write must not reach the CRTC register the
            // index points at.
            io_write(15'h03D4, 8'h0E);
            io_write(15'h03D5, 8'h11);
            io_write_with_transient(15'h03C0, 8'h00, 15'h03D5, 8'hEE);
            io_read(15'h03D5, v);
            check8("CRTC data ignores one-clock 3D5 transient", v, 8'h11);

            // A genuine write still lands.
            io_write(15'h03D5, 8'h22);
            io_read(15'h03D5, v);
            check8("CRTC data takes a genuine write", v, 8'h22);
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
        run_crtc_readback_tests("loop: ");

        $display("");
        $display("-- transient-address rejection must still hold --");
        run_transient_tests();

        $display("");
        $display("-- read path, return path removed at source --");
        loop_enable = 1'b0;
        clks(8);
        run_crtc_readback_tests("noloop: ");

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
