; This file is part of the MCL86 SoC PC project

; Filename: bios.asm
; Description: Part of the MCL86 SoC PC project, ROM BIOS code
; Version 1.0
; Creation date: Feb-Jun 2013

; Author: Nicolae Dumitrache (Next186)
; e-mail: ndumitrache@opencores.org

; -------------------------------------------------------------------------------------
 
; Copyright (C) 2013 Nicolae Dumitrache
 
; This source file may be used and distributed without 
; restriction provided that this copyright statement is not 
; removed from the file and that any derivative work contains 
; the original copyright notice and the associated disclaimer.
 
; This source file is free software; you can redistribute it 
; and/or modify it under the terms of the GNU Lesser General 
; Public License as published by the Free Software Foundation;
; either version 2.1 of the License, or (at your option) any 
; later version. 
 
; This source is distributed in the hope that it will be 
; useful, but WITHOUT ANY WARRANTY; without even the implied 
; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR 
; PURPOSE. See the GNU Lesser General Public License for more 
; details. 
 
; You should have received a copy of the GNU Lesser General 
; Public License along with this source; if not, download it 
; from http://www.opencores.org/lgpl.shtml 
 
; -----------------------------------------------------------------------

.186 ; Missing 186 instructions to migrate to 8086, related to disk access, ideally replace with Universal XTIDE ide and ROM.
.model tiny
.code

SCANCODE1   equ 1
    
        org 0e000h        
bios:        
biosmsg     db 'MCL86 SoC PC BIOS (C) 2022 MicroCore Labs', 0
msgkb       db 'PS2 KB detected', 13, 10, 0
        
        org 0e05bh
coldboot:
warmboot:                
        in      al, 98h               
        cmp     al, 2
        jz      bios2mb
        mov     word ptr cs:[ramsize], 0004h        
        
bios2mb:        
        cli
        cld
        mov     ax, 30h
        mov     ss, ax
        mov     sp, 100h
        
        xor     ax, ax
        push    ax
        popf
        
        mov     al, 36h
        out     43h, al
        xor     ax, ax
        out     7, ax       ; NMIonIORQ_HI = 0
        out     40h, al
        out     40h, al      ; 18Hz PIT CH0
        out     61h, al      ; speaker off
        not     al
        out     21h, al      ; disable all interrupts
		out		0a1h, al
        out     6, ax       ; NMIonIORQ_LO = 255 -> disabled
        
; -------------------- Interrupt table init
        xor     ax, ax
        mov     ds, ax        
        push    ds
        pop     es
        xor     si, si
        mov     di, 4
        mov     word ptr [si], offset defint
        mov     word ptr [si+2], cs
        mov     cx, 256-2
        rep     movsw
        mov     word ptr ds:[7*4], offset int07
        mov     word ptr ds:[8*4], offset int08
        mov     word ptr ds:[9*4], offset int09
        mov     word ptr ds:[10h*4], offset int10        
        mov     word ptr ds:[11h*4], offset int11        
        mov     word ptr ds:[12h*4], offset int12        
        mov     word ptr ds:[13h*4], offset int13        
        mov     word ptr ds:[15h*4], offset int15
        mov     word ptr ds:[16h*4], offset int16
        mov     word ptr ds:[18h*4], offset int18
        mov     word ptr ds:[19h*4], offset int19
        mov     word ptr ds:[1ah*4], offset int1a
        mov     word ptr ds:[1dh*4], offset int_1D
        mov     word ptr ds:[70h*4], offset int70
        mov     word ptr ds:[74h*4], offset int74

; ------------------- BDA init
        mov     ax, 40h
        mov     ds, ax
        push    ds
        pop     es
        xor     di, di
        xor     si, si
        xor     ax, ax
        mov     cl, 80h
        rep     stosw
	mov	word ptr [si+08h], 378h	 ; LPT1 base port address
        mov     byte ptr [si+10h], 24h   ; equipment word (color 80x25, PS2 mouse present)
        mov     word ptr [si+13h], 640   ; memory size in KB
        add     word ptr [si+1ah], 1eh   ; next char pointer in kb buffer
        add     word ptr [si+1ch], 1eh   ; last char pointer in kb buffer
        mov     word ptr [si+60h], 0e0fh ; cursor shape
        mov     word ptr [si+63h], 3d4h  ; video port address
        add     word ptr [si+80h], 1eh   ; start kb buffer
        add     word ptr [si+82h], 3eh   ; end kb buffer
        mov     word ptr [si+87h], 0940h ; video adapter options (512Kb video)
        mov     word ptr [si+89h], 0b71h ; VGA video flags: 400 line text mode, default palette loading on (0), blinking on
        mov     byte ptr [si+96h], 10h   ; 101 keyboard installed 
        
        in      al, 98h        
        cmp     al, 2                    
        jz      bios2mb_2   
        mov     word ptr [si+13h], 256   ; memory size in KB        
bios2mb_2: 
 ; ------------------- Graph mode init
        mov     ax, 3
        int     10h
        
        mov     al, 0
        out     97h, al     ; cpu_speed max        
        
        cmp     byte ptr cs:[kbbios], 01h
        jz      short no_initkb
        
        mov     al, 0aeh
        out     64h, al     ; enable kb
        mov     al, 0a7h
        out     64h, al     ; disable mouse
        call    KbInit        
no_initkb:
        
        mov     al, 0adh
        out     64h, al      ; disable kb interface
        mov     al, 0a8h
        out     64h, al     ; enable mouse
        call    MouseInit

        call    enableKbIfPresent

        mov     al, 20h
        out     64h, al
        in      al, 60h
        or      al, 3
        mov     ah, al
        mov     al, 60h
        out     64h, al
        mov     al, ah
        out     60h, al     ; enable 8042 mouse and kb interrupts

		mov     ax, 0		; 1000-1   ; 1ms
		out     70h, ax     ; set RTC frequency (stop)

;		mov     al, 0
		out     21h, al     ; enable all PIC interrupts (8h, 9h, 0ch)
		out		0a1h, al	; enable all PIC interrupts (70h, 74h)
		out		1, al		; intialize COM mux
		inc		ax
		out		1, ax		; enable auto flush on vblank
        sti                 ; enable CPU interrupts
        
        mov     al, 1
        out     97h, al      ; cpu_speed setted
        
; ---------------------   HDD init
;        call    sdinit
;        mov     HDSize, ax
        push    cs
        pop     es
        mov     si, offset biosmsg
        call    prts
        mov     si, offset bioscont
        call    prts
        mov     si, offset bioscont2
        in      al, 98h        
        cmp     al, 2     
        jz      bios2mb_3
        mov     si, offset bioscont512
bios2mb_3:
        call    prts
               
;        mov     ax, HDSize
;        shr     ax, 1
;        call    dispAX        
;        mov     si, offset msgmb
;        call    prts
        
        test    byte ptr KbdFlags3, 10h
        jz      nokbmsg
        mov     si, offset msgkb
        call    prts
nokbmsg:
        test    byte ptr EquipmentWord, 4
        jz      nomousemsg
        mov     si, offset msgmouse
        call    prts
nomousemsg:
               
;-------------- HD bootstrap
            db      0eah
            dw      0, 0f600h   ; JMP to IBM BASIC ROM

            ; Original HD bootstrap
            mov     ax, 305h
            xor     bx, bx
            int     16h     ; set typematic rate and delay to fastest
            int     19h

msgmouse    db 'PS2 Mouse detected', 13, 10, 0
bioscont    db 13, 10, 13, 10, 'CPU: 8088 @ 4.77Mhz', 13, 10, 0            
                        
bioscont512 db 13, 10, 'RAM: 256KB', 13, 10, 0           
bioscont2   db 13, 10, 'RAM: 2MB (1MB available + 1MB EMS)', 13, 10, 0

; ---------------------------- INT 07 ---------------------
int07 proc near ; coprocessor ESC sequence
        push    ax
        push    bx
        push    ds
        push    bp
        mov     bp, sp
        lds     bx, [bp+8]  
int07_pfx:        
        mov     al, [bx]
        inc     bx
        and     al, 0f8h
        cmp     al, 0d8h        ; ESC code
        jne     short int07_pfx
              
        cmp     byte ptr [bx], 0c0h ; mod reg r/m of ESC 8087 instruction
        sbb     al, al
        and     al, [bx]
        and     ax, 0c7h
        cmp     al, 6
        jne     int072
        mov     al, 80h
int072:
        push    cx
        mov     cl, 6        
        shr     al, cl
        pop     cx
        
        inc     ax
        add     ax, bx
        mov     [bp+8], ax
        pop     bp
        pop     ds
        pop     bx
        pop     ax
        iret
int07 endp


; ---------------------------- INT 08 ---------------------
int08 proc near
        push    ds
        push    bx
        push    ax
        mov     ax, 40h
        mov     ds, ax
        pop     ax        
        mov     bx, 6ch
        add     word ptr [bx], 1
        adc     word ptr [bx+2], 0
        cmp     word ptr [bx+2], 18h
        jne     short int081
        cmp     word ptr [bx], 0b0h
        jne     short int081
        mov     word ptr [bx], 0
        mov     word ptr [bx+2], 0
        mov     byte ptr [bx+4], 1
int081:
        int     1ch
        sti
        push    ax
        mov     ah, 4
kloop:        
        in      al, 64h
        test    al, 1
        jz      short nokey
        dec     ah
        jnz     short kloop
        test    al, 20h
        jz      short kbdata
        int     74h
        jmp     short nokey
kbdata:
        int     9h        
nokey:
        pop     ax
        pop     bx
        pop     ds
        iret
int08 endp

; --------------------- INT 09 - keyboard ------------------
KbdFlags1       equ     <ds:[17h]>
KbdFlags2       equ     <ds:[18h]>
AltKpd          equ     <ds:[19h]>
CtrlBreak       equ     <ds:[71h]>
KbdFlags3       equ     <ds:[96h]>
KbdFlags4       equ     <ds:[97h]>

; Bits for the KbdFlags1
RShfDown        equ     1
LShfDown        equ     2
CtrlDown        equ     4
AltDown         equ     8
ScrLock         equ     10h
NumLock         equ     20h
CapsLock        equ     40h
Insert          equ     80h

; Bits for the KbdFlags2
LCtrDown        equ     1
LAltDown        equ     2
SysReqDown      equ     4
Pause           equ     8
ScrLockDown     equ     10h
NumLockDown     equ     20h
CapsLockDown    equ     40h
InsDown         equ     80h
 
; Bits for the KbdFlags3
LastE1          equ     1
LastE0          equ     2
RCtrDown        equ     4
RAltDown        equ     8
LastF0          equ     20h

; Bits for the KbdFlags4
ScrLockLED      equ     1
NumLockLED      equ     2
CapsLockLED     equ     4
SetRepeat       equ     8       ; Set auto repeat command in progress
AckReceived     equ     10h
LEDUpdate       equ     40h

IFDEF SCANCODE1

int09 proc near
        
        push    ax
        push    bx
        push    cx
        push    dx
        push    ds
        push    es
        push    ss        
        
        push    ds
        push    es
        
        mov     dx, 40h
        mov     ds, dx
        
        in      al, 60h         ; al contains the scan code
        mov     dx, KbdFlags1
        mov     cx, KbdFlags3
        cmp     al, 0fah        ; ACK
        jne     short noACK

; ------------ manage ACK response
        test    ch, LEDUpdate
        jz      short ToggleACK ; no LED update
        test    ch, AckReceived
        jnz     short SecondACK ; second ACK received
        mov     ah, ch          ; LED update command sent, ACK received, need to send second byte
        and     ah, ScrLockLED or NumLockLED or CapsLockLED
        mov     bl, 0
        call    sendps2byte
        jmp     short ToggleACK
SecondACK:        
        xor     ch, LEDUpdate   ; second ACK, clear LED update bit
ToggleACK:
        xor     ch, AckReceived ; toggle ACK bit 
SetFlags1:                                  
        jmp     SetFlags               
        
; ------------ no ACK
noACK:
        mov     ah,4fh
        stc
        int     15h
        jnc     int09Exit
        cmp     al, 0e0h
        jne     short noE0
        or      cl, LastE0
        jmp     short SetFlags1
noE0:
        cmp     al, 0e1h
        jne     short noE1
        or      cl, LastE1
        jmp     short SetFlags1
noE1:   
        cmp     al, 53h     ; is DEL?
        jne     short noDEL
        mov     ah, dl
        and     ah, CtrlDown or AltDown
        cmp     ah, CtrlDown or AltDown
        jne     NormalKey   ; is DEL, but no CTRL+ALt+DEL
        mov     word ptr ds:[72h], 1234h    ; warm boot flag
        db      0eah
        dw      0, 0ffffh       ; reboot
noDEL:
        test    cl, LastE0
        jnz     short noRSUp    ; ignore fake shifts
        cmp     al, 2ah         ; left shift
        jne     short noLSDown
        or      dl, LShfDown
        jmp     short SetFlagsKey2
noLSDown:
        cmp     al, 2ah or 80h
        jne     short noLSUp
        and     dl, not LShfDown
        jmp     short SetFlagsKey2
noLSUp:
        cmp     al, 36h         ; right shift
        jne     short noRSDown
        or      dl, RShfDown
        jmp     short SetFlagsKey2
noRSDown:
        cmp     al, 36h or 80h
        jne     short noRSUP
        and     dl, not RShfDown
        jmp     short SetFlagsKey2
noRSUp:
        cmp     al, 38h         ; ALT
        jne     short noALTDown
        test    cl, LastE0
        jz      short LALTDn
        or      cl, RAltDown
        or      dl, AltDown
        jmp     short SetFlagsKey2
LALTDn:
        or      dx, (LAltDown shl 8) or AltDown
        jmp     short SetFlagsKey2
noALTDown:
        cmp     al, 38h or 80h
        jne     short noALTUp
        test    cl, LastE0
        jz      short LALTUp
        and     cl, not RAltDown
        and     dl, not AltDown
        jmp     short ALTup
LALTUp:
        and     dx, not ((LAltDown shl 8) or AltDown)
ALTUp:
        xor     ax, ax
        xchg    al, AltKpd
        test    al, al
        jz      short SetFlagsKey2     
        jmp     pushKey
noALTUp:
        cmp     al, 1dh         ; CTL
        jne     short noCTLDown
        test    cl, lastE0
        jz      short LCTLDn
        or      cl, RCtrDown
        or      dl, CtrlDown
SetFlagsKey2:        
        jmp     short SetFlagsKey1
LCTLDn:
        or      dx, (LCtrDown shl 8) or CtrlDown
        jmp     short SetFlagsKey1
noCTLDown:
        cmp     al, 1dh or 80h
        jne     short noCTLUp
        test    cl, LastE0
        jz      short LCTLUp
        and     cl, not RCtrDown
        and     dl, not CtrlDown
        jmp     short SetFlagsKey1
LCTLUp:
        and     dx,  not ((LCtrDown shl 8) or CtrlDown)
        jmp     short SetFlagsKey1
noCTLUp:
        mov     bx, 3a00h + CapsLock
        call    KeyLock
        jnc     short SetFlagsKey1
        
        mov     bx, 4600h + ScrLock
        push    dx          ; save ScrLock state bit (dl)
        call    KeyLock
        pop     bx          ; restore ScrLock state bit (bl)
        jc      short noScrLock
        test    dl, CtrlDown
        jz      short SetFlagsKey1; no break, just ScollLock
        mov     dl, bl      ; restore ScrLock flag
        test    bh, ScrLockDown
        jnz     short SetFlagsKey1 
        mov     byte ptr CtrlBreak, 80h   ; CTRL+BREAK flag
        mov     ax, Buffer
        mov     HeadPtr, ax
        mov     TailPtr, ax
        int     1bh
        xor     ax, ax
        jmp     pushkey
noScrLock:        
        test    cl, LastE0  ; INS
        jnz     short testINS
        test    dl, RShfDown or LShfDown
        jnz     short testINS
        test    dl, NumLock
        jnz     short NoIns      
testINS:
        mov     bx, 5200h + Insert
        call    KeyLock  
noIns:
        mov     bx, 4500h + NumLock
        push    dx          ; save NumLock state bit (dl)
        call    KeyLock
        pop     bx          ; restore NumLock state bit (bl)
        jc      short NormalKey   ; CTRL+NumLock = Pause
        test    dl, CtrlDown
        jz      short SetFlagsKey1
        mov     dl, bl      ; restore NumLock flag
        or      dh, Pause   ; set Pause bit
SetFlagsKey1:
        jmp     SetFlagsKey
E0Key:
        mov     di, offset E0KeyList
        push    cx
        mov     cx, E0KeyIndex - E0KeyList
        cld
        push    cs
        pop     es
        repne   scasb
        pop     cx
        jne     short SetFlagsKey
        mov     al, es:[di + E0KeyIndex - E0KeyList - 1]
        jmp     short KeyDown
NormalKey:
        test    al, 80h
        jnz     short SetFlagsKey ; key up
        test    cl, LastE0
        jnz     short E0Key
        cmp     al, 59h
        sbb     ah, ah
        and     al, ah
        mov     bx, offset KeyIndex
        xlat    cs:[bx]
KeyDown:
        xor     bx, bx 
        test    dl, RShfDown or LShfDown
        jz      short noShift
        mov     bl, 2
noShift:
        cmp     al, 26
        ja      short noCaps
        test    dl, CapsLock
        jz      short noNum
        xor     bl, 2
        jmp     short noNum 
noCaps:
        cmp     al, 37
        ja      short noNum
        test    dl, NumLock
        jnz     short NumDown
        mov     bl, 2
NumDown:
        xor     bl, 2
noNum:        
        test    dl, CtrlDown
        jz      short noCtrl
        mov     bl, 4
noCtrl:
        test    dl, AltDown
        jz      short noAlt
        mov     bl, 6
noAlt:
        cbw
        push    cx
        mov     cl, 3        
        shl     ax, cl
        pop     cx
        add     bx, ax
        mov     ax, cs:KeyCode[bx]
        cmp     ax, 000ah
        ja      short pushKey
        dec     ax
        js      short SetFlagsKey     ; ax was 0
        mov     ah, AltKpd
        aad
        mov     AltKpd, al
        jmp     short SetFlagsKey
pushKey:                
        push    cx
        mov     cx, ax
        mov     ah, 5
        int     16h
        pop     cx
        and     dh, not Pause    ; clear Pause bit
SetFlagsKey:
        and     cl, not (LastE0 or LastE1)    ; not prefix key code, clear all prefixes
SetFlags:
        mov     al, dl
        push    cx
        mov     cl, 4
        shr     al, cl
        pop     cx
        xor     al, ch
        and     al, 7
        jz      short SF1   ; no LEDs to update 
        test    ch, SetRepeat or AckReceived or LEDUpdate
        jnz     short SF1   ; can not update LEDS, so just write the flags and exit
        or      al, LEDUpdate
        xor     ch, al      ; insert the LEDs in KbdFlags4
        mov     ah, 0edh    ; set LED
        mov     bl, 0

        call    sendps2byte
SF1:        
        mov     KbdFlags1, dx
        mov     KbdFlags3, cx
        
int09Exit:
	mov     al, 20h
	out     20h, al
	pop     es
	pop     ds
    
    pop    ss
    pop    es
    pop    ds
    pop    dx
    pop    cx
    pop    bx
    pop    ax
    
	iret
int09 endp

ELSE    ; SCANCODE2

int09 proc near
        pusha
        push    ds
        push    es
        push    40h
        pop     ds
        in      al, 60h         ; al contains the scan code
        mov     dx, KbdFlags1
        mov     cx, KbdFlags3
        cmp     al, 0fah        ; ACK
        jne     short noACK
; ------------ manage ACK response
        test    ch, LEDUpdate
        jz      short ToggleACK ; no LED update
        test    ch, AckReceived
        jnz     short SecondACK ; second ACK received
        mov     ah, ch          ; LED update command sent, ACK received, need to send second byte
        and     ah, ScrLockLED or NumLockLED or CapsLockLED
        mov     bl, 0
        call    sendps2byte
        jmp     short ToggleACK
SecondACK:        
        xor     ch, LEDUpdate   ; second ACK, clear LED update bit
ToggleACK:
        xor     ch, AckReceived ; toggle ACK bit 
SetFlags1:                                  
        jmp     SetFlags               
        
; ------------ no ACK
noACK:
        cmp     al, 0e0h
        jne     short noE0
        or      cl, LastE0
        jmp     short SetFlags1
noE0:
        cmp     al, 0e1h
        jne     short noE1
        or      cl, LastE1
        jmp     short SetFlags1
noE1:   
        cmp     al, 0f0h
        jne     short noF0
        or      cl, LastF0
        jmp     short SetFlags1
noF0:   
        cmp     al, 71h     ; is DEL?
        jne     short noDEL
        mov     ah, dl
        and     ah, CtrlDown or AltDown
        cmp     ah, CtrlDown or AltDown
        je      short noF01
NormalKey1:        
        jmp     NormalKey
noF01:        
        mov     word ptr ds:[72h], 1234h    ; warm boot flag
        db      0eah
        dw      0, 0ffffh       ; reboot
noDEL:
        cmp     al, 83h         ; is F7
        je      short NormalKey1
        ja      short SetFlags1
        test    cl, LastF0      ; key up?
        jz      short noKeyUp
        or      al, 80h         ; key up flag
noKeyUp:
        test    cl, LastE0
        jnz     short noRSUp    ; ignore fake shifts      
        cmp     al, 12h         ; left shift
        jne     short noLSDown
        or      dl, LShfDown
        jmp     short SetFlagsKey2
noLSDown:
        cmp     al, 12h or 80h
        jne     short noLSUp
        and     dl, not LShfDown
        jmp     short SetFlagsKey2
noLSUp:
        cmp     al, 59h         ; right shift
        jne     short noRSDown
        or      dl, RShfDown
        jmp     short SetFlagsKey2
noRSDown:
        cmp     al, 59h or 80h
        jne     short noRSUP
        and     dl, not RShfDown
        jmp     short SetFlagsKey2
noRSUp:
        cmp     al, 11h         ; ALT
        jne     short noALTDown
        test    cl, LastE0
        jz      short LALTDn
        or      cl, RAltDown
        or      dl, AltDown
        jmp     short SetFlagsKey2
LALTDn:
        or      dx, (LAltDown shl 8) or AltDown
        jmp     short SetFlagsKey2
noALTDown:
        cmp     al, 11h or 80h
        jne     short noALTUp
        test    cl, LastE0
        jz      short LALTUp
        and     cl, not RAltDown
        and     dl, not AltDown
        jmp     short ALTup
LALTUp:
        and     dx, not ((LAltDown shl 8) or AltDown)
ALTUp:
        xor     ax, ax
        xchg    al, AltKpd
        test    al, al
        jz      short SetFlagsKey2     
        jmp     pushKey
noALTUp:
        cmp     al, 14h         ; CTL
        jne     short noCTLDown
        test    cl, lastE0
        jz      short LCTLDn
        or      cl, RCtrDown
        or      dl, CtrlDown
SetFlagsKey2:        
        jmp     short SetFlagsKey1
LCTLDn:
        or      dx, (LCtrDown shl 8) or CtrlDown
        jmp     short SetFlagsKey1
noCTLDown:
        cmp     al, 14h or 80h
        jne     short noCTLUp
        test    cl, LastE0
        jz      short LCTLUp
        and     cl, not RCtrDown
        and     dl, not CtrlDown
        jmp     short SetFlagsKey1
LCTLUp:
        and     dx,  not ((LCtrDown shl 8) or CtrlDown)
        jmp     short SetFlagsKey1
noCTLUp:
        mov     bx, 5800h + CapsLock
        call    KeyLock
        jnc     short SetFlagsKey1
        
        mov     bx, 7e00h + ScrLock
        push    dx          ; save ScrLock state bit (dl)
        call    KeyLock
        pop     bx          ; restore ScrLock state bit (bl)
        jc      short noScrLock
        test    dl, CtrlDown
        jz      short SetFlagsKey1; no break, just ScollLock
        mov     dl, bl      ; restore ScrLock flag
        test    bh, ScrLockDown
        jnz     short SetFlagsKey1 
        mov     byte ptr CtrlBreak, 80h   ; CTRL+BREAK flag
        mov     ax, Buffer
        mov     HeadPtr, ax
        mov     TailPtr, ax
        int     1bh
        xor     ax, ax
        jmp     pushkey
noScrLock:        
        test    cl, LastE0  ; INS
        jnz     short testINS
        test    dl, RShfDown or LShfDown
        jnz     short testINS
        test    dl, NumLock
        jnz     short NoIns      
testINS:
        mov     bx, 7000h + Insert
        call    KeyLock  
noIns:
        mov     bx, 7700h + NumLock
        push    dx          ; save NumLock state bit (dl)
        call    KeyLock
        pop     bx          ; restore NumLock state bit (bl)
        jc      short noPause
        test    dl, CtrlDown
        jz      short SetFlagsKey1
        mov     dl, bl      ; restore NumLock flag
        or      dh, Pause   ; set Pause bit
SetFlagsKey1:
        jmp     SetFlagsKey
E0Key:
        mov     di, offset E0KeyList
        push    cx
        mov     cx, E0KeyIndex - E0KeyList
        cld
        push    cs
        pop     es
        repne   scasb
        pop     cx
        jne     short SetFlagsKey
        mov     al, es:[di + E0KeyIndex - E0KeyList - 1]
        jmp     short KeyDown
noPause:
        and     al, 07fh    ; delete up bit
NormalKey:
        test    cl, LastF0
        jnz     short SetFlagsKey ; key up
        test    cl, LastE0
        jnz     short E0Key
        mov     bx, offset KeyIndex
        xlat    cs:[bx]
KeyDown:
        xor     bx, bx 
        test    dl, RShfDown or LShfDown
        jz      short noShift
        mov     bl, 2
noShift:
        cmp     al, 26
        ja      short noCaps
        test    dl, CapsLock
        jz      short noNum
        xor     bl, 2
        jmp     short noNum 
noCaps:
        cmp     al, 37
        ja      short noNum
        test    dl, NumLock
        jnz     short NumDown
        mov     bl, 2
NumDown:
        xor     bl, 2
noNum:        
        test    dl, CtrlDown
        jz      short noCtrl
        mov     bl, 4
noCtrl:
        test    dl, AltDown
        jz      short noAlt
        mov     bl, 6
noAlt:
        cbw
        shl     ax, 3
        add     bx, ax
        mov     ax, cs:KeyCode[bx]
        cmp     ax, 000ah
        ja      short pushKey
        dec     ax
        js      short SetFlagsKey     ; ax was 0
        mov     ah, AltKpd
        aad
        mov     AltKpd, al
        jmp     short SetFlagsKey
pushKey:                
        push    cx
        mov     cx, ax
        mov     al, ah      ; scan code
        mov     ah,4fh
        stc
        int     15h
        jnc     nopush
        mov     ah, 5
        int     16h
nopush:        
        pop     cx
        and     dh, not Pause    ; clear Pause bit
SetFlagsKey:
        and     cl, not (LastE0 or LastE1 or LastF0)    ; not prefix key code, clear all prefixes
SetFlags:
        mov     al, dl
        shr     al, 4
        xor     al, ch
        and     al, 7
        jz      short SF1   ; no LEDs to update
        test    ch, SetRepeat or AckReceived or LEDUpdate
        jnz     short SF1   ; can not update LEDS, so just write the flags and exit
        or      al, LEDUpdate
        xor     ch, al      ; insert the LEDs in KbdFlags4
        mov     ah, 0edh    ; set LED
        mov     bl, 0
        call    sendps2byte
SF1:        
        mov     KbdFlags1, dx
        mov     KbdFlags3, cx
        
int09Exit:
	mov     al, 20h
	out     20h, al
        pop     es
        pop     ds
        popa
        iret
int09 endp

ENDIF

KeyLock proc near   ; input: BH = expected scan code, al = scan code, BL = key lock flag. Returns CF=1 to continue, CF=0 to exit
        xor     bh, al
        jnz     short s2
        mov     ah, dh
        or      dh, bl      ; set flag
        xor     ah, dh      ; get flag difference
        xor     dl, ah      ; toggle only if key was not already down
        ret
s2:     cmp     bh, 80h
        stc
        jne     short exit11
        xor     dh, bl      ; key up
exit11:
        ret
KeyLock endp

; --------------------- INT 10h - Video ----------------
biosdseg            equ	0040h
video_mode          equ 49h	; byte - active video mode number
video_columns       equ 4Ah	; word - number of text columns for active mode
video_page_size     equ 4Ch	; word - size of video page in bytes
video_page_offt     equ 4Eh	; word - offset of the active video page
video_cur_pos       equ 50h	; byte[16] - cursor position for each page
video_cur_shape     equ 60h	; word - cursor shape
video_page          equ 62h	; byte - active video page
video_port          equ 63h	; word - I/O port for the display adapter
video_mode_reg      equ 65h	; byte - video adapter mode register
video_palet_reg     equ 66h	; byte - color palette


;-------------------------------------------------------------------------
; CRTC registers
crtc_cur_start      equ 0Ah ; CRTC cursor start line register
crtc_cur_end        equ	0Bh ; CRTC cursor end line register
crtc_offset_hi      equ	0Ch ; CRTC start address high register
crtc_offset_lo      equ	0Dh ; CRTC start address low register
crtc_cur_pos_hi     equ	0Eh ; CRCT cursor location high register
crtc_cur_pos_lo     equ	0Fh ; CRTC cursor location low register
crtc_pen_hi         equ 10h ; CRTC light pen position high byte
crtc_pen_lo         equ 11h ; CRTC light pen position low byte

;-------------------------------------------------------------------------
; control characters
bel                 equ 07h
bs                  equ 08h
lf                  equ 0Ah
cr                  equ 0Dh



int_10_dispatch:
	dw	int_10_fn00		; Set video mode
	dw	int_10_fn01		; Set text mode cursor shape
	dw	int_10_fn02		; Set cursor position
	dw	int_10_fn03		; Get cursor position and shape
	dw	int_10_fn04		; Read light pen position
	dw	int_10_fn05		; Set active display page
	dw	int_10_fn06		; Scroll up window
	dw	int_10_fn07		; Scroll down window
	dw	int_10_fn08		; Read character and attribute
	dw	int_10_fn09		; Write character and attribute
	dw	int_10_fn0A		; Write character only
	dw	int_10_fn0B		; Set background color or palette
	dw	int_10_fn0C		; Write graphics pixel
	dw	int_10_fn0D		; Read graphics pixel
	dw	int_10_fn0E		; Teletype output
	dw	int_10_fn0F		; Get current video mode
int_10_num_func	equ ($-int_10_dispatch)/2

;-------------------------------------------------------------------------
; offsets for registers on stack

int_10_ax	equ	0
int_10_al	equ	int_10_ax
int_10_ah	equ	int_10_ax+1
int_10_bx	equ	int_10_ax+2
int_10_bl	equ	int_10_bx
int_10_bh	equ	int_10_bx+1
int_10_cx	equ	int_10_bx+2
int_10_ch	equ	int_10_cx+1
int_10_dx	equ	int_10_cx+2

;=========================================================================
; int_1D - Video parameters tables
; Contains values loaded to MC6845 CRTC registers 00h to 0Fh during
; video mode initialization
;-------------------------------------------------------------------------
	
;=========================================================================
; int_10 - BIOS video services
; Input:
;	AH - Function
;		00h - Set video mode
;		01h - Set text mode cursor shape
;		02h - Set cursor position
;		03h - Get cursor position and shape
;		04h - Read light pen position
;		05h - Select active display page
;		06h - Scroll up window
;		07h - Scroll down window
;		08h - Read character and attribute at cursor position
;		09h - Write character and attribute at cursor position
;		0Ah - Write character only at cursor position
;		0Bh -
;			BH = 00h - Set background/border color
;			BH = 01h - Set palette
;		0Ch - Write graphics pixel
;		0Dh - Read graphics pixel
;		0Eh - Teletype output
;		0Fh - Get current video mode
;-------------------------------------------------------------------------
	
int10 proc near
	sti
	cld				;  ...strings auto-increment
	push	bp
	push	es
	push	ds
	push	si
	push	di
	push	dx
	push	cx
	push	bx
	push	ax
	mov	bx,biosdseg
	mov	ds,bx
	mov	bl,ds:byte ptr [video_mode]
	cmp	bl,07h			; check for monochrome mode
	mov	bx,0B800h		; assume CGA, BX = CGA video segment
	jb	.color			; it is CGA    
	mov	bh,0B0h			; else MDA, BX = MDA video segment

.color:
	mov	es,bx			; load video segment to ES
	mov	bp,sp			;  ...start of stack frame
	cmp	ah,int_10_num_func	; dispatch table size
	jae	.exit_1			; invalid function
	mov	bh,0
	mov	bl,ah
	shl	bx,1
    call	cs:[int_10_dispatch+bx]

.exit_1:
	pop	ax
	pop	bx
	pop	cx
	pop	dx
	pop	di
	pop	si
	pop	ds
	pop	es
	pop	bp
	iret

;=========================================================================
; int_10_fn00 - Set video mode
; Input:
;	AH = 00h
;	AL = video mode
;		00h - CGA - text 40x25, 16 shades of gray
;		01h - CGA - text 40x25, 16 colors
;		02h - CGA - text 80x25, 16 shades of gray
;		03h - CGA - text 80x25, 16 colors
;		04h - CGA - graphics 320x200, 4 colors
;		05h - CGA - graphics 320x200, 4 shades of gray
;		06h - CGA - graphics 640x200, monochrome
;		07h - MDA - text 80x25, monochrome
;-------------------------------------------------------------------------
int_10_fn00:
	mov	bl,byte ptr [bp]+int_10_al	; BL = video mode
                        ; assume CGA mode
	mov	cx,0B800h		; CGA video memory segment
	mov	dx,3D4h			; port for MC6845 CRTC address register
	mov	al,0
	cmp	bl,07h
	jb	.color_1			; jump if CGA/color mode
                        ; set MDA mode
	mov	ch,0B0h			; MDA video memory segment
	mov	dl,0B4h 		; port for MC6845 CRTC address register
	inc	al

.color_1:
	mov	es,cx			; ES = video memory segment
	mov ds:word ptr [video_port],dx	; Save current CRTC display port
	add	dl,4
	out	dx,al			; Reset the video    
	mov	ds:byte ptr [video_mode],bl	; Save current CRTC mode
	mov	bh,0
	push	bx
	push	es
	xor	ax,ax
	mov	es,ax			; Load interrupt table segment to ES
    les	si,es:[1Dh*4]		; Load video parameters table
					; (INT 1Dh vector) to ES:SI
    mov	bl,byte ptr cs:[bx+TABMUL]	; Get BL for indexing into int_1D
	add	si,bx

    mov	cx,es:word ptr [si+crtc_cur_start] ; cursor shape from INT 1Dh table
	xchg	cl,ch			; convert to LSB format
	mov	ds:word ptr [video_cur_shape],cx ; store cursor shape

	mov	cx,10h			; Sixteen values to send

.setup_crt_loop:
    mov	al,es:byte ptr [si]		; Value to send in SI
	call	vid_crtc_writeb			;  ...send it
	inc	ah			;  ...bump count
	inc	si			;  ...point to next
	loop	.setup_crt_loop		;  ...loop until done
	pop	es
	xor	di,di
	mov	cx,2000h		; video memory size for CGA
	xor	ax,ax			; fill word for graphics mode
	call	vid_check_mode		; Set flags according to mode
	jc	.clear_screen		; jump if graphics mode
	jnz	.text_fill_1		; jump if CGA mode
	mov	cx,0800h 		; video memory size for MDA

.text_fill_1:	
    mov	ax,720h	

.clear_screen:
	repz	stosw			; clear screen with fill word

	mov	dx,ds:word ptr [video_port]	; Get the port
	add	dl,4
	pop	bx
    mov	al,byte ptr cs:[bx+MODES]	; Load data to set for mode
	out	dx,al			;  ...and send it
	mov	ds:byte ptr [video_mode_reg],al ;  ...then save active data
	inc	dx
	mov	al,30h			; Assume not 640 x 200 b/w
	cmp	bl,6			;  ...correct?
	jnz	.set_palette
	mov	al,3Fh			; Palette for 640 x 200 b/w

.set_palette:
	mov	ds:byte ptr [video_palet_reg],al ;  ...save palette
	out	dx,al			;  ...send palette

	mov	ax,ds
	mov	es,ax
	xor	ax,ax
	mov	ds:byte ptr [video_page],al	;  ...active page=page 0
	mov	cx,9			; video_page_offt + video_cur_pos * 8
	mov	di,video_page_offt
 	rep	stosw			; zero page offset and cursor position

    mov	al,cs:byte ptr [bx+columns]	; Get display width
	mov	ds:word ptr [video_columns],ax	;  ...save it
	and	bl,0FEh			; Clear the LSB to get an index
					; to 16-bit word page_size table
					; FIXME: It returns graphics mode page
					; size for mode 7. Probably not
					; critical, as MDA has only one page
    mov	ax,word ptr cs:[bx+page_size]	; Get video page size
	mov	ds:word ptr [video_page_size],ax ;  ...save it
	ret


;=========================================================================
; int_10_fn01 - Set text-mode cursor shape
; Input:
;	AH = 01h
;	CH = cursor scan line start
;	CL = cursor scan line end
; Output:
;	none
;-------------------------------------------------------------------------
int_10_fn01:
	mov	ds:word ptr [video_cur_shape],cx ; save cursor shape to BIOS data area
	mov	ah,crtc_cur_start	; select CRTC cursor shape registers
	call	vid_crtc_writew		; write it to CRTC
	ret

;=========================================================================
; int_10_fn02 - Set cursor position
; Input:
;	AH = 02h
;	BH = page number
;	DH = cursor row (00h is top)
;	DL = cursor column (00h is left)
; Output:
;	none
;-------------------------------------------------------------------------
int_10_fn02:
	mov	bl,byte ptr [bp]+int_10_bh	; BL = page number
	cmp	ds:byte ptr [video_page],bl	; is it on current page?
	jne	bios_set_cur_pos	; if not visible only update BIOS data

;=========================================================================
; set_cur_pos - set CRTC cursor position, update BIOS cursor location
;	BL = page
;	DH = cursor row (00h is top)
;	DL = cursor column (00h is left)
;-------------------------------------------------------------------------
set_cur_pos:
	mov	ax,dx			; AX = cursor position
	call	vid_position_to_offset			; AX - offset
	add	ax,word ptr ds:[video_page_offt]	;  + byte offset, regen reg.
	shr	ax,1
	mov	cx,ax
	mov	ah,crtc_cur_pos_hi	; CRCT cursor location high register
	call	vid_crtc_writew		; send cursor position to CRTC
bios_set_cur_pos:
	mov	bh,0
	shl	bl,1			; index to words table
	mov	word ptr [bx+video_cur_pos],dx ; save position to BIOS data area
	ret

;=========================================================================
; int_10_fn03 - Get cursor position and shape
; Input:
;	AH = 03h
;	BH = page number
; Output:
;	CH = cursor start scan line
;	CL = cursor end scan line
;	DH = cursor row (00h is top)
;	DL = cursor column (00h is left)
;-------------------------------------------------------------------------
int_10_fn03:
	mov	bh,0
	mov	bl,byte ptr [bp]+int_10_bh	; BL = page number
	shl	bl,1
	mov	ax,word ptr [bx+video_cur_pos] ; get current cursor position
	mov	word ptr [bp]+int_10_dx,ax	; return position in DX
	mov	ax,ds:word ptr [video_cur_shape]  ; get cursor shape
	mov	word ptr [bp]+int_10_cx,ax	; return cursor shape in CX
	ret

;=========================================================================
; int_10_fn04 - Read light pen position
; Input:
;	AH = 04h
; Output:
;	AH - light pen trigger flag
;		00h not down/triggered
;		01h down/triggered
;	If light pen is triggered:
;		DH = character row
;		DL = character column
;		CH = pixel row
;		BX = pixel column
;-------------------------------------------------------------------------
int_10_fn04:
	mov	byte ptr [bp]+int_10_ah,0	; set AH = 0, light pen not triggered
	mov	dx,ds:word ptr [video_port]
	add	dl,6			; CRTC status register
	in	al,dx			; read it
	test	al,4			; test light pen switch bit
	jz	.reset_pen		; reset pen and return if switch is off
	test	al,2			; test light pen tigger bit
	jnz	.read_pen		; continue if triggered
	ret				; not triggered - return

.read_pen:
	mov	dx,ds:word ptr [video_port]	; CRTC index register
	mov	al,crtc_pen_hi		; CRTC pen position high byte register
	out	dx,al			; select it
	inc	dx			; CRTC data register
	in	al,dx			; read high byte of pen position
	mov	ah,al
	dec	dx			; CRTC index register
	mov	al,crtc_pen_lo		; CRTC pen position low byte register
	out	dx,al			; select it
	inc	dx			; CRTC data register
	in	al,dx			; read low byte of pen position

	mov	bh,0
	mov	bl,ds:byte ptr [video_mode]	; get current video mode
    mov	bl,cs:byte ptr [bx+.correction] ; light pen correction factor
	sub	ax,bx
	jns	.1
	xor	ax,ax			; set to zero if negative result

.1:
	call	vid_check_mode			; check video mode
	jnc	.text			; calculate character position if text
	mov	dl,40			; divide by 40
	div	dl			; AL = row, AH = column (reminder)
	mov	bh,0
	mov	bl,ah
	mov	cl,3
	shl	bx,cl			; BX = AH * 8 - pixel column
	mov	ch,al
	shl	ch,1			; CH = AL * 2 - pixel row
	mov	dl,ah			; DL = AH - character column
	mov	dh,al
	shr	dh,1
	shr	dh,1			; DH = AL / 4 - character row
	cmp	ds:byte ptr [video_mode],6	; check for 640x200 mode
	jnz	.exit_3
	shl	bx,1			; adjust pixel column (double it)
	shl	dl,1			; same or character column
	jmp	.exit_3

.text:
	div	ds:byte ptr [video_columns] 	; divide by number of columns
	xchg	al,ah			; AL = column, AH = row
	mov	dx,ax			; save characer row,column to DH,AL
	mov	cl,3
	shl	ah,cl
	mov	ch,ah			; CH = AH * 8 - pixel row
	mov	bh,0
	mov	bl,al
	shl	bx,cl			; BX = AL * 8 - pixel column

.exit_3:
	mov	byte ptr [bp]+int_10_ah,1	; set AH = 1, light pen triggered
	mov	word ptr [bp]+int_10_dx,dx	;  ...row, column in user dx
	mov	word ptr [bp]+int_10_bx,bx	;  ...pixel column in user bx
	mov	byte ptr [bp]+int_10_ch,ch	;  ...raster line in user ch

.reset_pen:
	mov	dx,ds:word ptr [video_port]	; Get port of active CRTC card
	add	dl,7			; clear light pen strobe reg
	out	dx,al			; reset it
	ret

.correction:
	db	3, 3, 5, 5, 3, 3, 3, 4	; light pen correction

;=========================================================================
; int_10_fn05 - Select active display page
; Input:
;	AH = 05h
;	AL - new page number (00h is the first page)
; Output:
;	none
;-------------------------------------------------------------------------
int_10_fn05:
	mov	ds:byte ptr [video_page],al	; update page number in BIOS data area
	mov	bl,al			; also copy it to BL
	mov	ah,0
	mul	ds:word ptr [video_page_size]	; calculate page offset
	mov	ds:word ptr [video_page_offt],ax ; save the offset
	shr	ax,1			; calculate CRTC page start address
	mov	cx,ax			; save a copy to CX
	mov	ah,crtc_offset_hi	; CRTC start address high register
	call	vid_crtc_writew		; write new offset to CRTC

	mov	bh,0
	shl	bx,1
	mov	ax,word ptr [bx+video_cur_pos] ; AX - cursor position for new page
	call	vid_position_to_offset			; AX - offset relative to start of page
	shr	ax,1
	add	cx,ax			; add to the page offset
	mov	ah,crtc_cur_pos_hi	; CRCT cursor location high register
	call	vid_crtc_writew		; send cursor position to CRTC
	ret

;=========================================================================
; int_10_fn06 - scroll up window
; int_10_fn07 - scroll down window
; Input:
;	AH = 06h (scroll up) or AH = 07 (scroll down)
;	AL = number of rows by which to scroll up (00h = clear entire window)
;	BH = attribute used to write blank rows at bottom of window
;	CH,CL = row,column of window's upper left corner
;	DH,DL = row,column of window's lower right corner
; Output:
;	none
; TODO:
;	optimize graphics fill
;-------------------------------------------------------------------------
int_10_fn06:
int_10_fn07:
	call	vid_check_mode
	jc	.graphics_scroll

	xor	si,si			; SI - "snow" workaround not required
	cmp	ds:byte ptr [video_mode],2
	jb	.no_snow
	cmp	ds:byte ptr [video_mode],3
	ja	.no_snow
	mov	si,0101010101010101b	; CGA "snow" workaround required
;	mov	si,0001000100010001b	; CGA "snow" workaround required
.no_snow:
	mov	ax,word ptr [bp]+int_10_dx	; AX = window's lower right corner
	push	ax
	cmp	byte ptr [bp]+int_10_ah,07h	; check for scroll down function
	jz	.11			; jump if scroll down
	mov	ax,word ptr [bp]+int_10_cx	; AX = window's upper left corner

.11:
	call	vid_position_to_offset
	add	ax,ds:word ptr [video_page_offt]
	mov	di,ax			; DI = scroll copy destination address

; calculate scroll window size (DX)

	pop	dx			; DX = window's lower right corner
	sub	dx,word ptr [bp]+int_10_cx	; substract windows's upper left corner
	add	dx,101h 		; add 1x1

; calculate offset between the source and the destination (AX)

	mov	bx,ds:word ptr [video_columns]	; BX = columns (note BX <= 80)
	shl	bx,1			; each character takes two bytes
	mov	al,byte ptr [bp]+int_10_al	; AL = number of rows to scroll
	push    dx
    mov     ah,0
    mul     bx
    pop     dx

	sub	bl,dl			; BX = distance between end of one
	sub	bl,dl			;   row and beggining of another
	push	ds
	mov	cx,es
	mov	ds,cx			; load video segment to DS
	cmp	byte ptr [bp]+int_10_ah,06h	; check for scroll up function
	jz	.2			; jump if scroll up
	neg	ax			; negate offset
	neg	bx			; negate distance
	std				; copy backwards

.2:
	mov	cl,byte ptr [bp]+int_10_al	; CL = number of rows to scroll
	or	cl,cl
	jz	.text_fill_only		; jump if clear window only requested
	xchg	ax,si			; AX = snow workaround flag, SI = offset
	add	si,di			; SI = scroll copy source address
	sub	dh,cl			; DH = number of rows to copy

	or	bx,bx
	jz	.text_full_row_scroll

.text_scroll_loop:
	mov	ch,0
	mov	cl,dl			; CX = characters in row to copy

	ror	ax,1			; rotate snow workaround flag
	jnc	.text_scroll_no_retrace
	call	.retrace_wait

.text_scroll_no_retrace:
	repz	movsw			; copy one row

;.text_scroll_next_row:
	add	si,bx			; SI = next row to copy source address
	add	di,bx			; DI = next row to copy destination
	dec	dh			; decrement row counter
	jnz	.text_scroll_loop	; jump if there is more rows to copy

.text_fill:
	mov	dh,byte ptr [bp]+int_10_al	; DH = number of rows to fill
	mov	si,ax			; SI = snow workaround flag

.text_fill_only:
	mov	ch,0
	mov	ah,byte ptr [bp]+int_10_bh	; AH = blank attribute
	mov	al,' '			; AL = blank character

.text_fill_loop:
	mov	cl,dl			; CX = characters in row to fill
	ror	si,1			; rotate snow workaround flag
	jnc	.text_fill_no_retrace	; jump if LSB was zero - no wait
	call	.retrace_wait		; wait for vertical retrace

.text_fill_no_retrace:
	repz	stosw			; fill one row
	add	di,bx			; DI = next row to fill destination
	dec	dh			; decrement row counter
	jnz	.text_fill_loop		; jump if there is more rows to fill

	pop	ds
	ret

.text_full_row_scroll:
	or	ax,ax
	jz	.text_full_row_no_snow
	push	ax
	mov	al,dl
	mul	dh

.text_full_row_loop:
	mov	cx,240
	cmp	ax,cx
	ja	.copy_chunk
	xchg	ax,cx
	xor	ax,ax
	jmp	.do_copy

.copy_chunk:
	sub	ax,cx

.do_copy:
	call	.retrace_wait
	rep	movsw
	or	ax,ax
	jnz	.text_full_row_loop
	pop	ax
	jmp	.text_fill

.text_full_row_no_snow:
	push	ax
	mov	al,dl
	mul	dh
	mov	cx,ax
	rep	movsw
	pop	ax
	jmp	.text_fill

;-------------------------------------------------------------------------
; .retrace_wait - next till the next vertical retrace

.retrace_wait:
	push	ax
	push	dx
	mov	dx,03DAh		; DX = CGA status register

.retrace_wait_not_set:
	in	al,dx
	test	al,08h			; bit 3 set if vertical retrace
	jnz	.retrace_wait_not_set	; jump if retrace

.retrace_wait_set:
	in	al,dx
	test	al,08h			; bit 3 set if vertical retrace
	jz	.retrace_wait_set	; jump if no retrace
	pop	dx
	pop	ax

.retrace_exit:
	ret

;-------------------------------------------------------------------------
; .graphics_scroll - scroll for graphics modes

.graphics_scroll:
	mov	ax,word ptr [bp]+int_10_dx	; AX = window's lower right corner
	push	ax
	cmp	byte ptr [bp]+int_10_ah,07h ; check for scroll down function
	jz	.3			; jump if scroll down
	mov	ax,word ptr [bp]+int_10_cx	; AX = window's upper left corner

.3:
	call	vid_gfx_pos_to_offset	
	mov	di,ax			; DI = scroll copy destination address

; calculate scroll windows size (DX)

	pop	dx			; DX = window's lower right corner
	sub	dx,word ptr [bp]+int_10_cx	; substract window's upper left corner
	add	dx,101h 		; add 1x1
	shl	dh,1			; multiply by four: one character takes
	shl	dh,1			;   four bytes in each plane
	mov	al,byte ptr [bp]+int_10_ah	; AL = function
	cmp	ds:byte ptr [video_mode],06h	; check for 640x200 mode
	jz	.4			; jump if 640x200 mode
	shl	dl,1			; double character width for 320x200 
	shl	di,1			; double character width for 320x200
	cmp	al,07h			; check for scroll down function
	jnz	.5			; jump if scroll down
	inc	di			; scroll up - adjust source address

.4:
	cmp	al,07h			; check for scroll down function
	jnz	.5			; jump if not scroll down
	add	di,0F0h			; adjust destination address
					;   for copying backwards

.5:
	mov	bl,byte ptr [bp]+int_10_al	; BL = number of rows to scroll
	shl	bl,1			; multiply by four: one character takes
	shl	bl,1			;   four bytes in each plane
	push	bx
	sub	dh,bl			; DH = number of rows to copy
	mov	al,50h
	mul	bl
	mov	bx,1FB0h
	cmp	byte ptr [bp]+int_10_ah,06h	; check for scroll up function
	jz	.6			; jump if scroll up
	neg	ax			; negate offset for scroll down
	mov	bx,2050h
	std				; copy backwards

.6:
	mov	si,di
	add	si,ax			; SI = scroll copy source address
	pop	ax
	mov	cx,es
	mov	ds,cx			; load video segment to DS
	or	al,al
	jz	.graphics_fill		; jump if clear window only requested
	push	ax

.graphics_scroll_loop:
	mov	ch,0
	mov	cl,dl			; CX = bytes in row to copy
	push	si
	push	di
	repz	movsb			; copy one row in the first plane
	pop	di
	pop	si
	add	si,2000h		; point SI and DI to the second plane
	add	di,2000h
	mov	cl,dl			; CX = bytes in row to copy
	push	si
	push	di
	repz	movsb			; copy one row in the second plane
	pop	di
	pop	si
	sub	si,bx			; SI = next row to copy source address
	sub	di,bx			; DI = next row to copy destination
	dec	dh			; decrement row counter
	jnz	.graphics_scroll_loop	; jump if there is more rows to copy

	pop	ax
	mov	dh,al			; DH = number of rows to fill

.graphics_fill:
	mov	al,byte ptr [bp]+int_10_bh	; AL = fill color
	mov	ch,0

.graphics_fill_loop:
	mov	cl,dl			; CX = bytes in row to fill
	push	di
	repz	stosb			; fill one row in the first plane
	pop	di
	add	di,2000h		; point DI to the second plane
	mov	cl,dl			; CX = bytes in row to fill
	push	di
	repz	stosb			; fill one row in the second plane
	pop	di
	sub	di,bx
	dec	dh			; decrement row counter
	jnz	.graphics_fill_loop	; jumpif there is more rows to fill
	ret

;=========================================================================
; int_10_fn08 - Read character and attribute
; Input:
;	AH = 08h
; Output:
;	AL - character read
;	BH - video attribute (text modes only)
; int_10_fn09 - Write character and attribute
; Input:
;	AH = 09h
;	AL - character to write
;	BH - page number
;	BL - attribute (text modes) or color (graphics modes)
;	CX - number of times to write character
; Output:
;	none
; int_10_fn0A - Write character only
; Input:
;	AH = 0Ah
;	AL - character to write
;	BH - page number
;	CX - repeat count
; Output:
;	none
;-------------------------------------------------------------------------
int_10_fn08:
int_10_fn09:
int_10_fn0A:
	call	vid_check_mode
	jc	.graphics		; jump if graphics mode
	mov	bl,byte ptr [bp]+int_10_bh	; BL = page number
	mov	bh,0
	push	bx
	call	vid_current_offset
	mov	di,ax			; DI = character offset in the page
	pop	ax			; AX = page number
	mul	ds:word ptr [video_page_size] 	; AX = page number * page size
	add	di,ax			; DI = character offset
	mov	si,di			; SI = character offset
	mov	dx,ds:word ptr [video_port]	; DX = CRTC port
	add	dx,6			; DX = CGA status register
	push	ds
	mov	bx,es
	mov	ds,bx			; load video segment to DS
	mov	al,byte ptr [bp]+int_10_ah	; AL = function
	cmp	al,08h			; check for read character function
	jnz	.text_write		; jump if not read char (write char)

.read_retrace_wait:
	in	al,dx
	test	al,01h			; bit 0 set if horizontal retrace
	jnz	.read_retrace_wait	; jump if retrace
	cli

.read_no_retrace_wait:
	in	al,dx
	test	al,01h			; bit 0 set if horizontal retrace
	jz	.read_no_retrace_wait	; jump if no retrace

	lodsw				; read character and attribute
	sti
	pop	ds
	mov	word ptr [bp]+int_10_ax,ax	; return character and attribute in AX
	ret

.text_write:
	mov	bl,byte ptr [bp]+int_10_al	; BL = character to write
	mov	bh,byte ptr [bp]+int_10_bl	; BH = attribute to write
	mov	cx,word ptr [bp]+int_10_cx  ; CX = number of times to write char
	cmp	al,0Ah			; check for write char only function
	jz	.text_write_char_only	; jump if write char only

.write_char_retrace:
	in	al,dx
	test	al,08h			; bit 3 set if vertical retrace
	jnz	.do_write_char_attr	; retrace is in progress - write char

.write_retrace_wait1:
	in	al,dx
	test	al,01h			; bit 0 set if horizontal retrace
	jnz	.write_retrace_wait1	; jump if retrace
	cli

.write_no_retrace_wait1:
	in	al,dx
	test	al,01h			; bit 0 set if horizontal retrace
	jz	.write_no_retrace_wait1	; jump if no retrace

.do_write_char_attr:
	mov	ax,bx			; AX = character / attribute
	stosw				; write it to video memory
	sti
	loop	.write_char_retrace	; repeat CX times
	pop	ds
	ret

.text_write_char_only:
	in	al,dx
	test	al,08h			; bit 3 set if vertical retrace
	jnz	.do_write_char_only	; retrace is in progress - write char

.write_retrace_wait2:
	in	al,dx
	test	al,01h			; bit 0 set if horizontal retrace
	jnz	.write_retrace_wait2	; jump if retrace
	cli

.write_no_retrace_wait2:
	in	al,dx
	test	al,01h			; bit 0 set if horizontal retrace
	jz	.write_no_retrace_wait2	; jump if no retrace

.do_write_char_only:
	mov	al,bl			; AL = character to write
	stosb				; write it to video memory
	sti
	inc	di			; skip attribute
	loop	.text_write_char_only	; repeat CX times
	pop	ds
	ret

.graphics:
	cmp	byte ptr [bp]+int_10_ah,08h	; check for read character function
	jz	.graphics_read

	mov	ax,ds:word ptr [video_cur_pos]	; Get cursor position
	call	vid_gfx_pos_to_offset	;  ...convert (row,col) -> col
	mov	di,ax			; Save in displacement register
	push	ds
	mov	al,byte ptr [bp]+int_10_al	; Get character to write
	mov	ah,0
	or	al,al			; Is it user character set?
	js	.CG9_02			;  ...skip if so
	mov	dx,cs			; Else use ROM character set
	mov	si,gfx_font		; load graphics font offset    
	jmp	.CG9_03

.CG9_02:
	and	al,7Fh			; Origin to zero
	xor	bx,bx			;  ...then go load
	mov	ds,bx			;  ...user graphics
	lds	si,ds:[7Ch]		;  ...vector, offset in si
	mov	dx,ds			;  ...segment into dx

.CG9_03:
	pop	ds			; Restore data segment
	mov	cl,3			;  ...char 8 pixels wide
	shl	ax,cl
	add	si,ax			; Add regen. buffer base addr.
	mov	cx,word ptr [bp]+int_10_cx	;  ...load char. count
	cmp	ds:byte ptr [video_mode],6	; Is the mode 640 x 200 b/w?
	push	ds
	mov	ds,dx
	jz	.CG8_02			;  ...skip if so
	shl	di,1
	mov	al,byte ptr [bp]+int_10_bl	; Get character attribute
	and	ax,3
	mov	bx,5555h
	mul	bx
	mov	dx,ax
	mov	bl,byte ptr [bp]+int_10_bl	; Restore BL (character attribute)

.CG9_04:
	mov	bh,8			; Char 8 pixels wide
	push	di
	push	si

.CG9_05:
	lodsb				; Read the screen
	push	cx
	push	bx
	xor	bx,bx
	mov	cx,8

.CG9_06:
	shr	al,1			; Shift bits thru byte
	rcr	bx,1
	sar	bx,1
	loop	.CG9_06

	mov	ax,bx			; Result into ax
	pop	bx
	pop	cx
	and	ax,dx
	xchg	ah,al
	or	bl,bl
	jns	.CG9_07
    xor	ax,es:word ptr [di]

.CG9_07:
    mov	es:word ptr [di],ax		; Write new word
	xor	di,2000h
	test	di,2000h		; Is this other plane?
	jnz	.CG9_08			;  ...nope
	add	di,50h			; Else advance character

.CG9_08:
	dec	bh			; Show another char written
	jnz	.CG9_05			;  ...more to go
	pop	si
	pop	di
	inc	di
	inc	di
	loop	.CG9_04
	pop	ds
	ret

.CG8_02:
	mov	bl,byte ptr [bp]+int_10_bl	; Get display page
	mov	dx,2000h		;  ...size of graphics plane

.CG8_03:
	mov	bh,8			; Pixel count to write
	push	di
	push	si

.CG8_04:
	lodsb				; Read from one plane
	or	bl,bl			;  ...done both planes?
	jns	.CG8_05			;  ...skip if not
    	xor	al,es:byte ptr [di]		; Else load attribute

.CG8_05:
    	mov	es:byte ptr [di],al		; Write out attribute
	xor	di,dx			;  ...get other plane
	test	di,dx			; Done both planes?
	jnz	.CG8_06			;  ...skip if not
	add	di,50h			; Else position for now char

.CG8_06:
	dec	bh			; Show row of pixels read
	jnz	.CG8_04			;  ...not done all of them
	pop	si
	pop	di
	inc	di
	loop	.CG8_03
	pop	ds
	ret

.graphics_read:
	cld				; Increment upwards
	mov	ax,ds:word ptr [video_cur_pos]	;  ...get cursor position
	call	vid_gfx_pos_to_offset	; Convert (row,col) -> columns
	mov	si,ax			;  ...save in si
	sub	sp,8			; Grab 8 bytes temp storage
	mov	di,sp			;  ...save base in di
	cmp	ds:byte ptr [video_mode],6	; Mode 640 x 200 b/w?
	mov	ax,es
	push	ds
	push	di
	mov	ds,ax			; load video segment to DS
	jz	CGR_06			; Mode is 640 x 200 b/w - skip
	mov	dh,8			; Eight pixels high/char
	shl	si,1
	mov	bx,2000h		; Bytes per video plane

CGR_02:
	mov	ax,word ptr [si] 		; Read existing word
	xchg	ah,al
	mov	cx,0C000h		; Attributes to scan for
	mov	dl,0

CGR_03:
	test	ax,cx			; Look for attributes
	clc
	jz	CGR_04			;  ...set, skip
	stc				; Else show not set

CGR_04:
	rcl	dl,1
	shr	cx,1
	shr	cx,1
	jnb	CGR_03			;  ...more shifts to go
    mov	ss:byte ptr [di],dl
	inc	di
	xor	si,bx			; Do other video plane
	test	si,bx			;  ...done both planes?
	jnz	CGR_05			;  ...no, skip
	add	si,50h			; Else advance pointer

CGR_05:
	dec	dh			; Show another pixel row done
	jnz	CGR_02			;  ...more rows to do
	jmp	short	CGR_08

CGR_06:
	mov	dh,4			; Mode 640 x 200 b/w - special

CGR_07:
	mov	ah,byte ptr [si] 		; Read pixels from one plane
    mov	ss:byte ptr [di],ah		;  ...save on stack
	inc	di			;  ...advance
	mov	ah,byte ptr [si+2000h]	; Read pixels from other plane
    mov	ss:byte ptr [di],ah		; Save pixels on stack
	inc	di			;  ...advance
	add	si,50h			; Total pixels in char
	dec	dh			;  ...another row processed
	jnz	CGR_07			;  ...more to do

CGR_08:
	mov	dx,cs			; Load segment of graphics font 
	mov	di,gfx_font		;  ...and offset    
	mov	es,dx			;  ...save offset in es
	mov	dx,ss
	mov	ds,dx
	pop	si
	mov	al,0

CGR_09:
	mov	dx,80h			; Number of char. in graphics set

CGR_10:
	push	si
	push	di
	mov	cx,8			; Bytes to compare for char
	repz	cmpsb			;  ...do compare
	pop	di
	pop	si
	jz	CGR_11			; Found graphics character
	inc	al			;  ...else show another char
	add	di,8			;  ...advance one row
	dec	dx			;  ...one less char  to scan
	jnz	CGR_10			; Loop if more char left

	or	al,al			; User graphics character set?
	jz	CGR_11			;  ...no, not found
	xor	bx,bx			; 
	mov	ds,bx			; Load interrupt table segment to ES
	les	di,ds:[1Fh*4]		; Load user font for graphics 
					; (INT 1Fh vector) to ES:SI
	mov	bx,es
	or	bx,di
	jz	CGR_11			;  ...not found
	jmp	short	CGR_09		; Try using user graphics char

CGR_11:
	mov	byte ptr [bp]+int_10_al,al	; Return char in user al
	pop	ds
	add	sp,8			;  ...return temp storage
	ret

;=========================================================================
; int_10_fn0B - Set background color or palette
; Input:
; 	AH - 0Bh
;	BH = 00h - set background / border color
;		BL - background (graphics modes) or border (text modes)
;	BH = 01h - set palette (320x200 graphics mode)
;		BL - palette ID:
;			00h - background, green, red, and yellow (brown)
;			01h - background, cyan, magenta, and white
; Output:
;	none
;-------------------------------------------------------------------------
int_10_fn0B:
	mov	al,ds:byte ptr [video_palet_reg] ; AL = current palette register
	mov	ah,byte ptr [bp]+int_10_bl	; AH = color / palette ID
	cmp	byte ptr [bp]+int_10_bh,00h	; check function
	jnz	.set_palette1		; jump to set palette if BH != 0

	and	al,0E0h			; clear color bits - bits 0-5
	and	ah,1Fh			; clear non-color bits in input
	or	al,ah			; apply new color
	jmp	.write_palet_reg

.set_palette1:
	and	al,0DFh			; clear palette bit - bit 6
	test	ah,01h
	jz	.write_palet_reg
	or	al,20h			; set palette bit for BL = 01h

.write_palet_reg:
	mov	ds:byte ptr [video_palet_reg],al ; save new palette reg in BIOS data
	mov	dx,ds:word ptr [video_port]
	add	dx,5			; CRTC color select register
	out	dx,al			; send it to CRTC
	ret

;=========================================================================
; int_10_fn0C - Write graphics pixel
; Input:
;	AH = 0Ch
;	AL = pixel color, if bit 7 set, pixel is XOR'ed onto screen
;	CX = column
;	DX = row
; Output:
;	none
;-------------------------------------------------------------------------
int_10_fn0C:
	call	vid_pixel_address	; calculate pixel address	
	jnz	.mode_320x200		; jump if 320x200 mode
	mov	al,byte ptr [bp]+int_10_al	; AL - color
	mov	bl,al			; copy color to BL
	and	al,1			; one bit per pixel
	ror	al,1			; make color MSB instead of LSB
	mov	ah,7Fh			; AH = pixel mask
	jmp	.prepare_mask

.mode_320x200:
	shl	cl,1
	mov	al,byte ptr [bp]+int_10_al	; AL - color
	mov	bl,al			; copy color to BL
	and	al,3			; two bit per pixel
	ror	al,1			; make color MSB instead of LSB
	ror	al,1
	mov	ah,3Fh			; AH = pixel mask

.prepare_mask:
	ror	ah,cl			; position pixel mask correctly
	shr	al,cl			; position color bits correctly
    mov	cl,es:byte ptr [si]		; read the byte containing the pixel
	or	bl,bl			; check if bit 7 set
	jns	.set_color		; bit 7 not set - new color
	xor	cl,al			; else XOR with existing color
	jmp	.write_pixel

.set_color:
	and	cl,ah			; clear existing color bits
	or	cl,al			; set new color bits

.write_pixel:
    	mov	es:[si],cl			; write the byte with the new pixel
	ret

;=========================================================================
; int_10_fn0D - Read graphics pixel
; Input:
;	AH = 0Dh
;	CX = column
;	DX = row
; Output:
;	AL = pixel color 
;-------------------------------------------------------------------------
int_10_fn0D:
	call	vid_pixel_address	; calculate pixel address
    mov	al,es:byte ptr [si]		; read byte containing the pixel
	jnz	.mode_320x200_1		; jump if 320x200 mode
	shl	al,cl			; shift pixel to bit 7
	rol	al,1			; shift pixel from bit 7 to bit 0
	and	al,1			; one bit per pixel
	jmp	.exit_4

.mode_320x200_1:
	shl	cl,1			; update position for two bits per pixel
	shl	al,cl			; shift pixel to bits 7-6
	rol	al,1			; shift pixel to bits 1-0
	rol	al,1
	and	al,3			; two bits per pixel

.exit_4:
	mov	byte ptr [bp]+int_10_al,al	; return pixel color in AL
	ret

;=========================================================================
; int_10_fn0E - Teletype output
; Input:
;	AH = 0Eh
;	AL = character to write
;	BL = foreground color (graphics modes only)
; Output:
;	none
; Notes:
;	- writes character to the active video page
;	- support following control characters: BEL, BS, LF, CR
;-------------------------------------------------------------------------
int_10_fn0E:    
	mov	bl,ds:byte ptr [video_page]	; BL = active video page
	mov	bh,0
	shl	bl,1			; word index
	mov	dx,word ptr [bx+video_cur_pos] ; DX = cursor position

	mov	al,byte ptr [bp]+int_10_al	; AL = character to write
    
	cmp	al,bs
	jz	.bs			; jump if backspace (BS)
	cmp	al,lf
	jz	.lf			; jump if line feed (LF)
	cmp	al,bel
	jz	.bel			; jump if beep (BEL)
	cmp	al,cr
	jz	.cr			; jump if carriage return (CR)
	mov	bl,byte ptr [bp]+int_10_bl	; BL = attribute for graphics mode
	mov	ah,0Ah			; INT 10h, function 0Ah - write char
	mov	cx,1			; one character
	int	10h			; write character
	inc	dl			; move cursor to the next column
	cmp	dl,ds:byte ptr [video_columns]	; compare position to number of columns
	jnz	.set_cursor_pos		; jump if not past the last column
	mov	dl,0			; move to the first position

.lf:
	cmp	dh,24			; on the last row?
	jz	.scroll			; jump if on the last row - scroll
	inc	dh			; move cursor to the next row
	jnz	.set_cursor_pos		; set new cursor position

.bs:
	cmp	dl,0			; on the first column?
	jz	.set_cursor_pos		; jump if yes - nothing to do
	dec	dl			; move cursor to the previous position
	jmp	.set_cursor_pos		; set new cursor position

.cr:
	mov	dl,0			; set cursor to the first column

.set_cursor_pos:
	mov	bl,ds:byte ptr [video_page]	; BL = active video page
	jmp	set_cur_pos		; set new cursor position

.bel:
	mov	bl,2			; 0.2 second beep
	call	beep
	ret

.scroll:
	mov	ah,02h
	int	10h			; set new cursor position    
	call	vid_check_mode
	mov	bh,0
	jc	.do_scroll		; jump if text mode - do scroll
	mov	ah,08h			; INT 10h, function 08h - read char
	int	10h			; read attirbute at current position    
	mov	bh,ah

.do_scroll:
	mov	ah,06h			; INT 10h, function 06h - Scroll up
	mov	al,1			; scroll one line
	xor	cx,cx			; top right corner is 0,0
	mov	dh,24			; bottom row is 24
	mov	dl,ds:byte ptr [video_columns] ; right column is the last column
	dec	dl
	int	10h			; scroll page up    
	ret

;=========================================================================
; int_10_fn0F - Get current video mode
; Input:
;	AH = 0Fh
; Output:
;	AL = video mode
;	AH = characters per column
;	BH = active video page
;-------------------------------------------------------------------------
int_10_fn0F:
	mov	al,ds:byte ptr [video_columns]
	mov	byte ptr [bp]+int_10_ah,al
	mov	al,ds:byte ptr [video_mode]
	mov	byte ptr [bp]+int_10_al,al
	mov	al,ds:byte ptr [video_page]
	mov	byte ptr [bp]+int_10_bh,al
	ret

pit_ch2_reg	    equ	42h
pit_ctl_reg	    equ	43h
ppi_pb_reg	    equ	61h	; 8255 PPI port B I/O register

;=========================================================================
; delay_15us - delay for multiplies of approximately 15 microseconds
; Input:
;	CX = time to delay (in 15 microsecond units)
; Notes:
;	This implementation does not provide precise timing
;	The actual delay depends on the CPU clock frequency
;-------------------------------------------------------------------------
delay_15us:
	push	ax
	push	cx
.delay1:
	; mov	al,4	; With real PCXT at 4.77Mhz
	mov	al,10   	; With Next186 at 12Mhz
.delay2:
	dec	al
	jnz	.delay2
	loop	.delay1
	pop	cx
	pop	ax
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

;=========================================================================
; vid_check_mode - Check current video mode
; Input:
;	none
; Output:
;	ZF set if monochrome mode (mode 07h)
;	CF set if graphics modes (modes 04h - 06h)
;-------------------------------------------------------------------------
vid_check_mode:
	push	ax
	mov	al,ds:byte ptr [video_mode]
	cmp	al,07h			; set ZF if monochrome mode
	jz	.exit_2			; jump if monochrome
	cmp	al,04h			; clears CF if graphics mode
	cmc				; invert CF flag (CF = 1 - graphics)
	jnc	.exit_2			; jump if not graphics (CF = 0, ZF = 0)
	sbb	al,al			; AL=AL-(AL+CF) set CF and clear ZF?
	stc				; set CF back

.exit_2:
	pop	ax
	ret

;=========================================================================
; vid_crtc_writew - Write a word to two consecutive CRTC registers
; Input:
;	AH = register number
;	CX = word to write
; Output:
;	AX trashed
; Note:
;	Writes CH to register number AH, and CL to register number AH+1
;-------------------------------------------------------------------------
vid_crtc_writew:
	mov	al,ch
	call	vid_crtc_writeb		; write CH to CRTC register AH
	inc	ah			; point AH to the next register
	mov	al,cl			; prepare AL for vid_crtc_writeb    

; fall through to vid_crtc_writeb (writting to AH+1)

;=========================================================================
; vid_crtc_writew - Write a word to two consecutive CRTC registers
; Input:
;	AH = register number
;	AL = byte to write
; Output:
;	none
;-------------------------------------------------------------------------
vid_crtc_writeb:
	push	dx
	mov	dx,ds:word ptr [video_port]	; DX = CRTC index port
	xchg	al,ah			; AH = byte, AL = register number
	out	dx,al			; write register number
	xchg	al,ah			; AH = register numbet, AL = byte
	inc	dl			; DX = CRTC data port
	out	dx,al			; write byte
	pop	dx
	ret

;=========================================================================
; vid_pixel_address - calculate pixel address and mask
; Input:
;	CX - column
;	DX - row
; Output:
;	SI - pixel address
;	CH - pixel mask
;	CL - pixel position in the byte
;	ZF - mode
;		0 = 320x200
;		1 = 640x200
;-------------------------------------------------------------------------
vid_pixel_address:
	xor	si,si			; SI = 0
	shr	dl,1			; divide row by two
	jnb	.even			; jump if on even row 
	mov	si,2000h		; odd row - second video plane

