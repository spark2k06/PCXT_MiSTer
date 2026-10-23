//
// rom_loader: ioctl downloads as hps_io sends them (one ioctl_wr per 16-bit
// word, never while ioctl_wait is high), the bus hold handshake, the slot
// addresses in the ROM bank, write_main, and a transaction port that takes
// a variable number of clocks.
//
`timescale 1ns / 1ps

module rom_loader_tb #(
    // 0: a PCXT build (slot 0 only), 1: a build that is only a Tandy 1000 (slot 1
    // only), 2: a build that chooses the machine at run time (both slots), 3: a
    // build that is only a PCjr (slot 4 only)
    parameter int MODEL = 0
);
    localparam bit HAS_PCXT  = (MODEL != 1) && (MODEL != 3);
    localparam bit HAS_TANDY = (MODEL != 0) && (MODEL != 3);
    localparam bit HAS_PCJR  = (MODEL == 3);

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
    wire         write_any, write_main, write_tandy, write_pcjr, ec00_loaded;
    wire  [7:0]  cart1_seg, cart2_seg;
    wire  [16:0] cart1_len, cart2_len;

    rom_loader #(.ROM_PCXT(HAS_PCXT), .ROM_TANDY(HAS_TANDY), .ROM_PCJR(HAS_PCJR), .ROM_PCJR_CART(HAS_PCJR)) dut (
        .clock(clock), .reset(reset), .sdram_ready(1'b1),
        .ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_data(ioctl_data), .ioctl_wait(ioctl_wait),
        .hold_request(hold_request), .hold_granted(hold_granted),
        .l_start(l_start), .l_addr(l_addr), .l_wdata(l_wdata), .l_busy(l_busy), .l_done(l_done),
        .write_any(write_any), .write_main(write_main), .write_tandy(write_tandy),
        .write_pcjr(write_pcjr), .ec00_loaded(ec00_loaded),
        .cart1_seg(cart1_seg), .cart1_len(cart1_len), .cart2_seg(cart2_seg), .cart2_len(cart2_len)
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
    int     writes = 0, mains = 0, tandys = 0, pcjrs = 0;
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
        if (write_tandy) tandys++;
        if (write_pcjr) pcjrs++;
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

    // A JRC cartridge: 256 words of header (the word at byte 1CEh carries the
    // address in its high byte), then the ROM
    task automatic download_cart(input logic [7:0] index, input int rom_words, input int seed,
                                 input logic [7:0] seg);
        ioctl_index    <= index;
        ioctl_download <= 1;
        @(posedge clock);
        for (int i = 0; i < 256 + rom_words; i++) begin
            while (ioctl_wait) @(posedge clock);
            ioctl_addr <= 25'(i * 2);
            ioctl_data <= (i == 231) ? {seg, 8'h12} : (i < 256) ? 16'(i + 1000) : 16'((i - 256) * 3 + seed);
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

        if (ec00_loaded) err("EC00 flagged as loaded before any download");
        writes = 0; mains = 0; tandys = 0;
        if (HAS_PCXT) begin
            download(8'd0, 300, 1);
            if (ec00_loaded) err("EC00 flagged as loaded by the PCXT BIOS");
            verify((PHYS_ROM_BANK + ROM_PCXT_BIOS) >> 1, 300, 1, 0, "PCXT BIOS");
            if (writes != 300) err($sformatf("PCXT BIOS: %0d writes", writes));
            if (mains != 300) err($sformatf("write_main pulsed %0d times", mains));
            if (tandys != 0) err("write_tandy for the PCXT slot");
        end
        else begin
            // A build that is only a Tandy 1000 does not offer the PCXT slot
            download(8'd0, 40, 5);
            if (writes != 0 || mains != 0) err("PCXT slot written in a Tandy-only build");
        end

        if (HAS_TANDY) begin
            writes = 0; mains = 0; tandys = 0;
            download(8'd1, 200, 3);
            if (ec00_loaded) err("EC00 flagged as loaded by the Tandy BIOS");
            verify((PHYS_ROM_BANK + ROM_TANDY_BIOS) >> 1, 200, 3, 0, "Tandy BIOS");
            if (writes != 200) err($sformatf("Tandy BIOS: %0d writes", writes));
            if (tandys != 200) err($sformatf("write_tandy pulsed %0d times", tandys));
            if (mains != 0) err("write_main for the Tandy slot");
            // Both images sit in their own place: the Tandy one did not overwrite the PCXT one
            if (HAS_PCXT)
                verify((PHYS_ROM_BANK + ROM_PCXT_BIOS) >> 1, 300, 1, 0, "PCXT BIOS after the Tandy one");
        end

        writes = 0; mains = 0; tandys = 0; pcjrs = 0;
        if (HAS_PCJR) begin
            download(8'd4, 150, 11);
            if (ec00_loaded) err("EC00 flagged as loaded by the PCjr BIOS");
            verify((PHYS_ROM_BANK + ROM_PCJR_BIOS) >> 1, 150, 11, 0, "PCjr BIOS");
            if (writes != 150) err($sformatf("PCjr BIOS: %0d writes", writes));
            if (pcjrs != 150) err($sformatf("write_pcjr pulsed %0d times", pcjrs));
            if (mains != 0 || tandys != 0) err("write_main / write_tandy for the PCjr slot");
        end
        else begin
            download(8'd4, 50, 11);      // PCjr slot: not in a PCXT or Tandy build
            if (writes != 0 || pcjrs != 0) err("PCjr slot written in a build without it");
        end

        // Cartridges: the ROM only goes to its slot, the header gives the address
        if (HAS_PCJR) begin
            if (cart1_len !== 17'd0 || cart2_len !== 17'd0) err("cartridge lengths not zero at reset");
            writes = 0;
            download_cart(8'd5, 3000, 21, 8'hD0);
            verify((PHYS_ROM_BANK + ROM_PCJR_CART1) >> 1, 3000, 21, 0, "cartridge 1");
            if (writes != 3000) err($sformatf("cartridge 1: %0d writes (the header must not be stored)", writes));
            if (cart1_seg !== 8'hD0 || cart1_len !== 17'd6000) err($sformatf("cartridge 1: seg %02h len %0d", cart1_seg, cart1_len));
            if (cart2_len !== 17'd0) err("cartridge 2 changed by cartridge 1");
            writes = 0;
            download_cart(8'd6, 32768, 33, 8'hE0);           // 64 KiB, the largest
            verify((PHYS_ROM_BANK + ROM_PCJR_CART2) >> 1, 32768, 33, 0, "cartridge 2 (64 KiB)");
            if (cart2_seg !== 8'hE0 || cart2_len !== 17'd65536) err($sformatf("cartridge 2: seg %02h len %0d", cart2_seg, cart2_len));
            if (cart1_len !== 17'd6000) err("cartridge 1 changed by cartridge 2");
            verify((PHYS_ROM_BANK + ROM_PCJR_CART1) >> 1, 3000, 21, 0, "cartridge 1 after cartridge 2");
            // Loading a new image empties the slot at once and keeps the other one
            download_cart(8'd5, 100, 5, 8'hC8);
            if (cart1_seg !== 8'hC8 || cart1_len !== 17'd200) err($sformatf("cartridge 1 reloaded: seg %02h len %0d", cart1_seg, cart1_len));
            if (ec00_loaded) err("EC00 flagged as loaded by a cartridge");
        end
        else begin
            download(8'd5, 50, 9);
            if (cart1_len !== 17'd0) err("cartridge written in a build without them");
        end

        writes = 0; mains = 0; tandys = 0; pcjrs = 0;
        download(8'd2, 9000, 7);         // 18000 bytes: wraps inside 16 KiB
        verify((PHYS_ROM_BANK + ROM_EC00) >> 1, 9000, 7, 8192, "EC00 (16 KiB window)");
        if (mains != 0 || tandys != 0 || pcjrs != 0) err("write_main / write_tandy / write_pcjr for EC00");
        if (!ec00_loaded) err("EC00 not flagged as loaded after its download");

        writes = 0;
        if (!HAS_TANDY) begin
            download(8'd1, 50, 9);       // Tandy slot: not in a PCXT build
            if (writes != 0) err("Tandy slot written in a PCXT build");
        end

        writes = 0;
        download(8'd3, 50, 9);           // unknown index: ignored
        if (writes != 0) err("unknown index written");
        if (!ec00_loaded) err("EC00 flag dropped by a later download");

        reset <= 1;
        repeat (3) @(posedge clock);
        reset <= 0;
        repeat (3) @(posedge clock);
        if (ec00_loaded) err("EC00 flag survived a reset");

        $display("RESULT: %s", errors == 0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule
