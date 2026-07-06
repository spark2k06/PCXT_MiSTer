`timescale 1ns / 1ps

module mcga_mode13_timing_tb;

    localparam integer H_ACTIVE = 640;
    localparam integer H_FRONT  = 24;
    localparam integer H_SYNC   = 96;
    localparam integer H_BACK   = 152;
    localparam integer H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam integer V_ACTIVE = 400;
    localparam integer V_FRONT  = 12;
    localparam integer V_SYNC   = 2;
    localparam integer V_BACK   = 35;
    localparam integer V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    reg         clock = 1'b0;
    reg         reset = 1'b1;
    reg         enable = 1'b0;
    wire [9:0]  pixel_x;
    wire [9:0]  pixel_y;
    wire        active;
    wire        hblank;
    wire        vblank;
    wire        hsync;
    wire        vsync;
    wire        line_start;
    wire        frame_start;

    integer failures = 0;
    integer i;
    integer active_count = 0;
    integer hsync_count = 0;
    integer vsync_count = 0;
    integer line_count = 0;
    integer frame_count = 0;
    integer max_pixel_x = 0;
    integer max_pixel_y = 0;

    mcga_mode13_timing dut (
        .clock          (clock),
        .reset          (reset),
        .enable         (enable),
        .pixel_x        (pixel_x),
        .pixel_y        (pixel_y),
        .active         (active),
        .hblank         (hblank),
        .vblank         (vblank),
        .hsync          (hsync),
        .vsync          (vsync),
        .line_start     (line_start),
        .frame_start    (frame_start)
    );

    always #5 clock = ~clock;

    task check;
        input condition;
        input [8*80-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL %0s", message);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clock);
        reset = 1'b0;
        enable = 1'b1;
        #1;

        for (i = 0; i < H_TOTAL * V_TOTAL; i = i + 1) begin
            check(pixel_x < H_TOTAL, "pixel_x stays inside horizontal total");
            check(pixel_y < V_TOTAL, "pixel_y stays inside vertical total");

            if (active) begin
                active_count = active_count + 1;
                check(!hblank, "active pixels are not hblank");
                check(!vblank, "active pixels are not vblank");
                check(pixel_x < 10'd320, "active x is inside logical 320");
                check(pixel_y < 10'd200, "active y is inside logical 200");
                if (pixel_x > max_pixel_x)
                    max_pixel_x = pixel_x;
                if (pixel_y > max_pixel_y)
                    max_pixel_y = pixel_y;
            end

            if (hsync)
                hsync_count = hsync_count + 1;
            if (vsync)
                vsync_count = vsync_count + 1;
            if (line_start)
                line_count = line_count + 1;
            if (frame_start)
                frame_count = frame_count + 1;

            @(posedge clock);
            #1;
        end

        check(active_count == H_ACTIVE * V_ACTIVE, "active dot count is doubled 640x400");
        check(max_pixel_x == 319, "maximum logical x reaches 319");
        check(max_pixel_y == 199, "maximum logical y reaches 199");
        check(hsync_count == H_SYNC * V_TOTAL, "hsync width is stable on every line");
        check(vsync_count == V_SYNC * H_TOTAL, "vsync width is stable");
        check(line_count == V_TOTAL, "one line_start per line");
        check(frame_count == 1, "one frame_start per frame");
        enable = 1'b0;
        @(posedge clock);
        #1;
        check(!active && hblank && vblank, "disabled timing blanks output");
        check(pixel_x == 10'd0 && pixel_y == 10'd0, "disabled timing resets counters");

        if (failures == 0) begin
            $display("PASS mcga_mode13_timing_tb");
            $finish;
        end

        $display("FAIL mcga_mode13_timing_tb failures=%0d", failures);
        $finish;
    end

endmodule
