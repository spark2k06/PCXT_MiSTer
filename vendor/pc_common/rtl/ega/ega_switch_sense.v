//============================================================================
//
//  IBM EGA monitor-switch readback
//
//  86Box models this as:
//
//      selector = (misc_output & 0x0c) >> 2;
//      status0  = switches & (8 >> selector) ? 0x10 : 0x00;
//
//  Keep that expression explicit here, and keep the whole register in the ISA
//  clock domain: 86Box has exactly one `egaswitchread`, written by ega_out()
//  and read by ega_in(), with nothing in between. Input Status Register 0 is
//  therefore answered here and only here (ega_top.v deliberately does not
//  decode 3C2h reads), because the video-domain copy of Miscellaneous Output
//  is several clocks behind the OUT that produced it.
//
//  The selector is captured from the live ISA cycle, not from the posted write
//  in the EGA I/O path. ROM 6277356 issues OUT 3C2h,01h and then, two
//  instructions later, OUT 3C2h,0Dh followed almost immediately by IN 3C2h.
//  The second OUT is still queued behind the first inside the stretcher when
//  the ROM asks for the answer, so a selector taken from the posted side is
//  one write old exactly for that first probe - which turns the CGA 80-column
//  pattern 0111b into 0110b, the CGA 40-column setting. Taking it from the
//  live cycle updates the selector during the OUT itself, so no subsequent IN
//  can ever see the previous value.
//
//============================================================================

`default_nettype wire

module ega_switch_sense_decode (
    input  wire [1:0] monitor_profile,
    input  wire [1:0] switch_select,
    output wire [7:0] status0
);

    localparam [3:0] EGA_SWITCH_5154_ECD     = 4'b1001;
    localparam [3:0] EGA_SWITCH_5153_CGA_80 = 4'b0111;
    localparam [3:0] EGA_SWITCH_5151_MDA_80 = 4'b1011;

    wire [3:0] switch_pattern =
        (monitor_profile == 2'd1) ? EGA_SWITCH_5153_CGA_80 :
        (monitor_profile == 2'd2) ? EGA_SWITCH_5151_MDA_80 :
                                    EGA_SWITCH_5154_ECD;

    wire [3:0] selected_mask = 4'b1000 >> switch_select;

    assign status0 = |(switch_pattern & selected_mask) ? 8'h10 : 8'h00;

endmodule
module ega_switch_sense_host (
    input  wire        clock,
    input  wire        reset,
    input  wire [1:0]  monitor_profile,
    input  wire [14:0] io_address,
    input  wire [7:0]  io_data,
    input  wire        io_write_n,
    input  wire        io_read_n,
    input  wire        address_enable_n,
    output wire [7:0]  data_out,
    output wire        output_enable
);

    wire switch_port = (io_address == 15'h03C2) ||
                       (io_address == 15'h02C2);

    reg [1:0] switch_select = 2'b00;

    // Sampled on every clock the write command is asserted, so the value that
    // survives is the one that was on the bus at the end of the cycle. The
    // 8288 raises DEN with the command and the bus arbiter selects the CPU's
    // own data while it is transmitting, so io_data carries the OUT operand
    // for the whole of that window.
    always @(posedge clock or posedge reset) begin
        if (reset)
            switch_select <= 2'b00;
        else if (switch_port && !address_enable_n && !io_write_n)
            switch_select <= io_data[3:2];
    end

    ega_switch_sense_decode decode (
        .monitor_profile (monitor_profile),
        .switch_select   (switch_select),
        .status0         (data_out)
    );

    assign output_enable = switch_port && !address_enable_n && !io_read_n;

endmodule
