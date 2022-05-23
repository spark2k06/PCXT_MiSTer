module vram(
  input clka,
  input ena,  
  input wea,
  input [14:0] addra,
  input [7:0] dina,
  output reg [7:0] douta,
  input clkb,
  input enb,
  input web,
  input [14:0] addrb,
  input [7:0] dinb,
  output reg [7:0] doutb
);

reg [7:0] vram[32767:0];

initial $readmemh("splash.hex", vram);

always @(posedge clka)
  if (ena)
		if (wea)
			vram[addra] <= dina;
		else
			douta <= vram[addra];
		
			
always @(posedge clkb)
  if (enb)
		if (web)
			vram[addrb] <= dinb;
		else
			doutb <= vram[addrb];

endmodule