; Phase E (linker §8): the map (option M) and the symbol file (option Y),
; written after publication. A report that can't be written is deleted and
; reported; the published program stands.
;
; Names come from the program's name stream, NAME.$NM, and the library's
; name section, each read forward in step with its directory: both hold one
; record per named blob, in directory order (object format §9).

; The reports' FDs share memory with Phase D's, which are finished with by
; publication: the library's byte section, the byte stream, the line stream
; and the line table (publication leaves LT_MADE clear).
MAP_FD  EQU     SRC_LIB
MAP_TYPE: DB      "MAP"
SY_FD  EQU     SRC_PROG
SY_TYPE: DB      "SYM"
NM_FD   EQU     LN_FD
NM_TYPE:  DB      "$NM"
NM_LIB  EQU     LT_FD           ; the library again, for its name section
REP_FD: DW      0               ; the report being written
MAP_ON: DB      0
SY_ON: DB      0
SY_COUNT: DW     0
MAP_PREV: DW     0              ; the end of the last live blob listed
NM_HAVE: DS     2               ; per owner: 1 while names remain
NM_ORD: DS     4                ; per owner: the pending record's ordinal
NM_PEND EQU     OUT_FD          ; per owner: its name, zero-terminated (64)
NM_BUF EQU     OUT_FD+64        ; the current blob's name, or empty (33)
REP_BUF  EQU     OUT_FD+97      ; a number's digits (10); all three in
                                ; Phase D's output FD, free after publication
KIND_TAB:  DB      "code   rodata data   bss    startup"

; ---- writing text ------------------------------------------------------------

; Write A to the report being written.
REP_BYTE:    PUSH    IX
        LD      IX,(REP_FD)
        CALL    FIL_PUTB
        POP     IX
        RET     NC
        JP      REP_FAIL

; Write the zero-terminated string at HL. Preserves BC and DE.
REP_STR:    LD      A,(HL)
        OR      A
        RET     Z
        CALL    REP_BYTE
        INC     HL
        JR      REP_STR

; Write the inline zero-terminated string after the CALL.
REP_LIT:    EX      (SP),HL
        CALL    REP_STR
        INC     HL
        EX      (SP),HL
        RET

; Start a line of the summary: CR LF, then the inline zero-terminated label
; after the CALL, padded with spaces to 19 columns.
REP_LINE:    CALL    REP_CRLF
        EX      (SP),HL
        LD      B,19
.CH:    LD      A,(HL)
        INC     HL
        OR      A
        JR      Z,.PAD
        CALL    REP_BYTE
        DEC     B
        JR      .CH
.PAD:   LD      A,' '
        CALL    REP_BYTE
        DJNZ    .PAD
        EX      (SP),HL
        RET

; Two spaces, between the columns of a blob's row.
REP_GAP:    CALL    REP_LIT
        DB      "  ",0
        RET

REP_CRLF: LD      A,13
        CALL    REP_BYTE
        LD      A,10
        JR      REP_BYTE

; Write "$" and HL in four hex digits.
REP_HEX: LD      A,'$'
        CALL    REP_BYTE
; Write HL in four hex digits.
REP_WORD:   LD      A,H
        CALL    .HEX2
        LD      A,L
.HEX2:    PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    .HEX1
        POP     AF
.HEX1:    CALL    LK_DIGIT
        JR      REP_BYTE

; Write the unsigned value HL in decimal, unpadded.
REP_NUM:   LD      B,0
; Write the unsigned value HL in decimal, right-aligned in B columns.
REP_PAD:  XOR     A
        JR      REP_DEC
; Write A:HL, below, unpadded.
REP_SIGN:   LD      B,0
; Write the 24-bit two's-complement value A:HL in decimal, right-aligned in
; B columns (0: no padding). Preserves IX.
REP_DEC:  PUSH    IX
        CALL    .DIGITS
        POP     IX
        RET
