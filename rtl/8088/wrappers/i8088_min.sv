//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
// SPDX-FileType: SOURCE
// SPDX-FileCopyrightText: (c) 2020, Ted Fried <@MicroCoreLabs>
// SPDX-FileCopyrightText: (c) 2026, Marcus Andrade <marcus@opengateware.org>
//------------------------------------------------------------------------------
//
// Intel 8088 Microprocessor Core
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
// Intel 8088 CPU - Minimum Bus Mode
//
// Description:
//   Top level for an 8088 in MINIMUM mode: mcl86_eu_core (microcoded execution
//   unit) plus mcl86_biu_min (bus interface unit). 16-bit internal architecture
//   over an 8-bit external data bus, with a 20-bit multiplexed address/data bus
//   reaching 1 MB (0x00000-0xFFFFF).
//
//   In minimum mode the CPU drives its own bus control pins - ALE, RD_n, WR_n,
//   IOM, DTR, DEN, INTA_n - with no external 8288 needed. This is the PC/XT-style
//   configuration. i8088 is the same core wired for maximum mode, where those
//   pins are replaced by a status code for an external bus controller.
//
//   The two units overlap: the BIU refills a 4-byte prefetch queue whenever the
//   bus is otherwise idle while the EU executes out of it.
//
// Bus cycle (8-bit data bus - a WORD access runs as two byte cycles):
//
//   CLK    _/~~\__/~~\__/~~\__/~~\__/~~\__/~~\__
//            T1     T2     T3    (Tw)    T4
//   ALE    _/~~\_________________________________   address valid in T1,
//   AD     <  ADDR ><======= DATA =============>     latch on the ALE falling edge
//   RD_n   ~~~~~~~~\______________________/~~~~~~   data valid T3-T4 on a read
//   READY  ------------------< sampled >---------   low in T3 inserts Tw
//
//   IOM selects the space: 0 = memory, 1 = I/O.
//
// Clocking: CORE_CLK is the fast internal clock that runs both units. CLK is the
//   8088 pin clock and is only edge-detected inside the BIU to place bus events
//   at real 8088 timing - it is not a second clock domain.
//
// Limitations:
//   - This wrapper exposes no turbo controls, because mcl86_biu_min has none.
//     Cycle accuracy is always on here; the max-mode BIUs are the ones with a
//     scalable counter (see i8088 / i8086).
//   - The BIU's BIU_SEGMENT output is left unconnected in this wrapper.
//   - TEST_N is tied low at the EU, so a WAIT instruction completes immediately
//     rather than waiting on a coprocessor.
//
// References:
//   - Intel 8088 datasheet - minimum mode pin functions, bus cycle timing
//   - Intel 8086 Family User's Manual (Oct 1979)
//------------------------------------------------------------------------------

`default_nettype none
`timescale 1ns/1ps

