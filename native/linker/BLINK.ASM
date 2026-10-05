%INCLUDE "HEAD.ASM"
%INCLUDE "CPM.ASM"
%INCLUDE "FILE.ASM"
%INCLUDE "CRC.ASM"
%INCLUDE "MSG.ASM"
%INCLUDE "TAIL.ASM"
%INCLUDE "PHASEA.ASM"
%INCLUDE "PHASECD.ASM"
%INCLUDE "LINES.ASM"
%INCLUDE "PUBLISH.ASM"
%INCLUDE "PHASEE.ASM"

; BLINK: link a compiled Basie program (docs/linker.md; toolchain §5).
;
;     BLINK NAME [options]
;
; This is the skeleton of roadmap step 59: the command line, files, the CRC
; and diagnostics, checking the blob library's header and, with option V,
; its whole-file CRC. The link phases follow in later steps.

LIB_FD: DS      FDSIZE
LIB_TY: DB      "BRL"
LIB_TXT:
        DS      13              ; the library's name as text, for messages
LIB_LEN:
        DS      3               ; the library's length, from its header

START:  LD      HL,(TOP)
        LD      SP,HL
        CALL    PARSE
        JR      C,FAILED
        OR      A
        JR      NZ,.NAMED
        LD      HL,223          ; L-USAGE
        CALL    ERROR
        JR      FAILED
.NAMED: LD      A,1             ; from here a failure cleans up (toolchain §6.2)
        LD      (LINKING),A
        CALL    OPENLIB
        JR      C,FAILED
        CALL    LIBHEAD
        JR      C,FAILED
        LD      A,(O_FLAGS)
        AND     OF_V
        JR      Z,.DONE
        CALL    LIBCRC
        JR      C,FAILED
.DONE:  CALL    LIBNAME         ; the library's name, for messages
        CALL    PHASEA
        CALL    PHASEB
        LD      A,(O_FLAGS2)
        AND     OF2_W
        CALL    NZ,DUMP
        CALL    PHASEC
        CALL    PHASED
        CALL    PUBLISH
        CALL    PHASEE
        CALL    CLEANUP
        LD      DE,RC_OK
        JP      EXITRC

FAILED: LD      A,(LINKING)
        OR      A
        CALL    NZ,ABANDON
        LD      DE,RC_LINK
        JP      EXITRC

LINKING: DB     0

; Open NAME.BRL: on the drive option L gives, else the first part's drive,
; then A: (toolchain §5.3). Carry after a diagnostic.
OPENLIB:
        LD      IX,LIB_FD
        LD      A,(O_LDRV)
        OR      A
        JR      NZ,.ONLY
        LD      A,(O_DRV)
        CALL    .TRY
        RET     NC
        LD      A,1
.ONLY:  CALL    .TRY
        RET     NC
        CALL    LIBNAME
        LD      HL,225          ; L-MISSING
        CALL    ERROR
        SCF
        RET
.TRY:   LD      HL,O_LIB
        LD      DE,LIB_TY
        CALL    F_INIT
        JP      F_OPEN

; Read the library's header into LIBH and check its magic and version.
; Carry after a diagnostic.
LIBHEAD:
        LD      HL,LIBH
        LD      B,64            ; the header and the profile block
.READ:  PUSH    HL
        PUSH    BC
        CALL    F_GETB
        POP     BC
        POP     HL
        JR      C,.SHORT
        LD      (HL),A
        INC     HL
        DJNZ    .READ
        LD      HL,LIBH
        LD      DE,.MAGIC
        LD      B,4
.CHECK: LD      A,(DE)
        CP      (HL)
        JR      NZ,.BAD
        INC     HL
        INC     DE
        DJNZ    .CHECK
        LD      A,(LIBH+4)      ; version 1.0
        CP      1
        JR      NZ,.BAD
        LD      A,(LIBH+5)
        OR      A
        JR      NZ,.BAD
        LD      HL,(LIBH+28)    ; the file length
        LD      (LIB_LEN),HL
        LD      A,(LIBH+30)
        LD      (LIB_LEN+2),A
        OR      A
        RET
.BAD:   LD      HL,200          ; L-FORMAT
        JR      .SAY
.SHORT: LD      HL,214          ; L-TRUNCATED
.SAY:   PUSH    HL
        CALL    LIBNAME
        POP     HL
        CALL    ERROR
        SCF
        RET
.MAGIC: DB      "BSIR"

; Check the CRC of the library's first LIB_LEN - 2 bytes against its last
; two (object format §7.6). Carry after a diagnostic.
LIBCRC: XOR     A
        LD      HL,0
        CALL    F_SEEK
        JP      C,.BAD
        CALL    CRC_NEW
        LD      HL,(LIB_LEN)
        LD      A,(LIB_LEN+2)
        LD      C,A             ; C:HL = the bytes to add
        LD      DE,2
        OR      A
        SBC     HL,DE
        JR      NC,.LOOP
        DEC     C
.LOOP:  LD      A,H
        OR      L
        OR      C
        JR      Z,.STORED
        PUSH    BC
        PUSH    HL
        CALL    F_GETB
        POP     HL
        POP     BC
        JP      C,.BAD
        CALL    CRC_ADD
        LD      A,L
        SUB     1
        LD      L,A
        JR      NC,.LOOP
        DEC     H
        LD      A,H
        CP      $FF
        JR      NZ,.LOOP
        DEC     C
        JR      .LOOP
.STORED:
        CALL    F_GETW
        JP      C,.BAD
        LD      DE,(CRC_V)
        OR      A
        SBC     HL,DE
        RET     Z
.BAD:   CALL    LIBNAME
        LD      HL,214          ; L-TRUNCATED
        CALL    ERROR
        SCF
        RET

; Write the library's file name as text into LIB_TXT and make it argument 1.
LIBNAME:
        LD      DE,LIB_TXT
        LD      HL,O_LIB
        LD      B,8
.NAME:  LD      A,(HL)
        CP      ' '
        JR      Z,.TYPE
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    .NAME
.TYPE:  LD      HL,.EXT
        LD      BC,5
        LDIR
        LD      HL,LIB_TXT
        LD      (M_ARG1),HL
        RET
.EXT:   DB      ".BRL",0

; The end of the program: the linker's tables start here.
FREEMEM:
