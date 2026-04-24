bits 16
org 0

;=========================================================================
; ega_bios.asm - Minimal EGA BIOS Extension for Prehistorik (MiSTer PCXT)
;
; Hooks both INT 10h (video services) and INT 11h (equipment list).
; INT 11h is CRITICAL: Prehistorik reads equipment word bits 4-5 to
; verify EGA presence. Without this hook, it sees CGA and shows
; "Configuración no detectada".
;
; Compile: nasm -O9 -f bin -o ega_bios.rom ega_bios.asm
;=========================================================================

%define ROM_SIZE   2048
%define ROM_BLOCKS (ROM_SIZE / 512)

%define INT10_VEC  0x40   ; 0000:0040 = INT 10h vector
%define INT11_VEC  0x44   ; 0000:0044 = INT 11h vector
%define BDA_SEG    0x40
%define BDA_VGA_PTR 0xA8  ; 0040:00A8 VGA Save/Override Table pointer

    db 055h, 0AAh, ROM_BLOCKS   ; ROM signature

;=========================================================================
; INIT
;=========================================================================
init:
    call save_old_int10
    call save_old_int11
    call probe_ega_gate
    mov [cs:video_type], al
    mov ax, 0003h
    call call_old_int10
    mov byte [cs:current_mode], 03h
    mov byte [cs:current_cols], 50h
    mov byte [cs:current_page], 0
    cmp byte [cs:video_type], 0
    jz .exit
    call install_int10_hook
    call install_int11_hook
    call install_vga_bda_ptr
.exit:
    retf

save_old_int10:
    push ds
    xor ax, ax
    mov ds, ax
    mov ax, [INT10_VEC]
    mov [cs:old10_off], ax
    mov ax, [INT10_VEC+2]
    mov [cs:old10_seg], ax
    pop ds
    ret

save_old_int11:
    push ds
    xor ax, ax
    mov ds, ax
    mov ax, [INT11_VEC]
    mov [cs:old11_off], ax
    mov ax, [INT11_VEC+2]
    mov [cs:old11_seg], ax
    pop ds
    ret

install_int10_hook:
    push ds
    xor ax, ax
    mov ds, ax
    mov word [INT10_VEC], int10_hook
    mov ax, cs
    mov [INT10_VEC+2], ax
    pop ds
    ret

install_int11_hook:
    push ds
    xor ax, ax
    mov ds, ax
    mov word [INT11_VEC], int11_hook
    mov ax, cs
    mov [INT11_VEC+2], ax
    pop ds
    ret

install_vga_bda_ptr:
    push ds
    mov ax, BDA_SEG
    mov ds, ax
    mov word [BDA_VGA_PTR], ega_vga_table_stub
    mov ax, cs
    mov [BDA_VGA_PTR+2], ax
    pop ds
    ret

probe_ega_gate:
    push bx
    push dx
    mov dx, 3C4h
    mov al, 04h
    out dx, al
    inc dx
    in al, dx
    mov ah, al
    xor al, 04h
    mov bl, al
    out dx, al
    in al, dx
    mov bh, al
    mov al, ah
    out dx, al
    xor al, al
    cmp bh, bl
    jne .done
    mov al, 1
.done:
    pop dx
    pop bx
    ret

call_old_int10:
    pushf
    call far [cs:old10_off]
    ret

chain_old_int10:
    pushf
    call far [cs:old10_off]
    iret

chain_old_int11:
    pushf
    call far [cs:old11_off]
    iret

;=========================================================================
; int11_hook - Return equipment list with EGA bit set
;
; CRITICAL: Prehistorik calls INT 11h after user selects EGA mode.
; It checks bits 4-5 of AX. Value 00 = EGA/VGA, 01/10 = CGA, 11 = MDA.
; We return 0x44C0 (EGA, DMA, 2 serial, game port, 3 parallel)
;=========================================================================
int11_hook:
    mov ax, 044C0h    ; EGA (bits 4-5=00), DMA, 2 serial, game, 3 parallel
    iret

;=========================================================================
; int10_hook
;=========================================================================
int10_hook:
    cmp ah, 12h
    jne .chk_mode
    cmp bl, 10h
    jne .chk30
    cmp byte [cs:video_type], 2
    je .is_vga
.is_ega:
    mov bh, 00h
    mov bl, 03h
    mov cl, 09h
    iret
.is_vga:
    mov bh, 01h
    mov bl, 03h
    mov cl, 08h
    iret
.chk30:
    cmp bl, 30h
    jne .chk32
    mov bx, 1224h
    mov cl, 34h
    iret
.chk32:
    cmp bl, 32h
    jne chain_old_int10
    mov bh, 00h
    mov bl, 00h
    iret

.chk_mode:
    cmp ah, 00h
    jne .chk_pal
    cmp al, 0Dh
    je .mode0d
    cmp al, 07h
    jbe .txtmode
    jmp chain_old_int10

.chk_pal:
    cmp ah, 10h
    jne .chk_get
    cmp al, 00h
    je .pal_one
    cmp al, 01h
    je .pal_overscan
    cmp al, 02h
    je .pal_all
    jmp chain_old_int10

.chk_get:
    cmp ah, 0Fh
    jne chain_old_int10
    mov al, [cs:current_mode]
    mov ah, [cs:current_cols]
    mov bh, [cs:current_page]
    iret

