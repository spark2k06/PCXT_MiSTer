`timescale 1ns/1ps

// PCjr infrared keyboard: the frame for a key (start, 8 data bits, parity,
// stop bits, each as [v,~v]), the latch and the NMI hand-shake with port A0h,
// the queue (a second key waits for the first to be taken) and the typematic
// filter.
module pcjr_ir_kbd_tb;
    localparam int HB = 8;      // clocks per half-bit
    localparam int TM = 400;    // typematic window

    logic clock = 1'b0;
    logic reset = 1'b1;
    logic key_valid = 1'b0;
    logic [7:0] key_code = 8'h00;
    wire  key_clear;
    logic ack = 1'b0;
    wire  keyb_in;
    wire  latch;
    integer errors = 0;

    always #5 clock = ~clock;

    pcjr_ir_kbd #(.HALF_BIT_CYCLES(HB), .TYPEMATIC_CYCLES(TM)) dut (
        .clock(clock), .reset(reset),
        .key_valid(key_valid), .key_code(key_code), .key_clear(key_clear),
        .ack(ack), .keyb_in(keyb_in), .latch(latch)
    );

    // The keyboard controller holds irq until the chipset clears the code
    task automatic press(input logic [7:0] code);
        begin
            @(negedge clock);
            key_code = code;
            key_valid = 1'b1;
            while (!key_clear) @(negedge clock);
            key_valid = 1'b0;
            @(negedge clock);
            @(negedge clock);
        end
    endtask

    task automatic take;
        begin
            @(negedge clock);
            ack = 1'b1;
            @(negedge clock);
            ack = 1'b0;
        end
    endtask

    // Sample the 42 half-bits of a frame, from the first rising edge of the line
    task automatic frame(input string tag, input logic [7:0] code);
        logic [41:0] want, got;
        logic parity;
        integer i;
        begin
            parity = ^code;
            want[1:0] = 2'b01;      // [1,0] stored LSB = first half-bit... built below
            for (i = 0; i < 42; i = i + 1) want[i] = 1'b0;
            want[0] = 1'b1; want[1] = 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                want[2 + 2*i]     = code[i];
                want[2 + 2*i + 1] = ~code[i];
            end
            want[18] = parity; want[19] = ~parity;
            while (!keyb_in) @(posedge clock);
            repeat (HB/2) @(posedge clock);
            for (i = 0; i < 42; i = i + 1) begin
                got[i] = keyb_in;
                repeat (HB) @(posedge clock);
            end
            if (got !== want) begin
                errors = errors + 1;
                $display("FAIL: %s frame got=%b want=%b", tag, got, want);
            end
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
        repeat (3) @(posedge clock);
        reset = 1'b0;
        repeat (3) @(posedge clock);
        check("idle line low", keyb_in, 1'b0);
        check("idle latch clear", latch, 1'b0);

        // One key: the frame, with the latch up from its first edge
        press(8'h1E);
        while (!keyb_in) @(posedge clock);
        repeat (2) @(posedge clock);
        #1 check("latch rises with the frame", latch, 1'b1);
        fork
            frame("0x1E", 8'h1E);
        join
        check("latch holds until A0h is read", latch, 1'b1);
        check("line idles low after the frame", keyb_in, 1'b0);
        take;
        #1 check("A0h read clears the latch", latch, 1'b0);

        // A break code and a make code queue up: the second frame does not
        // start until the first has been taken
        press(8'h9E);
        press(8'h30);
        frame("0x9E", 8'h9E);
        repeat (6*HB) @(posedge clock);
        check("second key waits for the CPU", keyb_in, 1'b0);
        take;
        frame("0x30", 8'h30);
        take;

        // Typematic: the same make code again inside the window is dropped,
        // a different key and a break code are not
        repeat (60*HB) @(posedge clock);
        press(8'h10);
        frame("0x10 first", 8'h10);
        take;
        press(8'h10);
        repeat (50*HB) @(posedge clock);
        check("repeat inside the window is filtered", keyb_in, 1'b0);
        press(8'h90);
        frame("0x90 break passes", 8'h90);
        take;
        repeat (3*HB) @(posedge clock);
        check("nothing else queued", keyb_in, 1'b0);

        if (errors == 0) $display("RESULT: PASS");
        else $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #5000000;
        $display("TIMEOUT");
        $display("RESULT: FAIL");
        $finish;
    end
endmodule
