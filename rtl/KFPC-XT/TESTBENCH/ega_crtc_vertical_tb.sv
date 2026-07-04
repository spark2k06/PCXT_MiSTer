`timescale 1ns / 1ps

module ega_crtc_vertical_tb;

    timeunit 1ns;
    timeprecision 1ps;

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg ncs = 1'b1;
    reg rw = 1'b1;
    reg rs = 1'b0;
    reg [7:0] di = 8'h00;

    integer failures = 0;
    integer line_count = 0;
    integer start_row = 0;
    integer start_line = 0;
    integer row_delta = 0;
    integer line_delta = 0;
    integer vsync_lines = 0;
    wire cursor;
    wire [15:0] ma_full;
    wire cga_cursor;
    wire [13:0] cga_ma;
    wire [15:0] cga_ma_full;
    wire vsync;

    always #5 clk = ~clk;

    UM6845R dut (
        .CLOCK(clk),
        .CLKEN(1'b1),
        .nCLKEN(1'b0),
        .nRESET(reset_n),
        .CRTC_TYPE(1'b1),
        .ENABLE(1'b1),
        .nCS(ncs),
        .R_nW(rw),
        .RS(rs),
        .DI(di),
        .DO(),
        .hblank(),
        .vblank(),
        .line_reset(),
        .VSYNC(vsync),
        .HSYNC(),
        .DE(),
        .FIELD(),
        .CURSOR(cursor),
        .MA(),
        .MA_FULL(ma_full),
        .RA(),
        .HC(),
        .VC(),
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

    defparam dut.H_TOTAL = 8'd3;
    defparam dut.H_DISP = 8'd1;
    defparam dut.H_SYNCPOS = 8'd2;
    defparam dut.H_SYNCWIDTH = 4'd1;
    defparam dut.V_TOTAL = 7'd0;
    defparam dut.V_TOTALADJ = 5'd0;
    defparam dut.V_DISP = 7'd0;
    defparam dut.V_SYNCPOS = 7'd0;
    defparam dut.V_MAXSCAN = 5'd8;
    defparam dut.C_START = 7'd0;
    defparam dut.C_END = 5'd0;
    defparam dut.DISPLAYED_CHARS_PLUS1 = 1;
    defparam dut.EGA_RESET_R16 = 8'd0;
    defparam dut.EGA_RESET_R18 = 8'd0;
    defparam dut.EGA_RESET_R19 = 8'h14;

    UM6845R cga_dut (
        .CLOCK(clk),
        .CLKEN(1'b1),
        .nCLKEN(1'b0),
        .nRESET(reset_n),
        .CRTC_TYPE(1'b1),
        .ENABLE(1'b1),
        .nCS(1'b1),
        .R_nW(1'b1),
        .RS(1'b0),
        .DI(8'h00),
        .DO(),
        .hblank(),
        .vblank(),
        .line_reset(),
        .VSYNC(),
        .HSYNC(),
        .DE(),
        .FIELD(),
        .CURSOR(cga_cursor),
        .MA(cga_ma),
        .MA_FULL(cga_ma_full),
        .RA(),
        .HC(),
        .VC(),
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

    defparam cga_dut.H_TOTAL = 8'd3;
    defparam cga_dut.H_DISP = 8'd1;
    defparam cga_dut.H_SYNCPOS = 8'd2;
    defparam cga_dut.H_SYNCWIDTH = 4'd1;
    defparam cga_dut.V_TOTAL = 7'd0;
    defparam cga_dut.V_TOTALADJ = 5'd0;
    defparam cga_dut.V_DISP = 7'd0;
    defparam cga_dut.V_SYNCPOS = 7'd0;
    defparam cga_dut.V_MAXSCAN = 5'd8;
    defparam cga_dut.C_START = 7'd0;
    defparam cga_dut.C_END = 5'd0;

    task automatic crtc_write(input [7:0] index, input [7:0] data);
        begin
            @(negedge clk);
            ncs = 1'b0;
            rw = 1'b0;
            rs = 1'b0;
            di = index;
            @(negedge clk);
            rs = 1'b1;
            di = data;
            @(negedge clk);
            ncs = 1'b1;
            rw = 1'b1;
            rs = 1'b0;
            di = 8'h00;
        end
    endtask

    task automatic expect_eq(input [8*80-1:0] label, input integer actual, input integer expected);
        begin
            if (actual !== expected) begin
                $display("FAIL %0s: expected %0d got %0d", label, expected, actual);
                failures = failures + 1;
            end
        end
    endtask

    task automatic wait_hline;
        begin
            @(posedge clk);
            while (!dut.hcc_last)
                @(posedge clk);
            @(posedge clk);
            line_count = line_count + 1;
        end
    endtask

    task automatic expect_vsync_within(
        input [8*80-1:0] label,
        input integer max_lines
    );
        begin
            vsync_lines = 0;
            while (!dut.VSYNC_r && vsync_lines < max_lines) begin
                wait_hline();
                vsync_lines = vsync_lines + 1;
            end

            if (!dut.VSYNC_r) begin
                $display("FAIL %0s: no VSYNC within %0d scanlines", label, max_lines);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        reset_n = 1'b1;
        repeat (4) @(negedge clk);

        crtc_write(8'h09, 8'h08);
        crtc_write(8'h06, 8'h28);
        crtc_write(8'h12, 8'h04);
        crtc_write(8'h10, 8'h05);
        crtc_write(8'h07, 8'h00);

        wait_hline();
        start_row = dut.row;
        start_line = dut.line;

        repeat (6) wait_hline();
        row_delta = dut.row - start_row;
        line_delta = dut.line - start_line;
        if (line_delta < 0)
            line_delta = line_delta + 9;

        expect_eq("EGA vertical counter advances per scanline", row_delta, 6);
        expect_eq("EGA glyph scanline still follows maximum scan line", line_delta, 6);

        repeat (3) wait_hline();
        line_delta = dut.line - start_line;
        if (line_delta < 0)
            line_delta = line_delta + 9;
        expect_eq("EGA glyph scanline wraps after maximum scan line", line_delta, 0);

        crtc_write(8'h06, 8'h04);
        crtc_write(8'h07, 8'h01);
        crtc_write(8'h09, 8'h07);
        crtc_write(8'h10, 8'hDF);
        crtc_write(8'h12, 8'hC7);
        crtc_write(8'h13, 8'h28);
        expect_vsync_within("EGA extended VSYNC matches scanline timing", 300);

        force dut.row_addr_r = 16'h0123;
        force dut.cursor_addr_frame = 14'h0123;
        force dut.line = 5'd0;
        force dut.hde = 1'b1;
        force dut.vde = 1'b1;
        force dut.cursor_line = 1'b1;
        #1 begin
            expect_eq("EGA cursor scanout address is remapped", ma_full, 16'h0246);
            expect_eq("EGA cursor compares logical CRTC address", cursor, 1);
        end
        force dut.row_addr_r = 16'h0124;
        #1 expect_eq("EGA cursor clears on adjacent logical cell", cursor, 0);
        release dut.row_addr_r;
        release dut.cursor_addr_frame;
        release dut.line;
        release dut.hde;
        release dut.vde;
        release dut.cursor_line;

        force cga_dut.row_addr_r = 16'h0123;
        force cga_dut.hde = 1'b1;
        force cga_dut.vde = 1'b1;
        force cga_dut.cursor_line = 1'b1;
        force cga_dut.R14_cursor_h = 6'h01;
        force cga_dut.R15_cursor_l = 8'h23;
        #1 begin
            expect_eq("CGA CRTC keeps linear scanout address", cga_ma_full, 16'h0123);
            expect_eq("CGA cursor compares linear CRTC address", cga_cursor, 1);
        end
        force cga_dut.row_addr_r = 16'h0124;
        #1 expect_eq("CGA cursor clears on adjacent cell", cga_cursor, 0);
        release cga_dut.row_addr_r;
        release cga_dut.hde;
        release cga_dut.vde;
        release cga_dut.cursor_line;
        release cga_dut.R14_cursor_h;
        release cga_dut.R15_cursor_l;

        if (failures == 0) begin
            $display("PASS: ega_crtc_vertical_tb");
        end else begin
            $display("FAIL: ega_crtc_vertical_tb failures=%0d", failures);
            $fatal(1);
        end
        $finish;
    end

endmodule
