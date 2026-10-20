//
// Test-only stand-in for cpu_mem_port: the same ports, but the memory is an
// array that answers at once, with no wait states and no SDRAM behind it. It
// is what the CPU sees from a BRAM. sys_video_tb builds with this module in
// place of the real one (+define-free: the file list is swapped) to tell what
// the SDRAM path costs the CPU: whatever differs from this is the path's doing.
//
// The ROM image is taken from the same hex file the bench puts in the chip.
//
module cpu_mem_port (
    input  logic        clock,
    input  logic        reset,
    input  logic [7:0]  internal_data_bus,
    output logic [7:0]  data_bus_out,
    input  logic        word_read_request,
    input  logic        word_write_request,
    input  logic [15:0] data_bus_in_word,
    output logic [15:0] data_bus_out_word,
    input  logic        memory_read_n,
    input  logic        memory_write_n,
    output logic        memory_access_ready,
    input  logic        map_select,
    input  logic [24:0] map_phys,
    input  logic        map_protect,
    input  logic [1:0]  map_vclass,
    input  logic [24:0] map_phys2,
    input  logic        map_phys2_valid,
    input  logic        cpu_ce_posedge,
    input  logic        wait_count_clk_en,
    input  logic [1:0]  ram_read_wait_cycle,
    input  logic [1:0]  ram_write_wait_cycle,
    input  logic [1:0]  clk_select,
    input  logic        flush,
    input  logic        early_read,
    output logic        m_start,
    output logic        m_we,
    output logic [23:0] m_addr,
    output logic [1:0]  m_len,
    output logic [63:0] m_wdata,
    output logic [7:0]  m_wbe,
    input  logic        m_busy,
    input  logic        m_done,
    input  logic [63:0] m_rdata,
    output logic        snoop_valid,
    output logic [23:0] snoop_addr,
    output logic [15:0] snoop_data,
    output logic [1:0]  snoop_be
);
    logic [7:0] mem [int unsigned];
    logic [15:0] rom_img [0:32767];
    string hexfile = "sys_video_prog.hex";

    initial begin
        void'($value$plusargs("hex=%s", hexfile));
        for (int i = 0; i < 32768; i++) rom_img[i] = 16'bx;
        $readmemh(hexfile, rom_img);
        for (int i = 0; i < 32768; i++)
            if (rom_img[i] !== 16'bx) begin
                mem[25'h010_0000 + 2*i]     = rom_img[i][7:0];
                mem[25'h010_0000 + 2*i + 1] = rom_img[i][15:8];
            end
    end

    wire read_command  = map_select & ~memory_read_n;
    wire write_command = map_select & ~memory_write_n & ~map_protect;
    wire [24:0] a = map_phys;

    function automatic logic [7:0] rd(input logic [24:0] p);
        rd = mem.exists(p) ? mem[p] : 8'h00;
    endfunction

    always_ff @(posedge clock)
        if (write_command) begin
            mem[a] <= internal_data_bus;
            if (word_write_request) mem[a + 25'd1] <= data_bus_in_word[15:8];
        end

    assign data_bus_out      = read_command ? rd(a) : 8'h00;
    assign data_bus_out_word = {rd(a + 25'd1), rd(a)};
    assign memory_access_ready = 1'b1;

    assign m_start = 1'b0;  assign m_we = 1'b0;  assign m_addr = '0;  assign m_len = '0;
    assign m_wdata = '0;    assign m_wbe = '0;
    assign snoop_valid = 1'b0;  assign snoop_addr = '0;  assign snoop_data = '0;  assign snoop_be = '0;
endmodule
