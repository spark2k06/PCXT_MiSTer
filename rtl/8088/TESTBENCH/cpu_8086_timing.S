/*
 * Step-7 full-core timing workload.
 *
 * GNU as source rather than a hand-maintained byte array: labels deliberately
 * exercise near CALL/RET, an odd branch target and an external interrupt.
 * The testbench loads the flat binary in low RAM and enters at 0000:0500.
 */

    .code16
    .intel_syntax noprefix
    .section .text

    .macro MARK number
        mov     al, \number
        out     dx, al
    .endm

    .org 0x0500
start:
    cli
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, 0x8000

    /* External interrupt vector 60h -> 0000:irq_handler. */
    mov     ax, offset irq_handler
    mov     word ptr [0x0180], ax
    mov     word ptr [0x0182], 0x0000
    mov     word ptr [0x1a00], 0

    mov     dx, 0x00e0
    MARK    0

    /* 0 -> 1: register-only execution (apart from one byte signature). */
    xor     ax, ax
    mov     bx, 0x1357
    mov     cx, 64
reg_loop:
    add     ax, bx
    rol     ax, 1
    xor     ax, cx
    loop    reg_loop
    mov     byte ptr [0x1b00], al
    MARK    1

    /* 1 -> 2: aligned word reads. */
    mov     si, 0x1000
    mov     cx, 64
    xor     bx, bx
aligned_read_loop:
    mov     ax, word ptr [si]
    add     bx, ax
    add     si, 2
    loop    aligned_read_loop
    mov     byte ptr [0x1b01], bl
    MARK    2

    /* 2 -> 3: odd-address word reads. */
    mov     si, 0x1101
    mov     cx, 64
    xor     bx, bx
odd_read_loop:
    mov     ax, word ptr [si]
    add     bx, ax
    add     si, 2
    loop    odd_read_loop
    mov     byte ptr [0x1b02], bl
    MARK    3

    /* 3 -> 4: aligned read-modify-write words. */
    mov     cx, 32
aligned_rmw_loop:
    inc     word ptr [0x1200]
    loop    aligned_rmw_loop
    MARK    4

    /* 4 -> 5: odd-address read-modify-write words. */
    mov     cx, 32
odd_rmw_loop:
    inc     word ptr [0x1301]
    loop    odd_rmw_loop
    MARK    5

    /* 5 -> 6: aligned stack traffic through CALL/PUSH/POP/RET. */
    mov     cx, 32
stack_loop:
    call    stack_target
    loop    stack_loop
    MARK    6

    /* 6 -> 7: aligned REP MOVSW. */
    cld
    mov     si, 0x1400
    mov     di, 0x1600
    mov     cx, 32
    rep movsw
    MARK    7

    /* 7 -> 8: odd source and destination REP MOVSW. */
    mov     si, 0x1501
    mov     di, 0x1701
    mov     cx, 32
    rep movsw
    MARK    8

    /* 8 -> 9: force the loop body and its fetch stream to an odd IP. */
    mov     cx, 64
    xor     bx, bx
    .balign 2, 0x90
    .byte   0xeb, 0x01             /* short jump over one NOP */
    nop
odd_branch_target:
    inc     bx
    loop    odd_branch_target
    mov     byte ptr [0x1b03], bl
    MARK    9

    /* 9 -> 10: word I/O must remain two byte cycles in both CPU modes. */
    mov     dx, 0x0120
    mov     cx, 16
word_io_loop:
    in      ax, dx
    out     dx, ax
    loop    word_io_loop
    mov     dx, 0x00e0
    MARK    10

    /*
     * 10 -> 11: the bench raises INTR after marker 10. The handler exercises
     * the INTA pair, aligned interrupt-frame stack traffic, RMW and IRET.
     */
    sti
    nop
irq_wait:
    cmp     word ptr [0x1a00], 1
    jne     irq_wait
    cli
    MARK    11

    mov     word ptr [0x1bfe], 0xbeef
    hlt

stack_target:
    push    ax
    push    bx
    pop     bx
    pop     ax
    ret

irq_handler:
    push    ax
    inc     word ptr [0x1a00]
    pop     ax
    iret
