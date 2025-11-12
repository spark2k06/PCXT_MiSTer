; ============================================================================
; Example 2: Loop Example - Iterative Calculation
;
; This microprogram demonstrates:
; - Loop initialization and decrement
; - Repeated addition operations
; - Conditional branching
; ============================================================================

; Constants
.EQU ITERATIONS = 5

fpu_loop_example:
    LOAD                    ; Load initial value
    LOOP_INIT ITERATIONS    ; Initialize loop counter to 5

loop_body:
    ADD                     ; Perform addition
    LOOP_DEC loop_body      ; Decrement and jump if not zero

    ; Loop complete
    NORMALIZE               ; Normalize the result
    ROUND 0                 ; Round to nearest (mode 0)
    STORE                   ; Store final result
    HALT                    ; End

; ============================================================================
; This example shows how to use loops for iterative calculations
; like computing Taylor series, polynomial evaluation, etc.
; ============================================================================
