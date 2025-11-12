// Copyright 2025, Waldo Alvarez, https://pipflow.com
module ieee754_rounding_unit_extended(
    input clk,              // Clock input
    input [79:0] in,        // Input floating-point number (80-bit extended precision)
    input [1:0] mode,       // Rounding mode: 00 for nearest, 01 for up, 10 for down, 11 for zero
    output reg [79:0] out   // Rounded floating-point number
);

    // Stage 1: Extract components
    reg [79:0] stage1_out;
    reg [1:0] stage1_mode;
    reg stage1_sign;
    reg [14:0] stage1_exponent;
    reg [63:0] stage1_mantissa;

    always @(posedge clk) begin
        stage1_sign <= in[79];
        stage1_exponent <= in[78:64];
        stage1_mantissa <= in[63:0];
        stage1_out <= in;
        stage1_mode <= mode;
    end


    // Stage 2: Determine rounding conditions
    reg [79:0] stage2_out;
    reg [1:0] stage2_mode;
    wire guard_bit = stage1_mantissa[0];
    wire round_bit = stage1_mantissa[1];
    wire sticky_bit = |stage1_mantissa[0];  // OR of all bits below the guard bit
    reg round_up_nearest, round_up, round_down, truncate;

    always @(posedge clk) begin
        round_up_nearest <= guard_bit & (round_bit | sticky_bit | stage1_mantissa[2]);
        round_up <= (stage1_sign & (stage1_mode == 2'b10)) | (~stage1_sign & (stage1_mode == 2'b01)) | (round_up_nearest & (stage1_mode == 2'b00));
        round_down <= (stage1_sign & (stage1_mode == 2'b01)) | (~stage1_sign & (stage1_mode == 2'b10));
        truncate <= stage1_mode == 2'b11;
        stage2_out <= stage1_out;
        stage2_mode <= stage1_mode;
    end


    // Stage 3: Perform rounding
    wire [64:0] rounded_mantissa;
    wire [14:0] adjusted_exponent;
    wire [63:0] adjusted_mantissa;
    wire overflow_to_inf, underflow_to_zero;

    assign rounded_mantissa = {1'b0, stage2_out[63:1]} + round_up;
    assign adjusted_exponent = stage2_out[78:64] + (rounded_mantissa[64] & ~&stage2_out[78:64]);
    assign adjusted_mantissa = (truncate ? stage2_out[63:1] : rounded_mantissa[63:0]) | (rounded_mantissa[64] & &stage2_out[78:64]);
    assign overflow_to_inf = &stage2_out[78:64] & rounded_mantissa[64];
    assign underflow_to_zero = ~|stage2_out[78:64];

    always @(posedge clk) begin
        if (overflow_to_inf) begin
            out <= {stage2_out[79], 15'h7FFF, 64'h0};  // output Infinity
        end else if (underflow_to_zero) begin
            out <= {stage2_out[79], 15'h0, 64'h0};     // output Zero
        end else begin
            out <= {stage2_out[79], adjusted_exponent, adjusted_mantissa};
        end
    end
endmodule

