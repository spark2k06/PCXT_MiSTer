`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: sound_gen.v
// Description: Part of the Next186 SoC PC project, 
//		stereo 2x16bit pulse density modulated sound generator
// 	44100 samples/sec
//		Disney Sound Source and Covox Speech compatible
// Version 1.0
// Creation date: Jan2015
//
// Author: Nicolae Dumitrache 
// e-mail: ndumitrache@opencores.org
//
/////////////////////////////////////////////////////////////////////////////////
// 
// Copyright (C) 2015 Nicolae Dumitrache
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
//////////////////////////////////////////////////////////////////////////////////
// Additional Comments: 
//
//	byte write: both channels are the same (Covox emulation), the 8bit sample value is shifted by 8, the channel selector is reset to LEFT
// word write: LEFT first, the queue is updated only after RIGHT value is written
// sample rate: 44100Hz
//////////////////////////////////////////////////////////////////////////////////
`define SPKVOL	11

module soundwave(
		input CLK,
		input clk_en,
//		input [15:0]data,
		input [7:0]data,
		input we,
//		input word,
		input speaker,
		input [15:0]opl2left,
		input [15:0]opl2right,
		input [7:0]tandy_snd,
		output full,	// when not full, write max 2x1152 16bit samples
		output dss_full,
		output [15:0] lclamp,
		output [15:0] rclamp
	);

	reg [31:0]wdata;
	reg lr = 1'b0;
	reg [2:0]write = 3'b000;
	wire qempty;
	wire [31:0]sample;
	wire [31:0]sample1 = qempty ? 32'hc000c000 : sample;
	reg [15:0]r_opl2left = 0;
	reg [15:0]r_opl2right = 0;
	wire [16:0]lmix = {sample1[15], sample1[15:0]} + {r_opl2left[15], r_opl2left} + {tandy_snd, 6'd0} + (speaker << `SPKVOL); // signed mixer left
	wire [16:0]rmix = {sample1[31], sample1[31:16]} + {r_opl2right[15], r_opl2right} + {tandy_snd, 6'd0} + (speaker << `SPKVOL); // signed mixer right
	assign lclamp = (~|lmix[16:15] | &lmix[16:15]) ? {!lmix[15], lmix[14:0]} : {16{!lmix[16]}}; // clamp to [-32768..32767] and add 32878
	assign rclamp = (~|rmix[16:15] | &rmix[16:15]) ? {!rmix[15], rmix[14:0]} : {16{!rmix[16]}};
	wire [11:0]wrusedw;
	wire [11:0]rdusedw;
	assign full = wrusedw >= 12'd2940;
	assign dss_full = rdusedw > 12'd90;	// Disney sound source queue full
	 
	sndfifo sndfifo_inst 
	(
		.wrclk(CLK), // input wr_clk
		.rdclk(CLK), // input rd_clk
		.data(wdata), // input [31 : 0] din
		.wrreq(|write), // input wr_en
		.rdreq(clk_en), // input rd_en
		.q(sample), // output [31 : 0] dout
		.wrusedw(wrusedw),
		.rdusedw(rdusedw),
		.rdempty(qempty) // output empty
	);

	always @(posedge CLK) begin
		r_opl2left <= opl2left;
		r_opl2right <= opl2right;
		if(we) begin
		/*
			if(word) begin
				lr <= !lr;
				write <= {2'b00, lr};
				if(lr) wdata[31:16] <= data;
				else wdata[15:0] <= data;
			end else begin
		*/
				lr <= 1'b0;		// left
				write <= 3'b110;
				wdata <= {1'b1, data[7:0], 8'b00000001, data[7:0], 7'b0000000};
			end
		else write <= write - |write;
	end


endmodule
