// Graphics Gremlin
//
// Copyright (c) 2021 Eric Schlaepfer
// This work is licensed under the Creative Commons Attribution-ShareAlike 4.0
// International License. To view a copy of this license, visit
// http://creativecommons.org/licenses/by-sa/4.0/ or send a letter to Creative
// Commons, PO Box 1866, Mountain View, CA 94042, USA.
//
module mda_vgaport(
    input wire clk,

    input wire video,
    input wire intensity,

    // Analog outputs
    output reg [5:0] red,
    output reg [5:0] green,
    output reg [5:0] blue,
	 input wire [1:0] mda_rgb
    );

    always @(posedge clk)
    begin
        case({video, intensity}) // 1 = green, 2 = amber, 3 = b&w
            2'd0: begin
                red   <= 6'd0;
                green <= 6'd0;
					 blue  <= 6'd0;
            end
            2'd1: begin				    
                red   <= mda_rgb == 0 ? 6'd0 : 6'd16;
                green <= mda_rgb == 1 ? 6'd12 : 6'd16;
					 blue  <= mda_rgb == 2 ? 6'd16 : 6'd0;
            end
            2'd2: begin
                red   <= mda_rgb == 0 ? 6'd0 : 6'd48;
                green <= mda_rgb == 1 ? 6'd21 : 6'd48;
					 blue  <= mda_rgb == 2 ? 6'd48 : 6'd0;
            end
            2'd3: begin
                red   <= mda_rgb == 0 ? 6'd0 : 6'd63;
                green <= mda_rgb == 1 ? 6'd27 : 6'd63;
					 blue  <= mda_rgb == 2 ? 6'd63 : 6'd0;
            end
            default: ;
        endcase
    end
endmodule


