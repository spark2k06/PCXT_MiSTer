`timescale 1ns/1ps

// Diagnostic-only comparison of the CGA pixel fetch against a synchronous
// dual-port VRAM.  The existing cga_crtc_composite_tb drives vram_data
// combinationally; this bench models the port-B clock-to-Q delay used by the
// MiSTer vram module and records the values captured by cga_pixel.
module cga_vram_pixel_latency_tb;
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
    wire [3:0] video;

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

    cga_sequencer sequencer (
        .clk(clk), .reset(1'b0), .clk_seq(clkdiv), .vram_read(vram_read),
        .vram_read_a0(vram_read_a0), .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att), .hres_mode(hres_mode),
        .crtc_clk(crtc_clk), .charrom_read(charrom_read),
        .disp_pipeline(disp_pipeline), .isa_op_enable(isa_op_enable),
        .hclk(hclk), .lclk(lclk), .tandy_16_gfx(1'b0),
        .tandy_color_16(tandy_color_16)
    );

    UM6845R #(
        .H_TOTAL(8'd113), .H_DISP(8'd80), .H_SYNCPOS(8'd90),
        .H_SYNCWIDTH(4'd10), .V_TOTAL(7'd31), .V_TOTALADJ(5'd6),
        .V_DISP(7'd25), .V_SYNCPOS(7'd28), .V_MAXSCAN(5'd7),
        .C_START(7'd6), .C_END(7'd7)
    ) crtc (
        .CLOCK(clk), .CLKEN(crtc_clk), .nCLKEN(1'b1), .nRESET(nreset),
        .CRTC_TYPE(1'b1), .ENABLE(1'b1), .nCS(ncs), .R_nW(rnw),
        .RS(rs), .DI(di), .DO(), .hblank(hblank), .vblank(vblank),
        .line_reset(line_reset), .VSYNC(vsync), .HSYNC(hsync),
        .DE(display_enable), .FIELD(), .CURSOR(cursor), .MA(ma),
        .RA(row_addr), .hsync_width(hsync_width),
        .composite_phase(composite_phase), .crt_h_offset(4'd0),
        .crt_v_offset(3'd0), .vsync_width_osd(3'd0),
        .hsync_width_osd(3'd0), .hres_mode(hres_mode)
    );

    // The memory is deliberately address-derived and synchronous.  Every
    // character cell has a distinct glyph and attribute so a one-cycle swap
    // is visible in the captured IRGB sequence.
    reg [7:0] vram_dout = 8'h00;
    reg [13:0] vram_addr_q = 14'd0;
    wire [13:0] vram_addr = {ma[13:1], vram_read_a0};
    wire [7:0] memory_word = vram_addr[0] ?
                             {4'h0, vram_addr[7:4]} :
                             ((vram_addr[13:8] & 6'h03) == 0 ? 8'h55 :
                              (vram_addr[13:8] & 6'h03) == 1 ? 8'h13 :
                              (vram_addr[13:8] & 6'h03) == 2 ? 8'hb0 : 8'hb1);

    always @(posedge clk) begin
        if (vram_read) begin
            vram_addr_q <= vram_addr;
            vram_dout <= memory_word;
        end
    end

    cga_pixel pixel (
        .clk(clk), .clk_seq(clkdiv), .hres_mode(hres_mode),
        .grph_mode(grph_mode), .bw_mode(bw_mode), .mode_640(mode_640),
        .tandy_16_mode(tandy_16_mode), .thin_font(thin_font),
        .vram_data(vram_dout), .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att), .disp_pipeline(disp_pipeline),
        .charrom_read(charrom_read), .display_enable(display_enable),
        .cursor(cursor), .row_addr(row_addr), .blink_enabled(blink_enabled),
        .blink(blink), .hsync(hsync), .vsync(vsync),
        .video_enabled(video_enabled), .cga_color_reg(cga_color_reg),
        .tandy_palette_color(tandy_palette_color),
        .tandy_newcolor(tandy_newcolor), .tandy_palette_set(tandy_palette_set),
        .tandy_bordercol(tandy_bordercol), .tandy_color_4(tandy_color_4),
        .tandy_color_16(tandy_color_16), .video(video)
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
    integer unique_count;
    reg [3:0] previous_video;
    reg [7:0] previous_char;
    reg [7:0] previous_attr;

    always @(posedge clk) begin
        if (nreset && !clkdiv[0]) begin
            if (video != previous_video || pixel.char_byte != previous_char ||
                pixel.attr_byte != previous_attr || (sample_count % 32) == 0) begin
                $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                    sample_count, clkdiv, hblank, display_enable, vram_read,
                    vram_read_char, vram_read_att, vram_dout, pixel.char_byte,
                    pixel.attr_byte);
            end
            previous_video <= video;
            previous_char <= pixel.char_byte;
            previous_attr <= pixel.attr_byte;
            sample_count <= sample_count + 1;
        end
    end

    initial begin
        fd = $fopen("cga_vram_pixel_latency.csv", "w");
        $fwrite(fd, "sample,clkdiv,hblank,de,vram_read,read_char,read_attr,vram_dout,char_byte,attr_byte\n");
        sample_count = 0;
        previous_video = 4'h0;
        previous_char = 8'h00;
        previous_attr = 8'h00;
        force crtc.row_addr = 14'd0;
        force crtc.row_addr_r = 14'd0;
        repeat (4) @(posedge clk);
        nreset = 1'b1;
        crtc_write(5'd4, 8'h01);
        crtc_write(5'd6, 8'h01);
        crtc_write(5'd9, 8'h00);
        crtc_write(5'd7, 8'h02);
        release crtc.row_addr;
        release crtc.row_addr_r;
        force crtc.vde = 1'b1;
        force crtc.vde_r = 1'b1;
        #1 $readmemh("rtl/video/cga.hex", pixel.char_rom, 0, 4095);
        repeat (16000) @(posedge clk);
        release crtc.vde;
        release crtc.vde_r;
        $fclose(fd);
        $display("PASS: synchronous VRAM latency trace written");
        $finish;
    end
endmodule
