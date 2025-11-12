; ============================================================================
; Example 3: Subroutine Calls
;
; This microprogram demonstrates:
; - Subroutine calls and returns
; - Modular microcode design
; - Absolute value function
; ============================================================================

main_program:
    LOAD                    ; Load input value
    CALL abs_function       ; Call absolute value subroutine
    STORE                   ; Store result
    HALT                    ; End program

; Subroutine: Compute absolute value
abs_function:
    ABS                     ; Compute absolute value
    NORMALIZE               ; Normalize result
    RET                     ; Return to caller

; ============================================================================
; This example shows how to structure microcode as reusable subroutines
; The CALL instruction pushes the return address onto the call stack
; The RET instruction pops and jumps back to the caller
; ============================================================================
