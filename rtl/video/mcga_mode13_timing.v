//============================================================================
//
//  MCGA mode 13h logical 320x200 timing
//
//============================================================================

module mcga_mode13_timing(
    input  wire        clock,
    input  wire        reset,
    input  wire        enable,
    output wire [9:0]  pixel_x,
    output wire [9:0]  pixel_y,
    output wire        active,
    output wire        hblank,
    output wire        vblank,
    output wire        hsync,
    output wire        vsync,
    output wire        line_start,
    output wire        frame_start
);

    localparam [9:0] H_ACTIVE = 10'd320;
    localparam [9:0] H_FRONT  = 10'd16;
    localparam [9:0] H_SYNC   = 10'd48;
    localparam [9:0] H_BACK   = 10'd16;
    localparam [9:0] H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;

    localparam [9:0] V_ACTIVE = 10'd200;
    localparam [9:0] V_FRONT  = 10'd12;
    localparam [9:0] V_SYNC   = 10'd2;
    localparam [9:0] V_BACK   = 10'd35;
    localparam [9:0] V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    reg [9:0] h_count = 10'd0;
    reg [9:0] v_count = 10'd0;

    wire h_last = (h_count == H_TOTAL - 10'd1);
    wire v_last = (v_count == V_TOTAL - 10'd1);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else if (!enable) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else if (h_last) begin
            h_count <= 10'd0;
            if (v_last)
                v_count <= 10'd0;
            else
                v_count <= v_count + 10'd1;
        end else begin
            h_count <= h_count + 10'd1;
        end
    end

    assign pixel_x = h_count;
    assign pixel_y = v_count;
    assign active = enable && (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    assign hblank = !enable || (h_count >= H_ACTIVE);
    assign vblank = !enable || (v_count >= V_ACTIVE);
    assign hsync = enable &&
                   (h_count >= (H_ACTIVE + H_FRONT)) &&
                   (h_count <  (H_ACTIVE + H_FRONT + H_SYNC));
    assign vsync = enable &&
                   (v_count >= (V_ACTIVE + V_FRONT)) &&
                   (v_count <  (V_ACTIVE + V_FRONT + V_SYNC));
    assign line_start = enable && (h_count == 10'd0);
    assign frame_start = line_start && (v_count == 10'd0);

endmodule