module i8088_min
    (
        // System Interface
        input  wire         CORE_CLK,     // High-speed core clock (4x-8x CPU frequency)
        input  wire         CLK,          // CPU clock (4.77-10 MHz typical)
        input  wire         RESET,        // Synchronous reset (active high)
        // Bus Control Interface
        input  wire         READY,        // Memory/IO ready (0=insert wait states)
        input  wire         INTR,         // Maskable interrupt request
        input  wire         NMI,          // Non-maskable interrupt
        // Memory/IO Interface
        output logic [19:0] addr,         // 20-bit address bus (1MB address space)
        output logic  [7:0] dout,         // 8-bit data output
        input  wire   [7:0] din,          // 8-bit data input
        // Bus Control Outputs
        output logic        ALE,          // Address Latch Enable (address valid strobe)
        output logic        INTA_n,       // Interrupt Acknowledge (active low)
        output logic        RD_n,         // Read strobe (active low)
        output logic        WR_n,         // Write strobe (active low)
        output logic        IOM,          // Memory(0)/IO(1) space indicator
        output logic        DTR,          // Data Transmit/Receive direction
        output logic        DEN           // Data Enable for external bus transceivers
    );

    //--------------------------------------------------------------------------
    // Internal Interface Signals
    //--------------------------------------------------------------------------
    // BIU-EU Command and Control Interface
    logic [15:0] t_eu_biu_command;        // EU command to BIU for bus operations
    logic [15:0] t_eu_biu_dataout;        // EU data output for BIU write operations
    logic [15:0] t_eu_register_r3;        // EU register R3 for BIU addressing
    logic        t_eu_prefix_lock;        // EU LOCK prefix active flag
    logic        t_eu_flag_i;             // EU interrupt enable flag

    // BIU Status and Control Signals
    logic        t_biu_done;              // BIU operation complete flag
    logic        t_biu_clk_counter_zero;  // BIU clock counter zero flag
    logic        t_biu_ad_oe;             // BIU address/data output enable
    logic        t_biu_nmi_caught;        // BIU NMI edge detected
    logic        t_biu_nmi_debounce;      // BIU NMI debounce signal
    logic        t_biu_intr;              // BIU processed interrupt signal
    logic [19:0] t_biu_ad_out;            // BIU address/data output

    // Prefetch Queue Interface
    logic        t_pfq_empty;             // Prefetch queue empty status
    logic  [7:0] t_pfq_top_byte;          // Top byte from prefetch queue
    logic [15:0] t_pfq_addr_out;          // Prefetch queue address output

    // Segment Register Interface
    logic [15:0] t_biu_register_es;       // Extra Segment register
    logic [15:0] t_biu_register_ss;       // Stack Segment register
    logic [15:0] t_biu_register_cs;       // Code Segment register
    logic [15:0] t_biu_register_ds;       // Data Segment register
    logic [15:0] t_biu_register_rm;       // R/M operand register
    logic [15:0] t_biu_register_reg;      // REG operand register
    logic [15:0] t_biu_return_data;       // BIU return data to EU

    //--------------------------------------------------------------------------
    // Address/Data Bus Multiplexing Logic
    //--------------------------------------------------------------------------
    // Intel 8088 uses multiplexed address/data bus where addresses are output
    // during T1 and latched by ALE, then the bus switches to data during T2-T4
    always_ff @(posedge CORE_CLK) begin : address_data_mux
        if (ALE == 1'b0) begin
            // ALE low: output data on lower 8 bits of address/data bus
            dout <= t_biu_ad_out[7:0];
        end
        else begin
            // ALE high: output full 20-bit address
            addr <= t_biu_ad_out;
        end
    end

    //--------------------------------------------------------------------------
    // Bus Interface Unit (BIU) - Handles External Bus Operations
    //--------------------------------------------------------------------------
    // The BIU manages all external bus cycles, address generation, prefetch queue,
    // and interfaces with memory/IO devices. Equivalent to Intel 8288 Bus Controller.
    mcl86_biu_min u_biu_core
    (
        .CORE_CLK_INT         ( CORE_CLK               ),
        .RESET_INT            ( RESET                  ),
        .CLK                  ( CLK                    ),
        .READY_IN             ( READY                  ),
        .NMI                  ( NMI                    ),
        .INTR                 ( INTR                   ),
        .INTA_n               ( INTA_n                 ),
        .ALE                  ( ALE                    ),
        .RD_n                 ( RD_n                   ),
        .WR_n                 ( WR_n                   ),
        .IOM                  ( IOM                    ),
        .DTR                  ( DTR                    ),
        .DEN                  ( DEN                    ),
        .AD_OE                ( t_biu_ad_oe            ),
        .AD_OUT               ( t_biu_ad_out           ),
        .AD_IN                ( din                    ),
        .EU_BIU_COMMAND       ( t_eu_biu_command       ),
        .EU_BIU_DATAOUT       ( t_eu_biu_dataout       ),
        .EU_REGISTER_R3       ( t_eu_register_r3       ),
        .EU_PREFIX_LOCK       ( t_eu_prefix_lock       ),
        .BIU_DONE             ( t_biu_done             ),
        .BIU_CLK_COUNTER_ZERO ( t_biu_clk_counter_zero ),
        .BIU_SEGMENT          (                        ), // Unused in this implementation
        .BIU_NMI_CAUGHT       ( t_biu_nmi_caught       ),
        .BIU_NMI_DEBOUNCE     ( t_biu_nmi_debounce     ),
        .BIU_INTR             ( t_biu_intr             ),
        .PFQ_TOP_BYTE         ( t_pfq_top_byte         ),
        .PFQ_EMPTY            ( t_pfq_empty            ),
        .PFQ_ADDR_OUT         ( t_pfq_addr_out         ),
        .BIU_REGISTER_ES      ( t_biu_register_es      ),
        .BIU_REGISTER_SS      ( t_biu_register_ss      ),
        .BIU_REGISTER_CS      ( t_biu_register_cs      ),
        .BIU_REGISTER_DS      ( t_biu_register_ds      ),
        .BIU_REGISTER_RM      ( t_biu_register_rm      ),
        .BIU_REGISTER_REG     ( t_biu_register_reg     ),
        .BIU_RETURN_DATA      ( t_biu_return_data      )
    );

    //--------------------------------------------------------------------------
    // Execution Unit (EU) - Handles Instruction Execution
    //--------------------------------------------------------------------------
    // The EU contains the ALU, registers, instruction decoder, and control logic.
    // It executes instructions using 16-bit internal architecture while interfacing
    // with the 8-bit external bus through the BIU.
    mcl86_eu_core u_eu_core
    (
        .CORE_CLK_INT         ( CORE_CLK               ),
        .RESET_INT            ( RESET                  ),
        .TEST_N_INT           ( 1'b1                   ), // TEST pin tied high (not used)
        .EU_BIU_COMMAND       ( t_eu_biu_command       ),
        .EU_BIU_DATAOUT       ( t_eu_biu_dataout       ),
        .EU_REGISTER_R3       ( t_eu_register_r3       ),
        .EU_PREFIX_LOCK       ( t_eu_prefix_lock       ),
        .EU_FLAG_I            ( t_eu_flag_i            ),
        .BIU_DONE             ( t_biu_done             ),
        .BIU_CLK_COUNTER_ZERO ( t_biu_clk_counter_zero ),
        .BIU_NMI_CAUGHT       ( t_biu_nmi_caught       ),
        .BIU_NMI_DEBOUNCE     ( t_biu_nmi_debounce     ),
        .BIU_INTR             ( t_biu_intr             ),
        .PFQ_TOP_BYTE         ( t_pfq_top_byte         ),
        .PFQ_EMPTY            ( t_pfq_empty            ),
        .PFQ_ADDR_OUT         ( t_pfq_addr_out         ),
        .BIU_REGISTER_ES      ( t_biu_register_es      ),
        .BIU_REGISTER_SS      ( t_biu_register_ss      ),
        .BIU_REGISTER_CS      ( t_biu_register_cs      ),
        .BIU_REGISTER_DS      ( t_biu_register_ds      ),
        .BIU_REGISTER_RM      ( t_biu_register_rm      ),
        .BIU_REGISTER_REG     ( t_biu_register_reg     ),
        .BIU_RETURN_DATA      ( t_biu_return_data      )
    );

endmodule

`default_nettype wire
