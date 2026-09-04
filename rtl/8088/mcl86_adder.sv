//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
// SPDX-FileType: SOURCE
// SPDX-FileCopyrightText: (c) 2020, Ted Fried <@MicroCoreLabs>
// SPDX-FileCopyrightText: (c) 2026, Marcus Andrade <marcus@opengateware.org>
//------------------------------------------------------------------------------
//
// MCL86 - Intel 8086/8088 Microprocessor Compatible Gateware IP Core
//
// Copyright (c) 2020, Ted Fried <@MicroCoreLabs>
// Copyright (c) 2026, Marcus Andrade <marcus@opengateware.org>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
//------------------------------------------------------------------------------
// Execution Unit Adder
//
// Description:
//   The EU's 16-bit adder, and every carry its flag logic needs. carry[4] is the
//   BCD auxiliary carry, carry[8] the byte carry, carry[16] the word carry, and
//   the signed overflows are carry[16]^carry[15] and carry[8]^carry[7].
//
//   Needing those intermediates is why this was originally a per-bit ripple
//   written out longhand inside mcl86_eu_core, with the carry recurrence spelled
//   out bit by bit:
//
//       carry[i+1] = (a[i] & b[i]) | (a[i] & carry[i]) | (b[i] & carry[i]);
//
//   That works, and it is what a textbook says a full adder is, but it hands the
//   synthesiser sixteen chained LUT expressions instead of an addition. Quartus
//   then cannot map the chain onto the ALM's dedicated carry hardware, and builds
//   it out of general logic. On Cyclone V that put carry[5] through carry[15] on
//   the critical path of the entire core: 3.08 ns of a 10 ns period, measured on
//   the fitted design, with the path running
//
//       ucode ROM -> operand mux -> carry[5] -> carry[7] -> carry[10]
//                 -> carry[12] -> carry[15] -> ALU output mux -> eu_biu_command
//
//   and it is why clk_100 reached only 88 MHz against its 100 MHz constraint.
//
//   A single '+' does map to the carry chain. The intermediate carries come back
//   out of it for one XOR each, because the full-adder sum is
//
//       sum[i] = a[i] ^ b[i] ^ carry[i]
//
//   and XOR is its own inverse, so
//
//       carry[i] = a[i] ^ b[i] ^ sum[i]
//
//   exactly, for every bit and every input. carry[0] needs no special case: it
//   comes out as a[0]^b[0]^(a[0]^b[0]^0) = 0 on its own.
//
//   This is bit-for-bit the same function as the ripple it replaces, not an
//   approximation of it and not a different overflow convention.
//   TESTBENCH/mcl86_adder_tb.sv holds the original expression as a reference
//   model and compares the two across every carry-propagation pattern that
//   exists plus a large random sample.
//
// Note:
//   The carries are outputs of the sum, so they arrive one XOR *after* it rather
//   than before it. The flag registers that consume them (eu_add_carry and
//   friends) are a clock boundary away with margin to spare; the sum is the one
//   with none, and the sum is what got faster.
//------------------------------------------------------------------------------

`default_nettype none
`timescale 1ns/1ps

module mcl86_adder
    (
        input  wire  [15:0] a,      // Operand 0
        input  wire  [15:0] b,      // Operand 1
        output wire  [15:0] sum,    // a + b, truncated to 16 bits
        output wire  [16:0] carry   // carry[i] is the carry INTO bit i; [16] is carry out
    );

    //--------------------------------------------------------------------------
    // The addition itself
    //--------------------------------------------------------------------------
    // Widened by one bit so the carry out is part of the result rather than
    // something that has to be reconstructed.
    wire [16:0] full = {1'b0, a} + {1'b0, b};

    assign sum       = full[15:0];
    assign carry[16] = full[16];

    //--------------------------------------------------------------------------
    // Recovering the intermediate carries
    //--------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_carry
            assign carry[i] = a[i] ^ b[i] ^ sum[i];
        end
    endgenerate

endmodule

`default_nettype wire
