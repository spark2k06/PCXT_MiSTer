;=========================================================================
; sound.inc - Play power-on sound. This also tests PIT and PORT B functionality
;-------------------------------------------------------------------------
;
; Compiles with NASM 2.11.08, might work with other versions
;
; Copyright (C) 2019 - 2020 Aitor Gomez (spark2k06)
; Copyright (C) 2010 - 2020 Sergey Kiselev.
; Provided for hobbyist use on the Xi 8088 and Micro 8088 boards.
;
; Intel-Inside melody OPL2 is based and adapted from a work by @leonardo-ono
; https://github.com/leonardo-ono/Assembly8086OPL2AdlibHardwareLevelProgrammingTest 
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

notes	dw	pic_freq/554		; D flat
	dw	-1			; silent
	dw	pic_freq/227		; D flat
	dw	pic_freq/370		; G flat
	dw	pic_freq/227		; D flat
	dw	pic_freq/415		; A flat
	dw	0

;=========================================================================
; sound - Play power-on sound.
; Input:
;	al, OPL card type
; Output:
;	none, destroys some registers
;-------------------------------------------------------------------------
sound:
		
	and al, 1			; 388h OPL2 compatible available?
	cmp al, 1
	
	jz play_intel		; Plays sinfony	with OPL2	
						; Else through PC-Speaker
	cld					
	mov	si,notes		; set SI to notes table

	mov	al,0B6h			; set PIC channel 2 to mode 3
	out	pit_ctl_reg,al

.loop:
    cs	lodsw				; load next note to AX
	cmp	ax,0
	jz	.exit
	jl	.silent			; don't turn on speaker if silent note
	out	pit_ch2_reg,al		; load divisor's low byte to PIC
	mov	al,ah
	out	pit_ch2_reg,al		; load divisor's high byte to PIC

	in	al,ppi_pb_reg		; read current value of PORT B
        or      al,03h			; turn on the speaker
        out     ppi_pb_reg,al		; write the new value

.silent:
	mov	cx,3000h
	call	delay_15us		; delay while note is playing

	in	al,ppi_pb_reg		; read current value of PORT B
	and	al,0FCh			; turn off the speaker
        out     ppi_pb_reg,al		; write the new value

        mov     cx,0100h
	call	delay_15us		; delay after the note
        
        jmp     .loop			; play the next note
.exit:
	ret

;=========================================================================
; beep - Play a beep sound
; Input:
;	BL - duration in 0.1 second
; Output:
;	BL = 0
;-------------------------------------------------------------------------
beep:
	push	ax
	mov	al,0B6h			; set PIC channel 2 to mode 3
	out	pit_ctl_reg,al
	mov	ax,1193			; approximately 1000 Hz
	out	pit_ch2_reg,al		; load divisor's low byte to PIC
	mov	al,ah
	out	pit_ch2_reg,al		; load divisor's high byte to PIC
	in	al,ppi_pb_reg		; read current value of PORT B
	or	al,03h			; turn on the speaker
	out	ppi_pb_reg,al		; write the new value
.loop:
	mov	cx,6666			; 0.1 second delay
	call	delay_15us
	dec	bl
	jnz	.loop
	xor	al,03h			; turn off the speaker
	out	ppi_pb_reg,al		; write the new value
	pop	ax
	ret

play_intel:
			
	call reset_all_registers
		
	mov cl, 0 ; channel 0
	call setup_piano_instrument			
	mov cl, 1 ; channel 1
	call setup_piano_instrument
	mov cl, 2 ; channel 2
	call setup_piano_instrument
	
	call play_intel1
	ret
	
play_intel1:
	mov di, 0
	
.next_note:
	; channel 0
	; di = index
	; cl = channel
	; bx = channel music data
	mov cl, 0
	cs mov bx, intel_music_0
	call play_channel_note
	
	; channel 1
	; di = index
	; cl = channel
	; bx = channel music data
	mov cl, 1
	cs mov bx, intel_music_1
	call play_channel_note
	
	; channel 2
	; di = index
	; cl = channel
	; bx = channel music data
	mov cl, 2
	cs mov bx, intel_music_2
	call play_channel_note
	
	push ax
	push cx
	push dx
	mov dx, 389h			
	mov cx, 6000h ; delay
.delay:
	in al, dx			
	loop .delay
	pop dx
	pop cx
	pop ax
	
	inc di
	cmp di, word [cs:intel_music_size]
	jb .next_note
.end:
	ret

; di = index
; cl = channel
; bx = channel music data
play_channel_note:
	push di
	add di, bx
	mov bh, 0
	mov bl, [cs:di]
	pop di

	cmp bl, 255 ; ignore
	jz .ignore
	cmp bl, 254 ; note off
	jz .note_off
	
.play_midi_note:
	mov si, bx ; si = midi note
	; mov cl, 0 ; cl = channel
	call note_on
	jmp .ignore
	
.note_off:
	;mov cl, 0 ; cl = channel
	call note_off
.ignore:
	ret
	
; si = midi note
; cl = channel
note_on:
	shl si, 1
	mov ax, word [cs:midi_note_to_freq_table + si]
	
	mov bl, 0a0h ; register
	add bl, cl
	mov bh, al ; value
	call write_adlib

	mov bl, 0b0h ; register
	add bl, cl
	mov bh, 34h ; value
	or bh, ah
	call write_adlib

	ret

