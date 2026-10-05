; Packed LL(1) interpreter for the complete Stage 7 grammar.
; Token ordinals occupy $00..$3F, nonterminals $40..$7F, and explicit
; semantic or retained-expression actions $80..$FE. Productions store their
; right sides in reverse order so one bounded copy pushes a complete rule.

LL_CAP EQU  64
LL_DEPTH EQU  TG_WEND
LL_STACK EQU  LL_DEPTH+1
LL_WEND EQU  TG_END
DG_LLCAP EQU  87

; Push the start symbol and run until the grammar stack is empty. Explicit
; actions return through .RESUME with carry reporting failure.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
LL_PARSE:
    XOR  A
    LD   (LL_DEPTH),A
    LD   A,GR_START
    CALL .PUSHSYM
.LOOP:
    LD   A,(LL_DEPTH)
    OR   A
    RET  Z
    CALL .POPSYM
    CP   $40
    JR   C,.TERMINAL
    CP   $80
    JR   C,.NONTERM

; Action ordinal -> absolute routine address. A retains the
; zero-based ordinal for parameterised physical handlers.
    SUB  $80
    LD   L,A
    LD   H,0
    ADD  HL,HL
    LD   DE,GR_ACTX
    ADD  HL,DE
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    EX   DE,HL
    LD   DE,.RESUME
    PUSH DE
    JP   (HL)
.RESUME:
    JR   .LOOP

.TERMINAL:
    LD   E,A
    CALL PR_NEED
    JR   .LOOP

.NONTERM:
    SUB  $40
    LD   L,A
    LD   H,0
    ADD  HL,HL
    LD   DE,GR_ROWX
    ADD  HL,DE
    LD   E,(HL)
    INC  HL
    LD   A,(HL)
    PUSH AF
    LD   D,0
    LD   HL,GR_ROWS
    ADD  HL,DE
    PUSH HL
    CALL PR_PEEK
    POP  HL
    LD   C,A
.NEXTALT:
    LD   B,(HL)
    INC  HL
.TOKEN:
    LD   A,(HL)
    LD   E,A
    AND  $7F
    CP   C
    JR   Z,.MATCH
    INC  HL
    BIT  7,E
    JR   Z,.TOKEN
    BIT  7,B
    JR   NZ,.NOMATCH
    JR   .NEXTALT
.NOMATCH:
    POP  AF
    JP   DG_ISSUE
.MATCH:
    POP  AF
    LD   A,B
    AND  $7F
    CALL .EXPAND
    JR   .LOOP

; A is a production ordinal. Adjacent directory offsets delimit its body.
;@ROUTINE IN A OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
.EXPAND:
    CP   GR_SPLIT
    LD   DE,GR_ALTS
    LD   HL,GR_ALTX
    JR   C,.LOCATED
    SUB  GR_SPLIT
    LD   DE,GR_ALTHI
    LD   HL,GR_ALTXH
.LOCATED:
    LD   C,A
    LD   B,0
    ADD  HL,BC
    LD   C,(HL)
    INC  HL
    LD   A,(HL)
    SUB  C
    LD   B,A
    LD   A,C
    LD   L,A
    LD   H,0
    ADD  HL,DE
    LD   A,B
    OR   A
    RET  Z
    LD   A,(LL_DEPTH)
    LD   C,A
    ADD  A,B
    JR   C,.FULL
    CP   LL_CAP+1
    JR   NC,.FULL
    LD   (LL_DEPTH),A
    PUSH HL
    LD   A,C
    LD   E,A
    LD   D,0
    LD   HL,LL_STACK
    ADD  HL,DE
    EX   DE,HL
    POP  HL
    LD   C,B
    LD   B,0
    LDIR
    XOR  A
    RET

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,DE,HL
.PUSHSYM:
    LD   C,A
    LD   A,(LL_DEPTH)
    CP   LL_CAP
    JR   NC,.FULL
    LD   L,A
    LD   H,0
    LD   DE,LL_STACK
    ADD  HL,DE
    LD   (HL),C
    LD   HL,LL_DEPTH
    INC  (HL)
    XOR  A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
.POPSYM:
    LD   A,(LL_DEPTH)
    DEC  A
    LD   (LL_DEPTH),A
    LD   L,A
    LD   H,0
    LD   DE,LL_STACK
    ADD  HL,DE
    LD   A,(HL)
    OR   A
    RET

.FULL:
    CALL DG_RAISE
    DB   DG_LLCAP

LL_CEND:
