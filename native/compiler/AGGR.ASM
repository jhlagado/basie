; Stage 6 aggregate layout and static-image construction.
;
; Types use one-byte IDs. 1..3 are the predefined scalar types; dynamic IDs
; index a bounded four-byte descriptor plus a retained word extent. Aggregate
; storage is allocated by top-level variables and aggregate constants.
; Initializer bytes are staged privately; the Z80 backend publishes them only
; after the complete source has succeeded.

;@ROUTINE IN A OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,DE
AG_DESC:
    SUB  AG_FIRST
    LD   L,A
    LD   H,0
    ADD  HL,HL
    ADD  HL,HL
    LD   DE,AG_TTAB
    ADD  HL,DE
    RET

;@ROUTINE IN A OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,DE
AG_SIZEP:
    SUB  AG_FIRST
    ADD  A,A
    LD   E,A
    LD   D,0
    LD   HL,AG_XTAB
    ADD  HL,DE
    RET

;@ROUTINE IN A OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
AG_SIZE:
    CP   AG_FIRST
    JR   NC,.DYNAMIC
    LD   HL,1
    CP   AG_U16
    JR   Z,.WORD
    OR   A
    RET
.WORD:
    INC  L
    OR   A
    RET
.DYNAMIC:
    CALL AG_SIZEP
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    EX   DE,HL
    OR   A
    RET

; Append the descriptor and extent in AggregateCandidate*. No structural
; lookup is performed, so this entry creates nominal record identity.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
AG_ADD:
    LD   A,(AG_TCNT)
    CP   AG_TCAP
    JR   NC,AG_EMETA
    ADD  A,AG_FIRST
    CALL AG_DESC
    LD   D,H
    LD   E,L
    LD   HL,AG_NKIND
    LD   BC,AG_TLEN
    LDIR
    LD   A,(AG_TCNT)
    ADD  A,AG_FIRST
    LD   C,A
    CALL AG_SIZEP
    LD   DE,(AG_NSIZE)
    LD   (HL),E
    INC  HL
    LD   (HL),D
    LD   HL,AG_TCNT
    INC  (HL)
    LD   A,C
    OR   A
    RET
AG_EMETA:
    CALL DG_RAISE
    DB   DG_META

; Intern a structural string or array descriptor. CandidateKind/Aux/Length and
; CandidateExtent must already be complete.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
AG_REUSE:
    LD   A,(AG_TCNT)
    OR   A
    JR   Z,AG_ADD
    LD   B,A
    LD   C,AG_FIRST
.TYPELOOP:
    LD   A,C
    CALL AG_DESC
    LD   DE,AG_NKIND
    PUSH BC
    LD   B,AG_TLEN
.BYTELOOP:
    LD   A,(DE)
    CP   (HL)
    JR   NZ,.DIFFER
    INC  DE
    INC  HL
    DJNZ .BYTELOOP
    POP  BC
    JR   .FOUND
.DIFFER:
    POP  BC
.NEXT:
    INC  C
    DJNZ .TYPELOOP
    JR   AG_ADD
.FOUND:
    LD   A,C
    OR   A
    RET

; The first compiler admits one aggregate object up to the selected complete
; program-data region. HL is a nonzero mathematical extent.
;@ROUTINE IN HL OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AG_FITRW:
    LD   A,H
    CP   4
    JR   C,.OK
    JR   NZ,.FULL
    LD   A,L
    OR   A
    JR   NZ,.FULL
.OK:
    OR   A
    RET
.FULL:
    CALL DG_RAISE
    DB   DG_DATA

; The read-only image shares the same 1 KiB proof region as generated rodata,
; but exhaustion names the declaration class that consumed it.
;@ROUTINE IN HL OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AG_FITRO:
    LD   A,H
    CP   4
    JR   C,.OK
    JR   NZ,.FULL
    LD   A,L
    OR   A
    JR   NZ,.FULL
.OK:
    OR   A
    RET
.FULL:
    CALL DG_RAISE
    DB   DG_ROCAP

AG_ENEST:
    POP  AF
AG_EFORM:
    CALL DG_RAISE
    DB   DG_BOUND
AG_EDATA:
    CALL DG_RAISE
    DB   DG_DATA
AG_ESTR:
    CALL DG_RAISE
    DB   DG_SIZE

