// Copyright 2025, Waldo Alvarez, https://pipflow.com
module FPU_Status_Word(
    input clk,
    input reset,
    // Control inputs
    input [15:0] write_data,
    input write_enable,
    // Status outputs
    output reg [15:0] status_word,
    // Individual bit outputs for convenience
    output wire busy_bit,
    output wire [3:0] condition_codes,
    output wire [2:0] stack_ptr,
    output wire error_summary_bit,
    output wire stack_fault,
    output wire precision_error,
    output wire underflow_error,
    output wire overflow_error,
    output wire zero_divide_error,
    output wire denormalized_error,
    output wire invalid_operation_error
);

// Aliases for different parts of the status word
assign busy_bit = status_word[15]; // B: Busy bit
assign condition_codes = status_word[14:11]; // C3-C0: Condition code bits
assign stack_ptr = status_word[10:8]; // TOP: Top of stack pointer (ST0-ST7)
assign error_summary_bit = status_word[7]; // ES: Error summary bit
assign stack_fault = status_word[6]; // SF: Stack fault
assign precision_error = status_word[5]; // PE: Precision error
assign underflow_error = status_word[4]; // UE: Underflow error
assign overflow_error = status_word[3]; // OE: Overflow error
assign zero_divide_error = status_word[2]; // ZE: Zero divide error
assign denormalized_error = status_word[1]; // DE: Denormalized error
assign invalid_operation_error = status_word[0]; // IE: Invalid operation error

// Synchronous logic for updating the status word
always @(posedge clk or posedge reset) begin
    if (reset) begin
        status_word <= 16'b0;
    end else if (write_enable) begin
        status_word <= write_data;
    end
end

endmodule
