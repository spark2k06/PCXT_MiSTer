//
// CPU memory map, combinational.
//
// F1 implements the PCXT table with CGA + HGC/MDA only; the EGA, Tandy and
// PCjr rows come with their phases. For a 20-bit bus address it gives:
//
//   select   the address is memory this port serves (not video RAM, not a
//            disabled UMB window) - the old RAM.sv ram_address_select_n
//   phys     the physical byte address in SDRAM (sdram_pkg map)
//   protect  writes are ignored (BIOS Writable)
//
//   00000-AFFFF  CPU image (A0000-AFFFF only with the A000 UMB)
//   B0000-BFFFF  not here: CGA and HGC video RAM
//   C0000-EFFFF  CPU image, or the Lo-tech EMS frame when it is mapped
//   EC000-EFFFF  EC00 ROM slot (XTIDE), unless the EMS frame covers it
//   F0000-FFFFF  PCXT BIOS slot (Tandy BIOS slot in a ROM_VARIANT_TANDY build)
//
// The EMS frame wins over the EC00 window, as it did in RAM.sv.
//
module mem_map #(
    parameter bit ROM_TANDY = 1'b0
) (
    input  logic [19:0] address,
    input  logic [6:0]  map_ems [0:3],
    input  logic        ems_b1,
    input  logic        ems_b2,
    input  logic        ems_b3,
    input  logic        ems_b4,
    input  logic        enable_a000h,
    input  logic [1:0]  bios_protect_flag,   // [1] F000 (main), [0] EC00
    output logic        select,
    output logic [24:0] phys,
    output logic        protect
);
    import sdram_pkg::*;

    localparam logic [19:0] MAIN_ROM = ROM_TANDY ? ROM_TANDY_BIOS : ROM_PCXT_BIOS;

    wire seg_f    = (address[19:16] == 4'hF);
    wire seg_ec00 = (address[19:14] == 6'b111011);

    assign select = ~(address[19:16] == 4'hB) & ~(~enable_a000h & (address[19:16] == 4'hA));

    always_comb begin
        protect = 1'b0;
        if (ems_b1)
            phys = PHYS_EMS + {4'd0, map_ems[0], address[13:0]};
        else if (ems_b2)
            phys = PHYS_EMS + {4'd0, map_ems[1], address[13:0]};
        else if (ems_b3)
            phys = PHYS_EMS + {4'd0, map_ems[2], address[13:0]};
        else if (ems_b4)
            phys = PHYS_EMS + {4'd0, map_ems[3], address[13:0]};
        else if (seg_f) begin
            phys    = PHYS_ROM_BANK + {5'd0, MAIN_ROM[19:16], address[15:0]};
            protect = bios_protect_flag[1];
        end
        else if (seg_ec00) begin
            phys    = PHYS_ROM_BANK + {5'd0, ROM_EC00[19:14], address[13:0]};
            protect = bios_protect_flag[0];
        end
        else
            phys = PHYS_CPU_IMAGE + {5'd0, address};
    end

endmodule
