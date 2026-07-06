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
; programs the DAC through INT 10h AX=1010h and fills A000:0000 with vertical
; color bars. Press any key to return to text mode.

%define MCGA_FB_SEG    0A000h

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
    xor bx, bx
.next:
    mov al, bl
    and al, 03h
    call scale_2bit_to_dac
    mov dh, al

    mov al, bl
    shr al, 1
    shr al, 1
    and al, 03h
    call scale_2bit_to_dac
    mov ch, al

    mov al, bl
    shr al, 1
    shr al, 1
    shr al, 1
    shr al, 1
    and al, 03h
    call scale_2bit_to_dac
    mov cl, al

    mov ax, 1010h
    int 10h
    inc bl
    cmp bl, 40h
    jne .next
    ret

scale_2bit_to_dac:
    mov ah, al
    shl al, 1
    shl al, 1
    add al, ah
    shl al, 1
    shl al, 1
    add al, ah
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
    inc bl
    dec dx
    jne .bar

    dec bp
    jne .row
    ret

msg_mode_fail:
    db 'MCGA13BAR: INT 10h mode 13h was not reported. Is MCGA13TSR loaded and MCGA Gate enabled?', 13, 10, '$'
