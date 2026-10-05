;==========================================================================
;  Expression primaries and unary operators
;==========================================================================
;
;  The second of the expression parser's three files (EXPR.ASM describes
;  the module, its result convention and its operand stack). Parse the
;  operands of the binary operators: literals, names, parenthesized
;  expressions, conversions and the unary signs, emitting each one's load,
;  literal or operation and folding constants.
;
;  Principal entries:
;    EX_TERM   parse one primary
;    EX_LIT    return a literal as a known result
;    EX_PURE   reject a pending failable call inside a larger expression
;    EX_HOLD   check a left operand and push it
;    EX_JOIN   check a right operand and pop the left beneath it
;    EX_CAST   parse a conversion's parenthesized operand
;    EX_INT    require an integer result
;    EX_UNARY  parse a primary preceded by any signs
;    EX_UNOP   emit a unary operation, preserving the operand

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse one primary: a number, character, `true` or `false`, a name, a
; parenthesized expression or a u8(...) or u16(...) conversion. Its
; position becomes EX_VPOS, the position a range diagnostic blames. Any
; other token raises DG_VALUE.

EX_TERM:
    CALL PR_TAKE                   ; Consume the token; BC is its value.
    PUSH AF                        ; Keep its kind.
    PUSH BC                        ; Keep its value.
    LD   HL,TK_POS                 ; The token's offset, line and column...
    LD   DE,EX_VPOS                ; ...become the latest primary's position.
    CALL PR_COPY                   ; Copy the six bytes.
    POP  BC                        ; Restore the value.
    POP  AF                        ; Restore the kind.
    CP   TK_NUM                    ; A number?
    JR   Z,.NUMBER                 ; An exact literal.
    CP   TK_CHAR                   ; A character?
    JR   Z,.CHAR                   ; A u8 literal.
    CP   TK_TRUE                   ; `true`?
    JR   Z,.TRUE                   ; A Boolean literal.
    CP   TK_FALSE                  ; `false`?
    JR   Z,.FALSE                  ; A Boolean literal.
    CP   TK_NAME                   ; A name?
    JR   Z,EX_NAME                 ; Resolve it.
    CP   TK_LPAR                   ; A parenthesis?
    JP   Z,EX_PAREN                ; Parse the enclosed expression.
    CP   TK_U8                     ; A u8 conversion?
    JP   Z,EX_U8                   ; Parse it.
    CP   TK_U16                    ; A u16 conversion?
    JP   Z,EX_U16                  ; Parse it.
    JP   PR_ETERM                  ; Anything else: a value was expected.
.NUMBER:                       ; BC is the number's value.
    LD   H,B                       ; Return it in HL.
    LD   L,C                       ; Complete HL.
    LD   B,SY_KNOWN+SY_EXACT       ; A known value of no type yet.
    JR   EX_LIT                    ; Return it.
.CHAR:                         ; C is the character code.
    LD   H,0                       ; A byte value,
    LD   L,C                       ; exact like a number (spec 9.7).
    LD   B,SY_KNOWN+SY_EXACT       ; A known value of no type yet.
    JR   EX_LIT                    ; Return it.
.TRUE:                         ; `true` is one.
    LD   HL,1                      ; Form one.
    JR   .BOOL                     ; A known Boolean.
.FALSE:                        ; `false` is zero.
    LD   HL,0                      ; Form zero.
.BOOL:                         ; HL is a Boolean value.
    LD   B,SY_KNOWN+SY_BOOL        ; A known Boolean; fall into EX_LIT.

;@ROUTINE IN B,HL OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return the known value HL with metadata B. A constant generates no code
; until something needs it in the registers (GX_TOREG and the operator
; templates), as in the reference compiler. BC and DE are preserved.

EX_LIT:
    LD   A,B                       ; The metadata.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the known result.

; Resolve a NAME primary, already consumed: a predefined service query or
; error constant, a routine call, an aggregate object path, a scalar
; constant (emitted as a literal) or a scalar variable (emitted as a load).

EX_NAME:
    CALL RO_LIB                    ; A predefined service or error name?
    JR   NC,.ORDINARY              ; No: an ordinary name.
    CP   RO_ERRS                   ; An error constant?
    JP   NC,RO_CAUSE               ; Yes: parse it as a value.
    LD   B,A                       ; Keep the service ordinal.
    AND  $FD                       ; readInputByte/readStorageByte map to zero.
    JP   NZ,EX_ETYPE               ; Other services return no value.
    LD   A,B                       ; Recover the ordinal.
    JP   RO_QUERY                  ; Parse the value-returning service call.
