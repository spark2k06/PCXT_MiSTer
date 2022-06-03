module ram #(parameter AW=16)
(
  input clka,
  input ena,
  input wea,
  input [AW-1:0] addra,
  input [7:0] dina,
  output reg [7:0] douta
);

reg [7:0] ram[(2**AW)-1:0];

always @(posedge clka)
  if (ena)
		if (wea)
			ram[addra] <= dina;
		else
			douta <= ram[addra];

endmodule