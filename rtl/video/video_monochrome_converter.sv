//
//
// This program is GPL Licensed. See COPYING for the full license.
//
//
////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module video_monochrome_converter
(
	input      clk_vid,
  	input      ce_pix,

    input      [2:0] gfx_mode,

	input      [7:0] R,
	input      [7:0] G,
	input      [7:0] B,

	// video output signals
	output reg [7:0] R_OUT,
	output reg [7:0] G_OUT,
	output reg [7:0] B_OUT
	
);
  
  wire [7:0] r, g, b;	
  wire [7:0] mono;
  wire [7:0] shifted_mono;
    
  reg [7:0] red_weight[0:255] = '{ // 0.2126*R 
	 8'h0, 8'h0, 8'h0, 8'h0, 8'h0, 8'h1, 8'h1, 8'h1, 8'h1, 8'h1, 8'h2, 8'h2, 8'h2, 8'h2, 8'h2, 8'h3, 8'h3, 8'h3, 8'h3, 8'h4, 8'h4, 8'h4, 8'h4, 
	 8'h4, 8'h5, 8'h5, 8'h5, 8'h5, 8'h5, 8'h6, 8'h6, 8'h6, 8'h6, 8'h7, 8'h7, 8'h7, 8'h7, 8'h7, 8'h8, 8'h8, 8'h8, 8'h8, 8'h8, 8'h9, 8'h9, 8'h9, 
	 8'h9, 8'h9, 8'hA, 8'hA, 8'hA, 8'hA, 8'hB, 8'hB, 8'hB, 8'hB, 8'hB, 8'hC, 8'hC, 8'hC, 8'hC, 8'hC, 8'hD, 8'hD, 8'hD, 8'hD, 8'hE, 8'hE, 8'hE, 
	 8'hE, 8'hE, 8'hF, 8'hF, 8'hF, 8'hF, 8'hF, 8'h10, 8'h10, 8'h10, 8'h10, 8'h11, 8'h11, 8'h11, 8'h11, 8'h11, 8'h12, 8'h12, 8'h12, 8'h12, 8'h12,
	 8'h13, 8'h13, 8'h13, 8'h13, 8'h13, 8'h14, 8'h14, 8'h14, 8'h14, 8'h15, 8'h15, 8'h15, 8'h15, 8'h15, 8'h16, 8'h16, 8'h16, 8'h16, 8'h16, 8'h17, 
	 8'h17, 8'h17, 8'h17, 8'h18, 8'h18, 8'h18, 8'h18, 8'h18, 8'h19, 8'h19, 8'h19, 8'h19, 8'h19, 8'h1A, 8'h1A, 8'h1A, 8'h1A, 8'h1B, 8'h1B, 8'h1B, 
	 8'h1B, 8'h1B, 8'h1C, 8'h1C, 8'h1C, 8'h1C, 8'h1C, 8'h1D, 8'h1D, 8'h1D, 8'h1D, 8'h1D, 8'h1E, 8'h1E, 8'h1E, 8'h1E, 8'h1F, 8'h1F, 8'h1F, 8'h1F, 
	 8'h1F, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h21, 8'h21, 8'h21, 8'h21, 8'h22, 8'h22, 8'h22, 8'h22, 8'h22, 8'h23, 8'h23, 8'h23, 8'h23, 8'h23, 
	 8'h24, 8'h24, 8'h24, 8'h24, 8'h24, 8'h25, 8'h25, 8'h25, 8'h25, 8'h26, 8'h26, 8'h26, 8'h26, 8'h26, 8'h27, 8'h27, 8'h27, 8'h27, 8'h27, 8'h28,
	 8'h28, 8'h28, 8'h28, 8'h29, 8'h29, 8'h29, 8'h29, 8'h29, 8'h2A, 8'h2A, 8'h2A, 8'h2A, 8'h2A, 8'h2B, 8'h2B, 8'h2B, 8'h2B, 8'h2C, 8'h2C, 8'h2C, 
	 8'h2C, 8'h2C, 8'h2D, 8'h2D, 8'h2D, 8'h2D, 8'h2D, 8'h2E, 8'h2E, 8'h2E, 8'h2E, 8'h2E, 8'h2F, 8'h2F, 8'h2F, 8'h2F, 8'h30, 8'h30, 8'h30, 8'h30, 
	 8'h30, 8'h31, 8'h31, 8'h31, 8'h31, 8'h31, 8'h32, 8'h32, 8'h32, 8'h32, 8'h33, 8'h33, 8'h33, 8'h33, 8'h33, 8'h34, 8'h34, 8'h34, 8'h34, 8'h34, 
	 8'h35, 8'h35, 8'h35, 8'h35, 8'h36, 8'h36
  };

  reg [7:0] green_weight[0:255] = '{ // 0.7152*G 
	8'h0, 8'h0, 8'h1, 8'h2, 8'h2, 8'h3, 8'h4, 8'h5, 8'h5, 8'h6, 8'h7, 8'h7, 8'h8, 8'h9, 8'hA, 8'hA, 8'hB, 8'hC, 8'hC, 8'hD, 8'hE, 8'hF, 8'hF, 
	8'h10, 8'h11, 8'h11, 8'h12, 8'h13, 8'h14, 8'h14, 8'h15, 8'h16, 8'h16, 8'h17, 8'h18, 8'h19, 8'h19, 8'h1A, 8'h1B, 8'h1B, 8'h1C, 8'h1D, 8'h1E,
	8'h1E, 8'h1F, 8'h20, 8'h20, 8'h21, 8'h22, 8'h23, 8'h23, 8'h24, 8'h25, 8'h25, 8'h26, 8'h27, 8'h28, 8'h28, 8'h29, 8'h2A, 8'h2A, 8'h2B, 8'h2C,
	8'h2D, 8'h2D, 8'h2E, 8'h2F, 8'h2F, 8'h30, 8'h31, 8'h32, 8'h32, 8'h33, 8'h34, 8'h34, 8'h35, 8'h36, 8'h37, 8'h37, 8'h38, 8'h39, 8'h39, 8'h3A, 
	8'h3B, 8'h3C, 8'h3C, 8'h3D, 8'h3E, 8'h3E, 8'h3F, 8'h40, 8'h41, 8'h41, 8'h42, 8'h43, 8'h43, 8'h44, 8'h45, 8'h46, 8'h46, 8'h47, 8'h48, 8'h48,
	8'h49, 8'h4A, 8'h4B, 8'h4B, 8'h4C, 8'h4D, 8'h4D, 8'h4E, 8'h4F, 8'h50, 8'h50, 8'h51, 8'h52, 8'h52, 8'h53, 8'h54, 8'h55, 8'h55, 8'h56, 8'h57, 
	8'h57, 8'h58, 8'h59, 8'h5A, 8'h5A, 8'h5B, 8'h5C, 8'h5C, 8'h5D, 8'h5E, 8'h5F, 8'h5F, 8'h60, 8'h61, 8'h61, 8'h62, 8'h63, 8'h64, 8'h64, 8'h65, 
	8'h66, 8'h66, 8'h67, 8'h68, 8'h69, 8'h69, 8'h6A, 8'h6B, 8'h6B, 8'h6C, 8'h6D, 8'h6E, 8'h6E, 8'h6F, 8'h70, 8'h71, 8'h71, 8'h72, 8'h73, 8'h73, 
	8'h74, 8'h75, 8'h76, 8'h76, 8'h77, 8'h78, 8'h78, 8'h79, 8'h7A, 8'h7B, 8'h7B, 8'h7C, 8'h7D, 8'h7D, 8'h7E, 8'h7F, 8'h80, 8'h80, 8'h81, 8'h82, 
	8'h82, 8'h83, 8'h84, 8'h85, 8'h85, 8'h86, 8'h87, 8'h87, 8'h88, 8'h89, 8'h8A, 8'h8A, 8'h8B, 8'h8C, 8'h8C, 8'h8D, 8'h8E, 8'h8F, 8'h8F, 8'h90, 
	8'h91, 8'h91, 8'h92, 8'h93, 8'h94, 8'h94, 8'h95, 8'h96, 8'h96, 8'h97, 8'h98, 8'h99, 8'h99, 8'h9A, 8'h9B, 8'h9B, 8'h9C, 8'h9D, 8'h9E, 8'h9E,
	8'h9F, 8'hA0, 8'hA0, 8'hA1, 8'hA2, 8'hA3, 8'hA3, 8'hA4, 8'hA5, 8'hA5, 8'hA6, 8'hA7, 8'hA8, 8'hA8, 8'hA9, 8'hAA, 8'hAA, 8'hAB, 8'hAC, 8'hAD, 
	8'hAD, 8'hAE, 8'hAF, 8'hAF, 8'hB0, 8'hB1, 8'hB2, 8'hB2, 8'hB3, 8'hB4, 8'hB4, 8'hB5,	8'hB6
  };

  reg [7:0] blue_weight[0:255] = '{ // 0.0722*B
	8'h0, 8'h0, 8'h0, 8'h0, 8'h0, 8'h0, 8'h0, 8'h0, 8'h0, 8'h0, 8'h0, 8'h0, 8'h0, 8'h0, 8'h1, 8'h1, 8'h1, 8'h1, 8'h1, 8'h1, 8'h1, 8'h1, 8'h1, 
	8'h1, 8'h1, 8'h1, 8'h1, 8'h1, 8'h2, 8'h2, 8'h2, 8'h2, 8'h2, 8'h2, 8'h2, 8'h2, 8'h2, 8'h2, 8'h2, 8'h2, 8'h2, 8'h2, 8'h3, 8'h3, 8'h3, 8'h3, 
	8'h3, 8'h3, 8'h3, 8'h3, 8'h3, 8'h3, 8'h3, 8'h3, 8'h3, 8'h3, 8'h4, 8'h4, 8'h4, 8'h4, 8'h4, 8'h4, 8'h4, 8'h4, 8'h4, 8'h4, 8'h4, 8'h4, 8'h4, 
	8'h4, 8'h5, 8'h5, 8'h5, 8'h5, 8'h5, 8'h5, 8'h5, 8'h5, 8'h5, 8'h5, 8'h5, 8'h5, 8'h5, 8'h5, 8'h6, 8'h6, 8'h6, 8'h6, 8'h6, 8'h6, 8'h6, 8'h6, 
	8'h6, 8'h6, 8'h6, 8'h6, 8'h6, 8'h7, 8'h7, 8'h7, 8'h7, 8'h7, 8'h7, 8'h7, 8'h7, 8'h7, 8'h7, 8'h7, 8'h7, 8'h7, 8'h7, 8'h8, 8'h8, 8'h8, 8'h8, 
	8'h8, 8'h8, 8'h8, 8'h8, 8'h8, 8'h8, 8'h8, 8'h8, 8'h8, 8'h8, 8'h9, 8'h9, 8'h9, 8'h9, 8'h9, 8'h9, 8'h9, 8'h9, 8'h9, 8'h9, 8'h9, 8'h9, 8'h9, 
	8'h9, 8'hA, 8'hA, 8'hA, 8'hA, 8'hA, 8'hA, 8'hA, 8'hA, 8'hA, 8'hA, 8'hA, 8'hA, 8'hA, 8'hA, 8'hB, 8'hB, 8'hB, 8'hB, 8'hB, 8'hB, 8'hB, 8'hB, 
	8'hB, 8'hB, 8'hB, 8'hB, 8'hB, 8'hB, 8'hC, 8'hC, 8'hC, 8'hC, 8'hC, 8'hC, 8'hC, 8'hC, 8'hC, 8'hC, 8'hC, 8'hC, 8'hC, 8'hC, 8'hD, 8'hD, 8'hD, 
	8'hD, 8'hD, 8'hD, 8'hD, 8'hD, 8'hD, 8'hD, 8'hD, 8'hD, 8'hD, 8'hE, 8'hE, 8'hE, 8'hE, 8'hE, 8'hE, 8'hE, 8'hE, 8'hE, 8'hE, 8'hE, 8'hE, 8'hE, 
	8'hE, 8'hF, 8'hF, 8'hF, 8'hF, 8'hF, 8'hF, 8'hF, 8'hF, 8'hF, 8'hF, 8'hF, 8'hF, 8'hF, 8'hF, 8'h10, 8'h10, 8'h10, 8'h10, 8'h10, 8'h10, 8'h10,
	8'h10, 8'h10, 8'h10, 8'h10, 8'h10, 8'h10, 8'h10, 8'h11, 8'h11, 8'h11, 8'h11, 8'h11, 8'h11, 8'h11, 8'h11, 8'h11, 8'h11, 8'h11, 8'h11, 8'h11,
	8'h11, 8'h12, 8'h12, 8'h12, 8'h12, 8'h12, 8'h12
  };
  
  always @(posedge clk_vid) begin
	if(ce_pix) begin

		r <= R;
		g <= G;
		b <= B;
		
		mono         <= red_weight[r] + green_weight[g] + blue_weight[b];
		shifted_mono <= red_weight[r] + green_weight[g] + blue_weight[b] >> 1;
		  
		case(gfx_mode[2:0])
			// Green monitor mode
			3'b001	: begin
				R_OUT <= 8'b0;
				G_OUT <= mono < 8'hF ? 8'hF : mono;	// minimum level to simulate glow of phosphor 	 		
				B_OUT <= 8'b1;                      // very slight bluish tinge to all modes (8'b1)

			end
			// Amber monitor mode
			3'b010	: begin
				R_OUT <= mono < 8'h8 ? 8'h8 : mono;	
				G_OUT <= shifted_mono;
				B_OUT <= 8'b1; 
			end
			// B&W
			3'b011	: begin
				R_OUT <= mono; 
				G_OUT <= mono; 
				B_OUT <= mono; 
			end
			// Red monitor mode
			3'b100	: begin
				R_OUT <= mono < 8'h8 ? 8'h8 : mono;	
				G_OUT <= 8'b0;
				B_OUT <= 8'b1; 
			end
			// Blue
			3'b101	: begin
				R_OUT <= 8'b0; 
				G_OUT <= shifted_mono;
				B_OUT <= mono < 8'h8 ? 8'h8 : mono;	
			end
			// Fuchsia
			3'b110	: begin
				R_OUT <= mono < 8'h8 ? 8'h8 : mono;	
				G_OUT <= 8'b0;
				B_OUT <= shifted_mono;
			end
			// Purple
			3'b111	: begin
				R_OUT <= shifted_mono;
				G_OUT <= 8'b0;
				B_OUT <= mono < 8'h8 ? 8'h8 : mono;	
			end
			// Color mode i.e. 3'b000
			default: begin
				R_OUT <= r;
				G_OUT <= g;
				B_OUT <= b;
			end
		endcase

	end
   end
  
endmodule