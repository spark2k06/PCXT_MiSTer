//
// Tandy_Scancode_Converter
//
// Written by kitune-san
//
module Tandy_Scancode_Converter (
    input   logic           clock,
    input   logic           reset,

    input   logic   [7:0]   scancode,
    input   logic           keybord_irq,
    output  logic   [7:0]   convert_data
);

    logic   e0_temp;
    logic   e0;
    logic   prev_keybord_irq;
    logic   keybord_irq_posedge;
    logic   keybord_irq_negedge;

    function logic [6:0] tandy_code_converter (input [6:0] code, input e0_flag);
        casez ({e0_flag, code})
            {1'b1, 7'h48}:  tandy_code_converter = 7'h29;   // UP
            {1'b1, 7'h4B}:  tandy_code_converter = 7'h2B;   // LEFT
            {1'b1, 7'h50}:  tandy_code_converter = 7'h4A;   // DOWN
            {1'b1, 7'h4D}:  tandy_code_converter = 7'h4E;   // RIGHT
            {1'b0, 7'h4A}:  tandy_code_converter = 7'h53;   // Numeric key '-'
            {1'b0, 7'h4E}:  tandy_code_converter = 7'h55;   // Numeric key '+'
            {1'b0, 7'h53}:  tandy_code_converter = 7'h56;   // Numeric key '.'
            {1'b1, 7'h1C}:  tandy_code_converter = 7'h57;   // Enter
            {1'b1, 7'h47}:  tandy_code_converter = 7'h58;   // HOME
            {1'b?, 7'h57}:  tandy_code_converter = 7'h59;   // F11
            {1'b?, 7'h58}:  tandy_code_converter = 7'h5A;   // F12
            default:
                tandy_code_converter = code;
        endcase
    endfunction

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            prev_keybord_irq <= 1'b0;
        else
            prev_keybord_irq <= keybord_irq;
    end

    assign  keybord_irq_posedge = ~prev_keybord_irq & keybord_irq;
    assign  keybord_irq_negedge = prev_keybord_irq & ~keybord_irq;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            e0      <= 1'b0;
            e0_temp <= 1'b0;
        end
        else if (keybord_irq_posedge) begin
            e0      <= e0;
            if (scancode == 8'hE0)
                e0_temp <= 1'b1;
            else
                e0_temp <= 1'b0;
        end
        else if (keybord_irq_negedge) begin
            e0      <= e0_temp;
            e0_temp <= 1'b0;
        end
        else begin
            e0      <= e0;
            e0_temp <= e0_temp;
        end
    end

    assign  convert_data    = {scancode[7], tandy_code_converter(scancode[6:0], e0)};

endmodule
