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
MAP_FD  EQU     LIBB_FD
MAP_TY: DB      "MAP"
SYM_FD  EQU     BY_FD
SYM_TY: DB      "SYM"
NM_FD   EQU     LN_FD
NM_TY:  DB      "$NM"
LNM_FD  EQU     LT_FD           ; the library again, for its name section
REP_FD: DW      0               ; the report being written
MAP_ON: DB      0
SYM_ON: DB      0
SYMROWS: DW     0
PREVEND: DW     0               ; the end of the last live blob listed
NM_HAVE: DS     2               ; per owner: 1 while names remain
NM_PORD: DS     4               ; per owner: the pending record's ordinal
NM_PNAM EQU     OUT_FD          ; per owner: its name, zero-terminated (64)
NAMEBUF EQU     OUT_FD+64       ; the current blob's name, or empty (33)
NUMBUF  EQU     OUT_FD+97       ; a number's digits (10); all three in
                                ; Phase D's output FD, free after publication
KINDS:  DB      "code   rodata data   bss    startup"

; ---- writing text ------------------------------------------------------------

; Write A to the report being written.
MTB:    PUSH    IX
        LD      IX,(REP_FD)
        CALL    F_PUTB
        POP     IX
        RET     NC
        JP      REPFAIL

; Write the zero-terminated string at HL. Preserves BC and DE.
MTS:    LD      A,(HL)
        OR      A
        RET     Z
        CALL    MTB
        INC     HL
        JR      MTS

; Write the inline zero-terminated string after the CALL.
MTI:    EX      (SP),HL
        CALL    MTS
        INC     HL
        EX      (SP),HL
        RET

; Start a line of the summary: CR LF, then the inline zero-terminated label
; after the CALL, padded with spaces to 19 columns.
MTL:    CALL    MTCRLF
        EX      (SP),HL
        LD      B,19
.CH:    LD      A,(HL)
        INC     HL
        OR      A
        JR      Z,.PAD
        CALL    MTB
        DEC     B
        JR      .CH
.PAD:   LD      A,' '
        CALL    MTB
        DJNZ    .PAD
        EX      (SP),HL
        RET

; Two spaces, between the columns of a blob's row.
MT2:    CALL    MTI
        DB      "  ",0
        RET

MTCRLF: LD      A,13
        CALL    MTB
        LD      A,10
        JR      MTB

; Write "$" and HL in four hex digits.
MTHEX4: LD      A,'$'
        CALL    MTB
; Write HL in four hex digits.
MTH4:   LD      A,H
        CALL    .H2
        LD      A,L
.H2:    PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    .H1
        POP     AF
.H1:    CALL    HEXDIG
        JR      MTB

; Write the unsigned value HL in decimal, unpadded.
MTU0:   LD      B,0
; Write the unsigned value HL in decimal, right-aligned in B columns.
MTU16:  XOR     A
        JR      MTDEC
; Write A:HL, below, unpadded.
MTD0:   LD      B,0
; Write the 24-bit two's-complement value A:HL in decimal, right-aligned in
; B columns (0: no padding). Preserves IX.
MTDEC:  PUSH    IX
        CALL    MTDEC0
        POP     IX
        RET
MTDEC0: PUSH    BC
        LD      DE,NUMBUF
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
        LD      HL,NUMBUF
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
        CALL    MTB
        INC     C
        JR      .PAD
.TEXT:  POP     HL
        JP      MTS
.POWERS:
        DB      $A0,$86,$01     ; 100000
        DB      $10,$27,$00     ; 10000
        DB      $E8,$03,$00     ; 1000
        DB      $64,$00,$00     ; 100
        DB      $0A,$00,$00     ; 10
        DB      0,0,0


; Write the kind name of kind A, padded to 7 characters.
MTKIND: LD      L,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        SUB     L               ; A * 7
        LD      E,A
        LD      D,0
        LD      HL,KINDS
        ADD     HL,DE
        LD      B,7
.CH:    LD      A,(HL)
        CALL    MTB
        INC     HL
        DJNZ    .CH
        RET

; A report could not be written: delete it, say so, and stop.
REPFAIL:
        LD      IX,(REP_FD)
        CALL    F_DEL
        LD      HL,222          ; L-IO
        LD      DE,REP_TXT
        LD      (M_ARG1),DE
        CALL    ERROR
        CALL    CLEANUP
        LD      DE,RC_DISK
        JP      EXITRC
REP_TXT: DS     13

; ---- names -------------------------------------------------------------------

; Point the name reader of owner A (0 library, 1 program) at its first
; record, if it has names at all.
NM_RESET:
        LD      (NM_OWN),A
        CALL    NM_SLOT         ; HL = its have flag
        LD      (HL),0
        LD      A,(NM_OWN)
        OR      A
        JR      NZ,.PROG
        LD      HL,(LIBH+24)    ; the library's name section, or 0
        LD      A,(LIBH+26)
        LD      B,A
        OR      H
        OR      L
        RET     Z
        LD      A,B
        LD      IX,LNM_FD
        JR      .SEEK
.PROG:  LD      A,(NM_OPEN)
        OR      A
        RET     Z
        LD      IX,NM_FD
        XOR     A
        LD      HL,0
.SEEK:  CALL    F_SEEK
        RET     C
        LD      B,8             ; the header: magic, version, stamp
.HEAD:  CALL    F_GETB
        RET     C
        DJNZ    .HEAD
        CALL    NM_SLOT
        LD      (HL),1
        JR      NM_READ

NM_OWN: DB      0
NM_OPEN: DB     0               ; 1 when NAME.$NM was found

; HL = the have flag of NM_OWN.
NM_SLOT:
        LD      HL,NM_HAVE
        LD      A,(NM_OWN)
        ADD     A,L
        LD      L,A
        RET     NC
        INC     H
        RET

; IX = the FD of NM_OWN's names.
NM_IX:  LD      IX,LNM_FD
        LD      A,(NM_OWN)
        OR      A
        RET     Z
        LD      IX,NM_FD
        RET

; Read NM_OWN's next record into its pending slot; at the end (ordinal 0)
; its have flag clears.
NM_READ:
        CALL    NM_IX
        CALL    F_GETW
        JR      C,.END
        LD      A,H
        OR      L
        JR      Z,.END
        PUSH    HL              ; the ordinal into NM_PORD + owner * 2
        LD      A,(NM_OWN)
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,NM_PORD
        ADD     HL,DE
        POP     DE
        LD      (HL),E
        INC     HL
        LD      (HL),D
        CALL    NM_PSLOT        ; HL = the name buffer
        CALL    NM_IX
        CALL    F_GETB          ; the length
        JR      C,.END
        LD      B,A
.CH:    LD      A,B
        OR      A
        JR      Z,.DONE
        CALL    F_GETB
        JR      C,.END
        LD      (HL),A
        INC     HL
        DEC     B
        JR      .CH
.DONE:  LD      (HL),0
        RET
.END:   CALL    NM_SLOT
        LD      (HL),0
        RET

; HL = NM_OWN's pending name buffer.
NM_PSLOT:
        LD      HL,NM_PNAM
        LD      A,(NM_OWN)
        OR      A
        RET     Z
        LD      DE,32
        ADD     HL,DE
        RET

; NAMEBUF = the name of the blob just read (D_PREV) of owner WK_OWN, taken
; from its reader if the pending record is this blob's, else empty.
NM_GET: PUSH    IX              ; a walk's callback keeps IX on its directory
        CALL    NM_GET0
        POP     IX
        RET
NM_GET0:
        LD      A,(WK_OWN)
        LD      (NM_OWN),A
        XOR     A
        LD      (NAMEBUF),A
        CALL    NM_SLOT
        LD      A,(HL)
        OR      A
        RET     Z
        LD      A,(NM_OWN)
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,NM_PORD
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      HL,(D_PREV)
        OR      A
        SBC     HL,DE
        RET     NZ
        CALL    NM_PSLOT
        LD      DE,NAMEBUF
.COPY:  LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        OR      A
        JR      NZ,.COPY
        JP      NM_READ

; ---- Phase E -----------------------------------------------------------------

PHASEE: LD      A,(O_FLAGS)
        AND     OF_M
        LD      (MAP_ON),A
        LD      A,(O_FLAGS)
        AND     OF_Y
        LD      (SYM_ON),A
        LD      A,(MAP_ON)
        LD      B,A
        LD      A,(SYM_ON)
        OR      B
        RET     Z
        LD      (WK_NM),A       ; walks reset the name readers
        ; the names: NAME.$NM if it exists, and the library's section
        LD      IX,NM_FD
        LD      A,(DR_FD+FD_FCB)
        LD      HL,O_NAME
        LD      DE,NM_TY
        CALL    F_INIT
        CALL    F_OPEN
        LD      A,0
        JR      C,.NOMN
        INC     A
.NOMN:  LD      (NM_OPEN),A
        LD      IX,LNM_FD
        LD      A,(LIB_FD+FD_FCB)
        LD      HL,O_LIB
        LD      DE,LIB_TY
        CALL    F_INIT
        CALL    F_OPEN
        ; the reports
        LD      A,(MAP_ON)
        OR      A
        JR      Z,.NOMAP
        LD      IX,MAP_FD
        LD      DE,MAP_TY
        CALL    REPOPEN
.NOMAP: LD      A,(SYM_ON)
        OR      A
        JR      Z,.NOSYM
        LD      IX,SYM_FD
        LD      DE,SYM_TY
        CALL    REPOPEN
.NOSYM: LD      A,(MAP_ON)
        OR      A
        CALL    NZ,SUMMARY
        ; the live blobs, in address order
        LD      A,(MAP_ON)
        OR      A
        JR      Z,.HEAD2
        LD      HL,MAP_FD
        LD      (REP_FD),HL
        CALL    MTI
        DB      "LIVE BLOBS",13,10
        DB      "Address  Size  Kind     Pad  Ordinal  Name",13,10,0
.HEAD2: LD      HL,(PR_BASE)
        LD      (PREVEND),HL
        LD      HL,0
        LD      (SYMROWS),HL
        LD      A,S_START
        CALL    .LIVE
        LD      A,S_TEXT
        CALL    .LIVE
        LD      A,S_DATA
        CALL    .LIVE
        LD      HL,(IMG_END)    ; BSS's padding counts from the image's
        LD      (PREVEND),HL    ; end, past COPY
        LD      A,S_BSS
        CALL    .LIVE
        LD      A,(MAP_ON)
        OR      A
        CALL    NZ,REMOVED
        LD      A,(SYM_ON)
        OR      A
        JR      Z,.CLOSE
        LD      HL,SYM_FD
        LD      (REP_FD),HL
        CALL    SYMALIAS
        LD      HL,(SYMROWS)    ; no rows: one empty line
        LD      A,H
        OR      L
        CALL    Z,MTCRLF
        LD      A,$1A
        CALL    MTB
        LD      IX,SYM_FD
        CALL    F_CLOSE
        JP      C,REPFAIL
.CLOSE: LD      A,(MAP_ON)
        OR      A
        RET     Z
        LD      HL,MAP_FD
        LD      (REP_FD),HL
        LD      IX,MAP_FD
        CALL    F_CLOSE
        JP      C,REPFAIL
        RET
; The live passes of section A.
.LIVE:  LD      HL,MAPLIVE
        JP      SECTION

