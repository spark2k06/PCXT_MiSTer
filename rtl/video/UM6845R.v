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
	output           FIELD,
	output           CURSOR,

	output    [13:0] MA,
	output     [4:0] RA,
	output    [3:0] hsync_width,
	// 8088 MPH uses a one-dot CRTC timing change (R0=72 then R0=71)
	// to select the other composite colour-burst phase. The value is
	// latched here because R0 ends at 71 after the switch.
	output           composite_phase,

	input      [3:0] crt_h_offset,
	input      [2:0] crt_v_offset,
	input      [2:0] vsync_width_osd, // OSD vsync pulse width: 0=Auto (use register), 1-7=override
	input      [2:0] hsync_width_osd, // OSD hsync pulse width: 0=Auto, 1-7=fixed (N*16 pixel clocks)
	input            hres_mode,
	// OSD "CRTC Frame Stacking": 0 = Native, 1 = Rebuilt (show one-frame-
	// per-scanline tricks on a synthetic raster). Synchronous to CLOCK.
	input            frame_stack_rebuild
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

/* verilator lint_off WIDTH */

assign FIELD = ~field & interlace[0];

// While stacked frames are being rebuilt, the raster seen by the rest of the
// card comes from the synthetic generator at the end of this file.
assign MA = sf_active ? s_ma : row_addr_r;
assign RA = sf_active ? 5'd0 : (line | (field & interlace[0]));
assign hsync_width = R3_h_sync_width;
assign composite_phase = composite_phase_reg;

assign DE = sf_active ? ((s_hde & s_main_line) | s_lone) : de[R8_skew & ~{2{CRTC_TYPE}}];

assign hblank = sf_active ? ~s_hde : ~hde;
assign vblank = sf_active ? ~s_vde : ~vde;
assign line_reset = hcc_last;

reg [7:0] R0_h_total = H_TOTAL;
reg       composite_phase_reg = 1'b0;
reg [7:0] R1_h_displayed = H_DISP;
reg [7:0] R2_h_sync_pos = H_SYNCPOS;
reg [3:0] R3_v_sync_width;
reg [3:0] R3_h_sync_width = H_SYNCWIDTH;
reg [6:0] R4_v_total = V_TOTAL;
reg [4:0] R5_v_total_adj = V_TOTALADJ;
reg [6:0] R6_v_displayed = V_DISP;
reg [6:0] R7_v_sync_pos = V_SYNCPOS;
reg [1:0] R8_skew;
reg [1:0] R8_interlace = 2'd2;
reg [4:0] R9_v_max_line = V_MAXSCAN;
reg [1:0] R10_cursor_mode = 2'd0;
reg [4:0] R10_cursor_start = C_START;
reg [4:0] R11_cursor_end = C_END;
reg [5:0] R12_start_addr_h = 6'd0;
reg [7:0] R13_start_addr_l = 8'd0;
reg [5:0] R14_cursor_h = 6'd0;
reg [7:0] R15_cursor_l = 8'd0;

// Effective vsync width: OSD override (1-7) takes priority, 0 = use register/CRTC_TYPE default
wire [3:0] eff_v_sync_width = |vsync_width_osd ? {1'b0, vsync_width_osd} : (CRTC_TYPE ? 4'd0 : R3_v_sync_width);

reg [4:0] addr;
always @(*) begin
	DO = 8'hFF;
	if (ENABLE & ~nCS) begin
		if (RS) begin
			case (addr)
				10: DO = {R10_cursor_mode, R10_cursor_start};
				11: DO = R11_cursor_end;
				12: DO = CRTC_TYPE ? 8'h00 : R12_start_addr_h;
				13: DO = CRTC_TYPE ? 8'h00 : R13_start_addr_l;
				14: DO = R14_cursor_h;
				15: DO = R15_cursor_l;
				31: DO = CRTC_TYPE ? 8'hFF : 8'h00;
			 default: DO = 0;
			endcase
		end
		else if(CRTC_TYPE) begin
			DO = vde ? 8'h00 : 8'h20; // status for CRTC1
		end
	end
end

