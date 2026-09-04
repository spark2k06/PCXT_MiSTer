// Holds the machine at the boot splash while the required PCXT BIOS is absent.
// The hold is deliberately combinational at the splash handover: there must
// be no clock in which the CPU can start and reprogram the CRTC away from the
// known-good splash raster.

module bios_hold_notice #(
    parameter [24:0] INFO_PERIOD = 25'd21477000,
    parameter [24:0] INFO_WIDTH  = 25'd256
) (
    input  logic       clock,
    input  logic       splash_boot_phase,
    input  logic       bios_missing_pcxt,
    output logic       hold,
    output logic [7:0] info,
    output logic       info_req
);

    (* ASYNC_REG = "TRUE" *) logic [1:0] missing_pcxt_sync = 2'b00;
    logic [24:0] info_cnt = 25'd0;

    assign hold = ~splash_boot_phase & missing_pcxt_sync[1];

    always_ff @(posedge clock) begin
        missing_pcxt_sync <= {missing_pcxt_sync[0], bios_missing_pcxt};

        if (!hold) begin
            info_cnt <= 25'd0;
            info_req <= 1'b0;
            info     <= 8'd0;
        end else begin
            if (info_cnt == INFO_PERIOD)
                info_cnt <= 25'd0;
            else
                info_cnt <= info_cnt + 25'd1;

            // Index one selects the first message in the config string's I
            // section: No PCXT BIOS selected / Machine halted / OSD: ...
            info     <= 8'd1;
            info_req <= info_cnt < INFO_WIDTH;
        end
    end

endmodule
