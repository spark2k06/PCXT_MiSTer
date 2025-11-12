// Copyright 2025, Waldo Alvarez, https://pipflow.com
module FPU_ABS_Unit(
    input  [79:0] in,   // 80-bit input floating-point number
    output [79:0] out   // 80-bit absolute value output
);
    // Clear the sign bit (bit 79) to compute the absolute value.
    assign out = {1'b0, in[78:0]};
endmodule