; cl = channel
note_off:
	mov bl, 0b0h ; register
	add bl, cl
	mov bh, 0h ; value
	call write_adlib
	ret

; cl = channel
setup_piano_instrument:
	mov si, 0
.next_register:
	mov bl, [cs:instr_registers + si] ; register
	add bl, cl
	mov bh, [cs:piano_instr + si] ; value
	call write_adlib
	inc si
	cmp si, word [cs:instr_registers_count]
	jb .next_register
.end:
	ret

reset_all_registers:
	mov bl, 0h
	mov bh, 0
.next_register:
	; bl = register
	; bh = value
	call write_adlib
	inc bl
	cmp bl, 0f5h
	jbe .next_register
.end:
	ret

	; bl = register
	; bh = value
write_adlib:
	push ax
	push bx
	push cx
	push dx

	mov dx, 388h
	mov al, bl
	out dx, al			

	mov dx, 389h
	mov cx, 6
.delay_1:
	in al, dx
	loop .delay_1

	mov al, bh
	out dx, al

	mov cx, 35
.delay_2:
	in al, dx
	loop .delay_2

	pop dx
	pop cx
	pop bx
	pop ax
	
	ret
	
instr_registers_count:	dw 11
instr_registers:		db 020h, 040h, 060h, 080h, 0e0h, 0c0h, 023h, 043h, 063h, 083h, 0e3h
piano_instr:			db 033h, 05ah, 0b2h, 050h, 001h, 000h, 031h, 000h, 0b1h, 0f5h, 001h
	
						       

midi_note_to_freq_table:
				db 005h, 000h, 005h, 000h, 006h, 000h, 006h, 000h, 006h, 000h, 007h, 000h, 007h, 000h, 008h, 000h
				db 008h, 000h, 009h, 000h, 009h, 000h, 00ah, 000h, 00ah, 000h, 00bh, 000h, 00ch, 000h, 00ch, 000h
				db 00dh, 000h, 00eh, 000h, 00fh, 000h, 010h, 000h, 011h, 000h, 012h, 000h, 013h, 000h, 014h, 000h
				db 015h, 000h, 016h, 000h, 018h, 000h, 019h, 000h, 01bh, 000h, 01ch, 000h, 01eh, 000h, 020h, 000h
				db 022h, 000h, 024h, 000h, 026h, 000h, 028h, 000h, 02bh, 000h, 02dh, 000h, 030h, 000h, 033h, 000h
				db 036h, 000h, 039h, 000h, 03ch, 000h, 040h, 000h, 044h, 000h, 048h, 000h, 04ch, 000h, 051h, 000h
				db 056h, 000h, 05bh, 000h, 060h, 000h, 066h, 000h, 06ch, 000h, 073h, 000h, 079h, 000h, 081h, 000h
				db 088h, 000h, 091h, 000h, 099h, 000h, 0a2h, 000h, 0ach, 000h, 0b6h, 000h, 0c1h, 000h, 0cdh, 000h
				db 0d9h, 000h, 0e6h, 000h, 0f3h, 000h, 002h, 001h, 011h, 001h, 022h, 001h, 033h, 001h, 045h, 001h
				db 058h, 001h, 06dh, 001h, 083h, 001h, 09ah, 001h, 0b2h, 001h, 0cch, 001h, 0e7h, 001h, 004h, 002h
				db 023h, 002h, 044h, 002h, 066h, 002h, 08bh, 002h, 0b1h, 002h, 0dah, 002h, 006h, 003h, 034h, 003h
				db 065h, 003h, 098h, 003h, 0cfh, 003h, 009h, 004h, 046h, 004h, 088h, 004h, 0cdh, 004h, 016h, 005h
				db 063h, 005h, 0b5h, 005h, 00ch, 006h, 068h, 006h, 0cah, 006h, 031h, 007h, 09eh, 007h, 012h, 008h
				db 08dh, 008h, 010h, 009h, 09ah, 009h, 02ch, 00ah, 0c7h, 00ah, 06bh, 00bh, 018h, 00ch, 0d1h, 00ch
				db 094h, 00dh, 062h, 00eh, 03dh, 00fh, 025h, 010h, 01bh, 011h, 020h, 012h, 034h, 013h, 058h, 014h
				db 08eh, 015h, 0d6h, 016h, 031h, 018h, 0a2h, 019h, 028h, 01bh, 0c5h, 01ch, 07bh, 01eh, 04bh, 020h


intel_music_size: dw 24
	
	; 0~127 -> midi note
	; 254   -> note off
	; 255   -> ignore
			
	; channel 0
	intel_music_0:
			db   73, 0ffh, 0ffh, 0ffh, 0ffh, 0feh,   73, 0ffh, 0ffh, 0ffh, 0ffh, 0feh,   80, 0ffh, 0ffh, 0ffh
			db 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh

	; channel 1
	intel_music_1:
			db   80, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0feh,   78, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh
			db 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh
			
	; channel 2
	intel_music_2:
			db   85, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0feh,   73, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh
			db 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh, 0ffh
