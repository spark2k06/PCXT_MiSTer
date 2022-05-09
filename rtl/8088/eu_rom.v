module eu_rom(
  input clka,
  input [11:0] addra,
  output reg [31:0] douta
);

reg [31:0] memory[3961:0];

initial $readmemb("microcode.mem", memory);

always @(posedge clka)
  douta <= memory[addra];

endmodule