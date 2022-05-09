//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: PIC_8259.v
// Description: Part of the Next186 SoC PC project, PIC controller
// 	8259 simplified interrupt controller (only interrupt mask can be read, not IRR or ISR, no EOI required)
// Version 1.0
// Creation date: May2012
//
// Author: Nicolae Dumitrache 
// e-mail: ndumitrache@opencores.org
//
// ISR added, switched to non-automatic end: July2021 Gyorgy Szombathelyi
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
// http://wiki.osdev.org/8259_PIC
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module PIC_8259(
	input RST,
	input CS,
	input A,
	input WR,
	input [7:0]din,
	input slave,
	output wire [7:0]dout,
	output [7:0]ivect,
	input clk,		// cpu CLK
	output reg INT = 0,
	input IACK,
	input [4:0]I,	// 0:timer, 1:keyboard, 2:RTC, 3:mouse, 4:COM1
	output reg dbg_slave,
	output reg dbg_a,
	output reg dbg_wr,
	output reg [7:0] dbg_din
);

reg [4:0]ss_I = 0;
reg [4:0]s_I = 0;
reg [7:0]IMR_m = 8'hFF;
reg [7:0]IMR_s = 8'hFF;
reg [4:0]IRR = 0;
reg [4:0]ISR = 0;
reg      RIS; // Read ISR
reg      AEOI;

wire [4:0]IMR = {IMR_m[4],IMR_s[4],IMR_s[0],IMR_m[1:0]};

assign dout = A ? (slave ? IMR_s : IMR_m) :
            RIS ? (slave ? {3'b000, ISR[3], 3'b000, ISR[2]} : {3'b000, ISR[4], 2'b00, ISR[1:0]}) :
			      (slave ? {3'b000, IRR[3], 3'b000, IRR[2]} : {3'b000, IRR[4], 2'b00, IRR[1:0]});

wire [4:0] IRQ = IRR & ~IMR;

assign ivect = IRQ[0] ? 8'h08 :
               IRQ[1] ? 8'h09 :
               IRQ[2] ? 8'h70 :
               IRQ[3] ? 8'h74 :
               IRQ[4] ? 8'h0c : 8'h00;

always @ (posedge clk) begin
	if (RST) begin
		ss_I <= 0;
		s_I <= 0;
		IMR_m <= 8'hFF;
		IMR_s <= 8'hFF;
		IRR <= 0;
		ISR <= 0;
		INT <= 0;
		RIS <= 0;
		AEOI <= 0;
	end else begin
		ss_I <= I;
		s_I <= ss_I;
		IRR <= (IRR | (~s_I & ss_I));	// front edge detection
		if(~INT) begin
			if(IRQ[0] && !ISR[0]) begin //timer
				INT <= 1'b1; 
			end else if(IRQ[1] && ISR[1:0] == 0) begin  // keyboard
				INT <= 1'b1; 
			end else if(IRQ[2] && ISR[2:0] == 0) begin  // RTC
				INT <= 1'b1; 
			end else if(IRQ[3] && ISR[3:0] == 0) begin // mouse
				INT <= 1'b1; 
			end else if(IRQ[4] && ISR[4:0] == 0) begin // COM1
				INT <= 1'b1;
			end
		end else if(IACK) begin
			INT <= 1'b0;
			if (IRQ[0]) begin
				IRR[0] <= 0;
				ISR[0] <= !AEOI;
			end else if (IRQ[1]) begin
				IRR[1] <= 0;
				ISR[1] <= !AEOI;
			end else if (IRQ[2]) begin
				IRR[2] <= 0;
				ISR[2] <= !AEOI;
			end else if (IRQ[3]) begin
				IRR[3] <= 0;
				ISR[3] <= !AEOI;
			end else if (IRQ[4]) begin
				IRR[4] <= 0;
				ISR[4] <= !AEOI;
			end
		end
		if(CS) begin
			dbg_a <= A;
			dbg_wr <= WR;
			dbg_slave <= slave;
		end
		if(CS & WR) begin
			dbg_din <= din;
			if (!A) begin
				if (!din[4]) begin
					// OCW
					if (!din[3]) begin
						// OCW2
						if (din[5]) begin
							// End-of-interrupt
							if      (!slave && ISR[0]) ISR[0] <= 0;
							else if (!slave && ISR[1]) ISR[1] <= 0;
							else if ( slave && ISR[2]) ISR[2] <= 0;
							else if ( slave && ISR[3]) ISR[3] <= 0;
							else if (!slave && ISR[4]) ISR[4] <= 0;
						end
					end else begin
						// OCW3
						if (din[1]) RIS <= din[0];
					end
				end else begin
					// ICW
				end
			end else begin
				// OCW1
				if(slave) IMR_s <= din; else IMR_m <= din;
			end
		end
	end
end

endmodule


