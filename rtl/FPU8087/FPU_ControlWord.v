// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Intel 8087 FPU Control Word
//
// 16-bit control word format:
// [15:12] : Reserved
// [11:10] : Rounding Control (RC)
//           00 = Round to nearest (even)
//           01 = Round down (toward -∞)
//           10 = Round up (toward +∞)
//           11 = Round toward zero (truncate)
// [9:8]   : Precision Control (PC)
//           00 = 24 bits (single precision)
//           01 = Reserved
//           10 = 53 bits (double precision)
//           11 = 64 bits (extended precision)
// [7:6]   : Reserved
// [5]     : Precision Exception Mask (PM)
// [4]     : Underflow Exception Mask (UM)
// [3]     : Overflow Exception Mask (OM)
// [2]     : Zero Divide Exception Mask (ZM)
// [1]     : Denormalized Operand Exception Mask (DM)
// [0]     : Invalid Operation Exception Mask (IM)
//=====================================================================

module FPU_ControlWord(
    input wire clk,
    input wire reset,

    // Write interface
    input wire [15:0] control_in,
    input wire        write_enable,

    // Read interface
    output reg [15:0] control_out,

    // Decoded outputs
    output reg [1:0]  rounding_mode,    // Rounding control
    output reg [1:0]  precision_mode,   // Precision control
    output reg        mask_precision,   // Mask precision exception
    output reg        mask_underflow,   // Mask underflow exception
    output reg        mask_overflow,    // Mask overflow exception
    output reg        mask_zero_div,    // Mask zero divide exception
    output reg        mask_denormal,    // Mask denormal exception
    output reg        mask_invalid      // Mask invalid exception
);

    //=================================================================
    // Control Word Register
    //=================================================================

    reg [15:0] control_word;

    //=================================================================
    // Main Logic
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Default control word: All exceptions masked, round to nearest, extended precision
            control_word <= 16'h037F;
        end else begin
            if (write_enable) begin
                control_word <= control_in;
            end
        end
    end

    //=================================================================
    // Decode Control Word
    //=================================================================

    always @(*) begin
        // Output full control word
        control_out = control_word;

        // Decode fields
        rounding_mode  = control_word[11:10];
        precision_mode = control_word[9:8];
        mask_precision = control_word[5];
        mask_underflow = control_word[4];
        mask_overflow  = control_word[3];
        mask_zero_div  = control_word[2];
        mask_denormal  = control_word[1];
        mask_invalid   = control_word[0];
    end

endmodule
