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

    initial begin
        repeat (2) @(posedge clk);

        check_high_res_shift();
        repeat (2) @(posedge clk);
        check_low_res_repeat();

        if (errors == 0) begin
            $display("PASS ega_pixel_tb");
        end else begin
            $display("FAIL ega_pixel_tb: %0d errors", errors);
            $fatal(1);
        end

        $finish;
    end
endmodule
