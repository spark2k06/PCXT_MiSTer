// Copyright 2025, Waldo Alvarez, https://pipflow.com
// To create a 3-bit multiplexer with 4 inputs in Verilog, you need to define a module 
// that takes four 3-bit inputs, a 2-bit select line, and outputs a 3-bit value based 
// on the select line. The 2-bit select line is needed to choose among the 4 inputs 
// (00, 01, 10, 11).

module three_bit_4x1_mux(
    input [2:0] in0,       // First 3-bit input
    input [2:0] in1,       // Second 3-bit input
    input [2:0] in2,       // Third 3-bit input
    input [2:0] in3,       // Fourth 3-bit input
    input [1:0] select,    // 2-bit select input
    output reg [2:0] out   // 3-bit output
);

// Logic to select the output based on the select input
always @(*) begin
    case(select)
        2'b00: out = in0;
        2'b01: out = in1;
        2'b10: out = in2;
        2'b11: out = in3;
        default: out = 3'bxxx; // Undefined state
    endcase
end

endmodule
