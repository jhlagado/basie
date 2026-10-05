; Phases C and D (linker §6, §7): place the live blobs, then write the image.
;
; Neither phase sorts. Each pass re-reads the directories (linker §10) and
; takes, in directory order, the live blobs of one section and alignment
; class: library before program, classes from the largest down. That is the
; reference linker's order. Phase D makes the same passes, copying each blob
; from its byte stream and patching its references as they come.
;
; With option R, data blobs leave TEXT for a separate DATA section after it,
; followed by COPY, DATA written again byte for byte (linker §7.3). ROM
; targets (class 3 and above) are refused in Phase A.

PF_BLOCK    EQU     LIB_HEAD+42 ; the profile block's fields (object format §5)
PF_CLASS EQU    PF_BLOCK+0
PF_KINDS EQU    PF_BLOCK+1
PF_BASE EQU     PF_BLOCK+2
PF_LIMIT EQU    PF_BLOCK+4
PF_TOP  EQU     PF_BLOCK+6
PF_OPTS EQU     PF_BLOCK+16
PF_FILE EQU     PF_BLOCK+20

S_TEXT  EQU     2               ; sections, for WK_SEC: kinds 3 and 4
S_BSS   EQU     3               ; are the sections of their blobs, and DATA
S_START EQU     4               ; is TEXT with OF_R's bit
S_DATA  EQU     S_TEXT+OF_R

PC_NEXT: DW      0              ; the next free address
WK_SEC: DB     0                ; the pass's section
WK_CLASS: DB     0              ; and alignment class
IMG_END: DW     0
PC_BEG: DW     0                ; Phase C: the section's start
PC_BEGUN: DB     0              ; nonzero once its first blob is placed
DATA_BEG: DW     0
DATA_END: DW     0
BSS_BEG: DW     0
PD_DELTA: DW      0             ; Phase D: COPY's distance from DATA
PC_FREE: DW     0
PC_STACK: DW     0
FT_ADDR: DW     0
FT_SIZE: DW     0
FT_COUNT: DB      0
OUT_POS: DW      0              ; Phase D: the address written up to
WK_OWN: DB      0               ; the directory being walked: 0 library
WK_EACH:  DW      0             ; the routine called for each blob
WK_KIND: DB     0
WK_NAMES:  DB      0            ; nonzero: walks reset the name readers
WK_POS: DW      0               ; the blob's byte-stream offset
WK_ENTRY: DW      0             ; the blob's entry
SRC_FD: DW      0               ; Phase D: the byte stream being copied
.BASE: DS     3                 ; the byte stream's start in its file
PS_TAB: DS      40              ; MAIN to FILECOUNT: address, size

; ---- walking a directory ---------------------------------------------------

; Walk the library's directory, then the program's.
WK_BOTH:  XOR     A
        CALL    .WALK
        LD      A,1
; Walk the library's directory (A = 0) or the program's (A = 1), calling
; WK_EACH for each blob with WK_ENTRY, WK_KIND, RD_SIZE, REF_CNT and WK_POS set
; and the directory at its first reference. The callback consumes the
; references, with REFSKIP or by copying the blob. In Phase E (WK_NAMES) the
; owner's name reader starts again with each walk.
.WALK:   LD      (WK_OWN),A
        LD      HL,WK_NAMES
        INC     (HL)
        DEC     (HL)
        CALL    NZ,NM_RESET
        LD      A,(WK_OWN)
        OR      A
        JR      NZ,.PROG
        LD      IX,LIB_FD
        LD      A,(LIB_HEAD+14)
        LD      HL,(LIB_HEAD+12)
        CALL    FIL_SEEK
        JP      C,DG_SHORT
        LD      HL,0
        JR      .GO
.PROG:  LD      IX,DIR_FD
        XOR     A
        LD      HL,20           ; past the program header
        CALL    FIL_SEEK
        JP      C,DG_SHORT
        LD      HL,(DIR_HEAD+16)
        DEC     HL
.GO:    LD      (RD_PREV),HL
        LD      HL,0
        LD      (WK_POS),HL
.REC:   CALL    RD_BYTE
        CP      $FF
        RET     Z
        LD      (RD_HEAD),A
        AND     7
        CP      6
        JR      Z,.CTRL
        LD      (WK_KIND),A
        LD      A,(RD_HEAD)
        BIT     3,A
        JR      Z,.IMPL
        CALL    RD_WORD
        JR      .ORD
