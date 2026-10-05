;==========================================================================
;  Expression parser
;==========================================================================
;
;  Parse one scalar expression, check its types, fold it when its operands
;  are constant, and append its operations to the semantic transcript in
;  postfix order for the code generator to replay. The grammar actions call
;  EX_RUN for a run-time expression and EX_CONST for a compile-time one;
;  the module also holds the declaration-name checks, assignment
;  compatibility, variable stores and the failure exits that the parser's
;  other modules share.
;
;  Principal entries:
;    EX_RUN    parse a run-time expression, emitting its operations
;    EX_CONST  parse an expression without emitting, for constants
;    EX_PARSE  parse an expression in the current mode (nested uses)
;    EX_FITS   check a result against a destination type
;    EX_STORE  emit the store of a result into a variable
;    EX_LOCAL  emit the declaration of a scalar local
;    EX_WIDTH  return a scalar type's storage width
;    EX_DECL   check and retain a declaration's name
;    EX_PREP   restore a retained name and write its provisional symbol
;    EX_FRESH  check a routine-local name against symbols and `main`
;    EX_EMIT   append one operation unless emission is suppressed
;    EX_LIT    emit a literal and return it as a known result
;    EX_PURE   reject a pending failable call inside a larger expression
;
;  Precedence, loosest first: `or` and `xor`; `and`; `not`; the six
;  comparisons, which do not associate; `+` and `-`; `*`, `/` and `mod`;
;  unary `+` and `-`; primaries. `and` and `or` short-circuit when their
;  left operand is Boolean and are bitwise on integers; `xor` is bitwise.
;
;  A result is metadata in A and, when it is constant, its value in HL. The
;  low two bits of the metadata are the type: SY_U8, SY_U16, SY_BOOL, or
;  SY_EXACT for an untyped literal that takes the type of its typed peer or
;  of the expected type EX_WANT. SY_KNOWN (bit 7) marks a value known at
;  compile time. At run time every value is a 16-bit carrier on the stack;
;  u8 and Boolean carriers have a zero high byte. The declared type, not the
;  carrier, decides width and compatibility.
;
;  Constants are still emitted: a literal or constant name emits OP_LIT16
;  and every operator emits its operation, so the transcript always holds
;  the whole computation. Folding computes the value for range checks,
;  constant declarations and static initializers. EX_LIVE clear suppresses
;  emission for the last two.
;
;  A binary operator keeps its left operand on EX_STACK while the right is
;  parsed: sixteen entries (EX_STCAP) of thirteen bytes (EX_STLEN):
;
;    +0  byte  left operand's metadata
;    +1  word  left operand's value
;    +3  byte  EX_QUIET at the time of the push
;    +4  byte  EX_OPER, the pending operator
;    +5  word  EX_OPPOS, the operator's source offset
;    +7  six   EX_VPOS: offset, line and column of the left operand's last
;              primary, for a diagnostic that blames the left operand
;
;  EX_QUIET is nonzero inside the unevaluated right arm of a short circuit
;  whose left operand is constant. There a fault that only a run would
;  meet, such as a constant division by zero, yields a quiet zero rather
;  than a diagnostic (EX_FAULT). Each stack entry saves and restores it.
;
;  Every diagnostic is raised through DG_RAISE or DG_ISSUE, which restore
;  the parse driver's stack (PR_SP) and do not return: the routines here
;  return only on success.

;@ROUTINE OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,DE,HL
; Carry if the current NAME is the retained forward routine's name. Nothing
; sets PR_FORD during parsing (PR_RESET clears it), so this always returns
; carry clear: a remnant of Nucleus's single-forward slice.

EX_ISFWD:
    LD   A,(PR_FORD)               ; Is a forward signature retained?
    OR   A                         ; Test the flag.
    RET  Z                         ; No: return carry clear.
    LD   HL,PR_FNAME               ; Address the forward's name record.
    JP   TK_SAME                   ; Carry if the token spells it.

;@ROUTINE OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,B,DE,HL
; Carry if the current NAME token is `main`, which names the program's main
; body and may not be declared as anything else.

EX_MAIN:
    LD   HL,KW_MAIN                ; Address the spelling "main".
    LD   B,4                       ; It has four characters.
    JP   TK_MATCH                  ; Carry if the token spells it.

