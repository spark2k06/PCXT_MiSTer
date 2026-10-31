//============================================================================
//
//  PCXT MiSTer boot splash fade
//
//  Brightness of the splash, 0 (black) to 64 (exact colours), moved once per
//  frame. It rises while the splash shows and falls while fade_out is asked
//  for (the last second of the splash, unless F12 holds it). It starts from
//  black every time the splash appears, after HOLD_FRAMES frames of black:
//  the splash starts as the core is loaded, while the scaler and the display
//  are still locking to the new picture, and a fade-in there would go unseen
//  (PCAT-286 / ZXTres wait a second before showing it for the same reason).
//  The RGB of the picture is scaled by level / 64 on its way to the video
//  mixer, so the CGA path (RGB or composite) and the EGA path fade alike. Same
//  steps as the PCAT-286 / ZXTres splash: at about 60 frames per second it
//  fades in over half a second and out over one.
//
//============================================================================

`default_nettype wire

module splash_fade #(
    parameter [6:0] IN_STEP     = 7'd2,
    parameter [6:0] OUT_STEP    = 7'd1,
    parameter [6:0] HOLD_FRAMES = 7'd60     // one second at 60 Hz
) (
    input  wire       clock,
    input  wire       reset,
    input  wire       active,       // the splash is on screen
    input  wire       fade_out,
    input  wire       vsync,        // a frame starts on its rising edge
    input  wire [7:0] r_in,
    input  wire [7:0] g_in,
    input  wire [7:0] b_in,
    output wire [7:0] r_out,
    output wire [7:0] g_out,
    output wire [7:0] b_out
);

    localparam [6:0] FULL = 7'd64;

    reg [6:0] level = 7'd0;
    reg [6:0] held  = 7'd0;     // frames of black so far
    reg       vsync_q = 1'b0;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            level   <= 7'd0;
            held    <= 7'd0;
            vsync_q <= 1'b0;
        end else begin
            vsync_q <= vsync;
            if (!active) begin
                level <= 7'd0;
                held  <= 7'd0;
            end else if (vsync && !vsync_q) begin
                if (held != HOLD_FRAMES)
                    held <= held + 7'd1;
                else if (fade_out)
                    level <= (level > OUT_STEP) ? level - OUT_STEP : 7'd0;
                else
                    level <= (level < FULL - IN_STEP) ? level + IN_STEP : FULL;
            end
        end
    end

    // Outside the splash the picture goes through untouched.
    function [7:0] scale;
        input [7:0] c;
        input [6:0] l;
        reg   [14:0] p;
        begin
            p     = c * l;
            scale = p[13:6];
        end
    endfunction

    wire full = !active || level == FULL;

    assign r_out = full ? r_in : scale(r_in, level);
    assign g_out = full ? g_in : scale(g_in, level);
    assign b_out = full ? b_in : scale(b_in, level);

endmodule
