cpu 8086
bits 16
org 100h

; MCGA mode 13h development TSR for PCXT_MiSTer.
;
; Build:
;   nasm -O9 -f bin -o mcga13tsr.com mcga13tsr.asm
;
; Installs an INT 10h hook. AX=0013h updates the BIOS Data Area and writes
; 13h to the temporary MCGA control port 03CDh. INT 10h AH=0Fh reports mode
; 13h while active. Any other INT 10h AH=00h mode set clears the MCGA control
; port and chains to the existing video BIOS, normally the IBM EGA ROM.

%define INT10_VECTOR      10h
%define MCGA_CTRL_PORT    03CDh

%define BDA_SEG           0040h
%define BDA_MODE          0049h
%define BDA_COLS          004Ah
%define BDA_REGEN_SIZE    004Ch
%define BDA_PAGE_OFFSET   004Eh
%define BDA_ACTIVE_PAGE   0062h

start:
    push cs
    pop ds
    mov ax, 3510h
    int 21h
    mov [old10_off], bx
    mov [old10_seg], es

    mov dx, int10_hook
    mov ax, 2510h
    int 21h

    ; INT 21h/AH=31h counts paragraphs from the PSP. 20h paragraphs keep the
    ; 100h-byte PSP plus this small resident hook with room to spare.
    mov dx, 20h
    mov ax, 3100h
    int 21h

int10_hook:
    cmp ah, 00h
    jne .check_get_mode
    cmp al, 13h
    je .set_mode13

    push ax
    push dx
    mov dx, MCGA_CTRL_PORT
    xor al, al
    out dx, al
    mov byte [cs:current_mode], 00h
    pop dx
    pop ax
    jmp far [cs:old10_off]

.check_get_mode:
    cmp ah, 0Fh
    jne .chain
    cmp byte [cs:current_mode], 13h
    jne .chain
    mov al, 13h
    mov ah, 40
    xor bh, bh
    iret

.set_mode13:
    push ax
    push bx
    push dx
    push ds

    mov dx, MCGA_CTRL_PORT
    mov al, 13h
    out dx, al

    mov ax, BDA_SEG
    mov ds, ax
    mov byte [BDA_MODE], 13h
    mov word [BDA_COLS], 40
    mov word [BDA_REGEN_SIZE], 0FA00h
    mov word [BDA_PAGE_OFFSET], 0000h
    mov byte [BDA_ACTIVE_PAGE], 00h

    pop ds
    pop dx
    pop bx
    pop ax

    mov byte [cs:current_mode], 13h
    mov al, 13h
    mov ah, 40
    xor bh, bh
    iret

.chain:
    jmp far [cs:old10_off]

old10_off:      dw 0
old10_seg:      dw 0
current_mode:   db 0

resident_end:
