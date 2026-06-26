//============================================================================
//
//  PCXT MiSTer EGA graphics controller
//
//============================================================================

`default_nettype wire

module ega_gfx_ctrl (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] io_addr,
    input  wire [7:0]  io_data_in,
    output reg  [7:0]  io_data_out,
    input  wire        io_we,
    input  wire        io_re,
    output reg  [1:0]  write_mode,
    output reg  [1:0]  read_mode,
    output reg  [1:0]  read_plane_sel,
    output reg  [7:0]  color_compare,
    output reg  [7:0]  color_dont_care,
    output reg  [7:0]  bit_mask,
    output reg  [7:0]  set_reset,
    output reg  [3:0]  enable_set_reset,
    output reg  [1:0]  rop_select,
    output reg  [2:0]  rotate_count,
    output reg         odd_even_mode,
    output reg         chain2_read,
    output reg         graphics_mode,
    output reg         cga_2bpp_mode,
    output reg  [1:0]  mem_map_sel,
    output reg  [7:0]  mode_debug
);

    localparam [15:0] GFX_ADDR_PORT0 = 16'h03CE;
    localparam [15:0] GFX_ADDR_PORT1 = 16'h02CE;
    localparam [15:0] GFX_DATA_PORT0 = 16'h03CF;
    localparam [15:0] GFX_DATA_PORT1 = 16'h02CF;

    reg [3:0] gfx_index = 4'h0;
    reg [7:0] set_reset_reg = 8'h00;
    reg [7:0] enable_set_reset_reg = 8'h00;
    reg [7:0] color_compare_reg = 8'h00;
    reg [7:0] data_rotate_reg = 8'h00;
    reg [7:0] read_plane_sel_reg = 8'h00;
    reg [7:0] mode_reg = 8'h00;
    reg [7:0] misc_reg = 8'h00;
    reg [7:0] color_dont_care_reg = 8'h0F;
    reg [7:0] bit_mask_reg = 8'hFF;

    wire gfx_addr_cs = (io_addr == GFX_ADDR_PORT0) || (io_addr == GFX_ADDR_PORT1);
    wire gfx_data_cs = (io_addr == GFX_DATA_PORT0) || (io_addr == GFX_DATA_PORT1);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            gfx_index <= 4'h0;
            set_reset_reg <= 8'h00;
            enable_set_reset_reg <= 8'h00;
            color_compare_reg <= 8'h00;
            data_rotate_reg <= 8'h00;
            read_plane_sel_reg <= 8'h00;
            mode_reg <= 8'h00;
            misc_reg <= 8'h00;
            color_dont_care_reg <= 8'h0F;
            bit_mask_reg <= 8'hFF;
        end else begin
            if (io_we && gfx_addr_cs)
                gfx_index <= io_data_in[3:0];
            else if (io_we && gfx_data_cs) begin
                case (gfx_index)
                    4'h0: set_reset_reg <= io_data_in;
                    4'h1: enable_set_reset_reg <= io_data_in;
                    4'h2: color_compare_reg <= io_data_in;
                    4'h3: data_rotate_reg <= io_data_in;
                    4'h4: read_plane_sel_reg <= io_data_in;
                    4'h5: mode_reg <= io_data_in;
                    4'h6: misc_reg <= io_data_in;
                    4'h7: color_dont_care_reg <= io_data_in;
                    4'h8: bit_mask_reg <= io_data_in;
                    default: begin
                    end
                endcase
            end
        end
    end

    always @(*) begin
        io_data_out = 8'h00;
        case (gfx_index)
            4'h0: io_data_out = set_reset_reg;
            4'h1: io_data_out = enable_set_reset_reg;
            4'h2: io_data_out = color_compare_reg;
            4'h3: io_data_out = data_rotate_reg;
            4'h4: io_data_out = read_plane_sel_reg;
            4'h5: io_data_out = mode_reg;
            4'h6: io_data_out = misc_reg;
            4'h7: io_data_out = color_dont_care_reg;
            4'h8: io_data_out = bit_mask_reg;
            default: io_data_out = 8'h00;
        endcase

        if (!io_re || !gfx_data_cs)
            io_data_out = 8'h00;

        write_mode = mode_reg[1:0];
        read_mode = {1'b0, mode_reg[3]};
        read_plane_sel = read_plane_sel_reg[1:0];
        color_compare = color_compare_reg;
        color_dont_care = color_dont_care_reg;
        bit_mask = bit_mask_reg;
        set_reset = set_reset_reg;
        enable_set_reset = enable_set_reset_reg[3:0];
        rop_select = data_rotate_reg[4:3];
        rotate_count = data_rotate_reg[2:0];
        odd_even_mode = misc_reg[1];
        chain2_read = mode_reg[4];
        graphics_mode = misc_reg[0];
        cga_2bpp_mode = mode_reg[5];
        mem_map_sel = misc_reg[3:2];
        mode_debug = mode_reg;
    end

endmodule
