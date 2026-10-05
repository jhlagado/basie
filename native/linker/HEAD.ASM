;==========================================================================
;  Image head
;==========================================================================
;
;  BLINK.COM, the Basie linker (docs/linker.md), native for CP/M 2.2. The
;  CCP loads a .COM file at $0100 and jumps there, so this part comes first
;  in the image and holds only the jump to the driver, LK_START in BLINK.ASM,
;  which is assembled last.

    ORG  $0100                     ; A .COM file is loaded and entered at $0100.
    JP   LK_START                  ; The driver follows every module it calls.