.IMPL:  LD      HL,(RD_PREV)
        INC     HL
.ORD:   LD      (RD_PREV),HL
        CALL    TAB_FIND
        LD      (WK_ENTRY),HL
        CALL    RD_WORD
        LD      (RD_SIZE),HL
        CALL    RD_BYTE
        LD      L,A
        LD      H,0
        CP      255
        JR      NZ,.CNT
        CALL    RD_WORD
.CNT:   LD      (REF_CNT),HL
        PUSH    IX
        LD      HL,(WK_EACH)
        CALL    .CALL
        POP     IX
        LD      A,(WK_KIND)
        CP      K_BSS
        JR      Z,.REC
        LD      HL,(WK_POS)
        LD      DE,(RD_SIZE)
        ADD     HL,DE
        LD      (WK_POS),HL
        JR      .REC
.CALL:  JP      (HL)
.CTRL:  LD      A,(RD_HEAD)
        RRCA
        RRCA
        RRCA
        AND     $1F
        LD      B,6             ; alias: alias, base, offset
        JR      Z,.SKIP
        LD      B,2             ; entry
        DEC     A
        JR      Z,.SKIP
        LD      B,5             ; limits (bank never passes Phase A)
.SKIP:  CALL    RD_BYTE
        DJNZ    .SKIP
        JR      .REC

; Read and discard the current blob's references.
REF_SKIP:
        LD      HL,(REF_CNT)
.NEXT:  LD      A,H
        OR      L
        RET     Z
        PUSH    HL
        CALL    REF_READ
        POP     HL
        DEC     HL
        JR      .NEXT

; Read one reference: REF_LAST = its offset, REF_FORM its form, HL its target,
; DE its addend. Offsets accumulate from REFSTART.
REF_READ:
        CALL    RD_BYTE
        LD      B,A
        AND     $3F
        CP      63
        JR      NZ,.DELTA
        CALL    RD_WORD
        JR      .OFF
.DELTA: LD      L,A
        LD      H,0
        LD      A,(REF_ANY)
        OR      A
        JR      Z,.OFF
        LD      DE,(REF_LAST)
        ADD     HL,DE
.OFF:   LD      (REF_LAST),HL
        LD      A,1
        LD      (REF_ANY),A
        XOR     A
        BIT     7,B
        JR      Z,.FORM
        CALL    RD_BYTE
.FORM:  LD      (REF_FORM),A
        CALL    RD_WORD
        PUSH    HL
        LD      DE,0
        BIT     6,B
        JR      Z,.NOADD
        CALL    RD_WORD
        EX      DE,HL
.NOADD: POP     HL
        RET

; Before a blob's references: no previous offset yet.
REF_NEW:
        XOR     A
        LD      (REF_ANY),A
        RET

; Whether the blob just read belongs to this pass: live, of the pass's
; class, and in its section. Z when it does.
WK_MATCH: LD      HL,(WK_ENTRY)
        BIT     5,(HL)
        JR      Z,.NO
        LD      DE,E_LAYOUT
        ADD     HL,DE
        LD      A,(WK_CLASS)
        CP      (HL)
        RET     NZ
        LD      A,(WK_KIND)     ; the blob's section: code and rodata
        CP      K_DATA          ; are TEXT; data is TEXT or, under R, DATA
        JR      NC,.KIND
        LD      A,S_TEXT
.KIND:  JR      NZ,.SEC
        LD      A,(OP_FLAGS)
        AND     OF_R
        OR      S_TEXT
.SEC:   LD      HL,WK_SEC
        CP      (HL)
        RET
.NO:    OR      1               ; NZ
        RET

; Make the passes of section A, calling HL for each blob: for each class
; from 7 down that has a live blob (linker §10), the library's directory
; then the program's. DATA has passes only under option R.
WK_PASS:
        LD      (WK_SEC),A
        LD      (WK_EACH),HL
        CP      S_DATA
        JR      NZ,.GO
        LD      A,(OP_FLAGS)
        AND     OF_R
        RET     Z