;@ROUTINE OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,BC,DE,HL
; Check a declaration's NAME token and retain its spelling in AC_DNAME and
; its position in AC_DPOS, for the symbol written once the declaration is
; complete. `main` raises DG_DUP. EX_KEEP retains the name unchecked.

EX_DECL:
    CALL EX_MAIN                   ; Is the name `main`?
    JR   C,EX_EDUP                 ; Yes: it is already taken.
    CALL EX_ISFWD                  ; Is it the retained forward's name?
    JR   C,EX_EDUP                 ; Yes: it is already taken.
EX_KEEP:                       ; Retain the name without checks.
    LD   HL,AC_DNAME               ; Address the retained-name record.
    CALL TK_KEEP                   ; Keep the spelling's address and length.
    LD   HL,TK_POS                 ; The token's offset, line and column...
    LD   DE,AC_DPOS                ; ...become the declaration's position.
    CALL PR_COPY                   ; Copy the six bytes.
    OR   A                         ; Clear carry for success.
    RET                            ; Return to the declaration action.

EX_EDUP:                       ; A name that is already declared.
    CALL DG_RAISE                  ; Report it; no return.
    DB   DG_DUP                    ; Diagnostic: duplicate name.

;@ROUTINE OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,BC,DE,HL
; Check that the current NAME is neither an ordinary symbol nor `main`;
; either raises DG_DUP. The routine parser checks parameter names with it.

EX_FRESH:
    CALL SY_FIND                   ; Is the name an ordinary symbol?
    JR   C,EX_EDUP                 ; Yes: it is already taken.
    CALL EX_MAIN                   ; Is it `main`?
    JR   C,EX_EDUP                 ; Yes: it is already taken.
    OR   A                         ; Clear carry for success.
    RET                            ; The name is free.

;@ROUTINE OUT A,HL
; Make the retained declaration name (AC_DNAME) the current NAME token
; again, so that the symbol table and the name checks can read it. A
; returns its length and HL its address. Flags are preserved.

EX_RENEW:
    LD   HL,(AC_DNAME)             ; Fetch the retained spelling's address.
    LD   (TK_PTR),HL               ; Make it the token's spelling.
    LD   A,(AC_DLEN)               ; Fetch the retained length.
    LD   (TK_LEN),A                ; Make it the token's length.
    RET                            ; Return with the name current.

;@ROUTINE IN D,BC OUT A,CARRY,HL CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Write the provisional symbol for the retained declaration name, with
; class/type D and payload BC. The name is checked against symbols, routines and services (RO_FRESH) with
; its declaration position as the diagnostic's. BC and DE are preserved.

EX_PREP:
    CALL EX_RENEW                  ; Make the declared name current again.
    PUSH BC                        ; Keep the payload across the checks.
    PUSH DE                        ; Keep the class/type too.
    LD   HL,AC_DPOS                ; A duplicate is reported where the...
    LD   DE,TK_POS                 ; ...name was declared.
    CALL PR_COPY                   ; Copy the six-byte position.
    CALL RO_FRESH                  ; Raise DG_DUP for any collision.
    JR   NC,.CLEAR                 ; RO_FRESH returns only carry clear.
    POP  DE                        ; Unreachable: restore the class/type.
    POP  BC                        ; Unreachable: restore the payload.
    RET                            ; Unreachable: return the carry.
.CLEAR:                        ; The name is free.
    POP  DE                        ; Restore the class/type in D.
    POP  BC                        ; Restore the payload.
    JP   SY_NEW                    ; Write the provisional symbol.

; Emission wrappers. With EX_LIVE clear the same parser evaluates constant
; declarations and static initializers without emitting operations. Each
; preserves C, which the width-selecting callers keep across them.

;@ROUTINE IN A OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,B,DE,HL
; Append operation A, counted as an operation, unless emission is off.

EX_EMIT:
    LD   D,A                       ; Keep the operation code.
    LD   A,(EX_LIVE)               ; Is emission on?
    OR   A                         ; Test it; this clears carry.
    LD   A,D                       ; Recover the operation code.
    RET  Z                         ; Off: emit nothing.
    JP   TR_OPER                   ; Append it as a new operation.

