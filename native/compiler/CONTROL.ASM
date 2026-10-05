; Bounded structured-control parser layered over typed scalar expressions.
; Parser frames live only during source checking. Z80 emission reuses their
; workspace after the complete semantic transcript has been published.

;@ROUTINE IN A OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
CT_FRAME:
    LD   L,A
    LD   H,0
    ADD  HL,HL
    LD   E,L
    LD   D,H
    ADD  HL,HL
    ADD  HL,HL
    ADD  HL,DE
    LD   DE,CT_FTAB
    ADD  HL,DE
    OR   A
    RET

; A is ControlKind*. Return the new frame base in HL.
;@ROUTINE IN A OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C
CT_PUSH:
    LD   B,A
    LD   A,(CT_DEPTH)
    CP   CT_FCAP
    JR   NC,CT_EDEEP
    PUSH AF
    CALL CT_FRAME
    POP  AF
    INC  A
    LD   (CT_DEPTH),A
    LD   (HL),B
    INC  HL
    LD   B,CT_FLEN-1
    XOR  A
.CLEAR:
    LD   (HL),A
    INC  HL
    DJNZ .CLEAR
    LD   A,(CT_DEPTH)
    DEC  A
    CALL CT_FRAME
    PUSH HL
    LD   DE,CT_FVAR
    ADD  HL,DE
    LD   (HL),CT_NOVAR
    POP  HL
    OR   A
    RET
CT_EDEEP:
    CALL DG_RAISE
    DB   DG_NEST

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
CT_TOP:
    LD   A,(CT_DEPTH)
    OR   A
    JR   Z,CT_ELOOP
    DEC  A
    JR   CT_FRAME

;@ROUTINE IN B OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
CT_FIELD:
    CALL CT_TOP
    LD   E,B
    LD   D,0
    ADD  HL,DE
    OR   A
    RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
CT_POP:
    LD   HL,CT_DEPTH
    LD   A,(HL)
    OR   A
    JR   Z,CT_ELOOP
    DEC  (HL)
    XOR  A
    RET

;@ROUTINE OUT A,C,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
CT_EXIT:
    LD   B,CT_FEXIT
;@ROUTINE IN B OUT A,C,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
CT_ALLOT:
    LD   A,(CT_LABNO)
    CP   CT_LLIM
    JR   NC,CT_ELABS
    LD   C,A
    INC  A
    LD   (CT_LABNO),A
    CALL CT_FIELD
    LD   (HL),C
    RET

;@ROUTINE IN B OUT A,C,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
CT_OPEN:
    CALL AC_NEST
;@ROUTINE OUT A,C,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
CT_LABEL:
    LD   B,CT_FDEST
    JR   CT_ALLOT

CT_ELABS:
    CALL DG_RAISE
    DB   DG_LABEL
CT_ELOOP:
    CALL DG_RAISE
    DB   DG_LOOP

; Emit operation D followed by byte C.
;@ROUTINE IN C,D OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
CT_EMIT:
    LD   A,D
    CALL TR_OPER
    LD   A,C
    JP   TR_PUT

;@ROUTINE IN C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL
CT_PLACE:
    LD   D,OP_LABEL
    JR   CT_EMIT
;@ROUTINE IN C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL
CT_IFNOT:
    LD   D,OP_IFNOT
    JR   CT_EMIT
;@ROUTINE IN C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL
CT_JUMP:
    LD   D,OP_JUMP
    JR   CT_EMIT

; Return the nearest enclosing while/for frame in HL.
;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C
CT_LOOP:
    LD   A,(CT_DEPTH)
    OR   A
    JR   Z,CT_ELOOP
.NEXT:
    DEC  A
    PUSH AF
    CALL CT_FRAME
    LD   A,(HL)
    CP   CT_KLOOP
    JR   Z,.FOUND
    CP   CT_KFOR
    JR   Z,.FOUND
    POP  AF
    OR   A
    JR   NZ,.NEXT
    JR   CT_ELOOP
.FOUND:
    POP  AF
    OR   A
    RET

; C is a local byte offset. Reject a source write or nested counter reuse while
; that exact local is the counter of any active counted loop.
;@ROUTINE IN C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL
CT_GUARD:
    LD   A,(CT_DEPTH)
    OR   A
    RET  Z
.NEXT:
    DEC  A
    PUSH AF
    CALL CT_FRAME
    LD   A,(HL)
    CP   CT_KFOR
    JR   NZ,.SKIP
    LD   DE,CT_FVAR
    ADD  HL,DE
    LD   A,(HL)
    CP   C
    JR   Z,.ACTIVE
.SKIP:
    POP  AF
    OR   A
    JR   NZ,.NEXT
    RET
.ACTIVE:
    POP  AF
    CALL DG_RAISE
    DB   DG_INUSE

;@ROUTINE OUT A,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B
CT_NOTE:
    LD   A,(CT_FALLS)
    OR   A
    RET  Z
    LD   B,CT_FVAR
    CALL CT_FIELD
    LD   (HL),0
    XOR  A
    RET

; TK_WHILE has already been consumed.

; Parse one compile-time step constant. B returns mode bit 1 and DE magnitude.
;@ROUTINE OUT A,B,DE,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,HL
CT_STEP:
    XOR  A
    LD   (EX_LMETA),A
    CALL PR_PEEK
    CP   TK_PLUS
    JR   Z,.PLUS
    CP   TK_MINUS
    JR   NZ,.AMOUNT
    LD   A,2
    LD   (EX_LMETA),A
.PLUS:
    CALL PR_TAKE
.AMOUNT:
    CALL PR_TAKE
    CP   TK_NUM
    JR   Z,.NUMBER
    CP   TK_NAME
    JR   NZ,.BAD
    CALL RO_LIB
    JR   NC,.CONST
    CP   RO_ERRS
    JR   C,.BAD
    SUB  RO_ERRS-1
    LD   D,0
    LD   E,A
    JR   .NONZERO
.CONST:
    CALL SY_GET
    LD   D,A
    AND  SY_TYPE+SY_AGGR
    JR   NZ,.BAD
    LD   A,D
    AND  SY_CMASK
    JR   NZ,.BAD
    LD   A,D
    AND  SY_TMASK
    CP   SY_BOOL
    JR   Z,.BAD
.NUMBER:
    LD   D,B
    LD   E,C
.NONZERO:
    LD   A,D
    OR   E
    JR   Z,.BAD
    LD   A,(EX_LMETA)
    LD   B,A
    OR   A
    RET
.BAD:
    CALL DG_RAISE
    DB   DG_STEP

; TK_FOR has already been consumed.
CT_EVAR:
    CALL DG_RAISE
    DB   DG_COUNT

; Emit the fixed-width counted-loop records from the current frame.
;@ROUTINE IN A,HL OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
CT_FOROP:
    PUSH HL
    CALL TR_OPER
    POP  HL
    LD   DE,CT_FVAR
    ADD  HL,DE
    LD   A,(HL)
    CALL TR_PUTHL
    INC  HL
    RET

;@ROUTINE IN HL OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
CT_SETUP:
    LD   A,OP_FOR
    CALL CT_FOROP
    LD   A,(HL)
    JP   TR_PUT

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
CT_TEST:
    CALL CT_TOP
    LD   A,OP_TEST
    CALL CT_FOROP
    LD   A,(HL)                    ; mode
    CALL TR_PUTHL
    LD   B,CT_FEXIT
    CALL CT_FIELD
    LD   A,(HL)                    ; exit label
    JP   TR_PUT
CT_BYTES:
    LD   A,(HL)
    PUSH BC
    CALL TR_PUTHL
    POP  BC
    INC  HL
    DJNZ CT_BYTES
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,IX,IY
CT_AGAIN:
    CALL CT_TOP
    PUSH HL
    LD   A,OP_NEXT
    CALL TR_OPER
    POP  HL
    LD   DE,CT_FDEST
    ADD  HL,DE
    LD   A,(HL)                    ; test label
    CALL TR_PUTHL
    INC  HL                        ; continue label
    INC  HL                        ; exit label
    LD   A,(HL)
    CALL TR_PUTHL
    INC  HL                        ; counter
    LD   B,6                       ; counter, mode, step, trap offset
    JR   CT_BYTES
