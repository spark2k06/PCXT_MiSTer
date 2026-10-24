//
// mem_map_ega against the decode of the RAM.sv it replaces (PCXT-EGA c6b4dc8):
//
//   ram_address_select_n = ~(enable_sdram && ~(address[19:17] == 3'b101) &&
//        (umb_enabled || (address[19:14] != 110001 && != 110010 && != 110011)) &&
//        (~ems_page_frame || ems_bank_select));
//
// The select has to be that, with one difference that is meant: EC000-EFFFF
// with no EC00 ROM and no EMS bank is open bus (as in mem_map, F1). The physical
// address is checked against the memory map, region by region.
//
`timescale 1ns / 1ps

module mem_map_ega_tb;
    import sdram_pkg::*;

    logic [19:0] address;
    logic [6:0]  map_ems [0:3];
    logic        ems_b1, ems_b2, ems_b3, ems_b4;
    logic        umb_enabled, ec00_loaded;
    logic [2:0]  bios_protect_flag;
    wire         select;
    wire [24:0]  phys;
    wire         protect;

    mem_map_ega dut (
        .address(address), .map_ems(map_ems), .ems_b1(ems_b1), .ems_b2(ems_b2),
        .ems_b3(ems_b3), .ems_b4(ems_b4), .umb_enabled(umb_enabled),
        .bios_protect_flag(bios_protect_flag),
        .ec00_loaded(ec00_loaded), .select(select), .phys(phys), .protect(protect)
    );

    int errors = 0, checks = 0;

    task automatic fail(input string what);
        begin
            errors++;
            if (errors < 20)
                $display("FAIL %s: addr %05h umb %b ems %b%b%b%b ec00 %b -> sel %b phys %07h prot %b",
                         what, address, umb_enabled, ems_b1, ems_b2, ems_b3, ems_b4,
                         ec00_loaded, select, phys, protect);
        end
    endtask

    function automatic logic golden_select(input logic [19:0] a, input logic umb, input logic [3:0] eb,
                                           input logic ec);
        logic ems_page_frame, ems_bank, base;
        begin
            ems_page_frame = (a[19:16] == 4'b1101);
            ems_bank       = |eb;
            base = ~(a[19:17] == 3'b101) &&
                   (umb || (a[19:14] != 6'b110001 && a[19:14] != 6'b110010 && a[19:14] != 6'b110011)) &&
                   (~ems_page_frame || ems_bank);
            // the intended difference
            if (a[19:14] == 6'b111011 && ~ems_bank && ~ec) base = 1'b0;
            golden_select = base;
        end
    endfunction

    initial begin
        for (int i = 0; i < 4; i++) map_ems[i] = 7'(i * 13 + 5);
        bios_protect_flag = 3'b101;
        for (int cfg = 0; cfg < 32; cfg++) begin
            umb_enabled  = cfg[0];
            ec00_loaded  = cfg[1];
            {ems_b1, ems_b2, ems_b3, ems_b4} = 4'b0000;
            case (cfg[4:2])
                3'd1: ems_b1 = 1'b1;
                3'd2: ems_b2 = 1'b1;
                3'd3: ems_b3 = 1'b1;
                3'd4: ems_b4 = 1'b1;
                default: ;
            endcase
            // every 16K page with its edge and middle offsets, then a stride over everything
            for (int k = 0; k < 64 + 1048576 / 17 + 1; k++) begin
                logic [19:0] ad;
                if (k < 64) begin
                    ad = {6'(k), 14'h0000};
                    case (cfg % 4)
                        1: ad[13:0] = 14'h0001;
                        2: ad[13:0] = 14'h3FFF;
                        3: ad[13:0] = 14'h2AAA;
                        default: ;
                    endcase
                end
                else
                    ad = 20'((k - 64) * 17);
                address = ad;
                #1;
                checks++;
                if (select !== golden_select(address, umb_enabled, {ems_b1, ems_b2, ems_b3, ems_b4},
                                             ec00_loaded))
                    fail("select");
                if (select) begin
                    if (ems_b1 | ems_b2 | ems_b3 | ems_b4) begin
                        logic [6:0] pg;
                        pg = ems_b1 ? map_ems[0] : ems_b2 ? map_ems[1] : ems_b3 ? map_ems[2] : map_ems[3];
                        if (phys !== PHYS_EMS + {4'd0, pg, address[13:0]}) fail("EMS phys");
                        if (protect) fail("EMS protect");
                    end
                    else if (address[19:16] == 4'hF) begin
                        if (phys !== PHYS_ROM_BANK + {9'd0, address[15:0]}) fail("F000 phys");
                        if (protect !== bios_protect_flag[1]) fail("F000 protect");
                    end
                    else if (address[19:14] == 6'b111011) begin
                        if (phys !== PHYS_ROM_BANK + 25'h3_0000 + {11'd0, address[13:0]}) fail("EC00 phys");
                        if (protect !== bios_protect_flag[0]) fail("EC00 protect");
                    end
                    else if (address[19:14] == 6'b110000) begin
                        if (phys !== PHYS_ROM_BANK + 25'h3_4000 + {11'd0, address[13:0]}) fail("EGA BIOS phys");
                        if (protect !== bios_protect_flag[2]) fail("EGA BIOS protect");
                    end
                    else begin
                        if (phys !== PHYS_CPU_IMAGE + {5'd0, address}) fail("image phys");
                        if (protect) fail("image protect");
                    end
                end
            end
        end
        $display("mem_map_ega: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("RESULT: PASS"); else $display("RESULT: FAIL");
        $finish;
    end
endmodule
