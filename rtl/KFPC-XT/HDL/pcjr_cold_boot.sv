// PCjr cold boot: after a reset of the machine the BIOS must not take the
// warm-start marker (0040:0072) the RAM still holds - the SDRAM keeps it - or
// it would skip the memory test. Until the BIOS writes the flag, reads of
// 00472h-00473h come back as zero.
module pcjr_cold_boot (
    input  logic        clock,
    input  logic        reset,
    input  logic        pcjr,
    input  logic [19:0] address,
    input  logic        select,           // the address is RAM (map_select)
    input  logic        memory_write_n,
    output logic        override          // the read of the flag must return zero
);
    wire flag_address = (address == 20'h00472) | (address == 20'h00473);

    logic pending;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            pending <= 1'b1;
        else if (flag_address && select && !memory_write_n)
            pending <= 1'b0;
    end

    assign override = pcjr & pending & flag_address;
endmodule
