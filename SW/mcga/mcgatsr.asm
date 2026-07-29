cpu 8086
bits 16
org 100h

; MCGA mode 13h development TSR for PCXT_MiSTer.
;
; Build:
;   nasm -O9 -f bin -o mcgatsr.com mcgatsr.asm
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

    ; Refuse to install when the OSD has MCGA mode 13h switched off. The hook
    ; below answers "VGA present" to INT 10h AH=1Ah, and on a machine that will
    ; never render mode 13h that answer sends games down a path which leaves the
    ; screen black. The core reports 13h on the control port when it is enabled.
    mov dx, MCGA_CTRL_PORT
    in al, dx
    cmp al, 13h
    je .install
    mov dx, msg_disabled
    mov ah, 09h
    int 21h
    mov ax, 4C01h
    int 21h

.install:
    mov ax, 3510h
    int 21h
    mov [old10_off], bx
    mov [old10_seg], es

    mov dx, int10_hook
    mov ax, 2510h
    int 21h

    ; INT 21h/AH=31h counts paragraphs from the PSP, which is where this segment
    ; starts, so resident_end doubles as the byte count. Derive the paragraph
    ; count from it rather than hardcoding one: a hardcoded value silently stops
    ; covering the hook as soon as the code grows, and DOS then hands the tail of
    ; the INT 10h handler out to the next allocation.
    mov dx, (resident_end - $$ + 100h + 15) / 16
    mov ax, 3100h
    int 21h

int10_hook:
    cmp ah, 00h
    jne .check_get_mode
    ; Bit 7 of AL is the standard "do not clear video memory" flag, part of
    ; the mode number on any VGA BIOS; games do use AL=93h to re-enter mode
    ; 13h without a flash. Mask it only for the compare, so AX keeps flowing
    ; into set_mode13/clear_and_chain exactly as the caller passed it.
    push ax
    and al, 7Fh
    cmp al, 13h
    pop ax
    jne .clear_and_chain
    push ax
    call mcga_available
    pop ax
    je .set_mode13
    ; MCGA was switched off in the OSD after we went resident. Treat the request
    ; like any other mode set and let the video BIOS reject it, so the caller
    ; falls back instead of drawing into a mode nothing will display.

.clear_and_chain:
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
    jne .check_ega_info
    cmp byte [cs:current_mode], 13h
    jne .chain
    mov al, 13h
    mov ah, 40
    xor bh, bh
    iret

.check_ega_info:
    cmp ah, 12h
    jne .check_display_combination
    cmp bl, 10h
    jne .chain
    push ax
    call mcga_available
    pop ax
    jne .chain
    xor bh, bh
    mov bl, 03h
    mov cx, 0009h
    iret

.check_display_combination:
    cmp ah, 1Ah
    jne .check_write_pixel
    or al, al
    jne .chain
    push ax
    call mcga_available
    pop ax
    jne .chain
    mov ax, 001Ah
    mov bx, 0008h
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
    ; The DAC subfunctions (AL=10h/12h/15h/17h) are VGA-only: the EGA BIOS
    ; underneath does not implement them and drops them silently. The core's
    ; DAC now feeds every mode, not just mode 13h (see ega_dac_hit in
    ; ega_top.v), so serve these in any mode, gated only on MCGA being
    ; available, matching how a real VGA answers this call regardless of
    ; the current video mode.
    push ax
    call mcga_available
    pop ax
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
    ; No "xor bh, bh" here: AH=00h has no BH return value, and a mode set is
    ; called often enough that zeroing a caller's register is a real hazard.
    ; The page number in BH belongs to AH=0Fh, which sets it above.
    iret

.chain:
    jmp far [cs:old10_off]

; Returns ZF=1 when the core reports MCGA mode 13h available. Checked on every
; call rather than cached, because the OSD option can be toggled while resident.
; Clobbers AL; POP and RET leave the compare flags intact.
mcga_available:
    push dx
    mov dx, MCGA_CTRL_PORT
    in al, dx
    cmp al, 13h
    pop dx
    ret

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

; AL=15h returns DH=red, CH=green, CL=blue and nothing else: a real VGA BIOS
; leaves BX and DL alone. BH is only borrowed to hold red across the reads, so
; it has to be restored, and DX has to be put back before DH is loaded. Getting
; this wrong hangs fade loops that keep their step counter in BH, which is the
; usual place for it - every call would overwrite the counter with a colour
; component and the fade would never reach its last step.
read_one_dac:
    push ax
    push bx
    push dx
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
    mov al, bh
    pop dx
    mov dh, al
    pop bx
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

; Only reached before going resident, so keep it outside the retained block.
msg_disabled:   db 'MCGA mode 13h is disabled in the OSD; TSR not installed.', 13, 10, '$'
