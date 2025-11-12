// Copyright 2025, Waldo Alvarez, https://pipflow.com
// the HDL compiler should infer this is a ROM

module mathconstantsrom_32x80bits(
    input wire [4:0] address, // 5-bit address for 32 locations
    output reg [79:0] data    // 80-bit data width
);

    always @ (address) begin
        case (address)
            5'b00000: data = 80'h3FFF8000000000000000; // ? (pi) - placeholder value
            5'b00001: data = 80'h4000D555555555555555;  // e (Euler's number) - placeholder value
            5'b00010: data = 80'h3FFE62E42FEFA39EF357;  // ln2 (Natural Logarithm of 2) - placeholder value
            5'b00011: data = 80'h400026B17217F7D1CF79;  // ln10 (Natural Logarithm of 10) - placeholder value
            5'b00100: data = 80'h40004D104D427C4D2C1D;  // log?10 (Log Base 2 of 10) - placeholder value
            5'b00101: data = 80'h3FFD34413509F79FF9F2;  // log??2 (Log Base 10 of 2) - placeholder value
            5'b00110: data = 80'h3FFF0000000000000000;  // 1 (One) - example value, replace with actual
            5'b00111: data = 80'h00000000000000000000;  // 0 (Zero) - actual value
            5'b01000: data = 80'h3FFE0000000000000000;  // 0.5 (One Half) - example value, replace with actual
            // ...
            // Include all 32 cases, one for each address
            // ...
            5'b11110: data = 80'h00000000000000000000;
            5'b11111: data = 80'h00000000000000000000;
            default: data = 80'h0; // Default value if address is out of range
        endcase
    end

endmodule
