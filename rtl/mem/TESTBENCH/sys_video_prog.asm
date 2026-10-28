; Test program for sys_video_tb: the CPU writes and reads the CGA and HGC video
; memory (now in SDRAM) while both cards are scanning it.
;
;   nasm -f bin sys_video_prog.asm -o sys_video_prog.bin
;   python3 mkhex.py sys_video_prog.bin sys_video_prog.hex      (see run_tests.sh)
;
; Result, in RAM: 0000:0600 = number of read-back errors (0 = good),
;                 0000:0602 = BEEF when the program is done.
; The bench also checks the video memory contents in the chip.
bits 16
org 0

start:
    cli
    cld
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, 0x7C00
    xor     bp, bp                  ; error count

    ; ---- CGA, 80x25 text (the power-up CRTC values) ----
    mov     dx, 0x3D8
    mov     al, 0x29
    out     dx, al

    mov     ax, 0xB800
    mov     es, ax
    xor     di, di
    mov     cx, 2000
    xor     bl, bl
.cga_fill:
    mov     al, bl
    stosb
    add     bl, 3
    loop    .cga_fill

    mov     ax, 0xB800
    mov     ds, ax
    xor     si, si
    mov     cx, 2000
    xor     bl, bl
.cga_check:
    lodsb
    cmp     al, bl
    je      .cga_ok
    inc     bp
.cga_ok:
    add     bl, 3
    loop    .cga_check

    ; 16 KiB mirror: write at B800:0010, read at BC00:0010
    mov     byte [0x0010], 0x5A
    mov     ax, 0xBC00
    mov     ds, ax
    cmp     byte [0x0010], 0x5A
    je      .mirror_ok
    inc     bp
.mirror_ok:

    ; ---- HGC: allow graphics page 1, text mode ----
    mov     dx, 0x3BF
    mov     al, 0x03
    out     dx, al
    mov     dx, 0x3B8
    mov     al, 0x28
    out     dx, al

    mov     ax, 0xB000
    mov     es, ax
    xor     di, di
    mov     cx, 2000
    mov     bl, 0x11
.hgc_fill:
    mov     al, bl
    stosb
    add     bl, 5
    loop    .hgc_fill

    mov     ax, 0xB000
    mov     ds, ax
    xor     si, si
    mov     cx, 2000
    mov     bl, 0x11
.hgc_check:
    lodsb
    cmp     al, bl
    je      .hgc_ok
    inc     bp
.hgc_ok:
    add     bl, 5
    loop    .hgc_check

    ; ---- HGC graphics page 1: B8000 is CGA and HGC page 1; a write goes to both ----
    mov     dx, 0x3B8
    mov     al, 0xA8                ; page 1, video on
    out     dx, al
    mov     ax, 0xB800
    mov     es, ax
    mov     byte [es:0x0100], 0xC3
    mov     byte [es:0x0101], 0x3C
    mov     ax, 0xB800
    mov     ds, ax
    cmp     byte [0x0100], 0xC3     ; reads return the CGA's copy
    je      .p1_ok
    inc     bp
.p1_ok:
    cmp     byte [0x0101], 0x3C
    je      .p1_ok2
    inc     bp
.p1_ok2:
    mov     dx, 0x3B8
    mov     al, 0x28                ; page 0 again
    out     dx, al

    ; ---- read-after-write on the same address, back to back ----
    mov     ax, 0xB800
    mov     ds, ax
    mov     cx, 64
    mov     bl, 0x80
    xor     si, si
.raw:
    mov     [si + 0x200], bl
    mov     al, [si + 0x200]
    cmp     al, bl
    je      .raw_ok
    inc     bp
.raw_ok:
    inc     si
    inc     bl
    loop    .raw

    ; ---- BIOS-like teletype: cursor index in the BDA, character and attribute
    ;      into video memory, CRTC cursor out, then a scroll with REP MOVSW ----
    xor     ax, ax
    mov     ds, ax
    mov     word [0x0450], 0
    mov     ax, 0xB800
    mov     es, ax
    mov     cx, 160
.tty:
    mov     bx, [0x0450]            ; word read of RAM
    mov     di, bx
    shl     di, 1
    mov     [es:di + 0x1000], bl    ; character
    mov     byte [es:di + 0x1001], 0x07
    inc     bx
    mov     [0x0450], bx            ; word write of RAM
    mov     dx, 0x3D4
    mov     al, 0x0E
    out     dx, al
    inc     dx
    mov     al, bh
    out     dx, al
    dec     dx
    mov     al, 0x0F
    out     dx, al
    inc     dx
    mov     al, bl
    out     dx, al
    loop    .tty

    mov     ax, 0xB800
    mov     ds, ax
    mov     di, 0x1000
    mov     si, 0x1000 + 160
    mov     cx, 80
    rep movsw                       ; scroll one row up

    xor     si, si
    mov     cx, 80
    mov     bl, 80
.scroll_chk:
    mov     ax, [si + 0x1000]
    cmp     al, bl
    jne     .scroll_bad
    cmp     ah, 0x07
    je      .scroll_ok
.scroll_bad:
    inc     bp
.scroll_ok:
    add     si, 2
    inc     bl
    loop    .scroll_chk

    ; ---- done ----
    xor     ax, ax
    mov     ds, ax
    mov     [0x0600], bp
    mov     word [0x0602], 0xBEEF
    hlt
    jmp     $

    times 0xFFF0 - ($ - $$) db 0
reset_vector:
    jmp     0xF000:0x0000
    times 0x10000 - ($ - $$) db 0
