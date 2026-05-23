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
    wire [7:0] load_plane0 = fetch_en ? plane0_data : fetch_plane0;
    wire [7:0] load_plane1 = fetch_en ? plane1_data : fetch_plane1;
    wire [7:0] load_plane2 = fetch_en ? plane2_data : fetch_plane2;
    wire [7:0] load_plane3 = fetch_en ? plane3_data : fetch_plane3;
    //NEW pixel panning
    wire [7:0] panned0 = ({fetch_plane0, load_plane0} << h_pixel_pan) >> 8;
    wire [7:0] panned1 = ({fetch_plane1, load_plane1} << h_pixel_pan) >> 8;
    wire [7:0] panned2 = ({fetch_plane2, load_plane2} << h_pixel_pan) >> 8;
    wire [7:0] panned3 = ({fetch_plane3, load_plane3} << h_pixel_pan) >> 8;


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
            if (load_pending || fetch_en) begin
                plane_index <= {load_plane3[7], load_plane2[7], load_plane1[7], load_plane0[7]};
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
                plane_index <= {panned3[7], panned2[7], panned1[7], panned0[7]};
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