;@ROUTINE IN A OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,B,DE,HL
; Append operand byte A to the current operation unless emission is off.

EX_EMITB:
    LD   D,A                       ; Keep the operand byte.
    LD   A,(EX_LIVE)               ; Is emission on?
    OR   A                         ; Test it; this clears carry.
    LD   A,D                       ; Recover the byte.
    RET  Z                         ; Off: emit nothing.
    JP   TR_PUT                    ; Append it to the operation.

;@ROUTINE IN HL OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,B,DE,HL
; Append operand word HL, low byte first, unless emission is off.

EX_EMITW:
    PUSH HL                        ; Keep the word across the first byte.
    LD   A,L                       ; Low byte first.
    CALL EX_EMITB                  ; Append it.
    POP  HL                        ; Recover the word.
    LD   A,H                       ; Then the high byte.
    JR   EX_EMITB                  ; Append it and return.

;@ROUTINE IN A,BC OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,B,DE,HL
; Append operation A followed by the program address in BC, as a global
; load or store needs.

EX_OPW:
    PUSH BC                        ; Keep the address across the operation.
    CALL EX_EMIT                   ; Append the operation.
    POP  HL                        ; The address becomes the operand word.
    JR   EX_EMITW                  ; Append it and return.

;@ROUTINE IN A OUT HL CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,CARRY,A,DE
; Address operand-stack entry A in HL: EX_STACK plus thirteen times A.

EX_SLOT:
    LD   E,A                       ; Keep the index.
    ADD  A,A                       ; Index times two.
    ADD  A,E                       ; Times three.
    ADD  A,A                       ; Times six.
    ADD  A,A                       ; Times twelve.
    ADD  A,E                       ; Times thirteen, the entry stride.
    LD   E,A                       ; Widen the offset in DE.
    LD   D,0                       ; Sixteen entries fit in a byte offset.
    LD   HL,EX_STACK               ; Fetch the stack base.
    ADD  HL,DE                     ; Address the entry.
    RET                            ; Return it in HL.

;@ROUTINE OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,HL
; Push the pending left operand and its context (EX_LMETA, EX_LVAL,
; EX_QUIET, EX_OPER, EX_OPPOS and EX_VPOS) onto the operand stack. The
; operator's offset must be kept because a nested operation replaces
; EX_OPPOS before the outer one is reduced. A full stack raises DG_DEEP.

EX_PUSH:
    LD   A,(EX_DEPTH)              ; Fetch the stack depth.
    CP   EX_STCAP                  ; Is there room for one more entry?
    JR   NC,.FULL                  ; No: the expression nests too deeply.
    CALL EX_SLOT                   ; Address the free entry.
    LD   A,(EX_LMETA)              ; Fetch the left operand's metadata.
    LD   (HL),A                    ; Save it.
    INC  HL                        ; Step to the value word.
    LD   DE,(EX_LVAL)              ; Fetch the left operand's value.
    LD   (HL),E                    ; Save its low byte.
    INC  HL                        ; Step to the high byte.
    LD   (HL),D                    ; Save its high byte.
    INC  HL                        ; Step to the quiet count.
    LD   A,(EX_QUIET)              ; Fetch the short-circuit quiet count.
    LD   (HL),A                    ; Save it; the right arm may raise it.
    INC  HL                        ; Step to the operator.
    LD   A,(EX_OPER)               ; Fetch the pending operator.
    LD   (HL),A                    ; Save it.
    INC  HL                        ; Step to the operator offset.
    LD   DE,(EX_OPPOS)             ; Fetch the operator's source offset.
    LD   (HL),E                    ; Save its low byte.
    INC  HL                        ; Step to the high byte.
    LD   (HL),D                    ; Save its high byte.
    INC  HL                        ; Step to the left operand's position.
    EX   DE,HL                     ; It is the copy's destination.
    LD   HL,EX_VPOS                ; The last primary's position is the source.
    CALL PR_COPY                   ; Save offset, line and column.
    LD   A,(EX_DEPTH)              ; Fetch the depth again.
    INC  A                         ; Count the new entry.
    LD   (EX_DEPTH),A              ; Publish it.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the new depth in A.

.FULL:                         ; Sixteen operators are already pending.
    CALL DG_RAISE                  ; Report it; no return.
    DB   DG_DEEP                   ; Diagnostic: expression too deep.

;@ROUTINE IN A,HL OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,HL
; Make result A/HL the pending left operand and push it with its context.

EX_SAVE:
    LD   (EX_LMETA),A              ; The result becomes the left metadata.
    LD   (EX_LVAL),HL              ; And the left value.
    JR   EX_PUSH                   ; Push them with the operator context.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,DE,HL
; Make result A/HL the right operand (EX_RMETA, EX_RVAL) and pop the most
; recent left operand and its context. EX_LPOSP returns the address of the
; left operand's saved position, for EX_ELEFT. BC is preserved.

EX_POP:
    LD   (EX_RMETA),A              ; The result becomes the right metadata.
    LD   (EX_RVAL),HL              ; And the right value.
; Every reduction follows EX_SAVE. Keep the defensive test so a future
; parser change cannot turn a broken invariant into a wrapped address
; beyond PR_WEND.
    LD   A,(EX_DEPTH)              ; Fetch the stack depth.
    OR   A                         ; Is anything there to pop?
    JR   Z,EX_EPOP                 ; No: an internal invariant has failed.
    DEC  A                         ; Remove the top entry.
    LD   (EX_DEPTH),A              ; Publish the depth.
    CALL EX_SLOT                   ; Address the removed entry.
    LD   A,(HL)                    ; Fetch the left operand's metadata.
    LD   (EX_LMETA),A              ; Restore it.
    INC  HL                        ; Step to the value word.
    LD   E,(HL)                    ; Fetch its low byte.
    INC  HL                        ; Step to the high byte.
    LD   D,(HL)                    ; Fetch its high byte.
    LD   (EX_LVAL),DE              ; Restore the left value.
    INC  HL                        ; Step to the quiet count.
    LD   A,(HL)                    ; Fetch the count saved at the push.
    LD   (EX_QUIET),A              ; Restore it, ending a quiet right arm.
    INC  HL                        ; Step to the operator.
    LD   A,(HL)                    ; Fetch the pending operator.
    LD   (EX_OPER),A               ; Restore it.
    INC  HL                        ; Step to the operator offset.
    LD   E,(HL)                    ; Fetch its low byte.
    INC  HL                        ; Step to the high byte.
    LD   D,(HL)                    ; Fetch its high byte.
    LD   (EX_OPPOS),DE             ; Restore the operator's offset.
    INC  HL                        ; HL addresses the saved position.
    LD   (EX_LPOSP),HL             ; Keep it for a left-operand diagnostic.
    OR   A                         ; Clear carry for success.
    RET                            ; Return with both operands in place.
EX_EPOP:                       ; A pop with nothing pushed.
    CALL DG_RAISE                  ; Report it; no return.
    DB   DG_BUG                    ; Diagnostic: internal compiler error.

; Range and type failure exits. None returns, except that EX_FAULT returns
; a quiet zero inside the unevaluated arm of a constant short circuit.

EX_ERNG:                       ; The latest primary is out of range.
    LD   HL,EX_VPOS                ; Blame the latest primary's position.
    JR   EX_EPOS                   ; Report it there.
EX_ELEFT:                      ; The left operand is out of range.
    LD   HL,(EX_LPOSP)             ; Blame the popped left operand.
EX_EPOS:                       ; Report DG_RANGE at the position at HL.
    LD   DE,TK_POS                 ; It becomes the diagnostic's position.
    CALL PR_COPY                   ; Copy offset, line and column.
EX_EBIG:                       ; Report DG_RANGE at the current token.
    CALL DG_RAISE                  ; Report it.
    DB   DG_RANGE                  ; Diagnostic: value out of range.
EX_ETYPE:                      ; An operand of the wrong type.
    CALL DG_RAISE                  ; Report it.
    DB   DG_CLASH                  ; Diagnostic: type mismatch.
EX_EZERO:                      ; Constant division by zero; C is the width.
    LD   B,C                       ; A quiet result has the divide's width.
    LD   C,DG_ZERO                 ; Diagnostic: division by zero.
    JR   EX_FAULT                  ; Report it unless quiet.
