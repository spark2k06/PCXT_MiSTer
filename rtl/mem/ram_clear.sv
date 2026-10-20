//
// Memory clearing through the LDR port (the clear of video
// memory is done by ram_clear on the region it belongs to).
//
// SDRAM comes up with undefined contents, where the BRAM it replaces came up
// zeroed, so the video regions are written with zeros once the chip has been
// initialised. It writes four-word bursts (8 bytes) over each region and has
// no effect on the rest of the system: a warm reset does not clear video
// memory, as it does not today.
//
//   BASES  word address of each region (a multiple of 4)
//   WORDS  length of each region in words (a multiple of 4)
//
// `clear` restarts the sequence at any time (for a later cold-boot clear).
//
module ram_clear #(
    parameter int                  NREG  = 2,
    parameter logic [24*NREG-1:0]  BASES = '0,
    parameter logic [24*NREG-1:0]  WORDS = '0
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        init_done,
    input  logic        clear,          // start again (pulse or level)

    output logic        busy,
    output logic        req,            // LDR-style write request, held until ack
    output logic [23:0] addr,
    output logic [1:0]  len,
    output logic [63:0] wdata,
    output logic [7:0]  wbe,
    input  logic        ack
);
    import sdram_pkg::*;

    localparam int RW = (NREG > 1) ? $clog2(NREG) : 1;

    logic          init_q;
    logic [RW-1:0] reg_i;
    logic [23:0]   pos;         // words written so far in the region
    logic          run;

    wire [23:0] r_base = BASES[24*reg_i +: 24];
    wire [23:0] r_len  = WORDS[24*reg_i +: 24];

    assign busy  = run;
    assign req   = run & (pos < r_len);
    assign addr  = r_base + pos;
    assign len   = LEN_4;
    assign wdata = 64'd0;
    assign wbe   = 8'hFF;

    always_ff @(posedge clk) begin
        if (reset) begin
            init_q <= 1'b0;
            run    <= 1'b0;
            reg_i  <= '0;
            pos    <= 24'd0;
        end
        else begin
            init_q <= init_done;
            if ((init_done && !init_q) || clear) begin
                run   <= 1'b1;
                reg_i <= '0;
                pos   <= 24'd0;
            end
            else if (run) begin
                if (req && ack)
                    pos <= pos + 24'd4;
                else if (pos >= r_len) begin
                    // region finished: next one, or done
                    if (reg_i == RW'(NREG - 1))
                        run <= 1'b0;
                    else begin
                        reg_i <= reg_i + 1'b1;
                        pos   <= 24'd0;
                    end
                end
            end
        end
    end

endmodule
