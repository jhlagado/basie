; The line table (linker §7.7; object format §11), written during Phase D
; from the line stream NAME.$LN, unless option N.
;
; Line stream: BSIL, version, stamp; then part records (tag 1: part, name
; length, name) and blob-lines records (tag 2: ordinal, count, entries); then
; tag $FF and a CRC. Line table: BSIT, version, part count, an output name and
; a library name (both empty here), the part names, then 5-byte entries in
; address order, then $FF x 5, the entry count, the image's CRC and a CRC.

LN_FD:  DS      FDSIZE
LN_TY:  DB      "$LN"
LN_TXT: DS      13
LT_FD:  DS      FDSIZE
LT_TY:  DB      "$LT"
LT_TXT: DS      13
LN_ON:  DB      0               ; 1 while a line table is being written
LN_TAG: DB      0               ; the tag of the next line-stream record
LN_CRC: DW      0               ; the line stream's CRC, as read
LT_CRC: DW      0               ; the line table's CRC, as written
IMG_CRC: DW     0               ; the image's CRC, as written
LN_N:   DW      0               ; entries written
LN_OFF: DW      0               ; an entry's offset in its blob
LN_PART: DB     0               ; and its part

; A = the next byte of the line stream, added to its CRC.
LNB:    PUSH    IX
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      IX,LN_FD
        CALL    F_GETB
        POP     HL
        POP     DE
        POP     BC
        POP     IX
        JR      C,.SHORT
        PUSH    HL
        LD      HL,LN_CRC
        CALL    CRC_UPD
        POP     HL
        RET
.SHORT: LD      HL,LN_TXT
        LD      (R_NAME),HL
        JP      R_SHORT

; HL = the next word of the line stream.
LNW:    CALL    LNB
        LD      L,A
        CALL    LNB
        LD      H,A
        RET

; Write A to the line table, adding it to its CRC. Preserves A, BC, DE, HL.
LTB:    PUSH    HL
        LD      HL,LT_CRC
        CALL    CRC_UPD
        POP     HL
        PUSH    AF
        PUSH    IX
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      IX,LT_FD
        CALL    F_PUTB
        POP     HL
        POP     DE
        POP     BC
        POP     IX
        JR      C,.FULL
        POP     AF
        RET
.FULL:  POP     AF
        LD      HL,LT_TXT
        LD      (R_NAME),HL
        JP      DISKERR

; Write HL to the line table, low byte first.
LTW:    LD      A,L
        CALL    LTB
        LD      A,H
        JP      LTB

; Open the line stream and the line table, and write the table's header:
; the part names, from the stream's part records. Leaves LN_TAG holding the
; tag of the first blob-lines record, or $FF.
LN_OPEN:
        LD      A,(O_FLAGS)
        AND     OF_N
        RET     NZ              ; option N: no line table
        LD      A,1
        LD      (LN_ON),A
        LD      IX,LN_FD
        LD      A,(DR_FD+FD_FCB)
        LD      HL,O_NAME
        LD      DE,LN_TY
        CALL    F_INIT
        LD      HL,O_NAME
        LD      DE,LN_TXT
        LD      BC,LN_TY
        CALL    FILETXT
        CALL    F_OPEN
        LD      HL,LN_TXT
        LD      (R_NAME),HL
        LD      HL,225          ; L-MISSING
        JP      C,ERRFILE
        CALL    .HEAD
        ; first pass: count the parts
        LD      BC,0
.COUNT: CALL    LNB
        CP      $FF
        JR      Z,.COUNTED
        CP      1
        JR      Z,.CPART
        CP      2
        JP      NZ,.BAD
        PUSH    BC
        CALL    LN_SKIP         ; a blob-lines record
        POP     BC
        JR      .COUNT
.CPART: INC     BC
        CALL    LNB             ; the part's number
        CALL    LNB             ; its name's length
        LD      D,A
.CSKIP: LD      A,D
        OR      A
        JR      Z,.COUNT
        CALL    LNB
        DEC     D
        JR      .CSKIP
.COUNTED:
        PUSH    BC
        ; the line table, NAME.$LT on the output drive
        LD      IX,LT_FD
        CALL    OUTNAME
        LD      DE,LT_TY
        CALL    F_INIT
        CALL    OUTNAME
        LD      DE,LT_TXT
        LD      BC,LT_TY
        CALL    FILETXT
        LD      HL,LT_TXT
        LD      (R_NAME),HL
        XOR     A
        CALL    F_MAKE
        JP      C,DISKERR
        LD      A,1
        LD      (LT_MADE),A
        LD      HL,$FFFF
        LD      (LT_CRC),HL
        LD      HL,0
        LD      (LN_N),HL
        LD      HL,.MAGIC
        LD      B,4
.MAG:   LD      A,(HL)
        CALL    LTB
        INC     HL
        DJNZ    .MAG
        LD      A,1             ; version 1.0
        CALL    LTB
        XOR     A
        CALL    LTB
        POP     BC
        LD      A,C             ; the part count
        CALL    LTB
        XOR     A               ; no output name, no library name
        CALL    LTB
        CALL    LTB
        ; second pass: from the start again, copying the part names
        CALL    .HEAD
.NAMES: CALL    LNB
        CP      1
        JR      NZ,.FIRST
        CALL    LNB             ; the part's number
        CALL    LNB
        LD      D,A             ; the name's length
        CALL    LTB
.NAME:  LD      A,D
        OR      A
        JR      Z,.NAMES
        CALL    LNB
        CALL    LTB
        DEC     D
        JR      .NAME
.FIRST: LD      (LN_TAG),A
        RET
; Seek to the stream's start and check its header and stamp.
.HEAD:  LD      IX,LN_FD
        XOR     A
        LD      HL,0
        CALL    F_SEEK
        JP      C,R_SHORT
        LD      HL,$FFFF
        LD      (LN_CRC),HL
        LD      HL,.SMAGIC
        LD      B,4
.SMAG:  CALL    LNB
        CP      (HL)
        JR      NZ,.BAD
        INC     HL
        DJNZ    .SMAG
        CALL    LNB
        CP      1
        JR      NZ,.BAD
        CALL    LNB
        OR      A
        JR      NZ,.BAD
        CALL    LNW
        LD      DE,(PRGH+6)
        OR      A
        SBC     HL,DE
        RET     Z
        LD      HL,202          ; L-STAMP
        JP      ERRPLAIN
.BAD:   LD      HL,LN_TXT
        LD      (R_NAME),HL
        LD      HL,200          ; L-FORMAT
        JP      ERRFILE
.MAGIC: DB      "BSIT"
.SMAGIC: DB     "BSIL"

; Skip the rest of a blob-lines record (after its tag).
LN_SKIP:
        CALL    LNW             ; the ordinal
        CALL    LNW             ; the entry count
.NEXT:  LD      A,H
        OR      L
        RET     Z
        PUSH    HL
        CALL    LN_ENTRY
        POP     HL
        DEC     HL
        JR      .NEXT

; Read one entry of a blob-lines record into LN_OFF and LN_PART, returning
; HL = its source offset.
LN_ENTRY:
        CALL    LNB             ; control
        LD      B,A
        AND     $7F
        CP      127
        JR      NZ,.DELTA
        CALL    LNW             ; an absolute offset
        JR      .OFF
.DELTA: LD      L,A
        LD      H,0
        LD      DE,(LN_OFF)
        ADD     HL,DE
.OFF:   LD      (LN_OFF),HL
        BIT     7,B
        JR      Z,.SRC
        CALL    LNB
        LD      (LN_PART),A
.SRC:   JP      LNW

; Write the line-table entries for the blob being emitted, at address DE:
; one per statement for a program code blob whose record begins at offset 0,
; else a start entry ($FF, the ordinal) and then any statements. Called in
; every TEXT pass for each program code blob, emitted or not, so the line
; stream stays in step with the directory; A = 1 when the blob is emitted.
LN_BLOB:
        LD      (LN_EMIT),A
        LD      (LN_ADDR),DE
        LD      A,(LN_ON)
        OR      A
        RET     Z
        LD      A,(WK_OWN)      ; a program code blob has a record
        OR      A
        JR      Z,.START
        LD      A,(WK_KIND)
        CP      K_CODE
        JR      NZ,.START
        CALL    LN_REC      ; HL = its entry count
        LD      (LN_LEFT),HL
        LD      HL,0
        LD      (LN_OFF),HL
        LD      A,(LN_EMIT)
        OR      A
        JR      Z,.SKIPALL
        LD      HL,(LN_LEFT)
        LD      A,H
        OR      L
        JR      Z,.ONLY
        CALL    LN_ENTRY        ; the first entry: at offset 0?
        PUSH    HL
        LD      HL,(LN_OFF)
        LD      A,H
        OR      L
        JR      Z,.ZERO1
        CALL    .STARTENT
.ZERO1:
        POP     HL
        CALL    .ENTRY
.MORE:  LD      HL,(LN_LEFT)
        DEC     HL
        LD      (LN_LEFT),HL
        LD      A,H
        OR      L
        JR      Z,.DONE
        CALL    LN_ENTRY
        CALL    .ENTRY
        JR      .MORE
.DONE:  JP      LN_ADV
.SKIPALL:
        LD      HL,(LN_LEFT)
.SKIP:  LD      A,H
        OR      L
        JP      Z,LN_ADV
        PUSH    HL
        CALL    LN_ENTRY
        POP     HL
        DEC     HL
        JR      .SKIP
.ONLY:
        CALL    .STARTENT
        JP      LN_ADV
.START: LD      A,(LN_EMIT)     ; any other emitted blob: a start entry
        OR      A
        RET     Z
.STARTENT:
        LD      HL,(LN_ADDR)
        CALL    LTW
        LD      A,$FF
        CALL    LTB
        LD      HL,(D_PREV)     ; the blob's ordinal
        CALL    LTW
        JR      .COUNT
; An entry: address = the blob's + LN_OFF, part, source HL.
.ENTRY: PUSH    HL
        LD      HL,(LN_ADDR)
        LD      DE,(LN_OFF)
        ADD     HL,DE
        CALL    LTW
        LD      A,(LN_PART)
        CALL    LTB
        POP     HL
        CALL    LTW
.COUNT: LD      HL,(LN_N)
        INC     HL
        LD      (LN_N),HL
        RET

LN_EMIT: DB     0
LN_ADDR: DW     0
LN_LEFT: DW     0

; The next blob-lines record must be the current blob's: HL = its count.
LN_REC:
        LD      A,(LN_TAG)
        CP      2
        JR      NZ,.BAD
        CALL    LNW
        LD      DE,(D_PREV)
        OR      A
        SBC     HL,DE
        JR      NZ,.BAD
        JP      LNW
.BAD:   JP      LN_OOS

; The line stream is out of step with the directory, or damaged.
LN_OOS: LD      HL,LN_TXT
        LD      (R_NAME),HL
        LD      HL,214          ; L-TRUNCATED
        JP      ERRFILE

; Read the next record's tag into LN_TAG, skipping part records.
LN_ADV:
        CALL    LNB
        CP      1
        JR      NZ,.SET
        CALL    LNB
        CALL    LNB
        LD      D,A
.NAME:  LD      A,D
        OR      A
        JR      Z,LN_ADV
        CALL    LNB
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
        JP      NZ,LN_OOS
        LD      HL,(LN_CRC)     ; the stored CRC, read without adding it
        PUSH    HL
        LD      IX,LN_FD
        CALL    R_RAW
        LD      E,A
        CALL    R_RAW
        LD      D,A
        POP     HL
        OR      A
        SBC     HL,DE
        JP      NZ,LN_OOS
        LD      B,5
.MARK:  LD      A,$FF
        CALL    LTB
        DJNZ    .MARK
        LD      HL,(LN_N)
        CALL    LTW
        LD      HL,(IMG_CRC)
        CALL    LTW
        LD      HL,(LT_CRC)
        CALL    LTW
        LD      IX,LT_FD
        CALL    F_CLOSE
        RET     NC
        LD      HL,LT_TXT
        LD      (R_NAME),HL
        JP      DISKERR
