`timescale 1ns/1ps

// Exercise the actual 8088 MPH 1K text pattern rather than a repeated test
// character. The public demo source uses 80-column text with characters
// 55h/13h/B0h/B1h and an attribute byte that walks through 00h..FFh.
module cga_1k_chain_tb;
    parameter integer DECODE_OFFSET = 0;
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

    reg composite = 1'b1;
    reg hblank = 1'b1;
    reg [3:0] hsync_width = 4'd14;
    reg [3:0] border_color = 4'd0;
    reg phase = 1'b1;
    reg scandouble = 1'b0;
    wire [5:0] red;
    wire [5:0] green;
    wire [5:0] blue;

    reg [10:0] active_cycle = 11'd0;
    reg [7:0] current_line = 8'd0;
    integer group_index;
    integer char_slot;
    integer pair_index;
    integer attr_index;
    integer pattern_index;
    always @(posedge clk) begin
        if (hblank)
            active_cycle <= 11'd0;
        else if (active_cycle == 11'd1279)
            active_cycle <= 11'd0;
        else
            active_cycle <= active_cycle + 11'd1;
    end

    always @(*) begin
        char_slot = 0;
        pair_index = 0;
        attr_index = 0;
        pattern_index = 0;
        vram_read_char = (clk_seq == 5'd2) || (clk_seq == 5'd18);
        vram_read_att = (clk_seq == 5'd3) || (clk_seq == 5'd19);
        charrom_read = (clk_seq == 5'd3) || (clk_seq == 5'd19);
        disp_pipeline = (clk_seq == 5'd4) || (clk_seq == 5'd20);

        // The source builds each raster as one blank word, then 26 groups of
        // three identical characters with attributes i..i+25, and one blank
        // word. Every two raster lines advance i by 26; the character changes
        // at 256/512/768 in the 1024-byte cycle.
        char_slot = active_cycle / 16;
        pair_index = current_line / 2;
        group_index = (char_slot - 1) / 3;
        attr_index = (pair_index * 26) + group_index;
        pattern_index = (pair_index * 26) & 1023;

        if (hblank || char_slot == 0 || char_slot == 79) begin
            vram_data = 8'h00;
        end
        else begin
            if (pattern_index < 256)
                vram_data = vram_read_char ? 8'h55 :
                            vram_read_att ? attr_index[7:0] : 8'h00;
            else if (pattern_index < 512)
                vram_data = vram_read_char ? 8'h13 :
                            vram_read_att ? attr_index[7:0] : 8'h00;
            else if (pattern_index < 768)
                vram_data = vram_read_char ? 8'hb0 :
                            vram_read_att ? attr_index[7:0] : 8'h00;
            else
                vram_data = vram_read_char ? 8'hb1 :
                            vram_read_att ? attr_index[7:0] : 8'h00;
        end
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

    cga_vgaport #(.PHASE_OFFSET(DECODE_OFFSET)) decoder (
        .clk(clk), .clkdiv(clk_seq), .video(video), .composite(composite),
        .hblank(hblank), .bw_mode(bw_mode), .hres_mode(hres_mode),
        .grph_mode(grph_mode), .hsync_width(hsync_width),
        .border_color(border_color), .phase(phase), .scandouble(scandouble),
        .red(red), .green(green), .blue(blue)
    );

    integer n;
    integer line;
    integer accepted;
    integer sample_file;
    initial begin
        if ($test$plusargs("phase0"))
            phase = 1'b0;
        #1 $readmemh("rtl/video/cga.hex", pixel.char_rom, 0, 4095);
        sample_file = $fopen("rtl/video/TESTBENCH/cga_1k_chain_samples.csv", "w");
        if (sample_file == 0)
            $fatal(1, "Unable to create 1K sample file");
        $fwrite(sample_file, "line,sample,clk_seq,video,charbits,r,g,b\n");

        repeat (40) @(posedge clk);
        accepted = 0;
        for (line = 0; line < 100; line = line + 1) begin
            current_line = line;
            active_cycle = 11'd0;
            hblank = 1'b0;
            for (n = 0; n < 1280; n = n + 1) begin
                @(posedge clk);
                #1;
                if (!clk_seq[0]) begin
                    $fwrite(sample_file, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                            line, accepted, clk_seq, decoder.previous_video,
                            pixel.charbits, red, green, blue);
                    accepted = accepted + 1;
                end
            end
            hblank = 1'b1;
            repeat (32) @(posedge clk);
        end
        $fclose(sample_file);
        $display("accepted=%0d", accepted);
        $finish;
    end
endmodule
