// XTEGACTL - per-program hardware control for the PCXT-EGA core.
//
// A DOS program writes these ports to set the machine up the way it wants
// before it runs, the way a launcher or a batch file would, without the user
// having to walk the OSD.  Everything here takes effect immediately: nothing
// in this block needs a reset, which is the whole contract.  Options that are
// only sampled while reset is asserted - CPU type, the EGA monitor switches,
// the 2nd SD card mapping - deliberately have no port, because they describe
// the user's machine rather than the program running on it.
//
// This module is only the port block.  What the registers mean, and how they
// combine with the menu, is xtegactl_resolve, which lives up in the top level
// where the OSD status is.
//
// Address block, 8980h..898Fh
// ---------------------------
//   8980h  R   signature, 'E'
//   8981h  R/W CPU        [2:0] speed  [4:3] fake 286 FLAGS
//   8982h  R/W expansion  [1:0] OPL2  [3:2] CMS  [5:4] EMS  [7:6] UMB
//   8983h  R/W video      [1:0] VGA 13h+ (0/1 off, 2 on; warm boot clears)
//   8984h  R/W input      [1:0] joy 1  [3:2] joy 2  [5:4] swap  [7:6] joy sync
//   8985h  R/W MIDI       [1:0] MT32-pi mode  [3:2] MPU-401
//   8986h  R/W expansion 2 [1:0] Tandy sound  [3:2] Sound Blaster
//                         [5:4] Sound Blaster IRQ (0=OSD, 1=IRQ5, 2=IRQ7)
//   8987h  R/W CRT offset [3:0] H offset  [6:4] V offset  [7] override
//   8988h  R/W sync width [2:0] VSync  [5:3] HSync   (0 = OSD)
//   8989h  R   effective CPU/audio status
//   898Ah  R   effective memory/video/input status
//   898Bh  R   effective input/MIDI/audio status ([7:6] = 10b marker)
//   898Ch  R   effective CRT position
//   898Dh  R   effective sync widths ([7:6] = OSD-match flags)
//   898Eh  R   OSD-match flags [7:0]
//   898Fh  R   OSD-match flags [15:8]
//
// The CRT offsets keep the menu's convention of deferring to the OSD, but
// they cannot do it the way every other field does. Elsewhere a zero field
// means "leave it to the OSD"; here zero is a real offset, so bit 7 of
// 8987h says whether the register is speaking at all.
//
// The sync widths use the same zero-as-defer rule as the other fields: zero
// follows the OSD and a non-zero value is a per-program override. The OSD
// fields live in the first six extended status bits beyond the legacy map.
//
// Why 8980h and not next to the old 8888h port: the motherboard chip select
// decoder ignores address[15:10] entirely - it qualifies on ~address[9] &
// ~address[8] and then address[7:5] - so every port whose bits 9 and 8 are
// both clear also lands on one of the on-board devices.  8888h does, and a
// write there reaches the DMA page registers, where address[1:0] picks which.
// 8888h happens to select index 0, the one nothing ever reads back, which is
// the only reason the old port was ever harmless.  Ports one, two and three
// along from it are not: they overwrite the page registers for real DMA
// channels, floppy included.  Bit 8 of 8980h is set, so the on-board decoder
// never fires anywhere in this block and all sixteen ports are usable.
//
// The status extension is read-only. Its five effective bytes deliberately
// use the same compact menu ordering as the DOS status output, while the
// match flags say whether each value equals the current OSD value. The VGA
// 13h+ bit has no match flag because that extension is controlled by VGATSR,
// not by an OSD enable setting. The high two bits of 898Bh identify the
// extension so a newer tool can fall back cleanly on an older core.

`default_nettype none

module xtegactl #(
    parameter [7:0] SIGNATURE = 8'h45   // 'E'
) (
    input  wire        clock,
    input  wire        reset,
    // A BIOS warm boot returns the machine to its native EGA hardware. Other
    // per-program overrides remain intact, but VGATSR must be run again.
    input  wire        clear_vga13,

    // Host bus
    input  wire [15:0] address,
    input  wire        address_enable_n,
    input  wire        io_read_n,
    input  wire        io_write_n,
    input  wire  [7:0] data_in,
    output wire  [7:0] data_out,
    output wire        output_enable,

    // Raw register file, for xtegactl_resolve to interpret.
    output reg   [7:0] reg_cpu  = 8'h00,
    output reg   [7:0] reg_exp  = 8'h00,
    output reg   [7:0] reg_vid  = 8'h00,
    output reg   [7:0] reg_inp  = 8'h00,
    output reg   [7:0] reg_midi = 8'h00,
    output reg   [7:0] reg_exp2 = 8'h00,
    output reg   [7:0] reg_crt  = 8'h00,
    output reg   [7:0] reg_sync = 8'h00,

    // Read-only effective configuration for XTEGACTL status.
    input  wire  [39:0] status_effective,
    input  wire  [17:0] status_osd_match
);

    localparam [11:0] BLOCK = 12'h898;

    wire block_hit = ~address_enable_n & (address[15:4] == BLOCK);
    wire iorq      = ~io_read_n | ~io_write_n;

    always @(posedge clock, posedge reset) begin
        if (reset) begin
            reg_cpu  <= 8'h00;
            reg_exp  <= 8'h00;
            reg_vid  <= 8'h00;
            reg_inp  <= 8'h00;
            reg_midi <= 8'h00;
            reg_exp2 <= 8'h00;
            reg_crt  <= 8'h00;
            reg_sync <= 8'h00;
        end
        else if (clear_vga13) begin
            reg_vid <= 8'h00;
        end
        else if (block_hit & ~io_write_n) begin
            case (address[3:0])
                4'h1: reg_cpu  <= data_in;
                4'h2: reg_exp  <= data_in;
                4'h3: reg_vid  <= data_in;
                4'h4: reg_inp  <= data_in;
                4'h5: reg_midi <= data_in;
                4'h6: reg_exp2 <= data_in;
                4'h7: reg_crt  <= data_in;
                4'h8: reg_sync <= data_in;
                default: ;      // signature and the reserved ports ignore writes
            endcase
        end
    end

    reg [7:0] read_mux;
    always @(*) begin
        case (address[3:0])
            4'h0:    read_mux = SIGNATURE;
            4'h1:    read_mux = reg_cpu;
            4'h2:    read_mux = reg_exp;
            4'h3:    read_mux = reg_vid;
            4'h4:    read_mux = reg_inp;
            4'h5:    read_mux = reg_midi;
            4'h6:    read_mux = reg_exp2;
            4'h7:    read_mux = reg_crt;
            4'h8:    read_mux = reg_sync;
            4'h9:    read_mux = status_effective[7:0];
            4'hA:    read_mux = status_effective[15:8];
            // The marker is outside the six useful bits in this byte.
            4'hB:    read_mux = {2'b10, status_effective[21:16]};
            4'hC:    read_mux = status_effective[31:24];
            // Match flags 16 and 17 share the two spare high bits here.
            4'hD:    read_mux = {status_osd_match[17:16], status_effective[37:32]};
            4'hE:    read_mux = status_osd_match[7:0];
            4'hF:    read_mux = status_osd_match[15:8];
            default: read_mux = 8'h00;
        endcase
    end

    assign output_enable = block_hit & iorq & ~io_read_n;
    assign data_out      = read_mux;

endmodule

`default_nettype wire
