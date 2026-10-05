; Correctness-first typed scalar declarations and expressions.
;
; Expression results return metadata in A and, when constant, a value in HL.
; The low two metadata bits are ScalarType*, and SY_KNOWN marks an
; exact compile-time value. Runtime expressions are emitted as a checked
; postfix stream of 16-bit carriers; u8 and boolean carriers have a zero high
; byte. The declared type, not the carrier, controls width and compatibility.

;@ROUTINE OUT A,B,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,DE
EX_ISFWD:
    LD   A,(PR_FORD)
    OR   A
    RET  Z
    LD   HL,PR_FNAME
    JP   TK_SAME

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
EX_MAIN:
    LD   HL,KW_MAIN
    LD   B,4
    JP   TK_MATCH

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_DECL:
    CALL EX_MAIN
    JR   C,EX_EDUP
    CALL EX_ISFWD
    JR   C,EX_EDUP
EX_KEEP:
    LD   HL,AC_DNAME
    CALL TK_KEEP
    LD   HL,TK_POS
    LD   DE,AC_DPOS
    CALL PR_COPY
    OR   A
    RET

EX_EDUP:
    CALL DG_RAISE
    DB   DG_DUP

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
EX_FRESH:
    CALL SY_FIND
    JR   C,EX_EDUP
    CALL EX_MAIN
    JR   C,EX_EDUP
    OR   A
    RET

; Restore the retained declaration spelling as the current name token.
;@ROUTINE OUT A,HL
EX_RENEW:
    LD   HL,(AC_DNAME)
    LD   (TK_PTR),HL
    LD   A,(AC_DLEN)
    LD   (TK_LEN),A
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_PREP:
    CALL EX_RENEW
    PUSH BC
    PUSH DE
    LD   HL,AC_DPOS
    LD   DE,TK_POS
    CALL PR_COPY
    CALL RO_FRESH
    JR   NC,.CLEAR
    POP  DE
    POP  BC
    RET
.CLEAR:
    POP  DE
    POP  BC
    JP   SY_NEW

; Expression-only sink wrappers allow the same parser to evaluate static
; constant initializers without emitting runtime operations.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_EMIT:
    LD   D,A
    LD   A,(EX_LIVE)
    OR   A
    LD   A,D
    RET  Z
    JP   TR_OPER

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_EMITB:
    LD   D,A
    LD   A,(EX_LIVE)
    OR   A
    LD   A,D
    RET  Z
    JP   TR_PUT

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_EMITW:
    PUSH HL
    LD   A,L
    CALL EX_EMITB
    POP  HL
    LD   A,H
    JR   EX_EMITB

; Emit one expression operation followed by a complete program address.
;@ROUTINE IN A,BC OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
EX_OPW:
    PUSH BC
    CALL EX_EMIT
    POP  HL
    JR   EX_EMITW

; Push one pending binary-expression context into the bounded compiler stack.
; Retaining the operator source offset is necessary because a nested operation
; may replace the global offset before the outer operation is reduced.
;@ROUTINE IN A OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,DE,IX,IY
EX_SLOT:
    LD   E,A
    ADD  A,A
    ADD  A,E
    ADD  A,A
    ADD  A,A
    ADD  A,E
    LD   E,A
    LD   D,0
    LD   HL,EX_STACK
    ADD  HL,DE
    RET

EX_PUSH:
    LD   A,(EX_DEPTH)
    CP   EX_STCAP
    JR   NC,.FULL
    CALL EX_SLOT
    LD   A,(EX_LMETA)
    LD   (HL),A
    INC  HL
    LD   DE,(EX_LVAL)
    LD   (HL),E
    INC  HL
    LD   (HL),D
    INC  HL
    LD   A,(EX_QUIET)
    LD   (HL),A
    INC  HL
    LD   A,(EX_OPER)
    LD   (HL),A
    INC  HL
    LD   DE,(EX_OPPOS)
    LD   (HL),E
    INC  HL
    LD   (HL),D
    INC  HL
    EX   DE,HL
    LD   HL,EX_VPOS
    CALL PR_COPY
    LD   A,(EX_DEPTH)
    INC  A
    LD   (EX_DEPTH),A
    OR   A
    RET

.FULL:
    CALL DG_RAISE
    DB   DG_DEEP

; Store A/HL as the pending left result before pushing it.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_SAVE:
    LD   (EX_LMETA),A
    LD   (EX_LVAL),HL
    JR   EX_PUSH

; Save the right result, then restore the most recent left result.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_POP:
    LD   (EX_RMETA),A
    LD   (EX_RVAL),HL
