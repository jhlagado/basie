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
;    EX_SUB    parse a nested expression with its own expected type
;    EX_STORE  store a result into a variable
;    EX_OPEN   keep the left operand of `and`, `or` or `xor`
;    EX_INNER  parse a nested expression, keeping the operands' offsets
;    EX_SHAPE  type or load a shift's left operand before its count
;    EX_PEEKX, EX_PEEKC  whether the next operand is certainly exact, or
;              certainly a constant

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
    LD   A,B                       ; The minimum, for a primary
    LD   (EX_MINB),A               ; that compares itself (HN_EQ).
    PUSH BC                        ; Keep the minimum precedence.
    LD   A,(EX_PRIME)              ; Unless the first primary is parsed,
    OR   A                         ; the left operand's
    CALL Z,EX_LHS                  ; first token is next.
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
    CALL .OPTOKEN                  ; An operator? C is its code; A is kept.
    JR   NC,EX_STOP                ; No: the operand ends here.
    BIT  7,C                       ; A comparison?
    JR   Z,.SETOP                  ; No: C is its precedence, A the operator.
    LD   A,C                       ; A comparison's
    AND  7                         ; enum is the operator,
    LD   C,0                       ; at precedence zero, which only level 0 takes.
.SETOP:                        ; A is the operator, C its precedence.
    LD   (EX_OPER),A               ; Record it as pending; EX_POP restores an outer one.
    LD   A,C                       ; Fetch the precedence.
    POP  BC                        ; Recover the minimum in B.
    CP   B                         ; Does the operator bind tightly enough?
    JR   C,EX_PEAK                 ; No: leave it to an outer level.
    INC  A                         ; The right operand binds tighter still,
    LD   C,A                       ; so operators associate to the left.
    PUSH BC                        ; Keep the minimum and the right level.
    CALL PR_TAKE                   ; Consume the operator.
    LD   HL,(TK_POS)               ; Its offset locates its diagnostics...
    LD   (EX_OPPOS),HL             ; ...and any run-time trap.
    CALL PR_SPOT                   ; The right operand's first token
    LD   (EX_RAT),HL               ; (rightAt).
    POP  DE                        ; D is the minimum, E the right level.
    POP  HL                        ; Recover the left value.
    POP  AF                        ; Recover the left metadata.
    CALL EX_LBOK                   ; A Boolean takes = and <> only.
    PUSH DE                        ; Keep the levels across the push.
    CALL EX_SHAPE                  ; A shift's left takes a type or loads.
    CALL EX_SAVE                   ; Push the left operand and operator.
    LD   A,(EX_LMETA)              ; A computed left operand
    CALL GX_PUSH                   ; is pushed while the right is computed.
    POP  BC                        ; Recover the levels.
    PUSH BC                        ; Keep them across the right operand.
    LD   B,C                       ; The right operand's minimum level.
    CALL EX_CLIMB                  ; Parse the right operand.
    CALL EX_POP                    ; Pop the left operand beneath it.
    LD   A,(EX_OPER)               ; Fetch the operator.
    CP   6                         ; Enums 0..5 are comparisons.
    JR   C,.RELATION               ; Reduce a comparison.
    CALL EX_ARITH                  ; Reduce an arithmetic operator.
    POP  BC                        ; Recover the minimum precedence.
    JR   EX_RISE                   ; Look for a further operator.
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

;@ROUTINE IN A OUT A,C,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,B,HL
; Carry if token A is a binary operator of the climb, with its code in C:
; a precedence, 1 additive or 2 multiplicative, or $80 plus a
; comparison's EX_EQ..EX_GE enum. .RELTOKEN: carry for a comparison
; only. A is kept.

.OPTOKEN:
    LD   HL,.OPTAB                 ; Address the token-to-code pairs.
    LD   B,13                      ; Thirteen operators.
.SCAN:                         ; Try one pair.
    CP   (HL)                      ; Is this the token?
    INC  HL                        ; Step to its code; ZERO survives.
    JR   Z,.FOUND                  ; Yes: return its code.
    INC  HL                        ; Skip the code.
    DJNZ .SCAN                     ; Try the next pair.
    OR   A                         ; Not an operator: clear carry.
    RET                            ; Return.
.FOUND:                        ; HL addresses the matching code.
    LD   C,(HL)                    ; Return it in C.
    SCF                            ; Report an operator.
    RET                            ; Return.
.RELTOKEN:                     ; A comparison only.
    LD   HL,.RELTAB                ; The comparisons' pairs,
    LD   B,6                       ; six of them,
    JR   .SCAN                     ; searched alike.
.OPTAB:                        ; Operator tokens and their codes.
    DB   TK_MINUS,1                ; - is additive.
    DB   TK_PLUS,1                 ; + is additive.
    DB   TK_STAR,2                 ; * is multiplicative,
    DB   TK_SLASH,2                ; and /,
    DB   TK_MOD,2                  ; and mod,
    DB   TK_SHL,2                  ; and the
    DB   TK_SHR,2                  ; shifts.
.RELTAB:                       ; Comparison tokens and $80 plus their enums.
    DB   TK_EQ,$80+EX_EQ           ; = is equal.
    DB   TK_NE,$80+EX_NE           ; <> is not equal.
    DB   TK_LT,$80+EX_LT           ; < is less.
    DB   TK_LE,$80+EX_LE           ; <= is at most.
    DB   TK_GT,$80+EX_GT           ; > is more.
    DB   TK_GE,$80+EX_GE           ; >= is at least.

.CHAINED:                      ; A comparison follows a comparison.
    POP  HL                        ; Balance the stack.
    POP  AF                        ; Balance the stack.
    CALL DG_RAISE                  ; Report it; no return.
    DB   DG_CHAIN                  ; Diagnostic: chained comparison.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Reduce the comparison EX_OPER on the popped operands to a Boolean. Two
; Booleans compare only for = and <> (GX_BOOL); numbers compare at the
; unified width (GX_BINOP). Known operands fold to a known Boolean, two
; f32 values as the numbers they are (VL_FKEYS).

.REDUCE:
    CALL EX_LBOOL                  ; Is the left Boolean?
    JR   NZ,.INTEGER               ; No: compare integers.
    LD   A,(EX_RMETA)              ; Then the right must be Boolean too.
    LD   D,A                       ; (its metadata)
    CALL EX_TBOOL                  ; Is its type Boolean?
    JR   Z,.BOOLS                  ; If not, at the left:
    BIT  7,D                       ; a known one
    LD   A,DG_CLASH                ; is a mismatch,
    JP   NZ,EX_ELOP                ; a computed one
    LD   A,DG_CONV                 ; needs a
    JP   EX_ELOP                   ; conversion.
.BOOLS:                        ; Two Booleans, = or <> (EX_LBOK).
    CALL EX_KNOWN                  ; Are both known?
    JR   NZ,.FOLD                  ; Then fold them.
    LD   A,(EX_OPER)               ; = or <>.
    CALL GX_BOOL                   ; Compare them at run time.
    JR   .RUNTIME                  ; A computed Boolean.
.INTEGER:                      ; Numeric operands.
    CALL EX_UNIFY                  ; Check them; C is the width.
    CALL EX_KNOWN                  ; Are both known?
    JR   Z,.EMIT                   ; No: compare them at run time.
    LD   A,C                       ; Two f32 values
    CP   SY_F32                    ; are ordered
    CALL Z,VL_FKEYS                ; as numbers,
    JR   .FOLD                     ; folded.
.EMIT:                         ; Not both known:
    CALL GX_BINOP                  ; compared at run time.
.RUNTIME:                      ; The Boolean is in A.
    LD   A,SY_BOOL                 ; A run-time Boolean.
    OR   A                         ; Clear carry.
    RET                            ; Return it.
.FOLD:                         ; Both known: order them.
    CALL VL_CMP                    ; B is the ordering's bit.
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
    LD   B,SY_KNOWN+SY_BOOL        ; A known Boolean.
    JP   EX_LIT                    ; Return it.
.TRUE:                         ; By relation: bit 0 less, 1 equal, 2 greater.
    DB   2,5,1,3,4,6               ; = <> < <= > >=.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a `not` expression: Boolean negation or an integer's bitwise
; complement (GX_NOT), folded when the operand is known, a typed integer
; wrapped at its type. An exact operand takes the expected type when it
; is an integer, and must fit it (out-of-range); with none it has no
; definite type (no-definite-type), both at `not` (spec 9.12).
; `not` binds below comparisons and above `and`, so `not a = b` negates
; the comparison.

EX_NOT:
    CALL PR_PEEK                   ; Look at the next token.
    CP   TK_NOT                    ; Is it `not`?
    JP   NZ,EX_CMP                 ; No: parse a comparison-level operand.
    CALL PR_TAKE                   ; Consume `not`.
    LD   HL,(TK_POS)               ; Its offset,
    PUSH HL                        ; for its diagnostics.
    CALL EX_NOT                    ; Parse its operand, `not` included.
    POP  DE                        ; DE is `not`'s offset.
    LD   B,A                       ; Keep the operand's metadata.
    AND  SY_TMASK                  ; Keep its type,
    LD   C,A                       ; the result's.
    JR   NZ,.TYPED                 ; A typed operand keeps it.
    LD   A,(EX_WANT)               ; An exact one takes the expected type,
    LD   C,A                       ; which must be an integer:
    CALL GX_PROP                   ; a size,
    BIT  6,A                       ; neither
    JR   NZ,.NODEF                 ; Boolean nor f32,
    AND  7                         ; and not
    JR   Z,.NODEF                  ; exact itself.
    PUSH DE                        ; Keep the offset.
    LD   A,C                       ; The value
    LD   HL,EX_KVAL                ; must fit
    CALL VL_FITS                   ; the type; BC is kept.
    POP  HL                        ; The offset:
    LD   A,DG_RANGE                ; out-of-range
    JP   C,DG_HERE                 ; at `not`.
.TYPED:                        ; C is the result's type, B the metadata.
    LD   A,C                       ; An f32
    CP   SY_F32                    ; is no integer:
    JR   Z,.FLOAT                  ; type-mismatch at `not`.
    BIT  7,B                       ; SY_KNOWN: is the operand known?
    JR   NZ,.FOLD                  ; Yes: fold it.
    PUSH BC                        ; Keep the type.
    CALL GX_NOT                    ; Complement the registers.
    POP  BC                        ; C is the type.
    LD   A,C                       ; A run-time result of type C.
    OR   A                         ; Clear carry.
    RET                            ; Return it.
.FOLD:                         ; EX_KVAL is the known operand.
    LD   A,C                       ; A Boolean?
    CP   SY_BOOL                   ; It flips.
    JR   NZ,.INTCONST              ; An integer complements.
    LD   A,(EX_KVAL)               ; Its truth value
    XOR  1                         ; negated,
    LD   L,A                       ; as
    LD   H,0                       ; a word,
    LD   B,SY_KNOWN+SY_BOOL        ; a known Boolean.
    JP   EX_LIT                    ; Return it.
.INTCONST:                     ; Complement a known integer.
    CALL VL_NOT                    ; Every bit,
    JP   EX_FOLD                   ; wrapped to the type; return.
.NODEF:                        ; No integer type is expected:
    EX   DE,HL                     ; at `not`,
    LD   A,DG_INFER                ; no-definite-type.
    JP   DG_HERE                   ; No return.
.FLOAT:                        ; An f32 operand (unaryNot):
    EX   DE,HL                     ; at `not`,
    LD   A,DG_CLASH                ; type-mismatch.
    JP   DG_HERE                   ; No return.

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
    JR   NZ,EX_DONE                ; No: return the result.
    CALL HN_LOGIC                  ; (No move in its statement.)
    LD   (EX_OPER),A               ; `and` is the pending operator.
    CALL PR_TAKE                   ; Consume it.
    POP  HL                        ; Recover the left value.
    POP  AF                        ; Recover the left metadata.
    CALL EX_OPEN                   ; Keep the left operand.
    CALL EX_NOT                    ; Parse the right operand.
    CALL EX_POP                    ; Pop the left operand beneath it.
    CALL EX_LBOOL                  ; Is the left Boolean?
    JR   NZ,.INTEGER               ; No: reduce integer `and`.
    CALL EX_LOGIC                  ; Close the short circuit and fold.
    JR   .LOOP                     ; Look for another `and`.
.INTEGER:                      ; Integer operands.
    CALL EX_ARITH                  ; Reduce the bitwise `and`.
    JR   .LOOP                     ; Look for another `and`.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a complete expression and leave its first token's offset in
; EX_START, where a diagnostic about the whole value is reported, as the
; reference reports one at the value's first token. A nested expression
; leaves its own there, but the enclosing one's is set again as it ends.

EX_PARSE:
    CALL PR_SPOT                   ; The expression's first token: its offset; fall into EX_PFROM.

;@ROUTINE IN HL OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; EX_PARSE for an expression that begins at offset HL, its first primary
; perhaps parsed already (EX_PRIME).

EX_PFROM:
    LD   (EX_LAT),HL               ; The first operand's offset (leftAt).
    PUSH HL                        ; The offset, kept across the parse.
    CALL EX_LOR                    ; A and HL are the result.
    EX   (SP),HL                   ; HL is the offset, the value kept.
    LD   (EX_START),HL             ; It is the value's.
    POP  HL                        ; The value again.
    RET                            ; A and carry are the result's.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a chain of `and` operands joined by `or` and `xor`, reducing left
; to right; `xor` takes integers only.

EX_LOR:
    CALL EX_AND                    ; Parse the first operand.
EX_ORS:                        ; A/HL is the result so far.
    PUSH AF                        ; Keep its metadata.
    PUSH HL                        ; Keep its value.
    CALL PR_PEEK                   ; Look at the next token.
    CP   TK_XOR                    ; An `xor`?
    JR   Z,.OPER                   ; Reduce it.
    CP   TK_OR                     ; An `or`?
    JR   NZ,EX_DONE                ; No: return the result.
    CALL HN_LOGIC                  ; (No move in its statement.)
.OPER:                         ; A is `or` or `xor`.
    LD   (EX_OPER),A               ; It is the pending operator.
    CALL PR_TAKE                   ; Consume it.
    POP  HL                        ; Recover the left value.
    POP  AF                        ; Recover the left metadata.
    LD   D,A                       ; Keep it.
    LD   A,(EX_OPER)               ; `xor`
    CP   TK_XOR                    ; of a Boolean
    JR   NZ,.OPEN                  ; left
    CALL EX_DBOOL                  ; is
    JR   Z,EX_BXOR                 ; no short circuit.
.OPEN:                         ; D is the left's metadata.
    LD   A,D                       ; Keep the left operand.
    CALL EX_OPEN                   ; Push it or open the short circuit.
    CALL EX_AND                    ; Parse the right operand.
    CALL EX_POP                    ; Pop the left operand beneath it.
    CALL EX_LBOOL                  ; Is the left Boolean?
    JR   NZ,EX_ORINT               ; No: reduce the integer operator.
    CALL EX_LOGIC                  ; Close the short circuit and fold.
    JR   EX_ORS                    ; Look for another operator.
EX_DONE:                       ; No further operator at this level.
    POP  HL                        ; Recover the value.
    POP  AF                        ; Recover the metadata.
    RET                            ; Return the result.
EX_ORINT:                      ; Integer `or` or `xor`.
    CALL EX_ARITH                  ; Reduce the bitwise operator.
    JR   EX_ORS                    ; Look for another operator.

; Boolean `xor` (logicalOrBitwise), D/HL its left operand: a known left
; folds with a known right or appends XOR n; a computed one is kept by
; PUSH AF while the right is computed into A, then LD E,A, POP AF, XOR E.
; The right must be Boolean (type-mismatch).

EX_BXOR:                       ; D/HL is the left.
    PUSH HL                        ; (its value)
    PUSH DE                        ; (its metadata)
    CALL PR_SPOT                   ; The right's
    POP  DE                        ; first token
    PUSH DE                        ; (rightAt)
    PUSH HL                        ; kept.
    LD   A,D                       ; A computed left
    CALL GX_PUSH                   ; is pushed (PUSH AF).
    CALL EX_AND                    ; The right, A/HL:
    LD   D,A                       ; Boolean
    CALL EX_TBOOL                  ; (otherwise a mismatch
    POP  BC                        ; or a conversion
    JR   Z,.RBOOL                  ; required,
    LD   (EX_RAT),BC               ; at it,
    POP  BC                        ; as
    LD   A,B                       ; as the left
    OR   D                         ; or right
    JP   EX_EBOOL                  ; is known).
.RBOOL:                        ; A Boolean right.
    LD   E,A                       ; E: Boolean.
    POP  BC                        ; The left's metadata:
    BIT  7,B                       ; known?
    JR   NZ,.KNOWN                 ; Then folded or XOR n.
    POP  BC                        ; (its value unused)
    CALL GX_TOREG                  ; The right in A,
    CALL EM_SEQ                    ; LD E,A, POP AF, XOR E:
    DB   3,$5F,$F1,$AB             ; the left's popped,
    CALL EM_POP2                   ; two bytes.
.REG:                          ; A computed Boolean.
    LD   A,SY_BOOL                 ; Its metadata,
    OR   A                         ; carry clear.
    JR   EX_ORS                    ; Look for another operator.
.KNOWN:                        ; A known left, BC its value:
    POP  BC                        ; (C)
    BIT  7,D                       ; the right known
    JR   NZ,.FOLD                  ; folds;
    LD   A,C                       ; a computed one
    CALL EM_OPA                    ; takes XOR n,
    DB   $EE                       ; n the left's.
    JR   .REG                      ; A computed Boolean.
.FOLD:                         ; Both known:
    LD   A,L                       ; the values
    XOR  C                         ; differ?
    LD   L,A                       ; HL is
    LD   H,0                       ; the result,
    LD   B,D                       ; known
    CALL EX_LIT                    ; and Boolean.
    JP   EX_ORS                    ; Look for another operator.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Left operand metadata A before binary operator EX_OPER is taken: a
