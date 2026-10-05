;==========================================================================
;  Expression parser
;==========================================================================
;
;  Parse one scalar expression, check its types, fold it when its operands
;  are known, and generate the code of the rest as each step is reached,
;  in the reference compiler's templates (GENEXPR.ASM, design decision
;  D45). The grammar actions call EX_RUN for a run-time expression and
;  EX_CONST for a compile-time one; the module also holds the
;  declaration-name checks, assignment compatibility, variable stores and
;  the failure exits that the parser's other modules share.
;
;  The module spans three files, consecutive in the image, because ATOM
;  limits one source file to 64K bytes: this one (names, the operand stack,
;  failure exits and the reduction of arithmetic), EXTERM.ASM (primaries
;  and unary operators) and EXOPER.ASM (binary operators and the entries
;  the grammar actions call).
;
;  Principal entries in this file:
;    EX_DECL   check and retain a declaration's name
;    EX_PREP   restore a retained name and write its provisional symbol
;    EX_FRESH  check a routine-local name against symbols and `main`
;    EX_MAIN   test whether the current name is `main`
;    EX_SAVE   push a result as a pending left operand
;    EX_POP    pop the left operand beneath a right one
;    EX_UNIFY  resolve the width of a binary integer operation
;    EX_CLASS  check that a symbol is a scalar and return its class
;    EX_ARITH  reduce an arithmetic or bitwise operator
;    EX_TIMES  multiply two words, reporting overflow
;
;  Principal entries elsewhere: EX_RUN and EX_CONST parse an expression
;  for a grammar action, EX_FITS checks it against a destination and
;  EX_STORE stores it (EXOPER.ASM); EX_LIT returns a literal (EXTERM.ASM).
;
;  Precedence, loosest first: `or` and `xor`; `and`; `not`; the six
;  comparisons, which do not associate; `+` and `-`; `*`, `/` and `mod`;
;  unary `+` and `-`; primaries. `and` and `or` short-circuit when their
;  left operand is Boolean and are bitwise on integers; `xor` is bitwise.
;
;  A result is metadata in A and, when it is known, its value in HL. The
;  low two bits of the metadata are the type: SY_U8, SY_U16, SY_BOOL, or
;  SY_EXACT for an untyped value that takes the type of its typed peer or
;  of its destination. SY_KNOWN (bit 7) marks a value known at compile
;  time; it generates no code until something needs it in the registers.
;  A value not known is in the registers when the parser returns it: A for
;  a u8 or a Boolean, HL for a u16, as in the reference compiler.
;
;  Folding follows the reference: a typed operation wraps at its width, and
;  two exact operands give an exact result. The reference's exact values
;  reach 32 bits and may be negative; the native compiler's are sixteen-bit
;  and unsigned, so an exact result outside 0..65535 is refused (DG_RANGE)
;  rather than folded differently.
;
;  A binary operator keeps its left operand on EX_STACK while the right is
;  parsed: sixteen entries (EX_STCAP) of thirteen bytes (EX_STLEN):
;
;    +0  byte  left operand's metadata
;    +1  word  left operand's value; for a computed Boolean left of `and`
;              or `or`, the label its short circuit jumps to
;    +3  byte  EX_QUIET at the time of the push
;    +4  byte  EX_OPER, the pending operator
;    +5  word  EX_OPPOS, the operator's source offset
;    +7  six   EX_VPOS: offset, line and column of the left operand's last
;              primary, for a diagnostic that blames the left operand
;
;  A computed left operand is also pushed on the machine stack (GX_PUSH)
;  while the right is computed, and popped beneath it.
;
;  EX_QUIET is nonzero inside the right arm of a short circuit whose
;  constant left operand decides it. The reference compiles that arm and
;  discards its code; here the emitter writes nothing while EX_QUIET is
;  nonzero (EM_QUIET). Each stack entry saves and restores it.
;
;  Every diagnostic is raised through DG_RAISE or DG_ISSUE, which restore
;  the parse driver's stack (PR_SP) and do not return: the routines here
;  return only on success.

;@ROUTINE OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,B,DE,HL
; Carry if the current NAME token is `main`, which names the program's main
; body and may not be declared as anything else.

EX_MAIN:
    LD   HL,KW_MAIN                ; Address the spelling "main".
    LD   B,4                       ; It has four characters.
    JP   TK_MATCH                  ; Carry if the token spells it.

;@ROUTINE OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,BC,DE,HL
; Retain a declaration's NAME token, its spelling in AC_DNAME and its
; position in AC_DPOS, for the symbol written once the declaration is
; complete, which is checked then (EX_PREP). `main` is a name like any
; other until main is declared.

EX_DECL:
EX_KEEP:                       ; Retain the name.
    LD   HL,AC_DNAME               ; Address the retained-name record.
    CALL TK_KEEP                   ; Keep the spelling's address and length.
    LD   HL,TK_POS                 ; The token's offset, line and column...
    LD   DE,AC_DPOS                ; ...become the declaration's position.
    CALL PR_COPY                   ; Copy the six bytes.
    OR   A                         ; Clear carry for success.
    RET                            ; Return to the declaration action.

EX_EDUP:                       ; A name that is already declared.
    CALL DG_RNAME                  ; Report it, named; no return.
    DB   DG_DUP                    ; Diagnostic: duplicate name.

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
; class/type D and payload BC. The name is checked against routines and
; services (RO_FRESH: a duplicate at top level, hidden by a local or local
; constant in a body) and symbols (SY_NEW), with its declaration position
; as the diagnostic's. BC and DE are preserved.

EX_PREP:
    CALL EX_RENEW                  ; Make the declared name current again.
    PUSH BC                        ; Keep the payload across the checks.
    PUSH DE                        ; Keep the class/type too.
    LD   HL,AC_DPOS                ; A collision is reported where the...
    LD   DE,TK_POS                 ; ...name was declared.
    CALL PR_COPY                   ; Copy the six-byte position.
    LD   A,(RO_BODY)               ; In a body
    OR   A                         ; a declaration
    LD   A,DG_HIDE                 ; would hide
    JR   NZ,.CHECK                 ; a routine's or a service's name;
    LD   A,DG_DUP                  ; at top level it would repeat it.
.CHECK:                        ; A is the diagnostic.
    CALL RO_FRESH                  ; Raise it for a routine or a service.
    POP  DE                        ; Restore the class/type in D.
    POP  BC                        ; Restore the payload.
    JP   SY_NEW                    ; Write the provisional symbol.

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

; Range and type failure exits. None returns. A fault inside the discarded
; arm of a constant short circuit is reported too, as the reference
; compiler reports it.

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
EX_EXACT:                      ; An exact value the native compiler can't hold.
    CALL DG_RAISE                  ; Report it.
    DB   DG_EXACT                  ; Diagnostic: native-exact.
EX_EZERO:                      ; Division by a known zero.
    CALL DG_RAISE                  ; Report it.
    DB   DG_ZERO                   ; Diagnostic: division by zero.
