; The blob writer's test program: its memory and its entry jump. Included
; first, so that BLOB.ASM finds MM_BLOB defined.

MM_BLOB EQU  $4000             ; The blob writer's workspace.

    ORG  $0100                     ; A CP/M transient.
    JP   BT_START                  ; The driver's code follows the modules.

; The free memory a blob is built in: from RG_PEND, the end of the
; compiler's waiting constants, to NH_PTR, the bottom of its name heap.

RG_PEND:                       ; The free memory's start.
    DW   $5000                     ; Above the workspace.
NH_PTR:                        ; Its end.
    DW   $C000                     ; Below the BDOS.
