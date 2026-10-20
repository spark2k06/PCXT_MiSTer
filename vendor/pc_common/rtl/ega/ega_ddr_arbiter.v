//============================================================================
//
//  Up to three clients on one DDRAM port: the raster that reads frames out,
//  the capture that writes them in, and optionally the AT machine RAM
//  (spk286_at_mister_ddram_owner), which issues one single-beat write or
//  one short read burst (a cache line) at a time.
//
//  The reader wins every tie. It is feeding a line buffer against a fixed
//  deadline - the dot it is due at cannot be postponed - while the writer has
//  a 512 word FIFO and most of a scanline to catch up in. Neither is anywhere
//  near the bandwidth of the port: together they want about 120 MB/s of the
//  several hundred it can do, so the loser of a tie waits for one burst, not
//  for a queue.
//
//  The AT RAM comes second: the CPU waits on every access, while the writer
//  only fills its FIFO. With the AT client idle (at_req tied low) the
//  arbiter behaves exactly as the two-client version.
//
//  A burst, once started, is never interrupted. The memory has been told how
//  many beats are coming and will not accept the interleaving.
//
//============================================================================

`default_nettype wire

module ega_ddr_arbiter (
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
    output reg         wr_grant,

    // AT RAM client: one write beat, or a read burst of at_burstcnt beats,
    // held until at_done. at_rvalid pulses with each read beat in at_rdata;
    // at_done pulses with the last beat, or once the write beat has been
    // accepted.
    input  wire        at_req,
    input  wire        at_write,
    input  wire [28:0] at_addr,
    input  wire [7:0]  at_be,
    input  wire [63:0] at_din,
    input  wire [7:0]  at_burstcnt,
    output reg         at_done,
    output reg         at_rvalid,
    output reg  [63:0] at_rdata
);

    localparam [2:0] ST_IDLE     = 3'd0;
    localparam [2:0] ST_READ     = 3'd1;
    localparam [2:0] ST_WRITE    = 3'd2;
    localparam [2:0] ST_AT_READ  = 3'd3;
    localparam [2:0] ST_AT_WRITE = 3'd4;

    reg [2:0] state = ST_IDLE;
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
    //
    // The reset belongs to the framebuffer clients only. The AT RAM client is
    // served while it is held: the video reset can stay asserted for as long
    // as MiSTer loads the BIOS, and the loader writes through this port.
    reg reset_pending = 1'b0;
    wire reset_hold = reset | reset_pending;
    wire at_start   = at_req && !at_done;
    wire reset_take = reset_hold && (state == ST_IDLE) && !at_start;

    // The write client sees the memory as busy whenever it is not the one
    // holding the port, so its own burst logic stalls instead of needing to
    // know an arbiter exists.
    assign wr_busy_out   = ddram_busy || (state != ST_WRITE);
    assign ddram_din     = (state == ST_AT_WRITE) ? at_din : wr_din;
    assign ddram_be      = (state == ST_AT_WRITE) ? at_be  : 8'hFF;
    assign rd_data       = ddram_dout;
    assign rd_data_valid = (state == ST_READ) && ddram_dout_ready;

    always @(posedge clk) begin
        rd_grant <= 1'b0;
        wr_grant  <= 1'b0;
        at_done   <= 1'b0;
        at_rvalid <= 1'b0;

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
                    if (rd_req && !reset_hold) begin
                        ddram_addr     <= rd_addr;
                        ddram_burstcnt <= rd_burstcnt;
                        beats_left     <= {1'b0, rd_burstcnt};
                        ddram_rd       <= 1'b1;
                        rd_grant       <= 1'b1;
                        state          <= ST_READ;
                    end else if (at_start) begin
                        ddram_addr     <= at_addr;
                        ddram_burstcnt <= at_write ? 8'd1 : at_burstcnt;
                        beats_left     <= at_write ? 9'd1 : {1'b0, at_burstcnt};
                        ddram_we       <= at_write;
                        ddram_rd       <= !at_write;
                        state          <= at_write ? ST_AT_WRITE : ST_AT_READ;
                    end else if (wr_req && !reset_hold) begin
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

                // A burst that stops returning beats is ended with at_done
                // and no further at_rvalid, rather than leaving the AT bus
                // waiting forever; the owner answers the missing data as all
                // ones and does not keep the line.
                ST_AT_READ: begin
                    if (!ddram_busy) ddram_rd <= 1'b0;
                    if (ddram_dout_ready) begin
                        wdog       <= 12'd0;
                        at_rdata   <= ddram_dout;
                        at_rvalid  <= 1'b1;
                        beats_left <= beats_left - 9'd1;
                        if (beats_left == 9'd1) begin
                            at_done <= 1'b1;
                            state   <= ST_IDLE;
                        end
                    end else begin
                        wdog <= wdog + 12'd1;
                        if (&wdog) begin
                            ddram_rd <= 1'b0;
                            at_done  <= 1'b1;
                            state    <= ST_IDLE;
                        end
                    end
                end

                ST_AT_WRITE: begin
                    if (!ddram_busy) begin
                        ddram_we <= 1'b0;
                        at_done  <= 1'b1;
                        state    <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
