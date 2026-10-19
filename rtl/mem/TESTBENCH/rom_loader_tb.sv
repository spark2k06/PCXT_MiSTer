//
// rom_loader: ioctl downloads as hps_io sends them (one ioctl_wr per 16-bit
// word, never while ioctl_wait is high), the bus hold handshake, the slot
// addresses in the ROM bank, write_main, and a transaction port that takes
// a variable number of clocks.
//
`timescale 1ns / 1ps

module rom_loader_tb;
    import sdram_pkg::*;

    logic clock = 0;
    always #10 clock = ~clock;
    logic reset = 1;

    logic        ioctl_download = 0, ioctl_wr = 0;
    logic [7:0]  ioctl_index = 0;
    logic [24:0] ioctl_addr = 0;
    logic [15:0] ioctl_data = 0;
    wire         ioctl_wait;
    wire         hold_request;
    logic        hold_granted = 0;
    wire         l_start;  wire [23:0] l_addr;  wire [15:0] l_wdata;
    logic        l_busy = 0, l_done = 0;
    wire         write_any, write_main;

    rom_loader #(.ROM_TANDY(1'b0)) dut (
        .clock(clock), .reset(reset), .sdram_ready(1'b1),
        .ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_data(ioctl_data), .ioctl_wait(ioctl_wait),
        .hold_request(hold_request), .hold_granted(hold_granted),
        .l_start(l_start), .l_addr(l_addr), .l_wdata(l_wdata), .l_busy(l_busy), .l_done(l_done),
        .write_any(write_any), .write_main(write_main)
    );

    int errors = 0;
    task automatic err(input string m);
        errors++;
        if (errors <= 20) $display("%0t ERROR: %s", $time, m);
    endtask

    // Bus arbiter: grants HOLD a few clocks after the request.
    always @(posedge clock) begin
        if (!hold_request) hold_granted <= 0;
        else if (!hold_granted && $urandom_range(0, 3) == 0) hold_granted <= 1;
    end

    // Transaction port: busy for 3..12 clocks, then done.
    int     busy_left = 0;
    logic [15:0] mem [int unsigned];
    int     writes = 0, mains = 0;
    always @(posedge clock) begin
        l_done <= 0;
        if (l_start && !l_busy) begin
            if (!hold_granted) err("ROM write before HOLD was granted");
            l_busy    <= 1;
            busy_left = $urandom_range(3, 12);
            mem[l_addr] = l_wdata;
            writes++;
        end
        else if (l_busy) begin
            if (busy_left == 0) begin l_busy <= 0; l_done <= 1; end
            else busy_left--;
        end
        if (write_main) mains++;
    end

    // hps_io side
    task automatic download(input logic [7:0] index, input int words, input int seed);
        ioctl_index    <= index;
        ioctl_download <= 1;
        @(posedge clock);
        for (int i = 0; i < words; i++) begin
            while (ioctl_wait) @(posedge clock);
            ioctl_addr <= 25'(i * 2);
            ioctl_data <= 16'(i * 3 + seed);
            ioctl_wr   <= 1;
            @(posedge clock);
            ioctl_wr   <= 0;
            repeat ($urandom_range(1, 4)) @(posedge clock);
        end
        while (ioctl_wait) @(posedge clock);
        repeat (3) @(posedge clock);
        ioctl_download <= 0;
        repeat (5) @(posedge clock);
        if (hold_request) err("HOLD still requested after the download");
    endtask

    task automatic verify(input int unsigned base_word, input int words, input int seed,
                          input int wrap_words, input string name);
        int bad = 0;
        for (int i = 0; i < words; i++) begin
            int unsigned wa = base_word + (wrap_words ? (i % wrap_words) : i);
            int last = wrap_words ? ((words - 1 - i) < wrap_words) : 1;
            if (last && (!mem.exists(wa) || mem[wa] !== 16'(i * 3 + seed))) bad++;
        end
        if (bad) err($sformatf("%s: %0d words wrong", name, bad));
        else $display("%s: %0d words in place at word %06h", name, words, base_word);
    endtask

    initial begin
        repeat (4) @(posedge clock);
        reset <= 0;
        repeat (4) @(posedge clock);

        writes = 0; mains = 0;
        download(8'd0, 300, 1);
        verify((PHYS_ROM_BANK + ROM_PCXT_BIOS) >> 1, 300, 1, 0, "PCXT BIOS");
        if (writes != 300) err($sformatf("PCXT BIOS: %0d writes", writes));
        if (mains != 300) err($sformatf("write_main pulsed %0d times", mains));

        writes = 0; mains = 0;
        download(8'd2, 9000, 7);         // 18000 bytes: wraps inside 16 KiB
        verify((PHYS_ROM_BANK + ROM_EC00) >> 1, 9000, 7, 8192, "EC00 (16 KiB window)");
        if (mains != 0) err("write_main for EC00");

        writes = 0;
        download(8'd1, 50, 9);           // Tandy slot: not in a PCXT build
        if (writes != 0) err("Tandy slot written in a PCXT build");

        writes = 0;
        download(8'd3, 50, 9);           // unknown index: ignored
        if (writes != 0) err("unknown index written");

        $display("RESULT: %s", errors == 0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule
