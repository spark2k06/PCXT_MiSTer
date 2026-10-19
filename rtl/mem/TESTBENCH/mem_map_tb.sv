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
        .select(select_x), .phys(phys_x), .protect(protect_x)
    );
    mem_map #(.ROM_TANDY(1'b1)) dut_tandy (
        .address(address), .map_ems(map_ems), .ems_b1(ems_b[0]), .ems_b2(ems_b[1]),
        .ems_b3(ems_b[2]), .ems_b4(ems_b[3]), .enable_a000h(enable_a000h),
        .bios_protect_flag(bios_protect_flag), .ec00_loaded(ec00_loaded),
        .select(select_t), .phys(phys_t), .protect(protect_t)
    );

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