; Every reduction follows EX_SAVE. Keep the defensive test so
; a future parser change cannot turn a broken invariant into a
; wrapped address beyond PR_WEND.
    LD   A,(EX_DEPTH)
    OR   A
    JR   Z,EX_EPOP
    DEC  A
    LD   (EX_DEPTH),A
    CALL EX_SLOT
    LD   A,(HL)
    LD   (EX_LMETA),A
    INC  HL
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    LD   (EX_LVAL),DE
    INC  HL
    LD   A,(HL)
    LD   (EX_QUIET),A
    INC  HL
    LD   A,(HL)
    LD   (EX_OPER),A
    INC  HL
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    LD   (EX_OPPOS),DE
    INC  HL
    LD   (EX_LPOSP),HL
    OR   A
    RET
EX_EPOP:
    CALL DG_RAISE
    DB   DG_BUG

EX_ERNG:
    LD   HL,EX_VPOS
    JR   EX_EPOS
EX_ELEFT:
    LD   HL,(EX_LPOSP)
EX_EPOS:
    LD   DE,TK_POS
    CALL PR_COPY
EX_EBIG:
    CALL DG_RAISE
    DB   DG_RANGE
EX_ETYPE:
    CALL DG_RAISE
    DB   DG_CLASH
EX_EZERO:
    LD   B,C                       ; statically selected divide width
    LD   C,DG_ZERO
    JR   EX_FAULT
EX_ECAST:
    LD   B,SY_U8                   ; u8(...) always has u8 result type
    LD   C,DG_TRUNC
EX_FAULT:
    LD   A,(EX_QUIET)
    OR   A
    JR   NZ,.QUIET
    LD   A,C
    JP   DG_ISSUE
.QUIET:
    LD   A,B
    LD   HL,0
    OR   SY_KNOWN
    RET

; Resolve two integer operands. The four source metadata/value cells are live.
; C returns u8 or u16. Exact constants adopt the typed peer or expected type.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
EX_LBOOL:
    LD   A,(EX_LMETA)
    AND  SY_TMASK
    CP   SY_BOOL
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
EX_DTYPE:
    LD   A,(AC_DINFO)
    AND  SY_TMASK
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_UNIFY:
    CALL EX_LBOOL
    JR   Z,EX_ETYPE
    LD   D,A
    LD   A,(EX_RMETA)
    AND  SY_TMASK
    CP   SY_BOOL
    JR   Z,EX_ETYPE
    LD   E,A
    LD   A,D
    OR   A
    JR   NZ,EX_LTYPE
    LD   A,E
    OR   A
    JR   NZ,.RIGHT
    LD   A,(EX_WANT)
    CP   SY_U8
    JR   Z,.EXACT8
    LD   C,SY_U16
    OR   A
    RET
.EXACT8:
    LD   HL,(EX_LVAL)
    LD   A,H
    OR   A
    JR   NZ,EX_ELEFT
    LD   HL,(EX_RVAL)
    LD   A,H
    OR   A
    JR   NZ,EX_ERNG
    LD   C,SY_U8
    OR   A
    RET
.RIGHT:
    LD   C,E
    CP   SY_U8
    JR   NZ,EX_OK
    LD   HL,(EX_LVAL)
    LD   A,H
    OR   A
    JR   NZ,EX_ELEFT
EX_OK:
    OR   A
    RET
EX_LTYPE:
    LD   A,E
    OR   A
    JR   NZ,.BOTH
    LD   C,D
    LD   A,D
    CP   SY_U8
    JR   NZ,EX_OK
    LD   HL,(EX_RVAL)
    LD   A,H
    OR   A
    JP   NZ,EX_ERNG
    JR   EX_OK
.BOTH:
    LD   A,D
    CP   SY_U16
    JR   Z,.U16
    LD   A,E
    CP   SY_U16
    JR   Z,.U16
    LD   C,SY_U8
    OR   A
    RET
.U16:
    LD   C,SY_U16
    OR   A
    RET

;@ROUTINE IN A,D OUT A,D,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
EX_CLASS:
    AND  SY_TYPE+SY_AGGR
    JP   NZ,EX_ETYPE
    LD   A,D
    AND  SY_CMASK
    RET

; Return constant in A when both operands are constant.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_KNOWN:
    LD   A,(EX_LMETA)
    AND  SY_KNOWN
    RET  Z
    LD   A,(EX_RMETA)
    AND  SY_KNOWN
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_MASK:
    LD   A,C
    CP   SY_U8
    RET  NZ
    LD   H,0
    RET

; Emit a width-selected binary operation. D=u8 ordinal, E=u16 ordinal.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_PICK:
    LD   A,C
    CP   SY_U8
    LD   A,D
    JR   Z,.PICKED
    LD   A,E