EX_ECAST:                      ; A constant too large for u8(...).
    LD   B,SY_U8                   ; u8(...) always has a u8 result.
    LD   C,DG_TRUNC                ; Diagnostic: narrowing loses bits.
EX_FAULT:                      ; Fault C for a result of type B.
    LD   A,(EX_QUIET)              ; Is this arm unevaluated?
    OR   A                         ; Test the quiet count.
    JR   NZ,.QUIET                 ; Yes: return a quiet zero instead.
    LD   A,C                       ; Select the diagnostic.
    JP   DG_ISSUE                  ; Report it; no return.
.QUIET:                        ; The fault cannot happen at run time.
    LD   A,B                       ; Return the result's type...
    LD   HL,0                      ; ...with the value zero...
    OR   SY_KNOWN                  ; ...known, and carry clear.
    RET                            ; Return in place of the faulting routine.

;@ROUTINE OUT A,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY
; Zero if the pending left operand is Boolean. A returns its type.

EX_LBOOL:
    LD   A,(EX_LMETA)              ; Fetch the left metadata.
    AND  SY_TMASK                  ; Keep its type.
    CP   SY_BOOL                   ; Is it Boolean?
    RET                            ; Return the comparison in zero.

;@ROUTINE OUT A CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,CARRY
; Return in A the type of the declaration in progress (AC_DINFO).

EX_DTYPE:
    LD   A,(AC_DINFO)              ; Fetch the declaration's class and type.
    AND  SY_TMASK                  ; Keep the type.
    RET                            ; Return it.

;@ROUTINE OUT C,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,DE,HL
; Resolve the width of a binary integer operation from both operands in
; EX_LMETA/EX_LVAL and EX_RMETA/EX_RVAL, returning SY_U8 or SY_U16 in C with
; carry clear. A Boolean operand raises DG_CLASH. An exact constant adopts
; its typed peer's type, or EX_WANT when both are exact, and must fit it.
; Two typed operands widen to u16 if either is u16. B is preserved.

EX_UNIFY:
    CALL EX_LBOOL                  ; Fetch the left type.
    JR   Z,EX_ETYPE                ; Booleans have no arithmetic.
    LD   D,A                       ; D is the left type.
    LD   A,(EX_RMETA)              ; Fetch the right metadata.
    AND  SY_TMASK                  ; Keep its type.
    CP   SY_BOOL                   ; Is it Boolean?
    JR   Z,EX_ETYPE                ; Booleans have no arithmetic.
    LD   E,A                       ; E is the right type.
    LD   A,D                       ; Is the left operand typed?
    OR   A                         ; Test for SY_EXACT.
    JR   NZ,EX_LTYPE               ; Yes: resolve from the left type.
    LD   A,E                       ; The left is exact; is the right typed?
    OR   A                         ; Test for SY_EXACT.
    JR   NZ,.RIGHT                 ; Yes: the left adopts the right's type.
    LD   A,(EX_WANT)               ; Both exact: use the expected type.
    CP   SY_U8                     ; Is a u8 expected?
    JR   Z,.EXACT8                 ; Yes: both constants must fit a byte.
    LD   C,SY_U16                  ; Otherwise compute at u16.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the width.
.EXACT8:                       ; Two exact constants expected as u8.
    LD   HL,(EX_LVAL)              ; Fetch the left value.
    LD   A,H                       ; Does it exceed a byte?
    OR   A                         ; Test its high byte.
    JR   NZ,EX_ELEFT               ; Yes: the left is out of range.
    LD   HL,(EX_RVAL)              ; Fetch the right value.
    LD   A,H                       ; Does it exceed a byte?
    OR   A                         ; Test its high byte.
    JR   NZ,EX_ERNG                ; Yes: the right is out of range.
    LD   C,SY_U8                   ; Compute at u8.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the width.
.RIGHT:                        ; An exact left with a typed right.
    LD   C,E                       ; The operation takes the right's type.
    CP   SY_U8                     ; Is it u8?
    JR   NZ,EX_OK                  ; No: any word fits u16.
    LD   HL,(EX_LVAL)              ; Fetch the exact left value.
    LD   A,H                       ; Does it exceed a byte?
    OR   A                         ; Test its high byte.
    JR   NZ,EX_ELEFT               ; Yes: the left is out of range.
EX_OK:                         ; Shared success return.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the width in C.
EX_LTYPE:                      ; A typed left; D and E are the two types.
    LD   A,E                       ; Is the right operand typed?
    OR   A                         ; Test for SY_EXACT.
    JR   NZ,.BOTH                  ; Yes: combine the two types.
    LD   C,D                       ; The exact right adopts the left's type.
    LD   A,D                       ; Is it u8?
    CP   SY_U8                     ; Compare with u8.
    JR   NZ,EX_OK                  ; No: any word fits u16.
    LD   HL,(EX_RVAL)              ; Fetch the exact right value.
    LD   A,H                       ; Does it exceed a byte?
    OR   A                         ; Test its high byte.
    JP   NZ,EX_ERNG                ; Yes: the right is out of range.
    JR   EX_OK                     ; It fits.
.BOTH:                         ; Two typed operands.
    LD   A,D                       ; Is the left u16?
    CP   SY_U16                    ; Compare with u16.
    JR   Z,.U16                    ; Yes: compute at u16.
    LD   A,E                       ; Is the right u16?
    CP   SY_U16                    ; Compare with u16.
    JR   Z,.U16                    ; Yes: u8 widens implicitly.
    LD   C,SY_U8                   ; Both are u8.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the width.
.U16:                          ; At least one operand is u16.
    LD   C,SY_U16                  ; Compute at u16.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the width.

;@ROUTINE IN A,D OUT A,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY
; Check that symbol info A (also in D) names a scalar, not a type or an
; aggregate, which raise DG_CLASH; return its storage class in A, with zero
; set for a constant. D is preserved.

EX_CLASS:
    AND  SY_TYPE+SY_AGGR           ; A type name or an aggregate?
    JP   NZ,EX_ETYPE               ; Neither is a scalar value.
    LD   A,D                       ; Recover the symbol info.
    AND  SY_CMASK                  ; Keep the storage class; zero is constant.
    RET                            ; Return it.

;@ROUTINE OUT A,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY
; Nonzero when both operands are known at compile time; zero otherwise.

EX_KNOWN:
    LD   A,(EX_LMETA)              ; Is the left operand known?
    AND  SY_KNOWN                  ; Test its flag.
    RET  Z                         ; No: the operation is run-time.
    LD   A,(EX_RMETA)              ; Is the right operand known?
    AND  SY_KNOWN                  ; Test its flag.
    RET                            ; Nonzero only if both are.

;@ROUTINE IN C,HL OUT HL CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,CARRY,A
; Reduce constant HL to width C: a u8 result keeps only its low byte.

EX_MASK:
    LD   A,C                       ; Fetch the operation's width.
    CP   SY_U8                     ; Is it u8?
    RET  NZ                        ; No: keep all sixteen bits.
    LD   H,0                       ; u8 constants wrap modulo 256.
    RET                            ; Return the masked value.

;@ROUTINE IN C,D,E OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,B,DE,HL
; Emit the u8 operation D or the u16 operation E according to width C.

EX_PICK:
    LD   A,C                       ; Fetch the operation's width.
    CP   SY_U8                     ; Is it u8?
    LD   A,D                       ; Assume the u8 operation.
    JR   Z,.PICKED                 ; Yes: keep it.
    LD   A,E                       ; No: take the u16 operation.
.PICKED:                       ; A is the operation to emit.
    JP   EX_EMIT                   ; Emit it and return.

;@ROUTINE IN C,D,E OUT DE,HL,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY,A,B
; Emit the width-selected operation (EX_PICK). Zero means a run-time
; result; nonzero means both operands are known, with the left value in HL
; and the right in DE for folding. C is preserved.

EX_BINOP:
    CALL EX_PICK                   ; Emit the operation.
    CALL EX_KNOWN                  ; Are both operands known?
    RET  Z                         ; No: nothing to fold.
    LD   HL,(EX_LVAL)              ; Fetch the left value.
    LD   DE,(EX_RVAL)              ; Fetch the right value.
    RET                            ; Return them for folding, nonzero.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Reduce the integer operation EX_OPER (the token of +, -, *, /, mod, and,
; or or xor) on the popped operands: emit it at the unified width and fold
; it when both are known. Constants wrap at the operation's width; a known
; zero divisor raises DG_ZERO even when the dividend is run-time.

