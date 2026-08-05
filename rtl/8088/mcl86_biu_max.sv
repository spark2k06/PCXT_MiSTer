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
// Intel 8088 CPU - Bus Interface Unit in Maximum Bus Mode
//
// Description:
//   The BIU is everything the EU is not: the external bus, the segment
//   registers, and the prefetch queue. The EU asks for a transfer by placing a
//   command code on EU_BIU_COMMAND and the address in R3; the BIU runs the bus
//   cycle and raises BIU_DONE. It also keeps the queue fed with code bytes
//   whenever the bus would otherwise be idle, which is the whole point of the
//   8088's split-unit design.
//
//   MAXIMUM mode: the CPU does not drive RD/WR/IO-M itself. It emits a 3-bit
//   status code on S2_S0_OUT at the top of each bus cycle and an external 8288
//   bus controller decodes that into the actual command strobes. mcl86_biu_min
//   is the same BIU with minimum-mode pin behaviour instead.
//
// Two clocks - the thing to understand before editing:
//   The state machine is clocked by CORE_CLK_INT, which is FAST and unrelated to
//   the 8088's real bus rate. CLK is the 8088 pin clock, and it is only ever an
//   INPUT to be edge-detected (clk_posedge / clk_negedge). Bus events are placed
//   by waiting for the right edge of CLK, so the FSM burns many core clocks per
//   real bus clock and the external bus still sees authentic 8088 timing. States
//   that must land on a bus edge re-enter themselves until that edge arrives.
//
// Bus cycle: 8088 has an 8-bit data bus, so a WORD access is run as two
//   back-to-back byte cycles (byte_num 0 then 1, offset incremented between).
//   State 0x50 is the hop back to 0x01 for the second byte.
//
// EU command codes (eu_biu_req_code, EU_BIU_COMMAND[8:4]):
//   0x08 IO byte read     0x0C mem byte read     0x16 interrupt acknowledge
//   0x0A IO byte write    0x0E mem byte write    0x18 halt
//   0x1A IO word read     0x10 mem word read     0x19 jump (flush + reload PFQ)
//   0x1C IO word write    0x11 mem word read, SS forced
//                         0x12 mem word read, segment 0 (interrupt vectors)
//                         0x13 mem word write
//                         0x14 mem word write, SS forced
//
// Status codes driven on S2_S0_OUT (s_bits) - the real 8088 max-mode encoding:
//   000 INTA        010 I/O write    100 code fetch    110 memory write
//   001 I/O read    011 halt         101 memory read   111 passive (idle)
//
// Prefetch queue: four bytes (the 8088's depth; the 8086 has six). pfq_addr_in
//   and pfq_addr_out are the full 16-bit fetch and instruction pointers - the low
//   two bits select the entry, and bit 2 is the wrap bit that separates full from
//   empty. pfq_addr_out doubles as IP and is handed back to the EU.
//
// Turbo mode: clock_cycle_counter is loaded by microcode with the instruction's
//   nominal 8088 cycle count and counted down; the EU stalls until it reaches
//   zero (BIU_CLK_COUNTER_ZERO), which is what makes execution cycle-accurate.
//   Dividing/decrementing it faster runs the CPU "turbo"; wrappers can also tie
//   BIU_CLK_COUNTER_ZERO high to bypass cycle accuracy entirely.
//
// Reset: CS = 0xFFFF, IP = 0x0000, so the first fetch is from 0xFFFF0.
//
// Limitations:
//   - State 0x08 has no case arm and is reached only by the default increment.
//     That is intentional (a one-cycle delay slot), not a missing state.
//
// References:
//   - Intel 8088 datasheet - max-mode status encoding, bus cycle timing
//   - Intel 8086 Family User's Manual (Oct 1979)
//
// Changelog:
// 1.0 - 10/8/15 - Initial revision
//------------------------------------------------------------------------

`default_nettype none
`timescale 1ns/1ps

