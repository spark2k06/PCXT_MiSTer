//============================================================================
//
//  Glitch-free selection between two independent video rasters.
//
//  Waiting for both rasters to be in vertical blank at once is unsafe when
//  they have equal (or nearly equal) frame rates: their relative phase may
//  stay fixed and the overlap can take an arbitrarily long time to appear.
//  Instead, change over while the destination raster is blanked and exactly
//  on one of its horizontal-sync edges.  The old picture is therefore never
//  cut off by an active part of the new one, and the request completes within
//  one destination frame regardless of the two rasters' relative phase.
//
//============================================================================

`default_nettype wire

module video_source_switch (
    input  wire clock,
    input  wire reset,
    input  wire select_alt,

    input  wire primary_hsync,
    input  wire primary_vblank,
    input  wire alt_hsync,
    input  wire alt_vblank,

    output reg  alt_active
);

    reg primary_hsync_q = 1'b0;
    reg alt_hsync_q     = 1'b0;

    wire primary_line_edge = primary_hsync ^ primary_hsync_q;
    wire alt_line_edge     = alt_hsync ^ alt_hsync_q;

    always @(posedge clock) begin
        if (reset) begin
            primary_hsync_q <= 1'b0;
            alt_hsync_q     <= 1'b0;
            alt_active      <= 1'b0;
        end else begin
            primary_hsync_q <= primary_hsync;
            alt_hsync_q     <= alt_hsync;

            if (select_alt) begin
                if (alt_vblank && alt_line_edge)
                    alt_active <= 1'b1;
            end else begin
                if (primary_vblank && primary_line_edge)
                    alt_active <= 1'b0;
            end
        end
    end

endmodule



