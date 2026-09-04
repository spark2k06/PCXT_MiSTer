`timescale 1ns/1ps

// Diagnostic-only bench for the native CGA timing boundary.
// It deliberately keeps the composite decoder out of the first pass: the
// useful question here is whether the CRTC blanking and the delayed pixel
// stream describe the same electrical line.
module cga_crtc_pixel_timing_tb;
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

    wire hblank;
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

    // A solid glyph with an attribute selected by the CRTC character address
    // gives the timing test a deterministic, multi-colour active stream.
    wire [3:0] test_fg = {1'b0, ma[5:3]};
    wire [7:0] vram_data = vram_read_char ? 8'hDB :
                           vram_read_att  ? {1'b0, test_fg} : 8'h00;
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
        .C_END(5'd7)
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
        .hblank(hblank),
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
    reg old_hblank;
    reg old_line_reset;
    reg old_phase;
    reg [3:0] old_video;
    reg [1:0] old_display_enable_del;

    always @(posedge clk) begin
        if (nreset && (clkdiv[0] == 1'b1)) begin
            if (hblank != old_hblank || line_reset != old_line_reset ||
                composite_phase != old_phase || video != old_video ||
                pixel.display_enable_del != old_display_enable_del ||
                ((sample_count % 100) == 0)) begin
                $fwrite(fd, "%0t,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                    $time, sample_count, clkdiv, hblank, display_enable,
                    line_reset, composite_phase, hsync, video, ma,
                    pixel.display_enable_del, pixel.video_out, pixel.pix_delay,
                    pixel.attr_byte_del, pixel.charbits, pixel.pix_bits);
            end
            old_hblank <= hblank;
            old_line_reset <= line_reset;
            old_phase <= composite_phase;
            old_video <= video;
            old_display_enable_del <= pixel.display_enable_del;
            sample_count <= sample_count + 1;
        end
    end

    initial begin
        fd = $fopen("cga_crtc_pixel_timing.csv", "w");
        $fwrite(fd, "time,sample,clkdiv,hblank,de,line_reset,phase,hsync,video,ma,display_enable_del,video_out,pix_delay,attr_byte_del,charbits,pix_bits\n");
        sample_count = 0;
        old_hblank = 1'b1;
        old_line_reset = 1'b0;
        old_phase = 1'b0;
        old_video = 4'h0;
        old_display_enable_del = 2'b00;

        repeat (4) @(posedge clk);
        nreset = 1'b1;
        // Shorten only the vertical model so the bench reaches an active
        // line quickly.  The horizontal timing under test remains the CGA
        // 80-column timing (R0=71h, R1=50h, R2=5ah, R3=0ah).
        crtc_write(5'd4, 8'h01);
        crtc_write(5'd6, 8'h01);
        crtc_write(5'd9, 8'h00);
        crtc_write(5'd7, 8'h02);
        // This bench is about the horizontal boundary.  The UM6845R vertical
        // state only enables DE on a complete frame transition, which would
        // obscure the horizontal trace and make the result depend on the
        // shortened vertical registers above.  Hold the vertical gate open
        // after programming them so DE follows the real hde signal.
        force crtc.vde = 1'b1;
        force crtc.vde_r = 1'b1;
        repeat (10000) @(posedge clk);

        // This is the exact CRTC operation used by the calibration screen.
        crtc_write(5'd0, 8'h72);
        repeat (15000) @(posedge clk);
        crtc_write(5'd0, 8'h71);
        repeat (15000) @(posedge clk);

        release crtc.vde;
        release crtc.vde_r;
        $fclose(fd);
        $display("PASS: CRTC/pixel timing trace written; phase=%0d", composite_phase);
        $finish;
    end
endmodule
