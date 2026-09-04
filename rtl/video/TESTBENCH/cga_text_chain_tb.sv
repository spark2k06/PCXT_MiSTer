`timescale 1ns/1ps

// Focused regression for the 8088 MPH 1K-colour path.  The demo uses
// 80-column text mode and magic character patterns, not mode 6 graphics.
module cga_text_chain_tb;
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
    reg [3:0] hsync_width = 4'd15;
    reg [3:0] border_color = 4'd0;
    reg phase = 1'b0;
    reg scandouble = 1'b0;
    wire [5:0] red;
    wire [5:0] green;
    wire [5:0] blue;

    always @(*) begin
        vram_read_char = (clk_seq == 5'd2) || (clk_seq == 5'd18);
        vram_read_att = (clk_seq == 5'd3) || (clk_seq == 5'd19);
        charrom_read = (clk_seq == 5'd3) || (clk_seq == 5'd19);
        disp_pipeline = (clk_seq == 5'd4) || (clk_seq == 5'd20);
        // 0x55 supplies 01010101; the low attribute nibble is white and the
        // high nibble is black, producing the alternating text waveform.
        vram_data = vram_read_char ? 8'h55 :
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

    cga_vgaport decoder (
        .clk(clk), .clkdiv(clk_seq), .video(video), .composite(composite),
        .hblank(hblank), .bw_mode(bw_mode), .hres_mode(hres_mode),
        .grph_mode(grph_mode), .hsync_width(hsync_width),
        .border_color(border_color), .phase(phase), .scandouble(scandouble),
        .red(red), .green(green), .blue(blue)
    );

    integer n;
    integer accepted;
    integer sample_file;
    initial begin
        // cga_pixel's production source uses a relative ROM path.  Reload it
        // explicitly here so this focused test is independent of the launch
        // directory used by the simulator.
        #1 $readmemh("rtl/video/cga.hex", pixel.char_rom, 0, 4095);
        sample_file = $fopen("rtl/video/TESTBENCH/cga_text_chain_samples.csv", "w");
        if (sample_file == 0)
            $fatal(1, "Unable to create text-mode sample file");
        $fwrite(sample_file, "sample,sampled_input,r,g,b\n");
        repeat (40) @(posedge clk);
        hblank = 1'b0;
        accepted = 0;
        for (n = 0; n < 192; n = n + 1) begin
            @(posedge clk);
            #1;
            if (!clk_seq[0]) begin
                $fwrite(sample_file, "%0d,%0d,%0d,%0d,%0d\n",
                        accepted, decoder.previous_video, red, green, blue);
                accepted = accepted + 1;
            end
        end
        $fclose(sample_file);
        $display("accepted=%0d", accepted);
        $finish;
    end
endmodule
