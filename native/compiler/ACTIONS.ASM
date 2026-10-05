; Explicit semantic actions for the complete Stage 7 packed LL(1) grammar.
; These routines never select grammar productions. They consume only retained
; expression/type-directed external islands declared by the generated grammar.

; Aggregate initializer staging is dead while a routine body is parsed, so
; the for/flow action scratch safely reuses its first thirteen bytes.
AC_MODE EQU  AG_IBUF
AC_DELTA EQU  AC_MODE+1
AC_WHERE EQU  AC_DELTA+2
AC_FLOWS EQU  AC_WHERE+2
AC_WEND EQU  AC_FLOWS+CT_FCAP

; --------------------------------------------------------- retained parsers

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_FOLD:
    LD   A,SY_EXACT
    CALL EX_CONST
    JR   AC_STASH

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_EXPR:
    LD   A,(EX_WANT)
    CALL EX_RUN
AC_STASH:
    LD   (EX_RMETA),A
    LD   (EX_RVAL),HL
    OR   A
    RET

;@ROUTINE OUT A,B,DE,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,HL
AC_BY:
    CALL CT_STEP
    LD   A,(AC_MODE)
    OR   B
    LD   (AC_MODE),A
    LD   (AC_DELTA),DE
    OR   A
    RET

; The declared type has already selected the initializer shape. This external
; island retains the recursive, type-directed aggregate initializer machinery.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
AC_IMAGE:
    LD   A,(AC_DINFO)
    LD   B,A
    PUSH BC
    CALL AG_PARSE
    POP  BC
    LD   A,B
    LD   (AC_DINFO),A
    OR   A
    RET

AC_STRAY:
    CALL DG_RAISE
    DB   DG_END

; --------------------------------------------------------------- type actions

; A is the logical action ordinal for the contiguous u8/u16/Boolean family.
AC_TYPE:
    SUB  GR_U8-1
AC_USE:
    LD   (AG_CTYPE),A
    OR   A
    RET

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL,IX,IY
AC_NAMED:
    CALL SY_GET
    LD   D,A
    LD   (AC_DINFO),A
    LD   (AC_DVAL),BC
    AND  SY_TYPE+SY_AGGR
    CP   SY_TYPE
    JP   NZ,AG_EFORM
    LD   A,C
    JR   AC_USE

AC_BOUND:
AC_U16:
    LD   A,SY_U16
    JP   AC_WANT

; Return the checked, positive, byte-sized constant bound in HL.
;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,IX,IY
AC_COUNT:
    LD   A,(EX_RMETA)
    LD   D,A
    AND  SY_KNOWN
    JP   Z,AG_EFORM
    LD   E,SY_U16
    LD   A,D
    CALL EX_FITS
    LD   HL,(EX_RVAL)
    LD   A,H
    OR   L
    JP   Z,AG_EFORM
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
AC_STR:
    CALL AC_COUNT
    LD   A,H
    OR   A
    JP   NZ,AG_ESTR
    LD   A,L
    CP   254
    JP   NC,AG_ESTR
    LD   A,L
    LD   (AG_NAUX),A
    LD   (AG_NDIM),HL
    LD   A,AG_KSTR
    LD   (AG_NKIND),A
    INC  HL
    INC  HL
    LD   (AG_NSIZE),HL
AC_REUSE:
    CALL AG_REUSE
    JR   AC_USE

; `string[]` is a parameter-only view rather than an interned object type.
AC_OPEN:
    LD   A,AG_VIEW
    JR   AC_USE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
AC_ARRAY:
    LD   A,(AG_CTYPE)
    CP   AG_VIEW
    JP   Z,AG_EFORM
    CP   AG_FIRST
    JR   C,.ELEMENT
    PUSH AF
    CALL AG_DESC
    LD   A,(HL)
    CP   AG_KARR
    JP   Z,AG_ENEST
    POP  AF
.ELEMENT:
    LD   (AG_NAUX),A
    CALL AC_COUNT
    LD   (AG_NDIM),HL
    LD   B,H
    LD   C,L
    LD   A,(AG_NAUX)
    CALL AG_SIZE
    LD   D,H
    LD   E,L
    LD   HL,0
.SIZELOOP:
    ADD  HL,DE
    JP   C,AG_EDATA
    CALL AG_FITRW
    DEC  BC
    LD   A,B
    OR   C
    JR   NZ,.SIZELOOP
    LD   (AG_NSIZE),HL
    LD   A,AG_KARR
    LD   (AG_NKIND),A
    JR   AC_REUSE

; --------------------------------------------------------- scalar constants

AC_NAME EQU  EX_DECL

AC_WANT:
    LD   (EX_WANT),A
    OR   A
    RET

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,IX,IY
AC_VALUE:
    LD   HL,(EX_RVAL)
    LD   A,(EX_RMETA)
    LD   D,A
    AND  SY_KNOWN
    JP   Z,EX_ETYPE
    LD   A,D
    AND  SY_TMASK
    CP   SY_BOOL
    LD   A,SY_EXACT
    JR   NZ,.TYPEOK
    LD   A,SY_BOOL
.TYPEOK:
    LD   (AC_DINFO),A
    LD   HL,(EX_RVAL)
    LD   (AC_DVAL),HL
    OR   A
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AC_CONST:
    LD   A,(AC_DINFO)
    OR   SY_CONST
    LD   D,A
    LD   BC,(AC_DVAL)
    CALL EX_PREP
    JP   SY_CMT

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_ROCMT:
    CALL TG_HOME
    LD   (AC_DINFO),A
    CALL TG_LENAT
    PUSH HL
    LD   C,(HL)
    INC  HL
    LD   B,(HL)
    LD   (AC_DVAL),BC
    LD   HL,(AG_OSIZE)
    ADD  HL,BC
    LD   E,L
    LD   D,H
    POP  HL
    LD   (HL),E
    INC  HL
    LD   (HL),D
    LD   A,(AC_DINFO)
    RLCA
    RLCA
    RLCA
    RLCA
    OR   SY_AGGR+SY_CONST
    LD   (AC_DINFO),A
    LD   BC,(AG_ROLEN)
    LD   D,SY_AGGR+SY_CONST
    LD   A,(AC_DINFO)
    LD   D,A
    LD   BC,(AC_DVAL)
    CALL EX_PREP
    LD   BC,(AG_ROLEN)
    LD   HL,(AG_OSIZE)
    ADD  HL,BC
    LD   DE,(AG_DLEN)
    ADD  HL,DE
    CALL AG_FITRO
    OR   A
    SBC  HL,DE
    LD   (AG_ROLEN),HL
    LD   HL,AG_DATA
    ADD  HL,DE
    ADD  HL,BC
    EX   DE,HL
    LD   HL,AG_IBUF
    LD   BC,(AG_OSIZE)
    LDIR
    LD   A,(AG_CTYPE)
    JP   SY_TAG

AC_CLAIM EQU  EX_KEEP

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AC_PROVE:
    CALL AC_RESUB
    LD   A,(EX_RMETA)
    AND  SY_KNOWN+SY_TMASK
    CP   SY_KNOWN+SY_BOOL
    JR   NZ,.BADTYPE
    LD   A,(EX_RVAL)
    OR   A
    RET  NZ
    CALL DG_RAISE
    DB   DG_FALSE
.BADTYPE:
    CALL DG_RAISE
    DB   DG_CLASH

; ------------------------------------------------------ program declarations

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
AC_VAR:
    LD   A,(AG_CTYPE)
AC_OBJ:
    CP   AG_VIEW
    JP   Z,AG_EFORM
    LD   (AC_DINFO),A
    CALL AG_SIZE
    LD   (AG_OSIZE),HL
    LD   (AG_OEND),HL
    LD   HL,0
    LD   (AG_OPOS),HL
    CALL AG_ZERO
    XOR  A
    LD   (AG_LEVEL),A
    LD   (AG_GIVEN),A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
AC_ROOBJ:
    LD   A,(AG_CTYPE)
    CP   AG_FIRST
    JP   C,EX_ETYPE
    JR   AC_OBJ

AC_EXACT:
    LD   A,1
    LD   (AG_GIVEN),A
    LD   HL,(AG_OPOS)
    LD   DE,(AG_OEND)
    OR   A
    SBC  HL,DE
    JP   NZ,AG_ECNT
    OR   A
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_ALLOC:
    LD   A,(AG_GIVEN)
    OR   A
    JR   Z,.BSS
    JR   AC_DATA
.BSS:
    JR   AC_BSS
AC_ENTER:
    PUSH BC
    LD   A,(AC_DINFO)
    CP   AG_FIRST
    JR   C,.SCALAR
    LD   D,SY_AGLOB
    JR   .PREPARE
.SCALAR:
    OR   SY_GLOB
    LD   D,A
.PREPARE:
    CALL EX_PREP
    POP  BC
    LD   A,(AC_DINFO)
    CALL SY_TAG
    OR   A
    RET

; Return the absolute target address of one initialized program object in BC.
; The complete prepared bytes are appended to the rodata-backed data image.
AC_DATA:
    LD   DE,(AG_DLEN)
    CALL AC_GROW
    PUSH HL
    LD   DE,(AG_ROLEN)
    ADD  HL,DE
    CALL AG_FITRW
    POP  HL
    LD   (AG_DLEN),HL
    LD   BC,(AG_ROLEN)
    LD   A,B
    OR   C
    JR   Z,.SHIFTED
    LD   HL,AG_DATA
    LD   DE,(AG_OPOS)
    ADD  HL,DE
    ADD  HL,BC
    DEC  HL
    LD   DE,(AG_OSIZE)
    PUSH HL
    ADD  HL,DE
    EX   DE,HL
    POP  HL
    LDDR
.SHIFTED:
    LD   A,(AC_DINFO)
    CALL AG_SIZE
    LD   B,H
    LD   C,L
    LD   HL,AG_IBUF
    LD   DE,(AG_OPOS)
    PUSH HL
    LD   HL,AG_DATA
    ADD  HL,DE
    EX   DE,HL
    POP  HL
    LDIR
    LD   BC,(AG_OPOS)
; Target transcripts retain a segment-relative offset. Bit 15 is
; clear for initialized data and set for BSS.
    OR   A
    JR   AC_ENTER

; Return the absolute target address of one default-initialized object in BC.
AC_BSS:
    LD   DE,(PR_BSS)
    CALL AC_GROW
    LD   (PR_BSS),HL
    LD   B,D
    LD   C,E
    SET  7,B
    OR   A
    JP   AC_ENTER

; Add the current object extent to the selected segment length in DE. Return
; the old offset in DE and the checked mathematical end in HL.
;@ROUTINE IN DE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AC_GROW:
    LD   (AG_OPOS),DE
    LD   A,(AC_DINFO)
    CALL AG_SIZE
    LD   DE,(AG_OPOS)
    ADD  HL,DE
AC_ROOM:
; Initialized data and BSS use the same exact 1 KiB extent rule and diagnostic
; as complete aggregate objects.
    JP   AG_FITRW

; ---------------------------------------------------------- record metadata

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
AC_REC:
    CALL EX_DECL
    LD   A,(AG_TCNT)
    CP   AG_TCAP
    JP   NC,AG_EMETA
    LD   A,(AG_RCNT)
    CP   AG_RCAP
    JP   NC,AG_EMETA
    LD   A,(AG_FCNT)
    LD   (AG_CFIDX),A
    XOR  A
    LD   (AG_CFCNT),A
    LD   H,A
    LD   L,A
    LD   (AG_CSIZE),HL
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
AC_FIELD:
    CALL AG_FRESH
    LD   A,(AG_FCNT)
    LD   B,A
    LD   A,(AG_CFCNT)
    ADD  A,B
    CP   AG_FCAP
    JP   NC,AG_EMETA
    PUSH AF
    CALL AG_FIELD
    CALL TK_KEEP
    POP  AF
    OR   A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
AC_PLACE:
    LD   A,(AG_CTYPE)
    CP   AG_VIEW
    JP   Z,AG_EFORM
    LD   A,(AG_FCNT)
    LD   B,A
    LD   A,(AG_CFCNT)
    ADD  A,B
    CALL AG_FIELD
    INC  HL
    INC  HL
    INC  HL
    LD   A,(AG_CTYPE)
    LD   (HL),A
    INC  HL
    LD   DE,(AG_CSIZE)
    LD   (HL),E
    INC  HL
    LD   (HL),D
    LD   A,(AG_CTYPE)
    PUSH DE
    CALL AG_SIZE
    POP  DE
    ADD  HL,DE
    JP   C,AG_EDATA
    CALL AG_FITRW
    LD   (AG_CSIZE),HL
    LD   HL,AG_CFCNT
    INC  (HL)
    XOR  A
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AC_RECOK:
    LD   A,(AG_CFCNT)
    OR   A
    JP   Z,AG_EVOID
    LD   A,AG_KREC
    LD   (AG_NKIND),A
    LD   A,(AG_RCNT)
    LD   (AG_NAUX),A
    LD   HL,0
    LD   (AG_NDIM),HL
    LD   HL,(AG_CSIZE)
    LD   (AG_NSIZE),HL
    CALL AG_ADD
    LD   (AG_CTYPE),A
    LD   A,(AG_RCNT)
    ADD  A,A
    LD   E,A
    LD   D,0
    LD   HL,AG_RTAB
    ADD  HL,DE
    LD   A,(AG_CFIDX)
    LD   (HL),A
    INC  HL
    LD   A,(AG_CFCNT)
    LD   (HL),A
    LD   D,SY_RTYPE
    LD   A,(AG_CTYPE)
    LD   C,A
    LD   B,0
    CALL EX_PREP
    CALL SY_CMT
    LD   A,(AG_CFCNT)
    LD   HL,AG_FCNT
    ADD  A,(HL)
    LD   (HL),A
    LD   HL,AG_RCNT
    INC  (HL)
    XOR  A
    RET

; ----------------------------------------------------- Stage 7 routines/main

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
AC_EARLY:
    LD   A,(RO_CUR)
    INC  A
    RET  NZ
    CALL DG_RAISE
    DB   DG_EOF

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,HL,IX,IY
AC_MAIN:
    LD   A,(RO_CUR)
    INC  A
    JR   Z,.FORWARDS
    LD   A,(RO_MFLAG)
    AND  RO_FOPEN
    JR   NZ,.PARTIAL
    JR   .NOMAIN
.FORWARDS:
    LD   A,(RO_RCNT)
    LD   B,A
    XOR  A
    LD   C,A
.LOOP:
    LD   A,B
    OR   A
    RET  Z
    LD   A,C
    CALL RO_SUBAT
    LD   DE,RO_RFLAG
    ADD  HL,DE
    LD   A,(HL)
    AND  RO_FOPEN
    JR   NZ,.PARTIAL
    INC  C
    DEC  B
    JR   .LOOP
