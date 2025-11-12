// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// CORDIC Rotator using Barrel Shifter
//
// This module demonstrates how to use the barrel shifter for CORDIC
// (COordinate Rotation DIgital Computer) algorithms. CORDIC is widely
// used in FPUs for computing trigonometric, hyperbolic, logarithmic,
// and exponential functions.
//
// This implementation performs vectoring mode CORDIC to compute
// arctangent and magnitude (useful for complex-to-polar conversion).
//
// Algorithm:
// For each iteration i (0 to N-1):
//   if y < 0:
//     x_new = x - (y >> i)
//     y_new = y + (x >> i)
//     z_new = z - atan(2^-i)
//   else:
//     x_new = x + (y >> i)
//     y_new = y - (x >> i)
//     z_new = z + atan(2^-i)
//
// The barrel shifter makes the (x >> i) and (y >> i) operations
// very fast and efficient.
//=====================================================================

module CORDIC_Rotator_SingleCycle(
    input [63:0] x_in,              // Initial X coordinate (signed)
    input [63:0] y_in,              // Initial Y coordinate (signed)
    input [5:0] iteration,          // Iteration number (0-63)
    input [63:0] atan_value,        // Arctangent value for this iteration
    output reg [63:0] x_out,        // Updated X coordinate
    output reg [63:0] y_out,        // Updated Y coordinate
    output reg [63:0] z_out,        // Accumulated angle
    input [63:0] z_in               // Previous angle accumulator
);

    // Shifted values using barrel shifter
    wire [63:0] x_shifted;
    wire [63:0] y_shifted;

    // Direction control (based on y sign)
    wire y_negative = y_in[63];

    // Instantiate barrel shifters for x and y
    BarrelShifter64 shifter_x (
        .data_in(x_in),
        .shift_amount(iteration),
        .shift_direction(1'b1),         // Right shift
        .arithmetic(1'b1),              // Arithmetic (sign-extend)
        .data_out(x_shifted)
    );

    BarrelShifter64 shifter_y (
        .data_in(y_in),
        .shift_amount(iteration),
        .shift_direction(1'b1),         // Right shift
        .arithmetic(1'b1),              // Arithmetic (sign-extend)
        .data_out(y_shifted)
    );

    // CORDIC rotation logic
    always @(*) begin
        if (y_negative) begin
            // Rotate clockwise
            x_out = x_in - y_shifted;
            y_out = y_in + x_shifted;
            z_out = z_in - atan_value;
        end else begin
            // Rotate counter-clockwise
            x_out = x_in + y_shifted;
            y_out = y_in - x_shifted;
            z_out = z_in + atan_value;
        end
    end

endmodule


//=====================================================================
// Iterative CORDIC Engine
//
// This module performs multiple CORDIC iterations using a state machine.
// It demonstrates how to use the barrel shifter in an iterative design
// for computing transcendental functions.
//=====================================================================

module CORDIC_Engine(
    input clk,
    input reset,
    input start,                    // Start computation
    input [63:0] x_initial,         // Initial X value
    input [63:0] y_initial,         // Initial Y value
    input [5:0] num_iterations,     // Number of iterations (1-64)
    output reg [63:0] x_final,      // Final X (magnitude)
    output reg [63:0] y_final,      // Final Y (should approach 0)
    output reg [63:0] angle,        // Final angle (arctangent)
    output reg done                 // Computation complete
);

    // State machine
    localparam IDLE = 2'b00;
    localparam COMPUTE = 2'b01;
    localparam DONE = 2'b10;

    reg [1:0] state;
    reg [5:0] iteration_counter;

    // Current values
    reg [63:0] x_curr, y_curr, z_curr;

    // Next values from CORDIC rotator
    wire [63:0] x_next, y_next, z_next;

    // Arctangent lookup table (scaled by 2^32 for fixed-point)
    // atan(2^-i) for i = 0 to 15 (16 entries)
    reg [63:0] atan_table [0:15];

    initial begin
        // Arctangent values in Q32.32 fixed-point format
        // atan(2^0) = 45 degrees = 0.785398163 radians
        atan_table[0]  = 64'h00000000C90FDAA2; // atan(1.0)
        atan_table[1]  = 64'h0000000076B19C15; // atan(0.5)
        atan_table[2]  = 64'h000000003EB6EBF2; // atan(0.25)
        atan_table[3]  = 64'h000000001FD5BA9A; // atan(0.125)
        atan_table[4]  = 64'h000000000FFAADDB; // atan(0.0625)
        atan_table[5]  = 64'h0000000007FF556F; // atan(0.03125)
        atan_table[6]  = 64'h0000000003FFEAAB; // atan(0.015625)
        atan_table[7]  = 64'h0000000001FFFD55; // atan(0.0078125)
        atan_table[8]  = 64'h0000000000FFFFAA; // atan(0.00390625)
        atan_table[9]  = 64'h00000000007FFFF5; // atan(0.001953125)
        atan_table[10] = 64'h00000000003FFFFA; // atan(0.0009765625)
        atan_table[11] = 64'h00000000001FFFFF; // atan(0.00048828125)
        atan_table[12] = 64'h0000000000100000; // atan(0.000244140625)
        atan_table[13] = 64'h0000000000080000; // atan(0.0001220703125)
        atan_table[14] = 64'h0000000000040000; // atan(0.00006103515625)
        atan_table[15] = 64'h0000000000020000; // atan(0.000030517578125)
    end

    // Get current arctangent value
    wire [63:0] current_atan = (iteration_counter < 16) ?
                               atan_table[iteration_counter] : 64'h0;

    // Instantiate single-cycle CORDIC rotator
    CORDIC_Rotator_SingleCycle rotator (
        .x_in(x_curr),
        .y_in(y_curr),
        .iteration(iteration_counter),
        .atan_value(current_atan),
        .x_out(x_next),
        .y_out(y_next),
        .z_out(z_next),
        .z_in(z_curr)
    );

    // State machine
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            x_curr <= 64'h0;
            y_curr <= 64'h0;
            z_curr <= 64'h0;
            iteration_counter <= 6'h0;
            x_final <= 64'h0;
            y_final <= 64'h0;
            angle <= 64'h0;
            done <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        x_curr <= x_initial;
                        y_curr <= y_initial;
                        z_curr <= 64'h0;
                        iteration_counter <= 6'h0;
                        state <= COMPUTE;
                    end
                end

                COMPUTE: begin
                    // Update values from rotator
                    x_curr <= x_next;
                    y_curr <= y_next;
                    z_curr <= z_next;
                    iteration_counter <= iteration_counter + 1;

                    // Check if done
                    if (iteration_counter >= num_iterations - 1) begin
                        x_final <= x_next;
                        y_final <= y_next;
                        angle <= z_next;
                        state <= DONE;
                    end
                end

                DONE: begin
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule


//=====================================================================
// CORDIC Performance Notes
//=====================================================================
//
// The barrel shifter enables CORDIC to be very efficient:
//
// 1. Single-Cycle Shifts: Each CORDIC iteration requires shifts by
//    varying amounts. The barrel shifter can perform these in one
//    clock cycle, whereas a traditional shifter would take multiple
//    cycles.
//
// 2. Arbitrary Shift Amounts: CORDIC iterations need shifts by
//    1, 2, 3, ... N bits. The barrel shifter handles all these
//    efficiently without needing N different shift operations.
//
// 3. Arithmetic Shifts: CORDIC works with signed numbers, so
//    arithmetic (sign-extending) right shifts are essential.
//    The barrel shifter supports this natively.
//
// 4. Throughput: With the pipelined barrel shifter, you can achieve
//    one CORDIC iteration per clock cycle in a pipelined design.
//
// 5. Area vs Speed Trade-off: The combinational barrel shifter
//    (BarrelShifter64) gives fastest single-cycle operation but uses
//    more area. The pipelined version (BarrelShifter64_Pipelined)
//    allows higher clock frequencies at the cost of latency.
//
// Applications in 8087 FPU:
// - Transcendental functions: sin, cos, tan, atan, sinh, cosh, tanh
// - Logarithms and exponentials: log, ln, exp
// - Square root (using hyperbolic CORDIC)
// - Complex number operations: magnitude, phase
//=====================================================================