.txtmode:
    mov [cs:current_mode], al
    mov byte [cs:current_page], 0
    cmp al, 02h
    jb .c40
    cmp al, 03h
    jbe .c80
    cmp al, 06h
    je .c80
    cmp al, 07h
    je .c80
.c40:
    mov byte [cs:current_cols], 28h
    jmp chain_old_int10
.c80:
    mov byte [cs:current_cols], 50h
    jmp chain_old_int10

.mode0d:
    push ax
    push bx
    push cx
    push dx
    push si
    call set_mode_0d_regs
    mov byte [cs:current_mode], 0Dh
    mov byte [cs:current_cols], 28h
    mov byte [cs:current_page], 0
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret

.pal_one:
    push ax
    push bx
    call attr_write
    mov dx, 3DAh
    in al, dx
    mov dx, 3C0h
    mov al, 20h
    out dx, al
    pop bx
    pop ax
    iret

.pal_overscan:
    push ax
    push bx
    mov bl, 11h
    call attr_write
    mov dx, 3DAh
    in al, dx
    mov dx, 3C0h
    mov al, 20h
    out dx, al
    pop bx
    pop ax
    iret

.pal_all:
    push ax
    push bx
    push cx
    push dx
    push si
    push ds
    push es
    pop ds
    mov si, dx
    xor bx, bx
    mov cx, 16
.pl:
    mov bh, [si]
    call attr_write
    inc si
    inc bl
    loop .pl
    mov bl, 11h
    mov bh, [si]
    call attr_write
    mov dx, 3DAh
    in al, dx
    mov dx, 3C0h
    mov al, 20h
    out dx, al
    pop ds
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret

;=========================================================================
; set_mode_0d_regs
;=========================================================================
set_mode_0d_regs:
    mov dx, 3C2h
    mov al, 63h     ; bit7=0: 200-line mode (pallook16), bit5=1: page sel, bit1=1: enable RAM, bit0=1: color I/O
    out dx, al
    mov ax, 0100h
    call seq_write
    mov ax, 0901h
    call seq_write
    mov ax, 0F02h
    call seq_write
    mov ax, 0003h
    call seq_write
    mov ax, 0604h
    call seq_write
    mov ax, 0300h
    call seq_write
    xor ax, ax
    call gfx_write
    mov ax, 0001h
    call gfx_write
    mov ax, 0002h
    call gfx_write
    mov ax, 0003h
    call gfx_write
    mov ax, 0004h
    call gfx_write
    mov ax, 0005h
    call gfx_write
    mov ax, 0506h
    call gfx_write
    mov ax, 0F07h
    call gfx_write
    mov ax, 0FF08h
    call gfx_write
    mov si, crtc_data
    xor bx, bx
    mov cx, 16
.cl:
    mov al, bl
    mov ah, [cs:si]
    call crtc_write
    inc si
    inc bl
    loop .cl
    mov si, palette_data
    xor bx, bx
.al:
    mov bh, [cs:si]
    call attr_write
    inc si
    inc bl
    cmp bl, 16
    jb .al
    mov bx, 0110h
    call attr_write
    mov bx, 0011h
    call attr_write
    mov bx, 0F12h
    call attr_write
    mov bx, 0013h
    call attr_write
    mov dx, 3DAh
    in al, dx
    mov dx, 3C0h
    mov al, 20h
    out dx, al
    ret

;=========================================================================
; Hardware write helpers
;=========================================================================
seq_write:
    push dx
    mov dx, 3C4h
    out dx, al
    inc dx
    mov al, ah
    out dx, al
    pop dx
    ret

gfx_write:
    push dx
    mov dx, 3CEh
    out dx, al
    inc dx
    mov al, ah
    out dx, al
    pop dx
    ret

crtc_write:
    push dx
    mov dx, 3D4h
    out dx, al
    inc dx
    mov al, ah
    out dx, al
    pop dx
    ret

attr_write:
    push ax
    push dx
    mov dx, 3DAh
    in al, dx
    mov dx, 3C0h
    mov al, bl
    out dx, al
    mov al, bh
    out dx, al
    pop dx
    pop ax
    ret

;=========================================================================
; Variables and data
;=========================================================================
old10_off:      dw 0
old10_seg:      dw 0
old11_off:      dw 0
old11_seg:      dw 0
video_type:     db 0
current_mode:   db 03h
current_cols:   db 50h
current_page:   db 0

; CRTC timing for 320x200 (16 registers R0-RF)
crtc_data:
    db 38h, 28h, 2Dh, 05h, 1Fh, 06h, 19h, 1Ch
    db 00h, 07h, 06h, 07h, 00h, 00h, 00h, 00h

; Palette for mode 0Dh (16 entries) - standard IBM EGA values
; Entry 6 = 06h: with pallook16 (bit7=0 in Misc Output), value 6 triggers
; the brown exception in ega_vgaport: (color & 0x17)==0x06 -> R=0xAA,G=0x55,B=0
palette_data:
    db 00h, 01h, 02h, 03h, 04h, 05h, 06h, 07h
    db 38h, 39h, 3Ah, 3Bh, 3Ch, 3Dh, 3Eh, 3Fh

; Minimal non-null VGA save/override table placeholder.
ega_vga_table_stub:
    db 00h, 00h, 00h, 00h

    times ROM_SIZE - ($ - $$) - 1 db 0
checksum_byte: db 009h
