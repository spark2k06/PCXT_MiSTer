`timescale 1ns/1ps

// EGAUTIL option 5 rewrites CRTC Offset (index 13h) once per scanline,
// alternating between zero and the normal mode-0Dh value. An EGA never
// changes address-counter semantics when Offset is zero: the next row simply
// advances by zero bytes. Switching to the legacy 6845 row-save path at zero
// turns that test into a diagonal smear.
module ega_crtc_offset_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg reset_l = 1'b0;
    reg cs_l = 1'b1;
    reg read_nwrite = 1'b1;
    reg rs = 1'b0;
    reg [7:0] di = 8'h00;
    wire [15:0] ma_full;

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
        // A non-zero reset Offset identifies this instance as the EGA CRTC.
        .EGA_RESET_R17(8'h0E),
        .EGA_RESET_R19(8'd20)
    ) dut (
        .CLOCK(clk), .CLKEN(1'b1), .nCLKEN(1'b0), .PIXEL_CE(1'b1),
        .nRESET(reset_l), .CRTC_TYPE(1'b1),
        .ENABLE(1'b1), .nCS(cs_l), .R_nW(read_nwrite), .RS(rs),
        .DI(di), .DO(), .MA_FULL(ma_full),
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

    task sample_first_address_of_row1;
        output [15:0] value;
        begin
            // Wait for a fresh frame so prior Offset values cannot contribute
            // to the row pointer under test.
            while (dut.frame_new !== 1'b1) @(negedge clk);
            while (!((dut.row == 10'd1) && (dut.hcc == 8'd0))) @(negedge clk);
            #1 value = ma_full;
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

        // Byte addressing, one scanline per character row, start address zero.
        crtc_write(8'h09, 8'h00);
        crtc_write(8'h0C, 8'h00);
        crtc_write(8'h0D, 8'h00);
        crtc_write(8'h17, 8'hE3);

        // Offset zero repeats the same source row; it must not fall back to
        // MC6845 end-of-displayed-address accumulation.
        crtc_write(8'h13, 8'd0);
        sample_first_address_of_row1(row1_address);
        expect16("Offset 0 repeats start address", row1_address, 16'd0);

        // In EGA byte mode Offset is a word count, so 2 advances four bytes.
        crtc_write(8'h13, 8'd2);
        sample_first_address_of_row1(row1_address);
        expect16("Offset 2 advances four bytes", row1_address, 16'd4);

        if (errors == 0) $display("RESULT: PASS");
        else $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
