// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// Intel 8087 FPU Instruction Decoder
//
// Decodes real 8087 ESC instructions (opcodes D8-DF) into internal
// operation codes and operand specifications.
//
// Input: 16-bit instruction word (opcode + ModR/M byte)
// Output: Internal operation code, operand types, stack indices
//
// Supports all 68 8087 instructions with proper ModR/M decoding
//=====================================================================

module FPU_Instruction_Decoder(
    input wire [15:0] instruction,      // Full instruction: [opcode][ModR/M]
    input wire        decode,           // Trigger decode operation

    // Decoded outputs
    output reg [7:0]  internal_opcode,  // Internal operation code
    output reg [2:0]  stack_index,      // ST(i) index for register operations
    output reg        has_memory_op,    // Operation involves memory
    output reg        has_pop,          // Operation pops stack
    output reg        has_push,         // Operation pushes stack
    output reg [1:0]  operand_size,     // Memory operand size (0=word, 1=dword, 2=qword, 3=tbyte)
    output reg        is_integer,       // Memory operand is integer
    output reg        is_bcd,           // Memory operand is BCD
    output reg        valid,            // Instruction is valid
    output reg        uses_st0_sti,     // Format: op ST(0), ST(i)
    output reg        uses_sti_st0      // Format: op ST(i), ST(0)
);

    //=================================================================
    // Internal Opcode Definitions (matching FPU_Core.v)
    //=================================================================

    // Arithmetic
    localparam OP_FADD      = 8'h10;
    localparam OP_FADDP     = 8'h11;
    localparam OP_FSUB      = 8'h12;
    localparam OP_FSUBP     = 8'h13;
    localparam OP_FSUBR     = 8'h14;
    localparam OP_FSUBRP    = 8'h15;
    localparam OP_FMUL      = 8'h16;
    localparam OP_FMULP     = 8'h17;
    localparam OP_FDIV      = 8'h18;
    localparam OP_FDIVP     = 8'h19;
    localparam OP_FDIVR     = 8'h1A;
    localparam OP_FDIVRP    = 8'h1B;

    // Stack operations
    localparam OP_FLD       = 8'h20;
    localparam OP_FST       = 8'h21;
    localparam OP_FSTP      = 8'h22;
    localparam OP_FXCH      = 8'h23;

    // Integer loads/stores
    localparam OP_FILD16    = 8'h30;
    localparam OP_FILD32    = 8'h31;
    localparam OP_FILD64    = 8'h32;
    localparam OP_FIST16    = 8'h33;
    localparam OP_FIST32    = 8'h34;
    localparam OP_FISTP16   = 8'h35;
    localparam OP_FISTP32   = 8'h36;
    localparam OP_FISTP64   = 8'h37;

    // BCD operations
    localparam OP_FBLD      = 8'h38;
    localparam OP_FBSTP     = 8'h39;

    // FP format operations
    localparam OP_FLD32     = 8'h40;
    localparam OP_FLD64     = 8'h41;
    localparam OP_FST32     = 8'h42;
    localparam OP_FST64     = 8'h43;
    localparam OP_FSTP32    = 8'h44;
    localparam OP_FSTP64    = 8'h45;

    // Transcendental
    localparam OP_FSQRT     = 8'h50;
    localparam OP_FSIN      = 8'h51;
    localparam OP_FCOS      = 8'h52;
    localparam OP_FSINCOS   = 8'h53;
    localparam OP_FPTAN     = 8'h54;
    localparam OP_FPATAN    = 8'h55;
    localparam OP_F2XM1     = 8'h56;
    localparam OP_FYL2X     = 8'h57;
    localparam OP_FYL2XP1   = 8'h58;

    // Comparison
    localparam OP_FCOM      = 8'h60;
    localparam OP_FCOMP     = 8'h61;
    localparam OP_FCOMPP    = 8'h62;
    localparam OP_FTST      = 8'h63;
    localparam OP_FXAM      = 8'h64;
    localparam OP_FUCOM     = 8'h65;
    localparam OP_FUCOMP    = 8'h66;
    localparam OP_FUCOMPP   = 8'h67;

    // Stack management
    localparam OP_FINCSTP   = 8'h70;
    localparam OP_FDECSTP   = 8'h71;
    localparam OP_FFREE     = 8'h72;
    localparam OP_FNOP      = 8'h73;

    // Constants
    localparam OP_FLD1      = 8'h80;
    localparam OP_FLDZ      = 8'h81;
    localparam OP_FLDPI     = 8'h82;
    localparam OP_FLDL2E    = 8'h83;
    localparam OP_FLDL2T    = 8'h84;
    localparam OP_FLDLG2    = 8'h85;
    localparam OP_FLDLN2    = 8'h86;

    // Control
    localparam OP_FINIT     = 8'hF0;
    localparam OP_FLDCW     = 8'hF1;
    localparam OP_FSTCW     = 8'hF2;
    localparam OP_FSTSW     = 8'hF3;
    localparam OP_FCLEX     = 8'hF4;
    localparam OP_FWAIT     = 8'hF5;

    // Advanced
    localparam OP_FSCALE    = 8'h90;
    localparam OP_FXTRACT   = 8'h91;
    localparam OP_FPREM     = 8'h92;
    localparam OP_FRNDINT   = 8'h93;
    localparam OP_FABS      = 8'h94;
    localparam OP_FCHS      = 8'h95;
    localparam OP_FPREM1    = 8'h96;

    //=================================================================
    // Instruction Decoding
    //=================================================================

    wire [7:0] opcode;
    wire [7:0] modrm;
    wire [1:0] mod;
    wire [2:0] reg_op;
    wire [2:0] rm;

    assign opcode = instruction[15:8];
    assign modrm  = instruction[7:0];
    assign mod    = modrm[7:6];
    assign reg_op = modrm[5:3];
    assign rm     = modrm[2:0];

    always @(*) begin
        // Default values
        internal_opcode = 8'h00;
        stack_index = rm;
        has_memory_op = (mod != 2'b11);
        has_pop = 1'b0;
        has_push = 1'b0;
        operand_size = 2'd0;
        is_integer = 1'b0;
        is_bcd = 1'b0;
        valid = 1'b0;
        uses_st0_sti = 1'b0;
        uses_sti_st0 = 1'b0;

        if (decode) begin
            case (opcode)
                //=====================================================
                // D8: Arithmetic operations (32-bit memory or ST(i))
                //=====================================================
                8'hD8: begin
                    valid = 1'b1;
                    if (mod == 2'b11) begin
                        // Register operations: D8 C0-FF
                        case (reg_op)
                            3'b000: begin // FADD ST(0), ST(i)
                                internal_opcode = OP_FADD;
                                uses_st0_sti = 1'b1;
                            end
                            3'b001: begin // FMUL ST(0), ST(i)
                                internal_opcode = OP_FMUL;
                                uses_st0_sti = 1'b1;
                            end
                            3'b010: begin // FCOM ST(i)
                                internal_opcode = OP_FCOM;
                            end
                            3'b011: begin // FCOMP ST(i)
                                internal_opcode = OP_FCOMP;
                                has_pop = 1'b1;
                            end
                            3'b100: begin // FSUB ST(0), ST(i)
                                internal_opcode = OP_FSUB;
                                uses_st0_sti = 1'b1;
                            end
                            3'b101: begin // FSUBR ST(0), ST(i)
                                internal_opcode = OP_FSUBR;
                                uses_st0_sti = 1'b1;
                            end
                            3'b110: begin // FDIV ST(0), ST(i)
                                internal_opcode = OP_FDIV;
                                uses_st0_sti = 1'b1;
                            end
                            3'b111: begin // FDIVR ST(0), ST(i)
                                internal_opcode = OP_FDIVR;
                                uses_st0_sti = 1'b1;
                            end
                        endcase
                    end else begin
                        // Memory operations: 32-bit real
                        operand_size = 2'd1; // dword
                        case (reg_op)
                            3'b000: begin // FADD m32real
                                internal_opcode = OP_FADD;
                                has_push = 1'b1; // Load memory value first
                            end
                            3'b001: begin // FMUL m32real
                                internal_opcode = OP_FMUL;
                                has_push = 1'b1;
                            end
                            3'b010: begin // FCOM m32real
                                internal_opcode = OP_FCOM;
                            end
                            3'b011: begin // FCOMP m32real
                                internal_opcode = OP_FCOMP;
                                has_pop = 1'b1;
                            end
                            3'b100: begin // FSUB m32real
                                internal_opcode = OP_FSUB;
                                has_push = 1'b1;
                            end
                            3'b101: begin // FSUBR m32real
                                internal_opcode = OP_FSUBR;
                                has_push = 1'b1;
                            end
                            3'b110: begin // FDIV m32real
                                internal_opcode = OP_FDIV;
                                has_push = 1'b1;
                            end
                            3'b111: begin // FDIVR m32real
                                internal_opcode = OP_FDIVR;
                                has_push = 1'b1;
                            end
                        endcase
                    end
                end

                //=====================================================
                // D9: Load/Store, FPU control, transcendental
                //=====================================================
                8'hD9: begin
                    valid = 1'b1;
                    if (mod == 2'b11) begin
                        // Register/control operations
                        case (modrm)
                            // FLD ST(i): D9 C0-C7
                            8'hC0, 8'hC1, 8'hC2, 8'hC3,
                            8'hC4, 8'hC5, 8'hC6, 8'hC7: begin
                                internal_opcode = OP_FLD;
                                has_push = 1'b1;
                            end

                            // FXCH ST(i): D9 C8-CF
                            8'hC8, 8'hC9, 8'hCA, 8'hCB,
                            8'hCC, 8'hCD, 8'hCE, 8'hCF: begin
                                internal_opcode = OP_FXCH;
                            end

                            // FNOP: D9 D0
                            8'hD0: internal_opcode = OP_FNOP;

                            // FCHS: D9 E0
                            8'hE0: begin
                                internal_opcode = OP_FCHS;
                                stack_index = 3'd0;
                            end

                            // FABS: D9 E1
                            8'hE1: begin
                                internal_opcode = OP_FABS;
                                stack_index = 3'd0;
                            end

                            // FTST: D9 E4
                            8'hE4: begin
                                internal_opcode = OP_FTST;
                                stack_index = 3'd0;
                            end

                            // FXAM: D9 E5
                            8'hE5: begin
                                internal_opcode = OP_FXAM;
                                stack_index = 3'd0;
                            end

                            // FLD1: D9 E8
                            8'hE8: begin
                                internal_opcode = OP_FLD1;
                                has_push = 1'b1;
                                stack_index = 3'd0;
                            end

                            // FLDL2T: D9 E9
                            8'hE9: begin
                                internal_opcode = OP_FLDL2T;
                                has_push = 1'b1;
                                stack_index = 3'd0;
                            end

                            // FLDL2E: D9 EA
                            8'hEA: begin
                                internal_opcode = OP_FLDL2E;
                                has_push = 1'b1;
                                stack_index = 3'd0;
                            end

                            // FLDPI: D9 EB
                            8'hEB: begin
                                internal_opcode = OP_FLDPI;
                                has_push = 1'b1;
                                stack_index = 3'd0;
                            end

                            // FLDLG2: D9 EC
                            8'hEC: begin
                                internal_opcode = OP_FLDLG2;
                                has_push = 1'b1;
                                stack_index = 3'd0;
                            end

                            // FLDLN2: D9 ED
                            8'hED: begin
                                internal_opcode = OP_FLDLN2;
                                has_push = 1'b1;
                                stack_index = 3'd0;
                            end

                            // FLDZ: D9 EE
                            8'hEE: begin
                                internal_opcode = OP_FLDZ;
                                has_push = 1'b1;
                                stack_index = 3'd0;
                            end

                            // F2XM1: D9 F0
                            8'hF0: begin
                                internal_opcode = OP_F2XM1;
                                stack_index = 3'd0;
                            end

                            // FYL2X: D9 F1
                            8'hF1: begin
                                internal_opcode = OP_FYL2X;
                                has_pop = 1'b1;
                                stack_index = 3'd0;
                            end

                            // FPTAN: D9 F2
                            8'hF2: begin
                                internal_opcode = OP_FPTAN;
                                has_push = 1'b1;
                                stack_index = 3'd0;
                            end

                            // FPATAN: D9 F3
                            8'hF3: begin
                                internal_opcode = OP_FPATAN;
                                has_pop = 1'b1;
                                stack_index = 3'd0;
                            end

                            // FXTRACT: D9 F4
                            8'hF4: begin
                                internal_opcode = OP_FXTRACT;
                                has_push = 1'b1;
                                stack_index = 3'd0;
                            end

                            // FPREM1: D9 F5 (IEEE partial remainder, 387+)
                            8'hF5: begin
                                internal_opcode = OP_FPREM1;
                                stack_index = 3'd0;
                            end

                            // FPREM: D9 F8 (8087 partial remainder)
                            8'hF8: begin
                                internal_opcode = OP_FPREM;
                                stack_index = 3'd0;
                            end

                            // FYL2XP1: D9 F9
                            8'hF9: begin
                                internal_opcode = OP_FYL2XP1;
                                has_pop = 1'b1;
                                stack_index = 3'd0;
                            end

                            // FSQRT: D9 FA
                            8'hFA: begin
                                internal_opcode = OP_FSQRT;
                                stack_index = 3'd0;
                            end

                            // FSINCOS: D9 FB
                            8'hFB: begin
                                internal_opcode = OP_FSINCOS;
                                has_push = 1'b1;
                                stack_index = 3'd0;
                            end

                            // FRNDINT: D9 FC
                            8'hFC: begin
                                internal_opcode = OP_FRNDINT;
                                stack_index = 3'd0;
                            end

                            // FSCALE: D9 FD
                            8'hFD: begin
                                internal_opcode = OP_FSCALE;
                                stack_index = 3'd0;
                            end

                            // FSIN: D9 FE
                            8'hFE: begin
                                internal_opcode = OP_FSIN;
                                stack_index = 3'd0;
                            end

                            // FCOS: D9 FF
                            8'hFF: begin
                                internal_opcode = OP_FCOS;
                                stack_index = 3'd0;
                            end

                            default: valid = 1'b0;
                        endcase
                    end else begin
                        // Memory operations: 32-bit real
                        operand_size = 2'd1; // dword
                        case (reg_op)
                            3'b000: begin // FLD m32real
                                internal_opcode = OP_FLD32;
                                has_push = 1'b1;
                            end
                            3'b010: begin // FST m32real
                                internal_opcode = OP_FST32;
                            end
                            3'b011: begin // FSTP m32real
                                internal_opcode = OP_FSTP32;
                                has_pop = 1'b1;
                            end
                            3'b101: begin // FLDCW m16
                                internal_opcode = OP_FLDCW;
                                operand_size = 2'd0; // word
                            end
                            3'b111: begin // FSTCW m16
                                internal_opcode = OP_FSTCW;
                                operand_size = 2'd0; // word
                            end
                            default: valid = 1'b0;
                        endcase
                    end
                end

                //=====================================================
                // DA: Integer operations (32-bit) and FCOM variants
                //=====================================================
                8'hDA: begin
                    valid = 1'b1;
                    if (mod == 2'b11) begin
                        // Special operations
                        case (modrm)
                            8'hE9: begin // FUCOMPP
                                internal_opcode = OP_FUCOMPP;
                                has_pop = 1'b1;
                                stack_index = 3'd0;
                            end
                            default: valid = 1'b0;
                        endcase
                    end else begin
                        // Memory operations: 32-bit integer
                        operand_size = 2'd1; // dword
                        is_integer = 1'b1;
                        case (reg_op)
                            3'b000: begin // FIADD m32int
                                internal_opcode = OP_FADD;
                                has_push = 1'b1;
                            end
                            3'b001: begin // FIMUL m32int
                                internal_opcode = OP_FMUL;
                                has_push = 1'b1;
                            end
                            3'b010: begin // FICOM m32int
                                internal_opcode = OP_FCOM;
                            end
                            3'b011: begin // FICOMP m32int
                                internal_opcode = OP_FCOMP;
                                has_pop = 1'b1;
                            end
                            3'b100: begin // FISUB m32int
                                internal_opcode = OP_FSUB;
                                has_push = 1'b1;
                            end
                            3'b101: begin // FISUBR m32int
                                internal_opcode = OP_FSUBR;
                                has_push = 1'b1;
                            end
                            3'b110: begin // FIDIV m32int
                                internal_opcode = OP_FDIV;
                                has_push = 1'b1;
                            end
                            3'b111: begin // FIDIVR m32int
                                internal_opcode = OP_FDIVR;
                                has_push = 1'b1;
                            end
                        endcase
                    end
                end

                //=====================================================
                // DB: Integer operations (16-bit), 80-bit, BCD, control
                //=====================================================
                8'hDB: begin
                    valid = 1'b1;
                    if (mod == 2'b11) begin
                        // Control operations
                        case (modrm)
                            8'hE2: begin // FCLEX
                                internal_opcode = OP_FCLEX;
                                stack_index = 3'd0;
                            end
                            8'hE3: begin // FINIT
                                internal_opcode = OP_FINIT;
                                stack_index = 3'd0;
                            end
                            default: valid = 1'b0;
                        endcase
                    end else begin
                        case (reg_op)
                            3'b000: begin // FILD m32int
                                internal_opcode = OP_FILD32;
                                operand_size = 2'd1; // dword
                                is_integer = 1'b1;
                                has_push = 1'b1;
                            end
                            3'b010: begin // FIST m32int
                                internal_opcode = OP_FIST32;
                                operand_size = 2'd1; // dword
                                is_integer = 1'b1;
                            end
                            3'b011: begin // FISTP m32int
                                internal_opcode = OP_FISTP32;
                                operand_size = 2'd1; // dword
                                is_integer = 1'b1;
                                has_pop = 1'b1;
                            end
                            3'b101: begin // FLD m80real
                                internal_opcode = OP_FLD;
                                operand_size = 2'd3; // tbyte
                                has_push = 1'b1;
                            end
                            3'b111: begin // FSTP m80real
                                internal_opcode = OP_FSTP;
                                operand_size = 2'd3; // tbyte
                                has_pop = 1'b1;
                            end
                            default: valid = 1'b0;
                        endcase
                    end
                end

                //=====================================================
                // DC: Arithmetic operations (64-bit memory or reversed ST(i))
                //=====================================================
                8'hDC: begin
                    valid = 1'b1;
                    if (mod == 2'b11) begin
                        // Reversed register operations: DC C0-FF
                        case (reg_op)
                            3'b000: begin // FADD ST(i), ST(0)
                                internal_opcode = OP_FADD;
                                uses_sti_st0 = 1'b1;
                            end
                            3'b001: begin // FMUL ST(i), ST(0)
                                internal_opcode = OP_FMUL;
                                uses_sti_st0 = 1'b1;
                            end
                            3'b100: begin // FSUBR ST(i), ST(0)
                                internal_opcode = OP_FSUBR;
                                uses_sti_st0 = 1'b1;
                            end
                            3'b101: begin // FSUB ST(i), ST(0)
                                internal_opcode = OP_FSUB;
                                uses_sti_st0 = 1'b1;
                            end
                            3'b110: begin // FDIVR ST(i), ST(0)
                                internal_opcode = OP_FDIVR;
                                uses_sti_st0 = 1'b1;
                            end
                            3'b111: begin // FDIV ST(i), ST(0)
                                internal_opcode = OP_FDIV;
                                uses_sti_st0 = 1'b1;
                            end
                            default: valid = 1'b0;
                        endcase
                    end else begin
                        // Memory operations: 64-bit real
                        operand_size = 2'd2; // qword
                        case (reg_op)
                            3'b000: begin // FADD m64real
                                internal_opcode = OP_FADD;
                                has_push = 1'b1;
                            end
                            3'b001: begin // FMUL m64real
                                internal_opcode = OP_FMUL;
                                has_push = 1'b1;
                            end
                            3'b010: begin // FCOM m64real
                                internal_opcode = OP_FCOM;
                            end
                            3'b011: begin // FCOMP m64real
                                internal_opcode = OP_FCOMP;
                                has_pop = 1'b1;
                            end
                            3'b100: begin // FSUB m64real
                                internal_opcode = OP_FSUB;
                                has_push = 1'b1;
                            end
                            3'b101: begin // FSUBR m64real
                                internal_opcode = OP_FSUBR;
                                has_push = 1'b1;
                            end
                            3'b110: begin // FDIV m64real
                                internal_opcode = OP_FDIV;
                                has_push = 1'b1;
                            end
                            3'b111: begin // FDIVR m64real
                                internal_opcode = OP_FDIVR;
                                has_push = 1'b1;
                            end
                        endcase
                    end
                end

                //=====================================================
                // DD: Load/Store 64-bit, FST/FSTP ST(i), FUCOM
                //=====================================================
                8'hDD: begin
                    valid = 1'b1;
                    if (mod == 2'b11) begin
                        // Register operations
                        case (reg_op)
                            3'b000: begin // FFREE ST(i): DD C0-C7
                                internal_opcode = OP_FFREE;
                            end
                            3'b010: begin // FST ST(i): DD D0-D7
                                internal_opcode = OP_FST;
                            end
                            3'b011: begin // FSTP ST(i): DD D8-DF
                                internal_opcode = OP_FSTP;
                                has_pop = 1'b1;
                            end
                            3'b100: begin // FUCOM ST(i): DD E0-E7
                                internal_opcode = OP_FUCOM;
                            end
                            3'b101: begin // FUCOMP ST(i): DD E8-EF
                                internal_opcode = OP_FUCOMP;
                                has_pop = 1'b1;
                            end
                            default: valid = 1'b0;
                        endcase
                    end else begin
                        // Memory operations: 64-bit real
                        operand_size = 2'd2; // qword
                        case (reg_op)
                            3'b000: begin // FLD m64real
                                internal_opcode = OP_FLD64;
                                has_push = 1'b1;
                            end
                            3'b010: begin // FST m64real
                                internal_opcode = OP_FST64;
                            end
                            3'b011: begin // FSTP m64real
                                internal_opcode = OP_FSTP64;
                                has_pop = 1'b1;
                            end
                            3'b111: begin // FSTSW m16
                                internal_opcode = OP_FSTSW;
                                operand_size = 2'd0; // word
                            end
                            default: valid = 1'b0;
                        endcase
                    end
                end

                //=====================================================
                // DE: Integer ops (16-bit), arithmetic with pop
                //=====================================================
                8'hDE: begin
                    valid = 1'b1;
                    if (mod == 2'b11) begin
                        // Register operations with pop
                        case (reg_op)
                            3'b000: begin // FADDP ST(i), ST(0)
                                internal_opcode = OP_FADDP;
                                uses_sti_st0 = 1'b1;
                                has_pop = 1'b1;
                            end
                            3'b001: begin // FMULP ST(i), ST(0)
                                internal_opcode = OP_FMULP;
                                uses_sti_st0 = 1'b1;
                                has_pop = 1'b1;
                            end
                            3'b011: begin // FCOMPP (if modrm == D9)
                                if (modrm == 8'hD9) begin
                                    internal_opcode = OP_FCOMPP;
                                    has_pop = 1'b1;
                                    stack_index = 3'd1;  // FCOMPP compares ST(0) and ST(1)
                                end else begin
                                    valid = 1'b0;
                                end
                            end
                            3'b100: begin // FSUBP ST(i), ST(0)
                                internal_opcode = OP_FSUBP;
                                uses_sti_st0 = 1'b1;
                                has_pop = 1'b1;
                            end
                            3'b101: begin // FSUBRP ST(i), ST(0)
                                internal_opcode = OP_FSUBRP;
                                uses_sti_st0 = 1'b1;
                                has_pop = 1'b1;
                            end
                            3'b110: begin // FDIVP ST(i), ST(0)
                                internal_opcode = OP_FDIVP;
                                uses_sti_st0 = 1'b1;
                                has_pop = 1'b1;
                            end
                            3'b111: begin // FDIVRP ST(i), ST(0)
                                internal_opcode = OP_FDIVRP;
                                uses_sti_st0 = 1'b1;
                                has_pop = 1'b1;
                            end
                            default: valid = 1'b0;
                        endcase
                    end else begin
                        // Memory operations: 16-bit integer
                        operand_size = 2'd0; // word
                        is_integer = 1'b1;
                        case (reg_op)
                            3'b000: begin // FIADD m16int
                                internal_opcode = OP_FADD;
                                has_push = 1'b1;
                            end
                            3'b001: begin // FIMUL m16int
                                internal_opcode = OP_FMUL;
                                has_push = 1'b1;
                            end
                            3'b010: begin // FICOM m16int
                                internal_opcode = OP_FCOM;
                            end
                            3'b011: begin // FICOMP m16int
                                internal_opcode = OP_FCOMP;
                                has_pop = 1'b1;
                            end
                            3'b100: begin // FISUB m16int
                                internal_opcode = OP_FSUB;
                                has_push = 1'b1;
                            end
                            3'b101: begin // FISUBR m16int
                                internal_opcode = OP_FSUBR;
                                has_push = 1'b1;
                            end
                            3'b110: begin // FIDIV m16int
                                internal_opcode = OP_FDIV;
                                has_push = 1'b1;
                            end
                            3'b111: begin // FIDIVR m16int
                                internal_opcode = OP_FDIVR;
                                has_push = 1'b1;
                            end
                        endcase
                    end
                end

                //=====================================================
                // DF: Integer ops (16/64-bit), BCD, FSTSW AX
                //=====================================================
                8'hDF: begin
                    valid = 1'b1;
                    if (mod == 2'b11) begin
                        // Special operations
                        case (modrm)
                            8'hE0: begin // FSTSW AX
                                internal_opcode = OP_FSTSW;
                                stack_index = 3'd0;
                            end
                            8'hF7: begin // FINCSTP
                                internal_opcode = OP_FINCSTP;
                                stack_index = 3'd7;  // Uses RM field (7)
                            end
                            8'hF6: begin // FDECSTP
                                internal_opcode = OP_FDECSTP;
                                stack_index = 3'd6;  // Uses RM field (6)
                            end
                            default: valid = 1'b0;
                        endcase
                    end else begin
                        case (reg_op)
                            3'b000: begin // FILD m16int
                                internal_opcode = OP_FILD16;
                                operand_size = 2'd0; // word
                                is_integer = 1'b1;
                                has_push = 1'b1;
                            end
                            3'b010: begin // FIST m16int
                                internal_opcode = OP_FIST16;
                                operand_size = 2'd0; // word
                                is_integer = 1'b1;
                            end
                            3'b011: begin // FISTP m16int
                                internal_opcode = OP_FISTP16;
                                operand_size = 2'd0; // word
                                is_integer = 1'b1;
                                has_pop = 1'b1;
                            end
                            3'b100: begin // FBLD m80bcd
                                internal_opcode = OP_FBLD;
                                operand_size = 2'd3; // tbyte
                                is_bcd = 1'b1;
                                has_push = 1'b1;
                            end
                            3'b101: begin // FILD m64int
                                internal_opcode = OP_FILD64;
                                operand_size = 2'd2; // qword
                                is_integer = 1'b1;
                                has_push = 1'b1;
                            end
                            3'b110: begin // FBSTP m80bcd
                                internal_opcode = OP_FBSTP;
                                operand_size = 2'd3; // tbyte
                                is_bcd = 1'b1;
                                has_pop = 1'b1;
                            end
                            3'b111: begin // FISTP m64int
                                internal_opcode = OP_FISTP64;
                                operand_size = 2'd2; // qword
                                is_integer = 1'b1;
                                has_pop = 1'b1;
                            end
                            default: valid = 1'b0;
                        endcase
                    end
                end

                //=====================================================
                // 9B: FWAIT (may be standalone or prefix)
                //=====================================================
                8'h9B: begin
                    internal_opcode = OP_FWAIT;
                    valid = 1'b1;
                end

                default: begin
                    valid = 1'b0;
                end
            endcase
        end
    end

endmodule