.NOMAIN:
    CALL DG_RAISE
    DB   DG_TOP
.PARTIAL:
    CALL DG_RAISE
    DB   DG_UNMET

; The grammar deliberately treats the lexeme `main` as the same NAME token as
; ordinary routine names. This action is the one semantic discriminator.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_SUB:
    JP   EX_KEEP

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AC_RESUB:
    CALL EX_RENEW
    LD   HL,AC_DPOS
    LD   DE,TK_POS
    CALL PR_COPY
    OR   A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AC_CLEAR:
    XOR  A
    LD   (RO_CPCNT),A
    LD   (RO_CTYPE),A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
AC_SIG:
    CALL AC_RESUB
    CALL AC_EARLY
    CALL EX_MAIN
    JR   C,.MAIN
    LD   A,(RO_RCNT)
    CP   RO_RCAP
    JR   NC,.FULL
    CALL RO_FRESH
    LD   A,(RO_RCNT)
    LD   (RO_CUR),A
    CALL RO_SUBAT
    CALL TK_KEEP
    INC  HL
    LD   A,(RO_PCNT)
    LD   (HL),A
    LD   (RO_CPIDX),A
    CALL AC_CLEAR
    CALL TG_PACK
    LD   (RO_CFLAG),A
    RET
.MAIN:
    CALL TG_ENTRY
    LD   A,(RO_MFLAG)
    AND  RO_FOPEN
    JP   NZ,EX_EDUP
    CALL RO_FRESH
    LD   A,$FF
    LD   (RO_CUR),A
    CALL AC_CLEAR
    LD   A,RO_FMAIN
    CALL TG_PACK
    LD   (RO_CFLAG),A
    RET
.FULL:
    CALL DG_RAISE
    DB   DG_PROCS

; A forward uses the ordinary signature builder, then publishes that sole
; signature without opening a body or emitting code.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
AC_PROTO:
    CALL AC_SIG
    LD   A,(RO_CFLAG)
    OR   RO_FOPEN
    LD   (RO_CFLAG),A
    OR   A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
AC_SEAL:
    LD   A,(RO_CUR)
    INC  A
    JR   Z,.MAIN
    DEC  A
    CALL AC_PUB
    XOR  A
    RET
.MAIN:
    LD   A,(RO_CFLAG)
    LD   (RO_MFLAG),A
    XOR  A
    LD   (RO_CUR),A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
AC_PARAM:
    LD   A,(RO_CUR)
    INC  A
    JR   Z,.MAIN
    CALL RO_VET
    LD   HL,AC_DNAME
    CALL TK_KEEP
    OR   A
    RET
.MAIN:
    CALL DG_RAISE
    DB   DG_RPAR

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
AC_JOIN:
    CALL EX_RENEW
    LD   A,(AG_CTYPE)
    JP   RO_ENROL

AC_GIVES:
    LD   A,(RO_CUR)
    INC  A
    JR   Z,AC_ELINE
    RET

AC_GIVEN:
    LD   A,(AG_CTYPE)
    CP   AG_VIEW
    JP   Z,AG_EFORM
    LD   (RO_CTYPE),A
    OR   A
    RET

AC_FAILS:
    LD   A,(RO_CFLAG)
    OR   RO_FFAIL
    LD   (RO_CFLAG),A
    OR   A
    RET
AC_ELINE:
    CALL DG_RAISE
    DB   DG_EOL

; Open the abbreviated body of one exact incomplete forward and recover its
; sole stored signature, including the original parameter spellings.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_IMPL:
    CALL AC_RESUB
    CALL AC_EARLY
    CALL EX_MAIN
    JR   C,.MAIN
    CALL RO_FIND
    JR   NZ,.MISSING
    LD   (RO_CUR),A
    CALL RO_SUBAT
    LD   DE,RO_RPIDX
    ADD  HL,DE
    LD   A,(HL)
    LD   (RO_CPIDX),A
    INC  HL
    LD   A,(HL)
    LD   (RO_CPCNT),A
    INC  HL
    LD   A,(HL)
    LD   (RO_CTYPE),A
    INC  HL
    LD   A,(HL)
    LD   (RO_DEST),A
    INC  HL
    LD   A,(HL)
    BIT  2,A
    JP   Z,EX_EDUP
    LD   D,A
    PUSH AF
    PUSH HL
    CALL TG_MUST
    POP  HL
    POP  AF
    AND  $FB
    LD   (HL),A
    LD   (RO_CFLAG),A
    JR   AC_BEGIN
.MAIN:
    CALL TG_ENTRY
    LD   A,(RO_MFLAG)
    BIT  2,A
    JR   Z,.MISSING
    AND  $FB
    LD   (RO_CFLAG),A
    LD   (RO_MFLAG),A
    CALL AC_CLEAR
    DEC  A
    LD   (RO_CUR),A
    JP   AC_ENTRY
.MISSING:
    CALL DG_RAISE
    DB   DG_UNDEF

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_BODY:
    LD   A,(RO_CUR)
    INC  A
    JP   Z,AC_ENTRY
    DEC  A
    CALL AC_PUB
    JR   AC_BEGIN

;@ROUTINE IN A OUT A,BC,DE,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
AC_PUB:
    CALL RO_SUBAT
    LD   DE,RO_RPCNT
    ADD  HL,DE
    LD   A,(RO_CPCNT)
    LD   (HL),A
    INC  HL
    LD   A,(RO_CTYPE)
    LD   (HL),A
    INC  HL
    LD   A,(RO_CUR)
    ADD  A,RO_LBASE
    LD   (HL),A
    LD   (RO_DEST),A
    INC  HL
    LD   A,(RO_CFLAG)
    LD   (HL),A
    LD   HL,RO_RCNT
    INC  (HL)
    RET
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AC_SCOPE:
    LD   A,(SY_CNT)
    LD   (RO_GLOBS),A
    XOR  A
    LD   (SY_LSLOT),A
    LD   (CT_DEPTH),A
    RET
AC_BEGIN:
    CALL AC_SCOPE
    LD   A,(RO_CTYPE)
    OR   A
    LD   A,CT_RVAL
    JR   NZ,.KINDOK
    XOR  A
.KINDOK:
    LD   (CT_RKIND),A
    LD   A,(RO_CTYPE)
    LD   (CT_RTYPE),A
    LD   A,1
    LD   (CT_FALLS),A
    LD   A,OP_PROC
    CALL TR_OPER
    LD   A,(RO_DEST)
    CALL TR_PUT
    LD   A,(RO_CPCNT)
    CALL TR_PUT
    LD   A,(RO_CFLAG)
    CALL TG_SPLIT
    CALL TR_PUT
    LD   A,(RO_CPCNT)
    LD   B,A
    LD   A,(RO_CPIDX)
    LD   D,A
    XOR  A
    LD   E,A
.BINDLOOP:
    LD   A,B
    OR   A
    RET  Z
    CALL RO_DISP
    LD   A,D
    PUSH DE
    PUSH BC
    CALL RO_BIND
    POP  BC
    POP  DE
    INC  D
    INC  E
    DEC  B
    JR   .BINDLOOP

AC_ENTRY:
    LD   A,(RO_CFLAG)
    LD   (RO_MFLAG),A
    LD   A,OP_ENTRY
    CALL TR_OPER
    LD   A,(RO_CFLAG)
    CALL TR_PUT
    LD   A,(RO_CFLAG)
    CALL TG_SPLIT
    CALL TR_PUT
    CALL AC_SCOPE
    LD   (RO_CTYPE),A
    LD   (CT_RKIND),A

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AC_LIVE:
    LD   A,1
    LD   (CT_FALLS),A
    OR   A
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_END:
    LD   A,(RO_CUR)
    INC  A
    JR   Z,AC_CLOSE
    LD   A,(RO_CTYPE)
    OR   A
    JR   Z,.EMIT
    LD   A,(CT_FALLS)
    OR   A
    JP   NZ,EX_EFLOW
.EMIT:
    CALL AC_ENDOP
    LD   A,(RO_CTYPE)
    CALL TR_PUT
    LD   A,(RO_GLOBS)
    LD   (SY_CNT),A
    XOR  A
    LD   (SY_LSLOT),A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
AC_ENDOP:
    LD   A,(RO_CFLAG)
    AND  RO_FFAIL
    LD   A,OP_ENDP
    JR   Z,.PICKED
    LD   A,OP_ENDF
.PICKED:
    JP   TR_OPER
AC_CLOSE:
    CALL AC_ENDOP
    XOR  A
    JP   TR_PUT

; ------------------------------------------------------ recoverable failure

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
AC_FAIL:
    LD   A,(RO_CFLAG)
    AND  RO_FFAIL
    JR   Z,AC_ELEAK
    LD   HL,(TK_POS)
    LD   (RO_FPOS),HL
    LD   A,SY_U8
    JP   AC_WANT

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_THROW:
    LD   E,SY_U8
    CALL AC_VALOK
    LD   A,OP_FAIL
.EMIT:
    CALL TR_OPER
    LD   HL,(RO_FPOS)
    LD   A,L
    CALL TR_PUTHL
    LD   A,H
    CALL TR_PUT
AC_DEAD:
    XOR  A
    LD   (CT_FALLS),A
    RET

; Validate one scalar fail/return value and reject an unconsumed nested
; recoverable failure.
;@ROUTINE IN E OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,IX,IY
AC_VALOK:
    LD   A,(EX_RMETA)
    LD   HL,(EX_RVAL)
    CALL EX_FITS
    JP   AC_SAFE
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
AC_ELEAK:
    CALL DG_RAISE
    DB   DG_LEAK

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Both callers have already observed a nonzero RO_PEND. The
; generic entry checks the token; the selected entry reuses its caller's peek.
AC_RELAY:
    CALL PR_PEEK
    CP   TK_ELSE
    JR   NZ,AC_ELEAK
AC_PASS:
    LD   A,(RO_CFLAG)
    AND  RO_FFAIL
    JR   Z,AC_ELEAK
    CALL PR_TAKE
    LD   E,TK_FAIL
    CALL PR_NEED
    CALL PR_PEEK
    CP   TK_HANDL
    JR   Z,AC_ELEAK
    CP   TK_ELSE
    JR   Z,AC_ELEAK
    LD   A,RO_MPASS
.MODE:
    LD   HL,(RO_MODEP)
    LD   (HL),A
    INC  HL
    INC  HL
    LD   A,(RO_KEPT)
    LD   (HL),A
AC_DROP:
    XOR  A
    LD   (RO_PEND),A
    LD   (RO_KEPT),A
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AC_ROUTE:
    LD   A,(RO_PEND)
    OR   A
    JR   NZ,.PENDING
    LD   (RO_KEPT),A
    CALL PR_PEEK
    CP   TK_ELSE
    JR   Z,AC_ELEAK
    CP   TK_HANDL
    JR   Z,AC_ELEAK
    OR   A
    RET
.PENDING:
    CALL PR_PEEK
    CP   TK_ELSE
    JR   Z,AC_PASS
    CP   TK_HANDL
    JR   NZ,AC_ELEAK
    LD   B,CT_KTRAP
    CALL CT_OPEN
    CALL CT_EXIT
    LD   HL,(RO_MODEP)
    LD   (HL),RO_MTRAP
    LD   B,CT_FDEST
    CALL CT_FIELD
    LD   C,(HL)
    LD   HL,(RO_MODEP)
    INC  HL
    LD   (HL),C
    INC  HL
    LD   A,(RO_KEPT)
    LD   (HL),A
    JR   AC_DROP

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_FIND:
    CALL SY_GET
    LD   (AC_DINFO),A
    LD   (AC_DVAL),BC
    LD   D,A
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_ONERR:
    CALL AC_FIND
    CALL EX_CLASS
    JP   Z,EX_ETYPE
    CP   SY_LOCAL
    JR   NZ,.CHECKED
    CALL CT_GUARD
.CHECKED:
    CALL EX_DTYPE
    CP   SY_U8
    JP   NZ,EX_ETYPE
    LD   B,CT_FEXIT
    CALL CT_FIELD
    LD   C,(HL)
    LD   A,OP_HSKIP
    CALL AC_EMITC
    LD   B,CT_FDEST
    CALL CT_FIELD
    LD   C,(HL)
    LD   A,OP_HOPEN
    CALL AC_EMITC
    LD   A,(AC_DINFO)
    CALL TR_PUT
    AND  SY_CMASK
    CP   SY_GLOB
    LD   HL,(AC_DVAL)
    JR   Z,.GLOBAL
    LD   A,L
    CALL TR_PUT
    JR   .DONE
.GLOBAL:
    CALL RO_EMITW
.DONE:
    JP   AC_LIVE

;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
AC_EMITC:
    CALL TR_OPER
    LD   A,C
    JP   TR_PUT

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_NOERR:
    LD   B,CT_FEXIT
    CALL CT_FIELD
    LD   C,(HL)
    LD   A,OP_HDONE
    CALL AC_EMITC
    LD   A,1
    JP   AC_MERGE

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
AC_SAFE:
    LD   A,(RO_PEND)
    OR   A
    RET  Z
    JP   AC_ELEAK

; ------------------------------------------------------------- local scalars

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AC_LOCAL:
    LD   A,(AG_CTYPE)
    OR   SY_LOCAL
    LD   (AC_DINFO),A
    LD   A,(SY_LSLOT)
    LD   C,A
    LD   B,0
    LD   (AC_DVAL),BC
    PUSH BC
    LD   A,(AC_DINFO)
    LD   D,A
    CALL EX_PREP
    POP  BC
    CALL EX_DTYPE
    CALL EX_LOCAL
AC_TOVAR:
    CALL EX_DTYPE
    JP   AC_WANT

AC_INIT:
    CALL EX_DTYPE
    JP   AC_WANT

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
AC_ZERO:
    LD   A,1
    LD   (EX_LIVE),A
    LD   A,OP_LIT16
    CALL EX_EMIT
    LD   HL,0
    CALL EX_EMITW
    CALL EX_DTYPE
    OR   SY_KNOWN
    LD   (EX_RMETA),A
    LD   HL,0
    LD   (EX_RVAL),HL
    OR   A
    RET

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,IX,IY
AC_ADOPT:
    CALL AC_FIT
    LD   A,(RO_PEND)
    OR   A
    JP   NZ,AC_RELAY
    CALL PR_PEEK
    CP   TK_ELSE
    JP   Z,AC_ELEAK
    OR   A
    RET

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,IX,IY
AC_FIT:
    CALL EX_DTYPE
    LD   E,A

;@ROUTINE IN E OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,IX,IY
AC_FITTO:
    LD   HL,(EX_RVAL)
    LD   A,(EX_RMETA)
    JP   EX_FITS

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_BIND:
    LD   A,(AC_DINFO)
    LD   D,A
    LD   A,(AC_DVAL)
    LD   C,A
    CALL EX_STORE
    CALL SY_CMT
    CALL EX_DTYPE
    CALL EX_WIDTH
    LD   HL,SY_LSLOT
    ADD  A,(HL)
    LD   (HL),A
    OR   A
    RET

; ------------------------------------------------------------ simple statements

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_STMT:
    CALL PR_TAKE
    LD   HL,(TK_POS)
    LD   (EX_CPOS),HL
    LD   (RO_DPOS),HL
    CALL RO_LIB
    JR   NC,.ORDINARY
    CP   RO_ERRS
    JP   NC,EX_ETYPE
    LD   C,0
    CALL RO_SERVE
    JP   AC_ROUTE
.ORDINARY:
    CALL RO_FIND
    JR   NZ,.ASSIGN
    LD   C,0
    CALL RO_CALL
    JP   AC_ROUTE
.ASSIGN:
    CALL AC_FIND
    AND  SY_AGGR
    JP   NZ,RO_LET
    LD   A,D
    CALL EX_CLASS
    CP   SY_LOCAL
    JR   NZ,.CHECKED
    CALL CT_GUARD
.CHECKED:
    LD   A,D
    AND  SY_CMASK
    JP   Z,EX_ETYPE
    CALL PR_EQUAL
    CALL EX_DTYPE
    CALL EX_RUN
    LD   D,A
    CALL EX_DTYPE
    LD   E,A
    LD   A,D
    CALL EX_FITS
    CALL AC_ROUTE
    LD   BC,(AC_DVAL)
    LD   A,(AC_DINFO)
    LD   D,A
    JP   EX_STORE
AC_RET:
    LD   A,(RO_CTYPE)
    OR   A
    RET  Z
    CP   AG_FIRST
    RET  NC
    JP   AC_WANT

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_YIELD:
    LD   A,(RO_CTYPE)
    OR   A
    JP   Z,EX_EFLOW
    CP   AG_FIRST
    JR   NC,.AGGR
    CALL EX_RUN
    JP   AC_STASH
.AGGR:
    CALL RO_AGGR
    LD   (RO_OTYPE),A
    OR   A
    RET

AC_RETOP:
    LD   A,(RO_CTYPE)
    OR   A
    JP   Z,EX_EFLOW
    CP   AG_FIRST
    JR   NC,.AGGR
    LD   E,A
    CALL AC_VALOK
    LD   A,(RO_CFLAG)
    AND  RO_FFAIL
    LD   A,OP_RET
    JR   Z,.SCALAR
    LD   A,OP_RETF
.SCALAR:
    CALL TR_OPER
    JR   AC_RETOK
.AGGR:
    LD   D,A
    LD   A,(RO_OTYPE)
    CP   D
    JP   NZ,EX_ETYPE
    CALL AC_SAFE
    LD   A,(RO_CFLAG)
    AND  RO_FFAIL
    LD   A,OP_RETA
    JR   Z,.AGGROP
    LD   A,OP_RETAF
.AGGROP:
    CALL TR_OPER
AC_RETOK:
    JP   AC_DEAD

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_BARE:
    LD   A,(RO_CTYPE)
    OR   A
    JP   NZ,EX_EFLOW
    CALL AC_ENDOP
    XOR  A
    CALL TR_PUT
    JR   AC_RETOK

; A is the logical action ordinal. The two ordinals and tokens are contiguous.
AC_GOTO:
    DEC  A
.TRANSFER:
    LD   (AC_DINFO),A
    CALL CT_LOOP
    LD   DE,CT_FEXIT
    LD   A,(AC_DINFO)
    CP   TK_EXIT
    JR   Z,.PICKED
    LD   DE,CT_FCONT
.PICKED:
    ADD  HL,DE
    LD   C,(HL)
    JP   CT_JUMP

; ---------------------------------------------------------- structured flow

; Save the enclosing statement sequence's fallthrough bit, then push the
; control-frame kind supplied in B.
;@ROUTINE IN B OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C
AC_NEST:
    LD   A,(CT_DEPTH)
    CP   CT_FCAP
    JP   NC,CT_EDEEP
    CALL AC_FLOW
    LD   A,(CT_FALLS)
    LD   (HL),A
    LD   A,B
    JP   CT_PUSH

;@ROUTINE OUT A,DE,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
AC_FLOW:
    LD   A,(CT_DEPTH)
    LD   E,A
    LD   D,0
    LD   HL,AC_FLOWS
    ADD  HL,DE
    RET

; The frame has already been popped. Restore its enclosing sequence bit.
;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C
AC_OUTER:
    CALL AC_FLOW
    LD   A,(HL)
    LD   (CT_FALLS),A
    OR   A
    RET

; A is the completed compound statement's fallthrough bit.
;@ROUTINE IN A OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C
AC_MERGE:
    LD   B,A
    CALL CT_POP
    CALL AC_FLOW
    LD   A,(HL)
    AND  B
    LD   (CT_FALLS),A
    OR   A
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_BOOL:
    LD   E,SY_BOOL
