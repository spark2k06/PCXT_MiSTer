// Detect the XT keyboard sequence used by BIOS Ctrl+Alt+Del handling and hold
// a hardware-side indication long enough to reset the OPL2. VGA 13h+ clearing
// is handled separately from the BIOS warm-boot marker on the memory bus.
module keyboard_warm_reset #(
    parameter logic [15:0] HOLD_CYCLES = 16'd5000
) (
    input  logic       clock,
    input  logic       reset,
    input  logic       keycode_irq,
    input  logic [7:0] keycode,
    output logic       warm_reset_active
);

    logic        prev_keycode_irq = 1'b0;
    logic        ctrl_down = 1'b0;
    logic        alt_down = 1'b0;
    logic [15:0] hold_count = 16'd0;

    assign warm_reset_active = (hold_count != 16'd0);

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            prev_keycode_irq <= 1'b0;
            ctrl_down        <= 1'b0;
            alt_down         <= 1'b0;
            hold_count       <= 16'd0;
        end
        else begin
            prev_keycode_irq <= keycode_irq;

            if (hold_count != 16'd0)
                hold_count <= hold_count - 16'd1;

            if (keycode_irq && !prev_keycode_irq) begin
                case (keycode)
                    8'h1D: ctrl_down <= 1'b1;
                    8'h9D: ctrl_down <= 1'b0;
                    8'h38: alt_down  <= 1'b1;
                    8'hB8: alt_down  <= 1'b0;
                    default: ;
                endcase

                if ((keycode == 8'h53) && ctrl_down && alt_down) begin
                    hold_count <= HOLD_CYCLES;
                    // The reboot owns the chord now. Do not let a typematic
                    // Delete retrigger later if break codes are lost in POST.
                    ctrl_down  <= 1'b0;
                    alt_down   <= 1'b0;
                end
            end
        end
    end

endmodule
