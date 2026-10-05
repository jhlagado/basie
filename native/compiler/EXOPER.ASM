;==========================================================================
;  Expression binary operators and entries
;==========================================================================
;
;  The last of the expression parser's three files (EXPR.ASM describes the
;  module, its result convention and its operand stack). Parse the binary
;  operators: comparisons, additive and multiplicative operators by
;  precedence climbing, then `not`, `and`, `or` and `xor` by recursive
;  descent. Check results against destinations, and provide the entries the
;  grammar actions call to parse an expression and store its result.
;
;  Principal entries:
;    EX_CMP    parse a comparison-level expression
;    EX_NOT    parse a `not` expression
;    EX_AND    parse a chain of `and` operands
;    EX_PARSE  parse a complete expression in the current mode
;    EX_FITS   check a result against a destination type
;    EX_RUN    parse a run-time expression, generating its code
;    EX_CONST  parse an expression that must be known, for constants
;    EX_WIDTH  return a scalar type's storage width
;    EX_STORE  store a result into a variable
;    EX_OPEN   keep the left operand of `and`, `or` or `xor`

; Integer *, / and mod bind tighter than + and -, which bind tighter than
; comparisons. B is the minimum precedence: 0 comparison, 1 additive, 2
; multiplicative, 3 a right operand that must not accept any of them.
; Comparison enums occupy EX_OPER values 0..5; token operators are all
; larger, so the reduce path can tell them apart. Comparisons are
; non-associative: a second relation after a reduce is DG_CHAIN.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a comparison-level expression: any binary operator is accepted.

EX_CMP:
    LD   B,0                       ; Accept comparisons and everything above.

;@ROUTINE IN B OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a unary operand, then every binary operator of precedence at least
; B with its right operand, reducing left to right.

EX_CLIMB:
    PUSH BC                        ; Keep the minimum precedence.
    CALL EX_UNARY                  ; Parse the leftmost operand.
    POP  BC                        ; Recover the minimum precedence.
EX_RISE:                       ; A/HL is the left operand so far.
    PUSH AF                        ; Keep its metadata.
    PUSH HL                        ; Keep its value.
    LD   A,B                       ; At level three no operator may follow.
    CP   3                         ; Compare the minimum with three.
    JR   C,EX_LOOK                 ; Below it, look for an operator.
EX_PEAK:                       ; Return the left operand as it stands.
    POP  HL                        ; Recover its value.
    POP  AF                        ; Recover its metadata.
    RET                            ; Return it.
EX_STOP:                       ; Drop the saved precedence, then return.
    POP  BC                        ; Discard it.
    JR   EX_PEAK                   ; Return the left operand.
EX_LOOK:                       ; Is the next token a binary operator?
    PUSH BC                        ; Keep the minimum precedence.
    CALL PR_PEEK                   ; Look at the next token.
    CP   TK_MINUS                  ; Subtraction?
    JR   Z,.ADDPREC                ; Additive.
    CP   TK_PLUS                   ; Addition?
    JR   Z,.ADDPREC                ; Additive.
    CP   TK_STAR                   ; Multiplication?
    JR   Z,.MULPREC                ; Multiplicative.
    CP   TK_SLASH                  ; Division?
    JR   Z,.MULPREC                ; Multiplicative.
    CP   TK_MOD                    ; Remainder?
    JR   Z,.MULPREC                ; Multiplicative.
    POP  BC                        ; Recover the minimum precedence.
    LD   D,A                       ; Keep the token.
    LD   A,B                       ; Comparisons are allowed only at level 0.
    OR   A                         ; Is the minimum zero?
    JR   NZ,EX_PEAK                ; No: the operand ends here.
    LD   A,D                       ; Recover the token.
    PUSH BC                        ; Keep the minimum across the lookup.
    CALL .RELTOKEN                 ; Is it a comparison?
    JR   NC,EX_STOP                ; No: the operand ends here.
    LD   A,C                       ; The comparison's enum...
    LD   (EX_OPER),A               ; ...is the pending operator.
    LD   C,0                       ; Comparisons have precedence zero.
    JR   .HAVEPREC                 ; Compare it with the minimum.
.MULPREC:                      ; A multiplicative operator.
    LD   C,2                       ; Precedence two.
    JR   .SETOP                    ; Record it.
.ADDPREC:                      ; An additive operator.
    LD   C,1                       ; Precedence one.
.SETOP:                        ; The token itself is the operator.
    LD   (EX_OPER),A               ; Record it as pending.
.HAVEPREC:                     ; C is the operator's precedence.
    LD   A,C                       ; Fetch it.
    POP  BC                        ; Recover the minimum in B.
    CP   B                         ; Does the operator bind tightly enough?
    JR   C,EX_PEAK                 ; No: leave it to an outer level.
    INC  A                         ; The right operand binds tighter still,
    LD   C,A                       ; so operators associate to the left.
    PUSH BC                        ; Keep the minimum and the right level.
    CALL PR_TAKE                   ; Consume the operator.
    LD   HL,(TK_POS)               ; Its offset locates its diagnostics...
    LD   (EX_OPPOS),HL             ; ...and any run-time trap.
    POP  DE                        ; D is the minimum, E the right level.
    POP  HL                        ; Recover the left value.
    POP  AF                        ; Recover the left metadata.
    PUSH DE                        ; Keep the levels across the push.
    CALL EX_HOLD                   ; Push the left operand and operator.
    LD   A,(EX_LMETA)              ; A computed left operand
    CALL GX_PUSH                   ; is pushed while the right is computed.
    POP  BC                        ; Recover the levels.
    PUSH BC                        ; Keep them across the right operand.
    LD   B,C                       ; The right operand's minimum level.
    CALL EX_CLIMB                  ; Parse the right operand.
    CALL EX_JOIN                   ; Pop the left operand beneath it.
    LD   A,(EX_OPER)               ; Fetch the operator.
    CP   6                         ; Enums 0..5 are comparisons.
    JR   C,.RELATION               ; Reduce a comparison.
    CALL EX_ARITH                  ; Reduce an arithmetic operator.
    POP  BC                        ; Recover the minimum precedence.
    JP   EX_RISE                   ; Look for a further operator.
.RELATION:                     ; Reduce a comparison.
    CALL .REDUCE                   ; Emit and fold it.
    POP  BC                        ; Discard the levels.
    PUSH AF                        ; Keep the Boolean metadata.
    PUSH HL                        ; Keep its value.
    CALL PR_PEEK                   ; Look at the next token.
    CALL .RELTOKEN                 ; Another comparison?
    JR   C,.CHAINED                ; Yes: comparisons do not chain.
    POP  HL                        ; Recover the value.
    POP  AF                        ; Recover the metadata.
    RET                            ; Return the comparison.

;@ROUTINE IN A OUT C,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,B,HL
; Carry if token A is a comparison, with its EX_EQ..EX_GE enum in C.

.RELTOKEN:
    LD   HL,.RELTAB                ; Address the token-to-enum pairs.
    LD   B,6                       ; Six comparisons.
.SCAN:                         ; Try one pair.
    CP   (HL)                      ; Is this the token?
    JR   Z,.FOUND                  ; Yes: return its enum.
    INC  HL                        ; Skip the token.
    INC  HL                        ; Skip the enum.
    DJNZ .SCAN                     ; Try the next pair.
    OR   A                         ; Not a comparison: clear carry.
    RET                            ; Return.
.FOUND:                        ; HL addresses the matching token.
    INC  HL                        ; Step to its enum.
    LD   C,(HL)                    ; Return it in C.
    SCF                            ; Report a comparison.
    RET                            ; Return.
.RELTAB:                       ; Comparison tokens and their enums.
    DB   TK_EQ,EX_EQ               ; = is equal.
    DB   TK_NE,EX_NE               ; <> is not equal.
    DB   TK_LT,EX_LT               ; < is less.
    DB   TK_LE,EX_LE               ; <= is at most.
    DB   TK_GT,EX_GT               ; > is more.
    DB   TK_GE,EX_GE               ; >= is at least.