EX_ARITH:
    CALL EX_UNIFY                  ; Check the operands; C is the width.
    LD   A,(EX_OPER)               ; Fetch the operator token.
    CP   TK_PLUS                   ; Addition?
    JR   Z,.PLUS                   ; Reduce it.
    CP   TK_MINUS                  ; Subtraction?
    JR   Z,.MINUS                  ; Reduce it.
    CP   TK_STAR                   ; Multiplication?
    JR   Z,.TIMES                  ; Reduce it.
    CP   TK_SLASH                  ; Division?
    JP   Z,.DIVIDE                 ; Reduce it.
    CP   TK_MOD                    ; Remainder?
    JP   Z,.MODULO                 ; Reduce it.
    CP   TK_AND                    ; Bitwise and?
    JR   Z,.BITAND                 ; Reduce it.
    CP   TK_XOR                    ; Bitwise exclusive or?
    JR   Z,.BITXOR                 ; Reduce it; otherwise it is `or`.
.BITOR:                        ; Bitwise or.
    LD   DE,OP_OR8*$100+OP_OR16    ; D is the u8 form, E the u16 form.
    CALL EX_BINOP                  ; Emit it; fetch known operands.
    LD   A,C                       ; A run-time result has the width's type.
    RET  Z                         ; Return it if not both known.
    LD   A,L                       ; Fold the low bytes.
    OR   E                         ; Combine them.
    LD   L,A                       ; Keep the low result.
    LD   A,H                       ; Fold the high bytes.
    OR   D                         ; Combine them.
    LD   H,A                       ; Keep the high result.
    JP   .CONST                    ; Return the known result.
.BITXOR:                       ; Bitwise exclusive or.
    LD   DE,OP_XOR8*$100+OP_XOR16  ; D is the u8 form, E the u16 form.
    CALL EX_BINOP                  ; Emit it; fetch known operands.
    LD   A,C                       ; A run-time result has the width's type.
    RET  Z                         ; Return it if not both known.
    LD   A,L                       ; Fold the low bytes.
    XOR  E                         ; Combine them.
    LD   L,A                       ; Keep the low result.
    LD   A,H                       ; Fold the high bytes.
    XOR  D                         ; Combine them.
    LD   H,A                       ; Keep the high result.
    JP   .CONST                    ; Return the known result.
.BITAND:                       ; Bitwise and.
    LD   DE,OP_AND8*$100+OP_AND16  ; D is the u8 form, E the u16 form.
    CALL EX_BINOP                  ; Emit it; fetch known operands.
    LD   A,C                       ; A run-time result has the width's type.
    RET  Z                         ; Return it if not both known.
    LD   A,L                       ; Fold the low bytes.
    AND  E                         ; Combine them.
    LD   L,A                       ; Keep the low result.
    LD   A,H                       ; Fold the high bytes.
    AND  D                         ; Combine them.
    LD   H,A                       ; Keep the high result.
    JP   .CONST                    ; Return the known result.
.PLUS:                         ; Addition.
    LD   D,OP_ADD8                 ; The u8 form.
    LD   E,OP_ADD16                ; The u16 form.
    CALL EX_BINOP                  ; Emit it; fetch known operands.
    JP   Z,.RUNTIME                ; Not both known: a run-time result.
    ADD  HL,DE                     ; Fold modulo 65536.
    JR   .CONST                    ; Mask to the width and return.
.MINUS:                        ; Subtraction.
    LD   D,OP_SUB8                 ; The u8 form.
    LD   E,OP_SUB16                ; The u16 form.
    CALL EX_BINOP                  ; Emit it; fetch known operands.
    JR   Z,.RUNTIME                ; Not both known: a run-time result.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Fold modulo 65536.
    JR   .CONST                    ; Mask to the width and return.
.TIMES:                        ; Multiplication.
    LD   D,OP_MUL8                 ; The u8 form.
    LD   E,OP_MUL16                ; The u16 form.
    CALL EX_BINOP                  ; Emit it; fetch known operands.
    JR   Z,.RUNTIME                ; Not both known: a run-time result.
