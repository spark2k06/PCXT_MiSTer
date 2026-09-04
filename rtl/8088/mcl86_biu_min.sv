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
// Intel 8088 CPU - Bus Interface Unit in Minimum Bus Mode
//
// Description:
//   The BIU owns the external bus, the segment registers, and the prefetch
//   queue. The EU asks for a transfer by placing a command code on
//   EU_BIU_COMMAND with the address in R3; the BIU runs the bus cycle and
//   raises BIU_DONE. Between EU requests it keeps the queue filled with code
//   bytes, which is what lets fetch and execute overlap.
//
//   MINIMUM mode: the CPU drives its own bus control pins - ALE, RD_n, WR_n,
//   IOM, DTR, DEN, INTA_n - with no external 8288 bus controller. This is the
//   PC/XT-style configuration. mcl86_biu_max is the same BIU emitting max-mode
//   status codes instead, and mcl86_biu_max16 is its 16-bit (8086) sibling.
//
// Two clocks:
//   The state machine is clocked by CORE_CLK_INT, which is fast and unrelated to
//   the 8088 bus rate. CLK is the 8088 pin clock and is only ever an INPUT to be
//   edge-detected (clk_d2/d3/d4 form the detector). Bus events are placed by
//   waiting for the right CLK edge, so a fast FSM still produces authentic 8088
//   T1-T4 timing. States that must land on a bus edge re-enter themselves.
//
// Bus cycle (8-bit data bus - a WORD access runs as two byte cycles):
//
//   CLK    _/~~\__/~~\__/~~\__/~~\__/~~\__/~~\__
//            T1     T2     T3    (Tw)    T4
//   ALE    _/~~\_________________________________   address valid, latch on fall
//   AD     <  ADDR ><======= DATA =============>
//   RD_n   ~~~~~~~~\______________________/~~~~~~   read strobe
//   READY  ------------------< sampled >---------   low here inserts Tw
//
//   biu_state arms: 0x00 idle/dispatch, 0x01 T1 setup, 0x04 T1 address,
//   0x13 T2 ALE, 0x19 T2 data, 0x28 T3 DEN, 0x2F T3 READY sample,
//   0x3D/0x3E T4 sample, 0x40 T4 steer, 0x45/0x46 T4 end, 0x4E, 0x58.
//   biu_state free-runs (+1 per core clock) and the arms override it, so the
//   gaps between those numbers are deliberate timing delays, not dead states.
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
// Prefetch queue: four bytes (the 8088 depth; the 8086 has six). pfq_addr_in and
//   pfq_addr_out are full 16-bit pointers - [1:0] selects the entry, [2] is the
//   wrap bit separating full from empty, and pfq_addr_out doubles as IP. A jump
//   request (0x19) rewrites both pointers, which is how the queue is flushed.
//
// Cycle accuracy: microcode loads clock_cycle_counter with the instruction's
//   nominal 8088 cycle count; the EU stalls until it reaches zero. Unlike the
//   max-mode BIUs, this one has NO turbo scaling - there is no division ratio,
//   decrement value, or shift_read_timing input here.
//
// Reset: CS = 0xFFFF, IP = 0x0000, so the first fetch is from 0xFFFF0.
//
// References:
//   - Intel 8088 datasheet - minimum mode pin functions, bus cycle timing
//   - Intel 8086 Family User's Manual (Oct 1979)
//------------------------------------------------------------------------------

`default_nettype none
`timescale 1ns/1ps

