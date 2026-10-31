//============================================================================
//
//  splash_fade: the picture goes through untouched outside the splash, stays
//  black for the first 60 frames, fades in from black in 32 more, stays at
//  full brightness, fades out by one step a frame while fade_out is asked
//  for, and starts from black again the next time the splash appears.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module splash_fade_tb;

    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg       active = 1'b0;
    reg       fade_out = 1'b0;
    reg       vsync = 1'b0;
    reg [7:0] r = 8'hFF, g = 8'h55, b = 8'hAA;
    wire [7:0] ro, go, bo;

    splash_fade dut (
        .clock(clk), .reset(1'b0), .active(active), .fade_out(fade_out), .vsync(vsync),
        .r_in(r), .g_in(g), .b_in(b), .r_out(ro), .g_out(go), .b_out(bo)
    );

    integer errors = 0;
    integer i;

    task frame;
        begin
            repeat (3) @(posedge clk);
            vsync = 1'b1;
            repeat (3) @(posedge clk);
            vsync = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task expect_rgb;
        input [7:0] er, eg, eb;
        input [255:0] what;
        begin
            if (ro !== er || go !== eg || bo !== eb) begin
                $display("FAIL: %0s: %h %h %h, expected %h %h %h", what, ro, go, bo, er, eg, eb);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        frame; frame;
        expect_rgb(8'hFF, 8'h55, 8'hAA, "outside the splash");

        active = 1'b1;
        @(posedge clk); #1;
        expect_rgb(8'h00, 8'h00, 8'h00, "splash start");
        for (i = 0; i < 60; i = i + 1) frame;       // held black
        expect_rgb(8'h00, 8'h00, 8'h00, "black for the first second");
        frame;                                       // level 2
        expect_rgb((8'hFF * 2) >> 6, (8'h55 * 2) >> 6, (8'hAA * 2) >> 6, "first fade-in step");
        for (i = 0; i < 15; i = i + 1) frame;       // level 32
        expect_rgb((8'hFF * 32) >> 6, (8'h55 * 32) >> 6, (8'hAA * 32) >> 6, "half way in");
        for (i = 0; i < 16; i = i + 1) frame;       // level 64
        expect_rgb(8'hFF, 8'h55, 8'hAA, "full after 32 frames");
        frame; frame;
        expect_rgb(8'hFF, 8'h55, 8'hAA, "stays full");

        fade_out = 1'b1;
        frame;                                       // level 63
        expect_rgb((8'hFF * 63) >> 6, (8'h55 * 63) >> 6, (8'hAA * 63) >> 6, "first fade-out step");
        for (i = 0; i < 63; i = i + 1) frame;       // level 0
        expect_rgb(8'h00, 8'h00, 8'h00, "black after 64 frames");
        frame;
        expect_rgb(8'h00, 8'h00, 8'h00, "stays black");

        active = 1'b0; fade_out = 1'b0;
        @(posedge clk); @(posedge clk); #1;
        expect_rgb(8'hFF, 8'h55, 8'hAA, "after the splash");

        active = 1'b1;
        @(posedge clk); #1;
        expect_rgb(8'h00, 8'h00, 8'h00, "next splash starts from black");

        if (errors == 0) $display("PASS: splash fade in, hold, out and pass-through");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

endmodule