.GO:    LD      A,7
.CLASS: LD      (WK_CLASS),A
        CALL    .PRESENT
        CALL    NZ,WK_BOTH
        LD      A,(WK_CLASS)
        SUB     1
        JR      NC,.CLASS
        RET

; NZ when alignment class WK_CLASS has a live blob.
.PRESENT:
        LD      A,(WK_CLASS)
        INC     A
        LD      B,A
        LD      A,(PB_CLASS)
.SHIFT: RRCA
        DJNZ    .SHIFT
        RLCA                    ; back one: bit 0 is the class's
        AND     1
        RET

; ---- Phase C -----------------------------------------------------------------

PC_RUN: XOR     A               ; the CRCs were checked in Phase A
        LD      (RD_CRC),A
        LD      HL,(PF_BASE)
        LD      (PC_NEXT),HL
        LD      A,S_START
        CALL    .PLACESEC
        LD      A,S_TEXT
        CALL    .PLACESEC
        LD      A,S_DATA        ; empty, at TEXT's end, without R
        CALL    .PLACESEC
        LD      (DATA_BEG),HL
        LD      (DATA_END),DE
        EX      DE,HL           ; COPY follows DATA: the image ends at
        PUSH    HL              ; DATA's end plus its size
        OR      A
        SBC     HL,DE
        POP     DE
        ADD     HL,DE
        LD      (IMG_END),HL
        LD      (PC_NEXT),HL
        LD      A,S_BSS
        CALL    .PLACESEC
        LD      (BSS_BEG),HL
        ; the file table, after BSS, when the program uses files
        LD      A,(OP_FILES)
        OR      A
        JR      NZ,.SETCOUNT
        LD      A,4
.SETCOUNT:    LD      (FT_COUNT),A
        LD      HL,(PC_NEXT)
        LD      (FT_ADDR),HL
        LD      HL,0
        LD      A,(PB_FILES)
        OR      A
        JR      Z,.NOFILES
        LD      A,(FT_COUNT)
        LD      B,A
        LD      DE,(PF_FILE)
.MUL:   ADD     HL,DE
        DJNZ    .MUL
.NOFILES:
        LD      (FT_SIZE),HL
        LD      DE,(PC_NEXT)
        ADD     HL,DE
        LD      (PC_FREE),HL
        ; aliases of live blobs: their address and effective size
        LD      HL,0
.ALIAS: PUSH    HL
        CALL    TAB_AT
        JR      C,.ADONE
        BIT     6,(HL)
        CALL    NZ,.SETALIAS
        POP     HL
        INC     HL
        JR      .ALIAS
.ADONE: POP     HL
        ; the stack reserve: the compiler's, or STACK= when larger
        LD      HL,(PA_LIMIT)
        LD      DE,(OP_STACK)
        PUSH    HL
        OR      A
        SBC     HL,DE
        POP     HL
        JR      NC,.RES
        EX      DE,HL
.RES:   LD      (PC_STACK),HL
        CALL    .PSEUDOS
        ; fit checks (linker §6.4)
        LD      HL,(PF_LIMIT)
        LD      DE,(IMG_END)
        OR      A
        SBC     HL,DE
        LD      HL,216          ; L-FIT-IMAGE
        JP      C,DG_PLAIN
        LD      HL,(PC_FREE)
        LD      DE,(PC_STACK)
        ADD     HL,DE
        LD      HL,217          ; L-FIT-MEMORY: past $FFFF
        JP      C,DG_PLAIN
        LD      HL,(PC_FREE)
        ADD     HL,DE
        EX      DE,HL           ; DE = the memory needed
        LD      HL,(PF_TOP)
        LD      A,(OP_FLAGS)
        AND     OF_B
        JR      Z,.TOP
        LD      HL,(PF_LIMIT)
.TOP:   OR      A
        SBC     HL,DE
        RET     NC
        LD      HL,219          ; L-FIT-NOMINAL: a warning only
        JP      DG_WARN

; Place section A: HL = its start, DE = its end. The first blob placed is
; of the largest class present, so the section starts at its address, which
; is the cursor rounded up to that class (linker §6.3).
.PLACESEC:
        LD      HL,(PC_NEXT)
        LD      (PC_BEG),HL
        LD      HL,PC_BEGUN
        LD      (HL),0
        LD      HL,.PLACE
        CALL    WK_PASS
        LD      HL,(PC_BEG)
        LD      DE,(PC_NEXT)
        RET

