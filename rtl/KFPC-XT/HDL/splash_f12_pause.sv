// F12 while the boot splash is on screen holds it there.
//
// The machine is held in reset for the duration of the splash, so the normal
// keyboard controller cannot decode F12. This watches hps_io's decoded key
// stream instead, which remains active outside that reset.

module splash_f12_pause (
    input  logic        clock,
    input  logic        splash_active,
    // {toggle, pressed, extended, code} from hps_io, in another clock domain.
    input  logic [10:0] ps2_key,
    output logic        paused
);

    localparam [7:0] PS2_SET2_F12 = 8'h07;

    // Keep the toggle one stage ahead of the key data so both describe the
    // same framework event after synchronization.
    (* ASYNC_REG = "TRUE" *) logic [2:0] toggle_sync = 3'b000;
    (* ASYNC_REG = "TRUE" *) logic [9:0] key_sync_0  = 10'd0;
    logic [9:0] key_sync_1 = 10'd0;

    wire key_event = toggle_sync[2] ^ toggle_sync[1];
    wire f12_break = key_event & ~key_sync_1[9] & ~key_sync_1[8] &
                     (key_sync_1[7:0] == PS2_SET2_F12);

    initial paused = 1'b0;

    always_ff @(posedge clock) begin
        toggle_sync <= {toggle_sync[1:0], ps2_key[10]};
        key_sync_0  <= ps2_key[9:0];
        key_sync_1  <= key_sync_0;

        if (!splash_active)
            paused <= 1'b0;
        else if (f12_break)
            paused <= ~paused;
    end

endmodule
