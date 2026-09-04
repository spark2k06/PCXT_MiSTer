`timescale 1ns/1ps

// Exercise the character patterns used by the 8088 MPH 1K-colour effects.
// The important property here is the emitted RGBI stream, not the literal
// character glyph: composite colour is recovered from transitions in that
// stream.
module cga_text_patterns_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg [4:0] clk_seq = 5'd0;
    always @(posedge clk)
        clk_seq <= clk_seq + 5'd1;

    reg hres_mode = 1'b1;
    reg grph_mode = 1'b0;
    reg bw_mode = 1'b0;
    reg mode_640 = 1'b0;
    reg tandy_16_mode = 1'b0;
    reg thin_font = 1'b0;
    reg [7:0] current_char = 8'h55;
    reg [7:0] vram_data;
    wire [3:0] video;
    reg display_enable = 1'b1;
    reg video_enabled = 1'b1;
    reg disp_pipeline;
    reg charrom_read;
    reg vram_read_char;
    reg vram_read_att;
    reg cursor = 1'b0;
    reg [4:0] row_addr = 5'd0;
    reg blink_enabled = 1'b0;
    reg blink = 1'b0;
    reg hsync = 1'b0;
    reg vsync = 1'b0;
    reg [7:0] cga_color_reg = 8'h00;
    reg [3:0] tandy_palette_color = 4'd0;
    reg [3:0] tandy_newcolor = 4'd0;
    reg tandy_palette_set = 1'b0;
    reg [3:0] tandy_bordercol = 4'd0;
    reg tandy_color_4 = 1'b0;
    reg tandy_color_16 = 1'b0;

    always @(*) begin
        vram_read_char = (clk_seq == 5'd2) || (clk_seq == 5'd18);
        vram_read_att = (clk_seq == 5'd3) || (clk_seq == 5'd19);
        charrom_read = (clk_seq == 5'd3) || (clk_seq == 5'd19);
        disp_pipeline = (clk_seq == 5'd4) || (clk_seq == 5'd20);
        vram_data = vram_read_char ? current_char :
                    vram_read_att ? 8'h0f : 8'h00;
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

    integer i;
    integer n;
    integer sample_file;
    reg [7:0] test_chars [0:4];

    initial begin
        test_chars[0] = 8'h13;
        test_chars[1] = 8'h55;
        test_chars[2] = 8'hb0;
        test_chars[3] = 8'hb1;
        test_chars[4] = 8'hb2;
        #1 $readmemh("rtl/video/cga.hex", pixel.char_rom, 0, 4095);
        sample_file = $fopen("rtl/video/TESTBENCH/cga_text_patterns_samples.csv", "w");
        if (sample_file == 0)
            $fatal(1, "Unable to create text-pattern sample file");
        $fwrite(sample_file, "char,cycle,clk_seq,video,pix,charbits\n");

        repeat (32) @(posedge clk);
        for (i = 0; i < 5; i = i + 1) begin
            current_char = test_chars[i];
            // Let the character and attribute fetch pipeline settle.
            repeat (32) @(posedge clk);
            for (n = 0; n < 64; n = n + 1) begin
                @(posedge clk);
                #1;
                $fwrite(sample_file, "%02x,%0d,%0d,%0d,%0d,%02x\n",
                        current_char, n, clk_seq, video, pixel.pix,
                        pixel.charbits);
            end
        end
        $fclose(sample_file);
        $finish;
    end
endmodule
