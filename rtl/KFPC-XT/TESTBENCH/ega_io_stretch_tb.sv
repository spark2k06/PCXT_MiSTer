//============================================================================
//
//  The video I/O write crossing at the PC/AT 3.5MHz speed setting.
//
//  The video card receives the I/O bus through per-bit two-stage
//  synchronisers plus a two-identical-samples qualifier in ega_top, with no
//  handshake. A write therefore lands only if the IOW pulse overlaps the
//  video clock long enough - about 6-7 video clocks in the worst case phase,
//  210-245 ns. At the 3.5MHz setting the pulse is ~10 chipset clocks, 200 ns:
//  right on the edge, so writes are kept or lost by the momentary phase
//  between two free-running clocks. The writes software issues most are CRTC
//  index/data pairs, and a lost index desynchronises everything after it.
//
//  Two identical stimulus streams drive two ega_top instances: one through a
//  replica of the bare crossing Peripherals.sv used to have, one through
//  ega_io_stretch. Several hundred CRTC start-address pairs are written at
//  realistic widths while the incommensurate clocks sweep every phase, and
//  the registers are read back hierarchically after each pair. The bare
//  path is expected to drop pairs at the tight widths (its count is
//  reported); the stretched path must never drop any.
//
//============================================================================

`timescale 1ns/1ps

module ega_io_stretch_tb;

    // 50 MHz chipset clock, 28.636 MHz video clock. The periods are
    // incommensurate, so several hundred writes sweep every phase alignment.
    reg clk50 = 1'b0;
    always #10.000 clk50 = ~clk50;
    reg clkv = 1'b0;
    always #17.462 clkv = ~clkv;

    reg reset = 1'b1;

    integer errors_bare = 0;
    integer errors_stretch = 0;
    integer checks = 0;
    integer errors_bare_width;
    integer errors_stretch_width;

    // ------------------------------------------------------------- chain A --
    // Replica of the live-copy crossing Peripherals.sv used to implement.
    reg  [14:0] a_addr = 15'h0000;
    reg  [7:0]  a_data = 8'h00;
    reg         a_iow_n = 1'b1;
    reg         a_ior_n = 1'b1;

    reg  [14:0] a_io_address = 15'd0;
    reg  [7:0]  a_io_data = 8'd0;
    reg         a_io_write_n = 1'b1;
    reg         a_io_read_n = 1'b1;

    always @(posedge clk50) begin
        if (~a_iow_n | ~a_ior_n)
            a_io_address <= a_addr;
        if (~a_iow_n)
            a_io_data <= a_data;
        a_io_write_n <= a_iow_n;
        a_io_read_n  <= a_ior_n;
    end

    // ------------------------------------------------------------- chain B --
    reg  [14:0] b_addr = 15'h0000;
    reg  [7:0]  b_data = 8'h00;
    reg         b_iow_n = 1'b1;
    reg         b_ior_n = 1'b1;

    wire [14:0] b_io_address;
    wire [7:0]  b_io_data;
    wire        b_io_write_n;
    wire        b_io_read_n;
    wire        b_io_aen_n;
    wire        b_access_ready;

    ega_io_stretch u_stretch (
        .clock                  (clk50),
        .reset                  (reset),
        .io_write_n             (b_iow_n),
        .io_read_n              (b_ior_n),
        .address_enable_n       (1'b0),
        .address                (b_addr),
        .write_data             (b_data),
        .video_address          (b_io_address),
        .video_data             (b_io_data),
        .video_io_write_n       (b_io_write_n),
        .video_io_read_n        (b_io_read_n),
        .video_address_enable_n (b_io_aen_n),
        .access_ready           (b_access_ready)
    );

    // ------------------------------------- video-domain synchronisers, both --
    reg [14:0] a_sync1_addr, a_sync2_addr, b_sync1_addr, b_sync2_addr;
    reg [7:0]  a_sync1_data, a_sync2_data, b_sync1_data, b_sync2_data;
    reg        a_sync1_iow, a_sync2_iow, b_sync1_iow, b_sync2_iow;
    reg        a_sync1_ior, a_sync2_ior, b_sync1_ior, b_sync2_ior;
    reg        b_sync1_aen, b_sync2_aen;

    always @(posedge clkv or posedge reset) begin
        if (reset) begin
            {a_sync1_addr, a_sync2_addr, b_sync1_addr, b_sync2_addr} <= 60'd0;
            {a_sync1_data, a_sync2_data, b_sync1_data, b_sync2_data} <= 32'd0;
            {a_sync1_iow, a_sync2_iow, b_sync1_iow, b_sync2_iow} <= 4'b1111;
            {a_sync1_ior, a_sync2_ior, b_sync1_ior, b_sync2_ior} <= 4'b1111;
            {b_sync1_aen, b_sync2_aen} <= 2'b00;
        end else begin
            a_sync1_addr <= a_io_address;  a_sync2_addr <= a_sync1_addr;
            a_sync1_data <= a_io_data;     a_sync2_data <= a_sync1_data;
            a_sync1_iow  <= a_io_write_n;  a_sync2_iow  <= a_sync1_iow;
            a_sync1_ior  <= a_io_read_n;   a_sync2_ior  <= a_sync1_ior;
            b_sync1_addr <= b_io_address;  b_sync2_addr <= b_sync1_addr;
            b_sync1_data <= b_io_data;     b_sync2_data <= b_sync1_data;
            b_sync1_iow  <= b_io_write_n;  b_sync2_iow  <= b_sync1_iow;
            b_sync1_ior  <= b_io_read_n;   b_sync2_ior  <= b_sync1_ior;
            b_sync1_aen  <= b_io_aen_n;    b_sync2_aen  <= b_sync1_aen;
        end
    end

    // ------------------------------------------------------------ two DUTs --
    wire [7:0] unused_bus_out_a, unused_bus_out_b;

    `define EGA_TIE_OFF \
        .ega_plane0_data(8'h00), .ega_plane1_data(8'h00), \
        .ega_plane2_data(8'h00), .ega_plane3_data(8'h00), \
        .ega_fetch_data_valid(1'b0), \
        .ega_text_char(8'h00), .ega_text_attr(8'h00), .ega_text_glyph(8'h00), \
        .ega_text_data_valid(1'b0), .ega_text_tag_in(1'b0),         .ext_splash_pixel_index(4'd0), .ext_splash_pixel_valid(1'b0), .prebios_video(1'b0), \
        .cpu_mem_select(1'b0), .cpu_mem_write(1'b0), \
        .splashscreen(1'b0), .thin_font(1'b0), .scandouble_en(1'b0), \
        .ega_enabled(1'b1), .ega_monitor_profile(2'b00), \
        .crt_h_offset(4'd0), .crt_v_offset(3'd0), \
        .vsync_width_osd(3'd0), .hsync_width_osd(3'd0)

    ega_top dutA (
        .clk(clkv), .reset(reset),
        .bus_a(a_sync2_addr), .bus_ior_l(a_sync2_ior), .bus_iow_l(a_sync2_iow),
        .bus_d(a_sync2_data), .bus_out(unused_bus_out_a), .bus_aen(1'b0),
        `EGA_TIE_OFF
    );

    ega_top dutB (
        .clk(clkv), .reset(reset),
        .bus_a(b_sync2_addr), .bus_ior_l(b_sync2_ior), .bus_iow_l(b_sync2_iow),
        .bus_d(b_sync2_data), .bus_out(unused_bus_out_b), .bus_aen(b_sync2_aen),
        `EGA_TIE_OFF
    );

    // ------------------------------------------------------------ stimulus --
    // One I/O write the way the 8088 presents it: address a little ahead of
    // the strobe, data under it, both released after it. Chain A has no ready
    // to honour; chain B extends the strobe while access_ready is low, which
    // is what the READY wait-state path does to the real CPU.
    task write_a(input [14:0] port, input [7:0] value, input integer width);
        integer k;
        begin
            @(posedge clk50);
            a_addr <= port; a_ior_n <= 1'b1;
            repeat (2) @(posedge clk50);
            a_data <= value; a_iow_n <= 1'b0;
            for (k = 0; k < width; k = k + 1) @(posedge clk50);
            a_iow_n <= 1'b1;
            @(posedge clk50);
            a_addr <= 15'h1234;   // instruction fetches reclaim the bus
        end
    endtask

    task write_b(input [14:0] port, input [7:0] value, input integer width);
        integer k;
        begin
            @(posedge clk50);
            b_addr <= port; b_ior_n <= 1'b1;
            repeat (2) @(posedge clk50);
            b_data <= value; b_iow_n <= 1'b0;
            for (k = 0; k < width; k = k + 1) @(posedge clk50);
            while (!b_access_ready) @(posedge clk50);
            @(posedge clk50);
            b_iow_n <= 1'b1;
            @(posedge clk50);
            b_addr <= 15'h1234;
        end
    endtask

    // An I/O read, for the status-read flip-flop reset the attribute pairs
    // need. Chain B honours access_ready the way the CPU's wait states would.
    task read_a(input [14:0] port, input integer width);
        integer k;
        begin
            @(posedge clk50);
            a_addr <= port; a_iow_n <= 1'b1;
            repeat (2) @(posedge clk50);
            a_ior_n <= 1'b0;
            for (k = 0; k < width; k = k + 1) @(posedge clk50);
            a_ior_n <= 1'b1;
            @(posedge clk50);
            a_addr <= 15'h1234;
        end
    endtask

    task read_b(input [14:0] port, input integer width);
        integer k;
        begin
            @(posedge clk50);
            b_addr <= port; b_iow_n <= 1'b1;
            repeat (2) @(posedge clk50);
            b_ior_n <= 1'b0;
            for (k = 0; k < width; k = k + 1) @(posedge clk50);
            while (!b_access_ready) @(posedge clk50);
            @(posedge clk50);
            b_ior_n <= 1'b1;
            @(posedge clk50);
            b_addr <= 15'h1234;
        end
    endtask

    integer i, w;
    integer gap;
    reg [7:0] v12, v13;

    task run_pairs(input integer count, input integer width, input integer gap_in);
        begin
            gap = gap_in;
            errors_bare_width = 0;
            errors_stretch_width = 0;
            for (i = 0; i < count; i = i + 1) begin
                v12 = i[7:0] ^ 8'h5A;
                v13 = (i[7:0] + 8'd77) ^ 8'hA5;

                // the pair back to back, the way OUT/INC DX/OUT issues them
                write_a(15'h03D4, 8'h0C, width);
                repeat (gap) @(posedge clk50);
                write_a(15'h03D5, v12, width);
                repeat (gap) @(posedge clk50);
                write_a(15'h03D4, 8'h0D, width);
                repeat (gap) @(posedge clk50);
                write_a(15'h03D5, v13, width);

                write_b(15'h03D4, 8'h0C, width);
                repeat (gap) @(posedge clk50);
                write_b(15'h03D5, v12, width);
                repeat (gap) @(posedge clk50);
                write_b(15'h03D4, 8'h0D, width);
                repeat (gap) @(posedge clk50);
                write_b(15'h03D5, v13, width);

                // let the crossings drain
                repeat (30) @(posedge clkv);

                checks = checks + 1;
                if ((dutA.ega_crtc.R12_start_addr_h !== v12) ||
                    (dutA.ega_crtc.R13_start_addr_l !== v13))
                    errors_bare_width = errors_bare_width + 1;
                if ((dutB.ega_crtc.R12_start_addr_h !== v12) ||
                    (dutB.ega_crtc.R13_start_addr_l !== v13)) begin
                    errors_stretch_width = errors_stretch_width + 1;
                    $display("FAIL stretch width=%0d pair %0d: R12=%02X R13=%02X expected %02X %02X",
                             width, i, dutB.ega_crtc.R12_start_addr_h,
                             dutB.ega_crtc.R13_start_addr_l, v12, v13);
                end
            end
            $display("width %2d gap %2d chipset clocks: bare path lost %0d of %0d pairs, stretched path lost %0d",
                     width, gap_in, errors_bare_width, count, errors_stretch_width);
            errors_bare = errors_bare + errors_bare_width;
            errors_stretch = errors_stretch + errors_stretch_width;
        end
    endtask

    // Attribute controller pairs: index and data both go to 3C0h, so the only
    // thing separating the two writes on the far side is the strobe gap. That
    // is the vulnerable pattern - a marginal synchroniser resolution on real
    // silicon can eat one sample of an 80 ns gap, which an ideal simulation
    // never shows; driving the gap below one video clock here models exactly
    // that. A swallowed gap merges the pair, the data write is lost, and the
    // address/data flip-flop is left pointing the wrong way for every
    // attribute write that follows.
    task run_attr_pairs(input integer count, input integer width, input integer gap_in);
        begin
            errors_bare_width = 0;
            errors_stretch_width = 0;
            for (i = 0; i < count; i = i + 1) begin
                v12 = {4'h0, i[3:0] ^ 4'h5};

                read_a(15'h03DA, 6);
                repeat (4) @(posedge clk50);
                write_a(15'h03C0, 8'h33, width);        // index 13h, PAS set
                repeat (gap_in) @(posedge clk50);
                write_a(15'h03C0, v12, width);          // Pel Panning value

                read_b(15'h03DA, 6);
                repeat (4) @(posedge clk50);
                write_b(15'h03C0, 8'h33, width);
                repeat (gap_in) @(posedge clk50);
                write_b(15'h03C0, v12, width);

                repeat (30) @(posedge clkv);

                checks = checks + 1;
                if (dutA.ega_attr.pixel_panning_reg !== v12)
                    errors_bare_width = errors_bare_width + 1;
                if (dutB.ega_attr.pixel_panning_reg !== v12) begin
                    errors_stretch_width = errors_stretch_width + 1;
                    $display("FAIL stretch attr width=%0d gap=%0d pair %0d: panning=%02X expected %02X",
                             width, gap_in, i, dutB.ega_attr.pixel_panning_reg, v12);
                end
            end
            $display("attr  %2d gap %2d chipset clocks: bare path lost %0d of %0d pairs, stretched path lost %0d",
                     width, gap_in, errors_bare_width, count, errors_stretch_width);
            errors_bare = errors_bare + errors_bare_width;
            errors_stretch = errors_stretch + errors_stretch_width;
        end
    endtask

    initial begin
        repeat (10) @(posedge clk50);
        reset <= 1'b0;
        repeat (20) @(posedge clk50);

        // 10-12 clocks is the pulse when the io_settle waits land in time;
        // 4-6 clocks, one to three T-states, is the pulse when the wait
        // arrives after the CPU has already left T3 - the arm-latency case
        // measured on the memory side of the same ready path.
        run_pairs(100, 12, 8);
        run_pairs(100, 10, 8);
        run_pairs(100, 8, 8);
        run_pairs(100, 6, 8);
        run_pairs(100, 4, 6);
        run_pairs(100, 4, 4);
        // one lost boundary sample at each edge of a real 4-clock pulse
        run_pairs(100, 3, 8);
        run_pairs(100, 2, 8);

        // same-port pairs: the strobe gap is the only separator, and a gap
        // under one video clock is a real 80 ns gap after one marginal sample
        run_attr_pairs(100, 6, 4);
        run_attr_pairs(100, 6, 2);
        run_attr_pairs(100, 6, 1);
        run_attr_pairs(100, 4, 1);

        $display("");
        $display("%0d pairs checked: bare path lost %0d, stretched path lost %0d",
                 checks, errors_bare, errors_stretch);
        if (errors_bare == 0)
            $display("NOTE: the bare path lost nothing at these widths; the margin argument is unproven in this run");
        $display("RESULT: %0s", (errors_stretch == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        #6_000_000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

endmodule
