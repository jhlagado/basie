; Predictive aggregate paths, bounded routine signatures, forwards, and the
; predefined Stage 8 service surface. Runtime carriers are never entered in
; the source symbol model as integers.

;@ROUTINE IN A OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
RO_SUBAT:
    LD   L,A
    LD   H,0
    ADD  HL,HL
    ADD  HL,HL
    ADD  HL,HL
    LD   DE,RO_RTAB
    ADD  HL,DE
    OR   A
    RET

;@ROUTINE IN A OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE
RO_PARAM:
    LD   L,A
    LD   H,0
    ADD  HL,HL
    ADD  HL,HL
    LD   DE,RO_PTAB
    ADD  HL,DE
    OR   A
    RET

; Z returns one exact routine match and A its table index. NZ means that the
; current name is not a retained routine; it is not itself a diagnostic.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RO_FIND:
    LD   A,(RO_RCNT)
    OR   A
    JR   Z,.MISSING
    LD   C,A
    LD   B,0
.LOOP:
    LD   A,B
    CALL RO_SUBAT
    CALL TK_SAME
    JR   C,.FOUND
    INC  B
    DEC  C
    JR   NZ,.LOOP
.MISSING:
    LD   A,(RO_MFLAG)
    AND  RO_FMAIN
    JR   Z,.ABSENT
    CALL EX_MAIN
    JR   NC,.ABSENT
    LD   A,RO_MAIN
    CP   A
    RET
.ABSENT:
    LD   A,$FF
    OR   A
    RET
.FOUND:
    LD   A,B
    CP   A
    RET

RO_MATCH EQU  TK_SAME

; Carry identifies a predefined service or error constant and A returns its
; dense ordinal. No match returns carry clear.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RO_LIB:
    LD   HL,KW_NAMES
    LD   C,KW_NCNT
.LOOP:
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
    LD   A,KW_NCNT
    SUB  C
    SCF
    RET
.SKIP:
    LD   E,B
    LD   D,0
    ADD  HL,DE
    DEC  C
    JR   NZ,.LOOP
    OR   A
    RET

; Compile one multipart source stream and publish one append-only object.
; IX points at the stable compact target descriptor; A/HL retain the existing
; bounded source-part descriptor ABI.
;@ROUTINE IN A,HL,IX OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
PR_BUILD:
    LD   (PR_SP),SP
    LD   (TG_DESC),IX
    PUSH AF
    PUSH HL
    CALL PR_RESET
    POP  HL
    POP  AF
    PUSH AF
    CALL SRC_OPEN
    POP  BC
    LD   A,B
; Validate every bank-bearing descriptor field before source
; semantics can retain a bank ordinal. A is the bounded part count.
    LD   B,A
    LD   IX,(TG_DESC)
    LD   A,(IX+TG_DBCNT)
    OR   A
    JR   Z,.BADCFG
    CP   TG_BCAP+1
    JR   NC,.BADCFG
    LD   (TG_BCNT),A
    LD   C,A
    LD   A,(IX+TG_DEB)
    CP   C
    JR   NC,.BADCFG
    LD   (TG_EBANK),A
    LD   L,(IX+TG_DPART)
    LD   H,(IX+TG_DPART+1)
.BANKLOOP:
    LD   A,(HL)
    CP   C
    JR   NC,.BADCFG
    INC  HL
    DJNZ .BANKLOOP
    LD   HL,TG_ROTAB
    LD   B,TG_ROLIM-TG_ROTAB
    XOR  A
.WIPE:
    LD   (HL),A
    INC  HL
    DJNZ .WIPE
    CALL PR_PARSE
; A diagnostic during generation restores this synthetic frame and
; returns directly through the one target-output abort path. A
; successful generation returns normally and discards the frame.
    LD   HL,TG_ABORT
    PUSH HL
    LD   (PR_SP),SP
    CALL GA_BUILD
    POP  HL
    RET
.BADCFG:
    JP   TG_DENY

; Return the bank mapped to the current manifest source-part ordinal.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE,HL,IX
TG_HOME:
    LD   A,(SRC_LEFT)
    AND  SRC_ORD
    RRCA
    RRCA
    RRCA
    LD   E,A
    LD   D,0
    LD   IX,(TG_DESC)
    LD   L,(IX+TG_DPART)
    LD   H,(IX+TG_DPART+1)
    ADD  HL,DE
    LD   A,(HL)
    OR   A
    RET

; Add the current source bank to flag byte A without disturbing low flags.
;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL,IX
TG_PACK:
    LD   B,A
    CALL TG_HOME
    RLCA
    RLCA
    RLCA
    RLCA
    OR   B
    RET

; Extract the target bank stored in flag bits 4..5. The final rotate shifts a
; known zero bit through carry, so success returns carry clear.
;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
TG_SPLIT:
    AND  TG_BMASK
    RRCA
    RRCA
    RRCA
    RRCA
    RET

;@ROUTINE IN A OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE
TG_LENAT:
    LD   L,A
    LD   H,0
    ADD  HL,HL
    LD   DE,TG_ROTAB
    ADD  HL,DE
    OR   A
    RET

; Compare packed bank bits in D with the current source-part bank.
;@ROUTINE IN D OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL,IX
TG_SAME:
    LD   B,D
    CALL TG_HOME
    RLCA
    RLCA
    RLCA
    RLCA
    XOR  B
    AND  TG_BMASK
    RET
;@ROUTINE IN D OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
TG_MUST:
    CALL TG_SAME
    RET  Z
    JP   TG_DENY

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
TG_ENTRY:
    CALL TG_HOME
    LD   D,A
    LD   A,(TG_EBANK)
    CP   D
    RET  Z
    JP   TG_DENY

; The target entry initializes parts and calls the shared body.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
PR_PARSE:
    INC  A
    LD   (AG_MODE),A
    LD   HL,RO_BASE
    LD   B,RO_WEND-RO_BASE
    XOR  A
.WIPE:
    LD   (HL),A
    INC  HL
    DJNZ .WIPE
    LD   (CT_LABNO),A
    CALL LL_PARSE
    JP   TR_CLOSE

; Reject a routine name that collides with an ordinary name or an earlier
; routine. The current token remains the name being checked.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RO_FRESH:
    CALL SY_FIND
    JP   C,EX_EDUP
    CALL RO_FIND
    JP   Z,EX_EDUP
    CALL RO_LIB
    JP   C,EX_EDUP
    OR   A
    RET

; Check the current parameter name against the current signature prefix.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RO_NODUP:
    LD   A,(RO_CPCNT)
    OR   A
    RET  Z
    LD   C,A
    LD   A,(RO_CPIDX)
    LD   B,A
.LOOP:
    LD   A,B
    CALL RO_PARAM
    CALL TK_SAME
    JP   C,EX_EDUP
    INC  B
    DEC  C
    JR   NZ,.LOOP
    OR   A
    RET

; Reject a parameter name that collides with an ordinary declaration, an
; earlier routine, the routine whose signature is being parsed, or an earlier
; parameter in that signature.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RO_VET:
    CALL EX_FRESH
    CALL RO_FRESH
    LD   A,(RO_CUR)
    CALL RO_SUBAT
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    INC  HL
    LD   A,(HL)
    LD   B,A
    EX   DE,HL
    CALL TK_MATCH
    JP   C,EX_EDUP
    JR   RO_NODUP

; Append the current parameter name and its parsed type A.
;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RO_ENROL:
    LD   (RO_OTYPE),A
    LD   A,(RO_PCNT)
    CP   RO_PCAP
    JR   NC,.FULL
    CALL RO_PARAM
    CALL TK_KEEP
    INC  HL
    LD   A,(RO_OTYPE)
    LD   (HL),A
    LD   HL,RO_PCNT
    INC  (HL)
    LD   HL,RO_CPCNT
    INC  (HL)
    LD   A,(RO_OTYPE)
    OR   A
    RET
.FULL:
    CALL DG_RAISE
    DB   DG_PARAM

; Parse the parameter list and optional result of the provisional routine.

; Install one retained parameter as an activation symbol and emit the copy
; from its caller-stack carrier into the routine's negative IX frame.
;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RO_BIND:
    LD   (RO_CPIDX),A
    LD   A,C
    LD   (RO_AIDX),A
    LD   A,(RO_CPIDX)
    CALL RO_PARAM
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    INC  HL
    LD   B,(HL)
    INC  HL
    LD   A,(HL)
    LD   (RO_OTYPE),A
    LD   (TK_PTR),DE
    LD   A,B
    LD   (TK_LEN),A
    LD   A,(SY_LSLOT)
    LD   (RO_OPOS),A
    LD   C,A
    LD   B,0
    LD   A,(RO_OTYPE)
    CP   AG_FIRST
    LD   D,SY_AGGR+SY_PARAM
    JR   NC,.SYMBOL
