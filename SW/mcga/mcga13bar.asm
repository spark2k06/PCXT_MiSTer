cpu 8086
bits 16
org 100h

; MCGA mode 13h diagnostic bars.
;
; Run after installing the TSR:
;   MCGA13TSR.COM
;   MCGA13BAR.COM
;
; The program asks BIOS for mode 13h, verifies the TSR reports mode 13h, then
; programs the DAC directly through ports 03C8h/03C9h and fills A000:0000 with
; vertical color bars. Press any key to return to text mode.

%define MCGA_FB_SEG    0A000h
%define VGA_DAC_WRITE  03C8h
%define VGA_DAC_DATA   03C9h

start:
    push cs
    pop ds

    mov ax, 0013h
    int 10h

    mov ah, 0Fh
    int 10h
    cmp al, 13h
    jne mode_fail

    call program_palette
    call draw_bars

    xor ax, ax
    int 16h

    mov ax, 0003h
    int 10h
    mov ax, 4C00h
    int 21h

mode_fail:
    mov ax, 0003h
    int 10h
    mov dx, msg_mode_fail
    mov ah, 09h
    int 21h
    mov ax, 4C01h
    int 21h

program_palette:
    mov dx, VGA_DAC_WRITE
    xor al, al
    out dx, al
    mov dx, VGA_DAC_DATA

    mov cx, 256
    xor bl, bl
.next:
    mov al, bl
    and al, 3Fh
    out dx, al

    mov al, bl
    shr al, 1
    shr al, 1
    and al, 3Fh
    out dx, al

    mov al, bl
    shr al, 1
    shr al, 1
    shr al, 1
    shr al, 1
    and al, 3Fh
    out dx, al

    inc bl
    loop .next
    ret

draw_bars:
    mov ax, MCGA_FB_SEG
    mov es, ax
    xor di, di

    mov bp, 200
.row:
    xor bl, bl
    mov dx, 64
.bar:
    mov al, bl
    stosb
    stosb
    stosb
    stosb
    stosb
    add bl, 4
    dec dx
    jne .bar

    dec bp
    jne .row
    ret

msg_mode_fail:
    db 'MCGA13BAR: INT 10h mode 13h was not reported. Is MCGA13TSR loaded and MCGA Gate enabled?', 13, 10, '$'
