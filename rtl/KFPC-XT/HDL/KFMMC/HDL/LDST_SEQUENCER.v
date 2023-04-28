//
// LD/ST microsequencer
//
// MIT License
//
// Copyright (c) 2023 kitune-san
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

module LDST_SEQUENCER (
    input           clock,
    input           clock_enable,
    input           reset,

    output  [15:0]  instruction_bus_address,
    input   [12:0]  instruction_bus_data,

    output  [7:0]   io_bus_address,
    output  [7:0]   io_bus_data_out,
    input   [7:0]   io_bus_data_in,
    output          io_bus_out,
    output          io_bus_in
);

    //
    // Instructions
    // x = don't care
    //
    wire    transfer        = ~|instruction_bus_data[11:10];
    wire    immediate       = instruction_bus_data[9];
    // 00i0 : LOAD (i=immediate flag)
    wire    load            = transfer & ~instruction_bus_data[8];
    // 00x1 : STORE
    wire    store           = transfer &  instruction_bus_data[8];
    wire    subroutine      = ~instruction_bus_data[11] & instruction_bus_data[10];
    // 01x0 : CALL
    wire    call            = subroutine & ~instruction_bus_data[8];
    // 01x1 : RET
    wire    ret             = subroutine &  instruction_bus_data[8];
    // 1ccc : JUMP (c=condition)
    wire    jump            = instruction_bus_data[11];


    //
    // Assigned I/O address
    //
    wire    internal_select = ~|instruction_bus_data[7:2];
    wire    select_reg_a    = internal_select & (instruction_bus_data[1:0] == 2'b00);
    wire    select_reg_b    = internal_select & (instruction_bus_data[1:0] == 2'b01);
    wire    select_flags    = internal_select & (instruction_bus_data[1:0] == 2'b10);
    wire    select_alu      = internal_select & (instruction_bus_data[1:0] == 2'b11);


    //
    // Work register
    //
    wire    [7:0]   load_data;
    reg     [7:0]   reg_work;

    always @(posedge clock, posedge reset) begin
        if (reset)
            reg_work    <= 8'h00;
        else if (clock_enable & load)
            reg_work    <= immediate ? instruction_bus_data[7:0] : load_data;
        else
            reg_work    <= reg_work;
    end


    //
    // ALU
    //
    reg     [7:0]   reg_a;
    reg     [7:0]   reg_b;
    reg             overflow_flag;
    reg             carry_flag;
    reg             zero_flag;
    reg     [7:0]   alu_op;
    wire            alu_wb;
    wire            alu_wb_overflow_flag;
    wire            alu_wb_carry_flag;
    wire            alu_wb_zero_flag;

    // Registers
    always @(posedge clock, posedge reset) begin
        if (reset)
            reg_a   <= 8'h00;
        else if (clock_enable & store & select_reg_a)
            reg_a   <= reg_work;
        else
            reg_a   <= reg_a;
    end

    wire    [7:0]   reg_a_load = select_reg_a ? reg_a : 8'h00;

    always @(posedge clock, posedge reset) begin
        if (reset)
            reg_b   <= 8'h00;
        else if (clock_enable & store & select_reg_b)
            reg_b   <= reg_work;
        else
            reg_b   <= reg_b;
    end

    wire    [7:0]   reg_b_load = select_reg_b ? reg_b : 8'h00;

    // Flags
    always @(posedge clock, posedge reset) begin
        if (reset)
            {overflow_flag, carry_flag, zero_flag} <= 3'b000;
        else if (clock_enable & store & select_flags)
            {overflow_flag, carry_flag, zero_flag} <= reg_work[2:0];
        else if (clock_enable & alu_wb)
            {overflow_flag, carry_flag, zero_flag} <= {alu_wb_overflow_flag, alu_wb_carry_flag, alu_wb_zero_flag};
        else
            {overflow_flag, carry_flag, zero_flag} <= {overflow_flag, carry_flag, zero_flag};
    end

    wire    [7:0]   flags       = {5'b00000, overflow_flag, carry_flag, zero_flag};
    wire    [7:0]   flags_load  = select_flags ? flags : 8'h00;

    // Op code
    always @(posedge clock, posedge reset) begin
        if (reset)
            alu_op  <= 8'h00;
        else if (clock_enable & store & select_alu)
            alu_op  <= reg_work;
        else
            alu_op  <= alu_op;
    end

    // Execute op code
    wire    alu_op_and                      = alu_op[7:5] == 3'b000;
    wire    alu_op_or                       = alu_op[7:5] == 3'b001;
    wire    alu_op_xor                      = alu_op[7:5] == 3'b010;
    wire    alu_op_add                      = alu_op[7:5] == 3'b100;
    wire    alu_op_shl                      = alu_op[7:5] == 3'b101;
    wire    alu_op_shr                      = alu_op[7:6] == 2'b11;

    wire    alu_opf_op2_zero                = alu_op[3];
    wire    alu_opf_not                     = alu_op[2];
    wire    alu_opf_neg                     = alu_op[1];
    wire    alu_opf_carry                   = alu_op[0];

    wire    update_carry                    = alu_op[7];
    wire    update_overflow                 = alu_op_add;

    wire    [7:0]   alu_op1                 = reg_a;
    wire    [7:0]   alu_op2_tmp             = alu_opf_op2_zero ? 8'h00 : reg_b;
    wire    [7:0]   alu_op2                 = alu_opf_neg ? ~alu_op2_tmp : alu_op2_tmp;
    wire            alu_carry               = alu_opf_neg ? ~(alu_opf_carry & ~carry_flag) : (alu_opf_carry & carry_flag);

    wire    [7:0]   alu_result_and          = alu_op_and  ? (alu_op1 & alu_op2) : 8'h00;
    wire    [7:0]   alu_result_or           = alu_op_or   ? (alu_op1 | alu_op2) : 8'h00;
    wire    [7:0]   alu_result_xor          = alu_op_xor  ? (alu_op1 ^ alu_op2) : 8'h00;

    wire    [7:0]   alu_result_add;
    wire            alu_result_add_carry;
    assign  {alu_result_add_carry, alu_result_add}  = alu_op_add ? ({1'b0, alu_op1} + {1'b0, alu_op2} + alu_carry) : 9'h000;
    wire    alu_result_add_overflow                 = alu_op_add & ~(alu_op1[7] ^ alu_op2[7]) & (alu_op1[7] ^ alu_result_add[7]);

    wire    [7:0]   alu_result_shl;
    wire            alu_result_shl_carry;
    assign  {alu_result_shl_carry, alu_result_shl}  = alu_op_shl ? {alu_op1, alu_carry} : 9'h000;

    wire    [7:0]   alu_result_shr;
    wire            alu_result_shr_carry;
    assign  {alu_result_shr, alu_result_shr_carry}  = alu_op_shr ? {(alu_carry | (alu_op[5] & alu_op1[7])), alu_op1} : 9'h000;

    wire    [7:0]   alu_result_mux          = alu_result_and | alu_result_or | alu_result_xor | alu_result_add | alu_result_shl | alu_result_shr;
    wire    [7:0]   alu_result              = alu_opf_not ? ~alu_result_mux : alu_result_mux;
    assign          alu_wb_carry_flag       = (~update_carry & carry_flag) | alu_result_add_carry | alu_result_shl_carry | alu_result_shr_carry;
    assign          alu_wb_overflow_flag    = (~update_overflow & overflow_flag) | alu_result_add_overflow;
    assign          alu_wb_zero_flag        = ~|alu_result;

    // Writeback
    assign          alu_wb                  = io_bus_in & select_alu;
    wire    [7:0]   alu_load                = select_alu ? alu_result : 8'h00;


    //
    // Sequencer
    //
    reg     [15:0]  instruction_counter;
    wire    [15:0]  next_step;
    wire            jump_instruction;
    wire    [15:0]  jump_instruction_count;

    assign  next_step = instruction_counter + 1'b1;

    always @(posedge clock, posedge reset) begin
        if (reset)
            instruction_counter <= 16'h0000;
        else if (clock_enable)
            if (~jump_instruction)
                instruction_counter <= next_step;
            else
                instruction_counter <= jump_instruction_count;
        else
            instruction_counter <= instruction_counter;
    end

    // Call stack
    reg     [15:0]  stack[0:3];

    always @(posedge clock, posedge reset) begin
        if (reset) begin
            stack[0]    <= 16'h0000;
            stack[1]    <= 16'h0000;
            stack[2]    <= 16'h0000;
            stack[3]    <= 16'h0000;
        end
        else if (clock_enable & call) begin
            stack[0]    <= next_step;
            stack[1]    <= stack[0];
            stack[2]    <= stack[1];
            stack[3]    <= stack[2];
        end
        else if (clock_enable & ret) begin
            stack[0]    <= stack[1];
            stack[1]    <= stack[2];
            stack[2]    <= stack[3];
            stack[3]    <= 16'h0000;
        end
        else begin
            stack[0]    <= stack[0];
            stack[1]    <= stack[1];
            stack[2]    <= stack[2];
            stack[3]    <= stack[3];
        end
    end

    // Jump/Subroutine
    assign  jump_instruction = (jump & (|(flags[2:0] & instruction_bus_data[10:8]) | ~|instruction_bus_data[10:8])) | call | ret;
    assign  jump_instruction_count = ret ? stack[0] : {reg_work, instruction_bus_data[7:0]};


    //
    // Bus
    //
    assign  instruction_bus_address = instruction_counter;
    assign  load_data               = internal_select ? (reg_a_load | reg_b_load | flags_load | alu_load) : io_bus_data_in;
    assign  io_bus_address          = instruction_bus_data[7:0];
    assign  io_bus_data_out         = reg_work;
    assign  io_bus_in               = load & ~immediate;
    assign  io_bus_out              = store;

endmodule