.DIGITS: PUSH    BC
        LD      DE,REP_BUF
        BIT     7,A
        JR      Z,.POS
        LD      C,A             ; negate A:HL
        LD      A,L
        CPL
        LD      L,A
        LD      A,H
        CPL
        LD      H,A
        LD      A,C
        CPL
        LD      BC,1
        ADD     HL,BC
        ADC     A,0
        PUSH    AF
        LD      A,'-'
        LD      (DE),A
        INC     DE
        POP     AF
.POS:   LD      C,A             ; C:HL = the magnitude
        LD      IX,.POWERS
        LD      B,0             ; a digit has been written
.POW:   LD      A,(IX+0)
        OR      (IX+1)
        OR      (IX+2)
        JR      Z,.LAST
        PUSH    DE
        LD      E,'0'-1
.SUB:   INC     E
        LD      A,L
        SUB     (IX+0)
        LD      L,A
        LD      A,H
        SBC     A,(IX+1)
        LD      H,A
        LD      A,C
        SBC     A,(IX+2)
        LD      C,A
        JR      NC,.SUB
        LD      A,L             ; add the power back
        ADD     A,(IX+0)
        LD      L,A
        LD      A,H
        ADC     A,(IX+1)
        LD      H,A
        LD      A,C
        ADC     A,(IX+2)
        LD      C,A
        LD      A,E
        POP     DE
        CP      '0'
        JR      NZ,.DIGIT
        INC     B
        DEC     B
        JR      Z,.NEXT         ; a leading zero
.DIGIT: LD      (DE),A
        INC     DE
        LD      B,1
.NEXT:  INC     IX
        INC     IX
        INC     IX
        JR      .POW
.LAST:  LD      A,L
        ADD     A,'0'
        LD      (DE),A
        INC     DE
        XOR     A
        LD      (DE),A
        POP     BC              ; B = the width: pad on the left
        LD      HL,REP_BUF
        PUSH    HL
        LD      C,0             ; the length
.LEN:   LD      A,(HL)
        OR      A
        JR      Z,.PAD
        INC     C
        INC     HL
        JR      .LEN
.PAD:   LD      A,C
        CP      B
        JR      NC,.TEXT
        LD      A,' '
        CALL    REP_BYTE
        INC     C
        JR      .PAD
.TEXT:  POP     HL
        JP      REP_STR
.POWERS:
        DB      $A0,$86,$01     ; 100000
        DB      $10,$27,$00     ; 10000
        DB      $E8,$03,$00     ; 1000
        DB      $64,$00,$00     ; 100
        DB      $0A,$00,$00     ; 10
        DB      0,0,0


; Write the kind name of kind A, padded to 7 characters.
REP_KIND: LD      L,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        SUB     L               ; A * 7
        LD      E,A
        LD      D,0
        LD      HL,KIND_TAB
        ADD     HL,DE
        LD      B,7
.CH:    LD      A,(HL)
        CALL    REP_BYTE
        INC     HL
        DJNZ    .CH
        RET

; A report could not be written: delete it, say so, and stop.
REP_FAIL:
        LD      IX,(REP_FD)
        CALL    FIL_DEL
        LD      HL,222          ; L-IO
        LD      DE,REP_TEXT
        LD      (DG_ARG1),DE
        CALL    DG_ERROR
        CALL    PUB_TIDY
        LD      DE,RC_DISK
        JP      CPM_EXIT
REP_TEXT: DS     13

; ---- names -------------------------------------------------------------------

; Point the name reader of owner A (0 library, 1 program) at its first
; record, if it has names at all.
NM_RESET:
        LD      (NM_OWN),A
        CALL    NM_FLAG         ; HL = its have flag
        LD      (HL),0
        LD      A,(NM_OWN)
        OR      A
        JR      NZ,.PROG
        LD      HL,(LIB_HEAD+24) ; the library's name section, or 0
        LD      A,(LIB_HEAD+26)
        LD      B,A
        OR      H
        OR      L
        RET     Z
        LD      A,B
        LD      IX,NM_LIB
        JR      .SEEK
