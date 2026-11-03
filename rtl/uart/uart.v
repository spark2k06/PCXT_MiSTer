module uart
#(
	parameter RX_MIDSTOP = 0    // 1: receiver returns to idle at the centre of the stop bit
)
(
	input            clk,
	input            reset,

	input      [2:0] address,
	input            write,
	input      [7:0] writedata,
	input            read,
	output reg [7:0] readdata,
	input            cs,

	input            br_clk,
	input            rx,
	output           tx,
	input            cts_n,
	input            dcd_n,
	input            dsr_n,
	input            ri_n,
	output           rts_n,
	output           br_out,
	output           dtr_n,

	output           irq
);

wire [7:0] data;

always @(posedge clk) if(read & cs) readdata <= data;

uart_16750 #(.RX_MIDSTOP(RX_MIDSTOP)) uart_16750
(
	.CLK(clk),
	.RST(reset),
	.BAUDCE(br_clk),
	.CS(cs & (read | write)),
	.WR(write),
	.RD(read),
	.A(address),
	.DIN(writedata),
	.DOUT(data),
	.RCLK(br_out),
	
	.BAUDOUTN(br_out),

	.RTSN(rts_n),
	.DTRN(dtr_n),
	.CTSN(cts_n),
	.DSRN(dsr_n),
	.DCDN(dcd_n),
	
	.RIN(ri_n),	
	.SIN(rx),
	.SOUT(tx),

	.INT(irq)

);

endmodule
