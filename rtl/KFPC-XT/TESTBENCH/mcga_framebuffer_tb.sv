`timescale 1ns / 1ps

module mcga_framebuffer_tb;
    reg clk_cpu = 1'b0;
    reg clk_video = 1'b0;
    reg reset_cpu = 1'b1;
    reg [15:0] cpu_addr = 16'h0000;
    reg [7:0] cpu_din = 8'h00;
    reg cpu_read = 1'b0;
    reg cpu_write = 1'b0;
    wire [7:0] cpu_dout;
    wire cpu_ready;
    reg [15:0] video_addr = 16'h0000;
    reg video_read_en = 1'b0;
    wire [7:0] video_pixel;
    wire video_data_valid;

    integer errors = 0;
    integer i;

    mcga_framebuffer dut (
        .clk_cpu(clk_cpu),
        .reset_cpu(reset_cpu),
        .cpu_addr(cpu_addr),
        .cpu_din(cpu_din),
        .cpu_read(cpu_read),
        .cpu_write(cpu_write),
        .cpu_dout(cpu_dout),
        .cpu_ready(cpu_ready),
        .clk_video(clk_video),
        .video_addr(video_addr),
        .video_read_en(video_read_en),
        .video_pixel(video_pixel),
        .video_data_valid(video_data_valid)
    );

    always #5 clk_cpu = ~clk_cpu;
    always #7 clk_video = ~clk_video;

    function automatic [7:0] pattern;
        input [15:0] addr;
        begin
            pattern = addr[7:0] ^ addr[15:8] ^ 8'hA5;
        end
    endfunction

    task automatic expect8;
        input [191:0] name;
        input [7:0] actual;
        input [7:0] expected;
        begin
            if (actual !== expected) begin
                $display("FAIL %0s: expected=%02x actual=%02x", name, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task automatic expect1;
        input [191:0] name;
        input actual;
        input expected;
        begin
            if (actual !== expected) begin
                $display("FAIL %0s: expected=%0b actual=%0b", name, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task automatic cpu_write_byte;
        input [15:0] addr;
        input [7:0] data;
        begin
            @(negedge clk_cpu);
            cpu_addr = addr;
            cpu_din = data;
            cpu_write = 1'b1;
            cpu_read = 1'b0;
            @(negedge clk_cpu);
            expect1("cpu write ready", cpu_ready, 1'b1);
            cpu_write = 1'b0;
        end
    endtask

    task automatic cpu_read_byte;
        input [15:0] addr;
        input [7:0] expected;
        begin
            @(negedge clk_cpu);
            cpu_addr = addr;
            cpu_write = 1'b0;
            cpu_read = 1'b1;
            @(negedge clk_cpu);
            expect1("cpu read ready", cpu_ready, 1'b1);
            expect8("cpu read data", cpu_dout, expected);
            cpu_read = 1'b0;
        end
    endtask

    task automatic video_read_byte;
        input [15:0] addr;
        input [7:0] expected;
        begin
            @(negedge clk_video);
            video_addr = addr;
            video_read_en = 1'b1;
            @(negedge clk_video);
            expect1("video data valid", video_data_valid, 1'b1);
            expect8("video read data", video_pixel, expected);
            video_read_en = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk_cpu);
        reset_cpu = 1'b0;

        for (i = 0; i < 65536; i = i + 1)
            cpu_write_byte(i[15:0], pattern(i[15:0]));

        for (i = 0; i < 65536; i = i + 1)
            cpu_read_byte(i[15:0], pattern(i[15:0]));

        video_read_byte(16'h0000, pattern(16'h0000));
        video_read_byte(16'h013F, pattern(16'h013F));
        video_read_byte(16'hF9FF, pattern(16'hF9FF));
        video_read_byte(16'hFA00, pattern(16'hFA00));
        video_read_byte(16'hFFFF, pattern(16'hFFFF));

        cpu_write_byte(16'h1234, 8'h5A);
        cpu_read_byte(16'h1234, 8'h5A);
        video_read_byte(16'h1234, 8'h5A);

        if (errors == 0)
            $display("PASS mcga_framebuffer_tb");
        else
            $display("FAIL mcga_framebuffer_tb: %0d errors", errors);
        $finish;
    end
endmodule