always @(posedge CLOCK) begin
	if (ENABLE & ~nCS & ~R_nW) begin
		if (~RS) addr <= DI[4:0];
		else begin
			case (addr)
				00: begin
					// The calibration program changes R0 from the normal odd
					// total (71h) to an even total (72h), then writes 71h back.
					// Count the even write once so the setting survives the
					// write-back; another switch toggles it again.
					if ((R0_h_total == 8'h71) && (DI == 8'h72))
						composite_phase_reg <= ~composite_phase_reg;
					R0_h_total <= DI;
				end
				01: R1_h_displayed <= DI;
				02: R2_h_sync_pos <= DI;
				03: {R3_v_sync_width,R3_h_sync_width} <= DI;
				04: R4_v_total <= DI[6:0];
				05: R5_v_total_adj <= DI[4:0];
				06: R6_v_displayed <= DI[6:0];
				07: R7_v_sync_pos <= DI[6:0];
				08: {R8_skew, R8_interlace} <= {DI[5:4],DI[1:0]};
				09: R9_v_max_line <= DI[4:0];
				10: {R10_cursor_mode,R10_cursor_start} <= DI[6:0];
				11: R11_cursor_end <= DI[4:0];
				12: R12_start_addr_h <= DI[5:0];
				13: R13_start_addr_l <= DI[7:0];
				14: R14_cursor_h <= DI[5:0];
				15: R15_cursor_l <= DI[7:0];
			endcase
		end
	end
end

wire [4:0] interlace = &R8_interlace[1:0];

reg        in_adj;

reg  [7:0] hcc;
wire       hcc_last  = (hcc == R0_h_total) && (CRTC_TYPE || R0_h_total); // always false if !R0_h_total on CRTC0
wire [7:0] hcc_next  = hcc_last ? 8'h00 : hcc + 1'd1;

reg  [4:0] line;
wire [4:0] line_max  = (in_adj ? (|R5_v_total_adj ? R5_v_total_adj-1'd1 : 5'd0) : R9_v_max_line) & ~interlace;
reg        line_last_r;
wire       line_last = (line == line_max) || !line_max;
wire [4:0] line_next = ((CRTC_TYPE ? line_last : line_last_r) ? 5'd0 : line + 1'd1 + interlace) & ~interlace;
wire       line_new  = hcc_last;

reg  [6:0] row;
reg        row_last_r;
wire       row_last  = (row == R4_v_total) || (!CRTC_TYPE && !R4_v_total);
wire       row_frame_last = ((CRTC_TYPE ? row_last : row_last_r) | in_adj) & ~frame_adj;
wire [6:0] row_next  = row_frame_last ? 7'd0 : row + 1'd1;
wire       row_new   = line_new & (CRTC_TYPE ? line_last : line_last_r);

reg        frame_adj_r;
wire       frame_adj_CRTC0 = (hcc == 2) ? frame_adj_r & |R5_v_total_adj : frame_adj_r;
wire       frame_adj_CRTC1 = row_last && ~in_adj && R5_v_total_adj;
wire       frame_adj = CRTC_TYPE ? frame_adj_CRTC1 : frame_adj_CRTC0;
wire       frame_new = row_new & row_frame_last;

// counters
reg  field;
always @(posedge CLOCK) begin
	if(~nRESET) begin
		hcc    <= 0;
		line   <= 0;
		row    <= 0;
		in_adj <= 0;
		field  <= 0;
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
				field <= ~field & R8_interlace[0];
			end
		end
	end
end

wire CRTC1_reload =  CRTC_TYPE & (frame_new | (~line_last & !row & !hcc_next)); //CRTC1 reloads addr on every line of 1st row
wire CRTC0_reload = ~CRTC_TYPE & frame_new;
wire row_addr_save = hcc == R1_h_displayed && (CRTC_TYPE ? line_last : line_last_r);

