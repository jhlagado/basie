; The command line (toolchain §5): the first part's name, any further parts,
; then options in brackets. BLINK takes the options that concern linking.
;
;     BLINK MAIN [M,F=6]
;
; The tail is copied, upper-cased, to CMD_BUF and parsed there.

CMD_DISK:  DB      0            ; the first part's drive: 0 current, 1 A:
CMD_NAME: DS      8,' '         ; the first part's name
OP_FLAGS:
        DB      0               ; option flags, as OF_ below
LIB_FILE:  DB      "CPM22   "   ; P=: the library's name
LIB_DISK: DB      0             ; L=: the library's drive, or 0
OP_SPOOL: DB      0             ; S=: the spool drive, or 0
OUT_DISK: DB      0             ; O=: the output drive, name and type
OUT_NAME: DS      8,' '
OUT_TYPE: DB      "COM"
OUT_SET: DB      0              ; 1 when O= was given
OUT_KIND: DB      1             ; the output kind: 1 .COM, 2 .BIN, 4 .HEX
OP_FILES:
        DB      0               ; F=: file-table entries, or 0
OP_STACK:
        DW      0               ; STACK=: bytes, or 0
OP_SEEN: DW      0              ; one bit per option, to refuse repeats
OP_EXTRA:
        DB      0               ; more flags: OX_W

OF_K    EQU     $01             ; keep intermediate files
OF_M    EQU     $02             ; write the map
OF_Y    EQU     $04             ; write the symbol file
OF_N    EQU     $08             ; no line table
OF_R    EQU     $10             ; re-runnable image
OF_B    EQU     $20             ; keep the CCP resident
OF_Z    EQU     $40             ; no .BAK
OF_V    EQU     $80             ; verify placeholders and the library CRC
OX_W   EQU     $01              ; write the link tables to NAME.$TB (testing)

; CMD_BUF, the tail upper-cased and zero-terminated, and CMD_BAD, the text of a
; bad option for its message, are in two of Phase D's FDs (PHASECD.ASM).

FN_DISK:  DB      0             ; a parsed file name
FN_NAME:   DS      8
FN_TYPE:   DS      3
FN_TYPED:
        DB      0

; Parse the command tail. Returns A = 0 and carry clear when it is empty;
; A = 1 and carry clear when it parsed; carry after printing a diagnostic.
CMD_READ:  LD      HL,CPM_TAIL
        LD      B,(HL)
        INC     HL
        LD      DE,CMD_BUF
        LD      A,B
        OR      A
        JR      Z,.COPIED
.COPY:  LD      A,(HL)
        CP      'a'
        JR      C,.KEEP
        CP      'z'+1
        JR      NC,.KEEP
        SUB     32
.KEEP:  LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    .COPY
.COPIED:
        XOR     A
        LD      (DE),A
        LD      HL,CMD_BUF
        CALL    .SKIP
        LD      A,(HL)
        OR      A
        RET     Z               ; empty: A = 0, carry clear
        CALL    .PART
        RET     C
        LD      A,(FN_DISK)
        LD      (CMD_DISK),A
        PUSH    HL
        LD      HL,FN_NAME
        LD      DE,CMD_NAME
        LD      BC,8
        LDIR
        POP     HL
.PARTS: CALL    .SKIP           ; further parts: the linker doesn't need them
        LD      A,(HL)
        CP      ','
        JR      NZ,.OPTSTART
        INC     HL
        CALL    .SKIP
        CALL    .PART
        RET     C
        JR      .PARTS
.OPTSTART:  OR      A
        JR      Z,.DONE
        CP      '['
        JP      NZ,.BADWORD
        INC     HL
.OPTLOOP:   CALL    .SKIP
        CALL    .OPTION
        RET     C
        CALL    .SKIP
        LD      A,(HL)
        INC     HL
        CP      ','
        JR      Z,.OPTLOOP
        CP      ']'
        JP      NZ,.BRACKET
        CALL    .SKIP
        LD      A,(HL)
        OR      A
        JP      NZ,.BADWORD
.DONE:  LD      A,1
        OR      A
        RET

; Parse a part's file name at HL; carry after a diagnostic naming it.
.PART: LD      (.AT),HL
        CALL    .FILENAME
        RET     NC
        LD      HL,(.AT)
        JP      .REPORT
.AT:    DW      0

; Skip spaces at HL.
.SKIP: LD      A,(HL)
        CP      ' '
        RET     NZ
        INC     HL
        JR      .SKIP

; Parse one option at HL into the O_ fields. Carry after a diagnostic.
.OPTION:
        LD      (.START),HL
        LD      A,(HL)
        INC     HL
        LD      C,A             ; C = the option's letter
        LD      A,(HL)
        CP      '='
        JR      Z,.VALUE
        CP      'T'             ; STACK=
        JR      NZ,.NOVALUE
        LD      A,C
        CP      'S'
        JR      NZ,.NOVALUE
        LD      DE,.STACKW
        LD      B,5
