//
// IBM PCjr keyboard. The PCjr keyboard is an infrared link:
// every key arrives at the machine as a Manchester frame on a single line,
// not as a byte on port 60h. This module takes the scancodes of the PS/2
// keyboard (KFPS2KB, XT set 1) and plays the frame the PCjr receiver would
// have demodulated:
//
//   42 half-bits of HALF_BIT_CYCLES clocks each (220 us)
//     0-1    start bit  1 -> [1,0]
//     2-17   8 data bits, LSB first, each [value, ~value]
//     18-19  parity [p, ~p], p = ^data
//     20-41  stop bits, all 0
//
// The line (keyb_in) idles low. A rising edge on it sets `latch`, the source
// of the keyboard NMI (port C bit 0 and the NMI line); the CPU takes the key by
// reading port A0h, which clears it (ack). A new frame starts only when the
// latch is clear and a key is waiting in the 16 entry queue, so no key is lost
// while the BIOS handles the previous one.
//
// Auto-repeat is limited to one make code per TYPEMATIC_CYCLES (100 ms) for the
// same key, as the real keyboard does; break codes always pass.
//
module pcjr_ir_kbd #(
    parameter int HALF_BIT_CYCLES  = 11000,
    parameter int TYPEMATIC_CYCLES = 5000000
) (
    input  logic       clock,
    input  logic       reset,

    input  logic       key_valid,   // KFPS2KB irq: key_code holds a scancode
    input  logic [7:0] key_code,
    output logic       key_clear,   // KFPS2KB clear_keycode

    input  logic       ack,         // the CPU read port A0h
    output logic       keyb_in,     // the demodulated line (PPI port C bit 6)
    output logic       latch        // a frame has started and the CPU has not taken it
);
    localparam int TM_W = $clog2(TYPEMATIC_CYCLES + 1);
    localparam int HB_W = $clog2(HALF_BIT_CYCLES + 1);

    // ---- queue, with the typematic filter -------------------------------

    logic [7:0] queue [0:15];
    logic [3:0] q_head, q_tail;
    wire        q_empty = (q_head == q_tail);

    logic [TM_W-1:0] tm_timer;
    logic [6:0]      last_make;
    logic            key_seen;
    wire             tm_active = (tm_timer != '0);
    wire             filtered  = !key_code[7] && (key_code[6:0] == last_make) && tm_active;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            key_clear <= 1'b0;
            key_seen  <= 1'b0;
            q_tail    <= 4'd0;
            tm_timer  <= '0;
            last_make <= 7'd0;
        end
        else begin
            if (tm_active)
                tm_timer <= tm_timer - 1'b1;

            if (key_valid && !key_seen) begin
                key_clear <= 1'b1;
                key_seen  <= 1'b1;
                if (key_code[7]) begin
                    queue[q_tail] <= key_code;
                    q_tail        <= q_tail + 4'd1;
                    tm_timer      <= '0;
                end
                else if (!filtered) begin
                    queue[q_tail] <= key_code;
                    q_tail        <= q_tail + 4'd1;
                    last_make     <= key_code[6:0];
                    tm_timer      <= TM_W'(TYPEMATIC_CYCLES - 1);
                end
            end
            else begin
                key_clear <= 1'b0;
                if (!key_valid)
                    key_seen <= 1'b0;
            end
        end
    end

    // ---- frame transmitter ------------------------------------------------

    logic [7:0]      scancode;
    logic [5:0]      pos;           // half-bit 0-41
    logic [HB_W-1:0] phase;
    logic            sending;
    logic            parity;

    wire phase_end = (phase == '0);

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            scancode <= 8'h00;
            pos      <= 6'd0;
            sending  <= 1'b0;
            parity   <= 1'b0;
            q_head   <= 4'd0;
            phase    <= HB_W'(HALF_BIT_CYCLES - 1);
        end
        else begin
            if (!sending) begin
                phase <= HB_W'(HALF_BIT_CYCLES - 1);
                if (!q_empty && !latch) begin
                    scancode <= queue[q_head];
                    parity   <= ^queue[q_head];
                    pos      <= 6'd0;
                    sending  <= 1'b1;
                    q_head   <= q_head + 4'd1;
                end
            end
            else begin
                phase <= phase_end ? HB_W'(HALF_BIT_CYCLES - 1) : phase - 1'b1;
                if (phase_end) begin
                    if (pos == 6'd41) begin
                        sending <= 1'b0;
                        pos     <= 6'd0;
                    end
                    else
                        pos <= pos + 6'd1;
                end
            end
        end
    end

    // The level of the half-bit `pos`: [v, ~v] for the start, data and parity
    // bits, zeros for the stop bits
    wire [3:0] data_idx = pos[4:1] - 4'd1;
    wire       bit_v    = (pos < 6'd2)  ? 1'b1 :
                          (pos < 6'd18) ? scancode[data_idx[2:0]] :
                                          parity;
    wire level = (pos < 6'd20) ? (pos[0] ? ~bit_v : bit_v) : 1'b0;

    logic keyb_in_prev;
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            keyb_in      <= 1'b0;
            keyb_in_prev <= 1'b0;
            latch        <= 1'b0;
        end
        else begin
            keyb_in      <= sending & level;
            keyb_in_prev <= keyb_in;
            if (ack)
                latch <= 1'b0;
            else if (keyb_in && !keyb_in_prev)
                latch <= 1'b1;
        end
    end

endmodule
