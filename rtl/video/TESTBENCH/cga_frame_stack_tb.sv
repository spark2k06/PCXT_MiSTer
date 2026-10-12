`timescale 1ns/1ps

// Exercises the CRTC Frame Stacking option with a real program: replays the
// CGA register writes of an IBM 5150 running the end credits of the Area 5150
// demo (one CRTC frame per scanline) through the complete CGA card and dumps
// the raster.  cga_frame_stack_trace.py builds the write list from
// GloriousCow's bus capture and checks the dump.  Run from rtl/video so
// cga_pixel finds cga.hex:
//
//   python3 TESTBENCH/cga_frame_stack_trace.py stim <capture.csv.gz> /tmp/lake \
//       --font cga.hex --scale 1.03 --jitter 8 --latency 40
//   iverilog -g2012 -o /tmp/lake.vvp TESTBENCH/cga_frame_stack_tb.sv cga.v \
//       UM6845R.v cga_sequencer.v cga_pixel.sv cga_attrib.v \
//       cga_splash_renderer.v video_scandoubler.v vram.v \
//       ../common/jtframe_dual_ram.v
//   vvp /tmp/lake.vvp +stim=/tmp/lake.stim +vram=/tmp/lake.vram.hex \
//       +dump=/tmp/lake.dump +rebuild=1
//   python3 TESTBENCH/cga_frame_stack_trace.py check /tmp/lake.dump \
//       /tmp/lake.expected --png 8 --require 3
//
// Dump format: "F" starts a frame (VSYNC rising edge); every other line is
// one scanline from an HSYNC (or VSYNC) rising edge to the next: "V" or "A"
// for vertical blanking, then one hex RGBI digit per 14.318 MHz pixel.
module cga_frame_stack_tb;
    reg clk = 1'b0;
    always #17.461 clk = ~clk;  // 28.636 MHz

    reg  [14:0] bus_a = 15'h0;
    reg  [7:0]  bus_d = 8'h00;
    reg         bus_iow_l = 1'b1;
    reg         rebuild = 1'b0;
    reg         reset = 1'b1;

    wire [4:0]  clkdiv;
    wire        ram_en;
    wire [18:0] ram_a;
    wire [7:0]  ram_d;
    wire        hsync, vsync, vblank, raw_hblank;
    wire [3:0]  video;

    cga dut (
        .clk(clk),
        .reset(reset),
        .clkdiv(clkdiv),
        .bus_a(bus_a),
        .bus_ior_l(1'b1),
        .bus_iow_l(bus_iow_l),
        .bus_memr_l(1'b0),
        .bus_memw_l(1'b0),
        .bus_d(bus_d),
        .bus_out(),
        .bus_dir(),
        .bus_aen(1'b0),
        .bus_rdy(),
        .ram_we_l(ram_en),
        .ram_a(ram_a),
        .ram_d(ram_d),
        .hsync(hsync),
        .hblank(),
        .raw_hblank(raw_hblank),
        .dbl_hsync(),
        .vsync(vsync),
        .vblank(vblank),
        .vblank_border(),
        .std_hsyncwidth(),
        .de_o(),
        .raw_de_o(),
        .video(video),
        .dbl_video(),
        .comp_video(),
        .splashscreen(1'b0),
        .composite(1'b0),
        .thin_font(1'b0),
        .tandy_video(1'b0),
        .scandouble_en(1'b0),
        .grph_mode(),
        .hres_mode(),
        .bw_mode(),
        .mode_640(),
        .composite_hsync_width(),
        .composite_border_color(),
        .composite_phase(),
        .tandy_color_16(),
        .cga_hw(1'b1),
        .crt_h_offset(4'd0),
        .crt_v_offset(3'd0),
        .vsync_width_osd(3'd0),
        .hsync_width_osd(3'd0),
        .frame_stack_rebuild(rebuild)
    );
    defparam dut.BLINK_MAX = 24'd4772727;

    vram #(.AW(14)) vr (
        .clka(clk), .ena(1'b0), .wea(1'b0), .addra(14'd0), .dina(8'd0), .douta(),
        .clkb(clk), .enb(ram_en), .web(1'b0), .addrb(ram_a[13:0]), .dinb(8'd0),
        .doutb(ram_d)
    );

    // ------------------------------------------------------------------
    // Register writes, one bus cycle each (3 CPU cycles of IOW).
    reg [63:0] tick = 64'd0;
    always @(posedge clk) tick <= tick + 64'd1;

    string  stim_name, vram_name, dump_name;
    integer stim, dump, rc, rebuild_arg;
    reg [63:0] t_next;
    reg [11:0] port;
    reg [7:0]  data;
    reg        done = 1'b0;

    initial begin
        if (!$value$plusargs("stim=%s", stim_name)) $fatal(1, "+stim= missing");
        if (!$value$plusargs("vram=%s", vram_name)) $fatal(1, "+vram= missing");
        if (!$value$plusargs("dump=%s", dump_name)) $fatal(1, "+dump= missing");
        if ($value$plusargs("rebuild=%d", rebuild_arg)) rebuild = (rebuild_arg != 0);
        $readmemh(vram_name, vr.vram, 0, 16383);
        stim = $fopen(stim_name, "r");
        dump = $fopen(dump_name, "w");
        repeat (64) @(posedge clk);
        reset = 1'b0;
        rc = 3;
        while (!$feof(stim) && rc == 3) begin
            rc = $fscanf(stim, "%d %h %h\n", t_next, port, data);
            while (rc == 3 && tick < t_next) @(posedge clk);
            if (rc == 3 && port != 12'h000) begin
                bus_a <= {3'b000, port};
                bus_d <= data;
                bus_iow_l <= 1'b0;
                repeat (18) @(posedge clk);
                bus_iow_l <= 1'b1;
                repeat (2) @(posedge clk);
            end
        end
        done = 1'b1;
        $fclose(dump);
        $display("stimulus finished at tick %0d", tick);
        $finish;
    end

    // ------------------------------------------------------------------
    // Raster dump at the native pixel rate.
    reg hs_d = 1'b0, vs_d = 1'b0;
    always @(posedge clk) begin
        if (!done && !reset && clkdiv[0]) begin
            hs_d <= hsync;
            vs_d <= dut.vsync_l;  // active-high CRTC VSYNC
            if (dut.vsync_l && !vs_d)
                $fwrite(dump, "\nF\n%s", vblank ? "V" : "A");
            else if (hsync && !hs_d)
                $fwrite(dump, "\n%s", vblank ? "V" : "A");
            $fwrite(dump, "%h", video);
        end
    end
endmodule
