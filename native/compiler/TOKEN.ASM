; Tokenizer subset for the scalar-local, counted-loop, and array proofs.

;@ROUTINE OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,A,DE,HL
TK_MARK:
    LD   HL,(SRC_POS)
    LD   (TK_POS),HL
    LD   HL,(SRC_LINE)
    LD   (TK_LINE),HL
    LD   HL,(SRC_COL)
    LD   (TK_COL),HL
    LD   HL,(SRC_PTR)
    LD   (TK_PTR),HL
    RET

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D
TK_DONE:
    LD   D,A
    LD   A,1
    LD   (TK_LIVE),A
    LD   A,D
    OR   A
    RET

;@ROUTINE OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,A,DE,HL
TK_BAD:
    CALL DG_RAISE
    DB   DG_LEX

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,C
TK_ALPHA:
    LD   C,A
    OR   $20
    SUB  'a'
    CP   26
    LD   A,C
    RET

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,C
TK_ALNUM:
    CALL TK_ALPHA
    RET  C
    CP   '0'
    JR   C,.UNDER
    CP   '9'+1
    JR   C,.YES
.UNDER:
    CP   '_'
    JR   Z,.YES
    OR   A
    RET
.YES:
    SCF
    RET

;@ROUTINE IN B,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
TK_MATCH:
    LD   A,(TK_LEN)
    CP   B
    JR   NZ,.NO
    LD   DE,(TK_PTR)
.LOOP:
    LD   A,(DE)
    CP   (HL)
    JR   NZ,.NO
    INC  DE
    INC  HL
    DJNZ .LOOP
    SCF
    RET
.NO:
    OR   A
    RET

; Compare the current NAME token with the retained name record at HL. The
; record begins with a pointer word followed by a one-byte length.
;@ROUTINE IN BC,HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
TK_SAME:
    PUSH BC
    PUSH HL
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    INC  HL
    LD   A,(HL)
    LD   B,A
    EX   DE,HL
    CALL TK_MATCH
    POP  HL
    POP  BC
    RET

; Store the current NAME token's pointer and length in the three-byte record
; at HL. HL returns at the length byte, matching the former inline sequences.
;@ROUTINE IN HL OUT A,BC,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
TK_KEEP:
    LD   BC,(TK_PTR)
    LD   (HL),C
    INC  HL
    LD   (HL),B
    INC  HL
    LD   A,(TK_LEN)
    LD   (HL),A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
TK_WORD:
    LD   B,0
.NAMELOOP:
    CALL SRC_PEEK
    JR   C,.DONE
    CALL TK_ALNUM
    JR   NC,.DONE
    CALL SRC_TAKE
    INC  B
    JR   Z,TK_BAD
    JR   .NAMELOOP
.DONE:
    LD   A,B
    LD   (TK_LEN),A
    LD   HL,KW_TAB
    LD   C,KW_CNT
.KEYLOOP:
    LD   B,(HL)
    INC  HL
    LD   A,(TK_LEN)
    CP   B
    JR   NZ,.SKIP
    LD   DE,(TK_PTR)
.BYTELOOP:
    LD   A,(DE)
    CP   (HL)
    JR   NZ,.SKIP
    INC  DE
    INC  HL
    DJNZ .BYTELOOP
    LD   A,(HL)
    JP   TK_DONE
.SKIP:
    LD   E,B
    LD   D,0
    ADD  HL,DE
    INC  HL
    DEC  C
    JR   NZ,.KEYLOOP
    LD   A,TK_NAME
    JP   TK_DONE

; Scan one or more decimal digits and reject a value above 65535. BC carries
; the exact unsigned literal payload to the predictive parser.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
TK_DIGIT:
    LD   HL,0
.LOOP:
    PUSH HL
    CALL SRC_PEEK
    POP  HL
    JR   C,TK_NUMOK
    CP   '0'
    JR   C,TK_TRAIL
    CP   '9'+1
    JR   NC,TK_TRAIL
    SUB  '0'
    LD   C,A
    LD   A,H
    CP   $19
    JR   C,.APPEND
    JR   NZ,TK_ERR
    LD   A,L
    CP   $99
    JR   C,.APPEND
    JR   NZ,TK_ERR
    LD   A,C
    CP   6
    JR   NC,TK_ERR
.APPEND:
    LD   D,0
    LD   E,C
    ADD  HL,HL
    LD   B,H
    LD   C,L
    ADD  HL,HL
    ADD  HL,HL
    ADD  HL,BC
    ADD  HL,DE
    PUSH HL
    CALL SRC_TAKE
    POP  HL
    JR   .LOOP
TK_TRAIL:
; An integer token cannot be followed immediately by a name byte.
; Reject forms such as 0x2a and 12u8 as one malformed number rather
; than exposing a misleading number/name token pair to the parser.
    CALL TK_ALNUM
    JP   C,TK_BAD
