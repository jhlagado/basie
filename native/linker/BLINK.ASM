%INCLUDE "HEAD.ASM"
%INCLUDE "CPM.ASM"
%INCLUDE "FILE.ASM"
%INCLUDE "CRC.ASM"
%INCLUDE "MSG.ASM"
%INCLUDE "TAIL.ASM"

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
.NAMED: CALL    OPENLIB
        JR      C,FAILED
        CALL    LIBHEAD
        JR      C,FAILED
        LD      A,(O_FLAGS)
        AND     OF_V
        JR      Z,.DONE
        CALL    LIBCRC
        JR      C,FAILED
.DONE:  LD      DE,RC_OK
        JP      EXITRC

FAILED: LD      DE,RC_LINK
        JP      EXITRC

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

; Check the library's magic and version, and keep its length. Carry after a
; diagnostic.
LIBHEAD:
        LD      HL,.MAGIC
        LD      B,4
.CHECK: PUSH    HL
        PUSH    BC
        CALL    F_GETB
        POP     BC
        POP     HL
        JP      C,.BAD
        CP      (HL)
        JP      NZ,.BAD
        INC     HL
        DJNZ    .CHECK
        CALL    F_GETB          ; version 1.0
        JP      C,.BAD
        CP      1
        JP      NZ,.BAD
        CALL    F_GETB
        JP      C,.BAD
        OR      A
        JP      NZ,.BAD
        XOR     A
        LD      HL,28           ; the file length (u32)
        CALL    F_SEEK
        JR      C,.SHORT
        CALL    F_GETW
        JR      C,.SHORT
        LD      (LIB_LEN),HL
        CALL    F_GETB
        JR      C,.SHORT
        LD      (LIB_LEN+2),A
        OR      A
        RET
.BAD:   LD      HL,200          ; L-FORMAT
        JP      .SAY
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
