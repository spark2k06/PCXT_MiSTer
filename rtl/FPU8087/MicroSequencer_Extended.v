// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Extended MicroSequencer for 8087 FPU
//
// This module extends the basic microsequencer with hardware unit
// interface support. It provides "call and wait" subroutines that
// delegate to existing FPU_Core hardware units:
// - FPU_ArithmeticUnit (add, sub, mul, div, sqrt, trig, conversions)
// - Stack Manager (push, pop, exchange)
// - Format Converters (int, FP, BCD)
//
// Key Design: Microcode sequences operations, hardware units compute
//=====================================================================

module MicroSequencer_Extended (
    input wire clk,
    input wire reset,

    // Control interface
    input wire        start,                // Start microprogram execution
    input wire [3:0]  micro_program_index,  // Which microprogram to run
    output reg        instruction_complete, // Execution complete

    // Data bus interface (for memory operations)
    input wire [79:0] data_in,
    output reg [79:0] data_out,

    // Debug/test interface - expose internal registers
    output wire [79:0] debug_temp_result,
    output wire [79:0] debug_temp_fp_a,
    output wire [79:0] debug_temp_fp_b,

    // ===== Interfaces to FPU_Core Hardware Units (REUSE EXISTING) =====

    // Interface to FPU_ArithmeticUnit
    output reg [4:0]  arith_operation,      // Operation code
    output reg        arith_enable,         // Start operation
    output reg [1:0]  arith_rounding_mode,  // Rounding mode
    output reg [79:0] arith_operand_a,      // Operand A (80-bit FP)
    output reg [79:0] arith_operand_b,      // Operand B (80-bit FP)
    output reg signed [15:0] arith_int16_in,
    output reg signed [31:0] arith_int32_in,
    output reg [31:0] arith_fp32_in,
    output reg [63:0] arith_fp64_in,
    input wire [79:0] arith_result,         // Result (80-bit FP)
    input wire signed [15:0] arith_int16_out,
    input wire signed [31:0] arith_int32_out,
    input wire [31:0] arith_fp32_out,
    input wire [63:0] arith_fp64_out,
    input wire        arith_done,           // Operation complete
    input wire        arith_cc_less,
    input wire        arith_cc_equal,
    input wire        arith_cc_greater,
    input wire        arith_cc_unordered,

    // Interface to Stack Manager
    output reg        stack_push_req,       // Push request
    output reg        stack_pop_req,        // Pop request
    output reg [2:0]  stack_read_sel,       // Which register to read
    output reg [2:0]  stack_write_sel,      // Which register to write
    output reg        stack_write_en,       // Write enable
    output reg [79:0] stack_write_data,     // Data to write
    input wire [79:0] stack_read_data,      // Data read from stack
    input wire        stack_op_done,        // Stack operation complete

    // Status/Control interface
    input wire [15:0] status_word_in,
    output reg [15:0] status_word_out,
    output reg        status_word_write,
    input wire [15:0] control_word_in,
    output reg [15:0] control_word_out,
    output reg        control_word_write
);

    //=================================================================
    // Opcode Definitions
    //=================================================================

    // Overall opcodes
    localparam OPCODE_NOP    = 4'h0;
    localparam OPCODE_EXEC   = 4'h1;
    localparam OPCODE_JUMP   = 4'h2;
    localparam OPCODE_CALL   = 4'h3;
    localparam OPCODE_RET    = 4'h4;
    localparam OPCODE_HALT   = 4'hF;

    // Basic micro-operations (0x00-0x0F) - 5-bit encoding
    localparam MOP_LOAD           = 5'h01;  // Load from data bus
    localparam MOP_STORE          = 5'h02;  // Store to data bus
    localparam MOP_MOVE_TEMP      = 5'h03;  // Move between temp registers
    localparam MOP_LOAD_IMM       = 5'h04;  // Load immediate value
    localparam MOP_LOAD_A         = 5'h05;  // Load data_in into temp_fp_a
    localparam MOP_LOAD_B         = 5'h06;  // Load data_in into temp_fp_b
    localparam MOP_MOVE_RES_TO_A  = 5'h07;  // Move temp_result to temp_fp_a
    localparam MOP_MOVE_RES_TO_B  = 5'h08;  // Move temp_result to temp_fp_b
    localparam MOP_MOVE_A_TO_C    = 5'h09;  // Move temp_fp_a to temp_fp_c
    localparam MOP_MOVE_A_TO_B    = 5'h0A;  // Move temp_fp_a to temp_fp_b
    localparam MOP_MOVE_C_TO_A    = 5'h0B;  // Move temp_fp_c to temp_fp_a
    localparam MOP_MOVE_C_TO_B    = 5'h0C;  // Move temp_fp_c to temp_fp_b
    localparam MOP_LOAD_HALF_B    = 5'h0D;  // Load 0.5 constant into temp_fp_b

    // Hardware unit call operations (0x10-0x1F) - NEW!
    localparam MOP_CALL_ARITH     = 5'h10; // Start arithmetic operation
    localparam MOP_WAIT_ARITH     = 5'h11; // Wait for arithmetic completion
    localparam MOP_LOAD_ARITH_RES = 5'h12; // Load result from arithmetic unit
    localparam MOP_CALL_STACK     = 5'h13; // Execute stack operation
    localparam MOP_WAIT_STACK     = 5'h14; // Wait for stack completion
    localparam MOP_LOAD_STACK_REG = 5'h15; // Load from stack register
    localparam MOP_STORE_STACK_REG= 5'h16; // Store to stack register
    localparam MOP_SET_STATUS     = 5'h17; // Set status flags
    localparam MOP_GET_STATUS     = 5'h18; // Get status flags
    localparam MOP_GET_CC         = 5'h19; // Get condition codes

    //=================================================================
    // FSM States
    //=================================================================

    localparam STATE_IDLE   = 3'd0;
    localparam STATE_FETCH  = 3'd1;
    localparam STATE_DECODE = 3'd2;
    localparam STATE_EXEC   = 3'd3;
    localparam STATE_WAIT   = 3'd4;  // NEW: Wait for hardware completion

    reg [2:0] state;

    //=================================================================
    // Program Counter and Instruction
    //=================================================================

    reg [15:0] pc;                          // Program counter
    reg [31:0] microinstruction;            // Current instruction

    // Instruction fields
    wire [3:0]  opcode     = microinstruction[31:28];
    wire [4:0]  micro_op   = microinstruction[27:23];  // Extended to 5 bits!
    wire [7:0]  immediate  = microinstruction[22:15];
    wire [14:0] next_addr  = microinstruction[14:0];   // 15-bit address

    //=================================================================
    // Call Stack
    //=================================================================

    reg [15:0] call_stack [0:15];
    reg [3:0]  call_sp;

    //=================================================================
    // Microprogram Table
    //=================================================================

    reg [15:0] micro_program_table [0:15];
    initial begin
        // Program 0: FADD subroutine
        micro_program_table[0]  = 16'h0100;
        // Program 1: FSUB subroutine
        micro_program_table[1]  = 16'h0110;
        // Program 2: FMUL subroutine
        micro_program_table[2]  = 16'h0120;
        // Program 3: FDIV subroutine
        micro_program_table[3]  = 16'h0130;
        // Program 4: FSQRT subroutine (0x0140-0x01B1 = 114 instructions)
        micro_program_table[4]  = 16'h0140;
        // Program 5: FSIN subroutine (moved to avoid SQRT overlap)
        micro_program_table[5]  = 16'h01C0;
        // Program 6: FCOS subroutine (moved to avoid SQRT overlap)
        micro_program_table[6]  = 16'h01D0;
        // Program 7: FLD (with format conversion)
        micro_program_table[7]  = 16'h0200;
        // Program 8: FST (with format conversion)
        micro_program_table[8]  = 16'h0210;
        // Remaining slots for complex operations
        micro_program_table[9]  = 16'h0300;  // Reserved for FPREM
        micro_program_table[10] = 16'h0400;  // Reserved for FXTRACT
        micro_program_table[11] = 16'h0500;  // Reserved for FSCALE
    end

    //=================================================================
    // Temporary Registers
    //=================================================================

    reg [79:0] temp_fp_a;       // Operand A (80-bit FP)
    reg [79:0] temp_fp_b;       // Operand B (80-bit FP)
    reg [79:0] temp_fp_c;       // Operand C / scratch register (80-bit FP)
    reg [79:0] temp_result;     // Result storage

    // Expose internal registers for debug/test
    assign debug_temp_result = temp_result;
    assign debug_temp_fp_a = temp_fp_a;
    assign debug_temp_fp_b = temp_fp_b;
    reg [63:0] temp_reg;        // General purpose temp
    reg [31:0] loop_reg;        // Loop counter
    reg [2:0]  temp_stack_idx;  // Stack index

    // FP Constants (IEEE 754 extended precision format)
    localparam [79:0] CONST_HALF = 80'h3FFE8000000000000000;  // 0.5

    //=================================================================
    // Wait State Control
    //=================================================================

    reg waiting_for_arith;      // Waiting for arithmetic unit
    reg waiting_for_stack;      // Waiting for stack operation

    //=================================================================
    // Microcode ROM (4096 x 32-bit)
    //=================================================================

    reg [31:0] microcode_rom [0:4095];
    integer i;  // Loop variable for ROM initialization

    //=================================================================
    // Microcode Programs - Subroutine Library
    //=================================================================

    initial begin
        //-------------------------------------------------------------
        // Program 0: FADD - Floating Point Addition
        // Address: 0x0100-0x0105
        // Loads operands from data_in, then performs addition
        // Returns: result in temp_result
        //-------------------------------------------------------------
        microcode_rom[16'h0100] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0101};          // Load temp_fp_a from data_in
        microcode_rom[16'h0101] = {OPCODE_EXEC, MOP_LOAD_B, 8'd0, 15'h0102};          // Load temp_fp_b from data_in
        microcode_rom[16'h0102] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd0, 15'h0103};      // Call ADD (op=0)
        microcode_rom[16'h0103] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0104};      // Wait, advance to 0x0104 when done
        microcode_rom[16'h0104] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0105};  // Load result
        microcode_rom[16'h0105] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 1: FSUB - Floating Point Subtraction
        // Address: 0x0110-0x0115
        // Loads operands from data_in, then performs subtraction
        //-------------------------------------------------------------
        microcode_rom[16'h0110] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0111};          // Load temp_fp_a from data_in
        microcode_rom[16'h0111] = {OPCODE_EXEC, MOP_LOAD_B, 8'd0, 15'h0112};          // Load temp_fp_b from data_in
        microcode_rom[16'h0112] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd1, 15'h0113};      // Call SUB (op=1)
        microcode_rom[16'h0113] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0114};      // Wait, advance to 0x0114 when done
        microcode_rom[16'h0114] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0115};  // Load result
        microcode_rom[16'h0115] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 2: FMUL - Floating Point Multiplication
        // Address: 0x0120-0x0125
        // Loads operands from data_in, then performs multiplication
        //-------------------------------------------------------------
        microcode_rom[16'h0120] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0121};          // Load temp_fp_a from data_in
        microcode_rom[16'h0121] = {OPCODE_EXEC, MOP_LOAD_B, 8'd0, 15'h0122};          // Load temp_fp_b from data_in
        microcode_rom[16'h0122] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h0123};      // Call MUL (op=2)
        microcode_rom[16'h0123] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0124};      // Wait, advance to 0x0124 when done
        microcode_rom[16'h0124] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0125};  // Load result
        microcode_rom[16'h0125] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 3: FDIV - Floating Point Division
        // Address: 0x0130-0x0135
        // Loads operands from data_in, then performs division
        //-------------------------------------------------------------
        microcode_rom[16'h0130] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0131};          // Load temp_fp_a from data_in
        microcode_rom[16'h0131] = {OPCODE_EXEC, MOP_LOAD_B, 8'd0, 15'h0132};          // Load temp_fp_b from data_in
        microcode_rom[16'h0132] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h0133};      // Call DIV (op=3)
        microcode_rom[16'h0133] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0134};      // Wait, advance to 0x0134 when done
        microcode_rom[16'h0134] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0135};  // Load result
        microcode_rom[16'h0135] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 4: FSQRT - Newton-Raphson Square Root in Microcode
        // Address: 0x0140-0x01AB (108 instructions for 8 iterations)
        // Algorithm: x_{n+1} = 0.5 × (x_n + S/x_n)
        // Hardware-free implementation - uses only ADD/MUL/DIV
        //-------------------------------------------------------------
        // Setup: Load S and save to temp_fp_c, use S as initial approximation
        microcode_rom[16'h0140] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0141};          // Load S into temp_fp_a
        microcode_rom[16'h0141] = {OPCODE_EXEC, MOP_MOVE_A_TO_C, 8'd0, 15'h0142};     // Save S to temp_fp_c

        // Iteration 1: x1 = 0.5 × (x0 + S/x0)
        microcode_rom[16'h0142] = {OPCODE_EXEC, MOP_MOVE_A_TO_B, 8'd0, 15'h0143};     // Save x0 to temp_fp_b
        microcode_rom[16'h0143] = {OPCODE_EXEC, MOP_MOVE_C_TO_A, 8'd0, 15'h0144};     // Load S into temp_fp_a
        microcode_rom[16'h0144] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h0145};      // S / x0 (DIV)
        microcode_rom[16'h0145] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0146};      // Wait
        microcode_rom[16'h0146] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0147};  // Load quotient
        microcode_rom[16'h0147] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0148};   // quotient → temp_fp_a
        microcode_rom[16'h0148] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd0, 15'h0149};      // quotient + x0 (ADD, x0 still in B)
        microcode_rom[16'h0149] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h014A};      // Wait
        microcode_rom[16'h014A] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h014B};  // Load sum
        microcode_rom[16'h014B] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h014C};   // sum → temp_fp_a
        microcode_rom[16'h014C] = {OPCODE_EXEC, MOP_LOAD_HALF_B, 8'd0, 15'h014D};     // 0.5 → temp_fp_b
        microcode_rom[16'h014D] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h014E};      // 0.5 × sum (MUL)
        microcode_rom[16'h014E] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h014F};      // Wait
        microcode_rom[16'h014F] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0150};  // Load x1
        microcode_rom[16'h0150] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0151};   // x1 → temp_fp_a

        // Iteration 2: x2 = 0.5 × (x1 + S/x1)
        microcode_rom[16'h0151] = {OPCODE_EXEC, MOP_MOVE_A_TO_B, 8'd0, 15'h0152};  // Save x1 to temp_fp_b
        microcode_rom[16'h0152] = {OPCODE_EXEC, MOP_MOVE_C_TO_A, 8'd0, 15'h0153};  // Load S into temp_fp_a
        microcode_rom[16'h0153] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h0154};  // S / x1 (DIV)
        microcode_rom[16'h0154] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0155};  // Wait
        microcode_rom[16'h0155] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0156};  // Load quotient
        microcode_rom[16'h0156] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0157};  // quotient → temp_fp_a
        microcode_rom[16'h0157] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd0, 15'h0158};  // quotient + x1 (ADD, x1 still in B)
        microcode_rom[16'h0158] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0159};  // Wait
        microcode_rom[16'h0159] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h015A};  // Load sum
        microcode_rom[16'h015A] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h015B};  // sum → temp_fp_a
        microcode_rom[16'h015B] = {OPCODE_EXEC, MOP_LOAD_HALF_B, 8'd0, 15'h015C};  // 0.5 → temp_fp_b
        microcode_rom[16'h015C] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h015D};  // 0.5 × sum (MUL)
        microcode_rom[16'h015D] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h015E};  // Wait
        microcode_rom[16'h015E] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h015F};  // Load x2
        microcode_rom[16'h015F] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0160};  // x2 → temp_fp_a

        // Iteration 3: x3 = 0.5 × (x2 + S/x2)
        microcode_rom[16'h0160] = {OPCODE_EXEC, MOP_MOVE_A_TO_B, 8'd0, 15'h0161};  // Save x2 to temp_fp_b
        microcode_rom[16'h0161] = {OPCODE_EXEC, MOP_MOVE_C_TO_A, 8'd0, 15'h0162};  // Load S into temp_fp_a
        microcode_rom[16'h0162] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h0163};  // S / x2 (DIV)
        microcode_rom[16'h0163] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0164};  // Wait
        microcode_rom[16'h0164] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0165};  // Load quotient
        microcode_rom[16'h0165] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0166};  // quotient → temp_fp_a
        microcode_rom[16'h0166] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd0, 15'h0167};  // quotient + x2 (ADD, x2 still in B)
        microcode_rom[16'h0167] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0168};  // Wait
        microcode_rom[16'h0168] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0169};  // Load sum
        microcode_rom[16'h0169] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h016A};  // sum → temp_fp_a
        microcode_rom[16'h016A] = {OPCODE_EXEC, MOP_LOAD_HALF_B, 8'd0, 15'h016B};  // 0.5 → temp_fp_b
        microcode_rom[16'h016B] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h016C};  // 0.5 × sum (MUL)
        microcode_rom[16'h016C] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h016D};  // Wait
        microcode_rom[16'h016D] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h016E};  // Load x3
        microcode_rom[16'h016E] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h016F};  // x3 → temp_fp_a

        // Iteration 4: x4 = 0.5 × (x3 + S/x3)
        microcode_rom[16'h016F] = {OPCODE_EXEC, MOP_MOVE_A_TO_B, 8'd0, 15'h0170};  // Save x3 to temp_fp_b
        microcode_rom[16'h0170] = {OPCODE_EXEC, MOP_MOVE_C_TO_A, 8'd0, 15'h0171};  // Load S into temp_fp_a
        microcode_rom[16'h0171] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h0172};  // S / x3 (DIV)
        microcode_rom[16'h0172] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0173};  // Wait
        microcode_rom[16'h0173] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0174};  // Load quotient
        microcode_rom[16'h0174] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0175};  // quotient → temp_fp_a
        microcode_rom[16'h0175] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd0, 15'h0176};  // quotient + x3 (ADD, x3 still in B)
        microcode_rom[16'h0176] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0177};  // Wait
        microcode_rom[16'h0177] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0178};  // Load sum
        microcode_rom[16'h0178] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0179};  // sum → temp_fp_a
        microcode_rom[16'h0179] = {OPCODE_EXEC, MOP_LOAD_HALF_B, 8'd0, 15'h017A};  // 0.5 → temp_fp_b
        microcode_rom[16'h017A] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h017B};  // 0.5 × sum (MUL)
        microcode_rom[16'h017B] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h017C};  // Wait
        microcode_rom[16'h017C] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h017D};  // Load x4
        microcode_rom[16'h017D] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h017E};  // x4 → temp_fp_a

        // Iteration 5: x5 = 0.5 × (x4 + S/x4)
        microcode_rom[16'h017E] = {OPCODE_EXEC, MOP_MOVE_A_TO_B, 8'd0, 15'h017F};  // Save x4 to temp_fp_b
        microcode_rom[16'h017F] = {OPCODE_EXEC, MOP_MOVE_C_TO_A, 8'd0, 15'h0180};  // Load S into temp_fp_a
        microcode_rom[16'h0180] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h0181};  // S / x4 (DIV)
        microcode_rom[16'h0181] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0182};  // Wait
        microcode_rom[16'h0182] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0183};  // Load quotient
        microcode_rom[16'h0183] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0184};  // quotient → temp_fp_a
        microcode_rom[16'h0184] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd0, 15'h0185};  // quotient + x4 (ADD, x4 still in B)
        microcode_rom[16'h0185] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0186};  // Wait
        microcode_rom[16'h0186] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0187};  // Load sum
        microcode_rom[16'h0187] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0188};  // sum → temp_fp_a
        microcode_rom[16'h0188] = {OPCODE_EXEC, MOP_LOAD_HALF_B, 8'd0, 15'h0189};  // 0.5 → temp_fp_b
        microcode_rom[16'h0189] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h018A};  // 0.5 × sum (MUL)
        microcode_rom[16'h018A] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h018B};  // Wait
        microcode_rom[16'h018B] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h018C};  // Load x5
        microcode_rom[16'h018C] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h018D};  // x5 → temp_fp_a

        // Iteration 6: x6 = 0.5 × (x5 + S/x5)
        microcode_rom[16'h018D] = {OPCODE_EXEC, MOP_MOVE_A_TO_B, 8'd0, 15'h018E};  // Save x5 to temp_fp_b
        microcode_rom[16'h018E] = {OPCODE_EXEC, MOP_MOVE_C_TO_A, 8'd0, 15'h018F};  // Load S into temp_fp_a
        microcode_rom[16'h018F] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h0190};  // S / x5 (DIV)
        microcode_rom[16'h0190] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0191};  // Wait
        microcode_rom[16'h0191] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0192};  // Load quotient
        microcode_rom[16'h0192] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0193};  // quotient → temp_fp_a
        microcode_rom[16'h0193] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd0, 15'h0194};  // quotient + x5 (ADD, x5 still in B)
        microcode_rom[16'h0194] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0195};  // Wait
        microcode_rom[16'h0195] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0196};  // Load sum
        microcode_rom[16'h0196] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0197};  // sum → temp_fp_a
        microcode_rom[16'h0197] = {OPCODE_EXEC, MOP_LOAD_HALF_B, 8'd0, 15'h0198};  // 0.5 → temp_fp_b
        microcode_rom[16'h0198] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h0199};  // 0.5 × sum (MUL)
        microcode_rom[16'h0199] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h019A};  // Wait
        microcode_rom[16'h019A] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h019B};  // Load x6
        microcode_rom[16'h019B] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h019C};  // x6 → temp_fp_a

        // Iteration 7: x7 = 0.5 × (x6 + S/x6)
        microcode_rom[16'h019C] = {OPCODE_EXEC, MOP_MOVE_A_TO_B, 8'd0, 15'h019D};  // Save x6 to temp_fp_b
        microcode_rom[16'h019D] = {OPCODE_EXEC, MOP_MOVE_C_TO_A, 8'd0, 15'h019E};  // Load S into temp_fp_a
        microcode_rom[16'h019E] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h019F};  // S / x6 (DIV)
        microcode_rom[16'h019F] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h01A0};  // Wait
        microcode_rom[16'h01A0] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h01A1};  // Load quotient
        microcode_rom[16'h01A1] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h01A2};  // quotient → temp_fp_a
        microcode_rom[16'h01A2] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd0, 15'h01A3};  // quotient + x6 (ADD, x6 still in B)
        microcode_rom[16'h01A3] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h01A4};  // Wait
        microcode_rom[16'h01A4] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h01A5};  // Load sum
        microcode_rom[16'h01A5] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h01A6};  // sum → temp_fp_a
        microcode_rom[16'h01A6] = {OPCODE_EXEC, MOP_LOAD_HALF_B, 8'd0, 15'h01A7};  // 0.5 → temp_fp_b
        microcode_rom[16'h01A7] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h01A8};  // 0.5 × sum (MUL)
        microcode_rom[16'h01A8] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h01A9};  // Wait
        microcode_rom[16'h01A9] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h01AA};  // Load x7
        microcode_rom[16'h01AA] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h01AB};  // x7 → temp_fp_a

        // Iteration 8: x8 = 0.5 × (x7 + S/x7) - Final iteration
        microcode_rom[16'h01AB] = {OPCODE_EXEC, MOP_MOVE_A_TO_B, 8'd0, 15'h01AC};  // Save x7 to temp_fp_b
        microcode_rom[16'h01AC] = {OPCODE_EXEC, MOP_MOVE_C_TO_A, 8'd0, 15'h01AD};  // Load S into temp_fp_a
        microcode_rom[16'h01AD] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h01AE};  // S / x7 (DIV)
        microcode_rom[16'h01AE] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h01AF};  // Wait
        microcode_rom[16'h01AF] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h01B0};  // Load quotient
        microcode_rom[16'h01B0] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h01B1};  // quotient → temp_fp_a
        microcode_rom[16'h01B1] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd0, 15'h01B2};  // quotient + x7 (ADD, x7 still in B)
        microcode_rom[16'h01B2] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h01B3};  // Wait
        microcode_rom[16'h01B3] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h01B4};  // Load sum
        microcode_rom[16'h01B4] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h01B5};  // sum → temp_fp_a
        microcode_rom[16'h01B5] = {OPCODE_EXEC, MOP_LOAD_HALF_B, 8'd0, 15'h01B6};  // 0.5 → temp_fp_b
        microcode_rom[16'h01B6] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h01B7};  // 0.5 × sum (MUL)
        microcode_rom[16'h01B7] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h01B8};  // Wait
        microcode_rom[16'h01B8] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h01B9};  // Load x8 into temp_result

        // Return with final result in temp_result
        microcode_rom[16'h01B9] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};  // Return with result in temp_result

        //-------------------------------------------------------------
        // Program 5: FSIN - Sine
        // Address: 0x01C0-0x01C5 (moved to avoid SQRT overlap)
        //-------------------------------------------------------------
        microcode_rom[16'h01C0] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h01C1};          // Load temp_fp_a from data_in
        microcode_rom[16'h01C1] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd13, 15'h01C2};     // Call SIN (op=13)
        microcode_rom[16'h01C2] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h01C3};      // Wait, advance to 0x01C3 when done
        microcode_rom[16'h01C3] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h01C4};  // Load result into temp_result
        microcode_rom[16'h01C4] = {OPCODE_EXEC, MOP_STORE, 8'd0, 15'h01C5};           // Store temp_result to data_out
        microcode_rom[16'h01C5] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return with result in data_out

        //-------------------------------------------------------------
        // Program 6: FCOS - Cosine
        // Address: 0x01D0-0x01D5 (moved to avoid SQRT overlap)
        //-------------------------------------------------------------
        microcode_rom[16'h01D0] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h01D1};          // Load temp_fp_a from data_in
        microcode_rom[16'h01D1] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd14, 15'h01D2};     // Call COS (op=14)
        microcode_rom[16'h01D2] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h01D3};      // Wait, advance to 0x01D3 when done
        microcode_rom[16'h01D3] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h01D4};  // Load result into temp_result
        microcode_rom[16'h01D4] = {OPCODE_EXEC, MOP_STORE, 8'd0, 15'h01D5};           // Store temp_result to data_out
        microcode_rom[16'h01D5] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return with result in data_out

        //-------------------------------------------------------------
        // Program 9: FPREM - Partial Remainder
        // Address: 0x0300-0x030F
        // Computes: ST(0) = remainder of ST(0) / ST(1)
        // Algorithm: remainder = dividend - (quotient_int * divisor)
        //-------------------------------------------------------------
        // Step 1: Divide ST(0) / ST(1) to get quotient
        microcode_rom[16'h0300] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h0301};      // DIV: temp_result = temp_fp_a / temp_fp_b
        microcode_rom[16'h0301] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0302};      // Wait for division
        microcode_rom[16'h0302] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0303};  // Load quotient

        // Step 2: Convert quotient to integer (truncate towards zero)
        // For now, use the quotient directly - proper implementation would convert to integer
        // This is a simplified version for demonstration

        // Step 3: Multiply integer quotient by divisor
        // temp_fp_a already contains original dividend, we need quotient * divisor
        // Note: This is simplified - full implementation would need temp register juggling
        microcode_rom[16'h0303] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h0304};      // MUL: temp_result * temp_fp_b
        microcode_rom[16'h0304] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0305};      // Wait for multiplication
        microcode_rom[16'h0305] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0306};  // Load product

        // Step 4: Subtract product from original dividend to get remainder
        // remainder = dividend - product
        microcode_rom[16'h0306] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd1, 15'h0307};      // SUB: temp_fp_a - temp_result
        microcode_rom[16'h0307] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0308};      // Wait for subtraction
        microcode_rom[16'h0308] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0309};  // Load remainder
        microcode_rom[16'h0309] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        // Note: This is a simplified FPREM. A full implementation would need:
        // - Integer conversion for quotient
        // - Condition code setting (C0, C1, C2 for reduction progress)
        // - Iterative reduction for large operands
        // - Proper sign handling

        //-------------------------------------------------------------
        // Initialize rest of ROM to HALT
        //-------------------------------------------------------------
        for (i = 0; i < 4096; i = i + 1) begin
            if (microcode_rom[i] == 32'h0) begin
                microcode_rom[i] = {OPCODE_HALT, 5'd0, 8'd0, 15'd0};
            end
        end
    end

    //=================================================================
    // Main State Machine
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
            pc <= 16'd0;
            call_sp <= 4'd0;
            instruction_complete <= 1'b0;

            // Reset temp registers
            temp_fp_a <= 80'd0;
            temp_fp_b <= 80'd0;
            temp_fp_c <= 80'd0;
            temp_result <= 80'd0;
            temp_reg <= 64'd0;
            loop_reg <= 32'd0;
            temp_stack_idx <= 3'd0;

            // Reset hardware unit interfaces
            arith_enable <= 1'b0;
            arith_operation <= 5'd0;
            arith_rounding_mode <= 2'd0;
            arith_operand_a <= 80'd0;
            arith_operand_b <= 80'd0;
            arith_int16_in <= 16'd0;
            arith_int32_in <= 32'd0;
            arith_fp32_in <= 32'd0;
            arith_fp64_in <= 64'd0;

            stack_push_req <= 1'b0;
            stack_pop_req <= 1'b0;
            stack_read_sel <= 3'd0;
            stack_write_sel <= 3'd0;
            stack_write_en <= 1'b0;
            stack_write_data <= 80'd0;

            status_word_out <= 16'd0;
            status_word_write <= 1'b0;
            control_word_out <= 16'd0;
            control_word_write <= 1'b0;

            data_out <= 80'd0;

            waiting_for_arith <= 1'b0;
            waiting_for_stack <= 1'b0;

        end else begin
            // Default: clear pulse signals
            arith_enable <= 1'b0;
            stack_push_req <= 1'b0;
            stack_pop_req <= 1'b0;
            stack_write_en <= 1'b0;
            status_word_write <= 1'b0;
            control_word_write <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        pc <= micro_program_table[micro_program_index];
                        instruction_complete <= 1'b0;
                        call_sp <= 4'd0;
                        waiting_for_arith <= 1'b0;
                        waiting_for_stack <= 1'b0;
                        state <= STATE_FETCH;
                        $display("[MICROSEQ] START: program_index=%0d, start_addr=0x%04X", micro_program_index, micro_program_table[micro_program_index]);
                    end
                end

                STATE_FETCH: begin
                    microinstruction <= microcode_rom[pc];
                    state <= STATE_DECODE;
                    $display("[MICROSEQ] FETCH: pc=0x%04X, instr=0x%08X", pc, microcode_rom[pc]);
                end

                STATE_DECODE: begin
                    state <= STATE_EXEC;
                end

                STATE_WAIT: begin
                    // Dedicated wait state - check for completion every cycle
                    if (waiting_for_arith && arith_done) begin
                        // Arithmetic completed
                        waiting_for_arith <= 1'b0;
                        pc <= {1'b0, next_addr};  // Advance to next instruction
                        state <= STATE_FETCH;
                        $display("[MICROSEQ] WAIT: arith completed, advance to 0x%04X", next_addr);
                    end else if (waiting_for_stack && stack_op_done) begin
                        // Stack operation completed
                        waiting_for_stack <= 1'b0;
                        pc <= {1'b0, next_addr};
                        state <= STATE_FETCH;
                        $display("[MICROSEQ] WAIT: stack completed, advance to 0x%04X", next_addr);
                    end else begin
                        // Still waiting
                        state <= STATE_WAIT;
                        //$display("[MICROSEQ] WAIT: still waiting, arith_done=%b", arith_done);
                    end
                end

                STATE_EXEC: begin
                    case (opcode)
                        OPCODE_NOP: begin
                            pc <= pc + 1;
                            state <= STATE_FETCH;
                        end

                        OPCODE_EXEC: begin
                            case (micro_op)
                                //-------------------------------------
                                // Basic Operations
                                //-------------------------------------
                                MOP_LOAD: begin
                                    temp_result <= data_in;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                end

                                MOP_STORE: begin
                                    data_out <= temp_result;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                end

                                MOP_LOAD_A: begin
                                    temp_fp_a <= data_in;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ] LOAD_A: loaded 0x%020X into temp_fp_a", data_in);
                                end

                                MOP_LOAD_B: begin
                                    temp_fp_b <= data_in;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ] LOAD_B: loaded 0x%020X into temp_fp_b", data_in);
                                end

                                MOP_MOVE_RES_TO_A: begin
                                    temp_fp_a <= temp_result;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ] MOVE_RES_TO_A: 0x%020X", temp_result);
                                end

                                MOP_MOVE_RES_TO_B: begin
                                    temp_fp_b <= temp_result;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ] MOVE_RES_TO_B: 0x%020X", temp_result);
                                end

                                MOP_MOVE_A_TO_C: begin
                                    temp_fp_c <= temp_fp_a;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ] MOVE_A_TO_C: saved 0x%020X", temp_fp_a);
                                end

                                MOP_MOVE_A_TO_B: begin
                                    temp_fp_b <= temp_fp_a;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ] MOVE_A_TO_B: 0x%020X", temp_fp_a);
                                end

                                MOP_MOVE_C_TO_A: begin
                                    temp_fp_a <= temp_fp_c;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ] MOVE_C_TO_A: 0x%020X (S)", temp_fp_c);
                                end

                                MOP_MOVE_C_TO_B: begin
                                    temp_fp_b <= temp_fp_c;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ] MOVE_C_TO_B: 0x%020X", temp_fp_c);
                                end

                                MOP_LOAD_HALF_B: begin
                                    temp_fp_b <= CONST_HALF;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ] LOAD_HALF_B: loaded 0.5 = 0x%020X", CONST_HALF);
                                end

                                //-------------------------------------
                                // Arithmetic Unit Operations
                                //-------------------------------------
                                MOP_CALL_ARITH: begin
                                    // Start arithmetic operation
                                    arith_operation <= immediate[4:0];
                                    arith_operand_a <= temp_fp_a;
                                    arith_operand_b <= temp_fp_b;
                                    arith_enable <= 1'b1;
                                    waiting_for_arith <= 1'b1;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ] CALL_ARITH: op=%0d, enable=1, operands=0x%020X/0x%020X",
                                             immediate[4:0], temp_fp_a, temp_fp_b);
                                end

                                MOP_WAIT_ARITH: begin
                                    // Clear enable signal (operation already latched)
                                    arith_enable <= 1'b0;

                                    if (arith_done) begin
                                        // Arithmetic complete
                                        waiting_for_arith <= 1'b0;
                                        pc <= {1'b0, next_addr};
                                        state <= STATE_FETCH;
                                        $display("[MICROSEQ] WAIT_ARITH: DONE, advance to 0x%04X", next_addr);
                                    end else begin
                                        // Keep waiting - stay in WAIT state, don't cycle through FETCH/DECODE
                                        pc <= pc;
                                        state <= STATE_WAIT;  // Stay in dedicated wait state
                                        $display("[MICROSEQ] WAIT_ARITH: waiting, arith_done=%b", arith_done);
                                    end
                                end

                                MOP_LOAD_ARITH_RES: begin
                                    temp_result <= arith_result;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                end

                                //-------------------------------------
                                // Stack Operations
                                //-------------------------------------
                                MOP_LOAD_STACK_REG: begin
                                    stack_read_sel <= immediate[2:0];
                                    temp_result <= stack_read_data;  // Combinational read
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                end

                                MOP_STORE_STACK_REG: begin
                                    stack_write_sel <= immediate[2:0];
                                    stack_write_data <= temp_result;
                                    stack_write_en <= 1'b1;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                end

                                //-------------------------------------
                                // Status/Control Operations
                                //-------------------------------------
                                MOP_GET_STATUS: begin
                                    temp_reg <= {48'd0, status_word_in};
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                end

                                MOP_SET_STATUS: begin
                                    status_word_out <= temp_reg[15:0];
                                    status_word_write <= 1'b1;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                end

                                MOP_GET_CC: begin
                                    // Pack condition codes into temp_reg
                                    temp_reg[0] <= arith_cc_less;
                                    temp_reg[1] <= arith_cc_equal;
                                    temp_reg[2] <= arith_cc_greater;
                                    temp_reg[3] <= arith_cc_unordered;
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                end

                                default: begin
                                    pc <= {1'b0, next_addr};
                                    state <= STATE_FETCH;
                                end
                            endcase
                        end

                        OPCODE_JUMP: begin
                            pc <= {1'b0, next_addr};
                            state <= STATE_FETCH;
                        end

                        OPCODE_CALL: begin
                            call_stack[call_sp] <= pc + 1;
                            call_sp <= call_sp + 1;
                            pc <= {1'b0, next_addr};
                            state <= STATE_FETCH;
                        end

                        OPCODE_RET: begin
                            if (call_sp > 0) begin
                                call_sp <= call_sp - 1;
                                pc <= call_stack[call_sp - 1];
                                state <= STATE_FETCH;
                                $display("[MICROSEQ] RET: return to 0x%04X", call_stack[call_sp - 1]);
                            end else begin
                                // Empty call stack - treat as completion
                                // (happens when subroutine called directly)
                                instruction_complete <= 1'b1;
                                state <= STATE_IDLE;
                                $display("[MICROSEQ] RET: empty stack, COMPLETE");
                            end
                        end

                        OPCODE_HALT: begin
                            instruction_complete <= 1'b1;
                            state <= STATE_IDLE;
                        end

                        default: begin
                            pc <= pc + 1;
                            state <= STATE_FETCH;
                        end
                    endcase
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