.PICKED:
    JP   EX_EMIT

; Emit the selected operation, then retain both values only when the pair is
; compile-time constant. Carry reports emission failure; zero reports dynamic.
;@ROUTINE IN C,D,E OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_BINOP:
    CALL EX_PICK
    CALL EX_KNOWN
    RET  Z
    LD   HL,(EX_LVAL)
    LD   DE,(EX_RVAL)
    RET

; Reduce +, -, *, /, integer and, or, xor. EX_OPER holds the token.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_ARITH:
    CALL EX_UNIFY
    LD   A,(EX_OPER)
    CP   TK_PLUS
    JR   Z,.PLUS
    CP   TK_MINUS
    JR   Z,.MINUS
    CP   TK_STAR
    JR   Z,.TIMES
    CP   TK_SLASH
    JP   Z,.DIVIDE
    CP   TK_MOD
    JP   Z,.MODULO
    CP   TK_AND
    JR   Z,.BITAND
    CP   TK_XOR
    JR   Z,.BITXOR
.BITOR:
    LD   DE,OP_OR8*$100+OP_OR16
    CALL EX_BINOP
    LD   A,C
    RET  Z
    LD   A,L
    OR   E
    LD   L,A
    LD   A,H
    OR   D
    LD   H,A
    JP   .CONST
.BITXOR:
    LD   DE,OP_XOR8*$100+OP_XOR16
    CALL EX_BINOP
    LD   A,C
    RET  Z
    LD   A,L
    XOR  E
    LD   L,A
    LD   A,H
    XOR  D
    LD   H,A
    JP   .CONST
.BITAND:
    LD   DE,OP_AND8*$100+OP_AND16
    CALL EX_BINOP
    LD   A,C
    RET  Z
    LD   A,L
    AND  E
    LD   L,A
    LD   A,H
    AND  D
    LD   H,A
    JP   .CONST
.PLUS:
    LD   D,OP_ADD8
    LD   E,OP_ADD16
    CALL EX_BINOP
    JP   Z,.RUNTIME
    ADD  HL,DE
    JR   .CONST
.MINUS:
    LD   D,OP_SUB8
    LD   E,OP_SUB16
    CALL EX_BINOP
    JR   Z,.RUNTIME
    OR   A
    SBC  HL,DE
    JR   .CONST
.TIMES:
    LD   D,OP_MUL8
    LD   E,OP_MUL16
    CALL EX_BINOP
    JR   Z,.RUNTIME
; Constant multiplication modulo 65536, using sixteen shift/add
; steps.
    PUSH BC
    LD   BC,0
    LD   A,16
.MULLOOP:
    SRL  D
    RR   E
    JR   NC,.MULSKIP
    PUSH HL
    ADD  HL,BC
    LD   B,H
    LD   C,L
    POP  HL
.MULSKIP:
    ADD  HL,HL
    DEC  A
    JR   NZ,.MULLOOP
    LD   H,B
    LD   L,C
    POP  BC
    JR   .CONST
.DIVIDE:
    LD   DE,OP_DIV8*$100+OP_DIV16
    JR   .DIVMOD
.MODULO:
    LD   DE,OP_MOD8*$100+OP_MOD16
.DIVMOD:
    CALL EX_PICK
    LD   HL,(EX_OPPOS)
    CALL EX_EMITW
; A divisor known to be zero is invalid even when the dividend is
; dynamic. The fault helper also implements constant short-circuit
; suppression, so the unevaluated Boolean arm remains admissible.
    LD   A,(EX_RMETA)
    AND  SY_KNOWN
    JR   Z,.FOLD
    LD   HL,(EX_RVAL)
    LD   A,H
    OR   L
    JP   Z,EX_EZERO
.FOLD:
    CALL EX_KNOWN
    JR   Z,.RUNTIME
; The earlier exact-divisor check proves DE is nonzero here.
; Constant unsigned division uses a bounded subtraction loop.
    LD   DE,(EX_RVAL)
    LD   HL,(EX_LVAL)
    PUSH BC
    LD   BC,0
.DIVLOOP:
    OR   A
    SBC  HL,DE
    JR   C,.DIVDONE
    INC  BC
    JR   .DIVLOOP
.DIVDONE:
    ADD  HL,DE
    LD   A,(EX_OPER)
    CP   TK_MOD
    JR   Z,.RESULT
    LD   H,B
    LD   L,C
.RESULT:
    POP  BC
    OR   A
.CONST:
    CALL EX_MASK
    LD   A,C
    OR   SY_KNOWN
    RET
