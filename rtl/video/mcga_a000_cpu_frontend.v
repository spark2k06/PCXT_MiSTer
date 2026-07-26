//============================================================================
//
//  MCGA mode 13h A0000h packed framebuffer CPU frontend
//
//============================================================================

module mcga_a000_cpu_frontend(
    input  wire        clock,
    input  wire        reset,
    input  wire        clk_video,

    input  wire        active,
    input  wire [19:0] address,
    input  wire [7:0]  cpu_din,
    input  wire        iorq,
    input  wire        address_enable_n,
    input  wire        memory_read_n,
    input  wire        memory_write_n,

    output wire        a000_select,
    output wire        cpu_cycle,
    output wire [7:0]  cpu_dout,
    output wire        cpu_ready,

    input  wire [15:0] video_addr,
    input  wire        video_read_en,
    output wire [7:0]  video_pixel,
    output wire        video_data_valid
);

    wire cpu_read;
    wire cpu_write;
    wire framebuffer_ready;

    assign a000_select = active && ~iorq && ~address_enable_n && (address[19:16] == 4'hA);
    assign cpu_read = a000_select && ~memory_read_n;
    assign cpu_write = a000_select && ~memory_write_n;
    assign cpu_cycle = cpu_read | cpu_write;
    assign cpu_ready = cpu_cycle ? framebuffer_ready : 1'b1;

    mcga_framebuffer framebuffer (
        .clk_cpu            (clock),
        .reset_cpu          (reset),
        .cpu_addr           (address[15:0]),
        .cpu_din            (cpu_din),
        .cpu_read           (cpu_read),
        .cpu_write          (cpu_write),
        .cpu_dout           (cpu_dout),
        .cpu_ready          (framebuffer_ready),
        .clk_video          (clk_video),
        .video_addr         (video_addr),
        .video_read_en      (video_read_en),
        .video_pixel        (video_pixel),
        .video_data_valid   (video_data_valid)
    );

endmodule
