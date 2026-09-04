// Tracks whether a ROM image has been uploaded over ioctl since power-on.
//
// The flag is cleared once when a new file begins and set only when its final
// byte has completed in the SDRAM loader. An incomplete or absent BIOS can
// therefore never release the machine into an unknown F000 segment.
module rom_presence_latch (
    input  logic clock,
    input  logic reset,
    input  logic sdram_initialized,
    input  logic download_active,
    input  logic write_complete,
    output logic loaded
);

    logic download_active_q;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            download_active_q <= 1'b0;
            loaded <= 1'b0;
        end else if (!sdram_initialized) begin
            download_active_q <= 1'b0;
            loaded <= 1'b0;
        end else begin
            download_active_q <= download_active;

            if (download_active && !download_active_q)
                loaded <= 1'b0;
            else if (download_active && write_complete)
                loaded <= 1'b1;
        end
    end

endmodule
