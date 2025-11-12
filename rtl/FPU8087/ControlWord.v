// Copyright 2025, Waldo Alvarez, https://pipflow.com
module FPU_Control_Word_Register(
    input clk,
    input reset,
    // Control inputs
    input [15:0] write_data,
    input write_enable,
    // Control word output
    output reg [15:0] control_word,
    // Individual field outputs for convenience
    output wire [5:0] exception_masks,
    output wire interrupt_enable_mask,
    output wire infinity_control,
    output wire [1:0] rounding_control,
    output wire [1:0] precision_control
);

// Aliases for different parts of the control word
assign exception_masks = control_word[5:0]; // IM, DM, ZM, OM, UM, PM: Exception masks
assign interrupt_enable_mask = control_word[7]; // IEM: Interrupt Enable Mask (bit 6 is reserved)
assign infinity_control = control_word[12]; // IC: Infinity Control (bits 8-11 are reserved in original 8087)
assign rounding_control = control_word[11:10]; // RC: Rounding Control
assign precision_control = control_word[9:8]; // PC: Precision Control

// Synchronous logic for updating the control word
always @(posedge clk or posedge reset) begin
    if (reset) begin
        control_word <= 16'h037F; // Default 8087 reset value: all exceptions masked
    end else if (write_enable) begin
        control_word <= write_data;
    end
end

endmodule