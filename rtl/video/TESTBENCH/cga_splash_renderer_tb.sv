`timescale 1ns/1ps

module cga_splash_renderer_tb;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg enable = 1'b1;
    reg [4:0] clkdiv = 5'd0;
    reg display_enable = 1'b0;
    reg vblank = 1'b1;
    reg composite = 1'b0;
    wire [3:0] pixel_index;

    cga_splash_renderer dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .clkdiv(clkdiv),
        .display_enable(display_enable),
        .vblank(vblank),
        .composite(composite),
        .pixel_index(pixel_index)
    );

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
        // The artwork intentionally has a black top margin.  Run five
        // complete rows so the check covers both that margin and visible
        // artwork, while also checking that every line advances normally.
        for (row = 0; row < 5; row = row + 1) begin
            for (i = 0; i < 320 * 4; i = i + 1) begin
                tick();
                if (pixel_index !== 4'h0 && pixel_index !== 4'hC &&
                    pixel_index !== 4'hA && pixel_index !== 4'hE) begin
                    $display("FAIL: unexpected CGA index %h at row %0d clock %0d", pixel_index, row, i);
                    $fatal(1);
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

        if (active_pixels != 5 * 1280)
            $fatal(1, "FAIL: wrong active sample count %0d", active_pixels);
        if (first_nonblack < 0)
            $fatal(1, "FAIL: splash stream remained black");
        if (dut.pixel_x !== 10'd0)
            $fatal(1, "FAIL: pixel_x did not reset in horizontal blank (%0d)", dut.pixel_x);
        if (dut.scanline !== 9'd5)
            $fatal(1, "FAIL: scanline did not advance (%0d)", dut.scanline);

        $display("PASS: CGA splash renderer emitted 320 pixels over 1280 clocks; first=%h last=%h", first_pixel, last_pixel);
        $finish;
    end

endmodule
