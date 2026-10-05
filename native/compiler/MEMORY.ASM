;==========================================================================
;  Memory map
;==========================================================================
;
;  BASIE.COM's memory under CP/M (toolchain §7.1):
;
;    $0100  MM_BEG    JP SH_START (HEAD.ASM)
;    $0103  MM_RBASE  compiler core, then the shell's code and data (MM_END)
;    $4800  MM_WBASE  compiler workspace (STATE, CALLWORK, TGTWORK), LL_WEND
;    $5700  SH_WBEG   the shell's workspace, SH_WEND
;    $5800  MM_SRC    resident source parts, loaded upward by the shell
;           BDOS-$400 the stack, MM_STACK bytes below the BDOS entry
;
;  Nothing in the workspace is initialised by the image, so the image only
;  has to end below MM_WBASE. build.ts checks the three boundaries: MM_END
;  against MM_WBASE, LL_WEND against SH_WBEG and SH_WEND against MM_SRC.
;
;  The second group is the address map of the Nucleus proof target the
;  compiler was forked from. Placed output is discarded until blob output
;  replaces it (step 65.4), and nothing is ever written at these addresses:
;  RT_BASE takes MM_XBASE only to form runtime-state offsets, and the rest
;  are unread. They go with TARGET.ASM. Every MM_ name is an extent marker
;  that host tools may read, so none is removed while the map stands.

MM_RBASE EQU  $0103                ; Compiler core: after the jump at $0100.
MM_RLIM EQU  $4800                 ; Exclusive end of room for the image.
MM_WBASE EQU  $4800                ; Compiler workspace: the image ends below.
MM_WLIM EQU  $5800                 ; Exclusive end of both workspaces.
SH_WBEG EQU  $5700                 ; The shell's workspace, above the compiler's.
MM_SRC EQU  $5800                  ; Resident source parts, up to the stack.
MM_STACK EQU  $0400                ; Bytes kept below the BDOS entry for the stack.

; The Nucleus proof target's regions, in its address space.

MM_STAGE EQU  $5800                ; Staging area for generated code.
MM_STLIM EQU  $6800                ; Exclusive end of the staging area.
MM_GBASE EQU  MM_STAGE             ; Generated program: the staged image.
MM_GLIM EQU  MM_STLIM              ; Exclusive end of the generated program.
MM_GCODE EQU  MM_GBASE             ; Generated code starts the program.
MM_GCLIM EQU  MM_GLIM              ; Code may fill the whole program area.

MM_TBASE EQU  $6800                ; The linked runtime helpers.
MM_TLIM EQU  $7800                 ; Exclusive end of the runtime helpers.

MM_XBASE EQU  $7800                ; Execution area: runtime state first.
MM_XLIM EQU  $8800                 ; Exclusive end of the execution area.

MM_DBASE EQU  MM_XBASE+$0100       ; Program data, after the runtime state.
MM_DLIM EQU  MM_DBASE+$0400        ; One kilobyte of initialised data.
MM_BBASE EQU  MM_DLIM              ; Zeroed data (bss) follows it.
MM_BLIM EQU  MM_BBASE+$0400        ; One kilobyte of bss.
MM_DBLIM EQU  MM_BLIM              ; Exclusive end of all program data.
MM_DBCAP EQU  MM_DBLIM-MM_DBASE    ; Data and bss together: two kilobytes.
MM_ROCAP EQU  $0400                ; Capacity for read-only constants.

MM_IO EQU  $8800                   ; The proof's service mailboxes.
MM_IOLIM EQU  $9000                ; Exclusive end of the mailboxes.