.RUNTIME:
    LD   A,C
    OR   A
    RET

; Primary expressions.
EX_TERM:
    CALL PR_TAKE
    PUSH AF
    PUSH BC
    LD   HL,TK_POS
    LD   DE,EX_VPOS
    CALL PR_COPY
    POP  BC
    POP  AF
    CP   TK_NUM
    JR   Z,.NUMBER
    CP   TK_CHAR
    JR   Z,.CHAR
    CP   TK_TRUE
    JR   Z,.TRUE
    CP   TK_FALSE
    JR   Z,.FALSE
    CP   TK_NAME
    JR   Z,EX_NAME
    CP   TK_LPAR
    JP   Z,EX_PAREN
    CP   TK_U8
    JP   Z,EX_U8
    CP   TK_U16
    JP   Z,EX_U16
    JP   PR_ETERM
.NUMBER:
    LD   H,B
    LD   L,C
    LD   B,SY_KNOWN+SY_EXACT
    JR   EX_LIT
.CHAR:
    LD   H,0
    LD   L,C
    JR   .BYTE
.TRUE:
    LD   HL,1
    JR   .BOOL
.FALSE:
    LD   HL,0
.BOOL:
    LD   B,SY_KNOWN+SY_BOOL
    JR   EX_LIT
.BYTE:
    LD   B,SY_KNOWN+SY_U8
EX_LIT:
    PUSH BC
    PUSH HL
    LD   A,OP_LIT16
    CALL EX_EMIT
    POP  HL
    PUSH HL
    CALL EX_EMITW
    POP  HL
    POP  BC
    LD   A,B
    OR   A
    RET
EX_NAME:
    CALL RO_LIB
    JR   NC,.ORDINARY
    CP   RO_ERRS
    JP   NC,RO_CAUSE
    LD   B,A
    AND  $FD                       ; readInput/readStorage map to zero
    JP   NZ,EX_ETYPE
    LD   A,B
    JP   RO_QUERY
.ORDINARY:
    CALL RO_FIND
    JP   Z,RO_FUNC
    CALL SY_GET
    LD   D,A
    AND  SY_AGGR
    JP   NZ,RO_OBJ
    LD   A,D
    JR   .RESOLVED
; The retained routine table handles scalar calls above.
.VARIABLE:
    CALL SY_GET
    LD   D,A
.RESOLVED:
    CALL EX_CLASS
    JR   Z,.CONST
    LD   A,D
    AND  SY_TMASK
    LD   E,A
    LD   A,D
    AND  SY_CMASK
    CP   SY_GLOB
    JR   Z,.GLOBAL
    CP   SY_PARAM
    JR   Z,.PARAM
    LD   A,E
    CP   SY_U16
    LD   A,OP_LDL8
    JR   NZ,.LOAD
    LD   A,OP_LDL16
    JR   .LOAD
.GLOBAL:
    LD   A,E
    CP   SY_U16
    LD   A,OP_LDG8
    JR   NZ,.GLOBEMIT
    LD   A,OP_LDG16
.GLOBEMIT:
    PUSH DE
    CALL EX_OPW
    POP  DE
    LD   A,E
    OR   A
    RET
.PARAM:
    LD   A,E
    CP   SY_U16
    LD   A,OP_LDP8
    JR   NZ,.LOAD
    LD   A,OP_LDP16
.LOAD:
    PUSH DE
    PUSH BC
    CALL EX_EMIT
    POP  BC
    POP  DE
    LD   A,C
    PUSH DE
    CALL EX_EMITB
    POP  DE
    LD   A,E
    OR   A
    RET
.CONST:
    LD   H,B
    LD   L,C
    LD   B,D
    SET  7,B
    JP   EX_LIT

; Parse one call to the retained scalar forward. The outer call position stays
; on the compiler stack while a nested argument call is parsed.
; Kept only for the pre-aggregate expression proof layouts.
; A failable invocation remains consumable only while it is the complete,
; untouched expression. Preserve the expression result while checking that no
; pending direct failure is being enclosed by another expression form.
;@ROUTINE IN A,HL OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
EX_PURE:
    LD   C,A
    LD   A,(RO_PEND)
    OR   A
    JP   NZ,AC_ELEAK
    LD   A,C
    RET

;@ROUTINE IN A,HL OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_HOLD:
    CALL EX_PURE
    JP   EX_SAVE

;@ROUTINE IN A,HL OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_JOIN:
    CALL EX_PURE
    JP   EX_POP
EX_PAREN:
    CALL EX_PARSE
    PUSH AF
    PUSH HL
    CALL PR_RIGHT
    POP  HL
    POP  AF
    JR   EX_PURE

; Parse the parenthesized operand of an explicit conversion under the
; conversion's own expected type. The enclosing expected type is restored on
; every exit; A/HL return the checked operand on success.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_CAST:
    LD   C,A
    LD   A,(EX_WANT)
    LD   B,A
    PUSH BC
    LD   A,C
    LD   (EX_WANT),A
    CALL PR_LEFT
    CALL EX_PARSE
    LD   D,A
    PUSH DE
    PUSH HL
    CALL PR_RIGHT
    POP  HL
    POP  DE
    POP  BC
    LD   A,B
    LD   (EX_WANT),A
    LD   A,D
    CALL EX_PURE
    OR   A
    RET

EX_U8:
    LD   HL,(TK_POS)
    LD   (EX_OPPOS),HL
    PUSH HL                        ; this conversion's trap position
    LD   A,SY_U8
    CALL EX_CAST
; Restore the enclosing context while keeping this conversion's
; value and source offset live for the checked narrowing below.
    LD   D,A
    LD   B,H
    LD   C,L
    POP  HL
    LD   (EX_OPPOS),HL
    LD   H,B
    LD   L,C
    LD   A,D
    CALL EX_INT
    AND  SY_KNOWN
    JR   Z,.RUNTIME
    LD   A,H
    OR   A
    JP   NZ,EX_ECAST
    LD   A,SY_KNOWN+SY_U8
    OR   A
    RET
.RUNTIME:
    LD   A,OP_TRUNC
    CALL EX_EMIT
    LD   HL,(EX_OPPOS)
    CALL EX_EMITW
    LD   A,SY_U8
    OR   A
    RET

;@ROUTINE IN A OUT A,D,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
EX_INT:
    LD   D,A
    AND  SY_TMASK
    CP   SY_BOOL
    JP   Z,EX_ETYPE
    LD   A,D
    CCF                            ; valid scalar types compare below Boolean
    RET

EX_U16:
    LD   A,SY_U16
    CALL EX_CAST
    CALL EX_INT
    AND  SY_KNOWN
    LD   A,SY_U16
    RET  Z
    OR   SY_KNOWN
    RET

; Unary + and - bind above multiplicative operators.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_UNARY:
    CALL PR_PEEK
    CP   TK_PLUS
    JR   Z,EX_PLUS
    CP   TK_MINUS
    JR   Z,EX_MINUS
    JP   EX_TERM
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_PLUS:
    CALL PR_TAKE
    CALL EX_UNARY
    CALL EX_PURE
    CALL EX_INT
    OR   A
    RET
EX_MINUS:
    CALL EX_PLUS
    LD   D,A
    AND  SY_TMASK
    JR   NZ,.TYPED
    LD   A,(EX_WANT)
    CP   SY_U8
    JR   Z,EX_NEGU8
    LD   A,SY_U16
    JR   EX_NEG
.TYPED:
    LD   A,D
    AND  SY_TMASK
EX_NEG:
    LD   C,A
    CP   SY_U8
    LD   A,OP_NEG8
    JR   Z,.EMIT
    LD   A,OP_NEG16
.EMIT:
    CALL EX_UNOP
    LD   A,D
    AND  SY_KNOWN
    LD   A,C
    RET  Z
    XOR  A
    SUB  L
    LD   L,A
    LD   A,0
    SBC  A,H
    LD   H,A
    CALL EX_MASK
    LD   A,C
    OR   SY_KNOWN
    RET

;@ROUTINE IN A,BC,DE,HL OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_UNOP:
    PUSH BC
    PUSH DE
    PUSH HL
    CALL EX_EMIT
    POP  HL
    POP  DE
    POP  BC
    RET
EX_NEGU8:
; Width selection must not destroy evidence that the exact literal
; itself exceeded u8 before negation applies modulo 256.
    LD   A,D
    AND  SY_KNOWN
    JR   Z,.READY
    LD   A,H
    OR   A
    JP   NZ,EX_ERNG
.READY:
    LD   A,SY_U8
    JR   EX_NEG

; Integer * / mod bind tighter than + -, which bind tighter than
; comparisons. B is the minimum precedence: 0 comparison, 1 additive, 2
; multiplicative, 3 a right operand that must not accept any of them.
; Comparison enums occupy EX_OPER values 0..5; token operators
; are all larger, so the reduce path can tell them apart. Comparisons are
; non-associative: a second relation after a reduce is DG_CHAIN.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_CMP:
    LD   B,0
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_CLIMB:
    PUSH BC
    CALL EX_UNARY
    POP  BC
EX_RISE:
    PUSH AF
    PUSH HL
    LD   A,B
    CP   3
    JR   C,EX_LOOK
EX_PEAK:
    POP  HL
    POP  AF
    RET
EX_STOP:
    POP  BC
    JR   EX_PEAK
EX_LOOK:
    PUSH BC
    CALL PR_PEEK
    CP   TK_MINUS
    JR   Z,.ADDPREC
    CP   TK_PLUS
    JR   Z,.ADDPREC
    CP   TK_STAR
    JR   Z,.MULPREC
    CP   TK_SLASH
    JR   Z,.MULPREC
    CP   TK_MOD
    JR   Z,.MULPREC
    POP  BC
    LD   D,A
    LD   A,B
    OR   A
    JR   NZ,EX_PEAK
    LD   A,D
    PUSH BC
    CALL .RELTOKEN
    JR   NC,EX_STOP
    LD   A,C
    LD   (EX_OPER),A
    LD   C,0
    JR   .HAVEPREC
.MULPREC:
    LD   C,2
    JR   .SETOP
.ADDPREC:
    LD   C,1
.SETOP:
    LD   (EX_OPER),A
.HAVEPREC:
    LD   A,C
    POP  BC
    CP   B
    JR   C,EX_PEAK
    INC  A
    LD   C,A
    PUSH BC
    CALL PR_TAKE
    LD   HL,(TK_POS)
    LD   (EX_OPPOS),HL
    POP  DE
    POP  HL
    POP  AF
    PUSH DE
    CALL EX_HOLD
    POP  BC
    PUSH BC
    LD   B,C
    CALL EX_CLIMB
.RIGHT:
    CALL EX_JOIN
    LD   A,(EX_OPER)
    CP   6
    JR   C,.RELATION
    CALL EX_ARITH
    POP  BC
    JP   EX_RISE
.RELATION:
    CALL .REDUCE
    POP  BC
    PUSH AF
    PUSH HL
    CALL PR_PEEK
    CALL .RELTOKEN
    JR   C,.CHAINED
    POP  HL
    POP  AF
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
.RELTOKEN:
    LD   HL,.RELTAB
    LD   B,6
.SCAN:
    CP   (HL)
    JR   Z,.FOUND
    INC  HL
    INC  HL
    DJNZ .SCAN
    OR   A
    RET
.FOUND:
    INC  HL
    LD   C,(HL)
    SCF
    RET
.RELTAB:
    DB   TK_EQ,EX_EQ
    DB   TK_NE,EX_NE
    DB   TK_LT,EX_LT
    DB   TK_LE,EX_LE
    DB   TK_GT,EX_GT
    DB   TK_GE,EX_GE

.CHAINED:
    POP  HL
    POP  AF
    CALL DG_RAISE
    DB   DG_CHAIN
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
.REDUCE:
    LD   A,(EX_LMETA)
    AND  SY_TMASK
    LD   D,A
    LD   A,(EX_RMETA)
    AND  SY_TMASK
    LD   E,A
    LD   A,D
    CP   SY_BOOL
    JR   NZ,.INTEGER
    LD   A,E
    CP   SY_BOOL
    JP   NZ,EX_ETYPE
    LD   A,(EX_OPER)
    CP   EX_NE+1
    JP   NC,EX_ETYPE
    LD   A,OP_LCMP
    JR   .EMIT
.INTEGER:
    CALL EX_UNIFY
    LD   A,C
    CP   SY_U8
    LD   A,OP_CMP8
    JR   Z,.EMIT
    LD   A,OP_CMP16
.EMIT:
    CALL EX_EMIT
    LD   A,(EX_OPER)
    CALL EX_EMITB
    CALL EX_KNOWN
    LD   A,SY_BOOL
    RET  Z
    LD   HL,(EX_LVAL)
    LD   DE,(EX_RVAL)
    OR   A
    SBC  HL,DE
    LD   A,(EX_OPER)
    JR   Z,.EQUAL
    JR   C,.LESS
    LD   C,1
    JR   .SELECT
.EQUAL:
    LD   C,0
    JR   .SELECT
.LESS:
    LD   C,$FF
.SELECT:
; C is -1, 0, or 1. Map the requested relation to a Boolean.
    LD   B,A
    LD   HL,0
    LD   A,B
    CP   EX_EQ
    JR   Z,.IFEQUAL
    CP   EX_NE
    JR   Z,.IFUNEQ
    CP   EX_LT
    JR   Z,.IFLESS
    CP   EX_LE
    JR   Z,.IFATMOST
    CP   EX_GT
    JR   Z,.IFMORE
    LD   A,C
    CP   $FF
    JR   Z,.CONST
    INC  L
    JR   .CONST
.IFEQUAL:
    LD   A,C
    OR   A
    JR   NZ,.CONST
    INC  L
    JR   .CONST
.IFUNEQ:
    LD   A,C
    OR   A
    JR   Z,.CONST
    INC  L
    JR   .CONST
.IFLESS:
    LD   A,C
    CP   $FF
    JR   NZ,.CONST
    INC  L
    JR   .CONST
.IFATMOST:
    LD   A,C
    CP   1
    JR   Z,.CONST
    INC  L
    JR   .CONST
.IFMORE:
    LD   A,C
    CP   1
    JR   NZ,.CONST
    INC  L
.CONST:
    LD   A,SY_KNOWN+SY_BOOL
    OR   A
    RET

; `not` binds below comparisons and above `and`.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_NOT:
    CALL PR_PEEK
    CP   TK_NOT
    JP   NZ,EX_CMP
    CALL PR_TAKE
    CALL EX_NOT
    CALL EX_PURE
    LD   D,A
    AND  SY_TMASK
    CP   SY_BOOL
    LD   C,SY_BOOL
    LD   A,OP_LNOT
    JR   Z,.EMIT
    LD   A,D
    AND  SY_TMASK
    JR   NZ,.TYPED
    LD   A,(EX_WANT)
    CP   SY_U8
    JR   Z,.EXACT8
    LD   C,SY_U16
    LD   A,OP_NOT16
    JR   .EMIT
.EXACT8:
; As with unary minus, validate the exact operand before applying
; the width-specific complement and masking the result.
    LD   A,D
    AND  SY_KNOWN
    JR   Z,.BYTE
    LD   A,H
    OR   A
    JP   NZ,EX_ERNG
.BYTE:
    LD   C,SY_U8
    LD   A,OP_NOT8
    JR   .EMIT
.TYPED:
    LD   A,D
    AND  SY_TMASK
    LD   C,A
    CP   SY_U8
    LD   A,OP_NOT8
    JR   Z,.EMIT
    LD   A,OP_NOT16
.EMIT:
    CALL EX_UNOP
    LD   A,D
    AND  SY_KNOWN
    LD   A,C
    RET  Z
    CP   SY_BOOL
    JR   NZ,.INTCONST
    LD   A,L
    XOR  1
    LD   L,A
    LD   H,0
    JR   .CONST
.INTCONST:
    LD   A,L
    CPL
    LD   L,A
    LD   A,H
    CPL
    LD   H,A
    CALL EX_MASK
.CONST:
    LD   A,C
    OR   SY_KNOWN
    RET

; Boolean short circuit is represented by prefix/suffix operations so the
; Z80 backend can branch around the right operand. Integer and/or use the
; ordinary postfix reduction.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_AND:
    CALL EX_NOT
.LOOP:
    PUSH AF
    PUSH HL
    CALL PR_PEEK
    CP   TK_AND
    JP   NZ,EX_DONE
    LD   (EX_OPER),A
    CALL PR_TAKE
    POP  HL
    POP  AF
    CALL EX_HOLD
    CALL EX_LBOOL
    JR   NZ,.RIGHT
    LD   A,OP_CAND
    CALL EX_EMIT
    LD   C,0
    CALL EX_MUTE
.RIGHT:
    CALL EX_NOT
    CALL EX_JOIN
    CALL EX_LBOOL
    JR   NZ,.INTEGER
    CALL EX_LOGIC
    JR   .LOOP
.INTEGER:
    CALL EX_ARITH
    JR   .LOOP

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_PARSE:
    CALL EX_AND
EX_ORS:
    PUSH AF
    PUSH HL
    CALL PR_PEEK
    CP   TK_XOR
    JR   Z,.OPER
    CP   TK_OR
    JR   NZ,EX_DONE
    LD   A,(RO_PEND)
    OR   A
    JR   NZ,EX_ELEAK
    LD   A,TK_OR
.OPER:
    LD   (EX_OPER),A
    CALL PR_TAKE
    POP  HL
    POP  AF
    CALL EX_SAVE
    LD   A,(EX_OPER)
    CP   TK_XOR
    JR   NZ,.BOOLLEFT
    CALL EX_LBOOL
    JP   Z,EX_ETYPE
    JR   .RIGHT
.BOOLLEFT:
    CALL EX_LBOOL
    JR   NZ,.RIGHT
    LD   A,OP_COR
    CALL EX_EMIT
    LD   C,1
    CALL EX_MUTE
.RIGHT:
    CALL EX_AND
    CALL EX_JOIN
    CALL EX_LBOOL
    JR   NZ,EX_ORINT
    CALL EX_LOGIC
    JR   EX_ORS
