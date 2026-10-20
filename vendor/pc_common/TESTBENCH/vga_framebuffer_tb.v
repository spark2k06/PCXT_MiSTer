//============================================================================
//
//  The mode 13h framebuffer contract, so the memory can be restructured for
//  the Fitter without changing what the CPU and the raster see.
//
//  The 64 KiB packed framebuffer was being materialised twice, 128 M10K for
//  64 KiB, because the CPU port asked its M10K to return the previous contents
//  of an address it was writing in the same cycle. Removing that requirement
//  is a change to the port's read-during-write behaviour, and this bench pins
//  down everything that is not allowed to move with it:
//
//    * a byte written is the byte read back, at every corner of the map,
//    * the CPU read latency is one clk_cpu and cpu_ready follows the cycle,
//    * the video port reads the same memory on its own unrelated clock,
//      with video_data_valid one clock behind video_read_en,
//    * a CPU write and a video read at different addresses in the same cycle
//      do not disturb each other,
//    * a byte the CPU writes is visible to the raster afterwards.
//
//  Read-during-write on one address is deliberately not tested: the ISA bus
//  never asserts MEMR# and MEMW# together, so vga_a000_cpu_frontend cannot
//  produce it, and the whole point is that the answer is now don't-care.
//
//============================================================================

`timescale 1ns/1ps
`default_nettype wire

module vga_framebuffer_tb;

    // Two unrelated clocks, as in the core: the CPU side runs off the system
    // clock and the raster off the video clock.
    reg clk_cpu = 1'b0;
    always #10.0 clk_cpu = ~clk_cpu;

    reg clk_video = 1'b0;
    always #17.462 clk_video = ~clk_video;

    reg         reset_cpu = 1'b1;
    reg  [15:0] cpu_addr = 16'h0000;
    reg  [7:0]  cpu_din = 8'h00;
    reg         cpu_read = 1'b0;
    reg         cpu_write = 1'b0;
    wire [7:0]  cpu_dout;
    wire        cpu_ready;

    reg  [15:0] video_addr = 16'h0000;
    reg         video_read_en = 1'b0;
    wire [7:0]  video_pixel;
    wire        video_data_valid;

    vga_framebuffer dut (
        .clk_cpu(clk_cpu), .reset_cpu(reset_cpu),
        .cpu_addr(cpu_addr), .cpu_din(cpu_din),
        .cpu_read(cpu_read), .cpu_write(cpu_write),
        .cpu_dout(cpu_dout), .cpu_ready(cpu_ready),
        .clk_video(clk_video), .video_addr(video_addr),
        .video_read_en(video_read_en),
        .video_pixel(video_pixel), .video_data_valid(video_data_valid)
    );

    integer errors = 0;

    initial begin
        #200_000;
        $display("[vga_framebuffer_tb] TIMEOUT");
        $display("[vga_framebuffer_tb] RESULT: FAIL");
        $finish;
    end

    task cpu_store(input [15:0] a, input [7:0] d);
        begin
            @(negedge clk_cpu);
            cpu_addr <= a; cpu_din <= d; cpu_write <= 1'b1; cpu_read <= 1'b0;
            @(negedge clk_cpu);
            cpu_write <= 1'b0;
        end
    endtask

    // One clk_cpu of latency, and cpu_ready has to be up in the same cycle the
    // data is: the frontend releases the bus cycle on it.
    task cpu_load(input [15:0] a, output [7:0] d);
        begin
            @(negedge clk_cpu);
            cpu_addr <= a; cpu_read <= 1'b1; cpu_write <= 1'b0;
            @(negedge clk_cpu);
            cpu_read <= 1'b0;
            if (cpu_ready !== 1'b1) begin
                $display("FAIL cpu_ready is %b one clock into a read of %04h", cpu_ready, a);
                errors = errors + 1;
            end
            d = cpu_dout;
        end
    endtask

    task video_load(input [15:0] a, output [7:0] d);
        begin
            @(negedge clk_video);
            video_addr <= a; video_read_en <= 1'b1;
            @(negedge clk_video);
            video_read_en <= 1'b0;
            if (video_data_valid !== 1'b1) begin
                $display("FAIL video_data_valid is %b one clock into a read of %04h",
                         video_data_valid, a);
                errors = errors + 1;
            end
            d = video_pixel;
        end
    endtask

    task check_byte(input [8*24-1:0] what, input [15:0] a,
                    input [7:0] seen, input [7:0] want);
        begin
            if (seen !== want) begin
                $display("FAIL %0s at %04h: read %02h, wrote %02h", what, a, seen, want);
                errors = errors + 1;
            end
        end
    endtask

    // The four corners of the 64 KiB map plus a couple inside it, so a memory
    // that ends up narrower or shallower than it should be is caught.
    reg [15:0] probe [0:5];
    reg [7:0]  value [0:5];
    integer i, iw, ir;
    reg [7:0] got, got_v;

    initial begin
        probe[0] = 16'h0000; value[0] = 8'h5A;
        probe[1] = 16'h0001; value[1] = 8'hA5;
        probe[2] = 16'h3FFF; value[2] = 8'h1F;
        probe[3] = 16'h8000; value[3] = 8'hC3;
        probe[4] = 16'hFAFF; value[4] = 8'h7E;   // last byte of a 320x200 page
        probe[5] = 16'hFFFF; value[5] = 8'hDB;

        repeat (4) @(posedge clk_cpu);
        reset_cpu <= 1'b0;
        repeat (4) @(posedge clk_cpu);

        if (cpu_ready !== 1'b0) begin
            $display("FAIL cpu_ready did not come out of reset low");
            errors = errors + 1;
        end

        // Written by the CPU, read back by the CPU.
        for (i = 0; i < 6; i = i + 1) cpu_store(probe[i], value[i]);
        for (i = 0; i < 6; i = i + 1) begin
            cpu_load(probe[i], got);
            check_byte("cpu read back", probe[i], got, value[i]);
        end

        // ... and read by the raster, on its own clock.
        for (i = 0; i < 6; i = i + 1) begin
            video_load(probe[i], got);
            check_byte("video read", probe[i], got, value[i]);
        end

        // A write and a raster read of different addresses in the same cycle:
        // this is the normal case in mode 13h and neither may disturb the
        // other. The write runs on clk_cpu while the read runs free on
        // clk_video, so the two collide somewhere in the burst by construction.
        fork
            begin : writer
                for (iw = 0; iw < 40; iw = iw + 1)
                    cpu_store(16'h4000 + iw[15:0], 8'h80 + iw[7:0]);
            end
            begin : reader
                for (ir = 0; ir < 40; ir = ir + 1) begin
                    video_load(probe[5], got_v);
                    check_byte("video read during writes", probe[5], got_v, value[5]);
                end
            end
        join

        for (i = 0; i < 40; i = i + 1) begin
            cpu_load(16'h4000 + i[15:0], got);
            check_byte("written while the raster read", 16'h4000 + i[15:0], got, 8'h80 + i[7:0]);
        end

        // What the CPU writes has to reach the raster.
        cpu_store(16'h1234, 8'h96);
        video_load(16'h1234, got);
        check_byte("cpu write seen by the raster", 16'h1234, got, 8'h96);

        // And an untouched location must not have been disturbed by any of it.
        cpu_load(16'h3FFF, got);
        check_byte("still holding", 16'h3FFF, got, 8'h1F);

        if (errors == 0) $display("[vga_framebuffer_tb] RESULT: PASS");
        else             $display("[vga_framebuffer_tb] RESULT: FAIL");
        $finish;
    end

endmodule
