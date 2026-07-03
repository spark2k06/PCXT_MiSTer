//============================================================================
//
//  MCGA/VGA-compatible 256-entry DAC palette
//
//============================================================================

module mcga_dac(
    input  wire        clock,
    input  wire        reset,

    input  wire        write_en,
    input  wire [7:0]  write_index,
    input  wire [5:0]  write_red,
    input  wire [5:0]  write_green,
    input  wire [5:0]  write_blue,

    input  wire [7:0]  sample_index,
    output wire [5:0]  sample_red,
    output wire [5:0]  sample_green,
    output wire [5:0]  sample_blue,
    output wire [7:0]  sample_red_8,
    output wire [7:0]  sample_green_8,
    output wire [7:0]  sample_blue_8
);

    reg [5:0] red_ram[0:255];
    reg [5:0] green_ram[0:255];
    reg [5:0] blue_ram[0:255];

    integer reset_index;

    function [5:0] cube_level;
        input [2:0] level;
        begin
            case (level)
                3'd0: cube_level = 6'h00;
                3'd1: cube_level = 6'h0C;
                3'd2: cube_level = 6'h18;
                3'd3: cube_level = 6'h24;
                3'd4: cube_level = 6'h30;
                3'd5: cube_level = 6'h3F;
                default: cube_level = 6'h00;
            endcase
        end
    endfunction

    function [5:0] ega16_component;
        input [3:0] index;
        input [1:0] component;
        begin
            case (index)
                4'h0: ega16_component = 6'h00;
                4'h1: ega16_component = (component == 2'd2) ? 6'h2A : 6'h00;
                4'h2: ega16_component = (component == 2'd1) ? 6'h2A : 6'h00;
                4'h3: ega16_component = (component == 2'd0) ? 6'h00 : 6'h2A;
                4'h4: ega16_component = (component == 2'd0) ? 6'h2A : 6'h00;
                4'h5: ega16_component = (component == 2'd1) ? 6'h00 : 6'h2A;
                4'h6: ega16_component = (component == 2'd0) ? 6'h2A :
                                          (component == 2'd1) ? 6'h15 : 6'h00;
                4'h7: ega16_component = 6'h2A;
                4'h8: ega16_component = 6'h15;
                4'h9: ega16_component = (component == 2'd2) ? 6'h3F : 6'h15;
                4'hA: ega16_component = (component == 2'd1) ? 6'h3F : 6'h15;
                4'hB: ega16_component = (component == 2'd0) ? 6'h15 : 6'h3F;
                4'hC: ega16_component = (component == 2'd0) ? 6'h3F : 6'h15;
                4'hD: ega16_component = (component == 2'd1) ? 6'h15 : 6'h3F;
                4'hE: ega16_component = (component == 2'd2) ? 6'h15 : 6'h3F;
                4'hF: ega16_component = 6'h3F;
                default: ega16_component = 6'h00;
            endcase
        end
    endfunction

    function [5:0] default_component;
        input [7:0] index;
        input [1:0] component;
        integer cube_index;
        integer gray;
        reg [2:0] red_level;
        reg [2:0] green_level;
        reg [2:0] blue_level;
        begin
            if (index < 8'd16) begin
                default_component = ega16_component(index[3:0], component);
            end else if (index < 8'd232) begin
                cube_index = index - 8'd16;
                red_level = cube_index / 36;
                green_level = (cube_index / 6) % 6;
                blue_level = cube_index % 6;
                case (component)
                    2'd0: default_component = cube_level(red_level);
                    2'd1: default_component = cube_level(green_level);
                    2'd2: default_component = cube_level(blue_level);
                    default: default_component = 6'h00;
                endcase
            end else begin
                gray = 8 + ((index - 8'd232) * 10);
                if (gray > 63)
                    default_component = 6'h3F;
                else
                    default_component = gray[5:0];
            end
        end
    endfunction

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            for (reset_index = 0; reset_index < 256; reset_index = reset_index + 1) begin
                red_ram[reset_index] <= default_component(reset_index[7:0], 2'd0);
                green_ram[reset_index] <= default_component(reset_index[7:0], 2'd1);
                blue_ram[reset_index] <= default_component(reset_index[7:0], 2'd2);
            end
        end else if (write_en) begin
            red_ram[write_index] <= write_red;
            green_ram[write_index] <= write_green;
            blue_ram[write_index] <= write_blue;
        end
    end

    assign sample_red = red_ram[sample_index];
    assign sample_green = green_ram[sample_index];
    assign sample_blue = blue_ram[sample_index];
    assign sample_red_8 = {sample_red, sample_red[5:4]};
    assign sample_green_8 = {sample_green, sample_green[5:4]};
    assign sample_blue_8 = {sample_blue, sample_blue[5:4]};

endmodule
