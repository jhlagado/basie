; The command line (toolchain §5): the first part's name, any further parts,
; then options in brackets. BLINK takes the options that concern linking.
;
;     BLINK MAIN [M,F=6]
;
; The tail is copied, upper-cased, to T_BUF and parsed there.

O_DRV:  DB      0               ; the first part's drive: 0 current, 1 A:
O_NAME: DS      8,' '           ; the first part's name
O_FLAGS:
        DB      0               ; option flags, as OF_ below
O_LIB:  DB      "CPM22   "      ; P=: the library's name
O_LDRV: DB      0               ; L=: the library's drive, or 0
O_SDRV: DB      0               ; S=: the spool drive, or 0
O_ODRV: DB      0               ; O=: the output drive, name and type
O_ONAM: DS      8,' '
O_OTYP: DB      "COM"
O_OSET: DB      0               ; 1 when O= was given
O_KIND: DB      1               ; the output kind: 1 .COM, 2 .BIN, 4 .HEX
O_FILES:
        DB      0               ; F=: file-table entries, or 0
O_STACK:
        DW      0               ; STACK=: bytes, or 0
O_SEEN: DW      0               ; one bit per option, to refuse repeats
O_FLAGS2:
        DB      0               ; more flags: OF2_W

OF_K    EQU     $01             ; keep intermediate files
OF_M    EQU     $02             ; write the map
OF_Y    EQU     $04             ; write the symbol file
OF_N    EQU     $08             ; no line table
OF_R    EQU     $10             ; re-runnable image
OF_B    EQU     $20             ; keep the CCP resident
OF_Z    EQU     $40             ; no .BAK
OF_V    EQU     $80             ; verify placeholders and the library CRC
OF2_W   EQU     $01             ; write the link tables to NAME.$TB (testing)

T_BUF:  DS      130             ; the tail, upper-cased and zero-terminated
T_BAD:  DS      32              ; the text of a bad option, for the message

F_DRV:  DB      0               ; a parsed file name
F_NM:   DS      8
F_TY:   DS      3
F_HASTY:
        DB      0

; Parse the command tail. Returns A = 0 and carry clear when it is empty;
; A = 1 and carry clear when it parsed; carry after printing a diagnostic.
PARSE:  LD      HL,TAIL
        LD      B,(HL)
        INC     HL
        LD      DE,T_BUF
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
        LD      HL,T_BUF
        CALL    T_SKIP
        LD      A,(HL)
        OR      A
        RET     Z               ; empty: A = 0, carry clear
        CALL    T_PART
        RET     C
        LD      A,(F_DRV)
        LD      (O_DRV),A
        PUSH    HL
        LD      HL,F_NM
        LD      DE,O_NAME
        LD      BC,8
        LDIR
        POP     HL
.PARTS: CALL    T_SKIP          ; further parts: the linker doesn't need them
        LD      A,(HL)
        CP      ','
        JR      NZ,.OPTS
        INC     HL
        CALL    T_SKIP
        CALL    T_PART
        RET     C
        JR      .PARTS
.OPTS:  OR      A
        JR      Z,.DONE
        CP      '['
        JP      NZ,T_ERRW
        INC     HL
.OPT:   CALL    T_SKIP
        CALL    T_OPTION
        RET     C
        CALL    T_SKIP
        LD      A,(HL)
        INC     HL
        CP      ','
        JR      Z,.OPT
        CP      ']'
        JP      NZ,T_ERRB
        CALL    T_SKIP
        LD      A,(HL)
        OR      A
        JP      NZ,T_ERRW
.DONE:  LD      A,1
        OR      A
        RET

; Parse a part's file name at HL; carry after a diagnostic naming it.
T_PART: LD      (.AT),HL
        CALL    T_FILE
        RET     NC
        LD      HL,(.AT)
        JP      T_ERRAT
.AT:    DW      0

; Skip spaces at HL.
T_SKIP: LD      A,(HL)
        CP      ' '
        RET     NZ
        INC     HL
        JR      T_SKIP

; Parse one option at HL into the O_ fields. Carry after a diagnostic.
T_OPTION:
        LD      (.START),HL
        LD      A,(HL)
        INC     HL
        LD      C,A             ; C = the option's letter
        LD      A,(HL)
        CP      '='
        JR      Z,.VALUE
        CP      'T'             ; STACK=
        JR      NZ,.FLAG
        LD      A,C
        CP      'S'
        JR      NZ,.FLAG
        LD      DE,.STACKW
        LD      B,5
.SW:    LD      A,(DE)
        CP      (HL)
        JP      NZ,.BAD
        INC     DE
        INC     HL
        DJNZ    .SW
        LD      A,15
        CALL    .ONCE
        RET     C
        CALL    T_DEC
        JP      C,.BAD
        LD      (O_STACK),DE
        OR      A
        RET
.FLAG:  LD      A,C
        CP      'W'
        JR      NZ,.TABLE
        LD      A,(O_FLAGS2)    ; W: write the tables, for testing
        AND     OF2_W
        JP      NZ,.BAD
        LD      A,OF2_W
        LD      (O_FLAGS2),A
        OR      A
        RET
.TABLE: LD      DE,.FLAGS       ; letter, then its flag bit
        LD      B,8
.FL:    LD      A,(DE)
        CP      C
        JR      Z,.SETF
        INC     DE
        INC     DE
        DJNZ    .FL
        JP      .BAD
.SETF:  INC     DE
        LD      A,(DE)
        LD      B,A
        LD      A,(O_FLAGS)
        AND     B
        JP      NZ,.BAD         ; repeated
        LD      A,(O_FLAGS)
        OR      B
        LD      (O_FLAGS),A
        OR      A
        RET
.VALUE: INC     HL              ; past '='
        LD      A,C
        CP      'P'
        JR      Z,.P
        CP      'L'
        JR      Z,.L
        CP      'S'
        JR      Z,.S
        CP      'O'
        JR      Z,.O
        CP      'F'
        JP      Z,.F
        JP      .BAD
.P:     LD      A,8
        CALL    .ONCE
        RET     C
        CALL    T_FILE
        JP      C,.BAD
        LD      A,(F_DRV)       ; a library name has no drive or type
        LD      B,A
        LD      A,(F_HASTY)
        OR      B
        JP      NZ,.BAD
        PUSH    HL
        LD      HL,F_NM
        LD      DE,O_LIB
        LD      BC,8
        LDIR
        POP     HL
        OR      A
        RET
.L:     LD      A,9
        LD      DE,O_LDRV
        JR      .DRIVE
.S:     LD      A,10
        LD      DE,O_SDRV
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
.O:     LD      A,11
        CALL    .ONCE
        RET     C
        CALL    T_FILE
        JP      C,.BAD
        LD      A,1
        LD      (O_OSET),A
        LD      A,(F_DRV)
        LD      (O_ODRV),A
        PUSH    HL
        LD      HL,F_NM
        LD      DE,O_ONAM
        LD      BC,8
        LDIR
        LD      A,(F_HASTY)
        OR      A
        JR      Z,.OTYPED
        LD      BC,3            ; HL = F_TY, just after F_NM
        LD      DE,O_OTYP
        LDIR
.OTYPED:                        ; the type names the kind; others are bad
        LD      HL,.KINDS
        LD      C,1
.KIND:  PUSH    HL
        LD      DE,O_OTYP
        LD      B,3
.KCH:   LD      A,(DE)
        CP      (HL)
        INC     DE
        INC     HL
        JR      NZ,.KNO
        DJNZ    .KCH
        POP     HL
        LD      A,C
        LD      (O_KIND),A
        POP     HL
        OR      A
        RET
.KNO:   POP     HL
        INC     HL
        INC     HL
        INC     HL
        SLA     C
        BIT     3,C
        JR      Z,.KIND
        POP     HL
        JR      .BAD
.KINDS: DB      "COMBINHEX"
.F:     LD      A,12
        CALL    .ONCE
        RET     C
        CALL    T_DEC
        JR      C,.BAD
        LD      A,D
        OR      A
        JR      NZ,.BAD         ; at most 255
        LD      A,E
        LD      (O_FILES),A
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
        LD      HL,(O_SEEN)
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
        LD      (O_SEEN),HL
        POP     DE
        POP     HL
        OR      A
        RET
.TWICE: POP     DE
        POP     HL
        POP     BC              ; leave the option parser
.BAD:   LD      HL,(.START)
        JP      T_ERRAT
.START: DW      0
.STACKW:
        DB      "TACK="
.FLAGS: DB      'K',OF_K,'M',OF_M,'Y',OF_Y,'N',OF_N
        DB      'R',OF_R,'B',OF_B,'Z',OF_Z,'V',OF_V

; Parse a file name, [d:]name[.type], at HL into F_DRV, F_NM, F_TY and
; F_HASTY, leaving HL after it. Carry if it is malformed.
T_FILE: XOR     A
        LD      (F_DRV),A
        LD      (F_HASTY),A
        PUSH    HL
        LD      HL,F_NM
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
        LD      (F_DRV),A
        INC     HL
        INC     HL
.NAME:  LD      DE,F_NM
        LD      B,8
        CALL    .PART
        RET     C
        OR      A
        SCF
        RET     Z               ; an empty name
        LD      A,(HL)
        CP      '.'
        JR      NZ,.END
        INC     HL
        LD      A,1
        LD      (F_HASTY),A
        LD      DE,F_TY
        LD      B,3
        CALL    .PART
        RET     C
        OR      A
        SCF
        RET     Z               ; an empty type
.END:   OR      A
        RET
; Copy up to B name characters from HL to DE. A = the number copied; carry
; if there are more than B.
.PART:  LD      C,0
.CHAR:  LD      A,(HL)
        CALL    T_NAMEC
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
T_NAMEC:
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
T_DEC:  LD      DE,0
        LD      B,0             ; digits
.DIGIT: LD      A,(HL)
        SUB     '0'
        JR      C,.END
        CP      10
        JR      NC,.END
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
.END:   LD      A,B
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
T_ERRW: JR      T_ERRAT
; The same for a missing or misplaced bracket at HL - 1.
T_ERRB: DEC     HL
T_ERRAT:
        LD      DE,T_BAD
        LD      B,30
.COPY:  LD      A,(HL)
        OR      A
        JR      Z,.END
        CP      ','
        JR      Z,.END
        CP      ']'
        JR      Z,.END
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    .COPY
.END:   XOR     A
        LD      (DE),A
        LD      HL,T_BAD
        LD      (M_ARG1),HL
        LD      HL,224          ; L-COMMAND
        CALL    ERROR
        SCF
        RET