;@ROUTINE IN A OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY,DE
AG_FIELD:
    LD   E,A
    LD   D,0
    LD   H,D
    LD   L,E
    ADD  HL,HL
    ADD  HL,DE
    ADD  HL,HL
    LD   DE,AG_FTAB
    ADD  HL,DE
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
AG_FRESH:
    LD   A,(AG_CFCNT)
    OR   A
    RET  Z
    LD   C,A
    LD   A,(AG_CFIDX)
.LOOP:
    PUSH AF
    PUSH BC
    CALL AG_FIELD
    CALL TK_SAME
    JR   C,.UNWIND
    POP  BC
    POP  AF
    INC  A
    DEC  C
    JR   NZ,.LOOP
    OR   A
    RET
.UNWIND:
    POP  BC
    POP  AF
.DUP:
    JP   EX_EDUP

AG_EVOID:
    CALL DG_RAISE
    DB   DG_EMPTY

AG_EDEEP:
    CALL DG_RAISE
    DB   DG_INITS

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
AG_LEAVE:
    LD   HL,AG_LEVEL
    DEC  (HL)
    OR   A
    RET

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
AG_PUT:
    LD   B,A
    LD   HL,(AG_OPOS)
    LD   DE,AG_IBUF
    ADD  HL,DE
    LD   A,B
    LD   (HL),A
    LD   HL,(AG_OPOS)
    INC  HL
    LD   (AG_OPOS),HL
    OR   A
    RET

; Decode the already tokenized string literal directly from resident source.
; B is the fixed capacity. The enclosing object is already zeroed, so the
; final cursor advances over padding without rewriting it.
;@ROUTINE IN B OUT A,B,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,D,DE,HL
AG_TEXT:
    LD   A,(TK_LEN)
    LD   C,A
    PUSH BC
    CALL AG_PUT
    POP  BC
    LD   A,B
    SUB  C
    LD   B,A
    LD   HL,(TK_PTR)
    INC  HL
.LOOP:
    LD   A,C
    OR   A
    JR   Z,.PAD
    LD   A,(HL)
    INC  HL
    CP   '\\'
    JR   NZ,.WRITE
    LD   A,(HL)
    INC  HL
    CP   'x'
    JR   Z,.HEX
    CP   '0'
    JR   Z,.ZERO
    CP   'n'
    JR   Z,.NEWLINE
    CP   'r'
    JR   Z,.RETURN
    CP   't'
    JR   Z,.TAB
    JR   .WRITE
.HEX:
    LD   A,(HL)
    INC  HL
    CALL TK_HEX
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,A
    LD   D,A
    LD   A,(HL)
    INC  HL
    CALL TK_HEX
    OR   D
    JR   .WRITE
.ZERO:
    XOR  A
    JR   .WRITE
.NEWLINE:
    LD   A,10
    JR   .WRITE
.RETURN:
    LD   A,13
    JR   .WRITE
.TAB:
    LD   A,9
.WRITE:
    PUSH BC
    PUSH HL
    CALL AG_PUT
    POP  HL
    POP  BC
    DEC  C
    JR   .LOOP
.PAD:
    LD   E,B
    LD   D,0
    INC  DE                        ; permanent terminator at capacity+1
    LD   HL,(AG_OPOS)
    ADD  HL,DE
    LD   (AG_OPOS),HL
    OR   A
    RET

AG_EINIT:
    CALL DG_RAISE
    DB   DG_SHAPE
AG_ECNT:
    CALL DG_RAISE
    DB   DG_ITEMS

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
AG_PEEK:
    PUSH BC
    CALL PR_PEEK
    POP  BC
    RET

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
AG_TAKE:
    PUSH BC
    CALL PR_TAKE
    POP  BC
    RET

;@ROUTINE IN A,BC,ZERO OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
AG_COMMA:
    JR   Z,AG_ECNT
    CP   TK_COMMA
    JR   NZ,AG_EINIT
    JR   AG_TAKE

; Parse one type-directed static initializer at the current image cursor.
;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
AG_PARSE:
    CP   AG_FIRST
    JR   C,.SCALAR
    PUSH AF
    CALL AG_DESC
    LD   A,(HL)
    POP  DE
    LD   E,D
    LD   D,0
    CP   AG_KSTR
    JR   Z,.STRING
    CP   AG_KREC
    JR   Z,AG_REC
    CP   AG_KARR
    JP   Z,AG_ARRAY
    JR   AG_EINIT