; Place the blob just read, if it is in the pass, and skip its references.
.PLACE:  CALL    WK_MATCH
        JP      NZ,REF_SKIP
        LD      HL,(WK_ENTRY)   ; the alignment
        LD      DE,E_LAYOUT
        ADD     HL,DE
        LD      A,(HL)
        CALL    .ALIGN          ; HL = CURSOR rounded up
        LD      A,(PC_BEGUN)    ; the section starts at its first blob
        OR      A
        JR      NZ,.SET
        DEC     A
        LD      (PC_BEGUN),A
        LD      (PC_BEG),HL
.SET:   EX      DE,HL           ; DE = the address
        LD      HL,(WK_ENTRY)
        INC     HL
        LD      C,(HL)
        INC     HL
        LD      B,(HL)          ; BC = the size
        INC     HL
        LD      (HL),E
        INC     HL
        LD      (HL),D
        EX      DE,HL
        ADD     HL,BC
        LD      (PC_NEXT),HL
        JP      REF_SKIP

; HL = CURSOR rounded up to alignment code A: 2^A bytes, 256 for 7.
.ALIGN:
        LD      HL,(PC_NEXT)
        OR      A
        RET     Z
        LD      B,A
        LD      DE,1
        CP      7
        JR      NZ,.POW
        INC     B               ; code 7 is 256 bytes, 2^8
.POW:   SLA     E
        RL      D
        DJNZ    .POW
        DEC     DE              ; the mask
        ADD     HL,DE
        LD      A,E
        CPL
        AND     L
        LD      L,A
        LD      A,D
        CPL
        AND     H
        LD      H,A
        RET

; The alias entry at HL: when its base is live, its address is the base's
; plus its offset, and its size the base's less its offset.
.SETALIAS:
        PUSH    HL
        INC     HL
        LD      C,(HL)
        INC     HL
        LD      B,(HL)          ; BC = the offset
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = the base ordinal
        EX      DE,HL
        PUSH    BC
        CALL    TAB_FIND
        POP     BC
        POP     DE              ; DE = the alias entry
        RET     C
        BIT     5,(HL)
        RET     Z
        INC     HL
        LD      A,(HL)          ; the base's size less the offset
        SUB     C
        LD      (PS_TAB),A      ; scratch
        INC     HL
        LD      A,(HL)
        SBC     A,B
        PUSH    AF
        INC     HL
        LD      A,(HL)          ; the base's address plus the offset
        ADD     A,C
        LD      C,A
        INC     HL
        LD      A,(HL)
        ADC     A,B
        LD      B,A             ; BC = the alias's address
        EX      DE,HL           ; HL = the alias entry
        INC     HL
        LD      A,(PS_TAB)
        LD      (HL),A
        INC     HL
        POP     AF
        LD      (HL),A
        INC     HL
        LD      (HL),C
        INC     HL
        LD      (HL),B
        RET

; The pseudo-objects' addresses and sizes (object format §3.6).
.PSEUDOS:
        LD      HL,PS_TAB
        LD      (.ROWPTR),HL
        LD      HL,(PA_MAIN)    ; MAIN
        CALL    TAB_FIND
        INC     HL
        LD      C,(HL)
        INC     HL
        LD      B,(HL)
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        CALL    .PUT            ; address DE, size BC
        LD      DE,(PF_BASE)    ; IMAGE
        LD      HL,(IMG_END)
        CALL    .SPAN
        LD      HL,(FT_ADDR)    ; BSS: to the end of the file table
        LD      BC,(FT_SIZE)
        ADD     HL,BC
        LD      DE,(BSS_BEG)
        CALL    .SPAN
        LD      DE,(PC_FREE)    ; FREE
        LD      BC,0
        CALL    .PUT
        LD      HL,(PC_STACK)   ; REQUIRED: FREE plus the reserve
        LD      B,H
        LD      C,L
        ADD     HL,DE
        EX      DE,HL
        CALL    .PUT
        LD      HL,(DATA_END)   ; DATA, then DATACOPY: COPY, at DATA's
        LD      DE,(DATA_BEG)   ; end, of DATA's size (empty, at TEXT's
        CALL    .SPAN           ; end, without R)
        LD      DE,(DATA_END)
        CALL    .PUT
        LD      A,(OP_FLAGS)    ; OPTIONS: 1 keep the CCP (B), 2 re-runnable
        XOR     OF_N            ; (R), 4 a line table (not N): bits 5, 4
        RRCA                    ; and 3 of the flags, reversed
        RRCA
        RRCA
        LD      DE,0
        LD      B,3
