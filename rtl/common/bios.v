module bios(
  input clka,
  input ena,
  input wea,
  input [15:0] addra,
  input [7:0] dina,
  output reg [7:0] douta
);

reg [7:0] bios[65535:0];

initial begin

$readmemh("24Kb_ff.hex", bios, 0, 24575);

// Get IBM Basic from here: http://www.minuszerodegrees.net/bios/BIOS_IBM5150_27OCT82_1501476_U33.BIN
// With a hexadecimal editor, get the text of the hexadecimal values and put in the common folder

//$readmemh("ibmbasic.hex", bios, 24576, 57343)
 
$readmemh("bios.hex", bios, 57344, 65535);

end

always @(posedge clka)
  if (ena)
		if (wea)
			bios[addra] <= dina;
		else
			douta <= bios[addra];

endmodule