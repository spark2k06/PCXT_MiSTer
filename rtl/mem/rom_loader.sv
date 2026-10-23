//
// ROM loader: HPS ioctl downloads into the SDRAM ROM bank.
//
// It writes through the LDR port of the arbiter, one 16-bit word per ioctl
// word, instead of borrowing the chipset bus. The machine is still held the
// way the old loader in PCXT.sv held it, so the behaviour seen from DOS does
// not change:
//
//   - HOLD is requested for the whole download and the first word is only
//     taken once it has been granted (the CPU is off the bus).
//   - Replacing the PCXT BIOS while running still restarts the machine:
//     rom_presence_latch drops "loaded" when the download starts, which
//     raises bios_hold and the reset, and sets it again from write_main.
//
// Slots (ioctl index): 0 PCXT BIOS (first 64 KiB of the file; ROM_PCXT), 1 Tandy
// BIOS (ROM_TANDY), 2 EC00 (16 KiB window, wraps as before), 3 EGA BIOS (ROM_EGA
// builds, 16 KiB window). A build that is only a Tandy 1000 sets
// ROM_PCXT to 0 and the PCXT slot is not offered; a build that chooses the
// machine at run time has both, each in its own place in the ROM bank, and
// write_main / write_tandy tell which of the two has been written.
//
module rom_loader #(
    parameter bit ROM_PCXT  = 1'b1,
    parameter bit ROM_TANDY = 1'b0,
    parameter bit ROM_EGA   = 1'b0
) (
    input  logic        clock,
    input  logic        reset,
    input  logic        sdram_ready,

    input  logic        ioctl_download,
    input  logic [7:0]  ioctl_index,
    input  logic        ioctl_wr,
    input  logic [24:0] ioctl_addr,
    input  logic [15:0] ioctl_data,
    output logic        ioctl_wait,

    output logic        hold_request,   // to the bus arbiter (ext_access_request)
    input  logic        hold_granted,   // CPU off the bus

    // LDR transaction (to sdram_xbridge)
    output logic        l_start,
    output logic [23:0] l_addr,         // word address
    output logic [15:0] l_wdata,
    input  logic        l_busy,
    input  logic        l_done,

    output logic        write_any,      // a word is being written (lookahead flush)
    output logic        write_main,     // a word of slot 0 (PCXT BIOS) has been written
    output logic        write_tandy,    // a word of slot 1 (Tandy BIOS) has been written
    output logic        write_ega,      // a word of slot 3 has been written
    output logic        ec00_loaded     // a word of the EC00 slot has been written since reset
);
    import sdram_pkg::*;

    wire sel_pcxt  = ROM_PCXT && (ioctl_index[5:0] == 6'd0) && (ioctl_addr[24:16] == 9'd0);
    wire sel_tandy = ROM_TANDY && (ioctl_index[5:0] == 6'd1) && (ioctl_addr[24:16] == 9'd0);
    wire sel_ec00  = (ioctl_index == 8'd2);
    wire sel_ega   = ROM_EGA && (ioctl_index[5:0] == 6'd3) && (ioctl_addr[24:16] == 9'd0);
    wire selected  = sel_pcxt | sel_tandy | sel_ec00 | sel_ega;

    wire [24:0] dest = PHYS_ROM_BANK
                     + (sel_ec00  ? {5'd0, ROM_EC00[19:14], ioctl_addr[13:0]} :
                        sel_ega   ? {5'd0, ROM_EGA_BIOS[19:14], ioctl_addr[13:0]} :
                        sel_tandy ? {5'd0, ROM_TANDY_BIOS[19:16], ioctl_addr[15:0]} :
                                    {5'd0, ROM_PCXT_BIOS[19:16], ioctl_addr[15:0]});

    typedef enum logic [1:0] {L_IDLE, L_ARMED, L_WRITE} lstate_t;
    lstate_t state;
    logic    main_slot;
    logic    tandy_slot;
    logic    ec00_slot;
    logic    ega_slot;

    // l_busy rises on the edge that takes l_start and falls with l_done.
    assign l_start   = (state == L_WRITE) & ~l_busy & ~l_done;
    assign write_any = (state == L_WRITE);

    always_ff @(posedge clock) begin
        if (reset || !sdram_ready) begin
            state        <= L_IDLE;
            ioctl_wait   <= 1'b1;
            hold_request <= 1'b0;
            l_addr       <= 24'd0;
            l_wdata      <= 16'h0000;
            main_slot    <= 1'b0;
            tandy_slot   <= 1'b0;
            ec00_slot    <= 1'b0;
            ega_slot     <= 1'b0;
            ec00_loaded  <= 1'b0;
            write_main   <= 1'b0;
            write_tandy  <= 1'b0;
            write_ega    <= 1'b0;
        end
        else begin
            write_main  <= 1'b0;
            write_tandy <= 1'b0;
            write_ega   <= 1'b0;
            case (state)
                L_IDLE: begin
                    hold_request <= ioctl_download;
                    ioctl_wait   <= ioctl_download;
                    if (ioctl_download && hold_granted)
                        state <= L_ARMED;
                end
                L_ARMED: begin
                    hold_request <= 1'b1;
                    if (!ioctl_download) begin
                        hold_request <= 1'b0;
                        ioctl_wait   <= 1'b0;
                        state        <= L_IDLE;
                    end
                    else if (ioctl_wr && selected) begin
                        l_addr     <= dest[24:1];
                        l_wdata    <= ioctl_data;
                        main_slot  <= sel_pcxt;
                        tandy_slot <= sel_tandy;
                        ec00_slot  <= sel_ec00;
                        ega_slot   <= sel_ega;
                        ioctl_wait <= 1'b1;
                        state      <= L_WRITE;
                    end
                    else
                        ioctl_wait <= 1'b0;
                end
                L_WRITE:
                    if (l_done) begin
                        write_main  <= main_slot;
                        write_tandy <= tandy_slot;
                        write_ega   <= ega_slot;
                        if (ec00_slot)
                            ec00_loaded <= 1'b1;
                        ioctl_wait <= 1'b0;
                        state      <= L_ARMED;
                    end
                default:
                    state <= L_IDLE;
            endcase
        end
    end

endmodule
