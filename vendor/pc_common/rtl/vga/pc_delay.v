//============================================================================
//
//  Plain delay line: q is d, N clocks later (N = 0 is a wire).
//
//  The VGA renderers use it to follow a data path that takes longer than the
//  BRAM it was built for (DATA_EXTRA): everything the data does
//  not travel with is delayed by the same number of clocks.
//
//  The lines are a few dozen bits at most: kept as registers (no shift-register
//  recognition), because a recognised line takes a whole M10K block.
//
//============================================================================

`default_nettype wire

(* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *)
module pc_delay #(
    parameter W    = 1,
    parameter N    = 1,
    parameter INIT = 0
) (
    input  wire         clk,
    input  wire         reset,
    input  wire [W-1:0] d,
    output wire [W-1:0] q
);
    generate
        if (N == 0) begin : g_wire
            assign q = d;
        end else begin : g_line
            reg [W-1:0] r [0:N-1];
            integer i;
            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    for (i = 0; i < N; i = i + 1) r[i] <= INIT;
                end else begin
                    r[0] <= d;
                    for (i = 1; i < N; i = i + 1) r[i] <= r[i-1];
                end
            end
            assign q = r[N-1];
        end
    endgenerate
endmodule
