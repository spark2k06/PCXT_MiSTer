`timescale 1ns/1ps

// Integrated diagnostic bench for the native CGA composite path.
//
// It drives the real CRTC, sequencer and pixel pipeline with a deterministic
// text stream, then decodes the same stream twice:
//   - raw_hblank: the timing currently used by production;
//   - pixel_hblank: blanking aligned to cga_pixel's delayed active signal.
//
// The two RGB streams are intentionally kept side by side.  This bench is
// diagnostic only; it does not change the production hierarchy.
module cga_crtc_composite_tb #(
    parameter integer DECODE_OFFSET = 0
);
    reg clk = 1'b0;
    always #5 clk = ~clk;

    wire [4:0] clkdiv;
    wire vram_read;
    wire vram_read_a0;
    wire vram_read_char;
    wire vram_read_att;
    wire crtc_clk;
    wire charrom_read;
    wire disp_pipeline;
    wire isa_op_enable;
    wire hclk;
    wire lclk;

    wire raw_hblank;
    wire vblank;
    wire line_reset;
    wire vsync;
    wire hsync;
    wire display_enable;
    wire cursor;
    wire [13:0] ma;
    wire [4:0] row_addr;
    wire [3:0] hsync_width;
    wire composite_phase;

    reg nreset = 1'b0;
    reg ncs = 1'b1;
    reg rnw = 1'b1;
    reg rs = 1'b0;
    reg [7:0] di = 8'h00;

    wire hres_mode = 1'b1;
    wire grph_mode = 1'b0;
    wire bw_mode = 1'b0;
    wire mode_640 = 1'b0;
    wire tandy_16_mode = 1'b0;
    wire thin_font = 1'b0;
    wire blink_enabled = 1'b0;
    wire blink = 1'b0;
    wire video_enabled = 1'b1;
    wire [7:0] cga_color_reg = 8'h00;
    wire [3:0] tandy_palette_color = 4'h0;
    wire [3:0] tandy_newcolor = 4'h0;
    wire tandy_palette_set = 1'b0;
    wire [3:0] tandy_bordercol = 4'h0;
    wire tandy_color_4 = 1'b0;
    wire tandy_color_16 = 1'b0;

    // Use the same family of magic glyphs as the 1K-colour part of 8088MPH.
    // The character group follows the CRTC memory address and the attribute
    // changes inside each group, which creates transitions at the actual
    // pixel-pipeline timing rather than in an external synthetic stream.
    wire [7:0] test_char = (ma[7:6] == 2'd0) ? 8'h55 :
                           (ma[7:6] == 2'd1) ? 8'h13 :
                           (ma[7:6] == 2'd2) ? 8'hb0 : 8'hb1;
    wire [3:0] test_attr = {1'b0, ma[5:2]};
    wire [7:0] vram_data = vram_read_char ? test_char :
                           vram_read_att  ? {4'h0, test_attr} : 8'h00;
    wire [3:0] video;

    cga_sequencer sequencer (
        .clk(clk),
        .reset(1'b0),
        .clk_seq(clkdiv),
        .vram_read(vram_read),
        .vram_read_a0(vram_read_a0),
        .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att),
        .hres_mode(hres_mode),
        .crtc_clk(crtc_clk),
        .charrom_read(charrom_read),
        .disp_pipeline(disp_pipeline),
        .isa_op_enable(isa_op_enable),
        .hclk(hclk),
        .lclk(lclk),
        .tandy_16_gfx(1'b0),
        .tandy_color_16(tandy_color_16)
    );

    UM6845R #(
        .H_TOTAL(8'd113),
        .H_DISP(8'd80),
        .H_SYNCPOS(8'd90),
        .H_SYNCWIDTH(4'd10),
        .V_TOTAL(7'd31),
        .V_TOTALADJ(5'd6),
        .V_DISP(7'd25),
        .V_SYNCPOS(7'd28),
        .V_MAXSCAN(5'd7),
        .C_START(7'd6),
        .C_END(7'd7)
    ) crtc (
        .CLOCK(clk),
        .CLKEN(crtc_clk),
        .nCLKEN(1'b1),
        .nRESET(nreset),
        .CRTC_TYPE(1'b1),
        .ENABLE(1'b1),
        .nCS(ncs),
        .R_nW(rnw),
        .RS(rs),
        .DI(di),
        .DO(),
        .hblank(raw_hblank),
        .vblank(vblank),
        .line_reset(line_reset),
        .VSYNC(vsync),
        .HSYNC(hsync),
        .DE(display_enable),
        .FIELD(),
        .CURSOR(cursor),
        .MA(ma),
        .RA(row_addr),
        .hsync_width(hsync_width),
        .composite_phase(composite_phase),
        .crt_h_offset(4'd0),
        .crt_v_offset(3'd0),
        .vsync_width_osd(3'd0),
        .hsync_width_osd(3'd0),
        .hres_mode(hres_mode)
    );

    cga_pixel pixel (
        .clk(clk),
        .clk_seq(clkdiv),
        .hres_mode(hres_mode),
        .grph_mode(grph_mode),
        .bw_mode(bw_mode),
        .mode_640(mode_640),
        .tandy_16_mode(tandy_16_mode),
        .thin_font(thin_font),
        .vram_data(vram_data),
        .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att),
        .disp_pipeline(disp_pipeline),
        .charrom_read(charrom_read),
        .display_enable(display_enable),
        .cursor(cursor),
        .row_addr(row_addr),
        .blink_enabled(blink_enabled),
        .blink(blink),
        .hsync(hsync),
        .vsync(vsync),
        .video_enabled(video_enabled),
        .cga_color_reg(cga_color_reg),
        .tandy_palette_color(tandy_palette_color),
        .tandy_newcolor(tandy_newcolor),
        .tandy_palette_set(tandy_palette_set),
        .tandy_bordercol(tandy_bordercol),
        .tandy_color_4(tandy_color_4),
        .tandy_color_16(tandy_color_16),
        .video(video)
    );

    // cga_pixel delays display_enable internally so that attributes and
    // glyph data line up.  This is the active interval that corresponds to
    // the video nibble presented to the composite decoder.
    wire pixel_hblank = ~pixel.display_enable_del[0];

    wire [5:0] raw_red, raw_green, raw_blue;
    wire [5:0] pixel_red, pixel_green, pixel_blue;
    cga_vgaport #(.PHASE_OFFSET(DECODE_OFFSET)) raw_decoder (
        .clk(clk),
        .clkdiv(clkdiv),
        .video(video),
        .composite(1'b1),
        .hblank(raw_hblank),
        .bw_mode(bw_mode),
        .hres_mode(hres_mode),
        .grph_mode(grph_mode),
        .hsync_width(4'd14), // calibration setting [E,1]
        .border_color(4'h0),
        .phase(composite_phase),
        .scandouble(1'b0),
        .red(raw_red),
        .green(raw_green),
        .blue(raw_blue)
    );

    cga_vgaport #(.PHASE_OFFSET(DECODE_OFFSET)) pixel_decoder (
        .clk(clk),
        .clkdiv(clkdiv),
        .video(video),
        .composite(1'b1),
        .hblank(pixel_hblank),
        .bw_mode(bw_mode),
        .hres_mode(hres_mode),
        .grph_mode(grph_mode),
        .hsync_width(4'd14), // calibration setting [E,1]
        .border_color(4'h0),
        .phase(composite_phase),
        .scandouble(1'b0),
        .red(pixel_red),
        .green(pixel_green),
        .blue(pixel_blue)
    );

    task automatic crtc_write;
        input [4:0] address;
        input [7:0] value;
        begin
            @(negedge clk);
            ncs = 1'b0; rnw = 1'b0; rs = 1'b0; di = {3'b000, address};
            @(posedge clk);
            @(negedge clk);
            rs = 1'b1; di = value;
            @(posedge clk);
            @(negedge clk);
            ncs = 1'b1; rnw = 1'b1; rs = 1'b0; di = 8'h00;
        end
    endtask

    integer fd;
    integer sample_count;
    reg old_raw_hblank;
    reg old_pixel_hblank;
    reg old_phase;

    always @(posedge clk) begin
        if (nreset && (clkdiv[0] == 1'b1)) begin
            if (raw_hblank != old_raw_hblank ||
                pixel_hblank != old_pixel_hblank ||
                composite_phase != old_phase ||
                ((sample_count % 16) == 0)) begin
                $fwrite(fd,
                    "%0t,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                    $time, sample_count, raw_hblank, pixel_hblank,
                    composite_phase, video,
                    raw_red, raw_green, raw_blue,
                    pixel_red, pixel_green, pixel_blue, ma);
            end
            old_raw_hblank <= raw_hblank;
            old_pixel_hblank <= pixel_hblank;
            old_phase <= composite_phase;
            sample_count <= sample_count + 1;
        end
    end

    initial begin
        fd = $fopen("cga_crtc_composite.csv", "w");
        $fwrite(fd, "time,sample,raw_hblank,pixel_hblank,phase,video,raw_r,raw_g,raw_b,pixel_r,pixel_g,pixel_b,ma\n");
        sample_count = 0;
        old_raw_hblank = 1'b1;
        old_pixel_hblank = 1'b1;
        old_phase = 1'b0;

        // UM6845R is a CRTC1 model and its address pointer is deliberately
        // not reset by the production implementation.  Seed both the saved
        // and current pointers while the bench is being configured; without
        // this, the VRAM data path is X and the composite comparison silently
        // degenerates into an all-zero trace.
        force crtc.row_addr = 14'd0;
        force crtc.row_addr_r = 14'd0;

        repeat (4) @(posedge clk);
        nreset = 1'b1;

        // The calibration program uses a short vertical frame while it
        // changes horizontal timing.  Keep the bench horizontal-only.
        crtc_write(5'd4, 8'h01);
        crtc_write(5'd6, 8'h01);
        crtc_write(5'd9, 8'h00);
        crtc_write(5'd7, 8'h02);
        crtc_write(5'd3, 8'h0e); // E,0 before the phase flip
        release crtc.row_addr;
        release crtc.row_addr_r;
        force crtc.vde = 1'b1;
        force crtc.vde_r = 1'b1;

        // The source ROM is normally found relative to rtl/video when the
        // core is simulated from that directory.  Reload it explicitly so
        // this bench is also valid from the repository root.
        #1 $readmemh("rtl/video/cga.hex", pixel.char_rom, 0, 4095);

        // Allow the filter and the CRTC to reach steady state before the
        // first captured line.
        repeat (12000) @(posedge clk);

        // Exact phase transition used by 8088MPH: R0 71 -> 72.  The CRTC
        // latches composite_phase on this write.
        crtc_write(5'd0, 8'h72);
        repeat (9000) @(posedge clk);

        release crtc.vde;
        release crtc.vde_r;
        $fclose(fd);
        $display("PASS: integrated CRTC/composite trace written; phase=%0d", composite_phase);
        $finish;
    end
endmodule
