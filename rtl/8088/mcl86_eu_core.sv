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
// Execution Unit - Microcode-Based Instruction Processing Engine
//
// Description:
//   The EU owns the architectural register file (AX..DI, FLAGS), the ALU, and
//   the microcode sequencer. It never touches the bus: memory and I/O go to the
//   Bus Interface Unit over a request/done handshake, and instruction bytes
//   arrive through the BIU's prefetch queue. That split is what lets one EU
//   serve both the 8-bit 8088 and the 16-bit 8086 unchanged - it issues
//   width-tagged bus requests and never learns how wide the bus really is.
//
//   Execution is microcoded. Each 8086 instruction is a subroutine in a 4Kx32
//   ROM; the sequencer retires one microword per clock, decoding it into a
//   type / destination / two operand-select fields. Instruction dispatch is
//   itself a microcode jump - the opcode byte from the queue is concatenated
//   into the microcode address to vector into that instruction's handler.
//
//   The ALU is deliberately minimal (ADD, BYTESWAP, AND, OR, XOR, single-bit
//   SHR). There is no subtractor: microcode builds SUB from ADD by complementing
//   an operand and adding one (see 0x0A46). Wider shifts are microcode loops.
//
// Datapath:
//
//     eu_rom_address --> [ mcl86_ucode 4Kx32 ] --> decode --> operand muxes
//            ^                                                     |
//            |                                                     v
//            +------------- writeback / jump <----------------- [ ALU ]
//
// Sequencer lead - the one thing to know before editing this file:
//
//   The ROM read is registered while eu_rom_address keeps incrementing, so the
//   address counter runs TWO microwords ahead of the word being executed. Hence:
//
//   1. A taken jump has already admitted the next two words, so the sequencer
//      raises eu_stall_pipeline for one clock to squash them.
//   2. RTL that identifies an instruction by watching the microcode PC hit a
//      constant is watching an address the sequencer also GRAZES on its way past
//      a neighbouring routine. A marker must sit deep enough into its own arm
//      that no other path can overshoot into it. Not hypothetical: this is how a
//      marker meant for IDIV once fired for plain DIV (see the note below).
//
// FLAGS layout - eu_flags is not just the architectural FLAGS word. Microcode
//   reuses every bit the 8086 leaves RESERVED as private scratch:
//
//     bit  15  14  13  12  11  10   9   8   7   6   5   4   3   2   1   0
//     8086  -   -   -   -  OF  DF  IF  TF  SF  ZF   -  AF   -  PF   -  CF
//     here RPZ REP LCK NMD  OF  DF  IF  TF  SF  ZF TFD  AF NMP  PF TMP  CF
//
//   Architectural flags sit where an 8086 programmer expects them; the reserved
//   bits carry the REP/REPNZ/LOCK prefix latches, NMI debounce and pending, the
//   TF debounce, and a temp. Consumers wanting a real FLAGS value must mask the
//   scratch bits off, as sim/sst does.
//
// Limitations:
//   - Ten flag alias wires (eu_flag_o/d/s/z/a/p, eu_prefix_rep/repnz,
//     eu_nmi_pending, eu_flag_temp) are driven but never read. They name the bit
//     layout for waveforms; microcode reads these bits through eu_flags. Not dead
//     code to be swept up.
//   - system_signals bits 15, 14 and 10 have no driver. Microcode must not select
//     them as an operand source.
//   - The microcode addresses this file watches are load-bearing: tools/uccheck.py
//     scrapes them out of this source text, comments included. Write addresses in
//     comments as 0xNNNN, never in the eu_rom_address == 'hNNNN form it matches.
//
// References:
//   - Intel 8086 Family User's Manual (Oct 1979) - FLAGS, STI/IF delay, TF
//   - MCL86 by Ted Fried (MicroCoreLabs) - original microcoded implementation
//   - docs/learnings.md - the IDIV marker and divide-FLAGS investigations
//   - tools/uccheck.py - microcode round-trip and marker-coupling tripwire
//
// Changelog:
// 1.0 - 10/8/15 - Initial revision
// 2.0 - 11/6/22 - Changed overflow flag calculation into rtl instead of microcode
// 3.0 - 9/29/25 - For DIV overflow AX and DX are restored to initial values
//------------------------------------------------------------------------------

`default_nettype none
`timescale 1ns/1ps

module mcl86_eu_core
    (
        // System Interface
        input  wire        CORE_CLK_INT,          // High-speed core clock
        input  wire        RESET_INT,             // Synchronous reset (active high)
        input  wire        TEST_N_INT,            // Test pin input (active low, can be tied high)
        // EU to BIU Command Interface
        output wire [15:0] EU_BIU_COMMAND,        // Command word to BIU for bus operations
        output wire [15:0] EU_BIU_DATAOUT,        // Data output to BIU for write operations
        output wire [15:0] EU_REGISTER_R3,        // Temporary register R3 for BIU addressing
        output wire        EU_PREFIX_LOCK,        // LOCK prefix active flag
        output wire        EU_FLAG_I,             // Interrupt enable flag (delayed)
        // BIU to EU Status Interface
        input  wire        BIU_DONE,              // BIU operation complete flag
        input  wire        BIU_CLK_COUNTER_ZERO,  // BIU clock counter reached zero
        input  wire        BIU_NMI_CAUGHT,        // BIU detected NMI edge
        output wire        BIU_NMI_DEBOUNCE,      // EU NMI debounce control
        input  wire        BIU_INTR,              // BIU processed interrupt request
        // Prefetch Queue Interface
        input  wire  [7:0] PFQ_TOP_BYTE,          // Top byte from prefetch queue
        input  wire        PFQ_EMPTY,             // Prefetch queue empty status
        input  wire [15:0] PFQ_ADDR_OUT,          // Prefetch queue address output
        // Segment Register Interface (from BIU)
        input  wire [15:0] BIU_REGISTER_ES,       // Extra Segment register
        input  wire [15:0] BIU_REGISTER_SS,       // Stack Segment register
        input  wire [15:0] BIU_REGISTER_CS,       // Code Segment register
        input  wire [15:0] BIU_REGISTER_DS,       // Data Segment register
        input  wire [15:0] BIU_REGISTER_RM,       // R/M operand from BIU
        input  wire [15:0] BIU_REGISTER_REG,      // REG operand from BIU
        input  wire [15:0] BIU_RETURN_DATA        // Data returned from BIU read operations
    );

    //--------------------------------------------------------------------------
    // Internal Signals - Microcode Sequencer
    //--------------------------------------------------------------------------
    // NOTE: eu_rom_address, eu_flags and eu_register_* are poked and peeked by
    // hierarchical name from the Verilator SST harness (sim/sst/sst_main.cpp
    // reaches them as sst_tb.dut.u_eu_core.<name>). Renaming any of them breaks
    // the test harness silently - the C++ macro just stops resolving.
    reg  [12:0] eu_rom_address;         // Microcode PC. Runs 2 words ahead of the executing word
    reg  [51:0] eu_calling_address;     // 4-deep call stack: four 13-bit return addresses, shifted
    reg         eu_stall_pipeline;      // Squash the 2 words already in flight behind a taken jump
    wire [31:0] eu_rom_data;            // Microword fetched from the ucode ROM (registered read)
    wire        new_instruction;        // uPC is in the opcode dispatch page -> a macro-op is starting

    //--------------------------------------------------------------------------
    // Internal Signals - Microword Decode
    //--------------------------------------------------------------------------
    wire  [2:0] eu_opcode_type;         // ALU / control op: 0=NOP 1=JUMP 2=ADD 3=BSWAP 4=AND 5=OR 6=XOR 7=SHR
    wire  [3:0] eu_opcode_dst_sel;      // Writeback destination select
    wire  [3:0] eu_opcode_op0_sel;      // Operand 0 source select (EU-side)
    wire  [3:0] eu_opcode_op1_sel;      // Operand 1 source select (BIU-side)
    wire [15:0] eu_opcode_immediate;    // Immediate / jump target field
    wire        eu_opcode_jump_call;    // Jump variant: push the return address (microcode CALL)
    wire  [2:0] eu_opcode_jump_src;     // Jump variant: where the target address comes from
    wire  [3:0] eu_opcode_jump_cond;    // Jump variant: condition to evaluate
    wire        eu_jump_boolean;        // Resolved "take this jump" decision

    //--------------------------------------------------------------------------
    // Internal Signals - Architectural Register File
    //--------------------------------------------------------------------------
    reg  [15:0] eu_register_ax;         // Accumulator
    reg  [15:0] eu_register_bx;         // Base
    reg  [15:0] eu_register_cx;         // Count
    reg  [15:0] eu_register_dx;         // Data
    reg  [15:0] eu_register_sp;         // Stack pointer
    reg  [15:0] eu_register_bp;         // Base pointer
    reg  [15:0] eu_register_si;         // Source index
    reg  [15:0] eu_register_di;         // Destination index
    reg  [15:0] eu_flags;               // FLAGS + microcode scratch (see header for the bit map)

    //--------------------------------------------------------------------------
    // Internal Signals - Microcode Scratch Registers
    //--------------------------------------------------------------------------
    // r0/r1 double as the ALU operand staging pair: the flag-setter microcode
    // routines load them before computing, which is what lets the overflow and
    // divide fixups below snoop the true operands.
    reg  [15:0] eu_register_r0;         // Scratch 0 / ALU left operand for flag setters
    reg  [15:0] eu_register_r1;         // Scratch 1 / ALU right operand for flag setters
    reg  [15:0] eu_register_r2;         // Scratch 2 / divide partial remainder
    reg  [15:0] eu_register_r3;         // Scratch 3 / effective address, exported to the BIU

    //--------------------------------------------------------------------------
    // Internal Signals - Flag Aliases (decode of eu_flags)
    //--------------------------------------------------------------------------
    // Only eu_flag_c, eu_flag_i, eu_flag_t, eu_tf_debounce and eu_prefix_lock
    // are consumed by RTL. The rest are named purely to document the bit layout
    // and to show up in waveforms; microcode reads them via eu_flags directly.
    wire        eu_flag_c;              // bit  0 - Carry
    wire        eu_flag_temp;           // bit  1 - reserved on 8086; microcode temp
    wire        eu_flag_p;              // bit  2 - Parity
    wire        eu_nmi_pending;         // bit  3 - reserved on 8086; NMI pending
    wire        eu_flag_a;              // bit  4 - Auxiliary carry
    wire        eu_tf_debounce;         // bit  5 - reserved on 8086; clears the latched TF
    wire        eu_flag_z;              // bit  6 - Zero
    wire        eu_flag_s;              // bit  7 - Sign
    wire        eu_flag_t;              // bit  8 - Trap (single step)
    wire        eu_flag_i;              // bit  9 - Interrupt enable (raw; see intr_enable_delayed)
    wire        eu_flag_d;              // bit 10 - Direction
    wire        eu_flag_o;              // bit 11 - Overflow
    wire        eu_prefix_lock;         // bit 13 - reserved on 8086; LOCK prefix latch
    wire        eu_prefix_rep;          // bit 14 - reserved on 8086; REP prefix latch
    wire        eu_prefix_repnz;        // bit 15 - reserved on 8086; REPNZ prefix latch

    //--------------------------------------------------------------------------
    // Internal Signals - ALU and Adder
    //--------------------------------------------------------------------------
    wire [15:0] eu_operand0;            // Operand 0 mux output
    wire [15:0] eu_operand1;            // Operand 1 mux output
    wire [15:0] eu_alu2;                // ADD result
    wire [15:0] eu_alu3;                // BYTESWAP result
    wire [15:0] eu_alu4;                // AND result
    wire [15:0] eu_alu5;                // OR result
    wire [15:0] eu_alu6;                // XOR result
    wire [15:0] eu_alu7;                // SHR result
    wire [15:0] eu_alu_out;             // Selected ALU result
    reg  [15:0] eu_alu_last_result;     // Retained result - the z/nz jump conditions test THIS
    wire [15:0] adder_out;              // Adder sum
    wire [16:0] carry;                  // Carry into each bit; carry[16] is the carry out

    //--------------------------------------------------------------------------
    // Internal Signals - Arithmetic Flag Generation
    //--------------------------------------------------------------------------
    reg         eu_add_carry;           // Carry out of bit 15 (word ops)
    reg         eu_add_carry8;          // Carry out of bit 7  (byte ops)
    reg         eu_add_aux_carry;       // Carry out of bit 3  (BCD aux carry)
    reg         eu_add_overflow16;      // Signed overflow, word
    reg         eu_add_overflow8;       // Signed overflow, byte
    wire        eu_parity;              // Even parity of eu_alu_last_result[7:0]

    //--------------------------------------------------------------------------
    // Internal Signals - Signed Overflow Fixup
    //--------------------------------------------------------------------------
    // The adder's carry[n]^carry[n-1] overflow is not correct for every path the
    // microcode takes through ADD/ADC/SUB/SBB. Instead of fixing that in
    // microcode, the sequencer watches the eight flag-setter entry points, works
    // the signed-overflow rule directly on the operand and result sign bits, and
    // substitutes the answer. eu_overflow_override arms the substitution; the
    // main-loop microword (0x0011) disarms it.
    reg         eu_overflow_override;   // Use the *_fixed values instead of the carry-XOR ones
    reg         eu_add_overflow8_fixed; // Sign-rule overflow, byte
    reg         eu_add_overflow16_fixed;// Sign-rule overflow, word
    wire [15:0] add_total;              // r0 + r1        - probe for the fixup, not an ALU path
    wire [15:0] adc_total;              // r0 + r1 + CF   - probe for the fixup, not an ALU path
    wire [15:0] sub_total;              // r0 - r1        - probe for the fixup, not an ALU path
    wire [15:0] sbb_total;              // r0 - r1 - CF   - probe for the fixup, not an ALU path

    //--------------------------------------------------------------------------
    // Internal Signals - Divide Support
    //--------------------------------------------------------------------------
    reg         idiv_opcode;            // This divide is the signed (IDIV) arm, not DIV
    reg  [15:0] initial_ax;             // AX on entry to the divide, for the DIV0 restore
    reg  [15:0] initial_dx;             // DX on entry to the divide, for the DIV0 restore
    reg  [15:0] div_flag_src;           // Last in-range CORD subtract input - the FLAGS a divide leaves

    //--------------------------------------------------------------------------
    // Internal Signals - BIU Handshake and Interrupts
    //--------------------------------------------------------------------------
    reg         biu_done_d1;            // BIU_DONE resync / edge detect stage 1
    reg         biu_done_d2;            // BIU_DONE resync / edge detect stage 2
    reg         biu_done_caught;        // Sticky "BIU finished", cleared when the request drops
    wire        eu_biu_req;             // Bus request, decoded out of eu_biu_command
    reg         eu_biu_req_d1;          // Delayed request, for the falling-edge clear
    reg  [15:0] eu_biu_command;         // Command word presented to the BIU
    reg  [15:0] eu_biu_dataout;         // Write data / EA decode source presented to the BIU
    reg         intr_enable_delayed;    // IF, delayed one instruction (STI semantics)
    reg         intr_delay;             // BIU_INTR sampled at the last instruction boundary
    wire        intr_asserted;          // INTR that is actually allowed through right now
    reg         eu_flag_t_d;            // TF delayed, for rising-edge detect
    reg         eu_tr_latched;          // Single-step trap armed for this instruction

    //--------------------------------------------------------------------------
    // Internal Signals - Status Bus
    //--------------------------------------------------------------------------
    wire [15:0] system_signals;         // Status bits gathered so microcode can read them as an operand

    //--------------------------------------------------------------------------
    // EU Microcode RAM.  4Kx32 DPRAM
    //--------------------------------------------------------------------------
    // Head of the dataflow, so it stays here rather than down with the other
    // instantiations: everything below decodes what this ROM hands back. The
    // read is registered, which is where the sequencer's 2-word lead comes from.
    mcl86_ucode u_ucode_rom (
        .clk  ( CORE_CLK_INT         ),
        .addr ( eu_rom_address[11:0] ),
        .dout ( eu_rom_data          )
    );

    //--------------------------------------------------------------------------
    // Microcode Instruction Decoder
    //--------------------------------------------------------------------------
    // Decodes the 32-bit microcode word into control fields.
    //
    //   31 30    28 27    24 23    20 19    16 15                            0
    //  +--+--------+--------+--------+--------+--------------------------------+
    //  |  |  type  | dst    | op0    | op1    |           immediate            |
    //  +--+--------+--------+--------+--------+--------------------------------+
    //
    // A JUMP-type word (type == 1) re-reads the same bits as call / src / cond.
    // tools/mcl86_microcode.py transcribes this exact layout - keep them in sync.
    assign eu_opcode_type      = eu_rom_data[30:28];
    assign eu_opcode_dst_sel   = eu_rom_data[27:24];
    assign eu_opcode_op0_sel   = eu_rom_data[23:20];
    assign eu_opcode_op1_sel   = eu_rom_data[19:16];
    assign eu_opcode_immediate = eu_rom_data[15:0];

    // Jump-specific instruction decoding
    assign eu_opcode_jump_call = eu_rom_data[24];
    assign eu_opcode_jump_src  = eu_rom_data[22:20];
    assign eu_opcode_jump_cond = eu_rom_data[19:16];

    //--------------------------------------------------------------------------
    // Operand 0 Multiplexer - EU Register File and Control Signals
    //--------------------------------------------------------------------------
    // The EU-side operand: architectural registers, microcode scratch, the BIU
    // command word being assembled, or the status bus. Select 0xF reads as zero,
    // which microcode relies on to synthesise "load immediate" (zero OR imm).
    assign  eu_operand0 = (eu_opcode_op0_sel == 4'h0) ? eu_register_ax :
                          (eu_opcode_op0_sel == 4'h1) ? eu_register_bx :
                          (eu_opcode_op0_sel == 4'h2) ? eu_register_cx :
                          (eu_opcode_op0_sel == 4'h3) ? eu_register_dx :
                          (eu_opcode_op0_sel == 4'h4) ? eu_register_sp :
                          (eu_opcode_op0_sel == 4'h5) ? eu_register_bp :
                          (eu_opcode_op0_sel == 4'h6) ? eu_register_si :
                          (eu_opcode_op0_sel == 4'h7) ? eu_register_di :
                          (eu_opcode_op0_sel == 4'h8) ? eu_flags       :
                          (eu_opcode_op0_sel == 4'h9) ? eu_register_r0 :
                          (eu_opcode_op0_sel == 4'hA) ? eu_register_r1 :
                          (eu_opcode_op0_sel == 4'hB) ? eu_register_r2 :
                          (eu_opcode_op0_sel == 4'hC) ? eu_register_r3 :
                          (eu_opcode_op0_sel == 4'hD) ? eu_biu_command :
                          (eu_opcode_op0_sel == 4'hE) ? system_signals :
                                                        16'h0          ;

    //--------------------------------------------------------------------------
    // Operand 1 Multiplexer - BIU Interface and System Signals
    //--------------------------------------------------------------------------
    // The BIU-side operand: segment registers, the decoded mod/reg/rm operands,
    // returned bus data, the prefetch queue, or the microword's own immediate.
    // Select 0x4 is how the microcode consumes an instruction byte - it pulls
    // the top of the prefetch queue in zero-extended.
    assign  eu_operand1 = (eu_opcode_op1_sel == 4'h0) ? BIU_REGISTER_ES       :
                          (eu_opcode_op1_sel == 4'h1) ? BIU_REGISTER_SS       :
                          (eu_opcode_op1_sel == 4'h2) ? BIU_REGISTER_CS       :
                          (eu_opcode_op1_sel == 4'h3) ? BIU_REGISTER_DS       :
                          (eu_opcode_op1_sel == 4'h4) ? {8'h00, PFQ_TOP_BYTE} :
                          (eu_opcode_op1_sel == 4'h5) ? BIU_REGISTER_RM       :
                          (eu_opcode_op1_sel == 4'h6) ? BIU_REGISTER_REG      :
                          (eu_opcode_op1_sel == 4'h7) ? BIU_RETURN_DATA       :
                          (eu_opcode_op1_sel == 4'h8) ? PFQ_ADDR_OUT          :
                          (eu_opcode_op1_sel == 4'h9) ? eu_register_r0        :
                          (eu_opcode_op1_sel == 4'hA) ? eu_register_r1        :
                          (eu_opcode_op1_sel == 4'hB) ? eu_register_r2        :
                          (eu_opcode_op1_sel == 4'hC) ? eu_register_r3        :
                          (eu_opcode_op1_sel == 4'hD) ? eu_alu_last_result    :
                          (eu_opcode_op1_sel == 4'hE) ? system_signals        :
                                                        eu_opcode_immediate   ;

    //--------------------------------------------------------------------------
    // Jump Condition Evaluation Logic
    //--------------------------------------------------------------------------
    // The microcode's own condition set is deliberately tiny: always, "last ALU
    // result nonzero", "last ALU result zero". Everything else an 8086 can branch
    // on is reduced to one of those by microcode before it jumps.
    //
    // The two leading terms are the exception. IDIV has to detect a signed
    // quotient that will not fit in the destination, and that range check cannot
    // be phrased as a z/nz test on a single ALU result. So the check is wired
    // here instead, qualified by idiv_opcode so the unsigned DIV arm never sees
    // it, and by the microcode PC so it only applies at the one word that asks:
    //
    //   byte IDIV (uPC 0x0E76): quotient overflows if AX[15:7] is not all zero
    //   word IDIV (uPC 0x0F02): quotient overflows if DX is nonzero or AX[15] set
    //
    // Taking the jump vectors into the divide-overflow (INT 0) microcode.
    assign eu_jump_boolean = ((idiv_opcode == 'h1) && (eu_rom_address == 'h0E76) && ( eu_register_ax[15:7] != 'h0))                                 ? 1'b1 :
                             ((idiv_opcode == 'h1) && (eu_rom_address == 'h0F02) && ((eu_register_dx       != 'h0) || (eu_register_ax[15] != 'h0))) ? 1'b1 :
                             (eu_opcode_jump_cond  == 4'h0)                                                                                         ? 1'b1 : // unconditional jump
                             (eu_opcode_jump_cond  == 4'h1 && eu_alu_last_result != 16'h0)                                                          ? 1'b1 :
                             (eu_opcode_jump_cond  == 4'h2 && eu_alu_last_result == 16'h0)                                                          ? 1'b1 : 1'b0 ;

    //--------------------------------------------------------------------------
    // System Signals Consolidation
    //--------------------------------------------------------------------------
    // Combines various status and control signals into a single 16-bit bus.
    // Microcode selects this bus as an operand (op0/op1 select 0xE) and then
    // masks the bit it wants - that is how a microcoded conditional branch tests
    // a carry, a pending interrupt, or an empty prefetch queue.
    //
    // Bits 15, 14 and 10 are intentionally absent: nothing drives them, so
    // microcode must never mask them in.
    assign system_signals[13] = eu_add_carry8;         // Byte carry out
    assign system_signals[12] = BIU_CLK_COUNTER_ZERO;  // Bus cycle timing budget exhausted
    assign system_signals[11] = eu_add_overflow16;     // Word signed overflow
    assign system_signals[9]  = eu_add_overflow8;      // Byte signed overflow
    assign system_signals[8]  = eu_tr_latched;         // Single-step trap armed
    assign system_signals[7]  = ~PFQ_EMPTY;            // An instruction byte is available
    assign system_signals[6]  = biu_done_caught;       // The bus operation has completed
    assign system_signals[5]  = TEST_N_INT;            // TEST pin, for WAIT
    assign system_signals[4]  = eu_add_aux_carry;      // BCD auxiliary carry
    assign system_signals[3]  = BIU_NMI_CAUGHT;        // NMI edge seen by the BIU
    assign system_signals[2]  = eu_parity;             // Parity of the last ALU result
    assign system_signals[1]  = intr_asserted;         // Maskable interrupt, already IF-qualified
    assign system_signals[0]  = eu_add_carry;          // Word carry out

    //--------------------------------------------------------------------------
    // Flags Register Bit Assignments
    //--------------------------------------------------------------------------
    // Maps the 16-bit flags register to individual flag signals and prefix bits.
    // The scratch bits (1, 3, 5, 12, 13, 14, 15) are exactly the bits the 8086
    // leaves reserved - see the bit map in the file header.
    assign eu_prefix_repnz    = eu_flags[15];
    assign eu_prefix_rep      = eu_flags[14];
    assign eu_prefix_lock     = eu_flags[13];
    assign BIU_NMI_DEBOUNCE   = eu_flags[12];
    assign eu_flag_o          = eu_flags[11];
    assign eu_flag_d          = eu_flags[10];
    assign eu_flag_i          = eu_flags[9];
    assign eu_flag_t          = eu_flags[8];
    assign eu_flag_s          = eu_flags[7];
    assign eu_flag_z          = eu_flags[6];
    assign eu_tf_debounce     = eu_flags[5];
    assign eu_flag_a          = eu_flags[4];
    assign eu_nmi_pending     = eu_flags[3];
    assign eu_flag_p          = eu_flags[2];
    assign eu_flag_temp       = eu_flags[1];
    assign eu_flag_c          = eu_flags[0];

    //--------------------------------------------------------------------------
    // ALU Operations Implementation
    //--------------------------------------------------------------------------
    // eu_alu0 = NOP (no operation)
    // eu_alu1 = JUMP (control transfer, handled separately)
    assign eu_alu2 = adder_out;                              // ADD
    assign eu_alu3 = {eu_operand0[7:0], eu_operand0[15:8]};  // BYTESWAP
    assign eu_alu4 = eu_operand0 & eu_operand1;              // AND
    assign eu_alu5 = eu_operand0 | eu_operand1;              // OR
    assign eu_alu6 = eu_operand0 ^ eu_operand1;              // XOR
    assign eu_alu7 = {1'b0, eu_operand0[15:1]};              // SHR

    //--------------------------------------------------------------------------
    // ALU Output Multiplexer
    //--------------------------------------------------------------------------
    // Selects the appropriate ALU operation result based on microcode type field.
    // Types 0 and 1 (NOP and JUMP) produce no result and never write back, so the
    // 0xEEEE default is unreachable as a stored value.
    assign eu_alu_out = (eu_opcode_type == 3'h2) ? eu_alu2
                      : (eu_opcode_type == 3'h3) ? eu_alu3
                      : (eu_opcode_type == 3'h4) ? eu_alu4
                      : (eu_opcode_type == 3'h5) ? eu_alu5
                      : (eu_opcode_type == 3'h6) ? eu_alu6
                      : (eu_opcode_type == 3'h7) ? eu_alu7
                      :                            16'hEEEE;

    //--------------------------------------------------------------------------
    // 16-bit Adder
    //--------------------------------------------------------------------------
    // Full 16-bit addition, plus every intermediate carry the flag logic needs:
    // carry[4] is the BCD auxiliary carry, carry[8] the byte carry, carry[16] the
    // word carry, and the XOR of the top two carries is the signed overflow.
    //
    // This was a per-bit ripple written out longhand here. It was correct, but
    // sixteen chained carry expressions are not something Quartus can put on the
    // ALM's dedicated carry hardware, so it built the chain from general logic
    // and that chain became the critical path of the whole core - the reason
    // clk_100 closed at 88 MHz against its 100 MHz constraint.
    // mcl86_adder computes the same function bit for bit, with the intermediate
    // carries recovered from the sum instead of produced ahead of it.
    mcl86_adder u_adder (
        .a      (eu_operand0),
        .b      (eu_operand1),
        .sum    (adder_out),
        .carry  (carry)
    );

    //--------------------------------------------------------------------------
    // Parity Calculation for 8-bit Results
    //--------------------------------------------------------------------------
    // Calculates even parity for the lower 8 bits of ALU result. The 8086 defines
    // PF over the low byte only, whatever the operand width, so this deliberately
    // ignores bits 15:8.
    assign eu_parity       = ~(eu_alu_last_result[0] ^
                               eu_alu_last_result[1] ^
                               eu_alu_last_result[2] ^
                               eu_alu_last_result[3] ^
                               eu_alu_last_result[4] ^
                               eu_alu_last_result[5] ^
                               eu_alu_last_result[6] ^
                               eu_alu_last_result[7]);

    //--------------------------------------------------------------------------
    // Control Signal Derivations
    //--------------------------------------------------------------------------
    // new_instruction: microcode page 0x01 is the primary opcode dispatch table
    // (a jump with src=1 vectors to 0x0100 | opcode), so the PC sitting in that
    // page means a fresh macro-instruction is being dispatched right now. The
    // deferred STI below keys off this.
    assign eu_biu_req      = eu_biu_command[9];
    // A real 8088 recognises INTR at instruction boundaries. Sampling the live
    // pin throughout an instruction makes the result depend on the current
    // microcode position and therefore on timing. HLT is a boundary too: its
    // microsequencer does not return to the dispatch page while it waits.
    assign intr_asserted   = BIU_INTR & intr_delay & intr_enable_delayed;
    assign new_instruction = (eu_rom_address[12:8] == 5'h01) |
                             (eu_biu_command[8:4]  == 5'h18);   // HLT wait

    // Overflow-fixup probes. These are permanently computed from the scratch pair
    // and only sampled at the flag-setter microwords; they are not an ALU path.
    assign add_total       = eu_register_r0 + eu_register_r1;
    assign adc_total       = eu_register_r0 + eu_register_r1 + eu_flag_c;
    assign sub_total       = eu_register_r0 - eu_register_r1;
    assign sbb_total       = eu_register_r0 - eu_register_r1 - eu_flag_c;

    //--------------------------------------------------------------------------
    // EU Microsequencer
    //--------------------------------------------------------------------------
    // Controls microcode execution, register updates, flag generation, and
    // pipeline flow. One microword retires per clock unless a taken jump stalls
    // the pipe.
    //
    // Several blocks below identify a macro-instruction by comparing the
    // microcode PC against a hardcoded address. That is only sound because of the
    // 2-word lead described in the file header: a marker must sit deep enough
    // into its own microcode arm that a neighbouring arm's overshoot cannot graze
    // it. tools/uccheck.py scrapes these constants out of this file and reports
    // every marker that more than one path can reach.
    always_ff @(posedge CORE_CLK_INT) begin : proc_eu_microsequencer
        if (RESET_INT == 1'b1) begin
            biu_done_d1         <=   '0;
            biu_done_d2         <=   '0;
            eu_biu_req_d1       <=   '0;
            biu_done_caught     <=   '0;
            eu_flag_t_d         <=   '0;
            eu_tr_latched       <=   '0;
            eu_add_carry        <=   '0;
            eu_add_carry8       <=   '0;
            eu_add_aux_carry    <=   '0;
            eu_add_overflow16   <=   '0;
            eu_add_overflow8    <=   '0;
            eu_alu_last_result  <=   '0;
            div_flag_src        <=   '0;
            eu_register_ax      <=   '0;
            eu_register_bx      <=   '0;
            eu_register_cx      <=   '0;
            eu_register_dx      <=   '0;
            eu_register_sp      <=   '0;
            eu_register_bp      <=   '0;
            eu_register_si      <=   '0;
            eu_register_di      <=   '0;
            eu_flags            <=   '0;
            eu_register_r0      <=   '0;
            eu_register_r1      <=   '0;
            eu_register_r2      <=   '0;
            eu_register_r3      <=   '0;
            eu_biu_command      <=   '0;
            eu_biu_dataout      <=   '0;
            eu_stall_pipeline   <=   '0;
            eu_rom_address      <= 13'h0020;  // Reset entry point in the microcode ROM
            eu_calling_address  <=   '0;
            intr_enable_delayed <=   '0;
            intr_delay          <=   '0;
            idiv_opcode         <=   '0;
        end
        else begin
            // Delay the INTR enable flag until after the next instruction begins.
            // No delay when it is disabled.
            //
            // The 8086 STI rule: interrupts stay masked for the instruction after
            // STI, so "STI / RET" cannot be interrupted between the two. Enabling
            // takes effect only at an instruction boundary; CLI takes effect at once.
            if (eu_flag_i == 1'b0) begin
                intr_enable_delayed <= 1'b0;
            end
            else begin
                if (new_instruction == 1'b1) begin
                    intr_enable_delayed <= eu_flag_i;
                end
            end

            if (new_instruction == 1'b1) begin
                intr_delay <= BIU_INTR;
            end

            // Latch the TF flag on its rising edge.
            //
            // The trap must be decided from TF as it was when the instruction
            // started, so it is edge-latched here and cleared by microcode through
            // the tf_debounce scratch bit once taken. That keeps an instruction
            // that sets TF from immediately trapping on itself.
            eu_flag_t_d <= eu_flag_t;
            if (eu_flag_t_d == 1'b0 && eu_flag_t == 1'b1) begin
                eu_tr_latched <= 1'b1;
            end
            else if (eu_tf_debounce == 1'b1) begin
                eu_tr_latched <= 1'b0;
            end

            // Latch the done bit from the biu.
            // Debounce it when the request is released.
            //
            // Req/ack: the rising edge of BIU_DONE makes biu_done_caught sticky so
            // microcode polling system_signals[6] cannot miss a completion; it
            // clears only once microcode drops the request.
            biu_done_d1   <= BIU_DONE;
            biu_done_d2   <= biu_done_d1;
            eu_biu_req_d1 <= eu_biu_req;

            if      (biu_done_d2   == 1'b0 && biu_done_d1 == 1'b1) begin
                biu_done_caught <= 1'b1;
            end
            else if (eu_biu_req_d1 == 1'b1 && eu_biu_req  == 1'b0) begin
                biu_done_caught <= 1'b0;
            end

            //------------------------------------------------------------------
            // Signed overflow fixups
            //------------------------------------------------------------------
            // Eight flag-setter entry points, one per {ADD,ADC,SUB,SBB} x {byte,
            // word}. Each arms the override and computes OF the textbook way from
            // the sign bits of the two operands and the result: for addition,
            // overflow means both operands shared a sign and the result flipped;
            // for subtraction, that the operands differed in sign and the result
            // took the subtrahend's. The value is consumed further down, where the
            // add flags are stored.

            // ADD - Byte
            if (eu_rom_address == 16'h09C9) begin
                eu_overflow_override <= 1'b1;

                if (((eu_register_r0[7] == 1'b0) && (eu_register_r1[7] == 1'b0) && (add_total[7] == 1'b1)) ||
                    ((eu_register_r0[7] == 1'b1) && (eu_register_r1[7] == 1'b1) && (add_total[7] == 1'b0))) begin
                    eu_add_overflow8_fixed <= 1'b1;
                end
                else begin
                    eu_add_overflow8_fixed <= 1'b0;
                end
            end

            // ADC - Byte
            if (eu_rom_address == 16'h0A03) begin
                eu_overflow_override <= 1'b1;

                if (((eu_register_r0[7] == 1'b0) && (eu_register_r1[7] == 1'b0) && (adc_total[7] == 1'b1)) ||
                    ((eu_register_r0[7] == 1'b1) && (eu_register_r1[7] == 1'b1) && (adc_total[7] == 1'b0))) begin
                    eu_add_overflow8_fixed <= 1'b1;
                end
                else begin
                    eu_add_overflow8_fixed <= 1'b0;
                end
            end

            // SUB - Byte
            if (eu_rom_address == 16'h0A46) begin
                eu_overflow_override <= 1'b1;

                if (((eu_register_r0[7] == 1'b0) && (eu_register_r1[7] == 1'b1) && (sub_total[7] == 1'b1)) ||
                    ((eu_register_r0[7] == 1'b1) && (eu_register_r1[7] == 1'b0) && (sub_total[7] == 1'b0))) begin
                    eu_add_overflow8_fixed <= 1'b1;
                end
                else begin
                    eu_add_overflow8_fixed <= 1'b0;
                end
            end

            // SBB - Byte
            if (eu_rom_address == 16'h0AAE) begin
                eu_overflow_override <= 1'b1;

                if (((eu_register_r0[7] == 1'b0) && (eu_register_r1[7] == 1'b1) && (sbb_total[7] == 1'b1)) ||
                    ((eu_register_r0[7] == 1'b1) && (eu_register_r1[7] == 1'b0) && (sbb_total[7] == 1'b0))) begin
                    eu_add_overflow8_fixed <= 1'b1;
                end
                else begin
                    eu_add_overflow8_fixed <= 1'b0;
                end
            end

            // ADD - Word
            if (eu_rom_address == 16'h09CC) begin
                eu_overflow_override <= 1'b1;

                if (((eu_register_r0[15] == 1'b0) && (eu_register_r1[15] == 1'b0) && (add_total[15] == 1'b1)) ||
                    ((eu_register_r0[15] == 1'b1) && (eu_register_r1[15] == 1'b1) && (add_total[15] == 1'b0))) begin
                    eu_add_overflow16_fixed <= 1'b1;
                end
                else begin
                    eu_add_overflow16_fixed <= 1'b0;
                end
            end

            // ADC - Word
            if (eu_rom_address == 16'h0A12) begin
                eu_overflow_override <= 1'b1;

                if (((eu_register_r0[15] == 1'b0) && (eu_register_r1[15] == 1'b0) && (adc_total[15] == 1'b1)) ||
                    ((eu_register_r0[15] == 1'b1) && (eu_register_r1[15] == 1'b1) && (adc_total[15] == 1'b0))) begin
                    eu_add_overflow16_fixed <= 1'b1;
                end
                else begin
                    eu_add_overflow16_fixed <= 1'b0;
                end
            end

            // SUB - Word
            if (eu_rom_address == 16'h0A52) begin
                eu_overflow_override <= 1'b1;

                if (((eu_register_r0[15] == 1'b0) && (eu_register_r1[15] == 1'b1) && (sub_total[15] == 1'b1)) ||
                    ((eu_register_r0[15] == 1'b1) && (eu_register_r1[15] == 1'b0) && (sub_total[15] == 1'b0))) begin
                    eu_add_overflow16_fixed <= 1'b1;
                end
                else begin
                    eu_add_overflow16_fixed <= 1'b0;
                end
            end

            // SBB - Word
            if (eu_rom_address == 16'h0ABA) begin
                eu_overflow_override <= 1'b1;

                if (((eu_register_r0[15] == 1'b0) && (eu_register_r1[15] == 1'b1) && (sbb_total[15] == 1'b1)) ||
                    ((eu_register_r0[15] == 1'b1) && (eu_register_r1[15] == 1'b0) && (sbb_total[15] == 1'b0))) begin
                    eu_add_overflow16_fixed <= 1'b1;
                end
                else begin
                    eu_add_overflow16_fixed <= 1'b0;
                end
            end

            // Debounce the overflow flag override when microcode returns to the main loop
            // Store initial values of AX and DX
            //
            // 0x0011 is the top of the fetch/dispatch loop, so it is the natural
            // "between instructions" point: disarm the overflow override, and take
            // the AX/DX snapshot that a faulting divide will restore from.
            if (eu_rom_address == 'h0011) begin
                eu_overflow_override <= 1'b0;
                initial_ax           <= eu_register_ax;
                initial_dx           <= eu_register_dx;
                idiv_opcode          <= 'h0;
            end

            // Flag IDIV by watching the microcode PC enter its arm of the F6 /
            // F7 group. The sequencer runs two words ahead of the microword it
            // is executing, so an arm's first two addresses are also grazed by
            // whatever arm sits immediately above it:
            //
            //   F6  DIV  0x0E1E -> 0x0E52 ; eu_rom_address visits 52 53 54 55
            //   F6  IDIV 0x0E1F -> 0x0E54 ; eu_rom_address visits 54 55 56 ...
            //
            // so 0x0E56 is the first address only IDIV reaches. 0x0ED0 is safe
            // as-is because the F7 DIV arm lives at 0x0EE4, well clear of it.
            if ((eu_rom_address == 'h0E56) || (eu_rom_address == 'h0ED0)) begin
                idiv_opcode <= 'h1;
            end

            // Generate and store flags for addition
            //
            // Only ADD-type microwords (type 2) update the arithmetic flags, and
            // only when the pipe is not being squashed. This is where the fixup
            // computed at the flag-setter entry points is substituted for the
            // adder's carry-XOR overflow.
            if (eu_stall_pipeline == 1'b0 && eu_opcode_type == 3'h2) begin
                eu_add_carry      <= carry[16];
                eu_add_carry8     <= carry[8];
                eu_add_aux_carry  <= carry[4];
                eu_add_overflow16 <= (eu_overflow_override == 1'b1) ? eu_add_overflow16_fixed : (carry[16] ^ carry[15]);
                eu_add_overflow8  <= (eu_overflow_override == 1'b1) ? eu_add_overflow8_fixed  : (carry[8]  ^ carry[7] );
            end

            // Register writeback
            //
            // Every microword type except NOP (0) and JUMP (1) writes its ALU
            // result somewhere. eu_alu_last_result always shadows the write - it
            // is what the z/nz jump conditions test, which is how a microcoded
            // compare-and-branch works without a separate condition-code register.
            if (eu_stall_pipeline == 1'b0 && eu_opcode_type != 3'h0 && eu_opcode_type != 3'h1) begin
                eu_alu_last_result <= eu_alu_out[15:0];
                case (eu_opcode_dst_sel)  // synthesis parallel_case
                    4'h0: eu_register_ax <= eu_alu_out[15:0];
                    4'h1: eu_register_bx <= eu_alu_out[15:0];
                    4'h2: eu_register_cx <= eu_alu_out[15:0];
                    4'h3: eu_register_dx <= eu_alu_out[15:0];
                    4'h4: eu_register_sp <= eu_alu_out[15:0];
                    4'h5: eu_register_bp <= eu_alu_out[15:0];
                    4'h6: eu_register_si <= eu_alu_out[15:0];
                    4'h7: eu_register_di <= eu_alu_out[15:0];
                    4'h8: eu_flags       <= eu_alu_out[15:0];
                    4'h9: eu_register_r0 <= eu_alu_out[15:0];
                    4'hA: eu_register_r1 <= eu_alu_out[15:0];
                    4'hB: eu_register_r2 <= eu_alu_out[15:0];
                    4'hC: eu_register_r3 <= eu_alu_out[15:0];
                    4'hD: eu_biu_command <= eu_alu_out[15:0];
                    //4'hE: Reserved
                    4'hF: eu_biu_dataout <= eu_alu_out[15:0];
                    default:;
                endcase
            end

            // Restore initial values of AX and DX upon entering overflow DIV0 microcode
            //
            // A divide that overflows must raise INT 0 with AX and DX exactly as
            // they were before the divide started - the CORD loop has been
            // trampling them, so they are put back from the 0x0011 snapshot. This
            // write deliberately lands after the writeback case above so it wins.
            if (eu_rom_address == 'h0F11) begin
                eu_register_ax <= initial_ax;
                eu_register_dx <= initial_dx;
            end

            // Divide live-FLAGS source: capture the last in-range divide-loop
            // subtract input. The real 8088's CORD loop writes FLAGS from each
            // in-range SUBT (its CY-shortcut iterations skip the F write), so
            // the architectural flags a divide leaves are SZAPCO of the LAST
            // such subtract. MCL86's loop has the same partial remainders; the
            // shifted value is in r2 around the subtract word (byte loop 0E6C,
            // word loop 0EF0), and "in range" is r2 < 0x100 for the byte loop /
            // the r3 shift-out bit clear for the word loop. The byte watch sits
            // at 0E6E, not 0E6C: the loop's shift call at 0E6B grazes 0E6C/0E6D
            // (the sequencer runs two ahead) with the PRE-shift r2, which would
            // overwrite a good capture on CY-shortcut iterations; 0E6E is past
            // the graze and r2's subtract writeback has not landed yet there.
            if (eu_rom_address == 'h0E6C && eu_stall_pipeline == 1'b1 && eu_register_r2[15:8] == 8'h00) begin
                div_flag_src <= eu_register_r2;
            end
            if (eu_rom_address == 'h0EF0 && eu_register_r3[0] == 1'b0) begin
                div_flag_src <= eu_register_r2;
            end

            // The divide flag tails (BFDIV 0x0F85 / WFDIV 0x0F8D) read the
            // captured value back through r0 for the SUB flag setter.
            if (eu_rom_address == 'h0F85 || eu_rom_address == 'h0F8D) begin
                eu_register_r0 <= div_flag_src;
            end

            //------------------------------------------------------------------
            // JUMP Opcode
            //------------------------------------------------------------------
            // Microcode control transfer. The stall squashes the two words the
            // sequencer already pulled in behind this one.
            //
            // Rather than decode an opcode into a handler address with logic, the
            // opcode byte IS part of the address. Jump sources:
            //
            //   0 - direct: target is the immediate field
            //   1 - opcode dispatch: 0x100 | PFQ top byte, one entry per opcode
            //   2 - mod/reg/rm dispatch: imm | MOD | RM, the addressing-mode table
            //   3 - return: pop the call stack
            //   4 - EA register fetch table, keyed on the BIU's decoded operand
            //   5 - EA register writeback table, same key
            //   6 - REG-field table, for the groups that share one opcode
            //
            // The call stack is a 52-bit shift register, not an addressed array:
            // a call shifts a 13-bit return address in, a return shifts it back
            // out. Four deep; a fifth call pushes the oldest entry off the top.
            if (eu_stall_pipeline == 1'b0 && eu_opcode_type == 3'h1 && eu_jump_boolean == 1'b1) begin
                eu_stall_pipeline <= 1'b1;

                // For subroutine CALLs, store next opcode address
                if (eu_opcode_jump_call == 1'b1) begin
                    eu_calling_address[51:0] <= {eu_calling_address[38:0], eu_rom_address[12:0]};  // 4 deep calling addresses
                end

                case (eu_opcode_jump_src)  // synthesis parallel_case
                    3'h0: eu_rom_address <= eu_opcode_immediate[12:0];
                    3'h1: eu_rom_address <= {4'b0, 1'b1, PFQ_TOP_BYTE};                                             // If only used for primary opcode jump, maybe make fixed prepend rather than immediate value prepend?
                    3'h2: eu_rom_address <= {eu_opcode_immediate[4:0], PFQ_TOP_BYTE[7:6], PFQ_TOP_BYTE[2:0], 3'b0}; // Rearranged mod_reg_rm byte - imm,MOD,RM,000
                    3'h3: begin
                        eu_rom_address           <= eu_calling_address[12:0];
                        eu_calling_address[38:0] <= eu_calling_address[51:13];
                    end
                    3'h4: eu_rom_address <= {eu_opcode_immediate[7:0],  eu_biu_dataout[3:0], 1'b0};  // Jump table for EA register fetch decoding.  Jump Addresses decoded from biu_dataout.
                    3'h5: eu_rom_address <= {eu_opcode_immediate[6:0],  eu_biu_dataout[3:0], 2'b0};  // Jump table for EA register writeback decoding.  Jump Addresses decoded from biu_dataout.
                    3'h6: eu_rom_address <= {eu_opcode_immediate[12:3], eu_biu_dataout[5:3]};        // Jump table for instructions that share same opcode and decode using the REG field.
                    default:;
                endcase
            end
            else begin
                eu_stall_pipeline <= 1'b0; // Debounce the pipeline stall
                eu_rom_address    <= eu_rom_address + 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Output Signal Assignments
    //--------------------------------------------------------------------------
    // BIU_NMI_DEBOUNCE is not here: it is a bit of eu_flags, and is driven up in
    // the flags decode with its siblings.
    assign EU_BIU_COMMAND = eu_biu_command;
    assign EU_BIU_DATAOUT = eu_biu_dataout;
    assign EU_REGISTER_R3 = eu_register_r3;
    assign EU_FLAG_I      = intr_enable_delayed;
    assign EU_PREFIX_LOCK = eu_prefix_lock;

endmodule

`default_nettype wire