; Create report IX of type DE, NAME.TYP on the output drive.
REPOPEN:
        PUSH    DE
        CALL    OUTNAME
        POP     DE
        PUSH    DE
        CALL    F_INIT
        CALL    OUTNAME
        POP     BC
        LD      DE,REP_TXT
        CALL    FILETXT
        LD      (REP_FD),IX
        LD      A,$1A           ; a text file's last record: Control-Z
        CALL    F_MAKE
        JP      C,REPFAIL
        RET

; The map's summary (linker §8.1).
SUMMARY:
        LD      HL,MAP_FD
        LD      (REP_FD),HL
        CALL    MTI
        DB      "BASIE LINK MAP: ",0
        LD      HL,O_NAME
        LD      B,8
.NAME:  LD      A,(HL)
        CP      ' '
        JR      Z,.NAMED
        CALL    MTB
        INC     HL
        DJNZ    .NAME
.NAMED: CALL    MTCRLF
        CALL    MTL
        DB      "Library",0
        LD      HL,LIB_TXT
        CALL    MTS
        CALL    MTL
        DB      "Runtime, profile",0
        LD      HL,(LIBH+6)
        CALL    MTU0
        CALL    MTI
        DB      ", ",0
        LD      HL,(LIBH+10)
        CALL    MTU0
        CALL    MTL
        DB      "Output",0
        LD      A,'.'
        CALL    MTB
        LD      HL,O_OTYP
        LD      B,3
.TYPE:  LD      A,(HL)
        CALL    MTB
        INC     HL
        DJNZ    .TYPE
        CALL    MTL
        DB      "Image",0
        LD      HL,(PR_BASE)
        CALL    MTHEX4
        CALL    MTI
        DB      " to ",0
        LD      HL,(IMG_END)
        CALL    MTHEX4
        CALL    MTI
        DB      ", ",0
        LD      HL,(IMG_END)
        LD      DE,(PR_BASE)
        OR      A
        SBC     HL,DE
        CALL    MTU0
        CALL    MTI
        DB      " bytes",0
        CALL    MTL
        DB      "BSS",0
        LD      HL,(PSEUDO+8)
        CALL    MTHEX4
        CALL    MTI
        DB      ", ",0
        LD      HL,(PSEUDO+10)
        CALL    MTU0
        CALL    MTI
        DB      " bytes",0
        CALL    MTL
        DB      "Stack reserve",0
        LD      HL,(RESERVE)
        CALL    MTU0
        CALL    MTI
        DB      " bytes; largest frame ",0
        LD      HL,(LIMITS+2)
        CALL    MTU0
        LD      A,(LIMITS+4)
        AND     1
        JR      Z,.NOREC
        CALL    MTI
        DB      "; recursion present",0
.NOREC: CALL    MTL
        DB      "Required top",0
        CALL    REQUIRED        ; A:HL
        CALL    MTHEX4          ; its low 16 bits, as the reference prints
        CALL    MTL
        DB      "Image limit",0
        LD      HL,(PR_LIMIT)
        CALL    MTHEX4
        CALL    MTI
        DB      ", margin ",0
        LD      HL,(PR_LIMIT)
        LD      DE,(IMG_END)
        XOR     A
        SBC     HL,DE
        SBC     A,0
        CALL    MTD0
        CALL    MTL
        DB      "Nominal top",0
        LD      HL,(PR_TOP)
        CALL    MTHEX4
        CALL    MTI
        DB      ", margin ",0
        LD      HL,(PR_TOP)     ; nominal top - required, 24-bit
        CALL    .MINUSREQ
        CALL    MTD0
        CALL    MTL
        DB      "Under a debugger",0
        CALL    MTI
        DB      "margin ",0
        LD      HL,(PR_TOP)
        LD      DE,(PROF+18)    ; the debugger margin
        OR      A
        SBC     HL,DE
        CALL    .MINUSREQ
        CALL    MTD0
        CALL    MTCRLF
        JP      MTCRLF
