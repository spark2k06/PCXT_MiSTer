// Holds the machine at the boot screen while a required BIOS image is absent,
// and keeps an explanatory notice on the OSD while it does.
//
// The point of the hold is the raster, not the reset.  An 8088 released into an
// erased F000 segment executes whatever the SDRAM happens to hold, and sooner or
// later writes the CRTC - at which point the display leaves the power-on 640x200
// and a 15 kHz television loses lock, taking the OSD with it.  Never releasing
// it keeps the picture on the one mode every set can display, which is also the
// mode the boot splash is authored for, so the user can still reach the menu and
// pick the file that is missing.
//
// `hold` is combinational on purpose.  It has to rise on the very edge that
// `splash_boot_phase` falls; a registered version would leave one clock in which
// nothing held the machine.

module bios_hold_notice #(
    // Notices are drawn for two seconds and a redraw is refused while a menu is
    // open, so re-arm just inside that window: long enough not to fight the OSD,
    // short enough that the message never blinks out.
    parameter [24:0] INFO_PERIOD = 25'd21477000,   // 1.5 s at 14.318 MHz
    parameter [24:0] INFO_WIDTH  = 25'd256
) (
    input  logic       clock,
    // High for as long as the ordinary power-on splash owns the screen.  Both
    // of its terms are one-shots, so this falls exactly once.
    input  logic       splash_boot_phase,
    // Asynchronous to `clock`; they are driven from the chipset domain.
    input  logic       bios_missing_pcxt,
    input  logic       bios_missing_ega,
    output logic       hold,
    output logic [7:0] info,
    output logic       info_req
);

    (* ASYNC_REG = "TRUE" *) logic [1:0] missing_pcxt_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) logic [1:0] missing_ega_sync  = 2'b00;

    logic [24:0] info_cnt = 25'd0;

    assign hold = ~splash_boot_phase & (missing_pcxt_sync[1] | missing_ega_sync[1]);

    always_ff @(posedge clock) begin
        missing_pcxt_sync <= {missing_pcxt_sync[0], bios_missing_pcxt};
        missing_ega_sync  <= {missing_ega_sync[0],  bios_missing_ega};

        if (!hold) begin
            info_cnt <= 25'd0;
            info_req <= 1'b0;
            info     <= 8'd0;
        end
        else begin
            if (info_cnt == INFO_PERIOD)
                info_cnt <= 25'd0;
            else
                info_cnt <= info_cnt + 25'd1;

            // Index into the "I," section of the config string, 1 based.  The
            // main BIOS is named first: an EGA option ROM is no use without a
            // machine to run it on, so reporting both at once would be noise.
            info     <= missing_pcxt_sync[1] ? 8'd1 : 8'd2;
            info_req <= info_cnt < INFO_WIDTH;
        end
    end

endmodule