.SCALAR:
    LD   E,A
    PUSH DE
    CALL EX_CONST
    POP  DE
    CALL EX_FITS
    AND  SY_KNOWN
    JP   Z,EX_ETYPE
    LD   A,L
    PUSH DE
    PUSH HL
    CALL AG_PUT
    POP  HL
    POP  DE
    LD   A,E
    CP   AG_U16
    JR   Z,.UPPER
    OR   A
    RET
.UPPER:
    LD   A,H
    JP   AG_PUT

.STRING:
    EX   DE,HL
    LD   A,L
    CALL AG_DESC
    INC  HL
    LD   B,(HL)
    PUSH BC
    LD   E,TK_TEXT
    CALL PR_NEED
    POP  BC
    LD   A,(TK_LEN)
    CP   B
    JR   C,.DECODE
    JR   Z,.DECODE
    CALL DG_RAISE
    DB   DG_LONG
.DECODE:
; AG_ZERO already defined the complete object,
; so decoding need only overwrite the length and payload bytes.
    JP   AG_TEXT

;@ROUTINE IN A,BC OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL
AG_ENTER:
    PUSH AF
    CALL AG_PEEK
    POP  DE
    CP   D
    JP   NZ,AG_EINIT
    CALL AG_TAKE
    LD   A,(AG_LEVEL)
    CP   AG_LCAP
    JP   NC,AG_EDEEP
    INC  A
    LD   (AG_LEVEL),A
    OR   A
    RET

AG_REC:
    EX   DE,HL
    LD   A,L
    CALL AG_DESC
    INC  HL
    LD   A,(HL)
    ADD  A,A
    LD   E,A
    LD   D,0
    LD   HL,AG_RTAB
    ADD  HL,DE
    LD   B,(HL)
    INC  HL
    LD   C,(HL)
    LD   A,TK_LPAR
    CALL AG_ENTER
.LOOP:
    PUSH BC
    LD   A,B
    CALL AG_FIELD
    INC  HL
    INC  HL
    INC  HL
    LD   A,(HL)
    CALL AG_PARSE
    POP  BC
    INC  B
    DEC  C
    JR   Z,.CLOSE
    CALL AG_PEEK
    CP   TK_RPAR
    CALL AG_COMMA
    JR   .LOOP
.CLOSE:
    LD   BC,TK_RPAR<<8|TK_RBRAC
    JR   AG_CLOSE

AG_ARRAY:
    EX   DE,HL
    LD   A,L
    CALL AG_DESC
    INC  HL
    LD   C,(HL)
    INC  HL
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    PUSH BC
    PUSH DE
    LD   A,TK_LBRAC
    CALL AG_ENTER
    POP  DE
    POP  BC
.LOOP:
    PUSH BC
    PUSH DE
    LD   A,C
    CALL AG_PARSE
    POP  DE
    POP  BC
    DEC  DE
    LD   A,D
    OR   E
    JR   Z,.CLOSE
    PUSH DE
    CALL AG_PEEK
    POP  DE
    CP   TK_RBRAC
    PUSH DE
    CALL AG_COMMA
    POP  DE
    JR   .LOOP
.CLOSE:
    LD   BC,TK_RBRAC<<8|TK_RPAR

;@ROUTINE IN BC OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL,IX,IY
AG_CLOSE:
    CALL AG_PEEK
    CP   B
    JR   Z,.TAKE
    CP   C
    JP   Z,AG_EINIT
    JP   AG_ECNT
.TAKE:
    CALL PR_TAKE
    JP   AG_LEAVE

; Zero exactly the candidate object's complete extent before applying an
; explicit initializer. This also defines every byte of a zero initializer.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
AG_ZERO:
    LD   HL,(AG_OPOS)
    LD   DE,AG_IBUF
    ADD  HL,DE
    LD   BC,(AG_OSIZE)
.LOOP:
    LD   A,B
    OR   C
    RET  Z
    XOR  A
    LD   (HL),A
    INC  HL
    DEC  BC
    JR   .LOOP

; The current token is the program variable name.

; Dedicated Stage 6 compile entry. Historical slices keep AG_MODE clear;
; this entry makes the complete static-image path authoritative.
