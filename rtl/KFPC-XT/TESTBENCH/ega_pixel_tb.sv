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
    reg  [1:0] render_mode = 2'd1;
    reg  [3:0] h_pixel_pan = 4'd0;
    wire [3:0] plane_index;
    wire       pixel_valid;
    wire [1:0] render_mode_debug;

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
        .render_mode(render_mode),
        .h_pixel_pan(h_pixel_pan),
        .plane_index(plane_index),
        .pixel_valid(pixel_valid),
        .render_mode_debug(render_mode_debug)
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

    function automatic [3:0] egaremap2bpp;
        input [7:0] value;
        begin
            egaremap2bpp = {value[6], value[4], value[2], value[0]};
        end
    endfunction

    task automatic cga2bpp_convert;
        input [7:0] edat0;
        input [7:0] edat1;
        input [7:0] edat2;
        input [7:0] edat3;
        output [7:0] dat0;
        output [7:0] dat1;
        output [7:0] dat2;
        output [7:0] dat3;
        begin
            dat0 = {egaremap2bpp(edat0), egaremap2bpp(edat1)};
            dat1 = {egaremap2bpp({1'b0, edat0[7:1]}), egaremap2bpp({1'b0, edat1[7:1]})};
            dat2 = {egaremap2bpp(edat2), egaremap2bpp(edat3)};
            dat3 = {egaremap2bpp({1'b0, edat2[7:1]}), egaremap2bpp({1'b0, edat3[7:1]})};
        end
    endtask

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

    task automatic expect_mode;
        input [1:0] expected;
        input [80*8-1:0] label;
        begin
            if (render_mode_debug !== expected) begin
                $display(
                    "FAIL %0s: render_mode=%0d expected=%0d",
                    label,
                    render_mode_debug,
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

    task automatic check_render_mode_selection;
        begin
            dot_clock_div2 = 1'b0;
            h_pixel_pan = 4'd0;
            display_enable = 1'b1;

            render_mode = 2'd0;
            load_planes(8'hff, 8'hff, 8'hff, 8'hff);
            expect_mode(2'd0, "text handoff mode");
            if (pixel_valid || plane_index !== 4'h0) begin
                $display(
                    "FAIL text handoff: valid=%0b pixel=%h expected blank",
                    pixel_valid,
                    plane_index
                );
                errors = errors + 1;
            end

            render_mode = 2'd1;
            load_planes(8'h80, 8'h00, 8'h00, 8'h00);
            expect_mode(2'd1, "planar graphics mode");
            expect_pixel(4'h1, 0);
            drain_pixels(7);

            render_mode = 2'd2;
            load_planes(8'h80, 8'h00, 8'h00, 8'h00);
            expect_mode(2'd2, "cga-compatible graphics mode");
            if (!pixel_valid) begin
                $display("FAIL cga-compatible graphics mode did not route to graphics path");
                errors = errors + 1;
            end
        end
    endtask

    task automatic check_cga2bpp_conversion;
        reg [7:0] edat0;
        reg [7:0] edat1;
        reg [7:0] edat2;
        reg [7:0] edat3;
        reg [7:0] dat0;
        reg [7:0] dat1;
        reg [7:0] dat2;
        reg [7:0] dat3;
        integer i;
        begin
            edat0 = 8'b11001001;
            edat1 = 8'b00110110;
            edat2 = 8'b10100101;
            edat3 = 8'b01011010;
            cga2bpp_convert(edat0, edat1, edat2, edat3, dat0, dat1, dat2, dat3);

            render_mode = 2'd2;
            dot_clock_div2 = 1'b0;
            h_pixel_pan = 4'd0;
            display_enable = 1'b1;

            load_planes(edat0, edat1, edat2, edat3);
            expect_pixel(planar_pixel(dat0, dat1, dat2, dat3, 0), 0);

            for (i = 1; i < 8; i = i + 1) begin
                @(posedge clk);
                #1;
                expect_pixel(planar_pixel(dat0, dat1, dat2, dat3, i), i);
            end

            render_mode = 2'd1;
        end
    endtask

    task automatic check_display_disable_gating;
        begin
            render_mode = 2'd1;
            dot_clock_div2 = 1'b0;
            h_pixel_pan = 4'd0;
            display_enable = 1'b1;

            load_planes(8'hFF, 8'h00, 8'h00, 8'h00);
            expect_pixel(4'h1, 0);

            display_enable = 1'b0;
            @(posedge clk);
            #1;
            if (pixel_valid || plane_index !== 4'h0) begin
                $display(
                    "FAIL display disable gating: valid=%0b pixel=%h expected blank",
                    pixel_valid,
                    plane_index
                );
                errors = errors + 1;
            end

            display_enable = 1'b1;
            load_planes(8'h80, 8'h00, 8'h00, 8'h00);
            expect_pixel(4'h1, 0);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);

        check_high_res_shift();
        repeat (2) @(posedge clk);
        check_low_res_repeat();
        repeat (2) @(posedge clk);
        check_panned_shift();
        repeat (2) @(posedge clk);
        check_render_mode_selection();
        repeat (2) @(posedge clk);
        check_cga2bpp_conversion();
        repeat (2) @(posedge clk);
        check_display_disable_gating();

        if (errors == 0) begin
            $display("PASS ega_pixel_tb");
        end else begin
            $display("FAIL ega_pixel_tb: %0d errors", errors);
            $fatal(1);
        end

        $finish;
    end
endmodule