.ORDINARY:                     ; A routine or an ordinary symbol.
    CALL RO_FIND                   ; Is it a routine?
    JP   Z,RO_FUNC                 ; Yes: parse a call for its result.
    CALL SY_GET                    ; Fetch class/type and payload, or fail.
    LD   D,A                       ; Keep the symbol info.
    AND  SY_AGGR                   ; An aggregate?
    JP   NZ,RO_OBJ                 ; Yes: parse its field or element path.
    LD   A,D                       ; Recover the symbol info.
    JR   .RESOLVED                 ; Load or fold the scalar.
; The routine table handles scalar calls above.
.VARIABLE:                     ; Unreachable: nothing jumps here.
    CALL SY_GET                    ; Unreachable: fetch the symbol.
    LD   D,A                       ; Unreachable: keep its info.
.RESOLVED:                     ; D is a scalar symbol's info, BC its payload.
    CALL EX_CLASS                  ; Reject a type name; zero for a constant.
    JR   Z,.CONST                  ; A constant folds to a literal.
    LD   A,D                       ; Recover the symbol info.
    AND  SY_TMASK                  ; Keep the type.
    LD   E,A                       ; E is the variable's type.
    LD   A,D                       ; Recover the symbol info.
    AND  SY_CMASK                  ; Keep the storage class.
    CP   SY_GLOB                   ; A program variable?
    JR   Z,.GLOBAL                 ; Load it by address.
    CP   SY_PARAM                  ; A parameter?
    JR   Z,.PARAM                  ; Load it from the frame.
    LD   A,E                       ; A local: is it a word?
    CP   SY_U16                    ; Compare with u16.
    LD   A,OP_LDL8                 ; Assume a byte local.
    JR   NZ,.LOAD                  ; u8 and Boolean load a byte.
    LD   A,OP_LDL16                ; A u16 local loads a word.
    JR   .LOAD                     ; Emit it with the frame offset.
.GLOBAL:                       ; A program variable, blob BC.
    LD   A,E                       ; Its type.
    PUSH DE                        ; Keep it.
    CALL GX_LOAD                   ; Load it into A or HL.
    POP  DE                        ; Recover the type.
    LD   A,E                       ; A run-time result of that type.
    OR   A                         ; Clear carry for success.
    RET                            ; Return it.
.PARAM:                        ; A parameter at frame offset C.
    LD   A,E                       ; Is it a word?
    CP   SY_U16                    ; Compare with u16.
    LD   A,OP_LDP8                 ; Assume a byte parameter.
    JR   NZ,.LOAD                  ; u8 and Boolean load a byte.
    LD   A,OP_LDP16                ; A u16 parameter loads a word.
.LOAD:                         ; Emit a frame load at offset C.
    PUSH DE                        ; Keep the type.
    PUSH BC                        ; Keep the offset.
    CALL EX_EMIT                   ; Emit the load.
    POP  BC                        ; Recover the offset.
    POP  DE                        ; Recover the type.
    LD   A,C                       ; The frame offset is the operand.
    PUSH DE                        ; Keep the type.
    CALL EX_EMITB                  ; Emit it.
    POP  DE                        ; Recover the type.
    LD   A,E                       ; A run-time result of that type.
    OR   A                         ; Clear carry for success.
    RET                            ; Return it.
.CONST:                        ; A scalar constant with value BC.
    LD   H,B                       ; The value is the literal.
    LD   L,C                       ; Complete HL.
    LD   B,D                       ; Its type is the constant's...
    SET  7,B                       ; ...and it is known (SY_KNOWN).
    JP   EX_LIT                    ; Return it.

;@ROUTINE IN A,HL OUT A,HL CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,CARRY,C
; A failable call is consumable only while it is the complete, untouched
; expression, so that `else` or `handle` can follow it. Raise DG_LEAK if a
; failable result is pending (RO_PEND) where another expression form is
; about to enclose it; otherwise return result A/HL unchanged.

EX_PURE:
    LD   C,A                       ; Keep the result's metadata.
    LD   A,(RO_PEND)               ; Is a failable call result pending?
    OR   A                         ; Test the flag.
    JP   NZ,AC_ELEAK               ; Yes: its failure would be lost.
    LD   A,C                       ; Recover the metadata.
    RET                            ; Return the result unchanged.

;@ROUTINE IN A,HL OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,HL
; Check result A/HL with EX_PURE and push it as a pending left operand.

EX_HOLD:
    CALL EX_PURE                   ; It may not be a pending failable call.
    JP   EX_SAVE                   ; Push it with the operator context.

;@ROUTINE IN A,HL OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A,C,DE,HL
; Check right operand A/HL with EX_PURE and pop the left operand beneath it.

EX_JOIN:
    CALL EX_PURE                   ; It may not be a pending failable call.
    JP   EX_POP                    ; Pop the left operand and context.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a parenthesized expression after its '(' and require the ')'.

