`timescale 1ns/1ps

// EGA CRTC index 08h presets the scanline counter at the start of a frame.
// EGAUTIL option D combines this fine vertical scroll with Start Address and
// Attribute Controller pel panning.  Starting at scanline 5 in an eight-line
// character cell must therefore render 5, 6, 7, then advance to the next text
// row and continue at scanline 0.
module ega_crtc_preset_row_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg reset_l = 1'b0;
    reg cs_l = 1'b1;
    reg read_nwrite = 1'b1;
    reg rs = 1'b0;
    reg [7:0] di = 8'h00;
    wire [15:0] ma_full;
    wire [4:0] ra;

    integer errors = 0;

    UM6845R #(
        .H_TOTAL(7),
        .H_DISP(3),
        .H_SYNCPOS(5),
        .H_SYNCWIDTH(1),
        .V_TOTAL(7),
        .V_DISP(5),
        .V_SYNCPOS(6),
        .V_MAXSCAN(7),
        .EGA_RESET_R17(8'h0E),
        .EGA_RESET_R19(8'd20)
    ) dut (
        .CLOCK(clk), .CLKEN(1'b1), .nCLKEN(1'b0), .PIXEL_CE(1'b1),
        .nRESET(reset_l), .CRTC_TYPE(1'b1),
        .ENABLE(1'b1), .nCS(cs_l), .R_nW(read_nwrite), .RS(rs),
        .DI(di), .DO(), .MA_FULL(ma_full), .RA(ra),
        .crt_h_offset(4'd0), .crt_v_offset(3'd0),
        .vsync_width_osd(3'd0), .hsync_width_osd(3'd0), .hres_mode(1'b1)
    );

    task crtc_write;
        input [7:0] idx;
        input [7:0] data;
        begin
            @(negedge clk);
            cs_l = 1'b0; read_nwrite = 1'b0; rs = 1'b0; di = idx;
            @(negedge clk);
            cs_l = 1'b1; read_nwrite = 1'b1;
            @(negedge clk);
            cs_l = 1'b0; read_nwrite = 1'b0; rs = 1'b1; di = data;
            @(negedge clk);
            cs_l = 1'b1; read_nwrite = 1'b1;
        end
    endtask

    task wait_frame_start;
        begin
            while (dut.frame_new !== 1'b1) @(negedge clk);
            @(posedge clk);
            #1;
        end
    endtask

    task wait_next_scanline;
        begin
            while (dut.line_new !== 1'b1) @(negedge clk);
            @(posedge clk);
            #1;
        end
    endtask

    task expect_line_and_address;
        input string label;
        input [4:0] expected_line;
        input [15:0] expected_address;
        begin
            if ((ra !== expected_line) || (ma_full !== expected_address)) begin
                errors = errors + 1;
                $display("FAIL %0s: RA=%0d MA=%04h expected RA=%0d MA=%04h",
                         label, ra, ma_full, expected_line, expected_address);
            end else begin
                $display("PASS %0s: RA=%0d MA=%04h", label, ra, ma_full);
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset_l = 1'b1;

        // Eight scanlines per character row, byte addressing and an Offset of
        // two words (four bytes) make the row transition directly observable.
        crtc_write(8'h08, 8'd5);
        crtc_write(8'h09, 8'd7);
        crtc_write(8'h0C, 8'h00);
        crtc_write(8'h0D, 8'h00);
        crtc_write(8'h13, 8'd2);
        crtc_write(8'h17, 8'hE3);

        wait_frame_start();
        expect_line_and_address("first partial-row scanline", 5'd5, 16'd0);
        wait_next_scanline();
        expect_line_and_address("second partial-row scanline", 5'd6, 16'd0);
        wait_next_scanline();
        expect_line_and_address("last partial-row scanline", 5'd7, 16'd0);
        wait_next_scanline();
        expect_line_and_address("next character row", 5'd0, 16'd4);

        if (errors == 0) $display("RESULT: PASS");
        else $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
