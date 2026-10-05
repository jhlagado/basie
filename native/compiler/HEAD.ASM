;==========================================================================
;  Image head
;==========================================================================
;
;  CP/M loads a transient at $0100 and jumps to its first byte. BASIE.COM
;  begins with a jump to the shell, whose code ends the image; the shell
;  sets the stack, loads the source parts and calls the compiler. The
;  compiler core follows the jump at MM_RBASE.
;
;  MM_BEG and MM_CBEG are extent markers: build.ts reads them to cut the
;  .COM file and to measure the compiler core.

ORG  $0100                         ; CP/M loads every transient here.
MM_BEG:                            ; First byte of BASIE.COM.
    JP   SH_START                  ; Enter the shell at the end of the image.

    ORG  MM_RBASE                  ; The compiler core follows the jump.
MM_CBEG:                           ; First byte of the compiler's code.