.CHAINED:                      ; A comparison follows a comparison.
    POP  HL                        ; Balance the stack.
    POP  AF                        ; Balance the stack.
    CALL DG_RAISE                  ; Report it; no return.
    DB   DG_CHAIN                  ; Diagnostic: chained comparison.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Reduce the comparison EX_OPER on the popped operands to a Boolean. Two
; Booleans compare only for = and <> (GX_BOOL); integers compare at the
; unified width, unsigned (GX_BINOP). Known operands fold to a known
; Boolean.

.REDUCE:
    LD   A,(EX_LMETA)              ; Fetch the left metadata.
    AND  SY_TMASK                  ; Keep its type.
    CP   SY_BOOL                   ; Is the left Boolean?
    JR   NZ,.INTEGER               ; No: compare integers.
    LD   A,(EX_RMETA)              ; Then the right must be Boolean too.
    AND  SY_TMASK                  ; Keep its type.
    CP   SY_BOOL                   ; Compare with Boolean.
    JP   NZ,EX_ETYPE               ; It is not: a type mismatch.
    LD   A,(EX_OPER)               ; Booleans have no order...
    CP   EX_NE+1                   ; ...so only = and <> apply.
    JP   NC,EX_ETYPE               ; An ordering comparison is a mismatch.
    CALL EX_KNOWN                  ; Are both known?
    JR   NZ,.FOLD                  ; Then fold them.
    LD   A,(EX_OPER)               ; = or <>.
    CALL GX_BOOL                   ; Compare them at run time.
    JR   .RUNTIME                  ; A computed Boolean.
.INTEGER:                      ; Integer operands.
    CALL EX_UNIFY                  ; Check them; C is the width.
    CALL EX_KNOWN                  ; Are both known?
    JR   NZ,.FOLD                  ; Then fold them.
    CALL GX_BINOP                  ; Compare them at run time.
.RUNTIME:                      ; The Boolean is in A.
    LD   A,SY_BOOL                 ; A run-time Boolean.
    OR   A                         ; Clear carry.
    RET                            ; Return it.
.FOLD:                         ; Both known: order them, unsigned.
    LD   HL,(EX_LVAL)              ; Fetch the left value.
    LD   DE,(EX_RVAL)              ; Fetch the right value.
    OR   A                         ; Clear carry for the comparison.
    SBC  HL,DE                     ; Compare them.
    LD   B,2                       ; Equal: bit 1.
    JR   Z,.ORDERED                ; Equal.
    LD   B,1                       ; Less: bit 0.
    JR   C,.ORDERED                ; Less.
    LD   B,4                       ; Greater: bit 2.
.ORDERED:                      ; B is the ordering's bit.
    LD   A,(EX_OPER)               ; The relation
    LD   E,A                       ; indexes
    LD   D,0                       ; the table of
    LD   HL,.TRUE                  ; the orderings
    ADD  HL,DE                     ; that make it true.
    LD   A,(HL)                    ; Is this ordering
    AND  B                         ; one of them?
    LD   HL,0                      ; False,
    JR   Z,.CONST                  ; unless it is:
    INC  L                         ; then true.
.CONST:                        ; HL is the folded Boolean.
    LD   A,SY_KNOWN+SY_BOOL        ; A known Boolean.
    OR   A                         ; Clear carry.
    RET                            ; Return it.
.TRUE:                         ; By relation: bit 0 less, 1 equal, 2 greater.
    DB   2,5,1,3,4,6               ; = <> < <= > >=.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a `not` expression: Boolean negation or an integer's bitwise
; complement (GX_NOT), folded when the operand is known. An exact operand
; takes the expected type, u8 or u16; with neither expected it has no type
; and is refused (DG_CLASH).
; `not` binds below comparisons and above `and`, so `not a = b` negates
; the comparison.

EX_NOT:
    CALL PR_PEEK                   ; Look at the next token.
    CP   TK_NOT                    ; Is it `not`?
    JP   NZ,EX_CMP                 ; No: parse a comparison-level operand.
    CALL PR_TAKE                   ; Consume `not`.
    CALL EX_NOT                    ; Parse its operand, `not` included.
    CALL EX_PURE                   ; A failable call may not be enclosed.
    LD   D,A                       ; Keep the operand's metadata.
    AND  SY_TMASK                  ; Keep its type,
    LD   C,A                       ; the result's.
    JR   NZ,.TYPED                 ; A typed operand keeps it.
    LD   A,(EX_WANT)               ; An exact one takes the expected type,
    LD   C,A                       ; which must be an integer (spec 9.12).
    CP   SY_U16                    ; A u16?
    JR   Z,.TYPED                  ; Complement it as a word.
    CP   SY_U8                     ; A u8?
    JP   NZ,EX_ETYPE               ; Neither: the value has no type.
    LD   A,H                       ; A u8: the constant
    OR   A                         ; must fit a byte.
    JP   NZ,EX_ERNG                ; It does not.
.TYPED:                        ; C is the result's type.
    BIT  7,D                       ; SY_KNOWN: is the operand known?
    JR   NZ,.FOLD                  ; Yes: fold it.
    CALL GX_NOT                    ; Complement A or HL.
    LD   A,C                       ; A run-time result of type C.
    OR   A                         ; Clear carry.
    RET                            ; Return it.
.FOLD:                         ; HL is the known operand.
    LD   A,C                       ; A Boolean?
    CP   SY_BOOL                   ; It flips.
    JR   NZ,.INTCONST              ; An integer complements.
    LD   A,L                       ; Fetch the truth value.
    XOR  1                         ; Negate it.
    LD   L,A                       ; Keep the low result.
    LD   H,0                       ; Booleans have a zero high byte.
    JR   .CONST                    ; Return it.
.INTCONST:                     ; Complement a known integer.
    LD   A,L                       ; Fetch the low byte.
    CPL                            ; Complement it.
    LD   L,A                       ; Keep the low result.
    LD   A,H                       ; Fetch the high byte.
    CPL                            ; Complement it.
    LD   H,A                       ; Keep the high result.
    CALL EX_MASK                   ; Wrap it to the width.
.CONST:                        ; HL is the folded result.
    LD   A,C                       ; It has type C...
    OR   SY_KNOWN                  ; ...and is known.
    RET                            ; Return it with carry clear.

; Boolean `and` and `or` short-circuit: after a computed left operand, OR A
; and a jump over the right operand to a label (GX_SKIP), which is defined
; after the right (EX_LOGIC); a known left that decides the result leaves
; the right operand's code discarded (EX_MUTE). Integer `and`, `or` and
; `xor` are reduced like the other integer operators.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a chain of `and` operands, reducing left to right.

EX_AND:
    CALL EX_NOT                    ; Parse the first operand.
.LOOP:                         ; A/HL is the result so far.
    PUSH AF                        ; Keep its metadata.
    PUSH HL                        ; Keep its value.
    CALL PR_PEEK                   ; Look at the next token.
    CP   TK_AND                    ; Another `and`?
    JP   NZ,EX_DONE                ; No: return the result.
    LD   (EX_OPER),A               ; `and` is the pending operator.
    CALL PR_TAKE                   ; Consume it.
    POP  HL                        ; Recover the left value.
    POP  AF                        ; Recover the left metadata.
    CALL EX_OPEN                   ; Keep the left operand.
    CALL EX_NOT                    ; Parse the right operand.
    CALL EX_JOIN                   ; Pop the left operand beneath it.
    CALL EX_LBOOL                  ; Is the left Boolean?
    JR   NZ,.INTEGER               ; No: reduce integer `and`.
    CALL EX_LOGIC                  ; Close the short circuit and fold.
    JR   .LOOP                     ; Look for another `and`.
.INTEGER:                      ; Integer operands.
    CALL EX_ARITH                  ; Reduce the bitwise `and`.
    JR   .LOOP                     ; Look for another `and`.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a complete expression: a chain of `and` operands joined by `or`
; and `xor`, reducing left to right. A failable call may not be the left
; operand of `or`; `xor` takes integers only.

EX_PARSE:
    CALL EX_AND                    ; Parse the first operand.
EX_ORS:                        ; A/HL is the result so far.
    PUSH AF                        ; Keep its metadata.
    PUSH HL                        ; Keep its value.
    CALL PR_PEEK                   ; Look at the next token.
    CP   TK_XOR                    ; An `xor`?
    JR   Z,.OPER                   ; Reduce it.
    CP   TK_OR                     ; An `or`?
    JR   NZ,EX_DONE                ; No: return the result.
    LD   A,(RO_PEND)               ; Is a failable call result pending?
    OR   A                         ; Test the flag.
    JR   NZ,EX_ELEAK               ; Yes: `or` would lose its failure.
    LD   A,TK_OR                   ; Recover the operator token.
.OPER:                         ; A is `or` or `xor`.
    LD   (EX_OPER),A               ; It is the pending operator.
    CALL PR_TAKE                   ; Consume it.
    POP  HL                        ; Recover the left value.
    POP  AF                        ; Recover the left metadata.
    LD   D,A                       ; Keep it.
    LD   A,(EX_OPER)               ; `xor`?
    CP   TK_XOR                    ; It is for integers only.
    JR   NZ,.OPEN                  ; `or` takes Booleans too.
    LD   A,D                       ; The left's type.
    AND  SY_TMASK                  ; Alone.
    CP   SY_BOOL                   ; A Boolean?
    JP   Z,EX_ETYPE                ; Is a mismatch for `xor`.
.OPEN:                         ; D is the left's metadata.
    LD   A,D                       ; Keep the left operand.
    CALL EX_OPEN                   ; Push it or open the short circuit.
    CALL EX_AND                    ; Parse the right operand.
    CALL EX_JOIN                   ; Pop the left operand beneath it.
    CALL EX_LBOOL                  ; Is the left Boolean?
    JR   NZ,EX_ORINT               ; No: reduce the integer operator.
    CALL EX_LOGIC                  ; Close the short circuit and fold.
    JR   EX_ORS                    ; Look for another operator.
EX_DONE:                       ; No further operator at this level.
    POP  HL                        ; Recover the value.
    POP  AF                        ; Recover the metadata.
    RET                            ; Return the result.
EX_ELEAK:                      ; A failable call before `or`.
    CALL AC_ELEAK                  ; Report DG_LEAK; no return.
EX_ORINT:                      ; Integer `or` or `xor`.
    CALL EX_ARITH                  ; Reduce the bitwise operator.
    JR   EX_ORS                    ; Look for another operator.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Keep the left operand A/HL of `and`, `or` or `xor` (EX_OPER) on the
; operand stack while the right is parsed. An integer is pushed if it was
; computed (GX_PUSH). A computed Boolean opens the short circuit (GX_SKIP)
; and its value word holds the label to define after the right operand. A
; known Boolean that decides the result discards the right operand's code
; (EX_MUTE).

EX_OPEN:
    LD   D,A                       ; Keep the metadata.
    AND  SY_TMASK                  ; Its type.
    CP   SY_BOOL                   ; A Boolean?
    JR   Z,.BOOL                   ; It may short-circuit.
    LD   A,D                       ; An integer: keep it,
    CALL EX_HOLD                   ; with the operator.
    LD   A,(EX_LMETA)              ; If it was computed,
    JP   GX_PUSH                   ; push it, and return.
.BOOL:                         ; A Boolean left operand.
    BIT  7,D                       ; SY_KNOWN: is it known?
    JR   NZ,.KNOWN                 ; Then it may decide the result.
    PUSH DE                        ; Keep the metadata.
    LD   A,(EX_OPER)               ; `and` or `or`:
    CALL GX_SKIP                   ; OR A, JP Z or NZ to a new label A.
    POP  DE                        ; D is the metadata.
    LD   L,A                       ; Its value word
    LD   H,0                       ; holds the label.
    LD   A,D                       ; Keep the operand.
    JP   EX_HOLD                   ; With the operator, and return.
