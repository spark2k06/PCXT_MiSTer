// XTCTL identification block, read-only, 8990h..8997h.
//
// Sits next to XTEGACTL (8980h..898Fh) and answers what a DOS utility needs to
// know before it touches anything else: which machine and which video card it
// is running on, where the RTC lives, what the build contains, and a couple of
// debug counters. Every register is read-only, so a stray write is ignored.
//
//   8990h  model              00h = PCXT (01h Tandy 1000 and 02h PCjr reserved)
//   8991h  video card         [1:0] 1 = CGA, 2 = Hercules/MDA, 3 = EGA
//                             [7]   VGA 13h+ extension is switched on
//   8992h  block version      01h
//   8993h  RTC port, low byte
//   8994h  RTC port, high byte
//   8995h  capabilities       [0] EGA built    [1] VGA 13h+ built
//                             [2] CGA built    [3] Hercules/MDA built
//                             [4] Sound Blaster [5] OPL2  [6] C/MS  [7] Tandy sound
//   8996h  video underruns    video fetch underruns of the active card, saturating
//   8997h  max CPU latency    longest memory stall seen, chipset clocks, saturating
//
// A capability bit that reads zero says the hardware is not in the RBF at all,
// which is how a DOS tool tells a CGA-only build from one that has an EGA.

`default_nettype none

module xtctl_id #(
    parameter [7:0] MODEL        = 8'h00,
    parameter [7:0] VERSION      = 8'h01,
    parameter [7:0] CAPABILITIES = 8'h00
) (
    input  wire        clock,
    input  wire        reset,

    // Host bus
    input  wire [15:0] address,
    input  wire        address_enable_n,
    input  wire        io_read_n,
    output wire  [7:0] data_out,
    output wire        output_enable,

    // What the machine is running on right now
    input  wire  [1:0] video_card,
    input  wire        vga13_active,
    input  wire [15:0] rtc_port,
    input  wire [15:0] video_underruns,
    input  wire  [7:0] cpu_latency_max
);

    // 8990h..8997h: address[15:3] == 8990h >> 3
    wire hit = ~address_enable_n & ~io_read_n & (address[15:3] == 13'h1132);

    reg [7:0] read_mux;
    always @(*) begin
        case (address[2:0])
            3'd0:    read_mux = MODEL;
            3'd1:    read_mux = {vga13_active, 5'd0, video_card};
            3'd2:    read_mux = VERSION;
            3'd3:    read_mux = rtc_port[7:0];
            3'd4:    read_mux = rtc_port[15:8];
            3'd5:    read_mux = CAPABILITIES;
            3'd6:    read_mux = (|video_underruns[15:8]) ? 8'hFF : video_underruns[7:0];
            default: read_mux = cpu_latency_max;
        endcase
    end

    assign data_out      = read_mux;
    assign output_enable = hit;

    // clock and reset are kept for symmetry with the other port blocks; there
    // is nothing to clear because the block holds no state of its own.
    wire unused = &{1'b0, clock, reset};

endmodule