.PROG:  LD      A,(NM_OPEN)
        OR      A
        RET     Z
        LD      IX,NM_FD
        XOR     A
        LD      HL,0
.SEEK:  CALL    FIL_SEEK
        RET     C
        LD      B,8             ; the header: magic, version, stamp
.HEAD:  CALL    FIL_GETB
        RET     C
        DJNZ    .HEAD
        CALL    NM_FLAG
        LD      (HL),1
        JR      NM_READ

NM_OWN: DB      0
NM_OPEN: DB     0               ; 1 when NAME.$NM was found

; HL = the have flag of NM_OWN.
NM_FLAG:
        LD      HL,NM_HAVE
        LD      A,(NM_OWN)
        ADD     A,L
        LD      L,A
        RET     NC
        INC     H
        RET

; IX = the FD of NM_OWN's names.
NM_PICK:  LD      IX,NM_LIB
        LD      A,(NM_OWN)
        OR      A
        RET     Z
        LD      IX,NM_FD
        RET

; Read NM_OWN's next record into its pending slot; at the end (ordinal 0)
; its have flag clears.
NM_READ:
        CALL    NM_PICK
        CALL    FIL_GETW
        JR      C,.END
        LD      A,H
        OR      L
        JR      Z,.END
        PUSH    HL              ; the ordinal into NM_ORD + owner * 2
        LD      A,(NM_OWN)
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,NM_ORD
        ADD     HL,DE
        POP     DE
        LD      (HL),E
        INC     HL
        LD      (HL),D
        CALL    NM_SLOT         ; HL = the name buffer
        CALL    NM_PICK
        CALL    FIL_GETB        ; the length
        JR      C,.END
        LD      B,A
.CH:    LD      A,B
        OR      A
        JR      Z,.DONE
        CALL    FIL_GETB
        JR      C,.END
        LD      (HL),A
        INC     HL
        DEC     B
        JR      .CH
.DONE:  LD      (HL),0
        RET
.END:   CALL    NM_FLAG
        LD      (HL),0
        RET

; HL = NM_OWN's pending name buffer.
NM_SLOT:
        LD      HL,NM_PEND
        LD      A,(NM_OWN)
        OR      A
        RET     Z
        LD      DE,32
        ADD     HL,DE
        RET

; NAMEBUF = the name of the blob just read (RD_PREV) of owner WK_OWN, taken
; from its reader if the pending record is this blob's, else empty.
NM_GET: PUSH    IX              ; a walk's callback keeps IX on its directory
        CALL    .FETCH
        POP     IX
        RET
.FETCH:
        LD      A,(WK_OWN)
        LD      (NM_OWN),A
        XOR     A
        LD      (NM_BUF),A
        CALL    NM_FLAG
        LD      A,(HL)
        OR      A
        RET     Z
        LD      A,(NM_OWN)
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,NM_ORD
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      HL,(RD_PREV)
        OR      A
        SBC     HL,DE
        RET     NZ
        CALL    NM_SLOT
        LD      DE,NM_BUF
.COPY:  LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        OR      A
        JR      NZ,.COPY
        JP      NM_READ

; ---- Phase E -----------------------------------------------------------------

PE_RUN: LD      A,(OP_FLAGS)
        AND     OF_M
        LD      (MAP_ON),A
        LD      A,(OP_FLAGS)
        AND     OF_Y
        LD      (SY_ON),A
        LD      A,(MAP_ON)
        LD      B,A
        LD      A,(SY_ON)
        OR      B
        RET     Z
        LD      (WK_NAMES),A    ; walks reset the name readers
        ; the names: NAME.$NM if it exists, and the library's section
        LD      IX,NM_FD
        LD      A,(DIR_FD+FD_FCB)
        LD      HL,CMD_NAME
        LD      DE,NM_TYPE
        CALL    FIL_INIT
        CALL    FIL_OPEN
        LD      A,0
        JR      C,.NONAMES
        INC     A
.NONAMES:  LD      (NM_OPEN),A
        LD      IX,NM_LIB
        LD      A,(LIB_FD+FD_FCB)
        LD      HL,LIB_FILE
        LD      DE,LIB_TYPE
        CALL    FIL_INIT
        CALL    FIL_OPEN
        ; the reports
        LD      A,(MAP_ON)
        OR      A
        JR      Z,.NOMAP
        LD      IX,MAP_FD
        LD      DE,MAP_TYPE
        CALL    .CREATE
.NOMAP: LD      A,(SY_ON)
        OR      A
        JR      Z,.NOSYM
        LD      IX,SY_FD
        LD      DE,SY_TYPE
        CALL    .CREATE
.NOSYM: LD      A,(MAP_ON)
        OR      A
        CALL    NZ,.SUMMARY
        ; the live blobs, in address order
        LD      A,(MAP_ON)
        OR      A
        JR      Z,.LISTING
        LD      HL,MAP_FD
        LD      (REP_FD),HL
        CALL    REP_LIT
        DB      "LIVE BLOBS",13,10
        DB      "Address  Size  Kind     Pad  Ordinal  Name",13,10,0
.LISTING: LD      HL,(PF_BASE)
        LD      (MAP_PREV),HL
        LD      HL,0
        LD      (SY_COUNT),HL
        LD      A,S_START
        CALL    .LIVE
        LD      A,S_TEXT
        CALL    .LIVE
        LD      A,S_DATA
        CALL    .LIVE
        LD      HL,(IMG_END)    ; BSS's padding counts from the image's
        LD      (MAP_PREV),HL   ; end, past COPY
        LD      A,S_BSS
        CALL    .LIVE
        LD      A,(MAP_ON)
        OR      A
        CALL    NZ,MAP_DEAD
        LD      A,(SY_ON)
        OR      A
        JR      Z,.CLOSE
        LD      HL,SY_FD
        LD      (REP_FD),HL
        CALL    SY_ALIAS
        LD      HL,(SY_COUNT)   ; no rows: one empty line
        LD      A,H
        OR      L
        CALL    Z,REP_CRLF
        LD      A,$1A
        CALL    REP_BYTE
        LD      IX,SY_FD
        CALL    FIL_SHUT
        JP      C,REP_FAIL
.CLOSE: LD      A,(MAP_ON)
        OR      A
        RET     Z
        LD      HL,MAP_FD
        LD      (REP_FD),HL
        LD      IX,MAP_FD
        CALL    FIL_SHUT
        JP      C,REP_FAIL
        RET
; The live passes of section A.
.LIVE:  LD      HL,.LIVEBLOB
        JP      WK_PASS

; Create report IX of type DE, NAME.TYP on the output drive.
.CREATE:
        PUSH    DE
        CALL    OUT_PICK
        POP     DE
        PUSH    DE
        CALL    FIL_INIT
        CALL    OUT_PICK
        POP     BC
        LD      DE,REP_TEXT
        CALL    FIL_TEXT
        LD      (REP_FD),IX
        LD      A,$1A           ; a text file's last record: Control-Z
        CALL    FIL_MAKE
        JP      C,REP_FAIL
        RET

; The map's summary (linker §8.1).
.SUMMARY:
        LD      HL,MAP_FD
        LD      (REP_FD),HL
        CALL    REP_LIT
        DB      "BASIE LINK MAP: ",0
        LD      HL,CMD_NAME
        LD      B,8
.NAME:  LD      A,(HL)
        CP      ' '
        JR      Z,.NAMED
        CALL    REP_BYTE
        INC     HL
        DJNZ    .NAME