EX_DONE:
    POP  HL
    POP  AF
    RET
EX_ELEAK:
    CALL AC_ELEAK
EX_ORINT:
    CALL EX_ARITH
    JR   EX_ORS

;@ROUTINE IN C OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_MUTE:
    LD   A,(EX_LMETA)
    AND  SY_KNOWN
    RET  Z
    LD   HL,(EX_LVAL)
    LD   A,L
    XOR  C
    RET  NZ
    LD   HL,EX_QUIET
    INC  (HL)
    RET
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_LOGIC:
    LD   A,(EX_RMETA)
    AND  SY_TMASK
    CP   SY_BOOL
    JP   NZ,EX_ETYPE
    LD   A,OP_JOIN
    CALL EX_EMIT
    CALL EX_KNOWN
    LD   A,SY_BOOL
    RET  Z
    LD   HL,(EX_LVAL)
    LD   A,L
    OR   H
    LD   C,A
    LD   A,(EX_OPER)
    CP   TK_AND
    JR   Z,.ISAND
    LD   A,C
    OR   A
    JR   NZ,.TRUE
    JR   .RIGHT
.ISAND:
    LD   A,C
    OR   A
    JR   Z,.FALSE
.RIGHT:
    LD   HL,(EX_RVAL)
    JR   .CONST
.FALSE:
    LD   HL,0
    JR   .CONST
.TRUE:
    LD   HL,1
.CONST:
    LD   A,SY_KNOWN+SY_BOOL
    OR   A
    RET

; Assignment compatibility resolves exact constants and the sole implicit
; widening. A/HL is the expression; E is the destination type.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_FITS:
    LD   D,A
    AND  SY_TMASK
    JR   NZ,.TYPED
    LD   A,E
    CP   SY_BOOL
    JP   Z,EX_ETYPE
    CP   SY_U8
    JR   NZ,.EXACT
    LD   A,H
    OR   A
    JP   NZ,EX_ERNG
.EXACT:
    LD   A,D
    AND  SY_KNOWN
    OR   E
    RET
.TYPED:
    CP   E
    JR   Z,.SAME
    CP   SY_U8
    JP   NZ,EX_ETYPE
    LD   A,E
    CP   SY_U16
    JP   NZ,EX_ETYPE
.SAME:
    LD   A,D
    AND  SY_KNOWN
    OR   E
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_RUN:
    LD   (EX_WANT),A
    XOR  A
    LD   (RO_PEND),A
    LD   (RO_KEPT),A
    LD   A,1
    LD   (EX_LIVE),A
    XOR  A
    LD   (EX_QUIET),A
    LD   (EX_DEPTH),A
    JP   EX_PARSE
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_CONST:
    LD   (EX_WANT),A
    XOR  A
    LD   (EX_LIVE),A
    LD   (EX_QUIET),A
    LD   (EX_DEPTH),A
    JP   EX_PARSE

; Parse u8, u16, or boolean and return ScalarType* in A.

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_WIDTH:
    CP   SY_U16
    LD   A,1
    RET  NZ
    INC  A
    RET

; Emit a typed static program object. D=type, BC=offset, HL=value.

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_LOCAL:
    CP   SY_U16
    LD   A,OP_LOC8
    JR   NZ,.PICKED
    LD   A,OP_LOC16
.PICKED:
    CALL TR_OPER
    LD   A,(SY_LSLOT)
    JP   TR_PUT

; D is symbol info and C its byte offset.
;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
EX_STORE:
    LD   A,D
    AND  SY_CMASK
    CP   SY_GLOB
    JR   Z,.GLOBAL
    CP   SY_LOCAL
    JR   Z,.LOCAL
    CP   SY_PARAM
    JP   NZ,EX_ETYPE
    LD   A,D
    AND  SY_TMASK
    CP   SY_U16
    LD   A,OP_STP8
    JR   NZ,.EMIT
    LD   A,OP_STP16
    JR   .EMIT
.LOCAL:
    LD   A,D
    AND  SY_TMASK
    CP   SY_U16
    LD   A,OP_STL8
    JR   NZ,.EMIT
    LD   A,OP_STL16
    JR   .EMIT
.GLOBAL:
    LD   A,D
    AND  SY_TMASK
    CP   SY_U16
    LD   A,OP_STG8
    JR   NZ,.GLOBEMIT
    LD   A,OP_STG16
.GLOBEMIT:
    JP   EX_OPW
.EMIT:
    JP   PR_EMITC

EX_EFLOW:
    CALL DG_RAISE
    DB   DG_FLOW
.FORWARD:
    CALL DG_RAISE
    DB   DG_UNMET
