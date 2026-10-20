//
// SB volume / gain stage
//
// Lifted verbatim from ao486's rtl/soc/sound/sound.v, where it lives at the
// bottom of the file rather than in one of its own. Only this header is new.
//
// Copyright (c) 2014, Aleksander Osman; fixes and Sound Blaster 16 support
// (C) 2017-2020 Alexey Melnikov. BSD 2-clause, as carried in sb_dsp.sv.
//
// One multiplier, time-multiplexed across every channel: it walks `ch` round
// the channel list a clock at a time and shifts each attenuated result into
// samples_out, raising `valid` when the set is complete. At a chipset clock of
// tens of MHz against an audio rate in the tens of kHz there are thousands of
// clocks per sample, so a handful of channels costs one DSP block and no
// throughput.
//
// The sbp input selects the Pro's 8-level, 4 dB gain table over the 16's
// 32-level, 2 dB one. This core ties it high.
//
module sb_volume
#(
	parameter integer NUM_CH       = 10, // number of channels
	parameter integer SAMPLE_WIDTH = 16  // number of bits per sample
)(
	input                                clk,
	input                                sbp,         // SBPro: sbp=1, SB16: sbp=0
	input                 [NUM_CH*5-1:0] volumes_in,  // input volumes (5 bits per channel volume control)
	input      [NUM_CH*SAMPLE_WIDTH-1:0] samples_in,  // input samples (SAMPLE_WIDTH bits per channel sample)
	output reg [NUM_CH*SAMPLE_WIDTH-1:0] samples_out, // output samples (attenuated)
	output reg                           valid        // samples_out valid flag
);

// SBPro gain table (unsigned, 16-bit gain values)
// volume = 0 to 7 (3-bit) => -46 dB to 0 dB, in approximate 4 dB steps
// 8 x 16 = 128 bits packed into one vector
localparam [127:0] sbp_gain_lut = {
	16'hFFFF, //   0 dB (17'h10000 will be used for unity gain)
	16'hB53C, //  -3 dB
	16'h725A, //  -7 dB
	16'h4827, // -11 dB
	16'h2893, // -16 dB
	16'h1456, // -22 dB
	16'h0A31, // -28 dB
	16'h0148  // -46 dB
};

// SB16 gain table (unsigned, 16-bit gain values)
// volume = 0 to 31 (5-bit) => -62 dB to 0 dB, in 2 dB steps
// 32 x 16 = 512 bits packed into one vector
localparam [511:0] sb16_gain_lut = {
	16'hFFFF, //   0 dB (17'h10000 will be used for unity gain)
	16'hCB59, //  –2 dB
	16'hA186, //  –4 dB
	16'h804E, //  –6 dB
	16'h65EA, //  –8 dB
	16'h50F4, // –10 dB
	16'h404E, // –12 dB
	16'h3314, // –14 dB
	16'h2893, // –16 dB
	16'h203A, // –18 dB
	16'h199A, // –20 dB
	16'h1456, // –22 dB
	16'h1027, // –24 dB
	16'h0CD5, // –26 dB
	16'h0A31, // –28 dB
	16'h0818, // –30 dB
	16'h066E, // –32 dB
	16'h051C, // –34 dB
	16'h040F, // –36 dB
	16'h0339, // –38 dB
	16'h028F, // –40 dB
	16'h0209, // –42 dB
	16'h019E, // –44 dB
	16'h0148, // –46 dB
	16'h0105, // –48 dB
	16'h00CF, // –50 dB
	16'h00A5, // –52 dB
	16'h0083, // –54 dB
	16'h0068, // –56 dB
	16'h0053, // –58 dB
	16'h0042, // –60 dB
	16'h0034  // –62 dB
};

reg [$clog2(NUM_CH)-1:0] ch;

wire [4:0] volume_5bit = volumes_in[5*ch +: 5];
wire [2:0] volume_3bit = volume_5bit[3:1];

reg                    [16:0] gain;
reg signed [SAMPLE_WIDTH-1:0] sample;
always @(posedge clk) begin
	gain   <= (volume_5bit == 5'd31) ? 17'h10000 : 
	                             sbp ?  sbp_gain_lut[volume_3bit*16 +: 16] : 
	                                   sb16_gain_lut[volume_5bit*16 +: 16];
	sample <= samples_in[SAMPLE_WIDTH*ch +: SAMPLE_WIDTH];
end

// DSP-targeted multiply (1 x DSP block shared across all channels)
wire signed [33:0] gain_product = $signed({1'b0, gain}) * sample;

always @(posedge clk) begin
	samples_out       <= {gain_product[31:16], samples_out[NUM_CH*SAMPLE_WIDTH-1:SAMPLE_WIDTH]};
	valid             <= (ch == 0);
	ch                <= (ch == NUM_CH-1) ? 1'b0 : ch + 1'b1;
end

endmodule