module mcl86_biu_min
    (
        // System Interface
        input  wire        CORE_CLK_INT,          // High-speed core clock for internal logic
        input  wire        CLK,                   // 8088 CPU clock (4.77-10 MHz)
        input  wire        RESET_INT,             // Synchronous reset (active high)
        // External Bus Control Interface
        input  wire        READY_IN,              // Memory/IO ready signal (0=insert wait states)
        input  wire        NMI,                   // Non-maskable interrupt input
        input  wire        INTR,                  // Maskable interrupt request input
        output reg         INTA_n,                // Interrupt acknowledge output (active low)
        output reg         ALE,                   // Address Latch Enable (address valid strobe)
        output reg         RD_n,                  // Read strobe (active low)
        output reg         WR_n,                  // Write strobe (active low)
        output reg         IOM,                   // Memory(0)/IO(1) space indicator
        output reg         DTR,                   // Data Transmit/Receive direction control
        output reg         DEN,                   // Data Enable for external bus transceivers
        // Multiplexed Address/Data Bus Interface
        output reg         AD_OE,                 // Address/Data bus output enable
        output reg  [19:0] AD_OUT,                // Address/Data bus output (20-bit address, 8-bit data)
        input  wire  [7:0] AD_IN,                 // Data bus input (8-bit)
        // EU Command Interface
        input  wire [15:0] EU_BIU_COMMAND,        // Command word from EU
        input  wire [15:0] EU_BIU_DATAOUT,        // Data from EU for write operations
        input  wire [15:0] EU_REGISTER_R3,        // EU temporary register for addressing
        input  wire        EU_PREFIX_LOCK,        // LOCK prefix active from EU
        // BIU Status Interface
        output wire        BIU_DONE,              // BIU operation complete flag
        output wire        BIU_CLK_COUNTER_ZERO,  // Cycle accuracy counter reached zero
        output wire  [1:0] BIU_SEGMENT,           // Current segment selection
        output wire        BIU_NMI_CAUGHT,        // NMI edge detected and latched
        input  wire        BIU_NMI_DEBOUNCE,      // NMI debounce control from EU
        output reg         BIU_INTR,              // Processed interrupt request to EU
        // Prefetch Queue Interface
        output wire  [7:0] PFQ_TOP_BYTE,          // Top byte from prefetch queue
        output wire        PFQ_EMPTY,             // Prefetch queue empty status
        output wire [15:0] PFQ_ADDR_OUT,          // Prefetch queue read address
        // Segment Register Interface
        output wire [15:0] BIU_REGISTER_ES,       // Extra Segment register
        output wire [15:0] BIU_REGISTER_SS,       // Stack Segment register
        output wire [15:0] BIU_REGISTER_CS,       // Code Segment register
        output wire [15:0] BIU_REGISTER_DS,       // Data Segment register
        output wire [15:0] BIU_REGISTER_RM,       // R/M operand register
        output wire [15:0] BIU_REGISTER_REG,      // REG operand register
        output wire [15:0] BIU_RETURN_DATA        // Data returned from bus operations
    );

    //------------------------------------------------------------------------
    // Internal Control and Status Signals
    //------------------------------------------------------------------------
    reg         biu_done_int;                    // Internal BIU done signal
    reg         byte_num;                        // Current byte in word operation (0=low, 1=high)
    reg         clk_d1;                          // CLK delayed 1 cycle
    reg         clk_d2;                          // CLK delayed 2 cycles
    reg         clk_d3;                          // CLK delayed 3 cycles
    reg         clk_d4;                          // CLK delayed 4 cycles
    reg         eu_biu_req_caught;               // EU request edge detected and latched
    reg         eu_biu_req_d1;                   // EU request delayed 1 cycle
    reg         eu_prefix_lock_d1;               // LOCK prefix delayed 1 cycle
    reg         eu_prefix_lock_d2;               // LOCK prefix delayed 2 cycles
    reg         intr_d1;                         // INTR delayed 1 cycle
    reg         intr_d2;                         // INTR delayed 2 cycles
    reg         intr_d3;                         // INTR delayed 3 cycles
    reg         nmi_caught;                      // NMI edge detected flag
    reg         nmi_d1;                          // NMI delayed 1 cycle
    reg         nmi_d2;                          // NMI delayed 2 cycles
    reg         nmi_d3;                          // NMI delayed 3 cycles
    reg         pfq_write;                       // Prefetch queue write enable
    reg         ready_d1;                        // READY delayed 1 cycle
    reg         ready_d2;                        // READY delayed 2 cycles
    reg         ready_d3;                        // READY delayed 3 cycles
    reg         word_cycle;                      // Current operation is 16-bit

    //------------------------------------------------------------------------
    // Bus Cycle Control and Address Generation
    //------------------------------------------------------------------------
    reg   [7:0] ad_in_int;                       // Latched input data
    reg  [19:0] addr_out_temp;                   // Temporary address calculation
    reg   [7:0] biu_state;                       // Bus state machine state
    reg  [12:0] clock_cycle_counter;             // Instruction cycle accuracy counter
    reg   [7:0] latched_data_in;                 // Data latched during T4
    reg   [2:0] s_bits;                          // Status bits for bus cycle type

    //------------------------------------------------------------------------
    // Segment Registers and Pipeline Delays
    //------------------------------------------------------------------------
    reg  [15:0] biu_register_cs;                 // Code Segment register
    reg  [15:0] biu_register_es;                 // Extra Segment register
    reg  [15:0] biu_register_ss;                 // Stack Segment register
    reg  [15:0] biu_register_ds;                 // Data Segment register
    reg  [15:0] biu_register_rm;                 // R/M operand register
    reg  [15:0] biu_register_reg;                // REG operand register

    // Pipeline delay stages for timing optimization
    reg  [15:0] biu_register_cs_d1;              // Code Segment delayed 1 cycle
    reg  [15:0] biu_register_es_d1;              // Extra Segment delayed 1 cycle
    reg  [15:0] biu_register_ss_d1;              // Stack Segment delayed 1 cycle
    reg  [15:0] biu_register_ds_d1;              // Data Segment delayed 1 cycle
    reg  [15:0] biu_register_rm_d1;              // R/M operand delayed 1 cycle
    reg  [15:0] biu_register_reg_d1;             // REG operand delayed 1 cycle
    reg  [15:0] biu_register_cs_d2;              // Code Segment delayed 2 cycles
    reg  [15:0] biu_register_es_d2;              // Extra Segment delayed 2 cycles
    reg  [15:0] biu_register_ss_d2;              // Stack Segment delayed 2 cycles
    reg  [15:0] biu_register_ds_d2;              // Data Segment delayed 2 cycles
    reg  [15:0] biu_register_rm_d2;              // R/M operand delayed 2 cycles
    reg  [15:0] biu_register_reg_d2;             // REG operand delayed 2 cycles

    reg  [15:0] biu_return_data_int;             // Internal return data
    reg  [15:0] biu_return_data_int_d1;          // Return data delayed 1 cycle
    reg  [15:0] biu_return_data_int_d2;          // Return data delayed 2 cycles
    reg  [15:0] eu_register_r3_d;                // EU R3 register delayed

    //------------------------------------------------------------------------
    // Prefetch Queue Implementation (4-byte circular buffer)
    //------------------------------------------------------------------------
    reg  [15:0] pfq_addr_out;                    // Prefetch queue read pointer
    reg   [7:0] pfq_entry0;                      // Prefetch queue entry 0
    reg   [7:0] pfq_entry1;                      // Prefetch queue entry 1
    reg   [7:0] pfq_entry2;                      // Prefetch queue entry 2
    reg   [7:0] pfq_entry3;                      // Prefetch queue entry 3
    reg  [15:0] pfq_addr_in;                     // Prefetch queue write pointer
    reg   [7:0] pfq_top_byte_int_d1;             // Prefetch queue output delayed
    reg  [15:0] pfq_addr_out_d1;                 // Prefetch queue address delayed

    //------------------------------------------------------------------------
    // EU Command Decoder Signals
    //------------------------------------------------------------------------
    wire        eu_biu_req;                      // EU bus request
    wire        eu_prefix_seg;                   // Segment override prefix active
    wire        pfq_empty;                       // Prefetch queue empty flag
    wire        pfq_full;                        // Prefetch queue full flag
    wire [15:0] biu_muxed_segment;               // Selected segment register
    wire  [1:0] biu_segment;                     // Current segment selection
    wire  [1:0] eu_biu_strobe;                   // EU strobe commands
    wire  [1:0] eu_biu_segment;                  // EU segment selection
    wire  [4:0] eu_biu_req_code;                 // EU request operation code
    wire  [1:0] eu_qs_out;                       // EU queue status output
    wire  [1:0] eu_segment_override_value;       // EU segment override value
    wire  [7:0] pfq_top_byte_int;                // Internal prefetch queue top byte

    //------------------------------------------------------------------------
    // BIU Output Signal Assignments
    //------------------------------------------------------------------------
    assign BIU_DONE                 = biu_done_int;
    assign PFQ_EMPTY                = pfq_empty;
    assign PFQ_ADDR_OUT             = pfq_addr_out_d1;
    assign BIU_SEGMENT              = biu_segment;
    assign BIU_REGISTER_ES          = biu_register_es_d2;
    assign BIU_REGISTER_SS          = biu_register_ss_d2;
    assign BIU_REGISTER_CS          = biu_register_cs_d2;
    assign BIU_REGISTER_DS          = biu_register_ds_d2;
    assign BIU_REGISTER_RM          = biu_register_rm_d2;
    assign BIU_REGISTER_REG         = biu_register_reg_d2;
    assign BIU_RETURN_DATA          = biu_return_data_int_d2;
    assign BIU_NMI_CAUGHT           = nmi_caught;

    //------------------------------------------------------------------------
    // EU Command Decoder
    //------------------------------------------------------------------------
    // Decodes the 16-bit EU command word into control signals for BIU operation
    assign eu_prefix_seg                   = EU_BIU_COMMAND[14];     // Segment override active
    assign eu_biu_strobe[1:0]              = EU_BIU_COMMAND[13:12];  // Strobe commands: 01=opcode fetch, 10=clock load, 11=segment load
    assign eu_biu_segment[1:0]             = EU_BIU_COMMAND[11:10];  // Default segment selection
    assign eu_biu_req                      = EU_BIU_COMMAND[9];      // Bus request flag
    assign eu_biu_req_code                 = EU_BIU_COMMAND[8:4];    // Operation code (see state machine)
    assign eu_qs_out[1:0]                  = EU_BIU_COMMAND[3:2];    // Queue status for opcod fetch and jumps
    assign eu_segment_override_value[1:0]  = EU_BIU_COMMAND[1:0];    // Segment override value

    //------------------------------------------------------------------------
    // Segment Selection Logic
    //------------------------------------------------------------------------
    // Select either the current EU segment or the segment override value
    assign biu_segment =  (eu_prefix_seg == 1'b1) ? eu_segment_override_value  : eu_biu_segment;

    // Multiplex segment registers based on segment selection
    assign biu_muxed_segment = (biu_segment == 2'b00) ? biu_register_es :  // Extra Segment
                               (biu_segment == 2'b01) ? biu_register_ss :  // Stack Segment
                               (biu_segment == 2'b10) ? biu_register_cs :  // Code Segment
                                                        biu_register_ds ;  // Data Segment

    //------------------------------------------------------------------------
    // Prefetch Queue Output Multiplexer
    //------------------------------------------------------------------------
    // Steer the prefetch queue to the EU based on read pointer
    assign pfq_top_byte_int = (pfq_addr_out[1:0] == 2'b00) ? pfq_entry0 :
                              (pfq_addr_out[1:0] == 2'b01) ? pfq_entry1 :
                              (pfq_addr_out[1:0] == 2'b10) ? pfq_entry2 :
                                                             pfq_entry3 ;

    assign PFQ_TOP_BYTE = pfq_top_byte_int_d1;

    //------------------------------------------------------------------------
    // Prefetch Queue Status Generation
    //------------------------------------------------------------------------
    // Generate prefetch queue full and empty flags based on address pointers
    assign pfq_full  = ( (pfq_addr_in[2] != pfq_addr_out[2]) && (pfq_addr_in[1:0] == pfq_addr_out[1:0]) ) ?  1'b1 : 1'b0;
    assign pfq_empty = ( (pfq_addr_in[2] == pfq_addr_out[2]) && (pfq_addr_in[1:0] == pfq_addr_out[1:0]) ) ?  1'b1 : 1'b0;

    //------------------------------------------------------------------------
    // Instruction Cycle Accuracy Counter
    //------------------------------------------------------------------------
    // Provides cycle-accurate timing compatible with original Intel 8088
    // Can be disabled by tying BIU_CLK_COUNTER_ZERO to '1' for faster operation
    assign BIU_CLK_COUNTER_ZERO = (clock_cycle_counter == 13'h0000) ? 1'b1 : 1'b0;
    //assign BIU_CLK_COUNTER_ZERO = 1'b1;  // Uncomment to disable cycle accuracy

    //------------------------------------------------------------------------
    // BIU State Machine - Main Bus Controller
    //------------------------------------------------------------------------
    // Implements the complete Intel 8088 bus protocol with proper timing
    always @(posedge CORE_CLK_INT) begin : BIU_STATE_MACHINE
        if (RESET_INT == 1'b1) begin
            // Reset all internal registers to initial state
            clk_d1              <= 'h0;
            clk_d2              <= 'h0;
            clk_d3              <= 'h0;
            clk_d4              <= 'h0;
            nmi_d1              <= 'h0;
            nmi_d2              <= 'h0;
            nmi_d3              <= 'h0;
            nmi_caught          <= 'h0;
            eu_register_r3_d    <= 'h0;
            eu_biu_req_caught   <= 'h0;
            biu_register_cs     <= 16'hFFFF;  // Boot from reset vector
            biu_register_es     <= 'h0;
            biu_register_ss     <= 'h0;
            biu_register_ds     <= 'h0;
            biu_register_rm     <= 'h0;
            biu_register_reg    <= 'h0;
            clock_cycle_counter <= 'h0;
            pfq_addr_out        <= 'h0;
            pfq_entry0          <= 'h0;
            pfq_entry1          <= 'h0;
            pfq_entry2          <= 'h0;
            pfq_entry3          <= 'h0;
            biu_state           <= 8'hD0;     // Wait state before starting
            pfq_write           <= 'h0;
            pfq_addr_in         <= 'h0;
            biu_return_data_int <= 'h0;
            biu_done_int        <= 'h0;
            ready_d1            <= 'h0;
            ready_d2            <= 'h0;
            ready_d3            <= 'h0;
            eu_biu_req_d1       <= 'h0;
            latched_data_in     <= 'h0;
            addr_out_temp       <= 'h0;
            s_bits              <= 3'b111;
            AD_OUT              <= 'h0;
            word_cycle          <= 1'b0;
            byte_num            <= 1'b0;
            ad_in_int           <= 'h0;
            BIU_INTR            <= 'h0;
            eu_prefix_lock_d1   <= 'h0;
            eu_prefix_lock_d2   <= 'h0;
            intr_d1             <= 'h0;
            intr_d2             <= 'h0;
            intr_d3             <= 'h0;

            // Initialize bus control signals
            AD_OE               <= 'h0;
            RD_n                <= 1'b1;
            WR_n                <= 1'b1;
            IOM                 <= 'h0;
            DTR                 <= 'h0;
            DEN                 <= 1'b1;
            INTA_n              <= 1'b1;
        end
        else begin
            //----------------------------------------------------------------
            // Signal Pipeline Management
            //----------------------------------------------------------------
            // Clock edge detection pipeline
            clk_d1 <= CLK;
            clk_d2 <= clk_d1;
            clk_d3 <= clk_d2;
            clk_d4 <= clk_d3;

            // READY signal pipeline for proper sampling
            ready_d1 <= READY_IN;
            ready_d2 <= ready_d1;
            ready_d3 <= ready_d2;

            // NMI edge detection pipeline
            nmi_d1 <= NMI;
            nmi_d2 <= nmi_d1;
            nmi_d3 <= nmi_d2;

            // INTR signal pipeline
            intr_d1 <= INTR;
            intr_d2 <= intr_d1;
            intr_d3 <= intr_d2;

            //----------------------------------------------------------------
            // Register Pipeline Delays for Timing Optimization
            //----------------------------------------------------------------
            // These signals may be pipelined from zero to two clocks
            // Currently pipelined by two clocks for timing closure
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

            // Prefetch queue output pipeline (1 clock delay)
            pfq_top_byte_int_d1 <= pfq_top_byte_int;
            pfq_addr_out_d1     <= pfq_addr_out;

            // Return data pipeline for timing stability
            biu_return_data_int_d1 <= biu_return_data_int;
            biu_return_data_int_d2 <= biu_return_data_int_d1;

            //----------------------------------------------------------------
            // Interrupt and NMI Edge Detection
            //----------------------------------------------------------------
            // NMI caught on rising edge with debounce control
            if (nmi_d3 == 1'b0 && nmi_d2 == 1'b0 && nmi_d1 == 1'b1) begin
                nmi_caught <= 1'b1;
            end
            else if (BIU_NMI_DEBOUNCE == 1'b1) begin
                nmi_caught <= 1'b0;
            end

            // INTR sampled on rising edge of CLK for proper timing
            if (clk_d4 == 1'b0 && clk_d3 == 1'b0 && clk_d2 == 1'b1) begin
                BIU_INTR <= intr_d3;
            end

            // LOCK prefix pipeline
            eu_prefix_lock_d1 <= EU_PREFIX_LOCK;
            eu_prefix_lock_d2 <= eu_prefix_lock_d1;

            // Register input pipeline for timing
            eu_register_r3_d <= EU_REGISTER_R3;
            ad_in_int        <= AD_IN;

            //----------------------------------------------------------------
            // EU Request Edge Detection and Latching
            //----------------------------------------------------------------
            // Capture rising edge of bus request from EU
            eu_biu_req_d1 <= eu_biu_req;
            if (eu_biu_req_d1 == 1'b0 && eu_biu_req == 1'b1) begin
                eu_biu_req_caught <= 1'b1;
            end
            else if (biu_done_int == 1'b1) begin
                eu_biu_req_caught <= 1'b0;
            end

            //----------------------------------------------------------------
            // EU Strobe Command Processing
            //----------------------------------------------------------------
            // Strobe from EU to update segment and addressing registers
            if (eu_biu_strobe == 2'b11) begin
                case (eu_biu_req_code[2:0])  // synthesis parallel_case
                    3'h0 : biu_register_es  <= EU_BIU_DATAOUT[15:0];  // Load ES
                    3'h1 : biu_register_ss  <= EU_BIU_DATAOUT[15:0];  // Load SS
                    3'h2 : biu_register_cs  <= EU_BIU_DATAOUT[15:0];  // Load CS
                    3'h3 : biu_register_ds  <= EU_BIU_DATAOUT[15:0];  // Load DS
                    3'h4 : biu_register_rm  <= EU_BIU_DATAOUT[15:0];  // Load R/M
                    3'h5 : biu_register_reg <= EU_BIU_DATAOUT[15:0];  // Load REG
                    default :;
                endcase
            end

            //----------------------------------------------------------------
            // Instruction Cycle Counter Management
            //----------------------------------------------------------------
            // Strobe from EU to set the 8088 clock cycle counter for timing accuracy
            if (eu_biu_strobe == 2'b10) begin
                clock_cycle_counter <= EU_BIU_DATAOUT[12:0];
            end
            else if (clock_cycle_counter != 13'h0000) begin
                clock_cycle_counter <= clock_cycle_counter - 1;
            end

            //----------------------------------------------------------------
            // Prefetch Queue Management
            //----------------------------------------------------------------
            // Increment output address upon EU fetch request strobe
            // Update/flush the prefetch queue when EU asserts jump request
            // Increment input address during prefetch queue fetches
            if (eu_biu_req_caught == 1'b1 && eu_biu_req_code == 5'h19) begin
                pfq_addr_out <= eu_register_r3_d; // Update prefetch queue to new address (jump/call)
            end
            else if (eu_biu_strobe == 2'b01 && pfq_empty == 1'b0) begin
                pfq_addr_out <= pfq_addr_out + 1;  // Increment instruction pointer
            end

            // Prefetch queue write pointer management
            if (eu_biu_req_caught == 1'b1 && eu_biu_req_code == 5'h19) begin
                pfq_addr_in <= eu_register_r3_d; // Update prefetch queue to new address (jump/call)
            end
            else if (pfq_write == 1'b1) begin
                pfq_addr_in <= pfq_addr_in + 1;
            end

            // Write to the selected prefetch queue entry
            if (pfq_write == 1'b1) begin
                case (pfq_addr_in[1:0])  // synthesis parallel_case
                    2'b00 : pfq_entry0 <= latched_data_in[7:0];
                    2'b01 : pfq_entry1 <= latched_data_in[7:0];
                    2'b10 : pfq_entry2 <= latched_data_in[7:0];
                    2'b11 : pfq_entry3 <= latched_data_in[7:0];
                    default :;
                endcase
            end

            //----------------------------------------------------------------
            // 8088 BIU State Machine - Bus Cycle Controller
            //----------------------------------------------------------------
            // Implements the complete Intel 8088 bus timing protocol
            biu_state <= biu_state + 1'b1;

            case (biu_state) // synthesis parallel_case
                //------------------------------------------------------------
                // State 00h: IDLE - Wait for EU request or prefetch opportunity
                //------------------------------------------------------------
                8'h00: begin
                    // Reset cycle control signals
                    pfq_write  <= 1'b0;
                    byte_num   <= 1'b0;
                    word_cycle <= 1'b0;

                    if (eu_biu_req_caught == 1'b1) begin
                        case (eu_biu_req_code)  // synthesis parallel_case
                            // Interrupt Acknowledge Cycle (INTA)
                            8'h16: begin
                                addr_out_temp <= { 4'h0 , eu_register_r3_d[15:0] };
                                word_cycle <= 1'b1;
                                s_bits <= 3'b000;  // INTA cycle
                                biu_state <= 8'h01;
                            end

                            // I/O Byte Read
                            8'h08: begin
                                addr_out_temp <= { 4'h0 , eu_register_r3_d[15:0] };
                                s_bits <= 3'b001;  // I/O read
                                biu_state <= 8'h01;
                            end

                            // I/O Word Read
                            8'h1A: begin
                                addr_out_temp <= { 4'h0 , eu_register_r3_d[15:0] };
                                word_cycle <= 1'b1;
                                s_bits <= 3'b001;  // I/O read
                                biu_state <= 8'h01;
                            end

                            // I/O Byte Write
                            8'h0A: begin
                                addr_out_temp <= { 4'h0 , eu_register_r3_d[15:0] };
                                s_bits <= 3'b010;  // I/O write
                                biu_state <= 8'h01;
                            end

                            // I/O Word Write
                            8'h1C: begin
                                addr_out_temp <= { 4'h0 , eu_register_r3_d[15:0] };
                                word_cycle <= 1'b1;
                                s_bits <= 3'b010;  // I/O write
                                biu_state <= 8'h01;
                            end

                            // Halt Request
                            8'h18: begin
                                addr_out_temp <= { biu_register_cs[15:0] , 4'h0 } + pfq_addr_out[15:0] ;
                                s_bits <= 3'b011;  // Halt
                                biu_state <= 8'h01;
                            end

                            // Memory Byte Read
                            8'h0C: begin
                                addr_out_temp <= { biu_muxed_segment[15:0] , 4'h0 } + eu_register_r3_d[15:0];
                                s_bits <= 3'b101;  // Memory read
                                biu_state <= 8'h01;
                            end

                            // Memory Word Read
                            8'h10: begin
                                addr_out_temp <= { biu_muxed_segment[15:0] , 4'h0 } + eu_register_r3_d[15:0];
                                word_cycle <= 1'b1;
                                s_bits <= 3'b101;  // Memory read
                                biu_state <= 8'h01;
                            end

                            // Memory Word Read from Stack Segment
                            8'h11: begin
                                addr_out_temp <= { biu_register_ss[15:0] , 4'h0 } + eu_register_r3_d[15:0];
                                word_cycle <= 1'b1;
                                s_bits <= 3'b101;  // Memory read
                                biu_state <= 8'h01;
                            end

                            // Memory Word Read from Segment 0x0000 (interrupt vector fetch)
                            8'h12: begin
                                addr_out_temp <= { 4'h0 , eu_register_r3_d[15:0] };
                                word_cycle <= 1'b1;
                                s_bits <= 3'b101;  // Memory read
                                biu_state <= 8'h01;
                            end

                            // Memory Byte Write
                            8'h0E: begin
                                addr_out_temp <= { biu_muxed_segment[15:0] , 4'h0 } + eu_register_r3_d[15:0];
                                s_bits <= 3'b110;  // Memory write
                                biu_state <= 8'h01;
                            end

                            // Memory Word Write
                            8'h13: begin
                                addr_out_temp <= { biu_muxed_segment[15:0] , 4'h0 } + eu_register_r3_d[15:0];
                                word_cycle <= 1'b1;
                                s_bits <= 3'b110;  // Memory write
                                biu_state <= 8'h01;
                            end

                            // Memory Word Write to Stack Segment
                            8'h14: begin
                                addr_out_temp <= { biu_register_ss[15:0] , 4'h0 } + eu_register_r3_d[15:0];
                                word_cycle <= 1'b1;
                                s_bits <= 3'b110;  // Memory write
                                biu_state <= 8'h01;
                            end

                            // Jump Request (prefetch queue flush)
                            8'h19: begin
                                biu_done_int <= 1'b1;
                                biu_state <= 8'h46;
                            end

                            default :;
                        endcase
                    end

                    // Start prefetch if queue not full and no EU request pending
                    else if (pfq_full == 1'b0) begin
                        addr_out_temp <= { biu_register_cs[15:0] , 4'h0 } + pfq_addr_in[15:0] ;
                        s_bits        <= 3'b100;  // Code fetch
                        biu_state     <= 8'h01;
                    end

                    else begin
                        biu_state <= 8'h00;  // Stay in idle
                    end

                end

                //------------------------------------------------------------
                // State 01h: T1 Setup - Wait for CLK rising edge to start cycle
                //------------------------------------------------------------
                8'h01: begin
                    if (clk_d4 == 1'b0 && clk_d3 == 1'b0 && clk_d2 == 1'b1) // Wait for CLK rising edge
                    begin
                        IOM <= ~s_bits[2]; // Set Memory(0)/IO(1) signal
                        DTR <=  s_bits[1]; // Set Data Transmit/Receive direction
                    end
                    else begin
                        biu_state <= 8'h01;  // Wait for CLK edge
                    end
                end

                //------------------------------------------------------------
                // State 04h: T1 Address Phase - Output address and assert ALE
                //------------------------------------------------------------
                8'h04: begin
                    AD_OUT[19:0] <= addr_out_temp[19:0];  // Output 20-bit address
                    AD_OE <= 1'b1;                        // Enable address/data drivers
                    ALE   <= 1'b1;                        // Assert Address Latch Enable
                end

                //------------------------------------------------------------
                // State 13h: T2 Setup - Disable ALE, prepare for data phase
                //------------------------------------------------------------
                8'h13: begin
                    ALE <= 1'b0;  // Disable ALE (address latched externally)

                    if (s_bits[1] == 1'b1) begin  // For read cycles
                        DEN <= 1'b0;  // Enable data transceivers early
                    end
                end

                //------------------------------------------------------------
                // State 19h: T2 Data Phase - Setup data bus direction and strobes
                //------------------------------------------------------------
                8'h19: begin
                    AD_OE <=  s_bits[1];  // Disable drivers for read, enable for write
                    RD_n  <=  s_bits[1];  // Assert RD_n for read cycles
                    WR_n  <= ~s_bits[1];  // Assert WR_n for write cycles

                    // Special case for interrupt acknowledge
                    if (s_bits == 3'b000) begin
                        INTA_n <= 1'b0;
                    end

                    // Output write data (high byte for second cycle of word operation)
                    if (word_cycle == 1'b1 && byte_num == 1'b1) begin
                        AD_OUT[7:0] <= EU_BIU_DATAOUT[15:8];  // High byte
                    end
                    else begin
                        AD_OUT[7:0] <= EU_BIU_DATAOUT[7:0];   // Low byte
                    end
                end

                //------------------------------------------------------------
                // State 28h: T3 Setup - Assert DEN if not already done
                //------------------------------------------------------------
                8'h28: begin
                    DEN <= 1'b0;  // Ensure data enable is asserted
                end

                //------------------------------------------------------------
                // State 2Fh: T3 Ready Check - Sample READY for wait state insertion
                //------------------------------------------------------------
                8'h2F: begin
                    if (ready_d3 == 1'b0)    // READY low = insert wait state
                    begin
                        biu_state <= 8'h1A;  // Jump back to wait state loop
                    end
                end

                //------------------------------------------------------------
                // State 3Dh: T4 Data Sample - Latch input data on read cycles
                //------------------------------------------------------------
                8'h3D: begin
                    latched_data_in <= ad_in_int;

                    // Write to prefetch queue if this is a code fetch
                    if (s_bits == 3'b100) begin
                        pfq_write <= 1'b1;
                    end
                end

                //------------------------------------------------------------
                // State 3Eh: Prefetch Queue Write Debounce
                //------------------------------------------------------------
                8'h3E: begin
                    pfq_write <= 1'b0;  // Clear write pulse
                end

                //------------------------------------------------------------
                // State 40h: T4 Data Steering - Route data to appropriate destination
                //------------------------------------------------------------
                8'h40: begin
                    // Steer data for word operations and return data
                    if (s_bits != 3'b000 && (word_cycle == 1'b1 && byte_num == 1'b1)) begin
                        biu_return_data_int[15:8] <= latched_data_in[7:0];  // High byte
                    end
                    else begin
                        biu_return_data_int[15:0] <= { 8'h00 , latched_data_in[7:0] };  // Low byte with zero extension
                    end
                end

                //------------------------------------------------------------
                // State 45h: T4 End - Complete bus cycle, setup for next cycle
                //------------------------------------------------------------
                8'h45: begin
                    // Deassert all bus control signals
                    WR_n   <= 1'b1;
                    RD_n   <= 1'b1;
                    DEN    <= 1'b1;
                    INTA_n <= 1'b1;

                    // Increment address for next byte in word operation
                    addr_out_temp[15:0] <= addr_out_temp[15:0] + 1;

                    if (word_cycle == 1'b1 && byte_num == 1'b0) begin
                        byte_num  <= 1'b1;    // Start second byte of word operation
                        biu_state <= 8'h50;   // Continue to second cycle
                    end
                    else begin
                        // Complete operation (except for prefetch which doesn't signal done)
                        if (s_bits != 3'b100) begin
                            biu_done_int <= 1'b1;
                        end
                    end
                end

                //------------------------------------------------------------
                // State 46h: Done Signal Debounce
                //------------------------------------------------------------
                8'h46: begin
                    biu_done_int <= 1'b0;  // Clear done signal
                end

                //------------------------------------------------------------
                // State 4Eh: Return to Idle
                //------------------------------------------------------------
                8'h4E: begin
                    biu_state <= 8'h00;  // Return to idle state
                end

                //------------------------------------------------------------
                // State 58h: Continue Word Operation Second Cycle
                //------------------------------------------------------------
                8'h58: begin
                    biu_state <= 8'h01;  // Start second byte cycle
                end

                default :;
            endcase
        end

    end  // BIU_STATE_MACHINE

endmodule

`default_nettype wire