; A:HL = HL - REQUIRED, as a 24-bit signed value.
.MINUSREQ:
        PUSH    HL
        CALL    REQUIRED
        LD      C,A
        EX      DE,HL           ; C:DE = required
        POP     HL
        XOR     A
        SBC     HL,DE
        SBC     A,C
        RET

; A:HL = REQUIRED: FREE plus the stack reserve, which may reach $10000.
REQUIRED:
        LD      HL,(FREEADR)
        LD      DE,(RESERVE)
        XOR     A
        ADD     HL,DE
        ADC     A,0
        RET

; A blob of a live pass: keep the names in step, and list it if selected.
MAPLIVE:
        CALL    NM_GET
        CALL    SELECT
        JP      NZ,REFSKIP
        LD      HL,(WK_ENT)
        LD      DE,E_ADDR
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = the address
        LD      (MP_ADDR),DE
        LD      A,(MAP_ON)
        OR      A
        JR      Z,.SYM
        LD      HL,MAP_FD
        LD      (REP_FD),HL
        LD      HL,(MP_ADDR)
        CALL    MTHEX4
        CALL    MT2
        LD      HL,(D_SIZE)
        LD      B,5
        CALL    MTU16
        CALL    MT2
        LD      A,(WK_KIND)
        CALL    MTKIND
        CALL    MT2
        LD      HL,(MP_ADDR)    ; the padding paid
        LD      DE,(PREVEND)
        OR      A
        SBC     HL,DE
        LD      B,3
        CALL    MTU16
        CALL    MT2
        LD      HL,(D_PREV)
        CALL    MTHEX4
        CALL    MT2
        CALL    MT2
        LD      HL,NAMEBUF
        CALL    MTS
        CALL    MTCRLF
.SYM:   LD      HL,(MP_ADDR)
        LD      DE,(D_SIZE)
        ADD     HL,DE
        LD      (PREVEND),HL
        LD      A,(SYM_ON)
        OR      A
        JP      Z,REFSKIP
        LD      A,(NAMEBUF)
        OR      A
        JP      Z,REFSKIP
        LD      HL,SYM_FD
        LD      (REP_FD),HL
        LD      HL,(MP_ADDR)
        CALL    SYMROW
        JP      REFSKIP

MP_ADDR: DW     0

; A symbol row: address HL, the name in NAMEBUF to 16 characters.
SYMROW: CALL    MTH4
        LD      A,' '
        CALL    MTB
        LD      HL,NAMEBUF
        LD      B,16
.CH:    LD      A,(HL)
        OR      A
        JR      Z,.END
        CALL    MTB
        INC     HL
        DJNZ    .CH
.END:   CALL    MTCRLF
        LD      HL,(SYMROWS)
        INC     HL
        LD      (SYMROWS),HL
        RET

; The symbol file's alias rows: each live named alias, in address order.
; Aliases are rare, so each is found by a scan of the table, and its name by
; a scan of its owner's names.
SYMALIAS:
        LD      HL,0
        LD      (SA_LAST),HL
        XOR     A
        LD      (SA_ANY),A
.ROUND: LD      HL,$FFFF
        LD      (SA_BEST),HL
        XOR     A
        LD      (SA_FOUND),A
        LD      HL,0            ; scan for the lowest address above the last
.SCAN:  PUSH    HL
        CALL    ENTRYAT
        JR      C,.SCANNED
        LD      A,(HL)
        AND     F_ALIAS+F_DEF
        CP      F_ALIAS+F_DEF
        JR      NZ,.NEXT
        PUSH    HL
        CALL    ALIVE           ; carry unless its base is live
        POP     HL
        JR      C,.NEXT
        INC     HL
        INC     HL
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = its address
        LD      A,(SA_ANY)
        OR      A
        JR      Z,.FIRST
        LD      HL,(SA_LAST)    ; above the last one written
        OR      A
        SBC     HL,DE
        JR      NC,.NEXT
