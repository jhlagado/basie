;==========================================================================
;  Expression primaries and unary operators
;==========================================================================
;
;  The second of the expression parser's three files (EXPR.ASM describes
;  the module, its result convention and its operand stack). Parse the
;  operands of the binary operators: literals, names, parenthesized
;  expressions, conversions and the unary signs, folding constants and
;  generating the code of the rest (GENEXPR.ASM).
;
;  Principal entries:
;    EX_TERM   parse one primary
;    EX_LIT    return a literal as a known result
;    EX_CAST   parse a conversion's parenthesized operand
;    EX_INT    require an integer result
;    EX_UNARY  parse a primary preceded by any signs

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

; Resolve a NAME primary, already consumed: a predeclared constant (exact,
; as the reference's are; console and printer are Files, no scalar values:
; DG_CLASH) or a call to a service, a routine call, an aggregate object
; path, a scalar constant (emitted as a literal) or a scalar variable
; (emitted as a load).

EX_NAME:
    CALL RO_LIB                    ; A predeclared name?
    JR   NC,.ORDINARY              ; No: an ordinary name.
    JP   M,.PREDEF                 ; A constant: its value.
    OR   A                         ; A service without a result
    JP   Z,RO_EVOID                ; has no value (no-value).
    CALL RO_SVC                    ; A service: call it;
    JP   RO_VALUE                  ; its result is the value.
.PREDEF:                       ; A is SY_KNOWN and the constant's type.
    LD   B,A                       ; Its metadata:
    CP   SY_KNOWN+SY_EXACT         ; a File
    JP   NZ,EX_ETYPE               ; is no scalar value (DG_CLASH).
    INC  HL                        ; Its value,
    LD   L,(HL)                    ; a byte,
    LD   H,0                       ; widened.
    JP   EX_LIT                    ; Return it.
.ORDINARY:                     ; A routine or an ordinary symbol.
    CALL RO_FIND                   ; Is it a routine?
    JP   Z,RO_FUNC                 ; Yes: parse a call for its result.
    CALL SY_GET                    ; Fetch class/type and payload, or fail.
    LD   D,A                       ; Keep the symbol info.
    AND  SY_AGGR                   ; An aggregate?
    JP   NZ,RO_OBJ                 ; Yes: parse its field or element path.
    LD   A,D                       ; A scalar: D is its info, BC its payload.
    CALL EX_CLASS                  ; Reject a type name; zero for a constant.
    JR   Z,.CONST                  ; A constant folds to a literal.
    LD   A,D                       ; Recover the symbol info.
    AND  SY_TMASK                  ; Keep the type.
    LD   E,A                       ; E is the variable's type.
    LD   A,D                       ; Recover the symbol info.
    AND  SY_CMASK                  ; Keep the storage class.
    SUB  SY_GLOB                   ; A program variable?
    LD   (RO_ESC),A                ; Nonzero when it is in the frame.
    LD   A,E                       ; Its type.
    PUSH DE                        ; Keep it.
    JR   Z,.GLOBAL                 ; A program variable loads by address.
    LD   H,B                       ; A local or parameter:
    LD   L,C                       ; HL is its offset from IX.
    CALL GX_FLOAD                  ; Load it into A or HL.
    JR   .LOADED                   ; Return its type.
.GLOBAL:                       ; A program variable, blob BC.
    CALL GX_LOAD                   ; Load it into A or HL.
.LOADED:                       ; The value is in the registers.
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

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse a parenthesized expression after its '(' and require the ')'.

EX_PAREN:
    CALL EX_PARSE                  ; Parse the enclosed expression.
    PUSH AF                        ; Keep its metadata.
    PUSH HL                        ; Keep its value.
    CALL PR_RIGHT                  ; Require the closing parenthesis.
    POP  HL                        ; Recover the value.
    POP  AF                        ; Recover the metadata.
    RET                            ; Return it.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse the parenthesized operand of an explicit conversion, with no type
; expected inside it, as the reference parses it. The enclosing expected
; type is restored before returning the operand in A/HL.

EX_CAST:
    CALL PR_LEFT                   ; Require the opening parenthesis.
    XOR  A                         ; Nothing is expected inside the conversion.
    CALL EX_SUB                    ; Parse the operand; the type is restored.
    PUSH AF                        ; Save its metadata, carry clear,
    PUSH HL                        ; and its value.
    CALL PR_RIGHT                  ; Require the closing parenthesis.
    POP  HL                        ; Recover the value.
    POP  AF                        ; Recover the metadata.
    RET                            ; Return the operand.

;@ROUTINE OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IX,IY
; Parse u8(...), a checked narrowing. A known operand must fit a byte, or
; DG_TRUNC is raised; a computed u16 is checked at run time (GX_BYTE);
; a computed u8 is already one.

EX_U8:
    CALL EX_CAST                   ; Parse the parenthesized operand.
    CALL EX_INT                    ; A Boolean cannot be narrowed; D is A.
    AND  SY_KNOWN                  ; Is the operand known?
    JR   Z,.RUNTIME                ; No: check it at run time.
    LD   A,H                       ; Does the constant exceed a byte?
    OR   A                         ; Test its high byte.
    JP   NZ,EX_ECAST               ; Yes: report it.
    LD   A,SY_KNOWN+SY_U8          ; A known u8 with the same value.
    RET                            ; Return it; OR cleared carry.
.RUNTIME:                      ; A computed operand.
    LD   A,D                       ; Its type.
    AND  SY_TMASK                  ; Alone.
    CP   SY_U16                    ; A word?
    CALL Z,GX_BYTE                 ; Check its high byte and take the low.
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
; Parse u16(...), a widening that needs no check: every integer fits a
; u16. A computed u8 is widened into HL (GX_WIDEN).

EX_U16:
    CALL EX_CAST                   ; Parse the parenthesized operand.
    CALL EX_INT                    ; A Boolean cannot be converted; D is A.
    AND  SY_KNOWN                  ; Is the operand known?
    LD   A,SY_KNOWN+SY_U16         ; Known: keep the value in HL.
    RET  NZ                        ; Return it; AND cleared carry.
    LD   A,D                       ; A computed operand's type.
    AND  SY_TMASK                  ; Alone.
    CP   SY_U8                     ; A byte?
    CALL Z,GX_WIDEN                ; Then it moves to HL.
    LD   A,SY_U16                  ; A run-time u16.
    OR   A                         ; Clear carry for success.
    RET                            ; Return it.

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
    CALL EX_INT                    ; The operand must be an integer.
    OR   A                         ; Clear carry for success.
    RET                            ; Return the operand.

; Parse unary minus: negate the operand at its own type. An exact constant
; other than zero would be a negative exact value, which the reference
; keeps until its context types it; the native compiler has no negative
; exact values, so it refuses one (DG_EXACT).

EX_MINUS:
    CALL EX_PLUS                   ; Consume '-' and parse the operand.
    LD   D,A                       ; Keep its metadata.
    AND  SY_TMASK                  ; Is it typed?
    JR   NZ,EX_NEG                 ; Yes: negate at its type.
    LD   A,H                       ; An exact constant: is it zero?
    OR   L                         ; Then its negation is zero.
    JP   NZ,EX_EXACT               ; Otherwise refuse it.
    LD   A,D                       ; Exact zero, unchanged.
    RET                            ; OR cleared carry.

;@ROUTINE IN A,D,HL OUT A,HL,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Negate at type A (u8 or u16) the operand with metadata D and value HL:
; fold a known value modulo the width, or negate a computed one (GX_NEG).

EX_NEG:
    LD   C,A                       ; C is the negation's width.
    BIT  7,D                       ; SY_KNOWN: is the operand known?
    JR   NZ,.FOLD                  ; Yes: fold it.
    LD   D,C                       ; Its type.
    CALL GX_NEG                    ; Negate A or HL.
    LD   A,C                       ; A run-time result of the width's type.
    OR   A                         ; Clear carry for success.
    RET                            ; Return it.
.FOLD:                         ; HL is a known value.
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
