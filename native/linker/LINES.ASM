; The line table (linker §7.7; object format §11), written during Phase D
; from the line stream NAME.$LN, unless option N.
;
; Line stream: BSIL, version, stamp; then part records (tag 1: part, name
; length, name) and blob-lines records (tag 2: ordinal, count, entries); then
; tag $FF and a CRC. Line table: BSIT, version, part count, an output name and
; a library name (both empty here), the part names, then 5-byte entries in
; address order, then $FF x 5, the entry count, the image's CRC and a CRC.

LN_FD:  DS      FD_SIZE
LN_TYPE:  DB      "$LN"
LN_TEXT: DS      13
LT_FD:  DS      FD_SIZE
LT_TYPE:  DB      "$LT"
LT_TEXT: DS      13
LN_ON:  DB      0               ; 1 while a line table is being written
LN_TAG: DB      0               ; the tag of the next line-stream record
LN_CRC: DW      0               ; the line stream's CRC, as read
LT_CRC: DW      0               ; the line table's CRC, as written
IMG_CRC: DW     0               ; the image's CRC, as written
LT_CNT:   DW      0             ; entries written
LN_POS: DW      0               ; an entry's offset in its blob
LN_PART: DB     0               ; and its part

; A = the next byte of the line stream, added to its CRC.
LN_BYTE:    PUSH    IX
        LD      IX,LN_FD
        CALL    FIL_GETB
        POP     IX
        JR      C,.SHORT
        PUSH    HL
        LD      HL,LN_CRC
        CALL    CRC_FOLD
        POP     HL
        RET
.SHORT: LD      HL,LN_TEXT
        LD      (RD_NAME),HL
        JP      DG_SHORT

; HL = the next word of the line stream.
LN_WORD:    CALL    LN_BYTE
        LD      L,A
        CALL    LN_BYTE
        LD      H,A
        RET

; Write A to the line table, adding it to its CRC. Preserves A, BC, DE, HL.
LT_BYTE:    PUSH    HL
        LD      HL,LT_CRC
        CALL    CRC_FOLD
        POP     HL
        PUSH    AF
        PUSH    IX
        LD      IX,LT_FD
        CALL    FIL_PUTB
        POP     IX
        JR      C,.FULL
        POP     AF
        RET
.FULL:  POP     AF
        LD      HL,LT_TEXT
        LD      (RD_NAME),HL
        JP      DG_DISK

; Write HL to the line table, low byte first.
LT_WORD:    LD      A,L
        CALL    LT_BYTE
        LD      A,H
        JR      LT_BYTE

; Open the line stream and the line table, and write the table's header:
; the part names, from the stream's part records. Leaves LN_TAG holding the
; tag of the first blob-lines record, or $FF.
LN_OPEN:
        LD      A,(OP_FLAGS)
        AND     OF_N
        RET     NZ              ; option N: no line table
        LD      A,1
        LD      (LN_ON),A
        LD      IX,LN_FD
        LD      A,(DIR_FD+FD_FCB)
        LD      HL,CMD_NAME
        LD      DE,LN_TYPE
        CALL    FIL_INIT
        LD      HL,CMD_NAME
        LD      DE,LN_TEXT
        LD      BC,LN_TYPE
        CALL    FIL_TEXT
        CALL    FIL_OPEN
        LD      HL,LN_TEXT
        LD      (RD_NAME),HL
        LD      HL,225          ; L-MISSING
        JP      C,DG_FILE
        CALL    .HEAD
        ; first pass: count the parts
        LD      BC,0
.COUNT: CALL    LN_BYTE
        CP      $FF
        JR      Z,.COUNTED
        CP      1
        JR      Z,.ONEPART
        CP      2
        JP      NZ,.BAD
        PUSH    BC
        CALL    .SKIPREC        ; a blob-lines record
        POP     BC
        JR      .COUNT
.ONEPART: INC     BC
        CALL    LN_BYTE         ; the part's number
        CALL    LN_BYTE         ; its name's length
        LD      D,A
.SKIPNAME: LD      A,D
        OR      A
        JR      Z,.COUNT
        CALL    LN_BYTE
        DEC     D
        JR      .SKIPNAME
.COUNTED:
        PUSH    BC
        ; the line table, NAME.$LT on the output drive
        LD      IX,LT_FD
        CALL    OUT_PICK
        LD      DE,LT_TYPE
        CALL    FIL_INIT
        CALL    OUT_PICK
        LD      DE,LT_TEXT
        LD      BC,LT_TYPE
        CALL    FIL_TEXT
        LD      HL,LT_TEXT
        LD      (RD_NAME),HL
        XOR     A
        CALL    FIL_MAKE
        JP      C,DG_DISK
        LD      A,1
        LD      (LT_MADE),A
        LD      HL,$FFFF
        LD      (LT_CRC),HL
        LD      HL,0
        LD      (LT_CNT),HL
        LD      HL,.MAGIC
        LD      B,4
.PUTMAGIC:   LD      A,(HL)
        CALL    LT_BYTE
        INC     HL
        DJNZ    .PUTMAGIC
        LD      A,1             ; version 1.0
        CALL    LT_BYTE
        XOR     A
        CALL    LT_BYTE
        POP     BC
        LD      A,C             ; the part count
        CALL    LT_BYTE
        XOR     A               ; no output name, no library name
        CALL    LT_BYTE
        CALL    LT_BYTE
        ; second pass: from the start again, copying the part names
        CALL    .HEAD
.NAMES: CALL    LN_BYTE
        CP      1
        JR      NZ,.FIRST
        CALL    LN_BYTE         ; the part's number
        CALL    LN_BYTE
        LD      D,A             ; the name's length
        CALL    LT_BYTE
.NAME:  LD      A,D
        OR      A
        JR      Z,.NAMES
        CALL    LN_BYTE
        CALL    LT_BYTE
        DEC     D
        JR      .NAME
.FIRST: LD      (LN_TAG),A
        RET
; Seek to the stream's start and check its header and stamp.
.HEAD:  LD      IX,LN_FD
        XOR     A
        LD      HL,0
        CALL    FIL_SEEK
        JP      C,DG_SHORT
        LD      HL,$FFFF
        LD      (LN_CRC),HL
        LD      HL,.SRCMAGIC
        LD      B,4
.GETMAGIC:  CALL    LN_BYTE
        CP      (HL)
        JR      NZ,.BAD
        INC     HL
        DJNZ    .GETMAGIC
        CALL    LN_BYTE
        CP      1
        JR      NZ,.BAD
        CALL    LN_BYTE
        OR      A
        JR      NZ,.BAD
        CALL    LN_WORD
        LD      DE,(DIR_HEAD+6)
        OR      A
        SBC     HL,DE
        RET     Z
        LD      HL,202          ; L-STAMP
        JP      DG_PLAIN
.BAD:   LD      HL,LN_TEXT
        LD      (RD_NAME),HL
        LD      HL,200          ; L-FORMAT
        JP      DG_FILE
.MAGIC: DB      "BSIT"
.SRCMAGIC: DB     "BSIL"

; Skip the rest of a blob-lines record (after its tag).
.SKIPREC:
        CALL    LN_WORD         ; the ordinal
        CALL    LN_WORD         ; the entry count
.NEXT:  LD      A,H
        OR      L
        RET     Z
        PUSH    HL
        CALL    LN_ENTRY
        POP     HL
        DEC     HL
        JR      .NEXT

; Read one entry of a blob-lines record into LN_POS and LN_PART, returning
; HL = its source offset.
LN_ENTRY:
        CALL    LN_BYTE         ; control
        LD      B,A
        AND     $7F
        CP      127
        JR      NZ,.DELTA
        CALL    LN_WORD         ; an absolute offset
        JR      .OFF
.DELTA: LD      L,A
        LD      H,0
        LD      DE,(LN_POS)
        ADD     HL,DE
.OFF:   LD      (LN_POS),HL
        BIT     7,B
        JR      Z,.SRC
        CALL    LN_BYTE
        LD      (LN_PART),A
.SRC:   JP      LN_WORD

; Write the line-table entries for the blob being emitted, at address DE:
; one per statement for a program code blob whose record begins at offset 0,
; else a start entry ($FF, the ordinal) and then any statements. Called in
; every TEXT pass for each program code blob, emitted or not, so the line
; stream stays in step with the directory; A = 1 when the blob is emitted.
LN_BLOB:
        LD      (.EMITTED),A
        LD      (.ADDR),DE
        LD      A,(LN_ON)
        OR      A
        RET     Z
        LD      A,(WK_OWN)      ; a program code blob has a record
        OR      A
        JR      Z,.START
        LD      A,(WK_KIND)
        CP      K_CODE
        JR      NZ,.START
        CALL    .RECORD     ; HL = its entry count
        LD      (.LEFT),HL
        LD      HL,0
        LD      (LN_POS),HL
        LD      A,(.EMITTED)
        OR      A
        JR      Z,.SKIPALL
        LD      HL,(.LEFT)
        LD      A,H
        OR      L
        JR      Z,.ONLY
        CALL    LN_ENTRY        ; the first entry: at offset 0?
        PUSH    HL
        LD      HL,(LN_POS)
        LD      A,H
        OR      L
        JR      Z,.ATZERO
        CALL    .STARTER
.ATZERO:
        POP     HL
        CALL    .ENTRY
.MORE:  LD      HL,(.LEFT)
        DEC     HL
        LD      (.LEFT),HL
        LD      A,H
        OR      L
        JR      Z,.DONE
        CALL    LN_ENTRY
        CALL    .ENTRY
        JR      .MORE
.DONE:  JR      LN_NEXT
.SKIPALL:
        LD      HL,(.LEFT)
.SKIP:  LD      A,H
        OR      L
        JR      Z,LN_NEXT
        PUSH    HL
        CALL    LN_ENTRY
        POP     HL
        DEC     HL
        JR      .SKIP
.ONLY:
        CALL    .STARTER
        JR      LN_NEXT
.START: LD      A,(.EMITTED)    ; any other emitted blob: a start entry
        OR      A
        RET     Z
.STARTER:
        LD      HL,(.ADDR)
        CALL    LT_WORD
        LD      A,$FF
        CALL    LT_BYTE
        LD      HL,(RD_PREV)    ; the blob's ordinal
        CALL    LT_WORD
        JR      .COUNT
; An entry: address = the blob's + LN_POS, part, source HL.
.ENTRY: PUSH    HL
        LD      HL,(.ADDR)
        LD      DE,(LN_POS)
        ADD     HL,DE
        CALL    LT_WORD
        LD      A,(LN_PART)
        CALL    LT_BYTE
        POP     HL
        CALL    LT_WORD
.COUNT: LD      HL,(LT_CNT)
        INC     HL
        LD      (LT_CNT),HL
        RET

.EMITTED: DB     0
.ADDR: DW     0
.LEFT: DW     0

; The next blob-lines record must be the current blob's: HL = its count.
.RECORD:
        LD      A,(LN_TAG)
        CP      2
        JR      NZ,.BAD
        CALL    LN_WORD
        LD      DE,(RD_PREV)
        OR      A
        SBC     HL,DE
        JR      NZ,.BAD
        JP      LN_WORD
.BAD:   JR      LN_FAIL

; The line stream is out of step with the directory, or damaged.
LN_FAIL: LD      HL,LN_TEXT
        LD      (RD_NAME),HL
        LD      HL,214          ; L-TRUNCATED
        JP      DG_FILE

; Read the next record's tag into LN_TAG, skipping part records.
LN_NEXT:
        CALL    LN_BYTE
        CP      1
        JR      NZ,.SET
        CALL    LN_BYTE
        CALL    LN_BYTE
        LD      D,A
.NAME:  LD      A,D
        OR      A
        JR      Z,LN_NEXT
        CALL    LN_BYTE
        DEC     D
        JR      .NAME
.SET:   LD      (LN_TAG),A
        RET

; Finish the line table: the stream must be at its trailer, whose CRC is
; checked; then the table's trailer, with the image's CRC.
LN_CLOSE:
        LD      A,(LN_ON)
        OR      A
        RET     Z
        LD      A,(LN_TAG)
        CP      $FF
        JR      NZ,LN_FAIL
        LD      HL,(LN_CRC)     ; the stored CRC, read without adding it
        PUSH    HL
        LD      IX,LN_FD
        CALL    RD_RAW
        LD      E,A
        CALL    RD_RAW
        LD      D,A
        POP     HL
        OR      A
        SBC     HL,DE
        JR      NZ,LN_FAIL
        LD      B,5
.MARK:  LD      A,$FF
        CALL    LT_BYTE
        DJNZ    .MARK
        LD      HL,(LT_CNT)
        CALL    LT_WORD
        LD      HL,(IMG_CRC)
        CALL    LT_WORD
        LD      HL,(LT_CRC)
        CALL    LT_WORD
        LD      IX,LT_FD
        CALL    FIL_SHUT
        RET     NC
        LD      HL,LT_TEXT
        LD      (RD_NAME),HL
        JP      DG_DISK