module mcl86_biu_max
    (
        // System Interface
        input  wire         CORE_CLK_INT,           // Fast core clock - clocks this FSM
        input  wire         RESET_INT,              // Synchronous reset (active high)
        // 8088 Bus Pins (CLK is an input to be edge-detected, NOT the FSM clock)
        input  wire         CLK,                    // 8088 pin clock - sets real bus timing
        input  wire         READY_IN,               // Bus ready; low inserts wait states
        input  wire         NMI,                    // Non-maskable interrupt (rising edge)
        input  wire         INTR,                   // Maskable interrupt request (level)
        output logic        LOCK_n,                 // Bus lock (active low), from LOCK prefix or INTA
        output logic        AD_OE,                  // Address/data bus output enable
        output logic [19:0] AD_OUT,                 // Multiplexed address (20-bit) / data (low 8)
        input  wire   [7:0] AD_IN,                  // Data in from the multiplexed bus
        output logic        S6_3_MUX,               // Upper bus mux: 0 = address, 1 = status
        output logic  [2:0] S2_S0_OUT,              // Max-mode status for the 8288 (see table above)

        // EU to BIU Signals
        input  wire  [15:0] EU_BIU_COMMAND,         // Packed command word (decoded below)
        input  wire  [15:0] EU_BIU_DATAOUT,         // Write data / segment-register load value
        input  wire  [15:0] EU_REGISTER_R3,         // Address (offset) for the requested transfer
        input  wire         EU_PREFIX_LOCK,         // LOCK prefix is active

        // BIU to EU Signals
        output logic        BIU_DONE,               // Requested bus operation has completed
        output logic        BIU_CLK_COUNTER_ZERO,   // Cycle-accuracy counter has expired
        output logic  [1:0] BIU_SEGMENT,            // Segment in use: 00=ES 01=SS 10=CS 11=DS
        output logic        BIU_NMI_CAUGHT,         // NMI rising edge latched
        input  wire         BIU_NMI_DEBOUNCE,       // EU clears the latched NMI
        output logic        BIU_INTR,               // INTR, sampled on the CLK rising edge

        // Prefetch Queue Interface
        output logic  [7:0] PFQ_TOP_BYTE,           // Next instruction byte for the EU
        output logic        PFQ_EMPTY,              // Queue has no byte available
        output logic [15:0] PFQ_ADDR_OUT,           // Instruction pointer (IP)

        // Segment and Operand Registers (owned by the BIU, read by the EU)
        output logic [15:0] BIU_REGISTER_ES,        // Extra Segment
        output logic [15:0] BIU_REGISTER_SS,        // Stack Segment
        output logic [15:0] BIU_REGISTER_CS,        // Code Segment (resets to 0xFFFF)
        output logic [15:0] BIU_REGISTER_DS,        // Data Segment
        output logic [15:0] BIU_REGISTER_RM,        // Decoded R/M operand
        output logic [15:0] BIU_REGISTER_REG,       // Decoded REG operand
        output logic [15:0] BIU_RETURN_DATA,        // Data returned by the last read

        // Turbo mode - scales the cycle-accuracy counter (see header)
        input  wire   [7:0] clock_cycle_counter_division_ratio,  // Core clocks per counter tick
        input  wire   [7:0] clock_cycle_counter_decrement_value, // Amount subtracted per tick
        input  wire         shift_read_timing       // Sample read data on CLK falling edge instead of rising
    );

    //--------------------------------------------------------------------------
    // Internal Signals - Bus State Machine
    //--------------------------------------------------------------------------
    reg  [ 7:0] biu_state;              // FSM state; free-runs by +1, arms override it
    reg  [ 2:0] s_bits;                 // Status code for this cycle (see header table)
    reg  [ 2:0] s2_s0_out_int;          // s_bits, held until the pin register takes it
    reg         word_cycle;             // This request is a word: run two byte cycles
    reg         byte_num;               // Which half of a word cycle is in flight (0 = low)
    reg         biu_done_int;           // Completion pulse back to the EU
    reg         biu_lock_n_int;         // BIU-generated lock (INTA); OR'd with the LOCK prefix

    //--------------------------------------------------------------------------
    // Internal Signals - 8088 CLK Edge Detect
    //--------------------------------------------------------------------------
    // CLK is an input, not a clock domain: the FSM runs on CORE_CLK_INT and waits
    // on these edges to place bus events at authentic 8088 timing.
    reg         clk_d1;                 // CLK resync stage 1
    reg         clk_d2;                 // CLK resync stage 2
    wire        clk_posedge;            // CLK rising edge, one CORE_CLK_INT wide
    wire        clk_negedge;            // CLK falling edge, one CORE_CLK_INT wide
    reg         clk_negedge_d1;         // Falling edge, delayed - used to time LOCK_n out

    //--------------------------------------------------------------------------
    // Internal Signals - EU Command Decode
    //--------------------------------------------------------------------------
    wire        eu_prefix_seg;          // A segment-override prefix is in effect
    wire [ 1:0] eu_biu_strobe;          // 01 = opcode fetch, 10 = load clk counter, 11 = load register
    wire [ 1:0] eu_biu_segment;         // Default segment for this access
    wire        eu_biu_req;             // Bus request; held until the BIU services it
    wire [ 4:0] eu_biu_req_code;        // What kind of transfer (see the table in the header)
    wire [ 1:0] eu_qs_out;              // Queue status, for the max-mode QS pins
    wire [ 1:0] eu_segment_override_value; // Segment named by the override prefix
    wire [ 1:0] biu_segment;            // Segment actually used: override if present, else default
    wire [15:0] biu_muxed_segment;      // The selected segment register's value
    reg         eu_biu_req_d1;          // Request delayed, for rising-edge detect
    reg         eu_biu_req_caught;      // Sticky request, cleared on completion

    //--------------------------------------------------------------------------
    // Internal Signals - Segment and Operand Registers
    //--------------------------------------------------------------------------
    // The _d1/_d2 copies are a two-stage output pipeline into the EU. Depth is a
    // timing choice, not a functional one - the original notes these may be
    // pipelined zero to two clocks; they are currently pipelined by two.
    reg  [15:0] biu_register_cs;        // Code Segment (resets to 0xFFFF)
    reg  [15:0] biu_register_es;        // Extra Segment
    reg  [15:0] biu_register_ss;        // Stack Segment
    reg  [15:0] biu_register_ds;        // Data Segment
    reg  [15:0] biu_register_rm;        // Decoded R/M operand
    reg  [15:0] biu_register_reg;       // Decoded REG operand
    reg  [15:0] biu_register_cs_d1;     // Output pipeline stage 1
    reg  [15:0] biu_register_es_d1;
    reg  [15:0] biu_register_ss_d1;
    reg  [15:0] biu_register_ds_d1;
    reg  [15:0] biu_register_rm_d1;
    reg  [15:0] biu_register_reg_d1;
    reg  [15:0] biu_register_cs_d2;     // Output pipeline stage 2 - drives the port
    reg  [15:0] biu_register_es_d2;
    reg  [15:0] biu_register_ss_d2;
    reg  [15:0] biu_register_ds_d2;
    reg  [15:0] biu_register_rm_d2;
    reg  [15:0] biu_register_reg_d2;

    //--------------------------------------------------------------------------
    // Internal Signals - Address and Data Path
    //--------------------------------------------------------------------------
    reg  [19:0] addr_out_temp_base;     // Segment base, already shifted left 4
    reg  [15:0] addr_out_temp_offset;   // Offset within the segment; +1 between word halves
    reg  [ 7:0] ad_in_int;              // AD_IN, registered
    reg  [ 7:0] latched_data_in;        // Read byte, captured at the sampling edge
    reg  [15:0] biu_return_data_int;    // Assembled read result (both halves of a word)
    reg  [15:0] biu_return_data_int_d1; // Return pipeline; must be stable before BIU_DONE
    reg  [15:0] biu_return_data_int_d2; // Return pipeline stage 2 - drives the port
    reg  [15:0] eu_register_r3_d;       // EU_REGISTER_R3, registered on entry

    //--------------------------------------------------------------------------
    // Internal Signals - Prefetch Queue
    //--------------------------------------------------------------------------
    // Four bytes. addr_in / addr_out are full 16-bit pointers: [1:0] picks the
    // entry, [2] is the wrap bit that tells full from empty, and addr_out is IP.
    reg  [ 7:0] pfq_entry0;             // Queue byte 0
    reg  [ 7:0] pfq_entry1;             // Queue byte 1
    reg  [ 7:0] pfq_entry2;             // Queue byte 2
    reg  [ 7:0] pfq_entry3;             // Queue byte 3
    reg  [15:0] pfq_addr_in;            // Fetch pointer - where the next code byte lands
    reg  [15:0] pfq_addr_out;           // Instruction pointer - where the EU is reading
    reg  [15:0] pfq_addr_out_d1;        // IP, registered out to the EU
    wire [ 7:0] pfq_top_byte_int;       // Entry selected by pfq_addr_out[1:0]
    reg  [ 7:0] pfq_top_byte_int_d1;    // Top byte, registered out to the EU
    reg         pfq_write;              // Write strobe for a freshly fetched code byte
    wire        pfq_full;               // Wrap bit differs, index equal
    wire        pfq_empty;              // Wrap bit equal, index equal

    //--------------------------------------------------------------------------
    // Internal Signals - Interrupts, Ready, Lock
    //--------------------------------------------------------------------------
    reg         nmi_d1;                 // NMI resync stage 1
    reg         nmi_d2;                 // NMI resync stage 2
    reg         nmi_d3;                 // NMI resync stage 3 (edge detect needs the history)
    reg         nmi_caught;             // NMI rising edge latched; EU clears via BIU_NMI_DEBOUNCE
    reg         intr_d1;                // INTR registered before the CLK-edge sample
    reg         ready_d1;               // READY_IN resync stage 1
    reg         ready_d2;               // READY_IN resync stage 2
    reg         ready_d3;               // READY_IN resync stage 3
    reg         eu_prefix_lock_d1;      // LOCK prefix resync stage 1
    reg         eu_prefix_lock_d2;      // LOCK prefix resync stage 2

    //--------------------------------------------------------------------------
    // Internal Signals - Cycle Accuracy Counter
    //--------------------------------------------------------------------------
    reg  [12:0] clock_cycle_counter;    // 8088 cycles still owed for this instruction
    reg  [ 7:0] clock_cycle_counter_div;// Prescaler - core clocks per counter tick

    //--------------------------------------------------------------------------
    // BIU  Combinationals
    //--------------------------------------------------------------------------
    // Outputs to the EU
    assign BIU_DONE                       = biu_done_int;
    assign PFQ_EMPTY                      = pfq_empty;
    assign PFQ_ADDR_OUT                   = pfq_addr_out_d1;
    assign BIU_SEGMENT                    = biu_segment;
    assign BIU_REGISTER_ES                = biu_register_es_d2;
    assign BIU_REGISTER_SS                = biu_register_ss_d2;
    assign BIU_REGISTER_CS                = biu_register_cs_d2;
    assign BIU_REGISTER_DS                = biu_register_ds_d2;
    assign BIU_REGISTER_RM                = biu_register_rm_d2;
    assign BIU_REGISTER_REG               = biu_register_reg_d2;
    assign BIU_RETURN_DATA                = biu_return_data_int_d2;
    assign BIU_NMI_CAUGHT                 = nmi_caught;

    // Input signals from the EU requesting BIU processing.
    //  eu_biu_strobe[1:0] are available for only one clock cycle and cause BIU to take immediate action.
    //  eu_biu_req stays asserted until the BIU is available to service the request.
    assign eu_prefix_seg                  = EU_BIU_COMMAND[14];
    assign eu_biu_strobe[1:0]             = EU_BIU_COMMAND[13:12]; // 01=opcode fetch 10=clock load 11=load segment register(eu_biu_req_code has the regiter#)
    assign eu_biu_segment[1:0]            = EU_BIU_COMMAND[11:10];
    assign eu_biu_req                     = EU_BIU_COMMAND[9];
    assign eu_biu_req_code                = EU_BIU_COMMAND[8:4];
    assign eu_qs_out[1:0]                 = EU_BIU_COMMAND[3:2];  // Updated for every opcode fetch using biu_strobe and Jump request using eu_biu_rq
    assign eu_segment_override_value[1:0] = EU_BIU_COMMAND[1:0];

    // Select either the current EU Segment or the Segment Override value.
    assign biu_segment       = (eu_prefix_seg == 1'b1) ? eu_segment_override_value : eu_biu_segment;

    assign biu_muxed_segment = (biu_segment == 2'b00) ? biu_register_es :
                               (biu_segment == 2'b01) ? biu_register_ss :
                               (biu_segment == 2'b10) ? biu_register_cs :
                                                        biu_register_ds ;

    // Steer the Prefetch Queue to the EU
    assign pfq_top_byte_int = (pfq_addr_out[1:0] == 2'b00) ? pfq_entry0 :
                              (pfq_addr_out[1:0] == 2'b01) ? pfq_entry1 :
                              (pfq_addr_out[1:0] == 2'b10) ? pfq_entry2 :
                                                             pfq_entry3 ;

    assign PFQ_TOP_BYTE = pfq_top_byte_int_d1;

    // Generate the Prefetch Queue Flags
    assign pfq_full  = ((pfq_addr_in[2] != pfq_addr_out[2]) && (pfq_addr_in[1:0] == pfq_addr_out[1:0])) ? 1'b1 : 1'b0;
    assign pfq_empty = ((pfq_addr_in[2] == pfq_addr_out[2]) && (pfq_addr_in[1:0] == pfq_addr_out[1:0])) ? 1'b1 : 1'b0;

    // Instruction cycle accuracy counter. This can be tied to '1' to disable x86 cycle compatibiliy.
    assign BIU_CLK_COUNTER_ZERO = (clock_cycle_counter == 13'h0000) ? 1'b1 : 1'b0;

    // Clock edges
    assign clk_posedge =  clk_d1 & ~clk_d2;
    assign clk_negedge = ~clk_d1 &  clk_d2;

    //--------------------------------------------------------------------------
    // BIU State Machine
    //--------------------------------------------------------------------------
    always @(posedge CORE_CLK_INT) begin : biu_fsm
        if (RESET_INT == 1'b1) begin
            clk_d1               <= 'h0;
            clk_d2               <= 'h0;
            clk_negedge_d1       <= 'h0;
            nmi_d1               <= 'h0;
            nmi_d2               <= 'h0;
            nmi_d3               <= 'h0;
            nmi_caught           <= 'h0;
            eu_register_r3_d     <= 'h0;
            eu_biu_req_caught    <= 'h0;
            biu_register_cs      <= 16'hFFFF;
            biu_register_es      <= 'h0;
            biu_register_ss      <= 'h0;
            biu_register_ds      <= 'h0;
            biu_register_rm      <= 'h0;
            biu_register_reg     <= 'h0;
            clock_cycle_counter  <= 'h0;
            pfq_addr_out         <= 'h0;
            pfq_entry0           <= 'h0;
            pfq_entry1           <= 'h0;
            pfq_entry2           <= 'h0;
            pfq_entry3           <= 'h0;
            biu_state            <= 8'hD0;
            S2_S0_OUT            <= 'b111;
            s2_s0_out_int        <= 'b111;
            pfq_write            <= 'h0;
            pfq_addr_in          <= 'h0;
            biu_lock_n_int       <= 1'b1;
            S6_3_MUX             <= 'h0;
            AD_OE                <= 'h0;
            biu_return_data_int  <= 'h0;
            biu_done_int         <= 'h0;
            ready_d1             <= 'h0;
            ready_d2             <= 'h0;
            ready_d3             <= 'h0;
            eu_biu_req_d1        <= 'h0;
            latched_data_in      <= 'h0;
            addr_out_temp_base   <= 'h0;
            addr_out_temp_offset <= 'h0;
            s_bits               <= 3'b111;
            AD_OUT               <= 'h0;
            word_cycle           <= 1'b0;
            byte_num             <= 1'b0;
            ad_in_int            <= 'h0;
            BIU_INTR             <= 'h0;
            eu_prefix_lock_d1    <= 'h0;
            eu_prefix_lock_d2    <= 'h0;
            LOCK_n               <= 1'b1;
            intr_d1              <= 'h0;
        end
        else begin
            // Register pipelining
            clk_d1               <= CLK;
            clk_d2               <= clk_d1;

            clk_negedge_d1       <= clk_negedge;

            ready_d1             <= READY_IN;
            ready_d2             <= ready_d1;
            ready_d3             <= ready_d2;

            nmi_d1               <= NMI;
            nmi_d2               <= nmi_d1;
            nmi_d3               <= nmi_d2;

            intr_d1              <= INTR;

            // These signals may be pipelined from zero to two clocks.
            // They are currently pipelined by two clocks.
            biu_register_es_d1   <= biu_register_es;
            biu_register_ss_d1   <= biu_register_ss;
            biu_register_cs_d1   <= biu_register_cs;
            biu_register_ds_d1   <= biu_register_ds;
            biu_register_rm_d1   <= biu_register_rm;
            biu_register_reg_d1  <= biu_register_reg;
            biu_register_es_d2   <= biu_register_es_d1;
            biu_register_ss_d2   <= biu_register_ss_d1;
            biu_register_cs_d2   <= biu_register_cs_d1;
            biu_register_ds_d2   <= biu_register_ds_d1;
            biu_register_rm_d2   <= biu_register_rm_d1;
            biu_register_reg_d2  <= biu_register_reg_d1;

            // These signals may be pipelined from zero to one clock.
            // They are currently pipelined by one clock.
            pfq_top_byte_int_d1 <= pfq_top_byte_int;
            pfq_addr_out_d1     <= pfq_addr_out;

            // This signal may be pipelined any number of clocks as
            // long as is stable before BIU_DONE is asserted.
            biu_return_data_int_d1 <= biu_return_data_int;
            biu_return_data_int_d2 <= biu_return_data_int_d1;

            // NMI caught on it's rising edge
            if (nmi_d3 == 1'b0 && nmi_d2 == 1'b0 && nmi_d1 == 1'b1) begin
                nmi_caught <= 1'b1;
            end
            else if (BIU_NMI_DEBOUNCE == 1'b1) begin
                nmi_caught <= 1'b0;
            end

            // INTR sampled on the rising edge of the CLK
            if (clk_posedge) begin
                BIU_INTR <= intr_d1;
            end

            eu_prefix_lock_d1 <= EU_PREFIX_LOCK;
            eu_prefix_lock_d2 <= eu_prefix_lock_d1;

            // Drive LOCK_n out of the chip only on the falling edge of the 8088 CLK.
            // LOCK_n can be driven by either the BIU during an INTA cycle or by the
            // LOCK prefix opcode generated by the EU.
            if (clk_negedge_d1) begin
                LOCK_n <= ~eu_prefix_lock_d2 && biu_lock_n_int;
            end

            // Register pipelining in and out of the BIU.
            eu_register_r3_d <= EU_REGISTER_R3;
            ad_in_int        <= AD_IN;
            S2_S0_OUT        <= s2_s0_out_int;

            // Capture a bus request from the EU
            eu_biu_req_d1 <= eu_biu_req;
            if (eu_biu_req_d1 == 1'b0 && eu_biu_req == 1'b1) begin
                eu_biu_req_caught <= 1'b1;
            end
            else if (biu_done_int == 1'b1) begin
                eu_biu_req_caught <= 1'b0;
            end

            // Strobe from EU to update the segment and addressing registers
            if (eu_biu_strobe == 2'b11) begin
                case (eu_biu_req_code[2:0])  // synthesis parallel_case
                    3'h0: biu_register_es  <= EU_BIU_DATAOUT[15:0];
                    3'h1: biu_register_ss  <= EU_BIU_DATAOUT[15:0];
                    3'h2: biu_register_cs  <= EU_BIU_DATAOUT[15:0];
                    3'h3: biu_register_ds  <= EU_BIU_DATAOUT[15:0];
                    3'h4: biu_register_rm  <= EU_BIU_DATAOUT[15:0];
                    3'h5: biu_register_reg <= EU_BIU_DATAOUT[15:0];
                    default:;
                endcase
            end

            // Strobe from EU to set the 8088 clock cycle counter
            if (eu_biu_strobe == 2'b10) begin
                clock_cycle_counter_div <= clock_cycle_counter_division_ratio;
                clock_cycle_counter     <= EU_BIU_DATAOUT[12:0];
            end
            else if (8'h00 != clock_cycle_counter_div) begin
                clock_cycle_counter_div <= clock_cycle_counter_div - 1;
            end
            else begin
                clock_cycle_counter_div <= clock_cycle_counter_division_ratio;
                if (clock_cycle_counter != 13'h0000) begin
                    if (clock_cycle_counter > clock_cycle_counter_decrement_value) begin
                        clock_cycle_counter <= clock_cycle_counter - clock_cycle_counter_decrement_value;
                    end
                    else begin
                        clock_cycle_counter <= 0;
                    end
                end
            end

            // Prefetch Queue
            // --------------
            // Increment the output address of the queue upon EU fetch request strobe.
            // Update/flush the Prefetch Queue when the EU asserts the Jump request.
            // Increment the input address during prefetch queue fetches.
            //---------------------------------------------------------------------------------
            if (eu_biu_req_caught == 1'b1 && eu_biu_req_code == 5'h19) begin
                pfq_addr_out <= eu_register_r3_d; // Update the prefetch queue to the new address.
            end
            else if (eu_biu_strobe == 2'b01 && pfq_empty == 1'b0) begin
                pfq_addr_out <= pfq_addr_out + 1;  // Increment the current IP - Instruction Pointer
            end

            if (eu_biu_req_caught == 1'b1 && eu_biu_req_code == 5'h19) begin
                pfq_addr_in <= eu_register_r3_d; // Update the prefetch queue to the new address.
            end
            else if (pfq_write == 1'b1) begin
                pfq_addr_in <= pfq_addr_in + 1;
            end

            // Write to the selected prefetch queue entry.
            if (pfq_write == 1'b1) begin
                case (pfq_addr_in[1:0])  // synthesis parallel_case
                    2'b00: pfq_entry0 <= latched_data_in[7:0];
                    2'b01: pfq_entry1 <= latched_data_in[7:0];
                    2'b10: pfq_entry2 <= latched_data_in[7:0];
                    2'b11: pfq_entry3 <= latched_data_in[7:0];
                    default:;
                endcase
            end

            // 8088 BIU State Machine
            // ----------------------
            // biu_state free-runs (+1 every core clock); each arm overrides that
            // when it needs to hold or branch. A state that must land on a bus
            // edge re-enters ITSELF until clk_posedge / clk_negedge arrives, which
            // is how a fast FSM produces real 8088 bus timing.
            //
            //   0x00  idle: dispatch an EU request, else prefetch if queue not full
            //   0x01  drive address + status, wait for CLK rising edge
            //   0x02  wait for CLK falling edge
            //   0x03  falling edge: switch S[6:3] to status, float AD on a read,
            //         drive write data, assert LOCK_n on the first INTA cycle
            //   0x04  wait for CLK falling edge
            //   0x05  sample READY - if low, go back to 0x04 (wait state)
            //   0x06  sample the read byte at the chosen edge; queue it if a fetch
            //   0x07  drop the queue write strobe
            //   0x09  steer the byte into the low or high half of the return word
            //   0x0A  cycle done: bump offset; if a word's first half, go to 0x50
            //   0x0B  clear BIU_DONE        0x0C  back to idle
            //   0x50  second half of a word cycle - re-enter at 0x01
            //
            // States 0x08 and the gaps are reached by the free-running increment
            // and act as delay slots; they have no arm on purpose.
            biu_state <= biu_state + 1'b1;
            case (biu_state) // synthesis parallel_case
                8'h00: begin
                    // Debounce signals
                    pfq_write      <= 1'b0;
                    biu_lock_n_int <= 1'b1;
                    S6_3_MUX       <= 1'b0;
                    byte_num       <= 1'b0;
                    word_cycle     <= 1'b0;

                    if (eu_biu_req_caught == 1'b1) begin
                        case (eu_biu_req_code)  // synthesis parallel_case
                            // Interrupt ACK Cycle
                            8'h16: begin
                                addr_out_temp_base   <= {4'h0, eu_register_r3_d[15:0]};
                                addr_out_temp_offset <= 'h0;
                                // AD_OE                <= 'h0;
                                word_cycle           <= 1'b1;
                                s_bits               <= 3'b000;
                                biu_state            <= 8'h01;
                            end

                            // IO Byte Read
                            8'h08: begin
                                addr_out_temp_base   <= {4'h0, eu_register_r3_d[15:0]};
                                addr_out_temp_offset <= 'h0;
                                s_bits               <= 3'b001;
                                biu_state            <= 8'h01;
                            end

                            // IO Word Read
                            8'h1A: begin
                                addr_out_temp_base   <= {4'h0, eu_register_r3_d[15:0]};
                                addr_out_temp_offset <= 'h0;
                                word_cycle           <= 1'b1;
                                s_bits               <= 3'b001;
                                biu_state            <= 8'h01;
                            end

                            // IO Byte Write
                            8'h0A: begin
                                addr_out_temp_base   <= {4'h0, eu_register_r3_d[15:0]};
                                addr_out_temp_offset <= 'h0;
                                s_bits               <= 3'b010;
                                biu_state            <= 8'h01;
                            end

                            // IO Word Write
                            8'h1C: begin
                                addr_out_temp_base   <= {4'h0, eu_register_r3_d[15:0]};
                                addr_out_temp_offset <= 'h0;
                                word_cycle           <= 1'b1;
                                s_bits               <= 3'b010;
                                biu_state            <= 8'h01;
                            end

                            // Halt Request
                            8'h18: begin
                                addr_out_temp_base   <= {biu_register_cs[15:0], 4'h0};
                                addr_out_temp_offset <= pfq_addr_out[15:0];
                                s_bits               <= 3'b011;
                                biu_state            <= 8'h01;
                            end

                            // Memory Byte Read
                            8'h0C: begin
                                addr_out_temp_base   <= {biu_muxed_segment[15:0], 4'h0};
                                addr_out_temp_offset <= eu_register_r3_d[15:0];
                                s_bits               <= 3'b101;
                                biu_state            <= 8'h01;
                            end

                            // Memory Word Read
                            8'h10: begin
                                addr_out_temp_base   <= {biu_muxed_segment[15:0], 4'h0};
                                addr_out_temp_offset <= eu_register_r3_d[15:0];
                                word_cycle           <= 1'b1;
                                s_bits               <= 3'b101;
                                biu_state            <= 8'h01;
                            end

                            // Memory Word Read from Stack Segment
                            8'h11: begin
                                addr_out_temp_base   <= {biu_register_ss[15:0], 4'h0};
                                addr_out_temp_offset <= eu_register_r3_d[15:0];
                                word_cycle           <= 1'b1;
                                s_bits               <= 3'b101;
                                biu_state            <= 8'h01;
                            end

                            // Memory Word Read from Segment 0x0000 - Used for interrupt vector fetches
                            8'h12: begin
                                addr_out_temp_base   <= {4'h0, eu_register_r3_d[15:0]};
                                addr_out_temp_offset <= 'h0;
                                word_cycle           <= 1'b1;
                                s_bits               <= 3'b101;
                                biu_state            <= 8'h01;
                            end

                            // Memory Byte Write
                            8'h0E: begin
                                addr_out_temp_base   <= {biu_muxed_segment[15:0], 4'h0};
                                addr_out_temp_offset <= eu_register_r3_d[15:0];
                                s_bits               <= 3'b110;
                                biu_state            <= 8'h01;
                            end

                            // Memory Word Write
                            8'h13: begin
                                addr_out_temp_base   <= {biu_muxed_segment[15:0], 4'h0};
                                addr_out_temp_offset <= eu_register_r3_d[15:0];
                                word_cycle           <= 1'b1;
                                s_bits               <= 3'b110;
                                biu_state            <= 8'h01;
                            end

                            // Memory Word Write to Stack Segment
                            8'h14: begin
                                addr_out_temp_base   <= {biu_register_ss[15:0], 4'h0};
                                addr_out_temp_offset <= eu_register_r3_d[15:0];
                                word_cycle           <= 1'b1;
                                s_bits               <= 3'b110;
                                biu_state            <= 8'h01;
                            end

                            // Jump Request
                            8'h19: begin
                                biu_done_int <= 1'b1;
                                biu_state    <= 8'h0B;
                            end

                            default:;
                        endcase
                    end
                    else if (pfq_full == 1'b0) begin
                        addr_out_temp_base   <= {biu_register_cs[15:0], 4'h0};
                        addr_out_temp_offset <= pfq_addr_in[15:0];
                        s_bits               <= 3'b100;
                        biu_state            <= 8'h01;
                    end
                    else begin
                        biu_state <= 8'h00;
                    end
                end

                // Wait for the rising edge of CLK to start the bus cycle; then assert the S bits.
                // Leave AD bus hi-Z during INTA cycles.
                8'h01: begin
                    if (s_bits != 3'b000) begin
                        AD_OE        <= 1'b1;
                        // I/O addresses are 16 bits and wrap at FFFF; memory
                        // addresses are the full 20-bit segment:offset sum. Only
                        // I/O read (001) and write (010) use the port space, so
                        // mask their upper nibble - otherwise a word access at
                        // port FFFF carries into bit 16 (OUT DX,AX -> 0x10000).
                        if (s_bits == 3'b001 || s_bits == 3'b010) begin
                            AD_OUT[19:0] <= (addr_out_temp_base + addr_out_temp_offset) & 20'h0FFFF;
                        end
                        else begin
                            AD_OUT[19:0] <= addr_out_temp_base + addr_out_temp_offset;
                        end
                    end

                    S6_3_MUX <= 1'b0;

                    if (clk_posedge) begin // Wait until next CLK rising edge
                        s2_s0_out_int <= s_bits;
                    end
                    else begin
                        biu_state <= 8'h01;
                    end
                end

                8'h02: begin
                    if (~clk_negedge) begin // Wait until next CLK falling edge
                        biu_state <= 8'h02;
                    end 
                end

                // On the next falling CLK edge, switch the S[6:3] bits mode and float the AD[7:0] bus if it is a read cycle, and mux data to the databus
                // Assert the LOCK_n signal on the first cycle of an INTA cycle.
                8'h03: begin
                    if (clk_negedge) begin
                        if (s_bits == 3'b000 && byte_num == 1'b0) begin
                            biu_lock_n_int <= 1'b0;
                        end
                        else begin
                            biu_lock_n_int <= 1'b1;
                        end

                        S6_3_MUX <= 1'b1;

                        AD_OE    <= s_bits[1]; // Turn off bus drivers for read cycles

                        if (word_cycle == 1'b1 && byte_num == 1'b1) begin
                            AD_OUT[7:0] <= EU_BIU_DATAOUT[15:8];
                        end
                        else begin
                            AD_OUT[7:0] <= EU_BIU_DATAOUT[7:0];
                        end
                    end
                    else begin
                        biu_state <= 8'h03;
                    end
                end

                8'h04: begin
                    if (~clk_negedge) begin  // Wait until next CLK falling edge
                        biu_state <= 8'h04;
                    end
                end

                // On the next falling CLK edge, sample the READY signal
                8'h05: begin
                    if (READY_IN == 1'b0)    // Not ready yet, wait another clock cycle
                    begin
                        biu_state <= 8'h04;
                    end
                    else begin
                        s2_s0_out_int <= 3'b111;
                    end
                end

                // On the next CLK edge, sample the data.
                8'h06: begin
                    if ((~shift_read_timing & clk_posedge) || (shift_read_timing & clk_negedge)) begin
                        latched_data_in <= ad_in_int;

                        // If a code fetch, then write data to the prefetch queue
                        if (s_bits == 3'b100) begin
                            pfq_write <= 1'b1;
                        end
                    end
                    else begin
                        biu_state <= 8'h06;
                    end
                end

                // Debounce the prefetch queue write pulse and increment the prefetch queue address.
                8'h07: begin
                    pfq_write <= 1'b0;
                end

                //  Steer the data
                8'h09: begin
                    if (s_bits != 3'b000 && (word_cycle == 1'b1 && byte_num == 1'b1)) begin
                        biu_return_data_int[15:8] <= latched_data_in[7:0];
                    end
                    else begin
                        biu_return_data_int[15:0] <= {8'h0, latched_data_in[7:0]};
                    end
                end

                // The cycle is complete.
                8'h0A: begin
                    if (shift_read_timing | clk_negedge) begin
                        addr_out_temp_offset[15:0] <= addr_out_temp_offset[15:0] + 1;

                        if (word_cycle == 1'b1 && byte_num == 1'b0) begin
                            byte_num  <= 1'b1;
                            biu_state <= 8'h50;
                        end
                        else begin
                            if (s_bits != 3'b100) begin
                                biu_done_int <= 1'b1;
                            end
                        end
                    end
                    else begin
                        biu_state <= 8'h0A;
                    end
                end

                8'h0B: begin
                    biu_done_int <= 1'b0;
                end

                8'h0C: begin
                    biu_state <= 8'h00;
                end

                8'h50: begin
                    biu_state <= 8'h01;
                end

                default:;
            endcase
        end
    end

endmodule

`default_nettype wire
