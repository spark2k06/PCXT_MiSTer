//
// KFPS2KB
// SIMPLE KEYBOARD CONTROLLER
//
// Written by kitune-san
//
module KFPS2KB #(
    parameter over_time = 16'd1000
) (
    input   logic           clock,
    input   logic           peripheral_clock,
    input   logic           reset,

    input   logic           device_clock,
    input   logic           device_data,

    output  logic           irq,
    output  logic   [7:0]   keycode,
    input   logic           clear_keycode
);
    //
    // Internal Signals
    //
    logic   [7:0]   register;
    logic           recieved_flag;
    logic           error_flag;
    logic           break_flag;


    //
    // Shift register
    //
    KFPS2KB_Shift_Register #(
        .over_time      (over_time)
    ) u_Shift_Register (
        .clock              (clock),
        .peripheral_clock   (peripheral_clock),
        .reset              (reset),

        .device_clock       (device_clock),
        .device_data        (device_data),

        .register           (register),
        .recieved_flag      (recieved_flag),
        .error_flag         (error_flag)
    );

    //
    // Scancode converter (2 -> 1)
    //
    function logic [7:0] scancode_converter (input [7:0] code);
        casez (code)
            8'h00: scancode_converter = 8'hFF;
            8'h01: scancode_converter = 8'h43;  // F9
            8'h02: scancode_converter = 8'h41;
            8'h03: scancode_converter = 8'h3F;  // F5
            8'h04: scancode_converter = 8'h3D;  // F3
            8'h05: scancode_converter = 8'h3B;  // F1
            8'h06: scancode_converter = 8'h3C;  // F2
            8'h07: scancode_converter = 8'h58;  // F12
            8'h08: scancode_converter = 8'h64;
            8'h09: scancode_converter = 8'h44;  // F10
            8'h0A: scancode_converter = 8'h42;  // F8
            8'h0B: scancode_converter = 8'h40;  // F6
            8'h0C: scancode_converter = 8'h3E;  // F4
            8'h0D: scancode_converter = 8'h0F;  // Tab
            8'h0E: scancode_converter = 8'h29;  // '~ `'
            8'h0F: scancode_converter = 8'h59;

            8'h10: scancode_converter = 8'h65;
            8'h11: scancode_converter = 8'h38;  // Left Alt / Right Alt
            8'h12: scancode_converter = 8'h2A;  // Left Shift
            8'h13: scancode_converter = 8'h70;  // KANA
            8'h14: scancode_converter = 8'h1D;  // Left Ctrl / Right Ctrl
            8'h15: scancode_converter = 8'h10;  // 'Q'
            8'h16: scancode_converter = 8'h02;  // '! 1'
            8'h17: scancode_converter = 8'h5A;
            8'h18: scancode_converter = 8'h66;
            8'h19: scancode_converter = 8'h71;
            8'h1A: scancode_converter = 8'h2C;  // 'Z'
            8'h1B: scancode_converter = 8'h1F;  // 'S'
            8'h1C: scancode_converter = 8'h1E;  // 'A'
            8'h1D: scancode_converter = 8'h11;  // 'W'
            8'h1E: scancode_converter = 8'h03;  // '@ 2[" 2]'
            8'h1F: scancode_converter = 8'h5B;  // Left Command

            8'h20: scancode_converter = 8'h67;
            8'h21: scancode_converter = 8'h2E;  // 'C'
            8'h22: scancode_converter = 8'h2D;  // 'X'
            8'h23: scancode_converter = 8'h20;  // 'D'
            8'h24: scancode_converter = 8'h12;  // 'E'
            8'h25: scancode_converter = 8'h05;  // '$ 4'
            8'h26: scancode_converter = 8'h04;  // '# 3'
            8'h27: scancode_converter = 8'h5C;  // Right Command
            8'h28: scancode_converter = 8'h68;
            8'h29: scancode_converter = 8'h39;  // Space
            8'h2A: scancode_converter = 8'h2F;  // 'V'
            8'h2B: scancode_converter = 8'h21;  // 'F'
            8'h2C: scancode_converter = 8'h14;  // 'T'
            8'h2D: scancode_converter = 8'h13;  // 'R'
            8'h2E: scancode_converter = 8'h06;  // '% 5'
            8'h2F: scancode_converter = 8'h5D;  // Application

            8'h30: scancode_converter = 8'h69;
            8'h31: scancode_converter = 8'h31;  // 'N'
            8'h32: scancode_converter = 8'h30;  // 'B'
            8'h33: scancode_converter = 8'h23;  // 'H'
            8'h34: scancode_converter = 8'h22;  // 'G'
            8'h35: scancode_converter = 8'h15;  // 'Y'
            8'h36: scancode_converter = 8'h07;  // '^ 6[& 6]'
            8'h37: scancode_converter = 8'h5E;
            8'h38: scancode_converter = 8'h6A;
            8'h39: scancode_converter = 8'h72;
            8'h3A: scancode_converter = 8'h32;  // 'M'
            8'h3B: scancode_converter = 8'h24;  // 'J'
            8'h3C: scancode_converter = 8'h16;  // 'U'
            8'h3D: scancode_converter = 8'h08;  // '& 7[' 7]'
            8'h3E: scancode_converter = 8'h09;  // '' 8[( 8]'
            8'h3F: scancode_converter = 8'h5F;

            8'h40: scancode_converter = 8'h6B;
            8'h41: scancode_converter = 8'h33;  // ','
            8'h42: scancode_converter = 8'h25;  // 'K'
            8'h43: scancode_converter = 8'h17;  // 'I'
            8'h44: scancode_converter = 8'h18;  // 'O'
            8'h45: scancode_converter = 8'h0B;  // ') 0 [0]'
            8'h46: scancode_converter = 8'h0A;  // '( 9[) 9]'
            8'h47: scancode_converter = 8'h60;
            8'h48: scancode_converter = 8'h6C;
            8'h49: scancode_converter = 8'h34;  // '.'
            8'h4A: scancode_converter = 8'h35;  // Numeric key '/'
            8'h4B: scancode_converter = 8'h26;  // 'L'
            8'h4C: scancode_converter = 8'h27;  // ': ;[+ ;]'
            8'h4D: scancode_converter = 8'h19;  // 'P'
            8'h4E: scancode_converter = 8'h0C;  // '_ -[= -]'
            8'h4F: scancode_converter = 8'h61;

            8'h50: scancode_converter = 8'h6D;
            8'h51: scancode_converter = 8'h7D;  // ' [| \]'
            8'h52: scancode_converter = 8'h28;  // '" '[* :]'
            8'h53: scancode_converter = 8'h74;
            8'h54: scancode_converter = 8'h1A;  // '{ [[` @]'
            8'h55: scancode_converter = 8'h0D;  // '+ =[~ ^]'
            8'h56: scancode_converter = 8'h62;
            8'h57: scancode_converter = 8'h6E;
            8'h58: scancode_converter = 8'h3A;  // Caps
            8'h59: scancode_converter = 8'h36;  // Right Shift
            8'h5A: scancode_converter = 8'h1C;  // Enter
            8'h5B: scancode_converter = 8'h1B;  // '} ][{ []'
            8'h5C: scancode_converter = 8'h75;
            8'h5D: scancode_converter = 8'h2B;  // '| \[] }]'
            8'h5E: scancode_converter = 8'h63;
            8'h5F: scancode_converter = 8'h76;

            8'h60: scancode_converter = 8'h55;
            8'h61: scancode_converter = 8'h56;
            8'h62: scancode_converter = 8'h77;
            8'h63: scancode_converter = 8'h78;
            8'h64: scancode_converter = 8'h79;  // HENKAN
            8'h65: scancode_converter = 8'h7A;
            8'h66: scancode_converter = 8'h0E;  // Backspace
            8'h67: scancode_converter = 8'h7B;  // MUHENKAN
            8'h68: scancode_converter = 8'h7C;
            8'h69: scancode_converter = 8'h4F;  // Numeric key '1' / End
            8'h6A: scancode_converter = 8'h7D;
            8'h6B: scancode_converter = 8'h4B;  // Numeric key '4' / Left
            8'h6C: scancode_converter = 8'h47;  // Numeric key '7' / Home
            8'h6D: scancode_converter = 8'h7E;
            8'h6E: scancode_converter = 8'h7F;
            8'h6F: scancode_converter = 8'h6F;

            8'h70: scancode_converter = 8'h52;  // Numeric key '0' / Insert
            8'h71: scancode_converter = 8'h53;  // Numeric key '.' / Delete
            8'h72: scancode_converter = 8'h50;  // Numeric Key '2' / Down
            8'h73: scancode_converter = 8'h4C;  // Numeric key '5'
            8'h74: scancode_converter = 8'h4D;  // Numeric key '6' / Left
            8'h75: scancode_converter = 8'h48;  // Numeric key '8' / Up
            8'h76: scancode_converter = 8'h01;  // Esc
            8'h77: scancode_converter = 8'h45;  // Num Lock / Pause
            8'h78: scancode_converter = 8'h57;  // F11
            8'h79: scancode_converter = 8'h4E;  // Numeric key '+'
            8'h7A: scancode_converter = 8'h51;  // Numeric Key '3' / Page Down
            8'h7B: scancode_converter = 8'h4A;  // Numeric key '-'
            8'h7C: scancode_converter = 8'h37;  // Numeric key '*' / Print Screen
            8'h7D: scancode_converter = 8'h49;  // Numeric key '9' / Page Up
            8'h7E: scancode_converter = 8'h46;  // Scroll
            8'h7F: scancode_converter = 8'h54;

            8'h80: scancode_converter = 8'h81;
            8'h81: scancode_converter = 8'h82;
            8'h82: scancode_converter = 8'h83;
            8'h83: scancode_converter = 8'h41;  // F7
            8'h84: scancode_converter = 8'h84;
            8'h85: scancode_converter = 8'h85;
            8'h86: scancode_converter = 8'h86;
            8'h87: scancode_converter = 8'h87;
            8'h88: scancode_converter = 8'h88;
            8'h89: scancode_converter = 8'h89;
            8'h8A: scancode_converter = 8'h8A;
            8'h8B: scancode_converter = 8'h8B;
            8'h8C: scancode_converter = 8'h8C;
            8'h8D: scancode_converter = 8'h8D;
            8'h8E: scancode_converter = 8'h8E;
            8'h8F: scancode_converter = 8'h8F;

            default:
                scancode_converter = code;
        endcase
    endfunction

    //
    // Make keycode
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            irq         <= 1'b0;
            keycode     <= 8'h00;
            break_flag  <= 1'b0;
        end
        else if (clear_keycode) begin
            irq         <= 1'b0;
            keycode     <= 8'h00;
            break_flag  <= 1'b0;
        end
        else if (error_flag) begin
            // Error
            irq         <= 1'b1;
            keycode     <= 8'hFF;
            break_flag  <= 1'b0;
        end
        else if (recieved_flag) begin
            if (irq == 1'b1) begin
                // Error
                irq         <= 1'b1;
                keycode     <= 8'hFF;
                break_flag  <= 1'b0;
            end
            else if (register == 8'hFA) begin
                // ACK (ignore)
                irq         <= 1'b0;
                keycode     <= 8'h00;
                break_flag  <= 1'b0;
            end
            else if (register == 8'hF0) begin
                irq         <= 1'b0;
                keycode     <= 8'h00;
                break_flag  <= 1'b1;
            end
            else begin
                // Make code
                irq         <= 1'b1;
                keycode     <= scancode_converter(register) | (break_flag ? 8'h80 : 8'h00);
                break_flag  <= 1'b0;
            end
        end
        else begin
            irq         <= irq;
            keycode     <= keycode;
            break_flag  <= break_flag;
        end
    end

endmodule