TK_NUMOK:
    LD   B,H
    LD   C,L
    LD   A,TK_NUM
    JP   TK_DONE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL
TK_APOS:
    CALL SRC_TAKE
    JR   C,TK_ERR
    CALL SRC_TAKE
    JR   C,TK_ERR
    CP   $20
    JR   C,TK_ERR
    CP   $7F
    JR   NC,TK_ERR
    CP   '\''
    JR   Z,TK_ERR
    CP   '\\'
    JR   Z,TK_ERR
    LD   C,A
    CALL SRC_TAKE
    JR   C,TK_ERR
    CP   '\''
    JR   NZ,TK_ERR
    LD   A,TK_CHAR
    JP   TK_DONE
TK_ERR:
    JP   TK_BAD

; Return carry and the decoded nibble for one hexadecimal digit. Tokenization
; needs only the validity flag; the static-image decoder reuses the value.
;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
TK_HEX:
    CP   '0'
    JR   C,.NO
    CP   '9'+1
    JR   C,.DECIMAL
    OR   $20
    SUB  'a'
    CP   6
    JR   NC,.NO
    ADD  A,10
    SCF
    RET
.DECIMAL:
    SUB  '0'
    SCF
    RET
.NO:
    OR   A
    RET

; Scan and validate a bounded-string literal. BC returns the decoded byte
; length. TK_PTR continues to identify the opening quote so the
; declaration parser can decode the bytes directly into the static image.
;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
TK_QUOTE:
    CALL SRC_TAKE
    JR   C,TK_ERR
    LD   C,0
TK_QNEXT:
    CALL SRC_TAKE
    JR   C,TK_ERR
    CP   '"'
    JR   Z,TK_QDONE
    CP   $20
    JR   C,TK_ERR
    CP   $7F
    JR   NC,TK_ERR
    CP   '\\'
    JR   Z,TK_QESC
TK_QCNT:
    INC  C
    JR   Z,TK_ERR
    JR   TK_QNEXT
TK_QESC:
    CALL SRC_TAKE
    JR   C,TK_ERR
    CP   'x'
    JR   Z,.HEX
    LD   HL,TK_ESC
    LD   B,TK_ECNT
.LOOP:
    CP   (HL)
    JR   Z,TK_QCNT
    INC  HL
    DJNZ .LOOP
    JR   TK_ERR
.HEX:
    CALL SRC_TAKE
    JR   C,TK_ERR
    CALL TK_HEX
    JR   NC,TK_ERR
    CALL SRC_TAKE
    JR   C,TK_ERR
    CALL TK_HEX
    JR   NC,TK_ERR
    JR   TK_QCNT
TK_QDONE:
    LD   B,0
    LD   A,C
    LD   (TK_LEN),A
    LD   A,TK_TEXT
    JP   TK_DONE

;@ROUTINE OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,A,DE,HL
TK_REM:
.LOOP:
    CALL SRC_PEEK
    RET  C
    CP   10
    RET  Z
    CP   13
    RET  Z
    CALL SRC_TAKE
    JR   .LOOP

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
TK_NEXT:
TK_AGAIN:
    CALL TK_MARK
    CALL SRC_PEEK
    JP   C,TK_ATEND

    CP   ' '
    JR   Z,.SKIP
    CP   9
    JR   Z,.SKIP
    CP   10
    JP   Z,TK_LF
    CP   13
    JP   Z,TK_CRLF
    CP   '/'
    JR   Z,.SLASH
    CP   '('
    JP   Z,.LPAR
    CP   ')'
    JP   Z,.RPAR
    CP   '['
    JP   Z,.LBRAC
    CP   ']'
    JP   Z,.RBRAC
    CP   '<'
    JR   Z,.LESS
    CP   '>'
    JR   Z,.GREATER
    LD   HL,KW_PUNCT
    LD   B,KW_PCNT
.PUNCT:
    CP   (HL)
    INC  HL
    JP   Z,TK_PUNCT
    INC  HL
    DJNZ .PUNCT
    CP   '\''
    JP   Z,TK_APOS
    CP   '"'
    JP   Z,TK_QUOTE
    CP   '0'
    JR   C,.NAME
    CP   '9'+1
    JP   C,TK_DIGIT
.NAME:
    CALL TK_ALPHA
    JP   C,TK_WORD
    JR   TK_FAULT

.SKIP:
    CALL SRC_TAKE
    JR   TK_AGAIN

.SLASH:
    CALL SRC_TAKE
    CALL SRC_PEEK
    JR   C,.DIVIDE
    CP   '/'
    JR   NZ,.DIVIDE
    CALL SRC_TAKE
    CALL TK_REM
    JR   TK_AGAIN
.DIVIDE:
    LD   A,TK_SLASH
    JP   TK_DONE

.LESS:
    CALL SRC_TAKE
    CALL SRC_PEEK
    JR   C,.LT
    CP   '='
    JR   Z,.LE
    CP   '>'
    JR   Z,.NE
.LT:
    LD   A,TK_LT
    JP   TK_DONE
.LE:
    LD   C,TK_LE
    JR   TK_TAKE
.NE:
    LD   C,TK_NE
    JR   TK_TAKE

.GREATER:
    CALL SRC_TAKE
    CALL SRC_PEEK
    JR   C,.GT
    CP   '='
    JR   Z,.GE
.GT:
    LD   A,TK_GT
    JP   TK_DONE
.GE:
    LD   C,TK_GE
    JR   TK_TAKE

.LPAR:
    LD   C,TK_LPAR
    JR   .OPEN

.RPAR:
    LD   C,TK_RPAR
    JR   .CLOSE

.LBRAC:
    LD   C,TK_LBRAC
.OPEN:
    CALL SRC_TAKE
    LD   A,(TK_NEST)
    INC  A
    JR   Z,TK_FAULT
    LD   (TK_NEST),A
    LD   A,C
    JP   TK_DONE

.RBRAC:
    LD   C,TK_RBRAC
.CLOSE:
    LD   A,(TK_NEST)
    OR   A
    JR   Z,TK_FAULT
    DEC  A
    LD   (TK_NEST),A
    CALL SRC_TAKE
    LD   A,C
    JP   TK_DONE

TK_FAULT:
    JP   TK_BAD

TK_PUNCT:
    LD   C,(HL)
    BIT  7,C
    JR   NZ,TK_BASED
TK_TAKE:
    CALL SRC_TAKE
    LD   A,C
    JP   TK_DONE
TK_BASED:
    RES  7,C
    LD   B,C
    JR   TK_RADIX

TK_LF:
    CALL SRC_TAKE
    JR   TK_BREAK
TK_CRLF:
    CALL SRC_TAKE
    CALL SRC_PEEK
    JR   C,TK_FAULT
    CP   10
    JR   NZ,TK_FAULT
    CALL SRC_TAKE
TK_BREAK:
    CALL SRC_EOL
    LD   A,(TK_NEST)
    OR   A
    JP   NZ,TK_AGAIN
    LD   A,(TK_LIVE)
    OR   A
    JP   Z,TK_AGAIN
    XOR  A
    LD   (TK_LIVE),A
    LD   A,TK_EOL
    OR   A
    RET

TK_ATEND:
    LD   A,(TK_NEST)
    OR   A
    JR   NZ,TK_FAULT
    LD   A,(SRC_LEFT)
    BIT  7,A
    JR   NZ,.NEXTPART
    AND  SRC_CNT
    OR   A
    JR   Z,.LAST
    LD   A,(TK_LIVE)
    OR   A
    JR   Z,.NEXTPART
    XOR  A
    LD   (TK_LIVE),A
    LD   HL,SRC_LEFT
    SET  7,(HL)
    LD   A,TK_EOL
    OR   A
    RET
.NEXTPART:
    LD   HL,SRC_LEFT
    LD   A,(HL)
    AND  $7F
    ADD  A,SRC_STEP-1
    LD   (HL),A
    LD   HL,(SRC_DESC)
    CALL SRC_LOAD
    JP   TK_AGAIN
.LAST:
    LD   A,(TK_LIVE)
    OR   A
    JR   Z,.EOF
    XOR  A
    LD   (TK_LIVE),A
    LD   A,TK_EOL
    OR   A
    RET
.EOF:
    LD   A,TK_EOF
    OR   A
    RET

;@ROUTINE IN BC OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
TK_RADIX:
    CALL SRC_TAKE
    LD   HL,0
.LOOP:
    LD   D,0
    PUSH HL
    CALL SRC_PEEK
    POP  HL
    JR   C,.DONE
    LD   D,A
    BIT  4,C
    JR   NZ,.BINARY
    CALL TK_HEX
    JR   C,.DIGIT
    JR   .DONE
.BINARY:
    SUB  '0'
    JR   C,.DONE
    CP   2
    JR   C,.DIGIT
    JR   .DONE
.DIGIT:
    DEC  B
    JR   Z,.BAD
    LD   E,A
    BIT  4,C
    JR   NZ,.SHIFT
    ADD  HL,HL
    ADD  HL,HL
    ADD  HL,HL
.SHIFT:
    ADD  HL,HL
    LD   A,E
    OR   L
    LD   L,A
    PUSH HL
    CALL SRC_TAKE
    POP  HL
    JR   .LOOP
.DONE:
    LD   A,B
    CP   C
    JR   Z,.BAD
    LD   A,D
    OR   A
    JP   Z,TK_NUMOK
    JP   TK_TRAIL
.BAD:
    JP   TK_BAD

TK_ESC: DB   "0nrt",$27,$22,"\\"
TK_ECNT EQU  7