.OPT:   RRA
        RL      E
        DJNZ    .OPT
        LD      B,D             ; BC = 0
        LD      C,D
        CALL    .PUT
        LD      DE,(FT_ADDR)    ; FILES
        LD      BC,(FT_SIZE)
        CALL    .PUT
        LD      BC,0            ; FILECOUNT
        LD      D,B
        LD      E,B
        LD      A,(PB_FILES)
        OR      A
        JR      Z,.PUT
        LD      A,(FT_COUNT)
        LD      E,A
; The next row: address DE, size BC. Preserves BC and DE.
.PUT:   LD      HL,(.ROWPTR)
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      (HL),C
        INC     HL
        LD      (HL),B
        INC     HL
        LD      (.ROWPTR),HL
        RET
; The next row: address DE, size HL - DE.
.SPAN:  OR      A
        SBC     HL,DE
        LD      B,H
        LD      C,L
        JR      .PUT

.ROWPTR: DW      0

; ---- Phase D -----------------------------------------------------------------

OUT_FD: DS      FD_SIZE
TB_FD   EQU     OUT_FD          ; option W's dump, made before Phase D
OUT_TEMP: DB      "$$$"
OUT_TEXT: DS     13
SRC_LIB: DS     FD_SIZE         ; the library again, for its byte section
SRC_PROG:  DS      FD_SIZE
CMD_BUF   EQU     SRC_PROG      ; the command tail (130 bytes) and a bad
CMD_BAD   EQU     SRC_LIB       ; option's text (32), used only in parsing
SRC_TYPE:  DB      "$BY"
SRC_TEXT: DS      13

PD_RUN: ; NAME.$$$ on the output drive, under the output name
        LD      IX,OUT_FD
        CALL    OUT_PICK        ; HL = name, A = drive
        LD      DE,OUT_TEMP
        CALL    FIL_INIT
        LD      HL,OUT_TEXT
        LD      (RD_NAME),HL
        XOR     A               ; .COM: the last record padded with zeros
        CALL    FIL_MAKE
        JP      C,DG_DISK
        LD      A,1
        LD      (OUT_MADE),A
        ; the library's byte section, through a second FD
        LD      IX,SRC_LIB
        LD      A,(LIB_DISK)
        OR      A
        JR      NZ,.LIBDISK
        LD      A,(LIB_FD+FD_FCB)
.LIBDISK:    LD      HL,LIB_FILE
        LD      DE,LIB_TYPE
        CALL    FIL_INIT
        CALL    FIL_OPEN
        JP      C,DG_SHORT
        ; the program's byte stream, NAME.$BY on the spool drive
        LD      IX,SRC_PROG
        LD      A,(DIR_FD+FD_FCB)
        LD      HL,CMD_NAME
        LD      DE,SRC_TYPE
        CALL    FIL_INIT
        LD      HL,CMD_NAME
        LD      DE,SRC_TEXT
        LD      BC,SRC_TYPE
        CALL    FIL_TEXT
        LD      HL,SRC_TEXT
        LD      (RD_NAME),HL
        CALL    FIL_OPEN
        LD      HL,225          ; L-MISSING
        JP      C,DG_FILE
        CALL    SRC_HEAD
        LD      HL,$FFFF
        LD      (IMG_CRC),HL
        CALL    LN_OPEN
        LD      HL,(PF_BASE)
        LD      (OUT_POS),HL
        LD      (HEX_ADDR),HL
        LD      A,S_START
        CALL    .SECTION
        LD      A,S_TEXT
        CALL    .SECTION
        LD      A,S_DATA
        CALL    .SECTION
        LD      HL,(DATA_END)   ; COPY: the DATA passes again, with the
        LD      DE,(DATA_BEG)   ; output DATA's size further on
        OR      A
        SBC     HL,DE
        LD      (PD_DELTA),HL
        LD      A,S_DATA
        CALL    .SECTION
        ; .COM and .BIN: zeros to the end of the record; .HEX: the last
        ; data record, the end record, then $1A. Padding is in the CRC.
        LD      A,(OUT_KIND)
        CP      4
        LD      C,0
        JR      NZ,.PAD
        CALL    HEX_OUT
        LD      HL,HEX_END
        LD      B,13
