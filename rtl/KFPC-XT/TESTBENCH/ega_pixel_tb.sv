`timescale 1ns / 1ps

module ega_pixel_tb;
    reg        clk = 1'b0;
    reg        ce_pix = 1'b1;
    reg  [7:0] plane0_data = 8'h00;
    reg  [7:0] plane1_data = 8'h00;
    reg  [7:0] plane2_data = 8'h00;
    reg  [7:0] plane3_data = 8'h00;
    reg        fetch_en = 1'b0;
    reg        dot_clock_div2 = 1'b0;
    reg        display_enable = 1'b1;
    reg  [3:0] h_pixel_pan = 4'd0;
    wire [3:0] plane_index;
    wire       pixel_valid;

    integer errors = 0;

    ega_pixel dut (
        .clk(clk),
        .ce_pix(ce_pix),
        .plane0_data(plane0_data),
        .plane1_data(plane1_data),
        .plane2_data(plane2_data),
        .plane3_data(plane3_data),
        .fetch_en(fetch_en),
        .dot_clock_div2(dot_clock_div2),
        .display_enable(display_enable),
        .h_pixel_pan(h_pixel_pan),
        .plane_index(plane_index),
        .pixel_valid(pixel_valid)
    );

    always #5 clk = ~clk;

    function automatic [3:0] planar_pixel;
        input [7:0] plane0;
        input [7:0] plane1;
        input [7:0] plane2;
        input [7:0] plane3;
        input integer pixel;
        begin
            planar_pixel = {
                plane3[7 - pixel],
                plane2[7 - pixel],
                plane1[7 - pixel],
                plane0[7 - pixel]
            };
        end
    endfunction

    function automatic [7:0] panned_byte;
        input [7:0] previous_byte;
        input [7:0] current_byte;
        input [3:0] pan;
        reg [15:0] shifted;
        begin
            shifted = {previous_byte, current_byte} << pan;
            panned_byte = (pan == 4'd0) ? current_byte : shifted[15:8];
        end
    endfunction

    task automatic expect_pixel;
        input [3:0] expected;
        input integer sample;
        begin
            if (!pixel_valid || plane_index !== expected) begin
                $display(
                    "FAIL sample %0d: valid=%0b pixel=%h expected=%h",
                    sample,
                    pixel_valid,
                    plane_index,
                    expected
                );
                errors = errors + 1;
            end
        end
    endtask

    task automatic drain_pixels;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    task automatic load_planes;
        input [7:0] plane0;
        input [7:0] plane1;
        input [7:0] plane2;
        input [7:0] plane3;
        begin
            plane0_data = plane0;
            plane1_data = plane1;
            plane2_data = plane2;
            plane3_data = plane3;
            fetch_en = 1'b1;
            @(posedge clk);
            #1;
            fetch_en = 1'b0;
        end
    endtask

    task automatic check_high_res_shift;
        reg [7:0] p0;
        reg [7:0] p1;
        reg [7:0] p2;
        reg [7:0] p3;
        integer i;
        begin
            p0 = 8'b10101010;
            p1 = 8'b11001100;
            p2 = 8'b11110000;
            p3 = 8'b00001111;

            dot_clock_div2 = 1'b0;
            h_pixel_pan = 4'd0;
            load_planes(p0, p1, p2, p3);
            expect_pixel(planar_pixel(p0, p1, p2, p3, 0), 0);

            for (i = 1; i < 8; i = i + 1) begin
                @(posedge clk);
                #1;
                expect_pixel(planar_pixel(p0, p1, p2, p3, i), i);
            end
        end
    endtask

    task automatic check_low_res_repeat;
        reg [7:0] p0;
        reg [7:0] p1;
        reg [7:0] p2;
        reg [7:0] p3;
        integer i;
        begin
            p0 = 8'b10011001;
            p1 = 8'b01010101;
            p2 = 8'b00111100;
            p3 = 8'b00001111;

            dot_clock_div2 = 1'b1;
            h_pixel_pan = 4'd0;
            load_planes(p0, p1, p2, p3);
            expect_pixel(planar_pixel(p0, p1, p2, p3, 0), 0);

            for (i = 1; i < 16; i = i + 1) begin
                @(posedge clk);
                #1;
                expect_pixel(planar_pixel(p0, p1, p2, p3, i / 2), i);
            end
        end
    endtask

    task automatic check_panned_shift;
        reg [7:0] prev0;
        reg [7:0] prev1;
        reg [7:0] prev2;
        reg [7:0] prev3;
        reg [7:0] curr0;
        reg [7:0] curr1;
        reg [7:0] curr2;
        reg [7:0] curr3;
        reg [7:0] pan0;
        reg [7:0] pan1;
        reg [7:0] pan2;
        reg [7:0] pan3;
        integer i;
        begin
            prev0 = 8'b11110000;
            prev1 = 8'b00111100;
            prev2 = 8'b10101010;
            prev3 = 8'b01010101;
            curr0 = 8'b00001111;
            curr1 = 8'b11000011;
            curr2 = 8'b01010101;
            curr3 = 8'b10101010;

            dot_clock_div2 = 1'b0;
            h_pixel_pan = 4'd3;
            display_enable = 1'b0;
            @(posedge clk);
            #1;
            display_enable = 1'b1;

            load_planes(prev0, prev1, prev2, prev3);
            drain_pixels(7);

            pan0 = panned_byte(prev0, curr0, 4'd3);
            pan1 = panned_byte(prev1, curr1, 4'd3);
            pan2 = panned_byte(prev2, curr2, 4'd3);
            pan3 = panned_byte(prev3, curr3, 4'd3);

            load_planes(curr0, curr1, curr2, curr3);
            expect_pixel(planar_pixel(pan0, pan1, pan2, pan3, 0), 0);

            for (i = 1; i < 8; i = i + 1) begin
                @(posedge clk);
                #1;
                expect_pixel(planar_pixel(pan0, pan1, pan2, pan3, i), i);
            end

            display_enable = 1'b0;
            h_pixel_pan = 4'd0;
            @(posedge clk);
            #1;
            display_enable = 1'b1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);

        check_high_res_shift();
        repeat (2) @(posedge clk);
        check_low_res_repeat();
        repeat (2) @(posedge clk);
        check_panned_shift();

        if (errors == 0) begin
            $display("PASS ega_pixel_tb");
        end else begin
            $display("FAIL ega_pixel_tb: %0d errors", errors);
            $fatal(1);
        end

        $finish;
    end
endmodule