AC_CHECK:
    CALL AC_SAFE
    JP   AC_FITTO

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_IF:
    LD   B,CT_KIF
    CALL AC_NEST
    CALL CT_EXIT
    CALL CT_LABEL
    LD   DE,CT_FVAR-CT_FDEST
    ADD  HL,DE
    LD   (HL),1
AC_COND:
    LD   A,SY_BOOL
    JP   AC_WANT

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_THEN:
    CALL AC_BOOL
    LD   B,CT_FDEST

;@ROUTINE IN B OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_TEST:
    CALL CT_FIELD
    LD   C,(HL)
    CALL CT_IFNOT
AC_LIVEN:
    JP   AC_LIVE

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_ARM:
    CALL CT_NOTE
    LD   B,CT_FEXIT
    CALL CT_FIELD
    LD   C,(HL)
    CALL CT_JUMP
    CALL CT_TOP
    INC  HL
    LD   C,(HL)
    JP   CT_PLACE

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_ELIF:
    CALL AC_ARM
    CALL CT_LABEL
    JR   AC_COND

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_ELSE:
    CALL AC_ARM
    JR   AC_LIVEN

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C
AC_TOTAL:
    CALL CT_NOTE
    LD   B,CT_FMODE
    CALL CT_FIELD
    LD   (HL),1
    XOR  A
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_PART:
    CALL CT_NOTE
    CALL CT_TOP
    INC  HL
    LD   C,(HL)
    JP   CT_PLACE

; B selects a field in the active control frame. All callers have already
; established that frame; the helper preserves their existing precondition.
;@ROUTINE IN B OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_LABEL:
    CALL CT_FIELD
    LD   C,(HL)
    JP   CT_PLACE

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_ENDIF:
    LD   B,CT_FEXIT
    CALL AC_LABEL
    CALL CT_TOP
    PUSH HL
    LD   DE,CT_FVAR
    ADD  HL,DE
    LD   A,(HL)
    POP  HL
    LD   DE,CT_FMODE
    ADD  HL,DE
    AND  (HL)
    XOR  1
    JP   AC_MERGE

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_WHILE:
    LD   B,CT_KLOOP
    CALL CT_OPEN
    INC  HL
    LD   (HL),C
    CALL CT_EXIT
    CALL CT_TOP
    INC  HL
    LD   C,(HL)
    CALL CT_PLACE
    JP   AC_COND

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_DO:
    CALL AC_BOOL
    LD   B,CT_FEXIT
    JP   AC_TEST

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_LOOP:
    LD   B,CT_FCONT
    CALL CT_FIELD
    LD   C,(HL)
    CALL CT_JUMP
    LD   B,CT_FEXIT
    CALL AC_LABEL
AC_LEAVE:
    CALL CT_POP
    JP   AC_OUTER

; -------------------------------------------------------------- counted loop

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_FOR:
    LD   HL,(TK_POS)
    LD   (AC_WHERE),HL
    CALL AC_FIND
    AND  SY_CMASK
    CP   SY_LOCAL
    JP   NZ,CT_EVAR
    LD   A,D
    AND  SY_TMASK
    CP   SY_BOOL
    JP   Z,CT_EVAR
    CALL CT_GUARD
    JP   AC_TOVAR

.INITIAL:
    CALL AC_FIT
    JP   AC_SAFE

; A is the logical action ordinal for the contiguous to/until family.
AC_FORTO:
    AND  1
.MODE:
    LD   (AC_MODE),A
    CALL AC_ADOPT
    JP   AC_U16

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,IX,IY
AC_LIMIT:
    LD   E,SY_U16
    JP   AC_CHECK

AC_STEP EQU  AC_LIMIT

AC_BYONE:
    CALL AC_LIMIT
    LD   DE,1
    LD   (AC_DELTA),DE
    XOR  A
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_FORDO:
    LD   B,CT_KFOR
    CALL CT_OPEN
    LD   B,CT_FCONT
    CALL CT_ALLOT
    CALL CT_EXIT
    LD   B,CT_FVAR
    CALL CT_FIELD
    LD   A,(AC_DVAL)
    LD   (HL),A
    INC  HL
    CALL EX_DTYPE
    CP   SY_U16
    LD   A,(AC_MODE)
    JR   NZ,.MODEOK
    SET  2,A
.MODEOK:
    LD   (HL),A
    INC  HL
    LD   DE,(AC_DELTA)
    LD   (HL),E
    INC  HL
    LD   (HL),D
    INC  HL
    LD   DE,(AC_WHERE)
    LD   (HL),E
    INC  HL
    LD   (HL),D
    CALL CT_TOP
    CALL CT_SETUP
    CALL CT_TOP
    INC  HL
    LD   C,(HL)
    CALL CT_PLACE
    CALL CT_TEST
    JP   AC_LIVEN

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
AC_NEXT:
    LD   B,CT_FCONT
    CALL AC_LABEL
    CALL CT_AGAIN
    LD   B,CT_FEXIT
    CALL AC_LABEL
    LD   A,OP_CLEAN
    CALL TR_OPER
    JP   AC_LEAVE
AC_CEND:
