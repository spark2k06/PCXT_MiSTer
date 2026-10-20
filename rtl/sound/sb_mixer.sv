//
// Sound Blaster Pro mixer (CT1345 subset)
//
// The register file behind ports 2x4h (index) and 2x5h (data). Only the
// registers a real CT1345 has are here; the CT1745's 30h-47h bank belongs to a
// Sound Blaster 16 and is deliberately absent, so software that probes for one
// does not find it.
//
// Two things in here matter more than the volumes, because software uses them
// to decide whether the card exists at all:
//
//   Register 0Ah must survive a read-modify-write. SBPDIG.ADV detects a Sound
//   Blaster Pro by writing the mic volume and reading it back, which is how
//   Ultima Underworld and Dune II find the card. The 2-bit field therefore has
//   to round-trip through the 5-bit internal form and come back matching.
//
//   The reserved bits 0 and 4 of every volume register must read back as 1,
//   not 0. The Sound Blaster 16 MASI driver v2.90 - shipped with Epic Pinball
//   and Jazz Jackrabbit - writes F3h to the master volume register and enables
//   stereo only if it reads F3h back. Returning the volume with zeroed
//   reserved bits loses stereo in those games and looks like a mixer that
//   works.
//
// Volumes are stored in the 5-bit form sb_volume consumes, so the 3-bit fields
// the Pro exposes are widened on write and narrowed on read. That is upstream
// ao486's representation and is kept so its gain tables apply unchanged.
//
module sb_mixer (
    input   logic           clock,
    input   logic           reset,

    // Register access. The write strobe is single-cycle; reads are answered
    // combinationally, so there is no read strobe.
    input   logic   [3:0]   io_address,
    input   logic           io_write,
    input   logic   [7:0]   io_writedata,
    output  logic   [7:0]   io_readdata,
    output  logic           io_readdata_valid,  // high for port 2x5h only

    // To the DSP
    output  logic           sbp_stereo,
    output  logic           sbp_stereo_ff_rst,

    // To the gain stage
    output  logic   [4:0]   vol_master_l,
    output  logic   [4:0]   vol_master_r,
    output  logic   [4:0]   vol_voice_l,
    output  logic   [4:0]   vol_voice_r,
    output  logic   [4:0]   vol_midi_l,
    output  logic   [4:0]   vol_midi_r
);

    localparam [3:0] PORT_INDEX = 4'h4;
    localparam [3:0] PORT_DATA  = 4'h5;

    wire    index_write = io_write && (io_address == PORT_INDEX);
    wire    data_write  = io_write && (io_address == PORT_DATA);

    assign  io_readdata_valid = (io_address == PORT_DATA);

    //
    // Index register
    //
    logic   [7:0]   mixer_reg;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)            mixer_reg <= 8'h00;
        else if (index_write) mixer_reg <= io_writedata;
    end

    //
    // Register file
    //
    // Widening the Pro's 3-bit volume field: vol_5bit = 17 + vol_3bit*2, which
    // is the bit pattern {1, vol_3bit, 1}. Range -28 dB to 0 dB in 4 dB steps.
    //
    wire    [9:0]   vol_mapped = {1'b1, io_writedata[7:5], 1'b1,
                                  1'b1, io_writedata[3:1], 1'b1};

    // Mic is 2 bits on the Pro: vol_5bit = 19 + vol_2bit*4 = {1, vol_2bit, 11}.
    wire    [4:0]   mic_mapped = {1'b1, io_writedata[2:1], 2'b11};

    logic   [4:0]   vol_cd_l,   vol_cd_r;
    logic   [4:0]   vol_line_l, vol_line_r;
    logic   [4:0]   vol_mic;

    logic           input_lpf_bypass;
    logic           input_lpf_freq;
    logic   [1:0]   input_source;
    logic           output_lpf_bypass;

    // A write to register 00h resets the mixer, whatever the data.
    wire    mixer_reset = data_write && (mixer_reg == 8'h00);

    // Synchronous reset, unlike the rest of this module. A write to mixer
    // register 00h has to land on the same defaults the power-on reset
    // does, and an asynchronous block cannot say so: its first condition
    // must be the signal in its own sensitivity list, so `reset ||
    // mixer_reset` will not infer. The alternative is writing the default
    // list out twice, which is the version that drifts.
    always_ff @(posedge clock) begin
        if (reset || mixer_reset) begin
            // Upstream's defaults rather than the card's. A real Pro powers up
            // with the main volumes at -11 dB and CD/Line at -46 dB, which is
            // quiet enough that a program which never touches the mixer sounds
            // broken. 5'd29 is -3 dB and leaves headroom for the mix.
            {vol_master_l, vol_master_r} <= {5'd29, 5'd29};
            {vol_voice_l,  vol_voice_r}  <= {5'd29, 5'd29};
            {vol_midi_l,   vol_midi_r}   <= {5'd29, 5'd29};
            {vol_cd_l,     vol_cd_r}     <= {5'd29, 5'd29};
            {vol_line_l,   vol_line_r}   <= {5'd29, 5'd29};
            vol_mic                      <= 5'd0;

            sbp_stereo                   <= 1'b0;
            input_lpf_bypass             <= 1'b0;
            input_lpf_freq               <= 1'b0;
            input_source                 <= 2'b00;
            output_lpf_bypass            <= 1'b0;
        end
        else if (data_write) begin
            case (mixer_reg)
                8'h04: {vol_voice_l,  vol_voice_r}  <= vol_mapped;
                8'h22: {vol_master_l, vol_master_r} <= vol_mapped;
                8'h26: {vol_midi_l,   vol_midi_r}   <= vol_mapped;
                8'h28: {vol_cd_l,     vol_cd_r}     <= vol_mapped;
                8'h2E: {vol_line_l,   vol_line_r}   <= vol_mapped;
                8'h0A: vol_mic <= mic_mapped;
                8'h0C: {input_lpf_bypass, input_lpf_freq, input_source}
                           <= {io_writedata[5], io_writedata[3], io_writedata[2:1]};
                8'h0E: {output_lpf_bypass, sbp_stereo}
                           <= {io_writedata[5], io_writedata[1]};
                default: ; // a real mixer ignores the rest too
            endcase
        end
    end

    // Writing 0Eh re-arms the interleave flip-flop, so the first sample of a
    // stereo block lands in the channel the program expects. The flip-flop
    // itself lives in the DSP here, but on the real card it is in the mixer.
    assign sbp_stereo_ff_rst = data_write && (mixer_reg == 8'h0E);

    //
    // Readback
    //
    // Narrowing back to the Pro's field widths, with the reserved bits driven
    // to 1 - see the note at the top of this file for why that matters.
    //
    function automatic [7:0] vol_readback(input [4:0] l, input [4:0] r);
        vol_readback = {(l < 5'd17) ? 3'd0 : l[3:1], 1'b1,
                        (r < 5'd17) ? 3'd0 : r[3:1], 1'b1};
    endfunction

    // Combinational, matching sb_dsp's own read path. The wrapper registers
    // whichever of the two answers on the cycle its read strobe fires, so a
    // register here as well would put the previous access's value on the bus.
    always_comb begin
        case (mixer_reg)
            8'h04:   io_readdata = vol_readback(vol_voice_l,  vol_voice_r);
            8'h22:   io_readdata = vol_readback(vol_master_l, vol_master_r);
            8'h26:   io_readdata = vol_readback(vol_midi_l,   vol_midi_r);
            8'h28:   io_readdata = vol_readback(vol_cd_l,     vol_cd_r);
            8'h2E:   io_readdata = vol_readback(vol_line_l,   vol_line_r);
            // Mic narrows back the way it widened: vol_2bit = (v - 19) / 4.
            8'h0A:   io_readdata = {5'b00000,
                                    (vol_mic < 5'd19) ? 2'd0 : vol_mic[3:2],
                                    1'b0};
            8'h0C:   io_readdata = {2'b00, input_lpf_bypass, 1'b0,
                                    input_lpf_freq, input_source, 1'b1};
            8'h0E:   io_readdata = {2'b00, output_lpf_bypass, 1'b1,
                                    2'b00, sbp_stereo, 1'b1};
            default: io_readdata = 8'h00;
        endcase
    end

endmodule
