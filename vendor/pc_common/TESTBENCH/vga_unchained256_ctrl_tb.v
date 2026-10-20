`timescale 1ns/1ps

module vga_unchained256_ctrl_tb;
    reg mode13_active = 1'b0;
    reg mode12_tweak_pending = 1'b0;
    reg chain4 = 1'b1;
    reg shift256 = 1'b0;
    reg graphics_mode = 1'b0;
    reg [1:0] mem_map_sel = 2'b00;
    reg [7:0] crtc_h_displayed = 8'd79;
    reg [9:0] crtc_v_displayed = 10'd400;
    reg [7:0] crtc_offset = 8'd40;
    reg [7:0] crtc_underline_loc = 8'h40;
    reg [7:0] crtc_mode_control = 8'hA3;
    wire packed_active;
    wire planar640_active;
    wire unchained_active;
    wire [2:0] unchained_profile;
    integer errors = 0;

    vga_unchained256_ctrl dut (
        .mode13_active(mode13_active),
        .mode12_tweak_pending(mode12_tweak_pending), .chain4(chain4),
        .shift256(shift256), .graphics_mode(graphics_mode),
        .mem_map_sel(mem_map_sel), .crtc_h_displayed(crtc_h_displayed),
        .crtc_v_displayed(crtc_v_displayed), .crtc_offset(crtc_offset),
        .crtc_underline_loc(crtc_underline_loc),
        .crtc_mode_control(crtc_mode_control),
        .packed_active(packed_active), .planar640_active(planar640_active),
        .unchained_active(unchained_active), .unchained_profile(unchained_profile)
    );

    task check;
        input expected_packed;
        input expected_unchained;
        input [2:0] expected_profile;
        input [127:0] tag;
        begin
            #1;
            if ((packed_active !== expected_packed) ||
                (unchained_active !== expected_unchained) ||
                (unchained_profile !== expected_profile)) begin
                errors = errors + 1;
                $display("FAIL: %0s packed=%b unchained=%b profile=%0d", tag,
                         packed_active, unchained_active, unchained_profile);
            end
        end
    endtask

    initial begin
        check(1'b0, 1'b0, 2'd0, "outside mode 13h");
        mode13_active = 1'b1;
        check(1'b1, 1'b0, 2'd0, "mode 13h defaults to packed");
        shift256 = 1'b1; graphics_mode = 1'b1; mem_map_sel = 2'b01;
        check(1'b1, 1'b0, 2'd0, "Chain-4 keeps packed route");
        chain4 = 1'b0;
        check(1'b0, 1'b1, 2'd0, "unchained 320x200 selects planar route");
        crtc_h_displayed = 8'd89;
        check(1'b0, 1'b1, 2'd1, "90-character CRTC selects 360x200");
        crtc_h_displayed = 8'd79; crtc_v_displayed = 10'd480;
        check(1'b0, 1'b1, 2'd2, "480 physical scanlines select 320x240");
        check(1'b0, 1'b1, 2'd2, "320x240 profile ignores maximum scanline changes");
        crtc_v_displayed = 10'd350;
        check(1'b0, 1'b1, 3'd4, "350 physical scanlines select 320x350");
        crtc_h_displayed = 8'd89;
        check(1'b0, 1'b1, 2'd0, "90-character 350-line CRTC is not a profile");
        crtc_h_displayed = 8'd79;
        crtc_h_displayed = 8'd63; crtc_v_displayed = 10'd464;
        check(1'b0, 1'b1, 2'd3, "256x232 CRTC selects Dyna profile");
        crtc_v_displayed = 10'd400;
        shift256 = 1'b0;
        check(1'b1, 1'b0, 2'd0, "Shift256 is required");
        shift256 = 1'b1; graphics_mode = 1'b0;
        check(1'b1, 1'b0, 2'd0, "graphics mode is required");
        graphics_mode = 1'b1; mem_map_sel = 2'b00;
        check(1'b0, 1'b1, 2'd0, "A000 128K map is also planar");
        mem_map_sel = 2'b10;
        check(1'b1, 1'b0, 2'd0, "B000 aperture is not Mode X");
        mode13_active = 1'b0; mem_map_sel = 2'b01;
        check(1'b0, 1'b0, 2'd0, "leaving mode 13h restores EGA route");

        mode12_tweak_pending = 1'b1;
        crtc_h_displayed = 8'd63; crtc_v_displayed = 10'd464;
        crtc_offset = 8'd64; crtc_underline_loc = 8'h00;
        crtc_mode_control = 8'hE3;
        check(1'b0, 1'b1, 2'd3, "mode 12h Dyna signature enables VGA route");
        crtc_offset = 8'd32;
        check(1'b0, 1'b1, 2'd3, "direct-width Dyna stride also enables route");
        crtc_offset = 8'd45;
        check(1'b0, 1'b0, 2'd0, "partial mode 12h table stays on EGA route");
        crtc_offset = 8'd64; crtc_underline_loc = 8'h40;
        check(1'b0, 1'b0, 2'd0, "dword addressing rejects mode 12h tweak");
        crtc_underline_loc = 8'h00; crtc_mode_control = 8'hA3;
        check(1'b0, 1'b0, 2'd0, "non-byte addressing rejects mode 12h tweak");
        crtc_mode_control = 8'hE3; mode12_tweak_pending = 1'b0;
        check(1'b0, 1'b0, 2'd0, "leaving mode 12h restores EGA route");

        // VGA mode 12h: the TSR's baseline, and Pinball Fantasies' route
        // from mode 13h, select the 640x480 planar renderer.
        mode12_tweak_pending = 1'b1; mode13_active = 1'b0;
        chain4 = 1'b0; shift256 = 1'b0; graphics_mode = 1'b1; mem_map_sel = 2'b01;
        crtc_h_displayed = 8'd79; crtc_v_displayed = 10'd480; crtc_offset = 8'd40;
        #1 if (!planar640_active || unchained_active || packed_active) begin
            errors = errors + 1; $display("FAIL: mode 12h baseline is not planar640");
        end
        mode12_tweak_pending = 1'b0; mode13_active = 1'b1;
        #1 if (!planar640_active || packed_active) begin
            errors = errors + 1; $display("FAIL: mode 13h without Shift256 is not planar640");
        end
        shift256 = 1'b1;
        #1 if (planar640_active || !unchained_active) begin
            errors = errors + 1; $display("FAIL: Shift256 must keep unchained 320x240");
        end
        shift256 = 1'b0; chain4 = 1'b1;
        #1 if (planar640_active) begin
            errors = errors + 1; $display("FAIL: Chain-4 is not mode 12h");
        end
        chain4 = 1'b0; crtc_v_displayed = 10'd400;
        #1 if (planar640_active) begin
            errors = errors + 1; $display("FAIL: 400 scanlines are not mode 12h");
        end
        crtc_v_displayed = 10'd480; mode13_active = 1'b0;
        #1 if (planar640_active) begin
            errors = errors + 1; $display("FAIL: EGA modes must not select planar640");
        end

        if (errors == 0) $display("RESULT: PASS");
        else $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
