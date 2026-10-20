//
// Sound Blaster Pro (reduced) for PCXT-EGA
//
// Wraps the ao486 DSP in sb_dsp.sv and the DMA bridge in sb_dma_glue.sv, and
// presents them to this core's ISA bus. The DSP is configured as a Sound
// Blaster Pro and cannot be anything else: sbp is tied high and dma_16_en low,
// which is what reduces a Sound Blaster 16 to a Pro. See sb_dsp.sv for why
// that is a tie rather than a deletion.
//
// The OPL2 is not generated here, but it does pass through: the core
// instantiates jtopl2 in Peripherals.sv and decodes it at 228h/229h, the
// Sound Blaster FM alias, so the music side was working before this module
// existed. It is routed in so the mixer's register 26h can set its level
// the way a real card does, and Peripherals silences the direct path to
// stop the same FM being summed twice. That makes this module the only
// thing between the OPL2 and the speakers in every configuration, so the
// disabled path has to be a clean passthrough - see the output stage.
//
// A second OPL2 for the Pro 1.0's dual-chip stereo would duplicate a core
// that costs DSP blocks and BRAM, to serve software that essentially does
// not exist.
//
// Port map, at base 220h:
//
//   2x0-2x3   C/MS SAA1099   elsewhere, and mutually exclusive with this
//   2x4/2x5   mixer          index and data, CT1345 subset
//   2x6       DSP reset
//   2x8/2x9   OPL2 FM        elsewhere, already working
//   2xA       DSP read data
//   2xC       DSP write command/data, and write-buffer status on read
//   2xE       DSP read status, and 8-bit IRQ acknowledge on read
//
// Only the four DSP ports are claimed. Claiming the whole 16-byte block would
// be simpler but wrong: reads of 228h would then return the DSP's 0xFF filler
// instead of the OPL2's status, and 226h/227h would collide with the C/MS
// detection register. The DSP ignores writes to addresses it does not own, but
// the read mux cannot afford the same laxity.
//
module soundblaster (
    input   logic           clock,
    input   logic           reset,
    input   logic           cpu_ce_negedge,
    input   logic   [27:0]  clk_rate,

    // ISA bus
    input   logic   [15:0]  address,
    input   logic   [7:0]   internal_data_bus,
    input   logic           io_read_n,
    input   logic           io_write_n,
    input   logic           address_enable_n,
    input   logic           enable,             // runtime switch
    output  logic           read_select,        // drives the read mux upstream
    output  logic   [7:0]   data_bus_out,

    // DMA channel 1
    input   logic           dma_acknowledge,
    output  logic           dma_request,

    // IRQ
    output  logic           irq,

    // FM in from the core's jtopl2, signed. It arrives here so the mixer's
    // register 26h can attenuate it the way a real card does, and leaves again
    // in sample_l/r. When this module is disabled it passes through untouched,
    // which is what keeps plain Adlib at 388h working with the card switched
    // off.
    input   logic   [15:0]  fm_l,
    input   logic   [15:0]  fm_r,

    // Audio out, signed: the card's whole contribution, DAC and FM together,
    // after the master volume.
    output  logic   [15:0]  sample_l,
    output  logic   [15:0]  sample_r
);

    //
    // Decode
    //
    // The DSP does its own sub-decode from the low four address bits, so this
    // only has to pick the block and the four ports within it.
    //
    wire    block_select = enable && ~address_enable_n && (address[15:4] == (16'h0220 >> 4));

    wire    dsp_port     = (address[3:0] == 4'h6)   // reset
                        || (address[3:0] == 4'hA)   // read data
                        || (address[3:0] == 4'hC)   // write command/data
                        || (address[3:0] == 4'hE);  // status / IRQ acknowledge

    wire    mixer_port   = (address[3:0] == 4'h4)   // mixer index
                        || (address[3:0] == 4'h5);  // mixer data

    wire    dsp_select   = block_select && dsp_port;
    wire    mixer_select = block_select && mixer_port;

    wire    any_select   = dsp_select || mixer_select;

    // A DMA cycle that moves a byte the other way - device to memory - has the
    // 8237 assert IOR at us and MEMW at the memory, and expects US to put the
    // byte on the bus. Playback never does this, so it went unnoticed: every
    // transfer there is memory to device, MEMR and IOW, and we only read.
    //
    // Command E2h does. It is the DMA identification, and CT-VOICE.DRV runs it
    // during init - not as a diagnostic, but because it stores the pointer to
    // its own play routine ENCRYPTED and uses the DSP to decrypt it. The
    // dispatch table entry for function 6 holds FE9Ch on disk; the driver
    // feeds those two bytes back through E2h and DMAs the answers over the top
    // of them, and the answers are 0FB4h, the real entry point.
    //
    // The algorithm is an accumulator starting at AAh and an XOR key starting
    // at 96h that rotates right two bits per use:
    //
    //     AAh + (9Ch ^ 96h) = B4h
    //     B4h + (FEh ^ A5h) = 0Fh
    //
    // So it is a card-authentication trick: anything that is not a Sound
    // Blaster decrypts the pointer into nonsense. With nothing driving the bus
    // the 8237 latched FFh twice, function 6 became a call to offset FFFFh,
    // and every attempt to play a digitised sound jumped into open memory.
    // That is the game's missing sound and the game's hang, both of them, and
    // no amount of testing through the port interface could have shown it -
    // the harness that loads the driver itself is what caught it.
    wire    dma_read     = dma_acknowledge && ~io_read_n;

    // Only 2x5h answers a read on the mixer side; 2x4h is write-only, as on
    // the real card, and must not be claimed or it would return mixer data for
    // a port that has none. This is a function of the live address because the
    // read mux upstream needs it during the cycle, not after it.
    //
    // dma_read carries no address term on purpose: during a DMA cycle the
    // address on the bus belongs to memory, and DACK is the only thing that
    // says the byte is ours. The floppy's fdd_dma_read is built the same way.
    assign  read_select  = dsp_select || (mixer_select && (address[3:0] == 4'h5))
                        || dma_read;

    //
    // Bus strobes
    //
    // sb_dsp wants single-cycle pulses. A held level would re-trigger
    // cmd_start on every clock of the bus cycle and shift a command's
    // parameter bytes in several times over.
    //
    // The edges are not symmetric, and follow what the floppy does in
    // Peripherals.sv: the read pulse is on the LEADING edge of IOR, so the
    // rest of the cycle is left for the answer to reach the CPU, while the
    // write pulse is on the TRAILING edge, by which point the write data has
    // settled on the bus.
    //
    logic   prev_io_read_n;
    logic   prev_io_write_n;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            prev_io_read_n  <= 1'b1;
            prev_io_write_n <= 1'b1;
        end
        else begin
            prev_io_read_n  <= io_read_n;
            prev_io_write_n <= io_write_n;
        end
    end

    // A write pulses on the trailing edge of IOW, and by then the address may
    // already be gone from the bus - so the select and the address a write
    // needs are latched while IOW is still low, together with the data. On
    // real hardware the 8282 latches hold the address for the whole cycle, but
    // depending on that would make this module the one place in the core that
    // breaks if a cycle ends early. Peripherals.sv documents the same hazard
    // for the MPU-401, which is why that device's select carries no iorq term.
    logic           write_select_held;
    logic   [3:0]   write_address_held;
    logic   [7:0]   sb_io_writedata;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            write_select_held  <= 1'b0;
            write_address_held <= 4'h0;
            sb_io_writedata    <= 8'h00;
        end
        else if (~io_write_n) begin
            write_select_held  <= any_select;
            write_address_held <= address[3:0];
            sb_io_writedata    <= internal_data_bus;
        end
    end

    // One set of strobes serves both the DSP and the mixer. They do not need
    // splitting by address because each already ignores what it does not own:
    // the DSP acts only on 6h/Ah/Ch/Eh, the mixer only on 4h/5h.
    logic   [3:0]   sb_io_address;
    logic           sb_io_read;
    logic           sb_io_write;

    wire            read_strobe  = any_select        & ~io_read_n  &  prev_io_read_n;
    wire            write_strobe = write_select_held &  io_write_n & ~prev_io_write_n;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            sb_io_address <= 4'h0;
            sb_io_read    <= 1'b0;
            sb_io_write   <= 1'b0;
        end
        else begin
            // Reads take the live address, which is valid at the leading edge
            // they fire on; writes take the one latched during the cycle.
            sb_io_address <= read_strobe ? address[3:0] : write_address_held;
            sb_io_read    <= read_strobe;
            sb_io_write   <= write_strobe;
        end
    end

    //
    // Read data
    //
    // sb_dsp answers combinationally from io_address, and reading 2xAh shifts
    // its reply buffer on the same edge. Registering the answer on the cycle
    // the read strobe is asserted therefore captures the byte before the
    // shift, which is the one the CPU asked for.
    //
    wire    [7:0]   dsp_readdata;
    wire    [7:0]   mixer_readdata;
    wire            mixer_readdata_valid;
    wire    [15:0]  dsp_dma_writedata;

    // The DMA byte is taken on the level, not on an edge, and holds after the
    // cycle - the same shape as the floppy's fdd_readdata. It is safe to track
    // the level here because the DSP does not retire its side of the transfer
    // until the acknowledge pulse, which this glue raises on the FALLING edge
    // of DACK. So dsp_dma_writedata is still the byte for this cycle for the
    // whole of it.
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            data_bus_out <= 8'hFF;
        else if (sb_io_read)
            data_bus_out <= mixer_readdata_valid ? mixer_readdata : dsp_readdata;
        else if (dma_read)
            data_bus_out <= dsp_dma_writedata[7:0];
    end

    //
    // 1 us tick, for the DSP's busy-flag timing.
    //
    // Same accumulator Peripherals.sv already uses for its own ce_1us, with
    // one difference: the running sum is declared here rather than inside the
    // always block. Both are identical to Quartus, which follows Verilog-2001
    // and makes a block-local reg static, but Verilator treats one with an
    // initialiser as automatic and re-zeroes it every clock - so the in-block
    // form never reaches the threshold and the tick never fires. Keeping the
    // sum at module scope is unambiguous everywhere and costs nothing.
    logic           ce_1us;
    logic   [27:0]  ce_1us_sum = 28'd0;

    always_ff @(posedge clock) begin
        ce_1us     <= 1'b0;
        ce_1us_sum  = ce_1us_sum + 28'd1000000;
        if (ce_1us_sum >= clk_rate) begin
            ce_1us_sum  = ce_1us_sum - clk_rate;
            ce_1us     <= 1'b1;
        end
    end

    //
    // DMA
    //
    wire            dsp_dma_req8;
    wire            dsp_dma_ack;
    wire    [7:0]   dsp_dma_readdata;

    sb_dma_glue u_dma_glue (
        .clock                  (clock),
        .reset                  (reset),
        .cpu_ce_negedge         (cpu_ce_negedge),
        .dma_acknowledge        (dma_acknowledge),
        .io_write_n             (io_write_n),
        .internal_data_bus      (internal_data_bus),
        .dma_request            (dma_request),
        .device_dma_req         (dsp_dma_req8),
        .device_dma_ack         (dsp_dma_ack),
        .device_dma_readdata    (dsp_dma_readdata)
    );

    //
    // Mixer
    //
    wire            sbp_stereo;
    wire            sbp_stereo_ff_rst;
    wire    [4:0]   vol_master_l, vol_master_r;
    wire    [4:0]   vol_voice_l,  vol_voice_r;
    wire    [4:0]   vol_midi_l,   vol_midi_r;

    sb_mixer u_mixer (
        .clock              (clock),
        .reset              (reset),
        .io_address         (sb_io_address),
        .io_write           (sb_io_write),
        .io_writedata       (sb_io_writedata),
        .io_readdata        (mixer_readdata),
        .io_readdata_valid  (mixer_readdata_valid),
        .sbp_stereo         (sbp_stereo),
        .sbp_stereo_ff_rst  (sbp_stereo_ff_rst),
        .vol_master_l       (vol_master_l),
        .vol_master_r       (vol_master_r),
        .vol_voice_l        (vol_voice_l),
        .vol_voice_r        (vol_voice_r),
        .vol_midi_l         (vol_midi_l),
        .vol_midi_r         (vol_midi_r)
    );

    //
    // DSP
    //
    // sbp high and dma_16_en low are what make this a Pro rather than a 16.
    //
    wire    [15:0]  dsp_l, dsp_r;

    sb_dsp u_dsp (
        .clk                (clock),
        .rst_n              (~reset),

        .clock_rate         (clk_rate),
        .ce_1us             (ce_1us),

        .irq8               (irq),
        .irq16              (),                 // SB16 only, unreachable with sbp

        .io_address         (sb_io_address),
        .io_read            (sb_io_read),
        .io_readdata        (dsp_readdata),
        .io_write           (sb_io_write),
        .io_writedata       (sb_io_writedata),

        .dma_req8           (dsp_dma_req8),
        .dma_req16          (),                 // SB16 only
        .dma_ack            (dsp_dma_ack),
        .dma_readdata       ({8'h00, dsp_dma_readdata}),
        .dma_writedata      (dsp_dma_writedata),
        .dma_16_en          (1'b0),
        .sbp                (1'b1),
        .sbp_stereo         (sbp_stereo),
        .sbp_stereo_ff_rst  (sbp_stereo_ff_rst),

        .sample_value_l     (dsp_l),
        .sample_value_r     (dsp_r)
    );

    //
    // Gain and mix
    //
    // Six channels through one shared multiplier, arranged the way ao486 does
    // it: the master pair attenuates the PREVIOUS round's summed mix, fed back
    // in, so the master applies to everything downstream of it without needing
    // a second multiplier or a second pass.
    //
    wire    [15:0]  master_l, master_r;
    wire    [15:0]  voice_l,  voice_r;
    wire    [15:0]  midi_l,   midi_r;
    wire            gain_valid;

    logic   [15:0]  mix_pre_l, mix_pre_r;

    sb_volume #(.NUM_CH(6), .SAMPLE_WIDTH(16)) u_volume (
        .clk            (clock),
        .sbp            (1'b1),
        .volumes_in     ({vol_master_l, vol_master_r,
                          vol_voice_l,  vol_voice_r,
                          vol_midi_l,   vol_midi_r}),
        .samples_in     ({mix_pre_l,    mix_pre_r,
                          dsp_l,        dsp_r,
                          fm_l,         fm_r}),
        .samples_out    ({master_l,     master_r,
                          voice_l,      voice_r,
                          midi_l,       midi_r}),
        .valid          (gain_valid)
    );

    // Sum the attenuated sources, clipping rather than wrapping - a wrap turns
    // a loud passage into noise instead of a flat top.
    always_ff @(posedge clock) begin
        logic signed [16:0] sum_l, sum_r;

        if (gain_valid) begin
            sum_l = {voice_l[15], voice_l} + {midi_l[15], midi_l};
            sum_r = {voice_r[15], voice_r} + {midi_r[15], midi_r};

            mix_pre_l <= (^sum_l[16:15]) ? {sum_l[16], {15{sum_l[15]}}} : sum_l[15:0];
            mix_pre_r <= (^sum_r[16:15]) ? {sum_r[16], {15{sum_r[15]}}} : sum_r[15:0];
        end
    end

    // With the card switched off the FM has to keep reaching the speakers
    // untouched, because plain Adlib at 388h does not go through any of this.
    //
    // With it on, the outputs may only be sampled while gain_valid is high.
    // sb_volume is a shift register that rotates one channel per clock, so
    // master_l and master_r hold their own product for one cycle in every
    // six and carry some other channel the rest of the time. Reading them
    // unconditionally picks the register up mid-rotation: the output then
    // changes every clock on a steady input, and the two channels disagree
    // on a mono one. That is audible as a crackle with no music underneath
    // it, which is exactly how it was found.
    always_ff @(posedge clock) begin
        if (~enable) begin
            sample_l <= fm_l;
            sample_r <= fm_r;
        end
        else if (gain_valid) begin
            sample_l <= master_l;
            sample_r <= master_r;
        end
    end

endmodule
