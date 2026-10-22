//
// mem_map: golden table of the PCXT (CGA + HGC) map, then a sweep of every
// 2 KiB of the address space in every option combination against a
// reference written as plain address arithmetic.
//
`timescale 1ns / 1ps

module mem_map_tb;
    import sdram_pkg::*;

    logic [19:0] address;
    logic [6:0]  map_ems [0:3];
    logic        ems_b [4];
    logic        enable_a000h;
    logic [1:0]  bios_protect_flag;
    logic        ec00_loaded;
    wire         select_x, protect_x, select_t, protect_t;
    wire  [24:0] phys_x, phys_t;

    mem_map #(.ROM_TANDY(1'b0)) dut_xt (
        .address(address), .map_ems(map_ems), .ems_b1(ems_b[0]), .ems_b2(ems_b[1]),
        .ems_b3(ems_b[2]), .ems_b4(ems_b[3]), .enable_a000h(enable_a000h),
        .bios_protect_flag(bios_protect_flag), .ec00_loaded(ec00_loaded),
        .en_cga(1'b0), .en_hgc(1'b0), .hgc_page(1'b0),
        .tandy_video(1'b0), .tandy_block(3'd0), .tandy_cpu_page(3'd0),
        .select(select_x), .phys(phys_x), .protect(protect_x),
        .vclass(), .phys2(), .phys2_valid()
    );
    mem_map #(.ROM_TANDY(1'b1)) dut_tandy (
        .address(address), .map_ems(map_ems), .ems_b1(ems_b[0]), .ems_b2(ems_b[1]),
        .ems_b3(ems_b[2]), .ems_b4(ems_b[3]), .enable_a000h(enable_a000h),
        .bios_protect_flag(bios_protect_flag), .ec00_loaded(ec00_loaded),
        .en_cga(1'b0), .en_hgc(1'b0), .hgc_page(1'b0),
        .tandy_video(1'b0), .tandy_block(3'd0), .tandy_cpu_page(3'd0),
        .select(select_t), .phys(phys_t), .protect(protect_t),
        .vclass(), .phys2(), .phys2_valid()
    );

    // The same map with the two video cards (F2)
    logic        en_cga, en_hgc, hgc_page;
    wire         select_v, protect_v, phys2_valid_v;
    wire  [24:0] phys_v, phys2_v;
    wire  [1:0]  vclass_v;
    mem_map #(.ROM_TANDY(1'b0)) dut_vid (
        .address(address), .map_ems(map_ems), .ems_b1(ems_b[0]), .ems_b2(ems_b[1]),
        .ems_b3(ems_b[2]), .ems_b4(ems_b[3]), .enable_a000h(enable_a000h),
        .bios_protect_flag(bios_protect_flag), .ec00_loaded(ec00_loaded),
        .en_cga(en_cga), .en_hgc(en_hgc), .hgc_page(hgc_page),
        .tandy_video(1'b0), .tandy_block(3'd0), .tandy_cpu_page(3'd0),
        .select(select_v), .phys(phys_v), .protect(protect_v),
        .vclass(vclass_v), .phys2(phys2_v), .phys2_valid(phys2_valid_v)
    );

    // The Tandy 1000 video memory (F5): the CGA window is a window of the CPU image
    logic        t_video = 1'b1;
    logic [2:0]  t_block, t_page;
    wire         select_tv, protect_tv, phys2_valid_tv;
    wire  [24:0] phys_tv, phys2_tv;
    wire  [1:0]  vclass_tv;
    mem_map #(.ROM_TANDY(1'b1)) dut_tv (
        .address(address), .map_ems(map_ems), .ems_b1(ems_b[0]), .ems_b2(ems_b[1]),
        .ems_b3(ems_b[2]), .ems_b4(ems_b[3]), .enable_a000h(enable_a000h),
        .bios_protect_flag(bios_protect_flag), .ec00_loaded(ec00_loaded),
        .en_cga(en_cga), .en_hgc(en_hgc), .hgc_page(hgc_page),
        .tandy_video(t_video), .tandy_block(t_block), .tandy_cpu_page(t_page),
        .select(select_tv), .phys(phys_tv), .protect(protect_tv),
        .vclass(vclass_tv), .phys2(phys2_tv), .phys2_valid(phys2_valid_tv)
    );

    // Tandy rows: the physical target (0 and select 0 when nothing)
    task automatic check_tv(input string what, input logic sel, input logic [1:0] cls, input logic [24:0] ph);
        #1;
        checks++;
        if (select_tv !== sel || (sel && (vclass_tv !== cls || phys_tv !== ph ||
                                          phys2_valid_tv !== 1'b0 || protect_tv !== 1'b0))) begin
            errors++;
            if (errors <= 20)
                $display("ERROR %s @%05h block %0d page %0d: select %b class %0d phys %07h phys2 %b, expected %b %0d %07h",
                         what, address, t_block, t_page, select_tv, vclass_tv, phys_tv, phys2_valid_tv, sel, cls, ph);
        end
    endtask

    // Video rows: select, class, primary target, second target (0 = none)
    task automatic check_vid(input string what, input logic sel, input logic [1:0] cls,
                             input logic [24:0] ph, input logic [24:0] ph2);
        #1;
        checks++;
        if (select_v !== sel || (sel && (vclass_v !== cls || phys_v !== ph ||
                                         phys2_valid_v !== (ph2 != 0) || (ph2 != 0 && phys2_v !== ph2) ||
                                         protect_v !== 1'b0))) begin
            errors++;
            if (errors <= 20)
                $display("ERROR %s @%05h page %b: select %b class %0d phys %07h phys2 %b/%07h, expected %b %0d %07h %07h",
                         what, address, hgc_page, select_v, vclass_v, phys_v, phys2_valid_v, phys2_v, sel, cls, ph, ph2);
        end
    endtask

    int errors = 0, checks = 0;

    // The EMS frame decode as Peripherals.sv does it.
    logic [1:0] frame;    // 0 C000, 1 D000, 2 E000
    logic       ems_on;
    logic [3:0] ena;
    always_comb
        for (int i = 0; i < 4; i++)
            ems_b[i] = ems_on & ena[i] & (address[19:14] == {2'b11, frame, 2'(i)});

    task automatic check(input string what, input logic sel, input logic [24:0] ph, input logic pr,
                         input logic tandy);
        logic s; logic [24:0] p; logic r;
        #1;
        s = tandy ? select_t : select_x;
        p = tandy ? phys_t   : phys_x;
        r = tandy ? protect_t : protect_x;
        checks++;
        if (s !== sel || (sel && (p !== ph || r !== pr))) begin
            errors++;
            if (errors <= 20)
                $display("ERROR %s @%05h: select %b phys %07h protect %b, expected %b %07h %b",
                         what, address, s, p, r, sel, ph, pr);
        end
    endtask

    // Reference: written from the map table, not from mem_map.
    task automatic expect_ref(input logic tandy);
        logic sel, pr;
        logic [24:0] ph;
        int page;
        #1;                       // let the EMS decode settle on the new address
        sel = 1; pr = 0;
        page = -1;
        for (int i = 0; i < 4; i++) if (ems_b[i]) page = i;
        if (address >= 20'hB0000 && address <= 20'hBFFFF) sel = 0;
        if (address >= 20'hA0000 && address <= 20'hAFFFF && !enable_a000h) sel = 0;
        // No EC00 ROM and no EMS page over it: open bus.
        if (page < 0 && !ec00_loaded && address >= 20'hEC000 && address <= 20'hEFFFF) sel = 0;
        if (page >= 0)
            ph = 25'h100_0000 + map_ems[page] * 25'h4000 + (address & 20'h3FFF);
        else if (address >= 20'hF0000) begin
            ph = 25'h010_0000 + (tandy ? 25'h1_0000 : 25'h0) + (address - 20'hF0000);
            pr = bios_protect_flag[1];
        end
        else if (address >= 20'hEC000) begin
            ph = 25'h010_0000 + 25'h3_0000 + (address - 20'hEC000);
            pr = bios_protect_flag[0];
        end
        else
            ph = address;
        check("sweep", sel, ph, pr, tandy);
    endtask

    initial begin
        map_ems[0] = 7'h00; map_ems[1] = 7'h05; map_ems[2] = 7'h40; map_ems[3] = 7'h7F;
        frame = 2'd0; ems_on = 0; ena = 4'b0000;
        enable_a000h = 1; bios_protect_flag = 2'b11; ec00_loaded = 1;

        // Golden table (PCXT, CGA + HGC)
        address = 20'h00000; check("RAM 0",        1, 25'h000_0000, 0, 0);
        address = 20'h9FFFF; check("RAM top",      1, 25'h009_FFFF, 0, 0);
        address = 20'hA1234; check("UMB A000",     1, 25'h00A_1234, 0, 0);
        enable_a000h = 0;
        address = 20'hA1234; check("UMB off",      0, 25'h0, 0, 0);
        enable_a000h = 1;
        address = 20'hB0000; check("HGC",          0, 25'h0, 0, 0);
        address = 20'hB8000; check("CGA",          0, 25'h0, 0, 0);
        address = 20'hC8000; check("C800 RAM",     1, 25'h00C_8000, 0, 0);
        address = 20'hEC000; check("EC00 slot",    1, 25'h013_0000, 1, 0);
        address = 20'hEFFFF; check("EC00 end",     1, 25'h013_3FFF, 1, 0);
        address = 20'hEBFFF; check("below EC00",   1, 25'h00E_BFFF, 0, 0);
        address = 20'hF0000; check("BIOS",         1, 25'h010_0000, 1, 0);
        address = 20'hFFFF0; check("reset vector", 1, 25'h010_FFF0, 1, 0);
        address = 20'hFFFF0; check("Tandy BIOS",   1, 25'h011_FFF0, 1, 1);
        bios_protect_flag = 2'b00;
        address = 20'hFE000; check("BIOS writable", 1, 25'h010_E000, 0, 0);
        bios_protect_flag = 2'b10;
        address = 20'hED000; check("EC00 writable", 1, 25'h013_1000, 0, 0);
        address = 20'hF1000; check("main protected", 1, 25'h010_1000, 1, 0);
        // EMS at E000: page 3 covers EC00 and wins over it, unprotected.
        ems_on = 1; frame = 2'd2; ena = 4'b1111; bios_protect_flag = 2'b11;
        address = 20'hE0010; check("EMS p0",       1, 25'h100_0010, 0, 0);
        address = 20'hE4010; check("EMS p1",       1, 25'h101_4010, 0, 0);
        address = 20'hE8010; check("EMS p2",       1, 25'h110_0010, 0, 0);
        address = 20'hEC010; check("EMS p3 over EC00", 1, 25'h11F_C010, 0, 0);
        ena = 4'b0111;
        address = 20'hEC010; check("EC00 when p3 unmapped", 1, 25'h013_0010, 1, 0);

        // No EC00 ROM loaded: the window is open bus, but an EMS page over it
        // and the rest of the map are not affected.
        ec00_loaded = 0; ems_on = 0; ena = 4'b0000;
        address = 20'hEC000; check("EC00 open bus",      0, 25'h0, 0, 0);
        address = 20'hEFFFF; check("EC00 open bus end",  0, 25'h0, 0, 0);
        address = 20'hEBFFF; check("below EC00 (no ROM)", 1, 25'h00E_BFFF, 0, 0);
        address = 20'hF0000; check("BIOS (no EC00 ROM)", 1, 25'h010_0000, 1, 0);
        ems_on = 1; frame = 2'd2; ena = 4'b1000;
        address = 20'hEC010; check("EMS p3 over open EC00", 1, 25'h11F_C010, 0, 0);
        ec00_loaded = 1; ems_on = 0; ena = 4'b0000;
        address = 20'hEC000; check("EC00 slot once loaded", 1, 25'h013_0000, 1, 0);

        // Video memory (F2): CGA 16 KiB mirrored at B8000, HGC pages at B0000/B8000
        en_cga = 1; en_hgc = 1; hgc_page = 0;
        address = 20'hB0000; check_vid("HGC page 0 start", 1, VC_HGC, 25'h086_0000, 0);
        address = 20'hB7FFF; check_vid("HGC page 0 end",   1, VC_HGC, 25'h086_7FFF, 0);
        address = 20'hB8000; check_vid("CGA start",        1, VC_CGA, 25'h085_0000, 0);
        address = 20'hBBFFF; check_vid("CGA 16K",          1, VC_CGA, 25'h085_3FFF, 0);
        address = 20'hBC000; check_vid("CGA mirror",       1, VC_CGA, 25'h085_0000, 0);
        address = 20'hBFFFF; check_vid("CGA mirror end",   1, VC_CGA, 25'h085_3FFF, 0);
        address = 20'hAFFFF; check_vid("below B000",       1, VC_NONE, 25'h00A_FFFF, 0);
        address = 20'hC0000; check_vid("above B000",       1, VC_NONE, 25'h00C_0000, 0);
        hgc_page = 1;
        address = 20'hB0000; check_vid("page 1: B0000 is nothing", 0, VC_NONE, 0, 0);
        address = 20'hB8123; check_vid("page 1: CGA and HGC", 1, VC_CGA, 25'h085_0123, 25'h086_8123);
        address = 20'hBFFFF; check_vid("page 1: end",         1, VC_CGA, 25'h085_3FFF, 25'h086_FFFF);
        en_cga = 0;
        address = 20'hB8123; check_vid("page 1, no CGA: HGC only", 1, VC_HGC, 25'h086_8123, 0);
        hgc_page = 0;
        address = 20'hB8123; check_vid("no CGA, page 0: nothing", 0, VC_NONE, 0, 0);
        en_cga = 1; en_hgc = 0;
        address = 20'hB0000; check_vid("no HGC: B0000 nothing", 0, VC_NONE, 0, 0);
        address = 20'hB8000; check_vid("no HGC: CGA",           1, VC_CGA, 25'h085_0000, 0);
        hgc_page = 1;
        address = 20'hB8000; check_vid("no HGC, page 1: CGA only", 1, VC_CGA, 25'h085_0000, 0);
        en_cga = 0;
        address = 20'hB8000; check_vid("no cards", 0, VC_NONE, 0, 0);
        en_cga = 1; en_hgc = 1; hgc_page = 0;
        // Everything outside B0000-BFFFF is as without the cards
        for (int a = 0; a < 32'h100000; a += 32'h1001) begin
            if (a < 32'hB0000 || a > 32'hBFFFF) begin
                address = 20'(a);
                #1;
                checks++;
                if (select_v !== select_x || (select_x && (phys_v !== phys_x || vclass_v !== VC_NONE || phys2_valid_v !== 1'b0))) begin
                    errors++;
                    if (errors <= 20) $display("ERROR video map changes @%05h", address);
                end
            end
        end

        // Tandy 1000: B8000-BFFFF is a window onto the 128 KiB block of the
        // CPU image that A0h[3:1] chose. 3DFh[5:3] = CPU page: bit 3 set = 16 KiB pages
        // (the page is 3DFh[5:3], so 1, 3, 5 or 7, and the offset is address[13:0]),
        // clear = 32 KiB pages (3DFh[5:4], address[14:0]). The HGC is not there.
        t_video = 1;
        en_cga = 1; en_hgc = 1; hgc_page = 0;
        t_block = 3'd0; t_page = 3'b001;          // 16 KiB page 1 of block 0
        address = 20'hB8000; check_tv("T 16K p1 start",  1, VC_CGA, 25'h000_4000);
        address = 20'hBBFFF; check_tv("T 16K p1 end",    1, VC_CGA, 25'h000_7FFF);
        address = 20'hBC000; check_tv("T 16K p1 mirror", 1, VC_CGA, 25'h000_4000);
        address = 20'hBFFFF; check_tv("T 16K p1 top",    1, VC_CGA, 25'h000_7FFF);
        t_page = 3'b111;                          // 16 KiB page 7: the last 16 KiB
        address = 20'hB8001; check_tv("T 16K p7 start",  1, VC_CGA, 25'h001_C001);
        address = 20'hBBFFF; check_tv("T 16K p7 end",    1, VC_CGA, 25'h001_FFFF);
        t_page = 3'b011;                          // 16 KiB page 3
        address = 20'hB9234; check_tv("T 16K p3",        1, VC_CGA, 25'h000_D234);
        t_page = 3'b000;                          // 32 KiB page 0
        address = 20'hB8000; check_tv("T 32K p0 start",  1, VC_CGA, 25'h000_0000);
        address = 20'hBFFFF; check_tv("T 32K p0 end",    1, VC_CGA, 25'h000_7FFF);
        t_page = 3'b100;                          // 32 KiB page 2 (3DFh[5:4] = 2)
        address = 20'hB8000; check_tv("T 32K p2 start",  1, VC_CGA, 25'h001_0000);
        address = 20'hBFFFF; check_tv("T 32K p2 end",    1, VC_CGA, 25'h001_7FFF);
        t_page = 3'b110;                          // 32 KiB page 3, the top
        address = 20'hBABCD; check_tv("T 32K p3",        1, VC_CGA, 25'h001_ABCD);
        t_block = 3'd5; t_page = 3'b011;          // block 5 (A0h[3:1] = 5): +0xA0000
        address = 20'hB8000; check_tv("T block 5 16K p3", 1, VC_CGA, 25'h00A_C000);
        t_block = 3'd7; t_page = 3'b111;          // the last byte of the 1 MiB of RAM
        address = 20'hBBFFF; check_tv("T block 7 top",   1, VC_CGA, 25'h00F_FFFF);
        // Outside the window the map is the plain one, and the HGC is gone
        address = 20'hB7FFF; check_tv("T below B8000 (HGC gone)", 0, VC_NONE, 0);
        address = 20'hB0000; check_tv("T B0000 nothing", 0, VC_NONE, 0);
        address = 20'hC0000; check_tv("T above window",  1, VC_NONE, 25'h00C_0000);
        address = 20'hAFFFF; check_tv("T below B000",    1, VC_NONE, 25'h00A_FFFF);
        // The window does not depend on the Hercules page, and the enable still gates it
        hgc_page = 1; t_block = 3'd1; t_page = 3'b001;
        address = 20'hB8000; check_tv("T hgc_page ignored", 1, VC_CGA, 25'h002_4000);
        en_cga = 0;
        address = 20'hB8000; check_tv("T no CGA: nothing", 0, VC_NONE, 0);
        en_cga = 1; hgc_page = 0;
        // Every block, page and window offset against arithmetic written here
        for (int blk = 0; blk < 8; blk++)
        for (int pg = 0; pg < 8; pg++)
        for (int off = 0; off < 32'h8000; off += 32'h1F3) begin
            logic [24:0] exp;
            t_block = 3'(blk); t_page = 3'(pg);
            address = 20'hB8000 + 20'(off);
            if (pg % 2 == 1) exp = 25'(blk * 32'h20000 + pg * 32'h4000 + (off % 32'h4000));
            else             exp = 25'(blk * 32'h20000 + (pg / 2) * 32'h8000 + off);
            check_tv("T sweep", 1, VC_CGA, exp);
        end
        t_video = 0;
        en_cga = 0; en_hgc = 0; hgc_page = 0;

        // Sweep every 2 KiB in every combination.
        for (int f = 0; f < 3; f++)
        for (int on = 0; on < 2; on++)
        for (int e = 0; e < 16; e += 5)
        for (int u = 0; u < 2; u++)
        for (int bp = 0; bp < 4; bp++)
        for (int t = 0; t < 2; t++)
        for (int l = 0; l < 2; l++)
            for (int a = 0; a < 32'h100000; a += 32'h800) begin
                frame = 2'(f); ems_on = on[0]; ena = 4'(e); enable_a000h = u[0];
                bios_protect_flag = 2'(bp); ec00_loaded = l[0];
                address = 20'(a) | 20'(($urandom & 32'h7FF));
                expect_ref(t[0]);
            end

        $display("mem_map: %0d checks, %0d errors", checks, errors);
        $display("RESULT: %s", errors == 0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule
