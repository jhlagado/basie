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

PROF    EQU     LIBH+42         ; the profile block's fields (object format §5)
PR_CLASS EQU    PROF+0
PR_KINDS EQU    PROF+1
PR_BASE EQU     PROF+2
PR_LIMIT EQU    PROF+4
PR_TOP  EQU     PROF+6
PR_OPTS EQU     PROF+16
PR_FILE EQU     PROF+20

S_TEXT  EQU     2               ; sections, for SEL_SEC: kinds 3 and 4
S_BSS   EQU     3               ; are the sections of their blobs, and DATA
S_START EQU     4               ; is TEXT with OF_R's bit
S_DATA  EQU     S_TEXT+OF_R

CURSOR: DW      0               ; the next free address
SEL_SEC: DB     0               ; the pass's section
SEL_CLS: DB     0               ; and alignment class
IMG_END: DW     0
SEC_BEG: DW     0               ; Phase C: the section's start
SEC_SET: DB     0               ; nonzero once its first blob is placed
DAT_BEG: DW     0
DAT_END: DW     0
BSS_BEG: DW     0
EM_DLT: DW      0               ; Phase D: COPY's distance from DATA
FREEADR: DW     0
RESERVE: DW     0
FILEADR: DW     0
FILESIZ: DW     0
NFILES: DB      0
OUTPOS: DW      0               ; Phase D: the address written up to
WK_OWN: DB      0               ; the directory being walked: 0 library
WK_CB:  DW      0               ; the routine called for each blob
WK_KIND: DB     0
WK_NM:  DB      0               ; nonzero: walks reset the name readers
WK_OFF: DW      0               ; the blob's byte-stream offset
WK_ENT: DW      0               ; the blob's entry
SRC_FD: DW      0               ; Phase D: the byte stream being copied
SRCBASE: DS     3               ; the byte stream's start in its file
PSEUDO: DS      40              ; MAIN to FILECOUNT: address, size

; ---- walking a directory ---------------------------------------------------

; Walk the library's directory, then the program's.
WALK2:  XOR     A
        CALL    WALK
        LD      A,1
; Walk the library's directory (A = 0) or the program's (A = 1), calling
; WK_CB for each blob with WK_ENT, WK_KIND, D_SIZE, D_NREFS and WK_OFF set
; and the directory at its first reference. The callback consumes the
; references, with REFSKIP or by copying the blob. In Phase E (WK_NM) the
; owner's name reader starts again with each walk.
WALK:   LD      (WK_OWN),A
        LD      HL,WK_NM
        INC     (HL)
        DEC     (HL)
        CALL    NZ,NM_RESET
        LD      A,(WK_OWN)
        OR      A
        JR      NZ,.PROG
        LD      IX,LIB_FD
        LD      A,(LIBH+14)
        LD      HL,(LIBH+12)
        CALL    F_SEEK
        JP      C,R_SHORT
        LD      HL,0
        JR      .GO
.PROG:  LD      IX,DR_FD
        XOR     A
        LD      HL,20           ; past the program header
        CALL    F_SEEK
        JP      C,R_SHORT
        LD      HL,(PRGH+16)
        DEC     HL
.GO:    LD      (D_PREV),HL
        LD      HL,0
        LD      (WK_OFF),HL
.REC:   CALL    R_U8
        CP      $FF
        RET     Z
        LD      (D_HEADER),A
        AND     7
        CP      6
        JR      Z,.CTRL
        LD      (WK_KIND),A
        LD      A,(D_HEADER)
        BIT     3,A
        JR      Z,.IMPL
        CALL    R_U16
        JR      .ORD
.IMPL:  LD      HL,(D_PREV)
        INC     HL
.ORD:   LD      (D_PREV),HL
        CALL    ENT_MAKE
        LD      (WK_ENT),HL
        CALL    R_U16
        LD      (D_SIZE),HL
        CALL    R_U8
        LD      L,A
        LD      H,0
        CP      255
        JR      NZ,.CNT
        CALL    R_U16
.CNT:   LD      (D_NREFS),HL
        PUSH    IX
        LD      HL,(WK_CB)
        CALL    .CALL
        POP     IX
        LD      A,(WK_KIND)
        CP      K_BSS
        JR      Z,.REC
        LD      HL,(WK_OFF)
        LD      DE,(D_SIZE)
        ADD     HL,DE
        LD      (WK_OFF),HL
        JR      .REC
.CALL:  JP      (HL)
.CTRL:  LD      A,(D_HEADER)
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
.SKIP:  CALL    R_U8
        DJNZ    .SKIP
        JR      .REC

; Read and discard the current blob's references.
REFSKIP:
        LD      HL,(D_NREFS)
.NEXT:  LD      A,H
        OR      L
        RET     Z
        PUSH    HL
        CALL    REFREAD
        POP     HL
        DEC     HL
        JR      .NEXT

; Read one reference: D_LSTOFF = its offset, D_FORM its form, HL its target,
; DE its addend. Offsets accumulate from REFSTART.
REFREAD:
        CALL    R_U8
        LD      B,A
        AND     $3F
        CP      63
        JR      NZ,.DELTA
        CALL    R_U16
        JR      .OFF
.DELTA: LD      L,A
        LD      H,0
        LD      A,(D_HAVLST)
        OR      A
        JR      Z,.OFF
        LD      DE,(D_LSTOFF)
        ADD     HL,DE
.OFF:   LD      (D_LSTOFF),HL
        LD      A,1
        LD      (D_HAVLST),A
        XOR     A
        BIT     7,B
        JR      Z,.FORM
        CALL    R_U8
.FORM:  LD      (D_FORM),A
        CALL    R_U16
        PUSH    HL
        LD      DE,0
        BIT     6,B
        JR      Z,.NOADD
        CALL    R_U16
        EX      DE,HL
.NOADD: POP     HL
        RET

; Before a blob's references: no previous offset yet.
REFSTART:
        XOR     A
        LD      (D_HAVLST),A
        RET

; Whether the blob just read belongs to this pass: live, of the pass's
; class, and in its section. Z when it does.
SELECT: LD      HL,(WK_ENT)
        BIT     5,(HL)
        JR      Z,.NO
        LD      DE,E_LAYOUT
        ADD     HL,DE
        LD      A,(SEL_CLS)
        CP      (HL)
        RET     NZ
        LD      A,(WK_KIND)     ; the blob's section: code and rodata
        CP      K_DATA          ; are TEXT; data is TEXT or, under R, DATA
        JR      NC,.KIND
        LD      A,S_TEXT
.KIND:  JR      NZ,.SEC
        LD      A,(O_FLAGS)
        AND     OF_R
        OR      S_TEXT
.SEC:   LD      HL,SEL_SEC
        CP      (HL)
        RET
.NO:    OR      1               ; NZ
        RET

; Make the passes of section A, calling HL for each blob: for each class
; from 7 down that has a live blob (linker §10), the library's directory
; then the program's. DATA has passes only under option R.
SECTION:
        LD      (SEL_SEC),A
        LD      (WK_CB),HL
        CP      S_DATA
        JR      NZ,.GO
        LD      A,(O_FLAGS)
        AND     OF_R
        RET     Z
.GO:    LD      A,7
.CLASS: LD      (SEL_CLS),A
        CALL    PRESENT
        CALL    NZ,WALK2
        LD      A,(SEL_CLS)
        SUB     1
        JR      NC,.CLASS
        RET

; NZ when alignment class SEL_CLS has a live blob.
PRESENT:
        LD      A,(SEL_CLS)
        INC     A
        LD      B,A
        LD      A,(CLASSES)
.SHIFT: RRCA
        DJNZ    .SHIFT
        RLCA                    ; back one: bit 0 is the class's
        AND     1
        RET

; ---- Phase C -----------------------------------------------------------------

PHASEC: XOR     A               ; the CRCs were checked in Phase A
        LD      (CRC_ON),A
        LD      HL,(PR_BASE)
        LD      (CURSOR),HL
        LD      A,S_START
        CALL    PLACESEC
        LD      A,S_TEXT
        CALL    PLACESEC
        LD      A,S_DATA        ; empty, at TEXT's end, without R
        CALL    PLACESEC
        LD      (DAT_BEG),HL
        LD      (DAT_END),DE
        EX      DE,HL           ; COPY follows DATA: the image ends at
        PUSH    HL              ; DATA's end plus its size
        OR      A
        SBC     HL,DE
        POP     DE
        ADD     HL,DE
        LD      (IMG_END),HL
        LD      (CURSOR),HL
        LD      A,S_BSS
        CALL    PLACESEC
        LD      (BSS_BEG),HL
        ; the file table, after BSS, when the program uses files
        LD      A,(O_FILES)
        OR      A
        JR      NZ,.NF
        LD      A,4
.NF:    LD      (NFILES),A
        LD      HL,(CURSOR)
        LD      (FILEADR),HL
        LD      HL,0
        LD      A,(USEFILES)
        OR      A
        JR      Z,.NOFILES
        LD      A,(NFILES)
        LD      B,A
        LD      DE,(PR_FILE)
.MUL:   ADD     HL,DE
        DJNZ    .MUL
.NOFILES:
        LD      (FILESIZ),HL
        LD      DE,(CURSOR)
        ADD     HL,DE
        LD      (FREEADR),HL
        ; aliases of live blobs: their address and effective size
        LD      HL,0
.ALIAS: PUSH    HL
        CALL    ENTRYAT
        JR      C,.ADONE
        BIT     6,(HL)
        CALL    NZ,ALIASAT
        POP     HL
        INC     HL
        JR      .ALIAS
.ADONE: POP     HL
        ; the stack reserve: the compiler's, or STACK= when larger
        LD      HL,(LIMITS)
        LD      DE,(O_STACK)
        PUSH    HL
        OR      A
        SBC     HL,DE
        POP     HL
        JR      NC,.RES
        EX      DE,HL
.RES:   LD      (RESERVE),HL
        CALL    PSEUDOS
        ; fit checks (linker §6.4)
        LD      HL,(PR_LIMIT)
        LD      DE,(IMG_END)
        OR      A
        SBC     HL,DE
        LD      HL,216          ; L-FIT-IMAGE
        JP      C,ERRPLAIN
        LD      HL,(FREEADR)
        LD      DE,(RESERVE)
        ADD     HL,DE
        LD      HL,217          ; L-FIT-MEMORY: past $FFFF
        JP      C,ERRPLAIN
        LD      HL,(FREEADR)
        ADD     HL,DE
        EX      DE,HL           ; DE = the memory needed
        LD      HL,(PR_TOP)
        LD      A,(O_FLAGS)
        AND     OF_B
        JR      Z,.TOP
        LD      HL,(PR_LIMIT)
.TOP:   OR      A
        SBC     HL,DE
        RET     NC
        LD      HL,219          ; L-FIT-NOMINAL: a warning only
        JP      WARNING

; Place section A: HL = its start, DE = its end. The first blob placed is
; of the largest class present, so the section starts at its address, which
; is the cursor rounded up to that class (linker §6.3).
PLACESEC:
        LD      HL,(CURSOR)
        LD      (SEC_BEG),HL
        LD      HL,SEC_SET
        LD      (HL),0
        LD      HL,PLACE
        CALL    SECTION
        LD      HL,(SEC_BEG)
        LD      DE,(CURSOR)
        RET

; Place the blob just read, if it is in the pass, and skip its references.
PLACE:  CALL    SELECT
        JP      NZ,REFSKIP
        LD      HL,(WK_ENT)     ; the alignment
        LD      DE,E_LAYOUT
        ADD     HL,DE
        LD      A,(HL)
        CALL    ALIGNUP         ; HL = CURSOR rounded up
        LD      A,(SEC_SET)     ; the section starts at its first blob
        OR      A
        JR      NZ,.SET
        DEC     A
        LD      (SEC_SET),A
        LD      (SEC_BEG),HL
.SET:   EX      DE,HL           ; DE = the address
        LD      HL,(WK_ENT)
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
        LD      (CURSOR),HL
        JP      REFSKIP

; HL = CURSOR rounded up to alignment code A: 2^A bytes, 256 for 7.
ALIGNUP:
        LD      HL,(CURSOR)
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
ALIASAT:
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
        CALL    ENT_MAKE
        POP     BC
        POP     DE              ; DE = the alias entry
        RET     C
        BIT     5,(HL)
        RET     Z
        INC     HL
        LD      A,(HL)          ; the base's size less the offset
        SUB     C
        LD      (PSEUDO),A      ; scratch
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
        LD      A,(PSEUDO)
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
PSEUDOS:
        LD      HL,PSEUDO
        LD      (PS_PTR),HL
        LD      HL,(ENTRYORD)   ; MAIN
        CALL    ENT_MAKE
        INC     HL
        LD      C,(HL)
        INC     HL
        LD      B,(HL)
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        CALL    .PUT            ; address DE, size BC
        LD      DE,(PR_BASE)    ; IMAGE
        LD      HL,(IMG_END)
        CALL    .SPAN
        LD      HL,(FILEADR)    ; BSS: to the end of the file table
        LD      BC,(FILESIZ)
        ADD     HL,BC
        LD      DE,(BSS_BEG)
        CALL    .SPAN
        LD      DE,(FREEADR)    ; FREE
        LD      BC,0
        CALL    .PUT
        LD      HL,(RESERVE)    ; REQUIRED: FREE plus the reserve
        LD      B,H
        LD      C,L
        ADD     HL,DE
        EX      DE,HL
        CALL    .PUT
        LD      HL,(DAT_END)    ; DATA, then DATACOPY: COPY, at DATA's
        LD      DE,(DAT_BEG)    ; end, of DATA's size (empty, at TEXT's
        CALL    .SPAN           ; end, without R)
        LD      DE,(DAT_END)
        CALL    .PUT
        LD      A,(O_FLAGS)     ; OPTIONS: 1 keep the CCP (B), 2 re-runnable
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
        LD      DE,(FILEADR)    ; FILES
        LD      BC,(FILESIZ)
        CALL    .PUT
        LD      BC,0            ; FILECOUNT
        LD      D,B
        LD      E,B
        LD      A,(USEFILES)
        OR      A
        JR      Z,.PUT
        LD      A,(NFILES)
        LD      E,A
; The next row: address DE, size BC. Preserves BC and DE.
.PUT:   LD      HL,(PS_PTR)
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      (HL),C
        INC     HL
        LD      (HL),B
        INC     HL
        LD      (PS_PTR),HL
        RET
; The next row: address DE, size HL - DE.
.SPAN:  OR      A
        SBC     HL,DE
        LD      B,H
        LD      C,L
        JR      .PUT

PS_PTR: DW      0

; ---- Phase D -----------------------------------------------------------------

OUT_FD: DS      FDSIZE
TB_FD   EQU     OUT_FD          ; option W's dump, made before Phase D
OUT_TY: DB      "$$$"
OUT_TXT: DS     13
LIBB_FD: DS     FDSIZE          ; the library again, for its byte section
BY_FD:  DS      FDSIZE
T_BUF   EQU     BY_FD           ; the command tail (130 bytes) and a bad
T_BAD   EQU     LIBB_FD         ; option's text (32), used only in parsing
BY_TY:  DB      "$BY"
BY_TXT: DS      13

PHASED: ; NAME.$$$ on the output drive, under the output name
        LD      IX,OUT_FD
        CALL    OUTNAME         ; HL = name, A = drive
        LD      DE,OUT_TY
        CALL    F_INIT
        LD      HL,OUT_TXT
        LD      (R_NAME),HL
        XOR     A               ; .COM: the last record padded with zeros
        CALL    F_MAKE
        JP      C,DISKERR
        LD      A,1
        LD      (OUT_MADE),A
        ; the library's byte section, through a second FD
        LD      IX,LIBB_FD
        LD      A,(O_LDRV)
        OR      A
        JR      NZ,.LD
        LD      A,(LIB_FD+FD_FCB)
.LD:    LD      HL,O_LIB
        LD      DE,LIB_TY
        CALL    F_INIT
        CALL    F_OPEN
        JP      C,R_SHORT
        ; the program's byte stream, NAME.$BY on the spool drive
        LD      IX,BY_FD
        LD      A,(DR_FD+FD_FCB)
        LD      HL,O_NAME
        LD      DE,BY_TY
        CALL    F_INIT
        LD      HL,O_NAME
        LD      DE,BY_TXT
        LD      BC,BY_TY
        CALL    FILETXT
        LD      HL,BY_TXT
        LD      (R_NAME),HL
        CALL    F_OPEN
        LD      HL,225          ; L-MISSING
        JP      C,ERRFILE
        CALL    BYHEAD
        LD      HL,$FFFF
        LD      (IMG_CRC),HL
        CALL    LN_OPEN
        LD      HL,(PR_BASE)
        LD      (OUTPOS),HL
        LD      (HX_ADDR),HL
        LD      A,S_START
        CALL    EMITSEC
        LD      A,S_TEXT
        CALL    EMITSEC
        LD      A,S_DATA
        CALL    EMITSEC
        LD      HL,(DAT_END)    ; COPY: the DATA passes again, with the
        LD      DE,(DAT_BEG)    ; output DATA's size further on
        OR      A
        SBC     HL,DE
        LD      (EM_DLT),HL
        LD      A,S_DATA
        CALL    EMITSEC
        ; .COM and .BIN: zeros to the end of the record; .HEX: the last
        ; data record, the end record, then $1A. Padding is in the CRC.
        LD      A,(O_KIND)
        CP      4
        LD      C,0
        JR      NZ,.PAD
        CALL    HX_FLUSH
        LD      HL,HX_END
        LD      B,13
.END:   LD      A,(HL)
        CALL    OUTR
        INC     HL
        DJNZ    .END
        LD      C,$1A
.PAD:   LD      A,(OUT_FD+FD_POS)
        OR      A
        JR      Z,.PADDED
        LD      A,C
        CALL    OUTR
        JR      .PAD
.PADDED:
        LD      IX,OUT_FD
        CALL    F_CLOSE
        JP      C,DISKERR
        JP      LN_CLOSE

; Write section A.
EMITSEC:
        LD      HL,EMIT
        JP      SECTION

; HL = the output's 8-character name and A its drive: option O's, else the
; first part's.
OUTNAME:
        LD      A,(O_OSET)
        OR      A
        JR      Z,.PART
        LD      HL,O_ONAM
        LD      A,(O_ODRV)
        OR      A
        RET     NZ
        LD      A,(O_DRV)
        RET
.PART:  LD      HL,O_NAME
        LD      A,(O_DRV)
        RET

; Check NAME.$BY's header (object format §6): magic BSIB, version 1.0, and
; the directory's compilation stamp.
BYHEAD: LD      HL,.MAGIC
        LD      B,4
.MAG:   CALL    R_RAW
        CP      (HL)
        JR      NZ,.BAD
        INC     HL
        DJNZ    .MAG
        CALL    R_RAW
        CP      1
        JR      NZ,.BAD
        CALL    R_RAW
        OR      A
        JR      NZ,.BAD
        CALL    R_RAW
        LD      L,A
        CALL    R_RAW
        LD      H,A
        LD      DE,(PRGH+6)
        OR      A
        SBC     HL,DE
        RET     Z
        LD      HL,202          ; L-STAMP
        JP      ERRPLAIN
.BAD:   LD      HL,200          ; L-FORMAT
        JP      ERRFILE
.MAGIC: DB      "BSIB"

; Copy the blob just read to the output, if it is in the pass, patching its
; references; otherwise skip its references.
EMIT:   CALL    SELECT
        JR      Z,.SEL
        ; not in the pass; but a program code blob's line record is still
        ; read in the code pass, to keep the line stream in step
        LD      A,(SEL_SEC)
        CP      S_TEXT
        JP      NZ,REFSKIP
        LD      A,(SEL_CLS)
        OR      A
        JP      NZ,REFSKIP
        LD      A,(WK_OWN)
        OR      A
        JP      Z,REFSKIP
        LD      A,(WK_KIND)
        CP      K_CODE
        JP      NZ,REFSKIP
        XOR     A
        CALL    LN_BLOB
        JP      REFSKIP
