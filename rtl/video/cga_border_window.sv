// Active window of the CGA output with Border on: a fixed raster, the part
// of every line and every frame that a monitor locked to the sync pulses
// shows.
//
// The window is not taken from the picture. It is always H_WIDTH x V_LINES,
// placed after the sync pulses: the picture of the BIOS modes, 192 pixels
// after HSYNC and 38 lines after VSYNC, sits 64 pixels and 22 lines inside it,
// and the parts of Area 5150 that fill the whole raster (128..896, 16..261)
// fill it exactly. A program that changes the CRTC timing moves or resizes its
// picture inside the window, as on the real screen, and the scaler always
// receives frames of the same size.
//
// hsync and vsync are the CRTC's reference pulses (HSYNC_REF, VSYNC_REF): the
// positions an MC6845 gives them, the same in every mode and not moved by the
// OSD CRT offsets. H_START includes the pixel pipeline (BIOS picture at pixel
// 193 of this count).
//
// Lines and frames start on the leading edges. An HSYNC that comes while the
// window of its line is still open waits until it has closed and the next
// line starts that much further on, so a line of the window is never cut. A
// VSYNC in the last V_START - 1 lines of the window waits in the same way,
// which keeps the picture in place for frames down to V_LINES + 1 lines; an
// earlier one starts a new frame at once (a mode change, a CRTC trick). Without
// pulses the raster runs free (H_FREE pixels, V_FREE lines).
//
// The sync outputs replace the CGA ones after this point: the scaler path
// blanks during HSYNC, and the CGA keeps HSYNC on for up to 160 pixels in
// 40-column modes. HSYNC is HS_WIDTH pixels wide whatever the CRTC gives: a
// monitor that locks to the end of the pulse then places every mode alike, and
// the 80-pixel pulse of the 80-column modes is the one it is used to; VSYNC is
// the lines of each frame before the window.
//
// The OSD CRT V offset moves the picture down: the VSYNC the window follows is
// held back 7 - v_early lines (V_START is 7 lines shorter to make up for it),
// so with v_early = 0 the window is where it always was and every step brings
// the whole window, syncs included, one line earlier against the picture.
//
//   ce      one pixel (14.318 MHz) enable
//   v_early OSD CRT V offset, 0..7
module cga_border_window #(
    parameter [10:0] H_START = 11'd129,
    parameter [10:0] H_WIDTH = 11'd768,
    parameter [10:0] H_FREE  = 11'd1023,
    parameter [10:0] HS_WIDTH = 11'd80,
    parameter [8:0]  V_START = 9'd8,
    parameter [8:0]  V_LINES = 9'd246,
    parameter [8:0]  V_FREE  = 9'd400
)(
    input  wire clk,
    input  wire ce,
    input  wire hsync,
    input  wire vsync,
    input  wire [2:0] v_early,
    output reg  hblank = 1'b1,
    output reg  vblank = 1'b1,
    output reg  hsync_out = 1'b0,
    output reg  vsync_out = 1'b0
);
    localparam [10:0] H_END  = H_START + H_WIDTH;
    localparam [8:0]  V_END  = V_START + V_LINES;
    localparam [8:0]  V_WAIT = V_END - V_START + 9'd1;  // a VSYNC from here on waits

    reg        hs_q = 1'b0, vs_q = 1'b0;
    reg [10:0] hc = 11'd0;              // position of the last pixel in its line
    reg        h_pend = 1'b0;           // HSYNC edge waiting for the window to close
    reg [10:0] h_age = 11'd0;           // pixels since that edge
    reg [8:0]  vc = 9'd0;               // line in the frame
    reg        vs_seen = 1'b0;          // VSYNC edge during this line
    reg        v_pend = 1'b0;           // VSYNC edge waiting for the window to close
    reg [8:0]  v_age = 9'd0;            // lines since that edge
    reg        vd_act = 1'b0;           // VSYNC edge being held back
    reg [3:0]  vd_cnt = 4'd0;           // lines it still has to wait

    wire        hs_edge = hsync & ~hs_q;
    wire        vs_edge = vsync & ~vs_q;
    wire [3:0]  v_dly   = 4'd7 - {1'b0, v_early};   // lines the VSYNC edge is held back
    wire        vs_now_e = vs_edge & (v_dly == 4'd0);
    wire [10:0] hn      = hc + 11'd1;
    wire        h_done  = hn >= H_END;
    wire        line_go = ((hs_edge | h_pend) & h_done) | (hn >= H_FREE);
    // position of this pixel: 0 on the HSYNC edge, or the pixels already gone
    // since a waiting edge (kept before the window)
    wire [10:0] h_late  = (h_age < H_START - 11'd2) ? h_age + 11'd1 : H_START - 11'd1;
    wire [10:0] pos     = !line_go ? hn : (h_pend & ~hs_edge & h_done) ? h_late : 11'd0;

    // the same for the lines of a frame
    wire        vs_now  = vs_seen | vs_now_e;
    wire [8:0]  vn      = (vc == 9'h1FF) ? vc : vc + 9'd1;
    wire        v_wait  = vs_now & (vn >= V_WAIT) & (vn < V_END);
    wire        v_go    = (vs_now & ~v_wait) | (v_pend & (vn >= V_END));
    wire [8:0]  v_late  = (v_age < V_START - 9'd2) ? v_age + 9'd1 : V_START - 9'd1;
    wire [8:0]  vnext   = v_go ? (vs_now ? 9'd0 : v_late) : (vn >= V_FREE) ? 9'd0 : vn;
    wire [8:0]  line    = line_go ? vnext : vc;

    always @(posedge clk) begin
        if (ce) begin
            hs_q <= hsync;
            vs_q <= vsync;
            hc   <= pos;

            if (line_go) begin
                h_pend  <= 1'b0;
                vc      <= vnext;
                vs_seen <= 1'b0;
                if (v_go)
                    v_pend <= 1'b0;
                else if (v_wait) begin
                    v_pend <= 1'b1;
                    v_age  <= 9'd0;
                end else if (v_pend && v_age != 9'h1FF)
                    v_age  <= v_age + 9'd1;
            end else begin
                if (hs_edge) begin
                    h_pend <= 1'b1;
                    h_age  <= 11'd0;
                end else if (h_pend && h_age != 11'h7FF)
                    h_age  <= h_age + 11'd1;
                if (vs_now_e)
                    vs_seen <= 1'b1;
            end

            // An edge in line L acts as one in line L + v_dly: count the line starts
            if (vs_edge && v_dly != 4'd0) begin
                if (line_go && v_dly == 4'd1)
                    vs_seen <= 1'b1;
                else begin
                    vd_act <= 1'b1;
                    vd_cnt <= line_go ? v_dly - 4'd1 : v_dly;
                end
            end else if (line_go && vd_act) begin
                if (vd_cnt == 4'd1) begin
                    vs_seen <= 1'b1;
                    vd_act  <= 1'b0;
                end
                vd_cnt <= vd_cnt - 4'd1;
            end

            hblank    <= !(pos >= H_START && pos < H_END);
            vblank    <= !(line >= V_START && line < V_END);
            hsync_out <= pos < HS_WIDTH;
            vsync_out <= line < V_START;
        end
    end
endmodule
