//============================================================================
//
//  Two clients on one DDRAM port: the raster that reads frames out, and the
//  capture that writes them in.
//
//  The reader wins every tie. It is feeding a line buffer against a fixed
//  deadline - the dot it is due at cannot be postponed - while the writer has
//  a 512 word FIFO and most of a scanline to catch up in. Neither is anywhere
//  near the bandwidth of the port: together they want about 120 MB/s of the
//  several hundred it can do, so the loser of a tie waits for one burst, not
//  for a queue.
//
//  A burst, once started, is never interrupted. The memory has been told how
//  many beats are coming and will not accept the interleaving.
//
//============================================================================

`default_nettype wire

module hgc_ddr_arbiter (
    input  wire        clk,
    input  wire        reset,

    // DDRAM
    input  wire        ddram_busy,
    output reg  [7:0]  ddram_burstcnt,
    output reg  [28:0] ddram_addr,
    output wire [63:0] ddram_din,
    output wire [7:0]  ddram_be,
    output reg         ddram_we,
    output reg         ddram_rd,
    input  wire [63:0] ddram_dout,
    input  wire        ddram_dout_ready,

    // Read client, higher priority.
    input  wire        rd_req,
    input  wire [28:0] rd_addr,
    input  wire [7:0]  rd_burstcnt,
    output reg         rd_grant,
    output wire [63:0] rd_data,
    output wire        rd_data_valid,

    // Write client. Presents a beat at wr_din and advances it whenever
    // wr_advance is high, exactly as the memory itself would ask.
    input  wire        wr_req,
    input  wire [28:0] wr_addr,
    input  wire [7:0]  wr_burstcnt,
    input  wire [63:0] wr_din,
    output wire        wr_busy_out,
    output reg         wr_grant
);

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_READ  = 2'd1;
    localparam [1:0] ST_WRITE = 2'd2;

    reg [1:0] state = ST_IDLE;
    reg [8:0] beats_left = 9'd0;

    // A read that never finishes is not a slow read, it is a stopped design:
    // the port stays held, the writer is never granted again, its FIFO fills
    // and the capture stops publishing for good. 4096 clocks is 71 us, far
    // longer than any real stall and far shorter than a frame.
    //
    // Only reads are abandoned. Breaking a write burst midstream is what
    // f2sdram_safe_terminator exists to prevent, because it leaves the f2h
    // interface in a state only an HPS reset clears.
    reg [11:0] wdog = 12'd0;

    // Reset must never take a burst down with it. The memory has been told how
    // many beats are coming and is counting them; stopping short leaves the
    // f2sdram interface in a state that only an HPS cold reset clears, which
    // is the whole reason f2sdram_safe_terminator exists. That module covers
    // the framework's own reset - it cannot cover ours.
    //
    // And ours is not rare: video_retime_reset carries the OSD reset button,
    // the splash and every PLL relock, none of which know where a burst is.
    // So a reset arriving mid-burst is remembered and taken at the end of it,
    // a few clocks later. The watchdog above is what guarantees there is an
    // end to wait for.
    reg reset_pending = 1'b0;
    wire reset_take = (reset | reset_pending) && (state == ST_IDLE);

    // The write client sees the memory as busy whenever it is not the one
    // holding the port, so its own burst logic stalls instead of needing to
    // know an arbiter exists.
    assign wr_busy_out   = ddram_busy || (state != ST_WRITE);
    assign ddram_din     = wr_din;
    assign ddram_be      = 8'hFF;
    assign rd_data       = ddram_dout;
    assign rd_data_valid = (state == ST_READ) && ddram_dout_ready;

    always @(posedge clk) begin
        rd_grant <= 1'b0;
        wr_grant <= 1'b0;

        if (reset && (state != ST_IDLE))
            reset_pending <= 1'b1;

        if (reset_take) begin
            state          <= ST_IDLE;
            ddram_we       <= 1'b0;
            ddram_rd       <= 1'b0;
            ddram_burstcnt <= 8'd0;
            ddram_addr     <= 29'd0;
            beats_left     <= 9'd0;
            wdog           <= 12'd0;
            reset_pending  <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    ddram_we <= 1'b0;
                    ddram_rd <= 1'b0;
                    wdog     <= 12'd0;
                    if (rd_req) begin
                        ddram_addr     <= rd_addr;
                        ddram_burstcnt <= rd_burstcnt;
                        beats_left     <= {1'b0, rd_burstcnt};
                        ddram_rd       <= 1'b1;
                        rd_grant       <= 1'b1;
                        state          <= ST_READ;
                    end else if (wr_req) begin
                        ddram_addr     <= wr_addr;
                        ddram_burstcnt <= wr_burstcnt;
                        beats_left     <= {1'b0, wr_burstcnt};
                        ddram_we       <= 1'b1;
                        wr_grant       <= 1'b1;
                        state          <= ST_WRITE;
                    end
                end

                // Read address and burst count are held only until the memory
                // takes them; the beats come back later, on their own.
                ST_READ: begin
                    if (!ddram_busy) ddram_rd <= 1'b0;
                    if (ddram_dout_ready) begin
                        wdog       <= 12'd0;
                        beats_left <= beats_left - 9'd1;
                        if (beats_left == 9'd1) state <= ST_IDLE;
                    end else begin
                        wdog <= wdog + 12'd1;
                        if (&wdog) begin
                            ddram_rd <= 1'b0;
                            state    <= ST_IDLE;
                        end
                    end
                end

                ST_WRITE: begin
                    if (!ddram_busy) begin
                        beats_left <= beats_left - 9'd1;
                        if (beats_left == 9'd1) begin
                            ddram_we <= 1'b0;
                            state    <= ST_IDLE;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule


