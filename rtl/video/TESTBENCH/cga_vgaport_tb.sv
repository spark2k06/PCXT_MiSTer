`timescale 1ns/1ps

module cga_vgaport_tb;
    localparam integer ACTIVE_PIXELS = 512;

    reg        clk = 1'b0;
    reg  [4:0] clkdiv = 5'd0;
    reg  [3:0] video = 4'd0;
    reg        composite = 1'b0;
    reg        hblank = 1'b1;
    reg        bw_mode = 1'b0;
    reg        hres_mode = 1'b0;
    reg        grph_mode = 1'b1;
    reg  [3:0] hsync_width = 4'd10;
    reg  [3:0] border_color = 4'd0;
    reg        phase = 1'b0;
    // Most cases use the scan-doubled input convention.  The native 640-dot
    // graphics cases below deliberately exercise the 28.6 MHz mode-6 path.
    reg        scandouble = 1'b1;

    wire [5:0] red;
    wire [5:0] green;
    wire [5:0] blue;

    integer sample_file;
    integer x;

    always #5 clk = ~clk;
    always @(posedge clk)
        clkdiv <= clkdiv + 5'd1;

    cga_vgaport dut (
        .clk(clk),
        .clkdiv(clkdiv),
        .video(video),
        .composite(composite),
        .hblank(hblank),
        .bw_mode(bw_mode),
        .hres_mode(hres_mode),
        .grph_mode(grph_mode),
        .hsync_width(hsync_width),
        .border_color(border_color),
        .phase(phase),
        .scandouble(scandouble),
        .red(red),
        .green(green),
        .blue(blue)
    );

    function automatic [3:0] stimulus_pixel;
        input integer position;
        integer section;
        begin
            if ((position < 32) || (position >= 480)) begin
                stimulus_pixel = 4'h0;
            end
            else if (position < 160) begin
                // Four artifact-color frequencies and phases.
                section = (position - 32) >> 5;
                case (section)
                    0: stimulus_pixel = position[0] ? 4'hF : 4'h0;
                    1: stimulus_pixel = position[1] ? 4'hF : 4'h0;
                    2: stimulus_pixel = position[0] ? 4'h6 : 4'h1;
                    default: stimulus_pixel = position[1:0];
                endcase
            end
            else if (position < 288) begin
                // Transition-rich pseudo-gradient, similar to the patterns
                // exploited by the 8088 MPH burst calibration screen.
                case ((position - 160) & 7)
                    0: stimulus_pixel = 4'h0;
                    1: stimulus_pixel = 4'h1;
                    2: stimulus_pixel = 4'h8;
                    3: stimulus_pixel = 4'h9;
                    4: stimulus_pixel = 4'hF;
                    5: stimulus_pixel = 4'hE;
                    6: stimulus_pixel = 4'h7;
                    default: stimulus_pixel = 4'h6;
                endcase
            end
            else if (position < 416) begin
                // All sixteen direct RGBI values.
                stimulus_pixel = (position - 288) >> 3;
            end
            else begin
                stimulus_pixel = ((position * 5) ^ (position >> 2)) & 15;
            end
        end
    endfunction

    task automatic run_case;
        input case_bw;
        input case_hres;
        input case_grph;
        input [3:0] case_hsync_width;
        input [3:0] case_border_color;
        input       case_phase;
        integer blank_count;
        begin
            // Direct mode clears all streaming history.
            composite = 1'b0;
            hblank = 1'b1;
            video = 4'h0;
            bw_mode = case_bw;
            hres_mode = case_hres;
            grph_mode = case_grph;
            // This bench supplies one logical source sample per iteration;
            // keep the decoder in the scan-doubled-input convention for all
            // synthetic cases.  Native mode-6 bit timing is covered by the
            // cga_pixel-focused regression.
            scandouble = 1'b1;
            hsync_width = case_hsync_width;
            border_color = case_border_color;
            phase = case_phase;
            repeat (2) @(posedge clk);

            composite = 1'b1;
            for (blank_count = 0; blank_count < 20; blank_count = blank_count + 1) begin
                @(negedge clk);
                hblank = 1'b1;
                // The analogue line is primed by the programmed border while
                // blanked; exercise that context instead of forcing black.
                video = case_border_color;
            end

            for (x = 0; x < ACTIVE_PIXELS; x = x + 1) begin
                @(negedge clk);
                hblank = 1'b0;
                video = stimulus_pixel(x);
                @(posedge clk);
                #1;
                $fwrite(sample_file, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                        case_bw, case_hres, case_grph,
                        case_hsync_width, case_border_color, case_phase,
                        x, video, red, green, blue);
            end

            @(negedge clk);
            hblank = 1'b1;
            video = 4'h0;
            repeat (12) @(posedge clk);
        end
    endtask

    initial begin
        sample_file = $fopen("rtl/video/TESTBENCH/cga_vgaport_samples.csv", "w");
        if (sample_file == 0)
            $fatal(1, "Unable to create composite sample file");
        $fwrite(sample_file, "bw,hres,grph,hsync_width,border,phase,x,input,r,g,b\n");

        // Sanity-check that the untouched RGBI path retains its channel order.
        @(negedge clk);
        composite = 1'b0;
        video = 4'h1;
        @(posedge clk);
        #1;
        if ((red !== 6'd0) || (green !== 6'd0) || (blue !== 6'd42))
            $fatal(1, "RGBI bypass channel order is incorrect");

        run_case(1'b0, 1'b0, 1'b1, 4'd10, 4'd0, 1'b0);
        run_case(1'b1, 1'b0, 1'b1, 4'd10, 4'd0, 1'b0);

        // The CGA identification card uses the normal 40-column phase.
        run_case(1'b0, 1'b0, 1'b0, 4'd10, 4'd0, 1'b0);

        // 640-dot (1K-colour) graphics uses the high-resolution carrier
        // phase too, but does not apply the 80-column burst truncation.
        run_case(1'b0, 1'b1, 1'b1, 4'd10, 4'd0, 1'b0);
        run_case(1'b0, 1'b1, 1'b1, 4'd10, 4'd0, 1'b1);

        // BIOS/MS-DOS boot text: 80-column text with color burst enabled.
        run_case(1'b0, 1'b1, 1'b0, 4'd15, 4'd0, 1'b0);

        // Before the calibrated [E,1] point the real monitor is monochrome,
        // but the luminance ramps must remain present.
        run_case(1'b0, 1'b1, 1'b0, 4'd10, 4'd0, 1'b0);
        run_case(1'b0, 1'b1, 1'b0, 4'd13, 4'd0, 1'b1);
        run_case(1'b0, 1'b1, 1'b0, 4'd14, 4'd0, 1'b0);

        // Calibration phase 1 turns the E-width (14) setting into the first
        // full colour burst and rotates the hue.
        run_case(1'b0, 1'b1, 1'b0, 4'd14, 4'd0, 1'b1);

        // A non-black border also leaves a usable burst in 80-column mode.
        run_case(1'b0, 1'b1, 1'b0, 4'd10, 4'd1, 1'b0);

        $fclose(sample_file);
        $display("PASS: generated old-CGA color and monochrome samples");
        $finish;
    end
endmodule
