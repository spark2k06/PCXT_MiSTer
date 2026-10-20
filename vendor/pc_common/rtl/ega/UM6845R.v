//============================================================================
//  UM6845R for Amstrad CPC
//  Copyright (C) 2018 Sorgelig
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
//============================================================================

module UM6845R
(
	input            CLOCK,
	input            CLKEN,
	input            nCLKEN,
	// Dot clock enable.  The HSYNC delay and width shaping below are measured
	// in dots, not in CLOCK cycles: the EGA dot clock is not a fixed fraction
	// of CLOCK, so counting raw cycles would move HSYNC with respect to the
	// pixel stream from line to line.
	input            PIXEL_CE,
	input            nRESET,
	input            CRTC_TYPE,

	input            ENABLE,
	input            nCS,
	input            R_nW,
	input            RS,
	input      [7:0] DI,
	output reg [7:0] DO,

	output           hblank,
	output           vblank,
	output           line_reset,

	output reg       VSYNC,
	output reg       HSYNC,
	output           DE,
	output           VDE,
	output           FIELD,
	output           CURSOR,

	output    [13:0] MA,
	output    [15:0] MA_FULL,
	output     [4:0] RA,
	output     [7:0] HC,
	output     [6:0] VC,
	output     [9:0] VSCAN,
	output     [7:0] H_DISP_REG,
	// Active scanlines the current registers ask for, overflow bits included.
	// The only place the 200 and 350 line modes can be told apart without
	// naming a BIOS mode or trusting the monitor switches.
	output     [9:0] V_DISP_REG,
	output     [4:0] V_MAXSCAN_REG,
	// VGA R9 bit 7: every row scanned twice on top of Maximum Scan Line.
	output           V_DOUBLE_SCAN_REG,
	output    [3:0] hsync_width,
	output           status_vretrace,
	output           status_not_displaying,
	output           vert_blank_active,
	output     [3:0] scanline_mod16_debug,
	output     [3:0] vslines_debug,
	output     [7:0] crtc_r10_debug,
	output     [7:0] crtc_r11_debug,
	output     [7:0] crtc_r12_debug,
	output     [7:0] crtc_r13_debug,
	output     [7:0] crtc_r14_debug,
	output     [7:0] crtc_r17_debug,
	output     [7:0] crtc_r15_debug,
	output     [7:0] crtc_r16_debug,
	output     [7:0] crtc_r19_debug,
	// Raw Line Compare value, including the two overflow bits. The renderer
	// applies VGA's "restart on the following physical scanline" rule.
	output     [9:0] crtc_line_compare_debug,

	input      [3:0] crt_h_offset,
	input      [2:0] crt_v_offset,
	input      [2:0] vsync_width_osd, // OSD vsync pulse width: 0=Auto (use register), 1-7=override
	input      [2:0] hsync_width_osd, // OSD hsync pulse width: 0=Auto, 1-7=fixed (N*16 pixel clocks)
	input            hres_mode
);

parameter H_TOTAL = 0;
parameter H_DISP = 0;
parameter H_SYNCPOS = 0;
parameter H_SYNCWIDTH = 0;
parameter V_TOTAL = 0;
parameter V_TOTALADJ = 0;
parameter V_DISP = 0;
parameter V_SYNCPOS = 0;
parameter V_MAXSCAN = 0;
parameter C_START = 0;
parameter C_END = 0;
parameter DISPLAYED_CHARS_PLUS1 = 0;
parameter EGA_RESET_R16 = 0;
parameter EGA_RESET_R17 = 1;
parameter EGA_RESET_R18 = 0;
parameter EGA_RESET_R19 = 0;

/* verilator lint_off WIDTH */

wire [15:0] ega_display_addr;
wire ega_crtc_semantics = CRTC_TYPE && |EGA_RESET_R19;

assign FIELD = ~field & interlace[0];

assign MA = ega_display_addr[13:0];
assign MA_FULL = ega_display_addr;
assign RA = line | (field & interlace[0]);
assign HC = hcc;
assign VC = row[6:0];
assign VSCAN = row;
assign H_DISP_REG = R1_h_displayed;
assign V_MAXSCAN_REG = R9_v_max_line[4:0];
assign V_DOUBLE_SCAN_REG = R9_v_max_line[7];
assign hsync_width = R3_h_sync_width;
// Match 86Box more closely: Input Status #1 bit 3 tracks the retrace window
// opened at VSYNC start and closed a few scanlines later, not the whole
// vertical blank interval.
assign status_vretrace = ega_crtc_semantics ? ega_status_vretrace : 1'b0;
// Input Status #1 bit 0 is the inverted display enable, so it follows the
// vertical display end (R18) like DE does, not the vertical blanking window
// (R21/R22). Those coincide in the option ROM's 350-line table, where blanking
// starts at line 350 exactly, but not in its 200-line tables, where the
// display ends at 200 and blanking only starts at 224. Driving this from
// blanking made the ROM's monitor sense count 248 lines instead of 200, fail
// with 1 long + 3 short beeps and leave the card in the mode 1 it had set to
// take the measurement - which is why 5153/CGA booted at 40 columns while
// 5154/ECD was unaffected.
assign status_not_displaying = ~DE;
assign vert_blank_active = ega_crtc_semantics ? ega_vert_blank_active_r : ~vde;
assign scanline_mod16_debug = ega_scanline_mod16;
assign vslines_debug = ega_vslines;
assign crtc_r10_debug = R16_v_sync_pos_e;
assign crtc_r11_debug = R17_v_sync_end_e;
assign crtc_r12_debug = R12_start_addr_h;
assign crtc_r13_debug = R13_start_addr_l;
assign crtc_r14_debug = R20_underline_loc_e;
assign crtc_r17_debug = R23_mode_control_e;
assign crtc_r15_debug = R21_v_blank_start_e;
assign crtc_r16_debug = R22_v_blank_end_e;
assign crtc_r19_debug = R19_offset_e;
assign crtc_line_compare_debug = {R9_v_max_line[6], R7_v_sync_pos[4], R24_line_compare_e};

