//
// CPU memory map of the PCXT with the EGA/VGA card (spec sec. 5.5, table
// "PCXT · EGA + VGA 13h+"), combinational. Same outputs as mem_map:
//
//   select   the address is memory this port serves (the old RAM.sv
//            ram_address_select_n); video RAM that has its own frontend is not
//   phys     the physical byte address in SDRAM
//   protect  writes are ignored (BIOS Writable)
//
//   00000-9FFFF  CPU image
//   A0000-AFFFF  the packed 13h framebuffer (SDRAM 0x084_0000) while VGA 13h is
//                packed and the CPU is served here; otherwise the EGA aperture,
//                which is the frontend's, not this port's
//   B0000-BFFFF  EGA aperture (frontend)
//   C0000-C3FFF  EGA BIOS slot of the ROM bank (+0x34000)
//   C4000-CFFFF  CPU image when the C400 UMB is enabled, nothing otherwise
//   D0000-DFFFF  Lo-tech EMS frame, only where a bank is mapped (EMS is fixed
//                at D000 with EGA, C000 being the BIOS)
//   E0000-EBFFF  CPU image
//   EC000-EFFFF  EC00 ROM slot, unless the EMS frame covers it; with no EC00
//                ROM loaded it is open bus (as in mem_map)
//   F0000-FFFFF  PCXT BIOS slot
//
module mem_map_ega (
    input  logic [19:0] address,
    input  logic [6:0]  map_ems [0:3],
    input  logic        ems_b1,
    input  logic        ems_b2,
    input  logic        ems_b3,
    input  logic        ems_b4,
    input  logic        umb_enabled,         // C4000-CFFFF
    input  logic        vga13_packed,        // A0000-AFFFF is the packed framebuffer
    input  logic [2:0]  bios_protect_flag,   // [2] C000 (EGA), [1] F000 (main), [0] EC00
    input  logic        ec00_loaded,
    output logic        select,
    output logic [24:0] phys,
    output logic        protect
);
    import sdram_pkg::*;

    localparam logic [24:0] PHYS_VGA13 = 25'h084_0000;

    wire seg_a    = (address[19:16] == 4'hA);
    wire seg_c    = (address[19:16] == 4'hC);
    wire seg_f    = (address[19:16] == 4'hF);
    wire seg_ec00 = (address[19:14] == 6'b111011);
    wire c_rom    = (address[19:14] == 6'b110000);          // C0000-C3FFF
    wire c_umb    = seg_c & ~c_rom;                          // C4000-CFFFF
    wire d_frame  = (address[19:16] == 4'hD);

    wire ems_hit = ems_b1 | ems_b2 | ems_b3 | ems_b4;

    wire video_hole = (address[19:17] == 3'b101) & ~(seg_a & vga13_packed);   // A0000-BFFFF

    assign select = ~video_hole
                  & (~c_umb | umb_enabled)
                  & (~d_frame | ems_hit)
                  & ~(seg_ec00 & ~ems_hit & ~ec00_loaded);

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
            phys    = PHYS_ROM_BANK + {5'd0, ROM_PCXT_BIOS[19:16], address[15:0]};
            protect = bios_protect_flag[1];
        end
        else if (seg_ec00) begin
            phys    = PHYS_ROM_BANK + {5'd0, ROM_EC00[19:14], address[13:0]};
            protect = bios_protect_flag[0];
        end
        else if (c_rom) begin
            phys    = PHYS_ROM_BANK + {5'd0, ROM_EGA_BIOS[19:14], address[13:0]};
            protect = bios_protect_flag[2];
        end
        else if (seg_a & vga13_packed)
            phys = PHYS_VGA13 + {9'd0, address[15:0]};
        else
            phys = PHYS_CPU_IMAGE + {5'd0, address};
    end

endmodule