.SPELL:    LD      A,(DE)
        CP      (HL)
        JP      NZ,.BAD
        INC     DE
        INC     HL
        DJNZ    .SPELL
        LD      A,15
        CALL    .ONCE
        RET     C
        CALL    .DECIMAL
        JP      C,.BAD
        LD      (OP_STACK),DE
        OR      A
        RET
.NOVALUE:  LD      A,C
        CP      'W'
        JR      NZ,.TABLE
        LD      A,(OP_EXTRA)    ; W: write the tables, for testing
        AND     OX_W
        JP      NZ,.BAD
        LD      A,OX_W
        LD      (OP_EXTRA),A
        OR      A
        RET
.TABLE: LD      DE,.FLAGS       ; letter, then its flag bit
        LD      B,8
.LOOKFLAG:    LD      A,(DE)
        CP      C
        JR      Z,.SETFLAG
        INC     DE
        INC     DE
        DJNZ    .LOOKFLAG
        JP      .BAD
.SETFLAG:  INC     DE
        LD      A,(DE)
        LD      B,A
        LD      A,(OP_FLAGS)
        AND     B
        JP      NZ,.BAD         ; repeated
        LD      A,(OP_FLAGS)
        OR      B
        LD      (OP_FLAGS),A
        OR      A
        RET
.VALUE: INC     HL              ; past '='
        LD      A,C
        CP      'P'
        JR      Z,.LIBRARY
        CP      'L'
        JR      Z,.LIBDISK
        CP      'S'
        JR      Z,.SPOOL
        CP      'O'
        JR      Z,.OUTPUT
        CP      'F'
        JP      Z,.FILES
        JP      .BAD
.LIBRARY:     LD      A,8
        CALL    .ONCE
        RET     C
        CALL    .FILENAME
        JP      C,.BAD
        LD      A,(FN_DISK)     ; a library name has no drive or type
        LD      B,A
        LD      A,(FN_TYPED)
        OR      B
        JP      NZ,.BAD
        PUSH    HL
        LD      HL,FN_NAME
        LD      DE,LIB_FILE
        LD      BC,8
        LDIR
        POP     HL
        OR      A
        RET
.LIBDISK:     LD      A,9
        LD      DE,LIB_DISK
        JR      .DRIVE
.SPOOL:     LD      A,10
        LD      DE,OP_SPOOL
.DRIVE: CALL    .ONCE
        RET     C
        LD      A,(HL)
        SUB     'A'
        JP      C,.BAD
        CP      16
        JP      NC,.BAD
        INC     A
        LD      (DE),A
        INC     HL
        OR      A
        RET
.OUTPUT:     LD      A,11
        CALL    .ONCE
        RET     C
        CALL    .FILENAME
        JP      C,.BAD
        LD      A,1
        LD      (OUT_SET),A
        LD      A,(FN_DISK)
        LD      (OUT_DISK),A
        PUSH    HL
        LD      HL,FN_NAME
        LD      DE,OUT_NAME
        LD      BC,8
        LDIR
        LD      A,(FN_TYPED)
        OR      A
        JR      Z,.TYPED
        LD      BC,3            ; HL = FN_TYPE, just after FN_NAME
        LD      DE,OUT_TYPE
        LDIR
.TYPED:                         ; the type names the kind; others are bad
        LD      HL,.KINDS
        LD      C,1
.KIND:  PUSH    HL
        LD      DE,OUT_TYPE
        LD      B,3
.TYPECHAR:   LD      A,(DE)
        CP      (HL)
        INC     DE
        INC     HL
        JR      NZ,.NEXTKIND
        DJNZ    .TYPECHAR
        POP     HL
        LD      A,C
        LD      (OUT_KIND),A
        POP     HL
        OR      A
        RET
.NEXTKIND:   POP     HL
        INC     HL
        INC     HL
        INC     HL
        SLA     C
        BIT     3,C
        JR      Z,.KIND
        POP     HL
        JR      .BAD
.KINDS: DB      "COMBINHEX"
.FILES:     LD      A,12
        CALL    .ONCE
        RET     C
        CALL    .DECIMAL
        JR      C,.BAD
        LD      A,D
        OR      A
        JR      NZ,.BAD         ; at most 255
        LD      A,E
        LD      (OP_FILES),A
        OR      A
        RET
; Mark option number A seen; carry with the diagnostic if it already was.
.ONCE:  PUSH    HL
        PUSH    DE
        LD      HL,1
        OR      A
        JR      Z,.MASK
.SHIFT: ADD     HL,HL
        DEC     A
        JR      NZ,.SHIFT
.MASK:  EX      DE,HL
        LD      HL,(OP_SEEN)
        LD      A,H
        AND     D
        LD      B,A
        LD      A,L
        AND     E
        OR      B
        JR      NZ,.TWICE
        LD      A,H
        OR      D
        LD      H,A
        LD      A,L
        OR      E
        LD      L,A
        LD      (OP_SEEN),HL
        POP     DE
        POP     HL
        OR      A
        RET
.TWICE: POP     DE
        POP     HL
        POP     BC              ; leave the option parser
.BAD:   LD      HL,(.START)
        JP      .REPORT
.START: DW      0
.STACKW:
        DB      "TACK="
.FLAGS: DB      'K',OF_K,'M',OF_M,'Y',OF_Y,'N',OF_N
        DB      'R',OF_R,'B',OF_B,'Z',OF_Z,'V',OF_V

; Parse a file name, [d:]name[.type], at HL into FN_DISK, FN_NAME, FN_TYPE and
; FN_TYPED, leaving HL after it. Carry if it is malformed.
.FILENAME: XOR     A
        LD      (FN_DISK),A
        LD      (FN_TYPED),A
        PUSH    HL
        LD      HL,FN_NAME
        LD      B,11
.BLANK: LD      (HL),' '
        INC     HL
        DJNZ    .BLANK
        POP     HL
        INC     HL
        LD      A,(HL)
        DEC     HL
        CP      ':'
        JR      NZ,.NAME
        LD      A,(HL)
        SUB     'A'
        RET     C
        CP      16
        CCF
        RET     C
        INC     A
        LD      (FN_DISK),A
        INC     HL
        INC     HL
.NAME:  LD      DE,FN_NAME
        LD      B,8
        CALL    .FIELD
        RET     C
        OR      A
        SCF
        RET     Z               ; an empty name
        LD      A,(HL)
        CP      '.'
        JR      NZ,.ENDNAME
        INC     HL
        LD      A,1
        LD      (FN_TYPED),A
        LD      DE,FN_TYPE
        LD      B,3
        CALL    .FIELD
        RET     C
        OR      A
        SCF
        RET     Z               ; an empty type
.ENDNAME:   OR      A
        RET
; Copy up to B name characters from HL to DE. A = the number copied; carry
; if there are more than B.
.FIELD:  LD      C,0
.CHAR:  LD      A,(HL)
        CALL    .NAMECHAR
        JR      C,.STOP
        LD      A,C
        CP      B
        CCF
        RET     C               ; too long
        LD      A,(HL)
        LD      (DE),A
        INC     HL
        INC     DE
        INC     C
        JR      .CHAR
.STOP:  LD      A,C
        OR      A               ; carry clear
        RET

; Carry unless A may appear in a CP/M name (services §4.1).
.NAMECHAR:
        CP      'A'
        JR      C,.OTHER
        CP      'Z'+1
        CCF
        RET     NC
.OTHER: CP      '0'
        JR      C,.PUNCT
        CP      '9'+1
        CCF
        RET     NC
.PUNCT: PUSH    HL
        PUSH    BC
        LD      HL,.SET
        LD      B,16            ; the characters in .SET
.LOOK:  CP      (HL)
        JR      Z,.YES
        INC     HL
        DJNZ    .LOOK
        POP     BC
        POP     HL
        SCF
        RET
.YES:   POP     BC
        POP     HL
        OR      A
        RET
.SET:   DB      "!#$%&'()-@^_`{}~"

; DE = a decimal number of 1 to 5 digits at HL, 1 to 65535. Carry if it is
; malformed or out of range.
.DECIMAL:  LD      DE,0
        LD      B,0             ; digits
.DIGIT: LD      A,(HL)
        SUB     '0'
        JR      C,.ENDNUM
        CP      10
        JR      NC,.ENDNUM
        INC     B
        LD      C,A
        PUSH    HL
        LD      H,D
        LD      L,E
        ADD     HL,HL
        JR      C,.OVER
        ADD     HL,HL
        JR      C,.OVER
        ADD     HL,DE
        JR      C,.OVER
        ADD     HL,HL
        JR      C,.OVER         ; * 10
        LD      E,C
        LD      D,0
        ADD     HL,DE
        JR      C,.OVER
        EX      DE,HL
        POP     HL
        INC     HL
        JR      .DIGIT
.OVER:  POP     HL
        SCF
        RET
.ENDNUM:   LD      A,B
        OR      A
        SCF
        RET     Z               ; no digits
        CP      6
        CCF
        RET     C               ; too many
        LD      A,D
        OR      E
        SCF
        RET     Z               ; zero
        OR      A
        RET

; Report L-COMMAND for the word at HL (to the next comma, bracket or the
; end), then return carry.
.BADWORD: JR      .REPORT
; The same for a missing or misplaced bracket at HL - 1.
.BRACKET: DEC     HL
.REPORT:
        LD      DE,CMD_BAD
        LD      B,30
.COPYWORD:  LD      A,(HL)
        OR      A
        JR      Z,.ENDWORD
        CP      ','
        JR      Z,.ENDWORD
        CP      ']'
        JR      Z,.ENDWORD
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    .COPYWORD
.ENDWORD:   XOR     A
        LD      (DE),A
        LD      HL,CMD_BAD
        LD      (DG_ARG1),HL
        LD      HL,224          ; L-COMMAND
        CALL    DG_ERROR
        SCF
        RET
