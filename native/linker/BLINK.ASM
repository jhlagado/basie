%INCLUDE "HEAD.ASM"
%INCLUDE "CPM.ASM"
%INCLUDE "FILE.ASM"
%INCLUDE "CRC.ASM"
%INCLUDE "MSG.ASM"
%INCLUDE "TAIL.ASM"
%INCLUDE "PHASEA.ASM"
%INCLUDE "CHECKS.ASM"
%INCLUDE "PHASEB.ASM"
%INCLUDE "PHASEC.ASM"
%INCLUDE "PHASED.ASM"
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

LIB_FD: DS      FD_SIZE
LIB_TYPE: DB      "BRL"
LIB_TEXT:
        DS      13              ; the library's name as text, for messages
LIB_LEN:
        DS      3               ; the library's length, from its header

LK_START:  LD      HL,(CPM_TOP)
        LD      SP,HL
        CALL    CMD_READ
        JR      C,LK_FAIL
        OR      A
        JR      NZ,.NAMED
        LD      HL,223          ; L-USAGE
        CALL    DG_ERROR
        JR      LK_FAIL
.NAMED: LD      A,1             ; from here a failure cleans up (toolchain §6.2)
        LD      (LK_BUSY),A
        CALL    LIB_OPEN
        JR      C,LK_FAIL
        CALL    LIB_READ
        JR      C,LK_FAIL
        LD      A,(OP_FLAGS)
        AND     OF_V
        JR      Z,.DONE
        CALL    LIB_CHK
        JR      C,LK_FAIL
.DONE:  CALL    LIB_ARG         ; the library's name, for messages
        CALL    PA_RUN
        CALL    PB_RUN
        LD      A,(OP_EXTRA)
        AND     OX_W
        CALL    NZ,TB_WRITE
        CALL    PC_RUN
        CALL    PD_RUN
        CALL    PUB_RUN
        CALL    PE_RUN
        CALL    PUB_TIDY
        LD      DE,RC_OK
        JP      CPM_EXIT

LK_FAIL: LD      A,(LK_BUSY)
        OR      A
        CALL    NZ,PUB_UNDO
        LD      DE,RC_LINK
        JP      CPM_EXIT

LK_BUSY: DB     0

; Open NAME.BRL: on the drive option L gives, else the first part's drive,
; then A: (toolchain §5.3). Carry after a diagnostic.
LIB_OPEN:
        LD      IX,LIB_FD
        LD      A,(LIB_DISK)
        OR      A
        JR      NZ,.ONLY
        LD      A,(CMD_DISK)
        CALL    .TRY
        RET     NC
        LD      A,1
.ONLY:  CALL    .TRY
        RET     NC
        CALL    LIB_ARG
        LD      HL,225          ; L-MISSING
        CALL    DG_ERROR
        SCF
        RET
.TRY:   LD      HL,LIB_FILE
        LD      DE,LIB_TYPE
        CALL    FIL_INIT
        JP      FIL_OPEN

; Read the library's header into LIBH and check its magic and version.
; Carry after a diagnostic.
LIB_READ:
        LD      HL,LIB_HEAD
        LD      B,64            ; the header and the profile block
.READ:  CALL    FIL_GETB
        JR      C,.SHORT
        LD      (HL),A
        INC     HL
        DJNZ    .READ
        LD      HL,LIB_HEAD
        LD      DE,.MAGIC
        LD      B,4
.CHECK: LD      A,(DE)
        CP      (HL)
        JR      NZ,.BAD
        INC     HL
        INC     DE
        DJNZ    .CHECK
        LD      A,(LIB_HEAD+4)  ; version 1.0
        CP      1
        JR      NZ,.BAD
        LD      A,(LIB_HEAD+5)
        OR      A
        JR      NZ,.BAD
        LD      HL,(LIB_HEAD+28) ; the file length
        LD      (LIB_LEN),HL
        LD      A,(LIB_HEAD+30)
        LD      (LIB_LEN+2),A
        OR      A
        RET
.BAD:   LD      HL,200          ; L-FORMAT
        JR      .SAY
.SHORT: LD      HL,214          ; L-TRUNCATED
.SAY:   PUSH    HL
        CALL    LIB_ARG
        POP     HL
        CALL    DG_ERROR
        SCF
        RET
.MAGIC: DB      "BSIR"

; Check the CRC of the library's first LIB_LEN - 2 bytes against its last
; two (object format §7.6). Carry after a diagnostic.
LIB_CHK: XOR     A
        LD      HL,0
        CALL    FIL_SEEK
        JR      C,.BAD
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
        CALL    FIL_GETB
        JR      C,.BAD
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
        CALL    FIL_GETW
        JR      C,.BAD
        LD      DE,(CRC_VAL)
        OR      A
        SBC     HL,DE
        RET     Z
.BAD:   CALL    LIB_ARG
        LD      HL,214          ; L-TRUNCATED
        CALL    DG_ERROR
        SCF
        RET

; Write the library's file name as text into LIB_TEXT and make it argument 1.
LIB_ARG:
        LD      DE,LIB_TEXT
        LD      HL,LIB_FILE
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
        LD      HL,LIB_TEXT
        LD      (DG_ARG1),HL
        RET
.EXT:   DB      ".BRL",0

; The end of the program: the linker's tables start here.
FREEMEM:
