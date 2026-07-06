cpu 8086
bits 16
org 100h

; MCGA mode 13h development TSR for PCXT_MiSTer.
;
; Build:
;   nasm -O9 -f bin -o mcga13tsr.com mcga13tsr.asm
;
; Installs an INT 10h hook. AX=0013h updates the BIOS Data Area and writes
; 13h to the temporary MCGA control port 03CDh. While mode 13h is active, the
; hook provides the minimal BIOS calls needed by bring-up software. Any other
; INT 10h AH=00h mode set clears the MCGA control port and chains to the
; existing video BIOS, normally the IBM EGA ROM.

%define INT10_VECTOR      10h
%define MCGA_CTRL_PORT    03CDh
%define MCGA_FB_SEG       0A000h
%define VGA_DAC_READ      03C7h
%define VGA_DAC_WRITE     03C8h
%define VGA_DAC_DATA      03C9h

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

    ; INT 21h/AH=31h counts paragraphs from the PSP. 40h paragraphs keep the
    ; 100h-byte PSP plus the resident hook. Keep this conservative: if the hook
    ; grows past the retained block, DOS can overwrite the INT 10h handler.
    mov dx, 40h
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
    jne .check_write_pixel
    cmp byte [cs:current_mode], 13h
    jne .chain
    mov al, 13h
    mov ah, 40
    xor bh, bh
    iret

.check_write_pixel:
    cmp ah, 0Ch
    jne .check_read_pixel
    cmp byte [cs:current_mode], 13h
    jne .chain
    call write_pixel
    iret

.check_read_pixel:
    cmp ah, 0Dh
    jne .check_palette
    cmp byte [cs:current_mode], 13h
    jne .chain
    call read_pixel
    iret

.check_palette:
    cmp ah, 10h
    jne .chain
    cmp byte [cs:current_mode], 13h
    jne .chain
    cmp al, 10h
    je .set_one_dac
    cmp al, 12h
    je .set_dac_block
    cmp al, 15h
    je .read_one_dac
    cmp al, 17h
    je .read_dac_block
    jmp .chain

.set_one_dac:
    call set_one_dac
    iret

.set_dac_block:
    call set_dac_block
    iret

.read_one_dac:
    call read_one_dac
    iret

.read_dac_block:
    call read_dac_block
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

write_pixel:
    or bh, bh
    jne .done
    cmp cx, 320
    jae .done
    cmp dx, 200
    jae .done

    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov bl, al
    mov si, dx
    shl si, 1
    shl si, 1
    shl si, 1
    shl si, 1
    shl si, 1
    shl si, 1
    mov di, dx
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    add di, si
    add di, cx
    mov ax, MCGA_FB_SEG
    mov es, ax
    mov [es:di], bl

    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.done:
    ret

read_pixel:
    xor al, al
    or bh, bh
    jne .done
    cmp cx, 320
    jae .done
    cmp dx, 200
    jae .done

    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov si, dx
    shl si, 1
    shl si, 1
    shl si, 1
    shl si, 1
    shl si, 1
    shl si, 1
    mov di, dx
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    shl di, 1
    add di, si
    add di, cx
    mov ax, MCGA_FB_SEG
    mov es, ax
    mov al, [es:di]

    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
.done:
    ret

set_one_dac:
    push ax
    push bx
    push dx
    mov bh, dh
    mov dx, VGA_DAC_WRITE
    mov al, bl
    out dx, al
    inc dx
    mov al, bh
    out dx, al
    mov al, ch
    out dx, al
    mov al, cl
    out dx, al
    pop dx
    pop bx
    pop ax
    ret

set_dac_block:
    push ax
    push bx
    push cx
    push dx
    push si
    mov si, dx
    mov dx, VGA_DAC_WRITE
    mov al, bl
    out dx, al
    inc dx
    jcxz .done
.next:
    mov al, [es:si]
    out dx, al
    inc si
    mov al, [es:si]
    out dx, al
    inc si
    mov al, [es:si]
    out dx, al
    inc si
    loop .next
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

read_one_dac:
    push ax
    mov dx, VGA_DAC_READ
    mov al, bl
    out dx, al
    mov dx, VGA_DAC_DATA
    in al, dx
    mov bh, al
    in al, dx
    mov ch, al
    in al, dx
    mov cl, al
    mov dh, bh
    pop ax
    ret

read_dac_block:
    push ax
    push bx
    push cx
    push dx
    push di
    mov di, dx
    mov dx, VGA_DAC_READ
    mov al, bl
    out dx, al
    mov dx, VGA_DAC_DATA
    jcxz .done
.next:
    in al, dx
    mov [es:di], al
    inc di
    in al, dx
    mov [es:di], al
    inc di
    in al, dx
    mov [es:di], al
    inc di
    loop .next
.done:
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

old10_off:      dw 0
old10_seg:      dw 0
current_mode:   db 0

resident_end:
