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
;  The module spans three files, consecutive in the image, because ATOM
;  limits one source file to 64K bytes: this one (names, emission, the
;  operand stack, failure exits and the reduction of arithmetic), EXTERM.ASM
;  (primaries and unary operators) and EXOPER.ASM (binary operators and the
;  entries the grammar actions call).
;
;  Principal entries in this file:
;    EX_DECL   check and retain a declaration's name
;    EX_PREP   restore a retained name and write its provisional symbol
;    EX_FRESH  check a routine-local name against symbols and `main`
;    EX_MAIN   test whether the current name is `main`
;    EX_EMIT   append one operation unless emission is suppressed
;    EX_EMITW  append an operand word unless emission is suppressed
;    EX_SAVE   push a result as a pending left operand
;    EX_POP    pop the left operand beneath a right one
;    EX_UNIFY  resolve the width of a binary integer operation
;    EX_CLASS  check that a symbol is a scalar and return its class
;    EX_ARITH  reduce an arithmetic or bitwise operator
;
;  Principal entries elsewhere: EX_RUN and EX_CONST parse an expression
;  for a grammar action, EX_FITS checks it against a destination and
;  EX_STORE stores it (EXOPER.ASM); EX_LIT emits a literal and EX_PURE
;  rejects an enclosed failable call (EXTERM.ASM).
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
