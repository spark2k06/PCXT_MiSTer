`timescale 1ns / 1ps

module mcga_mode13_renderer_tb;

    reg         clock = 1'b0;
    reg         reset = 1'b1;
    reg         enable = 1'b0;
    wire [15:0] framebuffer_addr;
    wire        framebuffer_read_en;
    wire [7:0]  framebuffer_pixel;
    wire        framebuffer_data_valid;
    wire [7:0]  dac_index;
    wire [5:0]  dac_red;
    wire [5:0]  dac_green;
    wire [5:0]  dac_blue;
    wire [5:0]  red;
    wire [5:0]  green;
    wire [5:0]  blue;
    wire        de;
    wire        hsync;
    wire        vsync;
    wire        hblank;
    wire        vblank;

    reg [15:0] cpu_addr = 16'h0000;
    reg [7:0]  cpu_din = 8'h00;
    reg        cpu_read = 1'b0;
    reg        cpu_write = 1'b0;
    wire [7:0] cpu_dout;
    wire       cpu_ready;

    reg        dac_write_en = 1'b0;
    reg [7:0]  dac_write_index = 8'h00;
    reg [5:0]  dac_write_red = 6'h00;
    reg [5:0]  dac_write_green = 6'h00;
    reg [5:0]  dac_write_blue = 6'h00;

    integer failures = 0;
    integer i;
    integer visible_seen = 0;

    mcga_framebuffer framebuffer (
        .clk_cpu            (clock),
        .reset_cpu          (reset),
        .cpu_addr           (cpu_addr),
        .cpu_din            (cpu_din),
        .cpu_read           (cpu_read),
        .cpu_write          (cpu_write),
        .cpu_dout           (cpu_dout),
        .cpu_ready          (cpu_ready),
        .clk_video          (clock),
        .video_addr         (framebuffer_addr),
        .video_read_en      (framebuffer_read_en),
        .video_pixel        (framebuffer_pixel),
        .video_data_valid   (framebuffer_data_valid)
    );

    mcga_dac dac (
        .clock                  (clock),
        .reset                  (reset),
        .reset_palette          (1'b0),
        .write_en               (dac_write_en),
        .write_index            (dac_write_index),
        .write_red              (dac_write_red),
        .write_green            (dac_write_green),
        .write_blue             (dac_write_blue),
        .component_write_en     (1'b0),
        .component_write_index  (8'h00),
        .component_select       (2'd0),
        .component_data         (6'h00),
        .sample_index           (dac_index),
        .sample_red             (dac_red),
        .sample_green           (dac_green),
        .sample_blue            (dac_blue),
        .sample_red_8           (),
        .sample_green_8         (),
        .sample_blue_8          (),
        .port_index             (8'h00),
        .port_red               (),
        .port_green             (),
        .port_blue              ()
    );

    mcga_mode13_renderer renderer (
        .clock                  (clock),
        .reset                  (reset),
        .enable                 (enable),
        .framebuffer_addr       (framebuffer_addr),
        .framebuffer_read_en    (framebuffer_read_en),
        .framebuffer_pixel      (framebuffer_pixel),
        .framebuffer_data_valid (framebuffer_data_valid),
        .dac_index              (dac_index),
        .dac_red                (dac_red),
        .dac_green              (dac_green),
        .dac_blue               (dac_blue),
        .red                    (red),
        .green                  (green),
        .blue                   (blue),
        .de                     (de),
        .hsync                  (hsync),
        .vsync                  (vsync),
        .hblank                 (hblank),
        .vblank                 (vblank)
    );

    always #5 clock = ~clock;

    task write_framebuffer;
        input [15:0] addr;
        input [7:0] data;
        begin
            cpu_addr = addr;
            cpu_din = data;
            cpu_write = 1'b1;
            @(posedge clock);
            #1;
            cpu_write = 1'b0;
        end
    endtask

    task write_dac;
        input [7:0] index;
        input [5:0] r;
        input [5:0] g;
        input [5:0] b;
        begin
            dac_write_index = index;
            dac_write_red = r;
            dac_write_green = g;
            dac_write_blue = b;
            dac_write_en = 1'b1;
            @(posedge clock);
            #1;
            dac_write_en = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clock);
        reset = 1'b0;
        #1;

        write_framebuffer(16'h0000, 8'h2A);
        write_framebuffer(16'h0001, 8'h33);
        write_dac(8'h2A, 6'h01, 6'h23, 6'h3F);
        write_dac(8'h33, 6'h3E, 6'h05, 6'h10);

        enable = 1'b1;
        for (i = 0; i < 32 && visible_seen < 4; i = i + 1) begin
            @(posedge clock);
            #1;
            if (de) begin
                visible_seen = visible_seen + 1;
                if (visible_seen <= 2) begin
                    if (dac_index !== 8'h2A || red !== 6'h01 || green !== 6'h23 || blue !== 6'h3F) begin
                        $display("FAIL duplicated first packed pixel expected index/rgb=2a/01/23/3f actual=%02h/%02h/%02h/%02h",
                                 dac_index, red, green, blue);
                        failures = failures + 1;
                    end
                end else begin
                    if (dac_index !== 8'h33 || red !== 6'h3E || green !== 6'h05 || blue !== 6'h10) begin
                        $display("FAIL duplicated second packed pixel expected index/rgb=33/3e/05/10 actual=%02h/%02h/%02h/%02h",
                                 dac_index, red, green, blue);
                        failures = failures + 1;
                    end
                end
            end
        end

        if (visible_seen < 4) begin
            $display("FAIL renderer produced only %0d visible startup pixels", visible_seen);
            failures = failures + 1;
        end

        if (hblank || vblank) begin
            $display("FAIL visible pixels should not be blanked");
            failures = failures + 1;
        end

        if (failures == 0) begin
            $display("PASS mcga_mode13_renderer_tb");
            $finish;
        end

        $display("FAIL mcga_mode13_renderer_tb failures=%0d", failures);
        $finish;
    end

endmodule
