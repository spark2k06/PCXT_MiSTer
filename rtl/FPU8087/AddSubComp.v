// Copyright 2025, Waldo Alvarez, https://pipflow.com
module FPU_AddSub_Comp_Unit(
    input         clk,
    input         invert_operand_b, // When high, invert operand_b's sign for subtraction
    input  [79:0] operand_a,        // 80-bit extended precision operand
    input  [79:0] operand_b,        // 80-bit extended precision operand
    output reg [79:0] result,       // Result of arithmetic operation (not normalized)
    output reg        cmp_equal,    // Comparison: operand_a == operand_b
    output reg        cmp_less,     // Comparison: operand_a < operand_b
    output reg        cmp_greater   // Comparison: operand_a > operand_b
);

    // Modify operand_b based on invert_operand_b signal.
    // When invert_operand_b is asserted, the sign bit is flipped (for subtraction).
    wire [79:0] operand_b_mod;
    assign operand_b_mod = invert_operand_b ? {~operand_b[79], operand_b[78:0]} : operand_b;

    // Perform a simple 80-bit addition. In a full IEEE-754 design, you would align, normalize, and round.
    wire [80:0] sum;
    assign sum = operand_a + operand_b_mod;

    // Update the arithmetic result on the clock edge.
    always @(posedge clk) begin
        // Note: The result is simply the sum (not normalized).
        result <= sum[79:0];
    end

    // Always calculate the comparison flags for operand_a and operand_b.
    // This simple comparison does not handle unordered cases (e.g. NaNs).
    always @(posedge clk) begin
        if (operand_a == operand_b) begin
            cmp_equal   <= 1;
            cmp_less    <= 0;
            cmp_greater <= 0;
        end
        else if (operand_a[79] != operand_b[79]) begin
            // When sign bits differ, the operand with a sign of '1' (negative) is less.
            if (operand_a[79] == 1) begin
                cmp_equal   <= 0;
                cmp_less    <= 1;
                cmp_greater <= 0;
            end 
            else begin
                cmp_equal   <= 0;
                cmp_less    <= 0;
                cmp_greater <= 1;
            end
        end 
        else begin
            // When signs are the same, compare the magnitude bits.
            if (operand_a[78:0] < operand_b[78:0]) begin
                cmp_equal   <= 0;
                cmp_less    <= 1;
                cmp_greater <= 0;
            end 
            else begin
                cmp_equal   <= 0;
                cmp_less    <= 0;
                cmp_greater <= 1;
            end
        end
    end

endmodule