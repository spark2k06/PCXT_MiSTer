cpu 8086
bits 16
org 100h

; DOS smoke test for mcga13tsr.com.
;
; Run after installing the TSR:
;   MCGA13TSR.COM
;   MCGA13CHK.COM

start:
    push cs
    pop ds

    mov ax, 0013h
    int 10h

    mov ah, 0Fh
    int 10h
    cmp al, 13h
    jne fail_mode
    cmp ah, 40
    jne fail_mode
    or bh, bh
    jne fail_mode

    mov ah, 0Ch
    mov al, 5Ah
    xor bh, bh
    mov cx, 37
    mov dx, 23
    int 10h

    mov ah, 0Dh
    xor bh, bh
    mov cx, 37
    mov dx, 23
    int 10h
    cmp al, 5Ah
    jne fail_pixel

    mov ax, 1010h
    mov bx, 005Ah
    mov dh, 3Fh
    mov ch, 15h
    mov cl, 2Ah
    int 10h

    mov ax, 1015h
    mov bx, 005Ah
    int 10h
    cmp dh, 3Fh
    jne fail_palette
    cmp ch, 15h
    jne fail_palette
    cmp cl, 2Ah
    jne fail_palette

    mov dx, msg_ok
    mov bl, 00h
    jmp finish

fail_mode:
    mov dx, msg_mode
    mov bl, 01h
    jmp finish

fail_pixel:
    mov dx, msg_pixel
    mov bl, 02h
    jmp finish

fail_palette:
    mov dx, msg_palette
    mov bl, 03h

finish:
    push dx
    push bx
    mov ax, 0003h
    int 10h
    pop bx
    pop dx
    mov ah, 09h
    int 21h
    mov al, bl
    mov ah, 4Ch
    int 21h

msg_ok:      db 'MCGA13CHK OK', 13, 10, '$'
msg_mode:    db 'MCGA13CHK mode report failed', 13, 10, '$'
msg_pixel:   db 'MCGA13CHK pixel read/write failed', 13, 10, '$'
msg_palette: db 'MCGA13CHK palette service failed', 13, 10, '$'
