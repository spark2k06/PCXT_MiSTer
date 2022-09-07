`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
/*
MIT License

Copyright (c) 2022 Antonio S�nchez (@TheSonders)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

PS2MOUSE -> MSMOUSE Conversion
Preliminary
https://github.com/TheSonders/MouseConversion/blob/main/MSMouseWrapper.v

References:
https://roborooter.com/post/serial-mice/
https://isdaman.com/alsos/hardware/mouse/ps2interface.htm
https://www.avrfreaks.net/sites/default/files/PS2%20Keyboard.pdf

*/
//////////////////////////////////////////////////////////////////////////////////
module MSMouseWrapper
	#(parameter CLKFREQ=50_000_000)
	(input wire clk,
	input wire ps2dta_in,
	input wire ps2clk_in,
	output reg ps2dta_out,
	output reg ps2clk_out,
	input wire rts,
	output reg rd=0
	);

localparam PS2BAUDRATE=15_000;
localparam PS2PERIOD=(CLKFREQ/PS2BAUDRATE);
localparam HUNDRED=(CLKFREQ/10_000);
localparam SERIALBAUDRATE=1_200;
localparam SERIALPERIOD=(CLKFREQ/SERIALBAUDRATE);
localparam MILLIS=(CLKFREQ/1000);

`define 	PAR_ODD	0
`define	PAR_EVEN	1

///////////////////////////////////////////
//////////////PS2 Reception////////////////
///////////////////////////////////////////
`define PS2CLKRISE	(ps2clkbuf==4'b0011)
`define PS2CLKFALL	(ps2clkbuf==4'b1100)
`define RTSRISE		(rtsbuf==4'b0011)
`define TXIDLE			(PS2Tr_STM==1)
`define PS2R_Start	 0
`define PS2R_Parity	 9
`define PS2R_Stop		10
`define PS2R_Delay	11

reg [3:0]ps2clkbuf=0;
reg [3:0]rtsbuf=0;
reg [3:0]PS2R_STM=0;
reg PS2R_NewByte=0;
reg [7:0]PS2R_Byte=0;
reg PS2R_PAR=0;
reg [$clog2(PS2PERIOD)-1:0]PS2R_Counter=0;

always @(posedge clk)begin
	ps2clkbuf<={ps2clkbuf[2:0],ps2clk_in};
	rtsbuf<={rtsbuf[2:0],rts};
	if (PS2R_NewByte==1)PS2R_NewByte<=0;
	
	if (PS2R_STM==`PS2R_Delay)begin
		if (PS2R_Counter==0)begin
			PS2R_NewByte<=1;
			PS2R_STM<=0;
		end
		else PS2R_Counter<=PS2R_Counter-1;
	end
	else begin
	if (`PS2CLKRISE && `TXIDLE)begin
		case (PS2R_STM)
			`PS2R_Start:
				begin
					if (ps2dta_in==0)begin
						PS2R_STM<=PS2R_STM+1;
						PS2R_PAR<=`PAR_EVEN;
					end
				end
			`PS2R_Parity:
				begin
					if (ps2dta_in==PS2R_PAR)begin
						PS2R_STM<=PS2R_STM+1;
					end
					else begin
						PS2R_STM<=0;
					end
				end	
			`PS2R_Stop:
				begin
					if (ps2dta_in==1)begin
						PS2R_STM<=PS2R_STM+1;
						PS2R_Counter<=PS2PERIOD;
					end
					else PS2R_STM<=0;
				end
			default:
				begin
					PS2R_Byte<={ps2dta_in,PS2R_Byte[7:1]};
					PS2R_PAR<=PS2R_PAR^ps2dta_in;
					PS2R_STM<=PS2R_STM+1;
				end
		endcase
	end
	end	
end


///////////////////////////////////////////
//////////////PS2 Processing///////////////
///////////////////////////////////////////

`define PS2Pr_ResetDelay 		 0
`define PS2Pr_SendReset	 		 1
`define PS2Pr_WaitResetACK 	 2
`define PS2Pr_WaitBAT			 3
`define PS2Pr_WaitID				 4
`define PS2Pr_WaitACK			 5
`define PS2Pr_Query				 6
`define PS2Pr_Wait0				 7
`define PS2Pr_Wait1				 8
`define PS2Pr_Wait2				 9
`define PS2Pr_Wait3				10

`define PS2Pr_BAT			8'hAA
`define PS2Pr_ID			8'h00
`define PS2Pr_RESET		8'hFF
`define PS2Pr_REMOTE		8'hF0
`define PS2Pr_ACK			8'hFA
`define PS2Pr_READ		8'hEB

//Sustituye 30'h3FFFFE9A por 30'h3FFFFF9A
`define PS2Pr_M			30'h3FFFFE9A	
`define PS2BitSYNC		3

`define LeftBt				PS2Byte1[0]
`define RightBt			PS2Byte1[1]
`define MSMByte1			{2'b11,`LeftBt,`RightBt,PS2Byte1[5],PS2R_Byte[7],PS2Byte1[4],PS2Byte2[7]}
`define MSMByte2			{2'b10,PS2Byte2[6:1]}
`define MSMByte3			{2'b10,PS2R_Byte[6:1]}

`define Serial_Reset		 0
`define Serial_Idle		 1
`define Serial_Stop		10

`define TMR_END	(Timer==0)

`define PS2Tr_Reset		 0
`define PS2Tr_Idle		 1
`define PS2Tr_ClockLow	 2
`define PS2Tr_Parity		11
`define PS2Tr_Stop		12
`define PS2Tr_ACK			13
`define PS2Tr_End			14
`define STARTBIT			 0
`define STOPBIT			 1

reg [$clog2(MILLIS)-1:0]Timer=0;
reg SerialSendRequest=0;
reg [4:0]Serial_STM=0;

reg [3:0]PS2Pr_STM=0;
reg PS2SendRequest=0;
reg [7:0]PS2SendData=0;
reg [7:0]PS2Byte1=0;
reg [7:0]PS2Byte2=0;
reg [29:0]SerialSendData=0;

reg [3:0]PS2Tr_STM=0;
reg PS2Tr_PAR=0;

always @(posedge clk)begin
	if (PS2SendRequest==1)PS2SendRequest<=0;
	if (SerialSendRequest==1)SerialSendRequest<=0;
	if (`RTSRISE)begin
		PS2Pr_STM<=0;
		Timer<=0;
	end
	else begin
		if (Timer!=0)Timer<=Timer-1;
		case (PS2Pr_STM)
			`PS2Pr_ResetDelay:begin
				SetTimer(MILLIS);
				PS2Pr_STM<=PS2Pr_STM+1;
			end
			`PS2Pr_SendReset:begin
				if (`TMR_END)begin
					SendPS2(`PS2Pr_RESET);
					PS2Pr_STM<=PS2Pr_STM+1;
				end
			end
			`PS2Pr_WaitResetACK:begin
				if (PS2R_NewByte==1)begin
					if (PS2R_Byte==`PS2Pr_ACK)begin
						PS2Pr_STM<=PS2Pr_STM+1;
					end
					else begin
						PS2Pr_STM<=0;
					end
				end
			end
			`PS2Pr_WaitBAT:begin
				if (PS2R_NewByte==1)begin
				if (PS2R_Byte==`PS2Pr_BAT)begin
					PS2Pr_STM<=PS2Pr_STM+1;
				end
				else begin
					PS2Pr_STM<=0;
				end
				end
			end
			`PS2Pr_WaitID:begin
				if (PS2R_NewByte==1)begin
					if (PS2R_Byte==`PS2Pr_ID)begin
						PS2Pr_STM<=PS2Pr_STM+1;
						SendPS2(`PS2Pr_REMOTE);
					end
					else begin
						PS2Pr_STM<=0;
					end
				end
			end
			`PS2Pr_WaitACK:begin
				if (PS2R_NewByte==1)begin
					if (PS2R_Byte==`PS2Pr_ACK)begin
						PS2Pr_STM<=PS2Pr_STM+1;
						SendSerial(`PS2Pr_M);
					end
					else begin
						PS2Pr_STM<=0;
					end
				end
			end
			`PS2Pr_Query:begin
				if (SerialSendRequest==0 && Serial_STM==1)begin
					SendPS2(`PS2Pr_READ);
					PS2Pr_STM<=PS2Pr_STM+1;
				end
			end
			`PS2Pr_Wait0:begin
				if (PS2R_NewByte==1)begin
					if (PS2R_Byte==`PS2Pr_ACK)begin
						PS2Pr_STM<=PS2Pr_STM+1;
					end
					else begin
						PS2Pr_STM<=0;
					end
				end
			end
			`PS2Pr_Wait1:begin
				if (PS2R_NewByte==1)begin
					if (PS2R_Byte[`PS2BitSYNC]==1)begin
						PS2Byte1<=PS2R_Byte;
						PS2Pr_STM<=PS2Pr_STM+1;
					end
				end
			end
			`PS2Pr_Wait2:begin
				if (PS2R_NewByte==1)begin
					PS2Byte2<=PS2R_Byte;
					PS2Pr_STM<=PS2Pr_STM+1;
				end
			end
			`PS2Pr_Wait3:begin
				if (PS2R_NewByte==1)begin
					PS2Pr_STM<=`PS2Pr_Query;
					SendSerial({1'b1,`MSMByte3,2'b01,`MSMByte2,2'b01,`MSMByte1,1'b0});
				end
			end
		endcase
	end


///////////////////////////////////////////
/////////////Serial Transmision////////////
///////////////////////////////////////////
	if (`RTSRISE)begin
		Serial_STM<=0;
	end
	else begin
	case (Serial_STM)
		`Serial_Reset:begin
			rd<=1;
			Serial_STM<=Serial_STM+1;
		end
		`Serial_Idle:begin
			if (SerialSendRequest==1)begin
				Serial_STM<=Serial_STM+1;
				{SerialSendData,rd}<={1'b1,SerialSendData};
				SetTimer(SERIALPERIOD);
			end
		end
		default:begin
			if (`TMR_END)begin
				Serial_STM<=Serial_STM+1;
				{SerialSendData,rd}<={1'b1,SerialSendData};
				SetTimer(SERIALPERIOD);
			end
		end
	endcase
	end

	
///////////////////////////////////////////
//////////////PS2 Transmision//////////////
///////////////////////////////////////////
	if (`RTSRISE)begin
		PS2Tr_STM<=0;
	end
	else begin
	case (PS2Tr_STM)
		`PS2Tr_Reset:begin
			ps2dta_out<=1; 			//Requerido para algunas CPLD
			ps2clk_out<=1;
			PS2Tr_STM<=PS2Tr_STM+1;
		end
		`PS2Tr_Idle:begin
			if (PS2SendRequest==1)begin
				ps2clk_out<=0;
				SetTimer(HUNDRED);
				PS2Tr_STM<=PS2Tr_STM+1;
			end
		end
		`PS2Tr_ClockLow:begin
			if (`TMR_END)begin
				ps2dta_out<=`STARTBIT;
				ps2clk_out<=1;
				PS2Tr_STM<=PS2Tr_STM+1;
				PS2Tr_PAR<=`PAR_EVEN;
			end
		end
		`PS2Tr_Parity:begin
			if (`PS2CLKFALL)begin
				ps2dta_out<=PS2Tr_PAR;
				PS2Tr_STM<=PS2Tr_STM+1;
			end
		end
		`PS2Tr_Stop:begin
			if (`PS2CLKFALL)begin
				ps2dta_out<=`STOPBIT;
				PS2Tr_STM<=PS2Tr_STM+1;
			end
		end
		`PS2Tr_ACK:begin
			if (`PS2CLKFALL)begin
				PS2Tr_STM<=PS2Tr_STM+1;
			end
		end
		`PS2Tr_End:begin
			if (`PS2CLKRISE)begin
				PS2Tr_STM<=`PS2Tr_Idle;
			end
		end
		default:begin
			if (`PS2CLKFALL)begin
				{PS2SendData,ps2dta_out}<={1'b1,PS2SendData};
				PS2Tr_PAR<=PS2Tr_PAR^PS2SendData[0];
				PS2Tr_STM<=PS2Tr_STM+1;
			end
		end
	endcase
	end
end

task SendPS2 (input [7:0] ByteToSend);
begin
	PS2SendRequest<=1;
	PS2SendData<=ByteToSend;
end
endtask

task SendSerial (input [29:0] ByteToSend);
begin
	SerialSendRequest<=1;
	SerialSendData<=ByteToSend;
end
endtask

task SetTimer(input [31:0]TIME);
begin
	Timer<=TIME;
end
endtask

endmodule
