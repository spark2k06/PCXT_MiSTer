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
// Execution Unit Microcode ROM
//
// Description:
//   4K x 32 microcode store for mcl86_eu_core. Single synchronous read port,
//   inferred as a block ROM on every target. Each word is one microinstruction;
//   the field layout lives in mcl86_eu_core.sv, which decodes it.
//
//   The read is REGISTERED, and that one clock of latency is what gives the EU
//   sequencer its two-microword lead over the word it is executing. Do not
//   "optimize" this into an asynchronous read: the microcode, the pipeline stall
//   on taken jumps, and every microcode-address marker in the EU assume it.
//
// ROM image:
//   mcl86_ucode.mem is generated and validated by the tools in tools/ - ucasm.py
//   assembles it, ucdis.py disassembles it, and uccheck.py proves the round-trip
//   is lossless and that the EU's watched addresses still line up. Edit the ROM
//   through those tools, not by hand.
//
// Limitations:
//   - $readmemh resolves its path against the SIMULATOR's working directory, not
//     this file's. Testbenches must either run from a directory containing
//     mcl86_ucode.mem or drop a copy beside the executable (sim/sst/Makefile
//     does the latter). A missing file loads all-X and the core simply spins.
//   - Synthesis relies on the initial block for ROM contents. That is supported
//     by Quartus, Vivado and yosys, but it is not a reset value - the array is
//     never re-initialized after power-up.
//------------------------------------------------------------------------------

`default_nettype none
`timescale 1ns/1ps

module mcl86_ucode
    (
        // System Interface
        input  wire         clk,   // Core clock; read is registered on the rising edge
        // ROM Read Port
        input  wire  [11:0] addr,  // Microcode address (word address, 0..4095)
        output logic [31:0] dout   // Microword, valid one clock after addr
    );

    //--------------------------------------------------------------------------
    // ROM Storage
    //--------------------------------------------------------------------------
    logic [31:0] mem[0:4095];

    //--------------------------------------------------------------------------
    // ROM Initialization (Vivado / Others)
    //--------------------------------------------------------------------------
    initial begin
        $readmemh("mcl86_ucode.mem", mem);
    end

    //--------------------------------------------------------------------------
    // ROM Read Port
    //--------------------------------------------------------------------------
    // Registered read - the EU's 2-word sequencer lead depends on this latency.
    always_ff @(posedge clk) begin : read_mem
        dout <= mem[addr];
    end

endmodule

`default_nettype wire
