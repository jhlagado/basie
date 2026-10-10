; Nominal enums share the dynamic type table, but are byte scalars.
; Members live in the existing name heap: spelling word, length, ordinal,
; next word. Their names are qualified and never enter global hash chains.
; Declaration scratch reuses initializer scratch, unavailable concurrently.
EN_HEAD EQU AG_IBUF            ; Word: newest member.
EN_COUNT EQU AG_IBUF+2         ; Word: members seen, 1..256.

; A kept; carry iff a built-in scalar or a nominal enum. BC,DE,HL kept.
AG_SCAL:
    CP   AG_FIRST
    RET  C
    CP   AG_FIRST+AG_TCAP
    JR   NC,.OTHER
    PUSH BC
    PUSH DE
    PUSH HL
    LD   C,A
    CALL AG_DESC
    LD   A,(HL)
    CP   AG_KENUM
    LD   A,C
    POP  HL
    POP  DE
    POP  BC
    SCF
    RET  Z
.OTHER:
    OR   A
    RET

; A full type and D storage class -> D packed symbol information.
; BC,E,HL kept. Parameter flags are meaningful only for aggregates.
SY_KIND:
    CALL AG_SCAL
    JR   NC,.AGGR
    CP   AG_FIRST
    JR   C,.SCALAR
    LD   A,SY_ENUM
.SCALAR:
    RES  7,D                     ; Only aggregate parameter flags use bit 7.
    OR   D
    LD   D,A
    RET
.AGGR:
    SET  7,D
    RET

; Decode packed scalar A; HL is SY_GET's payload high byte. Registers
; other than A kept. The tag follows at HL+1.
EN_STYPE:
    AND  SY_TMASK
    CP   SY_ENUM
    RET  NZ
    INC  HL
    LD   A,(HL)
    DEC  HL
    RET

; Current token's spelling in member list HL; carry iff found, HL node.
EN_FIND:
    LD   A,H
    OR   L
    RET  Z
    CALL TK_SAME
    RET  C
    LD   DE,4
    ADD  HL,DE
    CALL WD_GET
    EX   DE,HL
    JR   EN_FIND

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; Island EnumDeclaration, after `enum`: the ENUMS overlay's entry (ED_RUN,
; ENDECL.ASM), run above NAMES through OV_XCALL.

EN_DECL:                       ; After `enum`.
    XOR  A                         ; Entry 0
    LD   B,OV_ENUMS                ; of ENUMS
    JP   OV_XCALL                  ; runs; it returns.

; A type name's payload BC. Resolve its qualified member as known enum.
; Non-enum names retain the existing wrong-class diagnostic.
EN_MEM:
    LD   A,D
    CP   SY_TYPE                ; A type name, not a pool (SY_GLOB too)?
    JR   NZ,.CLASS
    LD   A,C
    CALL AG_DESC                 ; Type names hold dynamic IDs; BC kept.
    LD   A,(HL)
    CP   AG_KENUM
.CLASS:
    LD   A,DG_CLASS
    JP   NZ,DG_NAMED
    PUSH BC                     ; Retain nominal ID.
    LD   HL,(TK_POS)
    PUSH HL                     ; Only the source position survives the peek.
    CALL PR_PEEK
    CP   TK_DOT
    JR   Z,.QUAL
    POP  HL
    PUSH HL
    LD   A,DG_CLASS
    CALL DG_WORD                ; Recover the typename for the diagnostic.
    POP  HL
    JP   DG_HERE
.QUAL:
    POP  HL
    CALL PR_TAKE
    CALL RO_NAME
    POP  BC
    PUSH BC
    LD   A,C
    CALL AG_DESC
    INC  HL
    INC  HL
    CALL WD_GET
    EX   DE,HL
    CALL EN_FIND
    JP   NC,SY_UNDEF
    INC  HL
    INC  HL
    INC  HL
    LD   L,(HL)
    LD   H,0
    POP  BC
    LD   B,C
    SET  7,B
    JP   EX_LIT