; Boolean has no arithmetic, shift or order (type-mismatch at it, as the
; reference's numericType reports before the right is parsed). A is kept.

EX_LBOK:                       ; A is the left's metadata.
    PUSH AF                        ; Kept.
    AND  SY_TMASK                  ; A Boolean
    CP   SY_BOOL                   ; left
    JR   NZ,.OK                    ; takes
    LD   A,(EX_OPER)               ; = and <>
    CP   EX_NE+1                   ; only.
    LD   A,DG_CLASH                ; Anything else
    JP   NC,EX_ELOP                ; is a mismatch at it.
.OK:                           ; Accepted.
    POP  AF                        ; A.
    RET                            ; Back.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS A,BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Keep the left operand A/HL of `and`, `or` or `xor` (EX_OPER) on the
; operand stack while the right is parsed. An integer is pushed if it was
; computed (GX_PUSH). A computed Boolean opens the short circuit (GX_SKIP)
; and its value word holds the label to define after the right operand. A
; known Boolean that decides the result discards the right operand's code
; (EX_MUTE).

EX_OPEN:
    PUSH AF                        ; Keep the left
    PUSH HL                        ; operand.
    CALL EX_LHS                    ; The token after the operator is
    LD   (EX_RAT),HL               ; both operands' place (binary's at).
    POP  HL                        ; The left
    POP  AF                        ; operand.
    LD   D,A                       ; Keep the metadata.
    CALL EX_TBOOL                  ; Is its type Boolean?
    JR   Z,.BOOL                   ; It may short-circuit.
    LD   A,D                       ; An integer: keep it,
    CALL EX_SAVE                   ; with the operator.
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
    JP   EX_SAVE                   ; With the operator, and return.
.KNOWN:                        ; A known Boolean.
    LD   A,D                       ; Keep it,
    CALL EX_SAVE                   ; with the operator.
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
    LD   A,(EX_LMETA)              ; A known left that decides
    RLCA                           ; returns, its right
    CALL C,.DECIDE                 ; unchecked (short circuit).
    LD   A,D                       ; The right:
    CALL EX_TBOOL                  ; Is its type Boolean?
    JR   Z,.RBOOL                  ; If not:
    LD   A,(EX_LMETA)              ; a mismatch or a conversion
    OR   D                         ; required, with the
    JP   EX_EBOOL                  ; Boolean left.
.RBOOL:                        ; A Boolean right.
    LD   E,A                       ; E is Boolean, for GX_TOREG.
    LD   A,(EX_LMETA)              ; Is the left known?
    RLCA                           ; SY_KNOWN into carry.
    JR   C,.RIGHT                  ; Yes: the right is the result.
    LD   HL,(EX_RVAL)              ; The right's value, if known,
    CALL GX_TOREG                  ; comes into A (a byte: EX_KVAL unread).
    LD   A,(EX_LVAL)               ; The short circuit's label is here, and nothing
    CALL EM_LDONE                  ; names it again: it may be used anew.
    LD   A,SY_BOOL                 ; A run-time Boolean.
    OR   A                         ; Clear carry.
    RET                            ; Return it.
.RIGHT:                        ; A known left that did not decide:
    LD   B,D                       ; the right is the result,
    LD   HL,(EX_RVAL)              ; known or computed.
    JP   EX_LIT                    ; Return it.
.DECIDE:                       ; A known left: if it decides,
    LD   HL,(EX_LVAL)              ; its value, 0 or 1,
    LD   A,(EX_OPER)               ; `and` deciding by false,
    CP   TK_AND                    ; `or` by true,
    LD   A,L                       ; is
    JR   Z,.ZERO                   ; the
    XOR  1                         ; result:
