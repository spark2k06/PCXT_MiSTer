`timescale 1ns / 1ps

module mcga_mode13_address_tb;

    reg  [9:0] pixel_x = 10'd0;
    reg  [9:0] pixel_y = 10'd0;
    wire [15:0] framebuffer_addr;
    wire        render_en;

    integer failures = 0;

    mcga_mode13_address dut (
        .pixel_x            (pixel_x),
        .pixel_y            (pixel_y),
        .framebuffer_addr   (framebuffer_addr),
        .render_en          (render_en)
    );

    task check_pixel;
        input [9:0] x;
        input [9:0] y;
        input [15:0] expected_addr;
        input expected_render;
        begin
            pixel_x = x;
            pixel_y = y;
            #1;
            if (framebuffer_addr !== expected_addr) begin
                $display("FAIL addr x=%0d y=%0d expected=%04h actual=%04h",
                         x, y, expected_addr, framebuffer_addr);
                failures = failures + 1;
            end
            if (render_en !== expected_render) begin
                $display("FAIL render x=%0d y=%0d expected=%0d actual=%0d",
                         x, y, expected_render, render_en);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        check_pixel(10'd0,   10'd0,   16'h0000, 1'b1);
        check_pixel(10'd1,   10'd0,   16'h0001, 1'b1);
        check_pixel(10'd319, 10'd0,   16'h013F, 1'b1);
        check_pixel(10'd0,   10'd1,   16'h0140, 1'b1);
        check_pixel(10'd10,  10'd10,  16'h0C8A, 1'b1);
        check_pixel(10'd319, 10'd199, 16'hF9FF, 1'b1);

        check_pixel(10'd320, 10'd199, 16'hFA00, 1'b0);
        check_pixel(10'd0,   10'd200, 16'hFA00, 1'b0);
        check_pixel(10'd319, 10'd200, 16'hFB3F, 1'b0);
        check_pixel(10'd400, 10'd200, 16'hFB90, 1'b0);

        if (failures == 0) begin
            $display("PASS mcga_mode13_address_tb");
            $finish;
        end

        $display("FAIL mcga_mode13_address_tb failures=%0d", failures);
        $finish;
    end

endmodule
