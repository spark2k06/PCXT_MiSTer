//============================================================================
//
//  VGA mode 13h state gate
//
//============================================================================

module vga_mode13_ctrl(
    input  wire clk,
    input  wire reset,
    input  wire vga_enabled,
    input  wire mode13_set,
    input  wire mode13_clear,
    output reg  vga_mode13_active
);

    always @(posedge clk or posedge reset) begin
        if (reset)
            vga_mode13_active <= 1'b0;
        else if (!vga_enabled || mode13_clear)
            vga_mode13_active <= 1'b0;
        else if (mode13_set)
            vga_mode13_active <= 1'b1;
    end

endmodule
