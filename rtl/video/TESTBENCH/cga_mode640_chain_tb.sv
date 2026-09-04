`timescale 1ns/1ps

module cga_mode640_chain_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg [4:0] clk_seq = 5'd0;
    always @(posedge clk)
        clk_seq <= clk_seq + 5'd1;

    reg hres_mode = 1'b0;
    reg grph_mode = 1'b1;
    reg bw_mode = 1'b0;
    reg mode_640 = 1'b1;
    reg tandy_16_mode = 1'b0;
    reg thin_font = 1'b0;
    reg [7:0] vram_data;
    wire [3:0] video;
    reg display_enable = 1'b1;
    reg video_enabled = 1'b1;
    reg disp_pipeline;
    reg charrom_read = 1'b0;
    reg vram_read_char;
    reg vram_read_att;
    reg cursor = 1'b0;
    reg [4:0] row_addr = 5'd0;
    reg blink_enabled = 1'b0;
    reg blink = 1'b0;
    reg hsync = 1'b0;
    reg vsync = 1'b0;
    reg [7:0] cga_color_reg = 8'h0f;
    reg [3:0] tandy_palette_color = 4'd0;
    reg [3:0] tandy_newcolor = 4'd0;
    reg tandy_palette_set = 1'b0;
    reg [3:0] tandy_bordercol = 4'd0;
    reg tandy_color_4 = 1'b0;
    reg tandy_color_16 = 1'b0;

    reg composite = 1'b1;
    reg hblank = 1'b1;
    reg [3:0] hsync_width = 4'd10;
    reg [3:0] border_color = 4'd0;
    reg phase = 1'b0;
    reg scandouble = 1'b0;
    wire [5:0] red;
    wire [5:0] green;
    wire [5:0] blue;

    always @(*) begin
        vram_read_char = (clk_seq == 5'd2);
        vram_read_att = (clk_seq == 5'd3);
        disp_pipeline = (clk_seq == 5'd4) || (clk_seq == 5'd20);
        vram_data = (clk_seq == 5'd2) ? 8'haa :
                    (clk_seq == 5'd3) ? 8'h55 : 8'h00;
    end

    cga_pixel pixel (
        .clk(clk), .clk_seq(clk_seq), .hres_mode(hres_mode),
        .grph_mode(grph_mode), .bw_mode(bw_mode), .mode_640(mode_640),
        .tandy_16_mode(tandy_16_mode), .thin_font(thin_font),
        .vram_data(vram_data), .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att), .disp_pipeline(disp_pipeline),
        .charrom_read(charrom_read), .display_enable(display_enable),
        .cursor(cursor), .row_addr(row_addr), .blink_enabled(blink_enabled),
        .blink(blink), .hsync(hsync), .vsync(vsync),
        .video_enabled(video_enabled), .cga_color_reg(cga_color_reg),
        .tandy_palette_color(tandy_palette_color),
        .tandy_newcolor(tandy_newcolor), .tandy_palette_set(tandy_palette_set),
        .tandy_bordercol(tandy_bordercol), .tandy_color_4(tandy_color_4),
        .tandy_color_16(tandy_color_16), .video(video)
    );

    cga_vgaport decoder (
        .clk(clk), .clkdiv(clk_seq), .video(video), .composite(composite),
        .hblank(hblank), .bw_mode(bw_mode), .hres_mode(hres_mode),
        .grph_mode(grph_mode), .hsync_width(hsync_width),
        .border_color(border_color), .phase(phase), .scandouble(scandouble),
        .red(red), .green(green), .blue(blue)
    );

    integer n;
    integer accepted;
    reg [3:0] previous_video;
    integer sample_file;
    initial begin
        previous_video = 4'h0;
        accepted = 0;
        sample_file = $fopen("rtl/video/TESTBENCH/cga_mode640_chain_samples.csv", "w");
        if (sample_file == 0)
            $fatal(1, "Unable to create native mode-6 sample file");
        $fwrite(sample_file, "sample,sampled_input,r,g,b\n");
        repeat (40) @(posedge clk);
        hblank = 1'b0;
        for (n = 0; n < 160; n = n + 1) begin
            @(posedge clk);
            #1;
            // After the nonblocking sequencer update, clk_seq is the next
            // value. The decoder accepted the preceding odd phase.
            if (!clk_seq[0]) begin
                // The decoder samples video on the pre-NBA clock value;
                // previous_video is the value it has just accepted.
                $fwrite(sample_file, "%0d,%0d,%0d,%0d,%0d\n",
                        accepted, decoder.previous_video, red, green, blue);
                if (video !== previous_video)
                    $display("sample %0d video=%h RGB=%0d,%0d,%0d seq=%0d pix640=%b",
                             accepted, video, red, green, blue, clk_seq,
                             pixel.pix_640);
                previous_video = video;
                accepted = accepted + 1;
            end
        end
        $display("accepted=%0d", accepted);
        $fclose(sample_file);
        $finish;
    end
endmodule