.END:   LD      A,(HL)
        CALL    OUT_RAW
        INC     HL
        DJNZ    .END
        LD      C,$1A
.PAD:   LD      A,(OUT_FD+FD_POS)
        OR      A
        JR      Z,.PADDED
        LD      A,C
        CALL    OUT_RAW
        JR      .PAD
.PADDED:
        LD      IX,OUT_FD
        CALL    FIL_SHUT
        JP      C,DG_DISK
        JP      LN_CLOSE

; Write section A.
.SECTION:
        LD      HL,PD_BLOB
        JP      WK_PASS

; HL = the output's 8-character name and A its drive: option O's, else the
; first part's.
OUT_PICK:
        LD      A,(OUT_SET)
        OR      A
        JR      Z,.PART
        LD      HL,OUT_NAME
        LD      A,(OUT_DISK)
        OR      A
        RET     NZ
        LD      A,(CMD_DISK)
        RET
.PART:  LD      HL,CMD_NAME
        LD      A,(CMD_DISK)
        RET

; Check NAME.$BY's header (object format §6): magic BSIB, version 1.0, and
; the directory's compilation stamp.
SRC_HEAD: LD      HL,.MAGIC
        LD      B,4
.COMPARE:   CALL    RD_RAW
        CP      (HL)
        JR      NZ,.BAD
        INC     HL
        DJNZ    .COMPARE
        CALL    RD_RAW
        CP      1
        JR      NZ,.BAD
        CALL    RD_RAW
        OR      A
        JR      NZ,.BAD
        CALL    RD_RAW
        LD      L,A
        CALL    RD_RAW
        LD      H,A
        LD      DE,(DIR_HEAD+6)
        OR      A
        SBC     HL,DE
        RET     Z
        LD      HL,202          ; L-STAMP
        JP      DG_PLAIN
.BAD:   LD      HL,200          ; L-FORMAT
        JP      DG_FILE
.MAGIC: DB      "BSIB"

; Copy the blob just read to the output, if it is in the pass, patching its
; references; otherwise skip its references.
PD_BLOB:   CALL    WK_MATCH
        JR      Z,.SEL
        ; not in the pass; but a program code blob's line record is still
        ; read in the code pass, to keep the line stream in step
        LD      A,(WK_SEC)
        CP      S_TEXT
        JP      NZ,REF_SKIP
        LD      A,(WK_CLASS)
        OR      A
        JP      NZ,REF_SKIP
        LD      A,(WK_OWN)
        OR      A
        JP      Z,REF_SKIP
        LD      A,(WK_KIND)
        CP      K_CODE
        JP      NZ,REF_SKIP
        XOR     A
        CALL    LN_BLOB
        JP      REF_SKIP
.SEL:   ; padding up to the blob's address, or in COPY its copy's
        LD      HL,(WK_ENTRY)
        LD      DE,E_ADDR
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = the address
        LD      HL,(PD_DELTA)
        LD      A,H
        OR      L
        ADD     HL,DE           ; keeps Z
        PUSH    HL
        LD      A,1
        CALL    Z,LN_BLOB       ; its line-table entries, but not in COPY
        POP     DE
        LD      HL,(OUT_POS)
.PAD:   LD      A,L
        CP      E
        JR      NZ,.ZERO
        LD      A,H
        CP      D
        JR      Z,.SOURCE
.ZERO:  XOR     A
        CALL    .OUTBYTE
        INC     HL
        JR      .PAD
.SOURCE:   LD      BC,(RD_SIZE) ; the output position moves past the blob
        ADD     HL,BC
        LD      (OUT_POS),HL
        ; the blob's bytes: the library's byte section or the program's stream
        LD      A,(WK_OWN)
        OR      A
        JR      NZ,.PROGRAM
        LD      HL,SRC_LIB
        LD      (SRC_FD),HL
        LD      HL,(LIB_HEAD+16)
        LD      A,(LIB_HEAD+18)
        JR      .SEEK