EX_PAREN:
    CALL EX_PARSE                  ; Parse the enclosed expression.
    PUSH AF                        ; Keep its metadata.
    PUSH HL                        ; Keep its value.
    CALL PR_RIGHT                  ; Require the closing parenthesis.
    POP  HL                        ; Recover the value.
    POP  AF                        ; Recover the metadata.
    JR   EX_PURE                   ; A failable call may not be enclosed.

;@ROUTINE IN A OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse the parenthesized operand of an explicit conversion to type A, with
; A as the expected type. The enclosing expected type is restored before
; returning the operand in A/HL.

EX_CAST:
    LD   C,A                       ; C is the conversion's type.
    LD   A,(EX_WANT)               ; Fetch the enclosing expected type.
    LD   B,A                       ; B keeps it.
    PUSH BC                        ; Save both across the operand.
    LD   A,C                       ; The conversion's type...
    LD   (EX_WANT),A               ; ...is expected inside it.
    CALL PR_LEFT                   ; Require the opening parenthesis.
    CALL EX_PARSE                  ; Parse the operand.
    LD   D,A                       ; Keep its metadata.
    PUSH DE                        ; Save it across the closing token.
    PUSH HL                        ; Save its value.
    CALL PR_RIGHT                  ; Require the closing parenthesis.
    POP  HL                        ; Recover the value.
    POP  DE                        ; Recover the metadata.
    POP  BC                        ; Recover the enclosing expected type.
    LD   A,B                       ; Restore it...
    LD   (EX_WANT),A               ; ...for the rest of the expression.
    LD   A,D                       ; Return the operand's metadata.
    CALL EX_PURE                   ; A failable call may not be enclosed.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the operand.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse u8(...), a checked narrowing. A known operand must fit a byte, or
; DG_TRUNC is raised; a run-time operand emits OP_TRUNC with the
; conversion's offset for the run-time trap.

EX_U8:
    LD   HL,(TK_POS)               ; The conversion keyword's offset...
    LD   (EX_OPPOS),HL             ; ...is the operator offset.
    PUSH HL                        ; This conversion's trap position.
    LD   A,SY_U8                   ; Parse the operand as a u8.
    CALL EX_CAST                   ; Parse the parenthesized operand.
; Restore the enclosing context while keeping this conversion's value and
; source offset live for the checked narrowing below.
    LD   D,A                       ; Keep the operand's metadata.
    LD   B,H                       ; Keep its value in BC...
    LD   C,L                       ; ...while HL takes the offset.
    POP  HL                        ; Recover this conversion's offset.
    LD   (EX_OPPOS),HL             ; Nested operators may have replaced it.
    LD   H,B                       ; Recover the value.
    LD   L,C                       ; Complete HL.
    LD   A,D                       ; Recover the metadata.
    CALL EX_INT                    ; A Boolean cannot be narrowed.
    AND  SY_KNOWN                  ; Is the operand known?
    JR   Z,.RUNTIME                ; No: check it at run time.
    LD   A,H                       ; Does the constant exceed a byte?
    OR   A                         ; Test its high byte.
    JP   NZ,EX_ECAST               ; Yes: report it, or return a quiet zero.
    LD   A,SY_KNOWN+SY_U8          ; A known u8 with the same value.
    OR   A                         ; Clear carry for success.
    RET                            ; Return it.
.RUNTIME:                      ; A run-time operand.
    LD   A,OP_TRUNC                ; Emit the checked narrowing...
    CALL EX_EMIT                   ; ...operation.
    LD   HL,(EX_OPPOS)             ; Its operand is the trap's offset.
    CALL EX_EMITW                  ; Emit it.
    LD   A,SY_U8                   ; A run-time u8.
    OR   A                         ; Clear carry for success.
    RET                            ; Return it.

;@ROUTINE IN A OUT A,D,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Require result metadata A to be an integer; a Boolean raises DG_CLASH.
; Returns the metadata in A and D with carry clear.

EX_INT:
    LD   D,A                       ; Keep the metadata.
    AND  SY_TMASK                  ; Keep the type.
    CP   SY_BOOL                   ; Is it Boolean?
    JP   Z,EX_ETYPE                ; Yes: an integer is required.
    LD   A,D                       ; Recover the metadata.
    CCF                            ; Valid scalar types compare below Boolean.
    RET                            ; Return with carry clear.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse u16(...), a widening that needs no check or run-time operation:
; every integer fits a u16 and carriers are already sixteen bits.

