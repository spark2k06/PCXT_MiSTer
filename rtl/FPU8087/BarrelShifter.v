// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Barrel Shifter - High-Performance Multi-bit Shifter for CORDIC
//
// This module implements a barrel shifter that can shift by any
// amount from 0 to 63 bits in a single clock cycle. It's optimized
// for CORDIC algorithms which require fast iterative shifts.
//
// Features:
// - 64-bit data width (suitable for FPU mantissa operations)
// - 6-bit shift amount (0-63 positions)
// - Supports left shift, logical right shift, and arithmetic right shift
// - Single-cycle operation (combinational logic)
// - Logarithmic depth (6 stages for 64-bit)
//=====================================================================

module BarrelShifter64(
    input [63:0] data_in,           // Input data
    input [5:0] shift_amount,       // Shift amount (0-63)
    input shift_direction,          // 0 = left, 1 = right
    input arithmetic,               // 0 = logical, 1 = arithmetic (for right shift only)
    output [63:0] data_out          // Shifted output
);

    // Internal wires for each stage of the barrel shifter
    wire [63:0] stage0, stage1, stage2, stage3, stage4, stage5;

    // Sign bit for arithmetic right shift
    wire sign_bit = data_in[63];

    //=================================================================
    // Stage 0: Shift by 0 or 1 bit
    //=================================================================
    assign stage0 = shift_amount[0] ?
                    (shift_direction ?
                        (arithmetic ? {sign_bit, data_in[63:1]} : {1'b0, data_in[63:1]}) :  // Right shift by 1
                        {data_in[62:0], 1'b0}) :                                             // Left shift by 1
                    data_in;                                                                  // No shift

    //=================================================================
    // Stage 1: Shift by 0 or 2 bits
    //=================================================================
    assign stage1 = shift_amount[1] ?
                    (shift_direction ?
                        (arithmetic ? {{2{sign_bit}}, stage0[63:2]} : {2'b0, stage0[63:2]}) : // Right shift by 2
                        {stage0[61:0], 2'b0}) :                                                 // Left shift by 2
                    stage0;                                                                      // No shift

    //=================================================================
    // Stage 2: Shift by 0 or 4 bits
    //=================================================================
    assign stage2 = shift_amount[2] ?
                    (shift_direction ?
                        (arithmetic ? {{4{sign_bit}}, stage1[63:4]} : {4'b0, stage1[63:4]}) : // Right shift by 4
                        {stage1[59:0], 4'b0}) :                                                 // Left shift by 4
                    stage1;                                                                      // No shift

    //=================================================================
    // Stage 3: Shift by 0 or 8 bits
    //=================================================================
    assign stage3 = shift_amount[3] ?
                    (shift_direction ?
                        (arithmetic ? {{8{sign_bit}}, stage2[63:8]} : {8'b0, stage2[63:8]}) : // Right shift by 8
                        {stage2[55:0], 8'b0}) :                                                 // Left shift by 8
                    stage2;                                                                      // No shift

    //=================================================================
    // Stage 4: Shift by 0 or 16 bits
    //=================================================================
    assign stage4 = shift_amount[4] ?
                    (shift_direction ?
                        (arithmetic ? {{16{sign_bit}}, stage3[63:16]} : {16'b0, stage3[63:16]}) : // Right shift by 16
                        {stage3[47:0], 16'b0}) :                                                    // Left shift by 16
                    stage3;                                                                          // No shift

    //=================================================================
    // Stage 5: Shift by 0 or 32 bits
    //=================================================================
    assign stage5 = shift_amount[5] ?
                    (shift_direction ?
                        (arithmetic ? {{32{sign_bit}}, stage4[63:32]} : {32'b0, stage4[63:32]}) : // Right shift by 32
                        {stage4[31:0], 32'b0}) :                                                    // Left shift by 32
                    stage4;                                                                          // No shift

    // Final output
    assign data_out = stage5;

endmodule


//=====================================================================
// 80-bit Barrel Shifter for Extended Precision Operations
//
// This variant handles 80-bit data for extended precision FPU
// operations. Useful for CORDIC operations on full extended
// precision mantissas.
//=====================================================================

module BarrelShifter80(
    input [79:0] data_in,           // Input data (80-bit)
    input [6:0] shift_amount,       // Shift amount (0-127, though max useful is 79)
    input shift_direction,          // 0 = left, 1 = right
    input arithmetic,               // 0 = logical, 1 = arithmetic (for right shift only)
    output [79:0] data_out          // Shifted output
);

    // Internal wires for each stage
    wire [79:0] stage0, stage1, stage2, stage3, stage4, stage5, stage6;

    // Sign bit for arithmetic right shift
    wire sign_bit = data_in[79];

    //=================================================================
    // Stage 0: Shift by 0 or 1 bit
    //=================================================================
    assign stage0 = shift_amount[0] ?
                    (shift_direction ?
                        (arithmetic ? {sign_bit, data_in[79:1]} : {1'b0, data_in[79:1]}) :
                        {data_in[78:0], 1'b0}) :
                    data_in;

    //=================================================================
    // Stage 1: Shift by 0 or 2 bits
    //=================================================================
    assign stage1 = shift_amount[1] ?
                    (shift_direction ?
                        (arithmetic ? {{2{sign_bit}}, stage0[79:2]} : {2'b0, stage0[79:2]}) :
                        {stage0[77:0], 2'b0}) :
                    stage0;

    //=================================================================
    // Stage 2: Shift by 0 or 4 bits
    //=================================================================
    assign stage2 = shift_amount[2] ?
                    (shift_direction ?
                        (arithmetic ? {{4{sign_bit}}, stage1[79:4]} : {4'b0, stage1[79:4]}) :
                        {stage1[75:0], 4'b0}) :
                    stage1;

    //=================================================================
    // Stage 3: Shift by 0 or 8 bits
    //=================================================================
    assign stage3 = shift_amount[3] ?
                    (shift_direction ?
                        (arithmetic ? {{8{sign_bit}}, stage2[79:8]} : {8'b0, stage2[79:8]}) :
                        {stage2[71:0], 8'b0}) :
                    stage2;

    //=================================================================
    // Stage 4: Shift by 0 or 16 bits
    //=================================================================
    assign stage4 = shift_amount[4] ?
                    (shift_direction ?
                        (arithmetic ? {{16{sign_bit}}, stage3[79:16]} : {16'b0, stage3[79:16]}) :
                        {stage3[63:0], 16'b0}) :
                    stage3;

    //=================================================================
    // Stage 5: Shift by 0 or 32 bits
    //=================================================================
    assign stage5 = shift_amount[5] ?
                    (shift_direction ?
                        (arithmetic ? {{32{sign_bit}}, stage4[79:32]} : {32'b0, stage4[79:32]}) :
                        {stage4[47:0], 32'b0}) :
                    stage4;

    //=================================================================
    // Stage 6: Shift by 0 or 64 bits
    //=================================================================
    assign stage6 = shift_amount[6] ?
                    (shift_direction ?
                        (arithmetic ? {{64{sign_bit}}, stage5[79:64]} : {64'b0, stage5[79:64]}) :
                        {stage5[15:0], 64'b0}) :
                    stage5;

    // Final output
    assign data_out = stage6;

endmodule


//=====================================================================
// Pipelined Barrel Shifter for High-Frequency Designs
//
// This variant adds pipeline registers between stages for higher
// clock frequency operation. Useful when the critical path through
// the combinational barrel shifter is too long.
//=====================================================================

module BarrelShifter64_Pipelined(
    input clk,
    input reset,
    input [63:0] data_in,
    input [5:0] shift_amount,
    input shift_direction,
    input arithmetic,
    output reg [63:0] data_out
);

    // Pipeline registers for data
    reg [63:0] stage0_reg, stage1_reg, stage2_reg, stage3_reg, stage4_reg, stage5_reg;

    // Pipeline registers for control signals
    reg [5:0] shift_reg[0:5];
    reg dir_reg[0:5];
    reg arith_reg[0:5];

    // Intermediate results
    wire [63:0] stage0, stage1, stage2, stage3, stage4, stage5;
    wire sign_bit;

    // Sign bit propagation through pipeline
    reg sign_bit_reg[0:5];
    assign sign_bit = data_in[63];

    integer i;

    //=================================================================
    // Pipeline Stage 0: Shift by 0 or 1 bit
    //=================================================================
    assign stage0 = shift_reg[0][0] ?
                    (dir_reg[0] ?
                        (arith_reg[0] ? {sign_bit_reg[0], stage0_reg[63:1]} : {1'b0, stage0_reg[63:1]}) :
                        {stage0_reg[62:0], 1'b0}) :
                    stage0_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            stage0_reg <= 64'b0;
            shift_reg[0] <= 6'b0;
            dir_reg[0] <= 1'b0;
            arith_reg[0] <= 1'b0;
            sign_bit_reg[0] <= 1'b0;
        end else begin
            stage0_reg <= data_in;
            shift_reg[0] <= shift_amount;
            dir_reg[0] <= shift_direction;
            arith_reg[0] <= arithmetic;
            sign_bit_reg[0] <= sign_bit;
        end
    end

    //=================================================================
    // Pipeline Stages 1-5 (similar pattern)
    //=================================================================
    genvar stage;
    generate
        for (stage = 1; stage < 6; stage = stage + 1) begin : pipeline_stages
            wire [63:0] current_stage;
            wire [63:0] prev_stage_reg;

            assign prev_stage_reg = (stage == 1) ? stage1_reg :
                                   (stage == 2) ? stage2_reg :
                                   (stage == 3) ? stage3_reg :
                                   (stage == 4) ? stage4_reg :
                                                  stage5_reg;

            assign current_stage = shift_reg[stage][stage] ?
                                  (dir_reg[stage] ?
                                      (arith_reg[stage] ?
                                          {{(1<<stage){sign_bit_reg[stage]}}, prev_stage_reg[63:(1<<stage)]} :
                                          {{(1<<stage){1'b0}}, prev_stage_reg[63:(1<<stage)]}) :
                                      {prev_stage_reg[63-(1<<stage):0], {(1<<stage){1'b0}}}) :
                                  prev_stage_reg;

            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    if (stage == 1) stage1_reg <= 64'b0;
                    else if (stage == 2) stage2_reg <= 64'b0;
                    else if (stage == 3) stage3_reg <= 64'b0;
                    else if (stage == 4) stage4_reg <= 64'b0;
                    else if (stage == 5) stage5_reg <= 64'b0;

                    shift_reg[stage] <= 6'b0;
                    dir_reg[stage] <= 1'b0;
                    arith_reg[stage] <= 1'b0;
                    sign_bit_reg[stage] <= 1'b0;
                end else begin
                    if (stage == 1) stage1_reg <= stage0;
                    else if (stage == 2) stage2_reg <= stage1;
                    else if (stage == 3) stage3_reg <= stage2;
                    else if (stage == 4) stage4_reg <= stage3;
                    else if (stage == 5) stage5_reg <= stage4;

                    shift_reg[stage] <= shift_reg[stage-1];
                    dir_reg[stage] <= dir_reg[stage-1];
                    arith_reg[stage] <= arith_reg[stage-1];
                    sign_bit_reg[stage] <= sign_bit_reg[stage-1];
                end
            end
        end
    endgenerate

    // Separate assignments for intermediate stages to avoid generate block complexity
    assign stage1 = shift_reg[1][1] ?
                    (dir_reg[1] ?
                        (arith_reg[1] ? {{2{sign_bit_reg[1]}}, stage1_reg[63:2]} : {2'b0, stage1_reg[63:2]}) :
                        {stage1_reg[61:0], 2'b0}) :
                    stage1_reg;

    assign stage2 = shift_reg[2][2] ?
                    (dir_reg[2] ?
                        (arith_reg[2] ? {{4{sign_bit_reg[2]}}, stage2_reg[63:4]} : {4'b0, stage2_reg[63:4]}) :
                        {stage2_reg[59:0], 4'b0}) :
                    stage2_reg;

    assign stage3 = shift_reg[3][3] ?
                    (dir_reg[3] ?
                        (arith_reg[3] ? {{8{sign_bit_reg[3]}}, stage3_reg[63:8]} : {8'b0, stage3_reg[63:8]}) :
                        {stage3_reg[55:0], 8'b0}) :
                    stage3_reg;

    assign stage4 = shift_reg[4][4] ?
                    (dir_reg[4] ?
                        (arith_reg[4] ? {{16{sign_bit_reg[4]}}, stage4_reg[63:16]} : {16'b0, stage4_reg[63:16]}) :
                        {stage4_reg[47:0], 16'b0}) :
                    stage4_reg;

    assign stage5 = shift_reg[5][5] ?
                    (dir_reg[5] ?
                        (arith_reg[5] ? {{32{sign_bit_reg[5]}}, stage5_reg[63:32]} : {32'b0, stage5_reg[63:32]}) :
                        {stage5_reg[31:0], 32'b0}) :
                    stage5_reg;

    // Final output register
    always @(posedge clk or posedge reset) begin
        if (reset)
            data_out <= 64'b0;
        else
            data_out <= stage5;
    end

endmodule
