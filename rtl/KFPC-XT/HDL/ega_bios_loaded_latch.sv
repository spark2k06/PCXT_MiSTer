module ega_bios_loaded_latch (
    input  logic clock,
    input  logic reset,
    input  logic sdram_initialized,
    input  logic download_active,
    input  logic write_complete,
    output logic loaded,
    output wire  write_protect,
    output wire [1:0] video_switches
);

    // A present option ROM is both read-only and advertised to the XT BIOS as
    // an adapter with its own firmware.  Without one, retain the CGA fallback.
    assign write_protect  = loaded;
    assign video_switches = loaded ? 2'b00 : 2'b10;

    rom_presence_latch presence (
        .clock             (clock),
        .reset             (reset),
        .sdram_initialized (sdram_initialized),
        .download_active   (download_active),
        .write_complete    (write_complete),
        .loaded            (loaded)
    );

endmodule
