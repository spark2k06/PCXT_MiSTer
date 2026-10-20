//============================================================================
//
//  VGA packed 8bpp framebuffer
//
//============================================================================

module vga_framebuffer(
    input  wire        clk_cpu,
    input  wire        reset_cpu,
    input  wire [15:0] cpu_addr,
    input  wire [7:0]  cpu_din,
    input  wire        cpu_read,
    input  wire        cpu_write,
    output reg  [7:0]  cpu_dout = 8'h00,
    output reg         cpu_ready = 1'b0,

    input  wire        clk_video,
    input  wire [15:0] video_addr,
    input  wire        video_read_en,
    output reg  [7:0]  video_pixel,
    output reg         video_data_valid
);

    // 64 KiB is 64 M10K blocks, and this has to stay one memory rather than
    // one per reader, so the CPU port is written the way Quartus infers a true
    // dual port block: the write forwards its own data to the output register
    // instead of returning what the location held before it. An M10K port
    // cannot return the old contents of an address it is writing in the same
    // cycle, and asking for that is what makes the Fitter build a second copy.
    //
    // Nothing observes the difference. MEMR# and MEMW# are never low together
    // on the ISA bus, so vga_a000_cpu_frontend never asserts cpu_read and
    // cpu_write at once, and the value here during a write is not read by
    // anyone: cpu_ready gates it.
    //
    // no_rw_check says the same thing about the other port. The CPU may well
    // write a byte the raster is reading, and across two unrelated clocks
    // there is no defined answer to give it anyway.
    (* ramstyle = "M10K, no_rw_check" *) reg [7:0] mem [0:65535];

    always @(posedge clk_cpu) begin
        if (cpu_write) begin
            mem[cpu_addr] <= cpu_din;
            cpu_dout      <= cpu_din;
        end else begin
            cpu_dout      <= mem[cpu_addr];
        end
    end

    // Kept out of the block above: an asynchronous reset on the same register
    // as the memory read is the other thing that stops the block being
    // inferred. cpu_dout needs none - it means nothing until cpu_ready says so.
    always @(posedge clk_cpu or posedge reset_cpu) begin
        if (reset_cpu)
            cpu_ready <= 1'b0;
        else
            cpu_ready <= cpu_read | cpu_write;
    end

    always @(posedge clk_video) begin
        video_data_valid <= video_read_en;
        if (video_read_en)
            video_pixel <= mem[video_addr];
    end

endmodule
