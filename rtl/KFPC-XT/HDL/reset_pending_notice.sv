// Says so when a menu option has been changed that the machine will not pick
// up until it is reset.
//
// Three options are sampled only while reset is asserted - CPU Type, the EGA
// monitor switches and the 2nd SD card mapping - and nothing else in the menu
// distinguishes them.  Changing one and watching nothing happen is the whole
// problem this notice exists to solve.
//
// It cannot be raised at the moment of the change.  The framework refuses to
// draw a notice while its own menu is open: Info() only acts when menustate is
// at or below MENU_INFO, and a core's option list sits well above that.  The
// menu is exactly where the user is standing when they change the option, so
// the notice would be discarded unseen.  Wait for the menu to close instead,
// and speak then, which is also the first moment the message can be read.
//
// One notice per menu close, not a periodic re-arm.  bios_hold_notice re-arms
// because the machine it describes is halted and the message is the only thing
// left to say; here the machine keeps running and repeating would be noise.
//
// `info` is constant rather than registered so that it is already valid on the
// clock the framework latches it: info_req crosses into the chipset domain,
// where hps_io samples `info` on its rising edge.

module reset_pending_notice #(
    // Notices are drawn for two seconds; this only has to outlast the transfer
    // that carries it, so it is short.
    parameter [15:0] INFO_WIDTH = 16'd256,
    // Index into the "I," section of the config string, 1 based.
    parameter [7:0]  INFO_INDEX = 8'd3
) (
    input  logic       clock,
    // Asynchronous to `clock`; driven from the chipset domain.
    input  logic       pending,
    // Asynchronous to `clock`; driven by the framework's OSD.
    input  logic       osd_status,
    // High while a more important notice owns the info box.
    input  logic       suppress,
    output logic [7:0] info,
    output logic       info_req = 1'b0
);

    (* ASYNC_REG = "TRUE" *) logic [1:0] pending_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *) logic [2:0] osd_sync     = 3'b000;

    logic [15:0] info_cnt = 16'd0;

    assign info = INFO_INDEX;

    // [0] catches metastability; [2:1] is the settled edge pair.
    wire osd_closed = osd_sync[2] & ~osd_sync[1];

    always_ff @(posedge clock) begin
        pending_sync <= {pending_sync[0], pending};
        osd_sync     <= {osd_sync[1:0], osd_status};

        if (suppress) begin
            info_cnt <= 16'd0;
            info_req <= 1'b0;
        end
        else if (osd_closed & pending_sync[1]) begin
            info_cnt <= INFO_WIDTH;
            info_req <= 1'b1;
        end
        else if (info_cnt != 16'd0) begin
            info_cnt <= info_cnt - 16'd1;
            info_req <= 1'b1;
        end
        else begin
            info_req <= 1'b0;
        end
    end

endmodule
