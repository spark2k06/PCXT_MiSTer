;================================================
; testopl.asm - Check & Test OPL2/3 FM Sound Card 
;------------------------------------------------
;
; Compiles with NASM 2.11.08, might work with other versions
;
; Copyright (C) 2019 - 2020 Aitor Gómez.
; Provided for hobbyist use on the Xi 8088 and Micro 8088 boards.
;
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;
;=========================================================================

	org 100h
	call opl_print			; print OPL card type
	call sound
	mov ah,4Ch
	xor al, al
	int 21h


; 8255 PPI port A I/O register - Read - keyboard data
ppi_pa_reg	equ	60h	; 8255 PPI port A I/O register

; Port 61h - 8255 PPI Port B - Write only
ppi_pb_reg	equ	61h	; 8255 PPI port B I/O register

pic1_reg0	equ	20h
pic1_reg1	equ	21h
pit_ch0_reg	equ	40h
pit_ch1_reg	equ	41h
pit_ch2_reg	equ	42h
pit_ctl_reg	equ	43h

pic_freq	equ	1193182	; PIC input frequency - 14318180 MHz / 12

%include 	"config.inc"
%include	"messages.inc"	; POST messages
%include	"delay.inc"		; delay function
%include	"opl.inc"		; check OPL2/3 FM boards
%include	"sound.inc"		; sound test



;=========================================================================
; print - print ASCIIZ string to the console
; Input:
;	CS:SI - pointer to string to print
; Output:
;	none
;-------------------------------------------------------------------------
print:
	pushf
	push	ax
	push	bx
	push	si
	push	ds
	push	cs
	pop	ds
	cld
.1:
	lodsb
	or	al,al
	jz	.exit
	mov	ah,0Eh
	mov	bl,0Fh
	int	10h
	jmp	.1
.exit:
	pop	ds
	pop	si
	pop	bx
	pop	ax
	popf
	ret