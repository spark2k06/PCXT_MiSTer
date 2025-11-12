// Copyright 2025, Waldo Alvarez, https://pipflow.com
module FPU_Stack_Registers(
    input clk,
    input reset,
    // Stack control
    input [2:0] read_addr,      // Address to read (0-7)
    input [2:0] write_addr,     // Address to write (0-7)
    input [79:0] write_data,    // Data to write
    input write_enable,         // Write enable
    // Stack output
    output reg [79:0] read_data // Data read from read_addr
);

// Define 8 80-bit wide floating-point registers
reg [79:0] ST[7:0];

// Synchronous read and write
always @(posedge clk or posedge reset) begin
    if (reset) begin
        // Initialize all registers to positive zero
        ST[0] <= 80'h0000_0000_0000_0000_0000;
        ST[1] <= 80'h0000_0000_0000_0000_0000;
        ST[2] <= 80'h0000_0000_0000_0000_0000;
        ST[3] <= 80'h0000_0000_0000_0000_0000;
        ST[4] <= 80'h0000_0000_0000_0000_0000;
        ST[5] <= 80'h0000_0000_0000_0000_0000;
        ST[6] <= 80'h0000_0000_0000_0000_0000;
        ST[7] <= 80'h0000_0000_0000_0000_0000;
    end else begin
        if (write_enable) begin
            ST[write_addr] <= write_data;
        end
    end
end

// Asynchronous read
always @(*) begin
    read_data = ST[read_addr];
end

endmodule