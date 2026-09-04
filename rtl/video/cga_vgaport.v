// Graphics Gremlin
//
// Copyright (c) 2021 Eric Schlaepfer
// Composite decoder reworked in 2026 for transition-aware old-CGA NTSC.
// The electrical model and Y/I/Q filter follow the reenigne algorithm used
// by x86EMU/UniPCemu, expressed here as a streaming fixed-point pipeline.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

`default_nettype none

module cga_vgaport #(
    // Four possible carrier-reference alignments are useful in simulation;
    // production uses the calibrated default.
    parameter integer PHASE_OFFSET = 0
)(
    input  wire       clk,
    input  wire [4:0] clkdiv,
    input  wire [3:0] video,
    input  wire       composite,
    input  wire       hblank,
    input  wire       bw_mode,
    input  wire       hres_mode,
    input  wire       grph_mode,
    input  wire [3:0] hsync_width,
    input  wire [3:0] border_color,
    input  wire       phase,
    input  wire       scandouble,
    output wire [5:0] red,
    output wire [5:0] green,
    output wire [5:0] blue
);

    // Measured old-CGA chroma multiplexer levels. The address is
    // {left RGB, right RGB, NTSC phase}; intensity is handled separately.
    (* ramstyle = "logic" *) reg [7:0] chroma_multiplexer [0:255];

    initial begin
        chroma_multiplexer[  0] =   2; chroma_multiplexer[  1] =   2;
        chroma_multiplexer[  2] =   2; chroma_multiplexer[  3] =   2;
        chroma_multiplexer[  4] = 114; chroma_multiplexer[  5] = 174;
        chroma_multiplexer[  6] =   4; chroma_multiplexer[  7] =   3;
        chroma_multiplexer[  8] =   2; chroma_multiplexer[  9] =   1;
        chroma_multiplexer[ 10] = 133; chroma_multiplexer[ 11] = 135;
        chroma_multiplexer[ 12] =   2; chroma_multiplexer[ 13] = 113;
        chroma_multiplexer[ 14] = 150; chroma_multiplexer[ 15] =   4;
        chroma_multiplexer[ 16] = 133; chroma_multiplexer[ 17] =   2;
        chroma_multiplexer[ 18] =   1; chroma_multiplexer[ 19] =  99;
        chroma_multiplexer[ 20] = 151; chroma_multiplexer[ 21] = 152;
        chroma_multiplexer[ 22] =   2; chroma_multiplexer[ 23] =   1;
        chroma_multiplexer[ 24] =   3; chroma_multiplexer[ 25] =   2;
        chroma_multiplexer[ 26] =  96; chroma_multiplexer[ 27] = 136;
        chroma_multiplexer[ 28] = 151; chroma_multiplexer[ 29] = 152;
        chroma_multiplexer[ 30] = 151; chroma_multiplexer[ 31] = 152;
        chroma_multiplexer[ 32] =   2; chroma_multiplexer[ 33] =  56;
        chroma_multiplexer[ 34] =  62; chroma_multiplexer[ 35] =   4;
        chroma_multiplexer[ 36] = 111; chroma_multiplexer[ 37] = 250;
        chroma_multiplexer[ 38] = 118; chroma_multiplexer[ 39] =   4;
        chroma_multiplexer[ 40] =   0; chroma_multiplexer[ 41] =  51;
        chroma_multiplexer[ 42] = 207; chroma_multiplexer[ 43] = 137;
        chroma_multiplexer[ 44] =   1; chroma_multiplexer[ 45] = 171;
        chroma_multiplexer[ 46] = 209; chroma_multiplexer[ 47] =   5;
        chroma_multiplexer[ 48] = 140; chroma_multiplexer[ 49] =  50;
        chroma_multiplexer[ 50] =  54; chroma_multiplexer[ 51] = 100;
        chroma_multiplexer[ 52] = 133; chroma_multiplexer[ 53] = 202;
        chroma_multiplexer[ 54] =  57; chroma_multiplexer[ 55] =   4;
        chroma_multiplexer[ 56] =   2; chroma_multiplexer[ 57] =  50;
        chroma_multiplexer[ 58] = 153; chroma_multiplexer[ 59] = 149;
        chroma_multiplexer[ 60] = 128; chroma_multiplexer[ 61] = 198;
        chroma_multiplexer[ 62] = 198; chroma_multiplexer[ 63] = 135;
        chroma_multiplexer[ 64] =  32; chroma_multiplexer[ 65] =   1;
        chroma_multiplexer[ 66] =  36; chroma_multiplexer[ 67] =  81;
        chroma_multiplexer[ 68] = 147; chroma_multiplexer[ 69] = 158;
        chroma_multiplexer[ 70] =   1; chroma_multiplexer[ 71] =  42;
        chroma_multiplexer[ 72] =  33; chroma_multiplexer[ 73] =   1;
        chroma_multiplexer[ 74] = 210; chroma_multiplexer[ 75] = 254;
        chroma_multiplexer[ 76] =  34; chroma_multiplexer[ 77] = 109;
        chroma_multiplexer[ 78] = 169; chroma_multiplexer[ 79] =  77;
        chroma_multiplexer[ 80] = 177; chroma_multiplexer[ 81] =   2;
        chroma_multiplexer[ 82] =   0; chroma_multiplexer[ 83] = 165;
        chroma_multiplexer[ 84] = 189; chroma_multiplexer[ 85] = 154;
        chroma_multiplexer[ 86] =   3; chroma_multiplexer[ 87] =  44;
        chroma_multiplexer[ 88] =  33; chroma_multiplexer[ 89] =   0;
        chroma_multiplexer[ 90] =  91; chroma_multiplexer[ 91] = 197;
        chroma_multiplexer[ 92] = 178; chroma_multiplexer[ 93] = 142;
        chroma_multiplexer[ 94] = 144; chroma_multiplexer[ 95] = 192;
        chroma_multiplexer[ 96] =   4; chroma_multiplexer[ 97] =   2;
        chroma_multiplexer[ 98] =  61; chroma_multiplexer[ 99] =  67;
        chroma_multiplexer[100] = 117; chroma_multiplexer[101] = 151;
        chroma_multiplexer[102] = 112; chroma_multiplexer[103] =  83;
        chroma_multiplexer[104] =   4; chroma_multiplexer[105] =   0;
        chroma_multiplexer[106] = 249; chroma_multiplexer[107] = 255;
        chroma_multiplexer[108] =   3; chroma_multiplexer[109] = 107;
        chroma_multiplexer[110] = 249; chroma_multiplexer[111] = 117;
        chroma_multiplexer[112] = 147; chroma_multiplexer[113] =   1;
        chroma_multiplexer[114] =  50; chroma_multiplexer[115] = 162;
        chroma_multiplexer[116] = 143; chroma_multiplexer[117] = 141;
        chroma_multiplexer[118] =  52; chroma_multiplexer[119] =  54;
        chroma_multiplexer[120] =   3; chroma_multiplexer[121] =   0;
        chroma_multiplexer[122] = 145; chroma_multiplexer[123] = 206;
        chroma_multiplexer[124] = 124; chroma_multiplexer[125] = 123;
        chroma_multiplexer[126] = 192; chroma_multiplexer[127] = 193;
        chroma_multiplexer[128] =  72; chroma_multiplexer[129] =  78;
        chroma_multiplexer[130] =   2; chroma_multiplexer[131] =   0;
        chroma_multiplexer[132] = 159; chroma_multiplexer[133] = 208;
        chroma_multiplexer[134] =   4; chroma_multiplexer[135] =   0;
        chroma_multiplexer[136] =  53; chroma_multiplexer[137] =  58;
        chroma_multiplexer[138] = 164; chroma_multiplexer[139] = 159;
        chroma_multiplexer[140] =  37; chroma_multiplexer[141] = 159;
        chroma_multiplexer[142] = 171; chroma_multiplexer[143] =   1;
        chroma_multiplexer[144] = 248; chroma_multiplexer[145] = 117;
        chroma_multiplexer[146] =   4; chroma_multiplexer[147] =  98;
        chroma_multiplexer[148] = 212; chroma_multiplexer[149] = 218;
        chroma_multiplexer[150] =   5; chroma_multiplexer[151] =   2;
        chroma_multiplexer[152] =  54; chroma_multiplexer[153] =  59;
        chroma_multiplexer[154] =  93; chroma_multiplexer[155] = 121;
        chroma_multiplexer[156] = 176; chroma_multiplexer[157] = 181;
        chroma_multiplexer[158] = 134; chroma_multiplexer[159] = 130;
        chroma_multiplexer[160] =   1; chroma_multiplexer[161] =  61;
        chroma_multiplexer[162] =  31; chroma_multiplexer[163] =   0;
        chroma_multiplexer[164] = 160; chroma_multiplexer[165] = 255;
        chroma_multiplexer[166] =  34; chroma_multiplexer[167] =   1;
        chroma_multiplexer[168] =   1; chroma_multiplexer[169] =  58;
        chroma_multiplexer[170] = 197; chroma_multiplexer[171] = 166;
        chroma_multiplexer[172] =   0; chroma_multiplexer[173] = 177;
        chroma_multiplexer[174] = 194; chroma_multiplexer[175] =   2;
        chroma_multiplexer[176] = 162; chroma_multiplexer[177] = 111;
        chroma_multiplexer[178] =  34; chroma_multiplexer[179] =  96;
        chroma_multiplexer[180] = 205; chroma_multiplexer[181] = 253;
        chroma_multiplexer[182] =  32; chroma_multiplexer[183] =   1;
        chroma_multiplexer[184] =   1; chroma_multiplexer[185] =  57;
        chroma_multiplexer[186] = 123; chroma_multiplexer[187] = 125;
        chroma_multiplexer[188] = 119; chroma_multiplexer[189] = 188;
        chroma_multiplexer[190] = 150; chroma_multiplexer[191] = 112;
        chroma_multiplexer[192] =  78; chroma_multiplexer[193] =   4;
        chroma_multiplexer[194] =   0; chroma_multiplexer[195] =  75;
        chroma_multiplexer[196] = 166; chroma_multiplexer[197] = 180;
        chroma_multiplexer[198] =  20; chroma_multiplexer[199] =  38;
        chroma_multiplexer[200] =  78; chroma_multiplexer[201] =   1;
        chroma_multiplexer[202] = 143; chroma_multiplexer[203] = 246;
        chroma_multiplexer[204] =  42; chroma_multiplexer[205] = 113;
        chroma_multiplexer[206] = 156; chroma_multiplexer[207] =  37;
        chroma_multiplexer[208] = 252; chroma_multiplexer[209] =   4;
        chroma_multiplexer[210] =   1; chroma_multiplexer[211] = 188;
        chroma_multiplexer[212] = 175; chroma_multiplexer[213] = 129;
        chroma_multiplexer[214] =   1; chroma_multiplexer[215] =  37;
        chroma_multiplexer[216] = 118; chroma_multiplexer[217] =   4;
        chroma_multiplexer[218] =  88; chroma_multiplexer[219] = 249;
        chroma_multiplexer[220] = 202; chroma_multiplexer[221] = 150;
        chroma_multiplexer[222] = 145; chroma_multiplexer[223] = 200;
        chroma_multiplexer[224] =  61; chroma_multiplexer[225] =  59;
        chroma_multiplexer[226] =  60; chroma_multiplexer[227] =  60;
        chroma_multiplexer[228] = 228; chroma_multiplexer[229] = 252;
        chroma_multiplexer[230] = 117; chroma_multiplexer[231] =  77;
        chroma_multiplexer[232] =  60; chroma_multiplexer[233] =  58;
        chroma_multiplexer[234] = 248; chroma_multiplexer[235] = 251;
        chroma_multiplexer[236] =  81; chroma_multiplexer[237] = 212;
        chroma_multiplexer[238] = 254; chroma_multiplexer[239] = 107;
        chroma_multiplexer[240] = 198; chroma_multiplexer[241] =  59;
        chroma_multiplexer[242] =  58; chroma_multiplexer[243] = 169;
        chroma_multiplexer[244] = 250; chroma_multiplexer[245] = 251;
        chroma_multiplexer[246] =  81; chroma_multiplexer[247] =  80;
        chroma_multiplexer[248] = 100; chroma_multiplexer[249] =  58;
        chroma_multiplexer[250] = 154; chroma_multiplexer[251] = 250;
        chroma_multiplexer[252] = 251; chroma_multiplexer[253] = 252;
        chroma_multiplexer[254] = 252; chroma_multiplexer[255] = 252;
    end

    function signed [9:0] intensity_offset;
        input [1:0] transition;
        begin
            case (transition)
                2'd0: intensity_offset = -10'sd1;
                2'd1: intensity_offset =  10'sd6;
                2'd2: intensity_offset =  10'sd64;
                default: intensity_offset = 10'sd70;
            endcase
        end
    endfunction

    function [17:0] rgbi_color;
        input [3:0] color;
        begin
            case (color)
                4'h0: rgbi_color = 18'b000000_000000_000000;
                4'h1: rgbi_color = 18'b101010_000000_000000;
                4'h2: rgbi_color = 18'b000000_101010_000000;
                4'h3: rgbi_color = 18'b101010_101010_000000;
                4'h4: rgbi_color = 18'b000000_000000_101010;
                4'h5: rgbi_color = 18'b101010_000000_101010;
                4'h6: rgbi_color = 18'b000000_010101_101010;
                4'h7: rgbi_color = 18'b101010_101010_101010;
                4'h8: rgbi_color = 18'b010101_010101_010101;
                4'h9: rgbi_color = 18'b111111_010101_010101;
                4'hA: rgbi_color = 18'b010101_111111_010101;
                4'hB: rgbi_color = 18'b111111_111111_010101;
                4'hC: rgbi_color = 18'b010101_010101_111111;
                4'hD: rgbi_color = 18'b111111_010101_111111;
                4'hE: rgbi_color = 18'b010101_111111_111111;
                default: rgbi_color = 18'b111111_111111_111111;
            endcase
        end
    endfunction

    function [5:0] clamp6;
        input signed [31:0] value;
        reg signed [31:0] scaled;
        begin
            scaled = value >>> 15;
            if (value <= 0)
                clamp6 = 6'd0;
            else if (scaled >= 63)
                clamp6 = 6'd63;
            else
                clamp6 = scaled[5:0];
        end
    endfunction

    reg [17:0] color_out = 18'd0;
    reg [3:0] active_edge_count = 4'd0;
    reg left_edge_blue_clamp = 1'b0;

    // The CGA carrier is sampled at the native 14.318 MHz dot rate.  The
    // scan-doubled input repeats each source dot on two 28.636 MHz clocks;
    // native mode 6 also holds each 1bpp pixel for those two clocks.  In both
    // cases accepting only one of the pair preserves the quarter-carrier
    // phase used by the 1K/chica effects.
    wire sample_ce = scandouble ? 1'b1 : clkdiv[0];

    reg [1:0] sample_phase = 2'd0;
    reg [3:0] previous_video = 4'd0;

    // cga_pixel delays the active indication together with the glyph and
    // attribute data.  The CRTC hblank input changes one native sample before
    // that delayed pixel stream.  Keep one accepted sample of history so the
    // analogue model sees the same transition at both sides of the line.
    reg hblank_delay = 1'b1;
    wire decoder_hblank = hblank_delay;
    reg decoder_hblank_prev = 1'b1;
    wire enter_hblank = decoder_hblank && !decoder_hblank_prev;

    // During horizontal blanking the CGA output is still driven by the
    // programmed overscan/border level (apart from the sync interval).  Keep
    // that level in the electrical model so the filter sees the same
    // transition into and out of the active line as the analogue monitor.
    wire [3:0] waveform_video = decoder_hblank ? border_color : video;

    wire [3:0] left_color = bw_mode ?
        {previous_video[3], (|previous_video[2:0]) ? 3'b111 : 3'b000} :
        previous_video;
    wire [3:0] right_color = bw_mode ?
        {waveform_video[3], (|waveform_video[2:0]) ? 3'b111 : 3'b000} :
        waveform_video;

    // The generated sample describes the previous pixel boundary because the
    // current pixel is the required look-ahead value.
    wire [1:0] generated_phase = sample_phase - 2'd1;
    wire [7:0] chroma_address = {
        left_color[2:0], right_color[2:0], generated_phase
    };
    wire [7:0] chroma_level = chroma_multiplexer[chroma_address];
    wire [15:0] old_chroma_product = chroma_level * 8'd189;
    wire signed [9:0] old_waveform_sample =
        $signed({2'b00, old_chroma_product[15:8]}) +
        intensity_offset({right_color[3], left_color[3]});

    wire signed [9:0] waveform_sample = old_waveform_sample;

    // Eleven samples provide the +/-5-pixel window needed by the chroma
    // comb filter and the following three-tap luma filter.
    reg signed [9:0] waveform_delay [0:9];

    wire signed [17:0] v0  = {{8{waveform_sample[9]}}, waveform_sample};
    wire signed [17:0] v1  = {{8{waveform_delay[0][9]}}, waveform_delay[0]};
    wire signed [17:0] v2  = {{8{waveform_delay[1][9]}}, waveform_delay[1]};
    wire signed [17:0] v3  = {{8{waveform_delay[2][9]}}, waveform_delay[2]};
    wire signed [17:0] v4  = {{8{waveform_delay[3][9]}}, waveform_delay[3]};
    wire signed [17:0] v5  = {{8{waveform_delay[4][9]}}, waveform_delay[4]};
    wire signed [17:0] v6  = {{8{waveform_delay[5][9]}}, waveform_delay[5]};
    wire signed [17:0] v7  = {{8{waveform_delay[6][9]}}, waveform_delay[6]};
    wire signed [17:0] v8  = {{8{waveform_delay[7][9]}}, waveform_delay[7]};
    wire signed [17:0] v9  = {{8{waveform_delay[8][9]}}, waveform_delay[8]};
    wire signed [17:0] v10 = {{8{waveform_delay[9][9]}}, waveform_delay[9]};

    wire signed [17:0] chroma_a_prev =
        v10 - ((v8 - v6 + v4) <<< 1) + v2;
    wire signed [17:0] chroma_a =
        v9 - ((v7 - v5 + v3) <<< 1) + v1;
    wire signed [17:0] chroma_a_next =
        v8 - ((v6 - v4 + v2) <<< 1) + v0;
    wire signed [17:0] chroma_b =
        (v8 - v6 + v4 - v2) <<< 1;

    wire signed [19:0] filtered_prev =
        ({{2{v6[17]}}, v6} <<< 3) - {{2{chroma_a_prev[17]}}, chroma_a_prev};
    wire signed [19:0] filtered_center =
        ({{2{v5[17]}}, v5} <<< 3) - {{2{chroma_a[17]}}, chroma_a};
    wire signed [19:0] filtered_next =
        ({{2{v4[17]}}, v4} <<< 3) - {{2{chroma_a_next[17]}}, chroma_a_next};

    wire signed [21:0] luma_value =
        {{1{filtered_center[19]}}, filtered_center, 1'b0} +
        {{2{filtered_prev[19]}}, filtered_prev} +
        {{2{filtered_next[19]}}, filtered_next};

    wire signed [21:0] mono_luma_value =
        ({{3{v5[17]}}, v5, 1'b0} +
         {{4{v6[17]}}, v6} +
         {{4{v4[17]}}, v4}) <<< 3;

    // The 1K-colour effects and the 80-column text stream use the high
    // resolution carrier convention. In this core that stream is half a
    // carrier cycle away from the normal CGA convention. Keep the correction
    // local to high resolution: applying it globally swaps the colours of the
    // 40-column CGA identification card.
    wire text_phase = hres_mode && !grph_mode;
    wire highres_phase = hres_mode;
    // The calibration screen's phase bit is a quarter-carrier rotation. It
    // is generated by the CRTC's temporary 72h/71h total change and is kept
    // separate from the four-sample pixel phase below.
    wire [1:0] decode_phase = generated_phase - 2'd1 +
        (highres_phase ? {1'b0, phase} : 2'd0) + PHASE_OFFSET;
    reg signed [17:0] i_component;
    reg signed [17:0] q_component;

    always @(*) begin
        case (decode_phase)
            2'd0: begin i_component =  chroma_a; q_component =  chroma_b; end
            2'd1: begin i_component = -chroma_b; q_component =  chroma_a; end
            2'd2: begin i_component = -chroma_a; q_component = -chroma_b; end
            default: begin i_component = chroma_b; q_component = -chroma_a; end
        endcase
    end

    // 80-column text mode on an IBM CGA has a slightly different hue angle.
    wire signed [12:0] coeff_ri = text_phase ? 13'sd840 : 13'sd845;
    wire signed [12:0] coeff_rq = text_phase ? -13'sd104 : 13'sd43;
    wire signed [12:0] coeff_gi = text_phase ? -13'sd463 : -13'sd415;
    wire signed [12:0] coeff_gq = text_phase ? -13'sd237 : -13'sd314;
    wire signed [12:0] coeff_bi = text_phase ? 13'sd185 : -13'sd77;
    wire signed [12:0] coeff_bq = text_phase ? 13'sd1497 : 13'sd1506;

    // In the real 8088 MPH calibration screen, all settings before [E,1]
    // retain the same luminance ramps but decode as monochrome.  [E,1] is the
    // first setting that supplies a usable colour burst.  Do not attenuate
    // chroma progressively here: that would also attenuate the only signal
    // from which the monitor can recover the intermediate ramp levels.
    function burst_lock_for;
        input [3:0] width;
        input       mode_text;
        input       phase_bit;
        begin
            // Motorola's 0 and 15 encodings are full-width sync pulses.
            // The calibrated transition is otherwise the E-width pulse with
            // the phase flip asserted: [E,1].
            burst_lock_for = !mode_text || (width == 4'd0) ||
                (width == 4'd15) || ((width == 4'd14) && phase_bit);
        end
    endfunction

    wire burst_locked = burst_lock_for(hsync_width, text_phase, phase);

    // Pipeline the filter, matrix multipliers and RGB accumulation.  The
    // unpipelined version put the complete YIQ decoder in one 28.6 MHz path
    // and missed timing on Cyclone V, which can appear as unstable colours.
    reg signed [21:0] luma_stage1 = 22'sd0;
    reg signed [21:0] mono_stage1 = 22'sd0;
    reg signed [17:0] i_stage1 = 18'sd0;
    reg signed [17:0] q_stage1 = 18'sd0;
    reg               monochrome_stage1 = 1'b1;

    wire signed [30:0] red_i_product   = i_stage1 * coeff_ri;
    wire signed [30:0] red_q_product   = q_stage1 * coeff_rq;
    wire signed [30:0] green_i_product = i_stage1 * coeff_gi;
    wire signed [30:0] green_q_product = q_stage1 * coeff_gq;
    wire signed [30:0] blue_i_product  = i_stage1 * coeff_bi;
    wire signed [30:0] blue_q_product  = q_stage1 * coeff_bq;

    reg signed [31:0] luma_stage2 = 32'sd0;
    reg signed [31:0] mono_stage2 = 32'sd0;
    reg signed [30:0] red_i_stage2 = 31'sd0;
    reg signed [30:0] red_q_stage2 = 31'sd0;
    reg signed [30:0] green_i_stage2 = 31'sd0;
    reg signed [30:0] green_q_stage2 = 31'sd0;
    reg signed [30:0] blue_i_stage2 = 31'sd0;
    reg signed [30:0] blue_q_stage2 = 31'sd0;
    reg               monochrome_stage2 = 1'b1;

    wire signed [31:0] red_accumulator = luma_stage2 +
        {red_i_stage2[30], red_i_stage2} +
        {red_q_stage2[30], red_q_stage2};
    wire signed [31:0] green_accumulator = luma_stage2 +
        {green_i_stage2[30], green_i_stage2} +
        {green_q_stage2[30], green_q_stage2};
    wire signed [31:0] blue_accumulator = luma_stage2 +
        {blue_i_stage2[30], blue_i_stage2} +
        {blue_q_stage2[30], blue_q_stage2};

    wire [17:0] decoded_color = monochrome_stage2 ? {
        clamp6(mono_stage2),
        clamp6(mono_stage2),
        clamp6(mono_stage2)
    } : {
        clamp6(blue_accumulator),
        clamp6(green_accumulator),
        clamp6(red_accumulator)
    };

    // Keep the full active aperture.  The first sample after the blanking
    // filter settles can carry a tiny blue-only edge residue.  Remove only
    // that blue component instead of moving the blanking edge and cropping
    // the first source column.
    wire [17:0] visible_color = left_edge_blue_clamp ?
        {6'd0, color_out[11:6], color_out[5:0]} : color_out;
    assign red   = visible_color[5:0];
    assign green = visible_color[11:6];
    assign blue  = visible_color[17:12];

    integer delay_index;
    always @(posedge clk) begin
        if (!composite) begin
            color_out <= rgbi_color(video);
            sample_phase <= 2'd0;
            previous_video <= video;
            hblank_delay <= 1'b1;
            decoder_hblank_prev <= 1'b1;
            active_edge_count <= 4'd0;
            left_edge_blue_clamp <= 1'b0;
            luma_stage1 <= 22'sd0;
            mono_stage1 <= 22'sd0;
            i_stage1 <= 18'sd0;
            q_stage1 <= 18'sd0;
            monochrome_stage1 <= 1'b1;
            luma_stage2 <= 32'sd0;
            mono_stage2 <= 32'sd0;
            red_i_stage2 <= 31'sd0;
            red_q_stage2 <= 31'sd0;
            green_i_stage2 <= 31'sd0;
            green_q_stage2 <= 31'sd0;
            blue_i_stage2 <= 31'sd0;
            blue_q_stage2 <= 31'sd0;
            monochrome_stage2 <= 1'b1;
            for (delay_index = 0; delay_index < 10; delay_index = delay_index + 1)
                waveform_delay[delay_index] <= 10'sd0;
        end
        else if (sample_ce) begin
            previous_video <= waveform_video;
            hblank_delay <= hblank;
            decoder_hblank_prev <= decoder_hblank;
            waveform_delay[0] <= waveform_sample;
            for (delay_index = 1; delay_index < 10; delay_index = delay_index + 1)
                waveform_delay[delay_index] <= waveform_delay[delay_index - 1];

            if (decoder_hblank) begin
                active_edge_count <= 4'd0;
                left_edge_blue_clamp <= 1'b0;
                // Keep the carrier phase continuous across the horizontal
                // blanking interval.  The filter history is deliberately not
                // cleared here: the border-to-pixel transition is part of
                // the sampled composite line and is used by the +/-5 sample
                // chroma window in the reference implementations.
                // The line's electrical phase is defined at the start of
                // horizontal blanking.  Re-anchor here so enabling Composite
                // halfway through a line cannot leave the decoder in an
                // arbitrary one-of-four carrier rotation.  Standard CGA
                // blanking is a multiple of four native samples, so the
                // active portion of the following line starts at phase zero.
                if (enter_hblank)
                    sample_phase <= 2'd0;
                else
                    sample_phase <= sample_phase + 2'd1;
                monochrome_stage1 <= 1'b1;
                monochrome_stage2 <= 1'b1;

                // Advance the same pipeline while blanked.  Its output is
                // suppressed above, but these samples provide the correct
                // line preamble for the first active pixels.
                luma_stage1 <= luma_value;
                mono_stage1 <= mono_luma_value;
                i_stage1 <= i_component;
                q_stage1 <= q_component;
                luma_stage2 <= {{10{luma_stage1[21]}}, luma_stage1} <<< 8;
                mono_stage2 <= {{10{mono_stage1[21]}}, mono_stage1} <<< 8;
                red_i_stage2 <= red_i_product;
                red_q_stage2 <= red_q_product;
                green_i_stage2 <= green_i_product;
                green_q_stage2 <= green_q_product;
                blue_i_stage2 <= blue_i_product;
                blue_q_stage2 <= blue_q_product;
                // Do not force the RGB output to black at the blanking edge.
                // The filter is intentionally still running on the border
                // waveform; forcing the output here creates a discontinuity
                // at the first visible column when the downstream blanking
                // path is a few clocks out of phase.
                color_out <= decoded_color;
            end
            else begin
                if (decoder_hblank_prev) begin
                    active_edge_count <= 4'd0;
                    left_edge_blue_clamp <= 1'b0;
                end
                else begin
                    if (active_edge_count != 4'd15)
                        active_edge_count <= active_edge_count + 4'd1;
                    left_edge_blue_clamp <= composite && !monochrome_stage2 &&
                        (active_edge_count >= 4'd7) &&
                        (active_edge_count <= 4'd9);
                end
                // The chroma table contains the four quarter-carrier
                // samples of one CGA colour cycle.  Each accepted source
                // sample advances exactly one of those phases.
                sample_phase <= sample_phase + 2'd1;

                luma_stage1 <= luma_value;
                mono_stage1 <= mono_luma_value;
                i_stage1 <= i_component;
                q_stage1 <= q_component;
                monochrome_stage1 <= bw_mode || !burst_locked;

                luma_stage2 <= {{10{luma_stage1[21]}}, luma_stage1} <<< 8;
                mono_stage2 <= {{10{mono_stage1[21]}}, mono_stage1} <<< 8;
                red_i_stage2 <= red_i_product;
                red_q_stage2 <= red_q_product;
                green_i_stage2 <= green_i_product;
                green_q_stage2 <= green_q_product;
                blue_i_stage2 <= blue_i_product;
                blue_q_stage2 <= blue_q_product;
                monochrome_stage2 <= monochrome_stage1;

                color_out <= decoded_color;
            end
        end
    end

endmodule

`default_nettype wire