; Constant multiplication modulo 65536 by sixteen shift-and-add steps: each
; set bit of DE, lowest first, adds the correspondingly doubled HL to BC.
    PUSH BC                        ; Keep the width in C.
    LD   BC,0                      ; Clear the product.
    LD   A,16                      ; One step per multiplier bit.
.MULLOOP:                      ; Consider one multiplier bit.
    SRL  D                         ; Shift the multiplier right...
    RR   E                         ; ...taking its low bit into carry.
    JR   NC,.MULSKIP               ; A clear bit adds nothing.
    PUSH HL                        ; Keep the doubled multiplicand.
    ADD  HL,BC                     ; Add it to the product.
    LD   B,H                       ; The sum is the new product.
    LD   C,L                       ; Complete BC.
    POP  HL                        ; Recover the multiplicand.
.MULSKIP:                      ; Prepare the next bit's weight.
    ADD  HL,HL                     ; Double the multiplicand.
    DEC  A                         ; One step fewer.
    JR   NZ,.MULLOOP               ; Continue through all sixteen bits.
    LD   H,B                       ; Return the product...
    LD   L,C                       ; ...in HL.
    POP  BC                        ; Restore the width.
    JR   .CONST                    ; Mask to the width and return.
.DIVIDE:                       ; Division.
    LD   DE,OP_DIV8*$100+OP_DIV16  ; D is the u8 form, E the u16 form.
    JR   .DIVMOD                   ; Share the divide path.
.MODULO:                       ; Remainder.
    LD   DE,OP_MOD8*$100+OP_MOD16  ; D is the u8 form, E the u16 form.
.DIVMOD:                       ; Division and remainder.
    CALL EX_PICK                   ; Emit the operation.
    LD   HL,(EX_OPPOS)             ; The operator's offset locates the...
    CALL EX_EMITW                  ; ...run-time divide-by-zero trap.
; A divisor known to be zero is invalid even when the dividend is dynamic.
; The fault helper also implements constant short-circuit suppression, so
; the unevaluated Boolean arm remains admissible.
    LD   A,(EX_RMETA)              ; Is the divisor known?
    AND  SY_KNOWN                  ; Test its flag.
    JR   Z,.FOLD                   ; No: it is checked at run time.
    LD   HL,(EX_RVAL)              ; Fetch the known divisor.
    LD   A,H                       ; Is it zero?
    OR   L                         ; Test both bytes.
    JP   Z,EX_EZERO                ; Yes: report it, or return a quiet zero.
.FOLD:                         ; The divisor is nonzero or unknown.
    CALL EX_KNOWN                  ; Are both operands known?
    JR   Z,.RUNTIME                ; No: a run-time result.
; The exact-divisor check above proves DE nonzero here. Constant unsigned
; division uses a bounded subtraction loop.
    LD   DE,(EX_RVAL)              ; DE is the divisor.
    LD   HL,(EX_LVAL)              ; HL is the dividend.
    PUSH BC                        ; Keep the width in C.
    LD   BC,0                      ; Clear the quotient.
.DIVLOOP:                      ; Subtract the divisor once more.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Take the divisor from the remainder.
    JR   C,.DIVDONE                ; A borrow means it no longer fits.
    INC  BC                        ; Count one more in the quotient.
    JR   .DIVLOOP                  ; Continue.
.DIVDONE:                      ; The last subtraction overshot.
    ADD  HL,DE                     ; Restore the remainder.
    LD   A,(EX_OPER)               ; Which result is wanted?
    CP   TK_MOD                    ; The remainder?
    JR   Z,.RESULT                 ; Yes: it is in HL.
    LD   H,B                       ; No: return the quotient...
    LD   L,C                       ; ...in HL.
.RESULT:                       ; HL is the folded result.
    POP  BC                        ; Restore the width.
    OR   A                         ; Clear carry.
.CONST:                        ; HL is a known result of width C.
    CALL EX_MASK                   ; Wrap it to the width.
    LD   A,C                       ; The result has the width's type...
    OR   SY_KNOWN                  ; ...and is known.
    RET                            ; Return it.
.RUNTIME:                      ; The result is computed at run time.
    LD   A,C                       ; It has the width's type.
    OR   A                         ; Clear carry.
    RET                            ; Return it.

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
