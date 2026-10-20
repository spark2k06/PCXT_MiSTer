`timescale 1ns/1ps

module keyboard_warm_reset_tb;
    logic clock = 1'b0;
    logic reset = 1'b1;
    logic keycode_irq = 1'b0;
    logic [7:0] keycode = 8'h00;
    wire warm_reset_active;
    integer errors = 0;

    always #5 clock = ~clock;

    keyboard_warm_reset #(
        .HOLD_CYCLES(16'd4)
    ) dut (
        .clock(clock),
        .reset(reset),
        .keycode_irq(keycode_irq),
        .keycode(keycode),
        .warm_reset_active(warm_reset_active)
    );

    task automatic send_key(input logic [7:0] code);
        begin
            @(negedge clock);
            keycode = code;
            keycode_irq = 1'b1;
            @(negedge clock);
            keycode_irq = 1'b0;
        end
    endtask

    task automatic check(input string tag, input logic got, input logic want);
        begin
            if (got !== want) begin
                errors = errors + 1;
                $display("FAIL: %s got=%0b expected=%0b", tag, got, want);
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clock);
        reset = 1'b0;

        send_key(8'h53);
        check("Delete alone does not reset", warm_reset_active, 1'b0);

        send_key(8'h1D);
        send_key(8'h38);
        send_key(8'h53);
        check("Ctrl+Alt+Del starts warm reset", warm_reset_active, 1'b1);
        repeat (3) @(posedge clock);
        #1 check("warm reset remains held", warm_reset_active, 1'b1);
        @(posedge clock);
        #1 check("warm reset expires", warm_reset_active, 1'b0);

        // The detector clears its modifier latch when the chord fires, so a
        // repeated Delete cannot trigger another reset without a new chord.
        send_key(8'h53);
        check("typematic Delete does not retrigger", warm_reset_active, 1'b0);

        send_key(8'h1D);
        send_key(8'h38);
        send_key(8'h9D);
        send_key(8'h53);
        check("released Ctrl cancels the chord", warm_reset_active, 1'b0);

        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL (%0d checks)", errors);
        $finish;
    end
endmodule
