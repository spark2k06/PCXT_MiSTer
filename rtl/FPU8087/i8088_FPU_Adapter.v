// i8088_FPU_Adapter.v
// Adaptador para integrar FPU8087 con el CPU i8088 del proyecto PCXT_MiSTer
// Autor: Integración para PCXT_MiSTer
// Fecha: 2025-11-12
//
// Este módulo actúa como puente entre el CPU i8088 y la FPU8087_Integrated,
// detectando instrucciones ESC (D8h-DFh) del prefetch queue y manejando
// la comunicación con el coprocesador matemático.

`timescale 1ns / 1ps

module i8088_FPU_Adapter(
    // System
    input wire clk,
    input wire reset,

    // Interfaz con i8088 - Señales de monitoreo
    input wire [7:0]  cpu_pfq_top_byte,        // Byte actual del prefetch queue
    input wire        cpu_pfq_empty,           // Prefetch queue vacío
    input wire [15:0] cpu_pfq_addr,            // Dirección del prefetch
    input wire [7:0]  cpu_data_bus_in,         // Bus de datos del CPU (para ModR/M)
    input wire [19:0] cpu_addr_bus,            // Bus de direcciones
    input wire        cpu_read,                // CPU leyendo
    input wire        cpu_write,               // CPU escribiendo

    // Interfaz con i8088 - Control
    output reg        fpu_cpu_wait,            // Señal WAIT para el CPU (cuando FPU está ocupada)
    output reg [7:0]  fpu_data_to_cpu,         // Datos de FPU a CPU

    // Interfaz de memoria para FPU (acceso a operandos en memoria)
    output wire [19:0] fpu_mem_addr,
    input wire [15:0]  fpu_mem_data_in,
    output wire [15:0] fpu_mem_data_out,
    output wire        fpu_mem_read,
    output wire        fpu_mem_write,
    input wire         fpu_mem_ready,

    // Debug
    output wire        fpu_detected_esc,
    output wire        fpu_active,
    output wire [15:0] fpu_status_word
);

    //=========================================================================
    // Detección de instrucciones ESC (D8h-DFh)
    //=========================================================================

    wire is_esc_instruction;
    assign is_esc_instruction = (cpu_pfq_top_byte[7:3] == 5'b11011) && !cpu_pfq_empty;
    assign fpu_detected_esc = is_esc_instruction;

    //=========================================================================
    // Máquina de estados para captura de instrucción
    //=========================================================================

    localparam [2:0] STATE_IDLE         = 3'd0;
    localparam [2:0] STATE_CAPTURE_ESC  = 3'd1;
    localparam [2:0] STATE_WAIT_MODRM   = 3'd2;
    localparam [2:0] STATE_SEND_TO_FPU  = 3'd3;
    localparam [2:0] STATE_WAIT_FPU     = 3'd4;
    localparam [2:0] STATE_COMPLETE     = 3'd5;

    reg [2:0] state, next_state;
    reg [7:0] captured_opcode;
    reg [7:0] captured_modrm;
    reg instruction_valid;

    //=========================================================================
    // Señales de la FPU
    //=========================================================================

    wire        fpu_instr_valid;
    wire [7:0]  fpu_opcode;
    wire [7:0]  fpu_modrm;
    wire        fpu_instr_ack;

    wire        fpu_data_write;
    wire        fpu_data_read;
    wire [2:0]  fpu_data_size;
    wire [79:0] fpu_data_in;
    wire [79:0] fpu_data_out;
    wire        fpu_data_ready;

    wire        fpu_busy;
    wire        fpu_ready;
    wire [15:0] fpu_control_word;
    wire        fpu_ctrl_write;
    wire        fpu_exception;
    wire        fpu_irq;
    wire        fpu_wait_signal;

    assign fpu_status_word = fpu_status_word_internal;
    assign fpu_active = fpu_busy;

    //=========================================================================
    // Asignaciones de señales
    //=========================================================================

    assign fpu_instr_valid = (state == STATE_SEND_TO_FPU);
    assign fpu_opcode = captured_opcode;
    assign fpu_modrm = captured_modrm;

    // Control de memoria (simplificado por ahora)
    assign fpu_mem_addr = 20'h0;
    assign fpu_mem_data_out = 16'h0;
    assign fpu_mem_read = 1'b0;
    assign fpu_mem_write = 1'b0;

    // Control Word por defecto (sin excepciones enmascaradas)
    assign fpu_control_word = 16'h037F;  // Control word estándar del 8087
    assign fpu_ctrl_write = 1'b0;

    // Datos (por ahora simplificado)
    assign fpu_data_in = 80'h0;
    assign fpu_data_write = 1'b0;
    assign fpu_data_read = 1'b0;
    assign fpu_data_size = 3'd0;
    assign fpu_wait_signal = 1'b0;

    //=========================================================================
    // Máquina de estados
    //=========================================================================

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;

        case (state)
            STATE_IDLE: begin
                if (is_esc_instruction) begin
                    next_state = STATE_CAPTURE_ESC;
                end
            end

            STATE_CAPTURE_ESC: begin
                // Capturamos el opcode ESC
                next_state = STATE_WAIT_MODRM;
            end

            STATE_WAIT_MODRM: begin
                // Esperamos a que el siguiente byte (ModR/M) esté disponible
                if (!cpu_pfq_empty) begin
                    next_state = STATE_SEND_TO_FPU;
                end
            end

            STATE_SEND_TO_FPU: begin
                // Enviamos la instrucción a la FPU
                if (fpu_instr_ack) begin
                    next_state = STATE_WAIT_FPU;
                end
            end

            STATE_WAIT_FPU: begin
                // Esperamos a que la FPU complete la operación
                if (!fpu_busy && fpu_ready) begin
                    next_state = STATE_COMPLETE;
                end
            end

            STATE_COMPLETE: begin
                next_state = STATE_IDLE;
            end

            default: next_state = STATE_IDLE;
        endcase
    end

    //=========================================================================
    // Lógica de captura y control
    //=========================================================================

    always @(posedge clk) begin
        if (reset) begin
            captured_opcode <= 8'h00;
            captured_modrm <= 8'h00;
            instruction_valid <= 1'b0;
            fpu_cpu_wait <= 1'b0;
            fpu_data_to_cpu <= 8'h00;
        end else begin
            case (state)
                STATE_IDLE: begin
                    instruction_valid <= 1'b0;
                    fpu_cpu_wait <= 1'b0;
                end

                STATE_CAPTURE_ESC: begin
                    // Capturamos el opcode ESC
                    captured_opcode <= cpu_pfq_top_byte;
                end

                STATE_WAIT_MODRM: begin
                    // Capturamos el byte ModR/M
                    if (!cpu_pfq_empty) begin
                        captured_modrm <= cpu_pfq_top_byte;
                    end
                end

                STATE_SEND_TO_FPU: begin
                    instruction_valid <= 1'b1;
                end

                STATE_WAIT_FPU: begin
                    // Activamos WAIT si la FPU está ocupada
                    fpu_cpu_wait <= fpu_busy;
                    instruction_valid <= 1'b0;
                end

                STATE_COMPLETE: begin
                    fpu_cpu_wait <= 1'b0;
                end
            endcase
        end
    end

    //=========================================================================
    // Instancia de FPU8087_Integrated
    //=========================================================================

    wire [15:0] fpu_status_word_internal;

    FPU8087_Integrated fpu_core (
        // Clock and Reset
        .clk(clk),
        .reset(reset),

        // CPU Side Interface - Instruction
        .cpu_fpu_instr_valid(fpu_instr_valid),
        .cpu_fpu_opcode(fpu_opcode),
        .cpu_fpu_modrm(fpu_modrm),
        .cpu_fpu_instr_ack(fpu_instr_ack),

        // CPU Side Interface - Data Transfer
        .cpu_fpu_data_write(fpu_data_write),
        .cpu_fpu_data_read(fpu_data_read),
        .cpu_fpu_data_size(fpu_data_size),
        .cpu_fpu_data_in(fpu_data_in),
        .cpu_fpu_data_out(fpu_data_out),
        .cpu_fpu_data_ready(fpu_data_ready),

        // CPU Side Interface - Status and Control
        .cpu_fpu_busy(fpu_busy),
        .cpu_fpu_status_word(fpu_status_word_internal),
        .cpu_fpu_control_word(fpu_control_word),
        .cpu_fpu_ctrl_write(fpu_ctrl_write),
        .cpu_fpu_exception(fpu_exception),
        .cpu_fpu_irq(fpu_irq),

        // CPU Side Interface - Synchronization
        .cpu_fpu_wait(fpu_wait_signal),
        .cpu_fpu_ready(fpu_ready)
    );

endmodule
