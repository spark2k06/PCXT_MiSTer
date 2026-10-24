//============================================================================
//
//  EGA BIOS mode 0Fh: 640x350 monochrome graphics on an IBM 5151.
//
//  This covers the renderer path which text-mode-only testing cannot reach:
//    * four planar bits are expanded at one dot per bit (640-pixel path),
//    * the attribute palette selects the EGA Mono Video + Intensity pins,
//    * the 5151 connector conversion emits alternating bright white/black.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_mode0f_mono_tb;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic reset = 1'b1;
    logic ce_pix = 1'b1;
    logic fetch_en = 1'b0;
    logic [7:0] plane0_data = 8'hAA;
    logic [7:0] plane1_data = 8'hAA;
    logic [7:0] plane2_data = 8'hAA;
    logic [7:0] plane3_data = 8'hAA;
    wire [3:0] plane_index;
    wire pixel_valid;

    logic [15:0] io_addr = 16'h0000;
    logic [7:0] io_data_in = 8'h00;
    logic io_we = 1'b0;
    logic io_re = 1'b0;
    logic status_re = 1'b0;
    wire [7:0] io_data_out;
    wire mono_attributes;
    wire [5:0] ega_color;
    wire [5:0] mono_luma;
    wire crtc_de;
    wire crtc_vde;
    wire crtc_line_reset;
    wire [9:0] crtc_vscan;

    integer errors = 0;
    integer pixel;
    integer frame_wraps;
    integer visible_lines;
    integer active_chars;
    logic [9:0] previous_vscan;
    logic previous_line_visible;
    logic horizontal_checked;

    ega_pixel pixel_gen (
        .clk(clk),
        .ce_pix(ce_pix),
        .plane0_data(plane0_data),
        .plane1_data(plane1_data),
        .plane2_data(plane2_data),
        .plane3_data(plane3_data),
        .fetch_en(fetch_en),
        .dot_clock_div2(1'b0),
        .display_enable(1'b1),
        .render_mode(2'd1),
        .plane_index(plane_index),
        .pixel_valid(pixel_valid),
        .render_mode_debug()
    );

    ega_attrib_ctrl attributes (
        .clk(clk),
        .reset(reset),
        .ce_pix(ce_pix),
        .io_addr(io_addr),
        .io_data_in(io_data_in),
        .io_data_out(io_data_out),
        .io_we(io_we),
        .io_re(io_re),
        .status_re(status_re),
        .plane_index(plane_index),
        .pixel_valid(pixel_valid),
        .display_enable(1'b1),
        .text_mode(1'b0),
        .blink_state(1'b0),
        .palette_64_mode(1'b1),
        .blink_enable_out(),
        .mono_attributes_out(mono_attributes),
        .line_graphics_enable_out(),
        .pixel_pan_out(),
        .color_out(ega_color),
        .display_enable_out(),
        .video_enable_out()
    );

    ega_5151_output monitor (
        .color(ega_color),
        .luma(mono_luma)
    );

    // IBM mode 0Fh CRTC values. R1=4Fh exposes 80 character clocks and the
    // extended vertical registers combine to a 350-line display end.
    UM6845R #(
        .H_TOTAL(8'h5B),
        .H_DISP(8'h4F),
        .H_SYNCPOS(8'h53),
        .H_SYNCWIDTH(4'h7),
        .V_TOTAL(7'h52),
        .V_TOTALADJ(5'h00),
        .V_DISP(8'h6C),
        .V_SYNCPOS(8'h1F),
        .V_MAXSCAN(5'h00),
        .DISPLAYED_CHARS_PLUS1(1),
        .EGA_RESET_R16(8'h5E),
        .EGA_RESET_R17(8'h2B),
        .EGA_RESET_R18(8'h5D),
        .EGA_RESET_R19(8'h28)
    ) mode0f_crtc (
        .CLOCK(clk),
        .CLKEN(1'b1),
        .nCLKEN(1'b0),
        .PIXEL_CE(1'b1),
        .nRESET(~reset),
        .CRTC_TYPE(1'b1),
        .ENABLE(1'b0),
        .nCS(1'b1),
        .R_nW(1'b1),
        .RS(1'b0),
        .DI(8'h00),
        .DO(),
        .hblank(),
        .vblank(),
        .line_reset(crtc_line_reset),
        .VSYNC(),
        .HSYNC(),
        .DE(crtc_de),
        .VDE(crtc_vde),
        .FIELD(),
        .CURSOR(),
        .MA(),
        .MA_FULL(),
        .RA(),
        .HC(),
        .VC(),
        .VSCAN(crtc_vscan),
        .H_DISP_REG(),
        .V_MAXSCAN_REG(),
        .hsync_width(),
        .status_vretrace(),
        .status_not_displaying(),
        .vert_blank_active(),
        .scanline_mod16_debug(),
        .vslines_debug(),
        .crtc_r10_debug(),
        .crtc_r11_debug(),
        .crtc_r12_debug(),
        .crtc_r13_debug(),
        .crtc_r14_debug(),
        .crtc_r17_debug(),
        .crtc_r15_debug(),
        .crtc_r16_debug(),
        .crt_h_offset(4'd0),
        .crt_v_offset(3'd0),
        .vsync_width_osd(3'd0),
        .hsync_width_osd(3'd0),
        .hres_mode(1'b1)
    );

    task automatic attr_write(input logic [4:0] index, input logic [7:0] data);
        begin
            // An Input Status 1 read resets the 3C0h address/data flip-flop.
            @(negedge clk);
            status_re <= 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            status_re <= 1'b0;

            io_addr <= 16'h03C0;
            io_data_in <= {2'b00, 1'b1, index};
            io_we <= 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            io_we <= 1'b0;
            @(posedge clk);
            #1;

            @(negedge clk);
            io_data_in <= data;
            io_we <= 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            io_we <= 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_planar_pixel(input integer number);
        logic [3:0] expected;
        begin
            expected = ((number & 1) == 0) ? 4'hF : 4'h0;
            if (!pixel_valid || (plane_index !== expected)) begin
                errors = errors + 1;
                $display("FAIL: mode 0Fh planar pixel %0d index=%h valid=%b, expected %h/1",
                         number, plane_index, pixel_valid, expected);
            end
        end
    endtask

    task automatic check_previous_luma(input integer number);
        logic [5:0] expected;
        begin
            expected = ((number & 1) == 0) ? 6'd63 : 6'd0;
            if (mono_luma !== expected) begin
                errors = errors + 1;
                $display("FAIL: mode 0Fh monitor pixel %0d luma=%0d, expected %0d",
                         number, mono_luma, expected);
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset <= 1'b0;
        repeat (2) @(posedge clk);

        // Mode 0Fh uses monochrome graphics attributes. Map logical colour F
        // to both Mono Video and Intensity (EGA connector code 18h).
        attr_write(5'h0F, 8'h18);
        attr_write(5'h10, 8'h03);
        attr_write(5'h12, 8'h0F);

        if (mono_attributes !== 1'b1) begin
            errors = errors + 1;
            $display("FAIL: mode 0Fh monochrome attribute control is not enabled");
        end

        // Ignore the partial power-on frame, then count one complete mode 0Fh
        // frame. Each active CRTC character clock feeds eight undivided dots.
        frame_wraps = 0;
        visible_lines = 0;
        active_chars = 0;
        previous_vscan = crtc_vscan;
        previous_line_visible = crtc_vde;
        horizontal_checked = 1'b0;
        while (frame_wraps < 2) begin
            @(posedge clk);
            #1;
            if (crtc_vscan != previous_vscan) begin
                if ((frame_wraps == 1) && previous_line_visible && !horizontal_checked) begin
                    horizontal_checked = 1'b1;
                    if (active_chars != 80) begin
                        errors = errors + 1;
                        $display("FAIL: mode 0Fh active character clocks=%0d, expected 80 (640 dots)",
                                 active_chars);
                    end
                end

                if (crtc_vscan < previous_vscan) begin
                    if (frame_wraps == 1 && visible_lines != 350) begin
                        errors = errors + 1;
                        $display("FAIL: mode 0Fh visible lines=%0d, expected 350", visible_lines);
                    end
                    frame_wraps = frame_wraps + 1;
                    visible_lines = 0;
                end

                previous_vscan = crtc_vscan;
                previous_line_visible = crtc_vde;
                active_chars = crtc_de ? 1 : 0;
                if ((frame_wraps == 1) && crtc_vde)
                    visible_lines = visible_lines + 1;
            end
            else if (crtc_de) begin
                active_chars = active_chars + 1;
            end
        end

        if (!horizontal_checked) begin
            errors = errors + 1;
            $display("FAIL: mode 0Fh did not expose a measurable 640-dot active line");
        end

        // AA in every plane must become F,0,F,0,F,0,F,0. With the mode 0Fh
        // non-divided dot clock there are exactly eight output dots, not four
        // repeated pairs as in a 320-pixel mode.
        @(negedge clk);
        fetch_en <= 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        fetch_en <= 1'b0;

        check_planar_pixel(0);
        for (pixel = 1; pixel < 8; pixel = pixel + 1) begin
            @(posedge clk);
            #1;
            check_planar_pixel(pixel);
            check_previous_luma(pixel - 1);
        end

        @(posedge clk);
        #1;
        check_previous_luma(7);

        if (errors == 0)
            $display("PASS: EGA mode 0Fh renders 640x350 planar monochrome as 5151 black/bright-white");
        else
            $display("FAIL: %0d EGA mode 0Fh checks failed", errors);

        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