.NAMED: CALL    REP_CRLF
        CALL    REP_LINE
        DB      "Library",0
        LD      HL,LIB_TEXT
        CALL    REP_STR
        CALL    REP_LINE
        DB      "Runtime, profile",0
        LD      HL,(LIB_HEAD+6)
        CALL    REP_NUM
        CALL    REP_LIT
        DB      ", ",0
        LD      HL,(LIB_HEAD+10)
        CALL    REP_NUM
        CALL    REP_LINE
        DB      "Output",0
        LD      A,'.'
        CALL    REP_BYTE
        LD      HL,OUT_TYPE
        LD      B,3
.TYPE:  LD      A,(HL)
        CALL    REP_BYTE
        INC     HL
        DJNZ    .TYPE
        CALL    REP_LINE
        DB      "Image",0
        LD      HL,(PF_BASE)
        CALL    REP_HEX
        CALL    REP_LIT
        DB      " to ",0
        LD      HL,(IMG_END)
        CALL    REP_HEX
        CALL    REP_LIT
        DB      ", ",0
        LD      HL,(IMG_END)
        LD      DE,(PF_BASE)
        OR      A
        SBC     HL,DE
        CALL    REP_NUM
        CALL    REP_LIT
        DB      " bytes",0
        CALL    REP_LINE
        DB      "BSS",0
        LD      HL,(PS_TAB+8)
        CALL    REP_HEX
        CALL    REP_LIT
        DB      ", ",0
        LD      HL,(PS_TAB+10)
        CALL    REP_NUM
        CALL    REP_LIT
        DB      " bytes",0
        CALL    REP_LINE
        DB      "Stack reserve",0
        LD      HL,(PC_STACK)
        CALL    REP_NUM
        CALL    REP_LIT
        DB      " bytes; largest frame ",0
        LD      HL,(PA_LIMIT+2)
        CALL    REP_NUM
        LD      A,(PA_LIMIT+4)
        AND     1
        JR      Z,.NOREC
        CALL    REP_LIT
        DB      "; recursion present",0
.NOREC: CALL    REP_LINE
        DB      "Required top",0
        CALL    .REQUIRED       ; A:HL
        CALL    REP_HEX         ; its low 16 bits, as the reference prints
        CALL    REP_LINE
        DB      "Image limit",0
        LD      HL,(PF_LIMIT)
        CALL    REP_HEX
        CALL    REP_LIT
        DB      ", margin ",0
        LD      HL,(PF_LIMIT)
        LD      DE,(IMG_END)
        XOR     A
        SBC     HL,DE
        SBC     A,0
        CALL    REP_SIGN
        CALL    REP_LINE
        DB      "Nominal top",0
        LD      HL,(PF_TOP)
        CALL    REP_HEX
        CALL    REP_LIT
        DB      ", margin ",0
        LD      HL,(PF_TOP)     ; nominal top - required, 24-bit
        CALL    .MINUSREQ
        CALL    REP_SIGN
        CALL    REP_LINE
        DB      "Under a debugger",0
        CALL    REP_LIT
        DB      "margin ",0
        LD      HL,(PF_TOP)
        LD      DE,(PF_BLOCK+18) ; the debugger margin
        OR      A
        SBC     HL,DE
        CALL    .MINUSREQ
        CALL    REP_SIGN
        CALL    REP_CRLF
        JP      REP_CRLF
; A:HL = HL - REQUIRED, as a 24-bit signed value.
.MINUSREQ:
        PUSH    HL
        CALL    .REQUIRED
        LD      C,A
        EX      DE,HL           ; C:DE = required
        POP     HL
        XOR     A
        SBC     HL,DE
        SBC     A,C
        RET

; A:HL = REQUIRED: FREE plus the stack reserve, which may reach $10000.
.REQUIRED:
        LD      HL,(PC_FREE)
        LD      DE,(PC_STACK)
        XOR     A
        ADD     HL,DE
        ADC     A,0
        RET