.ZERO:                         ; A is zero when the left decides.
    OR   A                         ; Not?
    RET  NZ                        ; Then the right is checked.
    POP  BC                        ; It did (EX_LOGIC's return dropped):
    LD   B,SY_KNOWN+SY_BOOL        ; the result is the known left,
    JP   EX_LIT                    ; HL; return it.

;@ROUTINE IN A,E,HL OUT A,D,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC
; Check result A/HL, the expression just parsed, against destination type
; E for assignment, passing or initialization, as the reference's
; toRegisters and coerceConst do, reporting at the value's first token
; (EX_START). An exact constant, whole in EX_KVAL, must fit E (DG_RANGE)
; and may not become a Boolean (DG_CLASH). A typed value fits its own type
; and those it widens to (EX_WIDEN); any other needs a conversion
; (DG_CONV), but a known one where only a Boolean or only a number will do
; is a mismatch (DG_CLASH), as a known f32 is anywhere but an f32. A known
; integer for an f32 becomes one, which must be it exactly (DG_RANGE).
; Returns E with the result's SY_KNOWN in A, the metadata in D; HL, the
; value's low word, and E are kept.

EX_FITS:
    LD   D,A                       ; Keep the metadata.
    AND  SY_TMASK                  ; Is the result typed?
    JR   NZ,.TYPED                 ; Yes: compare the types.
    LD   A,E                       ; An exact constant: what is the target?
    CP   SY_BOOL                   ; A Boolean?
    JR   Z,EX_EFIT                 ; A number is not a Boolean.
    CP   SY_F32                    ; An f32?
    JR   Z,.FLOAT                  ; It becomes one.
    PUSH DE                        ; Keep the metadata and the target.
    LD   HL,EX_KVAL                ; The value
    CALL VL_FITS                   ; must fit it,
    POP  DE                        ; (restored)
    LD   HL,(EX_KVAL)              ; (its low word again)
    LD   A,DG_RANGE                ; else it is out of range,
    JR   C,EX_EVAL                 ; reported at the value.
    JR   .FITS                     ; It fits.
.TYPED:                        ; A is the result's type.
    CP   E                         ; The destination's?
    JR   Z,.FITS                   ; It fits.
    CP   SY_F32                    ; An f32 to another:
    JR   Z,.FROMF                  ; known, never; computed, converted.
    CALL EX_WIDEN                  ; Does it widen to it?
    JR   NC,.NARROW                ; No.
    BIT  7,D                       ; A known integer
    JR   Z,.FITS                   ; widening
    LD   A,E                       ; to an f32
    CP   SY_F32                    ; becomes
    JR   NZ,.FITS                  ; one.
.FLOAT:                        ; The known value becomes an f32:
    PUSH DE                        ; (the metadata and the target)
    LD   HL,EX_KVAL                ; exactly
    CALL OV_ITOF                   ; (coerceConst),
    POP  DE                        ; else
    LD   HL,(EX_KVAL)              ; (its low word)
    LD   A,DG_RANGE                ; out of range,
    JR   C,EX_EVAL                 ; at the value.
    JR   .FITS                     ; It fits.
.FROMF:                        ; An f32 for an integer or a Boolean:
    BIT  7,D                       ; a known one
    JR   NZ,EX_EFIT                ; never adapts (type-mismatch).
.NARROW:                       ; It does not widen.
    BIT  7,D                       ; A computed value needs
    JR   Z,.CONVERT                ; a conversion;
    CALL EX_DBOOL                  ; a known Boolean for a number, or a known number
    JR   Z,EX_EFIT                 ; for a Boolean,
    LD   A,E                       ; is
    CP   SY_BOOL                   ; a mismatch.
    JR   Z,EX_EFIT                 ; (type-mismatch)
.CONVERT:                      ; A conversion is required,
    LD   A,DG_CONV                 ; reported
    JR   EX_EVAL                   ; at the value.
.FITS:                         ; The result fits.
    LD   A,D                       ; Keep its known flag...
    AND  SY_KNOWN                  ; ...alone...
    OR   E                         ; ...with the destination type.
    RET                            ; Return it with carry clear.

;@ROUTINE NORETURN
; Raise DG_CLASH, or diagnostic A at EX_EVAL, at the first token of the
; expression just parsed (EX_START).

EX_EFIT:                       ; A value of the wrong type.
    LD   A,DG_CLASH                ; Diagnostic: type mismatch.
EX_EVAL:                       ; A is the diagnostic.
    LD   HL,EX_START               ; At the value's first token.
    JP   DG_AT                     ; Report it; no return.

;@ROUTINE IN A OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a run-time expression with expected type A, generating its code.
; Clears the pending failable-call state and the operand stack.

EX_RUN:
    CALL EX_INIT                   ; Start a run-time expression.
    JP   EX_PARSE                  ; Parse it.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Start a run-time expression of expected type A: no failable call is
; pending, no arm unevaluated, the operand stack empty and no primary yet
; parsed (EX_CHR). Returns A zero.

EX_INIT:
    LD   (EX_WANT),A               ; Record the expected type.
    XOR  A                         ; Form zero.
    LD   (RO_PEND),A               ; No failable call is pending yet.
    LD   (EX_QUIET),A              ; No arm is unevaluated.
    LD   (EX_DEPTH),A              ; Empty the operand stack.
    LD   (EX_CHR),A                ; No primary yet,
    LD   (EX_MINB),A               ; at the lowest level.
    RET                            ; A is zero.

;@ROUTINE IN A OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse an expression with expected type A that must be known, for a
; constant declaration or a static initializer. The caller requires the
; result to be known.

EX_CONST:
    LD   (EX_WANT),A               ; Record the expected type.
    XOR  A                         ; Form zero.
    LD   (EX_QUIET),A              ; No arm is unevaluated.
    LD   (EX_DEPTH),A              ; Empty the operand stack.
    JP   EX_PARSE                  ; Parse the expression.

;@ROUTINE IN A OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse an expression nested in another, an index, an argument or a
; conversion's operand, with expected type A, and restore the enclosing
; expression's expected type after it. A and HL describe the nested one.

EX_SUB:
    LD   E,A                       ; The nested expected type.
    LD   A,(EX_WANT)               ; The enclosing one
    PUSH AF                        ; waits.
    LD   A,E                       ; The nested one
    LD   (EX_WANT),A               ; is asked for.
    CALL EX_INNER                  ; A and HL describe the expression.
    POP  DE                        ; D is the enclosing type,
    LD   E,A                       ; E the metadata.
    LD   A,D                       ; The enclosing type
    LD   (EX_WANT),A               ; is restored.
    LD   A,E                       ; The metadata.
    OR   A                         ; Carry clear.
    RET                            ; A and HL are the result.

;@ROUTINE IN D,BC CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Store the value in the registers into the variable with symbol info D: a
; program variable at blob BC (GX_STORE), or a local or parameter at offset
; BC from IX (GX_FPUT).

EX_STORE:
    LD   A,D                       ; Fetch the symbol info.
    AND  SY_TMASK                  ; Keep the type.
    LD   E,A                       ; E is the type.
    LD   A,D                       ; The symbol info again.
    AND  SY_CMASK                  ; Keep the storage class.
    CP   SY_GLOB                   ; A program variable?
    LD   A,E                       ; A is the type.
    JP   Z,GX_STORE                ; Store A or HL at blob BC and return.
    LD   H,B                       ; HL is the offset
    LD   L,C                       ; from IX.
    JP   GX_FPUT                   ; Store A or HL in the frame and return.

EX_EFLOW:                      ; A return of the wrong form:
    LD   A,DG_RFORM                ; return-form,
    LD   HL,AC_SPOS                ; at `return`
    JP   DG_AT                     ; (AC_RET keeps it). No return.

;@ROUTINE IN A,HL OUT A,HL CLOBBERS BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Prepare the left operand A/HL of the operator EX_OPER, just taken, for
; its push (binary): before a shift's count, an exact left whose count is
; not certainly exact (EX_PEEKX) takes the expected type, which must be an
; integer (no-definite-type) that it fits (out-of-range), both at the left;
; then a known typed left whose count is not certainly a constant
; (EX_PEEKC) is loaded into the registers at its type, to be pushed as a
; computed one is. Any other left is returned as it is.

EX_SHAPE:
    LD   D,A                       ; Keep the metadata.
    LD   A,(EX_OPER)               ; Only a shift's
    CP   TK_SHL                    ; left
    JR   Z,.SHIFT                  ; is
    CP   TK_SHR                    ; prepared.
    JR   Z,.SHIFT                  ; This is not one:
.DONE:                         ; D is the metadata.
    LD   A,D                       ; The left
    RET                            ; as it is.
.SHIFT:                        ; A shift's left.
    BIT  7,D                       ; Computed?
    JR   Z,.DONE                   ; Then it is pushed.
    LD   A,D                       ; Exact?
    AND  SY_TMASK                  ; Then it may
    JR   NZ,.TYPED                 ; take a type.
    PUSH DE                        ; Keep the metadata.
    CALL EX_PEEKX                  ; A certainly exact count?
    POP  DE                        ; (the metadata)
    JR   Z,.VALUE                  ; Then it folds exactly.
    LD   A,(EX_WANT)               ; Otherwise the expected type,
    LD   C,A                       ; which must be an integer:
    CALL GX_PROP                   ; a size,
    BIT  6,A                       ; neither Boolean
    LD   A,DG_INFER                ; nor f32,
    JR   NZ,.LEFT                  ; nor
    INC  C                         ; exact
    DEC  C                         ; itself
    JR   Z,.LEFT                   ; (no-definite-type, at the left).
    LD   HL,EX_KVAL                ; The value
    LD   A,C                       ; must fit it
    CALL VL_FITS                   ; (out-of-range, at the left); BC is kept.
    LD   A,DG_RANGE                ; It is typed
    JR   C,.LEFT                   ; from here:
    LD   A,C                       ; the expected
    OR   SY_KNOWN                  ; type,
    LD   D,A                       ; known.
.TYPED:                        ; A known typed left.
    PUSH DE                        ; Keep the metadata.
    CALL EX_PEEKC                  ; A certainly constant count?
    POP  DE                        ; (the metadata)
    JR   Z,.VALUE                  ; Then it folds.
    LD   A,D                       ; Otherwise it loads
    AND  SY_TMASK                  ; at its type,
    LD   E,A                       ; from
    LD   HL,(EX_KVAL)              ; its value,
    PUSH DE                        ; (kept)
    CALL GX_TOREG                  ; into the registers,
    POP  DE                        ; and is computed:
    LD   D,E                       ; its type alone.
.VALUE:                        ; D is the metadata.
    LD   HL,(EX_KVAL)              ; A known value's low word.
    LD   A,D                       ; The metadata.
    RET                            ; Ready to push.
.LEFT:                         ; A is the diagnostic,
    JP   EX_ELOP                   ; at the left; no return.

;@ROUTINE OUT ZERO CLOBBERS A,BC,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Z when the next token is certainly an exact operand (peekExactOperand):
; a number, or the name of an exact constant, predeclared or declared.

EX_PEEKX:
    LD   C,SY_TMASK                ; Its type must be exact;
    JR   EX_PEEKK                  ; look.

;@ROUTINE OUT ZERO CLOBBERS A,BC,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Z when the next token is certainly a constant operand
; (peekConstOperand): a number, or the name of a scalar constant.

EX_PEEKC:
    LD   C,0                       ; Any type will do; fall into EX_PEEKK.

;@ROUTINE IN C OUT ZERO CLOBBERS A,BC,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Z when the next token is a number, or names a scalar constant, whose
; type has none of C's bits: an integer literal has none, an f32 literal
; SY_F32 (TK_WIDE).

EX_PEEKK:                      ; C masks the type.
    PUSH BC                        ; Keep it.
    CALL PR_PEEK                   ; The next token.
    POP  BC                        ; C is the mask.
    CP   TK_NUM                    ; A number
    JR   NZ,.NAME                  ; is one,
    LD   A,(TK_WIDE)               ; its type, an f32's
    AND  C                         ; or none,
    RET                            ; masked.
.NAME:                         ; A is the kind.
    CP   TK_NAME                   ; Anything else but a name
    RET  NZ                        ; is not.
    PUSH BC                        ; Keep the mask.
    CALL RO_LIB                    ; A predeclared name?
    POP  BC                        ; (the mask)
    JR   NC,.SYMBOL                ; No: perhaps a symbol.
    JP   P,.NOT                    ; A service is not.
    AND  C                         ; A constant: its type masked.
    RET                            ; Z if it is one.
.SYMBOL:                       ; Not predeclared.
    PUSH BC                        ; Keep the mask.
    CALL SY_FIND                   ; A symbol?
    POP  BC                        ; (the mask)
    JR   NC,.NOT                   ; No.
    INC  HL                        ; Its
    INC  HL                        ; class
    INC  HL                        ; and type:
    LD   A,(HL)                    ; a scalar
    AND  SY_CMASK+SY_TYPE+SY_AGGR  ; constant
    JR   NZ,.NOT                   ; has none of these,
    LD   A,(HL)                    ; and its type
    AND  C                         ; masked
    RET                            ; is zero.
.NOT:                          ; Not a constant.
    OR   1                         ; NZ.
    RET                            ; Done.

;@ROUTINE OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; The next token's offset becomes the left operand's first (EX_LAT, the
; reference's leftAt); HL returns it.

EX_LHS:                        ; The next token
    CALL PR_SPOT                   ; is read, and its offset
    LD   (EX_LAT),HL               ; kept.
    RET                            ; HL is it.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; EX_PARSE an expression nested in another, a parenthesized one, an
; index, an argument or a conversion's operand, keeping the enclosing
; operator's operand offsets (EX_LAT, EX_RAT) across it. Each level takes
; about 22 bytes of the machine stack: one that would leave less than
; EX_SPARE of the stack's MM_STACK bytes below SP is too deep (DG_DEEP),
; at about 36 levels.

EX_INNER:                      ; A nested expression.
    LD   HL,(SH_BDOS+1)            ; The stack's top,
    LD   DE,EX_SPARE-MM_STACK      ; less all but the spare,
    ADD  HL,DE                     ; is the floor:
    OR   A                         ; is SP
    SBC  HL,SP                     ; above it?
    JR   C,.ROOM                   ; Yes.
    CALL DG_RAISE                  ; No: too deep
    DB   DG_DEEP                   ; for the stack.
.ROOM:                         ; There is room for another level.
    LD   A,(EX_MINB)               ; The enclosing level,
    PUSH AF                        ; and
    LD   HL,(EX_RAT)               ; the enclosing
    PUSH HL                        ; operator's
    LD   HL,(EX_LAT)               ; offsets
    PUSH HL                        ; wait.
    CALL EX_PARSE                  ; A and HL describe the expression.
    EX   DE,HL                     ; Its value waits in DE.
    POP  HL                        ; The offsets
    LD   (EX_LAT),HL               ; are
    POP  HL                        ; restored.
    LD   (EX_RAT),HL               ; Both,
    POP  HL                        ; and the
    LD   B,A                       ; level
    LD   A,H                       ; (A and
    LD   (EX_MINB),A               ; the flags
    LD   A,B                       ; kept).
    EX   DE,HL                     ; HL is the value.
    RET                            ; A and flags are the expression's.
