//
// mpu401.sv - Roland MPU-401 UART-mode MIDI interface
//
// Exposes the two classic MPU-401 I/O ports (data + status/command) on the
// ISA bus and drives a uart_16750 core underneath, hardwired to a fixed
// ~31250 baud (MIDI) 8N1 format. The CPU/driver never programs a baud rate
// on real MPU-401 UART-mode hardware, so this module performs the
// LCR/DLL/DLM register setup itself once, at reset, before the ISA-facing
// ports become live.
//
// Command/ack handling (reset -> 0xFF, enter-UART-mode -> 0x3F, both ACKed
// with 0xFE on the data port) follows the same behavior used by the ao486
// MiSTer core's "mpu" module (rtl/soc/uart/uart.v), which is what lets
// stock DOS MPU-401 drivers auto-detect the device and switch out of
// "intelligent mode" into plain UART passthrough.
//

module mpu401
(
    input            clk,
    input            reset,

    input            baudce,      // fixed MIDI baud-rate clock enable (~14.31818MHz single-cycle CE)

    input            address,     // 0 = data port (0x330), 1 = status/command port (0x331)
    input            write,
    input      [7:0] writedata,
    input            read,
    output reg [7:0] readdata,
    input            cs,

    output           midi_tx,
    input            midi_rx,

    output           irq
);

//
// One-shot reset-time UART init: LCR=0x83 (DLAB=1,8N1), DLL=25, DLM=0,
// LCR=0x03 (DLAB=0,8N1). baudce is fed a 12.5MHz enable (50MHz clk_chipset
// divided by 4), so 12500000/(16*25) = 31250 baud EXACTLY - no error at all.
// Getting this exact matters: ao486's UART core has a dedicated MPU mode with
// a hardwired divisor fed by an exact-rate clock, and MIDI receivers have no
// reason to tolerate error we can simply avoid.
//
localparam [7:0] MPU_DIVISOR_LO = 8'd25;
localparam [7:0] MPU_DIVISOR_HI = 8'd0;

wire [7:0] core_dout;
wire       lsr_dr, lsr_thre;
wire       baudoutn;

reg [2:0] init_step = 3'd0;
reg [3:0] init_wait = 4'd0;
reg       initializing = 1'b1;
reg       init_write = 1'b0;
reg [2:0] init_addr = 3'd0;
reg [7:0] init_data = 8'd0;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        init_step     <= 3'd0;
        init_wait     <= 4'd0;
        initializing  <= 1'b1;
        init_write    <= 1'b0;
    end
    else if (initializing) begin
        init_write <= 1'b0;

        if (init_wait != 4'd0) begin
            init_wait <= init_wait - 4'd1;
        end
        else begin
            case (init_step)
                3'd0: begin init_addr <= 3'd3; init_data <= 8'h83;          init_write <= 1'b1; init_wait <= 4'd4; init_step <= 3'd1; end
                3'd1: begin init_addr <= 3'd0; init_data <= MPU_DIVISOR_LO; init_write <= 1'b1; init_wait <= 4'd4; init_step <= 3'd2; end
                3'd2: begin init_addr <= 3'd1; init_data <= MPU_DIVISOR_HI; init_write <= 1'b1; init_wait <= 4'd4; init_step <= 3'd3; end
                3'd3: begin init_addr <= 3'd3; init_data <= 8'h03;          init_write <= 1'b1; init_wait <= 4'd4; init_step <= 3'd4; end
                default: initializing <= 1'b0;
            endcase
        end
    end
end

//
// MPU-401 command/status state (mirrors ao486's "mpu" module)
//
reg read_ack;
reg mpu_dumb;

wire rx_ready = ~initializing & lsr_dr;
wire tx_ready = ~initializing & lsr_thre;

assign irq = read_ack | rx_ready;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        read_ack <= 1'b0;
        mpu_dumb <= 1'b0;
    end
    else if (cs) begin
        if (address) begin
            if (write) begin
                read_ack <= ~mpu_dumb;
                if (writedata == 8'hFF) mpu_dumb <= 1'b0;
                if (writedata == 8'h3F) mpu_dumb <= 1'b1;
            end
        end
        else if (read) begin
            read_ack <= 1'b0;
        end
    end
end

always @(posedge clk) begin
    if (cs & read) begin
        if (address)
            readdata <= {~(read_ack | rx_ready), ~tx_ready, 6'd0};
        else
            readdata <= read_ack ? 8'hFE : core_dout;
    end
end

//
// ISA-side <-> core bus mux: the init FSM owns the core bus at reset,
// the data port (address==0) owns it afterwards. The status/command port
// (address==1) never touches the underlying UART core.
//
wire       core_cs  = initializing ? init_write : (cs & ~address & ((read & ~read_ack) | write));
wire       core_wr  = initializing ? init_write : write;
wire       core_rd  = initializing ? 1'b0       : (read & ~read_ack);
wire [2:0] core_addr = initializing ? init_addr  : 3'd0;
wire [7:0] core_din  = initializing ? init_data  : writedata;

uart_16750 uart_16750
(
    .CLK        (clk),
    .RST        (reset),
    .BAUDCE     (baudce),
    .CS         (core_cs),
    .WR         (core_wr),
    .RD         (core_rd),
    .A          (core_addr),
    .DIN        (core_din),
    .DOUT       (core_dout),
    .DDIS       (),
    .INT        (),
    .OUT1N      (),
    .OUT2N      (),
    .RCLK       (baudoutn),
    .BAUDOUTN   (baudoutn),
    .RTSN       (),
    .DTRN       (),
    .CTSN       (1'b0),
    .DSRN       (1'b0),
    .DCDN       (1'b0),
    .RIN        (1'b1),
    .SIN        (midi_rx),
    .SOUT       (midi_tx),
    .LSR_DR     (lsr_dr),
    .LSR_THRE   (lsr_thre)
);

endmodule