.KNOWN:                        ; A known Boolean.
    LD   A,D                       ; Keep it,
    CALL EX_HOLD                   ; with the operator.
    LD   A,(EX_OPER)               ; `and`?
    CP   TK_AND                    ; False decides it;
    LD   C,0                       ; true decides `or`.
    JR   Z,EX_MUTE                 ; Discard the right if it is false.
    INC  C                         ; Discard the right if it is true.

;@ROUTINE IN C OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY,A,HL
; Raise EX_QUIET when the left operand is the constant C that decides the
; short circuit (false for `and`, true for `or`): the right arm will never
; run, so its code is discarded, as the reference compiler discards it.
; EX_POP lowers it again.

EX_MUTE:
    LD   A,(EX_LMETA)              ; Is the left operand known?
    AND  SY_KNOWN                  ; Test its flag.
    RET  Z                         ; No: the right arm may run.
    LD   HL,(EX_LVAL)              ; Fetch the left value.
    LD   A,L                       ; Booleans are zero or one.
    XOR  C                         ; Is it the deciding value?
    RET  NZ                        ; No: the right arm decides the result.
    LD   HL,EX_QUIET               ; Address the quiet count.
    INC  (HL)                      ; The right arm is discarded.
    RET                            ; Return.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Close a Boolean `and` or `or` (EX_OPER); the right operand must be
; Boolean. After a computed left, the right is brought into A and the
; short circuit's label is defined (logicalOrBitwise). After a known
; left, the result is the left if it decided, otherwise the right.

EX_LOGIC:
    LD   A,(EX_RMETA)              ; Fetch the right metadata.
    LD   D,A                       ; Keep it.
    AND  SY_TMASK                  ; Keep its type.
    CP   SY_BOOL                   ; Is it Boolean?
    JP   NZ,EX_ETYPE               ; No: a mismatch with the Boolean left.
    LD   E,A                       ; E is Boolean, for GX_TOREG.
    LD   A,(EX_LMETA)              ; Is the left known?
    RLCA                           ; SY_KNOWN into carry.
    JR   C,.KNOWN                  ; Yes: it decided, or the right does.
    LD   HL,(EX_RVAL)              ; The right's value, if known,
    CALL GX_TOREG                  ; comes into A.
    LD   A,(EX_LVAL)               ; The short circuit's label
    CALL EM_LDEF                   ; is here.
    LD   A,SY_BOOL                 ; A run-time Boolean.
    OR   A                         ; Clear carry.
    RET                            ; Return it.
.KNOWN:                        ; A known left.
    LD   HL,(EX_LVAL)              ; Its value, 0 or 1.
    LD   A,(EX_OPER)               ; `and` is decided by false,
    CP   TK_AND                    ; `or` by true.
    LD   A,L                       ; The value.
    JR   Z,.DECIDE                 ; `and`: zero decides.
    XOR  1                         ; `or`: one decides.
.DECIDE:                       ; A is zero when the left decides.
    OR   A                         ; Did it?
    LD   A,SY_KNOWN+SY_BOOL        ; Then the result is the known left.
    RET  Z                         ; HL is it; carry is clear.
    LD   A,D                       ; Otherwise the right,
    LD   HL,(EX_RVAL)              ; known or computed.
    RET                            ; Carry is clear.

;@ROUTINE IN A,E,HL OUT A,D,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Check result A/HL against destination type E for assignment, passing or
; initialization. An exact constant must fit E and may not become a
; Boolean; the only implicit conversion is u8 to u16; anything else raises
; DG_CLASH. Returns E with the result's SY_KNOWN in A, the metadata in D.

EX_FITS:
    LD   D,A                       ; Keep the metadata.
    AND  SY_TMASK                  ; Is the result typed?
    JR   NZ,.TYPED                 ; Yes: compare the types.
    LD   A,E                       ; An exact constant: what is the target?
    CP   SY_BOOL                   ; A Boolean?
    JP   Z,EX_ETYPE                ; A number is not a Boolean.
    CP   SY_U8                     ; A u8?
    JR   NZ,.EXACT                 ; No: any word fits u16.
    LD   A,H                       ; Does the constant exceed a byte?
    OR   A                         ; Test its high byte.
    JP   NZ,EX_ERNG                ; Yes: it is out of range.
.EXACT:                        ; The constant fits.
    LD   A,D                       ; Keep its known flag...
    AND  SY_KNOWN                  ; ...alone...
    OR   E                         ; ...with the destination type.
    RET                            ; Return it with carry clear.
.TYPED:                        ; A is the result's type.
    CP   E                         ; The destination's type?
    JR   Z,.SAME                   ; Yes: it fits.
    CP   SY_U8                     ; Otherwise only u8...
    JP   NZ,EX_ETYPE               ; ...may convert implicitly...
    LD   A,E                       ; ...and only...
    CP   SY_U16                    ; ...to u16.
    JP   NZ,EX_ETYPE               ; Anything else is a mismatch.
.SAME:                         ; The result fits.
    LD   A,D                       ; Keep its known flag...
    AND  SY_KNOWN                  ; ...alone...
    OR   E                         ; ...with the destination type.
    RET                            ; Return it with carry clear.

;@ROUTINE IN A OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a run-time expression with expected type A, generating its code.
; Clears the pending failable-call state and the operand stack.

EX_RUN:
    LD   (EX_WANT),A               ; Record the expected type.
    XOR  A                         ; Form zero.
    LD   (RO_PEND),A               ; No failable call is pending yet.
    LD   (RO_KEPT),A               ; No carriers are kept beneath one.
    LD   A,1                       ; Turn emission on.
    LD   (EX_LIVE),A               ; What is not yet compiled is refused.
    XOR  A                         ; Form zero.
    LD   (EX_QUIET),A              ; No arm is unevaluated.
    LD   (EX_DEPTH),A              ; Empty the operand stack.
    JP   EX_PARSE                  ; Parse the expression.

;@ROUTINE IN A OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse an expression with expected type A that must be known, for a
; constant declaration or a static initializer. The caller requires the
; result to be known.

EX_CONST:
    LD   (EX_WANT),A               ; Record the expected type.
    XOR  A                         ; Form zero.
    LD   (EX_LIVE),A               ; Turn emission off.
    LD   (EX_QUIET),A              ; No arm is unevaluated.
    LD   (EX_DEPTH),A              ; Empty the operand stack.
    JP   EX_PARSE                  ; Parse the expression.

;@ROUTINE IN A OUT A CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,CARRY
; Return the storage width of scalar type A: two bytes for u16, one for u8
; and Boolean. Locals and parameters advance their frame slot by it.

EX_WIDTH:
    CP   SY_U16                    ; Is it a word?
    LD   A,1                       ; Assume one byte.
    RET  NZ                        ; u8 and Boolean take one.
    INC  A                         ; u16 takes two.
    RET                            ; Return it.

;@ROUTINE IN D,BC CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store the value in the registers into the variable with symbol info D: a
; program variable at blob BC (GX_STORE). A local or parameter, at frame
; offset C, is refused until frames are compiled (65.4 d).

EX_STORE:
    LD   A,D                       ; Fetch the symbol info.
    AND  SY_CMASK                  ; Keep the storage class.
    CP   SY_GLOB                   ; A program variable?
    JP   NZ,TR_OPER                ; No: refuse it for now.
    LD   A,D                       ; Its type
    AND  SY_TMASK                  ; alone.
    JP   GX_STORE                  ; Store A or HL there and return.

EX_EFLOW:                      ; A result or exit the routine does not allow.
    CALL DG_RAISE                  ; Report it; no return.
    DB   DG_FLOW                   ; Diagnostic: invalid control flow.
.FORWARD:                      ; Unreachable: nothing jumps here.
    CALL DG_RAISE                  ; Unreachable: report an unmet forward.
    DB   DG_UNMET                  ; Diagnostic: forward never defined.
