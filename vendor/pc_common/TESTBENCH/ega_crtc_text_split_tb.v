`timescale 1ns/1ps

// Regression for the interaction between EGA text split screens and the
// bounded VGA cleanup guard added in c59a2ee.  Text modes clear CRTC Mode
// Control bit 6, but Line Compare must still restart a non-zero top page at
// address zero.  The one sequence that remains guarded is a zero Start Address
// plus Line Compare zero, which otherwise pins a restored mode 03h to row zero.
module ega_crtc_text_split_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg reset_l = 1'b0;
    reg cs_l = 1'b1;
    reg read_nwrite = 1'b1;
    reg rs = 1'b0;
    reg [7:0] di = 8'h00;

    integer errors = 0;
    reg [15:0] row1_address;

    UM6845R #(
        .H_TOTAL(7),
        .H_DISP(3),
        .H_SYNCPOS(5),
        .H_SYNCWIDTH(1),
        .V_TOTAL(7),
        .V_DISP(5),
        .V_SYNCPOS(6),
        .V_MAXSCAN(0),
        .EGA_RESET_R17(8'h0E),
        .EGA_RESET_R19(8'd20)
    ) dut (
        .CLOCK(clk), .CLKEN(1'b1), .nCLKEN(1'b0), .PIXEL_CE(1'b1),
        .nRESET(reset_l), .CRTC_TYPE(1'b1),
        .ENABLE(1'b1), .nCS(cs_l), .R_nW(read_nwrite), .RS(rs),
        .DI(di), .DO(),
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

    task sample_row1;
        output [15:0] value;
        begin
            // Two frame boundaries cover both the retrace sampling latch and
            // the active-frame latch used by Start Address.
            wait_frame_start();
            wait_frame_start();
            while (!((dut.row == 10'd1) && (dut.hcc == 8'd0))) @(negedge clk);
            #1 value = dut.row_addr_r;
        end
    endtask

    task expect16;
        input string label;
        input [15:0] got;
        input [15:0] expected;
        begin
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: got %04h expected %04h", label, got, expected);
            end else begin
                $display("PASS %0s: %04h", label, got);
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset_l = 1'b1;

        // One scanline per character row, two words/four addresses per row.
        // A3h is the EGA BIOS text-mode value: bit 6 is deliberately clear.
        crtc_write(8'h08, 8'h00);
        crtc_write(8'h09, 8'h00);
        crtc_write(8'h13, 8'd2);
        crtc_write(8'h17, 8'hA3);
        crtc_write(8'h07, 8'h00);
        crtc_write(8'h18, 8'h00);

        // EGAUTIL option E selects a second text page as the top window.  A
        // Line Compare of zero makes row 1 restart at page/address zero.
        crtc_write(8'h0C, 8'h00);
        crtc_write(8'h0D, 8'h40);
        sample_row1(row1_address);
        expect16("text split restarts non-zero top page", row1_address, 16'h0000);

        // Preserve the c59a2ee cleanup fix: with both the restored text page
        // and Line Compare at zero, row 1 must advance normally instead of
        // being reset to address zero on every scanline.
        crtc_write(8'h0C, 8'h00);
        crtc_write(8'h0D, 8'h00);
        sample_row1(row1_address);
        expect16("zero-page mode 03h cleanup advances", row1_address, 16'h0004);

        if (errors == 0) $display("RESULT: PASS");
        else $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
