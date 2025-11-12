; ============================================================================
; Example 1: Simple FPU Operation
;
; This microprogram demonstrates:
; - Loading data from CPU bus
; - Accessing a math constant
; - Storing result back to CPU
; ============================================================================

; Define constants
.EQU CONST_PI = 0x00
.EQU CONST_E  = 0x01
.EQU CONST_LN2 = 0x02

; Start at address 0
.ORG 0x0000

main:
    LOAD                    ; Load value from CPU bus into temp_reg
    SET_CONST CONST_PI      ; Set math constant index to PI
    ACCESS_CONST            ; Load PI constant into temp_fp
    STORE                   ; Store result to CPU bus
    READ_STATUS             ; Read FPU status word
    HALT                    ; End program

; ============================================================================
; Expected output:
; Address  Encoded    Source
; 0000     1100_0001  LOAD
; 0001     1300_0002  SET_CONST CONST_PI
; 0002     1400_0003  ACCESS_CONST
; 0003     1200_0004  STORE
; 0004     1C00_0005  READ_STATUS
; 0005     F000_0000  HALT
; ============================================================================