; A blob of a live pass: keep the names in step, and list it if selected.
.LIVEBLOB:
        CALL    NM_GET
        CALL    WK_MATCH
        JP      NZ,REF_SKIP
        LD      HL,(WK_ENTRY)
        LD      DE,E_ADDR
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = the address
        LD      (.BLOBADDR),DE
        LD      A,(MAP_ON)
        OR      A
        JR      Z,.SYM
        LD      HL,MAP_FD
        LD      (REP_FD),HL
        LD      HL,(.BLOBADDR)
        CALL    REP_HEX
        CALL    REP_GAP
        LD      HL,(RD_SIZE)
        LD      B,5
        CALL    REP_PAD
        CALL    REP_GAP
        LD      A,(WK_KIND)
        CALL    REP_KIND
        CALL    REP_GAP
        LD      HL,(.BLOBADDR)  ; the padding paid
        LD      DE,(MAP_PREV)
        OR      A
        SBC     HL,DE
        LD      B,3
        CALL    REP_PAD
        CALL    REP_GAP
        LD      HL,(RD_PREV)
        CALL    REP_HEX
        CALL    REP_GAP
        CALL    REP_GAP
        LD      HL,NM_BUF
        CALL    REP_STR
        CALL    REP_CRLF
.SYM:   LD      HL,(.BLOBADDR)
        LD      DE,(RD_SIZE)
        ADD     HL,DE
        LD      (MAP_PREV),HL
        LD      A,(SY_ON)
        OR      A
        JP      Z,REF_SKIP
        LD      A,(NM_BUF)
        OR      A
        JP      Z,REF_SKIP
        LD      HL,SY_FD
        LD      (REP_FD),HL
        LD      HL,(.BLOBADDR)
        CALL    SY_ROW
        JP      REF_SKIP

.BLOBADDR: DW     0

; A symbol row: address HL, the name in NAMEBUF to 16 characters.
SY_ROW: CALL    REP_WORD
        LD      A,' '
        CALL    REP_BYTE
        LD      HL,NM_BUF
        LD      B,16
.CH:    LD      A,(HL)
        OR      A
        JR      Z,.END
        CALL    REP_BYTE
        INC     HL
        DJNZ    .CH
.END:   CALL    REP_CRLF
        LD      HL,(SY_COUNT)
        INC     HL
        LD      (SY_COUNT),HL
        RET

; The symbol file's alias rows: each live named alias, in address order.
; Aliases are rare, so each is found by a scan of the table, and its name by
; a scan of its owner's names.
SY_ALIAS:
        LD      HL,0
        LD      (.LAST),HL
        XOR     A
        LD      (.ANY),A
.ROUND: LD      HL,$FFFF
        LD      (.BEST),HL
        XOR     A
        LD      (.FOUND),A
        LD      HL,0            ; scan for the lowest address above the last
.SCAN:  PUSH    HL
        CALL    TAB_AT
        JR      C,.SCANNED
        LD      A,(HL)
        AND     EF_ALIAS+EF_DEF
        CP      EF_ALIAS+EF_DEF
        JR      NZ,.NEXT
        PUSH    HL
        CALL    .ALIVE          ; carry unless its base is live
        POP     HL
        JR      C,.NEXT
        INC     HL
        INC     HL
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = its address
        LD      A,(.ANY)
        OR      A
        JR      Z,.FIRST
        LD      HL,(.LAST)      ; above the last one written
        OR      A
        SBC     HL,DE
        JR      NC,.NEXT
.FIRST: LD      HL,(.BEST)
        OR      A
        SBC     HL,DE
        JR      C,.NEXT
        LD      (.BEST),DE
        POP     HL
        PUSH    HL
        LD      (.POS),HL
        LD      A,1
        LD      (.FOUND),A
.NEXT:  POP     HL
        INC     HL
        JR      .SCAN
