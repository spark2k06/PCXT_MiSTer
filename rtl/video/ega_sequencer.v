//============================================================================
//
//  PCXT MiSTer EGA sequencer
//
//============================================================================

`default_nettype wire

module ega_sequencer (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_pix,
    input  wire        ce_pix_early,
    input  wire [15:0] io_addr,
    input  wire [7:0]  io_data_in,
    output reg  [7:0]  io_data_out,
    input  wire        io_we,
    input  wire        io_re,
    output reg  [3:0]  plane_write_mask,
    output reg         chain2_write,
    output reg         extended_memory,
    output reg         ce_crt_fetch,
    output reg         ce_crt_fetch_early,
    output reg         ce_cpu_access,
    output reg         dot_clock_div2,
    output reg         char_9dot,
    output reg  [1:0]  char_map_a,
    output reg  [1:0]  char_map_b,
    output reg  [7:0]  map_mask_debug,
    output reg  [7:0]  memory_mode_debug
);

    localparam [15:0] SEQ_ADDR_PORT0 = 16'h03C4;
    localparam [15:0] SEQ_ADDR_PORT1 = 16'h02C4;
    localparam [15:0] SEQ_DATA_PORT0 = 16'h03C5;
    localparam [15:0] SEQ_DATA_PORT1 = 16'h02C5;

    reg [2:0] seq_index = 3'd0;
    reg [7:0] reset_reg = 8'h03;
    // Default to 8-dot text timing so the pre-BIOS splash has sane sync before
    // the EGA BIOS programs the sequencer.
    reg [7:0] clocking_mode_reg = 8'h01;
    reg [7:0] map_mask_reg = 8'h0F;
    reg [7:0] char_map_reg = 8'h00;
    // Start with planar CPU access enabled; odd/even can still be enabled later
    // by the guest through sequencer register 4.
    reg [7:0] memory_mode_reg = 8'h06;
    reg [3:0] fetch_phase = 4'd0;
    reg       fetch_pending = 1'b0;
    reg       fetch_req_armed = 1'b0;

    wire seq_addr_cs = (io_addr == SEQ_ADDR_PORT0) || (io_addr == SEQ_ADDR_PORT1);
    wire seq_data_cs = (io_addr == SEQ_DATA_PORT0) || (io_addr == SEQ_DATA_PORT1);
    wire [3:0] fetch_phase_last = clocking_mode_reg[3] ? 4'd15 : 4'd7;
    wire       fetch_wrap_now = ce_pix && (fetch_phase == fetch_phase_last);

    // The VRAM read must be issued one clock before the dot on which the
    // character is loaded, so that the fixed two-clock BRAM latency lands on
    // that dot whether the dot is one or two clocks away.  Armed on the wrap
    // and released on the next dot warning, exactly once per character.
    wire       fetch_req_issue = ce_pix_early && (fetch_req_armed || fetch_wrap_now);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            seq_index <= 3'd0;
            reset_reg <= 8'h03;
            clocking_mode_reg <= 8'h01;
            map_mask_reg <= 8'h0F;
            char_map_reg <= 8'h00;
            memory_mode_reg <= 8'h06;
            fetch_phase <= 4'd0;
            fetch_pending <= 1'b0;
            fetch_req_armed <= 1'b0;
        end else begin
            // The character tick is armed when the dot phase wraps and is
            // delivered on the next dot enable, never in between.  With the
            // 14.318 MHz clock the previous two-cycle delay landed on that
            // same dot; with the 16.257 MHz enable, whose dots are one or
            // two clocks apart, it landed between dots on some characters
            // and moved the CRTC outputs one dot from line to line.
            if (fetch_req_issue)
                fetch_req_armed <= 1'b0;
            else if (fetch_wrap_now)
                fetch_req_armed <= 1'b1;

            if (ce_pix) begin
                fetch_pending <= (fetch_phase == fetch_phase_last);

                if (fetch_phase == fetch_phase_last)
                    fetch_phase <= 4'd0;
                else
                    fetch_phase <= fetch_phase + 4'd1;
            end

            if (io_we && seq_addr_cs)
                seq_index <= io_data_in[2:0];
            else if (io_we && seq_data_cs) begin
                case (seq_index)
                    3'h0: reset_reg <= io_data_in;
                    3'h1: clocking_mode_reg <= io_data_in;
                    3'h2: map_mask_reg <= io_data_in;
                    3'h3: char_map_reg <= io_data_in;
                    3'h4: memory_mode_reg <= io_data_in;
                    default: begin
                    end
                endcase

                if (seq_index == 3'h1)
                    fetch_phase <= 4'd0;
            end
        end
    end

    always @(*) begin
        io_data_out = 8'h00;
        if (io_re && seq_data_cs) begin
            case (seq_index)
                3'h0: io_data_out = reset_reg;
                3'h1: io_data_out = clocking_mode_reg;
                3'h2: io_data_out = map_mask_reg;
                3'h3: io_data_out = char_map_reg;
                3'h4: io_data_out = memory_mode_reg;
                default: io_data_out = 8'h00;
            endcase
        end

        plane_write_mask = map_mask_reg[3:0];
        chain2_write = ~memory_mode_reg[2];
        extended_memory = memory_mode_reg[1];
        ce_crt_fetch = fetch_pending & ce_pix;
        ce_crt_fetch_early = fetch_req_issue;
        ce_cpu_access = ~(fetch_pending & ce_pix);
        dot_clock_div2 = clocking_mode_reg[3];
        char_9dot = ~clocking_mode_reg[0];
        char_map_a = char_map_reg[1:0];
        char_map_b = char_map_reg[3:2];
        map_mask_debug = map_mask_reg;
        memory_mode_debug = memory_mode_reg;
    end

endmodule
