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
;    EX_RUN    parse a run-time expression, emitting its operations
;    EX_CONST  parse an expression without emitting, for constants
;    EX_WIDTH  return a scalar type's storage width
;    EX_LOCAL  emit the declaration of a scalar local
;    EX_STORE  store a result into a variable

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
; Booleans compare only for = and <> (OP_LCMP); integers compare at the
; unified width (OP_CMP8, OP_CMP16), unsigned. The enum follows the
; operation. Known operands fold to a known Boolean.

.REDUCE:
    LD   A,(EX_LMETA)              ; Fetch the left metadata.
    AND  SY_TMASK                  ; Keep its type.
    LD   D,A                       ; D is the left type.
    LD   A,(EX_RMETA)              ; Fetch the right metadata.
    AND  SY_TMASK                  ; Keep its type.
    LD   E,A                       ; E is the right type.
    LD   A,D                       ; Is the left Boolean?
    CP   SY_BOOL                   ; Compare with Boolean.
    JR   NZ,.INTEGER               ; No: compare integers.
    LD   A,E                       ; Then the right must be Boolean too.
    CP   SY_BOOL                   ; Compare with Boolean.
    JP   NZ,EX_ETYPE               ; It is not: a type mismatch.
    LD   A,(EX_OPER)               ; Booleans have no order...
    CP   EX_NE+1                   ; ...so only = and <> apply.
    JP   NC,EX_ETYPE               ; An ordering comparison is a mismatch.
    LD   A,OP_LCMP                 ; Compare Booleans.
    JR   .EMIT                     ; Emit it.
.INTEGER:                      ; Integer operands.
    CALL EX_UNIFY                  ; Check them; C is the width.
    LD   A,C                       ; Is it u8?
    CP   SY_U8                     ; Compare with u8.
    LD   A,OP_CMP8                 ; Assume the byte comparison.
    JR   Z,.EMIT                   ; Yes: keep it.
    LD   A,OP_CMP16                ; No: the word comparison.
.EMIT:                         ; Emit the comparison.
    CALL EX_EMIT                   ; Emit the operation.
    LD   A,(EX_OPER)               ; Its operand is the enum.
    CALL EX_EMITB                  ; Emit it.
    CALL EX_KNOWN                  ; Are both operands known?
    LD   A,SY_BOOL                 ; A run-time Boolean...
    RET  Z                         ; ...if not.
    LD   HL,(EX_LVAL)              ; Fold: fetch the left value.
    LD   DE,(EX_RVAL)              ; Fetch the right value.
    OR   A                         ; Clear carry for the comparison.
    SBC  HL,DE                     ; Compare them, unsigned.
    LD   A,(EX_OPER)               ; Fetch the enum; flags survive.
    JR   Z,.EQUAL                  ; Equal.
    JR   C,.LESS                   ; Less.
    LD   C,1                       ; Greater: C is one.
    JR   .SELECT                   ; Map the relation.
.EQUAL:                        ; The operands are equal.
    LD   C,0                       ; C is zero.
    JR   .SELECT                   ; Map the relation.
.LESS:                         ; The left is less.
    LD   C,$FF                     ; C is minus one.
.SELECT:                       ; Map the requested relation.
; C is -1, 0, or 1. Map the requested relation to a Boolean.
    LD   B,A                       ; Keep the enum.
    LD   HL,0                      ; Assume false.
    LD   A,B                       ; Recover the enum.
    CP   EX_EQ                     ; Equal?
    JR   Z,.IFEQUAL                ; Test it.
    CP   EX_NE                     ; Not equal?
    JR   Z,.IFUNEQ                 ; Test it.
    CP   EX_LT                     ; Less?
    JR   Z,.IFLESS                 ; Test it.
    CP   EX_LE                     ; At most?
    JR   Z,.IFATMOST               ; Test it.
    CP   EX_GT                     ; More?
    JR   Z,.IFMORE                 ; Test it; otherwise at least.
    LD   A,C                       ; At least: true unless less.
    CP   $FF                       ; Was it less?
    JR   Z,.CONST                  ; Yes: false.
    INC  L                         ; No: true.
    JR   .CONST                    ; Return it.
.IFEQUAL:                      ; Equal: true when C is zero.
    LD   A,C                       ; Fetch the ordering.
    OR   A                         ; Is it zero?
    JR   NZ,.CONST                 ; No: false.
    INC  L                         ; Yes: true.
    JR   .CONST                    ; Return it.
.IFUNEQ:                       ; Not equal: true when C is nonzero.
    LD   A,C                       ; Fetch the ordering.
    OR   A                         ; Is it zero?
    JR   Z,.CONST                  ; Yes: false.
    INC  L                         ; No: true.
    JR   .CONST                    ; Return it.
.IFLESS:                       ; Less: true when C is minus one.
    LD   A,C                       ; Fetch the ordering.
    CP   $FF                       ; Was it less?
    JR   NZ,.CONST                 ; No: false.
    INC  L                         ; Yes: true.
    JR   .CONST                    ; Return it.
.IFATMOST:                     ; At most: true unless greater.
    LD   A,C                       ; Fetch the ordering.
    CP   1                         ; Was it greater?
    JR   Z,.CONST                  ; Yes: false.
    INC  L                         ; No: true.
    JR   .CONST                    ; Return it.
.IFMORE:                       ; More: true when C is one.
    LD   A,C                       ; Fetch the ordering.
    CP   1                         ; Was it greater?
    JR   NZ,.CONST                 ; No: false.
    INC  L                         ; Yes: true.
.CONST:                        ; HL is the folded Boolean.
    LD   A,SY_KNOWN+SY_BOOL        ; A known Boolean.
    OR   A                         ; Clear carry.
    RET                            ; Return it.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a `not` expression: Boolean negation (OP_LNOT) or an integer's
; bitwise complement (OP_NOT8, OP_NOT16). `not` binds below comparisons
; and above `and`, so `not a = b` negates the comparison.

EX_NOT:
    CALL PR_PEEK                   ; Look at the next token.
    CP   TK_NOT                    ; Is it `not`?
    JP   NZ,EX_CMP                 ; No: parse a comparison-level operand.
    CALL PR_TAKE                   ; Consume `not`.
    CALL EX_NOT                    ; Parse its operand, `not` included.
    CALL EX_PURE                   ; A failable call may not be enclosed.
    LD   D,A                       ; Keep the operand's metadata.
    AND  SY_TMASK                  ; Keep its type.
    CP   SY_BOOL                   ; Is it Boolean?
    LD   C,SY_BOOL                 ; Assume a Boolean result...
    LD   A,OP_LNOT                 ; ...from the Boolean negation.
    JR   Z,.EMIT                   ; Yes: emit it.
    LD   A,D                       ; An integer: is it typed?
    AND  SY_TMASK                  ; Keep its type.
    JR   NZ,.TYPED                 ; Yes: complement at its type.
    LD   A,(EX_WANT)               ; An exact constant: what is expected?
    CP   SY_U8                     ; A u8?
    JR   Z,.EXACT8                 ; Complement it as a byte.
    LD   C,SY_U16                  ; Otherwise a u16 result...
    LD   A,OP_NOT16                ; ...from the word complement.
    JR   .EMIT                     ; Emit it.
.EXACT8:                       ; An exact constant expected as u8.
; As with unary minus, validate the exact operand before applying the
; width-specific complement and masking the result.
    LD   A,D                       ; Is the operand known?
    AND  SY_KNOWN                  ; Test its flag.
    JR   Z,.BYTE                   ; No: nothing to check.
    LD   A,H                       ; Does the constant exceed a byte?
    OR   A                         ; Test its high byte.
    JP   NZ,EX_ERNG                ; Yes: it is out of range.
.BYTE:                         ; Complement as a byte.
    LD   C,SY_U8                   ; A u8 result...
    LD   A,OP_NOT8                 ; ...from the byte complement.
    JR   .EMIT                     ; Emit it.
.TYPED:                        ; A typed integer.
    LD   A,D                       ; Recover the metadata.
    AND  SY_TMASK                  ; Keep its type.
    LD   C,A                       ; The result has the operand's type.
    CP   SY_U8                     ; Is it u8?
    LD   A,OP_NOT8                 ; Assume the byte complement.
    JR   Z,.EMIT                   ; Yes: keep it.
    LD   A,OP_NOT16                ; No: the word complement.
.EMIT:                         ; Emit the operation A; C is the type.
    CALL EX_UNOP                   ; Emit it, keeping BC, DE and HL.
    LD   A,D                       ; Is the operand known?
    AND  SY_KNOWN                  ; Test its flag.
    LD   A,C                       ; A run-time result of type C...
    RET  Z                         ; ...if not.
    CP   SY_BOOL                   ; Fold: is it Boolean?
    JR   NZ,.INTCONST              ; No: complement the integer.
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

; Boolean short circuit is represented by prefix and suffix operations so
; the Z80 backend can branch around the right operand: OP_CAND or OP_COR
; after the left operand, OP_JOIN after the right. Integer `and` and `or`
; use the ordinary postfix reduction.

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
    CALL EX_HOLD                   ; Push the left operand.
    CALL EX_LBOOL                  ; Is the left Boolean?
    JR   NZ,.RIGHT                 ; No: integer `and` needs no prefix.
    LD   A,OP_CAND                 ; Open the short circuit...
    CALL EX_EMIT                   ; ...after the left operand.
    LD   C,0                       ; A constant false left...
    CALL EX_MUTE                   ; ...leaves the right arm unevaluated.
.RIGHT:                        ; Parse the right operand.
    CALL EX_NOT                    ; Parse it.
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
; operand of `or`.

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
    CALL EX_SAVE                   ; Push the left operand.
    LD   A,(EX_OPER)               ; Which operator?
    CP   TK_XOR                    ; `xor`?
    JR   NZ,.BOOLLEFT              ; No: `or` may short-circuit.
    CALL EX_LBOOL                  ; `xor` is for integers only.
    JP   Z,EX_ETYPE                ; A Boolean left is a mismatch.
    JR   .RIGHT                    ; Parse the right operand.
