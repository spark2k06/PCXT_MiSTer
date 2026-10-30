`timescale 1ns/1ps

module cga_splash_renderer_tb;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg enable = 1'b1;
    reg [4:0] clkdiv = 5'd0;
    reg display_enable = 1'b0;
    reg vblank = 1'b1;
    wire [3:0] pixel_index;
    wire [14:0] rom_addr;
    wire [7:0] rom_q;

    // Run from rtl/video so splash_rom finds splash_320x200.hex.
    cga_splash_renderer dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .clkdiv(clkdiv),
        .display_enable(display_enable),
        .vblank(vblank),
        .rom_addr(rom_addr),
        .rom_q(rom_q),
        .pixel_index(pixel_index)
    );

    splash_rom rom (
        .clk(clk),
        .addr_a(rom_addr),
        .q_a(rom_q),
        .addr_b(15'd0),
        .q_b()
    );

    reg [7:0] picture [0:31999];
    initial $readmemh("splash_320x200.hex", picture);

    function [3:0] expected;
        input integer line;
        input integer x;
        reg [7:0] b;
        begin
            b = picture[line * 160 + x / 2];
            expected = (x % 2) ? b[3:0] : b[7:4];
        end
    endfunction

    always #5 clk = ~clk;

    task tick;
        begin
            @(negedge clk);
            clkdiv = clkdiv + 1'b1;
            @(posedge clk);
        end
    endtask

    integer i;
    integer first_nonblack;
    integer row;
    integer active_pixels;
    integer mismatches;
    reg [3:0] first_pixel;
    reg [3:0] last_pixel;
    reg [3:0] previous_pixel;

    initial begin
        repeat (3) tick();
        reset = 1'b0;
        vblank = 1'b0;

        // Prefetch the first line during horizontal blank.
        repeat (8) tick();
        display_enable = 1'b1;

        first_pixel = 4'hx;
        last_pixel = 4'hx;
        previous_pixel = 4'hx;
        first_nonblack = -1;
        active_pixels = 0;
        mismatches = 0;
        // Run five complete rows and compare every source pixel with the
        // picture, while also checking that every line advances normally.
        for (row = 0; row < 5; row = row + 1) begin
            for (i = 0; i < 320 * 4; i = i + 1) begin
                tick();
                if (pixel_index !== expected(row, i / 4)) begin
                    if (mismatches < 8)
                        $display("FAIL: row %0d pixel %0d is %h, expected %h", row, i / 4, pixel_index, expected(row, i / 4));
                    mismatches = mismatches + 1;
                end
                // A source pixel is held for four master clocks.  This
                // catches a RAM output changing in the middle of a group,
                // which would appear as a thin vertical tear on hardware.
                if ((i % 4) != 0 && pixel_index !== previous_pixel) begin
                    $display("FAIL: pixel changed inside four-clock group at row %0d clock %0d", row, i);
                    $fatal(1);
                end
                previous_pixel = pixel_index;
                if (row == 0 && i == 0)
                    first_pixel = pixel_index;
                if (pixel_index != 4'h0 && first_nonblack < 0)
                    first_nonblack = active_pixels;
                if (row == 4)
                    last_pixel = pixel_index;
                active_pixels = active_pixels + 1;
            end
            display_enable = 1'b0;
            repeat (4) tick();
            if (row != 4)
                display_enable = 1'b1;
        end

        if (mismatches != 0)
            $fatal(1, "FAIL: %0d samples differ from the picture", mismatches);
        if (active_pixels != 5 * 1280)
            $fatal(1, "FAIL: wrong active sample count %0d", active_pixels);
        if (first_nonblack < 0)
            $fatal(1, "FAIL: splash stream remained black");
        if (dut.pixel_x !== 10'd0)
            $fatal(1, "FAIL: pixel_x did not reset in horizontal blank (%0d)", dut.pixel_x);
        if (dut.scanline !== 9'd5)
            $fatal(1, "FAIL: scanline did not advance (%0d)", dut.scanline);

        $display("PASS: CGA splash renderer emitted the picture's 320 pixels over 1280 clocks on 5 rows; first=%h last=%h", first_pixel, last_pixel);
        $finish;
    end

endmodule
