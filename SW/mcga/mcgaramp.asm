cpu 8086
bits 16
org 100h

; Visual MCGA mode 13h smoke program.
;
; Requires mcgatsr.com to be installed first. The program sets mode 13h,
; programs a 256-entry DAC ramp through INT 10h, fills A000:0000 with a color
; ramp, waits for one key, and returns to text mode.

%define MCGA_FB_SEG 0A000h

start:
    mov ax, 0013h
    int 10h

    call program_palette
    call draw_ramp

    xor ax, ax
    int 16h

    mov ax, 0003h
    int 10h

    mov ax, 4C00h
    int 21h

program_palette:
    xor bx, bx
.next:
    mov ax, 1010h

    mov dh, bl
    and dh, 3Fh

    mov ch, bl
    shr ch, 1
    shr ch, 1
    and ch, 3Fh

    mov cl, bl
    shr cl, 1
    shr cl, 1
    shr cl, 1
    shr cl, 1
    and cl, 3Fh

    int 10h
    inc bx
    cmp bx, 0100h
    jne .next
    ret

draw_ramp:
    mov ax, MCGA_FB_SEG
    mov es, ax
    xor di, di
    mov cx, 64000
    xor al, al
.next:
    stosb
    inc al
    loop .next
    ret
