//============================================================================
//
//  VGA packed/unchained mode 13h route selection
//
//============================================================================

module vga_unchained256_ctrl(
    input  wire       mode13_active,
    input  wire       mode12_tweak_pending,
    input  wire       chain4,
    input  wire       shift256,
    input  wire       graphics_mode,
    input  wire [1:0] mem_map_sel,
    // CRTC values are only used to select the deliberately supported
    // extensions. Anything else stays on the established 320x200 renderer.
    input  wire [7:0] crtc_h_displayed,
    input  wire [9:0] crtc_v_displayed,
    input  wire [7:0] crtc_offset,
    input  wire [7:0] crtc_underline_loc,
    input  wire [7:0] crtc_mode_control,
    output wire       packed_active,
    output wire       planar640_active,
    output wire       unchained_active,
    output wire [2:0] unchained_profile
);

    // VGA permits the unchained planar layout through both A0000 apertures:
    // GC06 map 00 exposes the full A0000-BFFFF range and map 01 exposes the
    // usual A0000-AFFFF 64K window. Some software (including Little Engine)
    // deliberately selects map 00, so rejecting it falls back to the packed
    // framebuffer renderer and interprets four planes as one byte stream.
    wire a000_aperture = (mem_map_sel == 2'b00) ||
                         (mem_map_sel == 2'b01);
    wire mode_256x232 = (crtc_h_displayed == 8'd63) &
                        (crtc_v_displayed == 10'd464);
    wire mode12_tweak_ready = mode_256x232 &
                              ((crtc_offset == 8'd32) || (crtc_offset == 8'd64)) &
                              ~crtc_underline_loc[6] & crtc_mode_control[6];
    // Mode 12h alone is not a supported VGA raster. Dyna Blaster starts from
    // that BIOS mode and then programs this precise unchained signature.
    assign unchained_active = (mode13_active |
                               (mode12_tweak_pending & mode12_tweak_ready)) &
                              ~chain4 & shift256 & graphics_mode & a000_aperture;
    // VGA mode 12h: 640x480x16 planar. The TSR loads its register baseline
    // for INT 10h AX=0012h; Pinball Fantasies also reaches it from mode 13h by
    // clearing GC 05h's 256-colour shift and keeping 80 characters and 480
    // scanlines. Shift256 is what tells it apart from unchained 320x240.
    assign planar640_active = (mode13_active | mode12_tweak_pending) &
                              ~chain4 & ~shift256 & graphics_mode & a000_aperture &
                              (crtc_h_displayed == 8'd79) &
                              (crtc_v_displayed == 10'd480);
    assign packed_active = mode13_active & ~unchained_active & ~planar640_active;

    // Standard Mode 13h uses 80 CRTC characters (R1 = 79). The common
    // 360x200 VGA variant uses 90 characters (CRTC R1 = 59h), while 320x240
    // raises the physical display end to 480 scanlines. 320x350 is the
    // 350-scanline variant used by Pinball Fantasies' high-resolution table
    // view (R12 = 5Dh with R7 bit 1, R9 maximum scan line 0). R9 is
    // deliberately not part of profile selection: software may animate
    // Maximum Scan Line or Scan Doubling while retaining the same Mode-X
    // memory layout. The renderer remains profile-based rather than a generic
    // VGA CRTC implementation.
    localparam [2:0] PROFILE_320X200 = 3'd0;
    localparam [2:0] PROFILE_360X200 = 3'd1;
    localparam [2:0] PROFILE_320X240 = 3'd2;
    localparam [2:0] PROFILE_256X232 = 3'd3;
    localparam [2:0] PROFILE_320X350 = 3'd4;

    wire crtc_80_columns = (crtc_h_displayed == 8'd79);
    wire mode_360x200 = (crtc_h_displayed == 8'd89) &
                        (crtc_v_displayed == 10'd400);
    wire mode_320x240 = crtc_80_columns & (crtc_v_displayed == 10'd480);
    wire mode_320x350 = crtc_80_columns & (crtc_v_displayed == 10'd350);

    assign unchained_profile = !unchained_active ? PROFILE_320X200 :
                               mode_256x232      ? PROFILE_256X232 :
                               mode_360x200      ? PROFILE_360X200 :
                               mode_320x240      ? PROFILE_320X240 :
                               mode_320x350      ? PROFILE_320X350 :
                                                  PROFILE_320X200;

endmodule
