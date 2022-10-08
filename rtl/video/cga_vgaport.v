// Graphics Gremlin
//
// Copyright (c) 2021 Eric Schlaepfer
// This work is licensed under the Creative Commons Attribution-ShareAlike 4.0
// International License. To view a copy of this license, visit
// http://creativecommons.org/licenses/by-sa/4.0/ or send a letter to Creative
// Commons, PO Box 1866, Mountain View, CA 94042, USA.
//

module cga_vgaport(
	input wire clk,
	input wire[3:0] video,
	input wire composite,

    // Analog outputs
	output wire[5:0] red,
	output wire[5:0] green,
	output wire[5:0] blue
	);

	reg[17:0] CGA_COMPOSITE_PATTERN_COLORS [0:65536];
	initial $readmemh("composite.hex", CGA_COMPOSITE_PATTERN_COLORS);
		
   reg[17:0] c0;
	reg[17:0] c;
	
	reg[2:0] pixel_counter = 4'd0;	
	reg composite_aux = 1'b0;
	
	reg[15:0] pattern;
	
    assign red = c[5:0];
    assign green = c[11:6];
    assign blue = c[17:12];	 

    always @(posedge clk)
    begin		
		composite_aux <= (pixel_counter < 7) ? composite_aux : composite;
		pixel_counter <= (pixel_counter < 7) ? pixel_counter + 1 : 0;
	 
		if (composite_aux) begin
			if (pixel_counter < 7)
				pattern <= pixel_counter[0] ? pattern : {pattern[11:8], pattern[7:4], pattern[3:0], video};
			else
				c <= CGA_COMPOSITE_PATTERN_COLORS[{pattern[3:0], pattern[7:4], pattern[11:8], pattern[15:12]}];
				
		end
		else begin
            case(video)
                4'h0: c <= 18'b000000_000000_000000;
                4'h1: c <= 18'b101010_000000_000000;
                4'h2: c <= 18'b000000_101010_000000;
                4'h3: c <= 18'b101010_101010_000000;
                4'h4: c <= 18'b000000_000000_101010;
                4'h5: c <= 18'b101010_000000_101010;
                4'h6: c <= 18'b000000_010101_101010; // Brown!
                4'h7: c <= 18'b101010_101010_101010;
                4'h8: c <= 18'b010101_010101_010101;
                4'h9: c <= 18'b111111_010101_010101;
                4'hA: c <= 18'b010101_111111_010101;
                4'hB: c <= 18'b111111_111111_010101;
                4'hC: c <= 18'b010101_010101_111111;
                4'hD: c <= 18'b111111_010101_111111;
                4'hE: c <= 18'b010101_111111_111111;
                4'hF: c <= 18'b111111_111111_111111;
                default: ;
            endcase
		end
    end
endmodule

