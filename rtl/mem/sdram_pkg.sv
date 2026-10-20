//
// Shared definitions of the SDRAM subsystem.
//
// The memory subsystem is split as in the unified-core specification:
//
//   client (cpu_mem_port, rom_loader, later vram_fetch)
//     -> sdram_xbridge   (only where a client lives in another clock domain)
//     -> sdram_arbiter   (priorities, refresh debt, statistics)
//     -> sdram_ctrl      (chip timing; platform layer)
//
// sdram_port protocol, as seen by a client of the arbiter (clk_sdram domain):
//
//   req     level, held with every field stable until ack
//   ack     one clock: the request has been captured. A write is complete
//           from the client's point of view - nothing issued later, by any
//           client, can overtake it. A read now waits for its beats.
//   we      1 = write
//   addr    16-bit word address {bank[1:0], row[12:0], col[8:0]}
//   len     LEN_1 / LEN_2 / LEN_4 consecutive words. A burst must not cross
//           the end of its 512-word row (the controller does not check).
//   wdata   word i in bits [16*i +: 16]
//   wbe     byte enables, bit 2*i = low byte of word i
//   rvalid  one clock per read word, in order, with rdata
//   rlast   with the last rvalid of a read
//
// Physical map (byte addresses). Storage is packed: two bytes per
// 16-bit word, the even byte in the low lane.
//
package sdram_pkg;

    localparam logic [1:0] LEN_1 = 2'd0;
    localparam logic [1:0] LEN_2 = 2'd1;
    localparam logic [1:0] LEN_4 = 2'd2;

    // Number of words of a burst code.
    function automatic logic [2:0] len_words(input logic [1:0] len);
        case (len)
            LEN_1:   len_words = 3'd1;
            LEN_2:   len_words = 3'd2;
            default: len_words = 3'd4;
        endcase
    endfunction

    // Bank 0: the 1 MiB image of the CPU address space, then the ROM bank.
    localparam logic [24:0] PHYS_CPU_IMAGE = 25'h000_0000;
    localparam logic [24:0] PHYS_ROM_BANK  = 25'h010_0000;
    // Bank 1: video memory. Only CGA and HGC so far.
    localparam logic [24:0] PHYS_CGA       = 25'h085_0000;   // 16 KiB used, 32 KiB reserved
    localparam logic [24:0] PHYS_HGC       = 25'h086_0000;   // 64 KiB: two 32 KiB pages
    // Bank 2: Lo-tech EMS, 2 MiB.
    localparam logic [24:0] PHYS_EMS       = 25'h100_0000;

    // Offsets inside the ROM bank.
    localparam logic [19:0] ROM_PCXT_BIOS  = 20'h0_0000;   // 64 KiB
    localparam logic [19:0] ROM_TANDY_BIOS = 20'h1_0000;   // 64 KiB
    localparam logic [19:0] ROM_PCJR_BIOS  = 20'h2_0000;   // 64 KiB
    localparam logic [19:0] ROM_EC00       = 20'h3_0000;   // 16 KiB
    localparam logic [19:0] ROM_EGA_BIOS   = 20'h3_4000;   // 16 KiB (32 KiB reserved)
    localparam logic [19:0] ROM_PCJR_CART1 = 20'h4_0000;   // 64 KiB
    localparam logic [19:0] ROM_PCJR_CART2 = 20'h5_0000;   // 64 KiB

    // Class of a CPU access to video memory, from mem_map. It tells the memory
    // port that the address is not system RAM: no RAM wait states, one byte at
    // a time, and for the CGA the write is made at the end of the bus cycle.
    localparam logic [1:0] VC_NONE = 2'd0;
    localparam logic [1:0] VC_CGA  = 2'd1;
    localparam logic [1:0] VC_HGC  = 2'd2;

    // Client tags, also the arbiter port numbers.
    localparam logic [1:0] TAG_VID = 2'd0;
    localparam logic [1:0] TAG_CPU = 2'd1;
    localparam logic [1:0] TAG_LDR = 2'd2;
    localparam logic [1:0] TAG_AUX = 2'd3;

endpackage
