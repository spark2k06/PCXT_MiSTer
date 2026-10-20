`timescale 1ns/1ps

module video_source_switch_tb;

    reg clock = 1'b0;
    always #5 clock = ~clock;

    reg reset = 1'b1;
    reg select_alt = 1'b0;
    reg primary_hsync = 1'b0;
    reg primary_vblank = 1'b0;
    reg alt_hsync = 1'b0;
    reg alt_vblank = 1'b0;
    wire alt_active;

    integer failed = 0;

    video_source_switch dut (
        .clock(clock),
        .reset(reset),
        .select_alt(select_alt),
        .primary_hsync(primary_hsync),
        .primary_vblank(primary_vblank),
        .alt_hsync(alt_hsync),
        .alt_vblank(alt_vblank),
        .alt_active(alt_active)
    );

    task check;
        input expected;
        input [255:0] message;
        begin
            @(negedge clock);
            if (alt_active !== expected) begin
                $display("FAIL: %0s (expected %0d, got %0d)",
                         message, expected, alt_active);
                failed = failed + 1;
            end
        end
    endtask

    task alt_hsync_edge;
        begin
            @(negedge clock);
            alt_hsync = ~alt_hsync;
            @(posedge clock);
        end
    endtask

    task primary_hsync_edge;
        begin
            @(negedge clock);
            primary_hsync = ~primary_hsync;
            @(posedge clock);
        end
    endtask

    initial begin
        repeat (3) @(posedge clock);
        reset = 1'b0;
        check(1'b0, "reset selects primary source");

        // Asking for the alternate source is not enough on its own, and its
        // horizontal edges outside vertical blank must not switch the mux.
        select_alt = 1'b1;
        alt_hsync_edge();
        check(1'b0, "alternate source waits for its vertical blank");

        // The primary source deliberately remains active (not blank). This is
        // the equal-rate, phase-offset case that used to wait indefinitely.
        alt_vblank = 1'b1;
        alt_hsync_edge();
        check(1'b1, "alternate source does not require simultaneous blanks");

        // Likewise, leaving the alternate path must wait for the destination
        // primary raster, not for the two blanking windows to overlap.
        select_alt = 1'b0;
        primary_hsync_edge();
        check(1'b1, "primary source waits for its vertical blank");

        alt_vblank = 1'b0;
        primary_vblank = 1'b1;
        primary_hsync_edge();
        check(1'b0, "primary source does not require simultaneous blanks");

        // Once selected, unrelated edges from the other source cannot move it.
        primary_vblank = 1'b0;
        alt_vblank = 1'b1;
        alt_hsync_edge();
        check(1'b0, "unrequested source cannot take over");

        if (failed == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL (%0d failed)", failed);

        $finish;
    end

endmodule

