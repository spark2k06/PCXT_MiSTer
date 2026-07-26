//============================================================================
//
//  MCGA mode 13h state gate
//
//============================================================================

module mcga_mode13_ctrl(
    input  wire clk,
    input  wire reset,
    input  wire mcga_enabled,
    input  wire mode13_set,
    input  wire mode13_clear,
    output reg  mcga_mode13_active
);

    always @(posedge clk or posedge reset) begin
        if (reset)
            mcga_mode13_active <= 1'b0;
        else if (!mcga_enabled || mode13_clear)
            mcga_mode13_active <= 1'b0;
        else if (mode13_set)
            mcga_mode13_active <= 1'b1;
    end

endmodule
