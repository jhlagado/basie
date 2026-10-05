; The blob writer's test program: its memory and its entry jump. Included
; first, so that BLOB.ASM finds MM_BLOB defined.

MM_BLOB EQU  $4000             ; The blob writer's workspace.

    ORG  $0100                     ; A CP/M transient.
    JP   BT_START                  ; The driver's code follows the modules.
