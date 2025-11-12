// Copyright 2025, Waldo Alvarez, https://pipflow.com

// Your suggestion to simultaneously compare each byte of the 64-bit number with zero and then use
// the combined result of these comparisons to look up a table is indeed a more efficient and parallel
// approach. This method leverages parallel processing capabilities of hardware and can lead to faster
// execution times, especially in hardware implementations like FPGAs or ASICs.

module leading_zero_byte_counter_byte(
    input [63:0] in,      // 64-bit input
    output reg [3:0] count // 4-bit output for the count of leading zero bytes
);

// Intermediate signals for byte-wise zero comparison
wire [7:0] zero_bytes;
assign zero_bytes[0] = (in[63:56] == 0);
assign zero_bytes[1] = (in[55:48] == 0);
assign zero_bytes[2] = (in[47:40] == 0);
assign zero_bytes[3] = (in[39:32] == 0);
assign zero_bytes[4] = (in[31:24] == 0);
assign zero_bytes[5] = (in[23:16] == 0);
assign zero_bytes[6] = (in[15:8] == 0);
assign zero_bytes[7] = (in[7:0] == 0);

// Lookup table for counting leading zero bytes
reg [3:0] lut [0:255]; // 256 entries for 8-bit input

// Initialize the lookup table with precomputed values
integer i;
initial begin
    for (i = 0; i < 256; i = i + 1) begin
        lut[i] = (i[7] == 0) + 
                 (i[7:6] == 0) + 
                 (i[7:5] == 0) + 
                 (i[7:4] == 0) + 
                 (i[7:3] == 0) + 
                 (i[7:2] == 0) + 
                 (i[7:1] == 0) + 
                 (i == 0);
    end
end

// Use the LUT to determine the count of leading zero bytes
always @(*) begin
    count = lut[zero_bytes];
end

endmodule