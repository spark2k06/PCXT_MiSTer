`timescale 1ns/1ps

// VGA software commonly updates CRTC overflow registers with read/modify/write
// sequences.  Cute Demo depends on that for R07 and R09 while establishing its
// 320x240 split-screen layout.  Returning zero from either read loses the
// vertical overflow bits and changes Maximum Scan Line from 1 to 0, compressing
// the displayed picture by exactly two.
module ega_crtc_readback_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg reset_l = 1'b0;
    reg enable = 1'b1;
    reg cs_l = 1'b1;
    reg read_nwrite = 1'b1;
    reg rs = 1'b0;
    reg [7:0] di = 8'h00;
    wire [7:0] dout;
    wire [4:0] max_scan;
    wire [9:0] line_compare;

    integer errors = 0;
    reg [7:0] value;

    UM6845R #(
        .EGA_RESET_R17(8'h0E),
        .EGA_RESET_R19(8'h28)
    ) dut (
        .CLOCK(clk), .CLKEN(1'b1), .nCLKEN(1'b0), .PIXEL_CE(1'b1),
        .nRESET(reset_l), .CRTC_TYPE(1'b1),
        .ENABLE(enable), .nCS(cs_l), .R_nW(read_nwrite), .RS(rs),
        .DI(di), .DO(dout),
        .V_MAXSCAN_REG(max_scan),
        .crtc_line_compare_debug(line_compare),
        .crt_h_offset(4'd0), .crt_v_offset(3'd0),
        .vsync_width_osd(3'd0), .hsync_width_osd(3'd0), .hres_mode(1'b1)
    );

    task crtc_index;
        input [7:0] idx;
        begin
            @(negedge clk);
            cs_l = 1'b0; read_nwrite = 1'b0; rs = 1'b0; di = idx;
            @(negedge clk);
            cs_l = 1'b1; read_nwrite = 1'b1;
        end
    endtask

    task crtc_write;
        input [7:0] idx;
        input [7:0] data;
        begin
            crtc_index(idx);
            @(negedge clk);
            cs_l = 1'b0; read_nwrite = 1'b0; rs = 1'b1; di = data;
            @(negedge clk);
            cs_l = 1'b1; read_nwrite = 1'b1;
        end
    endtask

    task crtc_read;
        input [7:0] idx;
        output [7:0] data;
        begin
            crtc_index(idx);
            @(negedge clk);
            cs_l = 1'b0; read_nwrite = 1'b1; rs = 1'b1;
            #1 data = dout;
            @(negedge clk);
            cs_l = 1'b1;
        end
    endtask

    task expect8;
        input [127:0] label;
        input [7:0] got;
        input [7:0] expected;
        begin
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: got %02h expected %02h", label, got, expected);
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset_l = 1'b1;

        // VGATSR's 320x200 baseline, also inherited by Cute's 320x240 mode.
        crtc_write(8'h07, 8'h3E);
        crtc_write(8'h09, 8'h41);
        crtc_write(8'h18, 8'hE0);

        crtc_read(8'h07, value);
        expect8("R07 readback", value, 8'h3E);
        // Cute: preserve every overflow bit while setting LC bit 8.
        value = value | 8'h10;
        crtc_write(8'h07, value);

        crtc_read(8'h09, value);
        expect8("R09 readback", value, 8'h41);
        // Cute: preserve Maximum Scan Line=1 while clearing LC bit 9.
        value = value & 8'hBF;
        crtc_write(8'h09, value);

        crtc_read(8'h09, value);
        expect8("R09 after RMW", value, 8'h01);
        if (max_scan !== 5'd1) begin
            errors = errors + 1;
            $display("FAIL Maximum Scan Line after RMW: %0d expected 1", max_scan);
        end
        if (line_compare !== 10'd480) begin
            errors = errors + 1;
            $display("FAIL Line Compare after RMW: %0d expected 480", line_compare);
        end

        if (errors == 0) $display("RESULT: PASS");
        else $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