// address
reg  [13:0] row_addr;   // saved pointer
reg  [13:0] row_addr_r; // current pointer
always @(posedge CLOCK) begin
	if(CLKEN) begin
		if(row_addr_save) row_addr <= row_addr_r; // save current pointer

		if(hcc_last & !row_addr_save) row_addr_r <= row_addr; // restore the pointer, take care of simultaneous saving and restoring
		if(!hcc_last)                 row_addr_r <= row_addr_r + 1'd1;

		if(CRTC0_reload) begin
			row_addr <= {R12_start_addr_h, R13_start_addr_l};
			row_addr_r <= {R12_start_addr_h, R13_start_addr_l};
		end
		if(CRTC1_reload) begin
			row_addr_r <= {R12_start_addr_h, R13_start_addr_l};
		end
	end
end

// horizontal output
reg        hde;
reg  [3:0] hsc;

// HSYNC starts a few characters early because the output delay line below
// moves it back.  The plain subtraction wrapped when R2 was smaller than that
// lead, so HSYNC never started (Area 5150's Lake effect puts R2=2 in a
// 26-character row).  An earlier start would have to happen in the previous
// row, before this row's R2 is known, so start at R2 itself: late by the
// lead, but present.
wire [7:0] hsync_lead  = hres_mode ? 8'd3 : 8'd4;
wire [7:0] hsync_start = (R2_h_sync_pos >= hsync_lead) ? R2_h_sync_pos - hsync_lead : R2_h_sync_pos;
wire hsync_on = hcc == hsync_start && R3_h_sync_width != 0;
wire hsync_off = (hsc == R3_h_sync_width) || (CRTC_TYPE && R3_h_sync_width == 0);

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
			if(hcc_next == R1_h_displayed) hde <= 0;

			if(hsync_raw) hsc <= hsc + 1'd1;
			else hsc <= 0;
		end
	end
end

wire hsync_src = sf_active ? s_hsync_raw : hsync_raw;

// Fixed-width HSYNC pulse shaping (for TV compatibility across 40/80-col modes)
// Detect rising edge of hsync_raw and generate a fixed-width pulse in pixel clocks.
reg hsync_raw_prev;
always @(posedge CLOCK) hsync_raw_prev <= hsync_src;
wire hsync_rising = hsync_src & ~hsync_raw_prev;

reg [6:0] hsync_fixed_cnt;
reg hsync_shaped;
always @(posedge CLOCK) begin
	if (~nRESET) begin
		hsync_fixed_cnt <= 0;
		hsync_shaped <= 0;
	end else if (hsync_rising) begin
		hsync_fixed_cnt <= {hsync_width_osd, 4'b0} - 1'd1; // N * 16 pixel clocks
		hsync_shaped <= 1;
	end else if (|hsync_fixed_cnt) begin
		hsync_fixed_cnt <= hsync_fixed_cnt - 1'd1;
	end else begin
		hsync_shaped <= 0;
	end
end

// Use reshaped HSYNC only in low-res (40-col) mode when OSD override is active.
wire hsync_effective = (|hsync_width_osd & ~hres_mode) ? hsync_shaped : hsync_src;

reg [121:0] hsync_delay_line;
wire [6:0] hsync_delay_index = hres_mode ?
                               (7'd60  - {crt_h_offset, 2'b00}) :
                               (7'd120 - {crt_h_offset, 3'b000});

// The OSD CRT H offset starts HSYNC earlier.  When the display reaches close
// to the sync position (Area 5150's 96-column screens: R1 = 96, R2 = 98) that
// would start HSYNC on the last visible characters, where it blanks them and,
// on HDMI, moves the VSYNC edge into the visible line.  A pulse whose early
// start would fall while the display (or the pixels still in the pipeline) is
// on comes out at its position without offset instead.  With no offset both
// positions are the same.
wire       h_disp   = sf_active ? s_hde : hde;
reg  [7:0] h_disp_q = 8'd0;
wire       h_busy   = h_disp | (|h_disp_q);
wire       hs_offs  = hsync_delay_line[hsync_delay_index];
wire       hs_dflt  = hsync_delay_line[hres_mode ? 7'd60 : 7'd120];
reg        hs_offs_q = 1'b0, hs_dflt_q = 1'b0, hs_late = 1'b0;
wire       hs_start = hs_offs & ~hs_offs_q;
wire       hs_late_now = hs_start ? h_busy : hs_late;
wire hsync_next = hs_late_now ? hs_dflt : hs_offs;

