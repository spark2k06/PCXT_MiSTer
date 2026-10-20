//============================================================================
//
//  IBM EGA physical monitor-switch application point
//
//============================================================================

`default_nettype wire

module ega_monitor_profile_latch (
    input  wire       clock,
    input  wire       reset_active,
    input  wire [1:0] selected,
    output reg  [1:0] applied = 2'b00
);

    // Physical EGA switches are sampled for the next BIOS startup. Keeping
    // this latch open for the complete stretched reset also lets MiSTer's OSD
    // status settle during initial core loading and during the boot splash.
    always @(posedge clock) begin
        if (reset_active)
            applied <= selected;
    end

endmodule