.SCALAR:
    OR   SY_PARAM
    LD   D,A
.SYMBOL:
    CALL SY_NEW
    LD   A,(RO_OTYPE)
    CALL SY_TAG
    LD   A,(RO_OTYPE)
    LD   C,A
    LD   A,OP_BIND
    CALL PR_EMITC
    LD   A,(RO_OPOS)
    CALL TR_PUT
    LD   A,(RO_AIDX)
    CALL TR_PUT
    LD   A,(RO_OTYPE)
    CP   AG_FIRST
    JR   C,.SIZE
    CP   AG_VIEW
    LD   A,3
    SBC  A,0
    JR   .ADVANCE
.SIZE:
    CALL EX_WIDTH
.ADVANCE:
    LD   HL,SY_LSLOT
    ADD  A,(HL)
    LD   (HL),A
    OR   A
    RET

; Current token is a non-main routine name.

; Return the positive IX displacement of the current source argument. Every
; later source parameter contributes one address/scalar word; each later open
; string contributes its hidden capacity word as well.
;@ROUTINE IN B,D OUT A,B,C,D,E,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,HL
RO_DISP:
    PUSH BC
    PUSH DE
    LD   A,B
    ADD  A,A
    ADD  A,2
    LD   C,A
    DEC  B
    JR   Z,.DONE
    LD   A,D
    INC  A
    CALL RO_PARAM
.LOOP:
    INC  HL
    INC  HL
    INC  HL
    LD   A,(HL)
    CP   AG_VIEW
    JR   NZ,.NEXT
    INC  C
    INC  C
.NEXT:
    INC  HL                        ; next four-byte parameter entry
    DJNZ .LOOP
.DONE:
    LD   A,C
    POP  DE
    POP  BC
    LD   C,A
    OR   A
    RET

; Return aggregate symbol info in D, byte payload in BC, and exact type ID in
; A. The ordinary symbol-table address determines the parallel type entry.
;@ROUTINE OUT A,BC,D,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,E,HL
RO_SYM:
    CALL SY_FIND
    JP   NC,SY_UNDEF
    PUSH HL
    INC  HL
    INC  HL
    INC  HL
    LD   D,(HL)
    LD   A,D
    LD   (RO_ACNT),A
    INC  HL
    LD   C,(HL)
    INC  HL
    LD   B,(HL)
    POP  HL
    LD   DE,SY_BASE
    OR   A
    SBC  HL,DE
    LD   A,L
    LD   E,0
.IDXLOOP:
    CP   SY_RECB
    JR   C,.INDEXED
    SUB  SY_RECB
    INC  E
    JR   .IDXLOOP
.INDEXED:
    LD   A,E
    LD   E,A
    LD   H,0
    LD   L,E
    LD   DE,AG_SYTAB
    ADD  HL,DE
    LD   A,(HL)
    LD   E,A
    LD   A,(RO_ACNT)
    LD   D,A
    LD   A,E
    OR   A
    RET

; Stage 7 structural operands are emitted whenever their owning operation is
; emitted. They are not expression values and therefore do not consult the
; constant-folding emission flag used by EX_EMITW.
;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL
RO_EMITW:
    LD   A,L
    CALL TR_PUTHL
    LD   A,H
    JP   TR_PUT

; D is the symbol class and BC its byte offset. Emit its opaque root carrier
; and return the exact aggregate type in A.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RO_ROOT:
    CALL RO_SYM
    LD   (RO_OTYPE),A
    CP   AG_VIEW
    JR   NZ,.CLASS
    LD   A,C
    INC  A
    INC  A
    LD   (RO_VCAP),A
.CLASS:
    LD   A,D
    AND  SY_CMASK
    JR   Z,RO_FIXED
    CP   SY_GLOB
    JR   NZ,RO_BYREF
    LD   A,OP_REFG
RO_ALIAS:
    PUSH BC
    CALL TR_OPER
    POP  HL
    CALL RO_EMITW
    JR   RO_TYPED
RO_FIXED:
    PUSH BC
    CALL TG_MUST
    POP  BC
    LD   A,OP_REFRO
    JR   RO_ALIAS
RO_BYREF:
    CP   SY_PARAM
    JP   NZ,EX_ETYPE
    LD   A,OP_REFP
.EMIT:
    CALL PR_EMITC
RO_TYPED:
    LD   A,(RO_OTYPE)
    OR   A
    RET

; Emit one checked postfix chain. A is the current aggregate type and one
; carrier is live on the generated evaluation stack. D returns zero for an
; address path or one when `.length` has already produced a scalar value.
;@ROUTINE IN A OUT A,D,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,E,HL,IX,IY
RO_PATH:
    LD   D,0
RO_SEL:
    PUSH AF
    CALL PR_PEEK
    CP   TK_DOT
    JR   Z,.DOT
    CP   TK_LBRAC
    JP   Z,RO_INDEX
    POP  AF
    LD   D,0
    OR   A
    RET
.DOT:
    POP  AF
    LD   (RO_OTYPE),A
    CALL AC_SAFE
    LD   A,(RO_OTYPE)
    PUSH AF
.FIELD:
    CALL PR_TAKE
    LD   E,TK_NAME
    CALL PR_NEED
    POP  AF
    PUSH AF
    CP   AG_FIRST
    CP   AG_VIEW
    JR   Z,.STRFIELD
    CALL AG_DESC
    LD   A,(HL)
    CP   AG_KSTR
    JR   NZ,RO_FIELD
.STRFIELD:
    LD   HL,KW_LEN
    LD   B,6
    CALL TK_MATCH
    JP   NC,RO_EPATH
    LD   A,(RO_OTYPE)
    CP   AG_VIEW
    JR   Z,.OPENSTR
    CALL AG_DESC
    INC  HL
    LD   C,(HL)                    ; capacity for L <= N validation
    LD   A,OP_LEN
    JR   .LENGTH
.OPENSTR:
    LD   A,(RO_VCAP)
    LD   C,A
    LD   A,OP_VLEN
.LENGTH:
    CALL PR_EMITC
    LD   HL,(TK_POS)
    CALL RO_EMITW
    POP  AF
    LD   A,SY_U8
    LD   D,1
    OR   A
    RET
RO_ENAME:
    CALL DG_RAISE
    DB   DG_UNDEF
RO_FIELD:
    POP  AF
    CALL AG_DESC
    LD   A,(HL)
    CP   AG_KREC
    JP   NZ,EX_ETYPE
    INC  HL
    LD   A,(HL)
    ADD  A,A
    LD   E,A
    LD   D,0
    LD   HL,AG_RTAB
    ADD  HL,DE
    LD   B,(HL)
    INC  HL
    LD   D,(HL)
.LOOP:
    LD   A,D
    OR   A
    JR   Z,RO_ENAME
    LD   A,B
    CALL AG_FIELD
    PUSH DE
    CALL TK_SAME
    POP  DE
    JR   C,.FOUND
    INC  B
    DEC  D
    JR   .LOOP
.FOUND:
    LD   A,B
    CALL AG_FIELD
    LD   DE,AG_FTYPE
    ADD  HL,DE
    LD   A,(HL)
    INC  HL
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    OR   A
    PUSH AF
    LD   (RO_OPOS),DE
    LD   A,OP_FIELD
    CALL TR_OPER
    LD   HL,(RO_OPOS)
    CALL RO_EMITW
    POP  AF
    JP   RO_SEL
RO_INDEX:
    POP  AF
    LD   (RO_OTYPE),A
    CALL AC_SAFE
    LD   A,(RO_VCAP)
    PUSH AF
    LD   A,(RO_OTYPE)
    PUSH AF
.OPERAND:
    LD   HL,(TK_POS)
    PUSH HL
    CALL PR_TAKE
    LD   A,(EX_WANT)
    PUSH AF
    LD   A,(EX_LIVE)
    PUSH AF
    LD   A,1
    LD   (EX_LIVE),A
    LD   A,SY_U16
    LD   (EX_WANT),A
    CALL EX_PARSE
    CALL EX_PURE
    LD   (EX_RMETA),A
    LD   (EX_RVAL),HL
    POP  AF
    LD   (EX_LIVE),A
    POP  AF
    LD   (EX_WANT),A
    LD   A,(EX_RMETA)
    AND  SY_TMASK
    CP   SY_BOOL
    JP   Z,RO_EIDX
    LD   E,TK_RBRAC
    CALL PR_NEED
    POP  HL
    LD   (RO_DPOS),HL
    POP  AF
    LD   E,A
    POP  BC
    LD   A,B
    LD   (RO_VCAP),A
    LD   A,E
    CP   AG_FIRST
    JP   C,EX_ETYPE
    PUSH AF
    CP   AG_VIEW
    JR   Z,RO_OSIDX
    CALL AG_DESC
    LD   A,(HL)
    CP   AG_KSTR
    JR   Z,RO_CHAR
    CP   AG_KARR
    JP   NZ,RO_EPATH
    INC  HL
    LD   A,(HL)                    ; element type
    LD   (RO_OTYPE),A
    INC  HL
    LD   C,(HL)                    ; fixed length
    INC  HL
    LD   B,(HL)
    LD   A,(EX_RMETA)
    AND  SY_KNOWN
    JR   Z,RO_ITEM
    LD   HL,(EX_RVAL)
    OR   A
    SBC  HL,BC
    JR   NC,RO_ERNG
RO_ITEM:
    LD   (RO_OPOS),BC
    LD   A,(RO_OTYPE)
    CALL AG_SIZE
    LD   (RO_OSIZE),HL
    LD   A,OP_INDEX
    CALL TR_OPER
    LD   HL,(RO_OPOS)
    CALL RO_EMITW
    LD   HL,(RO_OSIZE)
    CALL RO_EMITW
    LD   HL,(RO_DPOS)
    CALL RO_EMITW
    POP  AF
    CALL AG_DESC
    INC  HL
    LD   A,(HL)
    JP   RO_SEL
RO_CHAR:
    INC  HL
    LD   C,(HL)                    ; capacity
    LD   A,OP_CHAR
    JR   RO_IDXOP
RO_OSIDX:
    LD   A,(RO_VCAP)
    LD   C,A
    LD   A,OP_VCHAR
RO_IDXOP:
    CALL PR_EMITC
    LD   HL,(RO_DPOS)
    CALL RO_EMITW
    POP  AF
    LD   A,SY_U8
    JP   RO_SEL
RO_EIDX:
    POP  HL
    POP  AF
    POP  BC
    JP   EX_ETYPE
RO_ERNG:
    LD   A,(EX_QUIET)
    OR   A
    JR   NZ,RO_ITEM
    LD   HL,(RO_DPOS)
    LD   (TK_POS),HL
    POP  AF
    JP   EX_EBIG
RO_EPATH:
    POP  AF
    JP   EX_ETYPE

; Address one bounded nested-call frame. Eight bytes retain the source-call
; metadata that nested argument calls may overwrite. The scalar parser keeps
; only its balanced expression context, a source frame keeps its result flag,
; and a service keeps only its source offset temporarily on the compiler
; hardware stack.
;@ROUTINE IN A OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE
RO_FRAME:
    LD   L,A
    LD   H,0
    ADD  HL,HL
    ADD  HL,HL
    ADD  HL,HL
    LD   DE,RO_NTAB
    ADD  HL,DE
    OR   A
    RET

;@ROUTINE OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,D,DE
RO_TOP:
    LD   A,(RO_DEPTH)
    DEC  A
    JR   RO_FRAME

; Parse and validate one scalar argument against the expected type in A while
; preserving the enclosing expression context across nested calls.
;@ROUTINE IN A OUT A,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,IX,IY
RO_ARG:
    LD   D,A
    LD   A,(EX_WANT)
    LD   B,A
    LD   A,(EX_LIVE)
    LD   C,A
    PUSH BC
    PUSH DE
    LD   A,D
    LD   (EX_WANT),A
    LD   A,1
    LD   (EX_LIVE),A
    CALL EX_PARSE
    LD   (RO_OTYPE),A
    LD   (EX_RVAL),HL
    POP  DE
    POP  BC
    LD   A,C
    LD   (EX_LIVE),A
    LD   A,B
    LD   (EX_WANT),A
    LD   E,D
    LD   A,(RO_OTYPE)
    LD   HL,(EX_RVAL)
    CALL EX_FITS
    JP   AC_SAFE

; Parse one call to a retained routine. A is the routine-table index and C is
; zero when the result is discarded or one when its carrier remains live.
;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RO_CALL:
    LD   B,A
    LD   A,(RO_DEPTH)
    CP   RO_NCAP
    JR   C,.ROOM
    CALL DG_RAISE
    DB   DG_DEEP
.ROOM:
    CALL RO_FRAME
    LD   A,C
    PUSH AF
    PUSH HL
    LD   A,B
    CP   RO_MAIN
    JR   Z,.MAIN
    CALL RO_SUBAT
    INC  HL
    INC  HL
    INC  HL
    LD   D,(HL)                    ; parameter start
    INC  HL
    LD   E,(HL)                    ; parameter count
    INC  HL
    LD   B,(HL)                    ; result
    INC  HL
    LD   A,(HL)                    ; label
    INC  HL
    LD   C,(HL)                    ; failure flags
    JR   .FILL
.MAIN:
    LD   D,0                       ; parameter start
    LD   E,0                       ; parameter count
    LD   B,0                       ; result-free
    LD   A,(RO_MFLAG)
    LD   C,A
    LD   A,RO_MDEST
.FILL:
    POP  HL
    LD   (HL),A
    POP  AF
    OR   A
    JR   Z,.LABEL
    SET  6,(HL)
.LABEL:
    INC  HL
    LD   (HL),B
    INC  HL
    LD   (HL),D
    INC  HL
    LD   (HL),E
    INC  HL
    LD   (HL),E                    ; original argument count
    INC  HL
    LD   DE,(TK_POS)
    LD   (HL),E
    INC  HL
    LD   (HL),D
    INC  HL
    LD   (HL),C
    LD   HL,RO_DEPTH
    INC  (HL)
    CALL PR_LEFT
.ARGLOOP:
    CALL RO_TOP
    INC  HL
    INC  HL
    INC  HL
    LD   A,(HL)
    OR   A
    JP   Z,.ARGSDONE
    DEC  HL
    LD   A,(HL)                    ; current parameter table index
    CALL RO_PARAM
    INC  HL
    INC  HL
    INC  HL
    LD   A,(HL)
    LD   D,A
    XOR  A
    LD   (RO_PEND),A
    LD   A,D
    CP   AG_FIRST
    JR   NC,.AGGRARG
    CALL RO_ARG
    JR   .ARGOK
.AGGRARG:
    CALL RO_AGGR
    PUSH AF
    CALL RO_TOP
    INC  HL
    INC  HL
    LD   A,(HL)
    CALL RO_PARAM
    INC  HL
    INC  HL
    INC  HL
    LD   D,(HL)
    POP  AF
    LD   (RO_OTYPE),A
    LD   A,D
    LD   (RO_DTYPE),A
    CP   AG_VIEW
    JR   Z,.OPENSTR
    LD   A,(RO_OTYPE)
    CP   D
    JP   NZ,RO_EARG
    JR   .TYPEOK
.OPENSTR:
    LD   A,(RO_OTYPE)
    CP   AG_VIEW
    JR   Z,.TYPEOK
    CALL RO_CAP
.TYPEOK:
; A cross-bank aggregate parameter must originate at a direct
; program root. Diagnose through the ordinary call-frame unwind.
    CALL RO_TOP
    LD   DE,RO_NFLAG
    ADD  HL,DE
    LD   D,(HL)
    CALL TG_SAME
    JR   Z,.BANKOK
    LD   A,C
    OR   A
    JR   NZ,.BANKOK
    LD   A,DG_CFG
    CALL DG_ISSUE
.BANKOK:
    CALL AC_SAFE
    LD   A,(RO_DTYPE)
    CP   AG_VIEW
    JR   NZ,.ARGOK
    CALL .OPENARG
.ARGOK:
    CALL RO_TOP
    INC  HL
    INC  HL
    INC  (HL)
    INC  HL
    DEC  (HL)
    JR   Z,.ARGSDONE
    LD   E,TK_COMMA
    CALL PR_NEED
    JP   .ARGLOOP

; Convert one concrete or already-open bounded-string carrier into the two-word
; internal call form: actual capacity below the ordinary address carrier.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
.OPENARG:
    LD   A,(RO_OTYPE)
    CP   AG_VIEW
    JR   Z,.FORWARD
    CALL RO_CAP
    LD   (RO_ACNT),A
    XOR  A
    JR   .OPENOK
.FORWARD:
    LD   A,(RO_VCAP)
    LD   (RO_ACNT),A
    LD   A,1
.OPENOK:
    LD   C,A
    LD   A,OP_VIEW
    CALL PR_EMITC
    LD   A,(RO_ACNT)
    CALL TR_PUT
    CALL RO_TOP
    LD   DE,RO_NACNT
    ADD  HL,DE
    INC  (HL)
    OR   A
    RET
.ARGSDONE:
    CALL PR_RIGHT
    CALL RO_TOP
    LD   A,(HL)
    LD   (RO_DEST),A
    INC  HL
    LD   A,(HL)
    LD   (RO_DTYPE),A
    INC  HL
    INC  HL
    INC  HL
    LD   A,(HL)
    LD   (RO_ACNT),A
    INC  HL
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    LD   (RO_DPOS),DE
    INC  HL
    LD   A,(HL)
    LD   (RO_DFLAG),A
    LD   HL,RO_DEPTH
    DEC  (HL)
    LD   A,(RO_DTYPE)
    CP   AG_FIRST
    JR   C,.RESULTOK
    LD   A,(RO_DFLAG)
    LD   D,A
    CALL TG_MUST
.RESULTOK:
    LD   A,(RO_DFLAG)
    AND  RO_FFAIL
    JR   Z,.FAILOK
    LD   A,(RO_DEPTH)
    OR   A
    JP   NZ,AC_ELEAK
.FAILOK:
; Publish one completed call description. RO_DEST contains the packed
; target, kind, and keep-result choice. Target-specific signature fields are
; present only for source routines.
RO_PUB:
    LD   A,OP_CALL
    CALL TR_OPER
    LD   A,(RO_DEST)
    CALL TR_PUT
    AND  RO_FIO
    JR   NZ,.COMMON
    LD   A,(RO_ACNT)
    CALL TR_PUT
    LD   A,(RO_DTYPE)
    CALL TR_PUT
    LD   A,(RO_DFLAG)
    CALL TR_PUT
.COMMON:
    LD   HL,(RO_DPOS)
    CALL RO_EMITW
    CALL RO_PAD
    LD   A,(RO_DFLAG)
    AND  RO_FFAIL
    LD   (RO_PEND),A
    LD   A,(RO_DTYPE)
    OR   A
    RET
RO_EARG:
    LD   HL,RO_DEPTH
    DEC  (HL)
    JP   EX_ETYPE

; Parse a name-rooted aggregate path or aggregate-returning call. The result
; must still be an address path; scalar selection is rejected by this entry.
;@ROUTINE OUT A,C,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,D,DE,HL,IX,IY
RO_AGGR:
    LD   E,TK_NAME
    CALL PR_NEED
    CALL RO_FIND
    JR   NZ,.SYMBOL
    LD   C,1
    CALL RO_CALL
    CP   AG_FIRST
    JP   C,EX_ETYPE
    LD   C,0
    JR   .SUFFIX
.SYMBOL:
    CALL RO_SYM
    LD   A,D
    AND  SY_AGGR
    JP   Z,EX_ETYPE
    LD   A,D
    AND  SY_CMASK
    LD   C,0
    CP   SY_GLOB
    JR   NZ,.ROOTED
    INC  C
.ROOTED:
    PUSH BC
    CALL RO_ROOT
    POP  BC
    LD   A,(RO_OTYPE)
    JR   .SUFFIX
.SUFFIX:
    PUSH BC
    CALL RO_PATH
    POP  BC
    LD   E,A
    LD   A,D
    OR   A
    JP   NZ,EX_ETYPE
    LD   A,E
    CP   AG_FIRST
    JP   C,EX_ETYPE
    OR   A
    RET

; Convert a scalar address path to an ordinary typed expression carrier.
;@ROUTINE IN A,D OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL
RO_LOAD:
    CP   AG_FIRST
    JP   NC,EX_ETYPE
    LD   (RO_OTYPE),A
    LD   A,D
    LD   (RO_ACNT),A
    OR   A
    JR   NZ,.READY
    LD   A,(RO_OTYPE)
    CP   SY_U16
    LD   A,OP_LDX8
    JR   NZ,.EMIT
    LD   A,OP_LDX16
.EMIT:
    CALL TR_OPER
.READY:
    LD   A,(RO_OTYPE)
    OR   A
    RET

