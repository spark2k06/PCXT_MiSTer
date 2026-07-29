//============================================================================
//
//  VGA/VGA-compatible 256-entry DAC palette
//
//============================================================================

module vga_dac(
    input  wire        clock,
    input  wire        reset,
    input  wire        load_defaults,
    input  wire        invalidate,

    input  wire        write_en,
    input  wire [7:0]  write_index,
    input  wire [5:0]  write_red,
    input  wire [5:0]  write_green,
    input  wire [5:0]  write_blue,

    input  wire        component_write_en,
    input  wire [7:0]  component_write_index,
    input  wire [1:0]  component_select,
    input  wire [5:0]  component_data,

    input  wire [7:0]  sample_index,
    output wire [5:0]  sample_red,
    output wire [5:0]  sample_green,
    output wire [5:0]  sample_blue,
    output wire [7:0]  sample_red_8,
    output wire [7:0]  sample_green_8,
    output wire [7:0]  sample_blue_8,
    output wire        sample_valid,

    input  wire [7:0]  port_index,
    output wire [5:0]  port_red,
    output wire [5:0]  port_green,
    output wire [5:0]  port_blue,
    output wire        port_valid
);

    reg [5:0] red_ram[0:255];
    reg [5:0] green_ram[0:255];
    reg [5:0] blue_ram[0:255];
    // Set for every index loaded by load_defaults (i.e. while VGA mode 13h
    // is active) or explicitly written through the DAC ports; cleared by
    // invalidate (a mode set to anything other than mode 13h). Lets the EGA
    // path fall back to its own palette for any entry a VGA-unaware EGA
    // program never touched, instead of guessing a single default table that
    // cannot serve both the VGA and EGA 200-line attribute code conventions.
    reg [255:0] entry_valid;

    integer reset_index;

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

    function [5:0] gray_component;
        input [3:0] index;
        begin
            case (index)
                4'h0: gray_component = 6'h00;
                4'h1: gray_component = 6'h05;
                4'h2: gray_component = 6'h08;
                4'h3: gray_component = 6'h0B;
                4'h4: gray_component = 6'h0E;
                4'h5: gray_component = 6'h11;
                4'h6: gray_component = 6'h14;
                4'h7: gray_component = 6'h18;
                4'h8: gray_component = 6'h1C;
                4'h9: gray_component = 6'h20;
                4'hA: gray_component = 6'h24;
                4'hB: gray_component = 6'h28;
                4'hC: gray_component = 6'h2D;
                4'hD: gray_component = 6'h32;
                4'hE: gray_component = 6'h38;
                4'hF: gray_component = 6'h3F;
                default: gray_component = 6'h00;
            endcase
        end
    endfunction

    function [5:0] vga_ring_level;
        input [3:0] ring;
        input [2:0] level;
        begin
            case (ring)
                4'd0: begin
                    case (level)
                        3'd0: vga_ring_level = 6'h00;
                        3'd1: vga_ring_level = 6'h10;
                        3'd2: vga_ring_level = 6'h1F;
                        3'd3: vga_ring_level = 6'h2F;
                        default: vga_ring_level = 6'h3F;
                    endcase
                end
                4'd1: begin
                    case (level)
                        3'd0: vga_ring_level = 6'h1F;
                        3'd1: vga_ring_level = 6'h27;
                        3'd2: vga_ring_level = 6'h2F;
                        3'd3: vga_ring_level = 6'h37;
                        default: vga_ring_level = 6'h3F;
                    endcase
                end
                4'd2: begin
                    case (level)
                        3'd0: vga_ring_level = 6'h2D;
                        3'd1: vga_ring_level = 6'h31;
                        3'd2: vga_ring_level = 6'h36;
                        3'd3: vga_ring_level = 6'h3A;
                        default: vga_ring_level = 6'h3F;
                    endcase
                end
                4'd3: begin
                    case (level)
                        3'd0: vga_ring_level = 6'h00;
                        3'd1: vga_ring_level = 6'h07;
                        3'd2: vga_ring_level = 6'h0E;
                        3'd3: vga_ring_level = 6'h15;
                        default: vga_ring_level = 6'h1C;
                    endcase
                end
                4'd4: begin
                    case (level)
                        3'd0: vga_ring_level = 6'h0E;
                        3'd1: vga_ring_level = 6'h11;
                        3'd2: vga_ring_level = 6'h15;
                        3'd3: vga_ring_level = 6'h18;
                        default: vga_ring_level = 6'h1C;
                    endcase
                end
                4'd5: begin
                    case (level)
                        3'd0: vga_ring_level = 6'h14;
                        3'd1: vga_ring_level = 6'h16;
                        3'd2: vga_ring_level = 6'h18;
                        3'd3: vga_ring_level = 6'h1A;
                        default: vga_ring_level = 6'h1C;
                    endcase
                end
                4'd6: begin
                    case (level)
                        3'd0: vga_ring_level = 6'h00;
                        3'd1: vga_ring_level = 6'h04;
                        3'd2: vga_ring_level = 6'h08;
                        3'd3: vga_ring_level = 6'h0C;
                        default: vga_ring_level = 6'h10;
                    endcase
                end
                4'd7: begin
                    case (level)
                        3'd0: vga_ring_level = 6'h08;
                        3'd1: vga_ring_level = 6'h0A;
                        3'd2: vga_ring_level = 6'h0C;
                        3'd3: vga_ring_level = 6'h0E;
                        default: vga_ring_level = 6'h10;
                    endcase
                end
                default: begin
                    case (level)
                        3'd0: vga_ring_level = 6'h0B;
                        3'd1: vga_ring_level = 6'h0C;
                        3'd2: vga_ring_level = 6'h0D;
                        3'd3: vga_ring_level = 6'h0F;
                        default: vga_ring_level = 6'h10;
                    endcase
                end
            endcase
        end
    endfunction

    function [5:0] vga_ring_component;
        input [3:0] ring;
        input [4:0] position;
        input [1:0] component;
        reg [2:0] red_level;
        reg [2:0] green_level;
        reg [2:0] blue_level;
        begin
            case (position)
                5'd0:  begin red_level = 3'd0; green_level = 3'd0; blue_level = 3'd4; end
                5'd1:  begin red_level = 3'd1; green_level = 3'd0; blue_level = 3'd4; end
                5'd2:  begin red_level = 3'd2; green_level = 3'd0; blue_level = 3'd4; end
                5'd3:  begin red_level = 3'd3; green_level = 3'd0; blue_level = 3'd4; end
                5'd4:  begin red_level = 3'd4; green_level = 3'd0; blue_level = 3'd4; end
                5'd5:  begin red_level = 3'd4; green_level = 3'd0; blue_level = 3'd3; end
                5'd6:  begin red_level = 3'd4; green_level = 3'd0; blue_level = 3'd2; end
                5'd7:  begin red_level = 3'd4; green_level = 3'd0; blue_level = 3'd1; end
                5'd8:  begin red_level = 3'd4; green_level = 3'd0; blue_level = 3'd0; end
                5'd9:  begin red_level = 3'd4; green_level = 3'd1; blue_level = 3'd0; end
                5'd10: begin red_level = 3'd4; green_level = 3'd2; blue_level = 3'd0; end
                5'd11: begin red_level = 3'd4; green_level = 3'd3; blue_level = 3'd0; end
                5'd12: begin red_level = 3'd4; green_level = 3'd4; blue_level = 3'd0; end
                5'd13: begin red_level = 3'd3; green_level = 3'd4; blue_level = 3'd0; end
                5'd14: begin red_level = 3'd2; green_level = 3'd4; blue_level = 3'd0; end
                5'd15: begin red_level = 3'd1; green_level = 3'd4; blue_level = 3'd0; end
                5'd16: begin red_level = 3'd0; green_level = 3'd4; blue_level = 3'd0; end
                5'd17: begin red_level = 3'd0; green_level = 3'd4; blue_level = 3'd1; end
                5'd18: begin red_level = 3'd0; green_level = 3'd4; blue_level = 3'd2; end
                5'd19: begin red_level = 3'd0; green_level = 3'd4; blue_level = 3'd3; end
                5'd20: begin red_level = 3'd0; green_level = 3'd4; blue_level = 3'd4; end
                5'd21: begin red_level = 3'd0; green_level = 3'd3; blue_level = 3'd4; end
                5'd22: begin red_level = 3'd0; green_level = 3'd2; blue_level = 3'd4; end
                default: begin red_level = 3'd0; green_level = 3'd1; blue_level = 3'd4; end
            endcase

            case (component)
                2'd0: vga_ring_component = vga_ring_level(ring, red_level);
                2'd1: vga_ring_component = vga_ring_level(ring, green_level);
                2'd2: vga_ring_component = vga_ring_level(ring, blue_level);
                default: vga_ring_component = 6'h00;
            endcase
        end
    endfunction

    function [5:0] default_component;
        input [7:0] index;
        input [1:0] component;
        reg [3:0] ring;
        reg [4:0] position;
        begin
            if (index < 8'd16) begin
                default_component = ega16_component(index[3:0], component);
            end else if (index < 8'd32) begin
                default_component = gray_component(index[3:0]);
            end else if (index < 8'd248) begin
                if (index < 8'd56) begin
                    ring = 4'd0;
                    position = index - 8'd32;
                end else if (index < 8'd80) begin
                    ring = 4'd1;
                    position = index - 8'd56;
                end else if (index < 8'd104) begin
                    ring = 4'd2;
                    position = index - 8'd80;
                end else if (index < 8'd128) begin
                    ring = 4'd3;
                    position = index - 8'd104;
                end else if (index < 8'd152) begin
                    ring = 4'd4;
                    position = index - 8'd128;
                end else if (index < 8'd176) begin
                    ring = 4'd5;
                    position = index - 8'd152;
                end else if (index < 8'd200) begin
                    ring = 4'd6;
                    position = index - 8'd176;
                end else if (index < 8'd224) begin
                    ring = 4'd7;
                    position = index - 8'd200;
                end else begin
                    ring = 4'd8;
                    position = index - 8'd224;
                end
                default_component = vga_ring_component(ring, position, component);
            end else begin
                default_component = 6'h00;
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
            entry_valid <= 256'd0;
        end else if (load_defaults) begin
            for (reset_index = 0; reset_index < 256; reset_index = reset_index + 1) begin
                red_ram[reset_index] <= default_component(reset_index[7:0], 2'd0);
                green_ram[reset_index] <= default_component(reset_index[7:0], 2'd1);
                blue_ram[reset_index] <= default_component(reset_index[7:0], 2'd2);
            end
            entry_valid <= {256{1'b1}};
        end else if (invalidate) begin
            entry_valid <= 256'd0;
        end else if (write_en) begin
            red_ram[write_index] <= write_red;
            green_ram[write_index] <= write_green;
            blue_ram[write_index] <= write_blue;
            entry_valid[write_index] <= 1'b1;
        end else if (component_write_en) begin
            case (component_select)
                2'd0: red_ram[component_write_index] <= component_data;
                2'd1: green_ram[component_write_index] <= component_data;
                2'd2: blue_ram[component_write_index] <= component_data;
                default: begin
                end
            endcase
            entry_valid[component_write_index] <= 1'b1;
        end
    end

    assign sample_red = red_ram[sample_index];
    assign sample_green = green_ram[sample_index];
    assign sample_blue = blue_ram[sample_index];
    assign sample_red_8 = {sample_red, sample_red[5:4]};
    assign sample_green_8 = {sample_green, sample_green[5:4]};
    assign sample_blue_8 = {sample_blue, sample_blue[5:4]};
    assign sample_valid = entry_valid[sample_index];
    assign port_red = red_ram[port_index];
    assign port_green = green_ram[port_index];
    assign port_blue = blue_ram[port_index];
    assign port_valid = entry_valid[port_index];

endmodule
