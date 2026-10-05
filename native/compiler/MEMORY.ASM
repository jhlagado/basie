; BASIE.COM's memory under CP/M (toolchain §7.1). The compiler loads at $0100
; behind a jump to the shell; its workspace and the resident source parts
; follow the image, and the stack sits below the BDOS entry.
;
; The target addresses below them are the forked compiler's flat proof
; target. Placed output is discarded until blob output replaces it (native
; compiler plan, 65.4), so they are only numbers the compiler checks.

MM_RBASE EQU  $0103
MM_RLIM EQU  $4800
MM_WBASE EQU  $4800                ; the image must end below here
MM_WLIM EQU  $5800
SH_WBEG EQU  $5700                 ; the shell's workspace
MM_SRC EQU  $5800                  ; resident source parts, up to the stack
MM_STACK EQU  $0400                ; kept below the BDOS entry for the stack

MM_STAGE EQU  $5800
MM_STLIM EQU  $6800
MM_GBASE EQU  MM_STAGE
MM_GLIM EQU  MM_STLIM
MM_GCODE EQU  MM_GBASE
MM_GCLIM EQU  MM_GLIM

MM_TBASE EQU  $6800
MM_TLIM EQU  $7800

MM_XBASE EQU  $7800
MM_XLIM EQU  $8800

MM_DBASE EQU  MM_XBASE+$0100
MM_DLIM EQU  MM_DBASE+$0400
MM_BBASE EQU  MM_DLIM
MM_BLIM EQU  MM_BBASE+$0400
MM_DBLIM EQU  MM_BLIM
MM_DBCAP EQU  MM_DBLIM-MM_DBASE
MM_ROCAP EQU  $0400

MM_IO EQU  $8800
MM_IOLIM EQU  $9000
