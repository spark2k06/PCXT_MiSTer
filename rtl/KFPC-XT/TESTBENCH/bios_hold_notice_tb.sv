//============================================================================
//
//  Missing-BIOS hold regression.
//
//  The property that matters is the handover: the hold has to be up on the
//  very edge the splash lets go, because the reset it feeds is the only thing
//  keeping the 8088 away from the CRTC.  One clock of daylight there is enough
//  for the machine to start and leave 640x200 behind.
//
//    iverilog -g2012 -o hold_tb TESTBENCH/bios_hold_notice_tb.sv \
//      HDL/bios_hold_notice.sv
//    vvp hold_tb
//
//============================================================================

`timescale 1ns/1ps

module bios_hold_notice_tb;

    logic clock = 1'b0;
    logic splash_boot_phase = 1'b1;
    logic bios_missing_pcxt = 1'b1;
    logic bios_missing_ega  = 1'b0;
    wire  hold;
    wire [7:0] info;
    wire  info_req;

    always #34.92 clock = ~clock;   // 14.318 MHz

    // Shrunk so the bench runs in milliseconds; the ratio is what is tested.
    bios_hold_notice #(
        .INFO_PERIOD (25'd200),
        .INFO_WIDTH  (25'd20)
    ) dut (
        .clock             (clock),
        .splash_boot_phase (splash_boot_phase),
        .bios_missing_pcxt (bios_missing_pcxt),
        .bios_missing_ega  (bios_missing_ega),
        .hold              (hold),
        .info              (info),
        .info_req          (info_req)
    );

    integer errors = 0;

    task automatic check(input logic actual, input logic expected, input string what);
        begin
            if (actual !== expected) begin
                $display("FAIL: %s - expected %0d, got %0d", what, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    // Count the notices raised across a window, to prove the message is
    // repeated rather than fired once and lost.
    integer pulses = 0;
    logic   info_req_q = 1'b0;
    always @(posedge clock) begin
        if (info_req && !info_req_q) pulses = pulses + 1;
        info_req_q <= info_req;
    end

    initial begin
        repeat (4) @(posedge clock);
        check(hold, 1'b0, "held during the splash");

        // The handover.  splash_boot_phase falls between edges, exactly as it
        // does in the core, and the hold must already be up before the next one.
        #10 splash_boot_phase = 1'b0;
        #1;
        check(hold, 1'b1, "hold up on the edge the splash falls");

        repeat (500) @(posedge clock);
        check(info[0], 1'b1, "notice names the main BIOS");
        if (info !== 8'd1) begin
            $display("FAIL: expected info index 1, got %0d", info);
            errors = errors + 1;
        end
        if (pulses < 2) begin
            $display("FAIL: notice raised %0d times in 500 clocks, expected repeats",
                     pulses);
            errors = errors + 1;
        end

        // Main BIOS arrives, EGA still absent: still held, different message.
        bios_missing_pcxt = 1'b0;
        bios_missing_ega  = 1'b1;
        repeat (10) @(posedge clock);
        check(hold, 1'b1, "still held with the EGA BIOS missing");
        if (info !== 8'd2) begin
            $display("FAIL: expected info index 2, got %0d", info);
            errors = errors + 1;
        end

        // Both present: release, and stop talking about it.
        bios_missing_ega = 1'b0;
        repeat (10) @(posedge clock);
        check(hold, 1'b0, "released once both images are present");
        check(info_req, 1'b0, "notice withdrawn on release");

        // A BIOS swapped out under a running machine takes the hold again, so
        // the CPU is not left executing a half-rewritten F000.
        bios_missing_pcxt = 1'b1;
        repeat (10) @(posedge clock);
        check(hold, 1'b1, "hold retaken when an image is replaced");

        if (errors == 0)
            $display("PASS: BIOS hold covers the splash handover and repeats its notice");
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
