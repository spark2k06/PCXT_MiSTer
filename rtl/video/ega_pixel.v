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
    input  wire [1:0]  render_mode,
    output reg  [3:0]  plane_index,
    output reg         pixel_valid,
    output wire [1:0]  render_mode_debug
);

    localparam [1:0] RENDER_TEXT   = 2'd0;
    localparam [1:0] RENDER_PLANAR = 2'd1;
    localparam [1:0] RENDER_CGA2   = 2'd2;

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
    reg       have_pixel = 1'b0;

    // EGA CGA-compatible graphics fetches pack adjacent 2bpp pixels across
    // planes; this mirrors x86Box's EGA render path before palette lookup.
    function [3:0] egaremap2bpp;
        input [7:0] value;
        begin
            egaremap2bpp = {value[6], value[4], value[2], value[0]};
        end
    endfunction

    wire       cga2_render = (render_mode == RENDER_CGA2);
    wire [7:0] input_plane0 = cga2_render ? {egaremap2bpp(plane0_data), egaremap2bpp(plane1_data)} : plane0_data;
    wire [7:0] input_plane1 = cga2_render ? {egaremap2bpp({1'b0, plane0_data[7:1]}), egaremap2bpp({1'b0, plane1_data[7:1]})} : plane1_data;
    wire [7:0] input_plane2 = cga2_render ? {egaremap2bpp(plane2_data), egaremap2bpp(plane3_data)} : plane2_data;
    wire [7:0] input_plane3 = cga2_render ? {egaremap2bpp({1'b0, plane2_data[7:1]}), egaremap2bpp({1'b0, plane3_data[7:1]})} : plane3_data;
    wire [7:0] load_plane0 = fetch_en ? input_plane0 : fetch_plane0;
    wire [7:0] load_plane1 = fetch_en ? input_plane1 : fetch_plane1;
    wire [7:0] load_plane2 = fetch_en ? input_plane2 : fetch_plane2;
    wire [7:0] load_plane3 = fetch_en ? input_plane3 : fetch_plane3;
    wire [3:0] load_pixel = {load_plane3[7], load_plane2[7], load_plane1[7], load_plane0[7]};
    wire [3:0] shift_pixel = {shift_plane3[7], shift_plane2[7], shift_plane1[7], shift_plane0[7]};
    wire       graphics_render = (render_mode == RENDER_PLANAR) || (render_mode == RENDER_CGA2);
    assign render_mode_debug = render_mode;

    always @(posedge clk) begin
        if (fetch_en && graphics_render) begin
            fetch_plane0 <= input_plane0;
            fetch_plane1 <= input_plane1;
            fetch_plane2 <= input_plane2;
            fetch_plane3 <= input_plane3;
            load_pending <= 1'b1;
        end

        pixel_valid <= (bits_remaining != 4'd0);

        if (ce_pix) begin
            if (!display_enable) begin
                plane_index <= 4'h0;
                pixel_valid <= 1'b0;
                bits_remaining <= 4'd0;
                repeat_phase <= 1'b0;
                load_pending <= 1'b0;
                have_pixel <= 1'b0;
            end
            else if (!graphics_render) begin
                plane_index <= 4'h0;
                pixel_valid <= 1'b0;
                bits_remaining <= 4'd0;
                repeat_phase <= 1'b0;
                load_pending <= 1'b0;
                have_pixel <= 1'b0;
            end
            else if (load_pending || fetch_en) begin
                plane_index <= load_pixel;
                pixel_valid <= 1'b1;
                load_pending <= 1'b0;
                have_pixel <= 1'b1;

                if (dot_clock_div2) begin
                    shift_plane0 <= load_plane0;
                    shift_plane1 <= load_plane1;
                    shift_plane2 <= load_plane2;
                    shift_plane3 <= load_plane3;
                    bits_remaining <= 4'd8;
                    repeat_phase <= 1'b1;
                end
                else begin
                    shift_plane0 <= {load_plane0[6:0], 1'b0};
                    shift_plane1 <= {load_plane1[6:0], 1'b0};
                    shift_plane2 <= {load_plane2[6:0], 1'b0};
                    shift_plane3 <= {load_plane3[6:0], 1'b0};
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
                pixel_valid <= have_pixel;
                have_pixel <= 1'b0;
            end
        end
    end

endmodule