.SCANNED:
        POP     HL
        LD      A,(.FOUND)
        OR      A
        RET     Z
        LD      HL,(.BEST)
        LD      (.LAST),HL
        LD      A,1
        LD      (.ANY),A
        LD      HL,(.POS)       ; its name, by a scan of its owner's names
        CALL    TAB_ORD
        LD      (RD_PREV),HL
        LD      A,H
        CP      $04
        LD      A,0
        JR      C,.OWN
        INC     A
.OWN:   LD      (WK_OWN),A
        CALL    NM_RESET
.FIND:  CALL    NM_GET
        LD      A,(NM_BUF)
        OR      A
        JR      NZ,.ROW
        CALL    NM_FLAG         ; not this record: the next, until the end
        LD      A,(HL)
        OR      A
        JP      Z,.ROUND
        CALL    NM_READ
        JR      .FIND
.ROW:   LD      HL,(.BEST)
        CALL    SY_ROW
        JP      .ROUND

.LAST: DW     0
.BEST: DW     0
.POS: DW      0
.FOUND: DB    0
.ANY: DB      0

; Carry unless the alias entry at HL has a live base.
.ALIVE:  LD      DE,E_ADDR
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        CALL    TAB_FIND
        RET     C
        BIT     5,(HL)
        SCF
        RET     Z
        OR      A
        RET

; The removed blobs, in directory order, then the totals.
MAP_DEAD:
        LD      HL,MAP_FD
        LD      (REP_FD),HL
        CALL    REP_LIT
        DB      13,10,"REMOVED BLOBS",13,10
        DB      "Ordinal  Size  Kind     Name",13,10,0
        LD      HL,0
        LD      (LIB_KEPT),HL
        LD      (LIB_GONE),HL
        LD      (PRG_KEPT),HL
        LD      (PRG_GONE),HL
        LD      HL,MAP_ADD
        LD      (WK_EACH),HL
        CALL    WK_BOTH
        CALL    REP_LIT
        DB      13,10,"TOTALS",13,10
        DB      "Program   kept ",0
        LD      HL,(PRG_KEPT)
        CALL    REP_NUM
        CALL    REP_LIT
        DB      ", removed ",0
        LD      HL,(PRG_GONE)
        CALL    REP_NUM
        CALL    REP_LIT
        DB      13,10,"Library   kept ",0
        LD      HL,(LIB_KEPT)
        CALL    REP_NUM
        CALL    REP_LIT
        DB      ", removed ",0
        LD      HL,(LIB_GONE)
        CALL    REP_NUM
        JP      REP_CRLF

LIB_KEPT: DW      0
LIB_GONE: DW      0
PRG_KEPT: DW      0
PRG_GONE: DW      0

; A blob of the removed pass: count it, and list it when it is not live.
MAP_ADD:
        CALL    NM_GET
        LD      HL,(WK_ENTRY)
        BIT     5,(HL)
        LD      HL,LIB_KEPT     ; the right total: owner, kept or removed
        JR      NZ,.KEPT
        LD      HL,LIB_GONE
.KEPT:  LD      A,(WK_OWN)
        OR      A
        JR      Z,.ADD
        INC     HL              ; TOT_P* follow TOT_L* by four bytes
        INC     HL
        INC     HL
        INC     HL
.ADD:   LD      E,(HL)
        INC     HL
        LD      D,(HL)
        PUSH    HL
        LD      HL,(RD_SIZE)
        ADD     HL,DE
        EX      DE,HL
        POP     HL
        LD      (HL),D
        DEC     HL
        LD      (HL),E
        LD      HL,(WK_ENTRY)
        BIT     5,(HL)
        JP      NZ,REF_SKIP
        LD      HL,(RD_PREV)
        CALL    REP_HEX
        CALL    REP_GAP
        LD      HL,(RD_SIZE)
        LD      B,5
        CALL    REP_PAD
        CALL    REP_GAP
        LD      A,(WK_KIND)
        CALL    REP_KIND
        CALL    REP_GAP
        LD      HL,NM_BUF
        CALL    REP_STR
        CALL    REP_CRLF
        JP      REF_SKIP
