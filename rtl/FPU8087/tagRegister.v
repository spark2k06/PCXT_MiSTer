// Copyright 2025, Waldo Alvarez, https://pipflow.com
module FPU_Tag_Register(
    input clk,
    input reset,
    // Control inputs
    input [15:0] write_data,
    input write_enable,
    // Tag register output
    output reg [15:0] tag_register,
    // Individual tag outputs for convenience
    output wire [1:0] tag_ST0,
    output wire [1:0] tag_ST1,
    output wire [1:0] tag_ST2,
    output wire [1:0] tag_ST3,
    output wire [1:0] tag_ST4,
    output wire [1:0] tag_ST5,
    output wire [1:0] tag_ST6,
    output wire [1:0] tag_ST7
);

// Tag values according to 8087 spec:
// 00 = Valid (non-zero)
// 01 = Zero
// 10 = Special (NaN, Infinity, Denormal)
// 11 = Empty

// Aliases for each tag pair (2 bits per stack register)
assign tag_ST0 = tag_register[1:0];   // Tag for ST(0)
assign tag_ST1 = tag_register[3:2];   // Tag for ST(1)
assign tag_ST2 = tag_register[5:4];   // Tag for ST(2)
assign tag_ST3 = tag_register[7:6];   // Tag for ST(3)
assign tag_ST4 = tag_register[9:8];   // Tag for ST(4)
assign tag_ST5 = tag_register[11:10]; // Tag for ST(5)
assign tag_ST6 = tag_register[13:12]; // Tag for ST(6)
assign tag_ST7 = tag_register[15:14]; // Tag for ST(7)

// Synchronous logic for updating the tag register
always @(posedge clk or posedge reset) begin
    if (reset) begin
        tag_register <= 16'hFFFF; // All stack registers initially empty (11 = empty)
    end else if (write_enable) begin
        tag_register <= write_data;
    end
end

endmodule
