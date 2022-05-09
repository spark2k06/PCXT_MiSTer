//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: timer8253.v
// Description: Part of the Next186 SoC PC project, timer
// 	8253 simplified timer (only counters 0 and 2, no read back command, no BCD mode)
// Version 1.0
// Creation date: May2012
//
// Author: Nicolae Dumitrache 
// e-mail: ndumitrache@opencores.org
//
/////////////////////////////////////////////////////////////////////////////////
// 
// Copyright (C) 2012 Nicolae Dumitrache
// 
// This source file may be used and distributed without 
// restriction provided that this copyright statement is not 
// removed from the file and that any derivative work contains 
// the original copyright notice and the associated disclaimer.
// 
// This source file is free software; you can redistribute it 
// and/or modify it under the terms of the GNU Lesser General 
// Public License as published by the Free Software Foundation;
// either version 2.1 of the License, or (at your option) any 
// later version. 
// 
// This source is distributed in the hope that it will be 
// useful, but WITHOUT ANY WARRANTY; without even the implied 
// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR 
// PURPOSE. See the GNU Lesser General Public License for more 
// details. 
// 
// You should have received a copy of the GNU Lesser General 
// Public License along with this source; if not, download it 
// from http://www.opencores.org/lgpl.shtml 
// 
///////////////////////////////////////////////////////////////////////////////////
// Additional Comments: 
// http://wiki.osdev.org/Programmable_Interval_Timer
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module timer_8253(
	input CS,
	input WR,
	input [1:0]addr,
	input [7:0]din,
	output wire [7:0]dout,
	input CLK_25,
	input clk,		// cpu CLK
	input gate2,
	output out0,
	output out2,

	output reg dbg_wr,
	output reg [1:0] dbg_addr,
	output reg [7:0] dbg_din
	);
	 
	reg [8:0]rclk = 0; // rclk[8] oscillates at 1193181.8181... Hz
	reg [1:0]cclk = 0;

	always @(posedge CLK_25) begin
		if(rclk[7:0] < 8'd208) rclk <= rclk + 8'd21;
		else rclk <= rclk + 8'd57;
	end
	
	always @ (posedge clk) begin
		cclk <= {cclk[0], rclk[8]};
	end

	always @(posedge clk)
		if (CS) begin
			dbg_wr <= WR;
			dbg_addr <= addr;
			if (WR) dbg_din <= din;
		end

	wire a0 = addr == 0;
	wire a2 = addr == 2;
	wire a3 = addr == 3;
	wire cmd0 = a3 && din[7:6] == 0;
	wire cmd2 = a3 && din[7:6] == 2;
	wire [7:0]dout0;
	wire [7:0]dout2;
	wire [7:0]mode0;
	wire [7:0]mode2;

	counter counter0 (
		.CS(CS && (a0 || cmd0)),
		.WR(WR),
		.clk(clk),
		.gate(1'b1),
		.cmd(cmd0),
		.din(din),
		.dout(dout0),
		.out(out0),
		.CE(cclk)
	);

	counter counter2 (
		.CS(CS && (a2 || cmd2)),
		.WR(WR),
		.clk(clk),
		.gate(gate2),
		.cmd(cmd2),
		.din(din),
		.dout(dout2),
		.out(out2),
		.CE(cclk)
	);

	assign dout = 	a0 ? dout0 : dout2;
	
endmodule


module counter(
	input CS,
    input WR,	// write cmd/data
	input clk,	// CPU clk
	input gate,
    input cmd,
	input [7:0]din,
	output [7:0]dout,
	output out,
	input [1:0]CE	// count enable
	);
	 
	reg [15:0]count = 0;
	reg [15:0]init = 0;
	reg [15:0]latched = 0;
	reg [1:0]state = 0; // state[1] = init reg filled
	reg strobe = 0;
	reg rd = 0;
	reg latch = 0;
	reg newcmd = 0;
	reg newdata = 0;
	reg [6:0] mode; // mode[6] = output
	wire c1 = count == 1;
	wire c2 = count == 2;
	reg CE1 = 0;
	reg waitgate = 0;
	reg gate_d;

	assign out = mode[6];
	assign dout = latch ?
		(rd ? latched[15:8] : latched[7:0]) : 
		(mode[5] & (~mode[4] | rd) ? count[15:8] : count[7:0]);

	wire gate_r = ~gate_d & gate;

	always @(posedge clk) begin

		if(CE == 2'b10) CE1 <= 1;

		if(CE1) begin
			newdata <= 0;
			gate_d <= gate;
			CE1 <= 0;
			case(mode[3:1])
				3'b000:
					if (newdata) begin
						count <= init;
						newcmd <= 0;
						mode[6] <= 0;
					end else if(newcmd) begin
						mode[6] <= 0;
					end else begin
						count <= count - 1'd1;
						if(c1) mode[6] <= 1;
					end
				3'b001:
					if(newcmd) begin
						if (newdata) begin
							count <= init;
							newdata <= 0;
							newcmd <= 0;
							waitgate <= 1;
						end
					end else if (waitgate) begin
						if (gate_r) begin
							mode[6] <= 0;
							waitgate <= 0;
						end
					end else if (gate_r) begin
						mode[6] <= 0;
						count <= init;
					end else begin
						count <= count - 1'd1;
						if(c1) mode[6] <= 1;
					end
				3'b010, 3'b110: begin
					mode[6] <= ~c2 | ~gate;
					if(c1 | newcmd | gate_r) begin
						if (!newcmd | newdata | gate_r) begin
							newcmd <= 0;
							count <= init;
						end
					end else if (gate) count <= count - 1'd1;
				end
				3'b011, 3'b111:
					if(c1 | c2 | newcmd | gate_r) begin
						mode[6] <= {~mode[6] | newcmd | ~gate};
						if (!newcmd | newdata | gate_r) begin
							newcmd <= 0;
							count <= {init[15:1], (~mode[6] | newcmd) & init[0]};
						end
					end else if (gate) count <= count - 2'd2; else mode[6] <= 1;
				3'b100:
					if (newdata) begin
						newcmd <= 0;
						count <= init;
						strobe <= 1;
					end else if(newcmd) begin
						mode[6] <= 1;
					end else begin
						count <= count - 1'd1;
						if(c1) begin
							if(strobe) mode[6] <= 0;
							strobe <= 0;
						end else mode[6] <= 1'd1;
					end
				3'b101:
					if(newcmd) begin
						mode[6] <= 1;
						if (newdata) begin
							newcmd <= 0;
							waitgate <= 1;
						end
					end else if (gate_r) begin
						count <= init;
						strobe <= 1;
						waitgate <= 0;
					end else if (!waitgate) begin
						count <= count - 1'd1;
						if(c1) begin
							if(strobe) mode[6] <= 0;
							strobe <= 0;
						end else mode[6] <= 1'd1;
					end

			endcase
		end

		if(CS) begin
			if(WR) begin
				rd <= 0;
				latch <= 0;
				if(cmd) begin	// command
					if(|din[5:4]) begin
						mode[5:0] <= din[5:0];
						newcmd <= 1;
						state <= {1'b0, din[5] & ~din[4]};
					end else begin
						latch <= 1;
						latched <= count;
					end
				end else begin	// data
					state <= state[0] + ^mode[5:4] + 1'd1;
					if(state[0]) begin
						newdata <= 1;
						init[15:8] <= din;
						if (~mode[4]) init[7:0] <= 0;
					end
					else begin
						init[7:0] <= din;
						if (~mode[5]) init[15:8] <= 0;
						newdata <= ^mode[5:4];
					end
				end
			end else begin
				rd <= ~rd;
				if(rd) latch <= 0;
			end
		end
	end

endmodule
