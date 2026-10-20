//============================================================================
//
//  The EGA colour value to RGB conversion, exhaustively, against 86Box.
//
//  86Box builds two lookups in vid_ega.c and picks between them from
//  Miscellaneous Output bit 7 (ega->vres = !(val & 0x80);
//  ega->pallook = ega->vres ? pallook16 : pallook64):
//
//      pallook64[c] =  R,G,B from bits 2,1,0 at 0xAA
//                   + r,g,b from bits 5,4,3 at 0x55
//
//      pallook16[c] =  R,G,B from bits 2,1,0 at 0xAA
//                   + a shared intensity from bit 4 at 0x55
//      if ((c & 0x17) == 6) pallook16[c] = 0xAA,0x55,0x00
//
//  The 16 colour lookup gives bits 3 and 5 no weight, so the brown fix has to
//  cover every value that agrees with 06h on the bits that do count - 06h,
//  0Eh, 26h and 2Eh - which is what the 17h mask says.
//
//  0xAA of 0xFF is 42 of 63 and 0x55 is 21 of 63, the core working in 6 bits.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module ega_vgaport_tb;

    reg  [5:0] color = 6'd0;
    reg        palette_64_mode = 1'b0;
    wire [5:0] red, green, blue;

    integer errors = 0;
    integer checks = 0;

    ega_vgaport dut (
        .color(color),
        .palette_64_mode(palette_64_mode),
        .red(red),
        .green(green),
        .blue(blue)
    );

    // The 86Box formula, in the core's 6 bit scale.
    function [5:0] ref_channel;
        input [5:0] c;
        input       mode64;
        input [1:0] which;   // 0 = red, 1 = green, 2 = blue
        reg         primary;
        reg         secondary;
        begin
            primary   = (which == 2'd0) ? c[2] : (which == 2'd1) ? c[1] : c[0];
            secondary = mode64 ? ((which == 2'd0) ? c[5] : (which == 2'd1) ? c[4] : c[3])
                               : c[4];
            ref_channel = (primary ? 6'd42 : 6'd0) + (secondary ? 6'd21 : 6'd0);
        end
    endfunction

    integer m, c;
    reg [5:0] er, eg, eb;

    initial begin
        for (m = 0; m < 2; m = m + 1) begin
            for (c = 0; c < 64; c = c + 1) begin
                palette_64_mode = m[0];
                color = c[5:0];
                #1;

                if ((m == 0) && ((c & 6'h17) == 6'h06)) begin
                    er = 6'd42; eg = 6'd21; eb = 6'd0;      // brown fix
                end else begin
                    er = ref_channel(c[5:0], m[0], 2'd0);
                    eg = ref_channel(c[5:0], m[0], 2'd1);
                    eb = ref_channel(c[5:0], m[0], 2'd2);
                end

                checks = checks + 1;
                if ((red !== er) || (green !== eg) || (blue !== eb)) begin
                    errors = errors + 1;
                    $display("FAIL %s colour %02X: got %0d,%0d,%0d expected %0d,%0d,%0d",
                             m[0] ? "64" : "16", c, red, green, blue, er, eg, eb);
                end
            end
        end

        $display("");
        $display("%0d checks, %0d failed", checks, errors);
        $display("RESULT: %0s", (errors == 0) ? "PASS" : "FAIL");
        $finish;
    end

endmodule
