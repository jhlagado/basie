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
;    $5000  MM_WBASE  compiler workspace (STATE, CALLWORK), LL_WEND
;    $6240  SH_WBEG   the shell's workspace, SH_WEND
;    $6400  MM_BLOB   the blob writer's workspace (BLOB.ASM), BL_WEND
;    $7400  MM_SRC    resident source parts, loaded upward by the shell
;           BDOS-$400 the stack, MM_STACK bytes below the BDOS entry
;
;  Nothing in the workspace is initialised by the image, so the image and
;  the overlay area only have to end below MM_WBASE. build.ts checks the four boundaries: MM_END
;  against MM_WBASE, LL_WEND against SH_WBEG, SH_WEND against MM_BLOB and
;  BL_WEND against MM_SRC. Every MM_ name is an extent marker that host
;  tools may read.

MM_RBASE EQU  $0103            ; Compiler core: after the jump at $0100.
MM_RLIM EQU  $5000             ; Exclusive end of room for the image.
MM_WBASE EQU  $5000            ; Compiler workspace: the image ends below.
MM_WLIM EQU  $6400             ; Exclusive end of both workspaces.
SH_WBEG EQU  $6240             ; The shell's workspace, above the compiler's.
MM_BLOB EQU  $6400             ; The blob writer's workspace, BL_FLAGS on.
MM_SRC EQU  $7400              ; Resident source parts, up to the stack.
MM_STACK EQU  $0400            ; Bytes kept below the BDOS entry for the stack.