.even:
	mov	al,50h			; bytes in each row
	mul	dl			; AX - address of the row

	add	si,ax			; add row address to SI
	mov	dx,cx			; DX - column
	mov	cx,0302h 		; CH - pixel pos mask, CL - shift
	cmp	ds:byte ptr [video_mode],6	; 640x200 mode?
	pushf				; save ZF (and other flags
	jnz	.22			; skip if not 640x200
	mov	cx,0703h 		; pixel pos mask and shift for 640x200

.22:
	and	ch,dl			; CH = pixel position in the byte
	shr	dx,cl			; DX = address of the column
	add	si,dx			; add column address to SI
	xchg	cl,ch			; CH = pixel mask, CL = pixel position
	popf
	ret

;=========================================================================
; vid_current_offset - convert current cursor position to offset
;		       relative to page starting address
; Input:
;	BL = page
; Output:
;	AX = offset
;-------------------------------------------------------------------------
vid_current_offset:
	mov	bh,0
	shl	bx,1				; word index
	mov	ax,word ptr [bx+video_cur_pos]	; AX = current cursor position

; fall through to vid_position_to_offset

;=========================================================================
; vid_position_to_offset - convert position (row and column) to offset
;			   relative to page starting address
; Input:
;	AH = row
;	AL = column
; Output:
;	AX = offset
;-------------------------------------------------------------------------
vid_position_to_offset:
	push	bx
	mov	bl,al			; BL = column
	mov	al,ah			; AL = row
	mul	ds:byte ptr [video_columns] 	; AX = row * video_columns
	mov	bh,0			;
	add	ax,bx			; AX = row * video_columns + column
	shl	ax,1			; multiply by two (char + attribute)
	pop	bx
	ret

;=========================================================================
; vid_gfx_pos_to_offset - convert position (row and column) to offset
; Input:
;	AH = row
;	AL = column
; Output:
;	AX = offset
;-------------------------------------------------------------------------
vid_gfx_pos_to_offset:
	push	bx
	mov	bl,al			; BL = column
	mov	al,ah			; AL = row
	mul	ds:byte ptr [video_columns] 	; AX = row * video_columns
	shl	ax,1			; multiply by four: one character takes
	shl	ax,1			;   four bytes in each plane
	mov	bh,0
	add	ax,bx			; AX = row * video_columns * 4 + column
	pop	bx
	ret

int10 endp

; --------------------- INT 11h - Equipment ----------------
EquipmentWord       equ     <ds:[10h]>

int11   proc near
        push    ds
        mov     ax, 40h
        mov     ds, ax
        mov     ax, EquipmentWord
        pop     ds
        iret
int11   endp

; --------------------- INT 12h - Memory size ----------------
MemorySize       equ     <ds:[13h]>

int12   proc near
        push    ds
        mov     ax, 40h
        mov     ds, ax
        mov     ax, MemorySize
        pop     ds
        iret        
int12   endp

; --------------------- INT 13h - Disk services ----------------
HDLastError       equ     <ds:[74h]>
HDOpStarted       equ     <ds:[92h]>    ; bit 3: in INT13h (all other bits must be 0)
HDSize            equ     <ds:[94h]>

int13   proc near
        push    ds
        push    bp
        push    ax
        mov     ax, 40h
        mov     ds, ax
        pop     ax
        xor     byte ptr HDOpStarted, 8
        jz      short inINT13
        sti                     
        cld
        cmp     ah, 1ah
        jbe     short Disk1
        sub     ah, 41h-1bh     ; extensions
        cmp     ah, 22h
        jbe     short Disk1
        mov     ah, 1           ; bad command error
        jmp     short exit33
inINT13:        
        mov     ah, 0aah        ; drive not ready
        jmp     short exit2
Disk1:
        mov     bp, ax
        shr     bp, 7
        and     bp, 1feh
        push    ds
        call    cs:disktbl[bp]
        pop     ds
exit33:        
        mov     HDLastError, ah
exit2:
        xor     byte ptr HDOpStarted, 8
        neg     ah              ; CF <- (AH != 0)
exit77:
        pushf           ; preserve carry
        neg     ah
        popf            ; restore carry
        pop     bp
        pop     ds
        retf    0002h

disktbl dw      DiskReset, DiskGetStatus, DiskRead, DiskWrite, DiskVerify, DiskFormat, DiskFormat, DiskFormat, DiskGetParams, DiskInit, DiskRead, DiskWrite, DiskSeek, DiskRst, DiskReadSectBuffer, DiskWriteSectBuffer
        dw      DiskReady, DiskRecalibrate, DiskDiag, DiskDiag, DiskDiag, DiskGetType, DiskChanged, DiskSetDASDType, DiskSetMediaType, DiskPark, DiskFormat,  DiskExtInstCheck, DiskExtRead, DiskExtWrite, DiskExtVerify, DiskExtLock
        dw      DiskExtEject, DiskExtSeek, DiskExtGetParams

DiskGetType:
        cmp     dl, 80h
        jne     short DiskReset ; ah=0, drive not present
        mov     cx, HDSize      
        mov     dx, cx
        test    cx, cx
        jz      short DiskReset ; ah=0, drive not present
        mov     ah, -3      ; HD present
        shr     cx, 6
        shl     dx, 10      ; CX:DX = HDSize * 1024
DiskGetTypeexit:        
        pop     ds          ; discard ret address
        pop     ds          ; discard DS
        xor     byte ptr HDOpStarted, 8     ; CF <- 0 
        jmp     short   exit77

DiskExtInstCheck:
        xchg    bl, bh
        mov     ah, -1
        mov     cx, 1       ; extended disk access functions (AH=42h-44h,47h,48h) supported
        cmp     dl, 80h
        jne     short notready
        jmp     short DiskGetTypeexit

DiskReset:
DiskChanged:
DiskPark:
        mov     ah, 0       ; success
        ret

DiskGetStatus:
        mov     ah, HDLastError
        ret
      
DiskVerify:
        mov     bp, sdverify
        jmp     short   DiskRead1
DiskWrite:
        mov     bp, sdwrite
        jmp     short   DiskRead1
DiskRead:
        mov     bp, sdread
DiskRead1:        
        test    al, al
        jz      short DiskReset
        cmp     dl, 80h
        jne     short notready
        mov     ah, 4
        test    cl, 3fh
        jz      short DiskReadend   ; bad sector 0
        
        push    ax
        push    bx
        push    cx
        push    dx
        push    ds
        push    es
        push    ss
                
        mov     ah, 0
        push    ax
        call    HCStoLBA
        pop     cx
        push    cx        
        call    bp              ; DX:AX sector, ES:BX buffer, CX=sectors, returns AX=read sectors
        pop     cx
        sub     cx, ax
        neg     cx              ; CF=1 if cx != 0
        rcl     ah, 3           ; AH = 4*CF (sector not found / read error)
        mov     ds, ax
        
        pop    ss
        pop    es
        pop    ds
        pop    dx
        pop    cx
        pop    bx
        pop    ax
        
        mov     ax, ds
DiskReadend:
        ret

HCStoLBA:       ; CX = {cyl[7:0], cyl[9:8], sect[5:0]}, DH = head. Returns DX:AX LBA
        mov     al, ch
        mov     ah, cl
        shr     ah, 6
        shr     dx, 8
        imul    dx, 63
        and     cx, 3fh
        add     cx, dx
        dec     cx
        mov     dx, 255*63
        mul     dx
        add     ax, cx
        adc     dx, 0
        ret       
;    unsigned int s = cs & 0x3f;
;    unsigned int c = ((cs & 0xc0) << 2) | (cs >> 8);
;    return (c*255l + h)*63l + s - 1l;

DiskFormat:
DiskInit:
DiskSeek:
DiskRst:
DiskReady:
DiskRecalibrate:
DiskDiag:
DiskExtSeek:
        cmp     word ptr HDSize, 0
        je      short notready
        cmp     dl, 80h
        je      short DiskReset
notready:        
        mov     ah, 0aah        ; disk not ready
        ret

DiskGetParams:
        cmp     dl, 80h
        mov     ah, 7
        jne     short DiskReadend   ; ret
        mov     bl, 0   ; ???
        mov     ax, HDSize
        mov     dx, ax
        shl     ax, 10
        shr     dx, 6
        sub     ax, 30
        sbb     dx, 0
        mov     cx, 63*255
        div     cx
        dec     ax
        cmp     ax, 3feh
        jbe     dgpok
        mov     ax, 3feh
dgpok:        
        xchg    al, ah
        shl     al, 6
        or      al, 3fh
        mov     cx, ax
        mov     dx, 0fe01h
        xor     ax, ax
        ret        

DiskExtVerify:
        mov     bp, sdverify
        jmp     short DiskExtRead1
DiskExtWrite:
        mov     bp, sdwrite
        jmp     short DiskExtRead1
DiskExtRead:
        mov     bp, sdread
DiskExtRead1:
        cmp     dl, 80h
        jne     short notready
        push    es
        push    ax
        
        push    ax
        push    bx
        push    cx
        push    dx
        push    ds
        push    es
        push    ss
        
        mov     bx, sp
        mov     ds, ss:[bx+26]
        mov     cx, [si+2]
        les     bx, [si+4]
        mov     ax, [si+8]
        mov     dx, [si+10]
        push    ds
        push    si
        call    bp
        pop     si
        pop     ds
        sub     ax, [si+2]
        add     [si+2], ax
        
        pop    ss
        pop    es
        pop    ds
        pop    dx
        pop    cx
        pop    bx
        pop    ax
        
        pop     ax
        sbb     ah, ah
        and     ah, 4
        pop     es
        ret

DiskExtGetParams:
        cmp     dl, 80h
        jne     notready ; short
        push    ax
        mov     ax, HDSize   
        mov     bp, sp
        mov     ds, [bp+8]
        xor     bp, bp
        mov     word ptr [si], 1ah      ; size
        mov     word ptr [si+2], 0bh    ; flags
        mov     word ptr [si+4], 1023   ; cylinders
        mov     word ptr [si+6], bp
        mov     word ptr [si+8], 255    ; heads
        mov     word ptr [si+10], bp
        mov     word ptr [si+12], 63     ; sectors/track
        mov     word ptr [si+14], bp
        mov     word ptr [si+16], ax
        shl     word ptr [si+16], 10
        shr     ax, 6
        mov     word ptr [si+18], ax
        mov     word ptr [si+20], bp
        mov     word ptr [si+22], bp
        mov     word ptr [si+24], 512   ; bytes/sector
        pop     ax
        mov     ah, 0
        ret 

DiskReadSectBuffer:
DiskWriteSectBuffer:
DiskSetDASDType:
DiskSetMediaType:
DiskExtLock:
DiskExtEject:
        mov     ah, 1       ; unsupported fn
        ret

int13   endp


; --------------------- INT 15h - Extended services ----------------
UFPtr           equ     <ds:[98h]>
WaitCount       equ     <ds:[9ch]>
UWaitFlag       equ     <ds:[0a0h]>
HandlerPtr      equ     <ds:[0a1h]> ; 4 bytes
DataBuffer      equ     <ds:[0a5h]> ; 3 bytes
DataCounter     equ     <ds:[067h]> ; 1 byte
PacketSize      equ     <ds:[068h]> ; 1 byte, 0->3bytes, 1->4bytes
FreeXMSKb       equ     0

; ------------ MovExt
IncSeg: ; DX = segment port address
        jnz     short SetSegExit        
        in      ax, dx
        and     ax, word ptr cs:[ramsize]-1
        inc     ax
        cmp     ax, 12h
        jne     short IncSeg1
        xor     ax, ax
IncSeg1:
        cmp     ax, 0ch
        jne     short SetSeg2
SetSeg: ; DX = segment port address, ax = logical segment (0..RAMSize-1)  
        and     ax, word ptr cs:[ramsize]-1
        cmp     ax, 0ch
        jb      short SetSeg1
        add     ax, 6
SetSeg2:        
        cmp     ax, word ptr cs:[ramsize]
        jb      short SetSeg1
        sub     ax, word ptr cs:[ramsize] - 0ch
SetSeg1:
        out     dx, ax          
SetSegExit:              
        ret

MovSeg  equ     01h
savess  dw      0
savesp  dw      MovExt, 0 ; tmp stack
; Log(idx) to Phy(val) segment map (RAMSize segs): 0,1,2,3,4,5,6,7,8,9,a,b,12h,13h,...,RAMSize-2,RAMSize-1,c,d,e,f,10h,11h, then wrap to 0,1,2,...
MovExt:
        push    es
        push    ds
        
        push    ax
        push    bx
        push    cx
        push    dx
        push    ds
        push    es
        push    ss        
        
        cli
        mov     cs:savess, ss
        push    cs
        pop     ss
        xchg    sp, cs:savesp
        mov     dx, 80h + MovSeg + 1
        jcxz    short MovExt_exit
        push    es
        pop     ds
        cld
        mov     al, [si+1ch]
        mov     ah, [si+1fh]
        mov     bl, [si+14h]
        mov     bh, [si+17h]
        mov     di, [si+1ah]
        mov     si, [si+12h]
        ;call    flush   
        call    SetSeg      ; 02000h = destination, DX=82h
        dec     dx
        xchg    ax, bx
        call    SetSeg      ; 01000h = source, DX=81h
        push    MovSeg shl 12 
        pop     ds
        push    (MovSeg + 1) shl 12
        pop     es
        xor     bx, bx
        add     cx, cx
        adc     bx, bx      ; BX:CX = bytes to transfer
; move from 01000h:si to 02000h:di, 2*cx bytes
MovExtLoop:
        inc     dx          ; 82h
        mov     ax, si
        cmp     ax, di
        ja      short MovExt1
        mov     ax, di
MovExt1:
        neg     ax
        adc     bx, -1
        sub     cx, ax
        sbb     bx, 0
        xchg    ax, cx      ; cx = bytes to move, bx:ax = bytes left for the next transfer
        jns     short MovExt2   ; ax <= bx:cx     
        add     cx, ax
        xor     ax, ax
        inc     bx
MovExt2:
        movsb               ; if CX = 0 transfer 10000h bytes
        dec     cx
        jz      short MovExt_next
        test    si, 1       ; read align
        jz      short raligned
        movsb
        dec     cx
raligned:
        shr     cx, 1
        rep     movsw
        jnc     short MovExt_next
        movsb
MovExt_next:
        ;call    flush
        mov     cx, ax
        or      ax, bx
        jz      short MovExt_exit  ; finalized
        test    di, di
        call    incseg      ; does nothing if ZF == 0, dx = 8bh
        dec     dx          ; 81h
        test    si, si      
        call    incseg      ; dx = 81h
        jmp     short MovExtLoop
MovExt_exit:
        mov     ax, MovSeg + 1
        out     dx, ax      ; 82h
        dec     ax
        dec     dx
        out     dx, ax      ; 81h
        mov     ss, cs:savess
        xchg    sp, cs:savesp
        
        pop    ss
        pop    es
        pop    ds
        pop    dx
        pop    cx
        pop    bx
        pop    ax
        
        pop     ds
        pop     es
        xor     ah, ah
        jmp     short exit_ax
MovExtProxy:
        jmp     MovExt        

int15:
        cmp     ah, 4fh
        je      short exit_iret
        xchg    al, ah
        cmp     al, 80h
        jb      short exit15; CF=1  for <80h
        cmp     al, 83h
        jb      short done  ; no error for 80, 81, 82
        je      short SetEventWait; 83
        cmp     al, 86h
        jb      short exit15; CF=1 for 84, 85
        je      short Wait1 ; 86
        cmp     al, 88h
        jb      short MovExtProxy ; 87
        je      short ExtSize     ; 88
        cmp     al, 90h
        jb      short  exit15; CF=1 for 89..8f
        cmp     al, 92h
        jb      short done  ; no error for 90, 91
        cmp     al, 0c0h
        jb      short exit15; CF=1 for 92..bf
        je      short GetConfig   ; c0
        cmp     al, 0c2h
        jb      short exit15; CF=1 for c1
        je      short Mouse ; c2
done:
        cmc                 ; CF=1 for >c2
exit15:
        mov     ax, 8600h
exit_ax:        
        sti
        retf    2           ; discard flags (need to keep CF)
exit_iret:
        iret        

; ------------ SetEventWait
SetEventWait:
        push    ds
	push	ax
        mov     ax, 40h
        mov     ds, ax
	pop	ax
        xor     ah, 1
        jz      short cancel
        test    ah, byte ptr UWaitFlag ; ah=1
        jnz     short busy  ; CF=0
        mov     ax, 1000-1  ; 1ms
        out     70h, ax     ; restart RTC timer
        mov     UFPtr[0], bx
        mov     UFPtr[2], es
        add     ax, dx
        adc     cx, 0
        mov     WaitCount[0], ax
        mov     WaitCount[2], cx
        mov     ah, 1       ; wait in progress
cancel:
        mov     byte ptr UWaitFlag, ah   
        int     70h
        stc                 ; no error
busy:   
        cmc                 ; eror        
nowait:
        pop     ds
        jmp     short exit15

; ------------ Wait
Wait1:
        push    es
        push    bx
        mov     ax, 8300h
	push	ax
        mov     ax, 4ah
        mov     es, ax
	pop	ax
        xor     bx, bx      ; user wait flag address=0040:00a0
        int     15h         ; returns with IF = 1
        jc      short wbusy
wloop:        
        hlt   
        test    byte ptr es:[bx], 80h
        jz      short wloop
wbusy:        
        pop     bx
        pop     es
        jmp     short exit15
        

; ------------ ExtSize
ExtSize:
        mov     ax, FreeXMSKb
        jmp     short exit_ax
        
; ------------ GetConfig
GetConfig:
        xor     ax, ax
        push    cs
        pop     es
        mov     bx, offset SysParams
        jmp     short exit_ax
        
; ------------ Mouse 
Mouse:
        push    ds
        push    dx
	push	ax
        mov     ax, 40h
        mov     ds, ax
	pop	ax
        test    byte ptr EquipmentWord, 4 ; ps2 mouse equipement word
        jnz     short mouse_present
if_err:
        mov     ax, 03a7h   ; interface error (no mouse present)
        out     64h, al     ; disable mouse
errexit:        
        stc                 ; error
exitok:        
        pushf               ; save CF
	push    ax
	call    enablemouseinterrupt
	pop     ax
        call    enableKbIfPresent
        popf
        pop     dx
        pop     ds
        jmp     exit_ax
mouse_present:
        mov     al, ah                                  
        mov     ah, 1       ; invalid function
        cmp     al, 7
        ja      short errexit
	push    ax

	call    disablemouseinterrupt
        sti                 ; allow interrupts for a short time, to flush possible pending KB/mouse requests
        mov     al, 0adh
        out     64h, al     ; disable kb interface
        pop     ax
        cmp     al, 1
        cli                 ; from now on we are working with ints disabled, as the following code is highly non re-entrant
        jb      short en_dis
        je      short reset
        cmp     al, 3
        jb      short sampling
        je      short resolution
        cmp     al, 5
        jb      short gettype
        je      short reset
        cmp     al, 6
        je      short extend

; ------------- set handler
        mov     HandlerPtr[0], bx
        mov     HandlerPtr[2], es
        jmp     short exit_success1        

; ------------- enable/disable
en_dis:
        mov     ax, 02f5h   ; ah = invalid input
        sub     al, bh
        cmp     bh, ah
        jnc     short errexit
        mov     ah, al
        call    sendcmd     ; enable/disable data reporting (CF = 1)
if_err1:        
        jc      short if_err
exit_success:
        mov     byte ptr DataCounter, 0
exit_success1:
        xor     ah, ah      ; success
        jmp     short exitok

; ------------- reset
reset:
        mov     ah, 0f6h    ; set defaults
        stc                 ; mouse command
        call    sendcmd     
        jc      short if_err
        mov     bx, 00aah
        mov     byte ptr PacketSize, bh ; 3bytes packet
        jmp     short exit_success

; ------------- sampling
sampling:
        cmp     bh, 6
badparam:
        mov     ah, 2       ; invalid input
        ja      short errexit
        shr     bx, 8
        mov     ah, cs:sample_tbl[bx]
        push    ax
        mov     ah, 0f3h    ; st sample rate
send2c:
        stc
        call    sendcmd              
        pop     ax
        jc      short if_err1
send1c:
        stc
        call    sendcmd
        jmp     short if_err1

; ------------- resolution
resolution:
        cmp     bh, 3
        ja      short badparam
        push    bx
        mov     ah, 0e8h    ; set resolution
        jmp     short send2c

; ------------- gettype
gettype:
        mov     ah, 0f2h
        stc
        call    sendcmd
        jc      short if_err1
        call    getps2byte
        jc      short if_err1
        mov     bh, al
        neg     al          ; CF=1 if al != 0
        adc     al, bh
        mov     byte ptr PacketSize, al ; 3 or 4 bytes packet
        jmp     short exit_success
        
; ------------- extended commands
extend:
        test    bh, bh
        jnz     short setscaling
        mov     ah, 0e9h    ; status request
        stc
        call    sendcmd
        jc      short if_err1
        call    getps2byte
        jc      short if_err1
        mov     bl, al
        call    getps2byte
        jc      short if_err1
        mov     cl, al
        call    getps2byte
        jc      short if_err1
        pop     dx  
        push    ax          ; replace dx on stack
        jmp     short exit_success
setscaling:    
        cmp     bh, 2
        ja      short badparam
        mov     ah, 0e5h    ; set scaling 1:1 or 2:1
        add     ah, bh
        jmp     short send1c
enablemouseinterrupt:
	mov     al, 20h
	out     064h, al
	in      al, 060h    ; read 8042 config byte
	or      al, 02h     ; set enable mouse interrupt
	mov     ah, al
	mov     al, 60h
	out     064h, al
	mov     al, ah
	out     060h, al    ; send 8042 config byte
	ret
disablemouseinterrupt:
	mov     al, 20h
	out     064h, al
	in      al, 060h    ; read 8042 config byte
	and     al, 0fdh     ; set disable mouse interrupt
	mov     ah, al
	mov     al, 60h
	out     064h, al
	mov     al, ah
	out     060h, al    ; send 8042 config byte
	ret

sample_tbl  db  10, 20, 40, 60, 80, 100, 200
SysParams   db  8, 0, 0fch, 0, 0
;--------------------------------------------------------------------------
; Feature byte 1
; b7: 1=DMA channel 3 used by hard disk
; b6: 1=2 interrupt controllers present
; b5: 1=RTC present
; b4: 1=BIOS calls int 15h/4Fh every key
; b3: 1=wait for extern event supported (Int 15h/41h)
; b2: 1=extended BIOS data area used
; b1: 0=AT or ESDI bus, 1=MicroChannel
; b0: 1=Dual bus (MicroChannel + ISA)
;--------------------------------------------------------------------------
            db      10h
;--------------------------------------------------------------------------
; Feature byte 2
; b7: 1=32-bit DMA supported
; b6: 1=int16h, function 9 supported
; b5: 1=int15h/C6h (get POS data) supported
; b4: 1=int15h/C7h (get mem map info) supported
; b3: 1=int15h/C8h (en/dis CPU) supported
; b2: 1=non-8042 kb controller
; b1: 1=data streaming supported
; b0: reserved
;--------------------------------------------------------------------------
            db      44h
;--------------------------------------------------------------------------
; Feature byte 3
; b7: not used
; b6: reserved
; b5: reserved
; b4: POST supports ROM-to-RAM enable/disable
; b3: SCSI on system board
; b2: info panel installed
; b1: Initial Machine Load (IML) system - BIOS on disk
; b0: SCSI supported in IML
;--------------------------------------------------------------------------
            db      0
;--------------------------------------------------------------------------
; Feature byte 4
; b7: IBM private
; b6: EEPROM present
; b5-3: ABIOS presence (011 = not supported)
; b2: private
; b1: memory split above 16Mb supported
; b0: POSTEXT directly supported by POST
;--------------------------------------------------------------------------
            db      0
;--------------------------------------------------------------------------
; Feature byte 5 (IBM)
; b1: enhanced mouse
; b0: flash EPROM
;--------------------------------------------------------------------------
            db      0                                                


; --------------------- INT 16h - keyboard interface ----------------
;       AH      Description
;       --      ------------------------------------------------
;       00h     Get a key from the keyboard, return code in AX.
;       01h     Test for available key, ZF=1 if none, ZF=0 and
;               AX contains next key code if key available.
;       02h     Get shift status. Returns shift key status in AL.
;       03h     Set Autorepeat rate. BH=0,1,2,3 (delay time in quarter seconds), BL=0..1Fh for 30 char/sec to 2 char/sec repeat rate.
;       05h     Store scan code (in CX) in the type ahead buffer.
;       10h     Get a key (same as 00h in this implementation).
;       11h     Test for key (same as 01h).
;       12h     Get extended key status. Returns status in AX.

AltKpd          equ     <ds:[19h]>
HeadPtr         equ     <ds:[1ah]>
TailPtr         equ     <ds:[1ch]>
Buffer          equ     <ds:[80h]>;1eh
EndBuf          equ     <ds:[82h]>;3eh

int16 proc near
        push    ds
        push    si
        push    ax
        mov     ax, 40h
        mov     ds, ax
        pop     ax
        xchg    al, ah          ;shorter opcodes for al than ah
        dec     ax
        test    al, 0EFh        ;Check for 01h and 11h
        jz      short TestKey   ;TestKey does not need cld
        inc     ax
        cld
        test    al, 0EFh        ;Check for 0h and 10h
        jz      short GetKey
        cmp     al, 3           ;Check for 02h and 03h
        jb      short GetStatus
        je      short SetAutoRpt   
        cmp     al, 5           ;Check for StoreKey function.
        je      short StoreKey
        cmp     al, 9           ;Get KB functionality
        je      short kbfunc     
        cmp     al, 12h         ;Extended status call
        je      short ExtStatus
        cmp     al, 92h         ;stupid keyb.com 
        jne     short Exit
kbfunc:
        mov     al, 24h         ;AL=20h (fn 10h, 12h supported, set typematic supported)        
Exit:        
        pop     si
        pop     ds
        iret                    ; unknown function, Restores flags.

GetKey1:                        ; wait for interrupt
        hlt
GetKey: ; ----------- fn 00h, 10h
        mov     ah, 11h
        int     16h             ;See if key is available (IF becomes 1 after this int)
        jz      short GetKey1   ;Wait for keystroke.
        cli                     ;Critical region! Ints off.
        mov     si, HeadPtr     ;Ptr to next character.
        lodsw                   ;Get the character, Bump up HeadPtr
        cmp     si, EndBuf
        jb      short noWrap
        mov     si, Buffer
noWrap:             
        mov     HeadPtr, si
        jmp     short Exit

TestKey: ; ---------- fn 01h
        mov     si, HeadPtr
        cmp     si, TailPtr     ;ZF=1, if empty buffer
        lodsw                   ;BIOS returns avail keycode.
        sti                     ;Ints back on.
        pop     si
        pop     ds
        retf    2               ;Pop flags (ZF is important!)

StoreKey: ; ---------- fn 05h - Inserts the value in CX into the type ahead buffer.  
        mov     si, TailPtr     ;Address where we can put next key code.
        mov     [si], cx        ;Store the key code away
        inc     si
        inc     si              ;Move on to next entry in buf
        cmp     si, EndBuf
        jb      short NoWrap1
        mov     si, Buffer
 NoWrap1:
        mov     al, 1           ;no room
        cmp     si, HeadPtr     ;Data overrun?
        je      short Exit      ;if so, ignore key entry.
        mov     TailPtr, si
        dec     ax              ;al=0
        jmp     short Exit       

ExtStatus: ; ------- fn 12h - Retrieve the extended keyboard status and return it in AH, and the standard keyboard status in AL.    
        mov     al, KbdFlags2
        and     al, 01110111b   ;Clear final sysreq field, and final right alt bit.
        test    al, 100b        ;Test cur sysreq bit.
        jz      short NoSysReq  ;Skip if it's zero.
        sub     al, 10000100b   ;Set final sysreq bit, clear final right ctl bit.
NoSysReq:
        mov     ah, KbdFlags3
        and     ah, 1100b       ;Grab rt alt/ctrl bits.
        or      ah, al          ;Merge into AH.

GetStatus: ; --------- fn 02h     
        mov     al, KbdFlags1   ;Just return Std Status.
Exit1:
        jmp     short Exit

SetAutoRpt: ; ------ fn 03h
        cmp     ah, 5
        jne     short Exit
        push    dx
        shl     bh, 5
        and     bl, 1fh
        or      bl, bh
        and     bl, 7fh
        mov     ah, 0           ; wait LED update progress to finalize
        call    WaitFlag        ; leaves with IF=0
        jc      short timeout
        or      byte ptr KbdFlags4, SetRepeat    ; set auto repeat in progress
        mov     ah, 0f3h        ; set typematic rate and delay
        push    bx
        xor     bl, bl          ; send to kb
        call    sendps2byte
        pop     bx
        jc      short timeout1  ; send timeout
        mov     ah, SetRepeat or AckReceived ; test if ACK received
        call    WaitFlag
        jc      short timeout1
        mov     ah, bl
        xor     bl, bl          ; send to kb
        call    sendps2byte     ; send data
timeout1:
        and     byte ptr KbdFlags4, not SetRepeat   
timeout:
        pop     dx
        jmp     short Exit1


WaitFlag:   ; ah = desired KbdFlags4 & (AckReceived | LEDUpdate | SetRepeat)
        mov     dx, 3dah
        mov     bh, 8*25    ; wait for max 25 * VGA frame time
wf_loop:
        cli
        mov     al, KbdFlags4
        and     al, AckReceived or LEDUpdate or SetRepeat
        cmp     al, ah
        je      short wf_ok ; flag ok, CF=0
        sti
        in      al, dx      ; get vblank
        xor     al, bh
        and     al, 8h
        sub     bh, al
        jnc     short wf_loop     ; IBF - buffer full, no timeout
wf_ok:
        ret
int16 endp

; --------------------- INT 18h - BIOS Basic ------------------
int18 proc near
        push    cs
        pop     es
        mov     si, offset booterrmsg
        call    prts
		;call	flush

;-------------- RS232 bootstrap
        mov     al, 0b4h
        out     43h, al
        mov     ax, 0f000h
        out     42h, al
        out     42h, al      ; 18Hz PIT CH2
		out		1, ax		; disable auto flush on vblank (bit0)
	  mov ds,ax
	  mov es,ax

        mov si,100h
	  call srecb
        cli
	  mov bh,ah
	  call srecb
	  mov bl,ah
sloop:	
	  call srecb
	  mov [si],ah
	  inc si
	  dec bx
	  jnz short sloop
	  db 0eah
        dw 100h,0f000h

booterrmsg db   'SYSTEM HALTED: No boot device available', 13, 10, 0
int18 endp

; --------------------- INT 19h - OS Bootstrap loader ------------------
int19 proc near
        xor     ax, ax
        mov     es, ax
        mov     ax, 201h
        mov     cx, 1
        mov     dx, 80h
        mov     bx, 7c00h
        int     13h
        jc      int19err
        db      0eah
        dw      7c00h, 0     ; jmp far 0000h:7c00h
int19err:
        int     18h
int19 endp


; --------------------- INT 1ah - Get System Time ------------------
int1a proc near
        push    ds
	push	dx
        mov     dx, 40h
        mov     ds, dx
	pop	dx
        cmp     ah, 1
        ja      clockexit
        je      setclock
        mov     dx, ds:[6ch]    ; read clock
        mov     cx, ds:[6eh]
        mov     al, ds:[70h]
clockexit1:
        mov     byte ptr ds:[70h], 0
clockexit:
        cmc     ; CF = 1 on error
        pop     ds
        sti
        retf    2

setclock:
        mov     ds:[6ch], dx
        mov     ds:[6eh], cx
        stc
        jmp     short clockexit1    
int1a endp


; --------------------- INT 70h - RTC ------------------
int70 proc near
        push    ds
        push    ax
        mov     ax, 40h
        mov     ds, ax
        pop     ax
        test    byte ptr UWaitFlag, 1    ; is wait in progress?
		jz      short exit111
        sub     word ptr WaitCount[0], 1000
        sbb     word ptr WaitCount[2], 0
        jnc     short exit44
        mov     byte ptr UWaitFlag, 0
        push    bx
        lds     bx, UFPtr
        or      byte ptr [bx], 80h
        pop     bx
exit111:
	push	ax
	xor	ax, ax
	out	70h, ax	; stop RTC
	pop	ax
exit44: 
	push    ax
	mov     al, 20h
	out     0a0h, al
	mov     al, 20h
	out     20h, al
	pop     ax
        pop     ds
        iret
int70 endp

        
; --------------------- INT 74h - mouse ------------------
int74 proc near
        cld
        
        push    ax
        push    bx
        push    cx
        push    dx
        push    ds
        push    es
        push    ss
        
        push    ds
        mov     ax, 40h
        mov     ds, ax
        
        mov     ah, 0
        in      al, 60h
        mov     bx, ax
        inc     byte ptr DataCounter
        mov     al, DataCounter
        mov     si, ax
        sub     al, 3
        ja      short docall
        mov     DataBuffer[si-1], bl
        cmp     al, PacketSize
        jne     short nocall
        mov     bl, 0
docall:
        mov     byte ptr DataCounter, bh    ; BH=0
        mov     si, offset DataBuffer-2
        lodsw
        or      ax, [si-4]
        jz      short nocall
        sti
        push    es
        mov     ah, 0
        lodsb
        push    ax
        lodsb
        push    ax
        lodsb
        push    ax
        push    bx
        call    far ptr [si-7]
        add     sp, 8
        pop     es
nocall:        
	mov     al, 20h
	out     0a0h, al
	mov     al, 20h
	out     20h, al
        pop     ds
                
        pop    ss
        pop    es
        pop    ds
        pop    dx
        pop    cx
        pop    bx
        pop    ax
        
        iret
int74 endp


; ----------------  serial receive byte 115200 bps --------------
srecb:  mov     ah, 80h
        mov     dx, 3dah
        mov     cx, -5aeh ; (half start bit)
srstb:  in      al, dx
	  shr     al, 2
	  jc      short srstb
        in      al, 42h ; lo counter
        add     ch, al
        in      al, 42h ; hi counter, ignore
l1:
        call    dlybit
	  in      al, dx
        shr     al, 2
	  rcr     ah, 1
	  jnc     short l1
dlybit:
        sub     cx, 0a5bh  ;  (full bit)
dly1:
        in      al, 42h
        cmp     al, ch
        in      al, 42h
        jnz     short dly1
        ret

; -------------------- KB/Mouse access ----------------
sendps2byte proc near   ; ah=data, bl!=0 for mouse, 0 for kb. returns cf=1 if timeout (al = 8)
; changes BH, AL
        push    dx
        mov     dx, 3dah
        mov     bh, 8*5
sps2b2:
        in      al, 64h
        test    al, 2
        jz      short sps2b1; buffer empty
        in      al, dx      ; get vblank
        xor     al, bh
        and     al, 8h
        sub     bh, al
        jnc     short sps2b2; IBF - buffer full, no timeout
        jmp     short exit55  ; timeout, CF=1
sps2b1:
        test    bl, bl      ; CF=0
        jz      short sps2_kb
        mov     al, 0d4h    ; next mouse
        out     64h, al
sps2_kb:
        mov     al, ah
        out     60h, al     ; send byte
exit55:        
        pop     dx
        ret
sendps2byte endp

getps2byte proc near    ; returns al=data, zf=0 for mouse, 1 for kb, cf=1 if timeout (al=8)
; changes BH, DX, AL
        mov     dx, 3dah
        mov     bh, 8*5
gps2b2:
        in      al, 64h
        test    al, 1
        jnz     short gps2b1     ; OBF (buffer full), continue
        in      al, dx     ; get vblank
        xor     al, bh
        and     al, 8
        sub     bh, al
        jnc     short gps2b2     ; buffer empty, no timeout
        ret                ; timeout, CF=1
gps2b1:
        test    al, 20h    ; CF=0, ZF <- !MOBF
        in      al, 60h    ; read byte (if IF=1, this data may be invalid)
        ret
getps2byte endp

sendcmd proc near     ; ah = command, CF=1 for mouse, CF=0 for kb. returns CF=1 on error
        sbb     bl, bl      ; bl <- CF
        call    sendps2byte 
        jc      short exit66
retry:        
        call    getps2byte
        jc      short exit66        
        cmp     al, 0fah    ; ack (returns CF=1 on error, when al=8)
        jne     short retry
exit66:
        ret
sendcmd endp

MouseInit:
; ------------------- Mouse init ----------------
mousei0:        
        call    getps2byte
        jnc     short mousei0
        mov     ah, 0ffh
        call    sendcmd      ; reset mouse (CF = 1)
        jc      short nomouse
        mov     cl, 25
mousei1:        
        dec     cx
        jcxz    short nomouse
        call    getps2byte
        jc      short mousei1
        cmp     al, 0aah     ; BAT
        jne     short nomouse
        call    getps2byte
        cmp     al, 0        ; mouse ID
        je      short mouseok
nomouse:
        mov     al, 0a7h        
        out     64h, al      ; disable mouse
        and     byte ptr EquipmentWord, not 4 ; ps2 mouse not present in equipement word
mouseok:
        ret

KbInit:
; ------------------- KB init ---------------- 
        mov     cx, 25
kbi1:       
        call    getps2byte
        loop    short kbi1  ; wait for kb timeout
        mov     ah, 0ffh    ; reset kb
        clc                 ; kb command
        call    sendcmd   
        jc      short nokb
        mov     cl, 25
kbi2:        
        dec     cx
        jcxz    short nokb
        call    getps2byte
        jc      short kbi2  ; wait for BAT
        cmp     al, 0aah
        jne     short nokb
        mov     ah, 0f2h    ; kb id
        call    sendcmd     ; CF = 0
        jc      short nokb
        call    getps2byte
        cmp     al, 0abh
        jne     short nokb
        call    getps2byte
        cmp     al, 83h
; set scan code 1
IFDEF SCANCODE1
        jne     short nokb
        mov     ah, 0f0h    ; kb scan set
        call    sendcmd   
        jc      short nokb
        mov     ah, 1       ; scan set 1
        call    sendcmd   
        jnc     short kbok
ELSE
        je     short kbok
ENDIF        

nokb:   
        mov     byte ptr KbdFlags3, 0   ; kb not present
kbok:
        ret

enableKbIfPresent proc near ; input DS = 40h
; modify AL, flags
        test    byte ptr KbdFlags3, 10h
        jz      short noenablekb
        mov     al, 0aeh
        out     64h, al     ; enable kb interface
        mov     byte ptr cs:[kbbios], 01h
noenablekb:        
        ret
enableKbIfPresent endp

; ----------------------- default interrupt handler ---------------
defint  proc near
        iret
defint  endp             

; ------------------------------- flush --------------------------
flush:
        pop     cs:flushret
flush_nostack:        
        mov     cs:flushbh, bh
        mov     bh, 64       ; flush all cache lines
flush1:        
        test    bl, cs:[bx + 0bf00h]
        dec     bh
        jnz     short flush1
        mov     bh, cs:flushbh
        jmp     word ptr cs:flushret
flushret dw 0
flushbh  db 0          

; ------------------------------- misc --------------------------
dispAX: 
        push    dx
        xor     dx, dx
        div     word ptr cs:ten
        test    ax, ax
        jz      dispAX1
        call    dispAX
dispAX1:
        xchg    ax, dx
        add     ax, 0e00h + '0'
        int     10h
        pop     dx
        ret        
ten     dw      10

prts:   ; es:si = string
        mov     ah, 0eh    
        lodsb   es:[si]
        or      al, al
        jz      short prtse
        int     10h
        jmp     short prts
prtse:
        ret



;---------------------  read/write byte ----------------------
sdrb:   mov al,0ffh
sdsb:               ; in AL=byte, DX = 0300h, out AX=result
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
                
        in      al, dx
        xchg    ah, al
        
        in      ax, dx
        ret

;---------------------  write block ----------------------
sdwblk proc near              ; in SI=data ptr, DX=0300h, CX=size
        shr     cx, 1
sdwblk1:
        lodsb
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        lodsb
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        add     ax, ax
        out     dx, al
        loop    short sdwblk1
        ret
sdwblk endp

;---------------------  read block ----------------------
sdrblk proc near              ; in DI=data ptr, DX=0300h, CX=size. Returns CF = 0
        mov     al, 0ffh
        out     dx, al
        shr     cx, 1         ; CF = 0
        out     dx, al
        jmp     short sdrblk2 
sdrblk1:
        out     dx, al
        mov     [di], ah
        out     dx, al
        inc     di
sdrblk2:
        out     dx, al
        nop
        out     dx, al
        nop
        out     dx, al
        nop
        out     dx, al
        nop
        out     dx, al
        nop
        out     dx, al
        in      ax, dx
        out     dx, al
        mov     [di], ah
        out     dx, al
        inc     di
        out     dx, al
        nop
        out     dx, al
        nop
        out     dx, al
        nop
        out     dx, al
        nop
        out     dx, al
        nop
        out     dx, al
        in      ax, dx
        loop    short sdrblk1
        mov     [di], ah
        inc     di
        ret
sdrblk endp

;---------------------  verify block ----------------------
sdvblk:              ; in DI=data ptr, DX=0300h, CX=size. Returns CF=1 on error
        push    bx
        xor     bl, bl
sdvblk1:
        call    sdrb
        sub     ah, [di]
        or      bl, ah
        inc     di
        loop    short sdvblk1
        neg     bl  ; CF=1 if BL != 0
        pop     bx
        ret

;---------------------  write command ----------------------
sdcmd8T:
        call    sdrb
sdcmd:              ; in SI=6 bytes cmd buffer, DX=0300h, out AH = 0ffh on error
        mov     cx, 6
        call    sdwblk
sdresp:
        xor     si, si
sdresp1:
        call    sdrb
        inc     si
        jz      short sdcmd1
        cmp     ah, 0ffh
        je      short sdresp1
sdcmd1: ret         

;---------------------  read ----------------------
sdverify:        
        mov     di, sdvblk
        push    di
        
        jmp     short sdread1
sdread:   ; DX:AX sector, ES:BX buffer, CX=sectors. returns AX=read sectors
        cmp     byte ptr cs:[sdtype], 1
        jz      short sdhc1
        push    cx
        mov     cx, 200h
        mul     cx ; DX: AX * 512 for compatibility with SD standard (without HC)        
        pop     cx
sdhc1:       
        mov     di, sdrblk  ; push proc address (read or verify) on stack
        push    di        
        
sdread1:        
        push    ax
        mov     al, dl
        push    ax
        mov     dl, 51h  ; CMD17
        cmp     cx, 1
        je      short sdr1s
        inc     dx      ; CMD18 - multiple sectors
sdr1s:
        push    dx
        mov     si, sp 

        mov     dx, 301h
        mov     ah, 1
        xchg    al, ah
        out     dx, al       ; CS on
        xchg    al, ah
        dec     dx
        mov     di, bx
        mov     bx, cx
        mov     bp, cx       ; save sectors number
        push    ss
        pop     ds
	mov	byte ptr [si+5], 0ffh ; checksum
        call    sdcmd
        add     sp, 6
        or      ah, ah
        jnz     short sdr11   ; error
        push    es
        pop     ds
sdrms:
        mov     ax, di
        push    cx
        mov     cl, 4
        shr     ax, cl
        pop     cx
        mov     si, ds
        add     ax, si
        mov     ds, ax
        and     di, 15
        call    sdresp     ; wait for 0feh token
        cmp     ah, 0feh
        jne     short sdr11; read token error 
        mov     ch, 2      ; 512 byte sector
        pop     si
        call    si         ; sdrblk or sdvblk
        push    si
        pushf
        call    sdrb       ; ignore CRC
        call    sdrb       ; ignore CRC
        popf
        jc      short sdr3 ; verify error   
        dec     bx
        jnz     short sdrms; multiple sectors
sdr3:        
        cmp     bp, 1
        je      short sdr11; single sector
        mov     si, offset SD_CMD12 ; stop transfer
        push    cs
        pop     ds
        call    sdcmd
sdr2:
        shr     ah, 1
        jnc     short sdr11
        call    sdrb
        jmp     short sdr2
sdr11:
        pop     ax         ; remove proc address from stack
sdr1:       
        xor     ax, ax
        inc     dx        
        out     dx, al        
        dec     dx
        call    sdrb       ; 8T
        mov     ax, bp
        sub     ax, bx
        ret     

;---------------------  write ----------------------
sdwrite:   ; DX:AX sector, ES:BX buffer, CX=sectors, returns AX=wrote sectors
        cmp     byte ptr cs:[sdtype], 1
        jz      short sdhc2
        push    cx
        mov     cx, 200h
        mul     cx ; DX: AX * 512 for compatibility with SD standard (without HC)        
        pop     cx
sdhc2: 
        
        push    ax
        mov     al, dl
        push    ax
        mov     dl, 58h  ; CMD24
        cmp     cx, 1
        je      short sdw1s
        inc     dx      ; CMD25 - multiple sectors
sdw1s:
        push    dx
        mov     si, sp 

        mov     dx, 301h
        mov     ah, 1
        xchg    al, ah
        out     dx, al       ; CS on
        xchg    al, ah
        dec     dx
        mov     bp, cx       ; save sectors number
        push    ss
        pop     ds
	mov	byte ptr [si+5], 0ffh ; checksum
        call    sdcmd
        add     sp, 6
        mov     si, bx
        mov     bx, bp
        or      ah, ah
        jnz     short sdr1   ; error
        push    es
        pop     ds
sdwms:
        mov     ax, si
        push    cx
        mov     cl, 4
        shr     ax, cl
        pop     cx
        mov     di, ds
        add     ax, di
        mov     ds, ax
        and     si, 15
        mov     al, 0feh      ; start token
        cmp     bp, 1
        je      short sdw1s1
        mov     al, 0fch   ; multiple sectors
sdw1s1:        
        call    sdsb     
        mov     ch, 2      ; 512 byte sector
        call    sdwblk
        call    sdrb       ; ignore CRC
        call    sdrb       ; ignore CRC
        call    sdrb       ; read response byte xxx00101
        and     ah, 0eh
        cmp     ah, 4
        jne     sdr1 ; write error ; short
sdwwait:
        call    sdrb
        shr     ah, 1
        jnc     short sdwwait     ; wait write completion
        dec     bx
        jnz     short sdwms       ; multiple sectors

        cmp     bp, 1
        je      sdr1
        mov     al, 0fdh     ; multiple end transfer
        call    sdsb 
		call	sdrb     
sdwwait1:
        call    sdrb
        shr     ah, 1
        jnc     short sdwwait1     ; wait write completion
        jmp     sdr1
        
;---------------------  init SD ----------------------
sdinit  proc near       ; returns AX = num kilosectors
        push    ds
        push    cx
        push    dx
        push    si
        push    di
        mov     dx, 300h
        mov     cx, 10
sdinit1:                   ; send 80T
        call    sdrb
        loop    short sdinit1

        mov     ah, 1
        inc     dx
        xchg    al, ah
        out     dx, al       ; select SD
        xchg    al, ah
        dec     dx

        mov     si, offset SD_CMD0
        push    cs
        pop     ds
        call    sdcmd
        dec     ah
        jnz     sdexit ; error
        
        mov     si, offset SD_CMD8
        call    sdcmd8T
        dec     ah
        jnz     sdexit ; error // jnz short
        mov     cl, 4
        sub     sp, cx
        mov     di, sp
        push    ss
        pop     ds
        call    sdrblk
        pop     ax
        pop     ax
        cmp     ah, 0aah
        jne     short sdexit ; CMD8 error
repinit:        
        mov     si, offset SD_CMD55
        push    cs
        pop     ds
        call    sdcmd8T
        call    sdrb
        mov     si, offset SD_CMD41
        call    sdcmd
        dec     ah
        jz      short repinit
        
        mov     si, offset SD_CMD58
        call    sdcmd8T
        mov     cl, 4
        sub     sp, cx
        mov     di, sp
        push    ss
        pop     ds
        call    sdrblk
        pop     ax        
        mov     byte ptr cs:[sdtype], 0
        test    al, 40h     ; test OCR bit 30 (CCS)
        pop     ax
        jz      short standard_sd        
        mov     byte ptr cs:[sdtype], 1
standard_sd:
        mov     si, offset SD_CMD9 ; get size info
        push    cs
        pop     ds
        call    sdcmd8T
        or      ah, ah
        jnz     short sdexit
        call    sdresp     ; wait for 0feh token
        cmp     ah, 0feh
        jne     short sdexit
        mov     cl, 18       ; 16bytes + 2bytes CRC
        sub     sp, cx
        mov     di, sp
        push    ss
        pop     ds
        call    sdrblk
        
        cmp     byte ptr cs:[sdtype], 1
        jnz     short getsize_standard_sd
        mov     cx, [di-10]
        push    ax
        mov     ax, cx
        mov     cl, 8
        rol     ax, cl
        mov     cx, ax        
        pop     ax        
        inc     cx
        mov     sp, di   
sdexit:       
        xor     ax, ax       ; raise CS
        inc     dx
        out     dx, al
        dec     dx
        call    sdrb
        pop     di
        pop     si
        pop     dx
        mov     ax, cx       
        pop     cx
        pop     ds
        ret

getsize_standard_sd: 

; TODO

; Improve this routine to get READ_BL_LEN and C_SIZE_MULT from CSD, references:

; https://www.ele.uva.es/~jesman/BigSeti/ftp/Componentes/Memoria%20SD%20o%20MMC/SD%20Card.pdf
; https://archive.goughlui.com/static/csdecode.htm
; https://www.fatalerrors.org/a/sd-card-initialization-and-command-details.html

; CSD lengh: 16 bytes
; CSD offset 0: [di-18]

; With the current result of C_SIZE + 1 (now CX) obtain the total size in bytes using the following formula: TOTAL_SIZE_BYTES = (C_SIZE + 1) x READ_BL_LEN x C_SIZE_MULT

; Finally perform the following operation: TOTAL_SIZE_MB = (TOTAL_SIZE_BYTES / 1024/1024) x 2
; Save the result again in CX before finishing, with which we will always obtain a correct result for standard SD cards.

        mov     dx, [di-12]
        mov     cl, 10
        and     dx, 3
        shl     dx, cl
        mov     ax, [di-11]
        mov     cl, 2
        shl     ax, cl
        and     ah, 3
        add     dx, ax
        mov     al, [di-10]
        mov     cl, 6
        shr     al, cl
        xor     ah, ah
        add     dx, ax
        inc     dx
        mov     cx, dx
        mov     sp, di
        mov     dx, 300h
        jmp     short sdexit


sdinit endp
    
SD_CMD0     db  40h, 0, 0, 0, 0, 95h
SD_CMD8     db  48h, 0, 0, 1, 0aah, 087h
SD_CMD9     db  49h, 0, 0, 0, 0, 0ffh
SD_CMD12    db  4ch, 0, 0, 0, 0, 0ffh
SD_CMD41    db  69h, 40h, 0, 0, 0, 0ffh
SD_CMD55    db  77h, 0, 0, 0, 0, 0ffh
SD_CMD58    db  7ah, 0, 0, 0, 0, 0ffh


IFDEF SCANCODE1 ; use SCANCODE1
KeyIndex:
        db	0, 82, 49, 50, 52, 51, 54, 55    ;0-7
        db 56, 57, 60, 59, 65, 68, 72, 47    ;8-f
        db	1,  5,  9, 13, 12, 18, 21, 23    ;10-17
        db 24, 26, 67, 70, 69,  0,  4,  3    ;18-1f
        db	8, 11, 17, 16, 20, 22, 25, 64    ;20-27
        db 66, 48,  0, 71,  2,  7,  6, 10    ;28-2f
        db 15, 14, 19, 58, 61, 62,  0, 87    ;30-37
        db	0, 53,  0, 40, 41, 39, 46, 38    ;38-3f
        db 45, 90, 44, 79, 43,  0, 89, 29    ;40-47
        db 34, 36, 86, 28, 37, 33, 84, 27    ;48-4f
        db 32, 35, 30, 31,  0,  0,	0, 83    ;50-57  
        db 42
E0KeyList:
	db	35h, 1ch, 4fh, 4bh, 47h, 52h, 53h, 50h, 4dh, 48h, 51h, 49h 

ELSE    ; use SCANCODE2

KeyIndex:
        db	0, 79,  0, 38, 39, 40, 41, 42
        db	0, 43, 44, 45, 46, 47, 48,  0
        db	0,  0,  0,  0,  0,  1, 49,  0
        db	0,  0,  2,	3,  4,  5, 50,  0
        db	0,  6,  7,	8,  9, 51, 52,  0
        db	0, 53, 10, 11, 12, 13, 54,  0
        db	0, 14, 15, 16, 17, 18, 55,  0
        db	0,  0, 19, 20, 21, 56, 57,  0
        db	0, 58, 22, 23, 24, 59, 60,  0
        db	0, 61, 62, 25, 64, 26, 65,  0
        db	0,  0, 66,	0, 67, 68,	0,  0
        db	0,  0, 69, 70,  0, 71,	0,  0
        db	0,  0,  0,	0,  0,  0, 72,  0
        db	0, 27,  0, 28, 29,  0,	0,  0
        db 30, 31, 32, 37, 33, 34, 82,  0
        db 83, 84, 35, 86, 87, 36, 89,  0
        db	0,  0,  0,	90 	
E0KeyList:
	db	4ah, 5ah, 69h, 6bh, 6ch, 70h, 71h, 72h, 74h, 75h, 7ah, 7dh 

ENDIF

E0KeyIndex:
	db	63,  69,  73,  74,  75,  76,  77,  78,  80,  81,  85,  88

KeyCode:	  
; Keys affected by CapsLock
;		norm   shft   ctrl   alt
        dw	0000h, 0000h, 0000h, 0000h ;17 - <0>
        dw	1071h, 1051h, 1011h, 1000h ;15 - Q, (E0)PrevTrack <1>
        dw	2c7ah, 2c5ah, 2c1ah, 2c00h ;1a - Z <2>
        dw	1f73h, 1f53h, 1f13h, 1f00h ;1b - S <3>
        dw	1e61h, 1e41h, 1e01h, 1e00h ;1c - A <4>
        dw	1177h, 1157h, 1117h, 1100h ;1d - W <5>
        dw	2e63h, 2e43h, 2e03h, 2e00h ;21 - C, (E0)Volume Down <6>
        dw	2d78h, 2d58h, 2d18h, 2d00h ;22 - X <7>
        dw	2064h, 2044h, 2004h, 2000h ;23 - D, (E0)Mute <8>
        dw	1265h, 1245h, 1205h, 1200h ;24 - E <9>
        dw	2f76h, 2f56h, 2f16h, 2f00h ;2a - V <10>
        dw	2166h, 2146h, 2106h, 2100h ;2b - F, (E0)Calculator <11>
        dw	1474h, 1454h, 1414h, 1400h ;2c - T <12>
        dw	1372h, 1352h, 1312h, 1300h ;2d - R <13>
        dw	316eh, 314eh, 310eh, 3100h ;31 - N <14>
        dw	3062h, 3042h, 3002h, 3000h ;32 - B, (E0)Volume Up <15>
        dw	2368h, 2348h, 2308h, 2300h ;33 - H <16>
        dw	2267h, 2247h, 2207h, 2200h ;34 - G, (E0)Play/Pause <17>
        dw	1579h, 1559h, 1519h, 1500h ;35 - Y <18>
        dw	326dh, 324dh, 320dh, 3200h ;3a - M, (E0)WWW Home <19>
        dw	246ah, 244ah, 240ah, 2400h ;3b - J, (E0)Stop <20>
        dw	1675h, 1655h, 1615h, 1600h ;3c - U <21>
        dw	256bh, 254bh, 250bh, 2500h ;42 - K <22>
        dw	1769h, 1749h, 1709h, 1700h ;43 - I <23>
        dw	186fh, 184fh, 180fh, 1800h ;44 - O <24>
        dw	266ch, 264ch, 260ch, 2600h ;4b - L <25>
        dw	1970h, 1950h, 1910h, 1900h ;4d - P, (E0)Next Track <26>
; keys affected by NumLock	
        dw	4f00h, 4f31h, 7500h, 0002h ;69 - KP1 <27>
        dw	4b00h, 4b34h, 7300h, 0005h ;6b - KP4 <28>
        dw	4700h, 4737h, 7700h, 0008h ;6c - KP7 <29>
        dw	5200h, 5230h, 9200h, 0001h ;70 - KP0 <30>
        dw	5300h, 532eh, 9300h, 0000h ;71 - KP. <31>
        dw	5000h, 5032h, 9100h, 0003h ;72 - KP2 <32>
        dw	4d00h, 4d36h, 7400h, 0007h ;74 - KP6 <33>
        dw	4800h, 4838h, 8d00h, 0009h ;75 - KP8 <34>
        dw	5100h, 5133h, 7600h, 0004h ;7a - KP3 <35>
        dw	4900h, 4939h, 8400h, 000ah ;7d - KP9 <36>
        dw	4c00h, 4c35h, 8f00h, 0006h ;73 - KP5 --- on VMWare, it does not send 4c00 <37>
; keys unaffected by CapsLock or N
        dw	3f00h, 5800h, 6200h, 6c00h ;03 - F5 <38>
        dw	3d00h, 5600h, 6000h, 6a00h ;04 - F3 <39>
        dw	3b00h, 5400h, 5e00h, 6800h ;05 - F1 <40>
        dw	3c00h, 5500h, 5f00h, 6900h ;06 - F2 <41>
        dw	8600h, 8800h, 8a00h, 8c00h ;07 - F12 <42>	
        dw	4400h, 5d00h, 6700h, 7100h ;09 - F10 <43>
        dw	4200h, 5b00h, 6500h, 6f00h ;0a - F8 <44>
        dw	4000h, 5900h, 6300h, 6d00h ;0b - F6 <45>
        dw	3e00h, 5700h, 6100h, 6b00h ;0c - F4 <46>
        dw	0f09h, 0f00h, 9400h, 0000h ;0d - TAB <47>	
        dw	2960h, 297eh, 0000h, 2900h ;0e - ` ~ <48>	
        dw	0231h, 0221h, 0000h, 7800h ;16 - 1 ! <49>	
        dw	0332h, 0340h, 0300h, 7900h ;1e - 2 @ <50>	
        dw	0534h, 0524h, 0000h, 7b00h ;25 - 4 $ <51>
        dw	0433h, 0423h, 0000h, 7a00h ;26 - 3 # <52>
        dw	3920h, 3920h, 3920h, 3920h ;29 - SPC <53>	
        dw	0635h, 0625h, 0000h, 7c00h ;2e - 5 % <54>
        dw	0736h, 075eh, 071eh, 7d00h ;36 - 6 ^ <55>
        dw	0837h, 0826h, 0000h, 7e00h ;3d - 7 & <56>
        dw	0938h, 092ah, 0000h, 7f00h ;3e - 8 * <57>
        dw	332ch, 333ch, 0000h, 3300h ;41 - , < <58>
        dw	0b30h, 0b29h, 0000h, 8100h ;45 - 0 ) <59>
        dw	0a39h, 0a28h, 0000h, 8000h ;46 - 9 ( <60>
        dw	342eh, 343eh, 0000h, 3400h ;49 - . > <61>
        dw	352fh, 353fh, 0000h, 3500h ;4a - / ? <62>
        dw	0e02fh, 0e02fh, 9500h, 0a400h ;4a - (e0)KP/ <63>
        dw	273bh, 273ah, 0000h, 2700h ;4c - ; : <64>
        dw	0c2dh, 0c5fh, 0c1fh, 8200h ;4e - - _ <65>
        dw	2827h, 2822h, 0000h, 2800h ;52 - ’ “ <66>
        dw	1a5bh, 1a7bh, 1a1bh, 1a00h ;54 - [ { <67>
        dw	0d3dh, 0d2bh, 0000h, 8300h ;55 - = + <68>	
        dw	1c0dh, 1c0dh, 1c0ah, 1c00h ;5a - Enter, (E0)KPEnter <69>
        dw	1b5dh, 1b7dh, 1b1dh, 1b00h ;5b - ] } <70>
        dw	2b5ch, 2b7ch, 2b1ch, 2b00h ;5d - \ | <71>
        dw	0e08h, 0e08h, 0e7fh, 0e00h ;66 - BKSP <72>
        dw	4f00h, 4f00h, 7500h, 9f00h ;69 - (E0)END <73>
        dw	4b00h, 4b00h, 7300h, 9b00h ;6b - (E0)LEFT <74>
        dw	4700h, 4700h, 7700h, 9700h ;6c - (E0)HOME <75>
        dw	5200h, 5200h, 9200h, 0a200h ;70 - (E0)INS <76>
        dw	5300h, 5300h, 9300h, 0a300h ;71 - (E0)DEL <77>
        dw	5000h, 5000h, 9100h, 0a000h ;72 - (E0)DOWN <78>
        dw	4300h, 5c00h, 6600h, 7000h ;01 - F9 <79>
        dw	4d00h, 4d00h, 7400h, 9d00h ;74 - (E0)RIGHT <80>
        dw	4800h, 4800h, 8d00h, 9800h ;75 - (E0)UP <81>
        dw	011bh, 011bh, 011bh, 0100h ;76 - ESC <82>
        dw	8500h, 8700h, 8900h, 8b00h ;78 - F11 <83>
        dw	4e2bh, 4e2bh, 9000h, 4e00h ;79 - KP+ <84>
        dw	5100h, 5100h, 7600h, 0a100h ;7a - (E0)PGDN <85>
        dw	4a2dh, 4a2dh, 8e00h, 4a00h ;7b - KP- <86>
        dw	372ah, 372ah, 9600h, 3700h ;7c - KP* --- on VMWare, it does not send 3710h with CTL <87>
        dw	4900h, 4900h, 8400h, 9900h ;7d - (E0)PGUP <88>
        dw	4600h, 4600h, 4600h, 4600h ;7e - SCRL <89>
        dw	4100h, 5a00h, 6400h, 6e00h ;83 - F7 <90>

int_1D:
	; CGA test 40x25 modes
	db	38h, 28h, 2Dh, 0Ah, 1Fh, 06h, 19h, 1Ch
	db	02h, 07h, 06h, 07h, 00h, 00h, 00h, 00h

	; CGA text 80x25 modes
	db	71h, 50h, 5Ah, 0Ah, 1Fh, 06h, 19h, 1Ch
	db	02h, 07h, 06h, 07h, 00h, 00h, 00h, 00h

	; CGA graphics modes
	db	38h, 28h, 2Dh, 0Ah, 7Fh, 06h, 64h, 70h
	db	02h, 01h, 06h, 07h, 00h, 00h, 00h, 00h

	; MDA text 80x25 mode
	db	61h, 50h, 52h, 0Fh, 19h, 06h, 19h, 19h
	db	02h, 0Dh, 0Bh, 0Ch, 00h, 00h, 00h, 00h

page_size:
	dw	0800h			; text 40x25 mode
	dw	1000h			; text 80x25 mode
	dw	4000h			; graphics modes
	dw	4000h

columns:
	db	40, 40			; modes 0, 1 - 40x25
	db	80, 80			; modes 2, 3 - 80x25
	db	40, 40			; modes 4, 5 - 40x25
	db	80, 80			; modes 6, 7 - 80x25

MODES	db	2Ch,28h,2Dh,29h,2Ah,2Eh,1Eh,29h ; Table of mode sets

TABMUL	db	00h,00h,10h,10h,20h,20h,20h,30h ; Table lookup for multiply

ramsize dw  0010h                           ; Default BIOS 2MB
kbbios  db  00h                             ; KB already initialized from BIOS
sdtype  db  00h                             ; 00h -> SD, 01h -> SDHC

gfx_font:
	db	 00h, 00h,   00h,  00h,  00h,  00h,  00h,  00h
	db	 7Eh, 81h,  0A5h,  81h, 0BDh,  99h,  81h,  7Eh
	db	 7Eh, 0FFh, 0DBh, 0FFh, 0C3h, 0E7h, 0FFh,  7Eh
	db	 6Ch, 0FEh, 0FEh, 0FEh,  7Ch,  38h,  10h,  00h
	db	 10h,  38h,  7Ch, 0FEh,  7Ch,  38h,  10h,  00h
	db	 38h,  7Ch,  38h, 0FEh, 0FEh,  7Ch,  38h,  7Ch
	db	 10h,  10h,  38h,  7Ch, 0FEh,  7Ch,  38h,  7Ch
	db	 00h,  00h,  18h,  3Ch,  3Ch,  18h,  00h,  00h
	db	0FFh, 0FFh, 0E7h, 0C3h, 0C3h, 0E7h, 0FFh, 0FFh
	db	 00h,  3Ch,  66h,  42h,  42h,  66h,  3Ch,  00h
	db	0FFh, 0C3h,  99h, 0BDh, 0BDh,  99h, 0C3h, 0FFh
	db	 0Fh,  07h,  0Fh,  7Dh, 0CCh, 0CCh, 0CCh,  78h
	db	 3Ch,  66h,  66h,  66h,  3Ch,  18h,  7Eh,  18h
	db	 3Fh,  33h,  3Fh,  30h,  30h,  70h, 0F0h, 0E0h
	db	 7Fh,  63h,  7Fh,  63h,  63h,  67h, 0E6h, 0C0h
	db	 99h,  5Ah,  3Ch, 0E7h, 0E7h,  3Ch,  5Ah,  99h
	db	 80h, 0E0h, 0F8h, 0FEh, 0F8h, 0E0h,  80h,  00h
	db	 02h,  0Eh,  3Eh, 0FEh,  3Eh,  0Eh,  02h,  00h
	db	 18h,  3Ch,  7Eh,  18h,  18h,  7Eh,  3Ch,  18h
	db	 66h,  66h,  66h,  66h,  66h,  00h,  66h,  00h
	db	 7Fh, 0DBh, 0DBh,  7Bh,  1Bh,  1Bh,  1Bh,  00h
	db	 3Eh,  63h,  38h,  6Ch,  6Ch,  38h, 0CCh,  78h
	db	 00h,  00h,  00h,  00h,  7Eh,  7Eh,  7Eh,  00h
	db	 18h,  3Ch,  7Eh,  18h,  7Eh,  3Ch,  18h, 0FFh
	db	 18h,  3Ch,  7Eh,  18h,  18h,  18h,  18h,  00h
	db	 18h,  18h,  18h,  18h,  7Eh,  3Ch,  18h,  00h
	db	 00h,  18h,  0Ch, 0FEh,  0Ch,  18h,  00h,  00h
	db	 00h,  30h,  60h, 0FEh,  60h,  30h,  00h,  00h
	db	 00h,  00h, 0C0h, 0C0h, 0C0h, 0FEh,  00h,  00h
	db	 00h,  24h,  66h, 0FFh,  66h,  24h,  00h,  00h
	db	 00h,  18h,  3Ch,  7Eh,  0FFh, 0FFh, 00h,  00h
	db	 00h, 0FFh, 0FFh,  7Eh,  3Ch,  18h,  00h,  00h
	db	 00h,  00h,  00h,  00h,  00h,  00h,  00h,  00h
	db	 30h,  78h,  78h,  30h,  30h,  00h,  30h,  00h
	db	 6Ch,  6Ch,  6Ch,  00h,  00h,  00h,  00h,  00h
	db	 6Ch,  6Ch, 0FEh,  6Ch, 0FEh,  6Ch,  6Ch,  00h
	db	 30h,  7Ch, 0C0h,  78h,  0Ch, 0F8h,  30h,  00h
	db	 00h, 0C6h, 0CCh,  18h,  30h,  66h, 0C6h,  00h
	db	 38h,  6Ch,  38h,  76h, 0DCh, 0CCh,  76h,  00h
	db	 60h,  60h, 0C0h,  00h,  00h,  00h,  00h,  00h
	db	 18h,  30h,  60h,  60h,  60h,  30h,  18h,  00h
	db	 60h,  30h,  18h,  18h,  18h,  30h,  60h,  00h
	db	 00h,  66h,  3Ch, 0FFh,  3Ch,  66h,  00h,  00h
	db	 00h,  30h,  30h, 0FCh,  30h,  30h,  00h,  00h
	db	 00h,  00h,  00h,  00h,  00h,  30h,  30h,  60h
	db	 00h,  00h,  00h, 0FCh,  00h,  00h,  00h,  00h
	db	 00h,  00h,  00h,  00h,  00h,  30h,  30h,  00h
	db	 06h,  0Ch,  18h,  30h,  60h, 0C0h,  80h,  00h
	db	 7Ch, 0C6h, 0CEh, 0DEh, 0F6h, 0E6h,  7Ch,  00h
	db	 30h,  70h,  30h,  30h,  30h,  30h, 0FCh,  00h
	db	 78h, 0CCh,  0Ch,  38h,  60h, 0CCh, 0FCh,  00h
	db	 78h, 0CCh,  0Ch,  38h,  0Ch, 0CCh,  78h,  00h
	db	 1Ch,  3Ch,  6Ch, 0CCh, 0FEh,  0Ch,  1Eh,  00h
	db	0FCh, 0C0h, 0F8h,  0Ch,  0Ch, 0CCh,  78h,  00h
	db	 38h,  60h, 0C0h, 0F8h, 0CCh, 0CCh,  78h,  00h
	db	0FCh, 0CCh,  0Ch,  18h,  30h,  30h,  30h,  00h
	db	 78h, 0CCh, 0CCh,  78h, 0CCh, 0CCh,  78h,  00h
	db	 78h, 0CCh, 0CCh,  7Ch,  0Ch,  18h,  70h,  00h
	db	 00h,  30h,  30h,  00h,  00h,  30h,  30h,  00h
	db	 00h,  30h,  30h,  00h,  00h,  30h,  30h,  60h
	db	 18h,  30h,  60h, 0C0h,  60h,  30h,  18h,  00h
	db	 00h,  00h, 0FCh,  00h,  00h, 0FCh,  00h,  00h
	db	 60h,  30h,  18h,  0Ch,  18h,  30h,  60h,  00h
	db	 78h, 0CCh,  0Ch,  18h,  30h,  00h,  30h,  00h
	db	 7Ch, 0C6h, 0DEh, 0DEh, 0DEh, 0C0h,  78h,  00h
	db	 30h,  78h, 0CCh, 0CCh, 0FCh, 0CCh, 0CCh,  00h
	db	0FCh,  66h,  66h,  7Ch,  66h,  66h, 0FCh,  00h
	db	 3Ch,  66h, 0C0h, 0C0h, 0C0h,  66h,  3Ch,  00h
	db	0F8h,  6Ch,  66h,  66h,  66h,  6Ch, 0F8h,  00h
	db	0FEh,  62h,  68h,  78h,  68h,  62h, 0FEh,  00h
	db	0FEh,  62h,  68h,  78h,  68h,  60h, 0F0h,  00h
	db	 3Ch,  66h, 0C0h, 0C0h, 0CEh,  66h,  3Eh,  00h
	db	0CCh, 0CCh, 0CCh, 0FCh, 0CCh, 0CCh, 0CCh,  00h
	db	 78h,  30h,  30h,  30h,  30h,  30h,  78h,  00h
	db	 1Eh,  0Ch,  0Ch,  0Ch, 0CCh, 0CCh,  78h,  00h
	db	0E6h,  66h,  6Ch,  78h,  6Ch,  66h, 0E6h,  00h
	db	0F0h,  60h,  60h,  60h,  62h,  66h, 0FEh,  00h
	db	0C6h, 0EEh, 0FEh, 0FEh, 0D6h, 0C6h, 0C6h,  00h
	db	0C6h, 0E6h, 0F6h, 0DEh, 0CEh, 0C6h, 0C6h,  00h
	db	 38h,  6Ch, 0C6h, 0C6h, 0C6h,  6Ch,  38h,  00h
	db	0FCh,  66h,  66h,  7Ch,  60h,  60h, 0F0h,  00h
	db	 78h, 0CCh, 0CCh, 0CCh, 0DCh,  78h,  1Ch,  00h
	db	0FCh,  66h,  66h,  7Ch,  6Ch,  66h, 0E6h,  00h
	db	 78h, 0CCh, 0E0h,  70h,  1Ch, 0CCh,  78h,  00h
	db	0FCh, 0B4h,  30h,  30h,  30h,  30h,  78h,  00h
	db	0CCh, 0CCh, 0CCh, 0CCh, 0CCh, 0CCh, 0FCh,  00h
	db	0CCh, 0CCh, 0CCh, 0CCh, 0CCh,  78h,  30h,  00h
	db	0C6h, 0C6h, 0C6h, 0D6h, 0FEh, 0EEh, 0C6h,  00h
	db	0C6h,  44h,  6Ch,  38h,  38h,  6Ch, 0C6h,  00h
	db	0CCh, 0CCh, 0CCh,  78h,  30h,  30h,  78h,  00h
	db	0FEh, 0C6h,  8Ch,  18h,  32h,  66h, 0FEh,  00h
	db	 78h,  60h,  60h,  60h,  60h,  60h,  78h,  00h
	db	0C0h,  60h,  30h,  18h,  0Ch,  06h,  02h,  00h
	db	 78h,  18h,  18h,  18h,  18h,  18h,  78h,  00h
	db	 10h,  38h,  6Ch, 0C6h,  00h,  00h,  00h,  00h
	db	 00h,  00h,  00h,  00h,  00h,  00h,  00h, 0FFh
	db	 30h,  30h,  18h,  00h,  00h,  00h,  00h,  00h
	db	 00h,  00h,  78h,  0Ch,  7Ch, 0CCh,  7Ch,  00h
	db	 60h,  60h,  60h,  7Ch,  66h,  66h,  7Ch,  00h
	db	 00h,  00h,  78h, 0CCh, 0C0h, 0CCh,  78h,  00h
	db	 0Ch,  0Ch,  0Ch,  7Ch, 0CCh, 0CCh,  7Ch,  00h
	db	 00h,  00h,  78h, 0CCh, 0FCh, 0C0h,  78h,  00h
	db	 38h,  6Ch,  60h, 0F0h,  60h,  60h, 0F0h,  00h
	db	 00h,  00h,  7Ch, 0CCh, 0CCh,  7Ch,  0Ch, 0F8h
	db	 60h,  60h,  7Ch,  66h,  66h,  66h,  66h,  00h
	db	 30h,  00h,  70h,  30h,  30h,  30h,  78h,  00h
	db	 0Ch,  00h,  0Ch,  0Ch,  0Ch,  0Ch,  6Ch,  38h
	db	 60h,  60h,  66h,  6Ch,  78h,  6Ch,  66h,  00h
	db	 70h,  30h,  30h,  30h,  30h,  30h,  78h,  00h
	db	 00h,  00h, 0CCh, 0FEh, 0FEh, 0D6h, 0C6h,  00h
	db	 00h,  00h, 0F8h, 0CCh, 0CCh, 0CCh, 0CCh,  00h
	db	 00h,  00h,  78h, 0CCh, 0CCh, 0CCh,  78h,  00h
	db	 00h,  00h,  7Ch,  66h,  66h,  7Ch,  60h,  60h
	db	 00h,  00h,  7Ch, 0CCh, 0CCh,  7Ch,  0Ch,  0Ch
	db	 00h,  00h, 0DCh,  76h,  66h,  60h, 0F0h,  00h
	db	 00h,  00h,  7Ch, 0C0h,  78h,  0Ch, 0F8h,  00h
	db	 10h,  30h,  7Ch,  30h,  30h,  34h,  18h,  00h
	db	 00h,  00h, 0CCh, 0CCh, 0CCh, 0CCh,  7Ch,  00h
	db	 00h,  00h, 0CCh, 0CCh, 0CCh,  78h,  30h,  00h
	db	 00h,  00h, 0C6h, 0D6h, 0FEh, 0FEh,  6Ch,  00h
	db	 00h,  00h, 0C6h,  6Ch,  38h,  6Ch, 0C6h,  00h
	db	 00h,  00h, 0CCh, 0CCh, 0CCh,  7Ch,  0Ch, 0F8h
	db	 00h,  00h, 0FCh,  98h,  30h,  64h, 0FCh,  00h
	db	 1Ch,  30h,  30h, 0E0h,  30h,  30h,  1Ch,  00h
	db	 18h,  18h,  18h,  00h,  18h,  18h,  18h,  00h
	db	0E0h,  30h,  30h,  1Ch,  30h,  30h, 0E0h,  00h
	db	 76h, 0DCh,  00h,  00h,  00h,  00h,  00h,  00h
	db	 00h,  10h,  38h,  6Ch, 0C6h, 0C6h, 0FEh,  00h

; ------------------------- POWER ON RESET -----------------------
        org     0fff0h
        
        db      0eah        
        dw      coldboot, 0f000h
        db      '05/05/22'
        db      0ffh, 0ffh, 0
end bios