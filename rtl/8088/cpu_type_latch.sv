//============================================================================
//
//  Reset-applied 8088/8086 selection
//
//============================================================================

`default_nettype wire

module cpu_type_latch (
    input  wire clock,
    input  wire reset_active,
    input  wire selected_8086,
    output logic is8086 = 1'b0
);

    // Keep the latch open for the complete stretched machine reset. This lets
    // MiSTer's persisted OSD status settle at startup, while guaranteeing that
    // queue depth and bus width remain immutable once the CPU begins running.
    //
    // Only the CPU type needs this. pfq_depth is combinational in IS8086, so
    // switching while the queue holds more bytes than the narrower depth
    // allows would leave pfq_used above pfq_depth and desync the pointers.
    // Fake 286 FLAGS has no such constraint - it only gates a PUSHF mux - so
    // it is applied live and is not latched here.
    always_ff @(posedge clock) begin
        if (reset_active)
            is8086 <= selected_8086;
    end

endmodule
