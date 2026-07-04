`timescale 1ns / 1ps

module ega_vgaport_tb;

    timeunit 1ns;
    timeprecision 1ps;

    reg [5:0] color = 6'h00;
    reg palette_64_mode = 1'b0;
    wire [5:0] red;
    wire [5:0] green;
    wire [5:0] blue;
    integer failures = 0;

    ega_vgaport dut (
        .color(color),
        .palette_64_mode(palette_64_mode),
        .red(red),
        .green(green),
        .blue(blue)
    );

    task automatic expect_rgb(
        input [8*40-1:0] label,
        input [5:0] exp_red,
        input [5:0] exp_green,
        input [5:0] exp_blue
    );
        begin
            #1;
            if ((red !== exp_red) || (green !== exp_green) || (blue !== exp_blue)) begin
                $display("FAIL %0s expected=%0d,%0d,%0d actual=%0d,%0d,%0d",
                         label, exp_red, exp_green, exp_blue, red, green, blue);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        palette_64_mode = 1'b0;

        color = 6'h06;
        expect_rgb("16-color brown", 6'd42, 6'd21, 6'd0);

        color = 6'h0E;
        expect_rgb("16-color bright yellow", 6'd42, 6'd42, 6'd0);

        if (failures == 0)
            $display("PASS ega_vgaport_tb");
        else
            $display("FAIL ega_vgaport_tb failures=%0d", failures);

        $finish(failures == 0 ? 0 : 1);
    end

endmodule
