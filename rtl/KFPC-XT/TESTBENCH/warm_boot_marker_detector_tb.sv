`timescale 1ns/1ps

module warm_boot_marker_detector_tb;

    logic        clock = 1'b0;
    logic        reset = 1'b1;
    logic [19:0] address = 20'h00000;
    logic        address_enable_n = 1'b1;
    logic        memory_write_n = 1'b1;
    logic [7:0]  byte_data = 8'h00;
    logic        word_write_request = 1'b0;
    logic [15:0] word_data = 16'h0000;
    logic        warm_boot_event;

    always #5 clock = ~clock;

    warm_boot_marker_detector dut (
        .clock             (clock),
        .reset             (reset),
        .address           (address),
        .address_enable_n  (address_enable_n),
        .memory_write_n    (memory_write_n),
        .byte_data         (byte_data),
        .word_write_request(word_write_request),
        .word_data         (word_data),
        .warm_boot_event   (warm_boot_event)
    );

    task automatic fail(input string message);
        begin
            $display("FAIL: %s", message);
            $fatal(1);
        end
    endtask

    task automatic idle;
        begin
            address_enable_n   = 1'b1;
            memory_write_n     = 1'b1;
            word_write_request = 1'b0;
            @(posedge clock);
            #1;
            if (warm_boot_event)
                fail("unexpected event while idle");
        end
    endtask

    task automatic byte_write(input logic [19:0] write_address,
                              input logic [7:0] write_data);
        begin
            @(negedge clock);
            address          = write_address;
            byte_data       = write_data;
            address_enable_n = 1'b0;
            memory_write_n   = 1'b0;
            @(posedge clock);
            #1;
            address_enable_n = 1'b0;
            memory_write_n   = 1'b1;
            @(negedge clock);
            address_enable_n = 1'b1;
        end
    endtask

    task automatic word_write(input logic [19:0] write_address,
                              input logic [15:0] write_data);
        begin
            @(negedge clock);
            address           = write_address;
            word_data         = write_data;
            word_write_request = 1'b1;
            address_enable_n  = 1'b0;
            memory_write_n    = 1'b0;
            @(posedge clock);
            #1;
            address_enable_n  = 1'b0;
            memory_write_n    = 1'b1;
            word_write_request = 1'b0;
            @(negedge clock);
            address_enable_n  = 1'b1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clock);
        reset = 1'b0;
        idle();

        // The standard 8088 little-endian byte sequence must be recognised.
        byte_write(20'h00472, 8'h34);
        idle();
        byte_write(20'h00473, 8'h12);
        #1;
        if (!warm_boot_event)
            fail("8088 marker was not recognised");
        idle();

        // A bad second byte must not be accepted.
        byte_write(20'h00472, 8'h34);
        byte_write(20'h00473, 8'h00);
        idle();

        // The 8086 wide path must be recognised as well.
        word_write(20'h00472, 16'h1234);
        #1;
        if (!warm_boot_event)
            fail("8086 marker was not recognised");
        idle();

        $display("RESULT: PASS");
        $finish;
    end

endmodule