.SEL:   ; padding up to the blob's address, or in COPY its copy's
        LD      HL,(WK_ENT)
        LD      DE,E_ADDR
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = the address
        LD      HL,(EM_DLT)
        LD      A,H
        OR      L
        ADD     HL,DE           ; keeps Z
        PUSH    HL
        LD      A,1
        CALL    Z,LN_BLOB       ; its line-table entries, but not in COPY
        POP     DE
        LD      HL,(OUTPOS)
.PAD:   LD      A,L
        CP      E
        JR      NZ,.ZERO
        LD      A,H
        CP      D
        JR      Z,.SRC
.ZERO:  XOR     A
        CALL    OUTB
        INC     HL
        JR      .PAD
.SRC:   LD      BC,(D_SIZE)     ; the output position moves past the blob
        ADD     HL,BC
        LD      (OUTPOS),HL
        ; the blob's bytes: the library's byte section or the program's stream
        LD      A,(WK_OWN)
        OR      A
        JR      NZ,.PSRC
        LD      HL,LIBB_FD
        LD      (SRC_FD),HL
        LD      HL,(LIBH+16)
        LD      A,(LIBH+18)
        JR      .SEEK
.PSRC:  LD      HL,BY_FD
        LD      (SRC_FD),HL
        LD      HL,8            ; past the stream's header
        XOR     A
.SEEK:  LD      DE,(WK_OFF)
        ADD     HL,DE
        ADC     A,0
        PUSH    IX
        LD      IX,(SRC_FD)
        CALL    F_SEEK
        POP     IX
        JP      C,R_SHORT
        LD      HL,0            ; HL = the bytes copied so far
        LD      (D_REFEND),HL
        CALL    REFSTART
.REF:   LD      HL,(D_NREFS)
        LD      A,H
        OR      L
        JR      Z,.REST
        DEC     HL
        LD      (D_NREFS),HL
        CALL    REFREAD         ; HL = target, DE = addend
        PUSH    DE
        PUSH    HL
        LD      HL,(D_LSTOFF)   ; copy up to the reference
        CALL    COPYTO
        POP     HL
        POP     DE
        CALL    VALUE           ; HL = the value
        CALL    PATCH
        JR      .REF
.REST:  LD      HL,(D_SIZE)
        JR      COPYTO

; Copy source bytes to the output until D_REFEND reaches HL.
COPYTO: LD      DE,(D_REFEND)
.LOOP:  LD      A,L
        CP      E
        JR      NZ,.ONE
        LD      A,H
        CP      D
        RET     Z
.ONE:   CALL    SRCB
        CALL    OUTB
        INC     DE
        LD      (D_REFEND),DE
        JR      .LOOP

; Write the reference's value HL in its form, in place of its placeholder.
PATCH:  LD      A,(D_FORM)
        CP      1
        JR      Z,.LO
        CP      2
        JR      Z,.HI
        CALL    .SKIP2          ; ABS16 and SIZE16: two bytes
        LD      A,L
        CALL    OUTB
        LD      A,H
        CALL    OUTB
        RET
.LO:    CALL    .SKIP1
        LD      A,L
        JP      OUTB
.HI:    CALL    .SKIP1
        LD      A,H
        JP      OUTB
.SKIP2: CALL    .SKIP1
.SKIP1: CALL    SRCB            ; the placeholder byte
        PUSH    AF
        LD      DE,(D_REFEND)
        INC     DE
        LD      (D_REFEND),DE
        POP     AF
        OR      A
        RET     Z
        LD      A,(O_FLAGS)     ; nonzero: an error under option V
        AND     OF_V
        RET     Z
        LD      HL,221          ; L-PLACEHOLDER
        JP      ERRPLAIN

