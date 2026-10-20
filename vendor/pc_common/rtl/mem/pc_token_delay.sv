//
// Token delay line: remembers that something was requested and says so again N
// steps later, in the same order, with a small payload that travels along.
//
// A step is a clock (adv tied high) or a dot enable of the video pipeline (adv =
// ce_pix). Which step a request belongs to (its origin T) is the one thing the
// timing of everything downstream depends on, so it is explicit:
//
//   ANCHOR_NEXT  T is the first step strictly after the clock of the request
//                (a graphics fetch asked one clock ahead of its dot)
//   ANCHOR_PREV  T is the last step strictly before the clock of the request (a
//                text cell asked one clock after the character tick)
//   ANCHOR_THIS  T is the clock of the request, which has to be a step (a glyph
//                asked on the very step that delivered its cell), or any clock
//                when adv is tied high
//
// The token is in stage 0 right after step T and in stage N-1 right after step
// T+N-1; exit_now is high on step T+N, together with the payload (exit_pay), so
// everything that has to happen "on the step" (popping the answer, capturing
// it into a register that is visible after the step) can use it. At most one
// token per step.
//
// The lines are a few dozen bits at most: kept as registers (no shift-register
// recognition), because a recognised line takes a whole M10K block.
//
(* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *)
module pc_token_delay #(
    parameter int N      = 16,
    parameter int PW     = 1,
    parameter int ANCHOR = 0        // 0 NEXT, 1 PREV, 2 THIS
) (
    input  logic          clk,
    input  logic          reset,
    input  logic          clear,           // forget everything in flight
    input  logic          adv,
    input  logic          tok_in,
    input  logic [PW-1:0] pay_in,
    output logic          exit_now,
    output logic [PW-1:0] exit_pay
);
    logic          pend;
    logic [PW-1:0] pend_pay;
    logic          tok [N];
    logic [PW-1:0] pay [N];

    assign exit_now = adv & tok[N-1];
    assign exit_pay = pay[N-1];

    // The token that enters at this edge, and the stage it goes to
    wire enter_next = (ANCHOR == 0) & adv & pend;                 // from the pending slot
    wire enter_this = (ANCHOR == 2) & tok_in;                     // at this edge, stage 0
    wire enter_prev = (ANCHOR == 1) & tok_in;                     // stage 0, or 1 if this edge is a step

    always_ff @(posedge clk) begin
        if (reset || clear) begin
            pend <= 1'b0;
            pend_pay <= '0;
            for (int i = 0; i < N; i++) tok[i] <= 1'b0;
        end
        else begin
            if (adv) begin
                for (int i = 1; i < N; i++) begin
                    tok[i] <= tok[i-1];
                    pay[i] <= pay[i-1];
                end
                tok[0] <= enter_next | enter_this;
                pay[0] <= enter_next ? pend_pay : pay_in;
                if (enter_prev) begin           // this edge is a step: already one step past T
                    tok[1] <= 1'b1;
                    pay[1] <= pay_in;
                    tok[0] <= 1'b0;
                end
                if (ANCHOR == 0) pend <= 1'b0;
            end
            else if (enter_prev) begin
                tok[0] <= 1'b1;
                pay[0] <= pay_in;
            end
            // ANCHOR_NEXT: wait for the next step after this clock
            if (ANCHOR == 0 && tok_in) begin
                pend     <= 1'b1;
                pend_pay <= pay_in;
            end
        end
    end
endmodule
