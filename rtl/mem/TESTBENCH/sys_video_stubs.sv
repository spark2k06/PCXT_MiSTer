// Stubs for sys_video_tb: modules the memory and video work does not touch and
// that Verilator cannot read (SAA1099 uses an unpacked-array initialiser) or
// that are VHDL (the 16750 UART) or vendor primitives (dual-port RAM).
module saa1099(input clk_sys, input ce, input rst_n, input cs_n, input a0, input wr_n, input [7:0] din,
               output [7:0] out_l, output [7:0] out_r);
    assign out_l = 8'd0;
    assign out_r = 8'd0;
endmodule

module uart_16750 #(parameter RX_MIDSTOP = 0)(input CLK, input RST, input BAUDCE, input CS, input WR, input RD, input [2:0] A, input [7:0] DIN,
                  output [7:0] DOUT, output DDIS, output INT, output OUT1N, output OUT2N, input RCLK, output BAUDOUTN,
                  output RTSN, output DTRN, input CTSN, input DSRN, input DCDN, input RIN, input SIN, output SOUT,
                  output LSR_DR, output TXRDY, output RXRDY, output LSR_THRE, output LSR_TEMT, output LSR_OE,
                  output LSR_PE, output LSR_FE, output LSR_BI, output [7:0] RBR, output [7:0] LCR, input PCJR_TEST);
    assign DOUT = 8'd0;
endmodule

module dpram #(parameter AW = 12, parameter DW = 16)(input clock, input [AW-1:0] address_a, input [DW-1:0] data_a,
               input wren_a, output [DW-1:0] q_a, input [AW-1:0] address_b, input [DW-1:0] data_b, input wren_b,
               output [DW-1:0] q_b);
    assign q_a = '0;
    assign q_b = '0;
endmodule
