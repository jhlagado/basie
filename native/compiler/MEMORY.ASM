;==========================================================================
;  Memory map
;==========================================================================
;
;  BASIE.COM's memory under CP/M (toolchain §7.1):
;
;    $0100  MM_BEG    JP SH_START (HEAD.ASM)
;    $0103  MM_RBASE  compiler core, then the shell's code and data (MM_END)
;           OV_AREA   the overlay area, from MM_END, as large as the largest
;                     overlay in whole records (OVERLAY.ASM, BASIE.OVL)
;    $5400  MM_WBASE  compiler workspace (STATE, CALLWORK), LL_WEND
;    $6640  SH_WBEG   the shell's workspace, SH_WEND
;    $6800  MM_BLOB   the blob writer's workspace (BLOB.ASM), BL_WEND
;    $7980  MM_SRC    resident source parts, loaded upward by the shell
;           BDOS-$400 the stack, MM_STACK bytes below the BDOS entry
;
;  Nothing in the workspace is initialised by the image, so the image and
;  the overlay area only have to end below MM_WBASE. build.ts checks the four boundaries: MM_END
;  against MM_WBASE, LL_WEND against SH_WBEG, SH_WEND against MM_BLOB and
;  BL_WEND against MM_SRC. Every MM_ name is an extent marker that host
;  tools may read.

MM_RBASE EQU  $0103            ; Compiler core: after the jump at $0100.
MM_RLIM EQU  $5400             ; Exclusive end of room for the image.
MM_WBASE EQU  $5400            ; Compiler workspace: the image ends below.
MM_WLIM EQU  $6800             ; Exclusive end of both workspaces.
SH_WBEG EQU  $6640             ; The shell's workspace, above the compiler's.
MM_BLOB EQU  $6800             ; The blob writer's workspace, BL_FLAGS on.

; The FLOAT overlay's workspace, between the shell's and the blob writer's,
; resident so that it takes no records of the overlay area (build.ts checks
; that SH_WEND is at or below FL_WBEG and FL_WEND at or below MM_BLOB).
FL_NB EQU  64                  ; Bytes of FL_N and FL_D.
FL_WBEG EQU  $6760             ; The workspace's start.
FL_N EQU  FL_WBEG              ; N, the dividend, FL_NB bytes.
FL_D EQU  FL_N+FL_NB           ; D, the divisor, FL_NB bytes.
FL_Q EQU  FL_D+FL_NB           ; q, the quotient, then the f32's bits: 5 bytes.
FL_E EQU  FL_Q+5               ; E, q's lowest bit's exponent: a word.
FL_SIGN EQU  FL_E+2            ; The result's sign, bit 7.
FL_LOST EQU  FL_SIGN+1         ; Nonzero when bits were lost in rounding.
FL_MODE EQU  FL_LOST+1         ; Nonzero for a literal's rounding.
FL_TEN EQU  FL_MODE+1          ; A literal's power of ten: a word.
FL_SIG EQU  FL_TEN+2           ; Its significant digits: a word.
FL_A EQU  FL_SIG+2             ; a unpacked: sign, exponent, significand.
FL_B EQU  FL_A+5               ; b unpacked.
FL_WEND EQU  FL_B+5            ; The workspace's end.
MM_SRC EQU  $7980              ; Resident source parts, up to the stack.
MM_STACK EQU  $0400            ; Bytes kept below the BDOS entry for the stack.
