//============================================================================
//
//  Missing-PCXT-BIOS hold regression.
//
//============================================================================

`timescale 1ns/1ps

module bios_hold_notice_tb;

    logic       clock = 1'b0;
    logic       splash_boot_phase = 1'b1;
    logic       bios_missing_pcxt = 1'b1;
    wire        hold;
    wire [7:0]  info;
    wire        info_req;

    always #34.92 clock = ~clock;

    bios_hold_notice #(
        .INFO_PERIOD (25'd200),
        .INFO_WIDTH  (25'd20)
    ) dut (
        .clock             (clock),
        .splash_boot_phase (splash_boot_phase),
        .bios_missing_pcxt (bios_missing_pcxt),
        .hold              (hold),
        .info              (info),
        .info_req          (info_req)
    );

    integer errors = 0;
    integer pulses = 0;
    logic info_req_q = 1'b0;

    always @(posedge clock) begin
        if (info_req && !info_req_q)
            pulses = pulses + 1;
        info_req_q <= info_req;
    end

    task automatic check(input logic actual, input logic expected, input string what);
        begin
            if (actual !== expected) begin
                $display("FAIL: %s - expected %0d, got %0d", what, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clock);
        check(hold, 1'b0, "held during the splash");

        // The missing flag is already synchronized before the splash ends,
        // so the hold must be present immediately at the handover.
        #10 splash_boot_phase = 1'b0;
        #1 check(hold, 1'b1, "hold up on the splash handover");

        repeat (500) @(posedge clock);
        check(info, 8'd1, "notice names the PCXT BIOS");
        if (pulses < 2) begin
            $display("FAIL: notice raised %0d times, expected repeats", pulses);
            errors = errors + 1;
        end

        bios_missing_pcxt = 1'b0;
        repeat (10) @(posedge clock);
        check(hold, 1'b0, "released once the BIOS is present");
        check(info_req, 1'b0, "notice withdrawn on release");

        // A replacement download that leaves the slot incomplete must hold
        // the machine again rather than exposing a partially written BIOS.
        bios_missing_pcxt = 1'b1;
        repeat (10) @(posedge clock);
        check(hold, 1'b1, "hold retaken when the BIOS is removed");

        if (errors == 0)
            $display("PASS: missing PCXT BIOS holds the splash and repeats its notice");
        else
            $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #5000000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

endmodule
