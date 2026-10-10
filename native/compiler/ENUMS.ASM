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

; Island after `enum`: retain the name, then nonempty member lines/end.
EN_DECL:
    CALL RO_NAME
    CALL EX_DECL
    LD   E,TK_EOL
    CALL PR_NEED
    LD   HL,0
    LD   (EN_HEAD),HL
    LD   (EN_COUNT),HL
.MEMBER:
    CALL PR_PEEK
    CP   TK_END
    JR   Z,.END
    CALL RO_NAME
    LD   HL,(EN_HEAD)
    CALL EN_FIND
    LD   A,DG_DUP
    JP   C,DG_NAMED
    LD   A,(EN_COUNT+1)
    OR   A
    LD   A,DG_EMEM
    JP   NZ,DG_ISSUE
    LD   BC,6
    CALL NH_ALLOC
    PUSH DE
    EX   DE,HL
    CALL TK_KEEP
    INC  HL
    LD   DE,(EN_COUNT)
    LD   (HL),E
    INC  DE
    LD   (EN_COUNT),DE
    INC  HL
    LD   DE,(EN_HEAD)
    LD   (HL),E
    INC  HL
    LD   (HL),D
    POP  HL
    LD   (EN_HEAD),HL
    LD   E,TK_EOL
    CALL PR_NEED
    JR   .MEMBER
.END:
    LD   HL,(EN_COUNT)
    LD   A,H
    OR   L
    LD   A,DG_EENUM
    JR   NZ,.NONEMPTY
    LD   HL,AC_DPOS
    JP   DG_AT
.NONEMPTY:
    LD   A,L                     ; Zero encodes the full 256 members.
    LD   (AG_NAUX),A
    LD   A,AG_KENUM
    LD   (AG_NKIND),A
    LD   HL,(EN_HEAD)
    LD   (AG_NDIM),HL
    LD   HL,1
    LD   (AG_NSIZE),HL
    CALL AG_ADD
    LD   C,A
    LD   B,0
    LD   D,SY_TYPE
    CALL EX_PREP
    CALL SY_CMT
    CALL PR_TAKE                 ; Consume end.
    LD   E,TK_EOL
    JP   PR_NEED

; A type name's payload BC. Resolve its qualified member as known enum.
; Non-enum names retain the existing wrong-class diagnostic.
EN_MEM:
    LD   A,C
    CALL AG_DESC                 ; Type names hold dynamic IDs; BC kept.
    LD   A,(HL)
    CP   AG_KENUM
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