assign DE = de[R8_skew & ~{2{CRTC_TYPE}}];
assign VDE = vde & vde_r;

assign hblank = ~hde;
assign vblank = ega_crtc_semantics ? ega_vert_blank_active_r : ~vde;
assign line_reset = hcc_last;

reg [7:0] R0_h_total = H_TOTAL;
reg [7:0] R1_h_displayed = H_DISP;
reg [7:0] R2_h_sync_pos = H_SYNCPOS;
reg [3:0] R3_v_sync_width;
reg [3:0] R3_h_sync_width = H_SYNCWIDTH;
reg [6:0] R4_v_total = V_TOTAL;
reg [4:0] R5_v_total_adj = V_TOTALADJ;
// Indexes 04h and 05h carry the horizontal retrace on an EGA, not the vertical
// total and its adjust. Kept alongside the MC6845 pair so the non-EGA instances
// of this CRTC are untouched.
reg [7:0] R4_h_retrace_start_e = 8'd0;
reg [4:0] R5_h_retrace_end_e = 5'd0;
reg [7:0] R6_v_displayed = V_DISP;
reg [7:0] R7_v_sync_pos = V_SYNCPOS;
reg [1:0] R8_skew;
reg [1:0] R8_interlace = 2'd2;
// EGA index 08h is Preset Row Scan, not the MC6845 interlace/skew register.
// Its low five bits seed the character scanline counter at frame start and
// provide the fine vertical half of smooth text scrolling.
reg [4:0] R8_preset_row_scan_e = 5'd0;
reg [7:0] R9_v_max_line = {3'b000, V_MAXSCAN};
reg [1:0] R10_cursor_mode = 2'd0;
reg [4:0] R10_cursor_start = C_START;
reg [4:0] R11_cursor_end = C_END;
reg [7:0] R12_start_addr_h = 8'd0;
reg [7:0] R13_start_addr_l = 8'd0;
reg [5:0] R14_cursor_h = 6'd0;
reg [7:0] R15_cursor_l = 8'd0;
reg [7:0] R16_v_sync_pos_e = 8'd0;
reg [7:0] R17_v_sync_end_e = EGA_RESET_R17;
reg [7:0] R18_v_display_end_e = 8'd0;
reg [7:0] R19_offset_e = 8'd0;
reg [7:0] R20_underline_loc_e = 8'd0;
reg [7:0] R21_v_blank_start_e = 8'd0;
reg [7:0] R22_v_blank_end_e = 8'd0;
reg [7:0] R23_mode_control_e = 8'h80;
reg [7:0] R24_line_compare_e = 8'hFF;
reg       ega_status_vretrace = 1'b0;
reg       ega_vert_blank_active_r = 1'b0;
reg [3:0] ega_scanline_mod16 = 4'd0;
reg [3:0] ega_vslines = 4'd0;

// Effective vsync width: OSD override (1-7) takes priority, 0 = use register/CRTC_TYPE default
wire [3:0] eff_v_sync_width = |vsync_width_osd ? {1'b0, vsync_width_osd} :
	(CRTC_TYPE ? (|R17_v_sync_end_e[3:0] ? R17_v_sync_end_e[3:0] : 4'd1) : R3_v_sync_width);
wire ega_ext_timing = ega_crtc_semantics && (|R16_v_sync_pos_e || |R18_v_display_end_e || |R19_offset_e || |R21_v_blank_start_e || |R22_v_blank_end_e);
wire ega_v_blank_start_valid = ega_ext_timing && |R21_v_blank_start_e;
wire ega_v_blank_end_valid = ega_ext_timing && |R22_v_blank_end_e;
wire [9:0] eff_v_total = ega_ext_timing ? ({R7_v_sync_pos[5], R7_v_sync_pos[0], R6_v_displayed} + 10'd2) : {3'd0, R4_v_total};
wire [9:0] eff_v_displayed = ega_ext_timing ? ({R7_v_sync_pos[6], R7_v_sync_pos[1], R18_v_display_end_e} + 10'd1) : {3'd0, R6_v_displayed[6:0]};
wire [9:0] eff_v_sync_pos = ega_ext_timing ? ({R7_v_sync_pos[7], R7_v_sync_pos[2], R16_v_sync_pos_e} + 10'd1) : {3'd0, R7_v_sync_pos[6:0]};
assign V_DISP_REG = eff_v_displayed;
wire [9:0] eff_v_blank_start = ega_v_blank_start_valid ? {1'b0, R7_v_sync_pos[3], R21_v_blank_start_e} : eff_v_displayed;

wire [9:0] eff_v_blank_end = ega_v_blank_end_valid ? {2'd0, R22_v_blank_end_e} : 10'd0;

// Whether what this mode emits is bound for a television.
//
// One question, answered once, because both halves of the sync placement turn
// on it - and answered here rather than beside the horizontal half, because the
// vertical half is decided further up the file. The geometry answers it on its
// own: a line with blanking enough to hold the fixed lead below is a 200 line
// block, and what cannot hold it is the 350 line enhanced modes and MDA, which
// go to an enhanced display, a 5151 or the scaler and never to a set.
//
// Everything a television needs and a monitor does not hangs off this: the
// fixed pulse position, the standard width, the vertical lead, and the CRT H
// and V offsets themselves. Left ungated those controls walk a 350 line mode's
// pulse into its own active video, where the scaler frames the line - or the
// frame - in the wrong place. The converted 480i and 240p paths are unaffected
// either way: they capture on display enable and build their own raster.
localparam [7:0] TV_LEAD_CHARS_HI   = 8'd32;  // 256 dots at 8 dots per character
localparam [7:0] TV_LEAD_CHARS_LO   = 8'd16;  // 256 dots at 16

wire [8:0] eff_h_total   = ega_crtc_semantics ? ({1'b0, R0_h_total} + 9'd1) : {1'b0, R0_h_total};
wire [7:0] tv_lead_chars = hres_mode ? TV_LEAD_CHARS_HI : TV_LEAD_CHARS_LO;

// Compared before the subtraction, so a line shorter than the lead falls out
// here rather than wrapping into a sync position the counter never reaches.

wire tv_geometry = ega_crtc_semantics &&
                   ((eff_h_total + 9'd1) > ({1'b0, R1_h_displayed} + {1'b0, tv_lead_chars}));
// VSYNC is generated four scanlines ahead of where the CRTC asks for it, and
// the delay line at the bottom of the file puts it back. The vertical offset
// control can only ever delay VSYNC, so without this the position the mode asks
// for is the bottom of its travel with nothing below it; advancing by half the
// travel puts it in the middle instead.
//
// Only for the modes a set sees. A 350 line mode given this lead has its VSYNC
// pulled four lines into its own picture, and the scaler frames the frame from
// there.
//
// Guarded, because a mode whose sync starts in the first few scanlines would
// wrap the compare to a row the counter never reaches and emit no VSYNC at all.
// Only the emitted pulse moves: the retrace bit software polls is timed off
// eff_v_sync_pos further down and does not shift with it.
localparam [9:0] TV_VSYNC_LEAD_LINES = 10'd4;
wire       tv_vsync_lead_fits = tv_geometry && (eff_v_sync_pos > 10'd8);
wire [9:0] eff_v_sync_match = eff_v_sync_pos
                              - (tv_vsync_lead_fits ? TV_VSYNC_LEAD_LINES : 10'd0)
                              - (hres_mode ? 10'd1 : 10'd2);

reg [4:0] addr;
wire ega_crtc_write_protect = ega_crtc_semantics && R17_v_sync_end_e[7];

always @(*) begin
	DO = 8'hFF;
	if (ENABLE & ~nCS) begin
		if (RS) begin
			case (addr)
				00: DO = ega_crtc_semantics ? R0_h_total : 8'h00;
				01: DO = ega_crtc_semantics ? R1_h_displayed : 8'h00;
				02: DO = ega_crtc_semantics ? R2_h_sync_pos : 8'h00;
				03: DO = ega_crtc_semantics ? {R3_v_sync_width, R3_h_sync_width} : 8'h00;
				04: DO = ega_crtc_semantics ? R4_h_retrace_start_e : 8'h00;
				05: DO = ega_crtc_semantics ? {3'b000, R5_h_retrace_end_e} : 8'h00;
				06: DO = ega_crtc_semantics ? R6_v_displayed : 8'h00;
				07: DO = ega_crtc_semantics ? R7_v_sync_pos : 8'h00;
				08: DO = ega_crtc_semantics ? {3'b000, R8_preset_row_scan_e} : 8'h00;
				09: DO = ega_crtc_semantics ? R9_v_max_line : 8'h00;
				10: DO = {R10_cursor_mode, R10_cursor_start};
				11: DO = R11_cursor_end;
				12: DO = R12_start_addr_h;
				13: DO = R13_start_addr_l;
				14: DO = R14_cursor_h;
				15: DO = R15_cursor_l;
				16: DO = ega_crtc_semantics ? R16_v_sync_pos_e : 8'h00;
				17: DO = ega_crtc_semantics ? R17_v_sync_end_e : 8'h00;
				18: DO = ega_crtc_semantics ? R18_v_display_end_e : 8'h00;
				19: DO = ega_crtc_semantics ? R19_offset_e : 8'h00;
				20: DO = ega_crtc_semantics ? R20_underline_loc_e : 8'h00;
				21: DO = ega_crtc_semantics ? R21_v_blank_start_e : 8'h00;
				22: DO = ega_crtc_semantics ? R22_v_blank_end_e : 8'h00;
				23: DO = ega_crtc_semantics ? R23_mode_control_e : 8'h00;
				24: DO = ega_crtc_semantics ? R24_line_compare_e : 8'h00;
				31: DO = ega_crtc_semantics ? 8'hFF : 8'h00;
			 default: DO = 0;
			endcase
		end
		else if(CRTC_TYPE) begin
			DO = vde ? 8'h00 : 8'h20; // status for CRTC1
		end
	end
end

always @(posedge CLOCK) begin
	if (~nRESET) begin
		addr <= 5'd0;
		R0_h_total <= H_TOTAL;
		R1_h_displayed <= H_DISP;
		R2_h_sync_pos <= H_SYNCPOS;
		R3_v_sync_width <= 4'd0;
		R3_h_sync_width <= H_SYNCWIDTH;
		R4_v_total <= V_TOTAL;
		R5_v_total_adj <= V_TOTALADJ;
		R4_h_retrace_start_e <= 8'd0;
		R5_h_retrace_end_e <= 5'd0;
		R6_v_displayed <= V_DISP;
		R7_v_sync_pos <= V_SYNCPOS;
		R8_skew <= 2'd0;
		R8_interlace <= 2'd2;
		R8_preset_row_scan_e <= 5'd0;
		R9_v_max_line <= {3'b000, V_MAXSCAN};
		R10_cursor_mode <= 2'd0;
		R10_cursor_start <= C_START;
		R11_cursor_end <= C_END;
		R12_start_addr_h <= 8'd0;
		R13_start_addr_l <= 8'd0;
		start_addr_latch <= 16'h0000;
		R14_cursor_h <= 6'd0;
		R15_cursor_l <= 8'd0;
		R16_v_sync_pos_e <= EGA_RESET_R16;
		R17_v_sync_end_e <= EGA_RESET_R17;
		R18_v_display_end_e <= EGA_RESET_R18;
		R19_offset_e <= EGA_RESET_R19;
		R20_underline_loc_e <= 8'd0;
		R21_v_blank_start_e <= 8'd0;
		R22_v_blank_end_e <= 8'd0;
		R23_mode_control_e <= 8'h80;
		R24_line_compare_e <= 8'hFF;
	end else if (ENABLE & ~nCS & ~R_nW) begin
		if (~RS) addr <= DI[4:0];
		else begin
			case (addr)
				00: if (!ega_crtc_write_protect) R0_h_total <= DI;
				01: if (!ega_crtc_write_protect) R1_h_displayed <= DI;
				02: if (!ega_crtc_write_protect) R2_h_sync_pos <= DI;
				03: if (!ega_crtc_write_protect) {R3_v_sync_width, R3_h_sync_width} <= DI;
				04: if (!ega_crtc_write_protect) begin
					if (ega_crtc_semantics) R4_h_retrace_start_e <= DI;
					else                    R4_v_total <= DI[6:0];
				end
				05: if (!ega_crtc_write_protect) begin
					if (ega_crtc_semantics) R5_h_retrace_end_e <= DI[4:0];
					else                    R5_v_total_adj <= DI[4:0];
				end
				06: if (!ega_crtc_write_protect) R6_v_displayed <= DI;
				07: R7_v_sync_pos <= ega_crtc_write_protect
					? {R7_v_sync_pos[7:5], DI[4], R7_v_sync_pos[3:0]}
					: DI; //R7_v_overflow <= DI;
				08: begin
					if(ega_crtc_semantics) R8_preset_row_scan_e <= DI[4:0];
					else {R8_skew, R8_interlace} <= {DI[5:4],DI[1:0]};
				end
				09: R9_v_max_line <= DI;
				10: {R10_cursor_mode,R10_cursor_start} <= DI[6:0];
				11: R11_cursor_end <= DI[4:0];
				12: begin R12_start_addr_h <= DI[7:0]; if (CRTC_TYPE) start_addr_latch[15:8] <= DI; end
				13: begin R13_start_addr_l <= DI[7:0]; if (CRTC_TYPE) start_addr_latch[7:0] <= DI; end
				14: R14_cursor_h <= DI[5:0];
				15: R15_cursor_l <= DI[7:0];
				16: if (ega_crtc_semantics) R16_v_sync_pos_e <= DI;
				17: if (ega_crtc_semantics) R17_v_sync_end_e <= DI;
				18: if (ega_crtc_semantics) R18_v_display_end_e <= DI;
				19: if (ega_crtc_semantics) R19_offset_e <= DI;
				20: if (ega_crtc_semantics) R20_underline_loc_e <= DI;
				21: if (ega_crtc_semantics) R21_v_blank_start_e <= DI;
				22: if (ega_crtc_semantics) R22_v_blank_end_e <= DI;
				23: if (ega_crtc_semantics) R23_mode_control_e <= DI;
				24: if (ega_crtc_semantics) R24_line_compare_e <= DI;
			endcase
		end
	end
end

wire [4:0] interlace = &R8_interlace[1:0];

reg        in_adj;

reg  [7:0] hcc;
wire       hcc_last  = (hcc == eff_h_total[7:0]) && (CRTC_TYPE || R0_h_total); // always false if !R0_h_total on CRTC0
wire [7:0] hcc_next  = hcc_last ? 8'h00 : hcc + 1'd1;

reg  [4:0] line;
wire [4:0] line_max  = (in_adj ? (|R5_v_total_adj ? R5_v_total_adj-1'd1 : 5'd0) : R9_v_max_line[4:0]) & ~interlace;
reg        line_last_r;
wire       line_last = (line == line_max) || !line_max;
wire [4:0] line_next = ((CRTC_TYPE ? line_last : line_last_r) ? 5'd0 : line + 1'd1 + interlace) & ~interlace;
wire       line_new  = hcc_last;

reg  [9:0] row;
reg        row_last_r;
wire       row_last  = (row == eff_v_total) || (!CRTC_TYPE && !R4_v_total);
wire       row_frame_last = ((CRTC_TYPE ? row_last : row_last_r) | in_adj) & ~frame_adj;
wire [9:0] row_next  = row_frame_last ? 10'd0 : row + 1'd1;
// EGA vertical timing registers count scanlines. Keep Maximum Scan Line for
// glyph row/address stepping, but do not multiply vtotal/vsync/dispend by it.
wire       row_new   = line_new & (ega_crtc_semantics ? 1'b1 :
                                   (CRTC_TYPE ? line_last : line_last_r));

reg        frame_adj_r;
wire       frame_adj_CRTC0 = (hcc == 2) ? frame_adj_r & |R5_v_total_adj : frame_adj_r;
wire       frame_adj_CRTC1 = row_last && ~in_adj && R5_v_total_adj;
wire       frame_adj = CRTC_TYPE ? frame_adj_CRTC1 : frame_adj_CRTC0;
wire       frame_new = row_new & row_frame_last;

// Line Compare / split screen. 86Box builds the compare in ega_recalctimings:
//
//     split = crtc[0x18];
//     if (crtc[7] & 0x10) split |= 0x100;
//     if (crtc[9] & 0x40) split |= 0x200;
//     split++;
//
// and acts on it in ega_poll once the scanline counter has advanced:
//
//     if (vc == split) { memaddr = memaddr_backup = 0; scanline = 0; }
//
// so the scanline the register names is the last one drawn from the start
// address, and the one after it restarts the display at address 0 with a fresh
// character row. That is what keeps a status area pinned to the bottom of the
// screen while everything above it scrolls.
wire [9:0] eff_line_compare = {R9_v_max_line[6], R7_v_sync_pos[4], R24_line_compare_e} + 10'd1;
// Cute Demo restores mode 03h and then writes Line Compare zero. Restarting
// address zero on every text row in that exact cleanup state leaves the
// display stuck on its first row. Do not disable text splits generally:
// EGAUTIL uses a non-zero top-page address in modes 03h and 01h and expects
// the lower part of the screen to restart at address zero.
wire       text_zero_page_line0_cleanup = ~R23_mode_control_e[6] &
                                           ({R12_start_addr_h, R13_start_addr_l} == 16'h0000) &
                                           (eff_line_compare == 10'd1);
wire       line_compare_hit = ega_crtc_semantics & ~text_zero_page_line0_cleanup &
                              row_new & (row_next == eff_line_compare);

// x86Box remaps interleaved byte addresses; this core fetches independent
// planes, so convert row_addr_r to byte space and return out_addr[17:2].
wire [19:0] ega_remap_in_addr = {2'b00, row_addr_r, 2'b00};
wire [19:0] ega_remap_word_ma13_addr = ((ega_remap_in_addr << 1) & 20'h3FFF8) |
                                       ((ega_remap_in_addr >> 13) & 20'h00004) |
                                       (ega_remap_in_addr & 20'hC0000);
wire [19:0] ega_remap_word_ma15_addr = ((ega_remap_in_addr << 1) & 20'h3FFF8) |
                                       ((ega_remap_in_addr >> 15) & 20'h00004) |
                                       (ega_remap_in_addr & 20'hC0000);
wire [19:0] ega_remap_dword_addr = ((ega_remap_in_addr << 2) & 20'h3FFF0) |
                                  ((ega_remap_in_addr >> 14) & 20'h0000C) |
                                  (ega_remap_in_addr & 20'hC0000);
wire [19:0] ega_remap_mode_addr = R20_underline_loc_e[6] ? ega_remap_dword_addr :
                                  R23_mode_control_e[6] ? ega_remap_in_addr :
                                  R23_mode_control_e[5] ? ega_remap_word_ma15_addr :
                                                          ega_remap_word_ma13_addr;
wire [19:0] ega_remap_row0_addr = R23_mode_control_e[0] ? ega_remap_mode_addr :
                                  ((ega_remap_mode_addr & 20'hF7FFF) |
                                   (line[0] ? 20'h08000 : 20'h00000));
wire [19:0] ega_remap_row_addr = R23_mode_control_e[1] ? ega_remap_row0_addr :
                                 ((ega_remap_row0_addr & 20'hEFFFF) |
                                  (line[1] ? 20'h10000 : 20'h00000));
assign ega_display_addr = ega_crtc_semantics ? ega_remap_row_addr[17:2] : row_addr_r;

// counters
reg  field;
always @(posedge CLOCK) begin
	if(~nRESET) begin
		hcc    <= 0;
		line   <= 0;
		row    <= 0;
		in_adj <= 0;
		field  <= 0;
		line_last_r <= 1'b0;
		row_last_r <= 1'b0;
		frame_adj_r <= 1'b0;
	end
	else if(CLKEN) begin
		hcc <= hcc_next;
		if(line_new) line <= line_next;
		if(hcc == 0) begin
			line_last_r <= line_last;
			row_last_r <= row_last;
			frame_adj_r <= line_last & row_last & ~in_adj;
		end
		// CRTC0 always schedule the adjustment run at HCC=0,
		// then at HCC=2 it decides that it really has to run
		if(hcc == 2) frame_adj_r <= frame_adj_r & |R5_v_total_adj;

		if(row_new) begin
			row <= row_next;
			if(frame_adj) in_adj <= 1;
			else if(frame_new) begin
				in_adj <= 0;
				row <= 0;
				// 86Box loads scanline from CRTC[08h] at vertical total.  Doing
				// the same here makes the first character row partial; once it
				// reaches Maximum Scan Line, normal Offset stepping resumes.
				if(ega_crtc_semantics) line <= R8_preset_row_scan_e;
				field <= ~field & R8_interlace[0];
			end
			// The split restarts the character row as well as the address, so
			// the lower screen does not inherit the scan line it landed on.
			if(line_compare_hit) line <= 5'd0;
		end
	end
end

wire CRTC1_reload =  CRTC_TYPE & (frame_new | (~line_last & !row & !hcc_next)); //CRTC1 reloads addr on every line of 1st row
wire CRTC0_reload = ~CRTC_TYPE & frame_new;
wire row_addr_save = hcc == R1_h_displayed && (CRTC_TYPE ? line_last : line_last_r);

// address
reg  [15:0] row_addr;   // saved pointer
reg  [15:0] row_addr_r; // current pointer
reg  [15:0] start_addr_latch;
reg  [15:0] start_addr_vsync;
reg  [15:0] start_addr_frame;
wire [15:0] crtc_reg_start_addr = {R12_start_addr_h, R13_start_addr_l};
reg  [13:0] cursor_addr_frame;
wire [13:0] crtc_reg_cursor_addr = {R14_cursor_h, R15_cursor_l};
wire [15:0] ega_row_advance = R9_v_max_line[7] ? {6'd0, R19_offset_e, 2'b00} :
                                                   {7'd0, R19_offset_e, 1'b0};
// Offset zero is a valid EGA value, not a request to fall back to the legacy
// MC6845 address accumulator. It repeats the same source row because the row
// advance is zero. EGAUTIL's Offset test changes R19 between zero and 20 once
// per scanline; changing the whole address algorithm with it turns the image
// into a diagonal smear instead of stretching the selected rows.
wire        ega_ma_mode = ega_crtc_semantics;
// 86Box samples the start address where it raises the retrace status bit, in
// ega_poll under "vc == vsyncstart":
//
//     ega->memaddr = ega->memaddr_backup = ega->memaddr_latch;
//
// not at the end of the frame. The distinction is the whole of smooth
// scrolling. Software scrolls by writing the start address, waiting for
// retrace, then writing the panning value for the same step - so the write for
// the *next* step lands just after retrace begins, in the same blanking
// interval. Sampled at retrace it waits for the following frame and stays in
// step with its panning value; sampled at the end of the frame it overtakes it
// by one frame, and the picture jumps a character backwards every eighth step
// while moving smoothly in between.
wire        ega_start_addr_sample = ega_crtc_semantics & row_new &
                                    (row_next == eff_v_sync_pos);
wire [15:0] crtc1_reload_addr = ega_crtc_semantics ?
                                (frame_new ? start_addr_vsync : start_addr_frame) :
                                crtc_reg_start_addr;
always @(posedge CLOCK) begin
	if(~nRESET) begin
		row_addr <= crtc_reg_start_addr;
		row_addr_r <= crtc_reg_start_addr;
		start_addr_vsync <= crtc_reg_start_addr;
		start_addr_frame <= crtc_reg_start_addr;
		cursor_addr_frame <= crtc_reg_cursor_addr;
	end
	else if(CLKEN) begin
		if(ega_start_addr_sample) start_addr_vsync <= start_addr_latch;
		if(ega_crtc_semantics && frame_new) begin
			start_addr_frame <= start_addr_vsync;
			cursor_addr_frame <= crtc_reg_cursor_addr;
		end
		if(ega_ma_mode) begin
			if(!hcc_last) begin
				row_addr_r <= row_addr_r + 16'd1;
			end else if(frame_new) begin
				row_addr <= start_addr_vsync;
				row_addr_r <= start_addr_vsync;
			end else if(line_compare_hit) begin
				row_addr <= 16'd0;
				row_addr_r <= 16'd0;
			end else if(line_last) begin
				row_addr <= row_addr + ega_row_advance;
				row_addr_r <= row_addr + ega_row_advance;
			end else begin
				row_addr_r <= row_addr;
			end
		end else begin
			if(row_addr_save) row_addr <= row_addr_r; // save current pointer

			if(hcc_last & !row_addr_save) row_addr_r <= row_addr; // restore the pointer, take care of simultaneous saving and restoring
			if(!hcc_last)                 row_addr_r <= row_addr_r + 1'd1;

			if(CRTC0_reload) begin
				row_addr <= crtc_reg_start_addr;
				row_addr_r <= crtc_reg_start_addr;
			end
			if(CRTC1_reload) begin
				row_addr_r <= crtc1_reload_addr;
			end
		end
	end
end

// horizontal output
reg        hde;
reg  [3:0] hsc;

// Where the sync pulse goes.
//
// An EGA takes the retrace from indexes 04h and 05h: 04h is the character it
// starts on and 05h is compared against the low five bits of the character
// counter to end it. Indexes 02h and 03h are the blanking window. That is what
// the real chip does, and it is what the fallback below still does.
//
// It is the wrong thing to send to a television, though. Every block of the
// option ROM parameter table carries its own front porch, sized for a 5153 or a
// 5154, so each mode lands somewhere different against the sync and no single
// CRT H offset centres them all.
//
// So where the geometry allows it the pulse is placed a fixed distance ahead of
// the first active dot instead, which is what a television wants - a constant
// back porch, and a picture in the same place whatever the mode programs.
// Active video starts at hcc 0, so a fixed lead is just a fixed number of
// characters before the end of the line, and 32 characters at the full dot
// clock and 16 at the halved one are both 256 dots.
//
// This moves only the pulse that leaves the chip. hcc, the display enable and
// the status register software polls for retrace are untouched, so nothing the
// emulated PC can observe changes with it.
localparam [6:0] TV_SYNC_WIDTH_DOTS = 7'd64;  // 4.47 us at 14.318 MHz

wire [8:0] tv_sync_char  = eff_h_total + 9'd1 - {1'b0, tv_lead_chars};

wire [7:0] hcc_sync = hcc + (hres_mode ? 8'd3 : 8'd4);
wire ega_h_retrace_valid = ega_crtc_semantics && (|R4_h_retrace_start_e);

wire hsync_on = tv_geometry         ? (hcc == tv_sync_char[7:0])
              : ega_h_retrace_valid ? (hcc_sync == R4_h_retrace_start_e)
                                    : (hcc == (R2_h_sync_pos - (hres_mode ? 3 : 4)) && R3_h_sync_width != 0);

// Under the fixed geometry the raw pulse is only a trigger. Its width comes
// from the dot counter further down, so one character is enough here.
wire hsync_off = tv_geometry         ? (hsc == 4'd1)
               : ega_h_retrace_valid ? (hcc_sync[4:0] == R5_h_retrace_end_e)
                                     : ((hsc == R3_h_sync_width) || (CRTC_TYPE && R3_h_sync_width == 0));

reg hsync_raw;
always @(posedge CLOCK) begin

	if(~nRESET) begin
		hsc    <= 0;
		hde    <= 0;
		hsync_raw <= 0;
	end
	else begin
		// should be a half char delay (other edge of the clock?)
		if (hsync_off)     hsync_raw <= 0;
		else if (hsync_on) hsync_raw <= 1;

		if (ENABLE & RS & ~nCS & ~R_nW & addr == 5'd01 & hcc == DI) hde <= 0;

		if (CLKEN) begin
			if(line_new)                   hde <= 1;
			// Some adapters program R1 as "displayed chars - 1". Keep the
			// shared default behaviour unchanged and enable the +1 quirk only
			// on the instances that explicitly opt in.
			if(DISPLAYED_CHARS_PLUS1 ? (hcc == R1_h_displayed) : (hcc_next == R1_h_displayed)) hde <= 0;

			if(hsync_raw) hsc <= hsc + 1'd1;
			else hsc <= 0;
		end
	end
end

// Fixed-width HSYNC pulse shaping (for TV compatibility across 40/80-col modes)
// Detect rising edge of hsync_raw and generate a fixed-width pulse in pixel clocks.
reg hsync_raw_prev;
always @(posedge CLOCK) begin
	if(~nRESET) hsync_raw_prev <= 1'b0;
	else hsync_raw_prev <= hsync_raw;
end
wire hsync_rising = hsync_raw & ~hsync_raw_prev;

reg [6:0] hsync_fixed_cnt;
reg hsync_shaped;
// The OSD override still wins where it is offered. Otherwise the fixed
// geometry asks for the standard pulse, which is the other half of putting
// every mode in the same place: a television measures its back porch from the
// end of the pulse, so a width that varies by mode moves the picture on its
// own, however the leading edge is placed.
wire [6:0] hsync_fixed_width = |hsync_width_osd ? {1'b0, hsync_width_osd, 3'b0}
                                               : TV_SYNC_WIDTH_DOTS;
always @(posedge CLOCK) begin
	if (~nRESET) begin
		hsync_fixed_cnt <= 0;
		hsync_shaped <= 0;
	end else if (hsync_rising) begin
		hsync_fixed_cnt <= hsync_fixed_width - 1'd1;
		hsync_shaped <= 1;
	end else if (PIXEL_CE) begin
		if (|hsync_fixed_cnt) hsync_fixed_cnt <= hsync_fixed_cnt - 1'd1;
		else hsync_shaped <= 0;
	end
end

// Shaped whenever the fixed geometry is in play, and as before in the low
// resolution modes when the OSD override is set.
wire hsync_effective = (tv_geometry | (|hsync_width_osd & ~hres_mode)) ? hsync_shaped
                                                                      : hsync_raw;

// The delay is expressed in dots rather than clocks, so it tracks whichever dot
// clock is selected.
reg [95:0] hsync_delay_line;
// It trims the fixed lead down to the back porch actually wanted, four dots to
// a step of the OSD control, which is what centres a 640 dot picture in the
// 52 us a television shows. 96 stages rather than 64 because the travel starts
// well below the top of the lead and will not fit in a shorter line.
//
// The fallback takes no offset at all. The CRT H control is a television
// control, and everything left on this path is a mode no television sees, so
// these go where 04h and 05h ask and stay there. Walking their pulse is not
// harmless: it already sits close to the last active dot, and it is the pulse
// the scaler frames the line from.
wire [6:0] hsync_delay_index =
    tv_geometry ? (7'd85 - ({3'd0, crt_h_offset} << 2))
                : (hres_mode ? 7'd30 : 7'd60);
always @(posedge CLOCK) begin
    if(~nRESET) begin
        hsync_delay_line <= 96'd0;
        HSYNC <= 1'b0;
    end else if (PIXEL_CE) begin
        hsync_delay_line <= {hsync_delay_line[94:0], hsync_effective};
        HSYNC <= hsync_delay_line[hsync_delay_index];
    end
end

reg vsync_raw;
// vertical output
reg vde, vde_r;
reg VSYNC_r;
always @(posedge CLOCK) begin
	if(~nRESET) vsync_raw <= 1'b0;
	else vsync_raw <= VSYNC_r; // delay the same as HSYNC to not confuse the GA
end
always @(posedge CLOCK) begin
	reg  [3:0] vsc;
	reg        vsync_allow;

	if(~nRESET) begin
		vsc    <= 0;
		vde    <= 0;
		vde_r  <= 0;
		VSYNC_r<= 0;
		vsync_allow <= 1;
		ega_vert_blank_active_r <= 1'b0;
	end
	else if (CLKEN) begin
		if (!CRTC_TYPE && row == 0 && line == 0 && R6_v_displayed == 0) begin
			vde <= ~vde;
			vde_r <= ~vde_r;
		end

		if(row_new) begin
			if((frame_new & row !=0) | row_next != row) vsync_allow <= 1;
			if(frame_new) begin
				vde <= 1;
				vde_r <= 1;
				ega_vert_blank_active_r <= 1'b0;
			end
			if(row_next == eff_v_displayed) begin vde <= 0; vde_r <= 0; end
			if(CRTC_TYPE) begin
				if(row_next == eff_v_blank_start)
					ega_vert_blank_active_r <= 1'b1;
				if(ega_v_blank_end_valid && ega_vert_blank_active_r && row_next == eff_v_blank_end)
					ega_vert_blank_active_r <= 1'b0;
			end
		end
		if(field ? (hcc_next == {1'b0, R0_h_total[7:1]}) : line_new) begin
			if(vsc) vsc <= vsc - 1'd1;
			else if (vsync_allow & (field ? ((row == eff_v_sync_match) && !line) :
				((row_next == eff_v_sync_match) && (ega_crtc_semantics ? 1'b1 : line_last)))) begin
				VSYNC_r <= 1;
				// Don't allow a new vsync until a new row (Onescreen Colonies) or the R7 is written (PHX)
				vsync_allow <= 0;
				vsc <= eff_v_sync_width - 1'd1;
			end
			else VSYNC_r <= 0;
		end
	end
	else if (nCLKEN) begin
		if (!CRTC_TYPE && row == 0 && line == 0 && R6_v_displayed == 0) begin
			vde <= ~vde;
			vde_r <= ~vde_r;
		end
	end

	if (ENABLE & RS & ~nCS & ~R_nW & addr == 5'd07) begin
		vsync_allow <= 1;
		if (row == DI[6:0] && !VSYNC_r) begin
			// TODO: extra conditions for CRTC0
			VSYNC_r <= 1;
			vsc <= eff_v_sync_width - 1'd1;
		end
	end
	if (nCLKEN & ENABLE & RS & ~nCS & ~R_nW & addr == 5'd06) begin
		if (CRTC_TYPE) begin
			if (row == DI[6:0]) vde_r <= 0;
			if (row != DI[6:0] && DI[6:0] != 0) vde <= vde_r;
			if (row == eff_v_displayed && DI[6:0] != row) vde <= 1;
			if (row == DI[6:0] || DI[6:0] == 0) vde <= 0;
		end else begin
			if (row == DI[6:0] && !(row == 0 && line == 0)) vde_r <= 0;
		end
	end
end

always @(posedge CLOCK) begin
	if(~nRESET) begin
		ega_status_vretrace <= 1'b0;
		ega_scanline_mod16 <= 4'd0;
		ega_vslines <= 4'd0;
	end
	else if (CLKEN && ega_crtc_semantics) begin
		if(frame_new)
			ega_scanline_mod16 <= 4'd0;
		else if(line_new)
			ega_scanline_mod16 <= ega_scanline_mod16 + 4'd1;

		if(line_new && ega_status_vretrace) begin
			if(ega_vslines != 4'd0 && ega_scanline_mod16 == R17_v_sync_end_e[3:0])
				ega_status_vretrace <= 1'b0;
			ega_vslines <= ega_vslines + 4'd1;
		end

		if(row_new && row_next == eff_v_sync_pos) begin
			ega_status_vretrace <= 1'b1;
			ega_vslines <= 4'd0;
		end
	end
	else if (CLKEN) begin
		ega_status_vretrace <= 1'b0;
		ega_scanline_mod16 <= 4'd0;
		ega_vslines <= 4'd0;
	end
end

reg [8:0] vsync_delay_line;
// Delay in scanlines, trimming the four line lead above back to what is wanted,
// which puts the position the mode asks for in the middle of the control's
// travel rather than at one end of it.
//
// Nothing at all on the fallback: it took no lead above, so it has nothing to
// trim and its VSYNC goes where the mode's own registers put it.
wire [3:0] vsync_delay_index = ega_crtc_semantics
                             ? (tv_geometry ? (4'd8 - {1'b0, crt_v_offset}) : 4'd0)
                             : (4'd7 - {1'b0, crt_v_offset});

// This used to be clocked by HSYNC itself, an unconstrained derived clock
// whose phase against CLOCK was fixed only while the dot clock was a uniform
// divide by two.  Advance it on the dot where HSYNC rises instead, so VSYNC
// changes on a dot boundary and keeps a fixed relationship with DE.  That
// matters in the 350 line modes, whose vertical front porch is zero.
reg hsync_dot_q;
wire hsync_dot_rise = PIXEL_CE & HSYNC & ~hsync_dot_q;
always @(posedge CLOCK) begin
    if(~nRESET) hsync_dot_q <= 1'b0;
    else if (PIXEL_CE) hsync_dot_q <= HSYNC;
end

always @(posedge CLOCK) begin
    if(~nRESET) begin
        vsync_delay_line <= 9'd0;
        VSYNC <= 1'b0;
    end else if (hsync_dot_rise) begin
        vsync_delay_line <= {vsync_delay_line[7:0], vsync_raw};
        VSYNC <= vsync_delay_line[vsync_delay_index];
    end
end

wire [3:0] de = {1'b0, dde[1:0], hde & vde & vde_r};
reg  [1:0] dde;
always @(posedge CLOCK) begin
	if(~nRESET) dde <= 2'b00;
	else if (CLKEN) dde <= {dde[0],de[0]};
end

// Cursor control
reg cursor_line;
wire [4:0] cursor_end_next = R11_cursor_end + 5'd1;

// The scanline counter does not always advance through line_next: a new frame
// and a line compare split both slam it to 0. Mirror that here, or the cursor
// latch misses the transition and carries its state across the boundary - with
// a start past end, which is exactly what the BIOS programs for the 200 line
// modes, it stayed on into scanline 0 and drew a stray line at the top of the
// cell. The 350 line modes were unaffected because there the BIOS writes a
// start below its end and the latch is already off by then.
wire       line_forced_zero = row_new & ((ega_crtc_semantics & frame_new & ~frame_adj)
                                         | line_compare_hit);
wire [4:0] line_next_eff    = line_forced_zero ? 5'd0 : line_next;
assign CURSOR = hde & vde &
                ((ega_crtc_semantics ? row_addr_r[13:0] : MA) ==
                 (ega_crtc_semantics ? cursor_addr_frame : crtc_reg_cursor_addr)) &
                cursor_line & ~R10_cursor_mode[0];

always @(posedge CLOCK) begin

	if(~nRESET) begin
		cursor_line <= 0;
	end
	// Decide at the end of a scanline, for the one about to be drawn. 86Box
	// does the same in ega_poll: it clears cursorvisible against the scanline
	// just finished and sets it against the already incremented one, so the
	// flag is settled before the line is rendered. Deciding against the
	// current line instead left it one character time late, and since the text
	// pipeline samples the cursor once at the start of each cell, a cursor in
	// column 0 missed its own first scanline entirely - the BIOS underline 6,7
	// came out as a single line where 86Box draws two.
	//
	// The cursor covers R10 to R11 inclusive, so the clear belongs one scanline
	// past R11, and the clear at line 0 stands in for 86Box's
	// "|| scanline == rowcount". That second term also keeps the latch bounded:
	// cursor-end values a BIOS hands out can land past the last real scanline
	// of the current font - the IBM EGA BIOS's CGA cursor-shape emulation adds
	// 5 to both start and end under an Enhanced Color Display switch reading -
	// and line never reaches an out-of-range R11, so without it the cursor
	// would latch on at R10 and never turn off.
	else if (CLKEN && line_new) begin
		if (line_next_eff == R10_cursor_start)
			cursor_line <= 1;
		else if ((line_next_eff == cursor_end_next) || (line_next_eff == 5'd0))
			cursor_line <= 0;
	end
end

endmodule