.FIRST: LD      HL,(SA_BEST)
        OR      A
        SBC     HL,DE
        JR      C,.NEXT
        LD      (SA_BEST),DE
        POP     HL
        PUSH    HL
        LD      (SA_POS),HL
        LD      A,1
        LD      (SA_FOUND),A
.NEXT:  POP     HL
        INC     HL
        JR      .SCAN
.SCANNED:
        POP     HL
        LD      A,(SA_FOUND)
        OR      A
        RET     Z
        LD      HL,(SA_BEST)
        LD      (SA_LAST),HL
        LD      A,1
        LD      (SA_ANY),A
        LD      HL,(SA_POS)     ; its name, by a scan of its owner's names
        CALL    POS2ORD
        LD      (D_PREV),HL
        LD      A,H
        CP      $04
        LD      A,0
        JR      C,.OWN
        INC     A
.OWN:   LD      (WK_OWN),A
        CALL    NM_RESET
.FIND:  CALL    NM_GET
        LD      A,(NAMEBUF)
        OR      A
        JR      NZ,.ROW
        CALL    NM_SLOT         ; not this record: the next, until the end
        LD      A,(HL)
        OR      A
        JP      Z,.ROUND
        CALL    NM_READ
        JR      .FIND
.ROW:   LD      HL,(SA_BEST)
        CALL    SYMROW
        JP      .ROUND

SA_LAST: DW     0
SA_BEST: DW     0
SA_POS: DW      0
SA_FOUND: DB    0
SA_ANY: DB      0

; Carry unless the alias entry at HL has a live base.
ALIVE:  LD      DE,E_ADDR
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        CALL    ENT_MAKE
        RET     C
        BIT     5,(HL)
        SCF
        RET     Z
        OR      A
        RET

; The removed blobs, in directory order, then the totals.
REMOVED:
        LD      HL,MAP_FD
        LD      (REP_FD),HL
        CALL    MTI
        DB      13,10,"REMOVED BLOBS",13,10
        DB      "Ordinal  Size  Kind     Name",13,10,0
        LD      HL,0
        LD      (TOT_LK),HL
        LD      (TOT_LR),HL
        LD      (TOT_PK),HL
        LD      (TOT_PR),HL
        LD      HL,MAPDEAD
        LD      (WK_CB),HL
        CALL    WALK2
        CALL    MTI
        DB      13,10,"TOTALS",13,10
        DB      "Program   kept ",0
        LD      HL,(TOT_PK)
        CALL    MTU0
        CALL    MTI
        DB      ", removed ",0
        LD      HL,(TOT_PR)
        CALL    MTU0
        CALL    MTI
        DB      13,10,"Library   kept ",0
        LD      HL,(TOT_LK)
        CALL    MTU0
        CALL    MTI
        DB      ", removed ",0
        LD      HL,(TOT_LR)
        CALL    MTU0
        JP      MTCRLF

TOT_LK: DW      0
TOT_LR: DW      0
TOT_PK: DW      0
TOT_PR: DW      0

; A blob of the removed pass: count it, and list it when it is not live.
MAPDEAD:
        CALL    NM_GET
        LD      HL,(WK_ENT)
        BIT     5,(HL)
        LD      HL,TOT_LK       ; the right total: owner, kept or removed
        JR      NZ,.KEPT
        LD      HL,TOT_LR
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
        LD      HL,(D_SIZE)
        ADD     HL,DE
        EX      DE,HL
        POP     HL
        LD      (HL),D
        DEC     HL
        LD      (HL),E
        LD      HL,(WK_ENT)
        BIT     5,(HL)
        JP      NZ,REFSKIP
        LD      HL,(D_PREV)
        CALL    MTHEX4
        CALL    MT2
        LD      HL,(D_SIZE)
        LD      B,5
        CALL    MTU16
        CALL    MT2
        LD      A,(WK_KIND)
        CALL    MTKIND
        CALL    MT2
        LD      HL,NAMEBUF
        CALL    MTS
        CALL    MTCRLF
        JP      REFSKIP
