//============================================================================
//
//  MCGA mode 13h visible pixel to packed framebuffer address
//
//============================================================================

module mcga_mode13_address(
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    output wire [15:0] framebuffer_addr,
    output wire        render_en
);

    wire [18:0] row_base = {9'b0, pixel_y} << 8;
    wire [18:0] row_extra = {9'b0, pixel_y} << 6;
    wire [18:0] pixel_offset = row_base + row_extra + {9'b0, pixel_x};

    assign framebuffer_addr = pixel_offset[15:0];
    assign render_en = (pixel_x < 10'd320) && (pixel_y < 10'd200);

endmodule
