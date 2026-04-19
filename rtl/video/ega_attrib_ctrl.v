//============================================================================
//
//  PCXT MiSTer EGA attribute controller
//
//============================================================================

`default_nettype wire

module ega_attrib_ctrl (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_pix,
    input  wire [15:0] io_addr,
    input  wire [7:0]  io_data_in,
    output reg  [7:0]  io_data_out,
    input  wire        io_we,
    input  wire        io_re,
    input  wire        status_re,
    input  wire [3:0]  plane_index,
    input  wire        pixel_valid,
    input  wire        display_enable,
    input  wire        palette_64_mode,
    output reg  [5:0]  color_out,
    output reg         display_enable_out,
    output reg         video_enable_out
);

    localparam [15:0] ATTR_ADDR_PORT0 = 16'h03C0;
    localparam [15:0] ATTR_ADDR_PORT1 = 16'h02C0;
    localparam [15:0] ATTR_READ_PORT0 = 16'h03C1;
    localparam [15:0] ATTR_READ_PORT1 = 16'h02C1;

    reg [7:0] raw_palette[0:15];
    reg [4:0] attr_index = 5'h00;
    reg       address_phase = 1'b1;
    reg       video_enable_reg = 1'b1;
    reg [7:0] mode_control_reg = 8'h01;
    reg [7:0] overscan_reg = 8'h00;
    reg [7:0] plane_enable_reg = 8'h0F;
    reg [7:0] pixel_panning_reg = 8'h00;
    reg [7:0] color_select_reg = 8'h00;
    reg       attr_write_q = 1'b0;
    reg       status_re_q = 1'b0;

    wire attr_addr_cs = (io_addr == ATTR_ADDR_PORT0) || (io_addr == ATTR_ADDR_PORT1);
    wire attr_read_cs = (io_addr == ATTR_READ_PORT0) || (io_addr == ATTR_READ_PORT1);
    wire attr_write_pulse = (io_we && attr_addr_cs) && !attr_write_q;
    wire status_re_pulse = status_re && !status_re_q;
    wire [3:0] masked_plane_index = plane_index & plane_enable_reg[3:0];
    // Match 86Box IBM EGA behavior: Color Select (0x14) is latched/readable,
    // but does not alter the effective 6-bit EGA palette on the base IBM card.
    wire [5:0] pixel_color_code = raw_palette[masked_plane_index][5:0];
    wire [5:0] border_color_code = palette_64_mode ? overscan_reg[5:0] : {2'b00, overscan_reg[3:0]};

    integer palette_index;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (palette_index = 0; palette_index < 16; palette_index = palette_index + 1)
                raw_palette[palette_index] <= palette_index[5:0];
            attr_index <= 5'h00;
            address_phase <= 1'b1;
            video_enable_reg <= 1'b1;
            mode_control_reg <= 8'h01;
            overscan_reg <= 8'h00;
            plane_enable_reg <= 8'h0F;
            pixel_panning_reg <= 8'h00;
            color_select_reg <= 8'h00;
            attr_write_q <= 1'b0;
            status_re_q <= 1'b0;
            color_out <= 6'h00;
            display_enable_out <= 1'b0;
            video_enable_out <= 1'b1;
        end else begin
            attr_write_q <= io_we && attr_addr_cs;
            status_re_q <= status_re;

            if (status_re_pulse)
                address_phase <= 1'b1;
            else if (attr_write_pulse) begin
                if (address_phase) begin
                    attr_index <= io_data_in[4:0];
                    video_enable_reg <= io_data_in[5];
                end else begin
                    case (attr_index)
                        5'h00, 5'h01, 5'h02, 5'h03,
                        5'h04, 5'h05, 5'h06, 5'h07,
                        5'h08, 5'h09, 5'h0A, 5'h0B,
                        5'h0C, 5'h0D, 5'h0E, 5'h0F:
                            raw_palette[attr_index[3:0]] <= io_data_in;
                        5'h10: mode_control_reg <= io_data_in;
                        5'h11: overscan_reg <= io_data_in;
                        5'h12: plane_enable_reg <= io_data_in;
                        5'h13: pixel_panning_reg <= io_data_in;
                        5'h14: color_select_reg <= io_data_in;
                        default: begin
                        end
                    endcase
                end

                address_phase <= ~address_phase;
            end

            if (ce_pix) begin
                if (display_enable && video_enable_reg) begin
                    if (pixel_valid)
                        color_out <= pixel_color_code;
                end
                else if (!display_enable) begin
                    color_out <= border_color_code;
                end
                else begin
                    color_out <= 6'h00;
                end

                display_enable_out <= display_enable && video_enable_reg;
                video_enable_out <= video_enable_reg;
            end
        end
    end

    always @(*) begin
        io_data_out = 8'h00;
        case (attr_index)
            5'h00, 5'h01, 5'h02, 5'h03,
            5'h04, 5'h05, 5'h06, 5'h07,
            5'h08, 5'h09, 5'h0A, 5'h0B,
            5'h0C, 5'h0D, 5'h0E, 5'h0F:
                io_data_out = raw_palette[attr_index[3:0]];
            5'h10: io_data_out = mode_control_reg;
            5'h11: io_data_out = overscan_reg;
            5'h12: io_data_out = plane_enable_reg;
            5'h13: io_data_out = pixel_panning_reg;
            5'h14: io_data_out = color_select_reg;
            default: io_data_out = 8'h00;
        endcase

        if (!io_re || !attr_read_cs)
            io_data_out = 8'h00;
    end

endmodule
