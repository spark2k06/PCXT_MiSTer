// Delays the pixel stream by n pixels (0..64) against everything that is
// not delayed with it.
//
// With Border on, the sync pulses and the window come from the CRTC's
// reference pulses, which the OSD CRT H offset does not move. The picture is
// moved inside the window instead, by the amount the same offset moves it
// against the CGA's own HSYNC with Border off. The window has 64 pixels of
// margin on each side, which is the most this delays the picture by.
//
// n = 0 passes the stream through, with no latency of its own.
//
//   en      one pixel enable
module cga_pixel_delay #(
    parameter W = 18
)(
    input  wire         clk,
    input  wire         en,
    input  wire [6:0]   n,
    input  wire [W-1:0] din,
    output wire [W-1:0] dout
);
    reg [W-1:0] sr [0:63];      // sr[0] is the previous pixel
    integer i;

    always @(posedge clk) begin
        if (en) begin
            sr[0] <= din;
            for (i = 1; i < 64; i = i + 1)
                sr[i] <= sr[i - 1];
        end
    end

    assign dout = (n == 7'd0)  ? din :
                  (n >= 7'd64) ? sr[63] : sr[n[5:0] - 6'd1];
endmodule