.PROGRAM:  LD      HL,SRC_PROG
        LD      (SRC_FD),HL
        LD      HL,8            ; past the stream's header
        XOR     A
.SEEK:  LD      DE,(WK_POS)
        ADD     HL,DE
        ADC     A,0
        PUSH    IX
        LD      IX,(SRC_FD)
        CALL    FIL_SEEK
        POP     IX
        JP      C,DG_SHORT
        LD      HL,0            ; HL = the bytes copied so far
        LD      (REF_END),HL
        CALL    REF_NEW
.REF:   LD      HL,(REF_CNT)
        LD      A,H
        OR      L
        JR      Z,.REST
        DEC     HL
        LD      (REF_CNT),HL
        CALL    REF_READ        ; HL = target, DE = addend
        PUSH    DE
        PUSH    HL
        LD      HL,(REF_LAST)   ; copy up to the reference
        CALL    .COPYTO
        POP     HL
        POP     DE
        CALL    .VALUE          ; HL = the value
        CALL    .PATCH
        JR      .REF
.REST:  LD      HL,(RD_SIZE)
        JR      .COPYTO

; Copy source bytes to the output until REF_END reaches HL.
.COPYTO: LD      DE,(REF_END)
.LOOP:  LD      A,L
        CP      E
        JR      NZ,.ONE
        LD      A,H
        CP      D
        RET     Z
.ONE:   CALL    .SRCBYTE
        CALL    .OUTBYTE
        INC     DE
        LD      (REF_END),DE
        JR      .LOOP

; Write the reference's value HL in its form, in place of its placeholder.
.PATCH:  LD      A,(REF_FORM)
        CP      1
        JR      Z,.LO
        CP      2
        JR      Z,.HI
        CALL    .SKIP2          ; ABS16 and SIZE16: two bytes
        LD      A,L
        CALL    .OUTBYTE
        LD      A,H
        CALL    .OUTBYTE
        RET
.LO:    CALL    .SKIP1
        LD      A,L
        JP      .OUTBYTE
.HI:    CALL    .SKIP1
        LD      A,H
        JP      .OUTBYTE
.SKIP2: CALL    .SKIP1
.SKIP1: CALL    .SRCBYTE        ; the placeholder byte
        PUSH    AF
        LD      DE,(REF_END)
        INC     DE
        LD      (REF_END),DE
        POP     AF
        OR      A
        RET     Z
        LD      A,(OP_FLAGS)    ; nonzero: an error under option V
        AND     OF_V
        RET     Z
        LD      HL,221          ; L-PLACEHOLDER
        JP      DG_PLAIN

; HL = the value of a reference to target HL with addend DE, in REF_FORM's
; form (linker §7.4). The value is the target's address plus the addend,
; signed, and must lie in 0 to $FFFF; a reference to a blob, or to MAIN, must
; also stay within its target: address <= value <= address + size.
.VALUE:  LD      A,H
        CP      $FF
        JR      NZ,.ENT
        LD      A,L
        CP      $E0
        JR      C,.ENT
        SUB     $E0             ; a pseudo-object: its row of PSEUDO
        PUSH    AF
        ADD     A,A
        ADD     A,A
        PUSH    DE
        LD      E,A
        LD      D,0
        LD      HL,PS_TAB
        ADD     HL,DE
        POP     DE
        LD      C,(HL)
        INC     HL
        LD      B,(HL)
        INC     HL
        PUSH    BC              ; the address
        LD      C,(HL)
        INC     HL
        LD      B,(HL)          ; BC = the size
        POP     HL              ; HL = the address
        POP     AF              ; row 0 is MAIN, the one checked
        OR      A
        LD      A,1
        JR      Z,.FORMS
        XOR     A
        JR      .FORMS
.ENT:   PUSH    DE
        CALL    TAB_FIND
        POP     DE
        INC     HL
        LD      C,(HL)
        INC     HL
        LD      B,(HL)          ; BC = the size
        INC     HL
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A             ; HL = the address
        LD      A,1             ; checked
.FORMS: LD      (.CHECKED),A
        LD      A,(REF_FORM)
        CP      3
        JR      Z,.SIZE
        LD      A,D
        AND     $80
        LD      (.NEGATIVE),A
        ADD     HL,DE           ; HL = the value
        LD      A,0
        RLA                     ; A = the carry
        LD      (.CARRY),A
        LD      A,(.NEGATIVE)
        OR      A
        JR      Z,.POS
        LD      A,(.CARRY)      ; a negative addend: no carry means below 0
        OR      A
        JR      Z,.RANGE
        LD      A,(.CHECKED)    ; and below the target when checked
        OR      A
        RET     Z
        JR      .RANGE
.POS:   LD      A,(.CARRY)      ; carry: past $FFFF
        OR      A
        JR      NZ,.RANGE
        LD      A,(.CHECKED)
        OR      A
        RET     Z
        PUSH    HL              ; checked: the addend no more than the size
        LD      H,B
        LD      L,C
        OR      A
        SBC     HL,DE
        POP     HL
        RET     NC
.RANGE: LD      HL,220          ; L-RANGE
        JP      DG_PLAIN
.SIZE:  LD      H,B             ; SIZE16: the size plus the addend
        LD      L,C
        ADD     HL,DE
        RET

.CHECKED:  DB      0
.NEGATIVE:  DB      0
.CARRY:   DB      0

; A = the next byte of the byte stream being copied.
.SRCBYTE:   PUSH    IX
        LD      IX,(SRC_FD)
        CALL    FIL_GETB
        POP     IX
        JP      C,DG_SHORT
        RET

; Write image byte A to the output: as itself, or into a .HEX record.
; Preserves BC, DE, HL, IX.
.OUTBYTE:   PUSH    HL
        LD      HL,OUT_KIND
        BIT     2,(HL)
        POP     HL
        JR      NZ,HEX_PUT
; Write A to the output file, adding it to the image's CRC. Preserves BC,
; DE, HL, IX.
OUT_RAW:   PUSH    HL
        LD      HL,IMG_CRC
        CALL    CRC_FOLD
        POP     HL
        PUSH    IX
        LD      IX,OUT_FD
        CALL    FIL_PUTB
        POP     IX
        RET     NC
        JP      DG_DISK

; ---- Intel HEX (linker §7.6) -------------------------------------------------

HEX_ADDR: DW     0              ; the address of the record being filled
HEX_CNT: DB      0              ; its bytes so far
HEX_BUF: DS      16
HEX_END: DB      ":00000001FF",13,10

; Add image byte A to the record, writing it when full. Preserves BC, DE,
; HL, IX.
HEX_PUT: PUSH    HL
        PUSH    DE
        LD      HL,HEX_CNT
        LD      E,(HL)
        INC     (HL)
        LD      D,0
        LD      HL,HEX_BUF
        ADD     HL,DE
        LD      (HL),A
        LD      A,E
        POP     DE
        POP     HL
        CP      15
        RET     NZ
; Write the record, if it has any bytes: colon, count, address, type 00,
; data and checksum in hex, then CR LF. Preserves BC, DE, HL, IX.
HEX_OUT:
        LD      A,(HEX_CNT)
        OR      A
        RET     Z
        PUSH    HL
        PUSH    BC
        LD      B,A
        LD      A,':'
        CALL    OUT_RAW
        LD      C,0             ; the sum
        LD      A,B
        CALL    .HEXBYTE
        LD      HL,(HEX_ADDR)
        LD      A,H
        CALL    .HEXBYTE
        LD      A,L
        CALL    .HEXBYTE
        XOR     A
        CALL    .HEXBYTE
        LD      A,L             ; the next record's address
        ADD     A,B
        LD      L,A
        ADC     A,H
        SUB     L
        LD      H,A
        LD      (HEX_ADDR),HL
        LD      HL,HEX_BUF
.DATA:  LD      A,(HL)
        CALL    .HEXBYTE
        INC     HL
        DJNZ    .DATA
        XOR     A               ; B = 0 now
        LD      (HEX_CNT),A
        SUB     C
        CALL    .HEXBYTE
        LD      A,13
        CALL    OUT_RAW
        LD      A,10
        CALL    OUT_RAW
        POP     BC
        POP     HL
        RET

; Write A in two hex digits and add it to C. Preserves B, DE, HL, IX.
.HEXBYTE: PUSH    AF
        ADD     A,C
        LD      C,A
        POP     AF
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    .NIBBLE
        POP     AF
.NIBBLE:   CALL    LK_DIGIT
        JP      OUT_RAW
