//============================================================================
//
//  MCGA packed 8bpp framebuffer
//
//============================================================================

module mcga_framebuffer(
    input  wire        clk_cpu,
    input  wire        reset_cpu,
    input  wire [15:0] cpu_addr,
    input  wire [7:0]  cpu_din,
    input  wire        cpu_read,
    input  wire        cpu_write,
    output reg  [7:0]  cpu_dout,
    output reg         cpu_ready,

    input  wire        clk_video,
    input  wire [15:0] video_addr,
    input  wire        video_read_en,
    output reg  [7:0]  video_pixel,
    output reg         video_data_valid
);

    reg [7:0] mem [0:65535];

    always @(posedge clk_cpu or posedge reset_cpu) begin
        if (reset_cpu) begin
            cpu_dout <= 8'h00;
            cpu_ready <= 1'b0;
        end else begin
            cpu_ready <= cpu_read | cpu_write;

            if (cpu_write)
                mem[cpu_addr] <= cpu_din;

            if (cpu_read)
                cpu_dout <= cpu_write ? cpu_din : mem[cpu_addr];
        end
    end

    always @(posedge clk_video) begin
        video_data_valid <= video_read_en;
        if (video_read_en)
            video_pixel <= mem[video_addr];
    end

endmodule
