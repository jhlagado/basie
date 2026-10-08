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
;    $6DD7  MM_WBASE  compiler workspace (STATE, CALLWORK), LL_WEND
;           LL_STACK  the LL(1) stack, from a page's start after the
;                     pools' bytes, the owner descriptors and FLOAT's
;                     workspace below it or after it (LL1.ASM)
;    $805E  SH_WBEG   the shell's workspace, SH_WEND
;    $816F  MM_BLOB   the blob writer's workspace (BLOB.ASM), BL_WEND
;    $84E4  MM_SRC    the source parts, the symbol table, the blob being
;                     written and the name heap
;           BDOS-$480 the stack, MM_STACK bytes below the BDOS entry
;
;  Nothing in the workspace is initialised by the image, so the image and
;  the overlay area only have to end below MM_WBASE. build.ts checks the
;  boundaries: MM_END against MM_WBASE, the LL(1) stack within its page,
;  LL_WEND against SH_WBEG, SH_WEND against MM_BLOB and BL_WEND against
;  MM_SRC; each is packed against the one below. Every MM_ name is
;  an extent marker that host tools may read.

MM_RBASE EQU  $0103            ; Compiler core: after the jump at $0100.
MM_RLIM EQU  $6E96             ; Exclusive end of room for the image.
MM_WBASE EQU  $6E96            ; Compiler workspace: the image ends below.
MM_WLIM EQU  $820F             ; Exclusive end of both workspaces.
SH_WBEG EQU  $80FE             ; The shell's workspace, above the compiler's.
MM_BLOB EQU  $820F             ; The blob writer's workspace, BL_FLAGS on.

MM_SRC EQU  $8584              ; Resident source parts, up to the stack.
MM_STACK EQU  $0480            ; Bytes kept below the BDOS entry for the stack.
