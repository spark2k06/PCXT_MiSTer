//============================================================================
//
//  Generic video scandoubler
//  Copyright (C) 2026
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

`default_nettype wire

module video_scandoubler #(
    parameter PIXEL_WIDTH = 4,
    parameter H_TOTAL_MAX = 912
) (
    input  wire                   clk,
    input  wire                   ce_pix,
    input  wire                   ce_2x,
    input  wire                   scandouble_en,

    input  wire [PIXEL_WIDTH-1:0] pixel_in,
    input  wire                   hsync_in,
    input  wire                   vsync_in,
    input  wire                   vblank_in,
    input  wire                   display_enable_in,

    output reg  [PIXEL_WIDTH-1:0] pixel_out,
    output reg                    hsync_out,
    output reg                    vsync_out,
    output reg                    vblank_out,
    output reg                    display_enable_out
);

    function integer clog2;
        input integer value;
        integer i;
        begin
            value = value - 1;
            for (i = 0; value > 0; i = i + 1) begin
                value = value >> 1;
            end
            clog2 = (i == 0) ? 1 : i;
        end
    endfunction

    localparam integer PTR_W = clog2(H_TOTAL_MAX);

    reg hsync_pix_r = 1'b0;
    reg de_pix_r = 1'b0;

    always @(posedge clk) begin
        if (ce_pix) begin
            hsync_pix_r <= hsync_in;
            de_pix_r <= display_enable_in;
        end
    end

    wire hsync_posedge = ce_pix && ~hsync_pix_r && hsync_in;
    wire hsync_negedge = ce_pix && hsync_pix_r && ~hsync_in;
    wire de_posedge = ce_pix && ~de_pix_r && display_enable_in;
    wire de_negedge = ce_pix && de_pix_r && ~display_enable_in;

    // Two line buffers with M10K preference.
    (* ramstyle = "M10K, no_rw_check" *) reg [PIXEL_WIDTH-1:0] linebuf[0:1][0:H_TOTAL_MAX-1];

    reg                    buf_wr = 1'b0;
    reg [PTR_W-1:0]        hcount_slow = {PTR_W{1'b0}};
    reg [PTR_W-1:0]        hcount_fast = {PTR_W{1'b0}};
    reg [PTR_W:0]          line_total = H_TOTAL_MAX;

    reg [PTR_W:0]          hs_start_dyn = {(PTR_W+1){1'b0}};
    reg [PTR_W:0]          de_start = {(PTR_W+1){1'b0}};
    reg [PTR_W:0]          de_end = {(PTR_W+1){1'b0}};

    reg [PIXEL_WIDTH-1:0]  pixel_sd = {PIXEL_WIDTH{1'b0}};
    reg                    hsync_sd = 1'b0;
    reg                    vsync_sd = 1'b0;
    reg                    vblank_sd = 1'b0;
    reg                    de_sd = 1'b0;

    // HS pulse strategy:
    // - fixed pulse width per 80/40-col profile for stable VGA lock
    // - dynamic start phase captured from input HS to keep centering consistent
    //   between text and graphics modes.
    localparam [PTR_W:0] HS_START_80 = 11'd748;
    localparam [PTR_W:0] HS_WIDTH_80 = 11'd110;
    localparam [PTR_W:0] HS_START_40 = 11'd374;
    localparam [PTR_W:0] HS_WIDTH_40 = 11'd55;

    localparam [PTR_W:0] HS_PROFILE_THRESHOLD = ((H_TOTAL_MAX * 3) / 4);
    wire use_80col_profile = (line_total > HS_PROFILE_THRESHOLD);
    wire [PTR_W:0] hs_start_fallback = use_80col_profile ? HS_START_80 : HS_START_40;
    wire [PTR_W:0] hs_start_use = (hs_start_dyn != 0) ? hs_start_dyn : hs_start_fallback;
    wire [PTR_W:0] hs_width_fixed = use_80col_profile ? HS_WIDTH_80 : HS_WIDTH_40;
    wire [PTR_W:0] hs_stop_sum = hs_start_use + hs_width_fixed;
    wire [PTR_W:0] hs_stop = (hs_stop_sum >= line_total) ? (hs_stop_sum - line_total) : hs_stop_sum;

    wire hs_active = (hs_width_fixed == 0) ? 1'b0 :
                     (hs_stop > hs_start_use) ?
                     (({1'b0,hcount_fast} >= hs_start_use) && ({1'b0,hcount_fast} < hs_stop)) :
                     (hs_stop < hs_start_use) ?
                     (({1'b0,hcount_fast} >= hs_start_use) || ({1'b0,hcount_fast} < hs_stop)) :
                     1'b0;

    wire de_active = (de_end > de_start) ?
                     (({1'b0,hcount_fast} >= de_start) && ({1'b0,hcount_fast} < de_end)) :
                     (de_end < de_start) ?
                     (({1'b0,hcount_fast} >= de_start) || ({1'b0,hcount_fast} < de_end)) :
                     1'b0;

    always @(posedge clk) begin
        if (!scandouble_en) begin
            buf_wr <= 1'b0;
            hcount_slow <= {PTR_W{1'b0}};
            hcount_fast <= {PTR_W{1'b0}};
            line_total <= H_TOTAL_MAX;

            hs_start_dyn <= {(PTR_W+1){1'b0}};
            de_start <= {(PTR_W+1){1'b0}};
            de_end <= {(PTR_W+1){1'b0}};

            pixel_sd <= {PIXEL_WIDTH{1'b0}};
            hsync_sd <= 1'b0;
            vsync_sd <= 1'b0;
            vblank_sd <= 1'b0;
            de_sd <= 1'b0;
        end else begin
            // Input pixel-domain write pointer in source pixel units.
            if (hsync_negedge) begin
                hcount_slow <= {PTR_W{1'b0}};
                buf_wr <= ~buf_wr;

                if (hcount_slow < (H_TOTAL_MAX-1)) begin
                    line_total <= {1'b0, hcount_slow} + 1'b1;
                end else begin
                    line_total <= H_TOTAL_MAX;
                end
                // Re-sync output counter at each source line start.
                hcount_fast <= {PTR_W{1'b0}};
            end else if (ce_pix) begin
                if (hcount_slow < (H_TOTAL_MAX-1))
                    hcount_slow <= hcount_slow + 1'b1;
            end

            if (ce_pix)
                linebuf[buf_wr][hcount_slow] <= pixel_in;

            if (de_posedge)
                de_start <= {1'b0, hcount_slow};

            if (de_negedge)
                de_end <= {1'b0, hcount_slow};

            if (hsync_posedge)
                hs_start_dyn <= {1'b0, hcount_slow};

            // Output at 2x pixel rate using source line geometry.
            // Keep explicit priority for source line re-sync.
            if (ce_2x && !hsync_negedge) begin
                if (line_total > 1) begin
                    if ({1'b0, hcount_fast} >= (line_total - 1'b1))
                        hcount_fast <= {PTR_W{1'b0}};
                    else
                        hcount_fast <= hcount_fast + 1'b1;
                end else begin
                    hcount_fast <= {PTR_W{1'b0}};
                end

                pixel_sd <= linebuf[~buf_wr][hcount_fast];
                hsync_sd <= hs_active;
                de_sd <= de_active;
                vsync_sd <= vsync_in;
                vblank_sd <= vblank_in;
            end
        end
    end

    // Bypass mux: zero additional latency when scandoubler is disabled.
    always @(*) begin
        if (scandouble_en) begin
            pixel_out          = pixel_sd;
            hsync_out          = hsync_sd;
            vsync_out          = vsync_sd;
            vblank_out         = vblank_sd;
            display_enable_out = de_sd;
        end else begin
            pixel_out          = pixel_in;
            hsync_out          = hsync_in;
            vsync_out          = vsync_in;
            vblank_out         = vblank_in;
            display_enable_out = display_enable_in;
        end
    end

endmodule