.BOOLLEFT:                     ; `or`: is the left Boolean?
    CALL EX_LBOOL                  ; Test the left type.
    JR   NZ,.RIGHT                 ; No: integer `or` needs no prefix.
    LD   A,OP_COR                  ; Open the short circuit...
    CALL EX_EMIT                   ; ...after the left operand.
    LD   C,1                       ; A constant true left...
    CALL EX_MUTE                   ; ...leaves the right arm unevaluated.
.RIGHT:                        ; Parse the right operand.
    CALL EX_AND                    ; Parse it.
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

;@ROUTINE IN C OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,CARRY,A,HL
; Raise EX_QUIET when the left operand is the constant C that decides the
; short circuit (false for `and`, true for `or`): the right arm will never
; run, so its faults are not diagnosed. EX_POP lowers it again.

EX_MUTE:
    LD   A,(EX_LMETA)              ; Is the left operand known?
    AND  SY_KNOWN                  ; Test its flag.
    RET  Z                         ; No: the right arm may run.
    LD   HL,(EX_LVAL)              ; Fetch the left value.
    LD   A,L                       ; Booleans are zero or one.
    XOR  C                         ; Is it the deciding value?
    RET  NZ                        ; No: the right arm decides the result.
    LD   HL,EX_QUIET               ; Address the quiet count.
    INC  (HL)                      ; The right arm is unevaluated.
    RET                            ; Return.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Close a Boolean short circuit (OP_JOIN) for the operator EX_OPER, `and`
; or `or`; the right operand must be Boolean. Fold when both are known.

EX_LOGIC:
    LD   A,(EX_RMETA)              ; Fetch the right metadata.
    AND  SY_TMASK                  ; Keep its type.
    CP   SY_BOOL                   ; Is it Boolean?
    JP   NZ,EX_ETYPE               ; No: a mismatch with the Boolean left.
    LD   A,OP_JOIN                 ; Close the short circuit.
    CALL EX_EMIT                   ; Emit it.
    CALL EX_KNOWN                  ; Are both operands known?
    LD   A,SY_BOOL                 ; A run-time Boolean...
    RET  Z                         ; ...if not.
    LD   HL,(EX_LVAL)              ; Fold: fetch the left value.
    LD   A,L                       ; Is it true?
    OR   H                         ; Test both bytes.
    LD   C,A                       ; C is nonzero for true.
    LD   A,(EX_OPER)               ; Which operator?
    CP   TK_AND                    ; `and`?
    JR   Z,.ISAND                  ; Fold it.
    LD   A,C                       ; `or`: is the left true?
    OR   A                         ; Test it.
    JR   NZ,.TRUE                  ; Yes: the result is true.
    JR   .RIGHT                    ; No: the result is the right operand.
.ISAND:                        ; `and`: is the left false?
    LD   A,C                       ; Fetch the left truth.
    OR   A                         ; Test it.
    JR   Z,.FALSE                  ; Yes: the result is false.
.RIGHT:                        ; The right operand decides.
    LD   HL,(EX_RVAL)              ; Return its value.
    JR   .CONST                    ; As a known Boolean.
.FALSE:                        ; The result is false.
    LD   HL,0                      ; Form zero.
    JR   .CONST                    ; As a known Boolean.
.TRUE:                         ; The result is true.
    LD   HL,1                      ; Form one.
.CONST:                        ; HL is the folded Boolean.
    LD   A,SY_KNOWN+SY_BOOL        ; A known Boolean.
    OR   A                         ; Clear carry.
    RET                            ; Return it.

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
; Parse a run-time expression with expected type A, emitting its
; operations. Clears the pending failable-call state and the operand stack.

EX_RUN:
    LD   (EX_WANT),A               ; Record the expected type.
    XOR  A                         ; Form zero.
    LD   (RO_PEND),A               ; No failable call is pending yet.
    LD   (RO_KEPT),A               ; No carriers are kept beneath one.
    LD   A,1                       ; Turn emission on.
    LD   (EX_LIVE),A               ; Operations go to the transcript.
    XOR  A                         ; Form zero.
    LD   (EX_QUIET),A              ; No arm is unevaluated.
    LD   (EX_DEPTH),A              ; Empty the operand stack.
    JP   EX_PARSE                  ; Parse the expression.

;@ROUTINE IN A OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse an expression with expected type A without emitting, for a
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

;@ROUTINE IN A OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,B,DE,HL
; Emit the declaration of a scalar local of type A (OP_LOC8 or OP_LOC16)
; at the next frame slot, SY_LSLOT. Always emitted.

EX_LOCAL:
    CP   SY_U16                    ; Is it a word?
    LD   A,OP_LOC8                 ; Assume a byte local.
    JR   NZ,.PICKED                ; u8 and Boolean are bytes.
    LD   A,OP_LOC16                ; A u16 local is a word.
.PICKED:                       ; A is the declaration operation.
    CALL TR_OPER                   ; Append it.
    LD   A,(SY_LSLOT)              ; Its operand is the frame slot.
    JP   TR_PUT                    ; Append it and return.

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
