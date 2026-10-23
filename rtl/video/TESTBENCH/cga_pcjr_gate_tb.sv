`timescale 1ns/1ps

// The IBM PCjr video gate array inside the CGA: the index/data
// flip-flop behind 3DAh (cleared by reading 3DAh), the mode decode from
// registers 0 and 3, the cadence of the CRTC (crtc_2x), the palette entries
// 10h-1Fh and the status register. Run from rtl/video so cga_pixel finds cga.hex:
//
//   iverilog -g2012 -DENABLE_TANDY_VIDEO=1 -DENABLE_PCJR=1 -o /tmp/pj.vvp \
//       TESTBENCH/cga_pcjr_gate_tb.sv cga.v UM6845R_cga.v cga_sequencer.v \
//       cga_pixel.sv cga_attrib.v cga_splash_renderer.v video_scandoubler_cga.v \
//       vram.v ../common/jtframe_dual_ram.v
module cga_pcjr_gate_tb;
    reg clk = 1'b0;
    always #17.461 clk = ~clk;

    reg  [14:0] bus_a = 15'h0;
    reg  [7:0]  bus_d = 8'h00;
    reg         bus_ior_l = 1'b1;
    reg         bus_iow_l = 1'b1;
    reg         reset = 1'b1;
    wire [7:0]  bus_out;
    wire        grph_mode, hres_mode, bw_mode, mode_640, tandy_color_16, crtc_2x, tandy_16_gfx_o;

    cga dut (
        .clk(clk), .reset(reset), .clkdiv(), .bus_a(bus_a), .bus_ior_l(bus_ior_l),
        .bus_iow_l(bus_iow_l), .bus_memr_l(1'b1), .bus_memw_l(1'b1), .bus_d(bus_d),
        .bus_out(bus_out), .bus_dir(), .bus_aen(1'b0), .bus_rdy(),
        .ram_we_l(), .ram_a(), .ram_d(8'h00),
        .hsync(), .hblank(), .raw_hblank(), .dbl_hsync(), .vsync(), .vblank(),
        .vblank_border(), .std_hsyncwidth(), .de_o(), .raw_de_o(), .video(),
        .dbl_video(), .comp_video(), .splashscreen(1'b0), .composite(1'b0),
        .thin_font(1'b0), .tandy_video(1'b1), .pcjr(1'b1), .pcjr_addr_mode(2'b00),
        .scandouble_en(1'b0), .crtc_2x(crtc_2x), .tandy_16_gfx_o(tandy_16_gfx_o),
        .grph_mode(grph_mode), .hres_mode(hres_mode), .bw_mode(bw_mode),
        .mode_640(mode_640), .composite_hsync_width(), .composite_border_color(),
        .composite_phase(), .tandy_color_16(tandy_color_16), .cga_hw(1'b1),
        .crt_h_offset(4'd0), .crt_v_offset(3'd0), .vsync_width_osd(3'd0),
        .hsync_width_osd(3'd0), .frame_stack_rebuild(1'b0)
    );

    integer errors = 0;
    integer checks = 0;

    task check(input bit ok, input string what);
        checks++;
        if (!ok) begin
            errors++;
            $display("ERROR: %s", what);
        end
    endtask

    task io_write(input [14:0] a, input [7:0] d);
        bus_a <= a; bus_d <= d;
        repeat (2) @(posedge clk);
        bus_iow_l <= 1'b0;
        repeat (10) @(posedge clk);
        bus_iow_l <= 1'b1;
        repeat (4) @(posedge clk);
    endtask

    task io_read(input [14:0] a, output [7:0] d);
        bus_a <= a;
        repeat (2) @(posedge clk);
        bus_ior_l <= 1'b0;
        repeat (10) @(posedge clk);
        d = bus_out;
        bus_ior_l <= 1'b1;
        repeat (4) @(posedge clk);
    endtask

    // A gate array register: index, then data
    task array_write(input [4:0] idx, input [7:0] d);
        logic [7:0] dummy;
        io_read(15'h3DA, dummy);
        io_write(15'h3DA, {3'b000, idx});
        io_write(15'h3DA, d);
    endtask

    logic [7:0] r0, r1, r2;

    initial begin
        repeat (64) @(posedge clk);
        reset = 1'b0;
        repeat (16) @(posedge clk);

        // Power-up: text mode, 80 column timing, display enabled, no blink
        check(grph_mode === 1'b0, "reset: text mode");
        check(crtc_2x === 1'b1, "reset: CRTC at the 80 column cadence");
        check(tandy_color_16 === 1'b0 && mode_640 === 1'b0, "reset: no graphics flags");

        // 320x200x16: register 0 = 12h (bit 1 graphics, bit 4 16 colours), 3 = 02h
        array_write(5'd0, 8'h12);
        check(grph_mode === 1'b1 && tandy_color_16 === 1'b1, "320x200x16: graphics, 16 colours");
        check(crtc_2x === 1'b0 && hres_mode === 1'b0, "320x200x16: 40 column cadence");
        check(mode_640 === 1'b0, "320x200x16: not a 640 mode");
        check(tandy_16_gfx_o === 1'b0, "320x200x16 at the slow cadence: no 16 colour tap");

        // 640x200x4 pixels at the 80 column cadence: register 0 = 13h
        array_write(5'd0, 8'h13);
        check(tandy_color_16 === 1'b1 && crtc_2x === 1'b1 && hres_mode === 1'b1, "register 0 = 13h: 160/16 colour modes");

        // 640x200x4: register 0 = 03h
        array_write(5'd0, 8'h03);
        check(grph_mode === 1'b1 && mode_640 === 1'b1 && tandy_color_16 === 1'b0, "640x200x4: graphics, 640");
        check(crtc_2x === 1'b1, "640x200x4: 80 column cadence");

        // 320x200x4: register 0 = 02h
        array_write(5'd0, 8'h02);
        check(grph_mode === 1'b1 && mode_640 === 1'b0 && tandy_color_16 === 1'b0, "320x200x4: graphics, 320");
        check(crtc_2x === 1'b0, "320x200x4: 40 column cadence");

        // 640x200x2: register 3 bit 3 plus register 0 = 02h. The CRTC stays at the
        // 40 column cadence (crtc_2x = register 0 bit 0) while hres_mode is forced
        array_write(5'd3, 8'h0A);
        check(grph_mode === 1'b1 && mode_640 === 1'b1, "640x200x2: graphics, 640");
        check(hres_mode === 1'b1, "640x200x2: hres_mode forced");
        check(crtc_2x === 1'b0, "640x200x2: CRTC cadence is the register 0 bit");
        array_write(5'd3, 8'h02);
        check(hres_mode === 1'b0, "register 3 cleared: hres follows register 0");

        // Text mode again, 40 column: register 0 = 08h
        array_write(5'd0, 8'h08);
        check(grph_mode === 1'b0 && crtc_2x === 1'b0, "text 40: not graphics, slow cadence");
        array_write(5'd0, 8'h09);
        check(grph_mode === 1'b0 && crtc_2x === 1'b1, "text 80: not graphics, fast cadence");

        // The flip-flop: an index written and not completed is overwritten after a
        // read of 3DAh (so the next write is an index again)
        io_read(15'h3DA, r0);
        io_write(15'h3DA, 8'h00);            // index 0 ...
        io_read(15'h3DA, r0);                // ... aborted by the read
        io_write(15'h3DA, 8'h03);            // index 3
        io_write(15'h3DA, 8'h02);            // data for register 3 (was 02h)
        io_write(15'h3DA, 8'h00);            // index 0
        io_write(15'h3DA, 8'h12);            // data for register 0
        check(grph_mode === 1'b1 && tandy_color_16 === 1'b1, "flip-flop: index/data pairing after 3DAh read");

        // Palette entries 10h-1Fh land in the card's palette
        array_write(5'h13, 8'h05);
        check(dut.pixel.tandy_palette[3] === 4'h5, "palette entry 13h = 5");
        array_write(5'h1F, 8'h0A);
        check(dut.pixel.tandy_palette[15] === 4'hA, "palette entry 1Fh = A");

        // Palette mask and border
        array_write(5'd1, 8'h0C);
        check(dut.pcjr_palette_mask === 4'hC, "palette mask register");
        array_write(5'd2, 8'h07);
        check(dut.pcjr_border_color === 4'h7, "border colour register");

        // Status: bits 7:5 and 2:1 read 0; bit 4 toggles with each read of 3DAh
        io_read(15'h3DA, r0);
        io_read(15'h3DA, r1);
        io_read(15'h3DA, r2);
        check((r0 & 8'hE6) == 8'h00, "status: unused bits are zero");
        check(r0[4] !== r1[4] && r1[4] !== r2[4], "status: bit 4 toggles on every read");

        // 3D8h/3D9h still reach the old CGA registers (not the PCjr mode)
        io_write(15'h3D9, 8'h2A);
        check(grph_mode === 1'b1, "3D9h write leaves the gate array mode alone");

        $display("cga_pcjr_gate_tb: %0d checks, %0d errors", checks, errors);
        if (errors != 0) $fatal(1, "FAIL");
        $finish;
    end
endmodule
