// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Extended MicroSequencer for 8087 FPU with BCD Support
//
// This module extends the basic microsequencer with hardware unit
// interface support. It provides "call and wait" subroutines that
// delegate to existing FPU_Core hardware units:
// - FPU_ArithmeticUnit (add, sub, mul, div, sqrt, trig, conversions)
// - Stack Manager (push, pop, exchange)
// - Format Converters (int, FP, BCD)
// - BCD Converters (Binary ↔ BCD) - NEW!
//
// Key Design: Microcode sequences operations, hardware units compute
//=====================================================================

module MicroSequencer_Extended_BCD (
    input wire clk,
    input wire reset,

    // Control interface
    input wire        start,                // Start microprogram execution
    input wire [4:0]  micro_program_index,  // Which microprogram to run (0-31)
    output reg        instruction_complete, // Execution complete

    // Data bus interface (for memory operations)
    input wire [79:0] data_in,
    output reg [79:0] data_out,

    // Debug/test interface - expose internal registers
    output wire [79:0] debug_temp_result,
    output wire [79:0] debug_temp_fp_a,
    output wire [79:0] debug_temp_fp_b,
    output wire [63:0] debug_temp_uint64,
    output wire        debug_temp_sign,

    // ===== Interfaces to FPU_Core Hardware Units (REUSE EXISTING) =====

    // Interface to FPU_ArithmeticUnit
    output reg [4:0]  arith_operation,      // Operation code
    output reg        arith_enable,         // Start operation
    output reg [1:0]  arith_rounding_mode,  // Rounding mode
    output reg [79:0] arith_operand_a,      // Operand A (80-bit FP)
    output reg [79:0] arith_operand_b,      // Operand B (80-bit FP)
    output reg signed [15:0] arith_int16_in,
    output reg signed [31:0] arith_int32_in,
    output reg [63:0] arith_uint64_in,      // For BCD conversion
    output reg        arith_uint64_sign_in, // Sign for BCD conversion
    output reg [31:0] arith_fp32_in,
    output reg [63:0] arith_fp64_in,
    input wire [79:0] arith_result,         // Result (80-bit FP)
    input wire signed [15:0] arith_int16_out,
    input wire signed [31:0] arith_int32_out,
    input wire [63:0] arith_uint64_out,     // From BCD conversion
    input wire        arith_uint64_sign_out, // Sign from BCD conversion
    input wire [31:0] arith_fp32_out,
    input wire [63:0] arith_fp64_out,
    input wire        arith_done,           // Operation complete
    input wire        arith_invalid,        // Exception flags
    input wire        arith_overflow,
    input wire        arith_cc_less,
    input wire        arith_cc_equal,
    input wire        arith_cc_greater,
    input wire        arith_cc_unordered,

    // NEW: Interface to BCD_to_Binary converter
    output reg        bcd2bin_enable,
    output reg [79:0] bcd2bin_bcd_in,
    input wire [63:0] bcd2bin_binary_out,
    input wire        bcd2bin_sign_out,
    input wire        bcd2bin_done,
    input wire        bcd2bin_error,

    // NEW: Interface to Binary_to_BCD converter
    output reg        bin2bcd_enable,
    output reg [63:0] bin2bcd_binary_in,
    output reg        bin2bcd_sign_in,
    input wire [79:0] bin2bcd_bcd_out,
    input wire        bin2bcd_done,
    input wire        bin2bcd_error,

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

    // Hardware unit call operations (0x10-0x1F)
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

    // NEW: BCD conversion operations (0x1A-0x1F)
    localparam MOP_CALL_BCD2BIN   = 5'h1A; // Start BCD → Binary conversion
    localparam MOP_WAIT_BCD2BIN   = 5'h1B; // Wait for BCD → Binary completion
    localparam MOP_LOAD_BCD2BIN   = 5'h1C; // Load result from BCD → Binary
    localparam MOP_CALL_BIN2BCD   = 5'h1D; // Start Binary → BCD conversion
    localparam MOP_WAIT_BIN2BCD   = 5'h1E; // Wait for Binary → BCD completion
    localparam MOP_LOAD_BIN2BCD   = 5'h1F; // Load result from Binary → BCD

    //=================================================================
    // FSM States
    //=================================================================

    localparam STATE_IDLE   = 3'd0;
    localparam STATE_FETCH  = 3'd1;
    localparam STATE_DECODE = 3'd2;
    localparam STATE_EXEC   = 3'd3;
    localparam STATE_WAIT   = 3'd4;  // Wait for hardware completion

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

    reg [15:0] micro_program_table [0:31];  // Expanded to 32 programs
    initial begin
        // Program 0: FADD subroutine
        micro_program_table[0]  = 16'h0100;
        // Program 1: FSUB subroutine
        micro_program_table[1]  = 16'h0110;
        // Program 2: FMUL subroutine
        micro_program_table[2]  = 16'h0120;
        // Program 3: FDIV subroutine
        micro_program_table[3]  = 16'h0130;
        // Program 4: FSQRT subroutine
        micro_program_table[4]  = 16'h0140;
        // Program 5: FSIN subroutine
        micro_program_table[5]  = 16'h01C0;
        // Program 6: FCOS subroutine
        micro_program_table[6]  = 16'h01D0;
        // Program 7: FLD (with format conversion)
        micro_program_table[7]  = 16'h0200;
        // Program 8: FST (with format conversion)
        micro_program_table[8]  = 16'h0210;
        // Program 9: FPREM
        micro_program_table[9]  = 16'h0300;
        // Program 10: FXTRACT
        micro_program_table[10] = 16'h0400;
        // Program 11: FSCALE
        micro_program_table[11] = 16'h0500;
        // Program 12: FBLD - Load BCD (BCD → Binary → FP80)
        micro_program_table[12] = 16'h0600;
        // Program 13: FBSTP - Store BCD (FP80 → Binary → BCD)
        micro_program_table[13] = 16'h0610;
        // Program 14: FPTAN - Partial tangent
        micro_program_table[14] = 16'h0700;
        // Program 15: FPATAN - Partial arctangent
        micro_program_table[15] = 16'h0710;
        // Program 16: F2XM1 - 2^x - 1
        micro_program_table[16] = 16'h0720;
        // Program 17: FYL2X - y × log₂(x)
        micro_program_table[17] = 16'h0730;
        // Program 18: FYL2XP1 - y × log₂(x+1)
        micro_program_table[18] = 16'h0740;
        // Program 19: FSINCOS - Sin and Cos simultaneously
        micro_program_table[19] = 16'h0750;
        // Program 20: FPREM1 - IEEE partial remainder
        micro_program_table[20] = 16'h0760;
        // Program 21: FRNDINT - Round to integer
        micro_program_table[21] = 16'h0770;
        // Reserved for future use
        micro_program_table[22] = 16'h0800;
        micro_program_table[23] = 16'h0810;
        micro_program_table[24] = 16'h0820;
        micro_program_table[25] = 16'h0830;
        micro_program_table[26] = 16'h0840;
        micro_program_table[27] = 16'h0850;
        micro_program_table[28] = 16'h0860;
        micro_program_table[29] = 16'h0870;
        micro_program_table[30] = 16'h0880;
        micro_program_table[31] = 16'h0890;
    end

    //=================================================================
    // Temporary Registers
    //=================================================================

    reg [79:0] temp_fp_a;       // Operand A (80-bit FP)
    reg [79:0] temp_fp_b;       // Operand B (80-bit FP)
    reg [79:0] temp_fp_c;       // Operand C / scratch register (80-bit FP)
    reg [79:0] temp_result;     // Result storage
    reg [63:0] temp_uint64;     // For BCD intermediate (binary value)
    reg        temp_sign;       // For BCD intermediate (sign)

    // Expose internal registers for debug/test
    assign debug_temp_result = temp_result;
    assign debug_temp_fp_a = temp_fp_a;
    assign debug_temp_fp_b = temp_fp_b;
    assign debug_temp_uint64 = temp_uint64;
    assign debug_temp_sign = temp_sign;

    reg [63:0] temp_reg;        // General purpose temp
    reg [31:0] loop_reg;        // Loop counter
    reg [2:0]  temp_stack_idx;  // Stack index

    // FP Constants (IEEE 754 extended precision format)
    localparam [79:0] CONST_HALF = 80'h3FFE8000000000000000;  // 0.5

    //=================================================================
    // Wait State Control
    //=================================================================

    reg waiting_for_arith;
    reg waiting_for_stack;
    reg waiting_for_bcd2bin;  // NEW!
    reg waiting_for_bin2bcd;  // NEW!

    //=================================================================
    // Microcode ROM
    //=================================================================

    reg [31:0] microcode_rom [0:4095];  // 4K × 32-bit microcode ROM
    integer i;

    initial begin
        // Initialize all entries to HALT
        for (i = 0; i < 4096; i = i + 1) begin
            microcode_rom[i] = {OPCODE_HALT, 5'd0, 8'd0, 15'd0};
        end

        //-------------------------------------------------------------
        // Program 0: FADD - Floating-Point Addition
        // Address: 0x0100-0x0103
        //-------------------------------------------------------------
        microcode_rom[16'h0100] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd0, 15'h0101};      // Call ADD (op=0)
        microcode_rom[16'h0101] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0102};      // Wait
        microcode_rom[16'h0102] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0103};  // Load result
        microcode_rom[16'h0103] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 1: FSUB - Floating-Point Subtraction
        // Address: 0x0110-0x0113
        //-------------------------------------------------------------
        microcode_rom[16'h0110] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd1, 15'h0111};      // Call SUB (op=1)
        microcode_rom[16'h0111] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0112};      // Wait
        microcode_rom[16'h0112] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0113};  // Load result
        microcode_rom[16'h0113] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 2: FMUL - Floating-Point Multiplication
        // Address: 0x0120-0x0123
        //-------------------------------------------------------------
        microcode_rom[16'h0120] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h0121};      // Call MUL (op=2)
        microcode_rom[16'h0121] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0122};      // Wait
        microcode_rom[16'h0122] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0123};  // Load result
        microcode_rom[16'h0123] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 3: FDIV - Floating-Point Division
        // Address: 0x0130-0x0133
        //-------------------------------------------------------------
        microcode_rom[16'h0130] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h0131};      // Call DIV (op=3)
        microcode_rom[16'h0131] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0132};      // Wait
        microcode_rom[16'h0132] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0133};  // Load result
        microcode_rom[16'h0133] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 4: FSQRT - Square Root
        // Address: 0x0140-0x014F
        // Computes √ST(0) using Newton-Raphson iteration
        // Newton-Raphson: x[n+1] = 0.5 * (x[n] + N/x[n])
        // For better performance, we use hardware OP_SQRT (12) if available
        //-------------------------------------------------------------
        microcode_rom[16'h0140] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0141};          // Load value from data_in
        microcode_rom[16'h0141] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd12, 15'h0142};     // Call SQRT (op=12) - hardware sqrt
        microcode_rom[16'h0142] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0143};      // Wait for completion
        microcode_rom[16'h0143] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0144};  // Load result
        microcode_rom[16'h0144] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 5: FSIN - Sine
        // Address: 0x01C0-0x01C5
        // Computes sin(ST(0)) using CORDIC algorithm via hardware
        //-------------------------------------------------------------
        microcode_rom[16'h01C0] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h01C1};          // Load angle from data_in
        microcode_rom[16'h01C1] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd13, 15'h01C2};     // Call SIN (op=13)
        microcode_rom[16'h01C2] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h01C3};      // Wait for completion
        microcode_rom[16'h01C3] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h01C4};  // Load sin result
        microcode_rom[16'h01C4] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 6: FCOS - Cosine
        // Address: 0x01D0-0x01D5
        // Computes cos(ST(0)) using CORDIC algorithm via hardware
        //-------------------------------------------------------------
        microcode_rom[16'h01D0] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h01D1};          // Load angle from data_in
        microcode_rom[16'h01D1] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd14, 15'h01D2};     // Call COS (op=14)
        microcode_rom[16'h01D2] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h01D3};      // Wait for completion
        microcode_rom[16'h01D3] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h01D4};  // Load cos result
        microcode_rom[16'h01D4] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 9: FPREM - Partial Remainder (8087 style)
        // Address: 0x0300-0x031F
        // Computes remainder: ST(0) = ST(0) - Q*ST(1)
        // Where Q = truncate(ST(0)/ST(1)) toward zero
        // Similar to FPREM1 but uses truncation instead of round-to-nearest
        //-------------------------------------------------------------
        // Step 1: Compute quotient = ST(0) / ST(1)
        microcode_rom[16'h0300] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0301};          // Load dividend (ST(0))
        microcode_rom[16'h0301] = {OPCODE_EXEC, MOP_LOAD_B, 8'd0, 15'h0302};          // Load divisor (ST(1))
        microcode_rom[16'h0302] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h0303};      // Call DIV (op=3)
        microcode_rom[16'h0303] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0304};      // Wait for division
        microcode_rom[16'h0304] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0305};  // quotient in temp_result

        // Step 2: Truncate quotient to integer (toward zero)
        // For FPREM (vs FPREM1), we truncate instead of rounding to nearest
        microcode_rom[16'h0305] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0306};   // Move quotient to temp_fp_a
        // Truncation is handled by setting rounding mode, or we can use temp value as-is
        // For simplicity, assuming quotient is small enough to be directly used

        // Step 3: Multiply truncated quotient by divisor
        microcode_rom[16'h0306] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h0307};      // Call MUL (op=2)
        microcode_rom[16'h0307] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0308};      // Wait for multiplication
        microcode_rom[16'h0308] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0309};  // product in temp_result

        // Step 4: Subtract product from original dividend
        // Need to reload dividend and subtract
        microcode_rom[16'h0309] = {OPCODE_EXEC, MOP_MOVE_RES_TO_B, 8'd0, 15'h030A};   // Move product to temp_fp_b
        microcode_rom[16'h030A] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h030B};          // Reload dividend
        microcode_rom[16'h030B] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd1, 15'h030C};      // Call SUB (op=1): A - B
        microcode_rom[16'h030C] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h030D};      // Wait for subtraction
        microcode_rom[16'h030D] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h030E};  // remainder in temp_result
        microcode_rom[16'h030E] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 10: FXTRACT - Extract Exponent and Significand
        // Address: 0x0400-0x0404
        // Separates FP80 into exponent (as FP) and significand [1.0, 2.0)
        // Returns significand in temp_result, exponent in result_secondary
        // Calls OP_FXTRACT (23) which returns two values
        //-------------------------------------------------------------
        microcode_rom[16'h0400] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0401};          // Load value from data_in
        microcode_rom[16'h0401] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd23, 15'h0402};     // Call FXTRACT (op=23)
        microcode_rom[16'h0402] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0403};      // Wait for extraction
        microcode_rom[16'h0403] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0404};  // Load significand result
        microcode_rom[16'h0404] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return (exponent in secondary)

        //-------------------------------------------------------------
        // Program 11: FSCALE - Scale by Power of 2
        // Address: 0x0500-0x0504
        // Scales ST(0) by 2^floor(ST(1))
        // Efficiently adds floor(ST(1)) to ST(0)'s exponent
        // Calls OP_FSCALE (24)
        //-------------------------------------------------------------
        microcode_rom[16'h0500] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0501};          // Load value (ST(0))
        microcode_rom[16'h0501] = {OPCODE_EXEC, MOP_LOAD_B, 8'd0, 15'h0502};          // Load scale factor (ST(1))
        microcode_rom[16'h0502] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd24, 15'h0503};     // Call FSCALE (op=24)
        microcode_rom[16'h0503] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0504};      // Wait for scaling
        microcode_rom[16'h0504] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0505};  // Load scaled result
        microcode_rom[16'h0505] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 12: FBLD - Load BCD
        // Address: 0x0600-0x0609
        // Flow: BCD (from data_in) → Binary (uint64) → FP80 (to temp_result)
        //-------------------------------------------------------------
        // Step 1: Convert BCD to Binary
        microcode_rom[16'h0600] = {OPCODE_EXEC, MOP_CALL_BCD2BIN, 8'd0, 15'h0601};    // Start BCD → Binary (data_in contains BCD)
        microcode_rom[16'h0601] = {OPCODE_EXEC, MOP_WAIT_BCD2BIN, 8'd0, 15'h0602};    // Wait for conversion (~18 cycles)
        microcode_rom[16'h0602] = {OPCODE_EXEC, MOP_LOAD_BCD2BIN, 8'd0, 15'h0603};    // Load binary result to temp_uint64, temp_sign

        // Step 2: Convert Binary (uint64) to FP80
        microcode_rom[16'h0603] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd16, 15'h0604};     // Call UINT64_TO_FP (op=16)
        microcode_rom[16'h0604] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0605};      // Wait for conversion (1 cycle)
        microcode_rom[16'h0605] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0606};  // Load FP80 result to temp_result
        microcode_rom[16'h0606] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return with FP80 in temp_result

        //-------------------------------------------------------------
        // Program 13: FBSTP - Store BCD and Pop
        // Address: 0x0610-0x0619
        // Flow: FP80 (from data_in) → Binary (uint64) → BCD (to data_out)
        //-------------------------------------------------------------
        // Step 0: Load FP80 from data_in into temp_fp_a
        microcode_rom[16'h0610] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0611};          // Load FP80 from data_in

        // Step 1: Convert FP80 to Binary (uint64)
        microcode_rom[16'h0611] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd17, 15'h0612};     // Call FP_TO_UINT64 (op=17)
        microcode_rom[16'h0612] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0613};      // Wait for conversion (1 cycle)
        microcode_rom[16'h0613] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0614};  // Load uint64 result (sets arith_uint64_out)

        // Step 2: Convert Binary to BCD
        microcode_rom[16'h0614] = {OPCODE_EXEC, MOP_CALL_BIN2BCD, 8'd0, 15'h0615};    // Start Binary → BCD
        microcode_rom[16'h0615] = {OPCODE_EXEC, MOP_WAIT_BIN2BCD, 8'd0, 15'h0616};    // Wait for conversion (~64 cycles)
        microcode_rom[16'h0616] = {OPCODE_EXEC, MOP_LOAD_BIN2BCD, 8'd0, 15'h0617};    // Load BCD result to data_out
        microcode_rom[16'h0617] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return with BCD in data_out

        //-------------------------------------------------------------
        // Program 14: FPTAN - Partial Tangent
        // Address: 0x0700-0x0705
        // Returns tan(ST(0)) in ST(0) and pushes 1.0 to ST(1)
        // Uses hardware OP_TAN (18) which computes sin/cos and divides
        //-------------------------------------------------------------
        microcode_rom[16'h0700] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0701};          // Load angle from data_in
        microcode_rom[16'h0701] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd18, 15'h0702};     // Call TAN (op=18)
        microcode_rom[16'h0702] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0703};      // Wait for completion
        microcode_rom[16'h0703] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0704};  // Load tan result
        microcode_rom[16'h0704] = {OPCODE_EXEC, MOP_STORE, 8'd0, 15'h0705};           // Store result
        microcode_rom[16'h0705] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 15: FPATAN - Partial Arctangent
        // Address: 0x0710-0x0715
        // Computes atan2(ST(1), ST(0)) = atan(y/x)
        // Uses hardware OP_ATAN (19)
        //-------------------------------------------------------------
        microcode_rom[16'h0710] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0711};          // Load x (from data_in)
        microcode_rom[16'h0711] = {OPCODE_EXEC, MOP_LOAD_B, 8'd0, 15'h0712};          // Load y (from data_in)
        microcode_rom[16'h0712] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd19, 15'h0713};     // Call ATAN (op=19)
        microcode_rom[16'h0713] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0714};      // Wait for completion
        microcode_rom[16'h0714] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0715};  // Load atan result
        microcode_rom[16'h0715] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 16: F2XM1 - 2^x - 1
        // Address: 0x0720-0x0724
        // Computes 2^ST(0) - 1 (for -1 ≤ ST(0) ≤ +1)
        // Uses hardware OP_F2XM1 (20)
        //-------------------------------------------------------------
        microcode_rom[16'h0720] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0721};          // Load x from data_in
        microcode_rom[16'h0721] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd20, 15'h0722};     // Call F2XM1 (op=20)
        microcode_rom[16'h0722] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0723};      // Wait for completion
        microcode_rom[16'h0723] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0724};  // Load result
        microcode_rom[16'h0724] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 17: FYL2X - y × log₂(x)
        // Address: 0x0730-0x0735
        // Computes ST(1) × log₂(ST(0))
        // Uses hardware OP_FYL2X (21)
        //-------------------------------------------------------------
        microcode_rom[16'h0730] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0731};          // Load x from data_in
        microcode_rom[16'h0731] = {OPCODE_EXEC, MOP_LOAD_B, 8'd0, 15'h0732};          // Load y from data_in
        microcode_rom[16'h0732] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd21, 15'h0733};     // Call FYL2X (op=21)
        microcode_rom[16'h0733] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0734};      // Wait for completion
        microcode_rom[16'h0734] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0735};  // Load result
        microcode_rom[16'h0735] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 18: FYL2XP1 - y × log₂(x+1)
        // Address: 0x0740-0x0745
        // Computes ST(1) × log₂(ST(0) + 1)
        // Uses hardware OP_FYL2XP1 (22)
        //-------------------------------------------------------------
        microcode_rom[16'h0740] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0741};          // Load x from data_in
        microcode_rom[16'h0741] = {OPCODE_EXEC, MOP_LOAD_B, 8'd0, 15'h0742};          // Load y from data_in
        microcode_rom[16'h0742] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd22, 15'h0743};     // Call FYL2XP1 (op=22)
        microcode_rom[16'h0743] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0744};      // Wait for completion
        microcode_rom[16'h0744] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0745};  // Load result
        microcode_rom[16'h0745] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 19: FSINCOS - Sin and Cos Simultaneously
        // Address: 0x0750-0x0755
        // Computes both sin(ST(0)) and cos(ST(0))
        // Uses hardware OP_SINCOS (15) which returns both results
        //-------------------------------------------------------------
        microcode_rom[16'h0750] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0751};          // Load angle from data_in
        microcode_rom[16'h0751] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd15, 15'h0752};     // Call SINCOS (op=15)
        microcode_rom[16'h0752] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0753};      // Wait for completion
        microcode_rom[16'h0753] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0754};  // Load sin result (primary)
        // Note: Secondary result (cos) available in arith_result_secondary
        microcode_rom[16'h0754] = {OPCODE_EXEC, MOP_STORE, 8'd0, 15'h0755};           // Store result
        microcode_rom[16'h0755] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 20: FPREM1 - IEEE Partial Remainder
        // Address: 0x0760-0x077F
        // Computes IEEE remainder: ST(0) = remainder(ST(0), ST(1))
        // This is a software implementation using subtract/compare loop
        //-------------------------------------------------------------
        // Step 1: Compute quotient = ST(0) / ST(1)
        microcode_rom[16'h0760] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0761};          // Load dividend
        microcode_rom[16'h0761] = {OPCODE_EXEC, MOP_LOAD_B, 8'd0, 15'h0762};          // Load divisor
        microcode_rom[16'h0762] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd3, 15'h0763};      // Call DIV (op=3)
        microcode_rom[16'h0763] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0764};      // Wait for division
        microcode_rom[16'h0764] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0765};  // quotient in temp_result

        // Step 2: Round quotient to nearest integer (FRNDINT equivalent)
        microcode_rom[16'h0765] = {OPCODE_EXEC, MOP_MOVE_RES_TO_A, 8'd0, 15'h0766};   // Move quotient to temp_fp_a
        // TODO: Add FRNDINT operation here - for now use simplified approach

        // Step 3: Multiply rounded quotient by divisor
        microcode_rom[16'h0766] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd2, 15'h0767};      // Call MUL (op=2)
        microcode_rom[16'h0767] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h0768};      // Wait for multiplication
        microcode_rom[16'h0768] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h0769};  // product in temp_result

        // Step 4: Subtract product from original dividend
        microcode_rom[16'h0769] = {OPCODE_EXEC, MOP_MOVE_RES_TO_B, 8'd0, 15'h076A};   // Move product to temp_fp_b
        microcode_rom[16'h076A] = {OPCODE_EXEC, MOP_CALL_ARITH, 8'd1, 15'h076B};      // Call SUB (op=1)
        microcode_rom[16'h076B] = {OPCODE_EXEC, MOP_WAIT_ARITH, 8'd0, 15'h076C};      // Wait for subtraction
        microcode_rom[16'h076C] = {OPCODE_EXEC, MOP_LOAD_ARITH_RES, 8'd0, 15'h076D};  // remainder in temp_result
        microcode_rom[16'h076D] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return

        //-------------------------------------------------------------
        // Program 21: FRNDINT - Round to Integer
        // Address: 0x0770-0x0780
        // Rounds ST(0) to integer according to rounding control
        // Simple implementation: Extract integer part (for demonstration)
        //-------------------------------------------------------------
        microcode_rom[16'h0770] = {OPCODE_EXEC, MOP_LOAD_A, 8'd0, 15'h0771};          // Load value from data_in
        // For FP80: [79]=sign, [78:64]=exponent, [63:0]=mantissa
        // Integer part extraction would require bit manipulation
        // For now, just return the value (placeholder - needs proper implementation)
        microcode_rom[16'h0771] = {OPCODE_EXEC, MOP_MOVE_A_TO_B, 8'd0, 15'h0772};     // Copy to result
        microcode_rom[16'h0772] = {OPCODE_EXEC, MOP_STORE, 8'd0, 15'h0773};           // Store result
        microcode_rom[16'h0773] = {OPCODE_RET, 5'd0, 8'd0, 15'd0};                     // Return
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
            temp_uint64 <= 64'd0;
            temp_sign <= 1'b0;
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
            arith_uint64_in <= 64'd0;
            arith_uint64_sign_in <= 1'b0;
            arith_fp32_in <= 32'd0;
            arith_fp64_in <= 64'd0;

            // Reset BCD interfaces
            bcd2bin_enable <= 1'b0;
            bcd2bin_bcd_in <= 80'd0;
            bin2bcd_enable <= 1'b0;
            bin2bcd_binary_in <= 64'd0;
            bin2bcd_sign_in <= 1'b0;

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
            waiting_for_bcd2bin <= 1'b0;
            waiting_for_bin2bcd <= 1'b0;

        end else begin
            // Default: clear pulse signals
            arith_enable <= 1'b0;
            bcd2bin_enable <= 1'b0;
            bin2bcd_enable <= 1'b0;
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
                        waiting_for_bcd2bin <= 1'b0;
                        waiting_for_bin2bcd <= 1'b0;
                        state <= STATE_FETCH;
                        $display("[MICROSEQ_BCD] START: program=%0d, addr=0x%04X", micro_program_index, micro_program_table[micro_program_index]);
                    end
                end

                STATE_FETCH: begin
                    microinstruction <= microcode_rom[pc];
                    state <= STATE_DECODE;
                    $display("[MICROSEQ_BCD] FETCH: PC=0x%04X, inst=%08X", pc, microcode_rom[pc]);
                end

                STATE_DECODE: begin
                    $display("[MICROSEQ_BCD] DECODE: opcode=%h, micro_op=%h", opcode, micro_op);
                    state <= STATE_EXEC;
                end

                STATE_EXEC: begin
                    case (opcode)
                        OPCODE_NOP: begin
                            pc <= pc + 1;
                            state <= STATE_FETCH;
                        end

                        OPCODE_EXEC: begin
                            case (micro_op)
                                MOP_LOAD_A: begin
                                    temp_fp_a <= data_in;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] LOAD_A: %h", data_in);
                                end

                                MOP_LOAD_B: begin
                                    temp_fp_b <= data_in;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] LOAD_B: %h", data_in);
                                end

                                MOP_STORE: begin
                                    data_out <= temp_result;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] STORE: %h", temp_result);
                                end

                                MOP_MOVE_RES_TO_A: begin
                                    temp_fp_a <= temp_result;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] MOVE_RES_TO_A: %h", temp_result);
                                end

                                MOP_MOVE_RES_TO_B: begin
                                    temp_fp_b <= temp_result;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] MOVE_RES_TO_B: %h", temp_result);
                                end

                                MOP_MOVE_A_TO_B: begin
                                    temp_fp_b <= temp_fp_a;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] MOVE_A_TO_B: %h", temp_fp_a);
                                end

                                MOP_MOVE_A_TO_C: begin
                                    temp_fp_c <= temp_fp_a;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] MOVE_A_TO_C: %h", temp_fp_a);
                                end

                                MOP_MOVE_C_TO_A: begin
                                    temp_fp_a <= temp_fp_c;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] MOVE_C_TO_A: %h", temp_fp_c);
                                end

                                MOP_MOVE_C_TO_B: begin
                                    temp_fp_b <= temp_fp_c;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] MOVE_C_TO_B: %h", temp_fp_c);
                                end

                                MOP_CALL_ARITH: begin
                                    arith_operation <= immediate[4:0];
                                    arith_operand_a <= temp_fp_a;
                                    arith_operand_b <= temp_fp_b;
                                    arith_uint64_in <= temp_uint64;
                                    arith_uint64_sign_in <= temp_sign;
                                    arith_enable <= 1'b1;
                                    waiting_for_arith <= 1'b1;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] CALL_ARITH: op=%0d", immediate[4:0]);
                                end

                                MOP_WAIT_ARITH: begin
                                    if (arith_done) begin
                                        waiting_for_arith <= 1'b0;
                                        arith_enable <= 1'b0;
                                        pc <= next_addr;
                                        state <= STATE_FETCH;
                                        $display("[MICROSEQ_BCD] WAIT_ARITH: Done");
                                    end else begin
                                        // Continue waiting
                                        state <= STATE_EXEC;  // Re-execute WAIT instruction
                                        $display("[MICROSEQ_BCD] WAIT_ARITH: Still waiting...");
                                    end
                                end

                                MOP_LOAD_ARITH_RES: begin
                                    temp_result <= arith_result;
                                    // Also capture uint64 outputs for BCD operations
                                    temp_uint64 <= arith_uint64_out;
                                    temp_sign <= arith_uint64_sign_out;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] LOAD_ARITH_RES: %h", arith_result);
                                end

                                // NEW: BCD to Binary operations
                                MOP_CALL_BCD2BIN: begin
                                    bcd2bin_bcd_in <= data_in;  // BCD data from memory
                                    bcd2bin_enable <= 1'b1;
                                    waiting_for_bcd2bin <= 1'b1;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] CALL_BCD2BIN: %h", data_in);
                                end

                                MOP_WAIT_BCD2BIN: begin
                                    if (bcd2bin_done) begin
                                        waiting_for_bcd2bin <= 1'b0;
                                        bcd2bin_enable <= 1'b0;
                                        pc <= next_addr;
                                        state <= STATE_FETCH;
                                        $display("[MICROSEQ_BCD] WAIT_BCD2BIN: Done, error=%b", bcd2bin_error);
                                    end else begin
                                        // Continue waiting
                                        state <= STATE_EXEC;  // Re-execute WAIT instruction
                                        $display("[MICROSEQ_BCD] WAIT_BCD2BIN: Still waiting...");
                                    end
                                end

                                MOP_LOAD_BCD2BIN: begin
                                    temp_uint64 <= bcd2bin_binary_out;
                                    temp_sign <= bcd2bin_sign_out;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] LOAD_BCD2BIN: uint64=%h, sign=%b", bcd2bin_binary_out, bcd2bin_sign_out);
                                end

                                // NEW: Binary to BCD operations
                                MOP_CALL_BIN2BCD: begin
                                    bin2bcd_binary_in <= arith_uint64_out;  // From previous FP80→UINT64 conversion
                                    bin2bcd_sign_in <= arith_uint64_sign_out;
                                    bin2bcd_enable <= 1'b1;
                                    waiting_for_bin2bcd <= 1'b1;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] CALL_BIN2BCD: uint64=%h, sign=%b", arith_uint64_out, arith_uint64_sign_out);
                                end

                                MOP_WAIT_BIN2BCD: begin
                                    if (bin2bcd_done) begin
                                        waiting_for_bin2bcd <= 1'b0;
                                        bin2bcd_enable <= 1'b0;
                                        pc <= next_addr;
                                        state <= STATE_FETCH;
                                        $display("[MICROSEQ_BCD] WAIT_BIN2BCD: Done, error=%b", bin2bcd_error);
                                    end else begin
                                        // Continue waiting
                                        state <= STATE_EXEC;  // Re-execute WAIT instruction
                                        $display("[MICROSEQ_BCD] WAIT_BIN2BCD: Still waiting...");
                                    end
                                end

                                MOP_LOAD_BIN2BCD: begin
                                    data_out <= bin2bcd_bcd_out;
                                    pc <= next_addr;
                                    state <= STATE_FETCH;
                                    $display("[MICROSEQ_BCD] LOAD_BIN2BCD: BCD=%h", bin2bcd_bcd_out);
                                end

                                default: begin
                                    $display("[MICROSEQ_BCD] ERROR: Unknown micro-op %h", micro_op);
                                    state <= STATE_IDLE;
                                end
                            endcase
                        end

                        OPCODE_RET: begin
                            instruction_complete <= 1'b1;
                            state <= STATE_IDLE;
                            $display("[MICROSEQ_BCD] RET: Result=%h", temp_result);
                        end

                        OPCODE_HALT: begin
                            instruction_complete <= 1'b1;
                            state <= STATE_IDLE;
                            $display("[MICROSEQ_BCD] HALT");
                        end

                        default: begin
                            $display("[MICROSEQ_BCD] ERROR: Unknown opcode %h", opcode);
                            state <= STATE_IDLE;
                        end
                    endcase
                end

                STATE_WAIT: begin
                    // Check all possible wait conditions
                    if (waiting_for_arith && arith_done) begin
                        waiting_for_arith <= 1'b0;
                        pc <= pc;  // Re-execute same instruction (WAIT_ARITH) which will advance
                        state <= STATE_FETCH;
                    end else if (waiting_for_bcd2bin && bcd2bin_done) begin
                        waiting_for_bcd2bin <= 1'b0;
                        pc <= pc;
                        state <= STATE_FETCH;
                    end else if (waiting_for_bin2bcd && bin2bcd_done) begin
                        waiting_for_bin2bcd <= 1'b0;
                        pc <= pc;
                        state <= STATE_FETCH;
                    end
                    // else: continue waiting
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