; HL = the value of a reference to target HL with addend DE, in D_FORM's
; form (linker §7.4). The value is the target's address plus the addend,
; signed, and must lie in 0 to $FFFF; a reference to a blob, or to MAIN, must
; also stay within its target: address <= value <= address + size.
VALUE:  LD      A,H
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
        LD      HL,PSEUDO
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
        CALL    ENT_MAKE
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
.FORMS: LD      (V_CHK),A
        LD      A,(D_FORM)
        CP      3
        JR      Z,.SIZE
        LD      A,D
        AND     $80
        LD      (V_NEG),A
        ADD     HL,DE           ; HL = the value
        LD      A,0
        RLA                     ; A = the carry
        LD      (V_CY),A
        LD      A,(V_NEG)
        OR      A
        JR      Z,.POS
        LD      A,(V_CY)        ; a negative addend: no carry means below 0
        OR      A
        JR      Z,.RANGE
        LD      A,(V_CHK)       ; and below the target when checked
        OR      A
        RET     Z
        JR      .RANGE
.POS:   LD      A,(V_CY)        ; carry: past $FFFF
        OR      A
        JR      NZ,.RANGE
        LD      A,(V_CHK)
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
        JP      ERRPLAIN
.SIZE:  LD      H,B             ; SIZE16: the size plus the addend
        LD      L,C
        ADD     HL,DE
        RET

V_CHK:  DB      0
V_NEG:  DB      0
V_CY:   DB      0

; A = the next byte of the byte stream being copied.
SRCB:   PUSH    IX
        LD      IX,(SRC_FD)
        CALL    F_GETB
        POP     IX
        JP      C,R_SHORT
        RET

; Write image byte A to the output: as itself, or into a .HEX record.
; Preserves BC, DE, HL, IX.
OUTB:   PUSH    HL
        LD      HL,O_KIND
        BIT     2,(HL)
        POP     HL
        JR      NZ,HX_PUT
; Write A to the output file, adding it to the image's CRC. Preserves BC,
; DE, HL, IX.
OUTR:   PUSH    HL
        LD      HL,IMG_CRC
        CALL    CRC_UPD
        POP     HL
        PUSH    IX
        LD      IX,OUT_FD
        CALL    F_PUTB
        POP     IX
        RET     NC
        JP      DISKERR

; ---- Intel HEX (linker §7.6) -------------------------------------------------

HX_ADDR: DW     0               ; the address of the record being filled
HX_CNT: DB      0               ; its bytes so far
HX_BUF: DS      16
HX_END: DB      ":00000001FF",13,10

; Add image byte A to the record, writing it when full. Preserves BC, DE,
; HL, IX.
HX_PUT: PUSH    HL
        PUSH    DE
        LD      HL,HX_CNT
        LD      E,(HL)
        INC     (HL)
        LD      D,0
        LD      HL,HX_BUF
        ADD     HL,DE
        LD      (HL),A
        LD      A,E
        POP     DE
        POP     HL
        CP      15
        RET     NZ
; Write the record, if it has any bytes: colon, count, address, type 00,
; data and checksum in hex, then CR LF. Preserves BC, DE, HL, IX.
HX_FLUSH:
        LD      A,(HX_CNT)
        OR      A
        RET     Z
        PUSH    HL
        PUSH    BC
        LD      B,A
        LD      A,':'
        CALL    OUTR
        LD      C,0             ; the sum
        LD      A,B
        CALL    HX_HEX
        LD      HL,(HX_ADDR)
        LD      A,H
        CALL    HX_HEX
        LD      A,L
        CALL    HX_HEX
        XOR     A
        CALL    HX_HEX
        LD      A,L             ; the next record's address
        ADD     A,B
        LD      L,A
        ADC     A,H
        SUB     L
        LD      H,A
        LD      (HX_ADDR),HL
        LD      HL,HX_BUF
.DATA:  LD      A,(HL)
        CALL    HX_HEX
        INC     HL
        DJNZ    .DATA
        XOR     A               ; B = 0 now
        LD      (HX_CNT),A
        SUB     C
        CALL    HX_HEX
        LD      A,13
        CALL    OUTR
        LD      A,10
        CALL    OUTR
        POP     BC
        POP     HL
        RET

; Write A in two hex digits and add it to C. Preserves B, DE, HL, IX.
HX_HEX: PUSH    AF
        ADD     A,C
        LD      C,A
        POP     AF
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    .NIB
        POP     AF
.NIB:   CALL    HEXDIG
        JP      OUTR
