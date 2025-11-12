// Copyright 2025, Waldo Alvarez, https://pipflow.com

// This performs a lookup table to count the bits, takes some area but should be quite fast

module leading_zero_counter_bit(
    input [7:0] in,           // 8-bit input
    output reg [2:0] count    // 3-bit output to count from 0 to 7 leading zeros
);

// Lookup table for counting leading zeros
reg [2:0] lut [0:255]; // 256 entries for 8-bit input

initial begin
    // Initialize the lookup table with precomputed values

    lut[0]   = 3'b111; // 7 leading zeros
    lut[1]   = 3'b110; // 6 leading zeros
    lut[2]   = 3'b101; // 5 leading zeros
    lut[3]   = 3'b101; // 5 leading zeros


    lut[4]   = 3'b100; // 4 leading zeros
    lut[5]   = 3'b100;
    lut[6]   = 3'b100;
    lut[7]   = 3'b100;

    lut[8]   = 3'b011; // 3 leading zeros
    lut[9]   = 3'b011; 
    lut[10]  = 3'b011; 
    lut[11]  = 3'b011; 
    lut[12]  = 3'b011; 
    lut[13]  = 3'b011; 
    lut[14]  = 3'b011; 
    lut[15]  = 3'b011;

    lut[16]  = 3'b010; // 2 leading zeros
    lut[17]  = 3'b010;
    lut[18]  = 3'b010;
    lut[19]  = 3'b010;
    lut[20]  = 3'b010;
    lut[21]  = 3'b010;
    lut[22]  = 3'b010;
    lut[23]  = 3'b010;
    lut[24]  = 3'b010;
    lut[25]  = 3'b010;
    lut[26]  = 3'b010;
    lut[27]  = 3'b010;
    lut[28]  = 3'b010;
    lut[29]  = 3'b010;
    lut[30]  = 3'b010;
    lut[31]  = 3'b010;


    lut[32]  = 3'b001; // 1 leading zero
    lut[33]  = 3'b001;
    lut[34]  = 3'b001;
    lut[35]  = 3'b001;
    lut[36]  = 3'b001;
    lut[37]  = 3'b001;
    lut[38]  = 3'b001;
    lut[39]  = 3'b001;
    lut[40]  = 3'b001;
    lut[41]  = 3'b001;
    lut[42]  = 3'b001;
    lut[43]  = 3'b001;
    lut[44]  = 3'b001;
    lut[45]  = 3'b001;
    lut[46]  = 3'b001;
    lut[47]  = 3'b001;
    lut[48]  = 3'b001;
    lut[49]  = 3'b001;
    lut[50]  = 3'b001;
    lut[51]  = 3'b001;
    lut[52]  = 3'b001;
    lut[53]  = 3'b001;
    lut[54]  = 3'b001;
    lut[55]  = 3'b001;
    lut[56]  = 3'b001;
    lut[57]  = 3'b001;
    lut[58]  = 3'b001;
    lut[59]  = 3'b001;
    lut[60]  = 3'b001;
    lut[61]  = 3'b001;
    lut[62]  = 3'b001;

    lut[63]  = 3'b001;

    lut[64]  = 3'b000; // 0 leading zeros
    // Continue this pattern...
    lut[127] = 3'b000;
    lut[128] = 3'b000;
    // Continue this pattern...
    lut[255] = 3'b000; // 0 leading zeros
end

// Use the LUT to determine the number of leading zeros
always @(*) begin
    count = lut[in];
end

endmodule