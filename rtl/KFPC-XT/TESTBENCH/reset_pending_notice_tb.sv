//============================================================================
//
//  Reset-pending notice regression.
//
//  The property that matters is when the notice is raised.  The framework
//  discards a notice while its own menu is open, and the menu is where the
//  user is standing when they change the option, so raising it on the change
//  would be raising it into the void.  It has to wait for the menu to close.
//
//    iverilog -g2012 -o pend_tb TESTBENCH/reset_pending_notice_tb.sv \
//      HDL/reset_pending_notice.sv
//    vvp pend_tb
//
//============================================================================

`timescale 1ns/1ps

module reset_pending_notice_tb;

    logic clock      = 1'b0;
    logic pending    = 1'b0;
    logic osd_status = 1'b0;
    logic suppress   = 1'b0;
    wire [7:0] info;
    wire       info_req;

    always #34.92 clock = ~clock;   // 14.318 MHz

    // Shrunk so the bench runs in microseconds; the behaviour is what is tested.
    reset_pending_notice #(
        .INFO_WIDTH (16'd20),
        .INFO_INDEX (8'd3)
    ) dut (
        .clock      (clock),
        .pending    (pending),
        .osd_status (osd_status),
        .suppress   (suppress),
        .info       (info),
        .info_req   (info_req)
    );

    integer errors = 0;

    task automatic check(input string tag, input logic expected);
        begin
            if (info_req !== expected) begin
                errors = errors + 1;
                $display("FAIL: %s info_req=%0b expected=%0b", tag, info_req, expected);
            end
        end
    endtask

    // Open the menu, change something, close it again.
    task automatic menu_visit;
        begin
            osd_status = 1'b1;
            repeat (8) @(posedge clock);
            osd_status = 1'b0;
            repeat (8) @(posedge clock);
        end
    endtask

    initial begin
        repeat (8) @(posedge clock);
        check("idle raises nothing", 1'b0);

        // Nothing pending: closing the menu must stay silent.
        menu_visit();
        check("closing the menu with nothing pending stays silent", 1'b0);

        // A pending change alone is not enough - the user is still in the menu,
        // where the framework would throw the notice away.
        pending = 1'b1;
        osd_status = 1'b1;
        repeat (8) @(posedge clock);
        check("pending change while the menu is open stays silent", 1'b0);

        // Closing it is what speaks.
        osd_status = 1'b0;
        repeat (6) @(posedge clock);
        check("closing the menu raises the notice", 1'b1);
        if (info !== 8'd3) begin
            errors = errors + 1;
            $display("FAIL: info=%0d expected=3", info);
        end

        // And it lets go by itself rather than latching on.
        repeat (30) @(posedge clock);
        check("the notice releases after its window", 1'b0);

        // Still pending, so a second visit asks again - once per close, which
        // is what keeps this from becoming a periodic nag.
        menu_visit();
        repeat (2) @(posedge clock);
        check("a later menu close asks again while still pending", 1'b1);
        repeat (30) @(posedge clock);

        // Applying the setting clears the source, and the notice goes quiet.
        pending = 1'b0;
        menu_visit();
        repeat (2) @(posedge clock);
        check("once applied the notice stops", 1'b0);

        // The halt notice owns the info box while it is up.
        pending  = 1'b1;
        suppress = 1'b1;
        menu_visit();
        repeat (2) @(posedge clock);
        check("suppressed while a more important notice is up", 1'b0);

        suppress = 1'b0;
        menu_visit();
        repeat (2) @(posedge clock);
        check("speaks again once the suppression lifts", 1'b1);

        if (errors == 0)
            $display("RESULT: PASS (notice is raised on menu close while pending)");
        else
            $display("RESULT: FAIL (%0d checks)", errors);
        $finish;
    end

endmodule