EX_ECAST:                      ; A constant too large for u8(...).
    CALL DG_RAISE                  ; Report it.
    DB   DG_TRUNC                  ; Diagnostic: narrowing loses bits.

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
; EX_LMETA/EX_LVAL and EX_RMETA/EX_RVAL, returning SY_EXACT, SY_U8 or SY_U16
; in C with carry clear. A Boolean operand raises DG_CLASH. An exact
; constant adopts its typed peer's type and must fit it; two exact ones
; stay exact (the reference's foldExact). Two typed operands widen to u16 if
; either is u16. B is preserved.

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
    LD   C,A                       ; Both exact: the result is exact too,
    RET                            ; with carry clear (folded unwrapped).
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

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Reduce the integer operation EX_OPER (the token of +, -, *, /, mod, and,
; or or xor) on the popped operands at the unified width. Known operands
; fold, wrapping at a typed width; an exact result that leaves 0..65535 is
; refused with DG_RANGE, since the native compiler folds in sixteen bits
; where the reference's exact values reach 32. Otherwise the reference's
; code for the operation is generated (GX_BINOP). A known zero divisor
; raises DG_ZERO even when the dividend is run-time.

EX_ARITH:
    CALL EX_UNIFY                  ; Check the operands; C is the width.
    LD   A,(EX_OPER)               ; Fetch the operator token.
    CP   TK_SLASH                  ; Division?
    JR   Z,.DIVIDES                ; Its divisor may not be a known zero.
    CP   TK_MOD                    ; Remainder?
    JR   NZ,.CHECKED               ; Anything else divides by nothing.
.DIVIDES:                      ; A division or remainder.
    LD   A,(EX_RMETA)              ; Is the divisor known?
    AND  SY_KNOWN                  ; Test its flag.
    JR   Z,.CHECKED                ; No: DIV16 checks it at run time.
    LD   HL,(EX_RVAL)              ; Fetch the known divisor.
    LD   A,H                       ; Is it zero?
    OR   L                         ; Test both bytes.
    JP   Z,EX_EZERO                ; Yes: report it.
.CHECKED:                      ; The operands are acceptable.
    CALL EX_KNOWN                  ; Are both known?
    JR   NZ,.FOLD                  ; Then fold them.
    PUSH BC                        ; Keep the width.
    CALL GX_BINOP                  ; Generate the operation.
    POP  BC                        ; C is the width.
    LD   A,C                       ; A run-time result of that type.
    OR   A                         ; Clear carry.
    RET                            ; Return it.
.FOLD:                         ; Both are known: compute the result.
    LD   HL,(EX_LVAL)              ; HL is the left value.
    LD   DE,(EX_RVAL)              ; DE is the right value.
    LD   A,(EX_OPER)               ; Fetch the operator token.
    CP   TK_PLUS                   ; Addition?
    JR   Z,.PLUS                   ; Fold it.
    CP   TK_MINUS                  ; Subtraction?
    JR   Z,.MINUS                  ; Fold it.
    CP   TK_STAR                   ; Multiplication?
    JR   Z,.TIMES                  ; Fold it.
    CP   TK_SLASH                  ; Division?
    JR   Z,.DIVMOD                 ; Fold it.
    CP   TK_MOD                    ; Remainder?
    JR   Z,.DIVMOD                 ; Fold it.
    LD   B,A                       ; Bitwise: keep the operator.
    LD   A,L                       ; The low bytes first.
    CALL .BITS                     ; Combine them.
    LD   L,A                       ; The low result.
    LD   A,H                       ; Then the high bytes:
    LD   E,D                       ; D is the right's.
    CALL .BITS                     ; Combine them.
    LD   H,A                       ; The high result.
    JR   .CONST                    ; Mask to the width and return.
.PLUS:                         ; Addition.
    ADD  HL,DE                     ; Fold modulo 65536.
    JR   .CARRY                    ; Carry means an exact value too large.
.MINUS:                        ; Subtraction.
    OR   A                         ; Clear carry for the subtraction.
    SBC  HL,DE                     ; Fold modulo 65536.
    JR   .CARRY                    ; Borrow means an exact value below zero.
.TIMES:                        ; Multiplication.
    PUSH BC                        ; Keep the width.
    CALL EX_TIMES                  ; HL is the product, carry if it overflowed.
    POP  BC                        ; C is the width; POP keeps the carry.
.CARRY:                        ; Carry if the result left 0..65535.
    JR   NC,.CONST                 ; It did not.
    LD   A,C                       ; Is the width exact?
    OR   A                         ; Typed widths wrap.
    JR   NZ,.CONST                 ; Keep the wrapped value.
    JP   EX_EXACT                  ; An exact value beyond 16 bits: refuse it.
.DIVMOD:                       ; Division and remainder.
; The divisor check above proves DE nonzero here. Constant unsigned
; division uses a bounded subtraction loop.
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
.CONST:                        ; HL is a known result of width C.
    CALL EX_MASK                   ; Wrap it to the width.
    LD   A,C                       ; The result has the width's type...
    OR   SY_KNOWN                  ; ...and is known; carry is clear.
    RET                            ; Return it.

;@ROUTINE IN A,B,E OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Combine byte A with byte E by the bitwise operator B: `and`, `or` or
; `xor`.

.BITS:                         ; A and E are bytes, B the operator.
    PUSH BC                        ; Keep the caller's BC.
    LD   C,A                       ; Keep the left byte.
    LD   A,B                       ; Which operator?
    CP   TK_AND                    ; `and`?
    LD   A,C                       ; The left byte again.
    JR   Z,.AND                    ; And it.
    LD   A,B                       ; `xor`?
    CP   TK_XOR                    ; Or `or`.
    LD   A,C                       ; The left byte again.
    JR   Z,.XOR                    ; Exclusive or.
    OR   E                         ; `or`.
    JR   .BITDONE                  ; Done.
.AND:                          ; `and`.
    AND  E                         ; Combine.
    JR   .BITDONE                  ; Done.
.XOR:                          ; `xor`.
    XOR  E                         ; Combine.
.BITDONE:                      ; A is the result.
    POP  BC                        ; Restore BC.
    RET                            ; Return it.

;@ROUTINE IN DE,HL OUT HL,CARRY CLOBBERS A,BC,DE,ZERO,SIGN,PARITY,HALFCARRY
; Multiply HL by DE modulo 65536, with carry when the true product does
; not fit sixteen bits. Each of the sixteen steps doubles the product and
; adds HL when the multiplier's next bit, highest first, is set; a carry
; out of either is shifted into the bottom of DE as the multiplier's bits
; leave its top, so DE ends nonzero exactly when the product overflowed.

EX_TIMES:
    LD   B,H                       ; BC is the multiplicand.
    LD   C,L                       ; Complete it.
    LD   HL,0                      ; The product starts at zero.
    LD   A,16                      ; One step per multiplier bit.
.LOOP:                         ; Consider the next bit.
    ADD  HL,HL                     ; Double the product; carry is an overflow.
    RL   E                         ; The overflow enters DE's bottom,
    RL   D                         ; and the multiplier's top bit leaves.
    JR   NC,.NEXT                  ; A clear bit adds nothing.
    ADD  HL,BC                     ; Add the multiplicand.
    JR   NC,.NEXT                  ; Without a carry nothing overflowed.
    SET  0,E                       ; Record the overflow.
.NEXT:                         ; The step is done.
    DEC  A                         ; One fewer.
    JR   NZ,.LOOP                  ; Through all sixteen.
    LD   A,D                       ; Any overflow recorded?
    OR   E                         ; Zero if none.
    ADD  A,$FF                     ; Carry unless A was zero.
    RET                            ; HL is the product.
