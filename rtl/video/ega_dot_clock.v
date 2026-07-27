//============================================================================
//
//  PCXT MiSTer EGA dot clock generator
//
//  A real IBM EGA carries two dot clock oscillators and picks between them
//  from bit 2 of the Miscellaneous Output register:
//
//    bit 2 = 0 -> 14.318181 MHz (157_500_000/11), CGA compatible modes
//    bit 2 = 1 -> 16.257000 MHz, ECD 350 line modes and MDA compatible mode 7
//
//  clk is the video clock, 315/11 MHz = 28.636363 MHz.  The 14.318181 MHz
//  clock is an exact divide by two.  16.257 MHz is not an integer fraction of
//  it, so it is produced by an accumulator whose long term average is exact:
//
//    16_257_000 / (315_000_000/11) = 59_609 / 105_000   (gcd reduced)
//
//============================================================================

`default_nettype wire

// ACC_W and the two constants below are sized together: ACC_W is
// ceil(log2(NCO_MOD + NCO_INC)) and the literals carry ACC_W+1 bits.
module ega_dot_clock #(
    parameter integer   ACC_W   = 18,
    parameter [ACC_W:0] NCO_INC = 19'd59609,
    parameter [ACC_W:0] NCO_MOD = 19'd105000
) (
    input  wire clk,
    input  wire reset,
    input  wire clock_select,   // Miscellaneous Output bit 2
    output wire ce_dot,         // one pulse per dot
    output wire ce_dot_early,   // one clock before ce_dot
    output wire ce_dot_2x,      // twice the dot rate, valid when clock_select == 0
    output reg  dot_toggle      // flips once per dot, for the 57.272 MHz domain
);

    reg             div2   = 1'b0;
    reg [ACC_W-1:0] acc    = {ACC_W{1'b0}};
    reg             ce_nco = 1'b0;
    reg             sel_q  = 1'b0;

    wire [ACC_W:0] acc_next = {1'b0, acc} + NCO_INC;
    wire [ACC_W:0] acc_sub  = acc_next - NCO_MOD;
    wire           acc_wrap = (acc_next >= NCO_MOD);

    // The divide by two path keeps the exact phase the core had before the
    // second clock existed, so the render pipeline delay constants in ega_top
    // do not need to be retuned.
    assign ce_dot    = clock_select ? ce_nco : div2;
    assign ce_dot_2x = ~clock_select;

    // One clock of warning before each dot.  Consumers with a fixed pipeline
    // latency need it because dots are one or two clocks apart on the NCO
    // path, so "two clocks after the character tick" is not always the next
    // dot the way it is on the divide by two path.
    assign ce_dot_early = clock_select ? acc_wrap : ~div2;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            div2       <= 1'b0;
            acc        <= {ACC_W{1'b0}};
            ce_nco     <= 1'b0;
            sel_q      <= 1'b0;
            dot_toggle <= 1'b0;
        end else begin
            sel_q <= clock_select;

            if (clock_select != sel_q) begin
                // Restart both generators on a mode set so no short dot is
                // emitted across the boundary.
                div2   <= 1'b0;
                acc    <= {ACC_W{1'b0}};
                ce_nco <= 1'b0;
            end else begin
                div2   <= ~div2;
                acc    <= acc_wrap ? acc_sub[ACC_W-1:0] : acc_next[ACC_W-1:0];
                ce_nco <= acc_wrap;
            end

            if (ce_dot)
                dot_toggle <= ~dot_toggle;
        end
    end

endmodule
