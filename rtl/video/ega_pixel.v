//============================================================================
//
//  PCXT MiSTer EGA pixel generator
//
//============================================================================

`default_nettype wire

module ega_pixel (
    input  wire        clk,
    input  wire        ce_pix,
    input  wire [7:0]  plane0_data,
    input  wire [7:0]  plane1_data,
    input  wire [7:0]  plane2_data,
    input  wire [7:0]  plane3_data,
    input  wire        fetch_en,
    input  wire        dot_clock_div2,
    input  wire        display_enable,
    input  wire [3:0]  h_pixel_pan,    //NEW
    output reg  [3:0]  plane_index,
    output reg         pixel_valid
);

    reg [7:0] shift_plane0 = 8'h00;
    reg [7:0] shift_plane1 = 8'h00;
    reg [7:0] shift_plane2 = 8'h00;
    reg [7:0] shift_plane3 = 8'h00;
    reg [7:0] fetch_plane0 = 8'h00;
    reg [7:0] fetch_plane1 = 8'h00;
    reg [7:0] fetch_plane2 = 8'h00;
    reg [7:0] fetch_plane3 = 8'h00;
    reg [3:0] bits_remaining = 4'd0;
    reg       repeat_phase = 1'b0;
    reg       load_pending = 1'b0;
    reg       display_enable_q = 1'b0;
    reg [3:0] pan_cache = 4'd0;
    wire [7:0] load_plane0 = fetch_en ? plane0_data : fetch_plane0;
    wire [7:0] load_plane1 = fetch_en ? plane1_data : fetch_plane1;
    wire [7:0] load_plane2 = fetch_en ? plane2_data : fetch_plane2;
    wire [7:0] load_plane3 = fetch_en ? plane3_data : fetch_plane3;
    wire [3:0] sanitized_pan = h_pixel_pan[3] ? 4'd0 : h_pixel_pan;
    wire [3:0] active_pan = (display_enable && !display_enable_q) ? sanitized_pan : pan_cache;
    //NEW pixel panning
    wire [15:0] pan_window0 = {fetch_plane0, load_plane0};
    wire [15:0] pan_window1 = {fetch_plane1, load_plane1};
    wire [15:0] pan_window2 = {fetch_plane2, load_plane2};
    wire [15:0] pan_window3 = {fetch_plane3, load_plane3};
    wire [15:0] pan_shift0 = pan_window0 << active_pan;
    wire [15:0] pan_shift1 = pan_window1 << active_pan;
    wire [15:0] pan_shift2 = pan_window2 << active_pan;
    wire [15:0] pan_shift3 = pan_window3 << active_pan;
    wire [7:0] panned0 = (active_pan == 4'd0) ? load_plane0 : pan_shift0[15:8];
    wire [7:0] panned1 = (active_pan == 4'd0) ? load_plane1 : pan_shift1[15:8];
    wire [7:0] panned2 = (active_pan == 4'd0) ? load_plane2 : pan_shift2[15:8];
    wire [7:0] panned3 = (active_pan == 4'd0) ? load_plane3 : pan_shift3[15:8];
    wire [3:0] load_pixel = {panned3[7], panned2[7], panned1[7], panned0[7]};
    wire [3:0] shift_pixel = {shift_plane3[7], shift_plane2[7], shift_plane1[7], shift_plane0[7]};

    always @(posedge clk) begin
        if (fetch_en) begin
            fetch_plane0 <= plane0_data;
            fetch_plane1 <= plane1_data;
            fetch_plane2 <= plane2_data;
            fetch_plane3 <= plane3_data;
            load_pending <= 1'b1;
        end

        pixel_valid <= (bits_remaining != 4'd0);

        if (ce_pix) begin
            display_enable_q <= display_enable;
            if (display_enable && !display_enable_q)
                pan_cache <= sanitized_pan;

            if (load_pending || fetch_en) begin
                plane_index <= load_pixel;
                pixel_valid <= 1'b1;
                load_pending <= 1'b0;

                if (dot_clock_div2) begin
                    shift_plane0 <= panned0; //load_plane
                    shift_plane1 <= panned1;
                    shift_plane2 <= panned2;
                    shift_plane3 <= panned3;
                    bits_remaining <= 4'd8;
                    repeat_phase <= 1'b1;
                end
                else begin
                    shift_plane0 <= {panned0[6:0], 1'b0}; //load_plane
                    shift_plane1 <= {panned1[6:0], 1'b0};
                    shift_plane2 <= {panned2[6:0], 1'b0};
                    shift_plane3 <= {panned3[6:0], 1'b0};
                    bits_remaining <= 4'd7;
                    repeat_phase <= 1'b0;
                end
            end
            else if (bits_remaining != 4'd0) begin
                plane_index <= shift_pixel;
                pixel_valid <= 1'b1;

                if (dot_clock_div2 && !repeat_phase) begin
                    repeat_phase <= 1'b1;
                end
                else begin
                    shift_plane0 <= {shift_plane0[6:0], 1'b0};
                    shift_plane1 <= {shift_plane1[6:0], 1'b0};
                    shift_plane2 <= {shift_plane2[6:0], 1'b0};
                    shift_plane3 <= {shift_plane3[6:0], 1'b0};
                    bits_remaining <= bits_remaining - 4'd1;
                    repeat_phase <= 1'b0;
                end
            end
            else begin
                plane_index <= 4'h0;
            end
        end
    end

endmodule
