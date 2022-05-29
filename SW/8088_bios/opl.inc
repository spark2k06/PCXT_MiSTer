;============================================
; opl.inc - Check & Test OPL2/3 FM Sound Card 
;--------------------------------------------
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

setport:
	out dx, al
	xchg ax, bx
	mov cx, 6
	
.loop1:
	in al,dx
	loop .loop1
	
	xchg ax, bx
	xchg al, ah
	add dx, 1
	out dx, al	
	xchg ax, bx
	sub dx, 1
	mov cx, 35

.loop2:
	in al,dx
	loop .loop2	
	
	ret

;=========================================================================
; oplcheck - Check OPL FM board 
; Input:
;	none
; Output:
;	none, destroys some registers
;-------------------------------------------------------------------------
oplcheck:
	push cx
	push ax
	
	mov al, 4
	mov ah, 60h	
	call setport
	
	mov al, 4	
	mov ah, 80h	
	call setport
	
	mov cx, 0F0h

.delay1:
	nop
	loop .delay1
		
	in al, dx
	push ax
	
	mov al, 2
	mov ah, 0FFh	
	call setport
	
	mov al, 4
	mov ah, 21h	
	call setport
	
	mov cx, 0F0h
	
.delay2:
	nop
	loop .delay2
	
	pop ax
	xchg al, ah
	in al, dx
	push ax
	
	mov al, 4
	mov ah, 60h	
	call setport
		
	mov al, 4
	mov ah, 80h	
	call setport
	
	pop ax
	xchg al, ah
	
	xor bl, bl ; None (0)
	and ax, 0e0e0h
	cmp ax, 0c000h	
	jnz .exit1
	mov bl, 1 ; OPL2 (1)
	in al, dx
	and al, 6
	cmp al, 0
	jnz .exit1
	mov bl, 2 ; OPL3 (2)
	
.exit1:
	pop ax
	pop cx
	ret

opl_init:

;-------------------------------------------------------------------------
; Initial delay before detecting the sound card, which is prior to video card initialization

%ifdef  INIT_DELAY
        mov     cx, INIT_DELAY
.wait:
        push    cx
        mov     cx, 43h
        call    delay_15us
        pop     cx
        loop    .wait
%endif
;
	xor al,al	; None

.check_388h:

	mov dx,388h
	call oplcheck
	cmp bl, 0
	jz .check_220h
	cmp bl, 1
	jz .opl2_388h
	or al, 00000010b ; 388h OPL3	
.opl2_388h:
	or al, 00000001b ; 388h OPL2
	
.check_220h:
	
	mov dx,220h
	call oplcheck
	cmp bl, 0
	jz .check_240h
	cmp bl, 1
	jz .opl2_220h
	or al, 00001000b ; 220h OPL3	
.opl2_220h:
	or al, 00000100b ; 220h OPL2
	
.check_240h:
	
	mov dx,240h
	call oplcheck
	cmp bl, 0
	jz .end_check
	cmp bl, 1
	jz .opl2_240h
	or al, 00100000b ; 240h OPL3	
.opl2_240h:
	or al, 00010000b ; 240h OPL2
	
.end_check:

	ret

; opl_print
; Input:
;	al, OPL card type
; Output:
;	none, destroys some registers
;-------------------------------------------------------------------------
	
opl_print:

	mov	si,msg_oplcard
	call	print	
	cmp al, 00000001b ; 388h OPL2
	jnz .next1
	mov	si,msg_adlib
	call	print
	jmp .exit2
	
.next1:

	cmp al, 00000011b ; 388h OPL3
	jnz .next2
	mov	si,msg_adlibgold
	call	print
	jmp .exit2
	
.next2:

	cmp al, 00000101b ; 388h OPL2 + 220h OPL2
	jz .sbpro
	cmp al, 00010001b ; 388h OPL2 + 240h OPL2
	jnz .next3
.sbpro:
	mov	si,msg_sbpro
	call	print
	jmp .exit2
	
.next3:

	cmp al, 00001111b ; 388h OPL3 + 220h OPL3
	jz .sbpro2
	cmp al, 00110011b ; 388h OPL3 + 240h OPL3
	jnz .next4
.sbpro2:
	mov	si,msg_sbpro2
	call	print
	jmp .exit2
	
.next4:

	cmp al, 00000100b ; 220h OPL2
	jnz .next5
	mov	si,msg_opl2_220h
	call	print
	jmp .exit2
	
.next5:

	cmp al, 00010000b ; 240h OPL2
	jnz .next6
	mov	si,msg_opl2_240h
	call	print
	jmp .exit2
	
.next6:

	cmp al, 00001100b ; 220h OPL3
	jnz .next7
	mov	si,msg_opl3_220h
	call	print
	jmp .exit2
	
.next7:

	cmp al, 00110000b ; 240h OPL3
	jnz .msg_opl_none
	mov	si,msg_opl3_240h
	call	print
	jmp .exit2
	
.msg_opl_none:

	mov	si,msg_opl_none
	call	print
	jmp .exit2

.exit2:
	ret
