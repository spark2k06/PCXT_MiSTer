// Copyright 2025, Waldo Alvarez, https://pipflow.com
module ieee754_normalizer_extended_precision(
    input clk,  // Clock input
    input [79:0] ieee754_in,
    output reg [79:0] ieee754_out
);
    // Pipeline stage registers
    reg [79:0] stage1_out;
    reg [14:0] stage1_exponent;
    reg sign;

    reg [79:0] stage2_out;
    reg [14:0] stage2_exponent;
    reg [3:0] byte_shift_amount;

    reg [79:0] stage3_out;
    reg [14:0] stage3_exponent;

    reg [2:0] bit_shift_amount;

    reg [79:0] stage4_out;
    reg [14:0] stage4_exponent;

    // Stage 1: Extract sign, exponent, and mantissa
    always @(posedge clk) begin
        sign <= ieee754_in[79];
        stage1_exponent <= ieee754_in[78:64];
        stage1_out <= {16'b0, ieee754_in[63:0]};
    end

    // Stage 2: Compute the byte shift amount
    leading_zero_byte_counter_byte lzc_byte(.in(stage1_out), .count(byte_shift_amount));
    always @(posedge clk) begin
        stage2_exponent <= stage1_exponent;
        stage2_out <= stage1_out;
    end

    // Stage 3: Perform the byte shift
    wire [79:0] shifted_mantissa_byte;
    multiplexer_based_byte_shifter_left mbbsbl(.data_in(stage2_out), .byte_shift(byte_shift_amount), .data_out(shifted_mantissa_byte));
    always @(posedge clk) begin
        stage3_out <= shifted_mantissa_byte;
        stage3_exponent <= stage2_exponent;
    end

    // Stage 4: Compute the bit shift amount
    leading_zero_counter_bit lzc_bit(.in(stage3_out[79:72]), .count(bit_shift_amount));
    always @(posedge clk) begin
        stage4_out <= stage3_out;
        stage4_exponent <= stage3_exponent;
    end

    // Stage 5: Perform the bit shift
    wire [79:0] shifted_mantissa_bit;
    multiplexer_based_bit_shifter_left mbbsl(.data_in(stage4_out), .shift_amount(bit_shift_amount), .data_out(shifted_mantissa_bit));

    // Stage 6: Adjust the exponent and reassemble the IEEE754 number
    always @(posedge clk) begin
        ieee754_out <= {sign, stage4_exponent - ({11'b0, byte_shift_amount} + {11'b0, bit_shift_amount}), shifted_mantissa_bit[63:0]};
    end

endmodule
