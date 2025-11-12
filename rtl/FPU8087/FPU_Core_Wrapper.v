// Copyright 2025, Waldo Alvarez, https://pipflow.com
`timescale 1ns / 1ps

//=====================================================================
// FPU Core Wrapper
//
// Wraps the FPU8087 core to work with the FPU_CPU_Interface.
// Translates interface operations into FPU core operations.
//=====================================================================

module FPU_Core_Wrapper(
    input wire clk,
    input wire reset,

    // From Interface
    input wire        if_start,
    input wire [7:0]  if_operation,
    input wire [7:0]  if_operand_select,
    input wire [79:0] if_operand_data,

    // To Interface
    output reg        if_operation_complete,
    output reg [79:0] if_result_data,
    output reg [15:0] if_status,
    output reg        if_error,

    // Control
    input wire [15:0] if_control_reg,
    input wire        if_control_update,

    // Memory Operation Format (from interface)
    input wire        if_has_memory_op,
    input wire [1:0]  if_operand_size,
    input wire        if_is_integer,
    input wire        if_is_bcd
);

    //=================================================================
    // Internal Registers
    //=================================================================

    // Stack simulation (simplified for testing)
    reg [79:0] stack [0:7];
    reg [2:0] stack_ptr;

    // Status register
    reg [15:0] status_reg;
    reg [15:0] control_reg;

    // Operation state
    reg [7:0] operation_cycles;
    reg operation_active;

    //=================================================================
    // Initialize
    //=================================================================

    integer i;
    initial begin
        stack_ptr = 3'd0;
        for (i = 0; i < 8; i = i + 1) begin
            stack[i] = 80'h0;
        end
        status_reg = 16'h0000;
        control_reg = 16'h037F;
        operation_cycles = 8'd0;
        operation_active = 1'b0;
        if_operation_complete = 1'b0;
        if_result_data = 80'h0;
        if_status = 16'h0000;
        if_error = 1'b0;
    end

    //=================================================================
    // Operation Decoder and Executor
    //=================================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            stack_ptr <= 3'd0;
            for (i = 0; i < 8; i = i + 1) begin
                stack[i] <= 80'h0;
            end
            status_reg <= 16'h0000;
            control_reg <= 16'h037F;
            operation_cycles <= 8'd0;
            operation_active <= 1'b0;
            if_operation_complete <= 1'b0;
            if_result_data <= 80'h0;
            if_status <= 16'h0000;
            if_error <= 1'b0;
        end else begin
            // Update control register
            if (if_control_update) begin
                control_reg <= if_control_reg;
            end

            // Handle operation start
            if (if_start && !operation_active) begin
                operation_active <= 1'b1;
                if_operation_complete <= 1'b0;

                // Decode operation and set execution cycles
                case (if_operation)
                    8'hD8: begin // FADD, FSUB, FMUL, FDIV
                        case (if_operand_select[5:3])
                            3'b000: operation_cycles <= 8'd70;  // FADD
                            3'b100: operation_cycles <= 8'd70;  // FSUB
                            3'b001: operation_cycles <= 8'd130; // FMUL
                            3'b110: operation_cycles <= 8'd215; // FDIV
                            default: operation_cycles <= 8'd10;
                        endcase
                    end

                    8'hD9: begin // FLD, FST, transcendentals
                        if (if_operand_select >= 8'hE8 && if_operand_select <= 8'hEF) begin
                            // Constants
                            operation_cycles <= 8'd4;
                            // Push constant onto stack
                            stack_ptr <= stack_ptr - 1;
                            case (if_operand_select)
                                8'hE8: stack[stack_ptr - 1] <= 80'h3FFF8000000000000000; // 1.0
                                8'hEE: stack[stack_ptr - 1] <= 80'h00000000000000000000; // 0.0
                                8'hEB: stack[stack_ptr - 1] <= 80'h4000C90FDAA22168C235; // π
                                default: stack[stack_ptr - 1] <= 80'h0;
                            endcase
                        end else if (if_operand_select == 8'hFA) begin
                            // FSQRT
                            operation_cycles <= 8'd120;
                        end else if (if_operand_select == 8'hFE) begin
                            // FSIN
                            operation_cycles <= 8'd250;
                        end else if (if_operand_select == 8'hFF) begin
                            // FCOS
                            operation_cycles <= 8'd250;
                        end else if (if_operand_select == 8'hF2) begin
                            // FPTAN
                            operation_cycles <= 8'd300;
                        end else if (if_operand_select == 8'hF3) begin
                            // FPATAN
                            operation_cycles <= 8'd300;
                        end else begin
                            // FLD or other
                            operation_cycles <= 8'd5;
                            if (if_operand_select[5:3] == 3'b000) begin
                                // FLD - push data
                                stack_ptr <= stack_ptr - 1;
                                stack[stack_ptr - 1] <= if_operand_data;
                            end else if (if_operand_select[5:3] == 3'b010) begin
                                // FST - prepare result
                                if_result_data <= stack[0]; // ST(0)
                            end
                        end
                    end

                    8'hDB: begin // FINIT, FLD m80, FSTP m80
                        if (if_operand_select == 8'hE3) begin
                            // FINIT
                            operation_cycles <= 8'd50;
                            stack_ptr <= 3'd0;
                            for (i = 0; i < 8; i = i + 1) begin
                                stack[i] <= 80'h0;
                            end
                            status_reg <= 16'h0000;
                        end else if (if_operand_select[5:3] == 3'b101) begin
                            // FLD m80real
                            operation_cycles <= 8'd6;
                            stack_ptr <= stack_ptr - 1;
                            stack[stack_ptr - 1] <= if_operand_data;
                        end else if (if_operand_select[5:3] == 3'b111) begin
                            // FSTP m80real
                            operation_cycles <= 8'd6;
                            if_result_data <= stack[0];
                            stack_ptr <= stack_ptr + 1; // Pop
                        end else begin
                            operation_cycles <= 8'd10;
                        end
                    end

                    8'hDD: begin // FLD m64, FST m64, FSTSW
                        if (if_operand_select[5:3] == 3'b000) begin
                            // FLD m64real
                            operation_cycles <= 8'd5;
                            stack_ptr <= stack_ptr - 1;
                            stack[stack_ptr - 1] <= if_operand_data;
                        end else if (if_operand_select[5:3] == 3'b010) begin
                            // FST m64real
                            operation_cycles <= 8'd8;
                            if_result_data <= stack[0];
                        end else if (if_operand_select[5:3] == 3'b111) begin
                            // FSTSW m16
                            operation_cycles <= 8'd3;
                            if_result_data <= {64'h0, status_reg};
                        end else begin
                            operation_cycles <= 8'd10;
                        end
                    end

                    8'hDF: begin // FSTSW AX
                        if (if_operand_select == 8'hE0) begin
                            // FSTSW AX
                            operation_cycles <= 8'd3;
                            if_result_data <= {64'h0, status_reg};
                        end else begin
                            operation_cycles <= 8'd10;
                        end
                    end

                    default: begin
                        operation_cycles <= 8'd10;
                    end
                endcase

                // Update status register
                status_reg[15] <= 1'b1; // Set busy bit
                status_reg[13:11] <= stack_ptr; // Stack top pointer
            end

            // Execute operation (count down cycles)
            if (operation_active) begin
                if (operation_cycles > 0) begin
                    operation_cycles <= operation_cycles - 1;
                end else begin
                    // Operation complete
                    operation_active <= 1'b0;
                    if_operation_complete <= 1'b1;
                    status_reg[15] <= 1'b0; // Clear busy bit
                end
            end else begin
                if_operation_complete <= 1'b0;
            end

            // Always output current status
            if_status <= status_reg;
        end
    end

endmodule