always @(posedge CLOCK) begin
    hsync_delay_line <= {hsync_delay_line[120:0], hsync_effective};
    HSYNC <= hsync_next;
    h_disp_q  <= {h_disp_q[6:0], h_disp};
    hs_offs_q <= hs_offs;
    hs_dflt_q <= hs_dflt;
    if (hs_start)                hs_late <= h_busy;
    else if (hs_dflt_q & ~hs_dflt) hs_late <= 1'b0;
end

// vertical output
//
// VSYNC is normally started one row early and then delayed by up to eight
// lines (vsync_delay_line), so that the OSD "CRT V offset" can also move it
// up.  When R7 is in the first row(s) of a frame, the row before it belongs
// to the previous frame: a program that restarts frames (Area 5150 sets
// R4 = 8, R7 = 1 just after a frame starts) then gets VSYNC a whole frame
// late, in the middle of its picture.  There, start VSYNC on row R7 itself
// and send it out without the delay; the V offset does not apply to it.
reg vde, vde_r;
reg VSYNC_r;
reg vs_direct = 1'b0;
wire [6:0] vsync_lead  = hres_mode ? 7'd1 : 7'd2;
wire       vsync_early = R7_v_sync_pos > vsync_lead;
wire [6:0] vsync_row   = vsync_early ? R7_v_sync_pos - vsync_lead : R7_v_sync_pos;
always @(posedge CLOCK) begin
	reg  [3:0] vsc;
	reg        vsync_allow;

	if(~nRESET) begin
		vsc    <= 0;
		vde    <= 0;
		vde_r  <= 0;
		VSYNC_r<= 0;
		vs_direct <= 0;
		vsync_allow <= 1;
	end
	else if (CLKEN) begin
		if (!CRTC_TYPE && row == 0 && line == 0 && R6_v_displayed == 0) begin
			vde <= ~vde;
			vde_r <= ~vde_r;
		end

		if(row_new) begin
			if((frame_new & row !=0) | row_next != row) vsync_allow <= 1;
			if(frame_new)                  begin vde <= 1; vde_r <= 1; end
			if(row_next == R6_v_displayed) begin vde <= 0; vde_r <= 0; end
		end
		if(field ? (hcc_next == {1'b0, R0_h_total[7:1]}) : line_new) begin
			if(vsc) vsc <= vsc - 1'd1;
			else if (vsync_allow & (field ? ((row == vsync_row) && !line) : ((row_next == vsync_row) && line_last))) begin
				VSYNC_r <= 1;
				vs_direct <= ~vsync_early;
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
			vs_direct <= 1'b0;
			vsc <= eff_v_sync_width - 1'd1;
		end
	end
	if (nCLKEN & ENABLE & RS & ~nCS & ~R_nW & addr == 5'd06) begin
		if (CRTC_TYPE) begin
			if (row == DI[6:0]) vde_r <= 0;
			if (row != DI[6:0] && DI[6:0] != 0) vde <= vde_r;
			if (row == R6_v_displayed && DI[6:0] != row) vde <= 1;
			if (row == DI[6:0] || DI[6:0] == 0) vde <= 0;
		end else begin
			if (row == DI[6:0] && !(row == 0 && line == 0)) vde_r <= 0;
		end
	end
end

reg [8:0] vsync_delay_line = 9'd0;
wire      vsync_delayed = vsync_delay_line[3'd7 - crt_v_offset];
always @(posedge CLOCK) begin
    if (~nRESET) begin
        vsync_delay_line <= 9'd0;
        VSYNC <= 1'b0;
    end
    else if (~HSYNC && hsync_next) begin
        // Shift on the same CLOCK edge that raises the delayed HSYNC output.
        // Sample the same VSYNC value that belongs to this delayed line edge.
        vsync_delay_line <= {vsync_delay_line[7:0], sf_active ? s_vsync : (VSYNC_r & ~vs_direct)};
        VSYNC <= vsync_delayed | (~sf_active & vs_direct & VSYNC_r);
    end
end

wire [3:0] de = {1'b0, dde[1:0], hde & vde & vde_r};
reg  [1:0] dde;
always @(posedge CLOCK) if (CLKEN) dde <= {dde[0],de[0]};

// Cursor control
reg cursor_line;
assign CURSOR = ~sf_active & hde & vde & MA == {R14_cursor_h, R15_cursor_l} & cursor_line;

always @(posedge CLOCK) begin

	if(~nRESET) begin
		cursor_line <= 0;
	end
	else if (CLKEN) begin
		if (line == R10_cursor_start)
			cursor_line <= 1;
		else if (line == R11_cursor_end)
			cursor_line <= 0;
		end
	end

// ---------------------------------------------------------------------------
// CRTC frame stacking, rebuilt (OSD "CRTC Frame Stacking": Native / Rebuilt)
//
// The 6845 loads the start address (R12/R13) only when a frame begins.
// "Frame stacking" makes frames begin more often than once per picture by
// programming a tiny frame (R4 = 0 or 1, R9 = 0).  Taken to its limit, R0/R1/R2
// are also rewritten in the middle of each scanline so that both rows of the
// frame share one physical line: every scanline is then a complete CRTC frame
// with its own start address, which software uses for per-line scrolling,
// mirrors and ripples.  Each write has to land within a few characters of its
// slot, so the trick needs a CPU and bus that are cycle-exact with the CGA.
//
// One program that does this is the end-credits water reflection of the
// Area 5150 demo.  At exactly 304 CPU cycles per scanline it writes eight
// registers: a 26-character row with one visible character (the frame start,
// which latches R12/R13) is followed by an 88-character row with 80 visible
// characters and no HSYNC.  On an IBM CGA this gives an ordinary 80-column
// raster in which scanline n shows characters A(n-1)+1 .. A(n-1)+80 in glyph
// row 0, plus character A(n) in the right overscan, A(k) being the start
// address written during scanline k.  A bus capture of a real IBM 5150
// running it confirms the write pattern and the A+1 offset.
//
// "Native" leaves all of this to the CRTC above.  With "Rebuilt" the register
// file behaves as before, but each start address written while frames are
// stacked is stored in order and the card shows those lines on a stable
// 114x262 raster of its own, so the picture depends on the order of the
// writes rather than on their timing.  While that raster is shown, the
// status port (3DA) reports its display enable and VSYNC.  The rebuilt lines
// use the split described above: 80-column timing, 80 characters from A+1,
// the overscan character at position 88 and up to 200 lines one line below
// the usual 80x25 text area.  A program that splits its lines differently is
// still shown on a stable raster, but not necessarily where a real CGA puts
// it.
//
// A stacked frame opens when R4 is written with 0 or 1 while R9 is 0: the
// current R12/R13 value is its line 0, and every completed R13 write adds the
// next line until R4 is set back above 1.  It only counts if R0 was also
// rewritten at least once per line on average: stacking frames inside the
// scanline needs a new row length on every line, whereas frames of one or two
// whole scanlines (R4 = 1 with R0 left alone, as in the wavy stripes that end
// Area 5150's twister part) are timed by the CRTC itself and are left to it.
// The lines go into a triple buffer:
// the program fills one bank while the raster shows another, and a finished
// frame (one of at least SF_MIN_LINES lines, ended by the next opening) is
// queued in the third and shown from the next picture on.  The raster runs
// freely at 262 lines, so every picture is one complete frame of the program
// and the program's own frame period does not matter: when its frames are
// longer than the raster's (a handler that overruns its timer period) a
// picture is shown twice, when shorter one is dropped.  The raster takes over
// when the first frame is finished and is released once SF_MISS_MAX + 1
// pictures have gone by without a stacked frame opening.
// ---------------------------------------------------------------------------
localparam [7:0] SF_HTOTAL     = 8'd113;  // 114 characters, as BIOS 80x25
localparam [7:0] SF_HDISP      = 8'd80;
localparam [7:0] SF_HSYNC      = 8'd90;   // BIOS 80x25 R2
localparam [7:0] SF_LONE_CHAR  = 8'd88;   // the frame-start row's character
localparam [8:0] SF_TOTAL      = 9'd262;
localparam [8:0] SF_FIRST_LINE = 9'd1;    // line 0 only carries a lone char
localparam [8:0] SF_LAST_LINE  = 9'd200;
localparam [8:0] SF_VSYNC_LINE = 9'd216;  // same placement as 80x25 here
localparam [7:0] SF_MIN_LINES  = 8'd32;   // shorter stacked frames are ignored
localparam [1:0] SF_MISS_MAX   = 2'd3;

reg        sf_active = 1'b0;
reg        sf_open   = 1'b0;
reg  [7:0] sf_idx    = 8'd0;   // lines recorded in the frame being written
reg  [7:0] sf_r0     = 8'd0;   // R0 writes in that frame
reg        sf_seen   = 1'b0;
reg  [1:0] sf_miss   = 2'd0;

// Banks 0..2: w_bank is being written, r_bank is on screen and q_bank holds
// the newest finished frame while q_valid is set.  w_bank never equals the
// other two, so a bank is never written while it is shown.
reg  [1:0] w_bank  = 2'd1;
reg  [1:0] r_bank  = 2'd0;
reg  [1:0] q_bank  = 2'd2;
reg        q_valid = 1'b0;
reg  [7:0] q_lines = 8'd0;
reg  [7:0] r_lines = 8'd0;

reg  [7:0] s_hcc  = 8'd0;
reg  [8:0] s_line = 9'd0;
reg        s_hde = 1'b0;
reg        s_vde = 1'b0;
reg        s_lone = 1'b0;
reg [13:0] s_ma = 14'd0;
reg        s_hsync_raw = 1'b0;
reg  [3:0] s_hsc = 4'd0;
reg        s_vsync = 1'b0;
reg  [3:0] s_vsc = 4'd0;

// Line start addresses, in the order the CPU wrote them, one bank per frame.
reg [13:0] sf_tbl[0:1023];
reg        sf_we = 1'b0;
reg  [9:0] sf_wa = 10'd0;
reg [13:0] sf_wd = 14'd0;
reg [13:0] s_tbl_q = 14'd0;

always @(posedge CLOCK) begin
	if (sf_we) sf_tbl[sf_wa] <= sf_wd;
	s_tbl_q <= sf_tbl[{r_bank, s_line[7:0]}];
end

// A data-register write is complete when its strobe falls; addr still names
// the register and the register already holds the value.
wire data_wr = ENABLE & ~nCS & ~R_nW & RS;
reg  data_wr_r = 1'b0;
always @(posedge CLOCK) data_wr_r <= data_wr;
wire data_wr_done = data_wr_r & ~data_wr;

wire [13:0] sf_start_addr = {R12_start_addr_h, R13_start_addr_l};
wire sf_frame_open  = frame_stack_rebuild & data_wr_done & (addr == 5'd4) &
                      (R4_v_total <= 7'd1) & (R9_v_max_line == 5'd0);
wire sf_frame_close = data_wr_done & (addr == 5'd4) & (R4_v_total > 7'd1);
wire sf_line_addr   = frame_stack_rebuild & data_wr_done & (addr == 5'd13) & sf_open;
wire sf_row_len     = data_wr_done & (addr == 5'd0) & sf_open;

wire       s_hlast     = (s_hcc == SF_HTOTAL);
wire [7:0] s_hcc_next  = s_hlast ? 8'd0 : s_hcc + 8'd1;
wire       s_vlast     = (s_line == SF_TOTAL - 9'd1);
wire [8:0] s_line_next = s_vlast ? 9'd0 : s_line + 9'd1;

// A new picture starts: show the queued frame, if any.
wire       s_wrap      = CLKEN & s_hlast & s_vlast;
wire       sf_swap     = s_wrap & q_valid & sf_active;
wire [1:0] r_bank_next = sf_swap ? q_bank : r_bank;

// An opening finishes the frame being written if it is long enough and its
// lines were split.  The next frame goes to the bank that is neither on
// screen nor just finished.
wire       sf_done     = sf_frame_open & (sf_idx >= SF_MIN_LINES) & (sf_r0 >= sf_idx);
wire [1:0] sf_free     = 2'd3 - r_bank_next - w_bank;
wire [1:0] w_bank_next = sf_done ? (sf_active ? sf_free : r_bank) : w_bank;

// Lines without a recorded address show the border.
wire s_main_line = s_vde && ({1'b0, r_lines} >= s_line);

wire s_hsync_on  = (s_hcc == SF_HSYNC - (hres_mode ? 8'd3 : 8'd4)) && R3_h_sync_width != 0;
wire s_hsync_off = (s_hsc == R3_h_sync_width) || (CRTC_TYPE && R3_h_sync_width == 0);

always @(posedge CLOCK) begin
	sf_we <= 1'b0;

	if (s_hsync_off)     s_hsync_raw <= 1'b0;
	else if (s_hsync_on) s_hsync_raw <= 1'b1;

	if (CLKEN) begin
		s_hcc <= s_hcc_next;
		if (s_hcc_next == 8'd0)     s_hde <= 1'b1;
		if (s_hcc_next == SF_HDISP) s_hde <= 1'b0;
		s_lone <= (s_hcc_next == SF_LONE_CHAR) && (s_line < SF_LAST_LINE) &&
		          ({1'b0, r_lines} > s_line);

		if (s_hcc_next == 8'd0)              s_ma <= s_tbl_q + 14'd1;
		else if (s_hcc_next == SF_LONE_CHAR) s_ma <= s_tbl_q;
		else                                 s_ma <= s_ma + 14'd1;

		if (s_hsync_raw) s_hsc <= s_hsc + 4'd1;
		else             s_hsc <= 4'd0;

		if (s_hlast) begin
			s_line <= s_line_next;
			s_vde  <= (s_line_next >= SF_FIRST_LINE) && (s_line_next <= SF_LAST_LINE);

			if (s_vsc) s_vsc <= s_vsc - 4'd1;
			else if (s_line_next == SF_VSYNC_LINE) begin
				s_vsync <= 1'b1;
				s_vsc   <= eff_v_sync_width - 4'd1;
			end
			else s_vsync <= 1'b0;

			if (s_vlast) begin
				if (sf_seen) sf_miss <= 2'd0;
				else if (sf_miss == SF_MISS_MAX) begin
					sf_active <= 1'b0;
					sf_idx    <= 8'd0;
				end
				else sf_miss <= sf_miss + 2'd1;
				sf_seen <= 1'b0;
			end
		end
	end

	if (sf_swap) begin
		r_bank  <= q_bank;
		r_lines <= q_lines;
		q_valid <= 1'b0;
	end

	if (sf_frame_open) begin
		sf_open <= 1'b1;
		sf_idx  <= 8'd1;
		sf_r0   <= 8'd0;
		sf_seen <= 1'b1;
		sf_we   <= 1'b1;
		sf_wa   <= {w_bank_next, 8'd0};
		sf_wd   <= sf_start_addr;
		w_bank  <= w_bank_next;
		if (sf_done) begin
			if (sf_active) begin
				q_bank  <= w_bank;
				q_lines <= sf_idx;
				q_valid <= 1'b1;
			end
			else begin
				// First finished frame: show it from a new picture that starts
				// in the bottom border, so VSYNC follows within a few lines.
				sf_active <= 1'b1;
				sf_miss   <= 2'd0;
				r_bank    <= w_bank;
				r_lines   <= sf_idx;
				q_valid   <= 1'b0;
				s_line    <= SF_LAST_LINE + 9'd1;
			end
		end
	end
	else if (sf_frame_close) begin
		sf_open <= 1'b0;
	end
	else if (sf_line_addr) begin
		sf_we <= 1'b1;
		sf_wa <= {w_bank, sf_idx};
		sf_wd <= sf_start_addr;
		if (~&sf_idx) sf_idx <= sf_idx + 8'd1;
	end

	if (sf_row_len && ~&sf_r0) sf_r0 <= sf_r0 + 8'd1;

	if (~nRESET | ~frame_stack_rebuild) begin
		sf_active <= 1'b0;
		sf_open   <= 1'b0;
		sf_seen   <= 1'b0;
		sf_miss   <= 2'd0;
		sf_idx    <= 8'd0;
		q_valid   <= 1'b0;
	end
end

endmodule
