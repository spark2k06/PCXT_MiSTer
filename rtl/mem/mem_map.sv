//
// CPU memory map, combinational.
//
// F1 implements the PCXT table with CGA + HGC/MDA only; the EGA, Tandy and
// PCjr rows come with their phases. F5 adds the Tandy 1000 window. For a
// 20-bit bus address it gives:
//
//   select   the address is memory this port serves (not a disabled UMB
//            window, not a video window without its card) - the old RAM.sv
//            ram_address_select_n
//   phys     the physical byte address in SDRAM (sdram_pkg map)
//   protect  writes are ignored (BIOS Writable)
//   vclass   VC_NONE, or the video memory the address belongs to (F2)
//   phys2    a second target for a write (valid when phys2_valid)
//
//   00000-AFFFF  CPU image (A0000-AFFFF only with the A000 UMB)
//   B0000-B7FFF  HGC page 0 (page bit 0)
//   B8000-BFFFF  CGA, 16 KiB mirrored; with the HGC graphics page selected
//                (page bit 1) it is also HGC page 1: a write goes to both, a
//                read returns the CGA, as the BRAMs did.
//                Tandy 1000 (tandy_video): a window onto the 128 KiB block of
//                system RAM that port A0h chose (tandy_block), 16 or 32 KiB
//                page by port 3DFh: the video memory is
//                CPU image, there is no copy of it
//   C0000-EFFFF  CPU image, or the Lo-tech EMS frame when it is mapped
//   EC000-EFFFF  EC00 ROM slot (XTIDE), unless the EMS frame covers it. With
//                no EC00 ROM loaded the window is not memory (open bus: reads
//                come back as FF, writes are ignored), like a PC without the card
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
    input  logic        ec00_loaded,         // an EC00 ROM has been written to the slot
    input  logic        en_cga,              // the card exists (compile-time in the core)
    input  logic        en_hgc,
    input  logic        hgc_page,            // Hercules graphics page (control bit 7)
    input  logic        tandy_video,         // Tandy 1000 video: the CGA window is shared RAM
    input  logic [2:0]  tandy_block,         // A0h bits 3:1: the 128 KiB block of video memory
    input  logic [2:0]  tandy_cpu_page,      // 3DFh bits 5:3: CPU page; bit 0 set = 16 KiB pages
    output logic        select,
    output logic [24:0] phys,
    output logic        protect,
    output logic [1:0]  vclass,
    output logic [24:0] phys2,
    output logic        phys2_valid
);
    import sdram_pkg::*;

    localparam logic [19:0] MAIN_ROM = ROM_TANDY ? ROM_TANDY_BIOS : ROM_PCXT_BIOS;

    wire seg_f    = (address[19:16] == 4'hF);
    wire seg_ec00 = (address[19:14] == 6'b111011);

    wire ems_hit = ems_b1 | ems_b2 | ems_b3 | ems_b4;

    wire seg_b    = (address[19:16] == 4'hB);
    wire cga_hit  = en_cga && (address[19:15] == 5'b10111);
    wire hgc_hit  = en_hgc && !tandy_video && ((address[19:15] == 5'b10110 && !hgc_page)
                                            || (address[19:15] == 5'b10111 &&  hgc_page));
    wire video    = cga_hit | hgc_hit;

    assign select = ~(seg_b & ~video) & ~(~enable_a000h & (address[19:16] == 4'hA))
                  & ~(seg_ec00 & ~ems_hit & ~ec00_loaded);

    wire [24:0] hgc_phys = PHYS_HGC + {9'd0, hgc_page, address[14:0]};

    // Offset in the 128 KiB block: 16 KiB pages when 3DFh bit 3 is set, 32 KiB
    // pages otherwise
    wire [16:0] tandy_off  = tandy_cpu_page[0] ? {tandy_cpu_page, address[13:0]}
                                               : {tandy_cpu_page[2:1], address[14:0]};
    wire [24:0] tandy_phys = PHYS_CPU_IMAGE + {5'd0, tandy_block, tandy_off};

    always_comb begin
        protect     = 1'b0;
        vclass      = VC_NONE;
        phys2       = hgc_phys;
        phys2_valid = 1'b0;
        if (cga_hit && tandy_video) begin
            phys   = tandy_phys;
            vclass = VC_CGA;
        end
        else if (cga_hit) begin
            phys        = PHYS_CGA + {11'd0, address[13:0]};
            vclass      = VC_CGA;
            phys2_valid = hgc_hit;
        end
        else if (hgc_hit) begin
            phys   = hgc_phys;
            vclass = VC_HGC;
        end
        else if (ems_b1)
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