EX_U16:
    LD   A,SY_U16                  ; Parse the operand as a u16.
    CALL EX_CAST                   ; Parse the parenthesized operand.
    CALL EX_INT                    ; A Boolean cannot be converted.
    AND  SY_KNOWN                  ; Is the operand known?
    LD   A,SY_U16                  ; The result is a u16.
    RET  Z                         ; Run-time: return it.
    OR   SY_KNOWN                  ; Known: keep the value in HL.
    RET                            ; Return it with carry clear.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a unary expression: a primary preceded by any number of signs.
; Unary + and - bind above the multiplicative operators.

EX_UNARY:
    CALL PR_PEEK                   ; Look at the next token.
    CP   TK_PLUS                   ; A unary plus?
    JR   Z,EX_PLUS                 ; Parse its operand.
    CP   TK_MINUS                  ; A unary minus?
    JR   Z,EX_MINUS                ; Parse and negate its operand.
    JP   EX_TERM                   ; Otherwise parse a primary.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Consume a sign and parse its integer operand, which unary plus returns
; unchanged. EX_MINUS uses it to parse its own operand.

EX_PLUS:
    CALL PR_TAKE                   ; Consume the sign.
    CALL EX_UNARY                  ; Parse its operand, signs included.
    CALL EX_PURE                   ; A failable call may not be enclosed.
    CALL EX_INT                    ; The operand must be an integer.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the operand.

; Parse unary minus: negate the operand at its own type, or for an exact
; constant at the expected width, u8 if EX_WANT is u8 and u16 otherwise.

EX_MINUS:
    CALL EX_PLUS                   ; Consume '-' and parse the operand.
    LD   D,A                       ; Keep its metadata.
    AND  SY_TMASK                  ; Is it typed?
    JR   NZ,.TYPED                 ; Yes: negate at its type.
    LD   A,(EX_WANT)               ; An exact constant: what is expected?
    CP   SY_U8                     ; A u8?
    JR   Z,EX_NEGU8                ; Negate it as a byte.
    LD   A,SY_U16                  ; Otherwise negate it as a word.
    JR   EX_NEG                    ; Emit and fold.
.TYPED:                        ; A typed operand.
    LD   A,D                       ; Recover the metadata.
    AND  SY_TMASK                  ; Keep its type for the negation.

; Negate at type A (u8 or u16) the operand with metadata D and value HL:
; emit OP_NEG8 or OP_NEG16, and fold a known value modulo the width.

EX_NEG:
    LD   C,A                       ; C is the negation's width.
    CP   SY_U8                     ; Is it u8?
    LD   A,OP_NEG8                 ; Assume the byte negation.
    JR   Z,.EMIT                   ; Yes: keep it.
    LD   A,OP_NEG16                ; No: the word negation.
.EMIT:                         ; Emit the negation.
    CALL EX_UNOP                   ; Emit it, keeping BC, DE and HL.
    LD   A,D                       ; Is the operand known?
    AND  SY_KNOWN                  ; Test its flag.
    LD   A,C                       ; A run-time result of the width's type.
    RET  Z                         ; Return it if not known.
    XOR  A                         ; Fold: zero...
    SUB  L                         ; ...less the low byte...
    LD   L,A                       ; ...is the low result.
    LD   A,0                       ; Zero...
    SBC  A,H                       ; ...less the high byte and the borrow...
    LD   H,A                       ; ...is the high result.
    CALL EX_MASK                   ; Wrap it to the width.
    LD   A,C                       ; The result has the width's type...
    OR   SY_KNOWN                  ; ...and is known.
    RET                            ; Return it.

;@ROUTINE IN A,BC,DE,HL OUT BC,DE,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,A
; Emit operation A, preserving BC, DE and HL for the folding that follows.

EX_UNOP:
    PUSH BC                        ; Keep the width.
    PUSH DE                        ; Keep the operand's metadata.
    PUSH HL                        ; Keep its value.
    CALL EX_EMIT                   ; Emit the operation.
    POP  HL                        ; Recover the value.
    POP  DE                        ; Recover the metadata.
    POP  BC                        ; Recover the width.
    RET                            ; Return to the fold.

; Negate an exact constant expected as u8; D is its metadata, HL its value.

EX_NEGU8:
; Width selection must not destroy evidence that the exact literal itself
; exceeded u8 before negation applies modulo 256.
    LD   A,D                       ; Is the operand known?
    AND  SY_KNOWN                  ; Test its flag.
    JR   Z,.READY                  ; No: nothing to check.
    LD   A,H                       ; Does the constant exceed a byte?
    OR   A                         ; Test its high byte.
    JP   NZ,EX_ERNG                ; Yes: it is out of range.
.READY:                        ; The operand fits a byte.
    LD   A,SY_U8                   ; Negate at u8.
    JR   EX_NEG                    ; Emit and fold.