; Hooks entered by the scalar primary parser after it has consumed the NAME.
RO_FUNC:
    LD   C,1
    CALL RO_CALL
    OR   A
    JP   Z,EX_ETYPE
    CP   AG_FIRST
    JR   NC,RO_WALK
    OR   A
    RET
RO_WALK:
    CALL RO_PATH
    JR   RO_LOAD

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RO_QUERY:
    LD   HL,(TK_POS)
    LD   (RO_DPOS),HL
    LD   C,1
    JR   RO_SERVE

;@ROUTINE IN A OUT A,B,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,C,D,DE,IX,IY
RO_CAUSE:
    SUB  RO_ERRS-1
    LD   L,A
    LD   H,0
    LD   B,SY_KNOWN+SY_U8
    JP   EX_LIT

; A is the dense service ID and C says whether a successful u8 result is kept.
;@ROUTINE IN A,C OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,C,D,DE,HL,IX,IY
RO_SERVE:
    LD   E,A
    LD   D,0
    LD   HL,KW_SIGS
    ADD  HL,DE
    LD   A,(HL)
    DEC  C
    JR   NZ,.DESC
    OR   RO_FKEEP
.DESC:
    LD   (RO_IO),A
    CALL PR_LEFT
    LD   A,(RO_IO)
    RRCA
    RRCA
    RRCA
    AND  $03
    JR   Z,.CLOSE
    LD   D,A
.ARG:
    LD   HL,(RO_DPOS)
    PUSH HL
    LD   A,D
    CALL RO_ARG
    POP  HL
    LD   (RO_DPOS),HL
.CLOSE:
    CALL PR_RIGHT
    LD   A,(RO_IO)
    LD   (RO_DEST),A
    AND  RO_RES8
    RLCA
    RLCA
    RLCA
.RESULT:
    LD   (RO_DTYPE),A
    LD   A,RO_FFAIL
    LD   (RO_DFLAG),A
    JP   RO_PUB

; Return the declared byte capacity of a bounded-string type ordinal.
;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,DE,HL
RO_CAP:
    CALL AG_DESC
    LD   A,(HL)
    CP   AG_KSTR
    JP   NZ,EX_ETYPE
    INC  HL
    LD   A,(HL)
    OR   A
    RET

;@ROUTINE OUT A,BC,DE,HL,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
RO_PAD:
    LD   HL,(TR_PTR)
    LD   (RO_MODEP),HL
    LD   C,3
    XOR  A
.LOOP:
    CALL TR_PUT
    DEC  C
    JR   NZ,.LOOP
    RET

RO_OBJ:
    CALL RO_ROOT
    JP   RO_WALK

; Current routine name has already been consumed as a complete statement.

; D contains the aggregate symbol info and AC_DVAL its root offset.
RO_LET:
    LD   A,D
    AND  SY_CMASK
    JR   NZ,.WRITABLE
    CALL DG_RAISE
    DB   DG_CONST
.WRITABLE:
    CALL RO_ROOT
    CALL RO_PATH
    LD   E,A
    LD   A,D
    OR   A
    JP   NZ,EX_ETYPE
    LD   A,E
    LD   (RO_OTYPE),A
    CALL PR_EQUAL
    LD   HL,(TK_POS)
    LD   (RO_DPOS),HL
    LD   A,(RO_OTYPE)
    CP   AG_FIRST
    JR   NC,.COPY
    LD   E,A
    CALL EX_RUN
    LD   D,A
    LD   A,(RO_OTYPE)
    LD   E,A
    LD   A,D
    CALL EX_FITS
    LD   A,1
    LD   (RO_KEPT),A
    CALL AC_ROUTE
    LD   A,(RO_OTYPE)
    CP   SY_U16
    LD   A,OP_STX8
    JR   NZ,.EMIT
    LD   A,OP_STX16
.EMIT:
    CALL TR_OPER
    RET
.COPY:
    PUSH AF
    CALL RO_AGGR
    LD   D,A
    POP  AF
    CP   AG_VIEW
    JP   Z,EX_ETYPE
    CP   D
    JP   NZ,EX_ETYPE
    CALL AG_SIZE
    LD   (RO_OSIZE),HL
    LD   A,1
    LD   (RO_KEPT),A
    CALL AC_ROUTE
    LD   A,OP_COPY
    CALL TR_OPER
    LD   HL,(RO_OSIZE)
    CALL RO_EMITW
    LD   HL,(RO_DPOS)
    CALL RO_EMITW
    RET
